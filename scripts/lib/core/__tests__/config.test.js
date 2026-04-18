const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = path.resolve(__dirname, '..', '..', '..', '..');

describe('config loader', () => {
  const configPath = path.join(PROJECT_ROOT, 'config.json');
  const backupPath = configPath + '.bak';

  before(() => {
    if (fs.existsSync(configPath)) {
      fs.renameSync(configPath, backupPath);
    }
  });

  after(() => {
    if (fs.existsSync(backupPath)) {
      fs.renameSync(backupPath, configPath);
    } else if (fs.existsSync(configPath)) {
      fs.unlinkSync(configPath);
    }
  });

  it('loads config.json and merges with defaults', () => {
    fs.writeFileSync(configPath, JSON.stringify({
      knowledge_body: { name: 'Test KB', name_en: 'test' },
      qa: { search_hit_threshold: 0.90 }
    }));

    delete require.cache[require.resolve('../config.js')];
    const { loadConfig } = require('../config.js');
    const config = loadConfig();

    assert.strictEqual(config.knowledge_body.name, 'Test KB');
    assert.strictEqual(config.qa.search_hit_threshold, 0.90);
    assert.strictEqual(config.qa.answer_rate_threshold, 0.98);
    assert.strictEqual(config.ui.locale, 'zh-TW');
  });
});
