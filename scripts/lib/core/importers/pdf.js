'use strict';

/**
 * PDF importer — uses pdf-parse to extract text from PDF files.
 */

const fs = require('fs');
const path = require('path');

/**
 * Parse a PDF file and return the standard importer output format.
 * @param {string} filePath  Absolute or relative path to the PDF file.
 * @returns {Promise<object>}
 */
async function parse(filePath) {
  let pdfParse;
  try {
    pdfParse = require('pdf-parse');
  } catch (e) {
    throw new Error(`[PDF parser not available: ${e.message}]`);
  }

  const buffer = fs.readFileSync(filePath);
  const data = await pdfParse(buffer);

  // pdf-parse exposes per-page text via the `data.text` combined string,
  // and per-page info via a render callback. Use the combined text
  // and split by page count as a best-effort approach.
  const rawPages = splitIntoPages(data.text, data.numpages || 1);

  const pages = rawPages.map((text, i) => ({
    page: i + 1,
    text: text.trim(),
    tables: [],
  }));

  return {
    source_file: filePath,
    parsed_at: new Date().toISOString(),
    pages,
    metadata: {
      title: (data.info && data.info.Title) || path.basename(filePath, '.pdf'),
      author: (data.info && data.info.Author) || '',
      page_count: data.numpages || pages.length,
    },
  };
}

/**
 * Split combined text into approximate per-page segments.
 * pdf-parse does not guarantee page boundaries in its default output,
 * so we divide the text evenly when count > 1.
 * @param {string} text
 * @param {number} pageCount
 * @returns {string[]}
 */
function splitIntoPages(text, pageCount) {
  if (pageCount <= 1) return [text];
  const chunkSize = Math.ceil(text.length / pageCount);
  const pages = [];
  for (let i = 0; i < pageCount; i++) {
    pages.push(text.slice(i * chunkSize, (i + 1) * chunkSize));
  }
  return pages;
}

module.exports = { parse };
