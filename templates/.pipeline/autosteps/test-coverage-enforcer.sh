#!/bin/bash
# Phase 4.2: Test Coverage Enforcer
# 输入: PIPELINE_DIR, COVERAGE_THRESHOLD（默认 80）
# 输出: .pipeline/artifacts/coverage-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
COVERAGE_DIR="$PIPELINE_DIR/artifacts/coverage"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/coverage-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONFIG_FILE="${CONFIG_FILE:-$PIPELINE_DIR/config.json}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

THRESHOLD=80
if [ -f "$CONFIG_FILE" ] && command -v python3 &>/dev/null; then
  THRESHOLD=$(CONFIG_FILE="$CONFIG_FILE" python3 << 'PYEOF'
import json, os
try:
    c = json.load(open(os.environ['CONFIG_FILE']))
    print(c.get('testing', {}).get('coverage_threshold', 80))
except Exception:
    print(80)
PYEOF
  )
  THRESHOLD="${THRESHOLD:-80}"
fi

COVERAGE_PCT=0
OVERALL="PASS"

LCOV_FILE=""
[ -f "$COVERAGE_DIR/coverage.lcov" ] && LCOV_FILE="$COVERAGE_DIR/coverage.lcov"
[ -z "$LCOV_FILE" ] && [ -f "$COVERAGE_DIR/lcov.info" ] && LCOV_FILE="$COVERAGE_DIR/lcov.info"

if [ -n "$LCOV_FILE" ]; then
  COVERAGE_PCT=$(LCOV_FILE="$LCOV_FILE" python3 << 'PYEOF'
import os
lcov_file = os.environ.get('LCOV_FILE', '')
try:
  total_lines = 0
  hit_lines = 0
  with open(lcov_file) as f:
    for line in f:
      if line.startswith('LF:'):
        total_lines += int(line.strip()[3:])
      elif line.startswith('LH:'):
        hit_lines += int(line.strip()[3:])
  if total_lines > 0:
    print(round(hit_lines / total_lines * 100, 1))
  else:
    print(0)
except Exception: print(0)
PYEOF
)
elif [ -f "$COVERAGE_DIR/coverage-summary.json" ]; then
  COVERAGE_PCT=$(COVERAGE_DIR="$COVERAGE_DIR" python3 << 'PYEOF'
import json, os
try:
    data = json.load(open(os.environ['COVERAGE_DIR'] + '/coverage-summary.json'))
    print(data.get('total', {}).get('lines', {}).get('pct', 0))
except Exception:
    print(0)
PYEOF
  )
  COVERAGE_PCT="${COVERAGE_PCT:-0}"
fi

BELOW_THRESHOLD=$(python3 -c "print('true' if $COVERAGE_PCT < $THRESHOLD else 'false')" 2>/dev/null || echo "true")
[ "$BELOW_THRESHOLD" = "true" ] && OVERALL="FAIL" || true

TIMESTAMP="$TIMESTAMP" COVERAGE_PCT="$COVERAGE_PCT" THRESHOLD="$THRESHOLD" \
BELOW_THRESHOLD="$BELOW_THRESHOLD" OVERALL="$OVERALL" OUTPUT_FILE="$OUTPUT_FILE" \
python3 << 'PYEOF'
import json, os
result = {
    "autostep": "TestCoverageEnforcer",
    "timestamp": os.environ["TIMESTAMP"],
    "line_coverage_pct": float(os.environ["COVERAGE_PCT"]),
    "threshold_pct": float(os.environ["THRESHOLD"]),
    "below_threshold": os.environ["BELOW_THRESHOLD"] == "true",
    "overall": os.environ["OVERALL"]
}
with open(os.environ["OUTPUT_FILE"], "w") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
PYEOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
