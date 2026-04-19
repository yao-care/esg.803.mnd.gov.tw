#!/usr/bin/env node
'use strict';

/**
 * build.js — Knowledge Body Assistant Build Assembler
 *
 * Reads documents + collected/reported tables, chunks them, builds search
 * indexes, and assembles the final assistant.html single-page app.
 *
 * All domain-specific values (paths, labels, prompts) are read from config.json
 * via the config loader, making this module reusable across knowledge bodies.
 *
 * Usage:
 *   node scripts/lib/core/build.js [output-dir] [dest-file]
 *
 * Arguments:
 *   output-dir  CI output directory containing rendered documents/, forms/
 *               (defaults to PROJECT_ROOT)
 *   dest-file   Optional destination path; defaults to <output-dir>/assistant.html
 *
 * Generalized from agent.system-integration-quality-control/scripts/lib/audit-assistant/build.js:
 *   - SCAN_DISPLAY_NAMES → config.ui.scan_display_names
 *   - readIsmsDocuments → readDocuments (path from config.data_sources.documents.path)
 *   - merge.yaml → config.domain.metadata_filename
 *   - FRM prefix → config.domain.form_prefix
 *   - docs/scans → config.data_sources.tables.collected.path
 *   - audit-assistant.html → assistant.html
 *   - locale → config.ui.locale
 *   - model → config.api.model
 *   - Added reported tables data source
 *   - Added HTML template placeholder substitution
 */

const fs   = require('fs');
const path = require('path');

const { loadConfig, PROJECT_ROOT } = require('./config.js');
const { chunkMarkdown, chunkCollectedResult } = require('./chunk.js');
const { buildSearchIndex, buildMetaIndex }     = require('./search.js');
const { renderCollectedHtml }                  = require('./render.js');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Recursively find all files matching a suffix within a directory.
 *
 * @param {string} dir
 * @param {string} suffix
 * @returns {string[]} Absolute file paths
 */
function findFiles(dir, suffix) {
  if (!fs.existsSync(dir)) return [];
  const results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...findFiles(full, suffix));
    } else if (entry.isFile() && entry.name.endsWith(suffix)) {
      results.push(full);
    }
  }
  return results;
}

/**
 * Safely read a file as UTF-8 string; return null if missing.
 *
 * @param {string} filePath
 * @returns {string|null}
 */
function readFileSafe(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return null;
  }
}

/**
 * Extract the zh main file path from metadata YAML content.
 * Looks for a line like:   zh: filename.md
 *
 * @param {string} yamlContent
 * @returns {string|null}
 */
function extractZhPath(yamlContent) {
  const m = yamlContent.match(/^\s+zh:\s*(.+)$/m);
  return m ? m[1].trim() : null;
}

/**
 * Extract the document_id from metadata YAML content.
 *
 * @param {string} yamlContent
 * @returns {string|null}
 */
function extractDocumentId(yamlContent) {
  const m = yamlContent.match(/^document_id:\s*(.+)$/m);
  return m ? m[1].trim() : null;
}

// ---------------------------------------------------------------------------
// Markdown → HTML fallback renderer (for documents without pre-rendered HTML)
// ---------------------------------------------------------------------------

/**
 * Escape HTML entities.
 *
 * @param {string} str
 * @returns {string}
 */
function escHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * Convert markdown text to a simple standalone HTML document.
 * Handles headings, bold, italic, code blocks, inline code, lists, tables,
 * horizontal rules, and paragraphs. Strips YAML front matter.
 *
 * @param {string} md - Markdown source
 * @param {string} title - Document title for the HTML <title>
 * @returns {string} Complete HTML document string
 */
function renderMarkdownToHtml(md, title) {
  // Strip YAML front matter
  let body = md.replace(/^---[\s\S]*?---\s*/, '');

  // Convert fenced code blocks first (before escaping)
  const codeBlocks = [];
  body = body.replace(/```(\w*)\n([\s\S]*?)```/g, (_m, _lang, code) => {
    const idx = codeBlocks.length;
    codeBlocks.push(`<pre style="background:#f0f1f3;padding:1rem;border-radius:0.5rem;overflow-x:auto;font-size:0.9em;line-height:1.5;"><code>${escHtml(code.trimEnd())}</code></pre>`);
    return `\x00CODEBLOCK${idx}\x00`;
  });

  // Escape HTML in the remaining text
  body = escHtml(body);

  // Restore code blocks
  body = body.replace(/\x00CODEBLOCK(\d+)\x00/g, (_m, idx) => codeBlocks[Number(idx)]);

  // Tables: detect lines starting with |
  body = body.replace(/((?:^|\n)\|.+\|(?:\n\|.+\|)+)/g, (tableBlock) => {
    const rows = tableBlock.trim().split('\n').filter(r => r.trim());
    // Skip separator row (contains ---)
    const dataRows = rows.filter(r => !/^\|[\s\-:|]+\|$/.test(r));
    if (dataRows.length === 0) return tableBlock;
    const parseRow = (row) => row.split('|').slice(1, -1).map(c => c.trim());
    const headerCells = parseRow(dataRows[0]);
    const thead = `<thead><tr>${headerCells.map(c => `<th style="padding:0.5rem 1rem;text-align:left;font-weight:600;background:#ecedf0;">${c}</th>`).join('')}</tr></thead>`;
    const tbody = dataRows.slice(1).map(r => {
      const cells = parseRow(r);
      return `<tr>${cells.map(c => `<td style="padding:0.5rem 1rem;border-top:1px solid #d5d6da;">${c}</td>`).join('')}</tr>`;
    }).join('\n');
    return `\n<table style="width:100%;border-collapse:collapse;background:#f5f6f8;border-radius:0.5rem;overflow:hidden;margin:1rem 0;">${thead}<tbody>${tbody}</tbody></table>\n`;
  });

  // Headings
  body = body.replace(/^#{6}\s+(.+)$/gm, '<h6 style="margin:1rem 0 0.5rem;font-weight:700;">$1</h6>');
  body = body.replace(/^#{5}\s+(.+)$/gm, '<h5 style="margin:1rem 0 0.5rem;font-weight:700;">$1</h5>');
  body = body.replace(/^#{4}\s+(.+)$/gm, '<h4 style="margin:1rem 0 0.5rem;font-weight:700;">$1</h4>');
  body = body.replace(/^#{3}\s+(.+)$/gm, '<h3 style="margin:1.2rem 0 0.5rem;font-weight:700;font-size:1.1em;">$1</h3>');
  body = body.replace(/^#{2}\s+(.+)$/gm, '<h2 style="margin:1.5rem 0 0.5rem;font-weight:700;font-size:1.25em;">$1</h2>');
  body = body.replace(/^#{1}\s+(.+)$/gm, '<h1 style="margin:1.5rem 0 0.5rem;font-weight:700;font-size:1.5em;">$1</h1>');

  // Bold and italic
  body = body.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  body = body.replace(/\*(.+?)\*/g, '<em>$1</em>');

  // Inline code
  body = body.replace(/`([^`]+)`/g, '<code style="background:#ecedf0;padding:0.15em 0.4em;border-radius:3px;font-size:0.9em;">$1</code>');

  // Horizontal rule
  body = body.replace(/^---+$/gm, '<hr style="border:none;border-top:1px solid #d5d6da;margin:1.5rem 0;">');

  // Unordered lists
  body = body.replace(/((?:^|\n)[ \t]*[-*]\s+.+(?:\n[ \t]*[-*]\s+.+)*)/g, (block) => {
    const items = block.trim().split(/\n/).map(line => {
      const content = line.replace(/^[ \t]*[-*]\s+/, '');
      return `<li style="margin:0.25rem 0;">${content}</li>`;
    });
    return `\n<ul style="margin:0.5rem 0;padding-left:1.5rem;">${items.join('\n')}</ul>\n`;
  });

  // Ordered lists
  body = body.replace(/((?:^|\n)[ \t]*\d+\.\s+.+(?:\n[ \t]*\d+\.\s+.+)*)/g, (block) => {
    const items = block.trim().split(/\n/).map(line => {
      const content = line.replace(/^[ \t]*\d+\.\s+/, '');
      return `<li style="margin:0.25rem 0;">${content}</li>`;
    });
    return `\n<ol style="margin:0.5rem 0;padding-left:1.5rem;">${items.join('\n')}</ol>\n`;
  });

  // Paragraphs: wrap remaining text blocks
  body = body.split(/\n{2,}/).map(block => {
    const trimmed = block.trim();
    if (!trimmed) return '';
    // Don't wrap blocks that are already HTML elements
    if (/^<(?:h[1-6]|ul|ol|li|table|thead|tbody|tr|td|th|pre|hr|div)/i.test(trimmed)) return trimmed;
    return `<p style="margin:0.5rem 0;line-height:1.7;">${trimmed.replace(/\n/g, '<br>')}</p>`;
  }).join('\n');

  return `<!DOCTYPE html>
<html lang="zh-TW">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escHtml(title)}</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: #f5f6f8; color: #1e2030;
  padding: 2rem; line-height: 1.6; font-size: 1rem;
  max-width: 800px;
}
</style>
</head>
<body>
${body}
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// Step 1: Read documents
// ---------------------------------------------------------------------------

/**
 * Read all documents from the configured documents directory.
 * Returns { chunks, renderedDocs }.
 *
 * @param {string} docsDir - Absolute path to documents directory
 * @param {Object} [options]
 * @param {string} [options.metadataFilename] - Metadata filename (default: 'merge.yaml')
 * @param {string} [options.formPrefix] - Prefix for form documents (default: 'FRM')
 * @param {string} [options.outputDir] - Output directory for finding rendered HTML
 * @returns {{ chunks: Object[], renderedDocs: Object }}
 */
function readDocuments(docsDir, options = {}) {
  const metadataFilename = options.metadataFilename || 'merge.yaml';
  const formPrefix = options.formPrefix || 'FRM';
  const outputDir = options.outputDir || '';

  const chunks = [];
  const renderedDocs = {};

  if (!fs.existsSync(docsDir)) {
    console.warn(`[build] Documents dir not found: ${docsDir}`);
    return { chunks, renderedDocs };
  }

  const entries = fs.readdirSync(docsDir, { withFileTypes: true });

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const folderName = entry.name;

    // Skip meta/internal directories
    if (folderName.startsWith('_')) continue;

    const folderPath = path.join(docsDir, folderName);
    const metaPath = path.join(folderPath, metadataFilename);
    const metaYaml = readFileSafe(metaPath);
    if (!metaYaml) continue; // No metadata file → skip

    // Extract zh file path
    const zhFile = extractZhPath(metaYaml);
    if (!zhFile) {
      console.warn(`[build] No zh: entry in ${metaPath}`);
      continue;
    }

    const mdPath = path.join(folderPath, zhFile);
    const md = readFileSafe(mdPath);
    if (!md) {
      console.warn(`[build] Markdown not found: ${mdPath}`);
      continue;
    }

    // Chunk the markdown
    const docChunks = chunkMarkdown(md, folderName);
    chunks.push(...docChunks);

    // Determine rendered HTML path (if outputDir is provided)
    const documentId = extractDocumentId(metaYaml) || '';
    let foundRendered = false;
    if (outputDir) {
      const isForm = documentId.startsWith(formPrefix);
      const htmlPath = isForm
        ? path.join(outputDir, 'forms', folderName, 'index.html')
        : path.join(outputDir, 'documents', folderName, 'index.html');

      const html = readFileSafe(htmlPath);
      if (html) {
        renderedDocs[folderName] = html;
        foundRendered = true;
      }
    }

    // Fallback: render markdown to HTML if no pre-rendered file exists
    if (!foundRendered) {
      const titleZh = metaYaml.match(/^title_zh:\s*(.+)$/m);
      const docTitle = titleZh ? titleZh[1].trim() : (documentId || folderName);
      renderedDocs[folderName] = renderMarkdownToHtml(md, `${documentId} ${docTitle}`);
    }
  }

  console.log(`[build] Documents: ${chunks.length} chunks from ${Object.keys(renderedDocs).length} rendered docs`);
  return { chunks, renderedDocs };
}

// ---------------------------------------------------------------------------
// Step 2: Read collected tables (e.g. scan results)
// ---------------------------------------------------------------------------

/**
 * Read collected table results from the configured path.
 * Finds the latest subdirectory, reads all *-result.json files.
 *
 * @param {string} collectedDir - Absolute path to collected tables directory
 * @param {Object} renderedDocs - Mutated in place to add rendered HTML entries
 * @param {Object} [displayNames] - Map of result basename → display name
 * @returns {Object[]} Collected table chunks
 */
function readCollectedTables(collectedDir, renderedDocs, displayNames = {}) {
  const collectedChunks = [];

  if (!fs.existsSync(collectedDir)) {
    console.warn(`[build] Collected tables dir not found: ${collectedDir}`);
    return collectedChunks;
  }

  // Find latest subdirectory (sort descending, take first)
  const subDirs = fs.readdirSync(collectedDir, { withFileTypes: true })
    .filter(e => e.isDirectory())
    .map(e => e.name)
    .sort()
    .reverse();

  if (subDirs.length === 0) {
    console.warn(`[build] No subdirectories found in ${collectedDir}`);
    return collectedChunks;
  }

  const latestName = subDirs[0];
  const latestDir  = path.join(collectedDir, latestName);
  console.log(`[build] Using collected tables from: ${latestName}`);

  // Recursively find all *-result.json files
  const resultFiles = findFiles(latestDir, '-result.json');

  for (const filePath of resultFiles) {
    const baseName = path.basename(filePath, '.json'); // e.g. "sast-result"
    const displayName = displayNames[baseName] || baseName;

    let json;
    try {
      json = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch (err) {
      console.warn(`[build] Failed to parse ${filePath}: ${err.message}`);
      continue;
    }

    const chunkArr = chunkCollectedResult(json, baseName, { displayName });
    collectedChunks.push(...chunkArr);

    // Generate rendered HTML for document viewer
    renderedDocs[`collected/${baseName}`] = renderCollectedHtml(json, baseName, displayName);
  }

  // Read quality-gate.json if exists
  const qgPath = path.join(latestDir, 'quality-gate.json');
  const qgContent = readFileSafe(qgPath);
  if (qgContent) {
    try {
      const qgJson = JSON.parse(qgContent);
      const chunkArr = chunkCollectedResult(qgJson, 'quality-gate', { displayName: 'Quality Gate' });
      collectedChunks.push(...chunkArr);
      renderedDocs['collected/quality-gate'] = renderCollectedHtml(qgJson, 'quality-gate', 'Quality Gate');
    } catch (err) {
      console.warn(`[build] Failed to parse quality-gate.json: ${err.message}`);
    }
  }

  // Read compliance/index.html
  const complianceHtml = readFileSafe(path.join(latestDir, 'compliance', 'index.html'));
  if (complianceHtml) {
    renderedDocs['collected/compliance'] = complianceHtml;
  }

  // Read index.html
  const indexHtml = readFileSafe(path.join(latestDir, 'index.html'));
  if (indexHtml) {
    renderedDocs['collected/index'] = indexHtml;
  }

  console.log(`[build] Collected: ${collectedChunks.length} chunks from ${resultFiles.length} result files`);
  return collectedChunks;
}

// ---------------------------------------------------------------------------
// Step 2b: Read reported tables
// ---------------------------------------------------------------------------

/**
 * Read reported table results from the configured path.
 * Similar to collected tables but for manually reported data.
 *
 * @param {string} reportedDir - Absolute path to reported tables directory
 * @param {Object} renderedDocs - Mutated in place to add rendered HTML entries
 * @param {Object} [displayNames] - Map of result basename → display name
 * @returns {Object[]} Reported table chunks
 */
function readReportedTables(reportedDir, renderedDocs, displayNames = {}) {
  const reportedChunks = [];

  if (!fs.existsSync(reportedDir)) {
    console.warn(`[build] Reported tables dir not found: ${reportedDir}`);
    return reportedChunks;
  }

  // Find all JSON files in the reported directory (flat structure)
  const jsonFiles = findFiles(reportedDir, '.json');

  for (const filePath of jsonFiles) {
    const baseName = path.basename(filePath, '.json');
    const displayName = displayNames[baseName] || baseName;

    let json;
    try {
      json = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch (err) {
      console.warn(`[build] Failed to parse ${filePath}: ${err.message}`);
      continue;
    }

    const chunkArr = chunkCollectedResult(json, baseName, { displayName });
    // Override source_type to 'reported'
    for (const c of chunkArr) {
      c.source_type = 'reported';
      c.type = 'reported';
      c.doc_key = `reported/${baseName}`;
      c.chunk_id = `reported/${baseName}`;
    }
    reportedChunks.push(...chunkArr);

    renderedDocs[`reported/${baseName}`] = renderCollectedHtml(json, baseName, displayName);
  }

  console.log(`[build] Reported: ${reportedChunks.length} chunks from ${jsonFiles.length} files`);
  return reportedChunks;
}

// ---------------------------------------------------------------------------
// Step 3–6: Build indexes and assemble HTML
// ---------------------------------------------------------------------------

/**
 * Replace a placeholder comment + default value in a template string.
 *
 * @param {string} template
 * @param {string} marker     e.g. '__CHUNKS__'
 * @param {string} defaultPat e.g. '{}'
 * @param {string} value      Replacement value string (already JSON-serialized)
 * @returns {string}
 */
function replacePlaceholder(template, marker, defaultPat, value) {
  const escapedMarker = marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const escapedDefault = defaultPat.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`/\\*${escapedMarker}\\*/${escapedDefault}`, 'g');
  return template.replace(re, `/*${marker}*/${value}`);
}

/**
 * Substitute UI/domain placeholders in the HTML template.
 *
 * @param {string} html - Template HTML string
 * @param {Object} config - Full config object
 * @returns {string} HTML with placeholders replaced
 */
function substitutePlaceholders(html, config) {
  const ui = config.ui || {};
  const domain = config.domain || {};
  const kb = config.knowledge_body || {};

  html = html.replace(/__ASSISTANT_TITLE__/g, ui.assistant_title || '');
  html = html.replace(/__WELCOME_MESSAGE__/g, ui.welcome_message || '');
  html = html.replace(/__DRILL_WELCOME_MESSAGE__/g, ui.drill_welcome_message || '');
  html = html.replace('__QA_SYSTEM_PROMPT__', JSON.stringify(domain.system_prompt || ''));
  html = html.replace('__DRILL_SYSTEM_PROMPT__', JSON.stringify(domain.drill_system_prompt || ''));
  html = html.replace('__ASSESSMENT_CONTROLS_COVERED__', JSON.stringify(domain.assessment_controls_covered || []));
  html = html.replace('__ASSESSMENT_CONTROLS_ALL__', JSON.stringify(domain.assessment_controls || []));
  html = html.replace('__DOC_GROUP_LABELS__', JSON.stringify(ui.doc_group_labels || {}));
  html = html.replace(/__KB_NAME__/g, kb.name || '');
  html = html.replace(/__KB_DESCRIPTION__/g, kb.description || '');
  html = html.replace('__ORGANIZATION__', kb.organization || '');
  html = html.replace('__CONTROL_NAME__', domain.control_name || '');
  html = html.replace('__CONTROL_ID_PATTERN__', domain.control_id_pattern || '');

  return html;
}

/**
 * Main build function. Can be called programmatically or from CLI.
 *
 * @param {Object} [overrides]
 * @param {string} [overrides.outputDir] - Override output directory
 * @param {string} [overrides.destFile] - Override destination file path
 * @param {Object} [overrides.config] - Override config (skip loadConfig)
 */
function build(overrides = {}) {
  const config = overrides.config || loadConfig();

  const outputDir = overrides.outputDir
    ? path.resolve(overrides.outputDir)
    : PROJECT_ROOT;

  const destFile = overrides.destFile
    ? path.resolve(overrides.destFile)
    : path.join(outputDir, 'assistant.html');

  const dataSources = config.data_sources || {};
  const domain = config.domain || {};
  const ui = config.ui || {};
  const api = config.api || {};

  // ---- Step 1: Documents ----
  const docsConfig = dataSources.documents || {};
  const docsPath = docsConfig.enabled !== false && docsConfig.path
    ? path.resolve(PROJECT_ROOT, docsConfig.path)
    : null;

  let allChunks = [];
  let renderedDocs = {};

  if (docsPath) {
    const result = readDocuments(docsPath, {
      metadataFilename: domain.metadata_filename || 'merge.yaml',
      formPrefix: domain.form_prefix || 'FRM',
      outputDir,
    });
    allChunks.push(...result.chunks);
    renderedDocs = { ...renderedDocs, ...result.renderedDocs };
  }

  // ---- Step 2a: Collected tables ----
  const collectedConfig = (dataSources.tables || {}).collected || {};
  if (collectedConfig.enabled !== false && collectedConfig.path) {
    const collectedDir = path.resolve(PROJECT_ROOT, collectedConfig.path);
    const displayNames = ui.scan_display_names || {};
    const collectedChunks = readCollectedTables(collectedDir, renderedDocs, displayNames);
    allChunks.push(...collectedChunks);
  }

  // ---- Step 2b: Reported tables ----
  const reportedConfig = (dataSources.tables || {}).reported || {};
  if (reportedConfig.enabled !== false && reportedConfig.path) {
    const reportedDir = path.resolve(PROJECT_ROOT, reportedConfig.path);
    const displayNames = ui.scan_display_names || {};
    const reportedChunks = readReportedTables(reportedDir, renderedDocs, displayNames);
    allChunks.push(...reportedChunks);
  }

  console.log(`[build] Total chunks: ${allChunks.length}`);

  // ---- Step 3: Build indexes ----
  const metaIndex = buildMetaIndex(allChunks);
  const searchIndexJson = buildSearchIndex(allChunks);

  // Build chunksMap: { chunk_id: { text, doc_key, title } }
  const chunksMap = {};
  for (const chunk of allChunks) {
    chunksMap[chunk.chunk_id] = { text: chunk.text, doc_key: chunk.doc_key, title: chunk.title };
  }

  console.log(`[build] Meta index: ${metaIndex.length} entries`);

  // ---- Step 4: Read template and MiniSearch lib ----
  const templatePath   = path.join(PROJECT_ROOT, 'templates', 'assistant.html');
  const miniSearchPath = path.join(PROJECT_ROOT, 'node_modules', 'minisearch', 'dist', 'umd', 'index.js');

  if (!fs.existsSync(templatePath)) {
    console.error(`[build] Template not found: ${templatePath}`);
    process.exit(1);
  }

  let template = fs.readFileSync(templatePath, 'utf8');
  const miniSearchLib = readFileSafe(miniSearchPath) || '';

  // ---- Step 5: Build app config for the SPA ----
  const appConfig = {
    api_key: api.key || '',
    model: api.model || 'claude-sonnet-4-20250514',
    max_tokens_per_turn: 4096,
    locale: ui.locale || 'zh-TW',
  };

  // ---- Step 6: Assemble ----
  // Replace data placeholders
  template = replacePlaceholder(template, '__CHUNKS__', '{}', JSON.stringify(chunksMap));
  template = replacePlaceholder(template, '__META_INDEX__', '[]', JSON.stringify(metaIndex));
  template = replacePlaceholder(template, '__SEARCH_INDEX__', '"{}"', JSON.stringify(searchIndexJson));

  // Escape </script> inside embedded HTML to prevent breaking the outer <script> tag
  const renderedJson = JSON.stringify(renderedDocs).replace(/<\/script>/gi, '<\\/script>');
  template = replacePlaceholder(template, '__RENDERED_DOCS__', '{}', renderedJson);

  // Replace APP_CONFIG
  template = template.replace(
    /\/\*__APP_CONFIG__\*\/\{[^\n]*\}/,
    `/*__APP_CONFIG__*/${JSON.stringify(appConfig)}`
  );

  // Replace MiniSearch lib
  if (miniSearchLib) {
    template = template.replace(
      '<script>/*__MINISEARCH_LIB__*/</script>',
      `<script>${miniSearchLib}</script>`
    );
  }

  // Substitute UI/domain placeholders
  template = substitutePlaceholders(template, config);

  // ---- Step 7: Write output ----
  fs.mkdirSync(path.dirname(destFile), { recursive: true });
  fs.writeFileSync(destFile, template, 'utf8');

  const sizeMB = (fs.statSync(destFile).size / (1024 * 1024)).toFixed(2);
  console.log(`[build] Output: ${destFile} (${sizeMB} MB)`);
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

if (require.main === module) {
  const [,, outputDir, destFile] = process.argv;
  build({ outputDir, destFile });
}

// ---------------------------------------------------------------------------
// Exports (for testing and programmatic use)
// ---------------------------------------------------------------------------

module.exports = {
  readDocuments,
  readCollectedTables,
  readReportedTables,
  replacePlaceholder,
  substitutePlaceholders,
  build,
  // Internal helpers exported for testing
  findFiles,
  readFileSafe,
  extractZhPath,
  extractDocumentId,
  renderMarkdownToHtml,
};
