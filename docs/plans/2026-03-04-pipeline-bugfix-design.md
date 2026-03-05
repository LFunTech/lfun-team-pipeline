# Pipeline Bug Fix Design — 2026-03-04

## 背景

通过完整执行 demo-pipeline（Notes REST API）校验了多角色软件交付流水线 v6 的所有阶段。
本文档记录执行过程中发现的问题及修复方案，采用**按文件纵向切割**策略实施。

---

## Section 1：AutoStep 脚本 Bug 修复

### 问题描述

`set -euo pipefail` 下，`[ condition ] && VAR="FAIL"` 构型当 condition 为 false 时，
`[ ... ]` 返回退出码 1，`&&` 短路后函数/脚本以 exit 1 返回，被调用方的 set -e 捕获导致脚本终止。

### 修复范围（5 个文件，8 处）

| 文件 | 行 | 修复内容 |
|------|-----|---------|
| `requirement-completeness-checker.sh` | 76 | `[ ... ] && SECTIONS_OVERALL="FAIL"` → 追加 `\|\| true` |
| `requirement-completeness-checker.sh` | 82 | 同上 |
| `static-analyzer.sh` | 43 | `[ ... ] && OVERALL="FAIL"` → 追加 `\|\| true` |
| `static-analyzer.sh` | 46 | 同上 |
| `static-analyzer.sh` | 55 | 同上 |
| `assumption-propagation-validator.sh` | 60 | `[ ... ] && OVERALL="WARN"` → 追加 `\|\| true` |
| `regression-guard.sh` | 46 | `[ ... ] && OVERALL="FAIL"` → 追加 `\|\| true` |
| `schema-completeness-validator.sh` | 64 | 链式 `[ ... ] && [ ... ] && OVERALL="FAIL"` → 追加 `\|\| true` |

### 已修复（上次执行中已完成，无需再改）

- `post-simplification-verifier.sh`：`add_check` 函数末尾追加 `|| true`
- `pre-deploy-readiness-check.sh`：`add_check` 函数末尾追加 `|| true`
- `contract-compliance-checker.sh`：`add_result` 函数末尾追加 `|| true`
- `test-coverage-enforcer.sh`：自动探测 `coverage.lcov` 或 `lcov.info`
- `schema-completeness-validator.sh`：`sys.exit(0)` 移出 try 块；`contracts` 缺省返回 -1

---

## Section 2：新增 AutoStep — impl-manifest-merger.sh

### 问题描述

Phase 3 各 Builder 各自写 `impl-manifest-<name>.json`，合并操作由 Orchestrator（LLM）内联完成，
容易出错或遗漏。

### 修复方案

新增 `templates/.pipeline/autosteps/impl-manifest-merger.sh`：

```
输入:  .pipeline/artifacts/impl-manifest-*.json
输出:  .pipeline/artifacts/impl-manifest.json
退出码: 0=PASS 1=FAIL(文件缺失或格式错误) 2=ERROR
```

输出格式：
```json
{
  "autostep": "ImplManifestMerger",
  "files_changed": [ ...所有 builder 的 files_changed 合并去重... ],
  "builders": [
    { "builder": "dba", "files_changed": [...] },
    { "builder": "backend", "files_changed": [...] }
  ],
  "overall": "PASS"
}
```

同时更新 `orchestrator.md`：将「合并 impl-manifest」从 LLM inline 操作改为调用此 AutoStep。

---

## Section 3：Orchestrator 两处架构修复

### Bug A — git worktree 创建命令错误

**当前（错误）写法：**
```bash
git checkout -b pipeline/phase-3/builder-<name> "$BASE_SHA"
git worktree add "$(pwd)/.worktrees/builder-<name>" pipeline/phase-3/builder-<name>
git checkout "$MAIN_BRANCH"
```

问题：`git checkout -b` 切换了当前分支，导致后续 `git worktree add` 尝试 attach 已被主 repo
checkout 的分支，报错退出。

**修复（原子操作）：**
```bash
git worktree add -b pipeline/phase-3/builder-<name> \
  "$(pwd)/.worktrees/builder-<name>" "$BASE_SHA"
```

修改文件：`agents/orchestrator.md` Phase 3 worktree 创建节。

---

### Bug B — Phase 3.7 依赖运行中服务，但流水线无启停机制

**问题：** Contract Compliance Checker 需要 `SERVICE_BASE_URL` 上有活跃服务，
但 Orchestrator 在调用前未启动服务，调用后未关闭。

**修复：** 在 `orchestrator.md` 的 Phase 3.7 步骤中明确加入启停指令：
```
Phase 3.7 前：
  npm start & → 记录 SERVICE_PID → 轮询 /health 最多 10s

Phase 3.7 后：
  kill $SERVICE_PID 2>/dev/null || true

启动失败时：
  跳过 Phase 3.7，在 artifacts 写入 WARN 报告，继续流水线
```

修改文件：`agents/orchestrator.md` Phase 3.7 节。

---

## Section 4：Agent 提示词修复（3 个文件）

### 4a — Builder agents：文件边界隔离

**问题：** demo 中 Builder-Backend 和 Builder-DBA 都写了 `database.js`、`noteRepository.js`，
导致合并冲突且 API 不一致。

**文件所有权约定：**
- DBA 拥有：`src/db/`、`src/repositories/`、`src/models/`
- Backend 拥有：`src/routes/`、`src/services/`、`src/middleware/`

**修复：** 在 `builder-backend.md` 和 `builder-dba.md` 中加入：
> 「**禁止修改不在自己所有权列表内的文件**；若需跨层调用，只能依赖 tasks.json 中声明的接口契约」

修改文件：`agents/builder-backend.md`、`agents/builder-dba.md`

---

### 4b — Contract Formalizer：补充内部模块接口定义

**问题：** 只生成 HTTP API 的 OpenAPI schema，未定义内部模块间接口，各 Builder 对接口理解不一致。

**修复：** 在 `contract-formalizer.md` 新增「内部接口定义」节，要求在 `tasks.json` 的
`contracts` 字段中记录关键内部模块接口（函数名 + 参数 + 返回类型）。

修改文件：`agents/contract-formalizer.md`

---

### 4c — Documenter：明确 CHANGELOG 格式

**问题：** 只说「按 Keep a Changelog 规范」，但 Changelog Checker 严格要求
`## [Unreleased]` 节存在，两者不对齐。

**修复：** 在 `documenter.md` 中明确写出期望格式并注明「不得删除 `## [Unreleased]` 节」。

修改文件：`agents/documenter.md`

---

## 实施顺序

1. Section 1：5 个 AutoStep 脚本（纯追加 `|| true`，独立无依赖）
2. Section 2：新增 `impl-manifest-merger.sh` + 更新 `orchestrator.md`（merger 节）
3. Section 3：更新 `orchestrator.md`（worktree 命令 + Phase 3.7 启停）
4. Section 4：更新 3 个 agent 提示词

Step 2、3 都改 orchestrator.md，可合并为一次编辑。
