#!/usr/bin/env node
'use strict';

const crypto = require('node:crypto');
const fs = require('fs');
const path = require('path');

/**
 * Audit chunk quality. Pure function — no I/O.
 *
 * @param {Array<{chunk_id: string, doc_key: string, text: string}>} chunks
 * @param {Array<{chunk_id: string, doc_key: string}>} metaIndex
 * @returns {Object} Audit report
 */
function auditChunks(chunks, metaIndex) {
  const issues = [];
  const chunksWithIssues = new Set();
  let empty = 0;
  let tooShort = 0;
  let duplicate = 0;
  let toc = 0;
  let orphan = 0;

  const metaChunkIds = new Set(metaIndex.map(m => m.chunk_id));
  const seenHashes = new Map(); // key: doc_key+hash, value: chunk_id

  for (const chunk of chunks) {
    const text = chunk.text || '';

    // Extract content after context header (lines starting with [ are header)
    const lines = text.split('\n');
    const contentLines = [];
    let pastHeader = false;
    for (const line of lines) {
      if (!pastHeader && (line.startsWith('[') || line.trim() === '')) {
        if (!line.startsWith('[')) pastHeader = true;
        continue;
      }
      pastHeader = true;
      contentLines.push(line);
    }
    const content = contentLines.join('\n').trim();

    // Empty check
    if (content.length === 0) {
      empty++;
      chunksWithIssues.add(chunk.chunk_id);
      issues.push({ type: 'empty', chunk_id: chunk.chunk_id, detail: 'No content after header' });
      continue;
    }

    // Too-short check (intro chunks use lower threshold — content before first heading is naturally short)
    const isIntro = /^[^#]*$/.test(chunk.section || '') || (chunk.section || '').includes('intro');
    const minChars = isIntro ? 20 : 100;
    if (content.length < minChars) {
      tooShort++;
      chunksWithIssues.add(chunk.chunk_id);
      issues.push({ type: isIntro ? 'too_short_intro' : 'too_short', chunk_id: chunk.chunk_id, detail: `${content.length} chars (min: ${minChars})` });
    }

    // TOC check (>50% of non-empty lines contain consecutive dots)
    const nonEmptyLines = content.split('\n').filter(l => l.trim().length > 0);
    const dotLines = nonEmptyLines.filter(l => /\.{4,}/.test(l));
    if (nonEmptyLines.length > 0 && dotLines.length / nonEmptyLines.length > 0.5) {
      toc++;
      chunksWithIssues.add(chunk.chunk_id);
      issues.push({ type: 'toc', chunk_id: chunk.chunk_id, detail: `${dotLines.length}/${nonEmptyLines.length} lines are TOC` });
    }

    // Duplicate check (same doc_key + same content hash)
    const hash = crypto.createHash('sha256').update(content).digest('hex').slice(0, 16);
    const dedupKey = `${chunk.doc_key}:${hash}`;
    if (seenHashes.has(dedupKey)) {
      duplicate++;
      chunksWithIssues.add(chunk.chunk_id);
      issues.push({ type: 'duplicate', chunk_id: chunk.chunk_id, detail: `Duplicate of ${seenHashes.get(dedupKey)}` });
    } else {
      seenHashes.set(dedupKey, chunk.chunk_id);
    }

    // Orphan check
    if (!metaChunkIds.has(chunk.chunk_id)) {
      orphan++;
      chunksWithIssues.add(chunk.chunk_id);
      issues.push({ type: 'orphan', chunk_id: chunk.chunk_id, detail: 'Not in META_INDEX' });
    }
  }

  // Doc-key coverage
  const docKeyCoverage = new Map();
  for (const chunk of chunks) {
    const dk = chunk.doc_key || '';
    if (!dk) continue;
    docKeyCoverage.set(dk, (docKeyCoverage.get(dk) || 0) + 1);
  }

  return {
    total: chunks.length,
    valid: chunks.length - chunksWithIssues.size,
    empty,
    tooShort,
    duplicate,
    toc,
    orphan,
    docKeyCoverage,
    issues,
  };
}

/**
 * Print audit report to stdout.
 */
function printReport(report) {
  console.log('chunk quality report');
  console.log('====================');
  console.log(`total chunks: ${report.total}`);
  console.log(`valid chunks: ${report.valid}`);
  console.log(`empty chunks: ${report.empty} ${report.empty > 0 ? '⚠' : '✓'}`);
  console.log(`too-short chunks: ${report.tooShort} ${report.tooShort > 0 ? '⚠' : '✓'}`);
  console.log(`duplicate chunks: ${report.duplicate} ${report.duplicate > 0 ? '⚠' : '✓'}`);
  console.log(`toc chunks: ${report.toc} ${report.toc > 0 ? '⚠' : '✓'}`);
  console.log(`orphan chunks: ${report.orphan} ${report.orphan > 0 ? '⚠' : '✓'}`);
  console.log(`doc_key coverage: ${report.docKeyCoverage.size} documents`);

  if (report.issues.length > 0) {
    console.log('\nissues:');
    for (const issue of report.issues) {
      console.log(`  [${issue.type}] ${issue.chunk_id}: ${issue.detail}`);
    }
  }
}

// CLI entry point
if (require.main === module) {
  const { loadConfig, PROJECT_ROOT } = require('./config.js');
  const { chunkMarkdown } = require('./chunk.js');
  const { buildMetaIndex } = require('./search.js');

  const config = loadConfig();
  const docsPath = (config.data_sources && config.data_sources.documents && config.data_sources.documents.path)
    || 'knowledge/';
  const metadataFilename = (config.domain && config.domain.metadata_filename) || 'merge.yaml';
  const docsDir = path.resolve(PROJECT_ROOT, docsPath);

  if (!fs.existsSync(docsDir)) {
    console.error(`Documents directory not found: ${docsDir}`);
    process.exit(1);
  }

  // Chunk all documents (same logic as build.js)
  const allChunks = [];
  const entries = fs.readdirSync(docsDir, { withFileTypes: true });

  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name.startsWith('_')) continue;
    const metaPath = path.join(docsDir, entry.name, metadataFilename);
    if (!fs.existsSync(metaPath)) continue;

    const metaContent = fs.readFileSync(metaPath, 'utf8');
    const zhMatch = metaContent.match(/^\s+zh:\s*(.+)$/m);
    if (!zhMatch) continue;

    const mdPath = path.join(docsDir, entry.name, zhMatch[1].trim());
    if (!fs.existsSync(mdPath)) continue;

    const md = fs.readFileSync(mdPath, 'utf8');
    allChunks.push(...chunkMarkdown(md, entry.name));
  }

  const metaIndex = buildMetaIndex(allChunks);
  const report = auditChunks(allChunks, metaIndex);
  printReport(report);

  process.exit(report.issues.filter(i => !i.type.startsWith('too_short')).length > 0 ? 1 : 0);
}

module.exports = { auditChunks };
