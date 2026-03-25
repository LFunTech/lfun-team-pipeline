#!/bin/bash
# install.sh — lfun-team-pipeline installer
# Installs agents, templates, and the `team` CLI command.
#
# Usage:
#   bash install.sh                    # normal install (Claude Code only)
#   bash install.sh --update           # update existing installation
#   bash install.sh --all-platforms    # install to all detected platforms (CC/Codex/Cursor/OpenCode)

set -euo pipefail

VERSION="6.5"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="$REPO_DIR/agents"
AGENTS_DST="$HOME/.claude/agents"
TEMPLATES_DST="$HOME/.local/share/team-pipeline"
BIN_DIR="$HOME/.local/bin"
TEAM_CMD="$BIN_DIR/team"
DIST_DIR="$REPO_DIR/dist"

UPDATE_MODE=""
ALL_PLATFORMS=false
for arg in "$@"; do
  case "$arg" in
    --update) UPDATE_MODE="--update" ;;
    --all-platforms) ALL_PLATFORMS=true ;;
  esac
done

print_header() {
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║       lfun-team-pipeline  v${VERSION}  installer        ║"
  echo "║       Multi-Platform Agent Delivery Pipeline         ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""
}

# Install agents from a dist directory to a target directory
install_agents_to() {
  local src_dir="$1"
  local dst_dir="$2"
  local platform_label="$3"
  local ext="${4:-.md}"

  mkdir -p "$dst_dir"

  local existing
  existing=$(find "$dst_dir" -maxdepth 1 -name "*${ext}" 2>/dev/null | wc -l)
  if [ "$existing" -gt 0 ] && [ "$UPDATE_MODE" != "--update" ]; then
    local backup="$dst_dir.backup.$(date +%Y%m%d%H%M%S)"
    echo "    ⚠  Backing up $existing existing agents → $backup"
    cp -r "$dst_dir" "$backup"
  fi

  local count=0
  while IFS= read -r f; do
    cp "$f" "$dst_dir/$(basename "$f")"
    count=$((count + 1))
  done < <(find "$src_dir" -maxdepth 1 -name "*${ext}" | sort)

  echo "    ✓ $platform_label: $count agents installed → $dst_dir"
}

print_header

if [ ! -d "$AGENTS_SRC" ]; then
  echo "  ❌ agents/ directory not found. Run this script from the repo root."
  exit 1
fi

# ── 1. Agent handling ──────────────────────────────────────────────────
# New architecture: agents are persisted per-repo via `team init --platform <x>`.
# Global install only stores agent sources + transpiler for use by `team init/migrate`.
# Legacy global install (to ~/.claude/agents/ etc.) is kept behind --all-platforms for backward compat.

if [ "$ALL_PLATFORMS" = true ]; then
  echo "▶ Step 1/4 — Building agents for all platforms (legacy global install)"
  echo ""

  if ! python3 "$REPO_DIR/scripts/build-agents.py" --output "$DIST_DIR" 2>&1; then
    echo "  ❌ Agent transpiler failed"
    exit 1
  fi
  echo ""

  DETECTED_PLATFORMS=("cc")
  if command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; then
    DETECTED_PLATFORMS+=("codex")
  fi
  if [ -d "$HOME/.cursor" ]; then
    DETECTED_PLATFORMS+=("cursor")
  fi
  if command -v opencode &>/dev/null || [ -d "$HOME/.config/opencode" ]; then
    DETECTED_PLATFORMS+=("opencode")
  fi

  echo "  Detected platforms: ${DETECTED_PLATFORMS[*]}"
  echo ""

  for platform in "${DETECTED_PLATFORMS[@]}"; do
    case "$platform" in
      cc)
        install_agents_to "$DIST_DIR/cc" "$HOME/.claude/agents" "Claude Code" ".md"
        ;;
      codex)
        install_agents_to "$DIST_DIR/codex" "$HOME/.codex/agents" "Codex" ".toml"
        ;;
      cursor)
        install_agents_to "$DIST_DIR/cursor" "$HOME/.cursor/agents" "Cursor" ".md"
        ;;
      opencode)
        mkdir -p "$HOME/.config/opencode/agents"
        install_agents_to "$DIST_DIR/opencode" "$HOME/.config/opencode/agents" "OpenCode" ".md"
        ;;
    esac
  done

  echo ""
  echo "  ℹ  Global agents installed for backward compatibility."
  echo "     Preferred: use 'team init --platform <x>' to persist agents per-repo."

else
  # Default: install CC agents globally (backward compatible) + agent sources for transpiler
  echo "▶ Step 1/4 — Installing CC agents to $AGENTS_DST"

  mkdir -p "$AGENTS_DST"

  EXISTING=$(find "$AGENTS_DST" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l)
  if [ "$EXISTING" -gt 0 ] && [ "$UPDATE_MODE" != "--update" ]; then
    BACKUP_DIR="$AGENTS_DST.backup.$(date +%Y%m%d%H%M%S)"
    echo "  ⚠  Backing up $EXISTING existing agents → $BACKUP_DIR"
    cp -r "$AGENTS_DST" "$BACKUP_DIR"
  fi

  INSTALLED=0
  while IFS= read -r f; do
    cp "$f" "$AGENTS_DST/$(basename "$f")"
    INSTALLED=$((INSTALLED + 1))
  done < <(find "$AGENTS_SRC" -maxdepth 1 -name "*.md" | sort)

  echo "  ✓ $INSTALLED CC agents installed globally"
  echo "  ℹ  For other platforms: use 'team init --platform <x>' per-repo"
fi

# ── 2. Copy templates to ~/.local/share/team-pipeline/ ──────────────
echo ""
echo "▶ Step 2/4 — Installing templates to $TEMPLATES_DST"

if [ -d "$TEMPLATES_DST" ] && [ "$(ls -A "$TEMPLATES_DST" 2>/dev/null)" ]; then
  TMPL_BACKUP="${TEMPLATES_DST}.pre-upgrade.$(date +%Y%m%d%H%M%S)"
  cp -r "$TEMPLATES_DST" "$TMPL_BACKUP"
  echo "  ✓ Old templates backed up → $TMPL_BACKUP"
fi

mkdir -p "$TEMPLATES_DST"
if cp -r "$REPO_DIR/templates/." "$TEMPLATES_DST/"; then
  echo "  ✓ Pipeline templates installed"
  # Clean up backup on success
  [ -n "${TMPL_BACKUP:-}" ] && [ -d "${TMPL_BACKUP:-}" ] && rm -rf "$TMPL_BACKUP"
else
  echo "  ❌ Template install failed"
  if [ -n "${TMPL_BACKUP:-}" ] && [ -d "${TMPL_BACKUP:-}" ]; then
    rm -rf "$TEMPLATES_DST"
    mv "$TMPL_BACKUP" "$TEMPLATES_DST"
    echo "  ✓ Restored from backup"
  fi
  exit 1
fi

# ── 3. Install `team` CLI to ~/.local/bin/ ───────────────────────────
echo ""
echo "▶ Step 3/4 — Installing \`team\` command to $BIN_DIR"

mkdir -p "$BIN_DIR"
cat > "$TEAM_CMD" << 'TEAM_SCRIPT'
#!/bin/bash
# team — lfun-team-pipeline CLI
set -euo pipefail

VERSION="6.5"
TEAM_HOME="$HOME/.local/share/team-pipeline"

usage() {
  echo ""
  echo "  lfun-team-pipeline v${VERSION}"
  echo ""
  echo "  Usage: team <command>"
  echo ""
  echo "  Commands:"
  echo "    init [--platform <cc|codex|cursor|opencode>]"
  echo "              Initialize pipeline (agents persisted to .pipeline/agents/)"
  echo "    status    Show current pipeline execution progress"
  echo "    run       Auto-run pipeline batches until done or intervention needed"
  echo "    migrate <cc|codex|cursor|opencode>"
  echo "              Switch agents to another platform (replaces .pipeline/agents/)"
  echo "    issue run <number> [--repo <owner/repo>]"
  echo "              将 GitHub Issue 转为单提案流水线并执行"
  echo "    watch-issues [--repo <owner/repo>] [--interval <sec>] [--max-workers <n>] [--labels a,b] [--exclude-labels x,y] [--dry-run] [--once]"
  echo "              轮询 GitHub Issue 队列并自动调度处理"
  echo "    upgrade   Upgrade playbook + autosteps in-place (preserves state)"
  echo "    repair    Restore pipeline runtime files in-place (preserves state/artifacts)"
  echo "    doctor    Check whether runtime guard files are up to date"
  echo "    replan    Re-plan the proposal queue (keeps completed work)"
  echo "    scan      Scan codebase for components and detect duplicates"
  echo "    version   Print version"
  echo "    update    Re-run installer to update agents and templates"
  echo ""
  echo "  Examples:"
  echo "    cd my-project && team init --platform codex"
  echo "    team run"
  echo "    team migrate cursor"
  echo "    team issue run 123"
  echo "    team watch-issues --once"
  echo "    team status"
  echo "    team migrate codex              # migrate current project to Codex"
  echo "    team migrate cursor --dry-run   # preview Cursor migration"
  echo ""
}

detect_platform() {
  if command -v claude &>/dev/null; then echo "cc"
  elif command -v codex &>/dev/null; then echo "codex"
  elif [ -d "$HOME/.cursor" ]; then echo "cursor"
  elif command -v opencode &>/dev/null; then echo "opencode"
  else echo "cc"
  fi
}

platform_label() {
  case "$1" in
    cc)       echo "Claude Code" ;;
    codex)    echo "Codex" ;;
    cursor)   echo "Cursor" ;;
    opencode) echo "OpenCode" ;;
    *)        echo "$1" ;;
  esac
}

platform_ext() {
  case "$1" in
    codex) echo ".toml" ;;
    *)     echo ".md" ;;
  esac
}

run_tui_with_auto_submit() {
  if [ "$#" -lt 2 ]; then
    echo "  ❌ run_tui_with_auto_submit 用法: run_tui_with_auto_submit '<prompt>' <command...>" >&2
    return 1
  fi

  local auto_prompt="$1"
  shift

  python3 - "$@" <<'PY'
import os, sys, select, signal, termios, tty, fcntl, time, subprocess

cmd = sys.argv[1:]
stdout_fd = sys.stdout.fileno()
prompt = os.environ.get("TEAM_TUI_AUTO_PROMPT", "")

if not cmd:
    sys.stderr.write("missing command\n")
    sys.exit(2)

try:
    tty_fd = os.open("/dev/tty", os.O_RDWR)
except OSError:
    tty_fd = None

if tty_fd is None or not os.isatty(tty_fd):
    sys.stderr.write(
        "\n  ❌  需要在真实终端中运行交互式会话。\n"
        "     请直接在 shell 中执行 team run。\n\n"
    )
    sys.exit(1)

saved_tty = termios.tcgetattr(tty_fd)

def resize_pty(master_fd):
    try:
        ws = fcntl.ioctl(stdout_fd, termios.TIOCGWINSZ, b'\x00' * 8)
        fcntl.ioctl(master_fd, termios.TIOCSWINSZ, ws)
    except Exception:
        pass

def child_setup():
    os.setsid()
    try:
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    except Exception:
        pass

master_fd, slave_fd = os.openpty()
resize_pty(master_fd)
proc = subprocess.Popen(
    cmd,
    stdin=slave_fd,
    stdout=slave_fd,
    stderr=slave_fd,
    close_fds=True,
    preexec_fn=child_setup,
)
os.close(slave_fd)

prompt_injected = False
submit_sent = False
quit_sent = False
t0 = time.monotonic()
t_last_out = t0
exit_code = 0
prompt_sent_at = None
exit_seen_at = None
buf = b""
track_exit = False

def on_winch(sig, frame):
    resize_pty(master_fd)

signal.signal(signal.SIGWINCH, on_winch)
tty.setraw(tty_fd)

try:
    while True:
        try:
            r, _, _ = select.select([master_fd, tty_fd], [], [], 0.2)
        except (select.error, ValueError):
            break

        now = time.monotonic()
        # 先注入文本，再单独发一次回车；避免“文本出现了但回车没触发提交”。
        if not prompt_injected and (
            (now - t_last_out > 2.5 and now - t0 > 1.0) or now - t0 > 6.0
        ):
            if prompt:
                os.write(master_fd, prompt.encode("utf-8"))
            prompt_injected = True
            prompt_sent_at = now

        if prompt_injected and not submit_sent and prompt_sent_at is not None and now - prompt_sent_at >= 0.35:
            os.write(master_fd, b"\r")
            submit_sent = True
            prompt_sent_at = now
            buf = b""

        # 只有在本轮 prompt 真正提交后一段时间，才开始监听新的 [EXIT]。
        # 避免恢复旧会话时把历史消息中的 [EXIT] 误判为本轮完成。
        if submit_sent and not track_exit and prompt_sent_at is not None and now - prompt_sent_at >= 2.0:
            track_exit = True
            buf = b""

        # 检测到 [EXIT] 后，给 TUI 一点时间落盘，再自动退出进入下一轮。
        if exit_seen_at is not None and not quit_sent and now - exit_seen_at >= 1.0:
            os.write(master_fd, b"/quit\r")
            quit_sent = True

        # 若 /quit 未能让进程退出，则强制结束，避免卡住外层循环。
        if exit_seen_at is not None and quit_sent and now - exit_seen_at >= 4.0 and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=1)
            except Exception:
                try:
                    proc.kill()
                    proc.wait(timeout=1)
                except Exception:
                    pass
            exit_code = proc.returncode or 0
            break

        for fd in r:
            if fd == master_fd:
                try:
                    data = os.read(master_fd, 4096)
                except OSError:
                    data = b''
                if data:
                    os.write(stdout_fd, data)
                    t_last_out = time.monotonic()
                    if track_exit and exit_seen_at is None:
                        buf += data
                        if len(buf) > 16384:
                            buf = buf[-16384:]
                        if b"[EXIT]" in buf:
                            exit_seen_at = time.monotonic()
            else:
                try:
                    data = os.read(tty_fd, 1024)
                except OSError:
                    data = b''
                if data:
                    os.write(master_fd, data)

        if proc.poll() is not None:
            exit_code = proc.returncode or 0
            break

    # 进程退出后尽量把剩余输出刷完。
    while True:
        try:
            data = os.read(master_fd, 4096)
        except OSError:
            break
        if not data:
            break
        os.write(stdout_fd, data)
finally:
    termios.tcsetattr(tty_fd, termios.TCSADRAIN, saved_tty)
    try:
        os.close(master_fd)
    except Exception:
        pass
    try:
        os.close(tty_fd)
    except Exception:
        pass
    if proc.poll() is None:
        try:
            proc.wait(timeout=1)
        except Exception:
            pass

sys.exit(exit_code)
PY
}

opencode_batch_mode() {
  python3 - <<'PY'
import json
import os

state_path = '.pipeline/state.json'
config_path = '.pipeline/config.json'
env_mode = os.environ.get('TEAM_OPENCODE_INTERACTION_MODE', '').strip().lower()

if not os.path.exists(state_path):
    print('tui-initial')
    raise SystemExit

with open(state_path, 'r', encoding='utf-8') as f:
    state = json.load(f)

phase = state.get('current_phase', '')
status = state.get('status', 'running')
dep = state.get('depend_collector_result', {})
unfilled = len(dep.get('unfilled_deps', []))

if phase == 'ALL-COMPLETED' or status == 'completed':
    print('done')
    raise SystemExit
if status == 'escalation':
    print('escalation')
    raise SystemExit
if unfilled > 0:
    print('pause')
    raise SystemExit

autonomous_mode = False
interaction_mode = 'hybrid'
if os.path.exists(config_path):
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
            autonomous_mode = bool(config.get('autonomous_mode', False))
            interaction_mode = str(
                config.get('opencode', {}).get('interaction_mode', 'hybrid')
            ).strip().lower() or 'hybrid'
    except Exception:
        autonomous_mode = False
        interaction_mode = 'hybrid'

if env_mode:
    interaction_mode = env_mode

if interaction_mode not in {'hybrid', 'tui', 'run'}:
    interaction_mode = 'hybrid'

if interaction_mode == 'tui':
    print('tui-initial' if not os.path.exists(state_path) else 'tui-continue')
    raise SystemExit

interactive_phases = {'system-planning'}
if not autonomous_mode:
    interactive_phases.update({'0.clarify', 'memory-consolidation'})

if phase in interactive_phases:
    print('tui-continue')
elif interaction_mode == 'run':
    print('run-continue')
else:
    print('run-continue')
PY
}

opencode_state_brief() {
  python3 - <<'PY'
import json
import os

PHASE_LABELS = {
    'initial': '初始化',
    'system-planning': '系统规划',
    'pick-next-proposal': '提案选取',
    'memory-load': '项目记忆加载',
    '0.clarify': '需求澄清',
    '0.5.requirement-check': '需求完整性检查',
    '1.design': '方案设计',
    'gate-a.design-review': '方案审核',
    '2.0a.repo-setup': '仓库初始化',
    '2.0b.depend-collect': '依赖与凭证收集',
    '2.plan': '任务细化',
    '2.1.assumption-check': '假设传播校验',
    'gate-b.plan-review': '计划审核',
    '2.5.contract-formalize': '契约形式化',
    '2.6.contract-validate-semantic': '契约语义校验',
    '2.7.contract-validate-schema': '契约 Schema 校验',
    '3.build': '并行实现',
    '3.0b.build-verify': '构建验证',
    '3.0d.duplicate-detect': '重复代码检测',
    '3.1.static-analyze': '静态分析',
    '3.2.diff-validate': 'Diff 校验',
    '3.3.regression-guard': '回归防护',
    '3.5.simplify': '代码精简',
    '3.6.simplify-verify': '精简后验证',
    'gate-c.code-review': '代码审查',
    '3.7.contract-compliance': '契约一致性检查',
    '4a.test': '功能测试',
    '4a.1.test-failure-map': '测试失败归因',
    '4.2.coverage-check': '覆盖率检查',
    '4b.optimize': '性能优化',
    'gate-d.test-review': '测试验收',
    'api-change-detect': 'API 变更检测',
    '5.document': '文档编写',
    '5.1.changelog-check': '变更日志检查',
    'gate-e.doc-review': '文档审核',
    '5.9.ci-push': 'CI 推送',
    '6.0.deploy-readiness': '部署就绪检查',
    '6.deploy': '部署执行',
    '7.monitor': '上线观测',
    'memory-consolidation': '项目记忆固化',
    'mark-proposal-completed': '提案完成标记',
    'ALL-COMPLETED': '全部完成',
    'none': '无',
    'unknown': '未知阶段',
}

STATUS_LABELS = {
    'not-started': '未开始',
    'running': '运行中',
    'completed': '已完成',
    'escalation': '需人工介入',
    'failed': '失败',
}

def fmt_phase(value: str) -> str:
    label = PHASE_LABELS.get(value, value)
    return f'{label} ({value})' if value not in ('none', 'unknown', 'initial') else label

def fmt_status(value: str) -> str:
    label = STATUS_LABELS.get(value, value)
    return f'{label} ({value})' if label != value else label

state_path = '.pipeline/state.json'
if not os.path.exists(state_path):
    print(f'phase={fmt_phase("initial")}|status={fmt_status("not-started")}|last={fmt_phase("none")}')
    raise SystemExit

with open(state_path, 'r', encoding='utf-8') as f:
    state = json.load(f)

phase = state.get('current_phase', '') or 'unknown'
status = state.get('status', 'running') or 'running'
last = state.get('last_completed_phase') or 'none'
print(f'phase={fmt_phase(phase)}|status={fmt_status(status)}|last={fmt_phase(last)}')
PY
}

print_opencode_banner() {
  local title="$1"
  echo ""
  echo "  ===== ${title} ====="
}

print_opencode_state() {
  local label="$1"
  local state_line
  state_line=$(opencode_state_brief 2>/dev/null || echo "phase=unknown|status=unknown|last=unknown")
  local phase status last
  phase=$(printf '%s' "$state_line" | python3 -c "import sys; s=sys.stdin.read().strip(); parts=dict(item.split('=',1) for item in s.split('|') if '=' in item); print(parts.get('phase','未知阶段'))")
  status=$(printf '%s' "$state_line" | python3 -c "import sys; s=sys.stdin.read().strip(); parts=dict(item.split('=',1) for item in s.split('|') if '=' in item); print(parts.get('status','未知状态'))")
  last=$(printf '%s' "$state_line" | python3 -c "import sys; s=sys.stdin.read().strip(); parts=dict(item.split('=',1) for item in s.split('|') if '=' in item); print(parts.get('last','未知阶段'))")
  echo "  ${label}: 当前阶段=${phase} | 状态=${status} | 上一完成阶段=${last}"
}

ensure_gh_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    echo "❌ gh 未认证。请先执行: gh auth login"
    exit 1
  fi
}

load_issue_automation_config() {
  python3 - <<'PY'
import json
import os

cfg = {
    'repo': '',
    'source_labels': '',
    'processing_label': 'pipeline:processing',
    'waiting_label': 'pipeline:waiting-user',
    'done_label': 'pipeline:done',
    'auto_close': False,
    'poll_interval_seconds': 30,
    'max_workers': 1,
    'worktree_dir': '.worktrees/issues',
}

path = '.pipeline/config.json'
if os.path.exists(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            user_cfg = json.load(f).get('issue_automation', {})
        if isinstance(user_cfg, dict):
            cfg.update({k: user_cfg[k] for k in user_cfg if k in cfg})
            if not cfg.get('source_labels') and user_cfg.get('inbox_label'):
                cfg['source_labels'] = user_cfg['inbox_label']
    except Exception:
        pass

print('|'.join([
    str(cfg.get('repo', '')),
    str(cfg.get('source_labels', '')),
    str(cfg.get('processing_label', 'pipeline:processing')),
    str(cfg.get('waiting_label', 'pipeline:waiting-user')),
    str(cfg.get('done_label', 'pipeline:done')),
    'true' if cfg.get('auto_close') else 'false',
    str(cfg.get('poll_interval_seconds', 30)),
    str(cfg.get('max_workers', 1)),
    str(cfg.get('worktree_dir', '.worktrees/issues')),
]))
PY
}

resolve_issue_repo() {
  local override="${1:-}"
  if [ -n "$override" ]; then
    printf '%s\n' "$override"
    return
  fi

  local cfg
  cfg=$(load_issue_automation_config 2>/dev/null || true)
  if [ -n "$cfg" ]; then
    local cfg_repo
    cfg_repo=$(printf '%s' "$cfg" | python3 -c "import sys; parts=sys.stdin.read().split('|'); print(parts[0] if parts else '')")
    if [ -n "$cfg_repo" ]; then
      printf '%s\n' "$cfg_repo"
      return
    fi
  fi

  gh repo view --json nameWithOwner --jq '.nameWithOwner'
}

ensure_issue_runtime_dirs() {
  mkdir -p .pipeline/issues/cache .pipeline/issues/results .pipeline/issues/logs
}

ensure_issue_label() {
  local repo="$1"
  local label="$2"
  local color="$3"
  local desc="$4"
  gh label create "$label" --repo "$repo" --color "$color" --description "$desc" >/dev/null 2>&1 || true
}

set_issue_processing_state() {
  local repo="$1"
  local issue_number="$2"
  local add_label="$3"
  shift 3
  local remove_labels=("$@")

  if [ -n "$add_label" ]; then
    gh issue edit "$issue_number" --repo "$repo" --add-label "$add_label" >/dev/null 2>&1 || true
  fi
  local remove_label
  for remove_label in "${remove_labels[@]}"; do
    [ -n "$remove_label" ] || continue
    gh issue edit "$issue_number" --repo "$repo" --remove-label "$remove_label" >/dev/null 2>&1 || true
  done
}

render_issue_worker_result() {
  python3 - "$1" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

status = data.get('result', 'unknown')
phase = data.get('phase', 'unknown')
title = data.get('issue_title', '')
url = data.get('issue_url', '')
worktree = data.get('worktree', '')

print(f"Issue #{data.get('issue_number')} {title}")
print(f"结果: {status}")
print(f"阶段: {phase}")
if url:
    print(f"URL: {url}")
if worktree:
    print(f"Worktree: {worktree}")
PY
}

build_issue_pipeline_files() {
  local issue_json="$1"
  local worktree="$2"
  local repo="$3"
  python3 - "$issue_json" "$worktree" "$repo" <<'PY'
import json
import os
import re
import sys
from datetime import datetime, timezone

issue_path, worktree, repo = sys.argv[1:4]
with open(issue_path, 'r', encoding='utf-8') as f:
    issue = json.load(f)

cfg_path = os.path.join(worktree, '.pipeline', 'config.json')
with open(cfg_path, 'r', encoding='utf-8') as f:
    cfg = json.load(f)

number = issue['number']
title = issue.get('title', '').strip() or f'Issue #{number}'
body = (issue.get('body') or '').strip()
labels = [item.get('name', '') for item in issue.get('labels', []) if item.get('name')]
comments = issue.get('comments', [])
issue_url = issue.get('url') or issue.get('html_url') or ''
project_name = cfg.get('project_name', 'PROJECT')
autonomous_mode = bool(cfg.get('autonomous_mode', False))

def compact_lines(text: str):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return lines[:8]

body_lines = compact_lines(body)
comment_lines = []
for comment in comments[:5]:
    author = ((comment.get('author') or {}).get('login') or (comment.get('authorAssociation') or 'unknown'))
    text = (comment.get('body') or '').strip().replace('\r', '')
    text = re.sub(r'\n{3,}', '\n\n', text)
    if len(text) > 300:
        text = text[:297] + '...'
    if text:
        comment_lines.append(f'- @{author}: {text}')

scope_parts = [f'基于 GitHub Issue #{number} 完成交付。']
if body_lines:
    scope_parts.append('Issue 描述要点：' + '；'.join(body_lines[:4]))

detail = {
    'user_stories': [f'作为维护者，我希望完成 Issue #{number}《{title}》中的需求。'],
    'business_rules': [f'以 GitHub Issue #{number} 的标题、正文、评论和标签为最高优先级输入。'],
    'acceptance_criteria': [
        f'最终实现满足 Issue #{number} 中描述的问题或需求。',
        f'完成后需要可向 GitHub Issue 回写处理结果。',
    ],
    'api_overview': [],
    'data_entities': [],
    'non_functional': [
        '在不破坏现有架构约束的前提下完成修改。',
    ],
}

for line in body_lines[:4]:
    detail['acceptance_criteria'].append(line)

proposal = {
    'id': f'ISSUE-{number}',
    'title': f'处理 Issue #{number}: {title}',
    'scope': ' '.join(scope_parts),
    'domains': ['Issue'],
    'depends_on': [],
    'status': 'pending',
    'parallel_group': 0,
    'detail': detail if autonomous_mode else {},
    'source_issue': {
        'repo': repo,
        'number': number,
        'url': issue_url,
        'labels': labels,
    },
}

queue = {
    'system_name': f'{project_name} Issue Intake',
    'source': {'type': 'github_issue', 'repo': repo, 'number': number, 'url': issue_url},
    'proposals': [proposal],
}

pipeline_id = f'issue-{number}-{datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")}'
state = {
    'pipeline_id': pipeline_id,
    'project_name': project_name,
    'current_phase': 'pick-next-proposal',
    'last_completed_phase': None,
    'status': 'running',
    'attempt_counts': {
        '0.clarify': 0, '0.5.requirement-check': 0, '1.design': 0, 'gate-a.design-review': 0,
        '2.0a.repo-setup': 0, '2.0b.depend-collect': 0, '2.plan': 0, '2.1.assumption-check': 0, 'gate-b.plan-review': 0,
        '2.5.contract-formalize': 0, '2.6.contract-validate-semantic': 0, '2.7.contract-validate-schema': 0,
        '3.build': 0, '3.0b.build-verify': 0, '3.0d.duplicate-detect': 0, '3.1.static-analyze': 0,
        '3.2.diff-validate': 0, '3.3.regression-guard': 0, '3.5.simplify': 0, '3.6.simplify-verify': 0,
        'gate-c.code-review': 0, '3.7.contract-compliance': 0, '4a.test': 0, '4a.1.test-failure-map': 0,
        '4.2.coverage-check': 0, '4b.optimize': 0, 'gate-d.test-review': 0, 'api-change-detect': 0,
        '5.document': 0, '5.1.changelog-check': 0, 'gate-e.doc-review': 0, '5.9.ci-push': 0,
        '6.0.deploy-readiness': 0, '6.deploy': 0, '7.monitor': 0, 'per_builder': {},
    },
    'conditional_agents': {'migrator': False, 'optimizer': False, 'translator': False},
    'phase_5_mode': 'full',
    'new_test_files': [],
    'phase_3_base_sha': None,
    'phase_3_worktrees': {},
    'phase_3_branches': {},
    'phase_3_wave_bases': {},
    'phase_3_conflict_files': [],
    'phase_3_main_branch': None,
    'phase_3_merge_order': [],
    'github_repo_created': False,
    'github_repo_url': None,
    'execution_log': [],
    'parallel_proposals': [],
    'parallel_base_sha': None,
    'parallel_base_branch': None,
    'parallel_worktrees': {},
    'parallel_branches': {},
    'parallel_merge_order': [],
    'parallel_completed': [],
    'parallel_precheck_report': None,
    'issue_context': {
        'repo': repo,
        'number': number,
        'title': title,
        'url': issue_url,
        'labels': labels,
        'autonomous_mode': autonomous_mode,
    },
}

artifacts_dir = os.path.join(worktree, '.pipeline', 'artifacts')
os.makedirs(artifacts_dir, exist_ok=True)
with open(os.path.join(worktree, '.pipeline', 'proposal-queue.json'), 'w', encoding='utf-8') as f:
    json.dump(queue, f, ensure_ascii=False, indent=2)
with open(os.path.join(worktree, '.pipeline', 'state.json'), 'w', encoding='utf-8') as f:
    json.dump(state, f, ensure_ascii=False, indent=2)
with open(os.path.join(artifacts_dir, 'issue-runtime.json'), 'w', encoding='utf-8') as f:
    json.dump({'repo': repo, 'issue': issue, 'pipeline_id': pipeline_id}, f, ensure_ascii=False, indent=2)

context_lines = [
    f'# GitHub Issue 上下文：#{number} {title}',
    '',
    f'- 仓库：`{repo}`',
    f'- Issue：`#{number}`',
    f'- URL：{issue_url}',
    f'- 标签：{", ".join(labels) if labels else "无"}',
    f'- 自治模式：{autonomous_mode}',
    '',
    '## 正文',
    body or '(无正文)',
    '',
    '## 最近评论',
]
if comment_lines:
    context_lines.extend(comment_lines)
else:
    context_lines.append('- 暂无评论')
context_lines.extend([
    '',
    '## Pilot 执行要求',
    '- 将 GitHub Issue 标题、正文、评论、标签视为当前提案的事实来源。',
    '- 若信息不足，在允许交互的阶段主动澄清；若处于自治模式，尽量基于 issue 内容做最小合理假设。',
    '- 完成后需要产出可回写到 GitHub Issue 的处理结果摘要。',
])
with open(os.path.join(artifacts_dir, 'issue-context.md'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(context_lines).rstrip() + '\n')
PY
}

bootstrap_issue_workspace() {
  local root_dir="$1"
  local worktree="$2"
  local issue_json="$3"
  local repo="$4"

  mkdir -p "$worktree"
  rm -rf "$worktree/.pipeline"
  mkdir -p "$worktree/.pipeline"

  cp "$root_dir/.pipeline/config.json" "$worktree/.pipeline/config.json"
  cp "$root_dir/.pipeline/playbook.md" "$worktree/.pipeline/playbook.md"
  cp "$root_dir/.pipeline/project-memory.json" "$worktree/.pipeline/project-memory.json"
  [ -f "$root_dir/.pipeline/micro-changes.json" ] && cp "$root_dir/.pipeline/micro-changes.json" "$worktree/.pipeline/micro-changes.json"
  [ -f "$root_dir/.pipeline/llm-router.sh" ] && cp "$root_dir/.pipeline/llm-router.sh" "$worktree/.pipeline/llm-router.sh"
  mkdir -p "$worktree/.pipeline/autosteps" "$worktree/.pipeline/history" "$worktree/.pipeline/artifacts" "$worktree/.pipeline/agents"
  cp -R "$root_dir/.pipeline/autosteps/." "$worktree/.pipeline/autosteps/"
  cp -R "$root_dir/.pipeline/agents/." "$worktree/.pipeline/agents/"

  [ -f "$root_dir/AGENTS.md" ] && cp "$root_dir/AGENTS.md" "$worktree/AGENTS.md"
  [ -f "$root_dir/CLAUDE.md" ] && cp "$root_dir/CLAUDE.md" "$worktree/CLAUDE.md"
  [ -f "$root_dir/opencode.json" ] && cp "$root_dir/opencode.json" "$worktree/opencode.json"
  if [ -d "$root_dir/.opencode" ]; then
    mkdir -p "$worktree/.opencode"
    cp -R "$root_dir/.opencode/." "$worktree/.opencode/"
  fi
  if [ -d "$root_dir/.cursor/rules" ]; then
    mkdir -p "$worktree/.cursor/rules"
    cp -R "$root_dir/.cursor/rules/." "$worktree/.cursor/rules/"
  fi

  build_issue_pipeline_files "$issue_json" "$worktree" "$repo"
}

prepare_issue_worktree() {
  local issue_number="$1"
  local repo="$2"
  local worktree_dir="$3"
  local root_dir="$4"

  local issue_json=".pipeline/issues/cache/issue-${issue_number}.json"
  gh issue view "$issue_number" --repo "$repo" --json number,title,body,url,labels,comments,author > "$issue_json"

  local abs_worktree_dir="$root_dir/$worktree_dir"
  mkdir -p "$abs_worktree_dir"

  local worktree_path="$abs_worktree_dir/issue-${issue_number}"
  local branch="pipeline/issue-${issue_number}"
  if [ ! -d "$worktree_path/.git" ] && [ ! -f "$worktree_path/.git" ]; then
    rm -rf "$worktree_path"
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      git worktree add "$worktree_path" "$branch" >/dev/null
    else
      git worktree add -b "$branch" "$worktree_path" HEAD >/dev/null
    fi
  fi

  bootstrap_issue_workspace "$root_dir" "$worktree_path" "$issue_json" "$repo"
  printf '%s\n' "$worktree_path"
}

write_issue_worker_result() {
  local result_file="$1"
  local result="$2"
  local phase="$3"
  local worktree="$4"
  local issue_number="$5"
  local issue_title="$6"
  local issue_url="$7"
  local log_file="${8:-}"
  python3 - "$result_file" "$result" "$phase" "$worktree" "$issue_number" "$issue_title" "$issue_url" "$log_file" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

path, result, phase, worktree, issue_number, issue_title, issue_url, log_file = sys.argv[1:9]
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w', encoding='utf-8') as f:
    json.dump({
        'result': result,
        'phase': phase,
        'worktree': worktree,
        'issue_number': int(issue_number),
        'issue_title': issue_title,
        'issue_url': issue_url,
        'log_file': log_file,
        'updated_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'github_feedback_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'github_feedback_written': True,
    }, f, ensure_ascii=False, indent=2)
PY
}

generate_agents_for_platform() {
  local platform="$1"
  local dest_dir="$2"
  local transpiler="$TEAM_HOME/scripts/build-agents.py"
  local agents_src="$TEAM_HOME/agents"

  if [ ! -f "$transpiler" ]; then
    echo "  ❌ Transpiler not found: $transpiler" >&2
    return 1
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  if ! python3 "$transpiler" --platforms "$platform" --output "$tmpdir" --agents-dir "$agents_src" >/dev/null 2>&1; then
    echo "  ❌ Transpiler failed for platform: $platform" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  mkdir -p "$dest_dir"
  rm -f "$dest_dir"/*.md "$dest_dir"/*.toml 2>/dev/null

  local ext
  ext=$(platform_ext "$platform")
  local count=0
  for f in "$tmpdir/$platform/"*"$ext"; do
    [ -f "$f" ] || continue
    cp "$f" "$dest_dir/$(basename "$f")"
    count=$((count + 1))
  done

  rm -rf "$tmpdir"
  echo "$count"
}

# Generate AGENTS.md with embedded pilot instructions for codex/opencode.
# CC/Cursor use CLAUDE.md for context and load pilot via --agent flag, so
# their AGENTS.md stays as a lightweight overview.
generate_agents_md_with_pilot() {
  local platform="$1"
  local base_agents_md="$TEAM_HOME/AGENTS.md"

  case "$platform" in
    codex|opencode) ;;
    *) return 0 ;;
  esac

  if [ ! -f "$base_agents_md" ]; then
    return 0
  fi

  local pilot_file=""
  case "$platform" in
    codex)    pilot_file=".pipeline/agents/pilot.toml" ;;
    opencode) pilot_file=".pipeline/agents/pilot.md" ;;
  esac

  cp "$base_agents_md" AGENTS.md

  if [ -f "$pilot_file" ]; then
    python3 -c "
import re, sys

platform = '$platform'
pilot_path = '$pilot_file'
content = open(pilot_path).read()

instructions = ''
if platform == 'codex':
    m = re.search(r'developer_instructions\s*=\s*\"\"\"(.*?)\"\"\"', content, re.DOTALL)
    if m:
        instructions = m.group(1).strip()
elif platform == 'opencode':
    if content.startswith('---'):
        end = content.index('---', 3) + 3
        instructions = content[end:].strip()
    else:
        instructions = content.strip()

if instructions:
    with open('AGENTS.md', 'a') as f:
        f.write('\n\n---\n\n')
        f.write(instructions)
        f.write('\n')
" 2>/dev/null && echo "  ✓ AGENTS.md (含 Pilot 指令)" || echo "  ⚠  AGENTS.md Pilot 指令追加失败" >&2
  fi
}

sync_opencode_project_files() {
  mkdir -p .opencode/agents
  rm -f .opencode/agents/*.md 2>/dev/null || true
  cp -R .pipeline/agents/. .opencode/agents/
  echo "  ✓ .opencode/agents/ synced from .pipeline/agents/"

  if [ ! -f "opencode.json" ]; then
    python3 - <<'PY'
import json

cfg = {
    "$schema": "https://opencode.ai/config.json",
    "instructions": ["AGENTS.md"],
}

with open('opencode.json', 'w', encoding='utf-8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
    echo "  ✓ opencode.json"
  else
    local opencode_json_state
    opencode_json_state="$(python3 - <<'PY'
import json
from pathlib import Path
path = Path('opencode.json')
try:
    cfg = json.loads(path.read_text(encoding='utf-8'))
except Exception:
    print('invalid')
    raise SystemExit(0)
if cfg.get('$schema') == 'https://opencode.ai/config.schema.json' and cfg.get('context') == ['AGENTS.md'] and 'instructions' not in cfg:
    cfg['$schema'] = 'https://opencode.ai/config.json'
    cfg['instructions'] = ['AGENTS.md']
    cfg.pop('context', None)
    path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('migrated')
elif cfg.get('$schema') == 'https://opencode.ai/config.json' and cfg.get('instructions') == ['AGENTS.md'] and 'context' not in cfg:
    print('ok')
else:
    print('custom')
PY
 )"
    case "$opencode_json_state" in
      ok) echo "  ✓ opencode.json" ;;
      migrated) echo "  ✓ opencode.json migrated to instructions" ;;
      custom) echo "  ⚠  opencode.json already exists, skipping" ;;
      invalid) echo "  ⚠  opencode.json exists but is invalid JSON, skipping" ;;
    esac
  fi
}

cmd_init() {
  if [ ! -d "$TEAM_HOME/.pipeline" ]; then
    echo "❌ Team pipeline not installed. Run: bash install.sh"
    exit 1
  fi

  # Parse --platform argument
  local platform="${PIPELINE_PLATFORM:-}"
  local next_is_platform=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --platform=*) platform="${1#*=}" ;;
      --platform)   next_is_platform=true ;;
      cc|codex|cursor|opencode)
        if [ "$next_is_platform" = true ] || [ -z "$platform" ]; then
          platform="$1"
          next_is_platform=false
        fi ;;
      *) next_is_platform=false ;;
    esac
    shift
  done

  # Auto-detect if not specified
  if [ -z "$platform" ]; then
    platform=$(detect_platform)
  fi

  local label
  label=$(platform_label "$platform")

  echo ""
  echo "  Initializing lfun-team-pipeline in: $(pwd)"
  echo "  Target platform: $label"
  echo ""

  # Track if .pipeline/ is newly created (for cleanup on failure)
  local is_fresh=false
  if [ ! -d ".pipeline" ]; then
    is_fresh=true
  fi

  _init_cleanup() {
    if [ "$is_fresh" = true ] && [ -d ".pipeline" ]; then
      echo "  ⚠  Cleaning up failed initialization..."
      rm -rf .pipeline
      echo "  ✓ .pipeline/ removed"
    fi
  }
  trap '_init_cleanup' ERR

  # ── 1. Platform-agnostic files ──────────────────────────────
  mkdir -p .pipeline/autosteps .pipeline/artifacts .pipeline/history .pipeline/agents

  if [ -f ".pipeline/config.json" ]; then
    echo "  ⚠  .pipeline/config.json already exists, skipping"
  else
    cp "$TEAM_HOME/.pipeline/config.json" .pipeline/config.json
    echo "  ✓ .pipeline/config.json"
  fi

  cp "$TEAM_HOME/.pipeline/playbook.md" .pipeline/playbook.md
  echo "  ✓ .pipeline/playbook.md"

  if [ -f ".pipeline/project-memory.json" ]; then
    echo "  ⚠  .pipeline/project-memory.json already exists, skipping"
  else
    cp "$TEAM_HOME/.pipeline/project-memory.json" .pipeline/project-memory.json
    echo "  ✓ .pipeline/project-memory.json"
  fi

  if [ -f ".pipeline/micro-changes.json" ]; then
    echo "  ⚠  .pipeline/micro-changes.json already exists, skipping"
  else
    cp "$TEAM_HOME/.pipeline/micro-changes.json" .pipeline/micro-changes.json
    echo "  ✓ .pipeline/micro-changes.json"
  fi

  STEP_COUNT=0
  while IFS= read -r f; do
    dest=".pipeline/autosteps/$(basename "$f")"
    cp "$f" "$dest"
    STEP_COUNT=$((STEP_COUNT + 1))
  done < <(find "$TEAM_HOME/.pipeline/autosteps" \( -name "*.sh" -o -name "*.py" \) | sort)
  echo "  ✓ .pipeline/autosteps/ ($STEP_COUNT scripts)"

  if [ -f "$TEAM_HOME/.pipeline/llm-router.sh" ]; then
    cp "$TEAM_HOME/.pipeline/llm-router.sh" .pipeline/llm-router.sh
    chmod +x .pipeline/llm-router.sh
    echo "  ✓ .pipeline/llm-router.sh"
  fi

  # ── 2. Platform-specific agents → .pipeline/agents/ ─────────
  local agent_count
  agent_count=$(generate_agents_for_platform "$platform" ".pipeline/agents")
  if [ -n "$agent_count" ] && [ "$agent_count" -gt 0 ] 2>/dev/null; then
    echo "  ✓ .pipeline/agents/ ($agent_count agents for $label)"
  else
    echo "  ⚠  Agent generation failed, falling back to CC format"
    # Fallback: copy raw CC agents
    local raw_agents="$TEAM_HOME/../agents"
    [ -d "$raw_agents" ] || raw_agents="$TEAM_HOME/agents"
    if [ -d "$raw_agents" ]; then
      for f in "$raw_agents"/*.md; do
        [ -f "$f" ] || continue
        cp "$f" ".pipeline/agents/$(basename "$f")"
      done
      echo "  ✓ .pipeline/agents/ (CC fallback)"
    fi
  fi

  # Record platform in config.json
  if [ -f ".pipeline/config.json" ]; then
    python3 -c "
import json, sys
try:
    c = json.load(open('.pipeline/config.json'))
    mr = c.setdefault('model_routing', {})
    mr['cli_backend'] = '$platform' if '$platform' != 'cc' else 'auto'
    with open('.pipeline/config.json', 'w') as f:
        json.dump(c, f, indent=2, ensure_ascii=False)
except Exception:
    pass
" 2>/dev/null
  fi

  # ── 3. Platform-specific context files ──────────────────────
  case "$platform" in
    cc|cursor)
      if [ ! -f "CLAUDE.md" ]; then
        cp "$TEAM_HOME/CLAUDE.md" CLAUDE.md
        echo "  ✓ CLAUDE.md"
      fi
      ;;
  esac

  case "$platform" in
    codex|opencode)
      if [ ! -f "AGENTS.md" ]; then
        generate_agents_md_with_pilot "$platform"
      else
        echo "  ⚠  AGENTS.md already exists, skipping"
      fi
      ;;
  esac

  if [ "$platform" = "opencode" ]; then
    sync_opencode_project_files
  fi

  case "$platform" in
    cursor)
      if [ -d "$TEAM_HOME/.cursor/rules" ]; then
        mkdir -p .cursor/rules
        cp "$TEAM_HOME/.cursor/rules/pipeline.md" .cursor/rules/pipeline.md 2>/dev/null || true
        echo "  ✓ .cursor/rules/pipeline.md"
      fi
      ;;
  esac

  echo ""
  echo "  ✅ Pipeline initialized for $label!"
  echo ""
  echo "     Next steps:"
  echo "     1. Edit .pipeline/config.json  ← set project_name and tech stack"
  echo "     2. Start: team run"
  case "$platform" in
    cc)       echo "        Or: claude --dangerously-skip-permissions --agent pilot" ;;
    codex)    echo "        Or: codex --full-auto" ;;
    cursor)   echo "        Or: Cursor Agent mode → /pilot" ;;
    opencode) echo "        Or: opencode run --agent build  (uses opencode.json + .opencode/agents/)" ;;
  esac
  echo ""
  echo "     Platform agents saved to: .pipeline/agents/"
  [ "$platform" = "opencode" ] && echo "     OpenCode project files: opencode.json, .opencode/agents/"
  echo "     Switch platform: team migrate <codex|cursor|opencode>"
  echo ""

  trap - ERR
}

cmd_version() {
  echo "lfun-team-pipeline v${VERSION}"
}

cmd_update() {
  echo ""
  echo "  To update, run install.sh from the team-creator git repository:"
  echo ""
  echo "    cd /path/to/team-creator && bash install.sh --update"
  echo ""
  echo "  This ensures agents and templates are copied from the latest source."
  echo ""
}

cmd_upgrade() {
  if [ ! -d "$TEAM_HOME/.pipeline" ]; then
    echo "❌ Team pipeline not installed. Run: bash install.sh"
    exit 1
  fi

  if [ ! -d ".pipeline" ]; then
    echo "❌ No .pipeline/ directory found. Run: team init"
    exit 1
  fi

  echo ""
  echo "  Upgrading lfun-team-pipeline in: $(pwd)"
  echo ""

  # ── Phase 1: Pre-flight — detect if migration is needed ──────────
  MIGRATE_SCRIPT="$TEAM_HOME/scripts/migrate-phase-names.py"
  NEEDS_MIGRATE=false
  if [ -f ".pipeline/config.json" ] && grep -q '"phase-[0-9]' .pipeline/config.json 2>/dev/null; then
    NEEDS_MIGRATE=true
  fi
  if [ -f ".pipeline/state.json" ] && grep -q '"phase-[0-9]' .pipeline/state.json 2>/dev/null; then
    NEEDS_MIGRATE=true
  fi

  # If migration is needed but script is missing, abort early
  if [ "$NEEDS_MIGRATE" = true ] && [ ! -f "$MIGRATE_SCRIPT" ]; then
    echo "  ❌ Phase name migration required but migration script not found."
    echo "     Expected: $MIGRATE_SCRIPT"
    echo ""
    echo "  Fix: Re-run installer first:"
    echo "    cd /path/to/lfun-team-pipeline && bash install.sh --update"
    echo "    cd $(pwd) && team upgrade"
    echo ""
    exit 1
  fi

  # ── Phase 2: Backup config/state (before anything is touched) ────
  BACKUP_TS=$(date +%Y%m%d%H%M%S)
  BACKUP_DIR=".pipeline/.upgrade-backup-${BACKUP_TS}"
  if [ "$NEEDS_MIGRATE" = true ]; then
    mkdir -p "$BACKUP_DIR"
    [ -f ".pipeline/config.json" ] && cp .pipeline/config.json "$BACKUP_DIR/"
    [ -f ".pipeline/state.json" ] && cp .pipeline/state.json "$BACKUP_DIR/"
    echo "  ✓ Backup saved to $BACKUP_DIR"
  fi

  # ── Phase 3: Migrate config/state FIRST (before template upgrade) ──
  #    Order matters: if migration fails, playbook is still old version,
  #    so the project stays consistent and usable.
  if [ "$NEEDS_MIGRATE" = true ]; then
    echo ""
    echo "  Migrating phase names (phase-X → X.semantic-name)..."
    MIGRATE_OK=true

    # Schema migration (execution_log field) — do this before phase rename
    if [ -f ".pipeline/state.json" ]; then
      python3 -c "
import json
s = json.load(open('.pipeline/state.json'))
if 'execution_log' not in s:
    s['execution_log'] = []
    json.dump(s, open('.pipeline/state.json', 'w'), ensure_ascii=False, indent=2)
    print('  ✓ state.json: added execution_log field')
" 2>/dev/null || true
    fi

    # Phase name migration
    if [ -f ".pipeline/config.json" ]; then
      if ! python3 "$MIGRATE_SCRIPT" --migrate-config .pipeline/config.json; then
        echo "  ❌ config.json migration failed"
        MIGRATE_OK=false
      fi
    fi

    if [ "$MIGRATE_OK" = true ] && [ -f ".pipeline/state.json" ]; then
      if ! python3 "$MIGRATE_SCRIPT" --migrate-state .pipeline/state.json; then
        echo "  ❌ state.json migration failed"
        MIGRATE_OK=false
      fi
    fi

    # Verify migration result
    if [ "$MIGRATE_OK" = true ]; then
      VERIFY_FAIL=false
      # Check no old-style names remain
      if [ -f ".pipeline/config.json" ] && grep -q '"phase-[0-9]' .pipeline/config.json 2>/dev/null; then
        echo "  ❌ Old phase names still present in config.json"
        VERIFY_FAIL=true
      fi
      if [ -f ".pipeline/state.json" ] && grep -q '"phase-[0-9]' .pipeline/state.json 2>/dev/null; then
        echo "  ❌ Old phase names still present in state.json"
        VERIFY_FAIL=true
      fi
      # Check valid JSON
      if [ -f ".pipeline/config.json" ] && ! python3 -c "import json; json.load(open('.pipeline/config.json'))" 2>/dev/null; then
        echo "  ❌ config.json is not valid JSON after migration"
        VERIFY_FAIL=true
      fi
      if [ -f ".pipeline/state.json" ] && ! python3 -c "import json; json.load(open('.pipeline/state.json'))" 2>/dev/null; then
        echo "  ❌ state.json is not valid JSON after migration"
        VERIFY_FAIL=true
      fi
      [ "$VERIFY_FAIL" = true ] && MIGRATE_OK=false
    fi

    # Rollback on failure — restore from backup, playbook NOT yet upgraded
    if [ "$MIGRATE_OK" = false ]; then
      echo ""
      echo "  ⚠  Rolling back config.json and state.json from backup..."
      [ -f "$BACKUP_DIR/config.json" ] && cp "$BACKUP_DIR/config.json" .pipeline/config.json
      [ -f "$BACKUP_DIR/state.json" ] && cp "$BACKUP_DIR/state.json" .pipeline/state.json
      echo ""
      echo "  ❌ Upgrade aborted: config/state migration failed, all files restored."
      echo "     Your project is unchanged and still usable with the old version."
      echo ""
      echo "  To retry manually:"
      echo "    python3 $MIGRATE_SCRIPT --migrate-config .pipeline/config.json"
      echo "    python3 $MIGRATE_SCRIPT --migrate-state .pipeline/state.json"
      echo "    team upgrade   # then retry"
      echo ""
      echo "  Backup kept at: $BACKUP_DIR"
      echo ""
      exit 1
    fi

    echo "  ✓ Phase names migrated successfully"
    # Backup kept until all phases complete (deleted at function end)
  else
    # No migration needed, still add execution_log if missing
    if [ -f ".pipeline/state.json" ]; then
      python3 -c "
import json
s = json.load(open('.pipeline/state.json'))
if 'execution_log' not in s:
    s['execution_log'] = []
    json.dump(s, open('.pipeline/state.json', 'w'), ensure_ascii=False, indent=2)
    print('  ✓ state.json: added execution_log field')
else:
    print('  ✓ state.json: already compatible')
" 2>/dev/null || true
    fi
    echo "  ✓ Phase names: already migrated"
  fi

  # ── Phase 4: Snapshot before overwriting files ─────────────────────
  # Ensure BACKUP_DIR exists even if migration was skipped
  if [ -z "${BACKUP_DIR:-}" ]; then
    BACKUP_TS=$(date +%Y%m%d%H%M%S)
    BACKUP_DIR=".pipeline/.upgrade-backup-${BACKUP_TS}"
  fi
  mkdir -p "$BACKUP_DIR"
  [ -f ".pipeline/playbook.md" ] && cp .pipeline/playbook.md "$BACKUP_DIR/" 2>/dev/null || true
  [ -f ".pipeline/llm-router.sh" ] && cp .pipeline/llm-router.sh "$BACKUP_DIR/" 2>/dev/null || true
  [ -f "CLAUDE.md" ] && cp CLAUDE.md "$BACKUP_DIR/CLAUDE.md.bak" 2>/dev/null || true
  [ -f "AGENTS.md" ] && cp AGENTS.md "$BACKUP_DIR/AGENTS.md.bak" 2>/dev/null || true
  [ -f "opencode.json" ] && cp opencode.json "$BACKUP_DIR/opencode.json.bak" 2>/dev/null || true
  [ -d ".opencode" ] && cp -r .opencode "$BACKUP_DIR/opencode-dir" 2>/dev/null || true
  [ -d ".pipeline/agents" ] && cp -r .pipeline/agents "$BACKUP_DIR/agents" 2>/dev/null || true

  # ── Phase 5: Upgrade template files ───────────────────────────────
  cp "$TEAM_HOME/.pipeline/playbook.md" .pipeline/playbook.md
  echo "  ✓ .pipeline/playbook.md upgraded"

  for ext in sh py; do cp "$TEAM_HOME/.pipeline/autosteps/"*."$ext" .pipeline/autosteps/ 2>/dev/null || true; done
  AUTOSTEP_COUNT=$(ls .pipeline/autosteps/*.sh .pipeline/autosteps/*.py 2>/dev/null | wc -l)
  echo "  ✓ $AUTOSTEP_COUNT autosteps upgraded"

  if [ -f "$TEAM_HOME/.pipeline/llm-router.sh" ]; then
    cp "$TEAM_HOME/.pipeline/llm-router.sh" .pipeline/llm-router.sh
    chmod +x .pipeline/llm-router.sh
    echo "  ✓ llm-router.sh upgraded"
  fi

  # Context files: backup old → write new (backup already saved above)
  if [ -f "$TEAM_HOME/CLAUDE.md" ]; then
    cp "$TEAM_HOME/CLAUDE.md" CLAUDE.md
    echo "  ✓ CLAUDE.md upgraded (backup in $BACKUP_DIR)"
  fi

  # Detect current platform for AGENTS.md generation
  local upgrade_platform="cc"
  if [ -f ".pipeline/config.json" ]; then
    upgrade_platform=$(python3 -c "
import json
c = json.load(open('.pipeline/config.json'))
print(c.get('model_routing',{}).get('cli_backend','cc'))
" 2>/dev/null || echo "cc")
    [ "$upgrade_platform" = "auto" ] && upgrade_platform="cc"
  fi

  case "$upgrade_platform" in
    codex|opencode)
      generate_agents_md_with_pilot "$upgrade_platform"
      echo "     (backup in $BACKUP_DIR)"
      ;;
    *)
      if [ -f "$TEAM_HOME/AGENTS.md" ]; then
        cp "$TEAM_HOME/AGENTS.md" AGENTS.md
        echo "  ✓ AGENTS.md upgraded (backup in $BACKUP_DIR)"
      fi
      ;;
  esac

  if [ -d "$TEAM_HOME/.cursor/rules" ]; then
    mkdir -p .cursor/rules
    cp "$TEAM_HOME/.cursor/rules/pipeline.md" .cursor/rules/pipeline.md 2>/dev/null || true
    echo "  ✓ .cursor/rules/pipeline.md upgraded"
  fi

  # ── Phase 6: Upgrade project-local agents (.pipeline/agents/) ─────
  if [ -d ".pipeline/agents" ]; then
    local current_platform="cc"
    if [ -f ".pipeline/config.json" ]; then
      current_platform=$(python3 -c "
import json
c = json.load(open('.pipeline/config.json'))
p = c.get('model_routing', {}).get('cli_backend', 'auto')
print(p if p not in ('auto', '') else 'cc')
" 2>/dev/null || echo "cc")
    fi
    if [ "$current_platform" = "cc" ] && ls .pipeline/agents/*.toml &>/dev/null; then
      current_platform="codex"
    fi

    local label
    label=$(platform_label "$current_platform")
    local agent_count
    agent_count=$(generate_agents_for_platform "$current_platform" ".pipeline/agents")
    if [ -n "$agent_count" ] && [ "$agent_count" -gt 0 ] 2>/dev/null; then
      echo "  ✓ .pipeline/agents/ upgraded ($agent_count agents for $label)"
    else
      echo "  ⚠  Agent upgrade failed — restoring from backup"
      if [ -d "$BACKUP_DIR/agents" ]; then
        rm -rf .pipeline/agents
        cp -r "$BACKUP_DIR/agents" .pipeline/agents
      fi
    fi
  else
    echo "  ℹ  No .pipeline/agents/ found (legacy project, using global agents)"
    echo "     To enable per-repo agents: team migrate <cc|codex|cursor|opencode>"
  fi

  if [ "$upgrade_platform" = "opencode" ]; then
    sync_opencode_project_files
  fi

  # ── Cleanup ───────────────────────────────────────────────────────
  rm -rf "$BACKUP_DIR"

  echo ""
  echo "  Preserved (not modified):"
  echo "    .pipeline/config.json"
  echo "    .pipeline/project-memory.json"
  echo "    .pipeline/micro-changes.json"
  echo "    .pipeline/proposal-queue.json"
  echo "    .pipeline/state.json"
  echo "    .pipeline/artifacts/*"
  echo ""

  echo "  ✅ Upgraded to v${VERSION}"
  echo ""
  echo "  Run 'team run' to continue from current phase."
  echo ""
}

cmd_repair() {
  if [ ! -d "$TEAM_HOME/.pipeline" ]; then
    echo "❌ Team pipeline not installed. Run: bash install.sh"
    exit 1
  fi

  if [ ! -d ".pipeline" ]; then
    echo "❌ No .pipeline/ directory found. Run: team init"
    exit 1
  fi

  echo ""
  echo "  Repairing lfun-team-pipeline in: $(pwd)"
  echo ""

  local BACKUP_TS
  BACKUP_TS=$(date +%Y%m%d%H%M%S)
  local BACKUP_DIR=".pipeline/.repair-backup-${BACKUP_TS}"
  mkdir -p "$BACKUP_DIR"

  [ -f ".pipeline/playbook.md" ] && cp .pipeline/playbook.md "$BACKUP_DIR/" 2>/dev/null || true
  [ -f ".pipeline/llm-router.sh" ] && cp .pipeline/llm-router.sh "$BACKUP_DIR/" 2>/dev/null || true
  [ -d ".pipeline/autosteps" ] && cp -r .pipeline/autosteps "$BACKUP_DIR/autosteps" 2>/dev/null || true
  [ -d ".pipeline/agents" ] && cp -r .pipeline/agents "$BACKUP_DIR/agents" 2>/dev/null || true
  [ -f "CLAUDE.md" ] && cp CLAUDE.md "$BACKUP_DIR/CLAUDE.md.bak" 2>/dev/null || true
  [ -f "AGENTS.md" ] && cp AGENTS.md "$BACKUP_DIR/AGENTS.md.bak" 2>/dev/null || true
  [ -f "opencode.json" ] && cp opencode.json "$BACKUP_DIR/opencode.json.bak" 2>/dev/null || true
  [ -d ".opencode" ] && cp -r .opencode "$BACKUP_DIR/opencode-dir" 2>/dev/null || true

  mkdir -p .pipeline/autosteps .pipeline/artifacts .pipeline/history

  cp "$TEAM_HOME/.pipeline/playbook.md" .pipeline/playbook.md
  echo "  ✓ .pipeline/playbook.md repaired"

  for ext in sh py; do cp "$TEAM_HOME/.pipeline/autosteps/"*."$ext" .pipeline/autosteps/ 2>/dev/null || true; done
  find .pipeline/autosteps -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true
  AUTOSTEP_COUNT=$(ls .pipeline/autosteps/*.sh .pipeline/autosteps/*.py 2>/dev/null | wc -l)
  echo "  ✓ $AUTOSTEP_COUNT autosteps repaired"

  if [ -f "$TEAM_HOME/.pipeline/llm-router.sh" ]; then
    cp "$TEAM_HOME/.pipeline/llm-router.sh" .pipeline/llm-router.sh
    chmod +x .pipeline/llm-router.sh
    echo "  ✓ .pipeline/llm-router.sh repaired"
  fi

  local repair_platform="cc"
  if [ -f ".pipeline/config.json" ]; then
    repair_platform=$(python3 -c "
import json
c = json.load(open('.pipeline/config.json'))
p = c.get('model_routing', {}).get('cli_backend', 'auto')
print(p if p not in ('auto', '') else 'cc')
" 2>/dev/null || echo "cc")
  fi
  if [ "$repair_platform" = "cc" ] && ls .pipeline/agents/*.toml &>/dev/null; then
    repair_platform="codex"
  fi
  local label
  label=$(platform_label "$repair_platform")

  if [ -d ".pipeline/agents" ]; then
    local agent_count
    agent_count=$(generate_agents_for_platform "$repair_platform" ".pipeline/agents")
    if [ -n "$agent_count" ] && [ "$agent_count" -gt 0 ] 2>/dev/null; then
      echo "  ✓ .pipeline/agents/ repaired ($agent_count agents for $label)"
    else
      echo "  ⚠  Agent repair failed — preserving current .pipeline/agents/"
    fi
  else
    echo "  ℹ  No .pipeline/agents/ found (legacy project, using global agents)"
  fi

  if [ -f "$TEAM_HOME/CLAUDE.md" ]; then
    cp "$TEAM_HOME/CLAUDE.md" CLAUDE.md
    echo "  ✓ CLAUDE.md repaired"
  fi

  case "$repair_platform" in
    codex|opencode)
      generate_agents_md_with_pilot "$repair_platform"
      echo "  ✓ AGENTS.md repaired"
      ;;
    *)
      if [ -f "$TEAM_HOME/AGENTS.md" ]; then
        cp "$TEAM_HOME/AGENTS.md" AGENTS.md
        echo "  ✓ AGENTS.md repaired"
      fi
      ;;
  esac

  if [ -d "$TEAM_HOME/.cursor/rules" ]; then
    mkdir -p .cursor/rules
    cp "$TEAM_HOME/.cursor/rules/pipeline.md" .cursor/rules/pipeline.md 2>/dev/null || true
    echo "  ✓ .cursor/rules/pipeline.md repaired"
  fi

  if [ "$repair_platform" = "opencode" ]; then
    sync_opencode_project_files
  fi

  echo ""
  echo "  Preserved (not modified):"
  echo "    .pipeline/config.json"
  echo "    .pipeline/project-memory.json"
  echo "    .pipeline/micro-changes.json"
  echo "    .pipeline/proposal-queue.json"
  echo "    .pipeline/state.json"
  echo "    .pipeline/artifacts/*"
  echo ""
  echo "  Backup saved to: $BACKUP_DIR"
  echo "  ✅ Repair complete"
  echo ""
  echo "  Run 'team status' or 'team run' to continue."
  echo ""
}

cmd_doctor() {
  if [ ! -d ".pipeline" ]; then
    echo "  ❌ .pipeline/ not found. Run: team init"
    return 1
  fi

  local checker=".pipeline/autosteps/runtime-guard-check.py"
  if [ ! -f "$checker" ]; then
    echo "  ❌ $checker missing"
    echo "     Run: team repair"
    return 1
  fi

  echo "  🔎 Checking runtime guard files..."
  echo ""
  if PIPELINE_DIR=.pipeline python3 "$checker"; then
    echo ""
    echo "  ✅ Runtime guard files are present and look current."
    return 0
  fi

  echo ""
  echo "  ⚠  Runtime guard check failed. Recommended: team repair"
  return 1
}

cmd_replan() {
  if [ ! -f ".pipeline/state.json" ]; then
    echo ""
    echo "  ❌ No pipeline found in current directory."
    echo "     Run: team init && team run"
    echo ""
    exit 1
  fi

  echo ""
  echo "  Re-planning: resetting pipeline to System Planning"
  echo ""

  # Archive current queue if present
  if [ -f ".pipeline/proposal-queue.json" ]; then
    BACKUP="proposal-queue.backup.$(date +%Y%m%d%H%M%S).json"
    cp .pipeline/proposal-queue.json ".pipeline/$BACKUP" 2>/dev/null || true
    echo "  ✓ Backed up current queue to .pipeline/$BACKUP"
    rm .pipeline/proposal-queue.json
    echo "  ✓ Removed current proposal queue"
  else
    echo "  ℹ  No existing proposal queue found; proceeding with state reset"
  fi

  python3 - <<'PY'
import json
from pathlib import Path

path = Path('.pipeline/state.json')
state = json.loads(path.read_text(encoding='utf-8'))
state['current_phase'] = 'system-planning'
state['last_completed_phase'] = None
state['status'] = 'running'
path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY
  echo "  ✓ State reset to system-planning"
  echo ""
  echo "  Note: Completed proposals are preserved in project-memory.json."
  echo "  The new plan will build on existing progress."
  echo ""
}

cmd_status() {
  local status_view="overview"
  local interactive="auto"
  while [ $# -gt 0 ]; do
    case "$1" in
      --view=*) status_view="${1#*=}" ;;
      --view) shift; status_view="${1:-overview}" ;;
      --interactive|-i) interactive=true ;;
      --plain|--no-interactive) interactive=false ;;
      overview|proposals|issues|execution|retries|all) status_view="$1" ;;
      *)
        echo "❌ 用法: team status [--interactive|--plain] [--view <overview|proposals|issues|execution|retries|all>]"
        return 1
        ;;
    esac
    shift || true
  done

  if [ "$interactive" = "auto" ]; then
    if [ -t 0 ] && [ -t 1 ] && [ -z "${TEAM_STATUS_INTERACTIVE_CHILD:-}" ] && [ "$status_view" = "overview" ]; then
      interactive=true
    else
      interactive=false
    fi
  fi

  if [ "$interactive" = true ] && [ "${TEAM_STATUS_INTERACTIVE_CHILD:-}" != "1" ]; then
    local views=(overview proposals issues execution retries)
    local current_index=0
    local i
    local cache_dir
    local proposals_expanded=false
    local issues_expanded=false
    local execution_expanded=false
    local retries_expanded=false
    local proposals_page=1
    local issues_page=1
    local execution_page=1
    local retries_page=1
    cache_dir=$(mktemp -d "${TMPDIR:-/tmp}/team-status.XXXXXX")
    trap 'rm -rf "$cache_dir"' RETURN
    render_status_view() {
      local target_view="$1"
      local expanded=""
      local target_file=""
      local target_page=1
      local term_lines=24
      term_lines=$(tput lines 2>/dev/null || echo 24)
      case "$target_view" in
        proposals)
          [ "$proposals_expanded" = true ] && expanded="proposals"
          target_page="$proposals_page"
          target_file="$cache_dir/${target_view}.${proposals_expanded}.${target_page}.txt"
          ;;
        issues)
          [ "$issues_expanded" = true ] && expanded="issues"
          target_page="$issues_page"
          target_file="$cache_dir/${target_view}.${issues_expanded}.${target_page}.txt"
          ;;
        execution)
          [ "$execution_expanded" = true ] && expanded="execution"
          target_page="$execution_page"
          target_file="$cache_dir/${target_view}.${execution_expanded}.${target_page}.txt"
          ;;
        retries)
          [ "$retries_expanded" = true ] && expanded="retries"
          target_page="$retries_page"
          target_file="$cache_dir/${target_view}.${retries_expanded}.${target_page}.txt"
          ;;
        *)
          target_file="$cache_dir/${target_view}.txt"
          ;;
      esac
      TEAM_STATUS_INTERACTIVE_CHILD=1 TEAM_STATUS_EXPANDED="$expanded" TEAM_STATUS_PAGE="$target_page" TEAM_STATUS_TERM_LINES="$term_lines" TEAM_STATUS_PAGINATE=1 "$0" status --view "$target_view" > "$target_file"
    }
    for i in "${!views[@]}"; do
      if [ "${views[$i]}" = "$status_view" ]; then
        current_index=$i
        break
      fi
    done

    render_status_view "${views[$current_index]}"
    for i in "${!views[@]}"; do
      if [ "$i" -ne "$current_index" ]; then
        render_status_view "${views[$i]}" &
      fi
    done

    while true; do
      printf '\033[2J\033[H'
      local current_view="${views[$current_index]}"
      local cache_file="$cache_dir/${current_view}.txt"
      case "$current_view" in
        proposals) cache_file="$cache_dir/${current_view}.${proposals_expanded}.${proposals_page}.txt" ;;
        issues) cache_file="$cache_dir/${current_view}.${issues_expanded}.${issues_page}.txt" ;;
        execution) cache_file="$cache_dir/${current_view}.${execution_expanded}.${execution_page}.txt" ;;
        retries) cache_file="$cache_dir/${current_view}.${retries_expanded}.${retries_page}.txt" ;;
      esac
      if [ ! -f "$cache_file" ]; then
        echo "  ⟳ 正在加载 ${current_view} ..."
        render_status_view "$current_view"
      fi
      cat "$cache_file"
      echo "  操作: Tab/右箭头=下一个  Shift-Tab/左箭头=上一个  n/p=翻页  q=退出  r=刷新当前视图  e=展开/收起清单"

      local key=""
      IFS= read -rsn1 key || break
      case "$key" in
        q|Q) break ;;
        r|R)
          rm -f "$cache_file"
          render_status_view "$current_view" &
          ;;
        e|E)
          case "$current_view" in
            proposals)
              proposals_expanded=$([ "$proposals_expanded" = true ] && echo false || echo true)
              proposals_page=1
              ;;
            issues)
              issues_expanded=$([ "$issues_expanded" = true ] && echo false || echo true)
              issues_page=1
              ;;
            execution)
              execution_expanded=$([ "$execution_expanded" = true ] && echo false || echo true)
              execution_page=1
              ;;
            retries)
              retries_expanded=$([ "$retries_expanded" = true ] && echo false || echo true)
              retries_page=1
              ;;
          esac
          ;;
        n|N)
          case "$current_view" in
            proposals) proposals_page=$((proposals_page + 1)) ;;
            issues) issues_page=$((issues_page + 1)) ;;
            execution) execution_page=$((execution_page + 1)) ;;
            retries) retries_page=$((retries_page + 1)) ;;
          esac
          ;;
        p|P)
          case "$current_view" in
            proposals) [ "$proposals_page" -gt 1 ] && proposals_page=$((proposals_page - 1)) ;;
            issues) [ "$issues_page" -gt 1 ] && issues_page=$((issues_page - 1)) ;;
            execution) [ "$execution_page" -gt 1 ] && execution_page=$((execution_page - 1)) ;;
            retries) [ "$retries_page" -gt 1 ] && retries_page=$((retries_page - 1)) ;;
          esac
          ;;
        $'\t') current_index=$(((current_index + 1) % ${#views[@]})) ;;
        $'\033')
          local rest=""
          IFS= read -rsn2 rest || true
          case "$rest" in
            '[C') current_index=$(((current_index + 1) % ${#views[@]})) ;;
            '[D') current_index=$(((current_index - 1 + ${#views[@]}) % ${#views[@]})) ;;
            '[Z') current_index=$(((current_index - 1 + ${#views[@]}) % ${#views[@]})) ;;
          esac
          ;;
      esac
    done
    echo ""
    return 0
  fi

  if [ ! -f ".pipeline/state.json" ]; then
    echo ""
    echo "  ❌ No pipeline found in current directory."
    echo "     Run: team init && team run"
    echo ""
    exit 1
  fi

  TEAM_STATUS_VIEW="$status_view" python3 - << 'PYEOF'
import json, os, sys
import subprocess
import re
from datetime import datetime, timezone

# ── ANSI colors ────────────────────────────────────────────────────
RESET  = "\033[0m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
GREEN  = "\033[32m"
YELLOW = "\033[33m"
RED    = "\033[31m"
CYAN   = "\033[36m"
BLUE   = "\033[34m"
WHITE  = "\033[37m"

def c(color, text): return f"{color}{text}{RESET}"

PHASE_LABELS = {
    'system-planning': '系统规划',
    'pick-next-proposal': '提案选取',
    'memory-load': '项目记忆加载',
    '0.clarify': '需求澄清',
    '0.5.requirement-check': '需求完整性检查',
    '1.design': '方案设计',
    'gate-a.design-review': '方案审核',
    '2.0a.repo-setup': '仓库初始化',
    '2.0b.depend-collect': '依赖与凭证收集',
    '2.plan': '任务细化',
    '2.1.assumption-check': '假设传播校验',
    'gate-b.plan-review': '计划审核',
    '2.5.contract-formalize': '契约形式化',
    '2.6.contract-validate-semantic': '契约语义校验',
    '2.7.contract-validate-schema': '契约 Schema 校验',
    '3.build': '并行实现',
    '3.0b.build-verify': '构建验证',
    '3.0d.duplicate-detect': '重复代码检测',
    '3.1.static-analyze': '静态分析',
    '3.2.diff-validate': 'Diff 校验',
    '3.3.regression-guard': '回归防护',
    '3.5.simplify': '代码精简',
    '3.6.simplify-verify': '精简后验证',
    'gate-c.code-review': '代码审查',
    '3.7.contract-compliance': '契约一致性检查',
    '4a.test': '功能测试',
    '4a.1.test-failure-map': '测试失败归因',
    '4.2.coverage-check': '覆盖率检查',
    '4b.optimize': '性能优化',
    'gate-d.test-review': '测试验收',
    'api-change-detect': 'API 变更检测',
    '5.document': '文档编写',
    '5.1.changelog-check': '变更日志检查',
    'gate-e.doc-review': '文档审核',
    '5.9.ci-push': 'CI 推送',
    '6.0.deploy-readiness': '部署就绪检查',
    '6.deploy': '部署执行',
    '7.monitor': '上线观测',
    'memory-consolidation': '项目记忆固化',
    'mark-proposal-completed': '提案完成标记',
    'ALL-COMPLETED': '全部完成',
}

def fmt_phase(value):
    if value in (None, '', '?', '-'):
        return '-'
    label = PHASE_LABELS.get(value)
    return f"{label} ({value})" if label else str(value)

def fmt_issue_result(value):
    mapping = {
        'done': ('已完成', GREEN, '✓'),
        'waiting': ('等待人工', YELLOW, '⏸'),
        'escalation': ('需人工介入', RED, '!'),
        'running': ('处理中', CYAN, '…'),
        'unknown': ('未知', DIM, '?'),
    }
    label, color, icon = mapping.get(value, (str(value), DIM, '?'))
    return label, color, icon

def fmt_ts(value):
    if not value:
        return '-'
    return str(value).replace('T', ' ').replace('Z', ' UTC')

def waiting_takeover_priority(item):
    phase = item.get('phase', '') or ''
    result = item.get('result', '') or ''
    priority_map = {
        '0.clarify': 1000,
        '2.0b.depend-collect': 900,
        'memory-consolidation': 800,
        'gate-d.test-review': 700,
        '6.0.deploy-readiness': 650,
    }
    score = priority_map.get(phase, 100)
    if result == 'escalation':
        score += 1200
    return (-score, item.get('updated_at', ''), item.get('issue_number', 0))

def parse_github_repo(remote_url):
    if not remote_url:
        return ''
    remote_url = remote_url.strip()
    m = re.search(r'github\.com[:/](.+?)(?:\.git)?$', remote_url)
    return m.group(1) if m else ''

def load_issue_cfg():
    cfg = {
        'repo': '',
        'source_labels': '',
        'processing_label': 'pipeline:processing',
        'waiting_label': 'pipeline:waiting-user',
        'done_label': 'pipeline:done',
    }
    cfg_path = '.pipeline/config.json'
    if os.path.exists(cfg_path):
        try:
            with open(cfg_path, 'r', encoding='utf-8') as f:
                issue_cfg = json.load(f).get('issue_automation', {})
            if isinstance(issue_cfg, dict):
                for key in cfg:
                    if key in issue_cfg:
                        cfg[key] = issue_cfg[key]
                if not cfg.get('source_labels') and issue_cfg.get('inbox_label'):
                    cfg['source_labels'] = issue_cfg['inbox_label']
        except Exception:
            pass
    return cfg

def detect_issue_repo(cfg):
    if cfg.get('repo'):
        return cfg['repo']
    try:
        remote = subprocess.check_output(
            ['git', 'remote', 'get-url', 'origin'], text=True, stderr=subprocess.DEVNULL
        ).strip()
        return parse_github_repo(remote)
    except Exception:
        return ''

def summarize_issue_queue_counts(items, cfg):
    if items is None:
        return None
    def extract_labels(raw_labels):
        labels = set()
        for lbl in raw_labels or []:
            if isinstance(lbl, dict):
                name = lbl.get('name', '')
            else:
                name = str(lbl)
            if name:
                labels.add(name)
        return labels
    source_labels = {x.strip().lower() for x in str(cfg.get('source_labels', '')).split(',') if x.strip()}
    queued = processing = waiting = done = 0
    for item in items:
        labels = extract_labels(item.get('labels', []))
        lower_labels = {x.lower() for x in labels}
        if source_labels and not (source_labels & lower_labels):
            continue
        state_name = str(item.get('state', 'OPEN')).lower()
        if state_name == 'closed':
            continue
        if cfg['processing_label'] in labels:
            processing += 1
        elif cfg['waiting_label'] in labels:
            waiting += 1
        elif cfg['done_label'] in labels:
            done += 1
        else:
            queued += 1
    return {'queued': queued, 'processing': processing, 'waiting': waiting, 'done': done}

def query_issue_queue_counts(repo, cfg):
    if not repo:
        return None
    try:
        raw = subprocess.check_output([
            'gh', 'issue', 'list',
            '--repo', repo,
            '--state', 'open',
            '--limit', '200',
            '--json', 'number,labels',
        ], text=True, stderr=subprocess.DEVNULL)
        items = json.loads(raw)
    except Exception:
        return None

    return summarize_issue_queue_counts(items, cfg)

def query_issue_items(repo, cfg):
    if not repo:
        return []
    try:
        raw = subprocess.check_output([
            'gh', 'issue', 'list',
            '--repo', repo,
            '--state', 'all',
            '--limit', '200',
            '--json', 'number,title,labels,createdAt,updatedAt,closedAt,state,url',
        ], text=True, stderr=subprocess.DEVNULL)
        items = json.loads(raw)
    except Exception:
        return []

    source_labels = {x.strip().lower() for x in str(cfg.get('source_labels', '')).split(',') if x.strip()}

    def score(labels):
        lower = {x.lower() for x in labels}
        s = 0
        if 'p0' in lower or 'critical' in lower or 'urgent' in lower or 'sev:critical' in lower:
            s += 1000
        if 'p1' in lower or 'high' in lower or 'priority:high' in lower:
            s += 700
        if 'bug' in lower or 'regression' in lower or 'hotfix' in lower:
            s += 400
        if 'security' in lower or 'security-fix' in lower:
            s += 350
        if 'feature' in lower or 'enhancement' in lower:
            s += 150
        return s

    result = []
    for item in items:
        labels = {lbl.get('name', '') for lbl in item.get('labels', [])}
        lower_labels = {x.lower() for x in labels}
        if source_labels and not (source_labels & lower_labels):
            continue
        state_name = str(item.get('state', 'OPEN')).lower()
        if state_name == 'closed' or cfg['done_label'] in labels:
            state = 'resolved'
        elif cfg['processing_label'] in labels:
            state = 'processing'
        elif cfg['waiting_label'] in labels:
            state = 'waiting'
        else:
            state = 'queued'
        result.append({
            'number': item.get('number', '?'),
            'title': item.get('title', ''),
            'url': item.get('url', ''),
            'labels': sorted(labels),
            'created_at': item.get('createdAt', ''),
            'updated_at': item.get('updatedAt', ''),
            'closed_at': item.get('closedAt', ''),
            'score': score(labels),
            'state': state,
        })

    result.sort(key=lambda x: ({'waiting': 0, 'processing': 1, 'queued': 2, 'resolved': 3}.get(x['state'], 9), -(x['score'] if x['state'] != 'resolved' else 0), x['closed_at'] if x['state'] == 'resolved' else '', x['updated_at'] if x['state'] != 'resolved' else '', x['number']), reverse=False)
    resolved = [x for x in result if x['state'] == 'resolved']
    unresolved = [x for x in result if x['state'] != 'resolved']
    resolved.sort(key=lambda x: (x['closed_at'] or x['updated_at'], x['number']), reverse=True)
    unresolved.sort(key=lambda x: ({'waiting': 0, 'processing': 1, 'queued': 2}.get(x['state'], 9), -x['score'], x['updated_at'], x['number']))
    return unresolved + resolved

page_number = max(1, int(os.environ.get('TEAM_STATUS_PAGE', '1') or '1'))
term_lines = max(20, int(os.environ.get('TEAM_STATUS_TERM_LINES', '24') or '24'))
paginate_mode = os.environ.get('TEAM_STATUS_PAGINATE', '') == '1'

def paginate_items(items, reserved_lines):
    if not paginate_mode:
        return items, 1, 1, len(items)
    per_page = max(5, term_lines - reserved_lines)
    total_pages = max(1, (len(items) + per_page - 1) // per_page)
    current_page = min(page_number, total_pages)
    start = (current_page - 1) * per_page
    end = start + per_page
    return items[start:end], current_page, total_pages, per_page

# ── Load state.json ────────────────────────────────────────────────
state = json.load(open(".pipeline/state.json"))
project   = state.get("project_name", os.path.basename(os.getcwd()))
phase     = state.get("current_phase", "?")
last_done = state.get("last_completed_phase", "-")
status    = state.get("status", "?")
pipeline_id = state.get("pipeline_id", "-")
cond      = state.get("conditional_agents", {})
attempts  = state.get("attempt_counts", {})

def print_panel(title, lines):
    print(c(BOLD + CYAN, f"  ╔══ {title} ══"))
    for line in lines:
        print(c(CYAN, "  ║") + f"  {line}")
    print(c(BOLD + CYAN, "  ╚" + "═" * 40))
    print()

MAX_PROPOSAL_ITEMS = 8
MAX_WAITING_ITEMS = 3
MAX_RECENT_ISSUES = 3
MAX_CHANGE_ITEMS = 5
status_view = os.environ.get('TEAM_STATUS_VIEW', 'overview')
expanded_flags = {x for x in os.environ.get('TEAM_STATUS_EXPANDED', '').split(',') if x}

def is_expanded(name):
    return name in expanded_flags

def wants(name):
    if status_view == 'all':
        return True
    if status_view == 'overview':
        return name == 'overview'
    return status_view == name

# ── Header / Overview ──────────────────────────────────────────────
print()
status_color = GREEN if status == "completed" else (YELLOW if status == "running" else RED)
overview_lines = [
    f"{c(BOLD, 'Pipeline:')}  {pipeline_id}",
    f"{c(BOLD, 'Status:')}    {c(status_color + BOLD, status.upper())}",
    f"{c(BOLD, 'Phase:')}     {c(BOLD, fmt_phase(phase))}  {c(DIM, f'(last done: {fmt_phase(last_done)})')}",
]

# ── Conditional agents ─────────────────────────────────────────────
if cond:
    active = [k for k, v in cond.items() if v]
    inactive = [k for k, v in cond.items() if not v]
    parts = [c(GREEN, f"+{k}") for k in active] + [c(DIM, f"-{k}") for k in inactive]
    overview_lines.append(f"{c(BOLD, 'Agents:')}    {', '.join(parts)}")

tab_items = [
    ('overview', 'Overview'),
    ('proposals', 'Proposals'),
    ('issues', 'Issues'),
    ('changes', 'Changes'),
    ('execution', 'Execution'),
    ('retries', 'Retries'),
]
tab_line = []
for key, label in tab_items:
    if status_view == 'all':
        tab_line.append(c(BOLD if key == 'overview' else DIM, label))
    elif key == status_view or (status_view == 'overview' and key == 'overview'):
        tab_line.append(c(CYAN + BOLD, f'[{label}]'))
    else:
        tab_line.append(c(DIM, label))
overview_lines.append(f"{c(BOLD, 'Views:')}     {' | '.join(tab_line)}")
if status_view == 'overview':
    overview_lines.append(c(DIM, "提示: team status --view proposals|issues|changes|execution|retries|all"))

print_panel(f"Pipeline Status — {project}", overview_lines)

# ── Proposals panel ────────────────────────────────────────────────
queue_file = ".pipeline/proposal-queue.json"
if os.path.exists(queue_file):
    q = json.load(open(queue_file))
    proposals = q if isinstance(q, list) else q.get("proposals", [])
    system_name = q.get("system_name", "") if isinstance(q, dict) else ""
    total = len(proposals)
    done  = sum(1 for p in proposals if p.get("status") == "completed")
    running = [p for p in proposals if p.get("status") == "running"]

    proposal_lines = [f"{c(BOLD, 'System:')}    {system_name}"]
    bar_filled = int(done / total * 20) if total else 0
    bar = c(GREEN, "█" * bar_filled) + c(DIM, "░" * (20 - bar_filled))
    proposal_lines.append(f"{c(BOLD, 'Progress:')}  [{bar}{RESET}] {c(BOLD, str(done))}/{total}")
    if running:
        proposal_lines.append(f"{c(BOLD, 'Running:')}   {', '.join(p.get('id', '?') for p in running)}")

    visible_proposals = []
    unfinished = [p for p in proposals if p.get("status") != "completed"]
    completed = [p for p in proposals if p.get("status") == "completed"]
    proposal_pool = sorted(
        proposals,
        key=lambda p: (
            {"running": 0, "pending": 1, "completed": 2}.get(p.get("status", "pending"), 9),
            p.get("id", ""),
        ),
    )
    if is_expanded('proposals') and wants('proposals'):
        visible_proposals, proposal_page, proposal_total_pages, _ = paginate_items(proposal_pool, reserved_lines=18)
    else:
        proposal_limit = len(proposals) if is_expanded('proposals') else MAX_PROPOSAL_ITEMS
        if unfinished:
            visible_proposals.extend(unfinished[:proposal_limit])
        else:
            visible_proposals.extend(completed[:(len(completed) if is_expanded('proposals') else min(len(completed), 3))])
        proposal_page, proposal_total_pages = 1, 1

    for p in visible_proposals:
        pid    = p.get("id", "?")
        title  = p.get("title", "")
        pst    = p.get("status", "pending")
        if pst == "completed":
            icon = c(GREEN, "✓")
            color = DIM
        elif pst == "running":
            icon = c(YELLOW + BOLD, "▶")
            color = BOLD
        else:
            icon = c(DIM, "○")
            color = ""
        deps = p.get("depends_on", [])
        dep_str = c(DIM, f"  ← {', '.join(deps)}") if deps else ""
        proposal_lines.append(f"  {icon} {c(color, f'[{pid}] {title}')}{dep_str}")

    hidden_proposals = max(0, len(proposals) - len(visible_proposals))
    if hidden_proposals:
        proposal_lines.append(c(DIM, f"  ... 另有 {hidden_proposals} 个 proposal，避免状态页过长未展开"))
    elif wants('proposals') and is_expanded('proposals'):
        proposal_lines.append(c(DIM, "  已展开全部 proposal；按 e 可收起"))
    if wants('proposals') and is_expanded('proposals') and proposal_total_pages > 1:
        proposal_lines.append(c(DIM, f"  第 {proposal_page}/{proposal_total_pages} 页；按 n/p 翻页"))

    if wants('proposals'):
        print_panel("Proposals", proposal_lines)
    elif status_view == 'overview':
        proposal_summary = [f"{c(BOLD, 'Progress:')}  {c(BOLD, str(done))}/{total}"]
        if running:
            proposal_summary.append(f"{c(BOLD, 'Running:')}   {', '.join(p.get('id', '?') for p in running[:3])}")
        else:
            proposal_summary.append(f"{c(BOLD, 'State:')}     {c(DIM, '无运行中 proposal')}")
        if total > len(visible_proposals):
            proposal_summary.append(c(DIM, f"使用 `team status --view proposals` 查看全部摘要（当前隐藏 {total - len(visible_proposals)} 项）"))
        print_panel("Proposals", proposal_summary)

# ── Issues panel ───────────────────────────────────────────────────
issue_lines = []
issue_cfg = load_issue_cfg()
issue_repo = detect_issue_repo(issue_cfg)
need_issue_list = wants('issues') or status_view == 'all'
issue_queue_items = query_issue_items(issue_repo, issue_cfg) if need_issue_list else []
queue_counts = summarize_issue_queue_counts(issue_queue_items, issue_cfg) if need_issue_list else query_issue_queue_counts(issue_repo, issue_cfg)
watch_file = ".pipeline/issues/watch-state.json"
active_workers = []
if issue_repo:
    issue_lines.append(f"{c(BOLD, 'Repo:')}      {issue_repo}")
if issue_cfg.get('source_labels'):
    issue_lines.append(f"{c(BOLD, 'Source:')}    {issue_cfg.get('source_labels')}")
if queue_counts is not None:
    issue_lines.append(
        f"{c(BOLD, 'Queue:')}     queued={c(BLUE, str(queue_counts['queued']))} | processing={c(CYAN, str(queue_counts['processing']))} | waiting={c(YELLOW, str(queue_counts['waiting']))} | done={c(GREEN, str(queue_counts['done']))}"
    )
if issue_queue_items and wants('issues'):
    issue_lines.append(f"{c(BOLD, 'Open List:')}  {len(issue_queue_items)} issue(s)")
    if is_expanded('issues'):
        visible_issue_items, issue_page, issue_total_pages, _ = paginate_items(issue_queue_items, reserved_lines=24)
    else:
        visible_issue_items = issue_queue_items[:min(len(issue_queue_items), MAX_PROPOSAL_ITEMS)]
        issue_page, issue_total_pages = 1, 1
    issue_item_limit = len(visible_issue_items)
    state_color = {'queued': BLUE, 'processing': CYAN, 'waiting': YELLOW, 'done': GREEN}
    state_color['resolved'] = GREEN
    for item in visible_issue_items:
        labels_preview = ','.join(item.get('labels', [])[:3])
        labels_suffix = f" [{labels_preview}]" if labels_preview else ''
        issue_lines.append(
            f"  {c(state_color.get(item['state'], DIM), item['state']):>10}  #{item['number']} {item['title']}{c(DIM, labels_suffix)}"
        )
    if len(issue_queue_items) > len(visible_issue_items) and not is_expanded('issues'):
        issue_lines.append(c(DIM, f"  ... 另有 {len(issue_queue_items) - len(visible_issue_items)} 个 open issue 未展开"))
    elif is_expanded('issues'):
        issue_lines.append(c(DIM, "  已展开 open/resolved issue 清单；按 e 可收起"))
    if is_expanded('issues') and issue_total_pages > 1:
        issue_lines.append(c(DIM, f"  第 {issue_page}/{issue_total_pages} 页；按 n/p 翻页"))
if os.path.exists(watch_file):
    try:
        watch = json.load(open(watch_file))
        active_workers = watch.get("workers", [])
        issue_lines.append(f"{c(BOLD, 'Watcher:')}   {len(active_workers)} worker(s) running")
        worker_limit = len(active_workers) if is_expanded('issues') else MAX_RECENT_ISSUES
        for w in active_workers[:worker_limit]:
            issue_no = w.get("issue_number", "?")
            pid = w.get("pid", "?")
            worktree = w.get("worktree", "")
            issue_lines.append(f"  {c(YELLOW, '#'+str(issue_no))} pid={pid} {c(DIM, worktree)}")
        if len(active_workers) > worker_limit:
            issue_lines.append(c(DIM, f"  ... 另有 {len(active_workers) - worker_limit} 个活跃 worker 未展开"))
    except Exception as ex:
        issue_lines.append(f"{c(RED, 'watch-state 读取失败')} {c(DIM, str(ex))}")

results_dir = ".pipeline/issues/results"
if os.path.isdir(results_dir):
    results = []
    for name in sorted(os.listdir(results_dir)):
        if not name.endswith('.json'):
            continue
        path = os.path.join(results_dir, name)
        try:
            results.append(json.load(open(path)))
        except Exception:
            continue
    if results:
        processing_ids = {str(w.get('issue_number')) for w in active_workers}
        waiting_count = 0
        done_count = 0
        escalation_count = 0
        waiting_items = []
        seen = set()
        for item in sorted(results, key=lambda x: x.get('updated_at', ''), reverse=True):
            issue_key = str(item.get('issue_number', '?'))
            if issue_key in seen:
                continue
            seen.add(issue_key)
            result = item.get('result', 'unknown')
            if issue_key in processing_ids:
                continue
            if result == 'done':
                done_count += 1
            elif result == 'waiting':
                waiting_count += 1
                waiting_items.append(item)
            elif result == 'escalation':
                escalation_count += 1

        issue_lines.append(
            f"{c(BOLD, 'Summary:')}   processing={c(CYAN, str(len(processing_ids)))} | waiting={c(YELLOW, str(waiting_count))} | done={c(GREEN, str(done_count))} | escalation={c(RED, str(escalation_count))}"
        )
        if waiting_items:
            waiting_items = sorted(waiting_items, key=waiting_takeover_priority)
            issue_lines.append(f"{c(YELLOW + BOLD, 'Waiting-User:')}  {len(waiting_items)} issue(s) need manual takeover")
            issue_lines.append(f"  {c(DIM, '优先级: escalation > 0.clarify > 2.0b.depend-collect > memory-consolidation > 其他')}" )
            waiting_limit = len(waiting_items) if is_expanded('issues') else MAX_WAITING_ITEMS
            for item in waiting_items[:waiting_limit]:
                waiting_phase = fmt_phase(item.get('phase', 'unknown'))
                extras = []
                if item.get('worktree'):
                    extras.append(f"wt={item.get('worktree')}")
                if item.get('log_file'):
                    extras.append(f"log={item.get('log_file')}")
                if item.get('issue_url'):
                    extras.append(f"url={item.get('issue_url')}")
                tail = c(DIM, " | ".join(extras)) if extras else ""
                issue_lines.append(f"  {c(YELLOW, '⏸')} #{item.get('issue_number', '?')} {item.get('issue_title', '')} {c(DIM, '@ ' + waiting_phase)} {tail}")
            if len(waiting_items) > waiting_limit:
                issue_lines.append(c(DIM, f"  ... 另有 {len(waiting_items) - waiting_limit} 个 waiting issue 未展开"))
        latest_feedback = max((item.get('github_feedback_at', '') for item in results), default='')
        issue_lines.append(f"{c(BOLD, 'Feedback:')}  last GitHub writeback at {fmt_ts(latest_feedback)}")
        issue_lines.append(f"{c(BOLD, 'Recent:')}    {len(results)} issue run(s)")
        recent_limit = len(results) if is_expanded('issues') else MAX_RECENT_ISSUES
        recent_items = sorted(results, key=lambda x: x.get('updated_at', ''), reverse=True)[:recent_limit]
        for item in recent_items:
            issue_no = item.get('issue_number', '?')
            result = item.get('result', 'unknown')
            phase_name = item.get('phase', 'unknown')
            title = item.get('issue_title', '')
            result_label, result_color, result_icon = fmt_issue_result(result)
            extras = []
            if item.get('worktree'):
                extras.append(f"wt={item.get('worktree')}")
            if item.get('log_file'):
                extras.append(f"log={item.get('log_file')}")
            if item.get('issue_url'):
                extras.append(f"url={item.get('issue_url')}")
            tail = c(DIM, " | ".join(extras)) if extras else ""
            issue_lines.append(f"  {c(result_color, result_icon)} #{issue_no} {title} {c(DIM, f'({result_label} @ {fmt_phase(phase_name)})')} {tail}")
        if len(results) > recent_limit:
            issue_lines.append(c(DIM, f"  ... 另有 {len(results) - recent_limit} 条 issue 运行记录未展开"))
        elif wants('issues') and is_expanded('issues'):
            issue_lines.append(c(DIM, "  已展开 issue 清单；按 e 可收起"))

if active_workers and not os.path.isdir(results_dir):
    issue_lines.append(
        f"{c(BOLD, 'Summary:')}   processing={c(CYAN, str(len(active_workers)))} | waiting={c(YELLOW, '0')} | done={c(GREEN, '0')} | escalation={c(RED, '0')}"
    )

if not issue_lines:
    issue_lines.append(c(DIM, "暂无 issue watcher / issue run 数据"))

if wants('issues'):
    print_panel("Issues", issue_lines)
elif status_view == 'overview':
    issue_summary = []
    if issue_repo:
        issue_summary.append(f"{c(BOLD, 'Repo:')}      {issue_repo}")
    if queue_counts is not None:
        issue_summary.append(
            f"{c(BOLD, 'Queue:')}     queued={c(BLUE, str(queue_counts['queued']))} | processing={c(CYAN, str(queue_counts['processing']))} | waiting={c(YELLOW, str(queue_counts['waiting']))} | done={c(GREEN, str(queue_counts['done']))}"
        )
    if not issue_summary:
        issue_summary.append(c(DIM, '暂无 issue watcher / issue run 数据'))
    else:
        issue_summary.append(c(DIM, '使用 `team status --view issues` 查看 issue 明细'))
    print_panel("Issues", issue_summary)

# ── Micro-changes panel ────────────────────────────────────────────
changes_file = ".pipeline/micro-changes.json"
change_lines = []
if os.path.exists(changes_file):
    try:
        changes_data = json.load(open(changes_file))
        changes = changes_data.get('changes', [])
        pending_changes = [cng for cng in changes if cng.get('memory_candidate') and not cng.get('consumed_by_memory')]
        change_lines.append(f"{c(BOLD, 'Total:')}     {len(changes)}")
        change_lines.append(f"{c(BOLD, 'Pending:')}   {c(YELLOW if pending_changes else DIM, str(len(pending_changes)))}")

        visible_changes = []
        change_pool = sorted(
            changes,
            key=lambda item: (
                0 if item.get('memory_candidate') and not item.get('consumed_by_memory') else 1,
                item.get('date', ''),
                item.get('id', ''),
            ),
            reverse=True,
        )
        if wants('changes') and is_expanded('changes'):
            visible_changes, change_page, change_total_pages, _ = paginate_items(change_pool, reserved_lines=18)
        else:
            change_limit = len(change_pool) if is_expanded('changes') else MAX_CHANGE_ITEMS
            visible_changes = change_pool[:change_limit]
            change_page, change_total_pages = 1, 1

        for item in visible_changes:
            pending = item.get('memory_candidate') and not item.get('consumed_by_memory')
            icon = c(YELLOW + BOLD, '●') if pending else c(DIM, '○')
            domain_text = ','.join(item.get('domains') or []) or '-'
            change_lines.append(
                f"  {icon} [{item.get('id', '?')}] {item.get('normalized_change', '')} {c(DIM, f'(domains={domain_text})')}"
            )
            if pending and item.get('proposed_constraint'):
                change_lines.append(f"    {c(DIM, 'constraint:')} {item.get('proposed_constraint')}")

        hidden_changes = max(0, len(change_pool) - len(visible_changes))
        if hidden_changes:
            change_lines.append(c(DIM, f"  ... 另有 {hidden_changes} 条 micro-change 未展开"))
        elif wants('changes') and is_expanded('changes'):
            change_lines.append(c(DIM, '  已展开全部 micro-change；按 e 可收起'))
        if wants('changes') and is_expanded('changes') and change_total_pages > 1:
            change_lines.append(c(DIM, f"  第 {change_page}/{change_total_pages} 页；按 n/p 翻页"))
    except Exception as ex:
        change_lines.append(f"{c(RED, 'micro-changes 读取失败')} {c(DIM, str(ex))}")
else:
    change_lines.append(c(DIM, '暂无 micro-change 记录'))

if wants('changes'):
    print_panel("Changes", change_lines)
elif status_view == 'overview':
    pending_changes = []
    total_changes = 0
    if os.path.exists(changes_file):
        try:
            changes_data = json.load(open(changes_file))
            changes = changes_data.get('changes', [])
            total_changes = len(changes)
            pending_changes = [cng for cng in changes if cng.get('memory_candidate') and not cng.get('consumed_by_memory')]
        except Exception:
            pass
    change_summary = [
        f"{c(BOLD, 'Total:')}     {total_changes}",
        f"{c(BOLD, 'Pending:')}   {c(YELLOW if pending_changes else DIM, str(len(pending_changes)))}",
    ]
    if pending_changes:
        latest_pending = pending_changes[:3]
        for item in latest_pending:
            change_summary.append(f"  {c(YELLOW, '●')} [{item.get('id', '?')}] {item.get('normalized_change', '')}")
    change_summary.append(c(DIM, '使用 `team status --view changes` 查看 micro-change 明细'))
    print_panel("Changes", change_summary)

# ── Step execution log ─────────────────────────────────────────────
index_file = ".pipeline/artifacts/logs/pipeline.index.json"
ex_log = state.get("execution_log", [])

steps = []
if os.path.exists(index_file):
    idx = json.load(open(index_file))
    steps = idx.get("steps", [])
elif ex_log:
    steps = ex_log

if steps:
    exec_lines = [f"{c(BOLD, 'Execution Log:')}  ({len(steps)} steps)"]

    RESULT_COLOR = {"PASS": GREEN, "WARN": YELLOW, "FAIL": RED, "SKIP": DIM, "ERROR": RED}

    # Show all steps; mark rollbacks
    for i, s in enumerate(steps):
        step   = s.get("step", "?")
        result = s.get("result", "?")
        attempt = s.get("attempt", 1)
        rollback_to = s.get("caused_rollback_to") or s.get("rollback_to")
        triggered_by = s.get("rollback_triggered_by")

        rc = RESULT_COLOR.get(result, WHITE)
        attempt_str = c(DIM, f" ×{attempt}") if attempt > 1 else ""
        rollback_str = c(YELLOW, f" → rollback to {rollback_to}") if rollback_to else ""
        triggered_str = c(DIM, f" [by {triggered_by}]") if triggered_by else ""
        exec_lines.append(f"{c(rc + BOLD, result):>6}  {step}{attempt_str}{rollback_str}{triggered_str}")

    if wants('execution'):
        if is_expanded('execution'):
            visible_exec_lines, exec_page, exec_total_pages, _ = paginate_items(exec_lines[1:], reserved_lines=16)
            exec_panel_lines = [exec_lines[0]] + visible_exec_lines
            exec_panel_lines.append(c(DIM, "  已展开 execution 清单；按 e 可收起"))
            if exec_total_pages > 1:
                exec_panel_lines.append(c(DIM, f"  第 {exec_page}/{exec_total_pages} 页；按 n/p 翻页"))
            print_panel("Execution", exec_panel_lines)
        else:
            print_panel("Execution", exec_lines)
    elif status_view == 'overview':
        exec_summary = [f"{c(BOLD, 'Execution Log:')}  ({len(steps)} steps)"]
        for s in steps[-5:]:
            step = s.get('step', '?')
            result = s.get('result', '?')
            rc = RESULT_COLOR.get(result, WHITE)
            exec_summary.append(f"{c(rc + BOLD, result):>6}  {step}")
        if len(steps) > 5:
            exec_summary.append(c(DIM, '使用 `team status --view execution` 查看完整执行记录'))
        print_panel("Execution", exec_summary)

# ── Retry counts (phases with >1 attempts) ─────────────────────────
notable = {k: v for k, v in attempts.items() if isinstance(v, int) and v > 1}
if notable:
    retry_lines = [f"{c(BOLD, 'Retried phases:')}"]
    for k, v in sorted(notable.items()):
        retry_lines.append(f"  {c(YELLOW, k)}: {v} attempts")
    if wants('retries') or status_view == 'overview':
        if status_view == 'overview' and len(retry_lines) > 5:
            retry_lines = retry_lines[:5] + [c(DIM, '使用 `team status --view retries` 查看全部重试阶段')]
        elif wants('retries') and is_expanded('retries'):
            visible_retry_lines, retry_page, retry_total_pages, _ = paginate_items(retry_lines[1:], reserved_lines=14)
            retry_panel_lines = [retry_lines[0]] + visible_retry_lines
            retry_panel_lines.append(c(DIM, '  已展开 retries 清单；按 e 可收起'))
            if retry_total_pages > 1:
                retry_panel_lines.append(c(DIM, f'  第 {retry_page}/{retry_total_pages} 页；按 n/p 翻页'))
            print_panel("Retries", retry_panel_lines)
        else:
            print_panel("Retries", retry_lines)

print()
PYEOF
}

cmd_run() {
  if [ ! -d ".pipeline" ]; then
    echo "❌ No .pipeline/ directory found. Run: team init"
    exit 1
  fi

  # Read cli_backend from config.json, env, or auto-detect
  local cli_backend="${PIPELINE_CLI_BACKEND:-auto}"
  if [ "$cli_backend" = "auto" ] && [ -f ".pipeline/config.json" ]; then
    local cfg_backend
    cfg_backend=$(python3 -c "import json; c=json.load(open('.pipeline/config.json')); print(c.get('model_routing',{}).get('cli_backend','auto'))" 2>/dev/null || echo "auto")
    if [ "$cfg_backend" != "auto" ] && [ -n "$cfg_backend" ]; then
      cli_backend="$cfg_backend"
    fi
  fi
  if [ "$cli_backend" = "auto" ] || [ "$cli_backend" = "cc" ]; then
    if command -v claude &>/dev/null; then cli_backend="claude"
    elif command -v codex &>/dev/null; then cli_backend="codex"
    elif command -v opencode &>/dev/null; then cli_backend="opencode"
    else
      echo "❌ No supported CLI found. Install one of: claude, codex, opencode"
      echo "   Or use Cursor IDE Agent mode with /pilot"
      exit 1
    fi
  fi
  echo "  Using CLI backend: $cli_backend"

  # Check for project-local agents in .pipeline/agents/
  local agent_dir=".pipeline/agents"
  local pilot_agent=""
  if [ -d "$agent_dir" ]; then
    if [ -f "$agent_dir/pilot.md" ]; then
      pilot_agent="$agent_dir/pilot.md"
    elif [ -f "$agent_dir/pilot.toml" ]; then
      pilot_agent="$agent_dir/pilot.toml"
    fi
  fi

  if [ -z "$pilot_agent" ]; then
    echo "  ⚠  No project-local agents in .pipeline/agents/"
    echo "     Falling back to global agents (run 'team init' to generate)"
  else
    echo "  Using project agents: $agent_dir/"
  fi

  # Non-claude backends: launch in native interactive mode
  # CC has a PTY runner that auto-loops batches; other platforms use their
  # own interactive sessions where the user drives batch continuation.
  if [ "$cli_backend" != "claude" ]; then
    local PILOT_PROMPT='你是 Pilot（流水线主控）。请严格按照 AGENTS.md 中的规则执行：1) 读取 .pipeline/state.json（若不存在则初始化）确定当前阶段；2) 读取 .pipeline/playbook.md 中对应章节；3) 先检查 .pipeline/artifacts/issue-context.md 是否存在，仅在存在时再读取，并按 GitHub Issue 交付模式执行；若不存在，不要尝试读取，也不要将其缺失视为错误；但如果 state.json 含 issue_context，或 .pipeline/artifacts/issue-runtime.json 存在，则说明当前就是 Issue 模式，此时 .pipeline/artifacts/issue-context.md 必须存在；若缺失，立即进入 ESCALATION，不得按普通流程继续；4) 执行当前批次。批次完成后更新 state.json 并输出 [EXIT]。'

    case "$cli_backend" in
      codex)
        echo ""
        local cx_msg=""
        if [ -f ".pipeline/state.json" ]; then
          cx_msg="继续执行流水线。读取 .pipeline/state.json 确定当前阶段，读取 .pipeline/playbook.md 对应章节；先检查 .pipeline/artifacts/issue-context.md 是否存在，仅在存在时再读取并按 GitHub Issue 交付模式执行；若不存在，不要尝试读取，也不要将其缺失视为错误；但如果 state.json 含 issue_context，或 .pipeline/artifacts/issue-runtime.json 存在，则说明当前就是 Issue 模式，此时 .pipeline/artifacts/issue-context.md 必须存在；若缺失，立即进入 ESCALATION，不得按普通流程继续；完成后更新 state.json 并输出 [EXIT]。"
          echo "  已检测到 state.json，尝试恢复上次会话..."
        else
          cx_msg="$PILOT_PROMPT"
          echo "  首次运行 — 启动 codex 交互 TUI..."
        fi
        echo "  (AGENTS.md 已包含 Pilot 指令，codex 自动加载)"
        echo ""
        # codex 支持 positional PROMPT 自动提交
        codex --full-auto "$cx_msg"
        ;;
      opencode)
        # OpenCode：交互阶段走 TUI，自动阶段优先走 run --continue。
        local OC_CONT_MSG="继续执行流水线。读取 .pipeline/state.json 确定当前阶段，读取 .pipeline/playbook.md 对应章节；先检查 .pipeline/artifacts/issue-context.md 是否存在，仅在存在时再读取并按 GitHub Issue 交付模式执行；若不存在，不要尝试读取，也不要将其缺失视为错误；但如果 state.json 含 issue_context，或 .pipeline/artifacts/issue-runtime.json 存在，则说明当前就是 Issue 模式，此时 .pipeline/artifacts/issue-context.md 必须存在；若缺失，立即进入 ESCALATION，不得按普通流程继续；完成后更新 state.json 并输出 [EXIT]。"
        local oc_sleep="${TEAM_OPENCODE_LOOP_SLEEP:-3}"
        local oc_round=0
        while true; do
          oc_round=$((oc_round + 1))
          print_opencode_banner "OpenCode 第 ${oc_round} 轮"
          echo "  (OpenCode 通过 .opencode/agents/ 加载 Agent，AGENTS.md 作为项目上下文)"
          print_opencode_state "本轮开始前"

	          local oc_mode
	          oc_mode=$(opencode_batch_mode 2>/dev/null || echo "tui-continue")

	          case "$oc_mode" in
            done)
              echo "  ✅ Pipeline ALL-COMPLETED."
              echo ""
              return
              ;;
            escalation)
              echo "  ⚠  Pipeline ESCALATION — 需要人工介入。运行: team status"
              echo ""
              return
              ;;
            pause)
              echo "  ⏸  凭证未就绪：请填写 .depend/*.env 后再次执行 team run"
              echo ""
              return
              ;;
	            tui-initial|tui-continue)
	              local oc_tui_msg="$PILOT_PROMPT"
	              if [ "$oc_mode" = "tui-continue" ] && [ -f ".pipeline/state.json" ]; then
	                oc_tui_msg="$OC_CONT_MSG"
	                print_opencode_banner "交互模式输出（TUI）"
	                echo "  决策: 当前 phase 需要人工交互，切换到 TUI 恢复会话并自动提交 prompt"
	                print_opencode_state "进入 TUI 前"
	                echo ""
	                if ! TEAM_TUI_AUTO_PROMPT="$oc_tui_msg" run_tui_with_auto_submit "$oc_tui_msg" opencode --continue; then
	                  echo "  ⚠  --continue 失败，尝试新开 TUI 会话..."
	                  echo ""
	                  TEAM_TUI_AUTO_PROMPT="$oc_tui_msg" run_tui_with_auto_submit "$oc_tui_msg" opencode || true
	                fi
	              else
	                print_opencode_banner "交互模式输出（TUI）"
	                echo "  决策: 当前 phase 需要人工交互，启动 TUI 并自动填充 prompt"
	                print_opencode_state "进入 TUI 前"
	                echo ""
	                TEAM_TUI_AUTO_PROMPT="$oc_tui_msg" run_tui_with_auto_submit "$oc_tui_msg" opencode || true
	              fi
	              print_opencode_banner "交互模式结束"
	              print_opencode_state "退出 TUI 后"
	              echo "  退出 TUI（/quit）后，若流水线未完成将自动进入下一轮。"
	              ;;
	            run-continue)
	              print_opencode_banner "自动模式输出（run --continue）"
	              echo "  决策: 当前 phase 无需人工交互，直接使用 run --continue"
	              print_opencode_state "进入自动模式前"
	              echo "  下方开始是 OpenCode 本轮自动执行输出"
	              echo ""
	              if ! opencode run --continue "$OC_CONT_MSG"; then
	                echo "  ⚠  run --continue 失败，回退到 TUI 恢复会话..."
	                echo ""
	                if ! TEAM_TUI_AUTO_PROMPT="$OC_CONT_MSG" run_tui_with_auto_submit "$OC_CONT_MSG" opencode --continue; then
	                  echo "  ⚠  TUI 恢复失败，尝试新开 TUI 会话..."
	                  echo ""
	                  TEAM_TUI_AUTO_PROMPT="$OC_CONT_MSG" run_tui_with_auto_submit "$OC_CONT_MSG" opencode || true
	                fi
	              fi
	              echo ""
	              print_opencode_banner "自动模式结束"
	              print_opencode_state "本轮自动执行后"
	              ;;
	          esac

          local oc_after
          oc_after=$(python3 -c "
import json, os
if not os.path.exists('.pipeline/state.json'):
    print('continue')
    raise SystemExit
s = json.load(open('.pipeline/state.json'))
phase = s.get('current_phase', '')
status = s.get('status', 'running')
dep = s.get('depend_collector_result', {})
unfilled = len(dep.get('unfilled_deps', []))
if phase == 'ALL-COMPLETED' or status == 'completed':
    print('done')
    raise SystemExit
if status == 'escalation':
    print('escalation')
    raise SystemExit
if unfilled > 0:
    print('pause')
    raise SystemExit
print('continue')
" 2>/dev/null || echo "continue")

          case "$oc_after" in
            done)
              echo ""
              echo "  ✅ Pipeline ALL-COMPLETED."
              echo ""
              return
              ;;
            escalation)
              echo ""
              echo "  ⚠  ESCALATION — 运行: team status"
              echo ""
              return
              ;;
            pause)
              echo ""
              echo "  ⏸  请填写凭证后再次: team run"
              echo ""
              return
              ;;
          esac

          print_opencode_banner "等待下一轮"
          print_opencode_state "准备休眠前"
          echo "  ⟳ 流水线未结束 — ${oc_sleep}s 后启动下一轮（Ctrl+C 可完全退出 team run）"
          sleep "$oc_sleep"
        done
        return
        ;;
      cursor)
        echo ""
        echo "  Cursor 是 IDE 驱动的，请在 Cursor IDE 中："
        echo "    1. 打开 Agent 模式 (Cmd+I / Ctrl+I)"
        echo "    2. 输入 /pilot 启动流水线"
        echo ""
        return
        ;;
      *)
        echo "❌ Unsupported backend: $cli_backend"
        exit 1
        ;;
    esac

    # After session ends, show state summary and hint
    echo ""
    local post_check
    post_check=$(python3 -c "
import json, os
if not os.path.exists('.pipeline/state.json'):
    print('none')
    exit()
s = json.load(open('.pipeline/state.json'))
phase = s.get('current_phase', '')
status = s.get('status', 'running')
if phase == 'ALL-COMPLETED' or status == 'completed':
    print('done')
elif status == 'escalation':
    print('escalation')
else:
    print('running|' + phase)
" 2>/dev/null || echo "unknown")

    case "$post_check" in
      done)
        echo "  ✅ Pipeline ALL-COMPLETED."
        ;;
      escalation)
        echo "  ⚠  Pipeline ESCALATION — 需要人工介入。"
        echo "     Run: team status"
        ;;
      none)
        echo "  ℹ  state.json 尚未创建。"
        ;;
      running|*)
        local phase="${post_check#running|}"
        echo "  ℹ  当前阶段: $phase"
        echo "     继续执行: team run"
        ;;
    esac
    echo ""
    return
  fi

  # PTY runner for claude backend (full TUI support)
  _RUNNER=$(mktemp "${TMPDIR:-/tmp}/team-runner-XXXXXX")
  trap 'rm -f "$_RUNNER"' EXIT

  cat > "$_RUNNER" << 'PYEOF'
#!/usr/bin/env python3
"""
team run — PTY daemon (multi-batch loop)

Each pipeline batch runs as a FRESH `claude --agent pilot` process.
When [EXIT] appears in the output:
  1. The current claude process is terminated.
  2. Pipeline state is checked.
  3. If not done, a new claude process is spawned for the next batch.
"""
import os, sys, select, signal, termios, tty, fcntl, time, json, subprocess

# ── helpers ──────────────────────────────────────────────────────────────────

def get_state():
    try:
        s = json.load(open('.pipeline/state.json'))
        dep = s.get('depend_collector_result', {})
        return s.get('status', 'running'), len(dep.get('unfilled_deps', []))
    except Exception:
        return 'unknown', 0

def resize_pty(master_fd):
    try:
        ws = fcntl.ioctl(sys.stdout.fileno(), termios.TIOCGWINSZ, b'\x00' * 8)
        fcntl.ioctl(master_fd, termios.TIOCSWINSZ, ws)
    except Exception:
        pass

def print_report():
    try:
        G="\033[32m"; Y="\033[33m"; R="\033[31m"; C="\033[36m"; B="\033[1m"; E="\033[0m"
        s = json.load(open('.pipeline/state.json'))
        q = json.load(open('.pipeline/proposal-queue.json')) if os.path.exists('.pipeline/proposal-queue.json') else []
        props = q if isinstance(q, list) else q.get('proposals', [])
        steps = s.get('execution_log', [])
        done  = sum(1 for p in props if p.get('status') == 'completed')
        ps    = sum(1 for e in steps if e.get('result') == 'PASS')
        fs    = sum(1 for e in steps if e.get('result') == 'FAIL')
        ws    = sum(1 for e in steps if e.get('result') == 'WARN')
        lines = [
            f"\r\n{B}{C}  ╔══ Pipeline Final Report ══════════════════════╗{E}",
            f"{C}  ║{E}  {B}Project:{E}    {s.get('project_name', os.path.basename(os.getcwd()))}",
            f"{C}  ║{E}  {B}Proposals:{E}  {G}{done}/{len(props)} completed{E}",
            f"{C}  ║{E}  {B}Steps:{E}      {G}{ps} PASS{E}  {Y}{ws} WARN{E}  {R}{fs} FAIL{E}  (total {len(steps)})",
            f"{C}  ║{E}",
        ]
        for p in props:
            icon = f"{G}✓{E}" if p.get('status') == 'completed' else f"{Y}○{E}"
            lines.append(f"{C}  ║{E}    {icon}  {p.get('title', '')}")
        lines.append(f"{B}{C}  ╚═══════════════════════════════════════════════╝{E}\r\n")
        sys.stdout.buffer.write('\r\n'.join(lines).encode())
        sys.stdout.buffer.flush()
    except Exception as ex:
        sys.stdout.buffer.write(f'\r\n[report error: {ex}]\r\n'.encode())
        sys.stdout.buffer.flush()

def write_status(msg, color=36):
    sys.stdout.buffer.write(f'\r\n\033[{color}m{msg}\033[0m\r\n'.encode())
    sys.stdout.buffer.flush()

# ── main ─────────────────────────────────────────────────────────────────────

def main():
    stdin_fd = sys.stdin.fileno()
    if not os.isatty(stdin_fd):
        sys.stderr.write(
            '\n  ❌  team run requires a real terminal (tty).\n'
            '     Run it directly in your shell, not via a pipe or script.\n\n'
        )
        sys.exit(1)

    # Inherit env without CLAUDECODE so nested invocation is allowed
    env = {k: v for k, v in os.environ.items() if k != 'CLAUDECODE'}
    saved_tty = termios.tcgetattr(stdin_fd)

    def start_claude():
        """Spawn a fresh claude process with its own PTY slave."""
        mfd, sfd = os.openpty()
        resize_pty(mfd)

        def child_setup():
            os.setsid()
            try:
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)
            except Exception:
                pass

        agent_ref = 'pilot'
        local_pilot = os.path.join('.pipeline', 'agents', 'pilot.md')
        if os.path.isfile(local_pilot):
            agent_ref = local_pilot

        p = subprocess.Popen(
            ['claude', '--dangerously-skip-permissions', '--agent', agent_ref],
            stdin=sfd, stdout=sfd, stderr=sfd,
            env=env, preexec_fn=child_setup, close_fds=True,
        )
        os.close(sfd)
        return p, mfd

    def kill_claude(p, mfd):
        """Terminate claude and close the master PTY fd."""
        try:
            p.terminate()
            p.wait(timeout=5)
        except Exception:
            try:
                p.kill()
            except Exception:
                pass
        try:
            os.close(mfd)
        except Exception:
            pass

    tty.setraw(stdin_fd)
    batch_num = 0

    try:
        while True:
            batch_num += 1
            proc, master_fd = start_claude()
            signal.signal(signal.SIGWINCH, lambda s, f: resize_pty(master_fd))

            buf          = b''
            exit_count   = 0
            prompt_sent  = False
            t0           = time.monotonic()
            t_last_out   = t0
            exit_seen_at = None

            # ── Run this batch until [EXIT] or natural claude exit ────────────
            while proc.poll() is None:
                try:
                    r, _, _ = select.select([master_fd, stdin_fd], [], [], 0.2)
                except (select.error, ValueError):
                    break

                now = time.monotonic()

                # Send initial prompt after settling (2 s silence or 5 s absolute)
                if not prompt_sent and (
                    (now - t_last_out > 2.0 and now - t0 > 1.0) or now - t0 > 5.0
                ):
                    os.write(master_fd, '请执行下一批次\r'.encode())
                    prompt_sent = True

                # [EXIT] detected and settled for 2 s → end this batch
                if exit_seen_at is not None and now - exit_seen_at >= 2.0:
                    break

                for fd in r:
                    if fd == master_fd:
                        try:
                            data = os.read(master_fd, 4096)
                        except OSError:
                            break
                        os.write(sys.stdout.fileno(), data)
                        buf += data
                        t_last_out = time.monotonic()

                        new_count = buf.count(b'[EXIT]')
                        if new_count > exit_count:
                            exit_count   = new_count
                            exit_seen_at = time.monotonic()

                    elif fd == stdin_fd:
                        try:
                            data = os.read(stdin_fd, 1024)
                        except OSError:
                            break
                        if data:
                            os.write(master_fd, data)

            # ── Terminate this claude instance ────────────────────────────────
            kill_claude(proc, master_fd)

            # ── Check pipeline state and decide what to do next ───────────────
            st, unfilled = get_state()

            if st == 'ALL-COMPLETED':
                print_report()
                break
            elif st == 'escalation':
                write_status('  ❌ ESCALATION — run: team status', 31)
                break
            elif unfilled > 0:
                # Restore terminal so the user can type the credentials path
                termios.tcsetattr(stdin_fd, termios.TCSADRAIN, saved_tty)
                sys.stdout.write(
                    f'\r\n\033[33m  ⏸  Credentials needed ({unfilled} unfilled).\r\n'
                    f'     Fill .depend/*.env then press Enter to continue.\033[0m\r\n'
                )
                sys.stdout.flush()
                sys.stdin.readline()
                tty.setraw(stdin_fd)
            else:
                write_status(f'  ↩  Batch {batch_num} complete — starting next batch...', 36)
                time.sleep(1)

    except KeyboardInterrupt:
        pass
    finally:
        try:
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, saved_tty)
        except Exception:
            pass

if __name__ == '__main__':
    main()
PYEOF

  python3 "$_RUNNER"
}

cmd_scan() {
  if [ ! -d ".pipeline" ]; then
    echo "❌ No .pipeline/ directory found. Run: team init"
    exit 1
  fi

  if [ ! -f ".pipeline/artifacts/component-registry.json" ]; then
    echo "❌ No component registry found. Run the pipeline first to generate component-registry.json"
    exit 1
  fi

  local SCAN_MODE="full"
  case "${1:-}" in
    --refresh)    SCAN_MODE="refresh" ;;
    --check-only) SCAN_MODE="check-only" ;;
    "")           SCAN_MODE="full" ;;
    *)
      echo "Usage: team scan [--refresh|--check-only]"
      exit 1
      ;;
  esac

  echo ""
  echo "  ▶ Duplicate Detector — mode: $SCAN_MODE"
  echo ""

  MODE="$SCAN_MODE" PIPELINE_DIR=".pipeline" \
    bash .pipeline/autosteps/duplicate-detector.sh

  echo ""
}

cmd_migrate() {
  local platform="${1:-}"
  local force=false
  local rollback=false

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      cc|codex|cursor|opencode)
        platform="$1" ;;
      --force)  force=true ;;
      --rollback) rollback=true ;;
      *) ;;
    esac
    shift
  done

  # --- Rollback mode ---
  if [ "$rollback" = true ]; then
    local snap=".pipeline/.migrate-snapshot"
    if [ ! -d "$snap" ]; then
      echo "❌ 没有可回滚的迁移快照 (.pipeline/.migrate-snapshot 不存在)"
      exit 1
    fi
    echo ""
    echo "  回滚到上次迁移前的状态..."
    echo ""
    # Restore agents
    rm -rf .pipeline/agents
    if [ -d "$snap/agents" ]; then
      cp -r "$snap/agents" .pipeline/agents
      echo "  ✓ .pipeline/agents/ 已恢复"
    else
      echo "  ✓ .pipeline/agents/ 已移除（迁移前不存在）"
    fi
    # Restore config.json
    if [ -f "$snap/config.json" ]; then
      cp "$snap/config.json" .pipeline/config.json
      echo "  ✓ config.json 已恢复"
    fi
    if [ -f "$snap/opencode.json" ]; then
      cp "$snap/opencode.json" opencode.json
      echo "  ✓ opencode.json 已恢复"
    elif [ -f "opencode.json" ]; then
      rm -f opencode.json
      echo "  ✓ opencode.json 已移除（迁移前不存在）"
    fi
    rm -rf .opencode
    if [ -d "$snap/opencode-dir" ]; then
      cp -r "$snap/opencode-dir" .opencode
      echo "  ✓ .opencode/ 已恢复"
    else
      echo "  ✓ .opencode/ 已移除（迁移前不存在）"
    fi
    local old_platform="unknown"
    if [ -f "$snap/config.json" ]; then
      old_platform=$(python3 -c "
import json
c = json.load(open('$snap/config.json'))
print(c.get('model_routing',{}).get('cli_backend','cc'))
" 2>/dev/null || echo "cc")
    fi
    rm -rf "$snap"
    echo "  ✓ 快照已清理"
    echo ""
    echo "  ✅ 已回滚到 $(platform_label "$old_platform")"
    echo ""
    return
  fi

  # --- Normal migrate ---
  if [ -z "$platform" ]; then
    echo ""
    echo "  用法: team migrate <cc|codex|cursor|opencode> [--force]"
    echo "        team migrate --rollback"
    echo ""
    echo "  切换当前项目到目标平台（替换 .pipeline/agents/ 中的 agent 定义）。"
    echo "  迁移前自动创建快照，支持 --rollback 一键回滚。"
    echo ""
    exit 1
  fi

  case "$platform" in
    cc|codex|cursor|opencode) ;;
    *)
      echo "❌ 不支持的平台: $platform"
      echo "   支持: cc, codex, cursor, opencode"
      exit 1
      ;;
  esac

  if [ ! -d ".pipeline" ]; then
    echo "❌ No .pipeline/ directory found. Run: team init"
    exit 1
  fi

  local label
  label=$(platform_label "$platform")

  # Detect current platform
  local current="cc"
  if [ -f ".pipeline/config.json" ]; then
    current=$(python3 -c "
import json
c = json.load(open('.pipeline/config.json'))
print(c.get('model_routing',{}).get('cli_backend','cc'))
" 2>/dev/null || echo "cc")
    [ "$current" = "auto" ] && current="cc"
  fi

  echo ""
  echo "  Migrating: $(platform_label "$current") → $label"
  echo ""

  # Confirm unless --force
  if [ "$force" != true ]; then
    read -p "  确认迁移? [y/N] " confirm
    case "$confirm" in
      y|Y|yes|YES) ;;
      *)
        echo "  已取消。"
        return
        ;;
    esac
    echo ""
  fi

  # --- Snapshot before migration ---
  local snap=".pipeline/.migrate-snapshot"
  if [ -d "$snap" ]; then
    echo "  ⚠  存在上次迁移的快照（尚未回滚）"
    if [ "$force" != true ]; then
      read -p "  覆盖旧快照继续? [y/N] " snap_confirm
      case "$snap_confirm" in
        y|Y|yes|YES) ;;
        *)
          echo "  已取消。先执行 team migrate --rollback 回滚上次迁移。"
          return
          ;;
      esac
    fi
  fi
  rm -rf "$snap"
  mkdir -p "$snap"
  if [ -d ".pipeline/agents" ]; then
    cp -r ".pipeline/agents" "$snap/agents"
  fi
  if [ -f ".pipeline/config.json" ]; then
    cp ".pipeline/config.json" "$snap/config.json"
  fi
  if [ -f "opencode.json" ]; then
    cp "opencode.json" "$snap/opencode.json"
  fi
  if [ -d ".opencode" ]; then
    cp -r ".opencode" "$snap/opencode-dir"
  fi
  echo "  ✓ 快照已保存 (team migrate --rollback 可回滚)"

  # --- Generate new agents ---
  local agent_count
  agent_count=$(generate_agents_for_platform "$platform" ".pipeline/agents")
  if [ -n "$agent_count" ] && [ "$agent_count" -gt 0 ] 2>/dev/null; then
    echo "  ✓ .pipeline/agents/ replaced ($agent_count agents for $label)"
  else
    echo "  ❌ Agent generation failed — rolling back..."
    # Auto-rollback on failure
    if [ -d "$snap/agents" ]; then
      rm -rf .pipeline/agents
      cp -r "$snap/agents" .pipeline/agents
    fi
    if [ -f "$snap/config.json" ]; then
      cp "$snap/config.json" .pipeline/config.json
    fi
    rm -rf "$snap"
    echo "  ✓ 已自动回滚到迁移前状态"
    exit 1
  fi

  # --- Update config.json (atomic write, rollback on failure) ---
  if [ -f ".pipeline/config.json" ]; then
    if ! python3 -c "
import json, os, tempfile
sf = '.pipeline/config.json'
c = json.load(open(sf))
mr = c.setdefault('model_routing', {})
mr['cli_backend'] = '$platform' if '$platform' != 'cc' else 'auto'
d = os.path.dirname(sf)
fd, tmp = tempfile.mkstemp(dir=d, suffix='.tmp')
with os.fdopen(fd, 'w') as f:
    json.dump(c, f, indent=2, ensure_ascii=False)
os.replace(tmp, sf)
" 2>/dev/null; then
      echo "  ❌ config.json update failed — rolling back..."
      if [ -f "$snap/config.json" ]; then
        cp "$snap/config.json" .pipeline/config.json
      fi
      if [ -d "$snap/agents" ]; then
        rm -rf .pipeline/agents
        cp -r "$snap/agents" .pipeline/agents
      fi
      rm -rf "$snap"
      echo "  ✓ 已自动回滚到迁移前状态"
      exit 1
    fi
    echo "  ✓ config.json cli_backend → $platform"
  fi

  # --- Update context files ---
  case "$platform" in
    cc|cursor)
      if [ ! -f "CLAUDE.md" ] && [ -f "$TEAM_HOME/CLAUDE.md" ]; then
        cp "$TEAM_HOME/CLAUDE.md" CLAUDE.md
        echo "  ✓ CLAUDE.md created"
      fi
      ;;
    codex|opencode)
      # Always regenerate AGENTS.md with pilot instructions on migrate
      generate_agents_md_with_pilot "$platform"
      ;;
  esac

  if [ "$platform" = "opencode" ]; then
    sync_opencode_project_files
  fi

  if [ "$platform" = "cursor" ]; then
    if [ -d "$TEAM_HOME/.cursor/rules" ]; then
      mkdir -p .cursor/rules
      cp "$TEAM_HOME/.cursor/rules/pipeline.md" .cursor/rules/pipeline.md 2>/dev/null || true
      echo "  ✓ .cursor/rules/pipeline.md"
    fi
  fi

  echo ""
  echo "  ✅ Migrated to $label!"
  echo "     Agent definitions: .pipeline/agents/"
  echo "     Start: team run"
  echo ""
  echo "     ↩ 回滚: team migrate --rollback"
  echo ""
}

cmd_issue_worker() {
  local worktree="$1"
  local repo="$2"
  local issue_number="$3"
  local processing_label="$4"
  local waiting_label="$5"
  local done_label="$6"
  local inbox_label="$7"
  local auto_close="$8"
  local detached="${9:-false}"
  local root_dir="${10:-$(pwd)}"
  local log_file="${11:-}"

  local result_file="$root_dir/.pipeline/issues/results/issue-${issue_number}.json"
  local issue_json="$root_dir/.pipeline/issues/cache/issue-${issue_number}.json"
  local issue_title
  issue_title=$(python3 - "$issue_json" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    print(json.load(f).get('title', '').strip())
PY
)
  local issue_url
  issue_url=$(python3 - "$issue_json" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
    print(data.get('url', '') or data.get('html_url', ''))
PY
)

  echo ""
  echo "  ▶ 开始处理 Issue #${issue_number}: ${issue_title}"
  echo "     worktree: ${worktree}"
  echo ""

  (
    cd "$worktree"
    if [ "$detached" = true ]; then
      export TEAM_OPENCODE_INTERACTION_MODE=run
    fi
    cmd_run
  )

  local outcome
  outcome=$(python3 - "$worktree/.pipeline/state.json" <<'PY'
import json
import os
import sys

path = sys.argv[1]
if not os.path.exists(path):
    print('unknown|unknown')
    raise SystemExit
with open(path, 'r', encoding='utf-8') as f:
    state = json.load(f)
phase = state.get('current_phase', 'unknown') or 'unknown'
status = state.get('status', 'running') or 'running'
if phase == 'ALL-COMPLETED' or status == 'completed':
    print(f'done|{phase}')
elif status == 'escalation':
    print(f'escalation|{phase}')
else:
    dep = state.get('depend_collector_result', {})
    if isinstance(dep, dict) and dep.get('unfilled_deps'):
        print(f'waiting|{phase}')
    else:
        print(f'running|{phase}')
PY
)

  local result phase
  result="${outcome%%|*}"
  phase="${outcome#*|}"

  case "$result" in
    done)
      set_issue_processing_state "$repo" "$issue_number" "$done_label" "$processing_label" "$waiting_label" "$inbox_label"
      local done_body
      done_body=$(cat <<EOF
已完成 Issue #${issue_number} 的流水线交付。

- 结果：完成
- 当前阶段：${phase}
- 工作目录：\`${worktree}\`
EOF
)
      gh issue comment "$issue_number" --repo "$repo" --body "$done_body" >/dev/null 2>&1 || true
      if [ "$auto_close" = true ]; then
        gh issue close "$issue_number" --repo "$repo" --comment "已由流水线处理完成，自动关闭。" >/dev/null 2>&1 || true
      fi
      ;;
    waiting|escalation)
      set_issue_processing_state "$repo" "$issue_number" "$waiting_label" "$processing_label" "$done_label"
      local waiting_body
      waiting_body=$(cat <<EOF
Issue #${issue_number} 处理暂停，等待人工介入。

- 结果：${result}
- 当前阶段：${phase}
- 工作目录：\`${worktree}\`

请在对应终端继续处理后，再重新执行 watcher 或手动进入该 worktree。
EOF
)
      gh issue comment "$issue_number" --repo "$repo" --body "$waiting_body" >/dev/null 2>&1 || true
      ;;
    *)
      set_issue_processing_state "$repo" "$issue_number" "$processing_label" "$waiting_label" "$done_label" "$inbox_label"
      ;;
  esac

  write_issue_worker_result "$result_file" "$result" "$phase" "$worktree" "$issue_number" "$issue_title" "$issue_url" "$log_file"
}

cmd_issue() {
  local subcmd="${1:-}"
  shift || true

  case "$subcmd" in
    run)
      local issue_number=""
      local repo_override=""
      local detached=false
      local log_file_override=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --repo=*) repo_override="${1#*=}" ;;
          --repo) shift; repo_override="${1:-}" ;;
          --detach) detached=true ;;
          --log-file=*) log_file_override="${1#*=}" ;;
          --log-file) shift; log_file_override="${1:-}" ;;
          [0-9]*) issue_number="$1" ;;
        esac
        shift || true
      done

      if [ -z "$issue_number" ]; then
        echo "❌ 用法: team issue run <number> [--repo <owner/repo>] [--detach]"
        exit 1
      fi
      if [ ! -d ".pipeline" ]; then
        echo "❌ No .pipeline/ directory found. Run: team init"
        exit 1
      fi

      ensure_gh_auth
      ensure_issue_runtime_dirs

      local cfg repo source_labels processing_label waiting_label done_label auto_close poll_interval max_workers worktree_dir
      cfg=$(load_issue_automation_config)
      IFS='|' read -r repo source_labels processing_label waiting_label done_label auto_close poll_interval max_workers worktree_dir <<< "$cfg"
      repo=$(resolve_issue_repo "$repo_override")

      ensure_issue_label "$repo" "$processing_label" "FBCA04" "流水线处理中"
      ensure_issue_label "$repo" "$waiting_label" "D93F0B" "等待人工处理"
      ensure_issue_label "$repo" "$done_label" "0E8A16" "流水线已完成"

      set_issue_processing_state "$repo" "$issue_number" "$processing_label" "$waiting_label" "$done_label"

      local root_dir
      root_dir=$(pwd)
      local worktree
      worktree=$(prepare_issue_worktree "$issue_number" "$repo" "$worktree_dir" "$root_dir")

      if [ "$detached" = true ]; then
        local log_file="$root_dir/.pipeline/issues/logs/issue-${issue_number}.log"
        nohup "$0" __issue-worker "$worktree" "$repo" "$issue_number" "$processing_label" "$waiting_label" "$done_label" "$source_labels" "$auto_close" true "$root_dir" > "$log_file" 2>&1 &
        local pid=$!
        python3 - "$root_dir/.pipeline/issues/watch-state.json" "$issue_number" "$pid" "$worktree" "$log_file" <<'PY'
import json, os, sys
path, issue_number, pid, worktree, log_file = sys.argv[1:6]
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {'workers': []}
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except Exception:
            data = {'workers': []}
workers = [w for w in data.get('workers', []) if str(w.get('issue_number')) != issue_number]
workers.append({'issue_number': int(issue_number), 'pid': int(pid), 'worktree': worktree, 'log_file': log_file, 'status': 'running'})
data['workers'] = workers
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PY
        echo "  ✓ Issue #${issue_number} 已进入后台处理 (pid=${pid})"
        echo "    日志: ${log_file}"
      else
        cmd_issue_worker "$worktree" "$repo" "$issue_number" "$processing_label" "$waiting_label" "$done_label" "$source_labels" "$auto_close" false "$root_dir" "$log_file_override"
      fi
      ;;
    *)
      echo "❌ 用法: team issue run <number> [--repo <owner/repo>]"
      exit 1
      ;;
  esac
}

cmd_watch_issues() {
  if [ ! -d ".pipeline" ]; then
    echo "❌ No .pipeline/ directory found. Run: team init"
    exit 1
  fi

  ensure_gh_auth
  ensure_issue_runtime_dirs

  local repo_override=""
  local interval_override=""
  local workers_override=""
  local include_labels_override=""
  local exclude_labels_override=""
  local dry_run=false
  local once=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo=*) repo_override="${1#*=}" ;;
      --repo) shift; repo_override="${1:-}" ;;
      --interval=*) interval_override="${1#*=}" ;;
      --interval) shift; interval_override="${1:-}" ;;
      --max-workers=*) workers_override="${1#*=}" ;;
      --max-workers) shift; workers_override="${1:-}" ;;
      --labels=*) include_labels_override="${1#*=}" ;;
      --labels) shift; include_labels_override="${1:-}" ;;
      --exclude-labels=*) exclude_labels_override="${1#*=}" ;;
      --exclude-labels) shift; exclude_labels_override="${1:-}" ;;
      --dry-run) dry_run=true ;;
      --once) once=true ;;
    esac
    shift || true
  done

  local cfg repo source_labels processing_label waiting_label done_label auto_close poll_interval max_workers worktree_dir
  cfg=$(load_issue_automation_config)
  IFS='|' read -r repo source_labels processing_label waiting_label done_label auto_close poll_interval max_workers worktree_dir <<< "$cfg"

  repo=$(resolve_issue_repo "$repo_override")
  [ -n "$interval_override" ] && poll_interval="$interval_override"
  [ -n "$workers_override" ] && max_workers="$workers_override"

  local autonomous_mode=false
  local cli_backend=auto
  if [ -f ".pipeline/config.json" ]; then
    autonomous_mode=$(python3 -c "import json; print(str(bool(json.load(open('.pipeline/config.json')).get('autonomous_mode', False))).lower())" 2>/dev/null || echo false)
    cli_backend=$(python3 -c "import json; print(json.load(open('.pipeline/config.json')).get('model_routing', {}).get('cli_backend', 'auto'))" 2>/dev/null || echo auto)
  fi
  if [ "$autonomous_mode" != "true" ] && [ "${max_workers:-1}" -gt 1 ] 2>/dev/null; then
    echo "  ⚠  非自治模式下为保证 TUI 交互可用，watcher 将最大并发降为 1"
    max_workers=1
  fi
  if [ "${max_workers:-1}" -gt 1 ] 2>/dev/null && [ "$cli_backend" != "opencode" ]; then
    echo "  ⚠  当前仅对 OpenCode 后端启用后台并行 worker，已将最大并发降为 1"
    max_workers=1
  fi

  ensure_issue_label "$repo" "$processing_label" "FBCA04" "流水线处理中"
  ensure_issue_label "$repo" "$waiting_label" "D93F0B" "等待人工处理"
  ensure_issue_label "$repo" "$done_label" "0E8A16" "流水线已完成"

  echo ""
  echo "  ▶ 启动 Issue Watcher"
  echo "    repo: ${repo}"
  if [ -n "$source_labels" ]; then
    echo "    source labels: ${source_labels}"
  else
    echo "    source labels: (all open issues)"
  fi
  [ -n "$include_labels_override" ] && echo "    include labels: ${include_labels_override}"
  [ -n "$exclude_labels_override" ] && echo "    exclude labels: ${exclude_labels_override}"
  [ -n "$include_labels_override" ] && echo "    note: --labels 是在 source labels 基础上的追加过滤"
  [ "$dry_run" = true ] && echo "    mode: dry-run（仅预览，不实际执行）"
  echo "    scheduling: urgent/bug/security 优先，其次按创建时间"
  echo "    max workers: ${max_workers}"
  echo "    poll interval: ${poll_interval}s"
  echo ""

  while true; do
    local active_workers=0
    if [ -f ".pipeline/issues/watch-state.json" ]; then
      active_workers=$(python3 - ".pipeline/issues/watch-state.json" <<'PY'
import json, os, signal, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
alive = []
for worker in data.get('workers', []):
    pid = worker.get('pid')
    if not pid:
        continue
    try:
        os.kill(int(pid), 0)
        alive.append(worker)
    except OSError:
        pass
data['workers'] = alive
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print(len(alive))
PY
)
    fi

    local slots=$((max_workers - active_workers))
    if [ "$slots" -lt 0 ]; then
      slots=0
    fi

    if [ "$slots" -gt 0 ]; then
      local candidates raw_issues
      raw_issues=$(gh issue list --repo "$repo" --state open --limit 100 --json number,title,labels,createdAt,url)
      candidates=$(printf '%s' "$raw_issues" | python3 -c '
import json
import sys

source_csv, processing, waiting, done, include_csv, exclude_csv = sys.argv[1:7]
items = json.load(sys.stdin)

source_labels = {x.strip().lower() for x in source_csv.split(",") if x.strip()}
include_labels = {x.strip().lower() for x in include_csv.split(",") if x.strip()}
exclude_labels = {x.strip().lower() for x in exclude_csv.split(",") if x.strip()}

def score(labels):
    score = 0
    lower = {x.lower() for x in labels}
    if "p0" in lower or "critical" in lower or "urgent" in lower or "sev:critical" in lower:
        score += 1000
    if "p1" in lower or "high" in lower or "priority:high" in lower:
        score += 700
    if "bug" in lower or "regression" in lower or "hotfix" in lower:
        score += 400
    if "security" in lower or "security-fix" in lower:
        score += 350
    if "feature" in lower or "enhancement" in lower:
        score += 150
    if "question" in lower or "docs" in lower or "documentation" in lower:
        score += 50
    return score

candidates = []
for item in items:
    labels = {lbl.get("name", "") for lbl in item.get("labels", [])}
    lower_labels = {x.lower() for x in labels}
    if processing in labels or waiting in labels or done in labels:
        continue
    if source_labels and not (source_labels & lower_labels):
        continue
    if include_labels and not (include_labels & lower_labels):
        continue
    if exclude_labels and (exclude_labels & lower_labels):
        continue
    candidates.append({
        "number": item.get("number"),
        "title": item.get("title", ""),
        "url": item.get("url", ""),
        "score": score(labels),
        "labels": sorted(labels),
        "created_at": item.get("createdAt", ""),
    })

candidates.sort(key=lambda x: (-x["score"], x["created_at"], x["number"]))
for item in candidates:
    print(json.dumps(item, ensure_ascii=False))
' "$source_labels" "$processing_label" "$waiting_label" "$done_label" "$include_labels_override" "$exclude_labels_override")

      if [ -n "$candidates" ]; then
        local candidate_line issue_number
        local preview_count=0
        while IFS= read -r candidate_line; do
          [ -n "$candidate_line" ] || continue
          issue_number=$(printf '%s' "$candidate_line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['number'])")
          if [ "$dry_run" = true ]; then
            preview_count=$((preview_count + 1))
            printf '%s' "$candidate_line" | python3 -c "import json,sys; x=json.loads(sys.stdin.read()); print(f\"  - #{x['number']} score={x['score']} labels={','.join(x.get('labels', [])) or '-'} title={x.get('title','')} url={x.get('url','-')}\")"
          else
            if [ "$max_workers" -gt 1 ] 2>/dev/null; then
              cmd_issue run "$issue_number" --repo "$repo" --detach
            else
              cmd_issue run "$issue_number" --repo "$repo"
            fi
          fi
          slots=$((slots - 1))
          [ "$slots" -le 0 ] && break
        done <<< "$candidates"
        if [ "$dry_run" = true ]; then
          if [ "$preview_count" -eq 0 ]; then
            echo "  ℹ  dry-run: 本轮没有可执行 issue"
          else
            echo "  ✓ dry-run: 以上为本轮按优先级排序后的候选 issue"
          fi
        fi
      else
        echo "  ℹ  当前没有待处理 issue"
        if [ "$raw_issues" = "[]" ]; then
          echo "  ℹ  该仓库当前没有 open issue"
        elif [ -n "$source_labels" ]; then
          echo "  ℹ  原因：没有 issue 匹配 source labels = ${source_labels}"
        fi
      fi
    else
      echo "  ℹ  当前活跃 worker 数已达上限 (${active_workers}/${max_workers})"
    fi

    if [ "$once" = true ] || [ "$dry_run" = true ]; then
      break
    fi

    echo "  ⟳ watcher 休眠 ${poll_interval}s，等待下一轮轮询..."
    sleep "$poll_interval"
  done
}

case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  status)  shift; cmd_status "$@" ;;
  upgrade) cmd_upgrade ;;
  repair)  cmd_repair ;;
  doctor)  cmd_doctor ;;
  version) cmd_version ;;
  update)  cmd_update ;;
  run)     cmd_run ;;
  issue)   shift; cmd_issue "$@" ;;
  watch-issues) shift; cmd_watch_issues "$@" ;;
  scan)    cmd_scan "${2:-}" ;;
  replan)  cmd_replan ;;
  migrate) shift; cmd_migrate "$@" ;;
  __issue-worker) shift; cmd_issue_worker "$@" ;;
  *)       usage ;;
esac
TEAM_SCRIPT

chmod +x "$TEAM_CMD"
echo "  ✓ 'team' command installed at $TEAM_CMD"

# ── 4. Install global routing config ──────────────────────────────
echo ""
echo "▶ Step 4 — Global model routing config"

GLOBAL_ROUTING_DIR="$HOME/.config/team-pipeline"
GLOBAL_ROUTING_FILE="$GLOBAL_ROUTING_DIR/routing.json"
mkdir -p "$GLOBAL_ROUTING_DIR"

if [ -f "$GLOBAL_ROUTING_FILE" ]; then
  echo "  ⚠  $GLOBAL_ROUTING_FILE already exists, skipping"
  echo "     To reset: rm $GLOBAL_ROUTING_FILE && bash install.sh"
else
  cp "$REPO_DIR/templates/routing.json" "$GLOBAL_ROUTING_FILE"
  echo "  ✓ $GLOBAL_ROUTING_FILE"
  echo ""
  echo "  To enable model routing globally:"
  echo "    1. Edit $GLOBAL_ROUTING_FILE"
  echo "    2. Set \"enabled\": true"
  echo "    3. Fill in api_key for your provider"
fi

# Copy install.sh, scripts, and agent sources for `team init` / `team migrate`
cp "$REPO_DIR/install.sh" "$TEMPLATES_DST/install.sh" 2>/dev/null || true
mkdir -p "$TEMPLATES_DST/scripts"
cp "$REPO_DIR/scripts/build-agents.py" "$TEMPLATES_DST/scripts/" 2>/dev/null || true
cp "$REPO_DIR/scripts/migrate-to-platform.sh" "$TEMPLATES_DST/scripts/" 2>/dev/null || true

# Agent sources (canonical CC definitions) — used by transpiler at init/migrate time
mkdir -p "$TEMPLATES_DST/agents"
for f in "$REPO_DIR/agents/"*.md; do
  [ -f "$f" ] && cp "$f" "$TEMPLATES_DST/agents/$(basename "$f")"
done
if [ -d "$REPO_DIR/agents/platforms" ]; then
  cp -r "$REPO_DIR/agents/platforms" "$TEMPLATES_DST/agents/platforms" 2>/dev/null || true
fi
echo "  ✓ Agent sources installed to $TEMPLATES_DST/agents/"

# ── PATH check ──────────────────────────────────────────────────────
echo ""
if echo "$PATH" | grep -q "$BIN_DIR"; then
  echo "  ✓ $BIN_DIR is in PATH"
else
  echo "  ⚠  Add the following to your shell profile (~/.bashrc or ~/.zshrc):"
  echo ""
  echo '     export PATH="$HOME/.local/bin:$PATH"'
  echo ""
  echo "  Then restart your terminal or run: source ~/.bashrc"
fi

# ── Verify agents ────────────────────────────────────────────────────
echo ""
echo "── Verification ────────────────────────────────────────────────"
REQUIRED=(pilot clarifier architect auditor-gate auditor-biz auditor-tech auditor-qa auditor-ops resolver planner contract-formalizer builder-frontend builder-backend builder-dba builder-security builder-infra simplifier inspector tester documenter deployer monitor migrator optimizer translator github-ops)
MISSING=0
for agent in "${REQUIRED[@]}"; do
  if [ ! -f "$AGENTS_DST/$agent.md" ]; then
    echo "  ✗ $agent (missing)"
    MISSING=$((MISSING + 1))
  fi
done

if [ "$MISSING" -eq 0 ]; then
  echo "  ✓ All 26 agents verified"
else
  echo "  ❌ $MISSING agents missing"
  exit 1
fi

# ── Verify & enable required plugins ──────────────────────────────────
echo ""
echo "── Required Plugins ────────────────────────────────────────────"

SETTINGS_FILE="$HOME/.claude/settings.json"
REQUIRED_PLUGINS=("code-review" "code-simplifier")

# Ensure settings.json exists with basic structure
if [ ! -f "$SETTINGS_FILE" ]; then
  mkdir -p "$HOME/.claude"
  echo '{"enabledPlugins":{}}' > "$SETTINGS_FILE"
  echo "  ✓ Created $SETTINGS_FILE"
fi

PLUGINS_CHANGED=false
for plugin in "${REQUIRED_PLUGINS[@]}"; do
  PLUGIN_KEY="${plugin}@claude-plugins-official"
  # Check if plugin is already enabled
  if python3 -c "
import json, sys
s = json.load(open('$SETTINGS_FILE'))
ep = s.get('enabledPlugins', {})
sys.exit(0 if ep.get('$PLUGIN_KEY') == True else 1)
" 2>/dev/null; then
    echo "  ✓ $plugin (enabled)"
  else
    # Enable the plugin (atomic write: tmp → mv)
    python3 -c "
import json, os, tempfile
sf = '$SETTINGS_FILE'
s = json.load(open(sf))
if 'enabledPlugins' not in s:
    s['enabledPlugins'] = {}
s['enabledPlugins']['$PLUGIN_KEY'] = True
d = os.path.dirname(sf)
fd, tmp = tempfile.mkstemp(dir=d, suffix='.tmp')
with os.fdopen(fd, 'w') as f:
    json.dump(s, f, indent=2)
os.replace(tmp, sf)
" 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "  ✓ $plugin (auto-enabled)"
      PLUGINS_CHANGED=true
    else
      echo "  ⚠  $plugin — failed to enable, please enable manually:"
      echo "     Add '\"$PLUGIN_KEY\": true' to enabledPlugins in $SETTINGS_FILE"
    fi
  fi
done

if [ "$PLUGINS_CHANGED" = true ]; then
  echo ""
  echo "  ℹ  Plugins enabled. Restart Claude Code for changes to take effect."
fi

# ── Done ─────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅  Installation complete!                          ║"
echo "║                                                      ║"
echo "║  Quick start:                                        ║"
echo "║    cd your-project                                   ║"
echo "║    team init                  # CC (default)         ║"
echo "║    team init --platform codex # or codex/cursor/oc   ║"
echo "║    team run                   # start pipeline       ║"
echo "║                                                      ║"
echo "║  Switch platform for a repo:                         ║"
echo "║    team migrate <cc|codex|cursor|opencode>           ║"
echo "║                                                      ║"
echo "║  Agents are stored per-repo in .pipeline/agents/     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
