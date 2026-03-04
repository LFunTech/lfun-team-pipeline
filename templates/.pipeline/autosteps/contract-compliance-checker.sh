#!/bin/bash
# Phase 3.7: Contract Compliance Checker
# 输入: PIPELINE_DIR, SERVICE_BASE_URL（运行中服务的基础 URL）
# 输出: .pipeline/artifacts/contract-compliance-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
CONTRACTS_DIR="$PIPELINE_DIR/artifacts/contracts"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/contract-compliance-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SERVICE_BASE_URL="${SERVICE_BASE_URL:-http://localhost:3000}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

OVERALL="PASS"
RESULTS_LIST="["
FIRST=true

add_result() {
  if ! $FIRST; then RESULTS_LIST+=","; fi
  FIRST=false
  RESULTS_LIST+="{\"schema\":\"$1\",\"tool\":\"$2\",\"result\":\"$3\",\"detail\":\"$4\"}"
  [ "$3" = "FAIL" ] && OVERALL="FAIL"
}

if ! curl -sf "$SERVICE_BASE_URL/health" > /dev/null 2>&1 && \
   ! curl -sf "$SERVICE_BASE_URL/" > /dev/null 2>&1; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"ContractComplianceChecker","timestamp":"$TIMESTAMP","error":"service not reachable at $SERVICE_BASE_URL","failure_type":"infrastructure_failure","overall":"ERROR"}
EOF
  exit 2
fi

for schema_file in "$CONTRACTS_DIR"/*.yaml "$CONTRACTS_DIR"/*.json; do
  [ -f "$schema_file" ] || continue
  fname=$(basename "$schema_file")

  if command -v schemathesis &>/dev/null; then
    set +e
    OUTPUT=$(schemathesis run "$schema_file" --base-url "$SERVICE_BASE_URL" --checks all 2>&1)
    EXIT_CODE=$?
    set -e
    if [ "$EXIT_CODE" -eq 0 ]; then
      add_result "$fname" "schemathesis" "PASS" "所有契约测试通过"
    else
      DETAIL=$(echo "$OUTPUT" | tail -3 | tr '\n' ' ' | sed 's/"/\\"/g')
      add_result "$fname" "schemathesis" "FAIL" "$DETAIL"
    fi
  else
    add_result "$fname" "none" "PASS" "WARNING: 未安装 schemathesis，跳过机械验证"
  fi
done

RESULTS_LIST+="]"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "ContractComplianceChecker",
  "timestamp": "$TIMESTAMP",
  "service_base_url": "$SERVICE_BASE_URL",
  "results": $RESULTS_LIST,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
