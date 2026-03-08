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

CONTRACTS_DIR="$CONTRACTS_DIR" TIMESTAMP="$TIMESTAMP" OUTPUT_FILE="$OUTPUT_FILE" python3 << 'PYEOF'
import json, os, sys, glob

contracts_dir = os.environ['CONTRACTS_DIR']
timestamp = os.environ['TIMESTAMP']
output_file = os.environ['OUTPUT_FILE']

errors = []
overall = 'PASS'

try:
    import yaml
except ImportError:
    yaml = None

for pattern in [f'{contracts_dir}/*.yaml', f'{contracts_dir}/*.json']:
    for schema_file in sorted(glob.glob(pattern)):
        fname = os.path.basename(schema_file)
        try:
            with open(schema_file) as f:
                if schema_file.endswith('.yaml'):
                    if yaml is None:
                        errors.append({'file': fname, 'rule': 'yaml-missing', 'message': 'pyyaml not installed'})
                        overall = 'FAIL'
                        continue
                    data = yaml.safe_load(f)
                else:
                    data = json.load(f)
        except Exception as e:
            errors.append({'file': fname, 'rule': 'parse-error', 'message': str(e)})
            overall = 'FAIL'
            continue

        for path, methods in (data.get('paths') or {}).items():
            if 'get' in methods and 'requestBody' in methods.get('get', {}):
                errors.append({'file': fname, 'rule': 'no-get-requestbody', 'message': 'GET endpoint must not have requestBody'})
                overall = 'FAIL'
            for method, op in methods.items():
                if isinstance(op, dict) and 'operationId' not in op:
                    errors.append({'file': fname, 'rule': 'operation-id-required', 'message': 'every operation must have operationId'})
                    overall = 'FAIL'
                    break

result = {
    'autostep': 'ContractSemanticValidator',
    'timestamp': timestamp,
    'errors': errors,
    'overall': overall
}
with open(output_file, 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

sys.exit(0 if overall == 'PASS' else 1)
PYEOF
