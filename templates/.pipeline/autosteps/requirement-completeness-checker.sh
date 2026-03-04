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
  MIN_WORDS=$(python3 -c "
import json, sys
try:
  c = json.load(open('$CONFIG_FILE'))
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

SECTIONS_JSON=""
SECTIONS_OVERALL="PASS"

if ! $PARENT_FOUND; then
  SECTIONS_JSON='"最终需求定义_section_found":false,"功能描述":"MISSING","用户故事":"MISSING","业务规则":"MISSING","范围边界":"MISSING","验收标准":"MISSING"'
  SECTIONS_OVERALL="FAIL"
else
  SECTIONS_JSON='"最终需求定义_section_found":true'
  for section in "${REQUIRED_SECTIONS[@]}"; do
    key=$(echo "$section" | sed 's/### //')
    if echo "$EXTRACTED" | grep -qF "$section"; then
      SECTIONS_JSON+=",\"$key\":\"PRESENT\""
    else
      SECTIONS_JSON+=",\"$key\":\"MISSING\""
      SECTIONS_OVERALL="FAIL"
    fi
  done
fi

CRITICAL_COUNT=$(grep -c '\[CRITICAL-UNRESOLVED' "$REQUIREMENT_FILE" 2>/dev/null || echo 0)
[ "$CRITICAL_COUNT" -gt 0 ] && SECTIONS_OVERALL="FAIL"

ASSUMED_COUNT=$(grep -c '\[ASSUMED:' "$REQUIREMENT_FILE" 2>/dev/null || echo 0)
ASSUMED_VALID=true

WORD_COUNT=$(wc -w < "$REQUIREMENT_FILE")
[ "$WORD_COUNT" -lt "$MIN_WORDS" ] && SECTIONS_OVERALL="FAIL"

OVERALL="$SECTIONS_OVERALL"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "RequirementCompletenessChecker",
  "timestamp": "$TIMESTAMP",
  "sections_check": {$SECTIONS_JSON},
  "critical_unresolved_count": $CRITICAL_COUNT,
  "assumed_items_count": $ASSUMED_COUNT,
  "assumed_items_valid_format": $ASSUMED_VALID,
  "word_count": $WORD_COUNT,
  "word_count_threshold": $MIN_WORDS,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
