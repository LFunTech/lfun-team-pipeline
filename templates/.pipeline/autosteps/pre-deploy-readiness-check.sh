#!/bin/bash
# Phase 6.0: Pre-Deploy Readiness Check
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/deploy-readiness-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
PROPOSAL_FILE="$PIPELINE_DIR/artifacts/proposal.md"
STATE_FILE="$PIPELINE_DIR/state.json"
DEPLOY_PLAN="$PIPELINE_DIR/artifacts/deploy-plan.md"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/deploy-readiness-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

OVERALL="PASS"
CHECKS_LIST="["
FIRST=true

add_check() {
  if ! $FIRST; then CHECKS_LIST+=","; fi
  FIRST=false
  CHECKS_LIST+="{\"check\":\"$1\",\"result\":\"$2\",\"detail\":\"$3\"}"
  [ "$2" = "FAIL" ] && OVERALL="FAIL" || true
}

if [ -f "$DEPLOY_PLAN" ]; then
  add_check "deploy_plan_exists" "PASS" "deploy-plan.md 存在"
else
  add_check "deploy_plan_exists" "FAIL" "deploy-plan.md 不存在，Builder-Infra 未生成部署计划"
fi

if [ -f "$DEPLOY_PLAN" ] && grep -qi "rollback_command" "$DEPLOY_PLAN"; then
  add_check "rollback_command_defined" "PASS" "rollback_command 已在 deploy-plan.md 中定义"
else
  add_check "rollback_command_defined" "FAIL" "rollback_command 未在 deploy-plan.md 中定义"
fi

if [ -f "$STATE_FILE" ] && command -v python3 &>/dev/null; then
  MIGRATION_REQUIRED=$(python3 -c "
import json
try:
  s = json.load(open('$STATE_FILE'))
  print('true' if s.get('conditional_agents', {}).get('migrator', False) else 'false')
except: print('false')
" 2>/dev/null || echo "false")

  if [ "$MIGRATION_REQUIRED" = "true" ]; then
    MIGRATION_FILES=$(find . -name "*.sql" -path "*/migrations/*" 2>/dev/null | wc -l)
    if [ "$MIGRATION_FILES" -gt 0 ]; then
      add_check "migration_scripts_exist" "PASS" "找到 $MIGRATION_FILES 个迁移脚本"
    else
      add_check "migration_scripts_exist" "FAIL" "data_migration_required=true 但未找到迁移脚本"
    fi
  fi
fi

if [ -f ".env.example" ]; then
  add_check "env_example_exists" "PASS" ".env.example 存在，环境变量已记录"
else
  add_check "env_example_exists" "PASS" "无 .env.example（可能无环境变量依赖）"
fi

CHECKS_LIST+="]"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "PreDeployReadinessCheck",
  "timestamp": "$TIMESTAMP",
  "checks": $CHECKS_LIST,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
