'use strict';

/**
 * Office document importers for .docx, .xlsx, and .pptx files.
 *
 * Dependencies:
 *   - mammoth  (docx)
 *   - exceljs  (xlsx/spreadsheets)
 *   - adm-zip  (pptx — optional, graceful degradation)
 */

const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// DOCX
// ---------------------------------------------------------------------------

/**
 * Parse a .docx file and return the standard importer output format.
 * @param {string} filePath
 * @returns {Promise<object>}
 */
async function parseDocx(filePath) {
  let mammoth;
  try {
    mammoth = require('mammoth');
  } catch (e) {
    throw new Error(`[DOCX parser not available: ${e.message}]`);
  }

  const buffer = fs.readFileSync(filePath);
  const result = await mammoth.extractRawText({ buffer });

  const text = result.value || '';

  return {
    source_file: filePath,
    parsed_at: new Date().toISOString(),
    pages: [{ page: 1, text: text.trim(), tables: [] }],
    metadata: {
      title: path.basename(filePath, '.docx'),
      author: '',
      page_count: 1,
    },
  };
}

// ---------------------------------------------------------------------------
// XLSX
// ---------------------------------------------------------------------------

/**
 * Parse a .xlsx (or .xls / .csv) file using exceljs.
 * Each sheet becomes one page entry. Tables are included as 2-D arrays.
 * @param {string} filePath
 * @returns {Promise<object>}
 */
async function parseXlsx(filePath) {
  let ExcelJS;
  try {
    ExcelJS = require('exceljs');
  } catch (e) {
    throw new Error(`[XLSX parser not available: ${e.message}]`);
  }

  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(filePath);

  const pages = [];
  workbook.eachSheet((worksheet, sheetIndex) => {
    const table = [];
    const csvLines = [];

    worksheet.eachRow({ includeEmpty: false }, (row) => {
      const rowValues = row.values.slice(1); // row.values is 1-indexed
      const cells = rowValues.map(v => (v === null || v === undefined) ? '' : String(v));
      table.push(cells);
      csvLines.push(cells.join(','));
    });

    pages.push({
      page: sheetIndex,
      sheet_name: worksheet.name,
      text: `[Sheet: ${worksheet.name}]\n${csvLines.join('\n')}`,
      tables: [table],
    });
  });

  return {
    source_file: filePath,
    parsed_at: new Date().toISOString(),
    pages,
    metadata: {
      title: path.basename(filePath, path.extname(filePath)),
      author: '',
      page_count: pages.length,
    },
  };
}

// ---------------------------------------------------------------------------
// PPTX
// ---------------------------------------------------------------------------

/**
 * Extract text from a .pptx file by reading slide XML via adm-zip.
 * adm-zip is optional; returns graceful error message if not installed.
 * @param {string} filePath
 * @returns {Promise<object>}
 */
async function parsePptx(filePath) {
  let AdmZip;
  try {
    AdmZip = require('adm-zip');
  } catch (e) {
    return {
      source_file: filePath,
      parsed_at: new Date().toISOString(),
      pages: [{ page: 1, text: `[PPTX parser not available: Cannot find module 'adm-zip']`, tables: [] }],
      metadata: {
        title: path.basename(filePath, '.pptx'),
        author: '',
        page_count: 0,
      },
    };
  }

  const zip = new AdmZip(filePath);
  const entries = zip.getEntries();

  // Collect slide XML files sorted by slide number
  const slideEntries = entries
    .filter(e => /^ppt\/slides\/slide\d+\.xml$/.test(e.entryName))
    .sort((a, b) => {
      const numA = parseInt(a.entryName.match(/\d+/)[0], 10);
      const numB = parseInt(b.entryName.match(/\d+/)[0], 10);
      return numA - numB;
    });

  const pages = slideEntries.map((entry, i) => {
    const xml = entry.getData().toString('utf8');
    const text = extractTextFromSlideXml(xml);
    return {
      page: i + 1,
      text: text.trim(),
      tables: [],
    };
  });

  if (pages.length === 0) {
    pages.push({ page: 1, text: '', tables: [] });
  }

  return {
    source_file: filePath,
    parsed_at: new Date().toISOString(),
    pages,
    metadata: {
      title: path.basename(filePath, '.pptx'),
      author: '',
      page_count: pages.length,
    },
  };
}

/**
 * Extract plain text from a PPTX slide XML string.
 * Strips all XML tags, collects text run content.
 * @param {string} xml
 * @returns {string}
 */
function extractTextFromSlideXml(xml) {
  // Match <a:t>...</a:t> text run elements
  const runs = [];
  const re = /<a:t[^>]*>([^<]*)<\/a:t>/g;
  let match;
  while ((match = re.exec(xml)) !== null) {
    const text = match[1]
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'");
    if (text.trim()) runs.push(text);
  }
  return runs.join(' ');
}

module.exports = {
  docx: { parse: parseDocx },
  xlsx: { parse: parseXlsx },
  pptx: { parse: parsePptx },
};
