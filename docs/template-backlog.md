# AKORA 模板待辦項目

## 已完成

### P0
- [x] #1 Profile 過濾繞過修正（df66bc1）

### P1
- [x] #2 Chunk 門檻可設定（9ddb7b9）
- [x] #3 外部來源 UI 標籤（d7d78b8）
- [x] #4 CLAUDE.md 更新（5f2ccdd）
- [x] #5 遷移指引（5f2ccdd）

### P2
- [x] #6 多語言支援
- [x] #7 搜尋權重設定
- [x] #8 Per-source profile 排除
- [x] #9 表單 schema 入索引
- [x] #10 舊欄位向下相容
- [x] #11 Glossary 雙語

### P3
- [x] #12 Chunk 語義邊界（42d6fcc）
- [x] #13 Chunk overlap（0cedf23）
- [x] #14 表單 field 型別保留（7a31d0c）

### 額外修正（來自 siqc 整合回饋）
- [x] shell-config.sh 加 count_matches() + safe_int()
- [x] renderedDocs 碰撞偵測
- [x] 遷移指引加 cache 失效提醒
- [x] CI workflow 範例
- [x] config.example.json 完整性確認

## 待做

### GitLab adapter（akora-app Phase 2）
- [ ] GitLab OAuth Application adapter
- [ ] /setup GitLab flow
- [ ] /token + /submit GitLab 支援
- [ ] GitLab polling for revoke detection
