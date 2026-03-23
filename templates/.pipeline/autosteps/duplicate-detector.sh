#!/usr/bin/env bash
# duplicate-detector.sh — Phase 3.0d 重复组件检测与整改
# 输入: MODE (full|refresh|incremental|check-only), PIPELINE_DIR
# 输出: .pipeline/artifacts/duplicate-report.json
# 退出码: 0=PASS(完成或无重复) 1=WARN(人工介入) 2=ERROR

set -euo pipefail

# --- 多平台 CLI 检测（优先级：环境变量 > config.json > llm-router.sh > 自动检测）---
detect_pipeline_cli() {
  if [ -n "${PIPELINE_CLI_BACKEND:-}" ]; then
    echo "$PIPELINE_CLI_BACKEND"
    return
  fi
  local config="${PIPELINE_DIR:-.pipeline}/config.json"
  if [ -f "$config" ]; then
    local cfg_backend
    cfg_backend=$(python3 -c "import json; c=json.load(open('$config')); print(c.get('model_routing',{}).get('cli_backend','auto'))" 2>/dev/null || echo "auto")
    if [ "$cfg_backend" != "auto" ] && [ -n "$cfg_backend" ]; then
      echo "$cfg_backend"
      return
    fi
  fi
  if command -v claude &>/dev/null; then echo "claude"; return; fi
  if command -v codex &>/dev/null; then echo "codex"; return; fi
  if command -v opencode &>/dev/null; then echo "opencode"; return; fi
  echo "none"
}

run_agent_cli() {
  local agent_name="$1"
  local prompt="$2"
  # Try llm-router.sh first (supports model_routing)
  local router="${PIPELINE_DIR:-.pipeline}/llm-router.sh"
  if [ -f "$router" ]; then
    bash "$router" "$agent_name" "$prompt" 2>/dev/null && return 0
    local rc=$?
    [ $rc -eq 10 ] || return $rc
  fi
  local cli
  cli=$(detect_pipeline_cli)
  case "$cli" in
    claude)   claude --dangerously-skip-permissions --agent "$agent_name" -p "$prompt" 2>/dev/null ;;
    codex)    codex exec --agent "$agent_name" --approval-mode never "$prompt" 2>/dev/null ;;
    opencode) opencode run --agent "$agent_name" "$prompt" 2>/dev/null ;;
    *)        echo "[DuplicateDetector] 未检测到支持的 CLI (claude/codex/opencode)" >&2; return 1 ;;
  esac
}

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
MODE="${MODE:-full}"
ARTIFACTS="$PIPELINE_DIR/artifacts"
CONFIG="$PIPELINE_DIR/config.json"
REGISTRY="$ARTIFACTS/component-registry.json"
CANDIDATES="$ARTIFACTS/duplicate-candidates.json"
REMEDIATION="$ARTIFACTS/remediation-plan.json"
AUDIT="$ARTIFACTS/audit-result.json"
REPORT="$ARTIFACTS/duplicate-report.json"
FEEDBACK_FILE="$ARTIFACTS/audit-feedback.txt"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$ARTIFACTS"

# ── Pre-checks ──
if [ ! -f "$REGISTRY" ]; then
  echo "[DuplicateDetector] component-registry.json not found, skipping"
  cat > "$REPORT" << EOF
{"autostep":"DuplicateDetector","timestamp":"$TIMESTAMP","status":"skipped","reason":"registry not found"}
EOF
  exit 0
fi

# Check if enabled
DD_ENABLED=$(python3 -c "
import json
try:
    c = json.load(open('$CONFIG'))
    print(str(c.get('component_registry',{}).get('duplicate_detection',{}).get('enabled', True)).lower())
except: print('true')
" 2>/dev/null || echo "true")

if [ "$DD_ENABLED" = "false" ]; then
  echo "[DuplicateDetector] duplicate_detection.enabled=false, skipping"
  cat > "$REPORT" << EOF
{"autostep":"DuplicateDetector","timestamp":"$TIMESTAMP","status":"disabled"}
EOF
  exit 0
fi

# ── Step 1: Python rule detection ──
echo "[DuplicateDetector] Step 1: Rule detection (mode: $MODE)"
python3 "$PIPELINE_DIR/autosteps/duplicate_analyzer.py" \
  --registry "$REGISTRY" \
  --config "$CONFIG" \
  --output "$CANDIDATES" \
  --mode "$MODE"

if [ "$MODE" = "check-only" ]; then
  echo "[DuplicateDetector] --check-only mode, output: $CANDIDATES"
  cp "$CANDIDATES" "$REPORT"
  exit 0
fi

# Check for candidates
CANDIDATE_COUNT=$(python3 -c "import json; print(len(json.load(open('$CANDIDATES')).get('candidates',[])))")
if [ "$CANDIDATE_COUNT" -eq 0 ]; then
  echo "[DuplicateDetector] No duplicates found"
  cat > "$REPORT" << EOF
{"autostep":"DuplicateDetector","timestamp":"$TIMESTAMP","status":"clean","stats":{"total_duplicates":0}}
EOF
  exit 0
fi

echo "[DuplicateDetector] Found $CANDIDATE_COUNT duplicate candidate groups"

# ── Read config ──
read -r CONFIGURED_MODEL MAX_RETRIES AUTO_APPLY <<< $(python3 -c "
import json
c = json.load(open('$CONFIG'))
dd = c.get('component_registry',{}).get('duplicate_detection',{})
model = dd.get('generator_model', 'auto')
retries = dd.get('max_retries_per_tier', 3)
auto = str(dd.get('auto_apply', False)).lower()
print(f'{model} {retries} {auto}')
")

# ── Step 2 + 3: Generate + Audit loop ──
AUDIT_RESULT="FAIL"
echo "" > "$FEEDBACK_FILE"

for TIER in "configured" "session"; do
  if [ "$TIER" = "configured" ] && [ "$CONFIGURED_MODEL" != "auto" ]; then
    MODEL_HINT="使用模型：$CONFIGURED_MODEL。"
  else
    MODEL_HINT=""
  fi

  for ATTEMPT in $(seq 1 "$MAX_RETRIES"); do
    echo "[DuplicateDetector] Tier=$TIER, Attempt=$ATTEMPT/$MAX_RETRIES"

    # Step 2: Generate
    FEEDBACK_CONTENT=$(cat "$FEEDBACK_FILE" 2>/dev/null || echo "")
    GENERATOR_PROMPT="读取 $CANDIDATES 中的重复候选列表和项目源码，为每组重复生成整改方案。输出到 $REMEDIATION。${MODEL_HINT}"
    if [ -n "$FEEDBACK_CONTENT" ]; then
      GENERATOR_PROMPT="$GENERATOR_PROMPT

上一次审计未通过，审计意见如下，请据此修正方案：
$FEEDBACK_CONTENT"
    fi

    echo "[DuplicateDetector]   Generating remediation plan..."
    run_agent_cli "duplicate-generator" "$GENERATOR_PROMPT" || {
      echo "[DuplicateDetector]   Generator failed"
      continue
    }

    if [ ! -f "$REMEDIATION" ]; then
      echo "[DuplicateDetector]   remediation-plan.json not generated"
      continue
    fi

    # Step 3: Audit (independent process)
    echo "[DuplicateDetector]   Auditing remediation plan..."
    run_agent_cli "duplicate-auditor" "审核 $REMEDIATION 中的整改方案正确性，独立验证每个 patch。输出到 $AUDIT。" || {
      echo "[DuplicateDetector]   Auditor failed"
      continue
    }

    if [ ! -f "$AUDIT" ]; then
      echo "[DuplicateDetector]   audit-result.json not generated"
      continue
    fi

    AUDIT_RESULT=$(python3 -c "import json; print(json.load(open('$AUDIT')).get('overall','FAIL'))")
    if [ "$AUDIT_RESULT" = "PASS" ]; then
      echo "[DuplicateDetector]   Audit passed!"
      break 2
    fi

    echo "[DuplicateDetector]   Audit failed, extracting feedback..."
    python3 -c "
import json
r = json.load(open('$AUDIT'))
issues = []
for rem in r.get('remediations', []):
    if rem.get('verdict') == 'FAIL':
        for issue in rem.get('issues', []):
            issues.append(f\"[{rem['group_id']}] {issue}\")
with open('$FEEDBACK_FILE', 'w') as f:
    f.write('\n'.join(issues))
"
  done
done

# ── Step 4: Final report ──
if [ "$AUDIT_RESULT" = "PASS" ]; then
  STATUS="ready"
else
  STATUS="manual_needed"
fi

python3 -c "
import json, datetime
candidates = json.load(open('$CANDIDATES'))
status = '$STATUS'
report = {
    'report_time': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'mode': '$MODE',
    'status': status,
    'duplicates': candidates.get('candidates', []),
    'stats': candidates.get('stats', {})
}
try:
    remediation = json.load(open('$REMEDIATION'))
    report['remediation_summary'] = remediation.get('summary', {})
except: pass
try:
    audit = json.load(open('$AUDIT'))
    report['audit_model'] = audit.get('auditor_model', '')
except: pass
with open('$REPORT', 'w') as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
"

echo "[DuplicateDetector] Report: $REPORT"

if [ "$STATUS" = "manual_needed" ]; then
  echo "[DuplicateDetector] WARN: Remediation audit failed, manual intervention needed"
  exit 1
fi

if [ "$AUTO_APPLY" = "true" ]; then
  echo "[DuplicateDetector] auto_apply=true, applying patches"
  # Patch application to be implemented when auto_apply is used
fi

exit 0
