// scripts/lib/core/__tests__/generate-schemas.test.js
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const { generateSchema, generateAllSchemas, fieldsToJsonSchema } = require('../generate-schemas');

const FIXTURES = path.resolve(__dirname, '..', '..', '..', '..', 'tests', 'fixtures');
const SCHEMAS_OUT = path.resolve(FIXTURES, '..', 'tmp-schemas');

describe('generate-schemas', () => {
  after(() => {
    fs.rmSync(SCHEMAS_OUT, { recursive: true, force: true });
  });

  describe('fieldsToJsonSchema', () => {
    it('converts text field to string property', () => {
      const fields = [{ name: '通報人', type: 'text', required: true }];
      const schema = fieldsToJsonSchema('FRM-TEST', fields);
      assert.strictEqual(schema.properties.fields.properties['通報人'].type, 'string');
      assert.ok(schema.properties.fields.required.includes('通報人'));
    });

    it('converts select field with enum', () => {
      const fields = [{ name: '類別', type: 'select', required: true, options: ['A', 'B'] }];
      const schema = fieldsToJsonSchema('FRM-TEST', fields);
      assert.deepStrictEqual(schema.properties.fields.properties['類別'].enum, ['A', 'B']);
    });

    it('converts multiselect to array of enum', () => {
      const fields = [{ name: '範圍', type: 'multiselect', options: ['X', 'Y'] }];
      const schema = fieldsToJsonSchema('FRM-TEST', fields);
      const prop = schema.properties.fields.properties['範圍'];
      assert.strictEqual(prop.type, 'array');
      assert.deepStrictEqual(prop.items.enum, ['X', 'Y']);
    });

    it('converts datetime to string with format', () => {
      const fields = [{ name: '時間', type: 'datetime', required: true }];
      const schema = fieldsToJsonSchema('FRM-TEST', fields);
      assert.strictEqual(schema.properties.fields.properties['時間'].format, 'date-time');
    });

    it('converts number to number type', () => {
      const fields = [{ name: '數量', type: 'number' }];
      const schema = fieldsToJsonSchema('FRM-TEST', fields);
      assert.strictEqual(schema.properties.fields.properties['數量'].type, 'number');
    });

    it('non-required fields are not in required array', () => {
      const fields = [
        { name: 'A', type: 'text', required: true },
        { name: 'B', type: 'text' }
      ];
      const schema = fieldsToJsonSchema('FRM-TEST', fields);
      assert.ok(schema.properties.fields.required.includes('A'));
      assert.ok(!schema.properties.fields.required.includes('B'));
    });
  });

  describe('generateAllSchemas', () => {
    it('generates schema files from fixtures', () => {
      const knowledgeDir = path.join(FIXTURES, 'knowledge');
      generateAllSchemas(knowledgeDir, SCHEMAS_OUT);
      const schemaPath = path.join(SCHEMAS_OUT, 'FRM-TEST.json');
      assert.ok(fs.existsSync(schemaPath), 'Schema file should exist');
      const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
      assert.strictEqual(schema.properties.document_id.const, 'FRM-TEST');
      assert.ok(schema.properties.fields.properties['類別']);
    });
  });
});
