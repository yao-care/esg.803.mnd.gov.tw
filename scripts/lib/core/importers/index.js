'use strict';

/**
 * Importer dispatcher — selects the correct parser module based on file extension.
 *
 * Supported extensions:
 *   .pdf                → pdf.js
 *   .docx               → office.js (docx)
 *   .xlsx               → office.js (xlsx)
 *   .pptx               → office.js (pptx)
 *   .png .jpg .jpeg     → image.js
 */

const path = require('path');

const pdf = require('./pdf');
const office = require('./office');
const image = require('./image');

/**
 * Map of lowercase extension (without dot) → importer module with a `parse` function.
 */
const EXTENSION_MAP = {
  pdf: pdf,
  docx: office.docx,
  xlsx: office.xlsx,
  pptx: office.pptx,
  png: image,
  jpg: image,
  jpeg: image,
};

/**
 * Return the importer module for the given file path, or null if unsupported.
 * @param {string} filePath
 * @returns {{ parse: function }|null}
 */
function selectImporter(filePath) {
  const ext = path.extname(filePath).toLowerCase().replace(/^\./, '');
  return EXTENSION_MAP[ext] || null;
}

/**
 * Parse a file using the appropriate importer.
 * Throws if the file type is unsupported.
 * @param {string} filePath
 * @returns {Promise<object>}
 */
async function parseFile(filePath) {
  const importer = selectImporter(filePath);
  if (!importer) {
    throw new Error(`Unsupported file type: ${path.extname(filePath)}`);
  }
  return importer.parse(filePath);
}

module.exports = { selectImporter, parseFile, EXTENSION_MAP };
