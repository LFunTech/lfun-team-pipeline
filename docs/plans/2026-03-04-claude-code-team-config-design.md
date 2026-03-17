# Claude Code Team Configuration Design

**Goal:** 将 `claude-code-multi-agent-team-design.md`（v6）描述的多角色软件交付流水线，转化为可直接使用的 Claude Code 配置文件集合。

**Architecture:** 24 个用户级 subagent 文件（`~/.claude/agents/`）+ 项目级 CLAUDE.md 模板 + 15 个 AutoStep Shell 脚本框架 + config.json 模板。Pilot 设计为通过 `claude --agent pilot` 启动，作为主线程 spawn 其他 subagents。

**Tech Stack:** Claude Code subagents (Markdown + YAML frontmatter), Bash shell scripts, JSON config

**参考文档:** `claude-code-multi-agent-team-design.md`（v6），`docs/plans/2026-03-04-v6-implementation-plan.md`

---

## Section 1：文件结构

```
~/.claude/agents/                        ← 用户级 Agent 定义（24 个文件）
├── pilot.md                      ← 主控，via `claude --agent pilot`
├── clarifier.md                         ← Phase 0
├── architect.md                         ← Phase 1
├── auditor-biz.md                       ← Gates A/B
├── auditor-tech.md                      ← Gates A/B/E
├── auditor-qa.md                        ← Gates A/B/D/E
├── auditor-ops.md                       ← Gates A/B
├── resolver.md                          ← Gate 冲突仲裁（条件激活）
├── planner.md                           ← Phase 2
├── contract-formalizer.md               ← Phase 2.5
├── builder-frontend.md                  ← Phase 3
├── builder-backend.md                   ← Phase 3
├── builder-dba.md                       ← Phase 3
├── builder-security.md                  ← Phase 3
├── builder-infra.md                     ← Phase 3
├── simplifier.md                        ← Phase 3.5（skill: code-simplifier）
├── inspector.md                         ← Gate C（skill: code-review）
├── tester.md                            ← Phase 4a
├── documenter.md                        ← Phase 5
├── deployer.md                          ← Phase 6
├── monitor.md                           ← Phase 7
├── migrator.md                          ← Phase 3 条件 Agent
├── optimizer.md                         ← Phase 4b 条件 Agent
└── translator.md                        ← Phase 3 条件 Agent

<项目根目录>/CLAUDE.md                   ← 项目级 Pilot 说明（模板文件）
<项目根目录>/.pipeline/
├── config.json                          ← 流水线配置模板
├── state.json                           ← 运行时状态（运行时由 Pilot 生成）
├── autosteps/
│   ├── requirement-completeness-checker.sh
│   ├── assumption-propagation-validator.sh
│   ├── schema-completeness-validator.sh
│   ├── contract-semantic-validator.sh
│   ├── static-analyzer.sh
│   ├── diff-scope-validator.sh
│   ├── regression-guard.sh
│   ├── post-simplification-verifier.sh
│   ├── contract-compliance-checker.sh
│   ├── test-failure-mapper.sh
│   ├── test-coverage-enforcer.sh
│   ├── performance-baseline-checker.sh
│   ├── api-change-detector.sh
│   ├── changelog-consistency-checker.sh
│   └── pre-deploy-readiness-check.sh
└── artifacts/                           ← 运行时产物目录（运行时生成）
```

**输出目录：** 本 repo 同时保存模板副本：
- `agents/` → 所有 24 个 Agent `.md` 文件（安装时 cp 到 `~/.claude/agents/`）
- `templates/CLAUDE.md` → 项目 CLAUDE.md 模板
- `templates/.pipeline/` → 完整 `.pipeline/` 目录模板
- `install.sh` → 一键安装脚本

---

## Section 2：Agent 文件格式规范

### Pilot（特殊主线程 Agent）

```yaml
---
name: pilot
description: "[Pipeline] 多角色软件交付流水线主控。通过 `claude --agent pilot`
  启动，读取 .pipeline/state.json 驱动阶段流转，依序调用各 Agent 和 AutoStep
  脚本，处理回滚（rollback_to）和 Escalation。不在普通对话中使用。"
tools: >
  Agent(clarifier, architect, auditor-biz, auditor-tech, auditor-qa, auditor-ops,
  resolver, planner, contract-formalizer, builder-frontend, builder-backend,
  builder-dba, builder-security, builder-infra, simplifier, inspector, tester,
  documenter, deployer, monitor, migrator, optimizer, translator),
  Bash, Read, Write, Edit, Glob, Grep, TodoWrite
model: inherit
permissionMode: acceptEdits
---
```

System prompt 包含：完整阶段顺序、每阶段如何 spawn 对应 Agent、如何运行 AutoStep 脚本（Bash）、如何读写 state.json、rollback 逻辑、Escalation 条件。

### 功能 Agent 通用格式

```yaml
---
name: <agent-name>
description: "[Pipeline] Phase X <中文名>。<一句话职责>。仅在多角色软件交付流水线中使用。"
tools: Read, Write, Edit, Bash, Glob, Grep   # 按职责裁剪
model: inherit
permissionMode: acceptEdits                   # 审查类 Agent 省略此字段
---
```

### 带 Skill 的 Agent

```yaml
---
name: inspector
description: "[Pipeline] Gate C 代码审查员。基于 code-review skill 审查实现质量，
  输出 gate-c-review.json。仅在多角色软件交付流水线中使用。"
tools: Read, Glob, Grep, Bash
model: inherit
skills:
  - code-review
---
```

### 权限分级表

| 类别 | permissionMode | tools |
|------|---------------|-------|
| Pilot | `acceptEdits` | Agent(*) + 所有工具 |
| Clarifier, Architect, Planner, Contract Formalizer | `acceptEdits` | Read/Write/Edit/Bash/Glob/Grep |
| Builder-*, Simplifier, Tester, Documenter | `acceptEdits` | Read/Write/Edit/Bash/Glob/Grep |
| Deployer | `acceptEdits` | Read/Write/Edit/Bash/Glob/Grep |
| Auditor-*, Resolver, Inspector, Monitor | （省略，使用默认） | Read/Grep/Glob/Bash（只读为主） |

### Skills 注入

| Agent | skills |
|-------|--------|
| simplifier | `code-simplifier` |
| inspector | `code-review` |
| builder-frontend | `frontend-design` |

---

## Section 3：AutoStep 脚本框架规范

### 统一接口

- **输入**：环境变量（`PIPELINE_DIR`、各阶段特定变量）
- **输出**：JSON 文件到 `.pipeline/artifacts/`
- **退出码**：`0` = PASS，`1` = FAIL，`2` = ERROR（基础设施故障）
- **TIMESTAMP**：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

### 脚本骨架

```bash
#!/bin/bash
# Phase X.Y: <AutoStep Name>
# 输入: <环境变量列表>
# 输出: .pipeline/artifacts/<output-file>.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/<output-file>.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── 检查逻辑（按技术栈填充）────────────────────────────────────
# TODO: 实现具体检查逻辑
# 参考: claude-code-multi-agent-team-design.md Section 5

OVERALL="PASS"

# ── 输出标准 JSON ──────────────────────────────────────────────
mkdir -p "$(dirname "$OUTPUT_FILE")"
cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "<AutoStepName>",
  "timestamp": "$TIMESTAMP",
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

### 15 个脚本与对应章节

| 脚本文件名 | Phase | 输入 | 输出 JSON |
|-----------|-------|------|----------|
| `requirement-completeness-checker.sh` | 0.5 | requirement.md | requirement-completeness-report.json |
| `assumption-propagation-validator.sh` | 2.1 | requirement.md + tasks.json | assumption-propagation-report.json |
| `schema-completeness-validator.sh` | 2.6 | contracts/ + tasks.json | schema-validation-report.json |
| `contract-semantic-validator.sh` | 2.7 | contracts/ + tasks.json | contract-semantic-report.json |
| `static-analyzer.sh` | 3.1 | 变更文件列表 | static-analysis-report.json |
| `diff-scope-validator.sh` | 3.2 | git diff + tasks.json | scope-validation-report.json |
| `regression-guard.sh` | 3.3 | 测试套件 | regression-report.json |
| `post-simplification-verifier.sh` | 3.6 | 精简后代码 | post-simplify-report.json |
| `contract-compliance-checker.sh` | 3.7 | contracts/ + 运行服务 | contract-compliance-report.json |
| `test-failure-mapper.sh` | 4a.1 | test-report.json + coverage.lcov | failure-builder-map.json |
| `test-coverage-enforcer.sh` | 4.2 | 覆盖率报告 + impl-manifest.json | coverage-report.json |
| `performance-baseline-checker.sh` | 4.3 | perf-report.json + baseline | perf-baseline-report.json |
| `api-change-detector.sh` | 5（前置） | old/new contracts/ | api-change-report.json |
| `changelog-consistency-checker.sh` | 5.1 | CHANGELOG.md + api-change-report.json | changelog-check-report.json |
| `pre-deploy-readiness-check.sh` | 6.0 | proposal.md + state.json + deploy-plan.md | deploy-readiness-report.json |

---

## Section 4：项目模板文件

### templates/CLAUDE.md

内容包含：
1. 流水线启动命令（`claude --agent pilot`）
2. 目录结构说明
3. 阶段顺序快速参考（Phase 0 → 0.5 → Gate A → ... → Phase 7）
4. config.json 关键配置说明
5. 常见操作（恢复流水线、查看 state.json、手动回退）

### templates/.pipeline/config.json

```json
{
  "version": "v6",
  "pipeline_id": "pipe-YYYYMMDD-001",
  "project_name": "YOUR_PROJECT_NAME",
  "max_attempts": {
    "default": 3,
    "phase-0": 5,
    "phase-3": 5
  },
  "required_skills": ["code-simplifier", "code-review"],
  "requirement_completeness": {
    "parent_section": "## 最终需求定义",
    "required_sections": ["### 功能描述", "### 用户故事", "### 业务规则", "### 范围边界", "### 验收标准"],
    "section_match_mode": "prefix",
    "min_words": 200,
    "abort_on_critical_unresolved": true
  },
  "testing": {
    "coverage_tool": "nyc",
    "coverage_format": ["lcov", "json"],
    "coverage_output_dir": ".pipeline/artifacts/coverage/",
    "coverage_required": true
  },
  "gates": {
    "gate-d": {
      "rollback_to_allowed": ["phase-4a", "phase-3", "phase-2"]
    }
  }
}
```

### install.sh

一键脚本：创建 `~/.claude/agents/`（如不存在），将 `agents/` 下所有 `.md` 复制到 `~/.claude/agents/`，并输出使用说明。

---

## 实施范围总结

| 类别 | 数量 | 输出位置 |
|------|------|---------|
| LLM Agent 文件 | 24 个 .md | `agents/` + 安装到 `~/.claude/agents/` |
| AutoStep 脚本 | 15 个 .sh | `templates/.pipeline/autosteps/` |
| 项目模板文件 | 2 个（CLAUDE.md + config.json） | `templates/` |
| 安装脚本 | 1 个（install.sh） | repo 根目录 |
| **合计** | **42 个文件** | — |
