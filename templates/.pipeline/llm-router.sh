#!/bin/bash
# llm-router.sh — 多平台模型路由调度器
# 用法: bash .pipeline/llm-router.sh <agent-name> <prompt> [--cwd <dir>] [--backend <cli>]
#
# 支持的 CLI 后端: claude, codex, opencode (自动检测或手动指定)
#
# 配置合并优先级（高→低）：
#   项目 .pipeline/config.json → 全局 ~/.config/team-pipeline/routing.json
#
# CLI 后端优先级（高→低）：
#   --backend 参数 → $PIPELINE_CLI_BACKEND 环境变量
#   → config.json 的 cli_backend 字段 → 自动检测
#
# API Key 优先级（高→低）：
#   项目 config.json 的 api_key → 全局 routing.json 的 api_key
#   → 环境变量（由 api_key_env 指定，如 $DASHSCOPE_API_KEY）→ .depend/llm.env
#
# 退出码:
#   0  = 成功（外部 LLM 执行完成）
#   1  = Agent 执行失败（应走 rollback）
#   10 = 降级：应改用默认模型（未启用/未路由/无 key/provider 缺失/无 CLI）
#        Pilot 收到 exit=10 时，改用平台原生 Agent 调度重新调用，不算失败

set -euo pipefail

EXIT_FALLBACK=10  # 降级退出码

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
CONFIG_FILE="$PIPELINE_DIR/config.json"
GLOBAL_CONFIG="${HOME}/.config/team-pipeline/routing.json"
AGENT_NAME="${1:?用法: llm-router.sh <agent-name> <prompt> [--cwd <dir>] [--backend <cli>]}"
PROMPT="${2:?缺少 prompt 参数}"
CWD="."
CLI_BACKEND_ARG=""

# 解析可选参数
shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd) CWD="$2"; shift 2 ;;
    --backend) CLI_BACKEND_ARG="$2"; shift 2 ;;
    *) echo "[llm-router] 未知参数: $1" >&2; exit 2 ;;
  esac
done

# --- 检测 CLI 后端 ---
detect_cli_backend() {
  # 1. 命令行参数最优先
  if [ -n "$CLI_BACKEND_ARG" ]; then
    echo "$CLI_BACKEND_ARG"
    return
  fi

  # 2. 环境变量
  if [ -n "${PIPELINE_CLI_BACKEND:-}" ]; then
    echo "$PIPELINE_CLI_BACKEND"
    return
  fi

  # 3. 配置文件中的 cli_backend 字段
  local cfg_backend
  cfg_backend=$(python3 -c "
import json, os
for path in ['$CONFIG_FILE', '$GLOBAL_CONFIG']:
    if os.path.exists(path):
        try:
            cfg = json.load(open(path))
            mr = cfg.get('model_routing', cfg)
            b = mr.get('cli_backend', '')
            if b and b != 'auto':
                print(b)
                exit(0)
        except Exception:
            pass
print('auto')
" 2>/dev/null) || echo "auto"

  if [ "$cfg_backend" != "auto" ]; then
    echo "$cfg_backend"
    return
  fi

  # 4. 自动检测可用 CLI
  if command -v claude &>/dev/null; then echo "claude"; return; fi
  if command -v codex &>/dev/null; then echo "codex"; return; fi
  if command -v opencode &>/dev/null; then echo "opencode"; return; fi

  echo "none"
}

CLI_BACKEND=$(detect_cli_backend)
if [ "$CLI_BACKEND" = "none" ]; then
  echo "[llm-router] 未检测到可用 CLI 后端 (claude/codex/opencode)，降级" >&2
  exit $EXIT_FALLBACK
fi
echo "[llm-router] CLI 后端: $CLI_BACKEND" >&2

# --- 合并读取路由配置（全局 + 项目） ---
ROUTE_INFO=$(python3 -c "
import json, sys, os

# 加载全局配置
global_cfg = {}
global_path = '$GLOBAL_CONFIG'
if os.path.exists(global_path):
    try:
        global_cfg = json.load(open(global_path))
    except Exception:
        pass

# 加载项目配置
project_cfg = {}
project_path = '$CONFIG_FILE'
if os.path.exists(project_path):
    try:
        project_cfg = json.load(open(project_path)).get('model_routing', {})
    except Exception:
        pass

# 合并：项目覆盖全局
enabled = project_cfg.get('enabled', global_cfg.get('enabled', False))
if not enabled:
    print('DISABLED')
    sys.exit(0)

# providers: 全局 + 项目（项目同名 key 级别合并）
providers = {}
for name, conf in global_cfg.get('providers', {}).items():
    providers[name] = dict(conf)
for name, conf in project_cfg.get('providers', {}).items():
    if name in providers:
        providers[name].update({k: v for k, v in conf.items() if v})  # 非空值覆盖
    else:
        providers[name] = dict(conf)

# routes: 全局 + 项目（项目同名覆盖）
routes = {}
routes.update(global_cfg.get('routes', {}))
routes.update(project_cfg.get('routes', {}))

# 查找当前 agent
agent = '$AGENT_NAME'
provider_name = routes.get(agent)
if not provider_name:
    print('NOT_ROUTED')
    sys.exit(0)

p = providers.get(provider_name)
if not p:
    print(f'NO_PROVIDER:{provider_name}')
    sys.exit(0)

api_key = p.get('api_key', '')
api_key_env = p.get('api_key_env', '')
max_turns = p.get('max_turns', 30)
timeout = p.get('timeout', 600)

print(f'{provider_name}|{p[\"base_url\"]}|{p[\"model\"]}|{api_key}|{api_key_env}|{max_turns}|{timeout}')
" 2>/dev/null) || {
  echo "[llm-router] 配置解析失败，降级到默认模型" >&2
  exit $EXIT_FALLBACK
}

# --- 降级判断 ---
case "$ROUTE_INFO" in
  DISABLED)
    echo "[llm-router] model_routing 未启用，降级到默认模型" >&2
    exit $EXIT_FALLBACK
    ;;
  NOT_ROUTED)
    echo "[llm-router] $AGENT_NAME 未配置路由，降级到默认模型" >&2
    exit $EXIT_FALLBACK
    ;;
  NO_PROVIDER:*)
    echo "[llm-router] provider '${ROUTE_INFO#NO_PROVIDER:}' 未定义，降级到默认模型" >&2
    exit $EXIT_FALLBACK
    ;;
esac

# 解析路由信息
IFS='|' read -r PROVIDER BASE_URL MODEL API_KEY API_KEY_ENV MAX_TURNS TIMEOUT <<< "$ROUTE_INFO"

# --- API Key 解析 ---
RESOLVED_KEY=""

# 1. config 中直接写的 api_key
if [ -n "$API_KEY" ]; then
  RESOLVED_KEY="$API_KEY"
fi

# 2. 通过环境变量名间接引用
if [ -z "$RESOLVED_KEY" ] && [ -n "$API_KEY_ENV" ]; then
  if [ -f ".depend/llm.env" ]; then
    set -a
    source ".depend/llm.env" 2>/dev/null || true
    set +a
  fi
  RESOLVED_KEY="${!API_KEY_ENV:-}"
fi

# 3. 需要 key 但找不到 → 降级
if [ -z "$RESOLVED_KEY" ] && [ -n "$API_KEY_ENV" ]; then
  echo "[llm-router] $PROVIDER 需要 API Key 但未配置，降级到默认模型" >&2
  echo "[llm-router] 配置方式: config.json 的 api_key 字段，或环境变量 \$$API_KEY_ENV" >&2
  exit $EXIT_FALLBACK
fi

# 4. 无需 key 的 provider（如 Ollama）直接放行

echo "[llm-router] $AGENT_NAME → $PROVIDER ($MODEL)" >&2

# --- 构建环境变量 ---
# Claude Code 使用 ANTHROPIC_* 环境变量
# Codex 使用 OPENAI_* 或兼容 Anthropic 网关
# OpenCode 使用其自身配置或 OPENAI_* 环境变量
setup_env_for_backend() {
  case "$CLI_BACKEND" in
    claude)
      export ANTHROPIC_BASE_URL="$BASE_URL"
      export ANTHROPIC_MODEL="$MODEL"
      [ -n "$RESOLVED_KEY" ] && export ANTHROPIC_AUTH_TOKEN="$RESOLVED_KEY"
      ;;
    codex)
      export OPENAI_BASE_URL="$BASE_URL"
      export OPENAI_MODEL="$MODEL"
      [ -n "$RESOLVED_KEY" ] && export OPENAI_API_KEY="$RESOLVED_KEY"
      ;;
    opencode)
      export OPENAI_BASE_URL="$BASE_URL"
      export OPENAI_MODEL="$MODEL"
      [ -n "$RESOLVED_KEY" ] && export OPENAI_API_KEY="$RESOLVED_KEY"
      ;;
  esac
}
setup_env_for_backend

# --- 启动 Agent ---
PROMPT_FILE=$(mktemp)
echo "$PROMPT" > "$PROMPT_FILE"
trap "rm -f '$PROMPT_FILE'" EXIT

TARGET_DIR="$(cd "$CWD" && pwd)"

echo "[llm-router] 启动 $AGENT_NAME (backend=$CLI_BACKEND, provider=$PROVIDER, model=$MODEL, max_turns=$MAX_TURNS, cwd=$TARGET_DIR)" >&2

# 确定 timeout 命令（macOS 兼容）
TIMEOUT_CMD=""
if command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout ${TIMEOUT}s"
elif command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout ${TIMEOUT}s"
fi

# 按 CLI 后端选择执行命令
run_with_backend() {
  local prompt_content
  prompt_content="$(cat "$PROMPT_FILE")"

  case "$CLI_BACKEND" in
    claude)
      cd "$TARGET_DIR" && $TIMEOUT_CMD claude -p \
        --agent "$AGENT_NAME" \
        --max-turns "$MAX_TURNS" \
        --dangerously-skip-permissions \
        "$prompt_content" 2>&1
      ;;
    codex)
      cd "$TARGET_DIR" && $TIMEOUT_CMD codex exec \
        --agent "$AGENT_NAME" \
        --max-turns "$MAX_TURNS" \
        --approval-mode never \
        "$prompt_content" 2>&1
      ;;
    opencode)
      cd "$TARGET_DIR" && $TIMEOUT_CMD opencode exec \
        --agent "$AGENT_NAME" \
        --max-turns "$MAX_TURNS" \
        "$prompt_content" 2>&1
      ;;
    *)
      echo "[llm-router] 不支持的后端: $CLI_BACKEND" >&2
      return 10
      ;;
  esac
}

OUTPUT=$(run_with_backend) || {
  EXIT_CODE=$?
  echo "[llm-router] $AGENT_NAME 执行失败 (backend=$CLI_BACKEND, exit=$EXIT_CODE)" >&2
  echo "$OUTPUT" >&2
  exit 1
}

# 输出结果（Pilot 会解析）
# 首行为模型标识，Pilot 据此记录 execution_log.model
echo "[llm-router:model] $MODEL"
echo "$OUTPUT"
