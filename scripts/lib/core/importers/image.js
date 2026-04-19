'use strict';

/**
 * Image importer — uses tesseract.js for OCR.
 * tesseract.js is an optional heavy dependency.
 * Returns graceful error text if not installed.
 */

const path = require('path');

/**
 * Run OCR on an image file and return the standard importer output format.
 * @param {string} filePath  Path to the image file (.png, .jpg, .jpeg, etc.)
 * @returns {Promise<object>}
 */
async function parse(filePath) {
  let Tesseract;
  try {
    Tesseract = require('tesseract.js');
  } catch (e) {
    return {
      source_file: filePath,
      parsed_at: new Date().toISOString(),
      pages: [
        {
          page: 1,
          text: `[OCR not available: ${e.message}]`,
          tables: [],
        },
      ],
      metadata: {
        title: path.basename(filePath, path.extname(filePath)),
        author: '',
        page_count: 1,
      },
    };
  }

  const { data } = await Tesseract.recognize(filePath, 'eng');

  return {
    source_file: filePath,
    parsed_at: new Date().toISOString(),
    pages: [
      {
        page: 1,
        text: (data.text || '').trim(),
        tables: [],
      },
    ],
    metadata: {
      title: path.basename(filePath, path.extname(filePath)),
      author: '',
      page_count: 1,
    },
  };
}

module.exports = { parse };
