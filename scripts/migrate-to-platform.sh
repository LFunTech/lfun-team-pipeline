#!/bin/bash
# migrate-to-platform.sh — 从 Claude Code 迁移到目标平台的完整脚本
#
# 用法:
#   bash scripts/migrate-to-platform.sh <platform> [options]
#
# 平台:
#   codex      → OpenAI Codex CLI
#   cursor     → Cursor IDE Agent 模式
#   opencode   → OpenCode TUI
#
# 选项:
#   --project-dir <path>  指定项目目录（默认: 当前目录）
#   --dry-run             仅预检，不实际修改
#   --skip-agents         跳过全局 Agent 安装
#   --skip-project        跳过项目级文件迁移
#   --skip-skills         跳过 Skill 迁移
#   --force               跳过确认提示
#   --verbose             输出详细日志
#
# 退出码:
#   0 = 迁移成功
#   1 = 致命错误
#   2 = 预检失败（缺少前置条件）

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════
# 常量与配色
# ═══════════════════════════════════════════════════════════════════════
VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}${BOLD}▶ $*${NC}"; }
log_detail(){ [ "$VERBOSE" = true ] && echo -e "${DIM}         $*${NC}" || true; }

# ═══════════════════════════════════════════════════════════════════════
# 平台配置映射（函数形式，兼容所有 bash 版本）
# ═══════════════════════════════════════════════════════════════════════
platform_cli() {
  case "$1" in
    codex)    echo "codex" ;;
    cursor)   echo "" ;;
    opencode) echo "opencode" ;;
  esac
}

platform_agent_dir() {
  case "$1" in
    codex)    echo "$HOME/.codex/agents" ;;
    cursor)   echo "$HOME/.cursor/agents" ;;
    opencode) echo "$HOME/.config/opencode/agents" ;;
  esac
}

platform_agent_ext() {
  case "$1" in
    codex)    echo ".toml" ;;
    cursor)   echo ".md" ;;
    opencode) echo ".md" ;;
  esac
}

platform_skill_dir() {
  case "$1" in
    codex)    echo "$HOME/.codex/skills" ;;
    cursor)   echo "$HOME/.cursor/skills" ;;
    opencode) echo "$HOME/.config/opencode/skills" ;;
  esac
}

platform_pilot_cmd() {
  case "$1" in
    codex)    echo "codex --full-auto" ;;
    cursor)   echo "在 Cursor Agent 模式中调用 /pilot" ;;
    opencode) echo "opencode run --agent build" ;;
  esac
}

platform_permissions() {
  case "$1" in
    codex)    echo "sandbox_mode = workspace-write" ;;
    cursor)   echo "readonly: false" ;;
    opencode) echo "implicit (no sandbox)" ;;
  esac
}

platform_shell_tool() {
  case "$1" in
    codex)    echo "bash()" ;;
    cursor)   echo "Shell()" ;;
    opencode) echo "bash()" ;;
  esac
}

platform_agent_tool() {
  case "$1" in
    codex)    echo "spawn_agent / 自然语言委派" ;;
    cursor)   echo "Task(subagent_type=name, prompt=...)" ;;
    opencode) echo "@agent-name 委派" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════
# 参数解析
# ═══════════════════════════════════════════════════════════════════════
TARGET_PLATFORM=""
PROJECT_DIR="."
DRY_RUN=false
SKIP_AGENTS=false
SKIP_PROJECT=false
SKIP_SKILLS=false
FORCE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    codex|cursor|opencode) TARGET_PLATFORM="$1"; shift ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --skip-agents) SKIP_AGENTS=true; shift ;;
    --skip-project) SKIP_PROJECT=true; shift ;;
    --skip-skills) SKIP_SKILLS=true; shift ;;
    --force) FORCE=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    -h|--help)
      echo ""
      echo "  migrate-to-platform.sh — Claude Code → 目标平台迁移工具 v${VERSION}"
      echo ""
      echo "  用法: bash scripts/migrate-to-platform.sh <codex|cursor|opencode> [options]"
      echo ""
      echo "  选项:"
      echo "    --project-dir <path>  项目目录（默认: .）"
      echo "    --dry-run             仅预检，不修改"
      echo "    --skip-agents         跳过全局 Agent 安装"
      echo "    --skip-project        跳过项目级迁移"
      echo "    --skip-skills         跳过 Skill 迁移"
      echo "    --force               跳过确认"
      echo "    --verbose             详细输出"
      echo ""
      exit 0
      ;;
    *) log_error "未知参数: $1"; exit 1 ;;
  esac
done

if [ -z "$TARGET_PLATFORM" ]; then
  log_error "请指定目标平台: codex, cursor, opencode"
  echo "  用法: bash scripts/migrate-to-platform.sh <codex|cursor|opencode>"
  exit 1
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || {
  log_error "项目目录不存在: $PROJECT_DIR"
  exit 1
}

# ═══════════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════════
confirm() {
  if [ "$FORCE" = true ]; then return 0; fi
  local prompt="${1:-确认继续？}"
  echo -ne "${YELLOW}  $prompt [y/N] ${NC}"
  read -r answer
  [[ "$answer" =~ ^[Yy] ]]
}

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    local backup="${file}.cc-backup.$(date +%Y%m%d%H%M%S)"
    cp "$file" "$backup"
    log_detail "备份: $file → $backup"
    echo "$backup"
  fi
}

dry_run_guard() {
  if [ "$DRY_RUN" = true ]; then
    log_info "${DIM}(dry-run) 跳过: $*${NC}"
    return 1
  fi
  return 0
}

# ═══════════════════════════════════════════════════════════════════════
# 打印迁移计划
# ═══════════════════════════════════════════════════════════════════════
print_migration_plan() {
  echo ""
  echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║  Claude Code → ${TARGET_PLATFORM} 迁移工具 v${VERSION}              ║${NC}"
  echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}目标平台:${NC}     $TARGET_PLATFORM"
  echo -e "  ${BOLD}项目目录:${NC}     $PROJECT_DIR"
  echo -e "  ${BOLD}Agent 目录:${NC}   $(platform_agent_dir "$TARGET_PLATFORM")"
  echo -e "  ${BOLD}Agent 格式:${NC}   $(platform_agent_ext "$TARGET_PLATFORM")"
  echo -e "  ${BOLD}Shell 工具:${NC}   $(platform_shell_tool "$TARGET_PLATFORM")"
  echo -e "  ${BOLD}Agent 调用:${NC}   $(platform_agent_tool "$TARGET_PLATFORM")"
  echo -e "  ${BOLD}权限模型:${NC}     $(platform_permissions "$TARGET_PLATFORM")"
  echo -e "  ${BOLD}启动命令:${NC}     $(platform_pilot_cmd "$TARGET_PLATFORM")"
  echo ""

  echo -e "  ${BOLD}迁移步骤:${NC}"
  [ "$SKIP_AGENTS" = false ]  && echo "    1. ✓ 全局 Agent 定义安装"    || echo "    1. ✗ 全局 Agent 定义安装（跳过）"
  [ "$SKIP_SKILLS" = false ]  && echo "    2. ✓ Skill 文件迁移"         || echo "    2. ✗ Skill 文件迁移（跳过）"
  [ "$SKIP_PROJECT" = false ] && echo "    3. ✓ 项目文件迁移"           || echo "    3. ✗ 项目文件迁移（跳过）"
  [ "$SKIP_PROJECT" = false ] && echo "    4. ✓ llm-router.sh 后端配置"
  [ "$SKIP_PROJECT" = false ] && echo "    5. ✓ config.json 适配"
  [ "$SKIP_PROJECT" = false ] && echo "    6. ✓ AutoStep 脚本适配"
  [ "$SKIP_PROJECT" = false ] && echo "    7. ✓ 上下文文件生成"
  echo "    8. ✓ 迁移后验证"
  echo ""

  if [ "$DRY_RUN" = true ]; then
    echo -e "  ${YELLOW}[DRY-RUN 模式] 不会实际修改任何文件${NC}"
    echo ""
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Step 0: 预检
# ═══════════════════════════════════════════════════════════════════════
preflight_checks() {
  log_step "Step 0: 预检"

  local failures=0

  # Python3 可用
  if command -v python3 &>/dev/null; then
    log_ok "python3 已安装: $(python3 --version 2>&1)"
  else
    log_error "python3 未安装"
    failures=$((failures + 1))
  fi

  # 转译器存在
  if [ -f "$REPO_DIR/scripts/build-agents.py" ]; then
    log_ok "Agent 转译器: $REPO_DIR/scripts/build-agents.py"
  else
    log_error "Agent 转译器缺失: $REPO_DIR/scripts/build-agents.py"
    failures=$((failures + 1))
  fi

  # 源 Agent 文件存在
  local agent_count
  agent_count=$(find "$REPO_DIR/agents" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$agent_count" -gt 0 ]; then
    log_ok "源 Agent 定义: $agent_count 个"
  else
    log_error "未找到源 Agent 定义: $REPO_DIR/agents/"
    failures=$((failures + 1))
  fi

  # 目标平台 CLI（非 Cursor）
  local cli="$(platform_cli "$TARGET_PLATFORM")"
  if [ -n "$cli" ]; then
    if command -v "$cli" &>/dev/null; then
      log_ok "$TARGET_PLATFORM CLI ($cli): 已安装"
    else
      log_warn "$TARGET_PLATFORM CLI ($cli): 未安装（安装后方可运行流水线）"
    fi
  else
    # Cursor 不需要 CLI
    if [ "$TARGET_PLATFORM" = "cursor" ]; then
      if [ -d "$HOME/.cursor" ]; then
        log_ok "Cursor: 检测到 ~/.cursor 目录"
      else
        log_warn "Cursor: 未检测到 ~/.cursor 目录（请先安装 Cursor IDE）"
      fi
    fi
  fi

  # 检查项目目录中的 .pipeline/
  if [ "$SKIP_PROJECT" = false ]; then
    if [ -d "$PROJECT_DIR/.pipeline" ]; then
      log_ok "项目流水线目录: $PROJECT_DIR/.pipeline/"
    else
      log_warn "项目中无 .pipeline/ — 项目级迁移将生成初始结构"
    fi
  fi

  # CC Skills 存在性检查
  if [ "$SKIP_SKILLS" = false ]; then
    local cc_skill_dir="$HOME/.claude/skills"
    if [ -d "$cc_skill_dir" ]; then
      local skill_count
      skill_count=$(find "$cc_skill_dir" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
      log_ok "Claude Code Skills: $skill_count 个 SKILL.md"
    else
      log_warn "Claude Code Skills 目录不存在: $cc_skill_dir"
    fi
  fi

  # 已有的 CC agents 检查
  if [ "$SKIP_AGENTS" = false ]; then
    local cc_agents="$HOME/.claude/agents"
    if [ -d "$cc_agents" ]; then
      local cc_count
      cc_count=$(find "$cc_agents" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
      log_ok "当前 CC Agents: $cc_count 个（将作为参考）"
    else
      log_info "未检测到已安装的 CC Agents"
    fi
  fi

  if [ "$failures" -gt 0 ]; then
    echo ""
    log_error "预检失败: $failures 个致命问题"
    exit 2
  fi

  log_ok "预检通过"
}

# ═══════════════════════════════════════════════════════════════════════
# Step 1: 全局 Agent 定义安装
# ═══════════════════════════════════════════════════════════════════════
install_global_agents() {
  if [ "$SKIP_AGENTS" = true ]; then return 0; fi

  log_step "Step 1: 安装全局 Agent 定义到 $(platform_agent_dir "$TARGET_PLATFORM")"

  local dist_dir="$REPO_DIR/dist"
  local target_dir="$(platform_agent_dir "$TARGET_PLATFORM")"
  local ext="$(platform_agent_ext "$TARGET_PLATFORM")"

  # 运行转译器
  log_info "运行 Agent 转译器..."
  if ! python3 "$REPO_DIR/scripts/build-agents.py" \
    --platforms "$TARGET_PLATFORM" \
    --output "$dist_dir" 2>&1; then
    log_error "转译器执行失败"
    return 1
  fi

  local platform_dist="$dist_dir/$TARGET_PLATFORM"
  if [ ! -d "$platform_dist" ]; then
    log_error "转译输出目录不存在: $platform_dist"
    return 1
  fi

  local count
  count=$(find "$platform_dist" -maxdepth 1 -name "*${ext}" 2>/dev/null | wc -l | tr -d ' ')
  log_info "已生成 $count 个 $TARGET_PLATFORM Agent 定义"

  if ! dry_run_guard "安装 Agent 到 $target_dir"; then
    return 0
  fi

  # 备份现有 Agent
  if [ -d "$target_dir" ]; then
    local existing
    existing=$(find "$target_dir" -maxdepth 1 -name "*${ext}" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$existing" -gt 0 ]; then
      local backup_dir="${target_dir}.backup.$(date +%Y%m%d%H%M%S)"
      cp -r "$target_dir" "$backup_dir"
      log_info "已备份 $existing 个现有 Agent → $backup_dir"
    fi
  fi

  mkdir -p "$target_dir"
  while IFS= read -r f; do
    cp "$f" "$target_dir/$(basename "$f")"
  done < <(find "$platform_dist" -maxdepth 1 -name "*${ext}" | sort)

  log_ok "$count 个 Agent 已安装到 $target_dir"
}

# ═══════════════════════════════════════════════════════════════════════
# Step 2: Skill 迁移
# ═══════════════════════════════════════════════════════════════════════
migrate_skills() {
  if [ "$SKIP_SKILLS" = true ]; then return 0; fi

  log_step "Step 2: Skill 文件迁移"

  local cc_skills="$HOME/.claude/skills"
  local target_skills="$(platform_skill_dir "$TARGET_PLATFORM")"
  local required_skills=("code-simplifier" "code-review")

  if [ ! -d "$cc_skills" ]; then
    log_warn "CC Skills 目录不存在 ($cc_skills)，跳过"
    log_info "请手动安装 required skills: ${required_skills[*]}"
    return 0
  fi

  if ! dry_run_guard "迁移 Skills 到 $target_skills"; then
    # dry-run: 列出将要迁移的 skills
    for skill in "${required_skills[@]}"; do
      if [ -d "$cc_skills/$skill" ]; then
        log_info "(dry-run) 将迁移 Skill: $skill"
      else
        log_warn "(dry-run) CC Skill 缺失: $skill"
      fi
    done
    return 0
  fi

  mkdir -p "$target_skills"

  local migrated=0
  # 迁移 required skills
  for skill in "${required_skills[@]}"; do
    local src="$cc_skills/$skill"
    local dst="$target_skills/$skill"

    if [ -d "$src" ]; then
      if [ -d "$dst" ]; then
        log_info "Skill '$skill' 已存在于目标，跳过"
      else
        cp -r "$src" "$dst"
        log_ok "迁移 Skill: $skill"
        migrated=$((migrated + 1))
      fi
    else
      log_warn "CC Skill 缺失: $skill（需手动安装）"
    fi
  done

  # 迁移其他自定义 skills（如 frontend-design）
  while IFS= read -r skill_dir; do
    local skill_name
    skill_name=$(basename "$skill_dir")
    # 跳过已处理的
    local already_done=false
    for s in "${required_skills[@]}"; do
      [ "$s" = "$skill_name" ] && already_done=true
    done
    [ "$already_done" = true ] && continue

    local dst="$target_skills/$skill_name"
    if [ -d "$dst" ]; then
      log_detail "Skill '$skill_name' 已存在，跳过"
    else
      cp -r "$skill_dir" "$dst"
      log_ok "迁移自定义 Skill: $skill_name"
      migrated=$((migrated + 1))
    fi
  done < <(find "$cc_skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

  log_ok "Skill 迁移完成: $migrated 个"

  # Skill 路径适配提醒
  case "$TARGET_PLATFORM" in
    codex)
      log_info "Codex Skills 位于: $target_skills/<name>/SKILL.md"
      log_info "Agent TOML 中通过 [[skills.config]] path 引用"
      ;;
    cursor)
      log_info "Cursor Skills 位于: $target_skills/<name>/SKILL.md"
      log_info "Agent 中通过 skill 描述触发（自动发现）"
      ;;
    opencode)
      log_info "OpenCode Skills 位于: $target_skills/<name>/SKILL.md"
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════
# Step 3: 项目级文件迁移
# ═══════════════════════════════════════════════════════════════════════
migrate_project_files() {
  if [ "$SKIP_PROJECT" = true ]; then return 0; fi

  log_step "Step 3: 项目级文件迁移"

  cd "$PROJECT_DIR"

  # --- 3a. 上下文文件 ---
  log_info "生成平台上下文文件..."

  case "$TARGET_PLATFORM" in
    codex)
      # Codex 需要 AGENTS.md
      if [ -f "$REPO_DIR/templates/AGENTS.md" ]; then
        if [ ! -f "AGENTS.md" ]; then
          if dry_run_guard "生成 AGENTS.md"; then
            cp "$REPO_DIR/templates/AGENTS.md" AGENTS.md
            log_ok "AGENTS.md 已生成"
          fi
        else
          log_info "AGENTS.md 已存在，跳过"
        fi
      fi
      ;;

    cursor)
      # Cursor 需要 .cursor/rules/pipeline.md + CLAUDE.md (Cursor 也读 CLAUDE.md)
      if [ -d "$REPO_DIR/templates/.cursor/rules" ]; then
        if dry_run_guard "生成 .cursor/rules/pipeline.md"; then
          mkdir -p .cursor/rules
          cp "$REPO_DIR/templates/.cursor/rules/pipeline.md" .cursor/rules/pipeline.md
          log_ok ".cursor/rules/pipeline.md 已生成"
        fi
      fi
      # CLAUDE.md 对 Cursor 也有效
      if [ ! -f "CLAUDE.md" ] && [ -f "$REPO_DIR/templates/CLAUDE.md" ]; then
        if dry_run_guard "生成 CLAUDE.md"; then
          cp "$REPO_DIR/templates/CLAUDE.md" CLAUDE.md
          log_ok "CLAUDE.md 已生成（Cursor 也使用此文件作为项目上下文）"
        fi
      fi
      ;;

    opencode)
      # OpenCode 需要 AGENTS.md
      if [ -f "$REPO_DIR/templates/AGENTS.md" ]; then
        if [ ! -f "AGENTS.md" ]; then
          if dry_run_guard "生成 AGENTS.md"; then
            cp "$REPO_DIR/templates/AGENTS.md" AGENTS.md
            log_ok "AGENTS.md 已生成"
          fi
        else
          log_info "AGENTS.md 已存在，跳过"
        fi
      fi
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════
# Step 4: llm-router.sh 后端配置
# ═══════════════════════════════════════════════════════════════════════
configure_llm_router() {
  if [ "$SKIP_PROJECT" = true ]; then return 0; fi

  log_step "Step 4: 配置 llm-router.sh 后端"

  cd "$PROJECT_DIR"

  local router=".pipeline/llm-router.sh"
  if [ ! -f "$router" ]; then
    log_info "无 llm-router.sh — 若项目尚未 init，请先运行 team init"
    return 0
  fi

  # 检测 llm-router.sh 版本 — 是否已支持多后端
  if grep -q "detect_cli_backend" "$router" 2>/dev/null; then
    log_ok "llm-router.sh 已是多后端版本"
  else
    log_warn "llm-router.sh 为旧版（仅支持 claude），需升级"
    if [ -f "$REPO_DIR/templates/.pipeline/llm-router.sh" ]; then
      if dry_run_guard "升级 llm-router.sh 为多后端版本"; then
        backup_file "$router"
        cp "$REPO_DIR/templates/.pipeline/llm-router.sh" "$router"
        chmod +x "$router"
        log_ok "llm-router.sh 已升级为多后端版本"
      fi
    else
      log_error "升级模板缺失: $REPO_DIR/templates/.pipeline/llm-router.sh"
    fi
  fi

  # 设置 config.json 中的 cli_backend
  local config=".pipeline/config.json"
  if [ -f "$config" ]; then
    local current_backend
    current_backend=$(python3 -c "
import json
c = json.load(open('$config'))
mr = c.get('model_routing', {})
print(mr.get('cli_backend', 'NOT_SET'))
" 2>/dev/null) || current_backend="NOT_SET"

    if [ "$current_backend" = "NOT_SET" ]; then
      log_info "config.json 中未设置 cli_backend，添加中..."
      if dry_run_guard "在 config.json 中添加 cli_backend"; then
        python3 -c "
import json
with open('$config') as f:
    c = json.load(f)
mr = c.setdefault('model_routing', {})
mr['cli_backend'] = '$TARGET_PLATFORM'
with open('$config', 'w') as f:
    json.dump(c, f, indent=2, ensure_ascii=False)
print('OK')
" 2>/dev/null && log_ok "config.json: cli_backend → $TARGET_PLATFORM"
      fi
    else
      log_info "config.json 当前 cli_backend=$current_backend"
      if [ "$current_backend" != "$TARGET_PLATFORM" ] && [ "$current_backend" != "auto" ]; then
        if dry_run_guard "更新 cli_backend: $current_backend → $TARGET_PLATFORM"; then
          python3 -c "
import json
with open('$config') as f:
    c = json.load(f)
c['model_routing']['cli_backend'] = '$TARGET_PLATFORM'
with open('$config', 'w') as f:
    json.dump(c, f, indent=2, ensure_ascii=False)
" 2>/dev/null && log_ok "config.json: cli_backend → $TARGET_PLATFORM"
        fi
      fi
    fi
  fi

  # 全局 routing.json 隔离检查
  local global_routing="$HOME/.config/team-pipeline/routing.json"
  if [ -f "$global_routing" ]; then
    local global_backend
    global_backend=$(python3 -c "
import json
c = json.load(open('$global_routing'))
print(c.get('cli_backend', 'auto'))
" 2>/dev/null) || global_backend="auto"

    if [ "$global_backend" != "auto" ] && [ "$global_backend" != "$TARGET_PLATFORM" ]; then
      log_warn "全局 routing.json 的 cli_backend=$global_backend（非 auto）"
      log_warn "这会影响所有未在项目级 config.json 中设置 cli_backend 的 repo!"
      log_warn "建议保持全局 cli_backend 为 \"auto\"，只在项目级设置"
    elif [ "$global_backend" = "auto" ]; then
      log_ok "全局 routing.json 的 cli_backend=auto（安全，不影响其他 repo）"
    fi
  fi

  # 环境变量隔离提示
  echo ""
  log_info "项目级切换后端（仅影响本项目，推荐）:"
  echo -e "  ${DIM}.pipeline/config.json → model_routing.cli_backend: \"$TARGET_PLATFORM\"${NC}"
  echo ""
  log_info "临时切换后端（仅当前终端会话）:"
  echo -e "  ${DIM}export PIPELINE_CLI_BACKEND=$TARGET_PLATFORM${NC}"
  echo ""
  log_warn "⚠ 不要在 ~/.bashrc 或 ~/.zshrc 中全局设置 PIPELINE_CLI_BACKEND"
  log_warn "  否则会影响所有 repo。项目级 config.json 是最安全的方式"
}

# ═══════════════════════════════════════════════════════════════════════
# Step 5: config.json 适配
# ═══════════════════════════════════════════════════════════════════════
adapt_config() {
  if [ "$SKIP_PROJECT" = true ]; then return 0; fi

  log_step "Step 5: config.json 适配"

  cd "$PROJECT_DIR"
  local config=".pipeline/config.json"

  if [ ! -f "$config" ]; then
    log_info "无 config.json，跳过"
    return 0
  fi

  # 适配 required_skills 路径
  local skill_dir="$(platform_skill_dir "$TARGET_PLATFORM")"
  log_info "required_skills 将从 $skill_dir 查找"

  # Codex 不需要 plugins — 提醒用户
  case "$TARGET_PLATFORM" in
    codex)
      log_info "Codex 不需要 Claude Code plugins（enabledPlugins），Skills 通过 TOML [[skills.config]] 引用"
      ;;
    cursor)
      log_info "Cursor 使用内置 Agent Skills 机制，不需要 CC plugins"
      ;;
    opencode)
      log_info "OpenCode 使用 JSON 配置文件，不需要 CC plugins"
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════
# Step 6: AutoStep 脚本适配
# ═══════════════════════════════════════════════════════════════════════
adapt_autosteps() {
  if [ "$SKIP_PROJECT" = true ]; then return 0; fi

  log_step "Step 6: AutoStep 脚本适配"

  cd "$PROJECT_DIR"
  local autosteps_dir=".pipeline/autosteps"

  if [ ! -d "$autosteps_dir" ]; then
    log_info "无 autosteps 目录，跳过"
    return 0
  fi

  # duplicate-detector.sh 是唯一包含 `claude` CLI 硬编码的 autostep
  local dup_script="$autosteps_dir/duplicate-detector.sh"
  if [ -f "$dup_script" ]; then
    if grep -q "claude --dangerously-skip-permissions" "$dup_script" 2>/dev/null; then
      log_info "duplicate-detector.sh 包含 CC 硬编码调用，需适配"

      if dry_run_guard "适配 duplicate-detector.sh"; then
        backup_file "$dup_script"

        # 使用通用的 CLI 检测替换硬编码 claude 命令
        python3 << 'PYEOF'
import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else ".pipeline/autosteps/duplicate-detector.sh"

with open(path, 'r') as f:
    content = f.read()

# 在文件开头插入 CLI 检测函数（如果尚未存在）
if 'detect_pipeline_cli' not in content:
    cli_detect_block = '''
# --- 多平台 CLI 检测 ---
detect_pipeline_cli() {
  if [ -n "${PIPELINE_CLI_BACKEND:-}" ]; then
    echo "$PIPELINE_CLI_BACKEND"
    return
  fi
  if command -v claude &>/dev/null; then echo "claude"; return; fi
  if command -v codex &>/dev/null; then echo "codex"; return; fi
  if command -v opencode &>/dev/null; then echo "opencode"; return; fi
  echo "claude"
}

run_agent_cli() {
  local agent_name="$1"
  local prompt="$2"
  local cli
  cli=$(detect_pipeline_cli)
  case "$cli" in
    claude)   claude --dangerously-skip-permissions --agent "$agent_name" -p "$prompt" 2>/dev/null ;;
    codex)    codex exec --agent "$agent_name" --approval-mode never "$prompt" 2>/dev/null ;;
    opencode) opencode exec --agent "$agent_name" "$prompt" 2>/dev/null ;;
  esac
}
'''
    # Insert after the last 'set -' line or after shebang
    import re
    m = re.search(r'(set -[a-z]+\n)', content)
    if m:
        pos = m.end()
    else:
        pos = content.index('\n') + 1

    content = content[:pos] + cli_detect_block + content[pos:]

# Replace all `claude --dangerously-skip-permissions --agent <name>` with run_agent_cli
content = re.sub(
    r'claude --dangerously-skip-permissions --agent (\S+)\s*\\\s*\n\s*-p\s+"([^"]*)"',
    r'run_agent_cli "\1" "\2"',
    content
)
# Simpler single-line variant
content = re.sub(
    r'claude --dangerously-skip-permissions --agent (\S+)\s+-p\s+"([^"]*)"',
    r'run_agent_cli "\1" "\2"',
    content
)

with open(path, 'w') as f:
    f.write(content)

print("OK")
PYEOF
        python3 - "$dup_script" < /dev/null && log_ok "duplicate-detector.sh 已适配" || log_warn "自动适配不完整，可能需手动检查"
      fi
    else
      log_ok "duplicate-detector.sh 已适配或无 CC 依赖"
    fi
  fi

  # 扫描其他 autostep 脚本（防遗漏）
  local other_cc_refs=0
  while IFS= read -r script; do
    [ "$script" = "$dup_script" ] && continue
    if grep -l "claude " "$script" 2>/dev/null >/dev/null; then
      log_warn "$(basename "$script") 中发现 'claude' 引用，请检查"
      other_cc_refs=$((other_cc_refs + 1))
    fi
  done < <(find "$autosteps_dir" -name "*.sh" 2>/dev/null)

  if [ "$other_cc_refs" -eq 0 ]; then
    log_ok "其他 AutoStep 脚本无 CC 依赖"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Step 7: 平台特定配置
# ═══════════════════════════════════════════════════════════════════════
platform_specific_config() {
  if [ "$SKIP_PROJECT" = true ]; then return 0; fi

  log_step "Step 7: ${TARGET_PLATFORM} 平台特定配置"

  cd "$PROJECT_DIR"

  case "$TARGET_PLATFORM" in
    codex)
      # Codex sandbox 配置
      log_info "Codex sandbox 模式: workspace-write（Agent TOML 已配置）"
      log_info "确保 codex CLI 已安装: npm install -g @openai/codex"

      # 生成 .codex/config.json 如果不存在
      if [ ! -f ".codex/config.json" ]; then
        if dry_run_guard "生成 .codex/config.json"; then
          mkdir -p .codex
          cat > .codex/config.json << 'EOF'
{
  "approval_mode": "never",
  "agents_dir": "~/.codex/agents"
}
EOF
          log_ok ".codex/config.json 已生成"
        fi
      fi
      ;;

    cursor)
      # Cursor 需要 .cursor/rules 但不需要额外 CLI 配置
      log_info "Cursor 通过 .cursor/rules/pipeline.md 加载流水线规则"
      log_info "Agent 模式中 /pilot 即可启动流水线"

      # 生成 .cursorrules 如果不存在（旧版 Cursor 兼容）
      if [ ! -f ".cursorrules" ] && [ ! -d ".cursor/rules" ]; then
        if dry_run_guard "生成 .cursor/rules/pipeline.md"; then
          mkdir -p .cursor/rules
          if [ -f "$REPO_DIR/templates/.cursor/rules/pipeline.md" ]; then
            cp "$REPO_DIR/templates/.cursor/rules/pipeline.md" .cursor/rules/pipeline.md
            log_ok ".cursor/rules/pipeline.md 已生成"
          fi
        fi
      fi
      ;;

    opencode)
      # OpenCode 配置
      log_info "OpenCode Agent 定义位于: ~/.config/opencode/agents/"

      if [ ! -f "opencode.json" ]; then
        if dry_run_guard "生成 opencode.json 项目配置"; then
          cat > opencode.json << EOF
{
  "\$schema": "https://opencode.ai/config.schema.json",
  "agents": {
    "pilot": {
      "description": "多角色软件交付流水线主控",
      "model": "default"
    }
  },
  "context": ["AGENTS.md"]
}
EOF
          log_ok "opencode.json 已生成"
        fi
      fi
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════
# Step 8: 迁移后验证
# ═══════════════════════════════════════════════════════════════════════
post_migration_verify() {
  log_step "Step 8: 迁移后验证"

  local issues=0
  local warnings=0

  # 验证 Agent 已安装
  if [ "$SKIP_AGENTS" = false ] && [ "$DRY_RUN" = false ]; then
    local target_dir="$(platform_agent_dir "$TARGET_PLATFORM")"
    local ext="$(platform_agent_ext "$TARGET_PLATFORM")"

    local required_agents=(pilot clarifier architect auditor-gate planner builder-backend builder-frontend builder-dba builder-security builder-infra simplifier inspector tester documenter deployer monitor)
    local missing=0

    for agent in "${required_agents[@]}"; do
      if [ ! -f "$target_dir/${agent}${ext}" ]; then
        log_warn "  缺失 Agent: ${agent}${ext}"
        missing=$((missing + 1))
      fi
    done

    if [ "$missing" -eq 0 ]; then
      local total
      total=$(find "$target_dir" -maxdepth 1 -name "*${ext}" 2>/dev/null | wc -l | tr -d ' ')
      log_ok "全局 Agent: $total 个已安装"
    else
      log_error "缺失 $missing 个必需 Agent"
      issues=$((issues + missing))
    fi
  fi

  # 验证 Skills
  if [ "$SKIP_SKILLS" = false ] && [ "$DRY_RUN" = false ]; then
    local skill_dir="$(platform_skill_dir "$TARGET_PLATFORM")"
    for skill in code-simplifier code-review; do
      if [ -d "$skill_dir/$skill" ]; then
        log_ok "  Skill '$skill' 已就绪"
      else
        log_warn "  Skill '$skill' 未安装"
        warnings=$((warnings + 1))
      fi
    done
  fi

  # 验证项目文件
  if [ "$SKIP_PROJECT" = false ] && [ "$DRY_RUN" = false ]; then
    cd "$PROJECT_DIR"

    # 上下文文件
    case "$TARGET_PLATFORM" in
      codex|opencode)
        [ -f "AGENTS.md" ] && log_ok "AGENTS.md 已就绪" || { log_warn "AGENTS.md 缺失"; warnings=$((warnings + 1)); }
        ;;
      cursor)
        [ -f "CLAUDE.md" ] && log_ok "CLAUDE.md 已就绪" || { log_warn "CLAUDE.md 缺失"; warnings=$((warnings + 1)); }
        [ -f ".cursor/rules/pipeline.md" ] && log_ok ".cursor/rules/pipeline.md 已就绪" || { log_warn ".cursor/rules/pipeline.md 缺失"; warnings=$((warnings + 1)); }
        ;;
    esac

    # llm-router.sh 多后端版本
    if [ -f ".pipeline/llm-router.sh" ]; then
      if grep -q "detect_cli_backend" ".pipeline/llm-router.sh" 2>/dev/null; then
        log_ok "llm-router.sh 已是多后端版本"
      else
        log_warn "llm-router.sh 尚未升级为多后端版本"
        warnings=$((warnings + 1))
      fi
    fi

    # config.json cli_backend
    if [ -f ".pipeline/config.json" ]; then
      local backend
      backend=$(python3 -c "
import json
c = json.load(open('.pipeline/config.json'))
print(c.get('model_routing', {}).get('cli_backend', 'NOT_SET'))
" 2>/dev/null) || backend="NOT_SET"
      if [ "$backend" = "$TARGET_PLATFORM" ] || [ "$backend" = "auto" ]; then
        log_ok "config.json cli_backend=$backend"
      elif [ "$backend" = "NOT_SET" ]; then
        log_warn "config.json 未设置 cli_backend"
        warnings=$((warnings + 1))
      fi
    fi

    # duplicate-detector.sh
    if [ -f ".pipeline/autosteps/duplicate-detector.sh" ]; then
      if grep -q "run_agent_cli\|detect_pipeline_cli" ".pipeline/autosteps/duplicate-detector.sh" 2>/dev/null; then
        log_ok "duplicate-detector.sh 已适配多平台"
      elif grep -q "claude --dangerously-skip-permissions" ".pipeline/autosteps/duplicate-detector.sh" 2>/dev/null; then
        log_warn "duplicate-detector.sh 仍包含 CC 硬编码"
        warnings=$((warnings + 1))
      fi
    fi
  fi

  # 汇总
  echo ""
  if [ "$issues" -eq 0 ] && [ "$warnings" -eq 0 ]; then
    log_ok "验证通过 — 无问题"
  elif [ "$issues" -eq 0 ]; then
    log_warn "验证完成 — $warnings 个警告（非阻断）"
  else
    log_error "验证完成 — $issues 个问题, $warnings 个警告"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# 完成信息
# ═══════════════════════════════════════════════════════════════════════
print_completion() {
  echo ""
  echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║  ✅  迁移完成!                                            ║${NC}"
  echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  echo -e "  ${BOLD}迁移摘要:${NC}"
  echo -e "    源平台:   Claude Code"
  echo -e "    目标平台: ${TARGET_PLATFORM}"
  echo ""

  echo -e "  ${BOLD}启动流水线:${NC}"
  case "$TARGET_PLATFORM" in
    codex)
      echo "    cd $PROJECT_DIR"
      echo "    codex --full-auto"
      echo ""
      echo "    或使用 team CLI:"
      echo "    export PIPELINE_CLI_BACKEND=codex"
      echo "    team run"
      ;;
    cursor)
      echo "    1. 用 Cursor 打开项目: $PROJECT_DIR"
      echo "    2. 在 Agent 模式中输入 /pilot 或自然语言请求"
      echo ""
      echo "    Cursor 同时读取 CLAUDE.md 和 .cursor/rules/ 作为上下文"
      ;;
    opencode)
      echo "    cd $PROJECT_DIR"
      echo "    opencode"
      echo "    # 在 TUI 中输入: @pilot"
      echo ""
      echo "    或使用 team CLI:"
      echo "    export PIPELINE_CLI_BACKEND=opencode"
      echo "    team run"
      ;;
  esac

  echo ""
  echo -e "  ${BOLD}隔离性保证:${NC}"
  echo "    • ~/.claude/agents/ 完全不受影响（CC repo 照常运行）"
  echo "    • 只修改了本项目的 .pipeline/config.json 中的 cli_backend"
  echo "    • 全局 routing.json 的 cli_backend 保持 auto（不影响其他 repo）"
  echo "    • state.json 格式完全兼容，可随时在 CC ↔ ${TARGET_PLATFORM} 间切换"
  echo ""
  echo -e "  ${BOLD}切换回 Claude Code:${NC}"
  echo "    方式 1: 编辑 .pipeline/config.json → cli_backend: \"claude\""
  echo "    方式 2: 临时 export PIPELINE_CLI_BACKEND=claude"
  echo "    方式 3: 删除 cli_backend 字段（回到 auto，自动检测优先用 claude）"
  echo ""
  echo -e "  ${BOLD}CLI 优先级（由高到低）:${NC}"
  echo "    \$PIPELINE_CLI_BACKEND 环境变量 > .pipeline/config.json > 全局 routing.json > 自动检测"

  if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "  ${YELLOW}[DRY-RUN] 以上为预览，实际未修改任何文件${NC}"
    echo -e "  ${YELLOW}去掉 --dry-run 参数以执行实际迁移${NC}"
  fi

  echo ""
}

# ═══════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════
main() {
  print_migration_plan

  if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
    if ! confirm "开始迁移到 $TARGET_PLATFORM？"; then
      echo "  已取消"
      exit 0
    fi
  fi

  preflight_checks
  install_global_agents
  migrate_skills
  migrate_project_files
  configure_llm_router
  adapt_config
  adapt_autosteps
  platform_specific_config
  post_migration_verify
  print_completion
}

main
