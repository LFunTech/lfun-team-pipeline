#!/bin/bash
# Phase 5 前置: API Change Detector
# 输入: PIPELINE_DIR, OLD_CONTRACTS_DIR
# 输出: .pipeline/artifacts/api-change-report.json
# 退出码: 0=检测完成 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
CONTRACTS_DIR="$PIPELINE_DIR/artifacts/contracts"
OLD_CONTRACTS_DIR="${OLD_CONTRACTS_DIR:-$PIPELINE_DIR/artifacts/contracts.old}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/api-change-report.json"
STATE_FILE="$PIPELINE_DIR/state.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

API_CHANGED=false
CHANGED_CONTRACTS="[]"

if [ ! -d "$OLD_CONTRACTS_DIR" ]; then
  API_CHANGED=true
  CHANGED_CONTRACTS=$(find "$CONTRACTS_DIR" -name "*.yaml" -o -name "*.json" 2>/dev/null | python3 -c "
import sys, json
files = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(files))
" 2>/dev/null || echo "[]")
elif [ -d "$CONTRACTS_DIR" ]; then
  DIFF_OUTPUT=$(diff -rq "$OLD_CONTRACTS_DIR" "$CONTRACTS_DIR" 2>/dev/null || echo "")
  if [ -n "$DIFF_OUTPUT" ]; then
    API_CHANGED=true
    CHANGED_CONTRACTS=$(echo "$DIFF_OUTPUT" | python3 -c "
import sys, json, re
files = set()
for line in sys.stdin:
  m = re.search(r'(?:Files|Only in) .+?/([^/\s:]+)', line)
  if m: files.add(m.group(1))
print(json.dumps(list(files)))
" 2>/dev/null || echo "[]")
  fi
fi

if [ -f "$STATE_FILE" ] && command -v python3 &>/dev/null; then
  PHASE5_MODE=$( [ "$API_CHANGED" = "true" ] && echo "full" || echo "changelog_only" )
  STATE_FILE="$STATE_FILE" PHASE5_MODE="$PHASE5_MODE" python3 << 'PYEOF'
import json, os
state_file = os.environ['STATE_FILE']
with open(state_file) as f:
    state = json.load(f)
state['phase_5_mode'] = os.environ['PHASE5_MODE']
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
PYEOF
fi

PHASE5_MODE=$( [ "$API_CHANGED" = "true" ] && echo "full" || echo "changelog_only" )
TIMESTAMP="$TIMESTAMP" API_CHANGED="$API_CHANGED" PHASE5_MODE="$PHASE5_MODE" \
CHANGED_CONTRACTS="$CHANGED_CONTRACTS" OUTPUT_FILE="$OUTPUT_FILE" python3 << 'PYEOF'
import json, os
result = {
    "autostep": "APIChangeDetector",
    "timestamp": os.environ["TIMESTAMP"],
    "api_changed": os.environ["API_CHANGED"] == "true",
    "changed_contracts": json.loads(os.environ.get("CHANGED_CONTRACTS", "[]")),
    "phase_5_mode": os.environ["PHASE5_MODE"],
    "overall": "PASS"
}
with open(os.environ["OUTPUT_FILE"], "w") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
PYEOF

exit 0
