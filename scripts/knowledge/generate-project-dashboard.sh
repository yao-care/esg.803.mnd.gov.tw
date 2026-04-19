#!/bin/bash
# Generate project dashboard HTML for findings tracking
# Usage: generate-project-dashboard.sh <project-name> <output-dir>
# Input:  $PROJECTS_PATH/<project-name>/findings/*.json
#         $PROJECTS_PATH/<project-name>/notifications/*.json
#         $COLLECTED_PATH/*/quality-gate.json + metadata.json (filtered by project)
# Output: <output-dir>/dashboard.html
set -e

PROJECT_NAME="$1"
OUTPUT_DIR="$2"

if [ -z "$PROJECT_NAME" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: generate-project-dashboard.sh <project-name> <output-dir>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

FINDINGS_DIR="$PROJECT_ROOT/$PROJECTS_PATH/$PROJECT_NAME/findings"
NOTIF_DIR="$PROJECT_ROOT/$PROJECTS_PATH/$PROJECT_NAME/notifications"
SCANS_DIR="$PROJECT_ROOT/$COLLECTED_PATH"

mkdir -p "$OUTPUT_DIR"

# ── Helper: severity colour (inline hex for standalone HTML) ─────────────────
sev_color() {
  case "$1" in
    critical) echo "#c93135" ;;
    high)     echo "#b86a2a" ;;
    medium)   echo "#8a7020" ;;
    low)      echo "#2a6bb8" ;;
    *)        echo "#8a8c98" ;;
  esac
}

sev_bg() {
  case "$1" in
    critical) echo "#fce8e8" ;;
    high)     echo "#fceee8" ;;
    medium)   echo "#fcf5e8" ;;
    low)      echo "#e8f0fc" ;;
    *)        echo "#ecedf0" ;;
  esac
}

status_color() {
  case "$1" in
    discovered)  echo "#b86a2a" ;;
    in_progress) echo "#2a6bb8" ;;
    fixed)       echo "#1e8050" ;;
    accepted)    echo "#8a8c98" ;;
    *)           echo "#8a8c98" ;;
  esac
}

# ── 1. Collect scan history filtered by project ──────────────────────────────
# First pass: collect metadata only (needed to compute CHART_MAX before rendering bars)
SCAN_COUNT=0
TOTAL_FINDINGS_MAX=0
PASS_COUNT=0
FAIL_COUNT=0

# Store scan entries as newline-delimited records: scan_id:critical:high:gate
SCAN_ENTRIES=""

if [ -d "$SCANS_DIR" ]; then
  for scan_dir in "$SCANS_DIR"/*/; do
    [ ! -d "$scan_dir" ] && continue
    meta="$scan_dir/metadata.json"
    qg="$scan_dir/quality-gate.json"
    [ ! -f "$meta" ] || [ ! -f "$qg" ] && continue

    proj=$(jq -r '.project_name // empty' "$meta" 2>/dev/null)
    [ "$proj" != "$PROJECT_NAME" ] && continue

    scan_id=$(basename "$scan_dir")
    critical=$(jq -r '.critical // 0' "$qg" 2>/dev/null)
    high=$(jq -r '.high // 0' "$qg" 2>/dev/null)
    gate=$(jq -r '.quality_gate // "UNKNOWN"' "$qg" 2>/dev/null)
    total=$((critical + high))

    [ "$total" -gt "$TOTAL_FINDINGS_MAX" ] && TOTAL_FINDINGS_MAX="$total"
    [ "$gate" = "PASS" ] && PASS_COUNT=$((PASS_COUNT+1))
    [ "$gate" = "FAIL" ] && FAIL_COUNT=$((FAIL_COUNT+1))

    SCAN_ENTRIES="${SCAN_ENTRIES}${scan_id}:${critical}:${high}:${gate}
"
    SCAN_COUNT=$((SCAN_COUNT+1))
  done
fi

# ── 2. Collect findings ───────────────────────────────────────────────────────
TOTAL_OPEN=0
TOTAL_FIXED=0
FINDING_ROWS=""
TIMELINE_EVENTS=""

if [ -d "$FINDINGS_DIR" ]; then
  for f in "$FINDINGS_DIR"/*.json; do
    [ ! -f "$f" ] && continue

    fid=$(jq -r '.id // empty' "$f" 2>/dev/null)
    severity=$(jq -r '.severity // "unknown"' "$f" 2>/dev/null)
    scanner=$(jq -r '.scanner // "—"' "$f" 2>/dev/null)
    description=$(jq -r '.description // "—"' "$f" 2>/dev/null | sed 's/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
    status=$(jq -r '.status // "discovered"' "$f" 2>/dev/null)
    first_seen=$(jq -r '.first_seen // "—"' "$f" 2>/dev/null)
    github_issue=$(jq -r '.github_issue // ""' "$f" 2>/dev/null)

    # Calculate days open
    days_open="—"
    if [ "$first_seen" != "—" ] && [ -n "$first_seen" ]; then
      # first_seen is a scan ID like 20260413-224552
      scan_date="${first_seen:0:4}-${first_seen:4:2}-${first_seen:6:2}"
      if date -j -f "%Y-%m-%d" "$scan_date" "+%s" >/dev/null 2>&1; then
        # macOS date
        start_ts=$(date -j -f "%Y-%m-%d" "$scan_date" "+%s" 2>/dev/null || echo 0)
      else
        start_ts=$(date -d "$scan_date" "+%s" 2>/dev/null || echo 0)
      fi
      now_ts=$(date "+%s")
      if [ "$start_ts" -gt 0 ] 2>/dev/null; then
        days_open=$(( (now_ts - start_ts) / 86400 ))
      fi
    fi

    [ "$status" = "fixed" ] && TOTAL_FIXED=$((TOTAL_FIXED+1)) || TOTAL_OPEN=$((TOTAL_OPEN+1))

    sc=$(sev_color "$severity")
    sb=$(sev_bg "$severity")
    stc=$(status_color "$status")

    issue_link=""
    if [ -n "$github_issue" ] && [ "$github_issue" != "null" ]; then
      issue_link=" <a href=\"$github_issue\" style=\"color:#2a6bb8;font-size:14px;\" target=\"_blank\">#issue</a>"
    fi

    FINDING_ROWS="${FINDING_ROWS}
<tr style=\"border-bottom:1px solid #dfe0e5;\">
  <td style=\"padding:10px 14px;font-size:14px;color:#8a8c98;white-space:nowrap;\">$(echo "$fid" | sed 's/</\&lt;/g; s/>/\&gt;/g')</td>
  <td style=\"padding:10px 14px;\"><span style=\"background:${sb};color:${sc};padding:2px 8px;border-radius:4px;font-size:14px;font-weight:700;text-transform:uppercase;\">$severity</span></td>
  <td style=\"padding:10px 14px;font-size:15px;\">$scanner</td>
  <td style=\"padding:10px 14px;font-size:15px;\">$description${issue_link}</td>
  <td style=\"padding:10px 14px;\"><span style=\"color:${stc};font-size:14px;font-weight:600;\">$status</span></td>
  <td style=\"padding:10px 14px;font-size:14px;color:#8a8c98;white-space:nowrap;\">$first_seen</td>
  <td style=\"padding:10px 14px;font-size:14px;text-align:right;\">${days_open}</td>
</tr>"

    # Build timeline from history array
    history_count=$(jq '.history | length' "$f" 2>/dev/null || echo 0)
    if [ "$history_count" -gt 0 ]; then
      while IFS= read -r event; do
        ev_date=$(echo "$event" | jq -r '.date // "—"')
        ev_action=$(echo "$event" | jq -r '.action // "—"')
        ev_scan=$(echo "$event" | jq -r '.scan_id // ""')
        ev_note=$(echo "$event" | jq -r '.note // ""' | sed 's/</\&lt;/g; s/>/\&gt;/g')

        ev_color="#5e6070"
        case "$ev_action" in
          discovered) ev_color="#b86a2a" ;;
          fixed)      ev_color="#1e8050" ;;
          reopened)   ev_color="#c93135" ;;
          in_progress) ev_color="#2a6bb8" ;;
          accepted)   ev_color="#8a8c98" ;;
        esac

        scan_ref=""
        [ -n "$ev_scan" ] && scan_ref=" <span style=\"color:#8a8c98;font-size:13px;\">[$ev_scan]</span>"

        note_html=""
        [ -n "$ev_note" ] && note_html="<div style=\"font-size:13px;color:#8a8c98;margin-top:2px;\">$ev_note</div>"

        TIMELINE_EVENTS="${TIMELINE_EVENTS}
<div style=\"display:flex;gap:1rem;margin-bottom:1rem;\">
  <div style=\"flex-shrink:0;width:10px;height:10px;border-radius:50%;background:${ev_color};margin-top:6px;\"></div>
  <div>
    <div style=\"font-size:14px;color:#8a8c98;\">$ev_date</div>
    <div style=\"font-size:16px;font-weight:600;color:${ev_color};\">$ev_action${scan_ref} — <span style=\"color:#1e2030;font-weight:400;\">$(echo "$fid" | sed 's/</\&lt;/g; s/>/\&gt;/g')</span></div>
    ${note_html}
  </div>
</div>"
      done < <(jq -c '.history[]' "$f" 2>/dev/null)
    fi
  done
fi

# ── 3. SLA compliance calculation ────────────────────────────────────────────
# Critical SLA: 24h = 1 workday; High SLA: 3 workdays
# Count findings that were fixed within SLA vs total fixed
SLA_CRITICAL_COMPLIANT=0
SLA_CRITICAL_TOTAL=0
SLA_HIGH_COMPLIANT=0
SLA_HIGH_TOTAL=0

if [ -d "$FINDINGS_DIR" ]; then
  for f in "$FINDINGS_DIR"/*.json; do
    [ ! -f "$f" ] && continue
    severity=$(jq -r '.severity // "unknown"' "$f" 2>/dev/null)
    status=$(jq -r '.status // "discovered"' "$f" 2>/dev/null)

    # Only evaluate critical/high findings
    [ "$severity" != "critical" ] && [ "$severity" != "high" ] && continue

    first_seen=$(jq -r '.first_seen // ""' "$f" 2>/dev/null)
    [ -z "$first_seen" ] && continue

    scan_date="${first_seen:0:4}-${first_seen:4:2}-${first_seen:6:2}"

    if date -j -f "%Y-%m-%d" "$scan_date" "+%s" >/dev/null 2>&1; then
      start_ts=$(date -j -f "%Y-%m-%d" "$scan_date" "+%s" 2>/dev/null || echo 0)
    else
      start_ts=$(date -d "$scan_date" "+%s" 2>/dev/null || echo 0)
    fi
    [ "$start_ts" -le 0 ] 2>/dev/null && continue

    now_ts=$(date "+%s")
    elapsed_days=$(( (now_ts - start_ts) / 86400 ))

    sla_days=3
    [ "$severity" = "critical" ] && sla_days=1

    if [ "$severity" = "critical" ]; then
      SLA_CRITICAL_TOTAL=$((SLA_CRITICAL_TOTAL+1))
      # compliant if fixed OR still within SLA window
      if [ "$status" = "fixed" ] || [ "$elapsed_days" -le "$sla_days" ]; then
        SLA_CRITICAL_COMPLIANT=$((SLA_CRITICAL_COMPLIANT+1))
      fi
    else
      SLA_HIGH_TOTAL=$((SLA_HIGH_TOTAL+1))
      if [ "$status" = "fixed" ] || [ "$elapsed_days" -le "$sla_days" ]; then
        SLA_HIGH_COMPLIANT=$((SLA_HIGH_COMPLIANT+1))
      fi
    fi
  done
fi

SLA_CRITICAL_PCT="N/A"
SLA_HIGH_PCT="N/A"
SLA_CRITICAL_COLOR="#8a8c98"
SLA_HIGH_COLOR="#8a8c98"

if [ "$SLA_CRITICAL_TOTAL" -gt 0 ]; then
  SLA_CRITICAL_PCT=$(( SLA_CRITICAL_COMPLIANT * 100 / SLA_CRITICAL_TOTAL ))%
  [ "$SLA_CRITICAL_COMPLIANT" -eq "$SLA_CRITICAL_TOTAL" ] && SLA_CRITICAL_COLOR="#1e8050" || SLA_CRITICAL_COLOR="#c93135"
fi
if [ "$SLA_HIGH_TOTAL" -gt 0 ]; then
  SLA_HIGH_PCT=$(( SLA_HIGH_COMPLIANT * 100 / SLA_HIGH_TOTAL ))%
  [ "$SLA_HIGH_COMPLIANT" -eq "$SLA_HIGH_TOTAL" ] && SLA_HIGH_COLOR="#1e8050" || SLA_HIGH_COLOR="#b86a2a"
fi

# ── 4. Build CSS-only bar chart ───────────────────────────────────────────────
BAR_CHART_HTML=""
if [ "$SCAN_COUNT" -gt 0 ]; then
  # Chart height = 120px; scale bars relative to max findings (min 1 to avoid div/0)
  CHART_MAX="$TOTAL_FINDINGS_MAX"
  [ "$CHART_MAX" -le 0 ] && CHART_MAX=1

  # Process each stored entry (format: scan_id:critical:high:gate)
  while IFS=: read -r scan_id critical high gate; do
    [ -z "$scan_id" ] && continue
    total=$((critical + high))

    bar_h=$(( total * 100 / CHART_MAX ))
    [ "$bar_h" -lt 4 ] && [ "$total" -gt 0 ] && bar_h=4   # min visible height
    [ "$total" -eq 0 ] && bar_h=2                           # zero = thin line

    bar_color="#1e8050"
    gate_color="#1e8050"
    if [ "$gate" = "FAIL" ]; then
      bar_color="#c93135"
      gate_color="#c93135"
    elif [ "$total" -gt 0 ]; then
      bar_color="#b86a2a"
    fi

    label="${scan_id:0:8}"  # YYYYMMDD
    gate_icon="✓"
    [ "$gate" = "FAIL" ] && gate_icon="✗"

    BAR_CHART_HTML="${BAR_CHART_HTML}
<div title=\"${scan_id}&#10;Critical: ${critical}  High: ${high}&#10;Gate: ${gate}\" style=\"display:flex;flex-direction:column;align-items:center;gap:4px;flex:1;min-width:40px;max-width:80px;\">
  <div style=\"font-size:11px;color:${gate_color};font-weight:700;\">${gate_icon}</div>
  <div style=\"height:120px;display:flex;align-items:flex-end;\">
    <div style=\"width:24px;background:${bar_color};height:${bar_h}%;border-radius:3px 3px 0 0;min-height:2px;\"></div>
  </div>
  <div style=\"font-size:11px;color:#8a8c98;writing-mode:vertical-rl;transform:rotate(180deg);height:50px;overflow:hidden;\">${label}</div>
</div>"
  done <<< "$SCAN_ENTRIES"
fi

# ── 5. Notifications section ─────────────────────────────────────────────────
NOTIF_ROWS=""
if [ -d "$NOTIF_DIR" ]; then
  for nf in "$NOTIF_DIR"/*.json; do
    [ ! -f "$nf" ] && continue
    ntype=$(jq -r '.type // "—"' "$nf" 2>/dev/null)
    nts=$(jq -r '.timestamp // "—"' "$nf" 2>/dev/null)
    nscan=$(jq -r '.scan_id // "—"' "$nf" 2>/dev/null)
    nsubject=$(jq -r '.subject // "—"' "$nf" 2>/dev/null | sed 's/</\&lt;/g; s/>/\&gt;/g')
    ngate=$(jq -r '.quality_gate // "—"' "$nf" 2>/dev/null)
    nrecip=$(jq -r '.recipients | join(", ")' "$nf" 2>/dev/null || echo "—")

    ngc="#1e8050"; [ "$ngate" = "FAIL" ] && ngc="#c93135"

    NOTIF_ROWS="${NOTIF_ROWS}
<tr style=\"border-bottom:1px solid #dfe0e5;\">
  <td style=\"padding:10px 14px;font-size:14px;color:#8a8c98;white-space:nowrap;\">$(echo "$nts" | cut -c1-10)</td>
  <td style=\"padding:10px 14px;font-size:15px;\">$nsubject</td>
  <td style=\"padding:10px 14px;font-size:14px;color:#8a8c98;\">$nscan</td>
  <td style=\"padding:10px 14px;font-size:14px;color:#5e6070;\">$nrecip</td>
  <td style=\"padding:10px 14px;\"><span style=\"color:${ngc};font-size:14px;font-weight:600;\">$ngate</span></td>
</tr>"
  done
fi

# ── 6. Empty state helpers ────────────────────────────────────────────────────
no_findings_msg=""
[ -z "$FINDING_ROWS" ] && no_findings_msg='<tr><td colspan="7" style="padding:2rem;text-align:center;color:#8a8c98;font-size:16px;">No findings recorded</td></tr>'

no_scan_msg=""
[ -z "$BAR_CHART_HTML" ] && no_scan_msg='<div style="padding:2rem;text-align:center;color:#8a8c98;font-size:16px;">No scan history available</div>'

no_timeline_msg=""
[ -z "$TIMELINE_EVENTS" ] && no_timeline_msg='<p style="color:#8a8c98;font-size:16px;">No events recorded</p>'

no_notif_msg=""
[ -z "$NOTIF_ROWS" ] && no_notif_msg='<tr><td colspan="5" style="padding:2rem;text-align:center;color:#8a8c98;font-size:16px;">No notifications recorded</td></tr>'

GENERATED=$(date -u '+%Y-%m-%d %H:%M UTC')

# ── 7. Write HTML ─────────────────────────────────────────────────────────────
cat > "$OUTPUT_DIR/dashboard.html" << HTMLEOF
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Project Dashboard — ${PROJECT_NAME}</title>
<style>
/* ── Inline design system (hex fallback, no CSS vars needed for standalone) ── */
* { box-sizing: border-box; }
body {
  background: #f5f6f8;
  color: #1e2030;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  font-size: 16px;
  line-height: 1.6;
  margin: 0;
}
a { color: #2a6bb8; text-decoration: none; }
a:hover { text-decoration: underline; }
h2 {
  font-size: 22px;
  font-weight: 700;
  margin: 0 0 1rem;
  padding-bottom: 0.5rem;
  border-bottom: 2px solid #dfe0e5;
}
.container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
.card-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
.card {
  background: #ecedf0;
  border-radius: 8px;
  padding: 1.25rem;
  text-align: center;
}
.card-value { font-size: 48px; font-weight: 700; line-height: 1; }
.card-label { font-size: 14px; color: #5e6070; margin-top: 0.25rem; }
.section { margin-bottom: 2.5rem; }
table { width: 100%; border-collapse: collapse; }
thead { background: #dfe0e5; }
th { padding: 10px 14px; text-align: left; font-size: 14px; font-weight: 600; }
tbody tr:hover { background: #e5e6ea; }
/* timeline */
.timeline { border-left: 3px solid #dfe0e5; padding-left: 1.5rem; margin-left: 5px; }
</style>
</head>
<body>
<div class="container">

<!-- ── Header ── -->
<div style="margin-bottom:2rem;">
  <div style="font-size:13px;color:#8a8c98;">${KB_NAME_EN}</div>
  <h1 style="font-size:40px;font-weight:700;margin:0.25rem 0 0.5rem;">${PROJECT_NAME}</h1>
  <div style="font-size:15px;color:#5e6070;">Project Security Dashboard &nbsp;·&nbsp; Generated: ${GENERATED}</div>
</div>

<!-- ── Summary Cards ── -->
<div class="card-grid">
  <div class="card">
    <div class="card-value" style="color:#c93135;">${TOTAL_OPEN}</div>
    <div class="card-label">Open Findings</div>
  </div>
  <div class="card">
    <div class="card-value" style="color:#1e8050;">${TOTAL_FIXED}</div>
    <div class="card-label">Fixed Findings</div>
  </div>
  <div class="card">
    <div class="card-value" style="color:#2a6bb8;">${SCAN_COUNT}</div>
    <div class="card-label">Total Scans</div>
  </div>
  <div class="card">
    <div class="card-value" style="color:#1e8050;">${PASS_COUNT}</div>
    <div class="card-label">Quality Gate PASS</div>
  </div>
  <div class="card">
    <div class="card-value" style="color:#c93135;">${FAIL_COUNT}</div>
    <div class="card-label">Quality Gate FAIL</div>
  </div>
</div>

<!-- ── 掃描趨勢 (CSS-only bar chart) ── -->
<div class="section">
  <h2>掃描趨勢 Scan Trend</h2>
  <div style="background:#ecedf0;border-radius:8px;padding:1.5rem;">
    <div style="font-size:13px;color:#8a8c98;margin-bottom:0.5rem;">Critical + High findings per scan &nbsp;
      <span style="display:inline-block;width:12px;height:12px;background:#1e8050;border-radius:2px;"></span> PASS
      <span style="display:inline-block;width:12px;height:12px;background:#b86a2a;border-radius:2px;margin-left:8px;"></span> PASS w/ findings
      <span style="display:inline-block;width:12px;height:12px;background:#c93135;border-radius:2px;margin-left:8px;"></span> FAIL
    </div>
    ${no_scan_msg}
    <div style="display:flex;align-items:flex-end;gap:4px;overflow-x:auto;padding-bottom:0.5rem;">
      ${BAR_CHART_HTML}
    </div>
  </div>
</div>

<!-- ── SLA 合規率 ── -->
<div class="section">
  <h2>SLA 合規率 SLA Compliance</h2>
  <div class="card-grid" style="max-width:600px;">
    <div class="card">
      <div class="card-value" style="color:${SLA_CRITICAL_COLOR};">${SLA_CRITICAL_PCT}</div>
      <div class="card-label">Critical (24hr SLA)</div>
      <div style="font-size:13px;color:#8a8c98;">${SLA_CRITICAL_COMPLIANT} / ${SLA_CRITICAL_TOTAL}</div>
    </div>
    <div class="card">
      <div class="card-value" style="color:${SLA_HIGH_COLOR};">${SLA_HIGH_PCT}</div>
      <div class="card-label">High (3-workday SLA)</div>
      <div style="font-size:13px;color:#8a8c98;">${SLA_HIGH_COMPLIANT} / ${SLA_HIGH_TOTAL}</div>
    </div>
  </div>
</div>

<!-- ── 發現清單 Findings Table ── -->
<div class="section">
  <h2>發現清單 Findings (${TOTAL_OPEN} open, ${TOTAL_FIXED} fixed)</h2>
  <div style="background:#ecedf0;border-radius:8px;overflow:hidden;">
    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Severity</th>
          <th>Scanner</th>
          <th>Description</th>
          <th>Status</th>
          <th>First Seen</th>
          <th style="text-align:right;">Days Open</th>
        </tr>
      </thead>
      <tbody>
        ${FINDING_ROWS}
        ${no_findings_msg}
      </tbody>
    </table>
  </div>
</div>

<!-- ── 修復履歷時間線 Remediation Timeline ── -->
<div class="section">
  <h2>修復履歷時間線 Remediation Timeline</h2>
  <div style="background:#ecedf0;border-radius:8px;padding:1.5rem;">
    <div class="timeline">
      ${TIMELINE_EVENTS}
      ${no_timeline_msg}
    </div>
  </div>
</div>

<!-- ── Notification History ── -->
<div class="section">
  <h2>通知紀錄 Notification History</h2>
  <div style="background:#ecedf0;border-radius:8px;overflow:hidden;">
    <table>
      <thead>
        <tr>
          <th>Date</th>
          <th>Subject</th>
          <th>Scan ID</th>
          <th>Recipients</th>
          <th>Quality Gate</th>
        </tr>
      </thead>
      <tbody>
        ${NOTIF_ROWS}
        ${no_notif_msg}
      </tbody>
    </table>
  </div>
</div>

<footer style="margin-top:3rem;padding-top:1rem;border-top:1px solid #dfe0e5;font-size:13px;color:#8a8c98;">
  ${KB_NAME_EN} &nbsp;·&nbsp; ${GENERATED}
</footer>

</div>
</body>
</html>
HTMLEOF

echo "Generated: $OUTPUT_DIR/dashboard.html (project=$PROJECT_NAME, scans=$SCAN_COUNT, open=$TOTAL_OPEN, fixed=$TOTAL_FIXED)"
