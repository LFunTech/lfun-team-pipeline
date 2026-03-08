#!/bin/bash
# Phase 2.1: Assumption Propagation Validator
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/assumption-propagation-report.json
# 退出码: 0=PASS/WARN 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
REQUIREMENT_FILE="$PIPELINE_DIR/artifacts/requirement.md"
TASKS_FILE="$PIPELINE_DIR/artifacts/tasks.json"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/assumption-propagation-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$REQUIREMENT_FILE" ] || [ ! -f "$TASKS_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"AssumptionPropagationValidator","timestamp":"$TIMESTAMP","error":"missing input files","overall":"ERROR"}
EOF
  exit 2
fi

ASSUMPTIONS=$(grep -oP '\[ASSUMED:[^\]]+\]' "$REQUIREMENT_FILE" 2>/dev/null || echo "")
ASSUMED_COUNT=$(echo "$ASSUMPTIONS" | grep -c '\[ASSUMED:' 2>/dev/null || true)

TASKS_TEXT=$(TASKS_FILE="$TASKS_FILE" python3 -c "
import json, os
try:
  data = json.load(open(os.environ['TASKS_FILE']))
  texts = []
  for t in data.get('tasks', []):
    texts.append(t.get('notes', ''))
    texts.extend(t.get('acceptance_criteria', []))
  print(' '.join(texts))
except: print('')
" 2>/dev/null || echo "")

COVERED=0
UNCOVERED_ASSUMPTIONS=()

if [ "$ASSUMED_COUNT" -gt 0 ]; then
  while IFS= read -r assumption; do
    [ -z "$assumption" ] && continue
    keyword=$(echo "$assumption" | sed 's/\[ASSUMED: *//; s/\]//' | cut -c1-30)
    if echo "$TASKS_TEXT" | grep -qi "$keyword"; then
      COVERED=$((COVERED + 1))
    else
      UNCOVERED_ASSUMPTIONS+=("$assumption")
    fi
  done <<< "$ASSUMPTIONS"
fi

UNCOVERED_COUNT=$((ASSUMED_COUNT - COVERED))
OVERALL="PASS"
[ "$UNCOVERED_COUNT" -gt 0 ] && OVERALL="WARN"

COVERED="$COVERED" UNCOVERED_COUNT="$UNCOVERED_COUNT" ASSUMED_COUNT="$ASSUMED_COUNT" \
OVERALL="$OVERALL" TIMESTAMP="$TIMESTAMP" OUTPUT_FILE="$OUTPUT_FILE" \
python3 -c "
import json, os, sys
uncovered_lines = sys.stdin.read().strip().splitlines() if sys.stdin.readable() else []
uncovered = [{'assumption': a, 'severity': 'WARN'} for a in uncovered_lines if a]
data = {
    'autostep': 'AssumptionPropagationValidator',
    'timestamp': os.environ['TIMESTAMP'],
    'assumptions_found': int(os.environ['ASSUMED_COUNT']),
    'covered': int(os.environ['COVERED']),
    'uncovered_count': int(os.environ['UNCOVERED_COUNT']),
    'uncovered': uncovered,
    'overall': os.environ['OVERALL']
}
with open(os.environ['OUTPUT_FILE'], 'w') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
" <<< "$(printf '%s\n' "${UNCOVERED_ASSUMPTIONS[@]+"${UNCOVERED_ASSUMPTIONS[@]}"}")"

exit 0
