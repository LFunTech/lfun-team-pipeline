# CLAUDE.md — 多角色软件交付流水线

本项目使用基于 Claude Code 的多角色软件交付流水线（v6）。

## 快速启动

```bash
# 启动流水线（从 Phase 0 开始，或从上次中断处继续）
claude --agent orchestrator

# 查看当前状态
cat .pipeline/state.json | python3 -m json.tool

# 查看最新日志
ls -t .pipeline/artifacts/*.json | head -5
```

## 目录结构

```
.pipeline/
├── config.json          ← 流水线配置（编辑此文件以自定义行为）
├── state.json           ← 运行时状态（Orchestrator 自动管理，勿手动修改）
├── autosteps/           ← AutoStep Shell 脚本（15 个）
└── artifacts/           ← 运行时产物（所有 Agent 和 AutoStep 的输出）
    ├── requirement.md
    ├── proposal.md
    ├── adr-draft.md
    ├── tasks.json
    ├── contracts/       ← OpenAPI Schema 文件
    ├── impl-manifest.json
    ├── gate-*.json
    └── ...
```

## 阶段顺序参考

```
Phase 0    → Clarifier（需求澄清，最多 5 轮）
Phase 0.5  → Requirement Completeness Checker（AutoStep）
Phase 1    → Architect（方案设计）
Gate A     → Auditor-Biz/Tech/QA/Ops（方案审核）
Phase 2    → Planner（任务细化）
Phase 2.1  → Assumption Propagation Validator（AutoStep）
Gate B     → Auditor-Biz/Tech/QA/Ops（任务审核）
Phase 2.5  → Contract Formalizer（契约形式化）
Phase 2.6  → Schema Completeness Validator（AutoStep）
Phase 2.7  → Contract Semantic Validator（AutoStep）
Phase 3    → Builders 并行实现（Frontend/Backend/DBA/Security/Infra）
             + 条件角色（Migrator/Translator）
Phase 3.1  → Static Analyzer（AutoStep）
Phase 3.2  → Diff Scope Validator（AutoStep）
Phase 3.3  → Regression Guard（AutoStep）
Phase 3.5  → Simplifier（代码精简）
Phase 3.6  → Post-Simplification Verifier（AutoStep）
Gate C     → Inspector（代码审查）
Phase 3.7  → Contract Compliance Checker（AutoStep）
Phase 4a   → Tester（功能测试）
Phase 4a.1 → Test Failure Mapper（AutoStep，FAIL 时）
Phase 4.2  → Test Coverage Enforcer（AutoStep）
Phase 4b   → Optimizer（性能优化，条件角色）
Gate D     → Auditor-QA（测试验收）
AutoStep   → API Change Detector
Phase 5    → Documenter（文档）
Phase 5.1  → Changelog Consistency Checker（AutoStep）
Gate E     → Auditor-QA + Auditor-Tech（文档审核）
Phase 6.0  → Pre-Deploy Readiness Check（AutoStep）
Phase 6    → Deployer（部署）
Phase 7    → Monitor（上线观测）
```

## 配置说明（.pipeline/config.json）

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `project_name` | 项目名称 | `YOUR_PROJECT_NAME` |
| `max_attempts.default` | 各阶段最大重试次数 | `3` |
| `requirement_completeness.min_words` | 需求文档最小字数 | `200` |
| `testing.coverage_tool` | 测试覆盖率工具 | `nyc` |
| `testing.coverage_threshold` | 覆盖率阈值（百分比） | `80` |

## 常见操作

### 恢复中断的流水线

```bash
# 查看中断的阶段
cat .pipeline/state.json | python3 -c "import json,sys; s=json.load(sys.stdin); print(f'Status: {s[\"status\"]}, Phase: {s[\"current_phase\"]}')"

# 重新启动（Orchestrator 会从 state.json 恢复）
claude --agent orchestrator
```

### 手动回退到指定阶段

```bash
# 编辑 state.json，将 current_phase 改为目标阶段，status 改为 running
python3 -c "
import json
s = json.load(open('.pipeline/state.json'))
s['current_phase'] = 'phase-3'
s['status'] = 'running'
with open('.pipeline/state.json', 'w') as f:
  json.dump(s, f, indent=2)
"
claude --agent orchestrator
```

### 查看 Gate 审核结果

```bash
cat .pipeline/artifacts/gate-a-review.json | python3 -m json.tool
```

### 必备 Skills 安装

流水线要求以下两个 Skill 已安装：

```bash
# 检查
ls ~/.claude/plugins/ | grep -E "code-simplifier|code-review"
```

如缺失，请参考 Claude Code Skill 安装文档。

## 安装 Agents

```bash
# 从本 repo 安装最新 Agents 到 ~/.claude/agents/
bash install.sh
```
