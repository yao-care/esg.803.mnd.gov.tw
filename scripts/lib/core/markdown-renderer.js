// scripts/lib/core/markdown-renderer.js
'use strict';

/**
 * markdown-renderer.js — Standalone Markdown → HTML renderer
 *
 * Extracted from build.js to break the circular dependency between
 * build.js and external-fetcher.js.
 *
 * Both build.js and external-fetcher.js import from this module.
 * build.js re-exports renderMarkdownToHtml for backward compatibility.
 */

const CHINESE_NUMBERS = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十'];

/**
 * Convert numbered headings to Chinese-style numbering.
 * - `## 1. Title` → `## 一、Title`  (top-level sections)
 * - `### X.Y Title` → `### （Y中文）Title`  (sub-sections)
 *
 * This runs ONLY in renderMarkdownToHtml (display), NOT in chunkMarkdown (search).
 *
 * @param {string} markdown
 * @returns {string}
 */
function convertNumbersToChinese(markdown) {
  // Convert top-level: ## 1. Title → ## 一、Title
  let result = markdown.replace(/^(## )(\d+)\. (.+)$/gm, (match, prefix, num, title) => {
    const cn = CHINESE_NUMBERS[parseInt(num)] || num;
    return `${prefix}${cn}、${title}`;
  });

  // Convert sub-sections: ### X.Y Title → ### （Y中文）Title
  result = result.replace(/^(### )\d+\.(\d+) (.+)$/gm, (match, prefix, subNum, title) => {
    const cn = CHINESE_NUMBERS[parseInt(subNum)] || subNum;
    return `${prefix}（${cn}）${title}`;
  });

  return result;
}

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

  // Convert numbered headings to Chinese format (display only)
  body = convertNumbersToChinese(body);

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

module.exports = {
  renderMarkdownToHtml,
  convertNumbersToChinese,
  CHINESE_NUMBERS,
};
