# lfun-team-pipeline

> A multi-agent software delivery pipeline for Claude Code — from idea to deployed production in a single command.

[中文](README.md) | **English**

---

## What is this?

**lfun-team-pipeline** orchestrates **25 specialized AI agents** that collaborate like a real engineering team — requirements analyst, architect, multiple parallel developers, QA engineers, a deployer, and a post-launch monitor — all driven by a single orchestrator.

You describe the full system you want to build. The pipeline automatically decomposes it into an ordered proposal queue and delivers each one sequentially. Each proposal runs through the complete requirements-to-production lifecycle independently.

```
system planning → proposal queue → [P-001: clarify → architect → build → test → deploy → monitor] → P-002 → ...
```

## Pipeline Overview

```
System Plan  System Planning (first run, interactive decomposition into proposal queue)
Pick Proposal Pick next pending proposal for execution
Phase 0    Clarifier            Requirements elicitation (up to 5 rounds)
Phase 0.5  AutoStep             Requirement completeness check
Phase 1    Architect            System design and ADR generation
Gate A     4 Auditors           Business / Technical / QA / Ops review
Phase 2    Planner              Task breakdown for each builder
Phase 2.5  Contract Formalizer  OpenAPI contract generation
Gate B     4 Auditors           Contract and task review
Phase 3    Builders (parallel)  Backend · Frontend · DBA · Infra · Security
Phase 3.x  AutoSteps            Static analysis · Regression · Contract compliance
Gate C     Inspector            Deep code review
Phase 4    Tester               Integration and unit test generation
Gate D     QA Auditor           Test coverage enforcement
Phase 5    Documenter           README · CHANGELOG · API docs
Gate E     Tech + QA Auditors   Documentation accuracy review
Phase 5.9  GitHub Ops           Repo creation · Woodpecker CI activation
Phase 6    Deployer             Docker Compose deployment · smoke test
Phase 7    Monitor              30-minute health observation window
Mark Done    Mark proposal completed, auto-loop to next
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
claude --agent orchestrator
# First run enters System Planning automatically, generates a proposal queue, then executes sequentially
# Restarting after interruption automatically resumes from last progress
```

On first run, the orchestrator guides you through describing the full system, generates a system blueprint and an ordered proposal queue, then automatically executes each proposal through the complete Phase 0-7 lifecycle.

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
claude --agent orchestrator
```

Describe the new feature or full system you want to add. On first run, the orchestrator enters System Planning to generate a proposal queue, then executes each proposal sequentially. Builders will read the existing codebase in their git worktrees and implement changes that are consistent with the current architecture.

**Important notes for existing repos:**

- Builders work in isolated git worktrees (`.worktrees/`) — your current branch is never modified directly
- The pipeline reads existing code to understand patterns before writing new code
- Gate C (Inspector) performs a diff-scoped review — it only reviews new/changed code, not the entire codebase
- Coverage thresholds should be set to match or slightly exceed your current baseline, not a fixed target like 80%
- If your project already has an OpenAPI spec, inform the orchestrator at Phase 2.5 to avoid regenerating from scratch

## Multi-Proposal System Delivery

The pipeline supports describing a complete system upfront, automatically decomposing it into an ordered proposal queue, and delivering each proposal sequentially.

**Flow overview:**

```
Describe system → System Planning → Proposal Queue → [P-001 execute] → [P-002 execute] → ... → All done
```

**Step 1 — Start**

```bash
claude --agent orchestrator
```

On first run, the Orchestrator enters System Planning and guides you through describing the full system. Once complete, it generates:
- `.pipeline/artifacts/system-blueprint.md`: System blueprint (tech stack, domain decomposition, data model skeleton)
- `.pipeline/proposal-queue.json`: Ordered proposal queue

**Step 2 — Auto-execution**

After System Planning completes, the first proposal starts automatically. Each proposal independently runs through the full Phase 0-7 lifecycle.

**Resume after interruption**

```bash
# Restart after interruption — automatically resumes from last progress
claude --agent orchestrator
```

**Check progress**

```bash
python3 -c "
import json
q = json.load(open('.pipeline/proposal-queue.json'))
for p in q['proposals']:
    s = '✓' if p['status'] == 'completed' else ('▶' if p['status'] == 'running' else '○')
    print(f'  {s} [{p[\"id\"]}] {p[\"title\"]}')
"
```

**Re-plan**

```bash
# Preserve completed work, re-plan remaining proposals
team replan
claude --agent orchestrator
```

## Project Memory

The pipeline automatically maintains `.pipeline/project-memory.json`, recording cross-proposal business and architecture constraints:

- **Constraint registry**: Automatically extracted after each proposal completes (in MUST/MUST NOT form), written after user confirmation
- **Implementation footprint**: Records APIs, database tables, and key files implemented by each proposal
- **Conflict detection**: When a new proposal conflicts with existing constraints, the Clarifier and Architect proactively flag the issue

Project memory ensures that business rules and technical decisions remain consistent across multiple proposals, preventing contradictions.

## `team init` Output

```
.pipeline/
├── config.json          ← Pipeline configuration (edit before starting)
├── playbook.md          ← Phase execution playbook (loaded on-demand by Orchestrator)
├── project-memory.json  ← Project memory (cross-pipeline constraint registry)
├── autosteps/           ← 17 automated scripts (do not edit)
├── artifacts/           ← Runtime outputs (auto-generated)
└── history/             ← Past proposal artifact archives
CLAUDE.md                ← Pipeline instructions for Claude Code
```

## Configuration Reference

```json
{
  "project_name": "my-app",
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
  }
}
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
