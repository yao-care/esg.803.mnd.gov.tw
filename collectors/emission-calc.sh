#!/bin/bash
# emission-calc.sh
# 月度排放量估算骨架腳本
# 每月 1 日執行（內建排程守衛）
# 實際計算邏輯待真實數據流程確立後填入

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ---------- 排程守衛：僅在每月 1 日執行 ----------
DAY_OF_MONTH="$(date +%d)"
if [[ "$DAY_OF_MONTH" != "01" ]]; then
  echo "emission-calc.sh: today is not the 1st of the month (day=$DAY_OF_MONTH). Skipping."
  exit 0
fi

MONTH_LABEL="$(date +%Y-%m)"
echo "emission-calc.sh: running monthly emission calculation for $MONTH_LABEL"
echo "NOTE: This is a skeleton script. Actual calculations are marked with TODO."

# ---------- Step 1: 讀取 FRM 月報數據 ----------
# TODO: implement when real data flows in
# 預期來源：knowledge/FRM-*/merge.yaml 中的月報欄位
# 例如：電費度數、油耗量、廢棄物重量等
#
# FRM_DIR="$PROJECT_DIR/knowledge"
# for yaml in "$FRM_DIR"/FRM-*/merge.yaml; do
#   # 解析 fields.electricity_kwh, fields.fuel_liter, etc.
#   :
# done
echo "[Step 1] TODO: 讀取 FRM 月報數據（electricity_kwh, fuel_liter, waste_kg 等）"

# ---------- Step 2: 套用排放係數（來自 GDL-CALC-METHOD）----------
# TODO: implement when real data flows in
# 來源：knowledge/GDL-CALC-METHOD/排放係數計算方法.md
# 台電電力排放係數（kg CO2e/kWh）：每年由 EPA 公告
# 燃油（汽油 2.263 kg CO2e/L；柴油 2.606 kg CO2e/L）
# 廢棄物焚化排放係數：依廢棄物種類
#
# ELEC_FACTOR=0.494   # kg CO2e/kWh（範例值，需依 EPA 最新公告更新）
# FUEL_FACTOR=2.263   # kg CO2e/L（汽油）
# WASTE_FACTOR=0.0    # TODO
echo "[Step 2] TODO: 套用排放係數（GDL-CALC-METHOD 定義）"

# ---------- Step 3: 計算各 Scope 排放量 ----------
# TODO: implement when real data flows in
# Scope 1：直接排放（自有燃油設備）
# Scope 2：間接排放（外購電力）
# Scope 3：其他間接排放（廢棄物、差旅等，視盤查邊界而定）
#
# SCOPE1_KG=$(echo "$FUEL_LITER * $FUEL_FACTOR" | bc)
# SCOPE2_KG=$(echo "$ELEC_KWH * $ELEC_FACTOR" | bc)
echo "[Step 3] TODO: 計算 Scope 1 / Scope 2 / Scope 3 排放量"

# ---------- Step 4: 輸出摘要 ----------
# TODO: implement when real data flows in
# 預期輸出格式（供 QA 或報告引用）：
# {
#   "month": "2026-01",
#   "scope1_tco2e": 0.0,
#   "scope2_tco2e": 0.0,
#   "scope3_tco2e": 0.0,
#   "total_tco2e": 0.0
# }
echo "[Step 4] TODO: 輸出月度排放摘要 JSON"

echo "emission-calc.sh: skeleton run complete for $MONTH_LABEL. No real data processed."
exit 0
