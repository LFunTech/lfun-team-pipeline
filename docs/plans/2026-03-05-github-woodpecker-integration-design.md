# GitHub & Woodpecker CI 集成 — 设计文档

**日期**：2026-03-05
**状态**：已批准
**范围**：team-creator v6 流水线新增 GitHub 自动化、凭证管理、Woodpecker CI 集成

---

## 1. 变更概览

### 新增组件

| 组件 | 类型 | 说明 |
|------|------|------|
| `agents/github-ops.md` | 新 Agent（第 25 个） | GitHub repo 创建、Woodpecker 配置 push |
| `templates/.pipeline/autosteps/depend-collector.sh` | 新 AutoStep | 解析 proposal.md → 生成 .depend/ 凭证模板 |

### 修改组件

| 组件 | 变更说明 |
|------|---------|
| `agents/pilot.md` | 新增 Phase 2.0a/b，每阶段 git push + 规范化 commit message |
| `agents/builder-infra.md` | 新增 .woodpecker/ 目录生成职责 |

### 流水线新节点

```
Gate A PASS
  → Phase 2.0a  GitHub Repo Creator   [github-ops Agent，用户确认后执行]
  → Phase 2.0b  Depend Collector      [AutoStep + Pilot 暂停等用户填写]
  → Phase 2     Planner
    ↓（每个 Phase/Gate 完成后：规范化 commit + git push）

Phase 3 Builder-Infra
  → 生成 .woodpecker/ 目录（test/staging/prod 三条流水线）

Gate E PASS
  → github-ops Agent：push .woodpecker/ 到 GitHub
```

---

## 2. github-ops Agent

### 职责

两个场景，由 Pilot 在不同时机调用。

### 场景 1 — Phase 2.0a：创建 GitHub Repo

**前提**：`gh` CLI 已在当前机器完成认证（无需 .depend/github.env）

**输入**：
- `.pipeline/artifacts/proposal.md`
- `.pipeline/config.json`（读取 `project_name`）

**行为**：
1. 从 `config.json` 读取 `project_name`，从 `gh` 读取当前认证用户/org
2. 展示将要执行的操作：
   ```
   将创建 GitHub Repo：
     名称：<org>/<project_name>
     可见性：private
     描述：<从 proposal.md 提取一行摘要>
   请确认（输入"确认"继续）：
   ```
3. 用户确认后执行：
   ```bash
   gh repo create <org>/<project_name> --private --description "<摘要>"
   git remote add origin git@github.com:<org>/<project_name>.git
   git push -u origin main
   ```
4. 输出 `.pipeline/artifacts/github-repo-info.json`

**输出**：
```json
{
  "repo_url": "https://github.com/<org>/<project_name>",
  "clone_url": "git@github.com:<org>/<project_name>.git",
  "created_at": "ISO-8601",
  "overall": "PASS|FAIL"
}
```

### 场景 2 — Gate E 后：推送 Woodpecker 配置

**输入**：
- `.woodpecker/` 目录（builder-infra 已生成）
- `.pipeline/artifacts/github-repo-info.json`

**行为**：
1. 确认 `.woodpecker/test.yml`、`.woodpecker/staging.yml`、`.woodpecker/prod.yml` 均存在
2. 执行：
   ```bash
   git add .woodpecker/
   git commit -m "chore: add deployment configuration and woodpecker pipelines"
   git push origin main
   ```
3. 追加结果到 `deploy-report.json`

---

## 3. Depend Collector AutoStep

**脚本**：`depend-collector.sh`

**执行时机**：Phase 2.0b（Gate A PASS 后，Phase 2 Planner 前）

### 关键词检测规则

解析 `.pipeline/artifacts/proposal.md`，按以下规则生成 `.depend/*.env.template`：

| 检测关键词 | 生成文件 | 模板内容 |
|-----------|---------|---------|
| `PostgreSQL`/`MySQL`/`MongoDB` | `db.env.template` | `DB_HOST=`、`DB_PORT=`、`DB_USER=`、`DB_PASSWORD=`、`DB_NAME=` |
| `Redis` | `redis.env.template` | `REDIS_HOST=`、`REDIS_PORT=`、`REDIS_PASSWORD=` |
| `Woodpecker` | `woodpecker.env.template` | `WOODPECKER_URL=`、`WOODPECKER_TOKEN=` |
| `GPU`/`V100`/`A100`/`CUDA` | `server.env.template` | `SSH_HOST=`、`SSH_PORT=22`、`SSH_USER=`、`SSH_KEY_PATH=` |
| `MinIO`/`S3`/`OSS` | `storage.env.template` | `STORAGE_ENDPOINT=`、`STORAGE_ACCESS_KEY=`、`STORAGE_SECRET_KEY=` |
| `SMTP`/`邮件`/`email` | `smtp.env.template` | `SMTP_HOST=`、`SMTP_PORT=`、`SMTP_USER=`、`SMTP_PASSWORD=` |

### 生成 .depend/README.md

中文说明每个文件的用途、填写示例，并注明：
- `.depend/` 已加入 `.gitignore`，不进入代码仓库
- 填写完成后将 `*.env.template` 重命名为 `*.env`，或直接创建 `*.env` 文件

### 幂等性

- 对应 `.env` 文件已存在 → 跳过该模板生成，不覆盖
- 无任何关键词匹配 → 生成空的 `.depend/README.md`，提示无需额外凭证

### 输出报告

`.pipeline/artifacts/depend-collection-report.json`：
```json
{
  "detected_deps": ["db", "redis", "server"],
  "templates_generated": [".depend/db.env.template", ...],
  "skipped": [],
  "overall": "PASS"
}
```

### Pilot 暂停逻辑

AutoStep 完成后，Pilot 检查 `detected_deps` 非空时：
```
⚠️  检测到以下外部依赖，请填写凭证文件后继续：
  • .depend/db.env（数据库连接信息）
  • .depend/redis.env（Redis 连接信息）
  • .depend/server.env（GPU 服务器 SSH 信息）
参考 .depend/README.md 了解填写说明。
完成后回复"继续"。
```
等待用户输入 "继续" 后进入 Phase 2。

---

## 4. git push 策略

### 触发时机

Gate A PASS 并完成 Phase 2.0a（GitHub repo 创建）后，每个 Phase/Gate 完成时 Pilot 自动执行：

```bash
git add -A
git commit -m "<规范化 commit message>" --allow-empty
git push origin main
```

若 push 失败（网络问题等）→ 记录 WARN，不中断流水线。

### Commit Message 规范（Conventional Commits）

| 阶段 | Commit Message |
|------|---------------|
| Phase 0 Clarifier | `docs: add requirement specification` |
| Phase 1 Architect | `docs: add architecture proposal and ADRs` |
| Phase 2 Planner | `docs: add task breakdown (N tasks, M builders)` |
| Phase 2.5 Contract Formalizer | `docs: add OpenAPI contracts for N services` |
| Phase 3 各 Builder | `feat(builder-<name>): implement <service-name>` |
| Phase 3.5 Simplifier | `refactor: simplify implementation per static analysis` |
| Phase 4a Tester | `test: add test suite (N cases, X% coverage)` |
| Phase 5 Documenter | `docs: add README, CHANGELOG and API documentation` |
| Phase 6 Deployer | `chore: add deployment configuration and woodpecker pipelines` |
| Gate A~E | `ci: gate-<x> passed` |

括号中的变量（N、X%、service-name）由 Pilot 从对应产物文件中读取实际值填入。

---

## 5. .woodpecker/ 目录结构（builder-infra 职责）

### 目录结构

```
.woodpecker/
├── test.yml       ← tag v*.*.*-test.* 触发
├── staging.yml    ← tag v*.*.*-rc.* 触发
└── prod.yml       ← tag v*.*.* 触发（纯数字版本，排除 rc/test）
```

### Tag 触发规范

| 环境 | Tag 格式 | 示例 |
|------|---------|------|
| 测试 | `v*.*.*-test.*` | `v1.0.0-test.1` |
| 预发布 | `v*.*.*-rc.*` | `v1.0.0-rc.1` |
| 生产 | `v[0-9]*.[0-9]*.[0-9]*`（排除含 `-` 的） | `v1.0.0` |

### Pipeline 模板结构

```yaml
# test.yml
when:
  event: tag
  tag: v*.*.*-test.*

steps:
  - name: test
    image: <项目测试镜像>          # builder-infra 按技术栈填入
    commands:
      - <运行测试命令>              # 从 config.json testing 配置读取

# staging.yml
when:
  event: tag
  tag: v*.*.*-rc.*
steps:
  - name: build
    image: <构建镜像>
    commands: [<构建命令>]
  - name: deploy-staging
    image: <部署镜像>
    commands: [<staging 部署命令>]
    secrets: [<从 .depend/ 推导的 secret 名称列表>]

# prod.yml
when:
  event: tag
  tag: v[0-9]*.[0-9]*.[0-9]*
  # Woodpecker 不支持负向匹配，用 tag 格式自然区分
steps:
  - name: build
  - name: deploy-prod
    secrets: [<从 .depend/ 推导的 secret 名称列表>]
```

具体 image、commands、secrets 由 builder-infra 根据 `proposal.md` 技术栈和 `depend-collection-report.json` 动态生成，不硬编码。

---

## 6. 范围边界

**本期包含：**
- `github-ops` Agent（repo 创建 + woodpecker 配置 push）
- `depend-collector.sh` AutoStep
- Pilot 每阶段规范化 commit + push
- builder-infra 生成 `.woodpecker/` 三环境 pipeline
- Pilot Phase 2.0a/b 两个新节点

**本期不包含：**
- Woodpecker API 注册 secret（用户手动操作）
- 触发首次 CI 构建
- GitHub Actions 支持
- 多 branch 策略（仅 main）
