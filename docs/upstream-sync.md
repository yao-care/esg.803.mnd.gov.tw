# 模板引擎同步指南

AKORA 採用**共用引擎 + 獨立內容**架構。Fork 出的實例專案可隨時合併模板的引擎更新。

## 架構分層

| 層 | 路徑 | 來源 | 同步方式 |
|---|------|------|---------|
| 引擎層 | `scripts/`、`templates/`、`tests/`、`.github/workflows/` | 模板持續演進 | `git merge template/main` |
| 領域層 | `_meta/`、`config.json`、`qa-questions.json` | 嚮導一次性產出 | 不同步（實例獨有） |
| 內容層 | `knowledge/`、`data/` | 用戶自行維護 | 不同步（實例獨有） |

## 初始設定

嚮導（CLAUDE.md Step 5）會自動執行：

```bash
git remote add template https://github.com/weiqi-kids/akora.git
```

若手動 fork，自行執行上述指令。

## 同步流程

### 1. 檢查是否有更新

```bash
git fetch template
git log --oneline HEAD..template/main -- scripts/ templates/ tests/ .github/
```

只看引擎層的變更。若無輸出，表示已是最新。

### 2. 合併更新

```bash
git merge template/main
```

### 3. 處理衝突

正常會衝突的檔案：

| 檔案 | 處理方式 |
|------|---------|
| `config.json` | **保留實例版本**（`git checkout --ours config.json`） |
| `config.example.json` | **接受模板版本**（`git checkout --theirs config.example.json`），然後對照更新自己的 `config.json` |
| `CLAUDE.md` | **接受模板版本**，嚮導段落更新不影響正常模式 |
| `package.json` | 手動合併（保留實例的 name/version，接受模板的 scripts/dependencies） |
| `knowledge/`、`_meta/` | **保留實例版本**（模板的骨架不會覆蓋實際內容） |

不會衝突的檔案（直接接受模板）：

- `scripts/lib/core/*.js` — 引擎核心
- `templates/*.html` — HTML 模板
- `tests/` — 測試
- `.github/workflows/*.yml` — CI 流程

### 4. 驗證

```bash
npm test
npm run build:assistant
```

## Session Start 自動提醒

CLAUDE.md 的 Session Start Checklist 會自動：

1. 偵測 `template` remote 是否存在
2. `git fetch template` 檢查引擎層更新
3. 若有更新，在報告中提醒操作者

操作者不需主動記得檢查。

## 常見問題

**Q: 模板更新了 config.example.json，我的 config.json 要怎麼跟上？**

合併後比對差異：
```bash
diff config.json config.example.json
```
將新增的欄位手動加入 config.json（填入實例的實際值）。

**Q: 我修改了 scripts/ 裡的檔案，會衝突嗎？**

會。實例不應修改引擎層檔案。如果有實例特有的需求，應在模板中以 config 驅動的方式實現，然後回饋到模板。

**Q: 可以只同步部分更新嗎？**

不建議。引擎層的模組有依賴關係（例如 build.js 依賴 form-processor.js），cherry-pick 容易遺漏依賴。
