#!/bin/bash
KUBECOST_URL="${KUBECOST_URL:-http://localhost:9090}"
WINDOW="${WINDOW:-7d}"
AGGREGATE="${AGGREGATE:-namespace}"
OUTPUT_FILE="${OUTPUT_FILE:-team_costs.csv}"
SCRIPT_DIR="$(dirname "$0")"

echo "[INFO] Fetching cost report for window=${WINDOW} aggregate=${AGGREGATE} from ${KUBECOST_URL}"
RAW=$(curl -sf --max-time 60 "${KUBECOST_URL}/model/allocation?window=${WINDOW}&aggregate=${AGGREGATE}&accumulate=false")

if [ -z "$RAW" ]; then
  echo "[ERROR] No response from Kubecost API"
  exit 1
fi

echo "team,date,cpu_cost_usd,memory_cost_usd,pv_cost_usd,network_cost_usd,lb_cost_usd,shared_cost_usd,total_cost_usd,cpu_efficiency_pct,memory_efficiency_pct" > "${OUTPUT_FILE}"
echo "$RAW" | python3 "${SCRIPT_DIR}/report_helper.py" csv >> "${OUTPUT_FILE}"

echo "[INFO] Report saved to ${OUTPUT_FILE}"
echo ""
echo "========== COST SUMMARY (${WINDOW}) =========="
echo "$RAW" | python3 "${SCRIPT_DIR}/report_helper.py" summary
echo "============================================"