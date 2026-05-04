# 既有實例遷移指引

適用於在 AKORA App 推出前已建立的實例（siqc、嘉義稅、mohw 等）。

## 步驟

### 1. 拉取模板最新版

```bash
git fetch template
git merge template/main
```

解決衝突後 commit。

### 2. 安裝 AKORA App

1. 到 https://github.com/apps/akora-app/installations/new
2. 選你的 org → 選 All repositories 或指定 repos
3. 授權後進入 setup 頁面
4. 選擇你的 AKORA repo → 點 Create PR
5. PR 會自動新增 `.github/akora.json`，`AKORA_BUILD_TOKEN` 自動寫入 Actions Secrets
6. Merge PR

### 3. 補填 form_submission.repo

在 config.json 的 `form_submission` 加上 `repo`：

```json
"form_submission": {
  "repo": "your-org/your-repo-name"
}
```

如果你的 config.json 還有舊欄位（`api_endpoint`、`auth_adapter`、`auth_config`），可以移除。保留也不影響運作，但會在 console 看到 deprecation warning。

### 4. 重新 build

```bash
npm run build:assistant
```

build 完成後：
- 表單送出自動走 akora.weiqi.kids/submit
- AI 對話自動走 akora.weiqi.kids/ask（需先設定 Anthropic API key）

### 5. 設定 Anthropic API key（選填）

兩種方式：

**方式 A：透過 AKORA App 設定**
```bash
curl -X PUT https://akora.weiqi.kids/installation/api-key \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {你的 AKORA_BUILD_TOKEN}" \
  -d '{"installation_id": "{你的 installation_id}", "api_key": "sk-ant-..."}'
```

**方式 B：使用者自備 key**
使用者在 assistant.html 介面中自行輸入 API key，請求直連 Anthropic，不經過 AKORA App。

### 注意：Chunk Overlap 導致 Cache 失效

模板更新加入了 chunk overlap（預設 200 字元），會改變所有 chunk 的內容 hash。
首次執行 `npm run qa-report -- --refresh-dynamic` 會重新呼叫 API 產生所有動態題，
這是一次性的 API 費用。之後的 cache 會正常運作。

## 確認清單

- [ ] `git merge template/main` 完成
- [ ] `.github/akora.json` 存在（透過 AKORA App PR）
- [ ] `AKORA_BUILD_TOKEN` 在 Actions Secrets 中
- [ ] `config.json` 的 `form_submission.repo` 已填
- [ ] `npm run build:assistant` 成功
- [ ] 表單送出測試通過
