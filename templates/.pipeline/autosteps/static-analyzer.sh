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

CHANGED_FILES=$(python3 -c "
import json
data = json.load(open('$IMPL_MANIFEST'))
files = [f['path'] for f in data.get('files_changed', []) if not f['path'].startswith('tests/')]
print('\n'.join(files))
" 2>/dev/null || echo "")

if command -v eslint &>/dev/null && [ -n "$CHANGED_FILES" ]; then
  LINT_ERRORS=$(echo "$CHANGED_FILES" | xargs -r eslint --format=json 2>/dev/null | python3 -c "
import json, sys
try:
  data = json.load(sys.stdin)
  print(sum(f.get('errorCount', 0) for f in data))
except: print(0)
" 2>/dev/null || echo 0)
  [ "$LINT_ERRORS" -gt 0 ] && OVERALL="FAIL"
elif command -v flake8 &>/dev/null; then
  LINT_ERRORS=$(echo "$CHANGED_FILES" | grep -E '\.py$' | xargs -r flake8 2>/dev/null | wc -l || echo 0)
  [ "$LINT_ERRORS" -gt 0 ] && OVERALL="FAIL"
fi

if command -v npm &>/dev/null && [ -f "package.json" ]; then
  DEPENDENCY_VULNS=$(npm audit --json 2>/dev/null | python3 -c "
import json, sys
try: print(json.load(sys.stdin).get('metadata', {}).get('vulnerabilities', {}).get('high', 0))
except: print(0)
" 2>/dev/null || echo 0)
  [ "$DEPENDENCY_VULNS" -gt 0 ] && OVERALL="FAIL"
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
