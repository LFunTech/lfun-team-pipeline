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
  PHASE3_BASE_SHA=$(python3 -c "
import json
try:
  s = json.load(open('$PIPELINE_DIR/state.json'))
  print(s.get('phase_3_base_sha') or '')
except:
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

AUTHORIZED_FILES=$(python3 -c "
import json
data = json.load(open('$TASKS_FILE'))
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

UNAUTHORIZED_LIST="["
FIRST=true
OVERALL="PASS"

while IFS= read -r changed_file; do
  [ -z "$changed_file" ] && continue
  [[ "$changed_file" == .pipeline/* ]] && continue
  if ! echo "$AUTHORIZED_FILES" | grep -qxF "$changed_file"; then
    if ! $FIRST; then UNAUTHORIZED_LIST+=","; fi
    FIRST=false
    UNAUTHORIZED_LIST+="\"$changed_file\""
    OVERALL="FAIL"
  fi
done <<< "$ACTUAL_CHANGES"

UNAUTHORIZED_LIST+="]"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "DiffScopeValidator",
  "timestamp": "$TIMESTAMP",
  "base_sha": "${PHASE3_BASE_SHA:-HEAD}",
  "unauthorized_changes": $UNAUTHORIZED_LIST,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
