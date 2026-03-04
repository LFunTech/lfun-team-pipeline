#!/bin/bash
# Phase 4.3: Performance Baseline Checker
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/perf-baseline-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
PERF_REPORT="$PIPELINE_DIR/artifacts/perf-report.json"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/perf-baseline-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$PERF_REPORT" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"PerformanceBaselineChecker","timestamp":"$TIMESTAMP","skipped":true,"reason":"perf-report.json not found (optimizer not activated)","overall":"PASS"}
EOF
  exit 0
fi

PIPELINE_DIR="$PIPELINE_DIR" TIMESTAMP="$TIMESTAMP" python3 << 'PYEOF'
import json, os, sys

pipeline_dir = os.environ.get('PIPELINE_DIR', '.pipeline')
timestamp = os.environ.get('TIMESTAMP', '')
perf_report = json.load(open(f'{pipeline_dir}/artifacts/perf-report.json'))
output_file = f'{pipeline_dir}/artifacts/perf-baseline-report.json'

sla_violated = perf_report.get('sla_violated', False)
results = perf_report.get('results', [])
violations = [r for r in results if r.get('sla_violated', False)]
overall = 'FAIL' if sla_violated or violations else 'PASS'

result = {
  'autostep': 'PerformanceBaselineChecker',
  'timestamp': timestamp,
  'sla_violated': sla_violated,
  'violations': violations,
  'overall': overall
}

with open(output_file, 'w') as f:
  json.dump(result, f, indent=2, ensure_ascii=False)

sys.exit(0 if overall == 'PASS' else 1)
PYEOF
