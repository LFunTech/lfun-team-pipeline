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
   - 按下方"传递格式"进入 0.clarify

### 多提案并行模式（同组有 ≥2 个 pending）

> 当同一 `parallel_group` 内有多个提案可同时执行时，启用并行模式。

1. 从可执行提案中，取 `parallel_group` 值最小的一组
2. **并行前置风险检查（强制）**：
   ```bash
   PIPELINE_DIR=.pipeline PROPOSAL_IDS="P-002,P-003" \
     python3 .pipeline/autosteps/parallel-proposal-detector.py
   ```
   读取 `.pipeline/artifacts/parallel-proposal-report.json`：
   - `overall = "PASS"` → 允许进入多提案并行模式
   - `overall = "OVERLAP"` → **降级为单提案模式**：只取该组中排序最前的一个提案进入 running，其余保持 pending，等待下一轮 `pick-next-proposal`
   - `overall = "ERROR"` 或脚本 exit != 0 → ESCALATION

   **降级规则（保守优先）**：出现以下任一情况都不得并行：
   - 任一提案缺少 `detail`
   - 任一提案缺少 `domains`
   - 两个提案在 `domains`、API 概览、数据实体、共享关键词上存在重叠
   - 命中共享基础设施关键词（如认证、权限、配置、路由、共享 schema、layout/app 壳层）

3. 记录当前分支和 SHA 为并行基准：
   ```bash
   PARALLEL_BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
   PARALLEL_BASE_SHA=$(git rev-parse HEAD)
   ```
4. 为每个并行提案创建 worktree：
   ```bash
   git worktree add -b pipeline/proposal-<id> \
     ".worktrees/proposal-<id>" "$PARALLEL_BASE_SHA"
   ```
5. 初始化每个提案的独立 pipeline 状态：
   - 在每个 worktree 中创建 `.pipeline/state-<id>.json`（独立 pipeline_id、attempt_counts 等）
   - 将所有并行提案 `status` 改为 `"running"`
6. 写入 `state.json` 的新字段：
   ```json
   {
      "parallel_proposals": ["P-002", "P-003"],
      "parallel_base_sha": "<SHA>",
      "parallel_base_branch": "<branch>",
      "parallel_worktrees": {"P-002": "<abs-path>", "P-003": "<abs-path>"},
      "parallel_branches": {"P-002": "pipeline/proposal-P-002", ...},
      "parallel_merge_order": ["P-002", "P-003"],
      "parallel_completed": [],
      "parallel_precheck_report": ".pipeline/artifacts/parallel-proposal-report.json"
   }
   ```
7. **并行执行**：在同一条响应中为每个并行提案发起独立的 Agent tool call：
   ```
   spawn: pilot（自身递归）
   cwd: <parallel_worktrees["P-NNN"]>
   PIPELINE_DIR: <worktree>/.pipeline
   PROPOSAL_ID: P-NNN
   MODE: parallel-child
   ```
   每个子 pilot 独立完成该提案的全部阶段（0.clarify → 7.monitor），使用 `state-<id>.json` 跟踪状态。
8. 所有并行提案完成后，进入**提案合并序列**（见下方）。

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

在 0.clarify 之前执行。通过 AutoStep 脚本按 tier/domain 分层过滤约束：

run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/memory-load.sh

输出: `.pipeline/artifacts/memory-injection.txt`

1. 文件不存在或无 running 提案 → SKIP，直接进入 0.clarify
2. PASS → Pilot 读取 `memory-injection.txt` 全文，作为 0.clarify Clarifier 和 1.design Architect 的 spawn 消息最前方内容
3. 其他阶段不注入项目记忆（通过 artifacts 文件传递信息）

**过滤规则**：
- `tier: 1`（或缺少 tier 字段）：全局约束，每次必注入
- `tier: 2`：领域约束，仅当约束的 `domain` 匹配当前提案时注入
- 匹配策略：proposal 的 `domains` 字段（显式声明）+ `scope` 文本匹配取并集

> `micro-change` 不直接注入 Clarifier / Architect。只有在后续 Memory Consolidation 中被提炼为长期约束后，才会通过 `project-memory.json` 间接生效。

---

## Non-Proposal Change Triage — 非提案变更分流

当用户提出的请求未进入正式 proposal 队列时，Pilot 仍必须先做变更分流，判断这是纯实现性调整、可直接落地的业务小改，还是必须升级为 proposal 的系统变更。

### 分类结果

Pilot 对每个请求只能输出以下三类之一：

1. `implementation-only`
   - 不改变业务语义
   - 典型场景：重构、样式微调、文案修正、测试补充、日志优化、代码清理
   - 处理方式：直接执行实现，不生成需求记录
2. `business-small-change`
   - 改变业务语义，但仍能在单次小改中安全完成
   - 典型场景：默认值调整、单模块权限限制、单流程通知规则变化、单模块状态规则调整
   - 处理方式：先记录 `micro-change`，再执行实现
3. `proposal-needed`
   - 已触及系统边界、契约边界、数据边界、权限边界，或明显需要设计拆解
   - 处理方式：升级为 proposal，进入正式 `requirement.md -> design -> build -> test -> memory` 主流程

### 硬升级条件

若命中以下任一项，Pilot 必须直接判定为 `proposal-needed`，不得按小改处理：

- API contract 变更
- 数据库 schema / migration 变更
- 涉及两个及以上业务 domain
- 涉及支付、计费、风控、合规、安全边界
- 涉及权限体系重构，而非单点规则
- 涉及核心状态机、审批流、跨模块自动化流程改造
- 需要多个 builder 角色协作才能完成
- 用户输入过于模糊，无法在不补充完整需求的情况下安全实现
- 明显需要 Architect 先完成方案设计

### 轻量评分规则

仅在未命中“硬升级条件”时使用轻量评分：

- 默认值、阈值、校验规则变化：+1
- 用户可见行为变化：+1
- 单模块权限规则变化：+1
- 通知语义或触发条件变化：+1
- 单模块状态流转变化：+1
- 会形成长期规则：+1
- 影响多个页面、组件或入口：+1
- 需要补充验收口径才能避免歧义：+1

评分结果：

- 0 分：`implementation-only`
- 1-2 分：`business-small-change`
- 3 分及以上：`proposal-needed`

### micro-change 记录要求

当请求被判定为 `business-small-change` 时，Pilot 必须将用户原话归一化为一条最小需求事实，并写入 `.pipeline/micro-changes.json`。

推荐调用方式：

```bash
PIPELINE_DIR=.pipeline bash .pipeline/autosteps/record-micro-change.sh \
  --raw "<用户原话>" \
  --normalized "<归一化描述>" \
  --domain "<领域，可重复>" \
  --memory-candidate true|false \
  --constraint "<长期规则候选，可选>"
```

推荐字段：

- `id`
- `date`
- `source`
- `raw_request`
- `normalized_change`
- `domains`
- `kind`
- `memory_candidate`
- `proposed_constraint`
- `status`
- `related_files`
- `related_commit`
- `consumed_by_memory`

即使用户只有一句话，也必须保留 `raw_request` 并补全 `normalized_change`。默认 `source="chat"`，`status="recorded"`。

### 长期规则判定

并非每条 `micro-change` 都需要进入 `project-memory.json`。只有当该小改表达长期稳定、可复用、会约束后续实现的业务或架构规则时，才可标记为 `memory_candidate=true`。

典型长期规则信号：

- 必须
- 统一
- 默认
- 禁止
- 仅允许
- 上限 / 下限
- 超时
- 重试
- 权限限制

典型非长期规则信号：

- 临时先这样
- 本次调整
- 视觉优化
- 文案润色
- 页面局部微调

### 与项目记忆的关系

- `micro-change` 是轻量事实层，不直接注入 Clarifier / Architect
- `project-memory.json` 是长期约束层，只接收经确认或提炼后的稳定规则
- `proposal` 仍是完整交付层，不与 `micro-change` 混用

---

## 0.clarify — Clarifier（需求澄清）
```
spawn: clarifier
input: 用户原始需求文本
output: .pipeline/artifacts/requirement.md
```
**交互模式**（`autonomous_mode = false`）：Clarifier 最多 5 轮澄清（每轮暂停展示问题给用户，等待用户回答后传回）。
**自治模式**（`autonomous_mode = true`）：**不 spawn Clarifier**。Pilot 直接将提案 detail 字段转写为 requirement.md（章节映射：user_stories→用户故事，business_rules→业务规则，acceptance_criteria→验收标准，api_overview→API概览，data_entities→数据实体，non_functional→非功能需求）。不确定项标注 `[ASSUMED]`。
完成后检查 requirement.md 存在且非空。

---

## 0.5.requirement-check — Requirement Completeness Checker（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/requirement-completeness-checker.sh
output: .pipeline/artifacts/requirement-completeness-report.json
```
读取报告 `overall` 字段：
- `PASS` → 进入 1.design
- `FAIL` → 递增 0.clarify attempt，rollback_to: 0.clarify（提示 Clarifier 补充缺失内容）

---

## 1.design — Architect（方案设计）

```
spawn: architect
input: requirement.md
output: .pipeline/artifacts/proposal.md, .pipeline/artifacts/adr-draft.md
```
验证 proposal.md 和 adr-draft.md 均存在且非空。

---

## gate-a.design-review — Auditor 校验（方案审核）

```
spawn: auditor-gate
input: requirement.md + proposal.md
output: .pipeline/artifacts/gate-a.design-review.json
```
矛盾检测 → 读取 overall：
- `PASS` → 解析 proposal.md 激活条件角色，按以下映射写入 state.json：
  - `data_migration_required: true` → `state.json.conditional_agents.migrator = true`
  - `performance_sensitive: true` → `state.json.conditional_agents.optimizer = true`
  - `i18n_required: true` → `state.json.conditional_agents.translator = true`
  - 若 proposal.md 中无对应字段，保持 `false`（默认值）
  进入 2.0a.repo-setup
- `FAIL` → rollback_to（取最深目标）

---

## 2.0a.repo-setup — GitHub Repo Creator（github-ops Agent）

```
spawn: github-ops
scenario: create_repo
input: config.json + proposal.md
output: .pipeline/artifacts/github-repo-info.json
```
读取 `github-repo-info.json` 中 `overall`：
- `PASS` → 写入 state.json `github_repo_created: true`、`github_repo_url: <url>`，进入 2.0b.depend-collect
- `CANCELLED` → 写入 state.json `github_repo_created: false`，进入 2.0b.depend-collect（后续 push 跳过）
- `FAIL` → ESCALATION

---

## 2.0b.depend-collect — Depend Collector（AutoStep + 暂停）
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
    等待用户输入"继续"后进入 2.plan。
  - **自治模式**（`autonomous_mode = true`）→ **不暂停**，输出 `[WARN] 自治模式：跳过凭证填写等待（unfilled: <列表>），部署阶段可能失败`，直接进入 2.plan。
- 空（所有依赖凭证已填写或无外部依赖）→ 直接进入 2.plan。

---

## 2.plan — Planner（任务细化）

```
spawn: planner
input: proposal.md + requirement.md
output: .pipeline/artifacts/tasks.json
```

---

## 2.1.assumption-check — Assumption Propagation Validator（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/assumption-propagation-validator.sh
output: .pipeline/artifacts/assumption-propagation-report.json
```
结果附加给 gate-b.plan-review Auditor-Biz（WARN 不阻断，仅信息传递）。

---

## gate-b.plan-review — Auditor 校验（任务细化审核）

```
spawn: auditor-gate
input: proposal.md + tasks.json + assumption-propagation-report.json
output: .pipeline/artifacts/gate-b.plan-review.json
```

---

## 2.5.contract-formalize — Contract Formalizer（契约形式化）

```
spawn: contract-formalizer
input: tasks.json
output: .pipeline/artifacts/contracts/ 目录
```

---

## 2.6.contract-validate-semantic + 2.7.contract-validate-schema — 契约验证（并行 AutoStep）

> **并行执行**：2.6.contract-validate-semantic 和 2.7.contract-validate-schema 无依赖关系，**必须**在同一条响应中发起两个 Bash tool call 并行执行。

**2.6.contract-validate-semantic — Schema Completeness Validator**
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/schema-completeness-validator.sh
output: .pipeline/artifacts/schema-validation-report.json
```

**2.7.contract-validate-schema — Contract Semantic Validator**
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/contract-semantic-validator.sh
output: .pipeline/artifacts/contract-semantic-report.json
```

**结果处理**：等待两者全部完成后判断——任一 FAIL → rollback_to: 2.5.contract-formalize

---

## 3.build — 并行实现（Worktree 隔离）

### 3.build Step 0 — Worktree 初始化（3.build 内部步骤，无独立路由条目）

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

3. 初始化运行态字段：
   - `phase_3_worktrees = {}`
   - `phase_3_branches = {}`
   - `phase_3_wave_bases = {}`
   - `phase_3_conflict_files = []`

4. **不要在 Step 0 一次性创建所有 Builder worktree。**
   - worktree 必须在每个波次/子波次开始前，基于**当时最新 HEAD**创建
   - 后续波次不得继续复用初始 `BASE_SHA`
   - 这是强制规则；否则 Backend/Frontend/Infra 会在旧基线上开发，导致后续合并冲突频发

### 3.build — Builder 调度（波次内并行）

> **并行执行**：同一波次内仅当文件集合无重叠时，才允许在同一条响应中发起多个 Agent tool call 并行执行。若同波次存在文件重叠，必须拆为串行子波次，并让后执行 Builder 基于前者合并后的最新 HEAD 继续实现。

按以下波次 spawn，每波内并行，波间顺序：
- 波次 1（**并行**）：DBA ∥ Migrator（条件）
- 波次 2：Backend
- 波次 3（**并行**）：Security ∥ Frontend
- 波次 4（**并行**）：Infra（依赖 Security）∥ Translator（条件，依赖 Frontend）

#### Step 1 — 波次内文件冲突检测（强制）

对每个波次，在创建 worktree 前必须执行：

```bash
PIPELINE_DIR=.pipeline BUILDERS="<comma-separated-builders>" \
  python3 .pipeline/autosteps/build-conflict-detector.py
```

读取 `.pipeline/artifacts/build-conflict-report.json`：

- `overall = "PASS"` 且 `overlap_paths = []` → 本波次允许并行
- `overall = "OVERLAP"` → 本波次必须拆成**串行子波次**
- `overall = "ERROR"` 或脚本 exit != 0 → ESCALATION

写入 state.json：
- `phase_3_conflict_files` = `overlap_paths`
- `phase_3_wave_bases["wave-<n>"]` = 当前 `git rev-parse HEAD`

#### Step 2 — 为当前波次/子波次创建 worktree（基于最新 HEAD）

设 `CURRENT_BASE=$(git rev-parse HEAD)`。

- 若当前波次无文件重叠：为本波次全部 Builder 创建 worktree
- 若当前波次有文件重叠：按 `phase_3_merge_order` 中的先后顺序，把该波次拆成单 Builder 子波次；每个子波次开始前都重新读取 `CURRENT_BASE`

创建方式：

```bash
git worktree add -b pipeline/3.build/builder-<name> \
  "$(pwd)/.worktrees/builder-<name>" "$CURRENT_BASE"
```

写入 state.json：`phase_3_worktrees["<name>"]` = 绝对路径, `phase_3_branches["<name>"]` = 分支名, `phase_3_wave_bases["<name>"]` = `CURRENT_BASE`

`git worktree list` 确认当前子波次所需 worktree 创建成功。

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
2. `git log pipeline/3.build/builder-<name> --oneline -1` 有 3.build 的 commit

每个 Builder 输出 `$PIPELINE_DIR/artifacts/impl-manifest-<builder>.json`。

#### Step 3 — 当前波次/子波次立即合并（强制）

当前波次/子波次完成后，**必须立刻合并到主分支**，然后下一波次/子波次才能开始。禁止所有 Builder 全部做完后再统一合并。

### 3.build — 合并序列（逐波次）

对当前波次/子波次中的 Builder，按 `phase_3_merge_order` 顺序执行：

```bash
git checkout "$MAIN_BRANCH"
for BUILDER in current_wave_builders:
  BRANCH="pipeline/3.build/builder-$BUILDER"
  # 干跑检测
  if ! git merge --no-commit --no-ff "$BRANCH" 2>/dev/null; then
    git merge --abort 2>/dev/null || true
    → ESCALATION：合并冲突，保留 .worktrees/builder-$BUILDER 供人工解决
    → 输出人工恢复指令（见 CLAUDE.md），status: escalation，停止
  fi
  git merge --abort 2>/dev/null || true
  git merge --no-ff "$BRANCH" -m "merge: 3.build builder-$BUILDER"
  NEW_SHA=$(git rev-parse HEAD)
  # 每合入一个 Builder，都要刷新 phase_3_base_sha，供后续 Builder 使用
```

合并成功后，立即写回 state.json：`phase_3_base_sha = NEW_SHA`

#### Step 4 — 当前波次/子波次清理

**合并成功后立即清理当前 Builder worktree，不等待全部波次结束**：

```bash
for BUILDER in current_wave_builders:
  git worktree remove ".worktrees/builder-$BUILDER" --force
  git branch -d "pipeline/3.build/builder-$BUILDER"
  # 删除 state.json 中 phase_3_worktrees / phase_3_branches 对应 key
```

全部波次完成后再执行：

```bash
rmdir .worktrees 2>/dev/null || true
```

**清理验证（强制）**：
```bash
# 验证所有 Builder worktree 已清理
REMAINING=$(git worktree list | grep -c "pipeline/3.build/" || echo 0)
if [ "$REMAINING" -gt 0 ]; then
  echo "[ERROR] Worktree 清理不完整，仍有 $REMAINING 个残余："
  git worktree list | grep "pipeline/3.build/"
  echo "请手动执行：git worktree remove .worktrees/builder-<name> --force"
  → ESCALATION：Worktree 清理失败，需人工介入后重启
  → 写入索引最终状态 status: escalation，停止流水线
fi
echo "✅ 所有 Builder worktree 已清理"
```

#### Step 5 — 全部波次完成后再合并 impl-manifest

**合并 impl-manifest**（AutoStep）：
```
PIPELINE_DIR=.pipeline bash .pipeline/autosteps/impl-manifest-merger.sh
```
若 exit ≠ 0：ESCALATION，停止流水线

---

## 3.0b.build-verify — Build Verifier（AutoStep）

在所有 Builder 代码合并完成后、进入静态分析之前，强制执行两阶段编译验证。这是防止 gate-c.code-review 独立性失效的关键屏障。

**两阶段验证：**
1. **生产编译**：`cargo build --release` / `go build ./...` / `npm run build`
2. **测试编译**（生产编译 PASS 后才运行）：`cargo test --no-run` / `go test -run='^$' ./...` / `npx tsc --noEmit`

测试编译失败同样视为 Builder 责任，回滚至 3.build。

```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/build-verifier.sh
output: .pipeline/artifacts/build-verifier-report.json
```
读取报告 `overall` 字段：
- `PASS` → 继续进入 3.1.static-analyze
- `FAIL` → rollback_to: 3.build（按原 Builder 任务重新实现，**Pilot 不得自行修复 Builder 代码**）

⚠️ **重要约束**：Build Verifier FAIL 时，Pilot **必须** rollback 委托给对应 Builder 重新实现，**禁止** Pilot 直接修改源代码绕过编译错误。

### 回滚清理（rollback_to: 3.build 时）

重进 3.build.0 前执行：
```bash
for BUILDER in phase_3_worktrees（若非空）:
  git worktree remove ".worktrees/builder-$BUILDER" --force 2>/dev/null || true
  git branch -D "pipeline/3.build/builder-$BUILDER" 2>/dev/null || true
rm -rf .worktrees 2>/dev/null || true

# 移除上一轮 Tester 新增的测试文件（避免 Regression Guard 误报）
for TEST_FILE in state.json.new_test_files（若非空）:
  git rm "$TEST_FILE" 2>/dev/null || true
git commit -m "chore: remove new_test_files before 3.build retry" --allow-empty 2>/dev/null || true

# 重置 state.json
phase_3_worktrees = {}; phase_3_branches = {}
phase_3_base_sha = null; phase_3_main_branch = null
new_test_files = []
```

---

## 3.0d.duplicate-detect + 3.1.static-analyze + 3.2.diff-validate + 3.3.regression-guard — 构建后分析（并行 AutoStep）

> **并行执行**：这四个分析步骤无依赖关系，**必须**在同一条响应中发起四个 Bash tool call 并行执行。

**3.0d.duplicate-detect — Duplicate Detector**
```
run: MODE="incremental" PIPELINE_DIR=".pipeline" bash .pipeline/autosteps/duplicate-detector.sh
```
FAIL → WARN（非阻塞，不触发回滚）

**3.1.static-analyze — Static Analyzer**
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/static-analyzer.sh
```
FAIL → rollback_to: 3.build（**阻断级**）

**3.2.diff-validate — Diff Scope Validator**
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/diff-scope-validator.sh
```
FAIL → WARN（非阻塞，未授权变更信息记录在 `scope-validation-report.json` 中供 gate-c.code-review Inspector 参考）

**3.3.regression-guard — Regression Guard**
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/regression-guard.sh
```
FAIL → WARN（非阻塞，回归测试失败信息记录在 `regression-report.json` 中供 gate-c.code-review 参考。new_test_files 排除在外）

**结果处理**：等待四者全部完成后统一判断——3.1.static-analyze FAIL → rollback_to: 3.build；其余 FAIL 仅记录 WARN 日志。全部处理完毕后进入 3.5.simplify。

---

## 3.5.simplify — Simplifier

```
spawn: simplifier
input: static-analysis-report.json + 代码
output: .pipeline/artifacts/simplify-report.md
```
验证 simplify-report.md 修改时间 > impl-manifest.json 修改时间。

---

## 3.6.simplify-verify — Post-Simplification Verifier（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/post-simplification-verifier.sh
```
FAIL → rollback_to: 3.5.simplify

---

## gate-c.code-review — Inspector（代码审查）

```
spawn: inspector
input: 代码 + 所有 3.build 报告
output: .pipeline/artifacts/gate-c.code-review.json
```
Inspector 调用前，Pilot 在 spawn 消息中追加 `simplifier_verified: true`（当 3.6.simplify-verify Post-Simplification Verifier PASS 时）或 `simplifier_verified: false`（当 3.6.simplify-verify 未执行或 FAIL 时）。此字段通过 spawn 消息传递，不存储在 state.json 或独立文件中。
FAIL → rollback_to: 3.build（先进入 Resolver 驱动的修复入口；Resolver 成功后重新经过 3.0b→3.1→3.2→3.3→3.5→3.6→gate-c.code-review）
1. 激活 Resolver 修复 Inspector 报告的 CRITICAL/MAJOR 问题（Resolver 直接在主分支上提交修复）。
   - 这一入口是 `gate-c` 派生出的“Resolver 修复轮次”，不是普通 Builder 重做轮次。
   - 因此在 Resolver 已接管、且尚未判定需要真正重开 Builder worktree 之前，**不得递增 `attempt_counts["3.build"]`**，也不得因主工作区存在 Resolver 产生的未提交改动而直接按普通 3.build 脏工作区规则进入 ESCALATION。
   - 只有当 Resolver 明确要求回到真实 Builder 重做（例如回退到 `3.build` 且需要重新起 worktree）时，才按普通 3.build 重试语义计数。
2. Resolver 完成后，**必须更新 `phase_3_base_sha`，并将当前审查轮次涉及的后处理阶段计数统一重置为 0**（Bug #15 修复 + 重试计数修复）：
   ```bash
   NEW_SHA=$(git rev-parse HEAD)
   python3 -c "
   import json
   s = json.load(open('.pipeline/state.json'))
   s['phase_3_base_sha'] = '$NEW_SHA'
    attempts = s.setdefault('attempt_counts', {})
    for key in [
        '3.0b.build-verify',
        '3.0d.duplicate-detect',
        '3.1.static-analyze',
        '3.2.diff-validate',
        '3.3.regression-guard',
        '3.5.simplify',
        '3.6.simplify-verify',
        'gate-c.code-review',
    ]:
        attempts[key] = 0
    json.dump(s, open('.pipeline/state.json', 'w'), indent=2)
    "
   ```
   此更新确保后续 3.2.diff-validate Diff Scope Validator 以 Resolver 修复后的 HEAD 为基准，避免将 Resolver 合法修复误报为未授权变更；同时避免 `3.0b.build-verify → 3.6.simplify-verify → gate-c.code-review` 这整条复审链在 Resolver 已产出有效修复时，因重新进站被重复累计到超 max_attempts 而误触发 ESCALATION。
3. 重新运行 3.0b.build-verify → 3.1 → 3.2 → 3.3 → 3.5 → 3.6 → gate-c.code-review。

**Resolver 退出条件**：
- Resolver 成功修复所有 CRITICAL/MAJOR 问题 → 更新 `phase_3_base_sha`，重置当前复审链 `3.0b/3.0d/3.1/3.2/3.3/3.5/3.6/gate-c` 的 `attempt_counts` 为 `0`，重新进入 3.0b.build-verify
- Resolver 修复不完整（仍有 CRITICAL/MAJOR 问题，或未形成可验证进展）→ 计入 `gate-c.code-review` attempt_count，超过 max_attempts 时 ESCALATION
- Resolver 判断问题需重新分配/重做 Builder 实现 → 保持 `rollback_to: 3.build`，此时才进入普通 3.build 重试语义并递增 `attempt_counts["3.build"]`
- Resolver 判断问题需架构变更（超出 3.build 范围）→ 输出 `rollback_to: 1.design`，Pilot 执行深度回滚


---

## 3.7.contract-compliance — Contract Compliance Checker（AutoStep）

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

FAIL → rollback_to: 3.build（对应 Builder）

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

## 4a.test — Tester（功能测试）

```
spawn: tester
input: tasks.json + impl-manifest.json
output: .pipeline/artifacts/test-report.json, .pipeline/artifacts/coverage.lcov
```
FAIL → 运行 4a.1.test-failure-map（Test Failure Mapper）

**new_test_files 写入**：Tester 完成后，Pilot 从 `test-report.json` 或 Tester 的 `state.json.new_test_files` 更新中读取新增测试文件路径列表。此列表的生命周期为：
- 3.3.regression-guard Regression Guard：排除 `new_test_files` 中的文件（避免对未毕业的新测试做回归）
- 4a.test Tester：**写入** `state.json.new_test_files`（当前运行新增的测试文件）
- 7.monitor Monitor NORMAL：**毕业**，将 `new_test_files` 条目迁移到 `regression-suite-manifest.json`，然后清空 `new_test_files`

---

## 4a.1.test-failure-map — Test Failure Mapper（AutoStep，仅 4a.test FAIL 时）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/test-failure-mapper.sh
output: .pipeline/artifacts/failure-builder-map.json
```
读取 `confidence` 字段：
- `HIGH` → 精确回退（仅 builders_to_rollback 中的 builder）
- `LOW` → 保守全体回退 3.build

---

## 4.2.coverage-check — Test Coverage Enforcer（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/test-coverage-enforcer.sh
```
FAIL → rollback_to: 4a.test

PASS 后条件跳转：读取 `state.json.conditional_agents.optimizer`，若为 `true` → 进入 4b.optimize；若为 `false` → 跳过 4b.optimize，直接进入 gate-d.test-review。

---

## 4b.optimize — Optimizer（条件角色，仅 performance_sensitive: true）

```
spawn: optimizer
input: test-report.json + impl-manifest.json
output: .pipeline/artifacts/perf-report.json
```
`perf-report.json` 中 `sla_violated: true` → 直接 rollback_to: 3.build（不等 gate-d.test-review）。

---

## gate-d.test-review — Auditor-QA（测试验收）

```
spawn: auditor-qa
input: test-report.json + coverage-report.json + perf-report.json（如有）
output: .pipeline/artifacts/gate-d.test-review.json（含结构化 rollback_to 字段）
```
FAIL → rollback_to（限制：不超过 2.plan，只能 4a.test 或 3.build）

---

## API Change Detector — api-change-detect（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/api-change-detect.sh
output: .pipeline/artifacts/api-change-report.json
```
写入 state.json: `phase_5_mode`（`full` 或 `changelog_only`）

---

## 5.document — Documenter（文档）

```
spawn: documenter
input: api-change-report.json + adr-draft.md + impl-manifest.json
output: .pipeline/artifacts/doc-manifest.json
```
如 `phase_5_mode: changelog_only`，仅更新 CHANGELOG，跳过 API 文档更新。

---

## 5.1.changelog-check — Changelog Consistency Checker（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/changelog-consistency-checker.sh
```
FAIL → rollback_to: 5.document

---

## gate-e.doc-review — Auditor-QA + Auditor-Tech（文档审核，并行）

> **并行执行**：auditor-qa 和 auditor-tech **必须**在同一条响应中发起两个 Agent tool call 并行执行。

```
spawn: auditor-qa ∥ auditor-tech
input: doc-manifest.json + API 文档 + CHANGELOG + ADR
output: .pipeline/artifacts/gate-e.doc-review.json
```
**结果处理**：等待两者全部完成后合并审核结论。任一 FAIL → rollback_to: 5.document；两者 rollback 目标不同时取最深。

---

## 5.9.ci-push — GitHub Woodpecker Push（github-ops Agent）

仅在 `state.json.github_repo_created = true` 时执行；否则跳过，直接进入 6.0.deploy-readiness。

```
spawn: github-ops
scenario: push_woodpecker
input: .woodpecker/ 目录 + github-repo-info.json
```
FAIL → WARN（不阻断，记录日志后继续 6.0.deploy-readiness）

---

## 6.0.deploy-readiness — Pre-Deploy Readiness Check（AutoStep）
```
run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/pre-deploy-readiness-check.sh
```
FAIL → **ESCALATION**（不自动回退，请求人工介入）

---

## 6.deploy — Deployer（部署）

```
spawn: deployer
input: deploy-plan.md + state.json
output: .pipeline/artifacts/deploy-report.json
```
FAIL：读取 `deploy-report.json` 中 `failure_type`：
- `deployment_failed` → rollback_to: 3.build
- `smoke_test_failed` → 激活 Deployer 执行生产回滚，然后 rollback_to: 1.design

---

## 7.monitor — Monitor（上线观测）

```
spawn: monitor
input: deploy-report.json + config.json 阈值
output: .pipeline/artifacts/monitor-report.json
```
读取 `status` 字段：
- `NORMAL` → 写入 state.json `status: COMPLETED`，执行测试文件毕业（new_test_files → regression-suite-manifest.json）
- `ALERT` → Pilot 分析 `monitor-report.json` 中 `alert_details` 定位受影响模块，映射到对应 Builder，rollback_to: 3.build（精确重跑受影响 Builder）
- `CRITICAL` → 激活 Deployer 执行生产回滚 → rollback_to: 1.design

---

## Memory Consolidation — 项目记忆固化

7.monitor 返回 NORMAL 后执行。

### Step 1 — 提取候选约束
读取 `requirement.md`、`proposal.md`、`adr-draft.md`，提取 **MUST / MUST NOT / 必须 / 禁止 / 统一 / 限制** 形式的约束句。

若 `.pipeline/micro-changes.json` 存在，还应追加读取其中满足以下条件的记录作为轻量候选约束来源：

- `memory_candidate = true`
- `consumed_by_memory = false`
- `status = "recorded"`

优先使用 `proposed_constraint` 作为候选约束文本；若缺失，则由 `normalized_change` 提炼为约束句。

若存在满足条件的 `micro-change` 记录，Pilot 在 Memory Consolidation 的 Step 1 必须先调用：

```bash
PIPELINE_DIR=.pipeline bash .pipeline/autosteps/sync-micro-changes-to-memory.sh
```

该脚本会将新增或重复候选标记为 `consumed_by_memory=true`，并产出 `.pipeline/artifacts/micro-change-sync-report.json`。若脚本输出 `SKIP`，再继续后续 Step 2；若输出 `PASS`，则将新增约束视为已纳入本次 consolidation 输入。

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
| 0.clarify | `docs: add requirement specification` |
| 1.design | `docs: add architecture proposal and ADRs` |
| gate-a.design-review | `ci: gate-a.design-review passed` |
| 2.plan | `docs: add task breakdown (N tasks, M builders)` |
| 2.5.contract-formalize | `docs: add OpenAPI contracts for N services` |
| gate-b.plan-review | `ci: gate-b.plan-review passed` |
| 3.build | `feat(builder-<name>): implement <service-name>` |
| 3.5.simplify | `refactor: simplify implementation per static analysis` |
| gate-c.code-review | `ci: gate-c.code-review passed` |
| 4a.test | `test: add test suite (N cases, M passed)` |
| gate-d.test-review | `ci: gate-d.test-review passed` |
| 5.document | `docs: add README, CHANGELOG and API documentation` |
| gate-e.doc-review | `ci: gate-e.doc-review passed` |
| 6.deploy | `chore: add deployment configuration and woodpecker pipelines` |

括号内变量从对应产物文件读取真实值。

## 附录 B — state.json 完整 Schema

```json
{
  "pipeline_id": "pipe-YYYYMMDD-001",
  "project_name": "PROJECT",
  "current_phase": "0.clarify",
  "last_completed_phase": null,
  "status": "running",
  "attempt_counts": {
    "0.clarify": 0, "0.5.requirement-check": 0, "1.design": 0, "gate-a.design-review": 0,
    "2.0a.repo-setup": 0, "2.0b.depend-collect": 0, "2.plan": 0, "2.1.assumption-check": 0, "gate-b.plan-review": 0,
    "2.5.contract-formalize": 0, "2.6.contract-validate-semantic": 0, "2.7.contract-validate-schema": 0,
    "3.build": 0, "3.0b.build-verify": 0, "3.1.static-analyze": 0, "3.2.diff-validate": 0, "3.3.regression-guard": 0,
    "3.5.simplify": 0, "3.6.simplify-verify": 0, "gate-c.code-review": 0, "3.7.contract-compliance": 0,
    "4a.test": 0, "4a.1.test-failure-map": 0, "4.2.coverage-check": 0, "4b.optimize": 0,
    "gate-d.test-review": 0, "api-change-detect": 0,
    "5.document": 0, "5.1.changelog-check": 0, "gate-e.doc-review": 0, "5.9.ci-push": 0,
    "6.0.deploy-readiness": 0, "6.deploy": 0, "7.monitor": 0,
    "per_builder": {}
  },
  "conditional_agents": { "migrator": false, "optimizer": false, "translator": false },
  "phase_5_mode": "full",
  "new_test_files": [],
  "phase_3_base_sha": null,
  "phase_3_worktrees": {},
  "phase_3_branches": {},
  "phase_3_wave_bases": {},
  "phase_3_conflict_files": [],
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
      "parallel_completed": [],
      "parallel_precheck_report": null
    }
```

---
