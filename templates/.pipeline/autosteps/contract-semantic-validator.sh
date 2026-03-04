#!/bin/bash
# Phase 2.7: Contract Semantic Validator
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/contract-semantic-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
TASKS_FILE="$PIPELINE_DIR/artifacts/tasks.json"
CONTRACTS_DIR="$PIPELINE_DIR/artifacts/contracts"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/contract-semantic-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -d "$CONTRACTS_DIR" ] || [ ! -f "$TASKS_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"ContractSemanticValidator","timestamp":"$TIMESTAMP","error":"missing inputs","overall":"ERROR"}
EOF
  exit 2
fi

OVERALL="PASS"
ERRORS_LIST="["
FIRST=true

check_error() {
  if ! $FIRST; then ERRORS_LIST+=","; fi
  FIRST=false
  ERRORS_LIST+="{\"file\":\"$1\",\"rule\":\"$2\",\"message\":\"$3\"}"
  OVERALL="FAIL"
}

for schema_file in "$CONTRACTS_DIR"/*.yaml "$CONTRACTS_DIR"/*.json; do
  [ -f "$schema_file" ] || continue
  fname=$(basename "$schema_file")

  if ! python3 -c "
import yaml, json, sys
with open('$schema_file') as f:
  data = yaml.safe_load(f) if '$schema_file'.endswith('.yaml') else json.load(f)
for path, methods in data.get('paths', {}).items():
  if 'get' in methods and 'requestBody' in methods['get']:
    sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    check_error "$fname" "no-get-requestbody" "GET endpoint must not have requestBody"
  fi

  if ! python3 -c "
import yaml, json, sys
with open('$schema_file') as f:
  data = yaml.safe_load(f) if '$schema_file'.endswith('.yaml') else json.load(f)
for path, methods in data.get('paths', {}).items():
  for method, op in methods.items():
    if isinstance(op, dict) and 'operationId' not in op:
      sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    check_error "$fname" "operation-id-required" "every operation must have operationId"
  fi
done

ERRORS_LIST+="]"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "ContractSemanticValidator",
  "timestamp": "$TIMESTAMP",
  "errors": $ERRORS_LIST,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
