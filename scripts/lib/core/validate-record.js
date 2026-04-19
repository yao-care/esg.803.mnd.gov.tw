'use strict';

const fs = require('node:fs');
const path = require('node:path');

const RECORD_ID_PATTERN = /^.+-\d{8}-\d{6}-[0-9a-f]{4}$/;

function validateRecord(record, schemasDir) {
  const errors = [];

  // 1. record_id format
  if (!record.record_id || !RECORD_ID_PATTERN.test(record.record_id)) {
    errors.push(`record_id: 格式不符 (expected {doc_id}-YYYYMMDD-HHmmss-XXXX, got "${record.record_id}")`);
  }

  // 2. document_id exists
  if (!record.document_id) {
    errors.push('document_id: 必填');
    return { valid: false, errors };
  }

  // 3. Load schema
  const schemaPath = path.join(schemasDir, `${record.document_id}.json`);
  if (!fs.existsSync(schemaPath)) {
    errors.push(`document_id: 對應的 schema 不存在 (${schemaPath})`);
    return { valid: false, errors };
  }

  const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
  const fieldSchema = schema.properties.fields;

  // 4. Required fields
  const requiredFields = fieldSchema.required || [];
  for (const req of requiredFields) {
    if (record.fields[req] === undefined || record.fields[req] === null || record.fields[req] === '') {
      errors.push(`${req}: 必填欄位缺少值`);
    }
  }

  // 5. Field type validation
  for (const [name, value] of Object.entries(record.fields || {})) {
    const prop = fieldSchema.properties[name];
    if (!prop) continue;

    if (prop.enum && !prop.enum.includes(value)) {
      errors.push(`${name}: 值 "${value}" 不在允許選項 [${prop.enum.join(', ')}] 內`);
    }

    if (prop.type === 'array' && Array.isArray(value)) {
      const allowed = prop.items?.enum || [];
      for (const v of value) {
        if (allowed.length > 0 && !allowed.includes(v)) {
          errors.push(`${name}: 值 "${v}" 不在允許選項 [${allowed.join(', ')}] 內`);
        }
      }
    }

    if (prop.type === 'number' && typeof value !== 'number') {
      errors.push(`${name}: 應為數字，實際為 ${typeof value}`);
    }
  }

  return { valid: errors.length === 0, errors };
}

function validateRecordFile(filePath, schemasDir) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    const record = JSON.parse(content);
    return validateRecord(record, schemasDir);
  } catch (err) {
    return { valid: false, errors: [`JSON 解析失敗: ${err.message}`] };
  }
}

// CLI entry point
if (require.main === module) {
  const { loadConfig, PROJECT_ROOT } = require('./config');
  const config = loadConfig();
  const schemasDir = path.join(PROJECT_ROOT, 'data', 'schemas');
  const reportedDir = path.join(PROJECT_ROOT, config.data_sources?.tables?.reported?.path || 'data/reported');

  const files = process.argv.slice(2);
  const targets = files.length > 0
    ? files
    : fs.readdirSync(reportedDir).filter(f => f.endsWith('.json')).map(f => path.join(reportedDir, f));

  let allValid = true;
  for (const f of targets) {
    const result = validateRecordFile(f, schemasDir);
    if (!result.valid) {
      console.error(`[FAIL] ${path.basename(f)}:`);
      result.errors.forEach(e => console.error(`  - ${e}`));
      allValid = false;
    } else {
      console.log(`[OK] ${path.basename(f)}`);
    }
  }
  process.exit(allValid ? 0 : 1);
}

module.exports = { validateRecord, validateRecordFile };
