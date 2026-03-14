# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.4] - 2026-03-14

### Added / 新增

- **Phase 3.0d Duplicate Detector / 重复组件检测阶段**: 新增 Phase 3.0d（Duplicate Detector），在 Builder 实现完成后自动检测跨 Builder 产生的重复代码和重复组件。
  Added Phase 3.0d (Duplicate Detector) to detect cross-builder duplicate code and components after parallel implementation.
  - `duplicate_analyzer.py`：Layer 1（文件级精确/近似匹配）+ Layer 2（函数级语义重复检测），含完整单元测试。
    `duplicate_analyzer.py`: Layer 1 (file-level exact/near-duplicate) + Layer 2 (function-level semantic duplicate detection) with full unit tests.
  - `duplicate-detector.sh`：AutoStep 脚本，调用 analyzer 并生成结构化报告。
    `duplicate-detector.sh`: AutoStep script invoking analyzer and producing structured report.
  - `duplicate-auditor` Agent：独立审计 remediation plan，确保整改方案合理。
    `duplicate-auditor` agent: independently audits the remediation plan for soundness.
  - Orchestrator 路由更新：Phase 3.0d 插入 Phase 3.0b（Build Verifier）之后。
    Orchestrator routing updated: Phase 3.0d inserted after Phase 3.0b (Build Verifier).

- **Component Registry 配置块 / 组件注册表配置**: `config.json` 模板新增 `component_registry` 配置块，为组件注册表功能预留配置入口。
  Added `component_registry` config block to `config.json` template for future component registry support.

- **`team scan` 命令 / `team scan` command**: 新增 `team scan` 子命令，支持手动触发项目扫描。`install.sh` 新增 `.py` autostep 文件支持。
  Added `team scan` subcommand for manual project scanning. `install.sh` now supports `.py` autostep files.

### Fixed / 修复

- **`duplicate_analyzer` 代码审查修复**: 修复三项代码审查问题（错误处理、边界条件、输出格式）。
  Fixed three code review issues in `duplicate_analyzer` (error handling, edge cases, output formatting).

- **`mktemp` 并发冲突**: 修复多个 autostep 并发执行时 `mktemp` 模板冲突问题，安装时自动启用依赖 plugins。
  Fixed `mktemp` template conflicts during concurrent autostep execution; install now auto-enables dependent plugins.

- **`team run` 批次间进程复用问题**: `team run` 每个批次启动独立 claude 进程，而非注入"继续"到现有进程，避免上下文累积导致的不稳定。
  `team run` now spawns a fresh claude process per batch instead of injecting prompts into an existing session, preventing context accumulation instability.

## [1.1.3] - 2026-03-09

### Changed / 变更

- **`team run` 架构重写：PTY + 守护进程 IPC**: `team run` 不再 kill/restart claude，改为通过 PTY（伪终端）启动一个完整的 claude 交互会话，守护进程监控 PTY 输出流，检测到 `[EXIT]` 后向 master 端写入 `继续\r`（模拟物理回车），整个流水线在同一个 claude 进程中运行完毕。用户可以看到完整的 claude TUI 并随时交互。
  Rewrote `team run` with PTY-based IPC: instead of kill/restarting claude per batch, one claude process runs the full pipeline. A Python daemon opens a PTY pair, starts claude on the slave end (full TUI preserved), proxies all I/O between the real terminal and the master end, and injects `继续\r` on `[EXIT]` detection.

### Fixed / 修复

- **`team run` Enter 键不触发**: PTY raw 模式下 Enter 键产生 `\r`（0x0D）而非 `\n`，守护进程注入时也须用 `\r`，否则文字出现在输入框但不触发提交。
  Fixed Enter key not submitting in PTY raw mode: injected prompts now use `\r` (0x0D) to match physical Enter key behavior.

- **无 tty 环境友好报错**: `team run` 在 pipe 或脚本中调用时，检测到 stdin 非 tty 会立即输出清晰错误提示而非 termios 崩溃。
  Added `os.isatty()` guard with a clear error message when `team run` is invoked without a real terminal.

- **`proposal-queue.json` 列表格式兼容**: `team status` 和完成报告同时支持列表格式（旧）和带 `proposals` 键的字典格式（新）。
  `team status` and final report now handle both list-format and dict-format `proposal-queue.json`.

- **`kill $FEEDER_PID` 缺 `|| true`**: feeder 进程提前退出（如用户按 Ctrl+D）时 `kill` 返回非零，触发 `set -e` 静默终止 `team run`。
  Added `|| true` to `kill $FEEDER_PID` to prevent `set -e` from exiting when the feeder process already terminated.

- **`grep -c || echo 0` 双输出**: `grep -c` 无匹配时退出码为 1，触发 `|| echo 0`，但 grep 已输出 `0`，变量值变成 `0\n0`，导致整数比较报错。改用 `(grep -cF ...; true)` 解决。
  Fixed double-output bug in `grep -c || echo 0` pattern causing integer comparison errors.

## [1.1.2] - 2026-03-09

### Fixed / 修复

- **`team run` 无回显**: 修正 stream-json 事件解析（使用 `assistant` 快照事件而非不存在的 `content_block_delta`），改回 pipe 方式（claude 向 pipe 实时写入，向文件则块缓冲），恢复实时回显。
  Fixed blank output in `team run` by using correct `assistant` snapshot event type and restoring direct pipe (claude line-buffers to pipes, block-buffers to files).

- **`team run` 卡在交互**: 改用 `claude -p`（print mode）让 claude 处理完一个批次后自动退出，不再等待用户输入。
  Fixed `team run` hanging on user input by switching to `claude -p` (print mode), which exits automatically after each batch.

- **嵌套 Claude Code 报错**: 在调用 claude 前执行 `env -u CLAUDECODE`，允许在 Claude Code 会话内部调用 `team run`。
  Fixed nested Claude Code session error by prepending `env -u CLAUDECODE` to the claude invocation.

- **子 agent 静默期无回显**: 新增后台心跳（每 20 秒输出 `... (still running)`），覆盖 `Agent()` 子 agent 调用期间的静默时段。
  Added 20s background heartbeat to show activity during silent Agent() subagent call periods.

- **stream-json 需要 `--verbose`**: 补加 `--verbose` 标志，满足 `--output-format=stream-json` 的依赖要求。
  Added missing `--verbose` flag required by `--output-format=stream-json`.

## [1.1.0] - 2026-03-08

### Added / 新增

- **`team upgrade` command / `team upgrade` 命令**: In-place upgrade of playbook + autosteps in a running project, preserving state.json, artifacts, and proposal queue. Automatically adds missing `execution_log` field to state.json.
  在执行中的项目原地升级 playbook + autosteps，保留 state.json、产物和提案队列。自动向 state.json 补充缺失的 `execution_log` 字段。

- **Autonomous Mode / 自治模式**: New `autonomous_mode` config option. After System Planning completes, all proposals execute fully automatically with zero human intervention.
  新增 `autonomous_mode` 配置项，规划阶段完成后全自动执行所有提案，无需人工干预。
  - Phase 0 Clarifier pass-through: skips interactive Q&A, generates requirement.md directly from confirmed detail.
    Phase 0 Clarifier 直通：跳过交互式 Q&A，从已确认的 detail 直接生成需求文档。
  - Phase 2.0b credential skip: does not pause for credential input in autonomous mode (logs WARN).
    Phase 2.0b 凭证跳过：自治模式下不暂停等待凭证填写（输出 WARN）。
  - Memory Consolidation auto-accept: new constraints are accepted automatically; conflicting constraints preserve the old value.
    Memory Consolidation 自动接受：新增约束自动写入，冲突约束保留旧值不推翻。

- **Proposal Detail Structure / 提案 detail 结构**: During System Planning, each proposal is confirmed with structured requirement details (user stories, business rules, acceptance criteria, API overview, data entities, non-functional requirements), stored in `proposal-queue.json`.
  System Planning 阶段逐个提案与用户确认结构化需求细节（用户故事、业务规则、验收标准、API 概览、数据实体、非功能需求），写入 `proposal-queue.json`。

- **Clarifier Autonomous Chapter / Clarifier 自治模式章节**: Clarifier transcribes confirmed details into requirement.md when receiving `[AUTONOMOUS_MODE]` marker.
  Clarifier 收到 `[AUTONOMOUS_MODE]` 标记时从 detail 转录需求文档。

- **Orchestrator Split / Orchestrator 拆分**: Split orchestrator (993 lines) into a lean state machine (612 lines) + on-demand Playbook loading, fixing phase transition loss caused by long prompts.
  Orchestrator（993 行）拆分为精简状态机（612 行）+ Playbook 按需加载，解决长 prompt 导致阶段流转丢失问题。

- **Phase Route Table / 阶段路由表**: 50+ flow transition rules ensuring deterministic next-step after each phase.
  Orchestrator 新增完整路由表（50+ 条流转规则），确保每个阶段完成后明确知道下一步。

- **Project Memory / 项目记忆**: New `.pipeline/project-memory.json` for cross-pipeline business and architecture constraints.
  新增 `.pipeline/project-memory.json`，存储跨流水线的业务和架构约束。
  - Memory Load: injected into Clarifier and Architect before Phase 0.
    Phase 0 前加载并注入给 Clarifier 和 Architect。
  - Memory Consolidation: extracts constraints after Phase 7, archives artifacts.
    Phase 7 后提取约束、用户确认、归档产物。
  - Conflict detection: prompts user when new constraints conflict with existing ones.
    新约束与已有约束冲突时提示用户确认推翻。

- **Artifact Archival / 产物归档**: Auto-archives artifacts to `.pipeline/history/<pipeline-id>/` after each pipeline completion.
  每次流水线完成后自动归档 artifacts 到 `.pipeline/history/<pipeline-id>/`。

- **System Planning / 系统规划**: Interactive system decomposition into an ordered proposal queue on first run.
  首次运行时自动进入交互式系统规划，将完整系统拆解为有序提案队列。

- **Proposal Queue / 提案队列**: `.pipeline/proposal-queue.json` manages multi-proposal sequential execution with dependency checking.
  `.pipeline/proposal-queue.json` 管理多提案顺序执行，自动依赖检查和状态流转。

- **Implementation Footprint / 实现足迹**: Records API endpoints, DB tables, and key file paths after each proposal, injected into subsequent proposals.
  每次提案完成后自动记录 API endpoints、DB tables、关键文件路径，注入给后续提案。

- **`team replan` command / `team replan` 命令**: Re-plan proposal queue while preserving completed work.
  重新规划提案队列（保留已完成工作）。

### Fixed / 修复

- **Auditor output field unification / Auditor 输出字段统一**: `verdict` → `overall` across 6 agent files (auditor-biz/tech/ops/qa, inspector, resolver).
  `verdict` → `overall`（auditor-biz/tech/ops/qa、inspector、resolver 共 6 文件）。

- **Playbook appendix field fix / Playbook 附录字段修正**: `comments[severity=CRITICAL].detail` → `issues[severity=CRITICAL].description`.

- **Playbook log instruction field fix / Playbook 写日志指令字段修正**: `issues[].message` → `issues[].description` (5 Gate log instructions).
  `issues[].message` → `issues[].description`（5 处 Gate 日志指令）。

- **Stale `.pipeline/` removal / 删除 `.pipeline/` 残留**: Removed stale working copy and added `.pipeline/` to `.gitignore` (`templates/` is the single source of truth).
  删除 `.pipeline/` 残留工作副本，加入 `.gitignore`（`templates/` 为唯一源）。

### Changed / 变更

- **Token optimization: Gate A/B auditor merge / Token 优化：Gate A/B 审计员合并**: Gate A/B now spawn a single `auditor-gate` agent covering all 4 perspectives (Biz/Tech/QA/Ops) in one call, saving 6 agent spawns per pipeline run.
  Gate A/B 改为 spawn 单个 `auditor-gate` 一次性覆盖四个视角，每次流水线减少 6 次 agent spawn。

- **Token optimization: Phase 0 spawn elimination / Token 优化：Phase 0 spawn 消除**: In autonomous mode, Orchestrator writes requirement.md directly from proposal detail without spawning Clarifier, saving 1 agent spawn.
  自治模式下 Orchestrator 直接从提案 detail 写 requirement.md，省去 1 次 Clarifier spawn。

- **Token optimization: Remove log system / Token 优化：移除日志系统**: Replaced the entire structured log system (35 step logs + pipeline.index.json + context injection + causality tracking, ~280 lines) with a lightweight `execution_log` array in state.json. Each step appends one line `{step, result, attempt, rollback_to, ts}`. Saves ~100 tool calls per pipeline run.
  移除整个结构化日志系统（35 个步骤日志 + pipeline.index.json + 上下文注入 + 因果标注，约 280 行），替换为 state.json 内嵌的 `execution_log` 轻量数组。每步追加一行记录。每次流水线减少约 100 次工具调用。

- **Batch execution model / 批次执行模型**: Orchestrator executes one batch per invocation then exits. Token cost drops from O(n²) to O(n). 12 batches cover the full pipeline (merged from 17); re-run `claude --agent orchestrator` to continue.
  Orchestrator 每次启动只执行一个批次后退出。Token 消耗从 O(n²) 降至 O(n)。12 个批次覆盖完整流水线（从 17 个合并），再次运行即可继续。

- **Token optimization: Orchestrator prompt slimming / Token 优化：Orchestrator 提示词瘦身**: Orchestrator system prompt reduced from 29KB to 6KB (-80%). Phase-specific instructions (System Planning, Memory Load/Consolidation, proposal detail) moved to playbook for on-demand loading.
  Orchestrator 系统提示词从 29KB 缩减至 6KB（-80%）。阶段特定指令（系统规划、记忆加载/固化、提案细节）移至 playbook 按需加载。

- **Token optimization: builder-infra slimming / Token 优化：builder-infra 瘦身**: builder-infra.md reduced from 9.8KB to 4KB (-60%). Removed redundant YAML templates and verbose comments while preserving all constraints.
  builder-infra.md 从 9.8KB 缩减至 4KB（-60%）。移除冗余 YAML 模板和详细注释，保留所有约束。

- **Token optimization: Playbook batch read / Token 优化：Playbook 批量读取**: Each batch reads all its playbook sections in one Read call instead of grep+read per step.
  每个批次一次性读取涉及的所有 playbook 章节，减少 grep+read 往返。

- **Model tiering / 模型分层**: 8 agents (auditor-biz/tech/ops/qa, documenter, monitor, github-ops, simplifier) use `model: sonnet` for cost efficiency; complex agents remain on parent model.
  8 个 Agent 使用 `model: sonnet` 降低成本；复杂 Agent 保持使用父模型。

- Pipeline version bump to v6.4 / 流水线版本升级至 v6.4
- `team init` now also copies `playbook.md` and `project-memory.json`, and creates `.pipeline/history/`.
  `team init` 现在额外复制 `playbook.md` 和 `project-memory.json`，并创建 `.pipeline/history/` 目录。

## [1.0.0] - 2026-03-06

First public release of lfun-team-pipeline. / lfun-team-pipeline 首次公开发布。

### Added

**25 Specialized Agents / 25 个专属 AI 角色**
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

**17 AutoStep Scripts / 17 个自动化脚本** (fully automated, no human involvement)
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

**Pipeline Features / 流水线特性**
- 8 phases (Phase 0–7) with 5 quality gates (A–E)
- Parallel builder execution via git worktrees
- GitHub integration + Woodpecker CI three-environment pipeline (test/staging/prod)
- Credential management via `.depend/` directory
- `team init` CLI for zero-friction project initialization

**Tech Stack Support / 技术栈支持**
- Rust + Axum / Cargo
- Go + Gin / Echo
- Python + FastAPI / Django
- Node.js + Express / Fastify
- React / Vue 3 frontends
- PostgreSQL / MySQL / SQLite
- Redis
- Docker + Docker Compose
