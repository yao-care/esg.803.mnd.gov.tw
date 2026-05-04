const { describe, it } = require('node:test');
const assert = require('node:assert');
const MiniSearch = require('minisearch');

const { chineseTokenize, buildSearchIndex, buildMetaIndex } = require('../search.js');

describe('search.js', () => {
  describe('chineseTokenize', () => {
    it('segments Chinese text', () => {
      const tokens = chineseTokenize('資訊安全管理');
      assert.ok(tokens.length > 0);
      assert.ok(Array.isArray(tokens));
    });
  });

  describe('buildSearchIndex', () => {
    it('builds MiniSearch index from chunks', () => {
      const chunks = [
        { chunk_id: 'DOC-01#1', text: '這是測試內容', title: '測試文件', section: '第一節' }
      ];
      const indexJson = buildSearchIndex(chunks);
      assert.ok(indexJson);
      assert.strictEqual(typeof indexJson, 'string', 'buildSearchIndex returns a JSON string');
      const index = MiniSearch.loadJSON(indexJson, {
        fields: ['text', 'title', 'section'],
        tokenize: chineseTokenize,
        searchOptions: { prefix: true, fuzzy: 0.2 },
      });
      const results = index.search('測試');
      assert.ok(results.length > 0);
    });
  });
});
