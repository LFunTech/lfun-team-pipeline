# PaddleOCR 手写体识别训练系统 — Pipeline 执行计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在新 demo 项目中运行 team-creator v6 流水线（24 Agent），由 Orchestrator 自动构建 PaddleOCR 手写体识别训练系统完整微服务代码。

**Architecture:** 7 个微服务（annotation/dataset/training/inference/model-registry + React前端 + Nginx网关），Docker Compose 编排，双 V100 GPU 分配，PostgreSQL + MinIO + Redis。

**Tech Stack:** Python/FastAPI × 5 服务，React/Vite，Nginx，PostgreSQL，MinIO，Redis，PaddleOCR，pix2tex，Celery，pytest，Playwright。

**设计文档：** `docs/plans/2026-03-05-paddleocr-training-design.md`

---

## Task 1: 安装最新版 agents

**Files:**
- Run: `bash /home/min/repos/team-creator/install.sh`

**Step 1: 确认 agents 源文件都在**

```bash
ls /home/min/repos/team-creator/agents/ | wc -l
```
Expected: 24

**Step 2: 安装到 ~/.claude/agents/**

```bash
bash /home/min/repos/team-creator/install.sh
```
Expected: 24 个 .md 文件复制到 `~/.claude/agents/`

**Step 3: 验证安装**

```bash
ls ~/.claude/agents/ | wc -l
```
Expected: ≥ 24

**Step 4: Commit**

```bash
# install.sh 不修改源码，无需 commit
echo "Agents installed successfully"
```

---

## Task 2: 创建 demo 项目目录并初始化

**Files:**
- Create: `/home/min/repos/demo-paddleocr/`

**Step 1: 创建目录**

```bash
mkdir -p /home/min/repos/demo-paddleocr
cd /home/min/repos/demo-paddleocr
```

**Step 2: 初始化 git 仓库**

```bash
cd /home/min/repos/demo-paddleocr
git init
git commit --allow-empty -m "chore: initial empty commit"
```
Expected: `Initialized empty Git repository`

**Step 3: 创建 .gitignore**

```bash
cat > .gitignore << 'EOF'
__pycache__/
*.pyc
*.pyo
.env
node_modules/
dist/
.worktrees/
*.egg-info/
.pytest_cache/
htmlcov/
.coverage
EOF
git add .gitignore
git commit -m "chore: add .gitignore"
```

---

## Task 3: 复制并配置 pipeline 模板

**Files:**
- Create: `/home/min/repos/demo-paddleocr/.pipeline/`
- Create: `/home/min/repos/demo-paddleocr/CLAUDE.md`

**Step 1: 复制 autosteps 和 CLAUDE.md**

```bash
cd /home/min/repos/demo-paddleocr
mkdir -p .pipeline/autosteps .pipeline/artifacts
cp -r /home/min/repos/team-creator/templates/.pipeline/autosteps/. .pipeline/autosteps/
cp /home/min/repos/team-creator/templates/CLAUDE.md CLAUDE.md
```

**Step 2: 复制并自定义 config.json**

```bash
cp /home/min/repos/team-creator/templates/.pipeline/config.json .pipeline/config.json
```

**Step 3: 编辑 config.json**

将以下内容写入 `.pipeline/config.json`（完整替换）：

```json
{
  "version": "v6",
  "pipeline_id": "pipe-20260305-001",
  "project_name": "paddleocr-training-system",
  "max_attempts": {
    "default": 3,
    "phase-0": 5,
    "phase-0.5": 3,
    "phase-1": 3,
    "phase-2": 3,
    "phase-2.5": 3,
    "phase-3": 5,
    "phase-3.5": 3,
    "phase-4a": 3,
    "phase-4b": 3,
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
    "coverage_tool": "pytest-cov",
    "coverage_format": ["lcov", "json"],
    "coverage_output_dir": ".pipeline/artifacts/coverage/",
    "coverage_required": true,
    "coverage_threshold": 80
  },
  "monitor": {
    "observation_window_minutes": 30,
    "error_rate_alert_ratio": 0.001,
    "error_rate_critical_ratio": 0.01
  },
  "gates": {
    "gate-d": {
      "rollback_to_allowed": ["phase-4a", "phase-3"],
      "rollback_to_max_depth": "phase-2"
    }
  },
  "autosteps": {
    "contract_compliance": {
      "service_start_cmd": "docker compose up -d --wait",
      "service_base_url": "http://localhost:80",
      "health_path": "/health"
    }
  }
}
```

**Step 4: 验证配置**

```bash
python3 -c "import json; d=json.load(open('.pipeline/config.json')); print('project_name:', d['project_name'])"
```
Expected: `project_name: paddleocr-training-system`

**Step 5: Commit**

```bash
git add .pipeline/ CLAUDE.md
git commit -m "chore: add pipeline templates and config"
```

---

## Task 4: 写入初始需求文档（供 Clarifier 使用）

**Files:**
- Create: `/home/min/repos/demo-paddleocr/.pipeline/artifacts/initial-requirement.txt`

**Step 1: 创建初始需求文本**

```bash
mkdir -p .pipeline/artifacts
cat > .pipeline/artifacts/initial-requirement.txt << 'EOF'
# 需求：PaddleOCR 手写体识别训练系统

## 背景
需要开发一套完整的 PaddleOCR 手写体识别训练系统，支持中英文及数学/物理/化学相关手写内容识别，并能将手写公式输出为 LaTeX 格式。

## 用户群体
1. **研究人员/教师**：上传手写样本，通过内置标注工具画框标注，提交 PaddleOCR 训练任务，导出训练好的模型
2. **学生/考生**：拍照上传手写内容（文字、公式、方程），在线获得识别结果（文字内容 + LaTeX 公式）
3. **平台运营方**：管理数据集、监控训练任务队列、管理模型版本上线/下线、查看推理日志

## 技术要求
- 完整微服务架构（7个服务）：annotation-service、dataset-service、training-service、inference-service、model-registry、React前端、Nginx网关
- 部署：Docker Compose，双 V100 32GB GPU（训练服务用 GPU #0，推理服务用 GPU #1）
- 数据存储：PostgreSQL（元数据）+ MinIO（图片/模型文件）+ Redis（Celery训练任务队列）
- 公式识别：调用 pix2tex 开源模型输出 LaTeX（第一期）
- 前端框架：React，支持三种用户角色视图
- 测试覆盖率：≥ 80%（pytest-cov）

## 功能清单
### 标注工具
- 图片上传（支持 JPG/PNG，最大 10MB）
- Canvas 画框标注，支持标注类型：text/formula/diagram
- LaTeX 输入实时 KaTeX 渲染预览

### 训练管理
- 选择数据集和模型类型提交训练任务
- 通过 WebSocket 实时显示训练进度（loss/accuracy曲线）
- 训练完成后自动注册到 model-registry

### 推理服务
- 上传图片，自动检测文字区域（PaddleOCR）和公式区域（pix2tex）
- 返回结构化 JSON：文字内容 + LaTeX 公式
- 推理延迟要求：< 3秒（单张 A4 纸）

### 模型管理
- 模型版本列表、准确率对比
- 一键上线/下线
- 模型文件存储在 MinIO

## 范围边界（本期不包括）
- 自训练公式识别模型
- 多机分布式训练
- 移动端 App
- 模型量化/蒸馏
EOF
```

**Step 2: Commit**

```bash
git add .pipeline/artifacts/initial-requirement.txt
git commit -m "docs: add initial requirement for pipeline"
```

---

## Task 5: 启动 Orchestrator（Phase 0 — Clarifier）

**注意：Phase 0 需要人工参与（Clarifier 会向用户提问）**

**Step 1: 切换到 demo 项目目录**

```bash
cd /home/min/repos/demo-paddleocr
```

**Step 2: 启动 Orchestrator**

```bash
claude --agent orchestrator
```

启动后，Orchestrator 会：
1. 初始化 `.pipeline/state.json`
2. 调用 Clarifier，Clarifier 读取 `initial-requirement.txt`
3. Clarifier 最多 5 轮澄清问题（每轮会暂停等待用户输入）

**Step 3: 回答 Clarifier 的问题**

参考设计文档 `docs/plans/2026-03-05-paddleocr-training-design.md` 回答问题：
- 用户角色：researcher/student/operator 三种
- 部署：Docker Compose + 双 V100
- 标注：内置工具
- 公式：pix2tex → LaTeX
- 测试框架：pytest-cov，80% 覆盖率

**Step 4: 确认 requirement.md 生成**

```bash
ls -la .pipeline/artifacts/requirement.md
wc -w .pipeline/artifacts/requirement.md
```
Expected: 存在，字数 > 200

---

## Task 6: 监控 Phase 0.5 → Gate A → Phase 2（自动执行）

这些阶段 Orchestrator 自动执行，无需人工干预（除非 FAIL）。

**Step 1: 观察 Phase 0.5（Requirement Completeness）**

Orchestrator 自动运行，观察输出。若 FAIL，Orchestrator 会自动回滚到 Phase 0 让 Clarifier 补充。

**Step 2: 观察 Phase 1（Architect）**

Architect 读取 requirement.md，生成：
- `.pipeline/artifacts/proposal.md`
- `.pipeline/artifacts/adr-draft.md`

期望：proposal.md 包含 7 个服务的技术设计、API 设计、数据库 schema 草稿。

**Step 3: 观察 Gate A（4 个 Auditor 并行）**

期望：4 个 Auditor（biz/tech/qa/ops）并行审核 proposal.md。

**常见 Gate A FAIL 原因**（参考历史 demo）：
- Architect 未考虑 GPU OOM 处理
- Architect 未考虑 Docker Compose 健康检查
- Architect 未定义 /health 路径
→ Resolver 会自动修复，属于预期行为

**Step 4: 观察 Phase 2（Planner）+ Gate B**

Planner 生成 `.pipeline/artifacts/tasks.json`，分配给各 Builder。

**检查点：Gate B 通过后，确认 tasks.json 包含 7 个服务的任务分配**

```bash
python3 -c "
import json
tasks = json.load(open('.pipeline/artifacts/tasks.json'))
print('Total tasks:', len(tasks.get('tasks', [])))
builders = set(t.get('assigned_to') for t in tasks.get('tasks', []))
print('Builders:', builders)
"
```

---

## Task 7: 监控 Phase 2.5 → Phase 3（并行 Builder 执行）

**Step 1: 观察 Phase 2.5（Contract Formalizer）**

Contract Formalizer 生成 `.pipeline/artifacts/contracts/` 目录，包含各服务的 OpenAPI spec。

**验证：**
```bash
ls .pipeline/artifacts/contracts/
```
Expected: annotation-service.yaml, dataset-service.yaml, training-service.yaml, inference-service.yaml, model-registry.yaml

**Step 2: 观察 Phase 3 Worktree 初始化**

Orchestrator 为每个 Builder 创建 worktree：
```bash
ls .worktrees/
```
Expected: builder-dba, builder-backend, builder-frontend, builder-security, builder-infra

**Step 3: 观察 Builder 执行顺序（波次）**

- 波次 1：builder-dba（PostgreSQL schema + migrations）
- 波次 2：builder-backend（5 个 FastAPI 服务）
- 波次 3：builder-security + builder-frontend（并行但顺序执行）
- 波次 4：builder-infra（Docker Compose + Nginx）

**重要：builder-backend 会构建 5 个服务，耗时最长**

**Step 4: 观察合并序列**

所有 Builder 完成后，Orchestrator 按顺序 merge worktree 分支。

若出现合并冲突（ESCALATION）：
```bash
# 人工解决
git checkout main
git merge --no-ff pipeline/phase-3/builder-<name>
# 手动解决冲突后
git add .
git commit -m "merge: resolve conflict in builder-<name>"
```

---

## Task 8: 监控 Phase 3.1 → Gate C → Phase 3.7（代码质量门禁）

**Step 1: 观察 Phase 3.1（Static Analyzer）**

```bash
cat .pipeline/artifacts/static-analysis-report.json | python3 -m json.tool | head -30
```

**Step 2: 观察 Phase 3.5（Simplifier）**

Simplifier 重构冗余代码。

**Step 3: 观察 Gate C（Inspector 代码审查）**

若 FAIL：Orchestrator 回滚到 Phase 3 重新构建。

**Step 4: 观察 Phase 3.7（Contract Compliance Checker）**

这是最容易出问题的环节。Orchestrator 会：
1. 读取 config.json 中的 `service_start_cmd`
2. 执行 `docker compose up -d --wait`
3. 轮询 `http://localhost:80/health`
4. 运行 contract-compliance-checker.sh
5. 关闭服务

**若服务启动失败，检查：**
```bash
docker compose logs --tail=50
docker compose ps
```

---

## Task 9: 监控 Phase 4a（Tester）→ Gate D → Phase 5/6

**Step 1: 观察 Phase 4a（Tester）**

Tester 运行所有 pytest 测试，生成覆盖率报告。

**验证：**
```bash
cat .pipeline/artifacts/test-report.json | python3 -c "
import json, sys
r = json.load(sys.stdin)
print('passed:', r.get('passed'))
print('failed:', r.get('failed'))
print('coverage:', r.get('coverage_percent'))
"
```

**Step 2: 观察 Phase 4.2（Test Coverage Enforcer）**

目标：≥ 80% 覆盖率。若未达标，Orchestrator 回滚 Phase 4a。

**Step 3: 观察 Gate D（Auditor-QA）**

**Step 4: 观察 Phase 5（Documenter）**

Documenter 生成/更新：
- `README.md`
- `CHANGELOG.md`
- `docs/openapi.yaml`（汇总）

**Step 5: 观察 Gate E（最终验收）**

4 个 Auditor 并行最终审核。PASS 即完成。

---

## Task 10: 验收与记录

**Step 1: 验证最终状态**

```bash
cd /home/min/repos/demo-paddleocr
git log --oneline | head -20
ls .pipeline/artifacts/
python3 -c "
import json
state = json.load(open('.pipeline/state.json'))
print('status:', state['status'])
print('last_completed_phase:', state['last_completed_phase'])
"
```
Expected: `status: completed`, `last_completed_phase: gate-e`

**Step 2: 验证服务可以启动**

```bash
docker compose up -d
docker compose ps
curl http://localhost:80/health
```
Expected: 所有容器 Running，/health 返回 200

**Step 3: 运行最终测试**

```bash
pytest --tb=short
```
Expected: 全部通过，覆盖率 ≥ 80%

**Step 4: 记录 pipeline 发现的 Bug**

将任何新发现的 pipeline bug 记录到：
```
/home/min/repos/team-creator/docs/plans/2026-03-05-paddleocr-pipeline-findings.md
```

格式：
```markdown
## Bug N: [标题]
- **发现阶段**：Phase X / Gate X
- **现象**：...
- **根因**：...
- **修复方案**：修改 agents/<agent>.md 或 templates/.pipeline/autosteps/<script>.sh
- **状态**：已修复 / 待修复
```

**Step 5: 若有 Bug 修复，更新 team-creator**

```bash
cd /home/min/repos/team-creator
# 修改对应 agent 或 autostep
bash install.sh  # 重新安装
git add agents/ templates/
git commit -m "fix: <bug description> found in paddleocr demo"
```

---

## 检查点汇总

| 阶段 | 人工介入？ | 预期产出 |
|------|----------|---------|
| Phase 0 Clarifier | ✅ 回答问题 | requirement.md |
| Phase 1 Architect | 否（可能 FAIL→Resolver自动修复） | proposal.md |
| Gate A | 否 | gate-a-review.json PASS |
| Phase 2 Planner | 否 | tasks.json |
| Phase 2.5 Contract Formalizer | 否 | contracts/*.yaml |
| Phase 3 Builders | ✅ 监控，冲突时人工解决 | 5个服务代码 |
| Gate C Inspector | 否 | gate-c-review.json PASS |
| Phase 3.7 Contract Compliance | ✅ 若服务起不来需人工排查 | compliance通过 |
| Phase 4a Tester | 否 | 覆盖率 ≥ 80% |
| Gate D Auditor-QA | 否 | gate-d-review.json PASS |
| Phase 5 Documenter | 否 | README/CHANGELOG |
| Gate E 最终验收 | 否 | gate-e-review.json PASS |

---

## 参考资料

- 设计文档：`docs/plans/2026-03-05-paddleocr-training-design.md`
- 历史 demo 记录：`/home/min/repos/team-creator/memory/MEMORY.md`
- Orchestrator 全文：`/home/min/repos/team-creator/agents/orchestrator.md`
- 已知问题：Gate A 常因 Architect 遗漏运维事项 FAIL → Resolver 自动修复，属预期行为
