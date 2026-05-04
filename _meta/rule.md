# Meta-Rule：閉環檔案品質規範

## 標記慣例
- 必要條目使用 **【必要】** 前綴
- 建議條目使用 【建議】 前綴
- reviewer.md 的 checkbox 必須覆蓋所有【必要】條目

## rule.md 的合格標準
- **【必要】** 包含「必要章節結構」區段，列出該文件必須有的章節（有序）
- **【必要】** 包含「語氣與用詞規範」區段
- **【必要】** 包含「必要元素」區段（如 RACI、SLA、流程圖等，依類型而異）
- **【必要】** 包含「交叉引用規則」區段
- **【必要】** 包含「審查重點」區段（對應 reviewer.md 的檢查碼）
- **【必要】** 每個必要條目使用【必要】標記
- **【必要】** 不含「待補充」「TBD」「TODO」等佔位符

## 閉環不變量（Invariants）
1. rule.md【必要】數 ≤ reviewer.md checkbox 數
2. writer.md 章節結構 ⊇ rule.md 必要章節結構
3. 三份檔案不含「待補充」「TBD」「TODO」
4. 三份檔案的 document_id 與 merge.yaml 一致

## ESG 領域術語規範
- 排放量（emissions）：非「碳排放」
- 類別 1（Category 1）：直接排放；非「範疇一」
- 類別 2（Category 2）：間接排放（輸入能源）；非「範疇二」
- 組織邊界（organizational boundary）：非「盤查範圍」
- 盤查（inventory）：非「碳盤」
- 查證（verification）：非「驗證」
- 排放係數（emission factor）：非「碳排放因子」
- tCO2e：公噸二氧化碳當量

## 交叉引用規則
- POL 必須向下連結至少一份 PRO
- PRO 必須引用 parent_policy（POL document_id）
- PRO 必須連結相關 FRM
- RPT 必須連結相關 MTX（如 RPT-GHG → MTX-EMISSION）
- MTX 必須引用資料來源文件

## 章節標題格式

### 儲存格式（Markdown）
章節標題使用數字編號 + Markdown heading：
## 1. 目的
## 2. 適用範圍
子章節使用「X.Y」格式：
### 4.1 申請階段

### 輸出格式（HTML）
build 時自動將數字編號轉換為中文編號（由 build.js 處理）。Markdown 原始檔一律使用數字格式。

### 禁止
- 禁止在 Markdown 中直接使用「一、」「二、」中文編號作為 heading
- 禁止混用數字和中文編號

## 引文格式
### AI 回答格式
[來源:文件編號#章節]
- 冒號使用半形 :（U+003A）
- 文件編號使用實際編號（如 RPT-GHG-2025、PRO-GHG-INV）
- 章節使用數字格式（如 #2. 盤查邊界）

### 防護機制
assistant.html 的 autoLinkDocKeys 機制會自動偵測回答中出現的所有已知文件編號並建立連結。
