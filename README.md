# lfun-team-pipeline

> A multi-agent software delivery pipeline for Claude Code — from idea to deployed production in a single command.

> 基于 Claude Code 的多角色软件交付流水线 — 从需求到上线，一条命令驱动。

---

## English

### What is this?

**lfun-team-pipeline** is a production-ready software delivery pipeline built on [Claude Code](https://claude.ai/code). It orchestrates **25 specialized AI agents** that collaborate like a real engineering team — requirements analyst, architect, multiple parallel developers, QA engineers, a deployer, and a post-launch monitor — all driven by a single orchestrator.

You describe what you want to build. The pipeline does the rest.

```
clarifier → architect → planner → [builders in parallel] → tester → deployer → monitor
```

### Pipeline Overview

```
Phase 0    Clarifier          Requirements elicitation (up to 5 rounds)
Phase 0.5  AutoStep           Requirement completeness check
Phase 1    Architect          System design and ADR generation
Gate A     4 Auditors         Business / Technical / QA / Ops review
Phase 2    Planner            Task breakdown for each builder
Phase 2.5  Contract Formalizer OpenAPI contract generation
Gate B     4 Auditors         Contract and task review
Phase 3    Builders (parallel) Backend · Frontend · DBA · Infra · Security
Phase 3.x  AutoSteps          Static analysis · Regression · Contract compliance
Gate C     Inspector          Deep code review
Phase 4    Tester             Integration and unit test generation
Gate D     QA Auditor         Test coverage enforcement
Phase 5    Documenter         README · CHANGELOG · API docs
Gate E     Tech + QA Auditors  Documentation accuracy review
Phase 5.9  GitHub Ops         Repo creation · Woodpecker CI activation
Phase 6    Deployer           Docker Compose deployment · smoke test
Phase 7    Monitor            30-minute health observation window
```

### Prerequisites

| Requirement | Details |
|-------------|---------|
| [Claude Code](https://claude.ai/code) | CLI tool (requires Pro, Max, or API subscription) |
| Git | v2.28+ (worktree support required) |
| Docker + Docker Compose | For Phase 6 deployment |
| `gh` CLI | For GitHub integration (Phase 5.9) |
| `sqlx-cli` or similar | For database migrations (optional) |

### Installation

**Option A — Clone and install:**

```bash
git clone https://github.com/LfunTech/lfun-team-pipeline.git
cd lfun-team-pipeline
bash install.sh
```

**Option B — One-liner (no clone needed):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LfunTech/lfun-team-pipeline/main/install.sh)
```

> **PATH note:** If `team` command is not found after install, add `$HOME/.local/bin` to your PATH:
> ```bash
> echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
> ```

### Quick Start

```bash
# 1. Initialize the pipeline in your project
cd my-new-project
team init

# 2. Edit the pipeline config (set project_name, tech stack, thresholds)
$EDITOR .pipeline/config.json

# 3. Start the pipeline — describe your project when asked
claude --agent orchestrator
```

The orchestrator will ask clarifying questions, design the system, assign tasks to builder agents, run all quality gates, and deploy — automatically.

### Project Initialization (`team init`)

`team init` sets up the following structure in your project:

```
.pipeline/
├── config.json          ← Pipeline configuration (edit before starting)
├── autosteps/           ← 16 automated scripts (do not edit)
└── artifacts/           ← Runtime outputs (auto-generated)
CLAUDE.md                ← Pipeline instructions for Claude Code
```

### Configuration (`config.json`)

Key fields to configure before starting:

```json
{
  "project_name": "my-app",
  "testing": {
    "coverage_tool": "nyc",        // nyc | cargo-tarpaulin | pytest-cov | go test
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

### GitHub + Woodpecker CI Integration

When you have GitHub and Woodpecker credentials, Phase 5.9 automatically:
1. Creates a GitHub repository under your organization
2. Pushes all code
3. Activates Woodpecker CI pipelines for three environments (test / staging / prod)

Set up credentials in `.depend/` before the pipeline reaches Phase 2.0b.

### License

MIT — see [LICENSE](LICENSE)

---

## 中文

### 这是什么？

**lfun-team-pipeline** 是基于 [Claude Code](https://claude.ai/code) 构建的生产级软件交付流水线。它编排 **25 个专属 AI 角色**，像真实工程团队一样协作 —— 需求分析师、架构师、多个并行开发者、QA 工程师、部署工程师、上线监控员 —— 由一个总指挥（Orchestrator）统一驱动。

你描述想构建什么，流水线自动完成剩下的事。

```
需求澄清 → 架构设计 → 任务拆解 → [并行构建] → 测试 → 部署 → 监控
```

### 流水线总览

```
Phase 0    Clarifier            需求澄清（最多 5 轮）
Phase 0.5  AutoStep             需求完整性检查
Phase 1    Architect            系统设计 + ADR 生成
Gate A     四位审计员            业务 / 技术 / QA / 运维 四视角评审
Phase 2    Planner              拆解任务，分配给各 Builder
Phase 2.5  Contract Formalizer  OpenAPI 契约生成
Gate B     四位审计员            契约与任务评审
Phase 3    Builders（并行）      后端 · 前端 · DBA · Infra · 安全
Phase 3.x  AutoStep 集群        静态分析 · 回归测试 · 契约合规
Gate C     Inspector            深度代码审查
Phase 4    Tester               集成测试 + 单元测试生成
Gate D     QA 审计员             测试覆盖率强制验证
Phase 5    Documenter           README · CHANGELOG · API 文档
Gate E     Tech + QA 审计员      文档准确性评审
Phase 5.9  GitHub Ops           仓库创建 · Woodpecker CI 激活
Phase 6    Deployer             Docker Compose 部署 + 冒烟测试
Phase 7    Monitor              30 分钟健康观测窗口
```

### 先决条件

| 要求 | 说明 |
|------|------|
| [Claude Code](https://claude.ai/code) | CLI 工具（需要 Pro、Max 或 API 订阅） |
| Git | v2.28+（需要 worktree 支持） |
| Docker + Docker Compose | Phase 6 部署使用 |
| `gh` CLI | GitHub 集成（Phase 5.9）使用 |

### 安装

**方式 A — Clone 后安装：**

```bash
git clone https://github.com/LfunTech/lfun-team-pipeline.git
cd lfun-team-pipeline
bash install.sh
```

**方式 B — 一键安装（无需 Clone）：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LfunTech/lfun-team-pipeline/main/install.sh)
```

> **PATH 说明：** 若 `team` 命令找不到，请将 `$HOME/.local/bin` 加入 PATH：
> ```bash
> echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
> ```

### 快速开始

```bash
# 1. 在你的项目中初始化流水线
cd my-new-project
team init

# 2. 编辑流水线配置（设置项目名、技术栈、覆盖率阈值等）
$EDITOR .pipeline/config.json

# 3. 启动流水线 —— 根据提示描述你要构建的项目
claude --agent orchestrator
```

Orchestrator 会主动提问澄清需求、设计系统、分配构建任务、运行所有质量门、最后自动部署。

### `team init` 初始化内容

```
.pipeline/
├── config.json          ← 流水线配置（启动前编辑）
├── autosteps/           ← 16 个自动化脚本（无需修改）
└── artifacts/           ← 运行时产物（自动生成）
CLAUDE.md                ← 流水线对 Claude Code 的指令
```

### 配置说明（config.json 关键字段）

```json
{
  "project_name": "my-app",
  "testing": {
    "coverage_tool": "nyc",        // nyc | cargo-tarpaulin | pytest-cov | go test
    "coverage_threshold": 80       // 覆盖率阈值（百分比）
  },
  "autosteps": {
    "contract_compliance": {
      "service_start_cmd": "npm start",        // 服务启动命令
      "service_base_url": "http://localhost:3000",
      "health_path": "/health"
    }
  }
}
```

### GitHub + Woodpecker CI 集成

填写 `.depend/github.env` 和 `.depend/woodpecker.env` 后，Phase 5.9 会自动：
1. 在指定 GitHub 组织下创建仓库
2. 推送所有代码
3. 为三个环境（test / staging / prod）激活 Woodpecker CI 流水线

### 技术栈支持

| 后端 | 前端 | 数据库 | 基础设施 |
|------|------|--------|---------|
| Rust + Axum | React | PostgreSQL | Docker Compose |
| Go + Gin | Vue 3 | MySQL | Woodpecker CI |
| Python + FastAPI | — | Redis | GitHub Actions |
| Node.js + Express | — | SQLite | — |

### License

MIT — 详见 [LICENSE](LICENSE)
