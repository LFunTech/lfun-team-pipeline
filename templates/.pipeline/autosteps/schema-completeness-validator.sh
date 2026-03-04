#!/bin/bash
# Phase 2.6: Schema Completeness Validator
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/schema-validation-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
TASKS_FILE="$PIPELINE_DIR/artifacts/tasks.json"
CONTRACTS_DIR="$PIPELINE_DIR/artifacts/contracts"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/schema-validation-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$TASKS_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"SchemaCompletenessValidator","timestamp":"$TIMESTAMP","error":"tasks.json not found","overall":"ERROR"}
EOF
  exit 2
fi

EXPECTED_COUNT=$(python3 -c "
import json
try:
  data = json.load(open('$TASKS_FILE'))
  contracts = data.get('contracts', None)
  print(len(contracts) if contracts is not None else -1)
except Exception:
  print(-1)
" 2>/dev/null || echo -1)

ACTUAL_COUNT=0
INVALID_LIST="["
FIRST=true
OVERALL="PASS"

if [ -d "$CONTRACTS_DIR" ]; then
  ACTUAL_COUNT=$(find "$CONTRACTS_DIR" \( -name "*.yaml" -o -name "*.json" \) 2>/dev/null | wc -l)

  while IFS= read -r f; do
    if ! python3 -c "
import yaml, json, sys
try:
  with open('$f') as fh:
    data = yaml.safe_load(fh) if '$f'.endswith('.yaml') else json.load(fh)
  assert str(data.get('openapi', '')).startswith('3.'), 'not openapi 3.x'
  assert 'paths' in data, 'missing paths'
except Exception:
  sys.exit(1)
" 2>/dev/null; then
      if ! $FIRST; then INVALID_LIST+=","; fi
      FIRST=false
      fname=$(basename "$f")
      INVALID_LIST+="\"$fname\""
      OVERALL="FAIL"
    fi
  done < <(find "$CONTRACTS_DIR" \( -name "*.yaml" -o -name "*.json" \) 2>/dev/null)
fi

INVALID_LIST+="]"
# 仅当 tasks.json 明确声明 contracts 列表时才检查数量（-1 表示未声明，跳过）
[ "$EXPECTED_COUNT" -ge 0 ] && [ "$ACTUAL_COUNT" -ne "$EXPECTED_COUNT" ] && OVERALL="FAIL" || true

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "SchemaCompletenessValidator",
  "timestamp": "$TIMESTAMP",
  "expected_contracts": $EXPECTED_COUNT,
  "actual_schemas": $ACTUAL_COUNT,
  "invalid_files": $INVALID_LIST,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
