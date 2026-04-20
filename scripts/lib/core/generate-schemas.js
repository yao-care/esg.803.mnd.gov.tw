'use strict';

const fs = require('node:fs');
const path = require('node:path');

const FIELD_TYPE_MAP = {
  text:        { type: 'string' },
  textarea:    { type: 'string' },
  email:       { type: 'string', format: 'email' },
  date:        { type: 'string', format: 'date' },
  datetime:    { type: 'string', format: 'date-time' },
  number:      { type: 'number' },
  select:      (f) => ({ type: 'string', enum: f.options || [] }),
  multiselect: (f) => ({ type: 'array', items: { type: 'string', enum: f.options || [] } }),
};

function fieldsToJsonSchema(documentId, fields) {
  const fieldProps = {};
  const required = [];

  for (const f of fields) {
    const mapper = FIELD_TYPE_MAP[f.type];
    if (!mapper) throw new Error(`Unknown field type: ${f.type}`);
    fieldProps[f.name] = typeof mapper === 'function' ? mapper(f) : { ...mapper };
    if (f.required) required.push(f.name);
  }

  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    type: 'object',
    properties: {
      document_id: { type: 'string', const: documentId },
      submitted_by: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          title: { type: 'string' },
        },
        required: ['name'],
      },
      fields: {
        type: 'object',
        properties: fieldProps,
        required,
      },
    },
    required: ['document_id', 'submitted_by', 'fields'],
  };
}

function parseYamlFields(yamlContent) {
  const { execSync } = require('node:child_process');
  const os = require('node:os');
  const tmpFile = path.join(os.tmpdir(), `akora-yaml-parse-${process.pid}.py`);
  const py = [
    'import sys, json, yaml',
    'data = yaml.safe_load(sys.stdin.read())',
    "print(json.dumps({",
    "  'document_id': data.get('document_id', ''),",
    "  'fields': data.get('fields', []),",
    "  'approval_required': data.get('approval_required', False),",
    "  'retention_period_days': data.get('retention_period_days', None),",
    '}))',
  ].join('\n');
  fs.writeFileSync(tmpFile, py);
  try {
    const result = execSync(`python3 ${tmpFile}`, {
      input: yamlContent,
      encoding: 'utf8',
    });
    return JSON.parse(result);
  } finally {
    try { fs.unlinkSync(tmpFile); } catch (_) {}
  }
}

function generateSchema(mergeYamlPath) {
  const yaml = fs.readFileSync(mergeYamlPath, 'utf8');
  const parsed = parseYamlFields(yaml);
  if (!parsed.fields || parsed.fields.length === 0) return null;
  return fieldsToJsonSchema(parsed.document_id, parsed.fields);
}

function generateAllSchemas(knowledgeDir, outputDir, metadataFilename = 'merge.yaml') {
  fs.mkdirSync(outputDir, { recursive: true });
  const folders = fs.readdirSync(knowledgeDir, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);

  const generated = [];
  for (const folder of folders) {
    const yamlPath = path.join(knowledgeDir, folder, metadataFilename);
    if (!fs.existsSync(yamlPath)) continue;
    const schema = generateSchema(yamlPath);
    if (!schema) continue;
    const docId = schema.properties.document_id.const;
    const outPath = path.join(outputDir, `${docId}.json`);
    fs.writeFileSync(outPath, JSON.stringify(schema, null, 2));
    generated.push(docId);
  }
  return generated;
}

// CLI entry point
if (require.main === module) {
  const { loadConfig, PROJECT_ROOT } = require('./config');
  const config = loadConfig();
  const knowledgeDir = path.join(PROJECT_ROOT, config.data_sources?.documents?.path || 'knowledge');
  const outputDir = path.join(PROJECT_ROOT, 'data', 'schemas');
  const generated = generateAllSchemas(knowledgeDir, outputDir, config.domain?.metadata_filename);
  console.log(`[generate-schemas] Generated ${generated.length} schemas: ${generated.join(', ')}`);
}

module.exports = { fieldsToJsonSchema, generateSchema, generateAllSchemas, parseYamlFields };
