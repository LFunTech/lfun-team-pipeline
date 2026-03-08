#!/bin/bash
# Phase 3.1: Static Analyzer
# 输入: PIPELINE_DIR, IMPL_MANIFEST（默认 .pipeline/artifacts/impl-manifest.json）
# 输出: .pipeline/artifacts/static-analysis-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
IMPL_MANIFEST="${IMPL_MANIFEST:-$PIPELINE_DIR/artifacts/impl-manifest.json}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/static-analysis-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$IMPL_MANIFEST" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"StaticAnalyzer","timestamp":"$TIMESTAMP","error":"impl-manifest.json not found","overall":"ERROR"}
EOF
  exit 2
fi

OVERALL="PASS"
LINT_ERRORS=0
COMPLEXITY_JSON="[]"
DEPENDENCY_VULNS=0

CHANGED_FILES=$(IMPL_MANIFEST="$IMPL_MANIFEST" python3 -c "
import json, os
data = json.load(open(os.environ['IMPL_MANIFEST']))
files = [f['path'] for f in data.get('files_changed', []) if not f['path'].startswith('tests/')]
print('\n'.join(files))
" 2>/dev/null || echo "")

# 语言检测优先级：Rust > Go > Node/Python（与 build-verifier.sh / regression-guard.sh 一致）
if [ -f "Cargo.toml" ]; then
  # Rust 项目：cargo clippy
  if command -v cargo &>/dev/null; then
    set +e
    CLIPPY_OUTPUT=$(cargo clippy --all-targets -- -D warnings 2>&1)
    CLIPPY_EXIT=$?
    set -e
    if [ "$CLIPPY_EXIT" -ne 0 ]; then
      LINT_ERRORS=$(echo "$CLIPPY_OUTPUT" | grep -cE "^error" || echo 0)
      [ "$LINT_ERRORS" -eq 0 ] && LINT_ERRORS=1
      OVERALL="FAIL"
    fi
  fi
  # Rust 依赖审计（cargo audit，若存在）
  if command -v cargo-audit &>/dev/null; then
    set +e
    AUDIT_OUTPUT=$(cargo audit 2>&1)
    AUDIT_EXIT=$?
    set -e
    if [ "$AUDIT_EXIT" -ne 0 ]; then
      DEPENDENCY_VULNS=$(echo "$AUDIT_OUTPUT" | grep -cE "^ID:" || echo 1)
      OVERALL="FAIL"
    fi
  fi

elif [ -f "go.mod" ]; then
  # Go 项目：go vet
  if command -v go &>/dev/null; then
    set +e
    VET_OUTPUT=$(go vet ./... 2>&1)
    VET_EXIT=$?
    set -e
    if [ "$VET_EXIT" -ne 0 ]; then
      LINT_ERRORS=$(echo "$VET_OUTPUT" | wc -l || echo 1)
      OVERALL="FAIL"
    fi
  fi
  # Go 静态分析（staticcheck / golangci-lint，若存在）
  if command -v golangci-lint &>/dev/null; then
    set +e
    GCI_OUTPUT=$(golangci-lint run ./... 2>&1)
    GCI_EXIT=$?
    set -e
    if [ "$GCI_EXIT" -ne 0 ]; then
      EXTRA_ERRORS=$(echo "$GCI_OUTPUT" | grep -cE "^[^#]" || echo 0)
      LINT_ERRORS=$((LINT_ERRORS + EXTRA_ERRORS))
      OVERALL="FAIL"
    fi
  fi

elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
  # Python 项目（优先级高于 Node，与 regression-guard.sh / post-simplification-verifier.sh 一致）
  if command -v flake8 &>/dev/null; then
    LINT_ERRORS=$(echo "$CHANGED_FILES" | grep -E '\.py$' | xargs -r flake8 2>/dev/null | wc -l || echo 0)
    [ "$LINT_ERRORS" -gt 0 ] && OVERALL="FAIL" || true
  fi

elif [ -f "package.json" ]; then
  # Node.js 项目
  if command -v eslint &>/dev/null && [ -n "$CHANGED_FILES" ]; then
    LINT_ERRORS=$(echo "$CHANGED_FILES" | xargs -r eslint --format=json 2>/dev/null | python3 -c "
import json, sys
try:
  data = json.load(sys.stdin)
  print(sum(f.get('errorCount', 0) for f in data))
except: print(0)
" 2>/dev/null || echo 0)
    [ "$LINT_ERRORS" -gt 0 ] && OVERALL="FAIL" || true
  fi

  if command -v npm &>/dev/null; then
    # Bug #7 fix: use set +e to avoid pipefail causing both python3 and || echo 0 to output
    set +e
    DEPENDENCY_VULNS=$(npm audit --json 2>/dev/null | python3 -c "
import json, sys
try: print(json.load(sys.stdin).get('metadata', {}).get('vulnerabilities', {}).get('high', 0))
except: print(0)
" 2>/dev/null)
    [ -z "$DEPENDENCY_VULNS" ] && DEPENDENCY_VULNS=0
    set -e
    [ "$DEPENDENCY_VULNS" -gt 0 ] && OVERALL="FAIL" || true
  fi
fi

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "StaticAnalyzer",
  "timestamp": "$TIMESTAMP",
  "lint_errors": $LINT_ERRORS,
  "complexity_issues": $COMPLEXITY_JSON,
  "dependency_vulnerabilities_high": $DEPENDENCY_VULNS,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
