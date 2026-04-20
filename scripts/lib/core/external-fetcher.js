// scripts/lib/core/external-fetcher.js
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const { chunkMarkdown } = require('./chunk');
const { renderMarkdownToHtml } = require('./markdown-renderer');

function matchGlob(name, pattern) {
  const regex = new RegExp('^' + pattern.replace(/\./g, '\\.').replace(/\*/g, '.*') + '$');
  return regex.test(name);
}

function buildExternalDocKey(sourceName, documentId) {
  return `external/${sourceName}/${documentId}`;
}

function resolveCloneUrl(source, env) {
  const token = source.token_env ? (env[source.token_env] || '') : '';
  if (source.gitlab_endpoint) {
    const host = source.gitlab_endpoint.replace(/\/$/, '');
    return token
      ? `https://oauth2:${token}@${host.replace('https://', '')}/${source.repo}.git`
      : `${host}/${source.repo}.git`;
  }
  return token
    ? `https://${token}@github.com/${source.repo}.git`
    : `https://github.com/${source.repo}.git`;
}

function cloneExternal(source, env) {
  const tmpDir = path.join(os.tmpdir(), `akora-external-${source.name}-${Date.now()}`);
  const url = resolveCloneUrl(source, env);
  const ref = source.ref || 'main';

  try {
    execFileSync('git', [
      'clone', '--depth', '1', '--filter=blob:none', '--sparse',
      '--branch', ref, url, tmpDir,
    ], { stdio: 'pipe' });

    execFileSync('git', ['sparse-checkout', 'set', source.path], {
      cwd: tmpDir, stdio: 'pipe',
    });
  } catch (err) {
    console.warn(`[external] Failed to clone ${source.name} (${source.repo}): ${err.message}`);
    fs.rmSync(tmpDir, { recursive: true, force: true });
    return null;
  }

  return tmpDir;
}

function readExternalDocuments(tmpDir, source, metadataFilename = 'merge.yaml') {
  const docsPath = path.join(tmpDir, source.path);
  if (!fs.existsSync(docsPath)) {
    console.warn(`[external] Path not found in clone: ${docsPath}`);
    return { chunks: [], renderedDocs: {} };
  }

  const folders = fs.readdirSync(docsPath, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);

  // Apply include filter
  const include = source.include || [];
  const filtered = include.length > 0
    ? folders.filter(f => include.some(pattern => matchGlob(f, pattern)))
    : folders;

  if (include.length > 0 && filtered.length === 0) {
    console.warn(`[external] No directories matched include patterns [${include.join(', ')}] in ${source.name}`);
  }

  const chunks = [];
  const renderedDocs = {};

  for (const folder of filtered) {
    const yamlPath = path.join(docsPath, folder, metadataFilename);
    if (!fs.existsSync(yamlPath)) continue;

    const yamlContent = fs.readFileSync(yamlPath, 'utf8');
    const docIdMatch = yamlContent.match(/^document_id:\s*(.+)$/m);
    const zhPathMatch = yamlContent.match(/^\s*zh:\s*(.+)$/m);
    if (!docIdMatch || !zhPathMatch) continue;

    const documentId = docIdMatch[1].trim();
    const zhFile = zhPathMatch[1].trim();
    const mdPath = path.join(docsPath, folder, zhFile);
    if (!fs.existsSync(mdPath)) continue;

    const md = fs.readFileSync(mdPath, 'utf8');
    const docKey = buildExternalDocKey(source.name, documentId);

    const docChunks = chunkMarkdown(md, docKey);
    chunks.push(...docChunks);

    // Simple HTML rendering for document viewer
    const titleMatch = yamlContent.match(/^title_zh:\s*(.+)$/m);
    const title = titleMatch ? titleMatch[1].trim() : documentId;
    renderedDocs[docKey] = renderMarkdownToHtml(md, title);
  }

  return { chunks, renderedDocs };
}

function fetchExternalSources(config, metadataFilename = 'merge.yaml') {
  const sources = config.data_sources?.external || [];
  if (sources.length === 0) return { chunks: [], renderedDocs: {} };

  const allChunks = [];
  const allRenderedDocs = {};
  const env = process.env;

  for (const source of sources) {
    if (!source.name || !source.repo || !source.path) {
      console.warn(`[external] Skipping invalid source: missing name/repo/path`);
      continue;
    }

    if (source.token_env && !env[source.token_env]) {
      console.error(`[external] ${source.name}: token_env "${source.token_env}" not set, skipping`);
      continue;
    }

    console.log(`[external] Fetching ${source.name} from ${source.repo}...`);
    const tmpDir = cloneExternal(source, env);
    if (!tmpDir) continue;

    try {
      const { chunks, renderedDocs } = readExternalDocuments(tmpDir, source, metadataFilename);
      allChunks.push(...chunks);
      Object.assign(allRenderedDocs, renderedDocs);
      console.log(`[external] ${source.name}: ${chunks.length} chunks from ${Object.keys(renderedDocs).length} documents`);
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  }

  return { chunks: allChunks, renderedDocs: allRenderedDocs };
}

module.exports = {
  fetchExternalSources,
  matchGlob,
  buildExternalDocKey,
  resolveCloneUrl,
  cloneExternal,
  readExternalDocuments,
};
