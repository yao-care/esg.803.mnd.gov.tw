#!/bin/bash
# scripts/monitor/adapters/aws-guardduty.sh — AWS GuardDuty adapter
# Usage: aws-guardduty.sh <config_json> <output_dir>
#
# Config: { "type": "aws-guardduty", "region": "ap-northeast-1", "credentials_env": "GUARDDUTY_TOKEN" }
set -e

CONFIG_JSON="$1"
OUTPUT_DIR="$2"

if [ -z "$CONFIG_JSON" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: aws-guardduty.sh <config_json> <output_dir>" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

REGION=$(echo "$CONFIG_JSON" | jq -r '.region // "us-east-1"')
CRED_ENV=$(echo "$CONFIG_JSON" | jq -r '.credentials_env // ""')
LOOKBACK_HOURS=$(echo "$CONFIG_JSON" | jq -r '.lookback_hours // 24')
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Check AWS CLI
if ! command -v aws &>/dev/null; then
  cat > "$OUTPUT_DIR/aws-guardduty-result.json" << EOF
{
  "source": "aws-guardduty",
  "mode": "continuous",
  "status": "skipped",
  "reason": "AWS CLI not installed",
  "timestamp": "$TIMESTAMP",
  "last_event_at": null,
  "summary": { "critical": 0, "high": 0, "medium": 0, "low": 0, "total": 0 },
  "findings": []
}
EOF
  exit 0
fi

# Set credentials if env var specified
if [ -n "$CRED_ENV" ]; then
  TOKEN_VALUE="${!CRED_ENV}"
  if [ -z "$TOKEN_VALUE" ]; then
    cat > "$OUTPUT_DIR/aws-guardduty-result.json" << EOF
{
  "source": "aws-guardduty",
  "mode": "continuous",
  "status": "error",
  "error": "Credentials env var $CRED_ENV is empty",
  "timestamp": "$TIMESTAMP",
  "last_event_at": null,
  "summary": { "critical": 0, "high": 0, "medium": 0, "low": 0, "total": 0 },
  "findings": []
}
EOF
    exit 1
  fi
fi

# Get detector ID
DETECTOR_ID=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds[0]' --output text 2>/dev/null || echo "")

if [ -z "$DETECTOR_ID" ] || [ "$DETECTOR_ID" = "None" ]; then
  cat > "$OUTPUT_DIR/aws-guardduty-result.json" << EOF
{
  "source": "aws-guardduty",
  "mode": "continuous",
  "status": "error",
  "error": "No GuardDuty detector found in region $REGION",
  "timestamp": "$TIMESTAMP",
  "last_event_at": null,
  "summary": { "critical": 0, "high": 0, "medium": 0, "low": 0, "total": 0 },
  "findings": []
}
EOF
  exit 1
fi

# Calculate lookback time
SINCE=$(date -u -v-${LOOKBACK_HOURS}H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        date -u -d "${LOOKBACK_HOURS} hours ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        echo "2020-01-01T00:00:00Z")

# Fetch findings
FINDINGS_RAW=$(aws guardduty list-findings \
  --region "$REGION" \
  --detector-id "$DETECTOR_ID" \
  --finding-criteria "{\"Criterion\":{\"updatedAt\":{\"GreaterThanOrEqual\":$(date -d "$SINCE" +%s000 2>/dev/null || echo 0)}}}" \
  --query 'FindingIds' --output json 2>/dev/null || echo "[]")

FINDING_IDS=$(echo "$FINDINGS_RAW" | jq -r '.[]?' 2>/dev/null)
CRITICAL=0; HIGH=0; MEDIUM=0; LOW=0
FINDINGS="[]"
LAST_EVENT=""

if [ -n "$FINDING_IDS" ]; then
  DETAILS=$(aws guardduty get-findings \
    --region "$REGION" \
    --detector-id "$DETECTOR_ID" \
    --finding-ids $FINDING_IDS \
    --query 'Findings' --output json 2>/dev/null || echo "[]")

  CRITICAL=$(echo "$DETAILS" | jq '[.[] | select(.Severity >= 7)] | length' 2>/dev/null || echo "0")
  HIGH=$(echo "$DETAILS" | jq '[.[] | select(.Severity >= 4 and .Severity < 7)] | length' 2>/dev/null || echo "0")
  MEDIUM=$(echo "$DETAILS" | jq '[.[] | select(.Severity >= 2 and .Severity < 4)] | length' 2>/dev/null || echo "0")
  LOW=$(echo "$DETAILS" | jq '[.[] | select(.Severity < 2)] | length' 2>/dev/null || echo "0")

  LAST_EVENT=$(echo "$DETAILS" | jq -r '[.[].UpdatedAt] | sort | last // ""' 2>/dev/null || echo "")

  FINDINGS=$(echo "$DETAILS" | jq '[.[:20] | .[] | {
    severity: (if .Severity >= 7 then "critical" elif .Severity >= 4 then "high" elif .Severity >= 2 then "medium" else "low" end),
    title: .Title,
    description: .Description,
    first_seen: .CreatedAt,
    resource: (.Resource.ResourceType // "unknown")
  }]' 2>/dev/null || echo "[]")
fi

TOTAL=$((CRITICAL + HIGH + MEDIUM + LOW))

cat > "$OUTPUT_DIR/aws-guardduty-result.json" << EOF
{
  "source": "aws-guardduty",
  "mode": "continuous",
  "status": "completed",
  "timestamp": "$TIMESTAMP",
  "last_event_at": $([ -n "$LAST_EVENT" ] && echo "\"$LAST_EVENT\"" || echo "\"$TIMESTAMP\""),
  "region": "$REGION",
  "detector_id": "$DETECTOR_ID",
  "summary": {
    "critical": $CRITICAL,
    "high": $HIGH,
    "medium": $MEDIUM,
    "low": $LOW,
    "total": $TOTAL
  },
  "findings": $FINDINGS
}
EOF
