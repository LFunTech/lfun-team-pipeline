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

if [ -n "${TEST_COMMAND:-}" ]; then
  CMD="$TEST_COMMAND"
elif [ -f "Cargo.toml" ] && command -v cargo &>/dev/null; then
  # Bug regression fix: Rust projects must use cargo test, not npm/go
  CMD="cargo test 2>&1"
elif [ -f "go.mod" ] && command -v go &>/dev/null; then
  # Bug #8 fix: check go.mod before package.json to avoid false npm detection in Go+Node hybrid projects
  CMD="go test ./..."
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
  CMD="python -m pytest -q"
elif [ -f "package.json" ] && command -v npm &>/dev/null; then
  CMD="npm test -- --passWithNoTests"
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

ESCAPED_OUTPUT="$ESCAPED_OUTPUT" CMD="$CMD" TEST_EXIT="$TEST_EXIT" \
OVERALL="$OVERALL" TIMESTAMP="$TIMESTAMP" OUTPUT_FILE="$OUTPUT_FILE" \
python3 << 'PYEOF'
import json, os
result = {
    "autostep": "RegressionGuard",
    "timestamp": os.environ["TIMESTAMP"],
    "test_command": os.environ["CMD"],
    "exit_code": int(os.environ["TEST_EXIT"]),
    "output_summary": json.loads(os.environ["ESCAPED_OUTPUT"]),
    "overall": os.environ["OVERALL"]
}
with open(os.environ["OUTPUT_FILE"], "w") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
PYEOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
