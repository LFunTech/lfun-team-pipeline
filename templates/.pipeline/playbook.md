# Pipeline Playbook — 阶段执行手册

> 本文件由 Orchestrator 按需加载。进入某阶段时，只需读取对应章节，无需加载全文。
> 每个章节包含：spawn 规则、输入输出、验证条件、日志写入指令、失败处理。

---

## System Planning — 系统规划

> 仅在 `.pipeline/proposal-queue.json` 不存在时执行。详细规则见 orchestrator.md 中"System Planning"节。

本章节由 Orchestrator 内联执行（不 spawn 独立 Agent），交互式与用户对话：

1. 请用户描述完整系统
2. 最多 3 轮澄清（系统边界、核心域、技术偏好）
3. 生成系统蓝图 `.pipeline/artifacts/system-blueprint.md`
4. 拆解为提案队列 `.pipeline/proposal-queue.json`
5. 将共享约定写入 `project-memory.json` 的 constraints
6. 用户确认后进入 `pick-next-proposal`

---

## Pick Next Proposal — 提案选取

> 详细规则见 orchestrator.md 中"Pick Next Proposal"节。

1. 读取 proposal-queue.json，找第一个 pending 提案
2. 检查依赖是否全部 completed
3. 标记为 running，初始化新 state.json
4. 将提案 title + scope 作为输入传给 Phase 0

---

## Mark Proposal Completed — 提案完成标记

> 详细规则见 orchestrator.md 中"Mark Proposal Completed"节。

1. 将当前 running 提案标记为 completed
2. 输出完成日志
3. 进入 pick-next-proposal

---

## Phase 0 — Clarifier（需求澄清）
```
spawn: clarifier
input: 用户原始需求文本
output: .pipeline/artifacts/requirement.md
```
Clarifier 最多 5 轮澄清（每轮暂停展示问题给用户，等待用户回答后传回）。
完成后检查 requirement.md 存在且非空。

写日志：调用 `write_step_log`，step=`"phase-0"`，step_type=`"agent"`，agent=`"clarifier"`，从 `requirement.md` 提取"验收标准"前 3 条作为 `key_decisions`。

---

## Phase 0.5 — Requirement Completeness Checker（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/requirement-completeness-checker.sh
output: .pipeline/artifacts/requirement-completeness-report.json
```
读取报告 `overall` 字段：
- `PASS` → 进入 Phase 1
- `FAIL` → 递增 phase-0 attempt，rollback_to: phase-0（提示 Clarifier 补充缺失内容）
  标注因果：调用 `mark_rollback_causality(cause_step="phase-0.5", target_step="phase-0")`。

写日志：调用 `write_step_log`，step=`"phase-0.5"`，step_type=`"autostep"`，agent=`""`，从 `requirement-completeness-report.json` 读取 `overall` 及 `issues` 前 3 条作为 `key_decisions`。

---

## Phase 1 — Architect（方案设计）

注入上下文：调用 `build_context_injection(current_step="phase-1", include_steps=["phase-0"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: architect
input: requirement.md
output: .pipeline/artifacts/proposal.md, .pipeline/artifacts/adr-draft.md
```
验证 proposal.md 和 adr-draft.md 均存在且非空。

写日志：调用 `write_step_log`，step=`"phase-1"`，step_type=`"agent"`，agent=`"architect"`，从 `proposal.md` 技术栈段落提取前 2 行作为 `key_decisions`。

---

## Gate A — Auditor 校验（方案审核）

注入上下文：调用 `build_context_injection(current_step="gate-a", include_steps=["phase-0", "phase-1"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: auditor-biz, auditor-tech, auditor-qa, auditor-ops（并行）
input: requirement.md + proposal.md
output: .pipeline/artifacts/gate-a-review.json
```
矛盾检测 → 读取 overall：
- `PASS` → 解析 proposal.md 激活条件角色（读取 `data_migration_required`、`performance_sensitive`、`i18n_required` 字段，写入 `state.json.conditional_agents.{migrator,optimizer,translator}`），进入 Phase 2.0a
- `FAIL` → rollback_to（取最深目标）
  标注因果：调用 `mark_rollback_causality(cause_step="gate-a", target_step=<gate-a-review.json中rollback_to字段的值>)`。

写日志：调用 `write_step_log`，step=`"gate-a"`，step_type=`"gate"`，agent=`"auditor"`，从 `gate-a-review.json` 提取 `overall`、`rollback_to` 及所有 `severity=CRITICAL` 的 `issues[].message` 作为 `key_decisions`。

---

## Phase 2.0a — GitHub Repo Creator（github-ops Agent）

注入上下文：调用 `build_context_injection(current_step="phase-2.0a", include_steps=["phase-0", "phase-1", "gate-a"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: github-ops
scenario: create_repo
input: config.json + proposal.md
output: .pipeline/artifacts/github-repo-info.json
```
读取 `github-repo-info.json` 中 `overall`：
- `PASS` → 写入 state.json `github_repo_created: true`、`github_repo_url: <url>`，进入 Phase 2.0b
- `CANCELLED` → 写入 state.json `github_repo_created: false`，进入 Phase 2.0b（后续 push 跳过）
- `FAIL` → ESCALATION

写日志：调用 `write_step_log`，step=`"phase-2.0a"`，step_type=`"agent"`，agent=`"github-ops"`，从 `github-repo-info.json` 读取 `overall` 字段作为 `key_decisions`。

---

## Phase 2.0b — Depend Collector（AutoStep + 暂停）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/depend-collector.sh
output: .pipeline/artifacts/depend-collection-report.json
```
读取报告 `unfilled_deps` 字段（检测到但 .env 未填写的依赖）：
- 非空 → **暂停**，向用户展示：
  ```
  ⚠️  检测到以下外部依赖，请填写凭证文件后继续：
  <逐行列出 unfilled_deps 中每项对应的 .depend/<name>.env.template 路径>
  参考 .depend/README.md 了解填写说明。
  完成后回复"继续"。
  ```
  等待用户输入"继续"后进入 Phase 2。
- 空（所有依赖凭证已填写或无外部依赖）→ 直接进入 Phase 2。

写日志：调用 `write_step_log`，step=`"phase-2.0b"`，step_type=`"autostep"`，agent=`""`，从 `depend-collection-report.json` 读取 `unfilled_deps` 列表作为 `key_decisions`。

---

## Phase 2 — Planner（任务细化）

注入上下文：调用 `build_context_injection(current_step="phase-2", include_steps=["phase-0", "phase-1", "gate-a", "phase-2.0a", "phase-2.0b"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: planner
input: proposal.md + requirement.md
output: .pipeline/artifacts/tasks.json
```

写日志：调用 `write_step_log`，step=`"phase-2"`，step_type=`"agent"`，agent=`"planner"`，从 `tasks.json` 读取任务总数和 Builder 数量作为 `key_decisions`（格式："共 N 个任务，M 个 Builder"）。

---

## Phase 2.1 — Assumption Propagation Validator（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/assumption-propagation-validator.sh
output: .pipeline/artifacts/assumption-propagation-report.json
```
结果附加给 Gate B Auditor-Biz（WARN 不阻断，仅信息传递）。

写日志：调用 `write_step_log`，step=`"phase-2.1"`，step_type=`"autostep"`，agent=`""`，从 `assumption-propagation-report.json` 读取 `overall` 及 `issues` 前 3 条作为 `key_decisions`。

---

## Gate B — Auditor 校验（任务细化审核）

注入上下文：调用 `build_context_injection(current_step="gate-b", include_steps=["phase-0", "phase-1", "gate-a", "phase-2.0a", "phase-2.0b", "phase-2", "phase-2.1"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: auditor-biz, auditor-tech, auditor-qa, auditor-ops（并行）
input: proposal.md + tasks.json + assumption-propagation-report.json
output: .pipeline/artifacts/gate-b-review.json
```

写日志：调用 `write_step_log`，step=`"gate-b"`，step_type=`"gate"`，agent=`"auditor"`，从 `gate-b-review.json` 提取 `overall`、`rollback_to` 及所有 `severity=CRITICAL` 的 `issues[].message` 作为 `key_decisions`。

---

## Phase 2.5 — Contract Formalizer（契约形式化）

注入上下文：调用 `build_context_injection(current_step="phase-2.5", include_steps=["phase-0", "phase-1", "gate-a", "phase-2.0a", "phase-2.0b", "phase-2", "phase-2.1", "gate-b"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: contract-formalizer
input: tasks.json
output: .pipeline/artifacts/contracts/ 目录
```

写日志：调用 `write_step_log`，step=`"phase-2.5"`，step_type=`"agent"`，agent=`"contract-formalizer"`，统计 `contracts/` 目录下文件数量作为 `key_decisions`（格式："生成 N 个契约文件"）。

---

## Phase 2.6 — Schema Completeness Validator（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/schema-completeness-validator.sh
output: .pipeline/artifacts/schema-validation-report.json
```
FAIL → rollback_to: phase-2.5
标注因果：调用 `mark_rollback_causality(cause_step="phase-2.6", target_step="phase-2.5")`。

写日志：调用 `write_step_log`，step=`"phase-2.6"`，step_type=`"autostep"`，agent=`""`，从 `schema-validation-report.json` 读取 `overall` 及 `issues` 前 3 条作为 `key_decisions`。

---

## Phase 2.7 — Contract Semantic Validator（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/contract-semantic-validator.sh
output: .pipeline/artifacts/contract-semantic-report.json
```
FAIL → rollback_to: phase-2.5
标注因果：调用 `mark_rollback_causality(cause_step="phase-2.7", target_step="phase-2.5")`。

写日志：调用 `write_step_log`，step=`"phase-2.7"`，step_type=`"autostep"`，agent=`""`，从 `contract-semantic-report.json` 读取 `overall` 及 `issues` 前 3 条作为 `key_decisions`。

---

## Phase 3 — 并行实现（Worktree 隔离）

### Phase 3.0 — Worktree 初始化

检查 `state.json.phase_3_base_sha` 是否为 null：
- 非 null 且 `phase_3_worktrees` 非空 → 残余 worktree 清理（见"回滚清理"节）后重建
- 执行初始化：

1. 记录基准信息：
   ```bash
   MAIN_BRANCH=$(git rev-parse --abbrev-ref HEAD)
   BASE_SHA=$(git rev-parse HEAD)
   ```
   写入 state.json: `phase_3_main_branch`, `phase_3_base_sha`

2. 确定激活 Builder + 合并顺序（写入 `phase_3_merge_order`）：
   ```
   [dba, migrator*, backend, security, frontend, translator*, infra]
   ```
   （带 * 的条件角色仅在 conditional_agents 为 true 时插入）

3. 为每个激活 Builder 创建分支和 worktree：
   ```bash
   git worktree add -b pipeline/phase-3/builder-<name> \
     "$(pwd)/.worktrees/builder-<name>" "$BASE_SHA"
   ```
   写入 state.json: `phase_3_worktrees["<name>"]` = 绝对路径, `phase_3_branches["<name>"]` = 分支名

4. `git worktree list` 确认所有 worktree 创建成功。

### Phase 3 — Builder 调度（按依赖波次顺序执行）

> **注意**：Agent tool 按顺序调用，各 Builder 实际为顺序执行（非真正并行）。波次划分体现依赖顺序，同波次内也按列出顺序顺序调用。

按以下波次 spawn，每波完成后才启动下一波：
- 波次 1（顺序）：DBA、Migrator（条件）
- 波次 2（顺序）：Backend
- 波次 3（顺序）：Security、Frontend
- 波次 4（顺序）：Infra（等 Security）、Translator（条件，等 Frontend）

注入上下文：调用 `build_context_injection(current_step="phase-3-builder-<name>", include_steps=["phase-0", "phase-1", "gate-a", "phase-2", "phase-2.5", "gate-b"])`（将 `<name>` 替换为实际 Builder 名），将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。

**spawn 消息格式**：
```
spawn: builder-<name>
cwd: <phase_3_worktrees["name"]>（绝对路径）
PIPELINE_DIR: <主repo绝对路径>/.pipeline
BUILDER_NAME: <name>
```
Translator 额外传入：`FRONTEND_WORKTREE: <phase_3_worktrees["frontend"]>`

**完成验证**（每个 Builder 完成后机械检查）：
1. `$PIPELINE_DIR/artifacts/impl-manifest-<name>.json` 存在且非空
2. `git log pipeline/phase-3/builder-<name> --oneline -1` 有 Phase 3 的 commit

每个 Builder 输出 `$PIPELINE_DIR/artifacts/impl-manifest-<builder>.json`。
全部完成后进入合并步骤。

写日志：每个 Builder 完成验证后，调用 `write_step_log`，step=`"phase-3-builder-<name>"`（将 `<name>` 替换为实际 Builder 名），step_type=`"agent"`，agent=`"builder-<name>"`，从 `impl-manifest-<name>.json` 读取 `summary` 字段（若有）或统计 `files_changed` 数量作为 `key_decisions`。

### Phase 3 — 合并序列

按 `phase_3_merge_order` 顺序执行：

```bash
git checkout "$MAIN_BRANCH"
for BUILDER in merge_order:
  BRANCH="pipeline/phase-3/builder-$BUILDER"
  # 干跑检测
  if ! git merge --no-commit --no-ff "$BRANCH" 2>/dev/null; then
    git merge --abort 2>/dev/null || true
    → ESCALATION：合并冲突，保留 .worktrees/builder-$BUILDER 供人工解决
    → 输出人工恢复指令（见 CLAUDE.md），status: escalation，停止
  fi
  git merge --abort 2>/dev/null || true
  git merge --no-ff "$BRANCH" -m "merge: Phase 3 builder-$BUILDER"
```

**合并成功后清理**：
```bash
for BUILDER in phase_3_worktrees:
  git worktree remove ".worktrees/builder-$BUILDER" --force
  git branch -d "pipeline/phase-3/builder-$BUILDER"
  # 删除 state.json 对应 key
rmdir .worktrees 2>/dev/null || true
```

**清理验证（强制）**：
```bash
# 验证所有 Builder worktree 已清理
REMAINING=$(git worktree list | grep -c "pipeline/phase-3/" || echo 0)
if [ "$REMAINING" -gt 0 ]; then
  echo "[ERROR] Worktree 清理不完整，仍有 $REMAINING 个残余："
  git worktree list | grep "pipeline/phase-3/"
  echo "请手动执行：git worktree remove .worktrees/builder-<name> --force"
  → ESCALATION：Worktree 清理失败，需人工介入后重启
  → 写入索引最终状态 status: escalation，停止流水线
fi
echo "✅ 所有 Builder worktree 已清理"
```

**合并 impl-manifest**（AutoStep）：
```
PIPELINE_DIR=.pipeline bash .pipeline/autosteps/impl-manifest-merger.sh
```
若 exit ≠ 0：ESCALATION，停止流水线

---

## Phase 3.0b — Build Verifier（AutoStep）

在所有 Builder 代码合并完成后、进入静态分析之前，强制执行两阶段编译验证。这是防止 Gate C 独立性失效的关键屏障。

**两阶段验证：**
1. **生产编译**：`cargo build --release` / `go build ./...` / `npm run build`
2. **测试编译**（生产编译 PASS 后才运行）：`cargo test --no-run` / `go test -run='^$' ./...` / `npx tsc --noEmit`

测试编译失败同样视为 Builder 责任，回滚至 phase-3。

```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/build-verifier.sh
output: .pipeline/artifacts/build-verifier-report.json
```
读取报告 `overall` 字段：
- `PASS` → 继续进入 Phase 3.1
- `FAIL` → rollback_to: phase-3（按原 Builder 任务重新实现，**Orchestrator 不得自行修复 Builder 代码**）
  标注因果：调用 `mark_rollback_causality(cause_step="phase-3.0b", target_step="phase-3")`。

⚠️ **重要约束**：Build Verifier FAIL 时，Orchestrator **必须** rollback 委托给对应 Builder 重新实现，**禁止** Orchestrator 直接修改源代码绕过编译错误。

写日志：调用 `write_step_log`，step=`"phase-3.0b"`，step_type=`"autostep"`，agent=`""`，从 `build-verifier-report.json` 读取 `overall`、`tool`、`test_compile`、`errors`+`test_compile_errors` 前 3 条作为 `key_decisions`。

### 回滚清理（rollback_to: phase-3 时）

重进 Phase 3.0 前执行：
```bash
for BUILDER in phase_3_worktrees（若非空）:
  git worktree remove ".worktrees/builder-$BUILDER" --force 2>/dev/null || true
  git branch -D "pipeline/phase-3/builder-$BUILDER" 2>/dev/null || true
rm -rf .worktrees 2>/dev/null || true
# 重置 state.json
phase_3_worktrees = {}; phase_3_branches = {}
phase_3_base_sha = null; phase_3_main_branch = null
```

---

## Phase 3.1 — Static Analyzer（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/static-analyzer.sh
```
FAIL → rollback_to: phase-3
标注因果：调用 `mark_rollback_causality(cause_step="phase-3.1", target_step="phase-3")`。

写日志：调用 `write_step_log`，step=`"phase-3.1"`，step_type=`"autostep"`，agent=`""`，从 `static-analysis-report.json` 读取 `overall` 及 `issues` 前 3 条作为 `key_decisions`。

---

## Phase 3.2 — Diff Scope Validator（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/diff-scope-validator.sh
```

写日志：调用 `write_step_log`，step=`"phase-3.2"`，step_type=`"autostep"`，agent=`""`，从 `diff-scope-report.json`（若存在）读取 `overall` 及 `issues` 前 3 条作为 `key_decisions`。

---

## Phase 3.3 — Regression Guard（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/regression-guard.sh
```
（new_test_files 排除在外，不纳入回归套件）

写日志：调用 `write_step_log`，step=`"phase-3.3"`，step_type=`"autostep"`，agent=`""`，从 `regression-guard-report.json`（若存在）读取 `overall` 作为 `key_decisions`。

---

## Phase 3.5 — Simplifier

注入上下文：调用 `build_context_injection(current_step="phase-3.5", include_steps=["phase-0", "phase-1", "gate-a", "phase-2", "gate-b", "phase-3-builder-dba", "phase-3-builder-backend", "phase-3-builder-frontend", "phase-3-builder-security", "phase-3-builder-infra", "phase-3.1"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: simplifier
input: static-analysis-report.json + 代码
output: .pipeline/artifacts/simplify-report.md
```
验证 simplify-report.md 修改时间 > impl-manifest.json 修改时间。

写日志：调用 `write_step_log`，step=`"phase-3.5"`，step_type=`"agent"`，agent=`"simplifier"`，从 `simplify-report.md` 提取前 3 行作为 `key_decisions`。

---

## Phase 3.6 — Post-Simplification Verifier（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/post-simplification-verifier.sh
```
FAIL → rollback_to: phase-3.5
标注因果：调用 `mark_rollback_causality(cause_step="phase-3.6", target_step="phase-3.5")`。

写日志：调用 `write_step_log`，step=`"phase-3.6"`，step_type=`"autostep"`，agent=`""`，从 `post-simplification-report.json`（若存在）读取 `overall` 作为 `key_decisions`。

---

## Gate C — Inspector（代码审查）

注入上下文：调用 `build_context_injection(current_step="gate-c", include_steps=["phase-0", "phase-1", "gate-a", "phase-2", "gate-b", "phase-3-builder-dba", "phase-3-builder-backend", "phase-3-builder-frontend", "phase-3-builder-security", "phase-3-builder-infra", "phase-3.1", "phase-3.5", "phase-3.6"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: inspector
input: 代码 + 所有 Phase 3 报告
output: .pipeline/artifacts/gate-c-review.json
```
Inspector 调用前，Orchestrator 在产物中机械设置 `simplifier_verified: true/false`。
FAIL → rollback_to: phase-3（重新经过 3.0b→3.1→3.2→3.3→3.5→3.6→Gate C）
1. 激活 Resolver 修复 Inspector 报告的 CRITICAL/MAJOR 问题（Resolver 直接在主分支上提交修复）。
2. Resolver 完成后，**必须更新 `phase_3_base_sha`**（Bug #15 修复）：
   ```bash
   NEW_SHA=$(git rev-parse HEAD)
   python3 -c "
   import json
   s = json.load(open('.pipeline/state.json'))
   s['phase_3_base_sha'] = '$NEW_SHA'
   json.dump(s, open('.pipeline/state.json', 'w'), indent=2)
   "
   ```
   此更新确保后续 Phase 3.2 Diff Scope Validator 以 Resolver 修复后的 HEAD 为基准，避免将 Resolver 合法修复误报为未授权变更。
3. 重新运行 Phase 3.0b → 3.1 → 3.2 → 3.3 → 3.5 → 3.6 → Gate C。
标注因果：调用 `mark_rollback_causality(cause_step="gate-c", target_step="phase-3")`。

写日志：调用 `write_step_log`，step=`"gate-c"`，step_type=`"gate"`，agent=`"inspector"`，从 `gate-c-review.json` 提取 `overall`、`rollback_to` 及所有 `severity=CRITICAL` 的 `issues[].message` 作为 `key_decisions`。

---

## Phase 3.7 — Contract Compliance Checker（AutoStep）

从 config.json 读取服务启动配置（Python 解析）：
```
SERVICE_START_CMD=$(python3 -c "
import json
c=json.load(open('.pipeline/config.json'))
print(c.get('autosteps',{}).get('contract_compliance',{}).get('service_start_cmd','npm start'))
" 2>/dev/null || echo "npm start")

SERVICE_BASE_URL=$(python3 -c "
import json
c=json.load(open('.pipeline/config.json'))
print(c.get('autosteps',{}).get('contract_compliance',{}).get('service_base_url','http://localhost:3000'))
" 2>/dev/null || echo "http://localhost:3000")

HEALTH_PATH=$(python3 -c "
import json
c=json.load(open('.pipeline/config.json'))
print(c.get('autosteps',{}).get('contract_compliance',{}).get('health_path','/health'))
" 2>/dev/null || echo "/health")
```

启动服务（后台）：
  eval "$SERVICE_START_CMD" &
  SERVICE_PID=$!
  等待就绪（最多 30s）：轮询 curl -sf ${SERVICE_BASE_URL}${HEALTH_PATH}，间隔 2s
  若 30s 内未就绪：写入 WARN 报告跳过，kill $SERVICE_PID 2>/dev/null || true，继续

运行 AutoStep：
```
SERVICE_BASE_URL="$SERVICE_BASE_URL" \
PIPELINE_DIR=.pipeline \
bash .pipeline/autosteps/contract-compliance-checker.sh
```

停止服务：
  kill $SERVICE_PID 2>/dev/null || true

FAIL → rollback_to: phase-3（对应 Builder）
标注因果：调用 `mark_rollback_causality(cause_step="phase-3.7", target_step="phase-3")`。

写日志：调用 `write_step_log`，step=`"phase-3.7"`，step_type=`"autostep"`，agent=`""`，从 `contract-compliance-report.json`（若存在）读取 `overall` 及 `issues` 前 3 条作为 `key_decisions`。

**config.json 示例（Rust 项目）：**
```json
"autosteps": {
  "contract_compliance": {
    "service_start_cmd": "cargo run --bin api-service",
    "service_base_url": "http://localhost:8080",
    "health_path": "/v1/health"
  }
}
```

---

## Phase 4a — Tester（功能测试）

注入上下文：调用 `build_context_injection(current_step="phase-4a", include_steps=["gate-c"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: tester
input: tasks.json + impl-manifest.json
output: .pipeline/artifacts/test-report.json, .pipeline/artifacts/coverage.lcov
```
FAIL → 运行 Phase 4a.1（Test Failure Mapper）

**new_test_files 写入**：Tester 完成后，Orchestrator 从 `test-report.json` 或 Tester 的 `state.json.new_test_files` 更新中读取新增测试文件路径列表。此列表的生命周期为：
- Phase 3.3 Regression Guard：排除 `new_test_files` 中的文件（避免对未毕业的新测试做回归）
- Phase 4a Tester：**写入** `state.json.new_test_files`（当前运行新增的测试文件）
- Phase 7 Monitor NORMAL：**毕业**，将 `new_test_files` 条目迁移到 `regression-suite-manifest.json`，然后清空 `new_test_files`

写日志：调用 `write_step_log`，step=`"phase-4a"`，step_type=`"agent"`，agent=`"tester"`，从 `test-report.json` 读取 `total`、`passed`、`coverage` 三个字段作为 `key_decisions`（格式："共 N 用例，通过 M，覆盖率 X%"）。

---

## Phase 4a.1 — Test Failure Mapper（AutoStep，仅 Phase 4a FAIL 时）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/test-failure-mapper.sh
output: .pipeline/artifacts/failure-builder-map.json
```
读取 `confidence` 字段：
- `HIGH` → 精确回退（仅 builders_to_rollback 中的 builder）
- `LOW` → 保守全体回退 phase-3
标注因果：调用 `mark_rollback_causality(cause_step="phase-4a", target_step=<failure-builder-map.json中rollback目标>)`。

写日志：调用 `write_step_log`，step=`"phase-4a.1"`，step_type=`"autostep"`，agent=`""`，从 `failure-builder-map.json` 读取 `confidence` 及 `builders_to_rollback` 作为 `key_decisions`。

---

## Phase 4.2 — Test Coverage Enforcer（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/test-coverage-enforcer.sh
```
FAIL → rollback_to: phase-4a
标注因果：调用 `mark_rollback_causality(cause_step="phase-4.2", target_step="phase-4a")`。

PASS 后条件跳转：读取 `state.json.conditional_agents.optimizer`，若为 `true` → 进入 Phase 4b；若为 `false` → 跳过 Phase 4b，直接进入 Gate D。

写日志：调用 `write_step_log`，step=`"phase-4.2"`，step_type=`"autostep"`，agent=`""`，从 `coverage-report.json`（若存在）读取 `overall` 及覆盖率阈值对比结果作为 `key_decisions`。

---

## Phase 4b — Optimizer（条件角色，仅 performance_sensitive: true）

注入上下文：调用 `build_context_injection(current_step="phase-4b", include_steps=["gate-c", "phase-4a"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: optimizer
input: test-report.json + impl-manifest.json
output: .pipeline/artifacts/perf-report.json
```
`perf-report.json` 中 `sla_violated: true` → 直接 rollback_to: phase-3（不等 Gate D）。
标注因果：调用 `mark_rollback_causality(cause_step="phase-4b", target_step="phase-3")`。

写日志：调用 `write_step_log`，step=`"phase-4b"`，step_type=`"agent"`，agent=`"optimizer"`，从 `perf-report.json` 读取 `sla_violated` 及 `p95_latency` 作为 `key_decisions`。

---

## Gate D — Auditor-QA（测试验收）

注入上下文：调用 `build_context_injection(current_step="gate-d", include_steps=["phase-4a", "phase-4.2"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: auditor-qa
input: test-report.json + coverage-report.json + perf-report.json（如有）
output: .pipeline/artifacts/gate-d-review.json（含结构化 rollback_to 字段）
```
FAIL → rollback_to（限制：不超过 phase-2，只能 phase-4a 或 phase-3）
标注因果：调用 `mark_rollback_causality(cause_step="gate-d", target_step=<gate-d-review.json中rollback_to字段的值>)`。

写日志：调用 `write_step_log`，step=`"gate-d"`，step_type=`"gate"`，agent=`"auditor-qa"`，从 `gate-d-review.json` 提取 `overall`、`rollback_to` 及所有 `severity=CRITICAL` 的 `issues[].message` 作为 `key_decisions`。

---

## API Change Detector — api-change-detector（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/api-change-detector.sh
output: .pipeline/artifacts/api-change-report.json
```
写入 state.json: `phase_5_mode`（`full` 或 `changelog_only`）

写日志：调用 `write_step_log`，step=`"api-change-detector"`，step_type=`"autostep"`，agent=`""`，从 `api-change-report.json` 读取 `overall` 及 `phase_5_mode` 作为 `key_decisions`。

---

## Phase 5 — Documenter（文档）

注入上下文：调用 `build_context_injection(current_step="phase-5", include_steps=["gate-c", "gate-d", "phase-4a"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: documenter
input: api-change-report.json + adr-draft.md + impl-manifest.json
output: .pipeline/artifacts/doc-manifest.json
```
如 `phase_5_mode: changelog_only`，仅更新 CHANGELOG，跳过 API 文档更新。

写日志：调用 `write_step_log`，step=`"phase-5"`，step_type=`"agent"`，agent=`"documenter"`，从 `doc-manifest.json` 读取 `docs_updated` 列表前 3 项作为 `key_decisions`。

---

## Phase 5.1 — Changelog Consistency Checker（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/changelog-consistency-checker.sh
```
FAIL → rollback_to: phase-5
标注因果：调用 `mark_rollback_causality(cause_step="phase-5.1", target_step="phase-5")`。

写日志：调用 `write_step_log`，step=`"phase-5.1"`，step_type=`"autostep"`，agent=`""`，从 `changelog-consistency-report.json`（若存在）读取 `overall` 作为 `key_decisions`。

---

## Gate E — Auditor-QA + Auditor-Tech（文档审核）

注入上下文：调用 `build_context_injection(current_step="gate-e", include_steps=["phase-5"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: auditor-qa, auditor-tech（并行）
input: doc-manifest.json + API 文档 + CHANGELOG + ADR
output: .pipeline/artifacts/gate-e-review.json
```
FAIL → rollback_to: phase-5
标注因果：调用 `mark_rollback_causality(cause_step="gate-e", target_step="phase-5")`。

写日志：调用 `write_step_log`，step=`"gate-e"`，step_type=`"gate"`，agent=`"auditor-qa+tech"`，从 `gate-e-review.json` 提取 `overall`、`rollback_to` 及所有 `severity=CRITICAL` 的 `issues[].message` 作为 `key_decisions`。

---

## Phase 5.9 — GitHub Woodpecker Push（github-ops Agent）

仅在 `state.json.github_repo_created = true` 时执行；否则跳过，直接进入 Phase 6.0。

注入上下文：调用 `build_context_injection(current_step="phase-5.9", include_steps=["gate-e"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: github-ops
scenario: push_woodpecker
input: .woodpecker/ 目录 + github-repo-info.json
```
FAIL → WARN（不阻断，记录日志后继续 Phase 6.0）

写日志：调用 `write_step_log`，step=`"phase-5.9"`，step_type=`"agent"`，agent=`"github-ops"`，从 `woodpecker-push-report.json`（若存在）读取 `overall` 字段作为 `key_decisions`。

---

## Phase 6.0 — Pre-Deploy Readiness Check（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/pre-deploy-readiness-check.sh
```
FAIL → **ESCALATION**（不自动回退，请求人工介入）

写日志：调用 `write_step_log`，step=`"phase-6.0"`，step_type=`"autostep"`，agent=`""`，从 `deploy-readiness-report.json`（若存在）读取 `overall` 及 `issues` 前 3 条作为 `key_decisions`。

---

## Phase 6 — Deployer（部署）

注入上下文：调用 `build_context_injection(current_step="phase-6", include_steps=["gate-e"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: deployer
input: deploy-plan.md + state.json
output: .pipeline/artifacts/deploy-report.json
```
FAIL：读取 `deploy-report.json` 中 `failure_type`：
- `deployment_failed` → rollback_to: phase-3
  标注因果：调用 `mark_rollback_causality(cause_step="phase-6", target_step="phase-3")`。
- `smoke_test_failed` → 激活 Deployer 执行生产回滚，然后 rollback_to: phase-1
  标注因果：调用 `mark_rollback_causality(cause_step="phase-6", target_step="phase-1")`。

写日志：调用 `write_step_log`，step=`"phase-6"`，step_type=`"agent"`，agent=`"deployer"`，从 `deploy-report.json` 读取 `status`、`environment` 及 `failure_type`（如有）作为 `key_decisions`。

---

## Phase 7 — Monitor（上线观测）

注入上下文：调用 `build_context_injection(current_step="phase-7", include_steps=["phase-6"])`，将返回值附加到 spawn 消息头部（若返回空字符串则跳过）。
```
spawn: monitor
input: deploy-report.json + config.json 阈值
output: .pipeline/artifacts/monitor-report.json
```
读取 `status` 字段：
- `NORMAL` → 写入 state.json `status: COMPLETED`，执行测试文件毕业（new_test_files → regression-suite-manifest.json）
  写索引最终状态：将 `pipeline.index.json` 中 `status` 字段更新为 `"completed"`，`updated_at` 更新为当前时间。
- `ALERT` → 运行 Hotfix Scope Analyzer → phase-3 hotfix
  标注因果：调用 `mark_rollback_causality(cause_step="phase-7", target_step="phase-3")`。
- `CRITICAL` → 激活 Deployer 执行生产回滚 → rollback_to: phase-1
  标注因果：调用 `mark_rollback_causality(cause_step="phase-7", target_step="phase-1")`。

写日志：调用 `write_step_log`，step=`"phase-7"`，step_type=`"agent"`，agent=`"monitor"`，从 `monitor-report.json` 读取 `status`、`error_rate` 及 `p95_latency`（如有）作为 `key_decisions`。

---

## Memory Consolidation — 项目记忆固化

> 详细规则见 orchestrator.md 中"项目记忆固化"节。Phase 7 返回 NORMAL 后执行。

1. **提取候选约束**：读取 `requirement.md`、`proposal.md`、`adr-draft.md`，提取 MUST/MUST NOT 形式的约束句
2. **与已有约束去重**：读取 `project-memory.json`，语义重复跳过，语义冲突标记待确认
3. **展示给用户确认**：列出新约束和冲突约束，等待用户回复"确认"
4. **写入 project-memory.json**：
   - 新增约束追加到 `constraints`，自动分配 `id`（C-NNN）
   - 被推翻约束移入 `superseded`
   - 追加本次运行到 `runs`（含实现足迹）
   - 首次运行时写入 `project_purpose`
5. **归档本次产物**：复制 requirement.md、proposal.md、adr-draft.md、tasks.json 到 `.pipeline/history/<pipeline_id>/`

---

## Mark Proposal Completed — 提案完成标记

> 详细规则见 orchestrator.md 中"Mark Proposal Completed"节。

Memory Consolidation 完成后执行：

1. 读取 `proposal-queue.json`，找到当前 `status: "running"` 的提案
2. 将其 `status` 改为 `"completed"`
3. 写入 proposal-queue.json
4. 输出 `[Pipeline] 提案 <id> <title> 交付完成`
5. 进入 `pick-next-proposal`（路由表指向）

---

## Appendix: key_decisions 提取规则

从已有 artifact 机械提取，字段缺失时忽略不报错：

| 步骤 | 提取来源 | 提取内容 |
|------|----------|----------|
| Gate（Auditor 类） | `gate-*.json` | `issues[severity=CRITICAL].message`（全部）+ `overall` + `rollback_to` |
| AutoStep（report 类） | `*-report.json` | `overall` + `issues[severity!=INFO].message`（前 3 条） |
| Builder | `impl-manifest-<name>.json` | `summary`（若有）或 `"共变更 N 个文件"` |
| Architect | `proposal.md` | 技术栈段落的前 2 行 |
| Clarifier | `requirement.md` | "验收标准"的前 3 条 |
| Tester | `test-report.json` | `total`、`passed`、`coverage` 三个数字 |
| Documenter | `doc-manifest.json` | `docs_updated` 列表（前 3 项） |
| Deployer | `deploy-report.json` | `status` + `environment` + `failure_type`（如有） |
| Monitor | `monitor-report.json` | `status` + `error_rate` + `p95_latency`（如有） |
