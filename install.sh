#!/bin/bash
# install.sh — 安装 Claude Code Team Pipeline Agents
# 将 agents/ 目录下所有 .md 文件复制到 ~/.claude/agents/

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="$REPO_DIR/agents"
AGENTS_DST="$HOME/.claude/agents"

echo "╔══════════════════════════════════════════════╗"
echo "║  Claude Code Team Pipeline — Agent 安装程序  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 验证源目录 ─────────────────────────────────────────────────────
if [ ! -d "$AGENTS_SRC" ]; then
  echo "❌ 错误: agents/ 目录不存在，请在 repo 根目录运行此脚本"
  exit 1
fi

AGENT_COUNT=$(find "$AGENTS_SRC" -name "*.md" | wc -l)
if [ "$AGENT_COUNT" -eq 0 ]; then
  echo "❌ 错误: agents/ 目录为空，请先执行安装计划"
  exit 1
fi

# ── 创建目标目录 ────────────────────────────────────────────────────
mkdir -p "$AGENTS_DST"
echo "📁 目标目录: $AGENTS_DST"
echo ""

# ── 备份现有文件 ────────────────────────────────────────────────────
EXISTING=$(find "$AGENTS_DST" -name "*.md" 2>/dev/null | wc -l)
if [ "$EXISTING" -gt 0 ]; then
  BACKUP_DIR="$AGENTS_DST.backup.$(date +%Y%m%d%H%M%S)"
  echo "⚠️  检测到 $EXISTING 个现有 Agent 文件，备份到: $BACKUP_DIR"
  cp -r "$AGENTS_DST" "$BACKUP_DIR"
  echo ""
fi

# ── 复制 Agent 文件 ─────────────────────────────────────────────────
echo "📋 安装 Agent 文件..."
INSTALLED=0
while IFS= read -r agent_file; do
  fname=$(basename "$agent_file")
  cp "$agent_file" "$AGENTS_DST/$fname"
  echo "  ✓ $fname"
  INSTALLED=$((INSTALLED + 1))
done < <(find "$AGENTS_SRC" -name "*.md" | sort)

echo ""
echo "✅ 安装完成！已安装 $INSTALLED 个 Agent 文件到 $AGENTS_DST"
echo ""

# ── 验证安装 ──────────────────────────────────────────────────────
echo "── 安装验证 ──────────────────────────────────────"
REQUIRED_AGENTS=("orchestrator" "clarifier" "architect" "auditor-biz" "auditor-tech" "auditor-qa" "auditor-ops" "resolver" "planner" "contract-formalizer" "builder-frontend" "builder-backend" "builder-dba" "builder-security" "builder-infra" "simplifier" "inspector" "tester" "documenter" "deployer" "monitor" "migrator" "optimizer" "translator")

MISSING=0
for agent in "${REQUIRED_AGENTS[@]}"; do
  if [ -f "$AGENTS_DST/$agent.md" ]; then
    echo "  ✓ $agent"
  else
    echo "  ✗ $agent (缺失!)"
    MISSING=$((MISSING + 1))
  fi
done

echo ""
if [ "$MISSING" -eq 0 ]; then
  echo "🎉 所有 24 个 Agent 已成功安装！"
else
  echo "⚠️  $MISSING 个 Agent 安装失败，请检查 agents/ 目录"
  exit 1
fi

# ── 检查必备 Skills ────────────────────────────────────────────────
echo ""
echo "── 必备 Skills 检查 ────────────────────────────"
echo "流水线需要以下两个 Skill："
echo "  • code-simplifier (Simplifier 使用)"
echo "  • code-review (Inspector 使用)"
echo ""
if ls ~/.claude/plugins/ 2>/dev/null | grep -qE "code-simplifier|code-review"; then
  echo "  ✓ Skills 已安装"
else
  echo "  ℹ️  提示：如 Skills 未安装，Inspector 和 Simplifier 功能将降级"
  echo "      请参考: https://docs.anthropic.com/claude-code/skills"
fi

# ── 使用说明 ──────────────────────────────────────────────────────
echo ""
echo "── 使用方法 ─────────────────────────────────────"
echo ""
echo "1. 初始化项目流水线配置："
echo "   mkdir -p .pipeline/autosteps .pipeline/artifacts"
echo "   cp -r $REPO_DIR/templates/.pipeline/config.json .pipeline/"
echo "   cp -r $REPO_DIR/templates/.pipeline/autosteps/ .pipeline/autosteps/"
echo "   cp $REPO_DIR/templates/CLAUDE.md CLAUDE.md"
echo ""
echo "2. 编辑 .pipeline/config.json，设置 project_name 等配置"
echo ""
echo "3. 启动流水线："
echo "   claude --agent orchestrator"
echo ""
echo "════════════════════════════════════════════════"
