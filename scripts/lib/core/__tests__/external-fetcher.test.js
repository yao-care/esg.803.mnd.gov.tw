// scripts/lib/core/__tests__/external-fetcher.test.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const { matchGlob, buildExternalDocKey, resolveCloneUrl } = require('../external-fetcher');

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
