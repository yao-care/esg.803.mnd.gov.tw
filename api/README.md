# AKORA Form Submission API

## 概述

輕量 API，接收表單提交、驗證後寫入 git repo。

## 部署

本目錄提供 OpenAPI spec (`openapi.yaml`) 和平台無關的參考實作 (`reference/handler.js`)。
你可以選擇任何平台部署：Cloudflare Workers、Vercel Edge Functions、AWS Lambda 等。

## 環境變數

| 變數 | 必填 | 說明 |
|---|---|---|
| `API_KEY` | 是 | 實例的 API key |
| `GITHUB_TOKEN` 或 `GITLAB_TOKEN` | 是 | Git 平台 access token |
| `REPO` | 是 | 目標 repo (owner/name) |
| `GITLAB_ENDPOINT` | 否 | 有值 → GitLab，無值 → GitHub |
| `SCHEMAS_PATH` | 否 | JSON Schema 檔案路徑或 URL |

## 參考實作

`reference/handler.js` 提供核心邏輯：
- `handleSubmit(request, env)` — 主要處理函式
- 驗證 API key、JSON Schema、冪等性
- 呼叫 GitHub/GitLab API commit 或開 PR

你需要將此 handler 包裝在你選擇的平台的 HTTP 框架中。
