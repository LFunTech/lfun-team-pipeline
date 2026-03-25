# lfun-team-pipeline

> Multi-platform AI multi-agent software delivery pipeline — 28 AI agents collaborating from requirements to production.

[中文](README.md) | **English**

---

## What is this?

**lfun-team-pipeline** is a production-grade software delivery pipeline that supports **Claude Code / Codex / Cursor / OpenCode** — four major AI coding platforms. It orchestrates **28 specialized AI agents** that collaborate like a real engineering team — requirements analyst, architect, multiple parallel developers, QA engineers, a deployer, and a post-launch monitor — all driven by a single Pilot.

You describe the full system you want to build. The pipeline automatically decomposes it into an ordered proposal queue and delivers each one sequentially or in parallel. Each proposal runs through the complete requirements-to-production lifecycle independently. Supports routing builder agents to external LLMs (e.g., GLM-5, Ollama) to significantly reduce token costs. Team members can each use their preferred platform, and projects can seamlessly switch between platforms.

```
system planning → proposal queue → [P-001: clarify → architect → build → test → deploy → monitor] → P-002 → ...
                                    ↕ proposals in the same parallel_group execute concurrently
```

## Pipeline Overview

```
System Plan   System Planning (first run, interactive decomposition + parallel topology)
Pick Proposal Pick next proposal/group (same parallel_group runs concurrently)
Memory Load   Project memory injection (constraints → Clarifier/Architect)
Phase 0       Clarifier            Requirements elicitation (up to 5 rounds; skipped in autonomous)
Phase 0.5     AutoStep             Requirement completeness check
Phase 1       Architect            System design + ADR generation
Gate A        Auditor-Gate         Biz / Tech / QA / Ops review (single spawn)
Phase 2.0a    GitHub Ops           GitHub repo creation
Phase 2.0b    AutoStep             Dependency scan + credential pause
Phase 2       Planner              Task breakdown for each builder
Phase 2.1     AutoStep             Assumption propagation validation
Gate B        Auditor-Gate         Contract and task review (single spawn)
Phase 2.5     Contract Formalizer  OpenAPI contract generation
Phase 2.6∥2.7 AutoStep (parallel)  Schema validation ∥ Semantic validation
Phase 3       Builders (wave-parallel) Backend · Frontend · DBA · Infra · Security + conditional
Phase 3.0b    AutoStep             Build verification
Phase 3.0d∥3.1∥3.2∥3.3 AutoStep (parallel) Duplicate detect · Static analysis · Regression · Diff
Phase 3.5     Simplifier           Code simplification
Phase 3.6     AutoStep             Post-simplification regression
Gate C        Inspector            Deep code review
Phase 3.7     AutoStep             Contract compliance check
Phase 4a      Tester               Integration + unit test generation
Phase 4a.1    AutoStep             Test failure mapping (on FAIL only)
Phase 4.2     AutoStep             Coverage enforcement
Phase 4b      Optimizer            Performance optimization (conditional)
Gate D        Auditor-QA           Test acceptance
AutoStep      API Change Detector  Breaking change detection
Phase 5       Documenter           README · CHANGELOG · API docs
Phase 5.1     AutoStep             CHANGELOG consistency check
Gate E        Auditor-QA ∥ Auditor-Tech (parallel) Documentation review
Phase 5.9     GitHub Ops           Woodpecker CI config push
Phase 6.0     AutoStep             Pre-deploy readiness check
Phase 6       Deployer             Docker Compose deployment + smoke test
Phase 7       Monitor              30-minute health observation window
Memory Consolidation  Extract and persist constraints (user-confirmed)
Mark Done     Mark proposal completed, auto-loop to next
```

## Supported Platforms

| Platform | Launch Command | Agent Format | Notes |
|----------|---------------|-------------|-------|
| [Claude Code](https://claude.ai/code) | `claude --agent pilot` | `.md` | Native support, CLI-driven |
| [Codex](https://openai.com/codex) | `codex --full-auto` | `.toml` | AGENTS.md auto-loads pilot instructions |
| [Cursor](https://cursor.sh) | Agent mode → `/pilot` | `.md` | IDE built-in Agent mode |
| [OpenCode](https://opencode.ai) | `opencode run --agent build` | `.md` | Uses `opencode.json` + `.opencode/agents/`, with `AGENTS.md` as shared context |

The same project can seamlessly switch between platforms — `state.json` format is fully compatible.

## Prerequisites

| Requirement | Details |
|-------------|---------|
| AI coding tool (any one) | Claude Code / Codex / Cursor / OpenCode |
| Git | v2.28+ (worktree support required) |
| Python 3 | Agent transpiler and state management |
| Docker + Docker Compose | For Phase 6 deployment |
| `gh` CLI | For GitHub integration (Phase 5.9) |

## Installation

```bash
git clone https://github.com/LFunTech/lfun-team-pipeline.git
cd lfun-team-pipeline
bash install.sh
```

The installer sets up:
- `team` CLI command (to `~/.local/bin/`)
- Agent sources + transpiler (to `~/.local/share/team-pipeline/`)
- Pipeline templates (autosteps, playbook, etc.)
- CC agents to `~/.claude/agents/` (backward compatible)

> **Important:** Agent definitions are now **persisted per-repo**. `team init` generates platform-specific agents into `.pipeline/agents/`, so each repo independently manages its own agent version.

> **PATH note:** If the `team` command is not found after install, add `$HOME/.local/bin` to your PATH:
> ```bash
> echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
> ```

## Quick Start — New Project

```bash
# 1. Create your project and initialize the pipeline (specify platform)
mkdir my-project && cd my-project
git init
team init                          # Default: Claude Code
team init --platform codex         # Or specify: codex / cursor / opencode

# 2. Edit pipeline config (set project_name, tech stack, coverage threshold)
$EDITOR .pipeline/config.json

# 3. Start the pipeline — describe the full system you want to build
team run
```

### `team run` per-platform behavior

| Platform | Execution | Batch loop |
|----------|-----------|------------|
| **Claude Code** | PTY Runner watches for `[EXIT]`, kills & restarts next batch | **Full auto-loop** — one `team run` does it all |
| **Codex** | Launches `codex --full-auto` interactive TUI with full context | **Single batch** — `team run` again to continue (uses `codex resume`) |
| **OpenCode** | Uses TUI for interactive phases; prefers `opencode run --continue` for automatic phases | **Outer `team run` loop** — after each round it reads `state.json`, waits a few seconds, then starts the next round automatically if the pipeline is not done |
| **Cursor** | IDE-driven, enter `/pilot` in Agent mode | **IDE interaction** |

> **Codex vs OpenCode loop behavior**
> CC uses a PTY runner inside a single `team run` process to restart `claude` batch by batch.
> **OpenCode** uses a shell-level loop: interactive phases such as `system-planning` stay in TUI with auto-injected prompts, while automatic phases prefer `opencode run --continue`.
> **Codex** remains primarily one interactive session per batch; run `team run` again to continue.

> If you want OpenCode to stay fully interactive throughout the pipeline, set `opencode.interaction_mode` to `tui` in `.pipeline/config.json`, or run `TEAM_OPENCODE_INTERACTION_MODE=tui team run` for a temporary override.
> `team run` now prints section banners around OpenCode output and renders phases with human-friendly labels, such as `并行实现 (3.build)` and `需求澄清 (0.clarify)`, so you can quickly tell whether the current output is TUI interaction, automatic execution, or the wait-before-next-round step.

It pauses automatically when human intervention is needed:

```bash
# Check current progress (color status panel)
team status
```

## Autonomous Mode

> New in v6.4

Set `"autonomous_mode": true` to have the pipeline **automatically execute all proposals** after System Planning, with zero human intervention.

**Workflow:**

```
                    ┌─ System Planning (interactive) ──┐
                    │  Describe the system              │
                    │  Confirm the blueprint            │
                    │  Confirm detail for each proposal │
                    └────────┬──────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  Fully automatic │
                    │  P-001 → P-002   │
                    │  → ... → Done    │
                    └─────────────────┘
```

**Key Design: Front-loaded Requirements**

The core insight of autonomous mode is **shifting requirement gathering into the planning phase**. During System Planning, each proposal is not just confirmed with a scope — you also review structured requirement details for each one:

- User stories
- Business rules
- Acceptance criteria
- API overview
- Data entities
- Non-functional requirements

These details are stored in each proposal's `detail` field in `proposal-queue.json`. During execution, the Pilot generates the requirement document directly from confirmed details without spawning the Clarifier agent, saving one agent call.

**Usage:**

```bash
cd my-project
team init

# Edit config: set autonomous_mode to true
cat > .pipeline/config.json << 'EOF'
{
  "project_name": "my-app",
  "autonomous_mode": true,
  ...
}
EOF

# Start the pipeline
team run
# → System Planning interacts with you (describe system, confirm blueprint, confirm proposal details)
# → After planning, all proposals execute automatically with no further interaction
```

**Human interaction points skipped in autonomous mode:**

| Pause Point | Interactive Mode | Autonomous Mode |
|-------------|-----------------|-----------------|
| Phase 0 Requirements | Up to 5 Q&A rounds | Skipped (generated from detail) |
| Phase 2.0b Credentials | Pauses for user input | Skipped (WARN logged) |
| Memory Consolidation | Waits for user confirmation | Auto-accepted (conflicts preserve old value) |

> **Note:** System Planning always requires human interaction. Autonomous mode only affects proposal execution phases.

## Integrating into an Existing Repository

The pipeline can add new features or modules to any existing codebase.

**Step 1 — Initialize**

```bash
cd your-existing-repo
team init --platform codex   # or cc / cursor / opencode
```

This only adds `.pipeline/` (including `agents/`) and platform-specific context files (`CLAUDE.md`/`AGENTS.md`/`.cursor/rules/`) — it does not touch any existing code.

**Step 2 — Configure**

Edit `.pipeline/config.json` to match your existing stack:

```json
{
  "project_name": "your-repo-name",
  "autonomous_mode": false,
  "testing": {
    "coverage_tool": "cargo-tarpaulin",   // match your existing test setup
    "coverage_threshold": 70              // adjust to current baseline
  },
  "autosteps": {
    "contract_compliance": {
      "service_start_cmd": "cargo run",   // your existing start command
      "service_base_url": "http://localhost:8080",
      "health_path": "/health"
    }
  }
}
```

**Step 3 — Commit the pipeline config**

```bash
git add .pipeline/config.json .pipeline/autosteps/ CLAUDE.md AGENTS.md .cursor/
git commit -m "chore: add lfun-team-pipeline"
```

**Step 4 — Start the pipeline**

```bash
team run
```

Describe the new feature or full system you want to add. On first run, the Pilot enters System Planning to generate a proposal queue, then auto-loops to execute each proposal. Builders will read the existing codebase in their git worktrees and implement changes that are consistent with the current architecture.

**Important notes for existing repos:**

- Builders work in isolated git worktrees (`.worktrees/`) — your current branch is never modified directly
- The pipeline reads existing code to understand patterns before writing new code
- Gate C (Inspector) performs a diff-scoped review — it only reviews new/changed code, not the entire codebase
- Coverage thresholds should be set to match or slightly exceed your current baseline, not a fixed target like 80%
- If your project already has an OpenAPI spec, inform the pilot at Phase 2.5 to avoid regenerating from scratch

## Multi-Proposal System Delivery

The pipeline supports describing a complete system upfront, automatically decomposing it into an ordered proposal queue, and delivering each proposal sequentially.

**Flow overview:**

```
Describe system → System Planning → Proposal Queue → [P-001 execute] → [P-002 execute] → ... → All done
```

**Step 1 — Start**

```bash
team run
```

On first run, the Pilot enters System Planning and guides you through describing the full system. Once complete, it generates:
- `.pipeline/artifacts/system-blueprint.md`: System blueprint (tech stack, domain decomposition, data model skeleton)
- `.pipeline/proposal-queue.json`: Ordered proposal queue

After System Planning, `team run` continues automatically by phase: interactive phases open TUI, while automatic phases go through `opencode run --continue`. If no human intervention is needed, it runs until completion.

```bash
# Check current progress
team status
```

**Check proposal progress**

```bash
python3 -c "
import json
q = json.load(open('.pipeline/proposal-queue.json'))
for p in q['proposals']:
    s = '✓' if p['status'] == 'completed' else ('▶' if p['status'] == 'running' else '○')
    print(f'  {s} [{p[\"id\"]}] {p[\"title\"]}')
"
```

**Check execution log**

```bash
python3 -c "
import json
s = json.load(open('.pipeline/state.json'))
for e in s.get('execution_log', []):
    rb = f' → {e[\"rollback_to\"]}' if e.get('rollback_to') else ''
    print(f'[{e[\"step\"]}] {e[\"result\"]}{rb} (attempt {e[\"attempt\"]})')
"
```

**Re-plan**

```bash
# Preserve completed work, re-plan remaining proposals
team replan
team run
```

## Project Memory

The pipeline automatically maintains `.pipeline/project-memory.json`, recording cross-proposal business and architecture constraints:

- **Constraint registry**: Automatically extracted after each proposal completes (in MUST/MUST NOT form), written after user confirmation (auto-accepted in autonomous mode)
- **Implementation footprint**: Records APIs, database tables, and key files implemented by each proposal
- **Conflict detection**: When a new proposal conflicts with existing constraints, the Clarifier and Architect proactively flag the issue

For day-to-day business tweaks that do not go through a full proposal, Pilot now performs a lightweight non-proposal triage first:

- **Implementation-only tweaks** (refactors, styling, copy edits, tests) are applied directly and do not enter requirement memory
- **Business small changes** are first recorded in `.pipeline/micro-changes.json` as one-line "minimum requirement facts"
- **Long-lived rules** are then promoted into `.pipeline/project-memory.json` during Memory Consolidation
- **High-risk or cross-boundary changes** (API, schema, security, billing, cross-domain workflows) are escalated into full proposals

You can also record a one-line business tweak manually:

```bash
PIPELINE_DIR=.pipeline bash .pipeline/autosteps/record-micro-change.sh \
  --raw "Set export links to 7 days by default" \
  --normalized "Change the default export link TTL to 7 days" \
  --domain "Export" \
  --memory-candidate true \
  --constraint "Export links must default to a 7-day TTL"

PIPELINE_DIR=.pipeline bash .pipeline/autosteps/sync-micro-changes-to-memory.sh

PIPELINE_DIR=.pipeline bash .pipeline/autosteps/list-micro-changes.sh --pending
```

The first command appends a micro-change record, the second promotes durable rules into project memory, and the third lists pending memory candidates that have not yet been consumed.

Project memory ensures that business rules and technical decisions remain consistent across multiple proposals, preventing contradictions.

## CLI Commands

| Command | Description |
|---------|-------------|
| `team init [--platform <cc\|codex\|cursor\|opencode>]` | Initialize pipeline, generate platform-specific agents to `.pipeline/agents/` |
| `team run` | CC: auto-loop all batches; OpenCode: outer loop with TUI for interactive phases and `run --continue` for automatic phases; Codex: one TUI batch at a time |
| `team issue run <number> [--repo <owner/repo>]` | Convert a GitHub Issue into a single-proposal pipeline run inside its own worktree |
| `team watch-issues [--once] [--interval <sec>] [--max-workers <n>] [--labels a,b] [--exclude-labels x,y] [--dry-run]` | Poll labeled GitHub Issues and dispatch them automatically |
| `team migrate <cc\|codex\|cursor\|opencode> [--force]` | Switch platform (regenerates `.pipeline/agents/`, auto-snapshots) |
| `team migrate --rollback` | Rollback to pre-migration state |
| `team status` | Show pipeline execution progress (color panels: overview, Proposals, Issues, Changes, execution log; Changes shows pending micro-change summaries waiting for memory consolidation) |
| `team upgrade` | In-place upgrade of playbook + autosteps + agents (preserves state, artifacts, proposal queue) |
| `team repair` | In-place repair of playbook + autosteps + llm-router + agents (preserves config, state, artifacts, proposal queue) |
| `team doctor` | Check whether the repo runtime already includes the new parallel safety guards |
| `team replan` | Re-plan proposal queue (preserves completed work) |
| `team scan` | Manually trigger project scan (component registry) |
| `team version` | Print version |
| `team update` | Show instructions for updating global installation |

**Upgrading the pipeline version:**

```bash
# 1. Update global templates
cd /path/to/lfun-team-pipeline && bash install.sh

# 2. In-place upgrade in your project
cd /path/to/my-project && team upgrade

# 3. Continue execution
team run
```

`team upgrade` overwrites `playbook.md`, `autosteps/`, and regenerates `agents/` for the current platform, while preserving `config.json`, `state.json`, `artifacts/`, and `proposal-queue.json`, ensuring upgrades don't interrupt a running pipeline.

When a project only has runtime drift or broken pipeline files - for example missing scripts, stale templates, a broken `llm-router.sh`, or inconsistent project-local agents - prefer `team repair`. It restores the runnable pipeline files in place while keeping the current `state.json`, `artifacts/`, and proposal queue intact.

If you suspect the current repo is still running with the old parallel behavior, run `team doctor` first. It checks `.pipeline/playbook.md`, the key autosteps, and `state.json` for the Builder file-conflict guard, proposal parallel precheck, and the newer runtime fields; if it fails, follow up with `team repair`.

## Safety & Rollback

All file-modifying operations have built-in protection:

| Operation | Protection |
|-----------|-----------|
| `team init` | Auto-cleans `.pipeline/` on failure if freshly created |
| `team migrate` | Auto-snapshots before migration; auto-rollback on transpiler failure; atomic `config.json` writes |
| `team migrate --rollback` | One-command restore to pre-migration state (agents + config) |
| `team upgrade` | Backs up all files before overwriting; auto-restores agents on failure |
| `bash install.sh` | Template directory backed up before overwrite; atomic `settings.json` writes |

**Global environment rollback:**

```bash
# Rollback to pre-install global state (auto-finds latest backup)
bash scripts/rollback.sh

# Specify backup directory
bash scripts/rollback.sh ~/.local/share/team-pipeline-backup-20260322_215623
```

**Backward compatibility:** Projects created with the old `team init` (no `.pipeline/agents/`) work normally with the new CLI — `team run` automatically falls back to global `~/.claude/agents/`. `team upgrade` will suggest using `team migrate` to enable per-repo agents.

## `team init` Output

```
.pipeline/
├── config.json          ← Pipeline configuration (edit before starting, includes model routing)
├── playbook.md          ← Phase execution playbook (loaded on-demand by Pilot)
├── llm-router.sh        ← Multi-platform model routing dispatcher
├── project-memory.json  ← Project memory (cross-pipeline constraint registry)
├── micro-changes.json   ← Non-proposal business tweak records (minimum requirement facts)
├── agents/              ← ★ Platform-specific agent definitions (generated at init time)
├── autosteps/           ← 20 automated scripts (platform-agnostic)
├── artifacts/           ← Runtime outputs (auto-generated)
└── history/             ← Past proposal artifact archives
CLAUDE.md                ← Pipeline context (generated for CC/Cursor platforms)
AGENTS.md                ← Pipeline context + Pilot instructions (generated for Codex/OpenCode)
opencode.json            ← OpenCode project config (generated for OpenCode, using `instructions: ["AGENTS.md"]`)
.opencode/agents/        ← OpenCode project-level agent definitions (generated for OpenCode)
.cursor/rules/pipeline.md ← Cursor IDE pipeline rules (generated for Cursor platform)
```

> The file format in `.pipeline/agents/` depends on the platform chosen at init time: CC/Cursor/OpenCode use `.md`, Codex uses `.toml`.

## Configuration Reference

```json
{
  "project_name": "my-app",
  "autonomous_mode": false,
  "testing": {
    "coverage_tool": "nyc",           // nyc | cargo-tarpaulin | pytest-cov | go test
    "coverage_threshold": 80
  },
  "autosteps": {
    "contract_compliance": {
      "service_start_cmd": "npm start",
      "service_base_url": "http://localhost:3000",
      "health_path": "/health"
    }
  },
  "model_routing": {
    "enabled": false,                 // route some agents to external LLMs
    "cli_backend": "auto",            // auto | claude | codex | opencode
    "providers": {
      "glm5": {
        "base_url": "https://coding.dashscope.aliyuncs.com/apps/anthropic",
        "api_key": "",                // direct value, or leave empty and use api_key_env
        "api_key_env": "GLM5_API_KEY",
        "model": "glm-5"
      }
    },
    "routes": {
      "builder-backend": "glm5",      // unlisted agents default to Claude
      "builder-frontend": "glm5",
      "tester": "glm5"
    }
  }
}
```

| Field | Description | Default |
|-------|-------------|---------|
| `project_name` | Project name | `YOUR_PROJECT_NAME` |
| `autonomous_mode` | Autonomous mode: auto-execute all proposals after planning | `false` |
| `testing.coverage_tool` | Coverage tool | `nyc` |
| `testing.coverage_threshold` | Coverage threshold (%) | `80` |
| `max_attempts.default` | Max retries per phase | `3` |
| `model_routing.enabled` | Enable model routing (route some agents to external LLMs) | `false` |
| `model_routing.cli_backend` | CLI backend (`auto` / `claude` / `codex` / `opencode`) | `auto` |
| `opencode.interaction_mode` | OpenCode interaction mode (`hybrid` / `tui` / `run`) | `hybrid` |
| `issue_automation.repo` | Default GitHub repo watched by the issue watcher (empty = current repo) | `""` |
| `issue_automation.source_labels` | Source label filter for watched issues; empty means all open issues | `""` |
| `issue_automation.max_workers` | Max issue workers (auto-capped to 1 outside autonomous OpenCode mode) | `1` |
| `model_routing.providers` | External LLM provider configs | `glm5`, `ollama` |
| `model_routing.routes` | Agent → Provider mapping | see template |

## GitHub Issue Automation

GitHub Issues can now act as a dedicated Pilot input source:

```bash
# Process one issue
team issue run 123

# Start a watcher for label=pipeline
team watch-issues

# Scan once and exit
team watch-issues --once
```

- `team issue run` creates an isolated workspace at `.worktrees/issues/issue-<number>`
- It generates `.pipeline/artifacts/issue-context.md`, a single-proposal `proposal-queue.json`, and a fresh `state.json`
- When Pilot sees `issue-context.md`, it switches into GitHub-Issue single-proposal delivery mode
- On OpenCode, clarification phases automatically switch back to TUI; automatic phases keep using `run --continue`
- By default the watcher scans open issues directly; use `issue_automation.source_labels` or `--labels` to filter the source set
- The watcher reflects progress back to GitHub with labels for processing / waiting-human / done
- `watch-issues` prioritizes issues labeled `urgent` / `critical` / `p0` / `bug` / `security`, then falls back to creation time ordering
- `watch-issues --dry-run` previews the current scheduling order without actually executing issues
- The Issues panel in `team status` shows the latest GitHub writeback time
- The Issues panel in `team status` also shows recent issue URLs, worktrees, and log paths for quick handoff
- The Issues panel also includes a compact `issue -> worktree/log/url` summary for fast copy/paste handoff
- `team status` highlights `waiting-user` issues in a dedicated `Waiting-User` section and sorts them by `escalation > 0.clarify > 2.0b.depend-collect > memory-consolidation` takeover priority

## Multi-Platform Support

> New in v6.5

The pipeline supports four AI coding platforms. Agent definitions are transpiled from canonical sources (`agents/*.md`) and **persisted per-repo** in `.pipeline/agents/`.

**Core Architecture:**

```
agents/*.md (CC format, canonical source)
      │
      ▼
  build-agents.py (transpiler)
      │
      ├── team init --platform cc      → .pipeline/agents/*.md  (CC format)
      ├── team init --platform codex   → .pipeline/agents/*.toml (Codex format)
      ├── team init --platform cursor  → .pipeline/agents/*.md  (Cursor format)
      └── team init --platform opencode→ .pipeline/agents/*.md  (OpenCode format)
```

**Each repo independently manages its own platform.** Repo A can use Cursor while Repo B uses Codex, with no interference.

**Platform Comparison:**

| Feature | Claude Code | Codex | Cursor | OpenCode |
|---------|------------|-------|--------|----------|
| Agent Format | `.md` (YAML FM) | `.toml` | `.md` (YAML FM) | `.md` (YAML FM) |
| Pilot Loading | `--agent pilot.md` | `AGENTS.md` auto-loaded | `/pilot` command | `AGENTS.md` auto-loaded |
| Sub-agent Invocation | `Agent(name, prompt)` | `spawn_agent` / natural language | `Task(subagent_type, prompt)` | `@name` delegation |
| Shell Tool | `Bash()` | `bash()` | `Shell()` | `bash()` |
| Permission Model | `permissionMode` | `sandbox_mode` | `readonly` | implicit |

**OpenCode entrypoint:** OpenCode's official project entrypoints are `opencode.json` and `.opencode/agents/`. This repo generates `opencode.json` with `"$schema": "https://opencode.ai/config.json"` and `"instructions": ["AGENTS.md"]` so shared project instructions are loaded the OpenCode-native way. The canonical pipeline agents still live in `.pipeline/agents/*.md` and are synced to `.opencode/agents/*.md`; the OpenCode-specific Pilot source lives at `agents/platforms/opencode/pilot.md`.

**OpenCode compatibility notes:**

- `opencode.json` must use `instructions`; do not generate the legacy `context` field
- `.opencode/agents/*.md` frontmatter must render `description`, `mode`, `agent`, and `model` as valid string scalars; descriptions like `[Pipeline] ...` must be quoted so YAML does not parse them as arrays
- OpenCode `model` cannot use pipeline-internal shorthands like `inherit` or `sonnet`; use an explicit `provider/model` id or omit the field so OpenCode inherits the default model
- OpenCode CLI routing/fallback paths should call `opencode run`, not the non-existent `opencode exec`
- During OpenCode project upgrades, regenerate `.pipeline/agents/` first and sync `.opencode/agents/` afterward so stale agent files do not survive the upgrade

**Skill Dependency Differences:**

| Skill | Claude Code | Cursor | Codex | OpenCode |
|-------|------------|--------|-------|----------|
| code-review | `Skill("code-review")` (CodeRabbit CLI) | Built-in `code-reviewer` subagent | Requires CodeRabbit CLI | Requires CodeRabbit CLI |
| code-simplifier | `Skill("code-simplifier")` (prompt) | Built-in `code-simplifier` subagent | Skill file auto-copied | Skill file auto-copied |
| frontend-design | `Skill("frontend-design")` (prompt) | Skill file auto-copied | Skill file auto-copied | Skill file auto-copied |

> The transpiler automatically converts `Skill("code-review")` to `Task(subagent_type="code-reviewer")` for Cursor — no manual adjustment needed.

**Switching platforms:**

```bash
# Specify platform at init time
team init --platform codex

# Switch anytime (auto-snapshots, supports rollback)
team migrate cursor       # Regenerates .pipeline/agents/ for Cursor
team migrate cc           # Switch back to Claude Code
team migrate --rollback   # Rollback to pre-migration state
```

**CLI Backend Priority (highest to lowest):**

```
$PIPELINE_CLI_BACKEND env var (current terminal only)
    ↓
.pipeline/config.json → model_routing.cli_backend (project-level)
    ↓
Auto-detect (claude > codex > opencode)
```

## Model Routing

> New in v6.4

Route builder agents to external LLMs (e.g., GLM-5, local Ollama) while the default model handles review, architecture, and decision-making — significantly reducing token costs.

**Role Assignment:**

| Role | Agents | Description |
|------|--------|-------------|
| External LLM (workers) | Builders, Tester, Planner, Contract-Formalizer, Documenter, Optimizer, Translator, Migrator | Code implementation, testing, docs |
| Default model (lead) | Pilot, Clarifier, Architect, Simplifier, Inspector, all Auditors, Resolver, Deployer, Monitor | Requirements, architecture, code review, deployment decisions |

**Configuration (choose one):**

```bash
# Option A: Global config (set once, applies to all projects)
# Auto-created at ~/.config/team-pipeline/routing.json during install
# Edit to add API key and set enabled: true

# Option B: Project-level config (current project only, overrides global)
# Edit model_routing section in .pipeline/config.json
```

**Config merge priority:** Project `config.json` > Global `routing.json`.

**API key priority:** `api_key` (direct value) > `api_key_env` (env variable) > `.depend/llm.env`

**Auto-fallback:** When no API key is configured or routing is disabled, agents automatically fall back to the default model (exit code 10). The pipeline runs normally even without external LLM configuration.

## Parallel Execution

> New in v6.4

The pipeline supports parallelism at two levels:

**Within-batch parallelism:**

Steps with no dependencies within a batch run concurrently:
- Phase 3: Same-wave builders first pass a file-overlap check; they only run in parallel when their file sets do not overlap, otherwise the wave is downgraded into serialized sub-waves and each later sub-wave starts from the latest merged HEAD
- Phase 2.6 ∥ 2.7: Schema validation ∥ Semantic validation
- Phase 3.0d ∥ 3.1 ∥ 3.2 ∥ 3.3: Post-build analysis
- Gate E: auditor-qa ∥ auditor-tech

**Proposal-level parallelism:**

During System Planning, the pipeline computes a dependency topology across proposals. Proposals with no mutual dependencies first become candidates for the same `parallel_group`, but actual parallel execution is gated by `parallel-proposal-detector.py`: if a proposal lacks detail/domains, or overlaps on API surface, data entities, or shared infrastructure keywords, the group is downgraded to single-proposal execution before any worktree is spawned.

```
P-001 ──┐
P-002 ──┼── parallel_group: 1 → precheck PASS -> run concurrently -> merge in order
P-003 ──┘
P-004 ────── parallel_group: 2 → waits for group 1
```

## GitHub + Woodpecker CI Integration

With GitHub and Woodpecker credentials in `.depend/`, Phase 5.9 automatically:
1. Creates a GitHub repository under your organization
2. Pushes all code
3. Activates Woodpecker CI pipelines for three environments (test / staging / prod)

## Tech Stack Support

| Backend | Frontend | Database | Infrastructure |
|---------|----------|----------|----------------|
| Rust + Axum | React | PostgreSQL | Docker Compose |
| Go + Gin | Vue 3 | MySQL | Woodpecker CI |
| Python + FastAPI | — | Redis | GitHub Actions |
| Node.js + Express | — | SQLite | — |

## License

MIT — see [LICENSE](LICENSE)
