// scripts/lib/core/__tests__/external-fetcher.test.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { matchGlob, buildExternalDocKey, resolveCloneUrl, resolveCloneUrlWithToken, resolveAkoraConfig, findDocumentDirs } = require('../external-fetcher');

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

  describe('resolveCloneUrlWithToken', () => {
    it('builds GitHub URL with x-access-token prefix', () => {
      const url = resolveCloneUrlWithToken({ repo: 'owner/repo' }, 'ghs_abc123');
      assert.strictEqual(url, 'https://x-access-token:ghs_abc123@github.com/owner/repo.git');
    });

    it('builds GitLab URL with oauth2 prefix', () => {
      const url = resolveCloneUrlWithToken({
        repo: 'group/project',
        gitlab_endpoint: 'https://gitlab.example.com',
      }, 'glpat-xyz');
      assert.strictEqual(url, 'https://oauth2:glpat-xyz@gitlab.example.com/group/project.git');
    });

    it('falls back to resolveCloneUrl when token is empty', () => {
      const url = resolveCloneUrlWithToken({ repo: 'owner/repo' }, '');
      assert.strictEqual(url, 'https://github.com/owner/repo.git');
    });
  });

  describe('resolveAkoraConfig', () => {
    const tmpDir = path.join(require('os').tmpdir(), `akora-test-config-${Date.now()}`);

    it('returns null when no env vars and no config file', () => {
      fs.mkdirSync(tmpDir, { recursive: true });
      // Ensure env vars are not set
      const saved = {
        AKORA_INSTALLATION_ID: process.env.AKORA_INSTALLATION_ID,
        AKORA_BUILD_TOKEN: process.env.AKORA_BUILD_TOKEN,
      };
      delete process.env.AKORA_INSTALLATION_ID;
      delete process.env.AKORA_BUILD_TOKEN;

      const result = resolveAkoraConfig(tmpDir);
      assert.strictEqual(result, null);

      // Restore
      if (saved.AKORA_INSTALLATION_ID) process.env.AKORA_INSTALLATION_ID = saved.AKORA_INSTALLATION_ID;
      if (saved.AKORA_BUILD_TOKEN) process.env.AKORA_BUILD_TOKEN = saved.AKORA_BUILD_TOKEN;
      fs.rmSync(tmpDir, { recursive: true, force: true });
    });

    it('returns config from env vars (priority 1)', () => {
      const saved = {
        AKORA_INSTALLATION_ID: process.env.AKORA_INSTALLATION_ID,
        AKORA_BUILD_TOKEN: process.env.AKORA_BUILD_TOKEN,
        AKORA_ENDPOINT: process.env.AKORA_ENDPOINT,
        AKORA_PLATFORM: process.env.AKORA_PLATFORM,
      };
      process.env.AKORA_INSTALLATION_ID = '12345';
      process.env.AKORA_BUILD_TOKEN = 'tok_abc';
      process.env.AKORA_ENDPOINT = 'https://custom.example.com';
      process.env.AKORA_PLATFORM = 'gitlab';

      const result = resolveAkoraConfig('/nonexistent');
      assert.deepStrictEqual(result, {
        installation_id: '12345',
        build_token: 'tok_abc',
        endpoint: 'https://custom.example.com',
        platform: 'gitlab',
      });

      // Restore
      for (const [k, v] of Object.entries(saved)) {
        if (v === undefined) delete process.env[k]; else process.env[k] = v;
      }
    });

    it('returns config from .github/akora.json + env build token (priority 2)', () => {
      fs.mkdirSync(path.join(tmpDir, '.github'), { recursive: true });
      fs.writeFileSync(path.join(tmpDir, '.github', 'akora.json'), JSON.stringify({
        installation_id: 999,
        endpoint: 'https://akora.test.com',
        platform: 'github',
      }));

      const saved = {
        AKORA_INSTALLATION_ID: process.env.AKORA_INSTALLATION_ID,
        AKORA_BUILD_TOKEN: process.env.AKORA_BUILD_TOKEN,
      };
      delete process.env.AKORA_INSTALLATION_ID;
      process.env.AKORA_BUILD_TOKEN = 'tok_xyz';

      const result = resolveAkoraConfig(tmpDir);
      assert.deepStrictEqual(result, {
        installation_id: '999',
        build_token: 'tok_xyz',
        endpoint: 'https://akora.test.com',
        platform: 'github',
      });

      // Restore
      for (const [k, v] of Object.entries(saved)) {
        if (v === undefined) delete process.env[k]; else process.env[k] = v;
      }
      fs.rmSync(tmpDir, { recursive: true, force: true });
    });
  });
});
