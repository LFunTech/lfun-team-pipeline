# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- `builder-migrator` / `builder-translator` — Conditional specialist builders
- `simplifier` — Code simplification and cleanup
- `inspector` — Deep code review (Gate C)
- `tester` — Integration and unit test generation
- `optimizer` — Performance optimization (conditional)
- `documenter` — README, CHANGELOG, API documentation
- `deployer` — Deployment execution and rollback
- `monitor` — Post-deploy health observation (30-minute window)
- `github-ops` — GitHub repository creation and Woodpecker CI activation

**16 AutoStep Scripts** (fully automated, no human involvement)
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
- `depend-collector.sh` — Detects external dependencies and generates credential templates

**Pipeline Features**
- 8 phases (Phase 0–7) with 5 quality gates (A–E)
- Parallel builder execution via git worktrees
- Redis-based distributed locking for conversation state
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
