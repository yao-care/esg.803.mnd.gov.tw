'use strict';

/**
 * AKORA Form Submission API — 參考實作
 *
 * 這是平台無關的核心邏輯。部署時需要包裝在 HTTP 框架中。
 *
 * 使用方式：
 *   const { handleSubmit } = require('./handler');
 *   // 在你的 HTTP 框架中：
 *   app.post('/submit', async (req, res) => {
 *     const result = await handleSubmit(req.body, req.headers, env);
 *     res.status(result.status).json(result.body);
 *   });
 */

async function handleSubmit(body, headers, env) {
  // 1. Validate API key
  const apiKey = headers['x-api-key'];
  if (apiKey !== env.API_KEY) {
    return { status: 401, body: { error: 'invalid_api_key' } };
  }

  // 2. Check idempotency (implementation depends on storage backend)
  const idempotencyKey = headers['x-idempotency-key'];
  if (idempotencyKey && env.checkIdempotency) {
    const existing = await env.checkIdempotency(idempotencyKey);
    if (existing) {
      return { status: 409, body: { error: 'duplicate_submission', existing_record_id: existing, idempotency_key: idempotencyKey } };
    }
  }

  // 3. Validate body
  const { document_id, submitted_by, fields } = body;
  if (!document_id || !submitted_by || !fields) {
    return { status: 400, body: { error: 'validation_failed', details: ['Missing required fields: document_id, submitted_by, fields'] } };
  }

  // 4. Validate against JSON Schema (if schemas available)
  if (env.validateSchema) {
    const schemaErrors = await env.validateSchema(document_id, fields);
    if (schemaErrors.length > 0) {
      return { status: 400, body: { error: 'validation_failed', details: schemaErrors } };
    }
  }

  // 5. Generate record
  const now = new Date();
  const pad = (n, len = 2) => String(n).padStart(len, '0');
  const dateStr = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`;
  const timeStr = `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const hex = Math.random().toString(16).slice(2, 6);
  const recordId = `${document_id}-${dateStr}-${timeStr}-${hex}`;

  const record = {
    record_id: recordId,
    document_id,
    submitted_at: now.toISOString(),
    submitted_by: {
      ...submitted_by,
      source: 'api',
      ip: headers['x-forwarded-for'] || headers['cf-connecting-ip'] || '',
    },
    status: env.approval_required ? 'pending_review' : 'submitted',
    classification: env.classification || 'internal',
    fields,
    audit_trail: [{
      action: env.approval_required ? 'pending_review' : 'submitted',
      at: now.toISOString(),
      by: submitted_by.name || '',
      source: 'api',
    }],
  };

  // 6. Compute retained_until
  if (env.retention_period_days) {
    const retained = new Date(now);
    retained.setDate(retained.getDate() + env.retention_period_days);
    record.retained_until = retained.toISOString().slice(0, 10);
  }

  // 7. Commit or create PR
  const filePath = `data/reported/${recordId}.json`;
  const content = JSON.stringify(record, null, 2);

  let prUrl = null;
  if (env.approval_required) {
    prUrl = await env.createPullRequest(filePath, content, recordId);
  } else {
    await env.commitFile(filePath, content, `record: ${recordId}`);
  }

  // 8. Record idempotency key
  if (idempotencyKey && env.saveIdempotency) {
    await env.saveIdempotency(idempotencyKey, recordId);
  }

  return {
    status: 200,
    body: {
      record_id: recordId,
      status: record.status,
      ...(prUrl ? { pr_url: prUrl } : {}),
    },
  };
}

module.exports = { handleSubmit };
