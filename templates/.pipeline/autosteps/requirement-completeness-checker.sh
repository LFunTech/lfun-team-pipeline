#!/bin/bash
# Phase 0.5: Requirement Completeness Checker
# 输入: PIPELINE_DIR（默认 .pipeline），REQUIREMENT_FILE（默认 .pipeline/artifacts/requirement.md）
# 输出: .pipeline/artifacts/requirement-completeness-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
REQUIREMENT_FILE="${REQUIREMENT_FILE:-$PIPELINE_DIR/artifacts/requirement.md}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/requirement-completeness-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONFIG_FILE="${CONFIG_FILE:-$PIPELINE_DIR/config.json}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$REQUIREMENT_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"RequirementCompletenessChecker","timestamp":"$TIMESTAMP","error":"requirement.md not found","overall":"ERROR"}
EOF
  exit 2
fi

MIN_WORDS=200
if [ -f "$CONFIG_FILE" ] && command -v python3 &>/dev/null; then
  MIN_WORDS=$(CONFIG_FILE="$CONFIG_FILE" python3 -c "
import json, os
try:
  c = json.load(open(os.environ['CONFIG_FILE']))
  print(c.get('requirement_completeness', {}).get('min_words', 200))
except: print(200)
" 2>/dev/null || echo 200)
fi

REQUIRED_SECTIONS=("### 功能描述" "### 用户故事" "### 业务规则" "### 范围边界" "### 验收标准")

PARENT_FOUND=false
EXTRACTED=""
IN_PARENT=false

while IFS= read -r line; do
  if [[ "$line" == "## 最终需求定义"* ]]; then
    IN_PARENT=true
    PARENT_FOUND=true
    continue
  fi
  if $IN_PARENT; then
    if [[ "$line" =~ ^##[^#] ]]; then
      IN_PARENT=false
    else
      EXTRACTED+="$line"$'\n'
    fi
  fi
done < "$REQUIREMENT_FILE"

SECTIONS_RESULTS=()
SECTIONS_OVERALL="PASS"

if ! $PARENT_FOUND; then
  SECTIONS_RESULTS+=("最终需求定义_section_found|false")
  for section in "${REQUIRED_SECTIONS[@]}"; do
    key=$(echo "$section" | sed 's/### //')
    SECTIONS_RESULTS+=("$key|MISSING")
  done
  SECTIONS_OVERALL="FAIL"
else
  SECTIONS_RESULTS+=("最终需求定义_section_found|true")
  for section in "${REQUIRED_SECTIONS[@]}"; do
    key=$(echo "$section" | sed 's/### //')
    if echo "$EXTRACTED" | grep -qF "$section"; then
      SECTIONS_RESULTS+=("$key|PRESENT")
    else
      SECTIONS_RESULTS+=("$key|MISSING")
      SECTIONS_OVERALL="FAIL"
    fi
  done
fi

CRITICAL_COUNT=$(grep -c '\[CRITICAL-UNRESOLVED' "$REQUIREMENT_FILE" 2>/dev/null || true)
[ "$CRITICAL_COUNT" -gt 0 ] && SECTIONS_OVERALL="FAIL" || true

ASSUMED_COUNT=$(grep -c '\[ASSUMED:' "$REQUIREMENT_FILE" 2>/dev/null || true)
ASSUMED_VALID=true
if [ "$ASSUMED_COUNT" -gt 0 ]; then
  INVALID_FORMAT=$(grep '\[ASSUMED:' "$REQUIREMENT_FILE" | grep -cvE '\[ASSUMED: .+\]' 2>/dev/null || true)
  [ "$INVALID_FORMAT" -gt 0 ] && ASSUMED_VALID=false || true
fi

WORD_COUNT=$(wc -w < "$REQUIREMENT_FILE")
[ "$WORD_COUNT" -lt "$MIN_WORDS" ] && SECTIONS_OVERALL="FAIL" || true

OVERALL="$SECTIONS_OVERALL"

TIMESTAMP="$TIMESTAMP" CRITICAL_COUNT="$CRITICAL_COUNT" ASSUMED_COUNT="$ASSUMED_COUNT" \
ASSUMED_VALID="$ASSUMED_VALID" WORD_COUNT="$WORD_COUNT" MIN_WORDS="$MIN_WORDS" \
OVERALL="$OVERALL" OUTPUT_FILE="$OUTPUT_FILE" python3 -c "
import json, os, sys
sections_raw = [l for l in sys.stdin.read().strip().splitlines() if l]
sections_check = {}
for line in sections_raw:
    key, val = line.split('|', 1)
    sections_check[key] = val if val not in ('true', 'false') else (val == 'true')
result = {
    'autostep': 'RequirementCompletenessChecker',
    'timestamp': os.environ['TIMESTAMP'],
    'sections_check': sections_check,
    'critical_unresolved_count': int(os.environ['CRITICAL_COUNT']),
    'assumed_items_count': int(os.environ['ASSUMED_COUNT']),
    'assumed_items_valid_format': os.environ['ASSUMED_VALID'] == 'true',
    'word_count': int(os.environ['WORD_COUNT']),
    'word_count_threshold': int(os.environ['MIN_WORDS']),
    'overall': os.environ['OVERALL']
}
with open(os.environ['OUTPUT_FILE'], 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
" <<< "$(printf '%s\n' "${SECTIONS_RESULTS[@]}")"

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
