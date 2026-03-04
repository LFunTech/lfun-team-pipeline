#!/bin/bash
# Phase 3.3: Regression Guard
# 输入: PIPELINE_DIR, TEST_COMMAND（默认自动检测）
# 输出: .pipeline/artifacts/regression-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/regression-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
STATE_FILE="$PIPELINE_DIR/state.json"

mkdir -p "$(dirname "$OUTPUT_FILE")"

NEW_TEST_FILES=""
if [ -f "$STATE_FILE" ] && command -v python3 &>/dev/null; then
  NEW_TEST_FILES=$(python3 -c "
import json
data = json.load(open('$STATE_FILE'))
print('\n'.join(data.get('new_test_files', [])))
" 2>/dev/null || echo "")
fi

if [ -n "${TEST_COMMAND:-}" ]; then
  CMD="$TEST_COMMAND"
elif [ -f "package.json" ] && command -v npm &>/dev/null; then
  CMD="npm test -- --passWithNoTests"
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
  CMD="python -m pytest -q"
elif [ -f "go.mod" ]; then
  CMD="go test ./..."
else
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"RegressionGuard","timestamp":"$TIMESTAMP","warning":"no test command detected","overall":"PASS"}
EOF
  exit 0
fi

set +e
TEST_OUTPUT=$(eval "$CMD" 2>&1)
TEST_EXIT=$?
set -e

OVERALL="PASS"
[ "$TEST_EXIT" -ne 0 ] && OVERALL="FAIL" || true

ESCAPED_OUTPUT=$(echo "$TEST_OUTPUT" | head -50 | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read()))
" 2>/dev/null || echo '"[output unavailable]"')

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "RegressionGuard",
  "timestamp": "$TIMESTAMP",
  "test_command": "$CMD",
  "exit_code": $TEST_EXIT,
  "output_summary": $ESCAPED_OUTPUT,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
