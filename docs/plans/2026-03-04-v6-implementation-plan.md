# v6 漏洞修复 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 `docs/plans/2026-03-04-v6-design.md` 中定义的 7 个漏洞修复（Q~W），逐节写入 `claude-code-multi-agent-team-design.md`，使该主文档升级为 v6 版本。

**Architecture:** 本计划为纯文档编辑，目标文件为单一 Markdown 文件（当前 2690 行）。所有改动均为精准的 Edit 操作，按文档章节顺序从前往后执行，避免行号漂移干扰。每个 Task 完成后单独 commit。

**Tech Stack:** Markdown 编辑（Read + Grep + Edit 工具）、git commit

**参考文档:** `docs/plans/2026-03-04-v6-design.md`（每个 Task 的改动内容均来自此文件）

---

### Task 1：在文档顶部新增 v6 核心改进说明

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（第 40-49 行，v5 改进块末尾之后）

**Step 1: 定位插入点**

Grep `新增 Phase 4a.1 Test Failure Mapper` 找到 v5 最后一行，记录行号。

**Step 2: 在 v5 块末尾之后插入 v6 改进块**

在以下文字之后：
```
- 新增 Phase 4a.1 Test Failure Mapper（AutoStep）：测试失败后精确映射责任 Builder，降低多 Builder 场景下的无辜回退成本
```

插入：

```markdown

**v6 核心改进（基于逻辑漏洞分析）：**
- 修复漏洞 Q：Resolver conditions 字段升级为结构化 conditions_checklist，Pilot 在放行前机械验证每条条件是否满足，杜绝 Resolver 条件承诺成空话
- 修复漏洞 R：Phase 4a.1 Test Failure Mapper 流转规则新增 confidence 维度，LOW confidence 映射触发保守全体回退，防止不确定归属导致无辜 Builder 被精确回退
- 修复漏洞 S（高危）：Phase 0.5 Section 标题检查从 H2 修正为 H3（在 `## 最终需求定义` 下查找 `### 功能描述` 等子节），修复对所有合法 requirement.md 永远输出 FAIL 的严重错误
- 修复漏洞 T：Gate D 产物 gate-d-review.json 补充结构化 rollback_to 字段，与 Gate A / Gate C 一致，Pilot 可机械解析回退目标
- 修复漏洞 U：new_test_files 的 Regression Guard 排除规则扩展为覆盖所有 Phase 3 回退路径（不限于 Phase 4a FAIL），统一全生命周期语义
- 修复漏洞 V：Phase 4a 产物列表新增 coverage.lcov（必须生成），消除 Phase 4a.1 对覆盖率数据的隐式依赖；config.json 新增 testing 配置块
- 修复漏洞 W：state.json schema 补充 phase_5_mode 和 new_test_files 字段定义，明确写入时机，修复崩溃恢复时这两个关键字段丢失的问题
```

**Step 3: 验证**

Read 文件第 40-60 行，确认 v6 块在 v5 块之后，格式缩进与 v2/v3/v4/v5 块一致。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add v6 summary header to design document"
```

---

### Task 2：Section 2.4 新增 conditions_checklist 说明（漏洞 Q）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 2.4，Resolver 激活逻辑末尾）

**Step 1: 定位插入点**

Grep `Resolver 可将深层回退升浅，但不能完全消除回退` 找到 Rollback Depth Rule 说明末尾，在该段落后（即 `### 2.5 问题域划分` 之前）插入新段落。

**Step 2: 插入内容**

在 `Resolver 可将深层回退升浅，但不能完全消除回退。` 之后、`### 2.5 问题域划分` 之前，插入：

```markdown

**Resolver conditions_checklist 机械执行（v6 新增）：**

当 Resolver 仲裁结果为 PASS 且附有执行条件时，须在 `resolver_verdict` 中提供结构化的 `conditions_checklist` 数组，而非纯文本 `conditions` 字符串。Pilot 在推进到下一阶段前，逐条机械验证每个条件：

| 字段 | 说明 |
|------|------|
| `target_agent` | 需要执行此条件的 Agent 名称 |
| `target_phase` | 回退到该 Phase 让 Agent 按条件重新处理 |
| `requirement` | 可读说明（供 Agent 参考，非机械验证目标） |
| `verification_method` | `grep`（关键词搜索）/ `exists`（文件存在）/ `field_value`（JSON 字段比对） |
| `verification_pattern` | grep 的正则表达式，或 field_value 的期望值 |
| `verification_file` | 被验证的文件路径 |

**Pilot 条件验证流程：**
1. 通知 `target_agent` 重新处理（携带 `conditions_checklist` 作为约束输入）。
2. Agent 完成后，Pilot 逐条执行 `verification_method` 机械检查。
3. 全部通过 → 写入 `resolver-conditions-check.json`（`overall: PASS`），推进到下一阶段。
4. 任意失败 → `overall: FAIL`，回退到 `target_phase`，日志记录 `[WARN] Resolver 条件未满足：<requirement>`。

若 `conditions_checklist` 为空数组，跳过验证直接推进（兼容无附加条件的 PASS 仲裁）。
```

**Step 3: 验证**

Read 修改后区域，确认新段落位于 Rollback Depth Rule 说明之后、Section 2.5 之前，格式正确。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add conditions_checklist to Resolver mechanism (v6 fix漏洞Q)"
```

---

### Task 3：Phase 0.5 修复 Section 标题检查逻辑（漏洞 S，高危）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Phase 0.5 章节，Section 5）

**Step 1: 定位 Phase 0.5 章节**

Grep `### Phase 0\.5：需求完整性校验` 找到章节起始行。Read 该章节全文（约 45 行）。

**Step 2: 替换执行内容第 1 条**

找到当前文本：
```
1. **必填 Section 检查**：验证 requirement.md 包含以下 Section 标题且内容非空：
   - `## 功能描述`
   - `## 用户故事`
   - `## 验收标准`
   - `## 范围边界`
```

替换为：
```
1. **必填 Section 检查**：首先定位 `## 最终需求定义`（H2 标题），提取该节下所有内容（到下一个 H2 或文件末尾）；在提取内容中查找以下 H3 子节标题（使用前缀匹配，允许标题后有括号补充说明）：
   - `### 功能描述`
   - `### 用户故事`
   - `### 业务规则`
   - `### 范围边界`（前缀匹配，兼容"范围边界（包含 / 不包含）"）
   - `### 验收标准`

   以上 5 个 H3 子节全部存在且内容非空 → `sections_check.overall: PASS`；任意缺失 → `FAIL`，列出缺失项。`## 最终需求定义` 本身不存在时，所有子节均标记为 MISSING。
```

**Step 3: 替换产物 JSON 示例**

找到当前的 sections_check 示例：
```json
  "sections_check": {
    "功能描述": "PRESENT",
    "用户故事": "PRESENT",
    "验收标准": "PRESENT",
    "范围边界": "MISSING"
  },
```

替换为：
```json
  "sections_check": {
    "最终需求定义_section_found": true,
    "功能描述": "PRESENT",
    "用户故事": "PRESENT",
    "业务规则": "PRESENT",
    "范围边界": "PRESENT",
    "验收标准": "MISSING"
  },
```

**Step 4: 验证**

Read Phase 0.5 章节全文，确认：①检查逻辑从 H2 改为 H3；②required_sections 包含 `### 业务规则`；③JSON 示例的 sections_check 字段与新逻辑一致。

**Step 5: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: fix Phase 0.5 section header level check H2→H3 (v6 fix漏洞S)"
```

---

### Task 4：Gate A 更新 resolver_verdict 示例（漏洞 Q）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Gate A 章节，矛盾仲裁 JSON 示例）

**Step 1: 定位 Gate A 矛盾仲裁 JSON**

Grep `采用 SSE 替代 WebSocket` 定位 resolver_verdict 示例块。Read 该 JSON 块（约 15 行）。

**Step 2: 替换 resolver_verdict 示例**

找到当前内容：
```json
  "resolver_verdict": {
    "reviewer": "Resolver",
    "conflict_parties": ["Auditor-Biz", "Auditor-Ops"],
    "conflict_summary": "Auditor-Biz 要求实时通知，Auditor-Ops 认为 WebSocket 运维复杂",
    "resolution": "采用 SSE 替代 WebSocket",
    "verdict": "PASS",
    "rollback_to": null,
    "conditions": "Architect 需在 Proposal 中将 WebSocket 改为 SSE 方案"
  }
```

替换为：
```json
  "resolver_verdict": {
    "reviewer": "Resolver",
    "conflict_parties": ["Auditor-Biz", "Auditor-Ops"],
    "conflict_summary": "Auditor-Biz 要求实时通知，Auditor-Ops 认为 WebSocket 运维复杂",
    "resolution": "采用 SSE 替代 WebSocket",
    "verdict": "PASS",
    "rollback_to": null,
    "conditions": "Architect 需在 Proposal 中将 WebSocket 改为 SSE 方案",
    "conditions_checklist": [
      {
        "target_agent": "Architect",
        "target_phase": "phase-1",
        "requirement": "将 Proposal 中的 WebSocket 替换为 SSE 方案，并更新影响面分析",
        "verification_method": "grep",
        "verification_pattern": "SSE|Server-Sent Events",
        "verification_file": ".pipeline/artifacts/proposal.md"
      }
    ]
  }
```

**Step 3: 在矛盾仲裁 JSON 之后补充产物说明**

在该 JSON 块之后（即 `---` 分隔线之前）追加：

```markdown
**conditions_checklist 验证产物：** `.pipeline/artifacts/resolver-conditions-check.json`（仅在 `conditions_checklist` 非空时生成）

```json
{
  "gate": "A",
  "resolver_conditions_check": true,
  "timestamp": "2025-01-01T00:00:08Z",
  "checks": [
    {
      "target_agent": "Architect",
      "requirement": "将 Proposal 中的 WebSocket 替换为 SSE 方案",
      "verification_method": "grep",
      "verification_pattern": "SSE|Server-Sent Events",
      "verification_file": ".pipeline/artifacts/proposal.md",
      "result": "PASS",
      "matched_lines": 3
    }
  ],
  "overall": "PASS"
}
```
```

**Step 4: 验证**

Read Gate A 章节矛盾仲裁 JSON 及其后的说明，确认：①resolver_verdict 包含 conditions_checklist；②conditions 字段保留（人可读）；③产物说明格式正确。

**Step 5: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add conditions_checklist to Gate A resolver_verdict example (v6 fix漏洞Q)"
```

---

### Task 5：Phase 4a 更新产物列表 + new_test_files 全生命周期规则（漏洞 V + 漏洞 U）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Phase 4a 章节）

**Step 1: 定位 Phase 4a 章节**

Grep `### Phase 4a：功能测试` 找到章节。Read 该章节全文（约 20 行）。

**Step 2: 更新产物行**

找到：
```
**产物：** `.pipeline/artifacts/test-report.json`
```

替换为：
```
**产物：**
- `.pipeline/artifacts/test-report.json`
- `.pipeline/artifacts/coverage/coverage.lcov` ← **必须生成**（Phase 4a.1 的前置依赖）
- `.pipeline/artifacts/coverage/coverage.json`（Istanbul JSON 格式，可选但推荐）

> **覆盖率收集要求（v6 新增）：** Tester 必须在覆盖率收集模式下运行测试（由 `config.json.testing.coverage_required: true` 强制）。若 `coverage.lcov` 不存在，Pilot 跳过 Phase 4a.1，直接触发全体回退，日志记录 `[WARN] coverage.lcov 不存在，跳过 Test Failure Mapper，执行全体回退`。
```

**Step 3: 更新 new_test_files 生命周期说明**

找到现有说明：
```
**关于新增测试文件的生命周期：** Tester 新增的测试文件在 `impl-manifest.json` 中标记为 `"new_test_files": [...]`。Phase 3.3 / Phase 3.6 的 Regression Guard 排除这些文件。若 Phase 4a FAIL 回退到 Phase 3，Pilot 将 `new_test_files` 列表保留在 state.json 中，Builder 修复后 Phase 3.3 / 3.6 仍排除它们，避免未修复的新测试被纳入回归守卫形成死锁。
```

替换为：
```
**关于新增测试文件的生命周期（v6 扩展）：** Tester 新增的测试文件在 `impl-manifest.json` 中标记为 `"new_test_files": [...]`，同时 Pilot 同步写入 `state.json.new_test_files`。**以下任意情况触发 Phase 3 时，Phase 3.3 / Phase 3.6 均排除 state.json.new_test_files 中的文件：**

- Phase 4a FAIL → Phase 4a.1 → Phase 3 回退
- Gate D FAIL → Phase 4a 或 Phase 3 回退（若再次经过 Phase 3）
- Gate C FAIL → Phase 3 回退（即使 Phase 4a 之前已通过）
- Optimizer SLA 违规（sla_violated: true）→ Phase 3 直接回退

排除规则持续有效，直到 Pipeline 状态变为 COMPLETED，毕业操作将 new_test_files 写入 `regression-suite-manifest.json` 并清空 `state.json.new_test_files`。
```

**Step 4: 验证**

Read Phase 4a 章节全文，确认：①产物列表包含 coverage 文件；②new_test_files 说明覆盖 4 种回退场景。

**Step 5: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: update Phase 4a artifacts and new_test_files lifecycle (v6 fix漏洞V漏洞U)"
```

---

### Task 6：Phase 4a.1 更新流转规则 + 产物 JSON + 前置要求（漏洞 R + 漏洞 V）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Phase 4a.1 章节）

**Step 1: 定位 Phase 4a.1 章节**

Grep `### Phase 4a\.1：测试失败映射` 找到章节。Read 该章节全文（约 55 行）。

**Step 2: 在"执行内容"之前新增"前置要求"段落**

在 `**执行内容：**` 之前插入：

```markdown
**前置要求（v6 新增）：** Pilot 在触发 Phase 4a.1 前，验证 `.pipeline/artifacts/coverage/coverage.lcov` 存在且非空。若不存在，跳过 Phase 4a.1，直接触发全体回退（等同 PARTIAL_MAPPED），日志记录 `[WARN] coverage.lcov 不存在，跳过 Test Failure Mapper，执行全体回退`。

```

**Step 3: 更新产物 JSON 示例（新增 builders_high_confidence 字段和 LOW_CONFIDENCE_MAPPED 场景）**

找到当前 JSON 示例（包含 `"overall": "MAPPED"` 的那个）并替换为：

```json
// 高置信度精确映射场景：
{
  "autostep": "TestFailureMapper",
  "timestamp": "2025-01-01T00:07:30Z",
  "failure_mappings": [
    {
      "test_name": "test_get_user_not_found",
      "involved_files": ["src/routes/user.ts", "src/middleware/auth.ts"],
      "responsible_builders": ["Builder-Backend", "Builder-Security"],
      "confidence": "HIGH"
    }
  ],
  "builders_to_rollback": ["Builder-Backend", "Builder-Security"],
  "builders_high_confidence": ["Builder-Backend", "Builder-Security"],
  "unmapped_failures": [],
  "overall": "PRECISE_MAPPED"
}

// 低置信度保守场景（v6 新增）：
{
  "autostep": "TestFailureMapper",
  "timestamp": "2025-01-01T00:07:30Z",
  "failure_mappings": [
    {
      "test_name": "test_get_user_not_found",
      "involved_files": ["src/routes/user.ts"],
      "responsible_builders": ["Builder-Backend"],
      "confidence": "HIGH"
    },
    {
      "test_name": "test_auth_middleware",
      "involved_files": ["src/middleware/auth.ts", "src/config/security.ts"],
      "responsible_builders": ["Builder-Security", "Builder-Backend"],
      "confidence": "LOW"
    }
  ],
  "builders_to_rollback": ["Builder-Backend", "Builder-Security"],
  "builders_high_confidence": ["Builder-Backend"],
  "unmapped_failures": [],
  "overall": "LOW_CONFIDENCE_MAPPED"
}
```

**Step 4: 替换流转规则**

找到当前流转规则：
```
**流转规则：**
- `unmapped_failures` 为空（`overall: MAPPED`）→ 只回退 `builders_to_rollback` 中的 Builder，其余 Builder 的实现结果保留。
- `unmapped_failures` 不为空（`overall: PARTIAL_MAPPED`）→ 降级：回退所有 Builder（与 v4 行为一致），日志记录 `[WARN] 测试失败部分无法映射到 Builder，执行全体回退`。
```

替换为：
```
**流转规则（v6 更新，新增 confidence 维度）：**
- `overall: PRECISE_MAPPED`（所有映射均为 HIGH confidence，unmapped_failures 为空）→ 只回退 `builders_high_confidence` 中的 Builder，其余 Builder 的实现结果保留。
- `overall: LOW_CONFIDENCE_MAPPED`（存在 LOW confidence 映射，unmapped_failures 为空）→ 降级为全体回退，日志记录 `[WARN] 存在 LOW 置信度映射，执行保守全体回退`。
- `overall: PARTIAL_MAPPED`（unmapped_failures 不为空，无论 confidence）→ 回退所有 Builder，日志记录 `[WARN] 测试失败部分无法映射到 Builder，执行全体回退`。
```

**Step 5: 验证**

Read Phase 4a.1 章节全文，确认：①前置要求段落存在；②两个 JSON 场景示例格式正确；③流转规则引用 PRECISE_MAPPED / LOW_CONFIDENCE_MAPPED / PARTIAL_MAPPED 三种 overall 值。

**Step 6: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: update Phase 4a.1 confidence-based flow rules and coverage prerequisite (v6 fix漏洞R漏洞V)"
```

---

### Task 7：Gate D 补充 rollback_to 字段（漏洞 T）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Gate D 章节）

**Step 1: 定位 Gate D 章节**

Grep `### Gate D：测试验收` 找到章节。Read 该章节全文（约 20 行）。

**Step 2: 替换 Gate D 产物 JSON 示例**

找到当前示例：
```json
{
  "gate": "D",
  "test_verdict": "PASS",
  "coverage_verdict": "PASS",
  "perf_verdict": "PASS",
  "overall": "PASS"
}
```

替换为（两个场景）：

```markdown
**PASS 场景：**

```json
{
  "gate": "D",
  "agent": "Auditor-QA",
  "attempt": 1,
  "test_verdict": "PASS",
  "coverage_verdict": "PASS",
  "perf_verdict": "N/A",
  "overall": "PASS",
  "rollback_to": null,
  "rollback_reason": null
}
```

**FAIL 场景（v6 新增 rollback_to 字段）：**

```json
{
  "gate": "D",
  "agent": "Auditor-QA",
  "attempt": 1,
  "test_verdict": "FAIL",
  "coverage_verdict": "PASS",
  "perf_verdict": "PASS",
  "overall": "FAIL",
  "rollback_to": "phase-4a",
  "rollback_reason": "功能测试存在 3 个失败用例，Tester 需补充边界条件测试"
}
```

**Pilot 机械验证 rollback_to 合法性（v6 新增）：** Gate D 的 `rollback_to` 只允许 `null`（PASS 时）、`"phase-4a"`、`"phase-3"`、`"phase-2"`。若 Auditor-QA 输出超出范围的值（如 `"phase-0"`），Pilot 拒绝并降级为 `"phase-2"`，日志记录 `[WARN] Gate D rollback_to 超出允许范围，已降级为 phase-2`。
```

**Step 3: 验证**

Read Gate D 章节全文，确认：①两个 JSON 场景均有 rollback_to 字段；②Pilot 验证说明存在；③与 rollback_to 范围限制说明（"不得指定 phase-0 或 phase-1"）一致。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add rollback_to field to Gate D JSON schema (v6 fix漏洞T)"
```

---

### Task 8：Phase 5 新增 state.json 写入时机说明（漏洞 W）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Phase 5 章节，API Change Detector 部分）

**Step 1: 定位 API Change Detector 段落**

Grep `Documenter 读取 \`state\.json\.phase_5_mode\`` 找到那行，定位其所在段落。

**Step 2: 在该行之后插入写入时机说明**

找到：
```
Documenter 读取 `state.json.phase_5_mode` 决定执行内容。`changelog_only` 模式下，Documenter 只更新 CHANGELOG，跳过 API 文档生成和 ADR 最终化。
```

替换为：
```
Documenter 读取 `state.json.phase_5_mode` 决定执行内容。`changelog_only` 模式下，Documenter 只更新 CHANGELOG，跳过 API 文档生成和 ADR 最终化。

**Pilot 写入 state.json（v6 明确，修复漏洞 W）：** AUTOSTEP_API_CHANGE_DETECTOR 完成后，Pilot 读取 `api-change-report.json.phase_5_mode`，同步写入 `state.json.phase_5_mode`。两个文件均保留此字段：`api-change-report.json` 作为产物归档，`state.json` 作为运行时状态（Documenter 运行时的读取来源）。
```

**Step 3: 验证**

Read Phase 5 章节的 API Change Detector 段落及 Phase 5 执行策略表，确认新增说明位置正确，不影响表格和原有流转规则。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: clarify state.json.phase_5_mode write timing in Phase 5 (v6 fix漏洞W)"
```

---

### Task 9：Section 7.1 状态机更新（漏洞 Q + R + T）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 7.1 状态机代码块）

**Step 1: 读取 Section 7.1 状态机代码块**

Read Section 7.1（约 120 行的代码块），识别需要修改的 3 处位置。

**Step 2: 在 GATE_A_REVIEW PASS 分支后插入 RESOLVER_CONDITIONS_CHECK 状态（漏洞 Q）**

找到：
```
GATE_A_REVIEW ──┬─ CONFLICT → RESOLVER → 重评估  │
                ├─ PASS ──▶ PHASE_2              │
                └─ FAIL ──▶ (rollback_to) ───────┘
```

替换为：
```
GATE_A_REVIEW ──┬─ CONFLICT → RESOLVER → 重评估  │
                │   └─ RESOLVER conditions_checklist 非空 → RESOLVER_CONDITIONS_CHECK ← v6 新增
                │         ├─ PASS → PHASE_2
                │         └─ FAIL → rollback_to target_phase
                ├─ PASS ──▶ PHASE_2              │
                └─ FAIL ──▶ (rollback_to) ───────┘
```

（注：Gate B 的同等逻辑在文档中复用 Gate A 的 Resolver 机制说明，不单独在状态机中展开。）

**Step 3: 更新 PHASE_4A_1_TEST_FAILURE_MAPPER 分支（漏洞 R）**

找到：
```
  └─ FAIL → PHASE_4A_1_TEST_FAILURE_MAPPER       ← AutoStep【v5 新增，修复漏洞 L】
               ├─ MAPPED      → 只回退 builders_to_rollback 中的 Builder（精确回退）
               └─ PARTIAL_MAPPED → 回退所有 Builder（降级，保留 new_test_files 标记）
```

替换为：
```
  └─ FAIL → PHASE_4A_1_TEST_FAILURE_MAPPER       ← AutoStep【v5 新增，修复漏洞 L；v6 更新漏洞 R】
               ├─ coverage.lcov 不存在 → 全体回退（跳过 Mapper，降级，v6 新增）
               ├─ PRECISE_MAPPED → 只回退 builders_high_confidence（精确回退）  ← v6
               ├─ LOW_CONFIDENCE_MAPPED → 全体回退（保守降级，v6 新增）
               └─ PARTIAL_MAPPED → 回退所有 Builder（降级，保留 new_test_files 标记）
```

**Step 4: 更新 GATE_D_QA_REVIEW 的 FAIL 分支（漏洞 T）**

找到：
```
GATE_D_QA_REVIEW
  │ rollback_to 范围限制: phase-4a / phase-3 / phase-2（不得超过 phase-2）
  ├─ PASS ──▶ AUTOSTEP_API_CHANGE_DETECTOR
  └─ FAIL ──▶ (rollback_to)
```

替换为：
```
GATE_D_QA_REVIEW
  │ rollback_to 范围限制: phase-4a / phase-3 / phase-2（不得超过 phase-2）
  │ rollback_to 字段由 gate-d-review.json 提供（v6 补充，修复漏洞 T）
  ├─ PASS ──▶ AUTOSTEP_API_CHANGE_DETECTOR
  └─ FAIL ──▶ (gate-d-review.json.rollback_to)
               Pilot 越界降级：超出允许范围 → 强制 phase-2
```

**Step 5: 验证**

Read Section 7.1 完整代码块，确认三处修改格式正确，箭头方向一致，无乱码。

**Step 6: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: update state machine with v6 resolver conditions, confidence branches, Gate D rollback"
```

---

### Task 10：Section 7.3 state.json 补充 phase_5_mode 和 new_test_files（漏洞 W）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 7.3 state.json 示例）

**Step 1: 定位 state.json 示例**

Grep `"pipeline_id": "pipe-20250301-001"` 找到 state.json 示例起始行。Read 该 JSON 块（约 30 行）。

**Step 2: 在 `"mode": "normal"` 行之后插入两个字段**

找到：
```json
  "mode": "normal",
  "hotfix": {
```

替换为：
```json
  "mode": "normal",
  "phase_5_mode": null,
  "new_test_files": [],
  "hotfix": {
```

**Step 3: 在 state.json 示例代码块之后追加字段语义说明**

在 state.json JSON 块结束后（即 `**崩溃恢复：**` 之前），追加：

```markdown
**state.json 新增字段语义（v6，修复漏洞 W）：**

- `phase_5_mode`：值域 `null`（未到 Phase 5）/ `"full"` / `"changelog_only"` / `"skip"`。写入时机：AUTOSTEP_API_CHANGE_DETECTOR 完成后，Pilot 从 api-change-report.json 同步。读取方：Documenter（决定 Phase 5 执行内容）、Phase 5.1 Changelog Consistency Checker（判断是否运行）。

- `new_test_files`：数组，存储本次 Pipeline Tester 新增的测试文件路径列表。写入时机：Phase 4a 完成后，Pilot 从 impl-manifest.json 同步。清空时机：Pipeline COMPLETED 毕业操作完成。读取方：Phase 3.3 Regression Guard、Phase 3.6 Post-Simplification Verifier（这些文件始终被排除在回归测试范围外，直到毕业）。

```

**Step 4: 验证**

Read Section 7.3 全文，确认：①state.json 示例包含 phase_5_mode 和 new_test_files；②字段语义说明存在且准确。

**Step 5: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add phase_5_mode and new_test_files to state.json schema (v6 fix漏洞W)"
```

---

### Task 11：Section 9 config.json 更新两处配置块（漏洞 S + 漏洞 V）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 9 config.json 代码块）

**Step 1: 定位 requirement_completeness 配置块**

Grep `"requirement_completeness"` 找到该配置块。Read 该 JSON 块周边 10 行。

**Step 2: 替换 requirement_completeness 配置**

找到：
```json
  "requirement_completeness": {
    "required_sections": ["功能描述", "用户故事", "验收标准", "范围边界"],
    "min_words": 200,
    "abort_on_critical_unresolved": true
  },
```

替换为：
```json
  "requirement_completeness": {
    "parent_section": "## 最终需求定义",
    "required_sections": ["### 功能描述", "### 用户故事", "### 业务规则", "### 范围边界", "### 验收标准"],
    "section_match_mode": "prefix",
    "min_words": 200,
    "abort_on_critical_unresolved": true
  },
```

**Step 3: 在 autosteps 对象之后追加 testing 配置块**

Grep `"test-failure-mapper"` 找到 autosteps 最后一个配置项，在 autosteps 对象闭合 `}` 之后（且在 `"gates"` 之前）插入：

```json
  "testing": {
    "coverage_tool": "nyc",
    "coverage_format": ["lcov", "json"],
    "coverage_output_dir": ".pipeline/artifacts/coverage/",
    "coverage_required": true,
    "note": "Phase 4a 必须在覆盖率收集模式下运行（v6 新增），coverage.lcov 是 Phase 4a.1 的前置依赖"
  },
```

**Step 4: 验证**

Read Section 9 的 config.json 代码块，确认：①requirement_completeness 包含 parent_section 和 section_match_mode；②testing 配置块存在且 JSON 逗号正确。

**Step 5: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: update config.json with H3 section check and testing coverage config (v6 fix漏洞S漏洞V)"
```

---

### Task 12：Section 13 总结新增 v6 改进要点

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 13 末尾）

**Step 1: 定位 Section 13 末尾**

Grep `Optimizer 直接回退（修复漏洞 P）` 找到 v5 最后一条改进要点（第 37 条）。

**Step 2: 在其后追加 v6 改进要点**

在第 37 条之后插入：

```markdown
**v6 新增改进要点：**

38. **Resolver 条件承诺机械化（修复漏洞 Q）**：resolver_verdict 新增结构化 `conditions_checklist` 数组，Pilot 在放行前逐条机械验证条件是否满足（grep / exists / field_value），验证结果写入 `resolver-conditions-check.json`，彻底消除 Resolver 条件成空话的风险。

39. **Test Failure Mapper 精确回退的置信度保护（修复漏洞 R）**：Phase 4a.1 新增 `PRECISE_MAPPED`（全部 HIGH confidence）/ `LOW_CONFIDENCE_MAPPED`（存在 LOW confidence）两种 overall 值，LOW confidence 映射触发保守全体回退，防止不确定的 Builder 归属导致无辜 Builder 被精确回退。

40. **Phase 0.5 标题层级 bug 修复（修复漏洞 S，高危）**：Phase 0.5 Section 检查从搜索 H2 标题（`## 功能描述`）修正为搜索 `## 最终需求定义` 下的 H3 子节（`### 功能描述` 等），修复了对所有合法 requirement.md 永远输出 FAIL 的严重 bug。

41. **Gate D 产物 schema 完整化（修复漏洞 T）**：gate-d-review.json 补充结构化 `rollback_to` 字段，与 Gate A / Gate C 产物格式对齐，Pilot 机械解析回退目标；超出允许范围的值自动降级并记录警告。

42. **new_test_files 排除规则统一（修复漏洞 U）**：new_test_files 的 Regression Guard 排除规则从"仅 Phase 4a FAIL 时"扩展为"任意 Phase 3 回退路径均适用"，消除 Gate C FAIL 等场景下的排除规则歧义。

43. **Phase 4a 覆盖率生成强制化（修复漏洞 V）**：Phase 4a 产物列表新增 coverage.lcov（必须生成），config.json 新增 `testing.coverage_required: true` 配置，消除 Phase 4a.1 对覆盖率数据的隐式依赖，确保精确回退功能真正可用。

44. **state.json schema 完整化（修复漏洞 W）**：state.json 补充 `phase_5_mode` 和 `new_test_files` 两个字段定义，明确写入时机和读取方，修复崩溃恢复时这两个关键字段丢失导致流转失效的问题。
```

**Step 3: 验证**

Read Section 13 末尾，确认 v6 要点编号从 38 开始，共 7 条（38-44），格式与 v5 要点一致。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add v6 summary improvement points to Section 13"
```

---

### Task 13：Section 14.1 漏洞汇总表新增 v6 修复行

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 14.1 漏洞汇总表末尾）

**Step 1: 定位表格末尾**

Grep `Optimizer SLA 明确违规时无直接回退机制` 找到漏洞 P 那行（当前最后一行），记录行号。

**Step 2: 在漏洞 P 行之后追加 7 行**

```markdown
| 漏洞 Q | Resolver 的 conditions 字段为纯文本，无机械验证路径；Resolver 说"PASS"并附条件后，Pilot 直接推进，条件是否被执行完全依赖下游 Agent 是否读到文字 | resolver_verdict 新增结构化 conditions_checklist，Pilot 逐条机械验证（grep/exists/field_value），验证结果写入 resolver-conditions-check.json | v6 |
| 漏洞 R | Phase 4a.1 的 confidence 字段（HIGH/LOW/UNKNOWN）完全不影响流转决策，LOW confidence 的不确定映射与 HIGH confidence 的确定映射被同等对待，可能导致无辜 Builder 被精确回退 | 流转规则新增 confidence 维度：PRECISE_MAPPED（全部 HIGH）→ 只回退 builders_high_confidence；LOW_CONFIDENCE_MAPPED（存在 LOW）→ 降级全体回退 | v6 |
| 漏洞 S | Phase 0.5 检查 `## 功能描述`（H2），但 requirement.md 格式定义的是 `### 功能描述`（H3，位于 `## 最终需求定义` 下），导致所有合法文档永远输出 FAIL（高危 bug） | Phase 0.5 改为在 `## 最终需求定义` 下检查 H3 子节；config.json required_sections 从 H2 改为 H3；新增 `### 业务规则` 检查项 | v6 |
| 漏洞 T | Gate D 产物 gate-d-review.json 缺少 rollback_to 字段，Gate D FAIL 时 Pilot 无法机械解析回退目标，与 Gate A / Gate C 产物格式不一致，违反"产物驱动流转"原则 | gate-d-review.json 补充 rollback_to 字段，枚举值限制为 null / phase-4a / phase-3 / phase-2；Pilot 机械验证并在越界时降级 | v6 |
| 漏洞 U | new_test_files 的 Regression Guard 排除规则只定义了"Phase 4a FAIL 回退"场景，未覆盖 Gate C FAIL、Gate D FAIL、Optimizer SLA 违规等其他 Phase 3 回退路径，语义歧义导致实现时各路径行为不一致 | 明确规定 new_test_files 排除规则适用于当前 Pipeline 内所有 Phase 3 回退路径，清空时机统一为 Pipeline COMPLETED 毕业操作 | v6 |
| 漏洞 V | Phase 4a 产物定义只有 test-report.json，未提及 coverage.lcov；Phase 4a.1 隐式依赖 coverage.lcov；若 Tester 未启用覆盖率收集，Phase 4a.1 全部返回 UNKNOWN，精确回退完全失效 | Phase 4a 产物列表新增 coverage.lcov（必须生成）；config.json 新增 testing.coverage_required: true；Pilot 在 Phase 4a.1 前验证 coverage.lcov 存在 | v6 |
| 漏洞 W | state.json schema 缺少 phase_5_mode 和 new_test_files 字段定义，但两者在 Phase 5 和 Phase 7 毕业机制中均被读取；崩溃恢复后这两个字段丢失，导致 Documenter 无法确定 Phase 5 执行模式，new_test_files 排除规则失效 | state.json schema 补充 phase_5_mode（枚举：null/full/changelog_only/skip）和 new_test_files（数组）字段；明确 Pilot 写入时机 | v6 |
```

**Step 3: 验证**

Read Section 14.1 末尾，确认 7 行的格式与已有行一致（列数相同，竖线对齐），无 Markdown 格式错误。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add v6 bug fixes Q-W to Section 14.1 design review table"
```

---

## 执行验证清单

所有 13 个 Task 完成后，执行以下验证：

```bash
# 1. 确认 v6 字样在文档头部出现
grep -n "v6 核心改进" claude-code-multi-agent-team-design.md

# 2. 确认 conditions_checklist 存在（漏洞 Q）
grep -n "conditions_checklist" claude-code-multi-agent-team-design.md

# 3. 确认 H3 标题检查（漏洞 S 修复）
grep -n "### 功能描述\|parent_section\|section_match_mode" claude-code-multi-agent-team-design.md

# 4. 确认 Gate D rollback_to 字段（漏洞 T）
grep -n "Gate D.*rollback_to\|gate-d-review.*rollback_to\|perf_verdict.*N/A" claude-code-multi-agent-team-design.md

# 5. 确认 PRECISE_MAPPED 和 LOW_CONFIDENCE_MAPPED（漏洞 R）
grep -n "PRECISE_MAPPED\|LOW_CONFIDENCE_MAPPED\|builders_high_confidence" claude-code-multi-agent-team-design.md

# 6. 确认 coverage.lcov 必须生成（漏洞 V）
grep -n "coverage\.lcov\|coverage_required\|testing_config" claude-code-multi-agent-team-design.md

# 7. 确认 state.json 补充字段（漏洞 W）
grep -n "phase_5_mode.*null\|new_test_files.*\[\]" claude-code-multi-agent-team-design.md

# 8. 确认 Section 13 v6 改进要点从 38 开始
grep -n "^38\.\|^39\.\|^44\." claude-code-multi-agent-team-design.md

# 9. 确认 Section 14.1 包含漏洞 Q~W
grep -n "漏洞 Q\|漏洞 R\|漏洞 S\|漏洞 T\|漏洞 U\|漏洞 V\|漏洞 W" claude-code-multi-agent-team-design.md
```

所有 grep 均有输出则验证通过。
