# lfun-team-pipeline

> A multi-agent software delivery pipeline for Claude Code — from idea to deployed production in a single command.

[中文](README.md) | **English**

---

## What is this?

**lfun-team-pipeline** orchestrates **25 specialized AI agents** that collaborate like a real engineering team — requirements analyst, architect, multiple parallel developers, QA engineers, a deployer, and a post-launch monitor — all driven by a single orchestrator.

You describe what you want to build. The pipeline does the rest.

```
clarifier → architect → planner → [builders in parallel] → tester → deployer → monitor
```

## Pipeline Overview

```
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

# 3. Start the pipeline — describe your project when prompted
claude --agent orchestrator
```

The orchestrator will clarify requirements, design the system, assign tasks to builder agents in parallel git worktrees, run all quality gates, and deploy — automatically.

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

When the orchestrator asks what to build, describe the new feature you want to add. Builders will read the existing codebase in their git worktrees and implement changes that are consistent with the current architecture.

**Important notes for existing repos:**

- Builders work in isolated git worktrees (`.worktrees/`) — your current branch is never modified directly
- The pipeline reads existing code to understand patterns before writing new code
- Gate C (Inspector) performs a diff-scoped review — it only reviews new/changed code, not the entire codebase
- Coverage thresholds should be set to match or slightly exceed your current baseline, not a fixed target like 80%
- If your project already has an OpenAPI spec, inform the orchestrator at Phase 2.5 to avoid regenerating from scratch

## `team init` Output

```
.pipeline/
├── config.json          ← Pipeline configuration (edit before starting)
├── autosteps/           ← 16 automated scripts (do not edit)
└── artifacts/           ← Runtime outputs (auto-generated)
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
