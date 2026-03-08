#!/bin/bash
# Phase 3.6: Post-Simplification Verifier
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/post-simplify-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/post-simplify-report.json"
SIMPLIFY_REPORT="$PIPELINE_DIR/artifacts/simplify-report.md"
IMPL_MANIFEST="$PIPELINE_DIR/artifacts/impl-manifest.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

# 收集检查结果到数组（格式：check|result|detail）
CHECKS=()
OVERALL="PASS"

add_check() {
  CHECKS+=("$1|$2|$3")
  [ "$2" = "FAIL" ] && OVERALL="FAIL" || true
}

if [ -f "$SIMPLIFY_REPORT" ] && [ -f "$IMPL_MANIFEST" ]; then
  if [ "$SIMPLIFY_REPORT" -nt "$IMPL_MANIFEST" ]; then
    add_check "simplify_report_newer_than_manifest" "PASS" "simplify-report.md 比 impl-manifest.json 更新"
  else
    add_check "simplify_report_newer_than_manifest" "FAIL" "simplify-report.md 不比 impl-manifest.json 更新，Simplifier 可能未运行"
  fi
else
  add_check "simplify_report_exists" "FAIL" "simplify-report.md 或 impl-manifest.json 不存在"
fi

REGRESSION_EXIT=0
# Bug #8 fix: check go.mod before package.json to avoid false npm detection in Go+Node hybrid projects
# Rust support added: check Cargo.toml first
if [ -f "Cargo.toml" ] && command -v cargo &>/dev/null; then
  set +e
  cargo test > /dev/null 2>&1
  REGRESSION_EXIT=$?
  set -e
elif [ -f "go.mod" ] && command -v go &>/dev/null; then
  set +e
  go test ./... > /dev/null 2>&1
  REGRESSION_EXIT=$?
  set -e
elif command -v python3 &>/dev/null && { [ -f "pyproject.toml" ] || [ -f "pytest.ini" ]; }; then
  set +e
  python3 -m pytest -q > /dev/null 2>&1
  REGRESSION_EXIT=$?
  set -e
elif [ -f "package.json" ] && command -v npm &>/dev/null; then
  set +e
  npm test -- --passWithNoTests > /dev/null 2>&1
  REGRESSION_EXIT=$?
  set -e
fi

if [ "$REGRESSION_EXIT" -eq 0 ]; then
  add_check "regression_after_simplification" "PASS" "回归测试通过"
else
  add_check "regression_after_simplification" "FAIL" "回归测试失败，精简可能破坏了现有功能"
fi

# 使用 python3 生成 JSON（避免手动拼接导致的转义问题）
TIMESTAMP="$TIMESTAMP" OVERALL="$OVERALL" OUTPUT_FILE="$OUTPUT_FILE" python3 -c "
import json, os, sys
checks_raw = [l for l in sys.stdin.read().strip().splitlines() if l]
checks = []
for line in checks_raw:
    parts = line.split('|', 2)
    if len(parts) == 3:
        checks.append({'check': parts[0], 'result': parts[1], 'detail': parts[2]})
result = {
    'autostep': 'PostSimplificationVerifier',
    'timestamp': os.environ['TIMESTAMP'],
    'checks': checks,
    'overall': os.environ['OVERALL']
}
with open(os.environ['OUTPUT_FILE'], 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
" <<< "$(printf '%s\n' "${CHECKS[@]}")"

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
