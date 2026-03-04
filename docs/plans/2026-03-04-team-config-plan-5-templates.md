# Team Config Plan Part 5: Templates + install.sh

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 创建项目模板文件（CLAUDE.md、config.json）、install.sh 安装脚本，并完成最终验证。

**Architecture:** `templates/CLAUDE.md` 供项目使用，`templates/.pipeline/config.json` 为流水线配置模板，`install.sh` 一键安装 agents 到 `~/.claude/agents/`。

**Tech Stack:** Markdown, JSON, Bash

**依赖:** Part 1-4（所有 Agent 文件和 AutoStep 脚本已创建）
**本文件是最后一步。**

---

### Task 1: 创建 templates/CLAUDE.md

**Files:**
- Create: `templates/CLAUDE.md`

**Step 1: 写入文件**

```markdown
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
```

**Step 2: 验证**

```bash
grep "claude --agent orchestrator" templates/CLAUDE.md
```
Expected: 输出包含该命令

**Step 3: Commit**

```bash
git add templates/CLAUDE.md
git commit -m "feat: add project CLAUDE.md template"
```

---

### Task 2: 创建 templates/.pipeline/config.json

**Files:**
- Create: `templates/.pipeline/config.json`

**Step 1: 写入文件**

```json
{
  "version": "v6",
  "pipeline_id": "pipe-YYYYMMDD-001",
  "project_name": "YOUR_PROJECT_NAME",
  "max_attempts": {
    "default": 3,
    "phase-0": 5,
    "phase-1": 3,
    "phase-2": 3,
    "phase-2.5": 3,
    "phase-3": 5,
    "phase-3.5": 3,
    "phase-4a": 3,
    "phase-5": 3,
    "phase-6": 2,
    "gate-a": 3,
    "gate-b": 3,
    "gate-c": 3,
    "gate-d": 3,
    "gate-e": 3
  },
  "required_skills": ["code-simplifier", "code-review"],
  "requirement_completeness": {
    "parent_section": "## 最终需求定义",
    "required_sections": [
      "### 功能描述",
      "### 用户故事",
      "### 业务规则",
      "### 范围边界",
      "### 验收标准"
    ],
    "section_match_mode": "prefix",
    "min_words": 200,
    "abort_on_critical_unresolved": true
  },
  "clarifier": {
    "max_rounds": 5
  },
  "testing": {
    "coverage_tool": "nyc",
    "coverage_format": ["lcov", "json"],
    "coverage_output_dir": ".pipeline/artifacts/coverage/",
    "coverage_required": true,
    "coverage_threshold": 80
  },
  "monitor": {
    "observation_window_minutes": 30,
    "error_rate_alert_pct": 0.1,
    "error_rate_critical_pct": 1.0
  },
  "gates": {
    "gate-d": {
      "rollback_to_allowed": ["phase-4a", "phase-3"],
      "rollback_to_max_depth": "phase-2"
    }
  },
  "autosteps": {
    "contract_compliance": {
      "service_base_url": "http://localhost:3000"
    }
  }
}
```

**Step 2: 验证 JSON 格式**

```bash
python3 -c "import json; json.load(open('templates/.pipeline/config.json')); print('Valid JSON')"
```
Expected: `Valid JSON`

**Step 3: Commit**

```bash
git add templates/.pipeline/config.json
git commit -m "feat: add pipeline config.json template"
```

---

### Task 3: 创建 install.sh

**Files:**
- Create: `install.sh`

**Step 1: 写入文件**

```bash
#!/bin/bash
# install.sh — 安装 Claude Code Team Pipeline Agents
# 将 agents/ 目录下所有 .md 文件复制到 ~/.claude/agents/

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="$REPO_DIR/agents"
AGENTS_DST="$HOME/.claude/agents"

echo "╔══════════════════════════════════════════════╗"
echo "║  Claude Code Team Pipeline — Agent 安装程序  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 验证源目录 ─────────────────────────────────────────────────────
if [ ! -d "$AGENTS_SRC" ]; then
  echo "❌ 错误: agents/ 目录不存在，请在 repo 根目录运行此脚本"
  exit 1
fi

AGENT_COUNT=$(find "$AGENTS_SRC" -name "*.md" | wc -l)
if [ "$AGENT_COUNT" -eq 0 ]; then
  echo "❌ 错误: agents/ 目录为空，请先执行安装计划"
  exit 1
fi

# ── 创建目标目录 ────────────────────────────────────────────────────
mkdir -p "$AGENTS_DST"
echo "📁 目标目录: $AGENTS_DST"
echo ""

# ── 备份现有文件 ────────────────────────────────────────────────────
EXISTING=$(find "$AGENTS_DST" -name "*.md" 2>/dev/null | wc -l)
if [ "$EXISTING" -gt 0 ]; then
  BACKUP_DIR="$AGENTS_DST.backup.$(date +%Y%m%d%H%M%S)"
  echo "⚠️  检测到 $EXISTING 个现有 Agent 文件，备份到: $BACKUP_DIR"
  cp -r "$AGENTS_DST" "$BACKUP_DIR"
  echo ""
fi

# ── 复制 Agent 文件 ─────────────────────────────────────────────────
echo "📋 安装 Agent 文件..."
INSTALLED=0
while IFS= read -r agent_file; do
  fname=$(basename "$agent_file")
  cp "$agent_file" "$AGENTS_DST/$fname"
  echo "  ✓ $fname"
  INSTALLED=$((INSTALLED + 1))
done < <(find "$AGENTS_SRC" -name "*.md" | sort)

echo ""
echo "✅ 安装完成！已安装 $INSTALLED 个 Agent 文件到 $AGENTS_DST"
echo ""

# ── 验证安装 ──────────────────────────────────────────────────────
echo "── 安装验证 ──────────────────────────────────────"
REQUIRED_AGENTS=("orchestrator" "clarifier" "architect" "auditor-biz" "auditor-tech" "auditor-qa" "auditor-ops" "resolver" "planner" "contract-formalizer" "builder-frontend" "builder-backend" "builder-dba" "builder-security" "builder-infra" "simplifier" "inspector" "tester" "documenter" "deployer" "monitor" "migrator" "optimizer" "translator")

MISSING=0
for agent in "${REQUIRED_AGENTS[@]}"; do
  if [ -f "$AGENTS_DST/$agent.md" ]; then
    echo "  ✓ $agent"
  else
    echo "  ✗ $agent (缺失!)"
    MISSING=$((MISSING + 1))
  fi
done

echo ""
if [ "$MISSING" -eq 0 ]; then
  echo "🎉 所有 24 个 Agent 已成功安装！"
else
  echo "⚠️  $MISSING 个 Agent 安装失败，请检查 agents/ 目录"
  exit 1
fi

# ── 检查必备 Skills ────────────────────────────────────────────────
echo ""
echo "── 必备 Skills 检查 ────────────────────────────"
echo "流水线需要以下两个 Skill："
echo "  • code-simplifier (Simplifier 使用)"
echo "  • code-review (Inspector 使用)"
echo ""
if ls ~/.claude/plugins/ 2>/dev/null | grep -qE "code-simplifier|code-review"; then
  echo "  ✓ Skills 已安装"
else
  echo "  ℹ️  提示：如 Skills 未安装，Inspector 和 Simplifier 功能将降级"
  echo "      请参考: https://docs.anthropic.com/claude-code/skills"
fi

# ── 使用说明 ──────────────────────────────────────────────────────
echo ""
echo "── 使用方法 ─────────────────────────────────────"
echo ""
echo "1. 初始化项目流水线配置："
echo "   mkdir -p .pipeline/autosteps .pipeline/artifacts"
echo "   cp -r $REPO_DIR/templates/.pipeline/config.json .pipeline/"
echo "   cp -r $REPO_DIR/templates/.pipeline/autosteps/ .pipeline/autosteps/"
echo "   cp $REPO_DIR/templates/CLAUDE.md CLAUDE.md"
echo ""
echo "2. 编辑 .pipeline/config.json，设置 project_name 等配置"
echo ""
echo "3. 启动流水线："
echo "   claude --agent orchestrator"
echo ""
echo "════════════════════════════════════════════════"
```

**Step 2: 设置可执行权限**

```bash
chmod +x install.sh
```

**Step 3: 验证**

```bash
bash -n install.sh && echo "Syntax OK"
```
Expected: `Syntax OK`

**Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: add install.sh one-click agent installer"
```

---

### Task 4: 最终验证和汇总 commit

**Step 1: 验证 agents/ 目录文件数量**

```bash
find agents/ -name "*.md" | wc -l
```
Expected: `24`

**Step 2: 验证 AutoStep 脚本数量**

```bash
find templates/.pipeline/autosteps/ -name "*.sh" | wc -l
```
Expected: `15`（注意：Part 4 Task 9 中有 4 个脚本在同一 Task，需确认全部 15 个都创建了）

**Step 3: 列出所有 24 个 Agent 文件**

```bash
ls agents/*.md | sort
```
Expected（按字母顺序）:
```
agents/architect.md
agents/auditor-biz.md
agents/auditor-ops.md
agents/auditor-qa.md
agents/auditor-tech.md
agents/builder-backend.md
agents/builder-dba.md
agents/builder-frontend.md
agents/builder-infra.md
agents/builder-security.md
agents/contract-formalizer.md
agents/deployer.md
agents/documenter.md
agents/inspector.md
agents/migrator.md
agents/monitor.md
agents/optimizer.md
agents/orchestrator.md
agents/planner.md
agents/resolver.md
agents/simplifier.md
agents/tester.md
agents/translator.md
agents/clarifier.md
```

**Step 4: 验证所有 YAML frontmatter 有效**

```bash
for f in agents/*.md; do
  name=$(python3 -c "
import re
with open('$f') as fh:
  content = fh.read()
m = re.search(r'^---\n(.*?)\n---', content, re.DOTALL)
if m:
  import yaml
  data = yaml.safe_load(m.group(1))
  print(data.get('name', 'NO_NAME'))
else:
  print('NO_FRONTMATTER')
" 2>/dev/null || echo "ERROR")
  echo "$f: $name"
done
```
Expected: 每个文件输出其 `name` 字段值，无 ERROR 或 NO_FRONTMATTER

**Step 5: 运行 install.sh 验证（dry-run 检查语法）**

```bash
bash -n install.sh && echo "install.sh syntax OK"
```

**Step 6: 检查 templates/ 结构**

```bash
find templates/ -type f | sort
```
Expected:
```
templates/.pipeline/artifacts/.gitkeep
templates/.pipeline/autosteps/api-change-detector.sh
templates/.pipeline/autosteps/assumption-propagation-validator.sh
templates/.pipeline/autosteps/changelog-consistency-checker.sh
templates/.pipeline/autosteps/contract-compliance-checker.sh
templates/.pipeline/autosteps/contract-semantic-validator.sh
templates/.pipeline/autosteps/diff-scope-validator.sh
templates/.pipeline/autosteps/performance-baseline-checker.sh
templates/.pipeline/autosteps/post-simplification-verifier.sh
templates/.pipeline/autosteps/pre-deploy-readiness-check.sh
templates/.pipeline/autosteps/regression-guard.sh
templates/.pipeline/autosteps/requirement-completeness-checker.sh
templates/.pipeline/autosteps/schema-completeness-validator.sh
templates/.pipeline/autosteps/static-analyzer.sh
templates/.pipeline/autosteps/test-coverage-enforcer.sh
templates/.pipeline/autosteps/test-failure-mapper.sh
templates/.pipeline/config.json
templates/CLAUDE.md
```

**Step 7: 最终汇总 commit（如有未提交的文件）**

```bash
git status
git add -A
git commit -m "feat: complete claude-code team pipeline configuration (42 files)

- 24 LLM agent files in agents/
- 15 AutoStep shell scripts in templates/.pipeline/autosteps/
- Project templates: CLAUDE.md + config.json
- install.sh one-click installer

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

**Step 8: 运行 install.sh 实际安装**

```bash
bash install.sh
```
Expected: 输出 "🎉 所有 24 个 Agent 已成功安装！"

---

### 附录：文件清单核对表

| 类别 | 数量 | 位置 |
|------|------|------|
| LLM Agent 文件 | 24 个 .md | `agents/` |
| AutoStep 脚本 | 15 个 .sh | `templates/.pipeline/autosteps/` |
| 项目模板 | 2 个 | `templates/` |
| 安装脚本 | 1 个 | `install.sh` |
| **合计** | **42 个文件** | — |

### 附录：15 个 AutoStep 文件清单

| 文件 | Phase | Plan 文件 |
|------|-------|----------|
| `requirement-completeness-checker.sh` | 0.5 | Part 4 Task 1 |
| `assumption-propagation-validator.sh` | 2.1 | Part 4 Task 2 |
| `schema-completeness-validator.sh` | 2.6 | Part 4 Task 3 |
| `contract-semantic-validator.sh` | 2.7 | Part 4 Task 4 |
| `static-analyzer.sh` | 3.1 | Part 4 Task 5 |
| `diff-scope-validator.sh` | 3.2 | Part 4 Task 6 |
| `regression-guard.sh` | 3.3 | Part 4 Task 6 |
| `post-simplification-verifier.sh` | 3.6 | Part 4 Task 7 |
| `contract-compliance-checker.sh` | 3.7 | Part 4 Task 7 |
| `test-failure-mapper.sh` | 4a.1 | Part 4 Task 8 |
| `test-coverage-enforcer.sh` | 4.2 | Part 4 Task 8 |
| `performance-baseline-checker.sh` | 4.3 | Part 4 Task 9 |
| `api-change-detector.sh` | 5前置 | Part 4 Task 9 |
| `changelog-consistency-checker.sh` | 5.1 | Part 4 Task 9 |
| `pre-deploy-readiness-check.sh` | 6.0 | Part 4 Task 9 |
