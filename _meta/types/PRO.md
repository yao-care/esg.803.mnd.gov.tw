---
type: PRO
meta_version: "1.0"
last_updated: "2026-05-05"
---
# PRO 類型規範 / PRO Type Specification

## 必要章節結構

程序文件（Procedure）須依以下順序呈現 7 個章節，所有章節均為必要：

1. **【必要】目的與範圍** — 說明本程序的目的、適用對象、適用範圍
2. **【必要】相關文件** — 列出上位 POL（parent_policy）文件 document_id、引用的 STD/GDL/FRM
3. **【必要】角色與責任（RACI）** — 使用 RACI 矩陣，涵蓋至少 3 個關鍵程序活動
4. **【必要】程序步驟（含流程圖）** — 逐步說明執行步驟；須包含 Mermaid 流程圖，含決策菱形節點
5. **【必要】監控與量測（含 SLA）** — 所有 SLA 須含具體時限數字（如「Critical 24 小時、High 7 個工作天」）
6. **【必要】紀錄與保存** — 保存期限、儲存位置、銷毀方式
7. **【必要】附錄** — 相關 FRM 表單、操作說明

## 語氣與用詞規範

- 步驟說明使用祈使句（如「填寫」「核對」「提交」）
- RACI 矩陣中：R（Responsible）、A（Accountable）、C（Consulted）、I（Informed）
- SLA 數字須明確（禁止「盡快」「儘速」等模糊用詞）

## 必要元素

- **【必要】parent_policy 引用**：標示為 `parent_policy`，格式 POL-NNN
- **【必要】RACI 矩陣**：Markdown 表格，涵蓋至少 3 個關鍵程序活動
- **【必要】SLA 數字（含時限）**：具體時限數字
- **【必要】Mermaid 流程圖**：含決策菱形節點

## 交叉引用規則

- **必須向上引用**上位 POL（parent_policy）
- **必須向下連結**相關 FRM 表單（於附錄章節列出）
- 可引用 STD、GDL 作為參考規範

## 審查重點

- **PR1 parent_policy**：相關文件章節明確標示 parent_policy 及其 document_id
- **PR2 RACI**：RACI 矩陣格式正確，涵蓋至少 3 個活動
- **PR3 SLA 數字**：監控與量測章節含具體時限數字
- **PR4 流程圖**：Mermaid 流程圖含決策菱形節點

## 類型特定關鍵字

`RACI`、`parent_policy`、`SLA`、`流程圖`
