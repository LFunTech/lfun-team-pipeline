#!/bin/bash
# Phase 4a.1: Test Failure Mapper (仅在 Phase 4a FAIL 时触发)
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/failure-builder-map.json
# 退出码: 0=完成映射 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
TEST_REPORT="$PIPELINE_DIR/artifacts/test-report.json"
IMPL_MANIFEST="$PIPELINE_DIR/artifacts/impl-manifest.json"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/failure-builder-map.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$TEST_REPORT" ] || [ ! -f "$IMPL_MANIFEST" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"TestFailureMapper","timestamp":"$TIMESTAMP","error":"missing input files","overall":"ERROR"}
EOF
  exit 2
fi

PIPELINE_DIR="$PIPELINE_DIR" TIMESTAMP="$TIMESTAMP" python3 << 'PYEOF'
import json, os, sys, re

pipeline_dir = os.environ.get('PIPELINE_DIR', '.pipeline')
timestamp = os.environ.get('TIMESTAMP', '')
test_report = json.load(open(f'{pipeline_dir}/artifacts/test-report.json'))
impl_manifest = json.load(open(f'{pipeline_dir}/artifacts/impl-manifest.json'))
output_file = f'{pipeline_dir}/artifacts/failure-builder-map.json'

file_to_builder = {}
for builder_info in impl_manifest.get('builders', []):
  builder = builder_info.get('builder', 'unknown')
  for f in builder_info.get('files_changed', []):
    file_to_builder[f['path']] = builder

failed_tests = test_report.get('failed_tests', [])
builder_failures = {}

for test in failed_tests:
  test_file = test.get('file', '')
  source_guess = re.sub(r'\.test\.|\.spec\.', '.', test_file.replace('tests/', 'src/'))
  builder = file_to_builder.get(source_guess, file_to_builder.get(test_file, None))
  if builder:
    builder_failures.setdefault(builder, []).append(test['test'])
  else:
    builder_failures.setdefault('unknown', []).append(test['test'])

has_unknown = 'unknown' in builder_failures
unique_builders = [b for b in builder_failures if b != 'unknown']

if has_unknown or len(unique_builders) > 2:
  confidence = 'LOW'
  builders_to_rollback = list(set(file_to_builder.values()))
else:
  confidence = 'HIGH'
  builders_to_rollback = unique_builders

result = {
  'autostep': 'TestFailureMapper',
  'timestamp': timestamp,
  'failed_test_count': len(failed_tests),
  'builder_failure_map': builder_failures,
  'confidence': confidence,
  'builders_to_rollback': builders_to_rollback,
  'rollback_strategy': 'precise' if confidence == 'HIGH' else 'conservative_full',
  'overall': 'MAPPED'
}

with open(output_file, 'w') as f:
  json.dump(result, f, indent=2, ensure_ascii=False)
PYEOF

exit 0
