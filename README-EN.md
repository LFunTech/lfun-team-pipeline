# lfun-team-pipeline

> A multi-agent software delivery pipeline for Claude Code — 28 AI agents collaborating from requirements to production.

[中文](README.md) | **English**

---

## What is this?

**lfun-team-pipeline** orchestrates **28 specialized AI agents** that collaborate like a real engineering team — requirements analyst, architect, multiple parallel developers, QA engineers, a deployer, and a post-launch monitor — all driven by a single Pilot.

You describe the full system you want to build. The pipeline automatically decomposes it into an ordered proposal queue and delivers each one sequentially or in parallel. Each proposal runs through the complete requirements-to-production lifecycle independently. Supports routing builder agents to external LLMs (e.g., GLM-5, Ollama) to significantly reduce Claude token costs.

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

## Prerequisites

| Requirement | Details |
|-------------|---------|
| [Claude Code](https://claude.ai/code) | CLI tool (requires Pro, Max, or API subscription) |
| Git | v2.28+ (worktree support required) |
| Docker + Docker Compose | For Phase 6 deployment |
| `gh` CLI | For GitHub integration (Phase 5.9) |

## Installation

**Option A — One-liner (recommended):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LFunTech/lfun-team-pipeline/main/install.sh)
```

**Option B — Clone and install:**

```bash
git clone https://github.com/LFunTech/lfun-team-pipeline.git
cd lfun-team-pipeline
bash install.sh
```

> **PATH note:** If the `team` command is not found after install, add `$HOME/.local/bin` to your PATH:
> ```bash
> echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
> ```

## Quick Start — New Project

```bash
# 1. Create your project and initialize the pipeline
mkdir my-project && cd my-project
git init
team init

# 2. Edit pipeline config (set project_name, tech stack, coverage threshold)
$EDITOR .pipeline/config.json

# 3. Start the pipeline — describe the full system you want to build
claude --dangerously-skip-permissions --agent pilot
# First run enters System Planning, generates a proposal queue, then starts execution
# Each run executes one batch and exits; run again to continue the next batch
```

The pipeline uses a **batch execution model**: each `claude --dangerously-skip-permissions --agent pilot` invocation executes one batch (typically 1-3 phases), then exits. Run it again to continue. 12 batches cover the complete pipeline (Phase 0 through Phase 7).

```bash
# Continue to the next batch
claude --dangerously-skip-permissions --agent pilot

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
claude --dangerously-skip-permissions --agent pilot
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
team init
```

This only adds `.pipeline/` and `CLAUDE.md` — it does not touch any existing code.

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
git add .pipeline/config.json .pipeline/autosteps/ CLAUDE.md
git commit -m "chore: add lfun-team-pipeline"
```

**Step 4 — Start the pipeline**

```bash
claude --dangerously-skip-permissions --agent pilot
```

Describe the new feature or full system you want to add. On first run, the pilot enters System Planning to generate a proposal queue, then executes each proposal sequentially. Builders will read the existing codebase in their git worktrees and implement changes that are consistent with the current architecture.

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
claude --dangerously-skip-permissions --agent pilot
```

On first run, the Pilot enters System Planning and guides you through describing the full system. Once complete, it generates:
- `.pipeline/artifacts/system-blueprint.md`: System blueprint (tech stack, domain decomposition, data model skeleton)
- `.pipeline/proposal-queue.json`: Ordered proposal queue

**Step 2 — Batch execution**

After System Planning completes, the first proposal starts automatically. Each run executes one batch and exits; run again to continue:

```bash
# Continue to the next batch
claude --dangerously-skip-permissions --agent pilot

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
claude --agent pilot
```

## Project Memory

The pipeline automatically maintains `.pipeline/project-memory.json`, recording cross-proposal business and architecture constraints:

- **Constraint registry**: Automatically extracted after each proposal completes (in MUST/MUST NOT form), written after user confirmation (auto-accepted in autonomous mode)
- **Implementation footprint**: Records APIs, database tables, and key files implemented by each proposal
- **Conflict detection**: When a new proposal conflicts with existing constraints, the Clarifier and Architect proactively flag the issue

Project memory ensures that business rules and technical decisions remain consistent across multiple proposals, preventing contradictions.

## CLI Commands

| Command | Description |
|---------|-------------|
| `team init` | Initialize pipeline in the current project directory |
| `team run` | Auto-loop batch execution until completion or human intervention needed |
| `team status` | Show pipeline execution progress (color panel: phase, proposal queue, execution log) |
| `team upgrade` | In-place upgrade of playbook + autosteps (preserves state.json, artifacts, proposal queue) |
| `team replan` | Re-plan proposal queue (preserves completed work) |
| `team scan` | Manually trigger project scan (component registry) |
| `team version` | Print version |
| `team update` | Show instructions for updating global installation |

**Upgrading the pipeline version:**

```bash
# 1. Update global agents and templates
cd /path/to/lfun-team-pipeline && bash install.sh

# 2. In-place upgrade in your project
cd /path/to/my-project && team upgrade

# 3. Continue execution
claude --dangerously-skip-permissions --agent pilot
```

`team upgrade` overwrites `playbook.md` and `autosteps/` while preserving `config.json`, `state.json`, `artifacts/`, and `proposal-queue.json`, ensuring upgrades don't interrupt a running pipeline.

## `team init` Output

```
.pipeline/
├── config.json          ← Pipeline configuration (edit before starting, includes model routing)
├── playbook.md          ← Phase execution playbook (loaded on-demand by Pilot)
├── llm-router.sh        ← Model routing dispatcher (auto-fallback to default model)
├── project-memory.json  ← Project memory (cross-pipeline constraint registry)
├── autosteps/           ← 20 automated scripts (do not edit)
├── artifacts/           ← Runtime outputs (auto-generated)
└── history/             ← Past proposal artifact archives
CLAUDE.md                ← Pipeline instructions for Claude Code
```

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
| `model_routing.providers` | External LLM provider configs | `glm5`, `ollama` |
| `model_routing.routes` | Agent → Provider mapping | see template |

## Model Routing

> New in v6.4

Route builder agents to external LLMs (e.g., GLM-5, local Ollama) while Claude handles review, architecture, and decision-making — significantly reducing token costs.

**Role Assignment:**

| Role | Agents | Description |
|------|--------|-------------|
| External LLM (workers) | Builders, Tester, Planner, Contract-Formalizer, Documenter, Optimizer, Translator, Migrator | Code implementation, testing, docs |
| Claude (lead) | Pilot, Clarifier, Architect, Simplifier, Inspector, all Auditors, Resolver, Deployer, Monitor | Requirements, architecture, code review, deployment decisions |

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
- Phase 3: Same-wave builders (Backend ∥ Frontend ∥ DBA ∥ Security ∥ Infra)
- Phase 2.6 ∥ 2.7: Schema validation ∥ Semantic validation
- Phase 3.0d ∥ 3.1 ∥ 3.2 ∥ 3.3: Post-build analysis
- Gate E: auditor-qa ∥ auditor-tech

**Proposal-level parallelism:**

During System Planning, the pipeline computes a dependency topology across proposals. Proposals with no mutual dependencies are assigned to the same `parallel_group` and execute in separate worktrees concurrently. After completion, they merge in `parallel_merge_order`.

```
P-001 ──┐
P-002 ──┼── parallel_group: 1 → run concurrently → merge in order
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
