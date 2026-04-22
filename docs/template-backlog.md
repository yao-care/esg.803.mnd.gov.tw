# AKORA 模板待辦項目

## 已完成

- [x] external-fetcher.js 支援 akora-app token（.github/akora.json + BUILD_TOKEN）
- [x] build.js 注入 window.__AKORA__ 到 assistant.html
- [x] form-processor.js 表單送出走 akora-app /submit
- [x] config.example.json 簡化 form_submission（移除 api_endpoint、auth_adapter、auth_config）
- [x] 6 個新 unit tests

## P0：Bug 修正

### 1. ~~Profile 過濾繞過修正~~ ✅ 已修正（df66bc1）

- ~~chunk.js 的 `chunkCollectedResult()` 缺少 `group` 欄位~~
- ~~chunk.js 的 `chunkReportedRecord()` 缺少 `group` 欄位~~
- collected: `group` 預設 `'collected'`，可透過 config.group 自訂
- reported: `group` 從 document_id 前綴萃取（如 FRM-001 → FRM），無前綴時 fallback 為 `'reported'`

## P1：設定機制與文件

### 2. Chunk 門檻可設定

- chunk.js 硬編碼 2000 字元
- config.json 加 `chunk_threshold` 欄位
- 各專案依內容長度自行調整

### 3. 外部來源文件 UI 顯示來源名稱

- assistant.html 搜尋結果不區分本地/外部
- 解析 doc_key 的 `external/{sourceName}/` 前綴
- 搜尋結果加上來源標籤

### 4. CLAUDE.md 更新 akora-app 整合說明

- 說明 .github/akora.json 的用途
- 說明 BUILD_TOKEN 的來源（自動寫入 Actions Secrets）
- 說明 form_submission.repo 必填

### 5. 既有實例遷移指引

- siqc、嘉義稅、mohw 怎麼從舊版升級
- `git fetch template && git merge template/main`
- 需補填 form_submission.repo
- 需安裝 AKORA App 取得 .github/akora.json

## P2：功能增強

### 6. 多語言支援

- build.js 只讀 main.zh
- config.json 加 `locale` 設定
- 支援 main.en 或其他語言路徑

### 7. 搜尋權重設定

- config.json 加 `search_boost` 設定
- 可設定 local vs external 的權重偏好
- 可設定 per-source 權重

### 8. Per-source profile 排除

- `profiles.exclude_types` 目前只能排除 type
- 加 `exclude_sources` 設定，可排除特定外部來源
- 讓不同 profile 看到不同來源的文件

### 9. 表單 schema 入索引

- data/schemas/ 的 form schema 納入搜尋範圍
- 使用者可以搜尋「哪個表單有這個欄位」

### 10. 舊欄位向下相容處理

- form_submission.api_endpoint 在程式碼中仍可讀取（fallback）
- 但 config.example.json 已移除
- 加 console.warn 提示遷移

### 11. Glossary 雙語支援

- _meta/glossary.json 支援 `{ term, zh, en }` 格式
- build 時依 locale 選擇顯示語言

## P3：未來改善

### 12. Chunk 語義邊界偵測

- 超過門檻時不只看 H3，也看段落結尾
- 避免在段落中間切斷

### 13. Chunk overlap

- chunk 之間加 context window（前一個 chunk 的最後 N 字元）
- 減少跨 chunk 資訊遺失

### 14. 表單 field 型別保留

- chunkReportedRecord 保留日期、數值等型別資訊
- 支援結構化查詢
