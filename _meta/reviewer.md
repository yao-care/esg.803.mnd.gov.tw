# Meta-Reviewer：閉環完備性判斷標準

## stub 判定（用於 audit.sh RC-2, RC-3, RC-4）

### rule.md stub 判定 (RC-2)
下列任一為 true → stub：
- 含「待補充」「TBD」「TODO」「FIXME」
- 不含任何「【必要】」標記

### writer.md stub 判定 (RC-3)
下列任一為 true → stub：
- 含「待補充」「TBD」「TODO」「FIXME」
- 不含「rule.md」引用（代表未連結到規範來源）

### reviewer.md stub 判定 (RC-4)
下列任一為 true → stub：
- 含「待補充」「TBD」「TODO」「FIXME」
- checkbox 數量 ≤ 10（通用模板的 checkbox 數）
- 不含類型特定關鍵字（見下方）

## 類型特定關鍵字（用於 RC-4 差異化判定）

| 類型 | 必含關鍵字（至少一個）|
|------|---------------------|
| POL  | shall、政策聲明、向下連結 |
| PRO  | RACI、parent_policy、SLA、流程圖 |
| RPT  | 數據年度、總排放量、邊界 |
| STD  | 條款、要求、合規 |
| PLN  | 行動表格、負責人、期限 |
| MTX  | 矩陣、對照、追溯 |
| FRM  | 必填、核准區段、填寫說明 |
| REG  | 表格格式、更新頻率 |
| GDL  | 參考、公式、範例 |

## 引文審查檢查點
1. 文件內引用的其他文件是否存在於 knowledge/ 中
2. merge.yaml 的 references 是否與文件內容中的引用一致
3. 引用的文件編號是否為 knowledge/ 下的已知文件
