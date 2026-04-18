'use strict';

/**
 * search.js — MiniSearch Index Builder for AI Audit Assistant
 *
 * Provides full-text search index building with Chinese word segmentation.
 * Works in Node.js (build time) and modern browsers (query time).
 * The `chineseTokenize` function is designed to be duplicated in the SPA
 * HTML template so both environments use the same tokenization logic.
 */

const MiniSearch = require('minisearch');

// ---------------------------------------------------------------------------
// Chinese tokenizer
// ---------------------------------------------------------------------------

/**
 * Tokenize text for MiniSearch, with Chinese word segmentation support.
 *
 * Strategy:
 * 1. If `Intl.Segmenter` is available (Node.js 16+, modern browsers):
 *    - Use Segmenter('zh-Hant', { granularity: 'word' }) for Chinese word segmentation
 *    - Filter to `isWordLike` segments only (excludes punctuation, spaces)
 * 2. Fallback (environments without Intl.Segmenter):
 *    - Split on whitespace/punctuation for English words
 *    - Extract consecutive Chinese character runs and bigram them
 *
 * All tokens are lowercased.
 *
 * @param {string} text - Input text (may be Chinese, English, or mixed)
 * @returns {string[]} Array of lowercase token strings
 */
function chineseTokenize(text) {
  if (!text || typeof text !== 'string') return [];

  // Primary path: Intl.Segmenter available
  if (typeof Intl !== 'undefined' && typeof Intl.Segmenter === 'function') {
    const segmenter = new Intl.Segmenter('zh-Hant', { granularity: 'word' });
    const tokens = [];
    for (const { segment, isWordLike } of segmenter.segment(text)) {
      if (isWordLike && segment.trim().length > 0) {
        tokens.push(segment.toLowerCase());
      }
    }
    return tokens;
  }

  // Fallback path: no Intl.Segmenter
  const tokens = [];
  const CJK_RANGE = /[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff\u3000-\u303f]/;

  // Split into runs of CJK characters vs. non-CJK characters
  const parts = text.split(/([^\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]+)/);

  for (const part of parts) {
    if (!part) continue;

    if (CJK_RANGE.test(part)) {
      // CJK run: produce individual chars and bigrams
      const chars = [...part]; // Unicode-safe split
      for (const ch of chars) {
        if (ch.trim()) tokens.push(ch.toLowerCase());
      }
      for (let i = 0; i < chars.length - 1; i++) {
        tokens.push((chars[i] + chars[i + 1]).toLowerCase());
      }
    } else {
      // Non-CJK run: split on whitespace and punctuation
      const words = part.split(/[\s\W]+/).filter(w => w.length > 0);
      for (const word of words) {
        tokens.push(word.toLowerCase());
      }
    }
  }

  return tokens.filter(t => t.length > 0);
}

// ---------------------------------------------------------------------------
// MiniSearch index builder
// ---------------------------------------------------------------------------

/**
 * Build a serialized MiniSearch full-text search index from chunks.
 *
 * MiniSearch configuration:
 * - Fields indexed: text, title, section
 * - Stored fields (returned in results): chunk_id, doc_key, title, section
 * - Tokenizer: chineseTokenize (Chinese + English)
 * - Boost: title 3×, section 2×, text 1×
 * - Search options: prefix matching, 0.2 fuzzy
 *
 * @param {Array<Object>} chunks - Array of chunk objects from chunk.js
 * @returns {string} JSON-serialized MiniSearch index (use MiniSearch.loadJSON to restore)
 */
function buildSearchIndex(chunks) {
  const ms = new MiniSearch({
    idField: 'chunk_id',
    fields: ['text', 'title', 'section'],
    storeFields: ['chunk_id', 'doc_key', 'title', 'section'],
    tokenize: chineseTokenize,
    searchOptions: {
      boost: { title: 3, section: 2, text: 1 },
      prefix: true,
      fuzzy: 0.2,
    },
  });

  // Prepare documents: MiniSearch requires the idField to be present.
  // scan chunks may not have title/section — provide empty string defaults
  // so MiniSearch doesn't encounter undefined during indexing.
  const docs = chunks.map(chunk => ({
    chunk_id: chunk.chunk_id,
    doc_key: chunk.doc_key || '',
    title: chunk.title || '',
    section: chunk.section || '',
    text: chunk.text || '',
  }));

  ms.addAll(docs);

  return JSON.stringify(ms);
}

// ---------------------------------------------------------------------------
// Metadata index builder
// ---------------------------------------------------------------------------

/**
 * Build a metadata array from chunks for non-search lookup.
 *
 * Each entry contains identifying and descriptive fields but NOT the full text,
 * keeping the metadata index small enough to ship to the browser.
 *
 * @param {Array<Object>} chunks - Array of chunk objects from chunk.js
 * @returns {Array<Object>} Array of metadata objects keyed by chunk_id
 */
function buildMetaIndex(chunks) {
  return chunks.map(chunk => ({
    chunk_id: chunk.chunk_id,
    doc_id: chunk.doc_id,
    doc_key: chunk.doc_key,
    title: chunk.title,
    version: chunk.version || '',
    section: chunk.section,
    iso_controls: chunk.iso_controls,
    type: chunk.type,
    char_count: chunk.text ? chunk.text.length : 0,
  }));
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = {
  chineseTokenize,
  buildSearchIndex,
  buildMetaIndex,
};
