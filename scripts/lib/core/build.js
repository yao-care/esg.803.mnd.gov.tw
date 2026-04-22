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
const { chunkMarkdown, chunkCollectedResult, chunkReportedRecord } = require('./chunk.js');
const { buildSearchIndex, buildMetaIndex }     = require('./search.js');
const { renderCollectedHtml }                  = require('./render.js');
const { generateAllSchemas }                   = require('./generate-schemas');
const { postProcessForms }                     = require('./form-processor');
const { renderRecords }                        = require('./record-renderer');
const { fetchExternalSources }                 = require('./external-fetcher');
const { renderMarkdownToHtml, convertNumbersToChinese, CHINESE_NUMBERS } = require('./markdown-renderer');

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
    const chunkConfig = options.chunk_threshold ? { chunk_threshold: options.chunk_threshold } : {};
    const docChunks = chunkMarkdown(md, folderName, chunkConfig);
    chunks.push(...docChunks);

    // Determine rendered HTML path (if outputDir is provided)
    const documentId = extractDocumentId(metaYaml) || '';
    let foundRendered = false;
    if (outputDir) {
      const docType = metaYaml.match(/^type:\s*(.+)$/m)?.[1]?.trim() || '';
      const isForm = documentId.startsWith(formPrefix) || docType === formPrefix;
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

    // Detect form records vs legacy collected-style data
    if (json.record_id && json.fields) {
      // Form submission record — use record-specific chunker
      const meta = { title_zh: displayName, document_id: json.document_id || baseName };
      const recordChunks = chunkReportedRecord(json, meta);
      reportedChunks.push(...recordChunks);
      if (recordChunks.length > 0) {
        renderedDocs[`reported/${baseName}`] = `<p>紀錄 ${json.record_id}</p>`;
      }
    } else {
      // Legacy format — use existing collected result chunker
      const chunkArr = chunkCollectedResult(json, baseName, { displayName });
      for (const c of chunkArr) {
        c.source_type = 'reported';
        c.type = 'reported';
        c.doc_key = `reported/${baseName}`;
        c.chunk_id = `reported/${baseName}`;
      }
      reportedChunks.push(...chunkArr);
      renderedDocs[`reported/${baseName}`] = renderCollectedHtml(json, baseName, displayName);
    }
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
function substitutePlaceholders(html, config, profile = null) {
  const ui = config.ui || {};
  const domain = config.domain || {};
  const kb = config.knowledge_body || {};

  // Profile overrides for title and system prompt
  const effectiveTitle = profile?.label || ui.assistant_title || '';
  const promptKey = profile?.system_prompt_key || 'system_prompt';
  const effectivePrompt = domain[promptKey] || domain.system_prompt || '';

  html = html.replace(/__ASSISTANT_TITLE__/g, effectiveTitle);
  html = html.replace(/__WELCOME_MESSAGE__/g, ui.welcome_message || '');
  html = html.replace(/__DRILL_WELCOME_MESSAGE__/g, ui.drill_welcome_message || '');
  html = html.replace('__QA_SYSTEM_PROMPT__', JSON.stringify(effectivePrompt));
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
 * Filter chunks by excluding specified document type groups.
 *
 * @param {Object[]} allChunks - Array of chunk objects (each with a `group` field)
 * @param {string[]|null} excludeTypes - Array of group names to exclude, or null/[] to keep all
 * @returns {Object[]} Filtered chunks
 */
function filterChunks(allChunks, excludeTypes) {
  if (!excludeTypes || excludeTypes.length === 0) return allChunks;
  return allChunks.filter(chunk => !excludeTypes.includes(chunk.group));
}

/**
 * Generate an index.html listing all profile entry points.
 * @param {string} outputDir - Directory where profile HTMLs were written
 * @param {Object} profiles - The profiles config object
 * @param {Object} config - Full config object for KB info
 */
function generateProfileIndex(outputDir, profiles, config) {
  const kb = config.knowledge_body || {};
  const profileEntries = Object.entries(profiles);

  if (profileEntries.length <= 1) return; // No index needed for single profile

  const rows = profileEntries.map(([name, p]) => {
    return `<tr>
      <td><a href="${name}.html" style="color:#2a6bb8;font-weight:600;text-decoration:none;">${name}</a></td>
      <td>${p.label || name}</td>
      <td>${(p.exclude_types || []).length > 0 ? p.exclude_types.join(', ') : '（全部）'}</td>
    </tr>`;
  }).join('\n');

  const html = `<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${kb.name || ''} — 知識助理</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f5f6f8; color: #1e2030; margin: 0; padding: 2rem; }
.wrapper { max-width: 800px; margin: 0 auto; }
h1 { font-size: 2rem; margin-bottom: 0.5rem; }
.subtitle { color: #5e6070; margin-bottom: 2rem; }
table { width: 100%; border-collapse: collapse; background: #ecedf0; border-radius: 8px; overflow: hidden; }
th { background: #dfe0e5; padding: 10px 14px; text-align: left; font-size: 14px; font-weight: 600; }
td { padding: 10px 14px; border-top: 1px solid #dfe0e5; }
footer { margin-top: 2rem; font-size: 14px; color: #8a8c98; }
</style>
</head>
<body>
<div class="wrapper">
<h1>${kb.name || '知識助理'}</h1>
<p class="subtitle">${kb.organization || ''}</p>
<table>
<thead><tr><th>Profile</th><th>名稱</th><th>排除類型</th></tr></thead>
<tbody>
${rows}
</tbody>
</table>
<footer>Generated: ${new Date().toISOString().slice(0, 19).replace('T', ' ')}</footer>
</div>
</body>
</html>`;

  const indexPath = path.join(outputDir, 'index.html');
  fs.writeFileSync(indexPath, html);
  console.log(`[build] Profile index: ${indexPath}`);
}

/**
 * Main build function. Can be called programmatically or from CLI.
 * Outputs one HTML per profile: {outputDir}/{profileName}.html
 *
 * @param {Object} [overrides]
 * @param {string} [overrides.outputDir] - Override output directory
 * @param {Object} [overrides.config] - Override config (skip loadConfig)
 */
async function build(overrides = {}) {
  const config = overrides.config || loadConfig();

  const outputDir = overrides.outputDir
    ? path.resolve(overrides.outputDir)
    : PROJECT_ROOT;

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
      chunk_threshold: config.chunk_threshold,
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

  // ---- Step 2c: Generate JSON schemas from FRM fields ----
  const knowledgeDir = docsPath || path.join(PROJECT_ROOT, 'knowledge');
  if (reportedConfig.enabled !== false) {
    const schemasDir = path.join(PROJECT_ROOT, 'data', 'schemas');
    const generated = generateAllSchemas(knowledgeDir, schemasDir, domain.metadata_filename);
    if (generated.length > 0) {
      console.log(`[build] Generated ${generated.length} form schemas`);
    }
  }

  // ---- Step 2d: External data sources ----
  const externalResult = await fetchExternalSources(config, domain.metadata_filename, PROJECT_ROOT);
  allChunks.push(...externalResult.chunks);
  Object.assign(renderedDocs, externalResult.renderedDocs);
  if (externalResult.chunks.length > 0) {
    console.log(`[build] External: ${externalResult.chunks.length} chunks merged`);
  }

  console.log(`[build] Total chunks: ${allChunks.length}`);

  // ---- Profile loop (Steps 3-7) ----
  const profiles = config.profiles || {
    assistant: {
      label: ui.assistant_title || '知識助理',
      system_prompt_key: 'system_prompt',
      exclude_types: [],
      qa_questions: 'qa-questions.json',
    },
  };

  // Read template and MiniSearch lib once (shared across profiles)
  const templatePath = path.join(PROJECT_ROOT, 'templates', 'assistant.html');
  const miniSearchPath = path.join(PROJECT_ROOT, 'node_modules', 'minisearch', 'dist', 'umd', 'index.js');

  if (!fs.existsSync(templatePath)) {
    console.error(`[build] Template not found: ${templatePath}`);
    process.exit(1);
  }

  const templateHtml = fs.readFileSync(templatePath, 'utf8');
  const miniSearchLib = readFileSafe(miniSearchPath) || '';

  const appConfig = {
    api_key: '',  // API key is entered by the user in the browser, never embedded
    model: api.model || 'claude-sonnet-4-20250514',
    max_tokens_per_turn: 4096,
    locale: ui.locale || 'zh-TW',
    no_result_message: ui.no_result_message || '',
  };

  for (const [profileName, profile] of Object.entries(profiles)) {
    // Validate profile key format (spec 3.1)
    if (!/^[a-z0-9-]+$/.test(profileName)) {
      console.error(`[build] Invalid profile key "${profileName}" — must match [a-z0-9-]+, skipping`);
      continue;
    }

    // ---- Step 3: Filter chunks for this profile ----
    const profileChunks = filterChunks(allChunks, profile.exclude_types);

    // ---- Step 4: Build indexes ----
    const metaIndex = buildMetaIndex(profileChunks);
    const searchIndexJson = buildSearchIndex(profileChunks);

    // Build chunksMap: { chunk_id: { text, doc_key, title } }
    const chunksMap = {};
    for (const chunk of profileChunks) {
      chunksMap[chunk.chunk_id] = { text: chunk.text, doc_key: chunk.doc_key, title: chunk.title };
    }

    console.log(`[build] Profile "${profileName}": ${profileChunks.length} chunks, meta index: ${metaIndex.length} entries`);

    // ---- Step 5: Filter rendered docs to only include matching doc_keys ----
    const profileRenderedDocs = {};
    const profileDocKeys = new Set(profileChunks.map(c => c.doc_key));
    for (const [key, html] of Object.entries(renderedDocs)) {
      if (profileDocKeys.has(key)) profileRenderedDocs[key] = html;
    }

    // ---- Step 6: Assemble HTML from template ----
    let template = templateHtml;

    // Replace MiniSearch lib
    if (miniSearchLib) {
      template = template.replace(
        '<script>/*__MINISEARCH_LIB__*/</script>',
        `<script>${miniSearchLib}</script>`
      );
    }

    // Replace data placeholders
    template = replacePlaceholder(template, '__CHUNKS__', '{}', JSON.stringify(chunksMap));
    template = replacePlaceholder(template, '__META_INDEX__', '[]', JSON.stringify(metaIndex));
    template = replacePlaceholder(template, '__SEARCH_INDEX__', '"{}"', JSON.stringify(searchIndexJson));

    // Escape </script> inside embedded HTML to prevent breaking the outer <script> tag
    const renderedJson = JSON.stringify(profileRenderedDocs).replace(/<\/script>/gi, '<\\/script>');
    template = replacePlaceholder(template, '__RENDERED_DOCS__', '{}', renderedJson);

    // Inject glossary (shared across all profiles)
    const glossaryRaw = readFileSafe(path.join(PROJECT_ROOT, '_meta', 'glossary.json'));
    let glossaryJson = '{}';
    if (glossaryRaw) {
      try {
        JSON.parse(glossaryRaw);
        glossaryJson = glossaryRaw;
      } catch (e) {
        console.warn('[build] glossary.json is not valid JSON, using empty {}');
      }
    }
    template = replacePlaceholder(template, '__GLOSSARY__', '{}', glossaryJson);

    // Replace APP_CONFIG
    template = template.replace(
      /\/\*__APP_CONFIG__\*\/\{[^\n]*\}/,
      `/*__APP_CONFIG__*/${JSON.stringify(appConfig)}`
    );

    // Inject akora-app client config (if .github/akora.json or .gitlab/akora.json exists)
    let akoraClientConfig = null;
    for (const p of ['.github/akora.json', '.gitlab/akora.json']) {
      const akoraPath = path.join(PROJECT_ROOT, p);
      if (fs.existsSync(akoraPath)) {
        try {
          akoraClientConfig = JSON.parse(fs.readFileSync(akoraPath, 'utf8'));
        } catch { /* ignore malformed config */ }
        break;
      }
    }
    if (akoraClientConfig) {
      const akoraJs = `<script>window.__AKORA__=${JSON.stringify({
        endpoint: akoraClientConfig.endpoint || 'https://akora.weiqi.kids',
        installation_id: akoraClientConfig.installation_id,
        platform: akoraClientConfig.platform || 'github',
        repo: config.form_submission?.repo || '',
      })};</script>`;
      template = template.replace('</head>', `${akoraJs}\n</head>`);
    }

    // Substitute UI/domain placeholders with profile overrides
    template = substitutePlaceholders(template, config, profile);

    // ---- Step 7: Write output ----
    const profileDestFile = path.join(outputDir, `${profileName}.html`);
    fs.mkdirSync(path.dirname(profileDestFile), { recursive: true });
    fs.writeFileSync(profileDestFile, template, 'utf8');

    const sizeMB = (fs.statSync(profileDestFile).size / (1024 * 1024)).toFixed(2);
    console.log(`[build] Profile "${profileName}": ${profileChunks.length} chunks → ${profileDestFile} (${sizeMB} MB)`);
  }

  // Generate profile index (only if multiple profiles)
  generateProfileIndex(outputDir, profiles, config);

  // ---- Step 8: Post-process form pages ----
  if (reportedConfig.enabled !== false) {
    const formCount = postProcessForms(outputDir, PROJECT_ROOT, config, domain.metadata_filename);
    if (formCount > 0) console.log(`[build] Post-processed ${formCount} form pages`);

    // Render record pages
    const reportedDir = path.resolve(PROJECT_ROOT, reportedConfig.path || 'data/reported');
    const recordCount = renderRecords(reportedDir, outputDir, knowledgeDir, domain.metadata_filename);
    if (recordCount > 0) console.log(`[build] Rendered ${recordCount} record pages`);
  }
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

if (require.main === module) {
  const [,, outputDir] = process.argv;
  build({ outputDir }).catch(err => {
    console.error(`[build] Fatal: ${err.message}`);
    process.exit(1);
  });
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
  filterChunks,
  generateProfileIndex,
  build,
  // Internal helpers exported for testing
  findFiles,
  readFileSafe,
  extractZhPath,
  extractDocumentId,
  renderMarkdownToHtml,
  convertNumbersToChinese,
};
