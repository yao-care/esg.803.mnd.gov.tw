const { describe, it } = require('node:test');
const assert = require('node:assert');

function expandGlossary(query, glossary) {
  if (!glossary || typeof glossary !== 'object') return query;
  const expansions = [];
  const sorted = Object.entries(glossary)
    .sort((a, b) => b[0].length - a[0].length);
  for (const [term, expansion] of sorted) {
    const termLower = term.toLowerCase();
    const queryLower = query.toLowerCase();
    if (queryLower.includes(termLower)) {
      expansions.push(expansion);
    }
  }
  if (expansions.length === 0) return query;
  return query + ' ' + expansions.join(' ');
}

describe('expandGlossary', () => {
  const glossary = {
    '管審會': '個人資料保護暨資通安全管理委員會',
    '資安長': '資通安全長',
    'PIMS': '個人資料保護管理系統',
    'BCP': '營運持續計畫',
  };

  it('expands a known abbreviation', () => {
    const result = expandGlossary('管審會的成員有哪些人？', glossary);
    assert.ok(result.includes('管審會'));
    assert.ok(result.includes('個人資料保護暨資通安全管理委員會'));
  });

  it('returns original query when no match', () => {
    const result = expandGlossary('天氣如何？', glossary);
    assert.strictEqual(result, '天氣如何？');
  });

  it('handles English abbreviations case-insensitively', () => {
    const result = expandGlossary('pims是什麼？', glossary);
    assert.ok(result.includes('個人資料保護管理系統'));
  });

  it('expands multiple matches', () => {
    const result = expandGlossary('管審會討論BCP', glossary);
    assert.ok(result.includes('個人資料保護暨資通安全管理委員會'));
    assert.ok(result.includes('營運持續計畫'));
  });

  it('returns original query for null glossary', () => {
    assert.strictEqual(expandGlossary('test', null), 'test');
  });

  it('returns original query for empty glossary', () => {
    assert.strictEqual(expandGlossary('test', {}), 'test');
  });

  it('does not chain-match expansion terms', () => {
    const g = {
      'ABC': 'Alpha Beta Contains-XYZ',
      'XYZ': 'Something Else',
    };
    const result = expandGlossary('ABC test', g);
    assert.ok(result.includes('Alpha Beta Contains-XYZ'));
    assert.ok(!result.includes('Something Else'));
  });
});
