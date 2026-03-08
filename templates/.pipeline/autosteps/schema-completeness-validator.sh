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

TASKS_FILE="$TASKS_FILE" CONTRACTS_DIR="$CONTRACTS_DIR" \
TIMESTAMP="$TIMESTAMP" OUTPUT_FILE="$OUTPUT_FILE" python3 << 'PYEOF'
import json, os, sys, glob

tasks_file = os.environ['TASKS_FILE']
contracts_dir = os.environ['CONTRACTS_DIR']
timestamp = os.environ['TIMESTAMP']
output_file = os.environ['OUTPUT_FILE']

try:
    import yaml
except ImportError:
    yaml = None

# 从 tasks.json 读取期望的 contracts 数量
try:
    data = json.load(open(tasks_file))
    contracts = data.get('contracts', None)
    if contracts is not None:
        expected_count = sum(1 for c in contracts if c.get('type') != 'internal')
    else:
        expected_count = -1
except Exception:
    expected_count = -1

actual_count = 0
invalid_files = []
overall = 'PASS'

if os.path.isdir(contracts_dir):
    all_files = sorted(
        glob.glob(f'{contracts_dir}/*.yaml') +
        glob.glob(f'{contracts_dir}/*.json')
    )
    # 排除以 _ 开头的元数据文件（如 _index.yaml）和非 OpenAPI 文件
    schema_files = [f for f in all_files if not os.path.basename(f).startswith('_')]
    actual_count = len(schema_files)

    for schema_file in schema_files:
        fname = os.path.basename(schema_file)
        try:
            with open(schema_file) as fh:
                if schema_file.endswith('.yaml'):
                    if yaml is None:
                        invalid_files.append(fname)
                        overall = 'FAIL'
                        continue
                    file_data = yaml.safe_load(fh)
                else:
                    file_data = json.load(fh)
            assert str(file_data.get('openapi', '')).startswith('3.'), 'not openapi 3.x'
            assert 'paths' in file_data, 'missing paths'
        except Exception:
            invalid_files.append(fname)
            overall = 'FAIL'

# 仅当 tasks.json 明确声明 contracts 列表时才检查数量（-1 表示未声明，跳过）
if expected_count >= 0 and actual_count != expected_count:
    overall = 'FAIL'

result = {
    'autostep': 'SchemaCompletenessValidator',
    'timestamp': timestamp,
    'expected_contracts': expected_count,
    'actual_schemas': actual_count,
    'invalid_files': invalid_files,
    'overall': overall
}
with open(output_file, 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

sys.exit(0 if overall == 'PASS' else 1)
PYEOF
