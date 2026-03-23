#!/bin/bash
# rollback.sh — 一键回滚到备份的全局环境
# Usage: bash scripts/rollback.sh [backup_dir]
#
# 不带参数时自动查找最近一次备份。
set -euo pipefail

find_latest_backup() {
  local pattern="$HOME/.local/share/team-pipeline-backup-"
  local latest=""
  for d in "${pattern}"*/; do
    [ -d "$d" ] && latest="$d"
  done
  [ -n "$latest" ] && echo "${latest%/}" || return 1
}

BACKUP_DIR="${1:-}"
if [ -z "$BACKUP_DIR" ]; then
  BACKUP_DIR=$(find_latest_backup) || {
    echo "❌ 未找到备份目录。"
    echo "   用法: bash scripts/rollback.sh <backup_dir>"
    echo "   备份目录格式: ~/.local/share/team-pipeline-backup-YYYYMMDD_HHMMSS"
    exit 1
  }
fi

if [ ! -d "$BACKUP_DIR" ]; then
  echo "❌ 备份目录不存在: $BACKUP_DIR"
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         lfun-team-pipeline 一键回滚                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  备份源: $BACKUP_DIR"
echo ""

# Pre-flight check
ITEMS=0
[ -f "$BACKUP_DIR/team" ] && ITEMS=$((ITEMS + 1))
[ -d "$BACKUP_DIR/team-pipeline" ] && ITEMS=$((ITEMS + 1))
[ -d "$BACKUP_DIR/claude-agents" ] && ITEMS=$((ITEMS + 1))
[ -f "$BACKUP_DIR/routing.json" ] && ITEMS=$((ITEMS + 1))

if [ "$ITEMS" -eq 0 ]; then
  echo "❌ 备份目录为空或格式不对"
  exit 1
fi

echo "  即将回滚以下 $ITEMS 项:"
[ -f "$BACKUP_DIR/team" ] && echo "    • team CLI → ~/.local/bin/team"
[ -d "$BACKUP_DIR/team-pipeline" ] && echo "    • TEAM_HOME → ~/.local/share/team-pipeline/"
[ -d "$BACKUP_DIR/claude-agents" ] && echo "    • CC agents → ~/.claude/agents/"
[ -f "$BACKUP_DIR/routing.json" ] && echo "    • routing.json → ~/.config/team-pipeline/routing.json"
echo ""

# Confirm unless --force
if [ "${2:-}" != "--force" ]; then
  read -p "  确认回滚? [y/N] " confirm
  case "$confirm" in
    y|Y|yes|YES) ;;
    *)
      echo "  已取消。"
      exit 0
      ;;
  esac
  echo ""
fi

# 1. team CLI
if [ -f "$BACKUP_DIR/team" ]; then
  cp "$BACKUP_DIR/team" "$HOME/.local/bin/team"
  chmod +x "$HOME/.local/bin/team"
  echo "  ✓ team CLI 已回滚"
fi

# 2. TEAM_HOME
if [ -d "$BACKUP_DIR/team-pipeline" ]; then
  rm -rf "$HOME/.local/share/team-pipeline"
  cp -r "$BACKUP_DIR/team-pipeline" "$HOME/.local/share/team-pipeline"
  echo "  ✓ TEAM_HOME 已回滚"
fi

# 3. CC agents
if [ -d "$BACKUP_DIR/claude-agents" ]; then
  rm -rf "$HOME/.claude/agents"
  cp -r "$BACKUP_DIR/claude-agents" "$HOME/.claude/agents"
  echo "  ✓ CC agents 已回滚 ($(ls "$HOME/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ') files)"
fi

# 4. routing.json
if [ -f "$BACKUP_DIR/routing.json" ]; then
  mkdir -p "$HOME/.config/team-pipeline"
  cp "$BACKUP_DIR/routing.json" "$HOME/.config/team-pipeline/routing.json"
  echo "  ✓ routing.json 已回滚"
fi

echo ""
echo "  ✅ 回滚完成！当前环境已恢复到备份时的状态。"
echo ""
echo "  验证:"
echo "    team version"
echo "    ls ~/.claude/agents/ | wc -l"
echo ""
