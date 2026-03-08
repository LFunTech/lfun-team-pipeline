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

# 收集结果到数组（格式：schema|tool|result|detail）
RESULTS=()
OVERALL="PASS"

add_result() {
  RESULTS+=("$1|$2|$3|$4")
  [ "$3" = "FAIL" ] && OVERALL="FAIL" || true
}

if ! curl -sf "$SERVICE_BASE_URL/health" > /dev/null 2>&1 && \
   ! curl -sf "$SERVICE_BASE_URL/" > /dev/null 2>&1; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"ContractComplianceChecker","timestamp":"$TIMESTAMP","error":"service not reachable at $SERVICE_BASE_URL","failure_type":"infrastructure_failure","overall":"ERROR"}
EOF
  exit 2
fi

# 检测 schemathesis，缺失时尝试自动安装
if ! command -v schemathesis &>/dev/null; then
  echo "[ContractCompliance] schemathesis 未找到，尝试自动安装..." >&2
  pip install schemathesis -q 2>/dev/null || true
fi

# 若仍不可用，整体 FAIL（不允许跳过合约验证）
if ! command -v schemathesis &>/dev/null; then
  for schema_file in "$CONTRACTS_DIR"/*.yaml "$CONTRACTS_DIR"/*.json; do
    [ -f "$schema_file" ] || continue
    add_result "$(basename "$schema_file")" "none" "FAIL" \
      "schemathesis 未安装，无法进行合约验证。请执行: pip install schemathesis"
  done

  TIMESTAMP="$TIMESTAMP" SERVICE_BASE_URL="$SERVICE_BASE_URL" \
  OVERALL="$OVERALL" OUTPUT_FILE="$OUTPUT_FILE" python3 -c "
import json, os, sys
lines = [l for l in sys.stdin.read().strip().splitlines() if l]
results = []
for line in lines:
    parts = line.split('|', 3)
    if len(parts) == 4:
        results.append({'schema': parts[0], 'tool': parts[1], 'result': parts[2], 'detail': parts[3]})
result = {
    'autostep': 'ContractComplianceChecker',
    'timestamp': os.environ['TIMESTAMP'],
    'service_base_url': os.environ['SERVICE_BASE_URL'],
    'error': 'schemathesis 未安装，合约验证无法执行',
    'results': results,
    'overall': os.environ['OVERALL']
}
with open(os.environ['OUTPUT_FILE'], 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
" <<< "$(printf '%s\n' "${RESULTS[@]}")"
  exit 1
fi

for schema_file in "$CONTRACTS_DIR"/*.yaml "$CONTRACTS_DIR"/*.json; do
  [ -f "$schema_file" ] || continue
  fname=$(basename "$schema_file")

  set +e
  # Bug #9 fix: schemathesis 4.x uses --url instead of --base-url; --checks all → -c all
  if schemathesis run --help 2>&1 | grep -q '\-\-url'; then
    OUTPUT=$(schemathesis run "$schema_file" --url "$SERVICE_BASE_URL" --phases examples -w 1 2>&1)
  else
    OUTPUT=$(schemathesis run "$schema_file" --base-url "$SERVICE_BASE_URL" --checks all 2>&1)
  fi
  EXIT_CODE=$?
  set -e
  if [ "$EXIT_CODE" -eq 0 ]; then
    add_result "$fname" "schemathesis" "PASS" "所有契约测试通过"
  else
    DETAIL=$(echo "$OUTPUT" | tail -3 | tr '\n' ' ')
    add_result "$fname" "schemathesis" "FAIL" "$DETAIL"
  fi
done

# 使用 python3 生成 JSON（避免手动拼接导致的转义问题）
TIMESTAMP="$TIMESTAMP" SERVICE_BASE_URL="$SERVICE_BASE_URL" \
OVERALL="$OVERALL" OUTPUT_FILE="$OUTPUT_FILE" python3 -c "
import json, os, sys
lines = [l for l in sys.stdin.read().strip().splitlines() if l]
results = []
for line in lines:
    parts = line.split('|', 3)
    if len(parts) == 4:
        results.append({'schema': parts[0], 'tool': parts[1], 'result': parts[2], 'detail': parts[3]})
result = {
    'autostep': 'ContractComplianceChecker',
    'timestamp': os.environ['TIMESTAMP'],
    'service_base_url': os.environ['SERVICE_BASE_URL'],
    'results': results,
    'overall': os.environ['OVERALL']
}
with open(os.environ['OUTPUT_FILE'], 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
" <<< "$(printf '%s\n' "${RESULTS[@]}")"

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
