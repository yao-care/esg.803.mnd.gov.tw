'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert');
const path = require('path');

const { selectImporter, parseFile, EXTENSION_MAP } = require('../importers/index');
const pdf = require('../importers/pdf');
const office = require('../importers/office');
const image = require('../importers/image');

// ---------------------------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------------------------
describe('importers/index.js — selectImporter', () => {
  it('returns pdf importer for .pdf', () => {
    const imp = selectImporter('document.pdf');
    assert.ok(imp, 'should return an importer');
    assert.strictEqual(typeof imp.parse, 'function');
  });

  it('returns docx importer for .docx', () => {
    const imp = selectImporter('report.docx');
    assert.ok(imp);
    assert.strictEqual(typeof imp.parse, 'function');
  });

  it('returns xlsx importer for .xlsx', () => {
    const imp = selectImporter('data.xlsx');
    assert.ok(imp);
    assert.strictEqual(typeof imp.parse, 'function');
  });

  it('returns pptx importer for .pptx', () => {
    const imp = selectImporter('slides.pptx');
    assert.ok(imp);
    assert.strictEqual(typeof imp.parse, 'function');
  });

  it('returns image importer for .png', () => {
    const imp = selectImporter('screenshot.png');
    assert.ok(imp);
    assert.strictEqual(typeof imp.parse, 'function');
  });

  it('returns image importer for .jpg', () => {
    const imp = selectImporter('photo.jpg');
    assert.ok(imp);
    assert.strictEqual(typeof imp.parse, 'function');
  });

  it('returns image importer for .jpeg', () => {
    const imp = selectImporter('photo.jpeg');
    assert.ok(imp);
    assert.strictEqual(typeof imp.parse, 'function');
  });

  it('handles uppercase extensions', () => {
    const imp = selectImporter('DOCUMENT.PDF');
    assert.ok(imp, 'should handle uppercase .PDF');
    assert.strictEqual(typeof imp.parse, 'function');
  });

  it('returns null for unsupported extension', () => {
    const imp = selectImporter('file.txt');
    assert.strictEqual(imp, null);
  });

  it('returns null for no extension', () => {
    const imp = selectImporter('Makefile');
    assert.strictEqual(imp, null);
  });

  it('parseFile throws for unsupported extension', async () => {
    await assert.rejects(
      () => parseFile('file.txt'),
      /Unsupported file type/
    );
  });
});

// ---------------------------------------------------------------------------
// Module interfaces
// ---------------------------------------------------------------------------
describe('importers/pdf.js — interface', () => {
  it('exports a parse function', () => {
    assert.strictEqual(typeof pdf.parse, 'function');
  });

  it('parse returns a Promise', () => {
    // pdf-parse may not be installed in CI, so we only check the type here.
    // Passing a non-existent path; the error will occur inside the promise.
    const result = pdf.parse('nonexistent.pdf');
    assert.ok(result instanceof Promise, 'parse should return a Promise');
    // Swallow the rejection so it does not fail the test runner.
    result.catch(() => {});
  });
});

describe('importers/office.js — interface', () => {
  it('exports docx, xlsx, pptx with parse functions', () => {
    assert.strictEqual(typeof office.docx.parse, 'function');
    assert.strictEqual(typeof office.xlsx.parse, 'function');
    assert.strictEqual(typeof office.pptx.parse, 'function');
  });
});

describe('importers/image.js — interface', () => {
  it('exports a parse function', () => {
    assert.strictEqual(typeof image.parse, 'function');
  });

  it('parse returns a Promise', () => {
    const result = image.parse('nonexistent.png');
    assert.ok(result instanceof Promise, 'parse should return a Promise');
    result.catch(() => {});
  });
});

// ---------------------------------------------------------------------------
// XLSX in-memory workbook round-trip
// ---------------------------------------------------------------------------
describe('importers/office.js — xlsx parser (in-memory workbook)', () => {
  it('parses an in-memory workbook created from array data', async () => {
    let XLSX;
    try {
      XLSX = require('xlsx');
    } catch (e) {
      // Skip if xlsx not installed
      return;
    }

    // Build an in-memory workbook from array data
    const sheetData = [
      ['Name', 'Score'],
      ['Alice', 95],
      ['Bob', 87],
    ];
    const ws = XLSX.utils.aoa_to_sheet(sheetData);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'Results');

    // Write to a temp buffer and parse via our importer
    const os = require('os');
    const tmpFile = path.join(os.tmpdir(), `test-workbook-${Date.now()}.xlsx`);
    XLSX.writeFile(wb, tmpFile);

    try {
      const result = await office.xlsx.parse(tmpFile);

      assert.strictEqual(result.source_file, tmpFile);
      assert.ok(typeof result.parsed_at === 'string', 'parsed_at should be a string');
      assert.ok(Array.isArray(result.pages), 'pages should be an array');
      assert.strictEqual(result.pages.length, 1, 'one sheet → one page');

      const page = result.pages[0];
      assert.strictEqual(page.page, 1);
      assert.ok(page.text.includes('Alice'), 'text should contain row data');
      assert.ok(page.text.includes('Score'), 'text should contain header');
      assert.ok(Array.isArray(page.tables), 'tables should be an array');
      assert.ok(page.tables.length > 0, 'should have at least one table');
      assert.ok(Array.isArray(page.tables[0]), 'table should be 2-D array');

      assert.strictEqual(result.metadata.page_count, 1);
    } finally {
      const fs = require('fs');
      if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
    }
  });

  it('parses a workbook with multiple sheets', async () => {
    let XLSX;
    try {
      XLSX = require('xlsx');
    } catch (e) {
      return;
    }

    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['A', 'B'], [1, 2]]), 'Sheet1');
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['X', 'Y'], [3, 4]]), 'Sheet2');

    const os = require('os');
    const tmpFile = path.join(os.tmpdir(), `test-multi-${Date.now()}.xlsx`);
    XLSX.writeFile(wb, tmpFile);

    try {
      const result = await office.xlsx.parse(tmpFile);
      assert.strictEqual(result.pages.length, 2, 'two sheets → two pages');
      assert.strictEqual(result.pages[0].sheet_name, 'Sheet1');
      assert.strictEqual(result.pages[1].sheet_name, 'Sheet2');
      assert.strictEqual(result.metadata.page_count, 2);
    } finally {
      const fs = require('fs');
      if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
    }
  });
});

// ---------------------------------------------------------------------------
// image.js graceful OCR fallback
// ---------------------------------------------------------------------------
describe('importers/image.js — graceful OCR fallback', () => {
  it('returns graceful error text when tesseract.js is not installed', async () => {
    // Temporarily override require to simulate missing tesseract.js
    // We test by passing a non-existent file; if tesseract.js IS installed,
    // it will reject. Either way, we verify the output shape.

    // Directly test the graceful path by monkey-patching require
    const Module = require('module');
    const originalLoad = Module._resolveFilename;
    Module._resolveFilename = function (request, ...args) {
      if (request === 'tesseract.js') {
        throw new Error("Cannot find module 'tesseract.js'");
      }
      return originalLoad.call(this, request, ...args);
    };

    // Clear the cached module so our patched require takes effect
    const imageModulePath = require.resolve('../importers/image');
    delete require.cache[imageModulePath];

    try {
      const imageModule = require('../importers/image');
      const result = await imageModule.parse('test.png');

      assert.strictEqual(result.source_file, 'test.png');
      assert.ok(typeof result.parsed_at === 'string');
      assert.strictEqual(result.pages.length, 1);
      assert.ok(
        result.pages[0].text.includes('[OCR not available:'),
        `Expected OCR fallback text, got: ${result.pages[0].text}`
      );
    } finally {
      // Restore original _resolveFilename and re-cache original module
      Module._resolveFilename = originalLoad;
      delete require.cache[imageModulePath];
      require('../importers/image');
    }
  });
});

// ---------------------------------------------------------------------------
// PPTX graceful fallback (adm-zip not installed)
// ---------------------------------------------------------------------------
describe('importers/office.js — pptx graceful fallback', () => {
  it('returns graceful error when adm-zip is not available', async () => {
    const Module = require('module');
    const originalLoad = Module._resolveFilename;
    Module._resolveFilename = function (request, ...args) {
      if (request === 'adm-zip') {
        throw new Error("Cannot find module 'adm-zip'");
      }
      return originalLoad.call(this, request, ...args);
    };

    const officeModulePath = require.resolve('../importers/office');
    delete require.cache[officeModulePath];

    try {
      const officeModule = require('../importers/office');
      const result = await officeModule.pptx.parse('slides.pptx');

      assert.strictEqual(result.source_file, 'slides.pptx');
      assert.strictEqual(result.pages.length, 1);
      assert.ok(
        result.pages[0].text.includes('[PPTX parser not available:'),
        `Expected PPTX fallback text, got: ${result.pages[0].text}`
      );
    } finally {
      Module._resolveFilename = originalLoad;
      delete require.cache[officeModulePath];
      require('../importers/office');
    }
  });
});
