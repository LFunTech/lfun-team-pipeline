# Pipeline Playbook — 阶段执行手册

> 本文件由 Pilot 按需加载。进入某阶段时，只需读取对应章节，无需加载全文。
> 每个章节包含：spawn 规则、输入输出、验证条件、失败处理。

---

## System Planning — 系统规划

> 仅在 `.pipeline/proposal-queue.json` 不存在时执行。

本章节由 Pilot 内联执行（不 spawn 独立 Agent），交互式与用户对话：

1. 向用户提问："请描述你要构建的完整系统（功能、用户角色、核心业务流程）。"
2. 最多 3 轮澄清（聚焦系统边界、核心域、技术偏好）
3. 生成系统蓝图 `.pipeline/artifacts/system-blueprint.md`，包含：
   - 系统定位（一句话）、技术栈选型、域划分（核心业务域列表）
   - 数据模型骨架（表名 + 核心外键关系，不含完整字段）
   - 跨域集成协议（域间交互方式）、共享约定（API 前缀、认证方式、错误格式）
4. 将系统拆解为有序提案队列，写入 `.pipeline/proposal-queue.json`：
   - 每个提案是一个可独立交付的增量
   - 明确 `depends_on`（依赖哪些前序提案）和 `scope`（包含/不包含什么）
   - `domains`（可选但推荐）：该提案涉及的业务领域列表，从已有约束的 domain 值中选取或新建简短中文领域名
   - 第一个提案应包含基础框架搭建（脚手架、CI、认证基础设施）
5. 将蓝图中的技术栈和共享约定写入 `project-memory.json` 的 `constraints`（自动分配 id）
6. 展示蓝图和提案队列给用户确认，用户可调整顺序、范围、增删提案
7. **自治模式**（`autonomous_mode = true`）：逐个提案与用户确认 `detail`（结构见下），全部确认后写入 proposal-queue.json
8. 用户确认后进入 `pick-next-proposal`

> 自治模式提示：System Planning 完成后，若 `autonomous_mode = false`，提示用户可设置 `"autonomous_mode": true` 以全自动执行。

### 蓝图模板

```markdown
# 系统蓝图: [系统名称]
## 系统定位
[一句话描述]
## 技术栈
- 后端: [框架] / 前端: [框架]（如有） / 数据库: [数据库] / 部署: [方式]
## 域划分与提案归属
| 业务域 | 负责提案 | 依赖域 |
## 数据模型骨架
[表名 + 核心外键关系]
## 跨域集成协议
[域间交互方式]
## 共享约定
[API 前缀、认证方式、错误格式、日志格式]
## 交付计划
[提案顺序 + 依赖关系 + 范围边界]
## 并行执行计划
| Group | 提案 | 并行度 |
```

### 提案 detail 结构（自治模式必填，交互模式可选）

```json
{
  "id": "P-001", "title": "基础框架与用户体系",
  "scope": "包含/不包含描述",
  "domains": ["用户", "团队", "环境"],
  "depends_on": [], "status": "pending",
  "parallel_group": 0,
  "detail": {
    "user_stories": ["管理员可以创建/编辑/禁用用户账号"],
    "business_rules": ["密码最少 8 位，包含大小写和数字"],
    "acceptance_criteria": ["POST /api/auth/login 返回 200 + JWT Token"],
    "api_overview": ["POST /api/auth/login — 登录"],
    "data_entities": ["users(id, email, password_hash, name, role, status, created_at)"],
    "non_functional": ["API 响应时间 p95 < 200ms"]
  }
}
```

细化流程（仅 `autonomous_mode = true`）：蓝图确认后逐个提案展示 detail 草案请用户审阅修改，确认后写入 proposal-queue.json。交互模式下 detail 字段可选。

### 并行拓扑计算（System Planning 第 4 步之后执行）

> `parallel_group` 字段标识提案的并行层级（从 0 开始）。同一 `parallel_group` 内的提案可同时执行。

**计算算法（拓扑排序 + 域冲突拆分）：**

1. **拓扑分层**：按 `depends_on` 构建 DAG，执行 Kahn 算法逐层分组
   - 无依赖提案 → group 0
   - 仅依赖 group 0 中已有提案 → group 1
   - 以此类推
2. **域冲突拆分**：同层内若两个提案 `domains` 有交集，将后者推迟到下一层
   - 比较方式：两个提案的 `domains` 数组取交集，非空则冲突
   - `domains` 为空或缺省的提案视为与所有提案冲突（不可并行），独占一层
3. **写入 `parallel_group`**：每个提案赋值计算后的层级编号

**示例**：
```
P-001（框架）     depends_on: []           domains: ["基础"]     → group 0
P-002（用户系统） depends_on: ["P-001"]    domains: ["用户"]     → group 1
P-003（商品管理） depends_on: ["P-001"]    domains: ["商品"]     → group 1（与 P-002 无域冲突，同层）
P-004（权限管理） depends_on: ["P-001"]    domains: ["用户"]     → group 2（与 P-002 域冲突"用户"，推迟）
P-005（订单系统） depends_on: ["P-002","P-003"] domains: ["订单"] → group 2（依赖 group 1）
```

**并行计划展示**（System Planning 蓝图中新增章节）：
```markdown
## 并行执行计划
| Group | 提案 | 预计并行度 |
|-------|------|-----------|
| 0     | P-001 | 1（串行） |
| 1     | P-002, P-003 | 2（并行） |
| 2     | P-004, P-005 | 2（并行） |
```

4. 用户可在确认蓝图时调整 `parallel_group`（手动合并或拆分层级）

---

## Pick Next Proposal — 提案选取

### 单提案模式（同组仅一个 pending）

1. 读取 `proposal-queue.json`，找所有 `status: "pending"` 且 `depends_on` 全部 `completed` 的提案
2. 若无可执行提案但仍有 `pending` → ESCALATION（依赖未满足）
3. 若只有一个可执行提案（或该提案 `parallel_group` 内无其他可执行提案）：
   - 将该提案 `status` 改为 `"running"`，`pipeline_id` 设为当前 `state.json.pipeline_id`
   - 重新初始化 `state.json`（新 pipeline_id，attempt_counts 归零，status: running）
   - 按下方"传递格式"进入 Phase 0

### 多提案并行模式（同组有 ≥2 个 pending）

> 当同一 `parallel_group` 内有多个提案可同时执行时，启用并行模式。

1. 从可执行提案中，取 `parallel_group` 值最小的一组
2. 记录当前分支和 SHA 为并行基准：
   ```bash
   PARALLEL_BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
   PARALLEL_BASE_SHA=$(git rev-parse HEAD)
   ```
3. 为每个并行提案创建 worktree：
   ```bash
   git worktree add -b pipeline/proposal-<id> \
     ".worktrees/proposal-<id>" "$PARALLEL_BASE_SHA"
   ```
4. 初始化每个提案的独立 pipeline 状态：
   - 在每个 worktree 中创建 `.pipeline/state-<id>.json`（独立 pipeline_id、attempt_counts 等）
   - 将所有并行提案 `status` 改为 `"running"`
5. 写入 `state.json` 的新字段：
   ```json
   {
     "parallel_proposals": ["P-002", "P-003"],
     "parallel_base_sha": "<SHA>",
     "parallel_base_branch": "<branch>",
     "parallel_worktrees": {"P-002": "<abs-path>", "P-003": "<abs-path>"},
     "parallel_branches": {"P-002": "pipeline/proposal-P-002", ...},
     "parallel_merge_order": ["P-002", "P-003"],
     "parallel_completed": []
   }
   ```
6. **并行执行**：在同一条响应中为每个并行提案发起独立的 Agent tool call：
   ```
   spawn: pilot（自身递归）
   cwd: <parallel_worktrees["P-NNN"]>
   PIPELINE_DIR: <worktree>/.pipeline
   PROPOSAL_ID: P-NNN
   MODE: parallel-child
   ```
   每个子 pilot 独立完成该提案的全部阶段（Phase 0 → Phase 7），使用 `state-<id>.json` 跟踪状态。
7. 所有并行提案完成后，进入**提案合并序列**（见下方）。

### 传递格式

**交互模式**：
```
[来自系统规划的提案 P-NNN]
标题: <title>
范围: <scope>
依赖提案: <depends_on 中已完成提案的 title>
请基于以上范围进行需求澄清。
```
**自治模式**（`autonomous_mode = true`）：**不 spawn Clarifier**。Pilot 直接将提案 `detail` 字段转写为 `requirement.md`。章节映射：
   - `user_stories` → `## 用户故事`、`business_rules` → `## 业务规则`
   - `acceptance_criteria` → `## 验收标准`、`api_overview` → `## API 概览`
   - `data_entities` → `## 数据实体`、`non_functional` → `## 非功能需求`
   - 文件头：`# <title>`、`> 范围: <scope>`。无 detail 的字段跳过，不确定项标注 `[ASSUMED]`

---

## Mark Proposal Completed — 提案完成标记

### 单提案模式

1. 读取 `proposal-queue.json`，找到当前 `status: "running"` 的提案
2. 将其 `status` 改为 `"completed"`，写入文件
3. 输出 `[Pipeline] 提案 <id> <title> 交付完成`
4. 进入 `pick-next-proposal`（路由表指向）

### 多提案并行模式 — 提案合并序列

> 当 `state.json.parallel_proposals` 非空时执行。所有并行子 pilot 完成后触发。

1. **验证完成状态**：检查 `parallel_proposals` 中每个提案的 worktree 内 `state-<id>.json` 的 `current_phase` 是否为 `mark-proposal-completed`。未全部完成 → 等待（子 pilot 仍在运行）。

2. **按序合并**（按 `parallel_merge_order` 顺序）：
   ```bash
   git checkout "$PARALLEL_BASE_BRANCH"
   for PROPOSAL_ID in parallel_merge_order:
     BRANCH="pipeline/proposal-$PROPOSAL_ID"
     # 干跑检测
     if ! git merge --no-commit --no-ff "$BRANCH" 2>/dev/null; then
       git merge --abort 2>/dev/null || true
       → ESCALATION：并行提案合并冲突（$PROPOSAL_ID），
         保留 worktree 供人工解决
       → 输出人工恢复指令，status: escalation，停止
     fi
     git merge --abort 2>/dev/null || true
     git merge --no-ff "$BRANCH" -m "merge: proposal $PROPOSAL_ID"
   ```

3. **合并 project-memory.json**：
   - 各 worktree 的 Memory Consolidation 已写入各自的 `project-memory.json`
   - 合并策略：以主分支为基准，依次合入各提案新增的 constraints（去重）
   - 冲突约束（不同提案产生矛盾约束）→ 标记 `[PARALLEL-CONFLICT]`，交互模式下请用户裁决，自治模式下保留先合入者

4. **清理 worktree**：
   ```bash
   for PROPOSAL_ID in parallel_proposals:
     git worktree remove ".worktrees/proposal-$PROPOSAL_ID" --force
     git branch -d "pipeline/proposal-$PROPOSAL_ID"
   rmdir .worktrees 2>/dev/null || true
   ```

5. **标记完成**：将所有并行提案 `status` 改为 `"completed"`，清空 `state.json` 中的 `parallel_*` 字段

6. **归档产物**：将各 worktree 中的 `.pipeline/artifacts/` 复制到主 repo 的 `.pipeline/history/<pipeline_id>/`（需在 worktree 清理前执行）

7. 输出 `[Pipeline] 并行组完成：<ids>，全部合并成功`
8. 进入 `pick-next-proposal`

---

## Memory Load — 项目记忆加载

在 Phase 0 之前执行。通过 AutoStep 脚本按 tier/domain 分层过滤约束：

run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/memory-load.sh

输出: `.pipeline/artifacts/memory-injection.txt`

1. 文件不存在或无 running 提案 → SKIP，直接进入 Phase 0
2. PASS → Pilot 读取 `memory-injection.txt` 全文，作为 Phase 0 Clarifier 和 Phase 1 Architect 的 spawn 消息最前方内容
3. 其他阶段不注入项目记忆（通过 artifacts 文件传递信息）

**过滤规则**：
- `tier: 1`（或缺少 tier 字段）：全局约束，每次必注入
- `tier: 2`：领域约束，仅当约束的 `domain` 匹配当前提案时注入
- 匹配策略：proposal 的 `domains` 字段（显式声明）+ `scope` 文本匹配取并集

---

## Phase 0 — Clarifier（需求澄清）
```
spawn: clarifier
input: 用户原始需求文本
output: .pipeline/artifacts/requirement.md
```
**交互模式**（`autonomous_mode = false`）：Clarifier 最多 5 轮澄清（每轮暂停展示问题给用户，等待用户回答后传回）。
**自治模式**（`autonomous_mode = true`）：**不 spawn Clarifier**。Pilot 直接将提案 detail 字段转写为 requirement.md（章节映射：user_stories→用户故事，business_rules→业务规则，acceptance_criteria→验收标准，api_overview→API概览，data_entities→数据实体，non_functional→非功能需求）。不确定项标注 `[ASSUMED]`。
完成后检查 requirement.md 存在且非空。

---

## Phase 0.5 — Requirement Completeness Checker（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/requirement-completeness-checker.sh
output: .pipeline/artifacts/requirement-completeness-report.json
```
读取报告 `overall` 字段：
- `PASS` → 进入 Phase 1
- `FAIL` → 递增 phase-0 attempt，rollback_to: phase-0（提示 Clarifier 补充缺失内容）

---

## Phase 1 — Architect（方案设计）

```
spawn: architect
input: requirement.md
output: .pipeline/artifacts/proposal.md, .pipeline/artifacts/adr-draft.md
```
验证 proposal.md 和 adr-draft.md 均存在且非空。

---

## Gate A — Auditor 校验（方案审核）

```
spawn: auditor-gate
input: requirement.md + proposal.md
output: .pipeline/artifacts/gate-a-review.json
```
矛盾检测 → 读取 overall：
- `PASS` → 解析 proposal.md 激活条件角色，按以下映射写入 state.json：
  - `data_migration_required: true` → `state.json.conditional_agents.migrator = true`
  - `performance_sensitive: true` → `state.json.conditional_agents.optimizer = true`
  - `i18n_required: true` → `state.json.conditional_agents.translator = true`
  - 若 proposal.md 中无对应字段，保持 `false`（默认值）
  进入 Phase 2.0a
- `FAIL` → rollback_to（取最深目标）

---

## Phase 2.0a — GitHub Repo Creator（github-ops Agent）

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

---

## Phase 2.0b — Depend Collector（AutoStep + 暂停）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/depend-collector.sh
output: .pipeline/artifacts/depend-collection-report.json
```
读取报告 `unfilled_deps` 字段（检测到但 .env 未填写的依赖）：
- 非空：
  - **交互模式**（`autonomous_mode = false`）→ **暂停**，向用户展示：
    ```
    ⚠️  检测到以下外部依赖，请填写凭证文件后继续：
    <逐行列出 unfilled_deps 中每项对应的 .depend/<name>.env.template 路径>
    参考 .depend/README.md 了解填写说明。
    完成后回复"继续"。
    ```
    等待用户输入"继续"后进入 Phase 2。
  - **自治模式**（`autonomous_mode = true`）→ **不暂停**，输出 `[WARN] 自治模式：跳过凭证填写等待（unfilled: <列表>），部署阶段可能失败`，直接进入 Phase 2。
- 空（所有依赖凭证已填写或无外部依赖）→ 直接进入 Phase 2。

---

## Phase 2 — Planner（任务细化）

```
spawn: planner
input: proposal.md + requirement.md
output: .pipeline/artifacts/tasks.json
```

---

## Phase 2.1 — Assumption Propagation Validator（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/assumption-propagation-validator.sh
output: .pipeline/artifacts/assumption-propagation-report.json
```
结果附加给 Gate B Auditor-Biz（WARN 不阻断，仅信息传递）。

---

## Gate B — Auditor 校验（任务细化审核）

```
spawn: auditor-gate
input: proposal.md + tasks.json + assumption-propagation-report.json
output: .pipeline/artifacts/gate-b-review.json
```

---

## Phase 2.5 — Contract Formalizer（契约形式化）

```
spawn: contract-formalizer
input: tasks.json
output: .pipeline/artifacts/contracts/ 目录
```

---

## Phase 2.6 + 2.7 — 契约验证（并行 AutoStep）

> **并行执行**：Phase 2.6 和 2.7 无依赖关系，**必须**在同一条响应中发起两个 Bash tool call 并行执行。

**Phase 2.6 — Schema Completeness Validator**
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/schema-completeness-validator.sh
output: .pipeline/artifacts/schema-validation-report.json
```

**Phase 2.7 — Contract Semantic Validator**
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/contract-semantic-validator.sh
output: .pipeline/artifacts/contract-semantic-report.json
```

**结果处理**：等待两者全部完成后判断——任一 FAIL → rollback_to: phase-2.5

---

## Phase 3 — 并行实现（Worktree 隔离）

### Phase 3 Step 0 — Worktree 初始化（Phase 3 内部步骤，无独立路由条目）

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

### Phase 3 — Builder 调度（波次内并行）

> **并行执行**：同一波次内的 Builder **必须**在同一条响应中发起多个 Agent tool call 并行执行。波次之间保持顺序（下一波等上一波全部完成）。

按以下波次 spawn，每波内并行，波间顺序：
- 波次 1（**并行**）：DBA ∥ Migrator（条件）
- 波次 2：Backend
- 波次 3（**并行**）：Security ∥ Frontend
- 波次 4（**并行**）：Infra（依赖 Security）∥ Translator（条件，依赖 Frontend）


**spawn 消息格式**：
```
spawn: builder-<name>
cwd: <phase_3_worktrees["name"]>（绝对路径）
PIPELINE_DIR: <主repo绝对路径>/.pipeline
BUILDER_NAME: <name>
```
Translator 额外传入：`FRONTEND_WORKTREE: <phase_3_worktrees["frontend"]>`（若 `phase_3_worktrees` 中不存在 `"frontend"` key，传空字符串 `FRONTEND_WORKTREE=""`，Translator 仅处理后端文案国际化，跳过前端代码读取）

**完成验证**（每个 Builder 完成后机械检查）：
1. `$PIPELINE_DIR/artifacts/impl-manifest-<name>.json` 存在且非空
2. `git log pipeline/phase-3/builder-<name> --oneline -1` 有 Phase 3 的 commit

每个 Builder 输出 `$PIPELINE_DIR/artifacts/impl-manifest-<builder>.json`。
全部完成后进入合并步骤。

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
- `FAIL` → rollback_to: phase-3（按原 Builder 任务重新实现，**Pilot 不得自行修复 Builder 代码**）

⚠️ **重要约束**：Build Verifier FAIL 时，Pilot **必须** rollback 委托给对应 Builder 重新实现，**禁止** Pilot 直接修改源代码绕过编译错误。

### 回滚清理（rollback_to: phase-3 时）

重进 Phase 3.0 前执行：
```bash
for BUILDER in phase_3_worktrees（若非空）:
  git worktree remove ".worktrees/builder-$BUILDER" --force 2>/dev/null || true
  git branch -D "pipeline/phase-3/builder-$BUILDER" 2>/dev/null || true
rm -rf .worktrees 2>/dev/null || true

# 移除上一轮 Tester 新增的测试文件（避免 Regression Guard 误报）
for TEST_FILE in state.json.new_test_files（若非空）:
  git rm "$TEST_FILE" 2>/dev/null || true
git commit -m "chore: remove new_test_files before phase-3 retry" --allow-empty 2>/dev/null || true

# 重置 state.json
phase_3_worktrees = {}; phase_3_branches = {}
phase_3_base_sha = null; phase_3_main_branch = null
new_test_files = []
```

---

## Phase 3.0d + 3.1 + 3.2 + 3.3 — 构建后分析（并行 AutoStep）

> **并行执行**：这四个分析步骤无依赖关系，**必须**在同一条响应中发起四个 Bash tool call 并行执行。

**Phase 3.0d — Duplicate Detector**
```
run: MODE="incremental" PIPELINE_DIR=".pipeline" bash .pipeline/autosteps/duplicate-detector.sh
```
FAIL → WARN（非阻塞，不触发回滚）

**Phase 3.1 — Static Analyzer**
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/static-analyzer.sh
```
FAIL → rollback_to: phase-3（**阻断级**）

**Phase 3.2 — Diff Scope Validator**
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/diff-scope-validator.sh
```
FAIL → WARN（非阻塞，未授权变更信息记录在 `scope-validation-report.json` 中供 Gate C Inspector 参考）

**Phase 3.3 — Regression Guard**
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/regression-guard.sh
```
FAIL → WARN（非阻塞，回归测试失败信息记录在 `regression-report.json` 中供 Gate C 参考。new_test_files 排除在外）

**结果处理**：等待四者全部完成后统一判断——Phase 3.1 FAIL → rollback_to: phase-3；其余 FAIL 仅记录 WARN 日志。全部处理完毕后进入 Phase 3.5。

---

## Phase 3.5 — Simplifier

```
spawn: simplifier
input: static-analysis-report.json + 代码
output: .pipeline/artifacts/simplify-report.md
```
验证 simplify-report.md 修改时间 > impl-manifest.json 修改时间。

---

## Phase 3.6 — Post-Simplification Verifier（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/post-simplification-verifier.sh
```
FAIL → rollback_to: phase-3.5

---

## Gate C — Inspector（代码审查）

```
spawn: inspector
input: 代码 + 所有 Phase 3 报告
output: .pipeline/artifacts/gate-c-review.json
```
Inspector 调用前，Pilot 在 spawn 消息中追加 `simplifier_verified: true`（当 Phase 3.6 Post-Simplification Verifier PASS 时）或 `simplifier_verified: false`（当 Phase 3.6 未执行或 FAIL 时）。此字段通过 spawn 消息传递，不存储在 state.json 或独立文件中。
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

**Resolver 退出条件**：
- Resolver 成功修复所有 CRITICAL/MAJOR 问题 → 更新 `phase_3_base_sha`，重新进入 Phase 3.0b
- Resolver 修复不完整（仍有 CRITICAL 问题）→ 计入 `gate-c` attempt_count，超过 max_attempts 时 ESCALATION
- Resolver 判断问题需架构变更（超出 Phase 3 范围）→ 输出 `rollback_to: phase-1`，Pilot 执行深度回滚


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

```
spawn: tester
input: tasks.json + impl-manifest.json
output: .pipeline/artifacts/test-report.json, .pipeline/artifacts/coverage.lcov
```
FAIL → 运行 Phase 4a.1（Test Failure Mapper）

**new_test_files 写入**：Tester 完成后，Pilot 从 `test-report.json` 或 Tester 的 `state.json.new_test_files` 更新中读取新增测试文件路径列表。此列表的生命周期为：
- Phase 3.3 Regression Guard：排除 `new_test_files` 中的文件（避免对未毕业的新测试做回归）
- Phase 4a Tester：**写入** `state.json.new_test_files`（当前运行新增的测试文件）
- Phase 7 Monitor NORMAL：**毕业**，将 `new_test_files` 条目迁移到 `regression-suite-manifest.json`，然后清空 `new_test_files`

---

## Phase 4a.1 — Test Failure Mapper（AutoStep，仅 Phase 4a FAIL 时）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/test-failure-mapper.sh
output: .pipeline/artifacts/failure-builder-map.json
```
读取 `confidence` 字段：
- `HIGH` → 精确回退（仅 builders_to_rollback 中的 builder）
- `LOW` → 保守全体回退 phase-3

---

## Phase 4.2 — Test Coverage Enforcer（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/test-coverage-enforcer.sh
```
FAIL → rollback_to: phase-4a

PASS 后条件跳转：读取 `state.json.conditional_agents.optimizer`，若为 `true` → 进入 Phase 4b；若为 `false` → 跳过 Phase 4b，直接进入 Gate D。

---

## Phase 4b — Optimizer（条件角色，仅 performance_sensitive: true）

```
spawn: optimizer
input: test-report.json + impl-manifest.json
output: .pipeline/artifacts/perf-report.json
```
`perf-report.json` 中 `sla_violated: true` → 直接 rollback_to: phase-3（不等 Gate D）。

---

## Gate D — Auditor-QA（测试验收）

```
spawn: auditor-qa
input: test-report.json + coverage-report.json + perf-report.json（如有）
output: .pipeline/artifacts/gate-d-review.json（含结构化 rollback_to 字段）
```
FAIL → rollback_to（限制：不超过 phase-2，只能 phase-4a 或 phase-3）

---

## API Change Detector — api-change-detector（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/api-change-detector.sh
output: .pipeline/artifacts/api-change-report.json
```
写入 state.json: `phase_5_mode`（`full` 或 `changelog_only`）

---

## Phase 5 — Documenter（文档）

```
spawn: documenter
input: api-change-report.json + adr-draft.md + impl-manifest.json
output: .pipeline/artifacts/doc-manifest.json
```
如 `phase_5_mode: changelog_only`，仅更新 CHANGELOG，跳过 API 文档更新。

---

## Phase 5.1 — Changelog Consistency Checker（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/changelog-consistency-checker.sh
```
FAIL → rollback_to: phase-5

---

## Gate E — Auditor-QA + Auditor-Tech（文档审核，并行）

> **并行执行**：auditor-qa 和 auditor-tech **必须**在同一条响应中发起两个 Agent tool call 并行执行。

```
spawn: auditor-qa ∥ auditor-tech
input: doc-manifest.json + API 文档 + CHANGELOG + ADR
output: .pipeline/artifacts/gate-e-review.json
```
**结果处理**：等待两者全部完成后合并审核结论。任一 FAIL → rollback_to: phase-5；两者 rollback 目标不同时取最深。

---

## Phase 5.9 — GitHub Woodpecker Push（github-ops Agent）

仅在 `state.json.github_repo_created = true` 时执行；否则跳过，直接进入 Phase 6.0。

```
spawn: github-ops
scenario: push_woodpecker
input: .woodpecker/ 目录 + github-repo-info.json
```
FAIL → WARN（不阻断，记录日志后继续 Phase 6.0）

---

## Phase 6.0 — Pre-Deploy Readiness Check（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/pre-deploy-readiness-check.sh
```
FAIL → **ESCALATION**（不自动回退，请求人工介入）

---

## Phase 6 — Deployer（部署）

```
spawn: deployer
input: deploy-plan.md + state.json
output: .pipeline/artifacts/deploy-report.json
```
FAIL：读取 `deploy-report.json` 中 `failure_type`：
- `deployment_failed` → rollback_to: phase-3
- `smoke_test_failed` → 激活 Deployer 执行生产回滚，然后 rollback_to: phase-1

---

## Phase 7 — Monitor（上线观测）

```
spawn: monitor
input: deploy-report.json + config.json 阈值
output: .pipeline/artifacts/monitor-report.json
```
读取 `status` 字段：
- `NORMAL` → 写入 state.json `status: COMPLETED`，执行测试文件毕业（new_test_files → regression-suite-manifest.json）
- `ALERT` → Pilot 分析 `monitor-report.json` 中 `alert_details` 定位受影响模块，映射到对应 Builder，rollback_to: phase-3（精确重跑受影响 Builder）
- `CRITICAL` → 激活 Deployer 执行生产回滚 → rollback_to: phase-1

---

## Memory Consolidation — 项目记忆固化

Phase 7 返回 NORMAL 后执行。

### Step 1 — 提取候选约束
读取 `requirement.md`、`proposal.md`、`adr-draft.md`，提取 **MUST / MUST NOT / 必须 / 禁止 / 统一 / 限制** 形式的约束句。

### Step 2 — 与已有约束去重
读取 `project-memory.json`（不存在则初始化为 `{"version":1,"project_purpose":"","constraints":[],"superseded":[],"runs":[]}`）。
- 语义重复 → 跳过
- 语义冲突 → 标记待确认

### Step 3 — 确认约束
**交互模式**（`autonomous_mode = false`）：
```
本次交付产生以下新约束，请确认或修改后回复"确认"：
  [C-NNN] <约束文本>
以下约束可能与已有约束冲突，请确认是否推翻：
  [C-XXX] <旧约束> ← 与新约束 <新文本> 冲突？
```
**自治模式**（`autonomous_mode = true`）：自动接受新增约束，冲突约束跳过（保留旧约束，标注 `[AUTO-SKIPPED]`），输出 `[Pipeline] 自治模式：自动接受 N 条新约束，跳过 M 条冲突约束`。

### Step 4 — 写入 project-memory.json
1. 首次运行时从 `requirement.md` 提取项目定位写入 `project_purpose`
2. 新增约束追加到 `constraints`，自动分配 `id`（C-NNN，已有最大编号 +1）
3. 每条约束：`{id, text, tags, source: <pipeline_id>, tier, domain}`
   - tier 分类规则：
     - tier=1（全局）：技术栈选型、API 规范、命名约定、安全基线、架构模式
     - tier=2（领域）：特定功能域的业务规则、数据约束、交互约束
   - domain：tier=2 时必填，从当前提案的 scope/domains 推断，使用简短中文名
   - 分类示例：
     - "所有 API 统一返回 {code, message, data} 格式" → tier=1, domain 留空
     - "密码策略必须包含大小写+数字+特殊字符" → tier=1, domain 留空
     - "POST /api/config-nodes 必须校验环境权限" → tier=2, domain="配置管理"
     - "数据库操作台 SQL 执行必须设置 30 秒超时" → tier=2, domain="数据库操作台"
     - "Webhook 重试策略为指数退避，最多 5 次" → tier=2, domain="通知/Webhook"
4. 被推翻约束从 `constraints` 移入 `superseded`，记录 `superseded_by` 和 `reason`
5. 追加本次运行到 `runs`：
   ```json
   {"pipeline_id":"<id>","date":"<YYYY-MM-DD>","feature":"<标题>",
    "proposal_ref":"history/<id>/proposal.md","adr_ref":"history/<id>/adr-draft.md",
    "footprint":{"api_endpoints":["从 impl-manifest-backend.json 提取"],
                 "db_tables":["从 impl-manifest-dba.json 提取"],
                 "key_files":["从 impl-manifest.json 提取前 10 个"]}}
   ```
6. `constraints` 超 50 条 → 输出 `[WARN] 项目约束已达 50 条上限，建议审查清理`

### Step 5 — 归档本次产物
```bash
ARCHIVE_DIR=".pipeline/history/${PIPELINE_ID}"
mkdir -p "$ARCHIVE_DIR"
cp .pipeline/artifacts/{requirement.md,proposal.md,adr-draft.md,tasks.json} "$ARCHIVE_DIR/"
```

---

## 附录 A — Git Commit Message 规范

| 阶段 | Commit Message |
|------|----------------|
| Phase 0 | `docs: add requirement specification` |
| Phase 1 | `docs: add architecture proposal and ADRs` |
| Gate A | `ci: gate-a passed` |
| Phase 2 | `docs: add task breakdown (N tasks, M builders)` |
| Phase 2.5 | `docs: add OpenAPI contracts for N services` |
| Gate B | `ci: gate-b passed` |
| Phase 3 | `feat(builder-<name>): implement <service-name>` |
| Phase 3.5 | `refactor: simplify implementation per static analysis` |
| Gate C | `ci: gate-c passed` |
| Phase 4a | `test: add test suite (N cases, M passed)` |
| Gate D | `ci: gate-d passed` |
| Phase 5 | `docs: add README, CHANGELOG and API documentation` |
| Gate E | `ci: gate-e passed` |
| Phase 6 | `chore: add deployment configuration and woodpecker pipelines` |

括号内变量从对应产物文件读取真实值。

## 附录 B — state.json 完整 Schema

```json
{
  "pipeline_id": "pipe-YYYYMMDD-001",
  "project_name": "PROJECT",
  "current_phase": "phase-0",
  "last_completed_phase": null,
  "status": "running",
  "attempt_counts": {
    "phase-0": 0, "phase-0.5": 0, "phase-1": 0, "gate-a": 0,
    "phase-2.0a": 0, "phase-2.0b": 0, "phase-2": 0, "phase-2.1": 0, "gate-b": 0,
    "phase-2.5": 0, "phase-2.6": 0, "phase-2.7": 0,
    "phase-3": 0, "phase-3.0b": 0, "phase-3.1": 0, "phase-3.2": 0, "phase-3.3": 0,
    "phase-3.5": 0, "phase-3.6": 0, "gate-c": 0, "phase-3.7": 0,
    "phase-4a": 0, "phase-4a.1": 0, "phase-4.2": 0, "phase-4b": 0,
    "gate-d": 0, "api-change-detector": 0,
    "phase-5": 0, "phase-5.1": 0, "gate-e": 0, "phase-5.9": 0,
    "phase-6.0": 0, "phase-6": 0, "phase-7": 0,
    "per_builder": {}
  },
  "conditional_agents": { "migrator": false, "optimizer": false, "translator": false },
  "phase_5_mode": "full",
  "new_test_files": [],
  "phase_3_base_sha": null,
  "phase_3_worktrees": {},
  "phase_3_branches": {},
  "phase_3_main_branch": null,
  "phase_3_merge_order": [],
  "github_repo_created": false,
  "github_repo_url": null,
  "execution_log": [],
  "parallel_proposals": [],
  "parallel_base_sha": null,
  "parallel_base_branch": null,
  "parallel_worktrees": {},
  "parallel_branches": {},
  "parallel_merge_order": [],
  "parallel_completed": []
}
```

---

