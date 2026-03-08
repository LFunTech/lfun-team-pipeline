# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Orchestrator Split**: Orchestrator（993 行）拆分为精简状态机（612 行）+ Playbook 按需加载，解决长 prompt 导致阶段流转丢失问题
- **阶段路由表**: Orchestrator 新增完整路由表（50+ 条流转规则），确保每个阶段完成后明确知道下一步
- **项目记忆（Project Memory）**: 新增 `.pipeline/project-memory.json`，存储跨流水线的业务和架构约束
  - Memory Load: Phase 0 前加载并注入给 Clarifier 和 Architect
  - Memory Consolidation: Phase 7 后提取约束、用户确认、归档产物
  - 约束冲突检测: 新约束与已有约束冲突时提示用户确认推翻
- **产物归档**: 每次流水线完成后自动归档 artifacts 到 `.pipeline/history/<pipeline-id>/`
- Clarifier 增加项目记忆感知（检测约束冲突、避免重复澄清）
- Architect 增加约束检查（新方案不得违反已有约束）
- **系统规划（System Planning）**: 首次运行时自动进入交互式系统规划，将完整系统拆解为有序提案队列
- **提案队列（Proposal Queue）**: `.pipeline/proposal-queue.json` 管理多提案顺序执行，自动依赖检查和状态流转
- **实现足迹（Footprint）**: 每次提案完成后自动记录 API endpoints、DB tables、关键文件路径，注入给后续提案
- `team replan` 命令：重新规划提案队列（保留已完成工作）

### Changed
- Pipeline version bump to v6.3
- `team init` 现在额外复制 `playbook.md` 和 `project-memory.json`，并创建 `.pipeline/history/` 目录

## [1.0.0] - 2026-03-06

First public release of lfun-team-pipeline.

### Added

**25 Specialized Agents**
- `orchestrator` — Pipeline conductor, manages all phases and gates
- `clarifier` — Requirements elicitation (up to 5 rounds)
- `architect` — System design and proposal generation
- `auditor-biz` / `auditor-tech` / `auditor-qa` / `auditor-ops` — Four-perspective gate review
- `resolver` — Conflict resolution for failed gates
- `planner` — Task breakdown into builder-assignable units
- `contract-formalizer` — OpenAPI contract generation and validation
- `builder-backend` / `builder-frontend` / `builder-dba` / `builder-infra` / `builder-security` — Parallel implementation builders
- `migrator` / `translator` — Conditional specialist builders
- `simplifier` — Code simplification and cleanup
- `inspector` — Deep code review (Gate C)
- `tester` — Integration and unit test generation
- `optimizer` — Performance optimization (conditional)
- `documenter` — README, CHANGELOG, API documentation
- `deployer` — Deployment execution and rollback
- `monitor` — Post-deploy health observation (30-minute window)
- `github-ops` — GitHub repository creation and Woodpecker CI activation

**17 AutoStep Scripts** (fully automated, no human involvement)
- `requirement-completeness-checker.sh` — Validates requirement document completeness
- `assumption-propagation-validator.sh` — Ensures assumptions propagate through tasks
- `schema-completeness-validator.sh` — Validates OpenAPI schema completeness
- `contract-semantic-validator.sh` — Validates contract semantics
- `static-analyzer.sh` — Security and quality analysis
- `diff-scope-validator.sh` — Validates builder file ownership
- `regression-guard.sh` — Runs regression tests after implementation (supports Rust/Go/Python/Node)
- `post-simplification-verifier.sh` — Regression check after simplification
- `contract-compliance-checker.sh` — Schemathesis contract compliance testing
- `test-failure-mapper.sh` — Maps test failures to root causes
- `test-coverage-enforcer.sh` — Enforces coverage thresholds
- `api-change-detector.sh` — Detects breaking API changes
- `changelog-consistency-checker.sh` — Validates CHANGELOG format
- `pre-deploy-readiness-check.sh` — Pre-deployment verification
- `impl-manifest-merger.sh` — Merges builder implementation manifests
- `build-verifier.sh` — Two-stage build verification (production + test compilation)
- `depend-collector.sh` — Detects external dependencies and generates credential templates

**Pipeline Features**
- 8 phases (Phase 0–7) with 5 quality gates (A–E)
- Parallel builder execution via git worktrees
- GitHub integration + Woodpecker CI three-environment pipeline (test/staging/prod)
- Credential management via `.depend/` directory
- `team init` CLI for zero-friction project initialization

**Tech Stack Support**
- Rust + Axum / Cargo
- Go + Gin / Echo
- Python + FastAPI / Django
- Node.js + Express / Fastify
- React / Vue 3 frontends
- PostgreSQL / MySQL / SQLite
- Redis
- Docker + Docker Compose
