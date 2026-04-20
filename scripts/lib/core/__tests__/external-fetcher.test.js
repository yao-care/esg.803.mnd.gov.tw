// scripts/lib/core/__tests__/external-fetcher.test.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { matchGlob, buildExternalDocKey, resolveCloneUrl, findDocumentDirs } = require('../external-fetcher');

describe('external-fetcher helpers', () => {
  describe('matchGlob', () => {
    it('matches wildcard pattern', () => {
      assert.ok(matchGlob('POL-001', 'POL-*'));
    });

    it('does not match non-matching pattern', () => {
      assert.ok(!matchGlob('WKI-001', 'POL-*'));
    });

    it('matches exact name', () => {
      assert.ok(matchGlob('FRM-001', 'FRM-001'));
    });

    it('matches multiple wildcards', () => {
      assert.ok(matchGlob('PRO-003-附件', 'PRO-*-*'));
    });
  });

  describe('buildExternalDocKey', () => {
    it('builds namespaced doc_key', () => {
      assert.strictEqual(buildExternalDocKey('siqc', 'POL-001'), 'external/siqc/POL-001');
    });
  });

  describe('findDocumentDirs', () => {
    const tmpBase = path.join(require('os').tmpdir(), `akora-test-finddocs-${Date.now()}`);

    it('finds merge.yaml in nested directories', () => {
      // Create nested structure: base/a/merge.yaml, base/b/c/merge.yaml, base/d/ (no yaml)
      fs.mkdirSync(path.join(tmpBase, 'a'), { recursive: true });
      fs.mkdirSync(path.join(tmpBase, 'b', 'c'), { recursive: true });
      fs.mkdirSync(path.join(tmpBase, 'd'), { recursive: true });
      fs.writeFileSync(path.join(tmpBase, 'a', 'merge.yaml'), 'document_id: A');
      fs.writeFileSync(path.join(tmpBase, 'b', 'c', 'merge.yaml'), 'document_id: BC');

      const dirs = findDocumentDirs(tmpBase, 'merge.yaml');
      assert.strictEqual(dirs.length, 2);
      assert.ok(dirs.some(d => d.endsWith('/a')));
      assert.ok(dirs.some(d => d.endsWith('/c')));

      fs.rmSync(tmpBase, { recursive: true, force: true });
    });

    it('skips dot and underscore directories', () => {
      fs.mkdirSync(path.join(tmpBase, '.hidden'), { recursive: true });
      fs.mkdirSync(path.join(tmpBase, '_meta'), { recursive: true });
      fs.mkdirSync(path.join(tmpBase, 'valid'), { recursive: true });
      fs.writeFileSync(path.join(tmpBase, '.hidden', 'merge.yaml'), 'id: 1');
      fs.writeFileSync(path.join(tmpBase, '_meta', 'merge.yaml'), 'id: 2');
      fs.writeFileSync(path.join(tmpBase, 'valid', 'merge.yaml'), 'id: 3');

      const dirs = findDocumentDirs(tmpBase, 'merge.yaml');
      assert.strictEqual(dirs.length, 1);
      assert.ok(dirs[0].endsWith('/valid'));

      fs.rmSync(tmpBase, { recursive: true, force: true });
    });

    it('returns empty array for non-existent path', () => {
      const dirs = findDocumentDirs('/tmp/non-existent-akora-path', 'merge.yaml');
      assert.strictEqual(dirs.length, 0);
    });
  });

  describe('resolveCloneUrl', () => {
    it('builds GitHub URL without token', () => {
      const url = resolveCloneUrl({ repo: 'owner/repo' }, {});
      assert.strictEqual(url, 'https://github.com/owner/repo.git');
    });

    it('builds GitHub URL with token', () => {
      const url = resolveCloneUrl({ repo: 'owner/repo', token_env: 'MY_TOKEN' }, { MY_TOKEN: 'abc123' });
      assert.strictEqual(url, 'https://abc123@github.com/owner/repo.git');
    });

    it('builds GitLab URL', () => {
      const url = resolveCloneUrl({
        repo: 'group/project',
        gitlab_endpoint: 'https://gitlab.example.com',
        token_env: 'GL_TOKEN',
      }, { GL_TOKEN: 'xyz' });
      assert.strictEqual(url, 'https://oauth2:xyz@gitlab.example.com/group/project.git');
    });
  });
});
