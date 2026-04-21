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

/**
 * Resolve akora-app configuration for centralized token management.
 *
 * Priority:
 *   1. AKORA_INSTALLATION_ID + AKORA_BUILD_TOKEN env vars
 *   2. .github/akora.json or .gitlab/akora.json + AKORA_BUILD_TOKEN env var
 *   3. null (fall back to per-source token_env)
 *
 * @param {string} projectRoot - Absolute path to project root
 * @returns {{ installation_id: string, build_token: string, endpoint: string, platform: string } | null}
 */
function resolveAkoraConfig(projectRoot) {
  const envInstallationId = process.env.AKORA_INSTALLATION_ID;
  const envBuildToken = process.env.AKORA_BUILD_TOKEN;
  const envEndpoint = process.env.AKORA_ENDPOINT;

  // Priority 1: all from env vars
  if (envInstallationId && envBuildToken) {
    return {
      installation_id: envInstallationId,
      build_token: envBuildToken,
      endpoint: envEndpoint || 'https://akora.weiqi.kids',
      platform: process.env.AKORA_PLATFORM || 'github',
    };
  }

  // Priority 2: config file + env build token
  for (const configPath of ['.github/akora.json', '.gitlab/akora.json']) {
    const fullPath = path.join(projectRoot, configPath);
    if (fs.existsSync(fullPath)) {
      try {
        const config = JSON.parse(fs.readFileSync(fullPath, 'utf8'));
        if (config.installation_id && envBuildToken) {
          return {
            installation_id: String(config.installation_id),
            build_token: envBuildToken,
            endpoint: config.endpoint || 'https://akora.weiqi.kids',
            platform: config.platform || 'github',
          };
        }
      } catch { /* ignore malformed config */ }
    }
  }

  return null;
}

/**
 * Fetch a short-lived installation token from the akora-app server.
 *
 * @param {{ installation_id: string, build_token: string, endpoint: string, platform: string }} akoraConfig
 * @returns {Promise<string>} Installation token
 */
async function fetchAkoraToken(akoraConfig) {
  const resp = await fetch(`${akoraConfig.endpoint}/token`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${akoraConfig.build_token}`,
    },
    body: JSON.stringify({
      installation_id: akoraConfig.installation_id,
      platform: akoraConfig.platform,
    }),
  });
  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`akora-app /token failed (${resp.status}): ${body}`);
  }
  const data = await resp.json();
  return data.token;
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

/**
 * Build a clone URL using an explicit token (from akora-app) instead of
 * per-source token_env.  Falls back to resolveCloneUrl when token is empty.
 */
function resolveCloneUrlWithToken(source, token) {
  if (!token) return resolveCloneUrl(source, process.env);
  if (source.gitlab_endpoint) {
    const host = source.gitlab_endpoint.replace(/\/$/, '');
    return `https://oauth2:${token}@${host.replace('https://', '')}/${source.repo}.git`;
  }
  return `https://x-access-token:${token}@github.com/${source.repo}.git`;
}

function cloneExternal(source, env, akoraToken) {
  const tmpDir = path.join(os.tmpdir(), `akora-external-${source.name}-${Date.now()}`);
  const url = akoraToken
    ? resolveCloneUrlWithToken(source, akoraToken)
    : resolveCloneUrl(source, env);
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

/**
 * Recursively find all directories containing a metadata file.
 * @param {string} baseDir - Root directory to search
 * @param {string} metadataFilename - Filename to look for (e.g. 'merge.yaml')
 * @returns {string[]} Array of absolute directory paths containing the metadata file
 */
function findDocumentDirs(baseDir, metadataFilename) {
  const results = [];
  if (!fs.existsSync(baseDir)) return results;

  const entries = fs.readdirSync(baseDir, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name.startsWith('.') || entry.name.startsWith('_')) continue;
    const dirPath = path.join(baseDir, entry.name);
    const yamlPath = path.join(dirPath, metadataFilename);
    if (fs.existsSync(yamlPath)) {
      results.push(dirPath);
    }
    // Recurse into subdirectories
    results.push(...findDocumentDirs(dirPath, metadataFilename));
  }
  return results;
}

function readExternalDocuments(tmpDir, source, metadataFilename = 'merge.yaml') {
  const docsPath = path.join(tmpDir, source.path);
  if (!fs.existsSync(docsPath)) {
    console.warn(`[external] Path not found in clone: ${docsPath}`);
    return { chunks: [], renderedDocs: {} };
  }

  // Recursively find all directories containing merge.yaml
  const docDirs = findDocumentDirs(docsPath, metadataFilename);

  // Apply include filter (match against relative path from docsPath)
  const include = source.include || [];
  const filtered = include.length > 0
    ? docDirs.filter(dir => {
        const relPath = path.relative(docsPath, dir);
        const dirName = path.basename(dir);
        // Match against both the directory name and the relative path
        return include.some(pattern => matchGlob(dirName, pattern) || matchGlob(relPath, pattern));
      })
    : docDirs;

  if (include.length > 0 && filtered.length === 0) {
    console.warn(`[external] No directories matched include patterns [${include.join(', ')}] in ${source.name}`);
  }

  const chunks = [];
  const renderedDocs = {};

  for (const dirPath of filtered) {
    const yamlPath = path.join(dirPath, metadataFilename);
    const yamlContent = fs.readFileSync(yamlPath, 'utf8');
    const docIdMatch = yamlContent.match(/^document_id:\s*(.+)$/m);
    const zhPathMatch = yamlContent.match(/^\s*zh:\s*(.+)$/m);
    if (!docIdMatch || !zhPathMatch) continue;

    const documentId = docIdMatch[1].trim();
    const zhFile = zhPathMatch[1].trim();
    const mdPath = path.join(dirPath, zhFile);
    if (!fs.existsSync(mdPath)) continue;

    const md = fs.readFileSync(mdPath, 'utf8');
    const docKey = buildExternalDocKey(source.name, documentId);

    const docChunks = chunkMarkdown(md, docKey);
    chunks.push(...docChunks);

    const titleMatch = yamlContent.match(/^title_zh:\s*(.+)$/m);
    const title = titleMatch ? titleMatch[1].trim() : documentId;
    renderedDocs[docKey] = renderMarkdownToHtml(md, title);
  }

  return { chunks, renderedDocs };
}

/**
 * Fetch all external sources, cloning each repo and reading documents.
 *
 * When an akora-app config is available (via env vars or .github/akora.json),
 * a single installation token is fetched and reused for ALL external sources.
 * Otherwise, falls back to per-source token_env (PAT).
 *
 * @param {Object} config - Full project config
 * @param {string} [metadataFilename] - Metadata filename (default: 'merge.yaml')
 * @param {string} [projectRoot] - Absolute path to project root (for akora.json lookup)
 * @returns {{ chunks: Object[], renderedDocs: Object }}
 */
async function fetchExternalSources(config, metadataFilename = 'merge.yaml', projectRoot = '') {
  const sources = config.data_sources?.external || [];
  if (sources.length === 0) return { chunks: [], renderedDocs: {} };

  const allChunks = [];
  const allRenderedDocs = {};
  const env = process.env;

  // Try to resolve a centralized akora-app token
  let akoraToken = null;
  if (projectRoot) {
    const akoraConfig = resolveAkoraConfig(projectRoot);
    if (akoraConfig) {
      try {
        akoraToken = await fetchAkoraToken(akoraConfig);
        console.log(`[external] Using akora-app token (${akoraConfig.platform})`);
      } catch (err) {
        console.warn(`[external] akora-app token failed, falling back to per-source tokens: ${err.message}`);
      }
    }
  }

  for (const source of sources) {
    if (!source.name || !source.repo || !source.path) {
      console.warn(`[external] Skipping invalid source: missing name/repo/path`);
      continue;
    }

    // When no akora token, require per-source token_env (existing behavior)
    if (!akoraToken && source.token_env && !env[source.token_env]) {
      console.error(`[external] ${source.name}: token_env "${source.token_env}" not set, skipping`);
      continue;
    }

    console.log(`[external] Fetching ${source.name} from ${source.repo}...`);
    const tmpDir = cloneExternal(source, env, akoraToken);
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
  findDocumentDirs,
  matchGlob,
  buildExternalDocKey,
  resolveCloneUrl,
  resolveCloneUrlWithToken,
  resolveAkoraConfig,
  fetchAkoraToken,
  cloneExternal,
  readExternalDocuments,
};
