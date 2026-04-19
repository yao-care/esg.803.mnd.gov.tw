'use strict';

/**
 * chunk.js — Document Chunker for Knowledge Body
 *
 * Processes markdown documents and collected result JSON files into
 * structured chunks suitable for MiniSearch indexing and Claude API context.
 *
 * Generalized from agent.system-integration-quality-control/scripts/lib/audit-assistant/chunk.js:
 * - "isms" type → "document" type
 * - "scan" type → "collected" type
 * - ISO control labels → generic/optional control labels
 * - chunkScanResult → chunkCollectedResult
 */

/**
 * Parse YAML frontmatter from a markdown string.
 *
 * Supports:
 * - Flat scalar fields:  key: value
 * - Quoted scalars:      key: "value"
 * - JSON arrays:         key: ["a", "b", "c"]
 *
 * @param {string} md - Markdown content (may or may not have frontmatter)
 * @returns {Object} Parsed frontmatter fields, or {} if none present
 */
function parseYamlFrontmatter(md) {
  if (!md || typeof md !== 'string') return {};

  const match = md.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return {};

  const block = match[1];
  const result = {};

  for (const line of block.split(/\r?\n/)) {
    // Skip blank lines and comment lines
    if (!line.trim() || line.trim().startsWith('#')) continue;

    const colonIdx = line.indexOf(':');
    if (colonIdx === -1) continue;

    const key = line.slice(0, colonIdx).trim();
    const rawValue = line.slice(colonIdx + 1).trim();

    if (!key) continue;

    // JSON array: ["a", "b"]
    if (rawValue.startsWith('[')) {
      try {
        result[key] = JSON.parse(rawValue);
      } catch {
        result[key] = rawValue;
      }
      continue;
    }

    // Quoted string: "value" or 'value'
    if ((rawValue.startsWith('"') && rawValue.endsWith('"')) ||
        (rawValue.startsWith("'") && rawValue.endsWith("'"))) {
      result[key] = rawValue.slice(1, -1);
      continue;
    }

    // Plain scalar
    result[key] = rawValue;
  }

  return result;
}

/**
 * Strip YAML frontmatter from markdown, returning body only.
 *
 * @param {string} md
 * @returns {string}
 */
function stripFrontmatter(md) {
  if (!md || typeof md !== 'string') return '';
  return md.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, '');
}

/**
 * Split markdown body by `## ` headings.
 * Returns array of { heading, content } objects.
 * The first element (before any heading) has heading = null.
 *
 * @param {string} body
 * @returns {Array<{heading: string|null, content: string}>}
 */
function splitByH2(body) {
  const sections = [];
  const parts = body.split(/^(?=## )/m);

  for (const part of parts) {
    const headingMatch = part.match(/^## (.+)/);
    if (headingMatch) {
      const heading = headingMatch[1].trim();
      const content = part.slice(headingMatch[0].length).trim();
      sections.push({ heading, content });
    } else {
      const content = part.trim();
      if (content) {
        sections.push({ heading: null, content });
      }
    }
  }

  return sections;
}

/**
 * Split a section by `### ` sub-headings for large sections.
 *
 * @param {string} heading - Parent heading
 * @param {string} content - Section content
 * @returns {Array<{heading: string, content: string}>}
 */
function splitByH3(heading, content) {
  const parts = content.split(/^(?=### )/m);
  const result = [];

  for (const part of parts) {
    const subHeadingMatch = part.match(/^### (.+)/);
    if (subHeadingMatch) {
      const subHeading = `${heading} > ${subHeadingMatch[1].trim()}`;
      const subContent = part.slice(subHeadingMatch[0].length).trim();
      result.push({ heading: subHeading, content: subContent });
    } else {
      const trimmed = part.trim();
      if (trimmed) {
        result.push({ heading, content: trimmed });
      }
    }
  }

  return result.length > 0 ? result : [{ heading, content }];
}

/**
 * Build a chunk text with context header.
 *
 * @param {Object} params
 * @param {string} params.title
 * @param {string} params.docId
 * @param {string[]} params.controls
 * @param {string} params.section
 * @param {string} params.content
 * @returns {string}
 */
function buildChunkText({ title, docId, controls, section, content }) {
  const controlsStr = controls && controls.length > 0
    ? controls.join(', ')
    : '';
  // Only include control line if controls are present
  const controlLine = controlsStr ? `[控制項: ${controlsStr}]` : '';

  const lines = [
    `[文件: ${title} (${docId})]`,
  ];
  if (controlLine) lines.push(controlLine);
  lines.push(`[章節: ${section}]`, '', content);

  return lines.join('\n');
}

/**
 * Slugify a section heading for use in chunk_id.
 *
 * @param {string} heading
 * @returns {string}
 */
function slugifySection(heading) {
  if (!heading) return 'intro';
  return heading
    .replace(/\s+/g, '-')
    .replace(/[^\w\-\u4e00-\u9fff\u3400-\u4dbf]/g, '')
    .toLowerCase();
}

/**
 * Chunk a markdown document into structured pieces.
 *
 * @param {string} md - Full markdown content including YAML frontmatter
 * @param {string} docKey - Document key used in chunk_id (e.g. "pro-002")
 * @param {Object} [config] - Optional configuration object (reserved for future use)
 * @returns {Array<Object>} Array of chunk objects
 */
function chunkMarkdown(md, docKey, config = {}) {
  const frontmatter = parseYamlFrontmatter(md);
  const body = stripFrontmatter(md);

  const docId = frontmatter.document_id || frontmatter.doc_id || docKey;
  const title = frontmatter.title_zh || frontmatter.title_en || frontmatter.title || docKey;
  const version = frontmatter.version || '';
  const group = frontmatter.group || '';
  const controls = Array.isArray(frontmatter.controls)
    ? frontmatter.controls
    : (Array.isArray(frontmatter.iso_27001_controls) ? frontmatter.iso_27001_controls : []);

  // Split by H2 headings
  const h2Sections = splitByH2(body);

  // Expand large sections by H3
  const rawChunks = [];
  for (const section of h2Sections) {
    const sectionHeading = section.heading || 'intro';
    if (section.content.length > 2000) {
      const subSections = splitByH3(sectionHeading, section.content);
      for (const sub of subSections) {
        rawChunks.push({ heading: sub.heading, content: sub.content });
      }
    } else {
      rawChunks.push({ heading: sectionHeading, content: section.content });
    }
  }

  // Build final chunk objects
  const chunks = rawChunks.map((c) => {
    const section = c.heading;
    const sectionSlug = slugifySection(section);
    const chunkId = `${docKey}#${sectionSlug}`;
    const text = buildChunkText({ title, docId, controls, section, content: c.content });

    return {
      chunk_id: chunkId,
      doc_id: docId,
      doc_key: docKey,
      title,
      version,
      section,
      controls,
      group,
      type: 'document',
      source_type: 'document',
      text,
    };
  });

  // Deduplicate chunk IDs: append -2, -3, ... for repeated IDs
  const idCount = {};
  for (const chunk of chunks) {
    if (idCount[chunk.chunk_id]) {
      idCount[chunk.chunk_id]++;
      chunk.chunk_id = `${chunk.chunk_id}-${idCount[chunk.chunk_id]}`;
    } else {
      idCount[chunk.chunk_id] = 1;
    }
  }

  return chunks;
}

/**
 * Create a single chunk from a collected result JSON object.
 *
 * @param {Object} json - Collected result object
 * @param {string} resultName - Identifier used in chunk_id (e.g. "vulnerability-result")
 * @param {Object} [config] - Optional configuration object (reserved for future use)
 * @returns {Array<Object>} Array containing single chunk object
 */
function chunkCollectedResult(json, resultName, config = {}) {
  const displayName = (config && config.displayName) || resultName;
  const text = `[收集結果: ${displayName}]\n[工具: ${json.tool || resultName}]\n[狀態: ${json.status || 'unknown'}]\n[時間: ${json.timestamp || 'unknown'}]\n\n${JSON.stringify(json, null, 2)}`;

  const chunk = {
    chunk_id: `collected/${resultName}`,
    doc_id: resultName,
    doc_key: `collected/${resultName}`,
    title: displayName,
    section: '',
    controls: [],
    type: 'collected',
    source_type: 'collected',
    text,
    char_count: text.length,
  };

  return [chunk];
}

module.exports = {
  parseYamlFrontmatter,
  stripFrontmatter,
  splitByH2,
  splitByH3,
  chunkMarkdown,
  chunkCollectedResult,
};
