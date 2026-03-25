# lfun-team-pipeline

> 多平台 AI 多角色软件交付流水线 — 从需求到上线，28 个 AI 角色协作交付。

**中文** | [English](README-EN.md)

---

## 这是什么？

**lfun-team-pipeline** 是一套生产级软件交付流水线，支持 **Claude Code / Codex / Cursor / OpenCode** 四大 AI 编程平台。它编排 **28 个专属 AI 角色**，像真实工程团队一样协作 —— 需求分析师、架构师、多个并行开发者、QA 工程师、部署工程师、上线监控员 —— 由一个总指挥（Pilot）统一驱动。

你描述想构建的完整系统，流水线自动拆解为有序提案队列并逐个交付。支持系统级规划与多提案顺序/并行执行，每个提案独立走完需求到上线全流程。支持将部分 Agent 路由到外部 LLM（如 GLM-5、Ollama），大幅降低 token 消耗。团队成员可以各自使用偏好的平台，同一个项目在不同平台间无缝切换。

```
系统规划 → 提案队列 → [P-001: 需求澄清 → 架构 → 构建 → 测试 → 部署 → 监控] → P-002 → ...
                       ↕ 同 parallel_group 内的提案可并行执行
```

## 流水线总览

```
System Plan   系统规划（首次运行，交互式拆解为提案队列 + 并行拓扑计算）
Pick Proposal 选取下一个/组待执行提案（同 parallel_group 可并行）
Memory Load   项目记忆加载（注入约束给 Clarifier/Architect）
Phase 0       Clarifier            需求澄清（最多 5 轮，自治模式跳过）
Phase 0.5     AutoStep             需求完整性检查
Phase 1       Architect            系统设计 + ADR 生成
Gate A        Auditor-Gate         业务 / 技术 / QA / 运维 四视角评审（单次 spawn）
Phase 2.0a    GitHub Ops           GitHub 仓库创建
Phase 2.0b    AutoStep             依赖扫描 + 凭证填写暂停
Phase 2       Planner              拆解任务，分配给各 Builder
Phase 2.1     AutoStep             假设传播验证
Gate B        Auditor-Gate         契约与任务评审（单次 spawn）
Phase 2.5     Contract Formalizer  OpenAPI 契约生成
Phase 2.6∥2.7 AutoStep（并行）     契约 Schema 验证 ∥ 语义验证
Phase 3       Builders（波次并行） 后端 · 前端 · DBA · Infra · 安全 + 条件角色
Phase 3.0b    AutoStep             编译验证
Phase 3.0d∥3.1∥3.2∥3.3 AutoStep（并行）重复检测 · 静态分析 · 回归测试 · Diff 验证
Phase 3.5     Simplifier           代码精简
Phase 3.6     AutoStep             精简后回归验证
Gate C        Inspector            深度代码审查
Phase 3.7     AutoStep             契约合规检查
Phase 4a      Tester               集成测试 + 单元测试生成
Phase 4a.1    AutoStep             测试失败映射（仅 FAIL 时）
Phase 4.2     AutoStep             测试覆盖率强制验证
Phase 4b      Optimizer            性能优化（条件角色）
Gate D        Auditor-QA           测试验收
AutoStep      API Change Detector  API 变更检测
Phase 5       Documenter           README · CHANGELOG · API 文档
Phase 5.1     AutoStep             CHANGELOG 一致性检查
Gate E        Auditor-QA ∥ Auditor-Tech（并行）文档准确性评审
Phase 5.9     GitHub Ops           Woodpecker CI 配置推送
Phase 6.0     AutoStep             部署前就绪检查
Phase 6       Deployer             Docker Compose 部署 + 冒烟测试
Phase 7       Monitor              30 分钟健康观测窗口
Memory Consolidation  项目记忆固化（提取约束，用户确认后写入）
Mark Done     标记提案完成，自动循环执行下一个
```

## 支持的平台

| 平台 | 启动方式 | Agent 格式 | 说明 |
|------|---------|-----------|------|
| [Claude Code](https://claude.ai/code) | `claude --agent pilot` | `.md` | 原生支持，CLI 驱动 |
| [Codex](https://openai.com/codex) | `codex --full-auto` | `.toml` | AGENTS.md 自动加载 Pilot 指令 |
| [Cursor](https://cursor.sh) | Agent 模式 → `/pilot` | `.md` | IDE 内置 Agent 模式 |
| [OpenCode](https://opencode.ai) | `opencode run --agent build` | `.md` | 使用 `opencode.json` + `.opencode/agents/`，并复用 `AGENTS.md` 作为上下文 |

同一个项目可以在不同平台间无缝切换，`state.json` 格式完全兼容。

## 先决条件

| 要求 | 说明 |
|------|------|
| AI 编程工具（任选其一） | Claude Code / Codex / Cursor / OpenCode |
| Git | v2.28+（需要 worktree 支持） |
| Python 3 | Agent 转译器和状态管理 |
| Docker + Docker Compose | Phase 6 部署使用 |
| `gh` CLI | GitHub 集成（Phase 5.9）使用 |

## 安装

```bash
git clone https://github.com/LFunTech/lfun-team-pipeline.git
cd lfun-team-pipeline
bash install.sh
```

安装器会安装：
- `team` CLI 命令（到 `~/.local/bin/`）
- Agent 源文件 + 转译器（到 `~/.local/share/team-pipeline/`）
- 流水线模板（autosteps、playbook 等）
- CC 版 Agent 到 `~/.claude/agents/`（向后兼容）

> **重要：** Agent 定义现在是**按项目持久化**的。`team init` 时自动生成对应平台的 agent 到 `.pipeline/agents/`，每个 repo 独立管理自己的 agent 版本。

> **PATH 说明：** 若 `team` 命令找不到，请将 `$HOME/.local/bin` 加入 PATH：
> ```bash
> echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
> ```

## 快速开始 — 全新项目

```bash
# 1. 创建项目并初始化流水线（指定平台）
mkdir my-project && cd my-project
git init
team init                          # 默认: Claude Code
team init --platform codex         # 或指定: codex / cursor / opencode

# 2. 编辑流水线配置（设置项目名、技术栈、覆盖率阈值等）
$EDITOR .pipeline/config.json

# 3. 启动流水线 —— 描述你要构建的完整系统
team run
```

### `team run` 各平台行为

| 平台 | 执行方式 | 批次循环 |
|------|---------|---------|
| **Claude Code** | PTY Runner 自动监听 `[EXIT]`，杀进程后重启下一批次 | **全自动** — 所有批次一次 `team run` 搞定 |
| **Codex** | 启动 `codex --full-auto` 交互 TUI，保留完整对话上下文 | **单批次** — 会话结束后再 `team run` 继续 |
| **OpenCode** | `system-planning` 等交互阶段用 TUI；自动阶段优先 `opencode run --continue` 自动提交 prompt | **`team run` 外层循环** — 每轮结束后读取 `state.json`，未完成则等待几秒自动进入下一轮（可用 `TEAM_OPENCODE_LOOP_SLEEP` 调整间隔秒数） |
| **Cursor** | IDE 驱动，在 Agent 模式中输入 `/pilot` | **IDE 内交互** |

> **Codex vs OpenCode 的循环方式**
> CC 用 PTY 在同一 `team run` 进程里反复拉起 `claude`。
> **OpenCode**：`team run` 在 shell 层 `while` 循环——每轮结束后读 `state.json`，未完成则睡眠后再次启动 opencode。`system-planning` 与需要人工回答的阶段走 TUI 自动注入 prompt，其余阶段优先走 `opencode run --continue`。
> **Codex**：仍是一次会话为主，退出后需再次执行 `team run`（或依赖 `codex resume` 的对话连续性）。

> 如果你希望 OpenCode 在整个流水线期间都保留人工交互能力，可将 `.pipeline/config.json` 中 `opencode.interaction_mode` 设为 `tui`；临时切换可用 `TEAM_OPENCODE_INTERACTION_MODE=tui team run`。
> `team run` 现在会在 OpenCode 输出前后打印分区标题，并把阶段显示成语义化名称，例如 `并行实现 (3.build)`、`需求澄清 (0.clarify)`，方便你一眼看出当前是在 TUI 交互、自动执行还是等待下一轮。

遇到需要人工介入的节点会自动暂停：

| 暂停原因 | 如何恢复 |
|----------|---------|
| Phase 0 需求澄清（Clarifier 提问） | 直接在终端回答，自动继续 |
| Phase 2.0b 凭证填写（`.depend/*.env`） | 填写凭证后重新运行 `team run` |
| 流水线 ESCALATION | 查看 `team status`，手动处理后运行 `team run` |

```bash
# 查看当前进度（彩色状态面板）
team status
```

## 自治模式（Autonomous Mode）

> v6.4 新增

设置 `"autonomous_mode": true` 后，流水线在完成系统规划后**全自动执行所有提案**，无需人工干预。

**工作流程：**

```
                    ┌─ 系统规划（交互式） ──┐
                    │  描述系统              │
                    │  确认蓝图              │
                    │  逐个提案确认细节      │
                    └────────┬───────────────┘
                             │
                    ┌────────▼────────┐
                    │  全自动执行       │
                    │  P-001 → P-002   │
                    │  → ... → 完成    │
                    └─────────────────┘
```

**关键设计：信息前置**

自治模式的核心在于**把需求沟通前置到规划阶段**。System Planning 时，每个提案不仅确认范围（scope），还会逐个与你确认结构化的需求细节：

- 用户故事
- 业务规则
- 验收标准
- API 概览
- 数据实体
- 非功能需求

这些细节写入 `proposal-queue.json` 的 `detail` 字段。后续执行时，Pilot 直接从已确认的细节生成需求文档，无需 spawn Clarifier，省去一次 Agent 调用。

**使用方法：**

```bash
cd my-project
team init

# 编辑配置：设置 autonomous_mode 为 true
cat > .pipeline/config.json << 'EOF'
{
  "project_name": "my-app",
  "autonomous_mode": true,
  ...
}
EOF

# 启动流水线
team run
# → 系统规划阶段与你交互（描述系统、确认蓝图、确认每个提案细节）
# → 规划完成后全自动执行所有提案，无需再次干预
```

**自治模式跳过的人工暂停点：**

| 暂停点 | 交互模式 | 自治模式 |
|--------|---------|---------|
| Phase 0 需求澄清 | 最多 5 轮 Q&A | 跳过（直接从 detail 生成） |
| Phase 2.0b 凭证填写 | 暂停等待填写 | 跳过（WARN 日志） |
| Memory Consolidation | 等待用户确认约束 | 自动接受（冲突项保留旧值） |

> **注意：** System Planning 始终需要人工交互。自治模式仅影响后续提案的执行阶段。

## 接入现有项目

流水线支持为任意已有代码库添加新功能或新模块。

**第一步 — 初始化**

```bash
cd your-existing-repo
team init --platform codex   # 或 cc / cursor / opencode
```

`team init` 只会新增 `.pipeline/` 目录（含 `agents/`）和平台对应的上下文文件（`CLAUDE.md`/`AGENTS.md`/`.cursor/rules/`），不会修改任何现有代码。

**第二步 — 配置**

编辑 `.pipeline/config.json`，与现有项目的技术栈对齐：

```json
{
  "project_name": "your-repo-name",
  "autonomous_mode": false,
  "testing": {
    "coverage_tool": "cargo-tarpaulin",   // 与现有测试框架一致
    "coverage_threshold": 70              // 设置为当前覆盖率基准或略高
  },
  "autosteps": {
    "contract_compliance": {
      "service_start_cmd": "cargo run",   // 现有服务启动命令
      "service_base_url": "http://localhost:8080",
      "health_path": "/health"
    }
  }
}
```

**第三步 — 提交流水线配置**

```bash
git add .pipeline/config.json .pipeline/autosteps/ CLAUDE.md AGENTS.md .cursor/
git commit -m "chore: add lfun-team-pipeline"
```

**第四步 — 启动流水线**

```bash
team run
```

描述你想新增的功能或完整系统。首次运行时 Pilot 会进入系统规划阶段，生成提案队列后自动逐批执行。各 Builder 会在独立的 git worktree 中读取现有代码，并按现有架构风格实现变更。

**接入现有项目的注意事项：**

- Builder 在隔离的 git worktree（`.worktrees/`）中工作，**不会直接修改你的当前分支**
- Builder 在动手前会阅读现有代码，沿用已有架构模式和命名规范
- Gate C（Inspector）只审查新增/变更代码，不重新审查整个代码库
- 覆盖率阈值建议设为当前基准值，而非固定的 80%
- 若项目已有 OpenAPI 契约，在 Phase 2.5 告知 Pilot，避免重复生成

## 多提案系统交付

流水线支持一次性描述完整系统，自动拆解为有序提案队列并逐个交付。

**流程概览：**

```
描述系统 → 系统规划 → 提案队列 → [P-001 执行] → [P-002 执行] → ... → 全部完成
```

**第一步 — 启动**

```bash
team run
```

首次运行时，Pilot 进入系统规划阶段，引导你描述完整系统。完成后自动生成：
- `.pipeline/artifacts/system-blueprint.md`：系统蓝图（技术栈、域划分、数据模型骨架）
- `.pipeline/proposal-queue.json`：有序提案队列

系统规划完成后，`team run` 会按阶段自动续跑：交互阶段进入 TUI，自动阶段直接走 `opencode run --continue`；若无需人工介入，会一直执行到全部完成。

```bash
# 查看当前进度
team status
```

**查看提案进度**

```bash
python3 -c "
import json
q = json.load(open('.pipeline/proposal-queue.json'))
for p in q['proposals']:
    s = '✓' if p['status'] == 'completed' else ('▶' if p['status'] == 'running' else '○')
    print(f'  {s} [{p[\"id\"]}] {p[\"title\"]}')
"
```

**查看执行记录**

```bash
python3 -c "
import json
s = json.load(open('.pipeline/state.json'))
for e in s.get('execution_log', []):
    rb = f' → {e[\"rollback_to\"]}' if e.get('rollback_to') else ''
    print(f'[{e[\"step\"]}] {e[\"result\"]}{rb} (attempt {e[\"attempt\"]})')
"
```

**重新规划**

```bash
# 保留已完成工作，重新规划剩余提案
team replan
team run
```

## 项目记忆

流水线自动维护 `.pipeline/project-memory.json`，记录跨提案的业务和架构约束：

- **约束清单**：每次提案完成后自动提取（MUST/MUST NOT 形式），经用户确认后写入（自治模式下自动接受）
- **实现足迹**：记录每个提案实现的 API、数据库表、关键文件
- **冲突检测**：新提案与已有约束冲突时，Clarifier 和 Architect 会主动提醒

对于未进入正式 proposal 的日常业务小改，Pilot 会先做“非提案变更分流”：

- **纯实现调整**（重构、样式、文案、测试等）直接实现，不进入需求记忆
- **业务型小改** 先沉淀到 `.pipeline/micro-changes.json`，记录一句话级别的“最小需求事实”
- **长期规则** 再由 Memory Consolidation 提炼进入 `.pipeline/project-memory.json`
- **高风险或跨边界变更**（API、Schema、安全、计费、跨域流程等）直接升级为 proposal

一句话级别的小改也可以直接记录：

```bash
PIPELINE_DIR=.pipeline bash .pipeline/autosteps/record-micro-change.sh \
  --raw "这里默认改成7天吧" \
  --normalized "将导出链接默认有效期调整为7天" \
  --domain "导出" \
  --memory-candidate true \
  --constraint "导出链接默认有效期必须为7天"

PIPELINE_DIR=.pipeline bash .pipeline/autosteps/sync-micro-changes-to-memory.sh

PIPELINE_DIR=.pipeline bash .pipeline/autosteps/list-micro-changes.sh --pending
```

第一条命令将对话沉淀到 `.pipeline/micro-changes.json`，第二条命令把已确认的长期规则同步到 `.pipeline/project-memory.json`，第三条命令查看尚未固化到项目记忆的小改。

正式流水线跑到 `memory-consolidation` 阶段时，Pilot 也会自动先执行这一步同步，再继续做约束确认与归档。

项目记忆确保多次提案之间的业务规则、技术决策保持一致，不会前后矛盾。

## CLI 命令

| 命令 | 说明 |
|------|------|
| `team init [--platform <cc\|codex\|cursor\|opencode>]` | 初始化流水线，生成平台特定的 agent 到 `.pipeline/agents/` |
| `team run` | CC: PTY 自动循环；OpenCode: 外层循环多轮，交互阶段 TUI、自动阶段 `run --continue`；Codex: 单次 TUI，退出后需再执行（或 resume） |
| `team issue run <number> [--repo <owner/repo>]` | 将 GitHub Issue 转为单提案流水线，在独立 worktree 中交付 |
| `team watch-issues [--once] [--interval <sec>] [--max-workers <n>] [--labels a,b] [--exclude-labels x,y] [--dry-run]` | 轮询带指定 label 的 GitHub Issue，自动领取并调度处理 |
| `team migrate <cc\|codex\|cursor\|opencode> [--force]` | 切换平台（重新生成 `.pipeline/agents/`，自动创建快照） |
| `team migrate --rollback` | 回滚到上次迁移前的状态 |
| `team status` | 显示流水线执行进度（彩色面板：总览、Proposals、Issues、Changes、执行日志；Changes 面板显示 micro-change 待固化摘要） |
| `team upgrade` | 原地升级 playbook + autosteps + agents（保留 state.json、产物、提案队列） |
| `team repair` | 原地修复 playbook + autosteps + llm-router + agents（保留 config、state、artifacts、proposal-queue） |
| `team doctor` | 检查当前 repo 的并行防护运行时文件是否齐全且为新版 |
| `team replan` | 重新规划提案队列（保留已完成的工作） |
| `team scan` | 手动触发项目扫描（组件注册表） |
| `team version` | 显示版本号 |
| `team update` | 提示如何更新全局安装 |

**升级流水线版本：**

```bash
# 1. 更新全局模板
cd /path/to/lfun-team-pipeline && bash install.sh

# 2. 在项目目录中原地升级
cd /path/to/my-project && team upgrade

# 3. 继续执行
team run
```

`team upgrade` 会覆盖 `playbook.md`、`autosteps/` 并用当前平台重新生成 `agents/`，同时保留 `config.json`、`state.json`、`artifacts/` 和 `proposal-queue.json`，确保升级不中断正在执行的流水线。

当项目只是出现脚本缺失、模板漂移、`llm-router.sh`/`autosteps` 损坏、agent 文件不一致等运行时问题，而不需要做版本迁移时，优先使用 `team repair`。它会重建运行时文件并保留当前 `state.json`、`artifacts/` 与提案队列，适合“当前 repo 先修好再继续跑”。

如果你怀疑当前 repo 仍在使用旧版并行逻辑，可先运行 `team doctor`。它会检查 `.pipeline/playbook.md`、关键 autostep 以及 `state.json` 是否已经包含 Builder 文件冲突检测、提案并行预检查和新的运行时字段；若失败，再执行 `team repair`。

## 安全机制与回滚

所有文件修改操作均内置保护机制：

| 操作 | 保护方式 |
|------|---------|
| `team init` | 失败时自动清理首次创建的 `.pipeline/` 目录 |
| `team migrate` | 迁移前自动创建快照；转译失败自动回滚；`config.json` 原子写入 |
| `team migrate --rollback` | 一键恢复到上次迁移前的状态（agents + config） |
| `team upgrade` | 升级前备份所有将被覆写的文件；agent 升级失败自动从备份恢复 |
| `bash install.sh` | 全局模板目录覆写前备份；`settings.json` 原子写入防截断 |

**全局环境回滚：**

```bash
# 回滚到安装前的全局环境（自动查找最近备份）
bash scripts/rollback.sh

# 指定备份目录
bash scripts/rollback.sh ~/.local/share/team-pipeline-backup-20260322_215623
```

**向后兼容：** 旧版 `team init` 创建的项目（无 `.pipeline/agents/`）在新版 CLI 下正常运行——`team run` 自动回退到全局 `~/.claude/agents/`。`team upgrade` 会提示可用 `team migrate` 启用 per-repo agents。

## `team init` 初始化内容

```
.pipeline/
├── config.json          ← 流水线配置（启动前编辑，含模型路由配置）
├── playbook.md          ← 阶段执行手册（Pilot 按需加载）
├── llm-router.sh        ← 多平台模型路由调度脚本
├── project-memory.json  ← 项目记忆（跨流水线约束清单）
├── micro-changes.json   ← 非提案业务小改记录（最小需求事实）
├── agents/              ← ★ 平台特定的 Agent 定义（team init 时生成）
├── autosteps/           ← 20 个自动化脚本（平台无关）
├── artifacts/           ← 运行时产物（自动生成）
└── history/             ← 历次提案产物归档
CLAUDE.md                ← 流水线上下文（CC/Cursor 平台时生成）
AGENTS.md                ← 流水线上下文 + Pilot 指令（Codex/OpenCode 平台时生成）
opencode.json            ← OpenCode 项目配置（OpenCode 平台时生成，使用 `instructions: ["AGENTS.md"]`）
.opencode/agents/        ← OpenCode 项目级 Agent 定义（OpenCode 平台时生成）
.cursor/rules/pipeline.md ← Cursor IDE 流水线规则（Cursor 平台时生成）
```

> `.pipeline/agents/` 中的文件格式取决于 init 时选择的平台：CC/Cursor/OpenCode 为 `.md`，Codex 为 `.toml`。

## 配置参考（config.json）

```json
{
  "project_name": "my-app",
  "autonomous_mode": false,
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
  },
  "model_routing": {
    "enabled": false,              // 启用后部分 Agent 路由到外部 LLM
    "cli_backend": "auto",         // auto | claude | codex | opencode
    "providers": {
      "glm5": {
        "base_url": "https://coding.dashscope.aliyuncs.com/apps/anthropic",
        "api_key": "",             // 直接填值，或留空通过 api_key_env 读取
        "api_key_env": "GLM5_API_KEY",
        "model": "glm-5"
      }
    },
    "routes": {
      "builder-backend": "glm5",   // 未列出的 agent 默认走 Claude
      "builder-frontend": "glm5",
      "tester": "glm5"
    }
  }
}
```

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `project_name` | 项目名称 | `YOUR_PROJECT_NAME` |
| `autonomous_mode` | 自治模式：规划后全自动执行所有提案 | `false` |
| `testing.coverage_tool` | 覆盖率工具 | `nyc` |
| `testing.coverage_threshold` | 覆盖率阈值（%） | `80` |
| `max_attempts.default` | 阶段最大重试次数 | `3` |
| `model_routing.enabled` | 启用模型路由（将部分 Agent 交由外部 LLM） | `false` |
| `model_routing.cli_backend` | CLI 后端（`auto` / `claude` / `codex` / `opencode`） | `auto` |
| `opencode.interaction_mode` | OpenCode 交互模式（`hybrid` / `tui` / `run`） | `hybrid` |
| `issue_automation.repo` | Issue watcher 默认监听的 GitHub 仓库（留空则取当前 repo） | `""` |
| `issue_automation.source_labels` | Issue 来源筛选标签，留空表示扫描所有 open issue | `""` |
| `issue_automation.max_workers` | Issue watcher 最大 worker 数（非自治或非 OpenCode 自动降为 1） | `1` |
| `model_routing.providers` | 外部 LLM 提供商配置 | `glm5`, `ollama` |
| `model_routing.routes` | Agent → Provider 映射表 | 见模板 |

## GitHub Issue 自动化

现在可以把 GitHub Issue 作为 Pilot 的输入源：

```bash
# 处理单个 issue
team issue run 123

# 启动 watcher，持续轮询 label=pipeline 的 issue
team watch-issues

# 只扫描一轮
team watch-issues --once
```

- `team issue run` 会在 `.worktrees/issues/issue-<number>` 创建独立工作目录
- 自动生成 `.pipeline/artifacts/issue-context.md`、单提案 `proposal-queue.json` 与新的 `state.json`
- Pilot 若发现 `issue-context.md`，会按“GitHub Issue 单提案交付模式”执行
- OpenCode 下需要澄清的阶段会自动切回 TUI；自动阶段继续走 `run --continue`
- watcher 默认直接扫描仓库中的 open issue；可用 `issue_automation.source_labels` 或 `--labels` 过滤来源
- watcher 会用 label 标记 issue 状态：处理中 / 等待人工 / 已完成
- `watch-issues` 会优先处理带 `urgent` / `critical` / `p0` / `bug` / `security` 等标签的 issue，再按创建时间排序
- `watch-issues --dry-run` 会只预览本轮将处理哪些 issue，不实际执行
- `team status` 的 Issues 面板会显示最近一次 GitHub 回写时间
- `team status` 的 Issues 面板会显示 recent issue 的 GitHub URL、worktree 与日志路径，便于直接接管
- `team status` 的 Issues 面板还会给出紧凑摘要，方便快速复制 issue -> worktree/log/url 映射
- `team status` 会将 `waiting-user` issue 单独高亮成 `Waiting-User` 区块，并按 `escalation > 0.clarify > 2.0b.depend-collect > memory-consolidation` 优先级排序，方便优先人工接管

## 多平台支持

> v6.5 新增

流水线支持四大 AI 编程平台。Agent 定义由转译器从统一源（`agents/*.md`）自动生成，**按项目持久化**到 `.pipeline/agents/`。

**核心架构：**

```
agents/*.md (CC 格式，canonical source)
      │
      ▼
  build-agents.py (转译器)
      │
      ├── team init --platform cc      → .pipeline/agents/*.md  (CC 格式)
      ├── team init --platform codex   → .pipeline/agents/*.toml (Codex 格式)
      ├── team init --platform cursor  → .pipeline/agents/*.md  (Cursor 格式)
      └── team init --platform opencode→ .pipeline/agents/*.md  (OpenCode 格式)
```

**每个 repo 独立管理自己的平台。** Repo A 用 Cursor，Repo B 用 Codex，互不干扰。

**平台差异对照：**

| 特性 | Claude Code | Codex | Cursor | OpenCode |
|------|------------|-------|--------|----------|
| Agent 格式 | `.md` (YAML FM) | `.toml` | `.md` (YAML FM) | `.md` (YAML FM) |
| Pilot 加载 | `--agent pilot.md` | `AGENTS.md` 自动加载 | `/pilot` 指令 | `AGENTS.md` 自动加载 |
| 子 Agent 调用 | `Agent(name, prompt)` | `spawn_agent` / 自然语言 | `Task(subagent_type, prompt)` | `@name` 委派 |
| Shell 工具 | `Bash()` | `bash()` | `Shell()` | `bash()` |
| 权限模型 | `permissionMode` | `sandbox_mode` | `readonly` | 隐式 |

**OpenCode 规则入口：** OpenCode 官方项目入口是 `opencode.json` 与 `.opencode/agents/`；本仓库会生成 `opencode.json` 并使用 `"$schema": "https://opencode.ai/config.json"` 与 `"instructions": ["AGENTS.md"]` 把共享上下文接入 OpenCode。流水线内部 canonical agent 仍保存在 `.pipeline/agents/*.md`，并同步到 `.opencode/agents/*.md`；OpenCode 专用 Pilot 源定义在 `agents/platforms/opencode/pilot.md`。

**OpenCode 兼容注意事项：**

- `opencode.json` 必须使用 `instructions`，不能再使用旧字段 `context`
- `.opencode/agents/*.md` 的 frontmatter 需要把 `description`、`mode`、`agent`、`model` 渲染为合法字符串标量；像 `[Pipeline] ...` 这类描述必须正确加引号，避免被 YAML 误解析为数组
- OpenCode 的 `model` 不能使用 `inherit` / `sonnet` 这类流水线内部缩写；只能写明确的 `provider/model`，否则应省略该字段，让 OpenCode 继承默认模型
- 走 OpenCode CLI 时，路由/降级脚本应调用 `opencode run`，不能使用不存在的 `opencode exec`
- 升级 OpenCode 项目时，应先重建 `.pipeline/agents/`，再同步到 `.opencode/agents/`，避免残留旧格式 agent 文件

**Skill 依赖差异：**

| Skill | Claude Code | Cursor | Codex | OpenCode |
|-------|------------|--------|-------|----------|
| code-review | `Skill("code-review")` (CodeRabbit CLI) | 内置 `code-reviewer` subagent | 需安装 CodeRabbit CLI | 需安装 CodeRabbit CLI |
| code-simplifier | `Skill("code-simplifier")` (prompt) | 内置 `code-simplifier` subagent | Skill 文件自动复制 | Skill 文件自动复制 |
| frontend-design | `Skill("frontend-design")` (prompt) | Skill 文件自动复制 | Skill 文件自动复制 | Skill 文件自动复制 |

> 转译器自动为 Cursor 将 `Skill("code-review")` 转换为 `Task(subagent_type="code-reviewer")`，无需手动调整。

**切换平台：**

```bash
# 初始化时指定平台
team init --platform codex

# 随时切换（自动创建快照，支持回滚）
team migrate cursor       # 重新生成 .pipeline/agents/ 为 Cursor 格式
team migrate cc           # 切回 Claude Code
team migrate --rollback   # 回滚到上次迁移前
```

**CLI 后端优先级（由高到低）：**

```
$PIPELINE_CLI_BACKEND 环境变量（仅当前终端）
    ↓
.pipeline/config.json → model_routing.cli_backend（项目级）
    ↓
自动检测（claude > codex > opencode）
```

## 模型路由（Model Routing）

> v6.4 新增

支持将部分 Agent 路由到外部 LLM（如 GLM-5、本地 Ollama），保留审核/决策/精简角色用默认模型执行，大幅降低 token 消耗。

**角色分工：**

| 角色 | Agent | 说明 |
|------|-------|------|
| 外部 LLM（干活） | Builder 系列、Tester、Planner、Contract-Formalizer、Documenter、Optimizer、Translator、Migrator | 代码实现、测试、文档等执行型任务 |
| 默认模型（决策） | Pilot、Clarifier、Architect、Simplifier、Inspector、所有 Auditor、Resolver、Deployer、Monitor | 需求分析、架构设计、代码审查、部署决策等判断型任务 |

**配置方式（二选一）：**

```bash
# 方式 A：全局配置（一次设好，所有项目生效）
# 安装时自动创建 ~/.config/team-pipeline/routing.json
# 编辑该文件填入 API Key 并设 enabled: true

# 方式 B：项目级配置（仅当前项目生效，可覆盖全局）
# 编辑 .pipeline/config.json 的 model_routing 部分
```

**配置合并优先级：** 项目 `config.json` > 全局 `routing.json`。

**API Key 优先级：** `api_key`（直接值）> `api_key_env`（环境变量）> `.depend/llm.env`

**自动降级：** 未配置 API Key 或路由未启用时，自动降级到默认模型执行，流水线无感切换（退出码 10）。这意味着即使不配外部 LLM，流水线也能正常跑完。

## 并行执行

> v6.4 新增

流水线在两个层级支持并行执行：

**批次内并行：**

同一批次内无依赖关系的步骤自动并行执行：
- Phase 3：同波次 Builder 先做文件级冲突检测；无重叠才并行，有重叠则自动降级为串行子波次，并且后一子波次基于前一子波次合并后的最新 HEAD
- Phase 2.6 ∥ 2.7：契约 Schema 验证 ∥ 语义验证
- Phase 3.0d ∥ 3.1 ∥ 3.2 ∥ 3.3：构建后分析并行
- Gate E：auditor-qa ∥ auditor-tech 并行审核

**提案级并行：**

系统规划时自动计算提案间的依赖拓扑。无依赖的提案会先进入同一 `parallel_group` 候选集合，但真正并行前还要经过 `parallel-proposal-detector.py` 预检查：若提案缺少 detail/domains，或在 API、数据实体、共享基础设施关键词上存在重叠，则自动降级为单提案模式，避免把潜在冲突留到最终 merge。

```
P-001 ──┐
P-002 ──┼── parallel_group: 1 → 预检查 PASS 后并行 → 按序合并
P-003 ──┘
P-004 ────── parallel_group: 2 → 等待 group 1 完成后执行
```

## Agent 转译器

`scripts/build-agents.py` 将规范源（`agents/*.md`）转译为各平台的 Agent 定义：

```bash
# 转译所有平台
python3 scripts/build-agents.py

# 输出到 dist/ 目录
dist/
├── cc/       ← Claude Code (.md)
├── codex/    ← Codex (.toml)
├── cursor/   ← Cursor (.md)
└── opencode/ ← OpenCode (.md)
```

转译器自动处理：
- 前置元数据格式转换（YAML ↔ TOML）
- 权限模型映射（`permissionMode` → `sandbox_mode` / `readonly`）
- Shell 工具名替换（`Bash()` → `Shell()` / `bash()`）
- 各平台 Pilot 的子 Agent 调用语法（`Agent()` → `Task()` / `spawn_agent` / `@name`）

Pilot Agent 的平台特定定义位于 `agents/platforms/{cc,codex,cursor,opencode}/pilot.md`，转译器优先读取这些文件中的前置元数据。

## GitHub + Woodpecker CI 集成

填写 `.depend/github.env` 和 `.depend/woodpecker.env` 后，Phase 5.9 会自动：
1. 在指定 GitHub 组织下创建仓库
2. 推送所有代码
3. 为三个环境（test / staging / prod）激活 Woodpecker CI 流水线

## 技术栈支持

| 后端 | 前端 | 数据库 | 基础设施 |
|------|------|--------|---------|
| Rust + Axum | React | PostgreSQL | Docker Compose |
| Go + Gin | Vue 3 | MySQL | Woodpecker CI |
| Python + FastAPI | — | Redis | GitHub Actions |
| Node.js + Express | — | SQLite | — |

## License

MIT — 详见 [LICENSE](LICENSE)
