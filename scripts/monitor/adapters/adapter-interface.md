# Adapter Interface

每個 adapter 是一個 shell 腳本，遵循以下介面：

## 輸入
- 環境變數 `ADAPTER_CONFIG`：JSON 格式的設定（來自 config.json）
- 環境變數 `OUTPUT_DIR`：輸出目錄

## 輸出
- `${OUTPUT_DIR}/${adapter_name}-events.json`：標準事件格式

## 標準事件格式

```json
{
  "adapter": "adapter-name",
  "collected_at": "2026-04-18T10:00:00Z",
  "events": [
    {
      "id": "...",
      "severity": "high",
      "source": "...",
      "summary": "...",
      "timestamp": "...",
      "raw": {}
    }
  ]
}
```

## 實作規範

每個 adapter 腳本必須：

1. 接受兩個位置參數：`<config_json> <output_dir>`
2. 輸出結果檔至 `<output_dir>/<adapter_name>-result.json`
3. 結果 JSON 必須包含：
   - `source`：adapter 名稱（與腳本檔名相同）
   - `mode`：`"continuous"` 或 `"polling"`
   - `status`：`"completed"` / `"error"` / `"skipped"`
   - `timestamp`：ISO 8601 UTC
   - `last_event_at`：最後一筆事件時間（供 heartbeat 使用）
   - `summary`：含 `critical`, `high`, `medium`, `low`, `total` 欄位
   - `findings`：事件陣列（最多 20 筆）

## 可用 Adapters

| Adapter | 說明 | 設定欄位 |
|---------|------|---------|
| `aws-guardduty` | AWS GuardDuty 威脅偵測 | `region`, `credentials_env`, `lookback_hours` |
| `wazuh` | Wazuh SIEM 告警 | `api_url`, `credentials_env`, `lookback_hours` |
| `syslog-file` | 本地 syslog 檔案分析 | `log_path`, `lookback_hours` |

## 新增 Adapter

1. 在 `adapters/` 建立 `<type>.sh`
2. 實作上述介面規範
3. `chmod +x adapters/<type>.sh`
4. 在 `config.json` 的 `monitor.adapters` 加入設定
