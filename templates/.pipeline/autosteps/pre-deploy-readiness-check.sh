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

# 收集检查结果到数组
CHECKS=()

if [ -f "$DEPLOY_PLAN" ]; then
  CHECKS+=("deploy_plan_exists|PASS|deploy-plan.md 存在")
else
  CHECKS+=("deploy_plan_exists|FAIL|deploy-plan.md 不存在，Builder-Infra 未生成部署计划")
fi

if [ -f "$DEPLOY_PLAN" ] && grep -qi "rollback_command" "$DEPLOY_PLAN"; then
  CHECKS+=("rollback_command_defined|PASS|rollback_command 已在 deploy-plan.md 中定义")
else
  CHECKS+=("rollback_command_defined|FAIL|rollback_command 未在 deploy-plan.md 中定义")
fi

if [ -f "$STATE_FILE" ] && command -v python3 &>/dev/null; then
  MIGRATION_REQUIRED=$(STATE_FILE="$STATE_FILE" python3 -c "
import json, os
try:
  s = json.load(open(os.environ['STATE_FILE']))
  print('true' if s.get('conditional_agents', {}).get('migrator', False) else 'false')
except Exception: print('false')
" 2>/dev/null || echo "false")

  if [ "$MIGRATION_REQUIRED" = "true" ]; then
    MIGRATION_FILES=$(find . -name "*.sql" -path "*/migrations/*" 2>/dev/null | wc -l)
    if [ "$MIGRATION_FILES" -gt 0 ]; then
      CHECKS+=("migration_scripts_exist|PASS|找到 $MIGRATION_FILES 个迁移脚本")
    else
      CHECKS+=("migration_scripts_exist|FAIL|data_migration_required=true 但未找到迁移脚本")
    fi
  fi
fi

if [ -f ".env.example" ]; then
  CHECKS+=("env_example_exists|PASS|.env.example 存在，环境变量已记录")
else
  CHECKS+=("env_example_exists|WARN|无 .env.example（建议创建以记录环境变量依赖）")
fi

# 使用 python3 生成 JSON（避免手动拼接导致的转义问题）
OVERALL=$(TIMESTAMP="$TIMESTAMP" OUTPUT_FILE="$OUTPUT_FILE" python3 -c "
import json, os, sys
checks_raw = sys.stdin.read().strip().splitlines()
checks = []
overall = 'PASS'
for line in checks_raw:
    if not line:
        continue
    parts = line.split('|', 2)
    if len(parts) == 3:
        checks.append({'check': parts[0], 'result': parts[1], 'detail': parts[2]})
        if parts[1] == 'FAIL':
            overall = 'FAIL'
result = {
    'autostep': 'PreDeployReadinessCheck',
    'timestamp': os.environ['TIMESTAMP'],
    'checks': checks,
    'overall': overall
}
with open(os.environ['OUTPUT_FILE'], 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
print(overall)
" <<< "$(printf '%s\n' "${CHECKS[@]}")")

OVERALL="${OVERALL:-FAIL}"
[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
