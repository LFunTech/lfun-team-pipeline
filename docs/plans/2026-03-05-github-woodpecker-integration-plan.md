# GitHub & Woodpecker CI 集成实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 team-creator v6 流水线新增 GitHub 自动化（repo 创建、每阶段 push）、`.depend/` 凭证管理、Woodpecker CI 三环境 pipeline 生成。

**Architecture:** 新增 `github-ops` Agent（第 25 个）+ `depend-collector.sh` AutoStep，修改 `orchestrator.md` 在每个 Phase/Gate 后执行规范化 commit+push，修改 `builder-infra.md` 增加 `.woodpecker/` 生成职责。

**Tech Stack:** bash, gh CLI, Woodpecker CI YAML, Conventional Commits

**设计文档：** `docs/plans/2026-03-05-github-woodpecker-integration-design.md`

---

## Task 1: 新增 github-ops Agent

**Files:**
- Create: `agents/github-ops.md`

**Step 1: 创建 github-ops.md**

```bash
cat > agents/github-ops.md << 'AGENT_EOF'
---
name: github-ops
description: "[Pipeline] GitHub 仓库管理与 Woodpecker CI 配置推送。Phase 2.0a 创建 GitHub repo（需用户确认），Gate E 后推送 .woodpecker/ 配置。仅在多角色软件交付流水线中使用。"
tools: Read, Write, Edit, Bash, Glob, Grep
model: inherit
permissionMode: acceptEdits
---

# GitHub Ops — GitHub 仓库管理

## 角色

你负责两个场景：
1. **Phase 2.0a**：在 GitHub 创建项目仓库（需用户确认）
2. **Gate E 后**：推送 `.woodpecker/` CI 配置到 GitHub

## 场景 1 — 创建 GitHub Repo

### 输入

- `.pipeline/config.json`（读取 `project_name`）
- `.pipeline/artifacts/proposal.md`（提取一行摘要作为 repo description）

### 行为

1. 读取 `project_name`：
   ```bash
   PROJECT_NAME=$(python3 -c "import json; print(json.load(open('.pipeline/config.json'))['project_name'])")
   ```

2. 读取当前认证用户：
   ```bash
   GH_USER=$(gh api user --jq '.login')
   ```

3. 从 proposal.md 提取摘要（第一个非空非标题行，截断到 100 字符）：
   ```bash
   DESCRIPTION=$(grep -v "^#" .pipeline/artifacts/proposal.md | grep -v "^$" | head -1 | cut -c1-100)
   ```

4. **向用户展示确认信息**：
   ```
   ══════════════════════════════════════
   即将创建 GitHub 仓库：
     名称：<GH_USER>/<PROJECT_NAME>
     可见性：private
     描述：<DESCRIPTION>
   ══════════════════════════════════════
   请确认（输入"确认"继续，输入"取消"中止）：
   ```

5. 等待用户输入：
   - 输入"确认" → 执行第 6 步
   - 输入"取消" → 输出 `overall: CANCELLED`，Orchestrator 跳过后续 push 但继续流水线

6. 执行创建：
   ```bash
   gh repo create "$GH_USER/$PROJECT_NAME" \
     --private \
     --description "$DESCRIPTION" \
     --source=. \
     --remote=origin \
     --push
   ```
   > `--source=. --remote=origin --push` 同时设置 remote 并推送当前内容。

7. 验证：
   ```bash
   git remote -v | grep origin
   gh repo view "$GH_USER/$PROJECT_NAME" --json url --jq '.url'
   ```

### 输出

`.pipeline/artifacts/github-repo-info.json`：
```json
{
  "github_ops_agent": "github-ops",
  "scenario": "create_repo",
  "timestamp": "<ISO-8601>",
  "repo_url": "https://github.com/<user>/<project>",
  "clone_url": "git@github.com:<user>/<project>.git",
  "overall": "PASS"
}
```

若用户取消：
```json
{
  "overall": "CANCELLED",
  "reason": "user_cancelled"
}
```

---

## 场景 2 — 推送 Woodpecker 配置

### 输入

- `.woodpecker/` 目录（builder-infra 已生成 test.yml / staging.yml / prod.yml）
- `.pipeline/artifacts/github-repo-info.json`

### 行为

1. 确认三个文件存在：
   ```bash
   for f in .woodpecker/test.yml .woodpecker/staging.yml .woodpecker/prod.yml; do
     [ -f "$f" ] || { echo "缺少 $f"; exit 1; }
   done
   ```

2. 检查 `github-repo-info.json` 中 `overall != CANCELLED`（若用户当时取消了创建，跳过 push）

3. 提交并推送：
   ```bash
   git add .woodpecker/
   git commit -m "chore: add deployment configuration and woodpecker pipelines"
   git push origin main
   ```

4. 输出推送结果：
   ```bash
   echo "Woodpecker 配置已推送至 $(gh repo view --json url --jq '.url')/.woodpecker/"
   ```

### 输出

追加到 `.pipeline/artifacts/github-repo-info.json`（更新 `woodpecker_pushed` 字段）：
```json
{
  "woodpecker_pushed": true,
  "woodpecker_push_timestamp": "<ISO-8601>"
}
```

---

## 约束

- 绝不自动执行创建操作，必须等用户确认
- `gh` CLI 必须已认证（`gh auth status` 验证），未认证时输出错误并 ESCALATION
- 不注册 Woodpecker secret，不触发 CI 构建
AGENT_EOF
```

**Step 2: 验证文件创建成功**

```bash
head -5 agents/github-ops.md
wc -l agents/github-ops.md
```
Expected: front matter 正确，行数 > 50

**Step 3: Commit**

```bash
git add agents/github-ops.md
git commit -m "feat: add github-ops agent for repo creation and woodpecker push"
```

---

## Task 2: 新增 depend-collector.sh AutoStep

**Files:**
- Create: `templates/.pipeline/autosteps/depend-collector.sh`

**Step 1: 创建脚本**

```bash
cat > templates/.pipeline/autosteps/depend-collector.sh << 'SCRIPT_EOF'
#!/usr/bin/env bash
# depend-collector.sh — 解析 proposal.md 关键词，生成 .depend/ 凭证模板
# 用法：PIPELINE_DIR=.pipeline bash .pipeline/autosteps/depend-collector.sh
set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
PROPOSAL="$PIPELINE_DIR/artifacts/proposal.md"
DEPEND_DIR=".depend"
REPORT="$PIPELINE_DIR/artifacts/depend-collection-report.json"

# 检查 proposal.md 存在
if [ ! -f "$PROPOSAL" ]; then
  echo "ERROR: $PROPOSAL 不存在" >&2
  exit 1
fi

mkdir -p "$DEPEND_DIR"

DETECTED=()
GENERATED=()
SKIPPED=()

# ── 检测函数 ──────────────────────────────────────────────
detect() {
  local keywords=("$@")
  for kw in "${keywords[@]}"; do
    if grep -qi "$kw" "$PROPOSAL"; then
      return 0
    fi
  done
  return 1
}

generate_template() {
  local name="$1"
  local content="$2"
  local template_file="$DEPEND_DIR/${name}.env.template"
  local env_file="$DEPEND_DIR/${name}.env"

  if [ -f "$env_file" ]; then
    SKIPPED+=("$env_file（已存在）")
    return
  fi

  if [ ! -f "$template_file" ]; then
    echo "$content" > "$template_file"
    GENERATED+=("$template_file")
  fi
  DETECTED+=("$name")
}

# ── 关键词检测 ────────────────────────────────────────────
if detect "PostgreSQL" "MySQL" "MariaDB" "MongoDB"; then
  generate_template "db" "# 数据库连接配置
DB_HOST=
DB_PORT=
DB_USER=
DB_PASSWORD=
DB_NAME="
fi

if detect "Redis"; then
  generate_template "redis" "# Redis 连接配置
REDIS_HOST=
REDIS_PORT=6379
REDIS_PASSWORD="
fi

if detect "Woodpecker"; then
  generate_template "woodpecker" "# Woodpecker CI 配置
WOODPECKER_URL=
WOODPECKER_TOKEN="
fi

if detect "GPU" "V100" "A100" "H100" "CUDA" "nvidia"; then
  generate_template "server" "# GPU 服务器 SSH 配置
SSH_HOST=
SSH_PORT=22
SSH_USER=
SSH_KEY_PATH=~/.ssh/id_rsa"
fi

if detect "MinIO" "S3" "OSS" "对象存储" "object storage"; then
  generate_template "storage" "# 对象存储配置
STORAGE_ENDPOINT=
STORAGE_ACCESS_KEY=
STORAGE_SECRET_KEY=
STORAGE_BUCKET="
fi

if detect "SMTP" "邮件" "email" "sendmail"; then
  generate_template "smtp" "# 邮件服务配置
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD="
fi

# ── 生成 .depend/.gitignore ───────────────────────────────
cat > "$DEPEND_DIR/.gitignore" << 'GITIGNORE_EOF'
# 凭证文件不进入版本控制
*.env
# 模板文件可以提交
!*.env.template
!README.md
!.gitignore
GITIGNORE_EOF

# ── 生成 README.md ────────────────────────────────────────
{
  echo "# .depend — 项目凭证配置"
  echo ""
  echo "> 此目录存储项目运行所需的外部凭证。**.env 文件已加入 .gitignore，不会进入版本控制。**"
  echo ""
  echo "## 使用方法"
  echo ""
  echo "将各 \`.env.template\` 文件复制并重命名为 \`.env\`，填入真实值："
  echo ""
  echo "\`\`\`bash"
  for tmpl in "$DEPEND_DIR"/*.env.template; do
    [ -f "$tmpl" ] || continue
    base=$(basename "$tmpl" .template)
    echo "cp $DEPEND_DIR/$base.template $DEPEND_DIR/$base"
  done
  echo "\`\`\`"
  echo ""
  echo "## 各文件说明"
  echo ""

  [ -f "$DEPEND_DIR/db.env.template" ] && echo "- **db.env**：数据库连接信息（主机、端口、用户名、密码、库名）"
  [ -f "$DEPEND_DIR/redis.env.template" ] && echo "- **redis.env**：Redis 连接信息"
  [ -f "$DEPEND_DIR/woodpecker.env.template" ] && echo "- **woodpecker.env**：Woodpecker CI 服务地址和访问 Token"
  [ -f "$DEPEND_DIR/server.env.template" ] && echo "- **server.env**：GPU 服务器 SSH 连接信息"
  [ -f "$DEPEND_DIR/storage.env.template" ] && echo "- **storage.env**：对象存储（MinIO/S3/OSS）连接信息"
  [ -f "$DEPEND_DIR/smtp.env.template" ] && echo "- **smtp.env**：邮件服务器配置"

  echo ""
  echo "## 填写完成后"
  echo ""
  echo "在 Claude Code 对话中回复 **继续**，流水线将恢复执行。"
} > "$DEPEND_DIR/README.md"

# ── 输出报告 ──────────────────────────────────────────────
DETECTED_JSON=$(printf '%s\n' "${DETECTED[@]+"${DETECTED[@]}"}" | python3 -c "
import sys, json
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items))
")

GENERATED_JSON=$(printf '%s\n' "${GENERATED[@]+"${GENERATED[@]}"}" | python3 -c "
import sys, json
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items))
")

SKIPPED_JSON=$(printf '%s\n' "${SKIPPED[@]+"${SKIPPED[@]}"}" | python3 -c "
import sys, json
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items))
")

cat > "$REPORT" << EOF
{
  "autostep": "depend-collector",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "detected_deps": $DETECTED_JSON,
  "templates_generated": $GENERATED_JSON,
  "skipped": $SKIPPED_JSON,
  "overall": "PASS"
}
EOF

echo "[depend-collector] 检测到依赖：${DETECTED[*]:-无}"
echo "[depend-collector] 生成模板：${GENERATED[*]:-无}"
echo "[depend-collector] 跳过（已存在）：${SKIPPED[*]:-无}"
echo "[depend-collector] 报告：$REPORT"
SCRIPT_EOF

chmod +x templates/.pipeline/autosteps/depend-collector.sh
```

**Step 2: 验证脚本语法**

```bash
bash -n templates/.pipeline/autosteps/depend-collector.sh
```
Expected: 无输出（语法正确）

**Step 3: 本地测试**

```bash
# 创建测试环境
mkdir -p /tmp/test-depend/.pipeline/artifacts
echo "## 技术栈
使用 PostgreSQL 数据库、Redis 缓存、MinIO 对象存储、Woodpecker CI，
部署在配备 V100 GPU 的服务器上。" > /tmp/test-depend/.pipeline/artifacts/proposal.md

cd /tmp/test-depend
PIPELINE_DIR=.pipeline bash /home/min/repos/team-creator/templates/.pipeline/autosteps/depend-collector.sh
```

Expected 输出：
```
[depend-collector] 检测到依赖：db redis woodpecker server storage
[depend-collector] 生成模板：.depend/db.env.template .depend/redis.env.template ...
```

**Step 4: 验证生成文件**

```bash
ls /tmp/test-depend/.depend/
cat /tmp/test-depend/.depend/README.md
cat /tmp/test-depend/.pipeline/artifacts/depend-collection-report.json
```
Expected: 5 个 .env.template 文件 + README.md + report JSON

**Step 5: 清理测试环境**

```bash
rm -rf /tmp/test-depend
cd /home/min/repos/team-creator
```

**Step 6: Commit**

```bash
git add templates/.pipeline/autosteps/depend-collector.sh
git commit -m "feat: add depend-collector autostep for credential template generation"
```

---

## Task 3: 修改 builder-infra.md — 新增 .woodpecker/ 生成职责

**Files:**
- Modify: `agents/builder-infra.md`

**Step 1: 在"工作内容"列表中新增第 6 条**

找到这一段：
```
5. **部署脚本**：`deploy-plan.md`（Deployer 在 Phase 6 使用）
```

在其后新增：
```
6. **Woodpecker CI 配置**：`.woodpecker/` 目录，包含三个 pipeline 文件（见下方规范）
```

**Step 2: 在 deploy-plan.md 格式章节后，新增 .woodpecker/ 规范章节**

在 `## deploy-plan.md 格式` 章节结束后，添加：

```markdown
## .woodpecker/ 目录规范

在项目根目录生成 `.woodpecker/` 目录，包含三个文件：

```
.woodpecker/
├── test.yml       ← tag v*.*.*-test.* 触发
├── staging.yml    ← tag v*.*.*-rc.* 触发
└── prod.yml       ← tag v*.*.* 触发（纯数字版本）
```

### Tag 触发规范

| 文件 | when.tag 值 | 示例 tag |
|------|------------|---------|
| test.yml | `v*.*.*-test.*` | `v1.0.0-test.1` |
| staging.yml | `v*.*.*-rc.*` | `v1.0.0-rc.1` |
| prod.yml | `v[0-9]*.[0-9]*.[0-9]*` | `v1.0.0` |

### 模板规范

根据 `proposal.md` 和 `depend-collection-report.json` 的技术栈动态生成 image、commands、secrets。

```yaml
# .woodpecker/test.yml 示例（Python/pytest 项目）
when:
  event: tag
  tag: v*.*.*-test.*

clone:
  default:
    image: woodpeckerci/plugin-git

steps:
  - name: test
    image: python:3.11-slim
    commands:
      - pip install -r requirements.txt
      - pytest --cov --cov-report=xml

# .woodpecker/staging.yml 示例
when:
  event: tag
  tag: v*.*.*-rc.*

steps:
  - name: build
    image: docker:dind
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    commands:
      - docker compose build

  - name: deploy-staging
    image: alpine/ssh
    secrets:
      - SSH_HOST
      - SSH_USER
      - SSH_KEY
    commands:
      - <staging 部署命令，根据 deploy-plan.md 生成>

# .woodpecker/prod.yml 示例
when:
  event: tag
  tag: v[0-9]*.[0-9]*.[0-9]*

steps:
  - name: build
    image: docker:dind
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    commands:
      - docker compose build

  - name: deploy-prod
    image: alpine/ssh
    secrets:
      - SSH_HOST
      - SSH_USER
      - SSH_KEY
    commands:
      - <生产部署命令，根据 deploy-plan.md 生成>
```

### secrets 字段规则

从 `$PIPELINE_DIR/artifacts/depend-collection-report.json` 的 `detected_deps` 推导：
- `server` → 包含 `SSH_HOST`、`SSH_USER`、`SSH_KEY`
- `db` → 包含 `DB_HOST`、`DB_USER`、`DB_PASSWORD`、`DB_NAME`
- `redis` → 包含 `REDIS_HOST`、`REDIS_PASSWORD`
- `storage` → 包含 `STORAGE_ENDPOINT`、`STORAGE_ACCESS_KEY`、`STORAGE_SECRET_KEY`

**注意**：secrets 字段列出所需 key 名称，实际值由运维人员在 Woodpecker 后台配置，pipeline 不处理真实凭证。
```

**Step 3: 在"输出"章节新增 .woodpecker/**

找到：
```
1. 代码实现（CI/CD 配置、Dockerfile 等）
2. `.pipeline/artifacts/deploy-plan.md`
3. `.pipeline/artifacts/impl-manifest-infra.json`（标准格式）
```

改为：
```
1. 代码实现（CI/CD 配置、Dockerfile 等）
2. `.woodpecker/test.yml`、`.woodpecker/staging.yml`、`.woodpecker/prod.yml`
3. `.pipeline/artifacts/deploy-plan.md`
4. `.pipeline/artifacts/impl-manifest-infra.json`（标准格式）
```

**Step 4: 验证修改**

```bash
grep -n "woodpecker\|\.woodpecker\|secrets" agents/builder-infra.md | head -20
```
Expected: 出现 woodpecker 相关行

**Step 5: Commit**

```bash
git add agents/builder-infra.md
git commit -m "feat(builder-infra): add .woodpecker/ tri-environment pipeline generation"
```

---

## Task 4: 修改 orchestrator.md — Phase 2.0a/b + 每阶段 push

**Files:**
- Modify: `agents/orchestrator.md`

这是最复杂的修改，分三个子步骤。

### 4a: 添加 github-ops 到 tools 列表 + state.json schema

**Step 1: 在 front matter tools 列表中添加 github-ops**

找到：
```
  Agent(clarifier, architect, auditor-biz, auditor-tech, auditor-qa, auditor-ops,
  resolver, planner, contract-formalizer, builder-frontend, builder-backend,
  builder-dba, builder-security, builder-infra, simplifier, inspector, tester,
  documenter, deployer, monitor, migrator, optimizer, translator),
```

改为：
```
  Agent(clarifier, architect, auditor-biz, auditor-tech, auditor-qa, auditor-ops,
  resolver, planner, contract-formalizer, builder-frontend, builder-backend,
  builder-dba, builder-security, builder-infra, simplifier, inspector, tester,
  documenter, deployer, monitor, migrator, optimizer, translator, github-ops),
```

**Step 2: 在 state.json schema 中新增字段**

找到 `"gate-e": 0` 这行，在其下的 `}` 之前新增：

```json
    "phase-2.0a": 0,
    "phase-2.0b": 0
```

（插入到 `attempt_counts` 对象中）

**Step 3: 在 state.json schema 中新增 `github_repo_created` 字段**

找到：
```json
  "phase_3_merge_order": []
```

在其后新增：
```json
  "github_repo_created": false,
  "github_repo_url": null
```

### 4b: 插入 Phase 2.0a/b 节点

**Step 4: 找到 Gate A PASS 行并修改**

找到：
```
- `PASS` → 解析 proposal.md 激活条件角色，进入 Phase 2
```

改为：
```
- `PASS` → 解析 proposal.md 激活条件角色，进入 Phase 2.0a
```

**Step 5: 在 `### Phase 2 — Planner` 之前插入新的两个 Phase**

在 `### Phase 2 — Planner（任务细化）` 标题行之前，插入：

```markdown
### Phase 2.0a — GitHub Repo Creator（github-ops Agent）
```
spawn: github-ops
scenario: create_repo
input: config.json + proposal.md
output: .pipeline/artifacts/github-repo-info.json
```
读取 `github-repo-info.json` 中 `overall`：
- `PASS` → 写入 state.json `github_repo_created: true`，`github_repo_url: <url>`，进入 Phase 2.0b
- `CANCELLED` → 写入 state.json `github_repo_created: false`，进入 Phase 2.0b（无 GitHub，后续 push 跳过）
- `FAIL` → ESCALATION

### Phase 2.0b — Depend Collector（AutoStep + 暂停）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/depend-collector.sh
output: .pipeline/artifacts/depend-collection-report.json
```
读取报告 `detected_deps` 字段：
- 非空 → **暂停**，向用户展示：
  ```
  ⚠️  检测到以下外部依赖，请填写凭证文件后继续：
  <逐行列出 .depend/*.env.template 文件路径>
  参考 .depend/README.md 了解填写说明。
  完成后回复"继续"。
  ```
  等待用户输入"继续"后进入 Phase 2。
- 空 → 直接进入 Phase 2（无需凭证）。

```

### 4c: 添加每阶段 git push 逻辑

**Step 6: 在 orchestrator.md 的"日志格式"章节之前，新增"Git Push 规范"章节**

在 `## 日志格式` 标题之前，插入：

```markdown
## Git Push 规范

每个 Phase/Gate 成功完成后，若 `state.json.github_repo_created = true`，执行：

```bash
git add -A
git commit -m "<COMMIT_MSG>" --allow-empty
git push origin main 2>/dev/null || echo "[WARN] git push 失败，继续流水线"
```

push 失败时仅记录 WARN，不中断流水线。

### Commit Message 规范

| 阶段 | COMMIT_MSG |
|------|-----------|
| Phase 0 Clarifier | `docs: add requirement specification` |
| Phase 1 Architect | `docs: add architecture proposal and ADRs` |
| Gate A | `ci: gate-a passed` |
| Phase 2.0a | `chore: initialize github repository` |
| Phase 2 Planner | `docs: add task breakdown (N tasks, M builders)`（N/M 从 tasks.json 读取） |
| Phase 2.5 Contract Formalizer | `docs: add OpenAPI contracts for N services`（N 从 contracts/ 目录文件数读取） |
| Gate B | `ci: gate-b passed` |
| Phase 3 各 Builder | `feat(builder-<name>): implement <service-name>`（service-name 从 impl-manifest 读取） |
| Phase 3.5 Simplifier | `refactor: simplify implementation per static analysis` |
| Gate C | `ci: gate-c passed` |
| Phase 4a Tester | `test: add test suite (N cases, X% coverage)`（从 test-report.json 读取） |
| Gate D | `ci: gate-d passed` |
| Phase 5 Documenter | `docs: add README, CHANGELOG and API documentation` |
| Gate E | `ci: gate-e passed` |
| Phase 6 Deployer | `chore: add deployment configuration and woodpecker pipelines` |

括号内的变量由 Orchestrator 在执行时从对应产物文件中读取真实值填入。

```

**Step 7: 在 Gate E 后，Phase 6.0 之前，插入 github-ops Woodpecker push 节点**

找到：
```
### Phase 6.0 — Pre-Deploy Readiness Check（AutoStep）
```

在其前插入：
```markdown
### Phase 5.9 — GitHub Woodpecker Push（github-ops Agent）

仅在 `state.json.github_repo_created = true` 时执行。
```
spawn: github-ops
scenario: push_woodpecker
input: .woodpecker/ 目录 + github-repo-info.json
```
FAIL → WARN（不阻断，记录日志后继续 Phase 6.0）

```

**Step 8: 验证修改完整性**

```bash
grep -n "Phase 2.0\|github-ops\|depend-collector\|git push\|COMMIT_MSG\|github_repo" agents/orchestrator.md
```
Expected: 出现所有新增关键词

**Step 9: Commit**

```bash
git add agents/orchestrator.md
git commit -m "feat(orchestrator): add Phase 2.0a/b, per-phase git push, woodpecker push"
```

---

## Task 5: 更新模板 .gitignore

**Files:**
- Modify: `templates/CLAUDE.md` 或在项目模板中新增 `.gitignore` 条目

**Step 1: 检查 CLAUDE.md 中是否有 .gitignore 说明**

```bash
grep -n "gitignore\|depend" templates/CLAUDE.md | head -10
```

**Step 2: 在流水线初始化说明中，添加 .depend 的注意事项**

在 `templates/CLAUDE.md` 中找到适当位置（如项目约定或注意事项章节），添加：

```markdown
## 凭证管理

项目根目录的 `.depend/` 目录存储外部服务凭证（数据库、Redis、GPU 服务器等）。
此目录已加入 `.gitignore`，**不得提交到版本控制**。

- `.depend/*.env.template`：模板文件（可提交）
- `.depend/*.env`：真实凭证（不提交）
- `.depend/README.md`：填写说明（可提交）
```

**Step 3: 确保项目模板 README 中提及 .depend**

检查是否需要更新 `install.sh` 以在初始化时生成 `.depend/.gitignore`。

```bash
grep -n "depend\|gitignore" install.sh | head -5
```

若 install.sh 不处理项目初始化（只安装 agents），则无需修改。

**Step 4: Commit**

```bash
git add templates/CLAUDE.md
git commit -m "docs: add .depend credential management documentation to template"
```

---

## Task 6: 安装并验证

**Step 1: 重新安装 agents**

```bash
bash install.sh
```
Expected: 显示 `✓ github-ops.md`，安装成功 25 个 Agent

**Step 2: 验证 github-ops 已安装**

```bash
ls ~/.claude/agents/github-ops.md
head -5 ~/.claude/agents/github-ops.md
```
Expected: 文件存在，front matter 正确

**Step 3: 验证 depend-collector.sh 已安装**

```bash
ls ~/.claude/agents/ | grep -v "\.md"
# autosteps 在 templates 中，不安装到 agents/
# 验证脚本在 templates 中
ls templates/.pipeline/autosteps/depend-collector.sh
```

**Step 4: 更新 MEMORY.md**

在 MEMORY.md 的"已完成工作"中记录本次变更。

**Step 5: 最终 Commit**

```bash
git add .
git commit -m "chore: finalize github-woodpecker integration (v6.1)"
```

---

## 验证清单

```bash
# 1. 25 个 Agent 文件存在
ls agents/ | wc -l  # Expected: 25

# 2. depend-collector.sh 语法正确
bash -n templates/.pipeline/autosteps/depend-collector.sh

# 3. orchestrator.md 包含所有新节点
grep -c "Phase 2.0\|github-ops\|depend-collector\|Git Push" agents/orchestrator.md

# 4. builder-infra.md 包含 woodpecker 规范
grep -c "woodpecker\|\.woodpecker" agents/builder-infra.md

# 5. install.sh 能成功运行
bash install.sh 2>&1 | grep -E "✓|✗|Error"
```
