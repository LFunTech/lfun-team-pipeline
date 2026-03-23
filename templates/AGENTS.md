# AGENTS.md — 多角色软件交付流水线

本项目使用多角色软件交付流水线（v6.5），支持 Claude Code / Codex / Cursor / OpenCode 多平台运行。

## 快速启动

```bash
# 所有平台统一使用
team run

# 或手动启动各平台
# Claude Code:  claude --dangerously-skip-permissions --agent pilot
# Codex:        codex --full-auto     (AGENTS.md 自动加载 Pilot 指令)
# Cursor:       Agent 模式中输入 /pilot
# OpenCode:     opencode run --agent build "读取 AGENTS.md 并执行流水线"

# 查看当前状态
team status
```

## 目录结构

```
.pipeline/
├── config.json          ← 流水线配置（编辑此文件以自定义行为）
├── playbook.md          ← 阶段执行手册（Pilot 按需加载，勿手动修改）
├── project-memory.json  ← 项目记忆（跨流水线约束清单，自动维护）
├── history/             ← 历次流水线产物归档（按需查阅）
├── state.json           ← 运行时状态（Pilot 自动管理，勿手动修改）
├── autosteps/           ← AutoStep Shell 脚本（20 个）
└── artifacts/           ← 运行时产物（所有 Agent 和 AutoStep 的输出）
    ├── requirement.md
    ├── proposal.md
    ├── adr-draft.md
    ├── tasks.json
    ├── contracts/       ← OpenAPI Schema 文件
    ├── impl-manifest.json
    ├── gate-*.json
    └── ...

.worktrees/              ← 3.build 临时目录（自动创建和清理，勿手动修改）
├── builder-dba/
├── builder-backend/
├── builder-frontend/
├── builder-security/
├── builder-infra/
├── builder-migrator/    ← 仅条件激活时存在
└── builder-translator/  ← 仅条件激活时存在
（3.build 完成后自动删除）
```

## 阶段顺序参考

```
System Planning → 系统规划（交互式拆解系统为提案队列 + 并行拓扑计算）
Pick Proposal   → 选取下一个/组待执行提案（同 parallel_group 可并行）
Memory Load     → 项目记忆加载（注入约束给 Clarifier/Architect）
0.clarify       → Clarifier（需求澄清，最多 5 轮）
0.5             → Requirement Completeness Checker（AutoStep）
1.design        → Architect（方案设计）
gate-a          → Auditor-Gate（四视角方案审核）
2.0a            → GitHub Repo Creator（github-ops Agent）
2.0b            → Depend Collector（AutoStep + 暂停等凭证）
2.plan          → Planner（任务细化）
2.1             → Assumption Propagation Validator（AutoStep）
gate-b          → Auditor-Gate（四视角任务审核）
2.5             → Contract Formalizer（契约形式化）
2.6 ∥ 2.7      → 契约验证（并行 AutoStep）
3.build         → Builders 波次内并行实现
3.0b            → Build Verifier（AutoStep，编译验证）
3.0d ∥ 3.1 ∥ 3.2 ∥ 3.3 → 构建后分析（并行 AutoStep）
3.5             → Simplifier（代码精简）
3.6             → Post-Simplification Verifier（AutoStep）
gate-c          → Inspector（代码审查）
3.7             → Contract Compliance Checker（AutoStep）
4a.test         → Tester（功能测试）
4.2             → Test Coverage Enforcer（AutoStep）
gate-d          → Auditor-QA（测试验收）
5.document      → Documenter（文档）
5.1             → Changelog Consistency Checker（AutoStep）
gate-e          → Auditor-QA ∥ Auditor-Tech（并行文档审核）
6.deploy        → Deployer（部署）
7.monitor       → Monitor（上线观测）
```

## 配置说明（.pipeline/config.json）

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `project_name` | 项目名称 | `YOUR_PROJECT_NAME` |
| `autonomous_mode` | 自治模式 | `false` |
| `max_attempts.default` | 最大重试次数 | `3` |
| `testing.coverage_threshold` | 覆盖率阈值（百分比） | `80` |
| `issue_automation.inbox_label` | 待处理 Issue 标签 | `pipeline` |
| `issue_automation.max_workers` | Issue watcher 最大 worker 数 | `1` |

## 模型路由（Model Routing）

设置 `"model_routing.enabled": true` 后，部分 Agent 交由外部 LLM 执行。
路由配置支持 `cli_backend` 字段指定 CLI 后端：`auto`（默认）、`claude`、`codex`、`opencode`。

## 常见操作

```bash
# 将单个 issue 转成单提案流水线并执行
team issue run 123

# 持续轮询带 pipeline label 的 issue
team watch-issues

# 只轮询一轮
team watch-issues --once

# 继续执行流水线
team run

# 查看状态
team status

# 手动回退到指定阶段
# 编辑 .pipeline/state.json 修改 current_phase 和 status

# 重新规划
team replan
```

## 凭证管理

流水线在 2.0b 阶段自动扫描项目依赖，在 `.depend/` 目录生成凭证模板。
将 `.env.template` 复制为 `.env` 并填入真实值后，回复"继续"恢复执行。
