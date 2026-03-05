# v5 设计方案落地 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 `docs/plans/2026-03-04-v5-design.md` 中定义的所有 v5 改动，逐节写入 `claude-code-multi-agent-team-design.md`，使该主文档升级为 v5 版本。

**Architecture:** 本计划为纯文档编辑，目标文件为单一 Markdown 文件（2378 行）。所有改动均为精准的 Edit 操作，按文档章节顺序从前往后执行，避免行号漂移干扰。每个 Task 对应文档中的一个逻辑区域，完成后单独 commit。

**Tech Stack:** Markdown 编辑（Read + Edit 工具）、git commit

**参考文档:** `docs/plans/2026-03-04-v5-design.md`（每个 Task 的改动内容均来自此文件）

---

### Task 1：在文档顶部新增 v5 核心改进说明

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（文件头部，当前第 25-38 行附近的 v4 改进块之后）

**Step 1: 读取文件头部确认插入位置**

Read `claude-code-multi-agent-team-design.md` offset=25 limit=20，找到 v4 改进块的最后一行（`- 新增 Phase 5.1 Changelog Consistency Checker AutoStep...`），记录其行号。

**Step 2: 在 v4 改进块末尾之后插入 v5 改进块**

在 v4 块结束位置之后，插入以下内容：

```markdown
**v5 核心改进（基于逻辑漏洞分析）：**
- 修复漏洞 K：新增 Phase 2.7 Contract Semantic Validator（AutoStep），使用 Spectral + 自定义脚本封堵"格式合法但语义错误"的 OpenAPI Schema，防止 Contract Formalizer 的类型/字段错误静默传递到 Phase 3
- 修复漏洞 L：新增 Phase 4a.1 Test Failure Mapper（AutoStep），分析测试失败的 Builder 责任归属，实现精确回退而非全体回退
- 修复漏洞 M：明确正常流程下 `api_changed: false` 时 Phase 5 的执行策略（新增 `phase_5_mode: changelog_only`），消除状态机空白路径
- 修复漏洞 N：修正第 8 节目录结构中 `.pipeline/artifacts/` 重复定义，统一 adr-draft.md 路径
- 修复漏洞 O：gate-b-review.json 新增 `assumption_dispositions` 字段，将 Gate B 对假设的处置决策升级为结构化记录，支持机械流转
- 修复漏洞 P：perf-report.json 新增 `sla_violated` 字段，Optimizer 明确发现 SLA 违规时直接触发 Phase 3 回退，不等待 Gate D
- 新增 Phase 0.5 Requirement Completeness Checker（AutoStep）：需求文档进入 Gate A 前的格式与完整性机械门禁
- 新增 Phase 2.7 Contract Semantic Validator（AutoStep）：封堵 Phase 2.6 无法检测的语义错误，使用 Spectral + 脚本，无 LLM
- 新增 Phase 4a.1 Test Failure Mapper（AutoStep）：测试失败后精确映射责任 Builder，降低多 Builder 场景下的无辜回退成本
```

**Step 3: 确认插入位置正确，内容无格式错误**

Read 修改后区域，确认 v5 块位于 v4 块之后，格式缩进与 v2/v3/v4 块一致。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add v5 summary header to design document"
```

---

### Task 2：Section 2.3 AutoStep 表新增三行

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 2.3 的 AutoStep 表格）

**Step 1: 读取 Section 2.3 AutoStep 表**

Grep `Pre-Deploy Readiness Check` 定位表格最后一行，确认当前最后一行是 `Pre-Deploy Readiness Check | Phase 6.0【v4 新增】`。

**Step 2: 在表格最后一行之后插入三行**

```markdown
| **Requirement Completeness Checker** | **Phase 0.5【v5 新增】** | 验证 requirement.md 必填 Section 存在且非空、`[CRITICAL-UNRESOLVED]` 数量为 0、`[ASSUMED:...]` 格式合规、最小字数达标 | requirement.md | `requirement-completeness-report.json` |
| **Contract Semantic Validator** | **Phase 2.7【v5 新增】** | Spectral 校验 RESTful 语义规则（路径参数 required、operationId、GET 无 requestBody）+ 自定义脚本比对 tasks.json definition 字段类型与 OpenAPI Schema 一致性 | contracts/ + tasks.json | `contract-semantic-report.json` |
| **Test Failure Mapper** | **Phase 4a.1【v5 新增，FAIL 时触发】** | 解析 coverage.lcov 提取失败测试涉及的文件，与 impl-manifest.json 交叉映射到责任 Builder，输出 builders_to_rollback 精确回退列表 | test-report.json + coverage.lcov + impl-manifest.json | `failure-builder-map.json` |
```

**Step 3: 确认表格格式对齐**

Read 修改后的 Section 2.3，确认新三行的列分隔符 `|` 对齐，与已有行格式一致。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add Phase 0.5, 2.7, 4a.1 to AutoStep table (v5)"
```

---

### Task 3：Section 5 新增 Phase 0.5 详细设计

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Phase 0 章节之后、Gate A 章节之前）

**Step 1: 定位插入点**

Grep `### Gate A：方案校验` 定位 Gate A 章节标题行号。在该标题行之前插入 Phase 0.5 章节（中间保留一个空行 + `---` 分隔线）。

**Step 2: 插入 Phase 0.5 完整章节**

```markdown
---

### Phase 0.5：需求完整性校验（Requirement Completeness Checker）【v5 新增 AutoStep】

**类型：** AutoStep

**触发时机：** Phase 0（Clarifier）完成 requirement.md 后，Gate A 审核前。

**执行内容：**

1. **必填 Section 检查**：验证 requirement.md 包含以下 Section 标题且内容非空：
   - `## 功能描述`
   - `## 用户故事`
   - `## 验收标准`
   - `## 范围边界`

2. **关键项检查**：确认 `[CRITICAL-UNRESOLVED]` 出现次数为 0。

3. **假设格式检查**：所有 `[ASSUMED:...]` 条目符合正则 `\[ASSUMED:[^\]]+\]`，确保 Phase 2.1 的关键词提取不受格式异常干扰。

4. **最小字数检查**：需求文档总字数 ≥ `config.json` 中 `requirement_completeness.min_words`（默认 200）。

**产物：** `.pipeline/artifacts/requirement-completeness-report.json`

```json
{
  "autostep": "RequirementCompletenessChecker",
  "timestamp": "2025-01-01T00:00:05Z",
  "sections_check": {
    "功能描述": "PRESENT",
    "用户故事": "PRESENT",
    "验收标准": "PRESENT",
    "范围边界": "MISSING"
  },
  "critical_unresolved_count": 0,
  "assumed_items_count": 2,
  "assumed_items_valid_format": true,
  "word_count": 450,
  "word_count_threshold": 200,
  "overall": "FAIL"
}
```

**流转规则：**
- `overall: FAIL` → 回退 Phase 0（Clarifier 补充缺失内容），不进入 Gate A。
- `overall: PASS` → 进入 Gate A，Auditor 无需再检查格式问题，专注内容审查。

> **这修复了 v4 遗留漏洞**：需求文档的格式完整性此前依赖 Gate A Auditor 的主观检查，现升级为机械前置门禁，同时为 Phase 2.1 的假设关键词提取提供格式保障。
```

**Step 3: 确认章节边界正确**

Read 插入区域前后各 5 行，确认：Phase 0 章节结尾的 `---` 之后是新的 Phase 0.5 章节，Phase 0.5 章节结尾的 `---` 之后是 Gate A 章节。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add Phase 0.5 Requirement Completeness Checker (v5)"
```

---

### Task 4：Section 5 新增 Phase 2.7 详细设计

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Phase 2.6 章节之后、Phase 3 章节之前）

**Step 1: 定位插入点**

Grep `### Phase 3：并行代码实现` 定位 Phase 3 章节标题行号。在该行之前（保留 `---` 分隔）插入 Phase 2.7 章节。

**Step 2: 插入 Phase 2.7 完整章节**

```markdown
---

### Phase 2.7：契约语义校验（Contract Semantic Validator）【v5 新增 AutoStep】

**类型：** AutoStep

**触发时机：** Phase 2.6（Schema Completeness Validator）PASS 后，Phase 3 并行实现前。

**工具栈（全部开源）：**
- `@stoplight/spectral-core` + `@stoplight/spectral-openapi`：RESTful 语义规则校验
- `@stoplight/spectral-owasp-rules`：API 安全基础规则校验
- 自定义比对脚本：`tasks.json contracts[].definition` 字段 ↔ OpenAPI Schema `properties` 类型比对

**执行内容：**

1. **Spectral 规则校验**（`@stoplight/spectral-openapi` + `@stoplight/spectral-owasp-rules`）：
   - 路径参数必须标记为 `required: true`
   - 每个 operation 必须有 `operationId`
   - 每个 operation 必须有 2xx 响应定义
   - GET / HEAD / DELETE 不得有 `requestBody`
   - API Key 不得在 query 参数中传递（OWASP）

2. **tasks.json ↔ OpenAPI 字段比对脚本**：
   - 提取 `tasks.json contracts[].definition.response` 中每个字段的名称和类型
   - 与对应 `contracts/contract-N.openapi.json` 的 `properties` 逐字段比对
   - 检测字段名不匹配或类型不一致（如 `integer` vs `string`）

**产物：** `.pipeline/artifacts/contract-semantic-report.json`

```json
{
  "autostep": "ContractSemanticValidator",
  "timestamp": "2025-01-01T00:00:45Z",
  "spectral_violations": [
    {
      "contract_id": "contract-1",
      "file": "contracts/contract-1.openapi.json",
      "rule": "oas3-path-params",
      "message": "路径参数 'id' 未标记为 required",
      "severity": "ERROR",
      "line": 12
    }
  ],
  "field_type_mismatches": [
    {
      "contract_id": "contract-1",
      "field": "id",
      "tasks_json_type": "integer",
      "openapi_type": "string",
      "severity": "ERROR"
    }
  ],
  "warnings": [],
  "overall": "FAIL"
}
```

**流转规则：**
- 任意 `severity: ERROR` → 回退 Phase 2.5（Contract Formalizer 基于报告修正 Schema）。
- 仅有 `severity: WARN` → 不阻断，追加到 Gate C Inspector 的参考输入上下文。
- 无任何问题 → 进入 Phase 3（并行实现）。

> **这修复了 v4 遗留漏洞 K**：Phase 2.6 只验证 OpenAPI 格式合法性，无法检测"格式合法但语义错误"的 Schema。Contract Formalizer 的字段类型错误（如整数定义为 string）、路径参数 required 遗漏等，此前需等到 Phase 3.7 才能发现，彼时整个 Phase 3 实现已完成。新增本 AutoStep 将发现点前移，回退成本降至最低（仅 Phase 2.5 重做）。
```

**Step 3: 确认章节边界**

Read 插入区域，确认 Phase 2.6 的 `---` → Phase 2.7 完整章节 → `---` → Phase 3 章节。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add Phase 2.7 Contract Semantic Validator (v5)"
```

---

### Task 5：Section 5 在 Phase 4a 之后新增 Phase 4a.1 详细设计

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Phase 4a 章节之后、Phase 4.2 章节之前）

**Step 1: 定位插入点**

Grep `### Phase 4.2：测试覆盖率门禁` 定位 Phase 4.2 章节，在其前插入 Phase 4a.1 章节。

**Step 2: 插入 Phase 4a.1 完整章节**

```markdown
---

### Phase 4a.1：测试失败映射（Test Failure Mapper）【v5 新增 AutoStep，Phase 4a FAIL 时触发】

**类型：** AutoStep

**触发时机：** Phase 4a 功能测试 FAIL 后，Phase 3 回退前。Phase 4a PASS 时本步骤跳过。

**执行内容：**

1. 解析 `test-report.json` 中 `failures` 的测试名列表。
2. 从覆盖率工具的 `coverage.lcov` 输出（或 Istanbul/nyc JSON 报告）中提取每个失败测试涉及的源文件路径。
3. 与 `impl-manifest.json` 中各 Builder 的 `files_changed` 列表交叉比对，推断 `responsible_builders`。
4. 合并所有失败测试的责任 Builder 集合，输出 `builders_to_rollback`。

**置信度规则：**
- `HIGH`：失败测试涉及的所有文件均可唯一归属单一 Builder。
- `LOW`：涉及多个 Builder 共享的文件，无法唯一归属。
- `UNKNOWN`：无法从覆盖率数据提取涉及文件（触发降级）。

**产物：** `.pipeline/artifacts/failure-builder-map.json`

```json
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
  "unmapped_failures": [],
  "overall": "MAPPED"
}
```

**流转规则：**
- `unmapped_failures` 为空（`overall: MAPPED`）→ 只回退 `builders_to_rollback` 中的 Builder，其余 Builder 的实现结果保留。
- `unmapped_failures` 不为空（`overall: PARTIAL_MAPPED`）→ 降级：回退所有 Builder（与 v4 行为一致），日志记录 `[WARN] 测试失败部分无法映射到 Builder，执行全体回退`。

> **这修复了 v4 遗留漏洞 L**：Phase 4a 测试失败后无法确定责任 Builder，Orchestrator 只能全体回退。在多 Builder 场景下，无辜 Builder 被强制重做整个 Phase 3，成本浪费显著。精确映射后，只有真正导致测试失败的 Builder 才需要回退。
```

**Step 3: 确认章节边界**

Read 插入区域，确认 Phase 4a 章节结尾 → Phase 4a.1 完整章节 → Phase 4.2 章节。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add Phase 4a.1 Test Failure Mapper (v5)"
```

---

### Task 6：修复 Gate B 产物格式（漏洞 O）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Gate B 章节的 JSON 示例）

**Step 1: 定位 Gate B 章节**

Grep `### Gate B：任务校验` 定位章节。读取该章节全文，确认当前 gate-b-review.json 示例内容（目前直接引用 Gate A 格式，未包含 assumption_dispositions）。

**Step 2: 在 Gate B 章节补充 assumption_dispositions 说明**

在现有 Gate B 章节的"流转规则"说明之后，追加以下内容：

```markdown
**假设处置记录（`assumption_dispositions`，v5 新增）：**

当 Phase 2.1 Assumption Propagation Validator 存在 `uncovered` 假设时，Auditor-Biz 须在 `gate-b-review.json` 中对每条假设明确标注处置结果：

```json
{
  "gate": "B",
  "assumption_dispositions": [
    {
      "assumption": "第三方支付回调格式遵循标准 Webhook 格式",
      "source": "requirement.md:行42",
      "disposition": "ACCEPTED",
      "auditor": "Auditor-Biz",
      "note": "与支付供应商确认后可接受此假设"
    },
    {
      "assumption": "用户量不超过 10 万",
      "source": "requirement.md:行18",
      "disposition": "REQUIRE_PLANNER_COVERAGE",
      "auditor": "Auditor-Tech",
      "note": "需要 Planner 在 tasks.json 中增加限流和分页任务"
    }
  ],
  "results": [...],
  "overall": "FAIL"
}
```

`disposition` 枚举值：
- `ACCEPTED`：接受假设，Builder 可直接基于此假设实现，无需 Planner 补充任务。
- `REQUIRE_PLANNER_COVERAGE`：要求 Planner 在 tasks.json 中增加对应任务或 notes 引用。

**追加流转规则（v5）：** 若任意假设的 `disposition: REQUIRE_PLANNER_COVERAGE` → Gate B FAIL，`rollback_to: phase-2`，Planner 补充覆盖任务后重新提交 Gate B 审核。若 `assumption-propagation-report.json` 中 `uncovered` 为空，`assumption_dispositions` 数组为空，不影响 Gate B 结论。
```

**Step 3: 确认修改内容**

Read Gate B 章节，确认新增内容格式正确，JSON 代码块缩进正确，与章节整体风格一致。

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add assumption_dispositions to Gate B (v5 fix漏洞O)"
```

---

### Task 7：更新 Phase 5 API Change Detector 章节（漏洞 M）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Phase 5 章节中的 API Change Detector 部分）

**Step 1: 定位 API Change Detector 章节**

Grep `AutoStep 前置：\`API Change Detector\`` 定位 Phase 5 中的 API Change Detector 内容。

**Step 2: 更新 api-change-report.json 示例，新增 `phase_5_mode` 字段**

找到当前的 api-change-report.json 示例：
```json
{
  "autostep": "APIChangeDetector",
  "api_changed": true,
  ...
```
在其中新增 `phase_5_mode` 字段，并将现有的 `documentation_required` 说明替换为完整的四种场景说明。

新的示例：
```json
{
  "autostep": "APIChangeDetector",
  "api_changed": true,
  "changed_contracts": ["contract-1"],
  "change_type": ["response_field_added"],
  "phase_5_mode": "full",
  "documentation_required": true,
  "changelog_required": true
}
```

**Step 3: 将现有"Hotfix 文档策略"替换为"Phase 5 执行策略（v5 扩展）"**

将当前的两行策略：
```
- `api_changed: true` → 必须执行 Phase 5，更新对应 API 文档。
- `api_changed: false` → Hotfix 可跳过 Phase 5。
```

替换为四行完整策略矩阵：

```markdown
**Phase 5 执行策略（v5 扩展，修复漏洞 M）：**

| 场景 | `api_changed` | `mode` | `phase_5_mode` | Phase 5 执行内容 | Phase 5.1 是否运行 |
|------|--------------|--------|---------------|----------------|--------------------|
| 正常流程，API 有变更 | true | normal | `full` | API 文档 + CHANGELOG + ADR 最终化 | 是 |
| 正常流程，API 无变更 | false | normal | `changelog_only` | **仅更新 CHANGELOG**，跳过 API 文档 | 是（验证 CHANGELOG 覆盖 impl-manifest 文件变更） |
| Hotfix，API 有变更 | true | hotfix | `full` | API 文档 + CHANGELOG + ADR 最终化 | 是 |
| Hotfix，API 无变更 | false | hotfix | `skip` | 跳过整个 Phase 5 | 否 |

Documenter 读取 `state.json.phase_5_mode` 决定执行内容。`changelog_only` 模式下，Documenter 只更新 CHANGELOG，跳过 API 文档生成和 ADR 最终化。
```

**Step 4: 确认修改**

Read Phase 5 章节，确认四行策略矩阵格式正确，Markdown 表格列对齐。

**Step 5: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add phase_5_mode strategy to Phase 5 (v5 fix漏洞M)"
```

---

### Task 8：更新 Phase 4b Optimizer 章节（漏洞 P）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Phase 4b 章节）

**Step 1: 定位 Phase 4b 章节**

Grep `### Phase 4b：性能压测` 定位章节。读取当前的 perf-report.json 示例。

**Step 2: 更新 perf-report.json 示例，新增 `sla_violated` 字段**

找到当前示例：
```json
{
  "sla": { "p99_latency_ms": 200 },
  "results": {
    "api_get_user": { "p50_ms": 45, "p99_ms": 185, "verdict": "PASS" }
  },
  "slow_queries": [],
  "overall": "PASS"
}
```

替换为同时展示 PASS 和 FAIL 两种场景：

```markdown
**性能达标场景（进入 Gate D）：**

```json
{
  "sla": { "p99_latency_ms": 200 },
  "results": {
    "api_get_user": { "p50_ms": 45, "p99_ms": 185, "verdict": "PASS" }
  },
  "slow_queries": [],
  "sla_violated": false,
  "overall": "PASS"
}
```

**SLA 违规场景（直接回退 Phase 3，v5 修复漏洞 P）：**

```json
{
  "sla": { "p99_latency_ms": 200 },
  "results": {
    "api_get_user": { "p50_ms": 120, "p99_ms": 850, "verdict": "FAIL" }
  },
  "slow_queries": [
    { "query": "SELECT * FROM users WHERE email = ?", "avg_ms": 620, "file": "src/services/user.ts:84" }
  ],
  "sla_violated": true,
  "rollback_reason": "api_get_user p99=850ms 超出 SLA 上限 200ms，见 slow_queries",
  "rollback_to": "phase-3",
  "overall": "FAIL"
}
```
```

**Step 3: 在 "Gate D 统一验收 4a + 4b 的结果" 说明之前，追加 Orchestrator 行为说明**

```markdown
**Orchestrator 对 perf-report.json 的处理（v5 新增）：**
- `sla_violated: true` → 直接回退 Phase 3，不等待 Gate D。Optimizer 标注的 `slow_queries` 和 `rollback_reason` 注入对应 Builder 的输入上下文；递增对应 Builder 的 `builder_attempt_counts`。
- `sla_violated: false` → 正常进入 Gate D，由 Auditor-QA 做最终验收。
```

**Step 4: 确认修改**

Read Phase 4b 章节，确认两个 JSON 示例格式正确，Orchestrator 行为说明位置合理。

**Step 5: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add sla_violated direct rollback to Optimizer (v5 fix漏洞P)"
```

---

### Task 9：更新 Section 4 流水线全景图

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 4 的 ASCII 流程图）

**Step 1: 读取 Section 4 流程图**

Read Section 4 的 ASCII 流程图（```代码块内容），识别需要插入新节点的位置。

**Step 2: 在 Phase 0 输出之后、Gate A 之前插入 Phase 0.5**

找到：
```
│ Phase 0: Clarifier（需求澄清）                                  │
...
└─────────────────────────┬─────────────────────────────────────┘
                            │ 输出: requirement.md
                            ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ Gate A: Auditor-Biz / Tech / QA / Ops                        │
```

在 `requirement.md` 箭头之后、Gate A 框之前插入：
```
                ┌──────────────────────────────┐
                │ Phase 0.5: Requirement        │ ← AutoStep【v5 新增】
                │ Completeness Checker         │
                │ FAIL → 回退 Phase 0          │
                └────────────┬─────────────────┘
                             │ 输出: requirement-completeness-report.json
                             ▼
```

**Step 3: 在 Phase 2.6 输出之后、Phase 3 之前插入 Phase 2.7**

找到：
```
                │ Phase 2.6: Schema Completeness Validator      │
...
                             │ 输出: schema-validation-report.json
                             ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │ Phase 3: 并行实现                                                │
```

在 `schema-validation-report.json` 箭头之后、Phase 3 框之前插入：
```
                ┌──────────────────────────────┐
                │ Phase 2.7: Contract Semantic  │ ← AutoStep【v5 新增】
                │ Validator                    │
                │ Spectral + 字段类型比对脚本   │
                │ ERROR → 回退 Phase 2.5        │
                └────────────┬─────────────────┘
                             │ 输出: contract-semantic-report.json
                             ▼
```

**Step 4: 在 Phase 4a FAIL 路径中插入 Phase 4a.1**

找到 Phase 4a 框，在其 FAIL 路径说明中补充：
```
                             │ FAIL → Phase 4a.1 Test Failure Mapper → 精确/全体回退 Phase 3
```

**Step 5: 确认流程图完整性**

Read Section 4 完整代码块，确认三处新增节点格式与相邻节点对齐，箭头方向正确。

**Step 6: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: update pipeline overview diagram with v5 phases"
```

---

### Task 10：更新 Section 7.1 状态机（含全部 v5 状态）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 7.1 状态机代码块）

**Step 1: 读取 Section 7.1 状态机代码块**

Read Section 7.1，识别需要插入/修改的位置（共 5 处）。

**Step 2: 在 `PHASE_0_CLARIFICATION` 之后插入 Phase 0.5 状态**

在 `PHASE_0_CLARIFICATION` 状态行之后插入：
```
PHASE_0_5_REQUIREMENT_COMPLETENESS_CHECKER        ← AutoStep【v5 新增】
  │ FAIL（缺失必填内容）→ 回退 Phase 0
  ▼
```

**Step 3: 在 `PHASE_2_6_SCHEMA_COMPLETENESS_VALIDATOR` 之后插入 Phase 2.7 状态**

```
PHASE_2_7_CONTRACT_SEMANTIC_VALIDATOR             ← AutoStep【v5 新增，修复漏洞 K】
  │ ERROR → 回退 Phase 2.5（语义错误）
  │ WARN  → 不阻断，追加到 Gate C 参考输入
  ▼
```

**Step 4: 在 `PHASE_4A_FUNCTIONAL_TESTING` 的 FAIL 分支插入 Phase 4a.1**

将原来的：
```
  │ FAIL → 回退（含 3.1→3.6→Gate C→3.7，保留 new_test_files 标记）
```
替换为：
```
  ├─ PASS → PHASE_4_2_TEST_COVERAGE_ENFORCER
  └─ FAIL → PHASE_4A_1_TEST_FAILURE_MAPPER       ← AutoStep【v5 新增，修复漏洞 L】
               ├─ MAPPED      → 只回退 builders_to_rollback 中的 Builder（精确回退）
               └─ PARTIAL_MAPPED → 回退所有 Builder（降级，保留 new_test_files 标记）
```

**Step 5: 在 `PHASE_4B_PERFORMANCE_TESTING` 之后更新 Optimizer 回退逻辑**

将原来的 Phase 4b 部分更新为：
```
PHASE_4B_PERFORMANCE_TESTING (条件，串行)
  ├─ sla_violated: true  → 直接回退 Phase 3   ← v5 修复漏洞 P
  └─ sla_violated: false → GATE_D_QA_REVIEW
```

**Step 6: 在 `AUTOSTEP_API_CHANGE_DETECTOR` 更新 phase_5_mode 逻辑**

将原来的两行：
```
  │ api_changed: true  → PHASE_5_DOCUMENTATION（必须）
  │ api_changed: false + hotfix → SKIP_PHASE_5 → PHASE_6_0
```
替换为四行：
```
  │ 写入 phase_5_mode:                                    ← v5 修复漏洞 M
  │   api_changed: true  + normal  → full    → PHASE_5（完整）
  │   api_changed: false + normal  → changelog_only → PHASE_5（仅 CHANGELOG）
  │   api_changed: true  + hotfix  → full    → PHASE_5（完整）
  │   api_changed: false + hotfix  → skip    → PHASE_6_0（跳过 Phase 5）
```

**Step 7: 确认状态机完整性**

Read Section 7.1 完整代码块，确认所有新增状态格式正确，箭头方向一致。

**Step 8: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: update state machine with v5 phases and fixes"
```

---

### Task 11：更新 Section 8 目录结构（漏洞 N + 新产物）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 8 目录结构代码块）

**Step 1: 读取 Section 8 目录结构**

Read Section 8，定位重复的 `artifacts/` 目录（`adr-draft.md` 被放在第二个 `artifacts/` 子目录下）。

**Step 2: 删除重复的 `artifacts/` 嵌套，将 `adr-draft.md` 移入第一层 `artifacts/`**

找到类似以下的重复结构（漏洞 N）：
```
│   ├── artifacts/
│   │   └── adr-draft.md
```
删除这个额外的 `artifacts/` 层级，将 `adr-draft.md` 行移入第一个 `artifacts/` 目录，与其他产物并列：
```
│   │   ├── adr-draft.md         # Phase 1 Architect 输出【v4 新增，v5 路径修正】
```

**Step 3: 在 `artifacts/` 目录中新增 v5 产物文件**

在合适位置插入新产物（按阶段顺序）：
- `requirement-completeness-report.json` — 插入在 `requirement.md` 之后，标注 `# Phase 0.5 AutoStep【v5 新增】`
- `contract-semantic-report.json` — 插入在 `schema-validation-report.json` 之后，标注 `# Phase 2.7 AutoStep【v5 新增】`
- `failure-builder-map.json` — 插入在 `test-report.json` 之后，标注 `# Phase 4a.1 AutoStep【v5 新增，Phase 4a FAIL 时生成】`

**Step 4: 在 `autosteps/` 目录中新增三个脚本**

```
│   │   ├── requirement-completeness-checker.sh  # Phase 0.5【v5 新增】
│   │   ├── contract-semantic-validator.sh        # Phase 2.7【v5 新增】
│   │   └── test-failure-mapper.sh                # Phase 4a.1【v5 新增】
```

**Step 5: 确认目录结构**

Read Section 8，确认：① `artifacts/` 只出现一次；② 三个新产物按阶段顺序排列；③ `autosteps/` 包含三个新脚本。

**Step 6: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: fix directory structure duplicates and add v5 artifacts (v5 fix漏洞N)"
```

---

### Task 12：更新 Section 9 config.json 示例

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 9 的 config.json 代码块）

**Step 1: 定位 config.json 代码块**

Grep `"pipeline_name": "default"` 定位 Section 9 的 config.json 示例。

**Step 2: 在 `"clarification_max_rounds"` 之后新增 requirement_completeness 配置**

```json
"requirement_completeness": {
  "required_sections": ["功能描述", "用户故事", "验收标准", "范围边界"],
  "min_words": 200,
  "abort_on_critical_unresolved": true
},
```

**Step 3: 在 `autosteps` 对象中追加三个新 AutoStep 配置**

```json
"requirement-completeness-checker": {
  "script": ".pipeline/autosteps/requirement-completeness-checker.sh",
  "timeout_seconds": 10
},
"contract-semantic-validator": {
  "script": ".pipeline/autosteps/contract-semantic-validator.sh",
  "timeout_seconds": 60,
  "tools": ["spectral", "node"]
},
"test-failure-mapper": {
  "script": ".pipeline/autosteps/test-failure-mapper.sh",
  "timeout_seconds": 30
}
```

**Step 4: 确认 JSON 格式合法**

Read Section 9 的 config.json 代码块，确认新增内容：① JSON 逗号正确；② 缩进与已有内容一致；③ 无重复 key。

**Step 5: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add v5 autostep configs to config.json example"
```

---

### Task 13：更新 Section 12 角色汇总（AutoStep 数量）

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 12.3 AutoStep 表 + 汇总行）

**Step 1: 定位 Section 12.3**

Grep `### 12.3 AutoStep` 定位表格。

**Step 2: 在表格末尾追加三行**

```markdown
| **36** | **Requirement Completeness Checker** | AutoStep | **Phase 0.5** | **v5** |
| **37** | **Contract Semantic Validator** | AutoStep | **Phase 2.7** | **v5** |
| **38** | **Test Failure Mapper** | AutoStep | **Phase 4a.1（FAIL 时）** | **v5** |
```

**Step 3: 更新汇总行**

找到：
```
**共计 35 个执行单元：19 个常驻 Agent + 4 个条件 Agent + 12 个 AutoStep。**
```
替换为：
```
**共计 38 个执行单元：19 个常驻 Agent + 4 个条件 Agent + 15 个 AutoStep。**
```

**Step 4: Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: update role count to 38 in Section 12 (v5)"
```

---

### Task 14：更新 Section 13 总结 + Section 14 设计审查记录

**Files:**
- Modify: `claude-code-multi-agent-team-design.md`（Section 13 总结末尾 + Section 14.1 漏洞汇总表）

**Step 1: 在 Section 13 末尾追加 v5 新增改进要点**

在 v4 改进要点列表（第 31 条）之后，追加：

```markdown
**v5 新增改进要点：**

32. **需求完整性前置门禁（新活动 Phase 0.5）**：Requirement Completeness Checker AutoStep 在进入 Gate A 前机械验证需求文档的必填 Section、关键项清零、假设格式合规，让 Auditor 聚焦内容审查。

33. **契约语义校验（新活动 Phase 2.7，修复漏洞 K）**：Contract Semantic Validator AutoStep 使用 Spectral 和比对脚本，封堵"格式合法但语义错误"的 OpenAPI Schema，将发现点从 Phase 3.7 前移至 Phase 2.7，回退成本降至最低。

34. **测试失败精确归因（新活动 Phase 4a.1，修复漏洞 L）**：Test Failure Mapper AutoStep 通过覆盖率数据将测试失败映射到责任 Builder，实现精确回退，避免多 Builder 场景下的无辜全体回退。

35. **Phase 5 策略完整定义（修复漏洞 M）**：新增 `phase_5_mode` 字段，明确正常流程下 `api_changed: false` 时的 `changelog_only` 路径，消除状态机空白。

36. **Gate B 假设处置结构化（修复漏洞 O）**：gate-b-review.json 新增 `assumption_dispositions`，假设的处置决策从自然语言 comments 升级为可机械流转的结构化记录。

37. **Optimizer 直接回退（修复漏洞 P）**：perf-report.json 新增 `sla_violated` 字段，SLA 明确违规时 Orchestrator 无需等待 Gate D，直接触发 Phase 3 回退。
```

**Step 2: 在 Section 14.1 漏洞汇总表末尾追加 v5 修复的漏洞**

在最后一行（漏洞 J）之后追加六行：

```markdown
| 漏洞 K | Phase 2.6 只验证 OpenAPI 格式合法性，无法检测字段类型错误、路径参数 required 遗漏等语义错误，Builder 基于错误 Schema 实现后 Phase 3.7 才发现 | 新增 Phase 2.7 Contract Semantic Validator（Spectral + 比对脚本） | v5 |
| 漏洞 L | Phase 4a 测试失败后 test-report.json 无 Builder 责任映射，Orchestrator 只能全体回退，浪费无辜 Builder 的重做成本 | 新增 Phase 4a.1 Test Failure Mapper（AutoStep），精确映射责任 Builder | v5 |
| 漏洞 M | 正常流程下 api_changed: false 时 Phase 5 的执行策略未定义（状态机空白路径） | 新增 phase_5_mode: changelog_only，明确只更新 CHANGELOG 的 partial 执行路径 | v5 |
| 漏洞 N | 第 8 节目录结构 .pipeline/artifacts/ 出现两次，adr-draft.md 路径存在二义性 | 统一为单一 artifacts 目录，adr-draft.md 与其他产物并列 | v5 |
| 漏洞 O | gate-b-review.json 无字段记录 Auditor-Biz 对未覆盖假设的处置决策，假设是否被接受仅存于自然语言 comments | 新增 assumption_dispositions 数组，支持 ACCEPTED / REQUIRE_PLANNER_COVERAGE 机械流转 | v5 |
| 漏洞 P | Optimizer SLA 明确违规时无直接回退机制，需等待 Gate D 的主观审批，产生不必要延迟 | perf-report.json 新增 sla_violated 字段，Orchestrator 机械检测并直接触发 Phase 3 回退 | v5 |
```

**Step 3: 确认两处修改**

Read Section 13 末尾，确认 v5 要点编号从 32 开始；Read Section 14.1 末尾，确认 6 行新漏洞的列对齐。

**Step 4: 最终 Commit**

```bash
git add claude-code-multi-agent-team-design.md
git commit -m "docs: add v5 summary and design review records to Sections 13-14"
```

---

## 执行验证清单

所有 14 个 Task 完成后，执行以下验证：

```bash
# 1. 确认 v5 字样在文档头部出现
grep -n "v5 核心改进" claude-code-multi-agent-team-design.md

# 2. 确认三个新 AutoStep 的章节标题存在
grep -n "Phase 0.5\|Phase 2.7\|Phase 4a.1" claude-code-multi-agent-team-design.md

# 3. 确认 artifacts/ 只出现一次（漏洞 N 修复）
grep -n "├── artifacts/" claude-code-multi-agent-team-design.md

# 4. 确认 phase_5_mode 字段存在（漏洞 M 修复）
grep -n "phase_5_mode" claude-code-multi-agent-team-design.md

# 5. 确认总执行单元数更新为 38
grep -n "38 个执行单元" claude-code-multi-agent-team-design.md

# 6. 确认 assumption_dispositions 存在（漏洞 O 修复）
grep -n "assumption_dispositions" claude-code-multi-agent-team-design.md

# 7. 确认 sla_violated 存在（漏洞 P 修复）
grep -n "sla_violated" claude-code-multi-agent-team-design.md
```

所有 grep 均有输出则验证通过。
