#!/bin/bash
# Phase 3.2: Diff Scope Validator
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/scope-validation-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
TASKS_FILE="$PIPELINE_DIR/artifacts/tasks.json"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/scope-validation-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 读取 Phase 3 基准 SHA（worktree 模式下使用）
PHASE3_BASE_SHA=""
if [ -f "$PIPELINE_DIR/state.json" ] && command -v python3 &>/dev/null; then
  PHASE3_BASE_SHA=$(PIPELINE_DIR="$PIPELINE_DIR" python3 -c "
import json, os
try:
  s = json.load(open(os.environ['PIPELINE_DIR'] + '/state.json'))
  print(s.get('phase_3_base_sha') or '')
except Exception:
  print('')
" 2>/dev/null || echo "")
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$TASKS_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"DiffScopeValidator","timestamp":"$TIMESTAMP","error":"tasks.json not found","overall":"ERROR"}
EOF
  exit 2
fi

AUTHORIZED_FILES=$(TASKS_FILE="$TASKS_FILE" python3 -c "
import json, os
data = json.load(open(os.environ['TASKS_FILE']))
files = set()
for task in data.get('tasks', []):
  for f in task.get('files', []):
    files.add(f['path'])
print('\n'.join(sorted(files)))
" 2>/dev/null || echo "")

if ! command -v git &>/dev/null; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"DiffScopeValidator","timestamp":"$TIMESTAMP","error":"git not available","overall":"ERROR"}
EOF
  exit 2
fi

if [ -n "$PHASE3_BASE_SHA" ]; then
  ACTUAL_CHANGES=$(git diff --name-only "$PHASE3_BASE_SHA"..HEAD 2>/dev/null || echo "")
else
  ACTUAL_CHANGES=$(git diff --name-only HEAD 2>/dev/null || echo "")
  ACTUAL_CHANGES+=$'\n'$(git diff --name-only --cached 2>/dev/null || echo "")
fi
ACTUAL_CHANGES=$(echo "$ACTUAL_CHANGES" | sort -u | grep -v '^$' || echo "")

UNAUTHORIZED=()
OVERALL="PASS"

while IFS= read -r changed_file; do
  [ -z "$changed_file" ] && continue
  [[ "$changed_file" == .pipeline/* ]] && continue
  if ! echo "$AUTHORIZED_FILES" | grep -qxF "$changed_file"; then
    UNAUTHORIZED+=("$changed_file")
    OVERALL="FAIL"
  fi
done <<< "$ACTUAL_CHANGES"

TIMESTAMP="$TIMESTAMP" PHASE3_BASE_SHA="${PHASE3_BASE_SHA:-HEAD}" \
OVERALL="$OVERALL" OUTPUT_FILE="$OUTPUT_FILE" python3 -c "
import json, os, sys
unauthorized = [u for u in sys.stdin.read().strip().splitlines() if u]
result = {
    'autostep': 'DiffScopeValidator',
    'timestamp': os.environ['TIMESTAMP'],
    'base_sha': os.environ['PHASE3_BASE_SHA'],
    'unauthorized_changes': unauthorized,
    'overall': os.environ['OVERALL']
}
with open(os.environ['OUTPUT_FILE'], 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
" <<< "$(printf '%s\n' "${UNAUTHORIZED[@]+"${UNAUTHORIZED[@]}"}")"

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
