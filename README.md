# lfun-team-pipeline

> 基于 Claude Code 的多角色软件交付流水线 — 从需求到上线，一条命令驱动。

**中文** | [English](README-EN.md)

---

## 这是什么？

**lfun-team-pipeline** 是基于 [Claude Code](https://claude.ai/code) 构建的生产级软件交付流水线。它编排 **25 个专属 AI 角色**，像真实工程团队一样协作 —— 需求分析师、架构师、多个并行开发者、QA 工程师、部署工程师、上线监控员 —— 由一个总指挥（Orchestrator）统一驱动。

你描述想构建的完整系统，流水线自动拆解为有序提案队列并逐个交付。支持系统级规划与多提案顺序执行，每个提案独立走完需求到上线全流程。

```
系统规划 → 提案队列 → [P-001: 需求澄清 → 架构 → 构建 → 测试 → 部署 → 监控] → P-002 → ...
```

## 流水线总览

```
System Plan  系统规划（首次运行，交互式拆解为提案队列）
Pick Proposal 选取下一个待执行提案
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
Mark Done    标记提案完成，自动循环执行下一个
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
claude --agent orchestrator
# 首次运行自动进入系统规划，生成提案队列后逐个执行
# 中断后重新启动会自动恢复到上次进度
```

首次运行时，Orchestrator 会引导你描述完整系统，生成系统蓝图和有序提案队列，然后自动逐个执行每个提案的 Phase 0-7 全流程。

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
claude --agent orchestrator
```

描述你想新增的功能或完整系统。首次运行时 Orchestrator 会进入系统规划阶段，生成提案队列后逐个执行。各 Builder 会在独立的 git worktree 中读取现有代码，并按现有架构风格实现变更。

**接入现有项目的注意事项：**

- Builder 在隔离的 git worktree（`.worktrees/`）中工作，**不会直接修改你的当前分支**
- Builder 在动手前会阅读现有代码，沿用已有架构模式和命名规范
- Gate C（Inspector）只审查新增/变更代码，不重新审查整个代码库
- 覆盖率阈值建议设为当前基准值，而非固定的 80%
- 若项目已有 OpenAPI 契约，在 Phase 2.5 告知 Orchestrator，避免重复生成

## 多提案系统交付

流水线支持一次性描述完整系统，自动拆解为有序提案队列并逐个交付。

**流程概览：**

```
描述系统 → 系统规划 → 提案队列 → [P-001 执行] → [P-002 执行] → ... → 全部完成
```

**第一步 — 启动**

```bash
claude --agent orchestrator
```

首次运行时，Orchestrator 进入系统规划阶段，引导你描述完整系统。完成后自动生成：
- `.pipeline/artifacts/system-blueprint.md`：系统蓝图（技术栈、域划分、数据模型骨架）
- `.pipeline/proposal-queue.json`：有序提案队列

**第二步 — 自动执行**

系统规划完成后自动开始第一个提案，每个提案独立走完 Phase 0-7 全流程。

**中断恢复**

```bash
# 中断后重新启动，自动继续上次进度
claude --agent orchestrator
```

**查看进度**

```bash
python3 -c "
import json
q = json.load(open('.pipeline/proposal-queue.json'))
for p in q['proposals']:
    s = '✓' if p['status'] == 'completed' else ('▶' if p['status'] == 'running' else '○')
    print(f'  {s} [{p[\"id\"]}] {p[\"title\"]}')
"
```

**重新规划**

```bash
# 保留已完成工作，重新规划剩余提案
team replan
claude --agent orchestrator
```

## 项目记忆

流水线自动维护 `.pipeline/project-memory.json`，记录跨提案的业务和架构约束：

- **约束清单**：每次提案完成后自动提取（MUST/MUST NOT 形式），经用户确认后写入
- **实现足迹**：记录每个提案实现的 API、数据库表、关键文件
- **冲突检测**：新提案与已有约束冲突时，Clarifier 和 Architect 会主动提醒

项目记忆确保多次提案之间的业务规则、技术决策保持一致，不会前后矛盾。

## `team init` 初始化内容

```
.pipeline/
├── config.json          ← 流水线配置（启动前编辑）
├── playbook.md          ← 阶段执行手册（Orchestrator 按需加载）
├── project-memory.json  ← 项目记忆（跨流水线约束清单）
├── autosteps/           ← 17 个自动化脚本（无需修改）
├── artifacts/           ← 运行时产物（自动生成）
└── history/             ← 历次提案产物归档
CLAUDE.md                ← 流水线对 Claude Code 的指令
```

## 配置参考（config.json）

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
