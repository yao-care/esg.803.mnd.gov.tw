# Meta-Writer：AI Agent 內容產生指引

## 讀取順序
1. `_meta/rule.md` — 了解合格標準與標記慣例
2. `_meta/types/{TYPE}.md` — 取得類型規範模板
3. `_meta/overrides/{DOC_ID}.md` — 取得特殊規範（若存在）
4. 目標資料夾/merge.yaml — 取得元資料

## 產出流程
### Step 1: 產出 rule.md
- 以 types/{TYPE}.md 為基礎
- 合併 overrides/{DOC_ID}.md 的額外規範（若存在）
- 所有必要條目使用【必要】標記

### Step 2: 從 rule.md 衍生 writer.md
- 將 rule.md「必要章節結構」轉化為寫作框架
- 從 types/{TYPE}.md 的「語氣與用詞規範」提取寫作風格指引

### Step 3: 從 rule.md 鏡像產出 reviewer.md
- 結構性檢查區段：繼承全域規則
- 內容檢查區段：rule.md 每個【必要】→ 一個 checkbox
- 類型檢查區段：types/{TYPE}.md 的審查重點

## 禁止事項
- 不得產出含「待補充」「TBD」「TODO」的內容
- 不得產出與其他資料夾完全相同的 reviewer.md

## ESG 寫作風格
- 術語遵循 ISO 14064-1:2018 中文版用語
- 語言：繁體中文（zh-TW）
- 數值：使用千位分隔（如 3,284.073 tCO2e）
- 年度：以民國年標註報告期間，西元年用於 YAML 日期欄位
- 排放數據：保留至小數點後四位（tCO2e）

## 引文撰寫指引
### 文件內交叉引用
在文件內容中引用其他文件時，直接使用文件編號：
- 「依 PRO-GHG-INV 辦理」
- 「填寫 FRM-DATA-FUEL 油料月報表」

### 引用的文件必須登錄
文件中引用了其他文件時，被引用的文件應列入 merge.yaml 的 references 欄位。
