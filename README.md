# lfun-team-pipeline

> 基于 Claude Code 的多角色软件交付流水线 — 从需求到上线，28 个 AI 角色协作交付。

**中文** | [English](README-EN.md)

---

## 这是什么？

**lfun-team-pipeline** 是基于 [Claude Code](https://claude.ai/code) 构建的生产级软件交付流水线。它编排 **28 个专属 AI 角色**，像真实工程团队一样协作 —— 需求分析师、架构师、多个并行开发者、QA 工程师、部署工程师、上线监控员 —— 由一个总指挥（Pilot）统一驱动。

你描述想构建的完整系统，流水线自动拆解为有序提案队列并逐个交付。支持系统级规划与多提案顺序/并行执行，每个提案独立走完需求到上线全流程。支持将部分 Agent 路由到外部 LLM（如 GLM-5、Ollama），大幅降低 Claude token 消耗。

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

## 先决条件

| 要求 | 说明 |
|------|------|
| [Claude Code](https://claude.ai/code) | CLI 工具（需要 Pro、Max 或 API 订阅） |
| Git | v2.28+（需要 worktree 支持） |
| Docker + Docker Compose | Phase 6 部署使用 |
| `gh` CLI | GitHub 集成（Phase 5.9）使用 |

## 安装

**方式 A — 一键安装（推荐）：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LFunTech/lfun-team-pipeline/main/install.sh)
```

**方式 B — Clone 后安装：**

```bash
git clone https://github.com/LFunTech/lfun-team-pipeline.git
cd lfun-team-pipeline
bash install.sh
```

> **PATH 说明：** 若 `team` 命令找不到，请将 `$HOME/.local/bin` 加入 PATH：
> ```bash
> echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
> ```

## 快速开始 — 全新项目

```bash
# 1. 创建项目并初始化流水线
mkdir my-project && cd my-project
git init
team init

# 2. 编辑流水线配置（设置项目名、技术栈、覆盖率阈值等）
$EDITOR .pipeline/config.json

# 3. 启动流水线 —— 描述你要构建的完整系统
team run
# 首次运行自动进入系统规划，生成提案队列后自动逐批执行至完成
```

`team run` 会自动循环执行所有批次，无需每次手动重启。遇到需要人工介入的节点会自动暂停：

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
team init
```

`team init` 只会新增 `.pipeline/` 目录和 `CLAUDE.md`，不会修改任何现有代码。

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
git add .pipeline/config.json .pipeline/autosteps/ CLAUDE.md
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

系统规划完成后，`team run` 自动继续执行所有后续批次直到全部完成。

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

项目记忆确保多次提案之间的业务规则、技术决策保持一致，不会前后矛盾。

## CLI 命令

| 命令 | 说明 |
|------|------|
| `team init` | 在当前项目目录初始化流水线 |
| `team run` | 自动循环执行批次直到完成或需要人工干预 |
| `team status` | 显示流水线执行进度（彩色面板：阶段、提案队列、执行日志） |
| `team upgrade` | 原地升级 playbook + autosteps（保留 state.json、产物、提案队列） |
| `team replan` | 重新规划提案队列（保留已完成的工作） |
| `team scan` | 手动触发项目扫描（组件注册表） |
| `team version` | 显示版本号 |
| `team update` | 提示如何更新全局安装 |

**升级流水线版本：**

```bash
# 1. 更新全局 agents 和模板
cd /path/to/lfun-team-pipeline && bash install.sh

# 2. 在项目目录中原地升级
cd /path/to/my-project && team upgrade

# 3. 继续执行
team run
```

`team upgrade` 会覆盖 `playbook.md` 和 `autosteps/`，同时保留 `config.json`、`state.json`、`artifacts/` 和 `proposal-queue.json`，确保升级不中断正在执行的流水线。

## `team init` 初始化内容

```
.pipeline/
├── config.json          ← 流水线配置（启动前编辑，含模型路由配置）
├── playbook.md          ← 阶段执行手册（Pilot 按需加载）
├── llm-router.sh        ← 模型路由调度脚本（自动降级到 Claude）
├── project-memory.json  ← 项目记忆（跨流水线约束清单）
├── autosteps/           ← 20 个自动化脚本（无需修改）
├── artifacts/           ← 运行时产物（自动生成）
└── history/             ← 历次提案产物归档
CLAUDE.md                ← 流水线对 Claude Code 的指令
```

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
| `model_routing.providers` | 外部 LLM 提供商配置 | `glm5`, `ollama` |
| `model_routing.routes` | Agent → Provider 映射表 | 见模板 |

## 模型路由（Model Routing）

> v6.4 新增

支持将部分 Agent 路由到外部 LLM（如 GLM-5、本地 Ollama），Claude 保留审核/决策/精简角色，大幅降低 token 消耗。

**角色分工：**

| 角色 | Agent | 说明 |
|------|-------|------|
| 外部 LLM（干活） | Builder 系列、Tester、Planner、Contract-Formalizer、Documenter、Optimizer、Translator、Migrator | 代码实现、测试、文档等执行型任务 |
| Claude（决策） | Pilot、Clarifier、Architect、Simplifier、Inspector、所有 Auditor、Resolver、Deployer、Monitor | 需求分析、架构设计、代码审查、部署决策等判断型任务 |

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

**自动降级：** 未配置 API Key 或路由未启用时，自动降级到 Claude 执行，流水线无感切换（退出码 10）。这意味着即使不配外部 LLM，流水线也能正常跑完。

## 并行执行

> v6.4 新增

流水线在两个层级支持并行执行：

**批次内并行：**

同一批次内无依赖关系的步骤自动并行执行：
- Phase 3：同波次 Builder 并行实现（Backend ∥ Frontend ∥ DBA ∥ Security ∥ Infra）
- Phase 2.6 ∥ 2.7：契约 Schema 验证 ∥ 语义验证
- Phase 3.0d ∥ 3.1 ∥ 3.2 ∥ 3.3：构建后分析并行
- Gate E：auditor-qa ∥ auditor-tech 并行审核

**提案级并行：**

系统规划时自动计算提案间的依赖拓扑。无依赖的提案被分配到同一 `parallel_group`，在独立 worktree 中并行执行完整流水线，完成后按 `parallel_merge_order` 顺序合并。

```
P-001 ──┐
P-002 ──┼── parallel_group: 1 → 并行执行 → 按序合并
P-003 ──┘
P-004 ────── parallel_group: 2 → 等待 group 1 完成后执行
```

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
