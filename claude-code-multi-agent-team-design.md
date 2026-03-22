# Claude Code 多角色协作流水线设计方案（v4）

## 1. 概述

本方案定义了一套基于 Claude Code 的多角色、多阶段、带回溯的软件交付流水线系统。其核心思想是将软件开发生命周期中的关键环节拆解为具名角色（Named Agent）和自动化步骤（AutoStep），由一个主控状态机（Pilot）统一编排，通过结构化的中间产物在角色之间传递上下文，并在关键节点引入用户澄清机制，实现从需求到部署再到上线观测的全流程自动化。

**v2 核心改进：**
- 新增 4 个自动化步骤（AutoStep），将机械可验证的检查从 LLM 中剥离
- 新增 2.5.contract-formalize Contract Formalizer，将接口契约从自然语言升级为可机械验证的 Schema
- gate-b.plan-review 补入 Auditor-Biz，封堵任务细化阶段的业务偏差
- Optimizer 改为在 Tester 通过后串行执行，杜绝无效性能数据
- 全面量化 Monitor 告警阈值，消除 LLM 主观判断
- 精简报告的"已完成"改为 Pilot 机械验证，替代 LLM 自报

**v3 核心改进（基于逻辑漏洞分析）：**
- 新增 2.6.contract-validate-semantic Schema Completeness Validator，封堵 Contract Formalizer 输出错误 Schema 导致的 3.build 白费问题
- 新增 3.6.simplify-verify Post-Simplification Verifier，将精简效果从 LLM 自我承诺升级为机械量化验证（同时重跑回归守卫）
- 新增 3.7.contract-compliance Contract Compliance Checker，在功能测试前用工具自动验证 API 实现与 OpenAPI Schema 的契约合规性
- 新增 4.2.coverage-check Test Coverage Enforcer，补充新增代码的覆盖率量化门禁，防止只写 happy-path 测试
- 修复 gate-d.test-review 回退范围过宽问题：Auditor-QA 的 rollback_to 限制在 3.build / 2.plan，不得回退到 0.clarify/1.design
- 修复 CRITICAL 回滚执行主体未定义问题：明确由 Pilot 重新激活 Deployer 执行生产回滚
- 修复 Resolver 内容矛盾检测的职责混淆：将"是否需要仲裁"的判断改为关键词冲突算法，Resolver 只做仲裁不做判断
- 漏洞 5（Hotfix Diff Scope 死锁）：新增 Hotfix Scope Analyzer（置信度驱动），见 Section 14.2

**v4 核心改进（基于逻辑漏洞分析）：**
- 修复漏洞 A：新增 6.0.deploy-readiness Pre-Deploy Readiness Check AutoStep，定义 6.deploy 部署失败的明确处理路径
- 修复漏洞 B：明确 impl-manifest.json 写入协议（各 Builder 写临时文件，Pilot 汇总合并），消除并行写入竞争
- 修复漏洞 C：Resolver 覆盖规则增加下边界保护，禁止将 rollback_to 设为 null 以绕过所有审查
- 修复漏洞 D：3.7.contract-compliance Contract Compliance Checker 新增服务启动失败的明确处理路径（基础设施故障 → Escalation）
- 修复漏洞 E：gate-e.doc-review 新增 Auditor-Tech，保障 API 文档和 ADR 的技术准确性
- 修复漏洞 F：新增 2.1.assumption-check Assumption Propagation Validator AutoStep，追踪 requirement.md 中的 [ASSUMED:...] 假设是否在 tasks.json 中被显式覆盖
- 修复漏洞 G：新增测试文件"毕业"机制（Pipeline COMPLETED 时 Pilot 执行），将 new_test_files 写入 regression-suite-manifest.json
- 修复漏洞 H：state.json 中 attempt_counts 增加 per-builder 粒度，多 Builder 独立计数
- 修复漏洞 I：2.5.contract-formalize Contract Formalizer 改为模板驱动输出，LLM 只填充语义字段，格式由模板固定
- 修复漏洞 J：Builder-Security 新增产物 security-checklist.json，Inspector 和 Auditor-Tech 可引用
- 新增 1.design ADR 草稿：Architect 在 1.design 输出 adr-draft.md，保留决策理由，Documenter 在 5.document 最终化
- 新增 3.1.static-analyze SAST 扫描：Static Analyzer 增加 Semgrep/CodeQL 源码安全扫描，覆盖 OWASP Top 10 模式
- 新增 5.1.changelog-check Changelog Consistency Checker AutoStep：校验 CHANGELOG 与 api-change-report.json / impl-manifest.json 的一致性

**v5 核心改进（基于逻辑漏洞分析）：**
- 修复漏洞 K：新增 2.7.contract-validate-schema Contract Semantic Validator（AutoStep），使用 Spectral + 自定义脚本封堵"格式合法但语义错误"的 OpenAPI Schema，防止 Contract Formalizer 的类型/字段错误静默传递到 3.build
- 修复漏洞 L：新增 4a.1.test-failure-map Test Failure Mapper（AutoStep），分析测试失败的 Builder 责任归属，实现精确回退而非全体回退
- 修复漏洞 M：明确正常流程下 `api_changed: false` 时 5.document 的执行策略（新增 `phase_5_mode: changelog_only`），消除状态机空白路径
- 修复漏洞 N：修正第 8 节目录结构中 `.pipeline/artifacts/` 重复定义，统一 adr-draft.md 路径
- 修复漏洞 O：gate-b.plan-review.json 新增 `assumption_dispositions` 字段，将 gate-b.plan-review 对假设的处置决策升级为结构化记录，支持机械流转
- 修复漏洞 P：perf-report.json 新增 `sla_violated` 字段，Optimizer 明确发现 SLA 违规时直接触发 3.build 回退，不等待 gate-d.test-review
- 新增 0.5.requirement-check Requirement Completeness Checker（AutoStep）：需求文档进入 gate-a.design-review 前的格式与完整性机械门禁
- 新增 2.7.contract-validate-schema Contract Semantic Validator（AutoStep）：封堵 2.6.contract-validate-semantic 无法检测的语义错误，使用 Spectral + 脚本，无 LLM
- 新增 4a.1.test-failure-map Test Failure Mapper（AutoStep）：测试失败后精确映射责任 Builder，降低多 Builder 场景下的无辜回退成本

**v6 核心改进（基于逻辑漏洞分析）：**
- 修复漏洞 Q：Resolver conditions 字段升级为结构化 conditions_checklist，Pilot 在放行前机械验证每条条件是否满足，杜绝 Resolver 条件承诺成空话
- 修复漏洞 R：4a.1.test-failure-map Test Failure Mapper 流转规则新增 confidence 维度，LOW confidence 映射触发保守全体回退，防止不确定归属导致无辜 Builder 被精确回退
- 修复漏洞 S（高危）：0.5.requirement-check Section 标题检查从 H2 修正为 H3（在 `## 最终需求定义` 下查找 `### 功能描述` 等子节），修复对所有合法 requirement.md 永远输出 FAIL 的严重错误
- 修复漏洞 T：gate-d.test-review 产物 gate-d.test-review.json 补充结构化 rollback_to 字段，与 gate-a.design-review / gate-c.code-review 一致，Pilot 可机械解析回退目标
- 修复漏洞 U：new_test_files 的 Regression Guard 排除规则扩展为覆盖所有 3.build 回退路径（不限于 4a.test FAIL），统一全生命周期语义
- 修复漏洞 V：4a.test 产物列表新增 coverage.lcov（必须生成），消除 4a.1.test-failure-map 对覆盖率数据的隐式依赖；config.json 新增 testing 配置块
- 修复漏洞 W：state.json schema 补充 phase_5_mode 和 new_test_files 字段定义，明确写入时机，修复崩溃恢复时这两个关键字段丢失的问题

### 1.1 设计原则

- **角色单一职责**：每个 Agent 只负责一个明确的职能，拥有语义化的名字，便于识别和追踪。
- **自动化优先**：机械可验证的检查（linting、类型检查、文件范围校验、回归测试）优先使用 AutoStep，LLM Agent 聚焦需要判断力的任务，降低成本和不稳定性。
- **量化驱动精简**：代码复杂度由可测量指标（圈复杂度、认知复杂度、函数行数）驱动，Simplifier 以量化目标为输入，而非主观判断"是否冗余"。
- **契约形式化先于实现**：接口契约在 2.5.contract-formalize 被形式化为 OpenAPI/JSON Schema，后续实现阶段和审查阶段均可机械比对，而非依赖 LLM 阅读 Markdown 判断。
- **中止优于带假设继续**：关键需求信息缺失时，流程应能触发 ESCALATION 中止，而非带着未解决项推进，避免白白消耗所有后续开销。
- **变更范围合规**：每个 Builder 的实际代码变更必须严格在 tasks.json 授权范围内，由自动化工具机械校验。
- **用户参与澄清**：需求理解和方案设计阶段，Agent 主动与用户交互，消除歧义和遗漏。Clarifier 聚焦业务域，Architect 聚焦技术域，两者不重叠提问。
- **开放格式优先**：所有文档类产物必须使用 Markdown，严禁使用 Word、PDF 等私有/封闭格式；结构化数据使用 JSON/YAML 等开放标准格式。
- **产物驱动流转**：阶段之间通过落盘的文件传递信息，而非依赖对话上下文。
- **校验即门禁**：每个关键阶段后设置 Gate，由专职校验角色决定通过或打回。
- **代码精简先行**：Code Review 前必须先经过 Code Simplification，且 Simplifier 以静态分析的量化报告为输入。
- **可回溯**：任何阶段失败均可回退到指定的前置阶段；多个 Auditor 指定不同回退目标时，取最深（最早）的目标。
- **有限重试**：所有回溯均有最大重试次数限制，超限后 Escalation 到人工。
- **并行安全**：并行实现阶段基于形式化契约开发，文件冲突按依赖层次串行化。
- **Skill 加持**：各角色可调用成熟的 Skill 能力来提升产出质量，其中 `code-simplifier` 和 `code-review` 为流水线必备 Skill。
- **条件角色按需激活**：部分角色仅在满足特定条件时参与流水线，降低简单需求的流程开销。

### 1.2 术语定义

| 术语 | 含义 |
|------|------|
| Agent | 一个带有特定 system prompt 的 Claude 实例，拥有唯一名称，扮演某个角色 |
| AutoStep | 自动化步骤，由 Pilot 直接调用工具/脚本执行，不涉及 LLM，成本低、结果确定 |
| Pilot | 主控脚本/状态机，负责阶段流转、回溯、并行控制 |
| Gate | 校验关卡，由一个或多个 Reviewer Agent 组成，全部通过才放行 |
| Artifact | 阶段产物，文档类使用 Markdown，结构化数据使用 JSON/YAML |
| Escalation | 超过重试上限或关键信息缺失时暂停流程，请求人工介入 |
| Clarification | 用户澄清环节，Agent 主动向用户提问以消除歧义 |
| Skill | 可复用的能力模块（如代码审查、代码精简等），Agent 按需调用 |
| Conditional Agent | 条件角色，仅在满足激活条件时参与流水线 |
| Rollback Depth Rule | 多 Auditor 指定不同回退目标时，取最深（最早的 Phase）作为最终 rollback_to |

### 1.3 产物格式规范

流水线中的产物分为两类，各自使用最合适的开放格式：

**文档类产物 → Markdown（`.md`）**

| 产物 | 格式 | 生产者 |
|------|------|--------|
| 需求文档 | `.md` | Clarifier |
| 技术方案（Proposal） | `.md` | Architect |
| 代码精简报告 | `.md` | Simplifier |
| 代码审查报告（详细） | `.md` | Inspector |
| 回溯反馈 | `.md` | Auditor/Inspector |
| API 文档、用户手册、CHANGELOG | `.md` | Documenter |
| 架构决策记录（ADR） | `.md` | Documenter |
| 各角色 system prompt | `.md` | 人工维护 |

**结构化数据 → JSON（`.json`）**

| 产物 | 格式 | 生产者 |
|------|------|--------|
| Gate 校验结果（结论） | `.json` | Auditor/Inspector |
| 任务列表与接口契约（自然语言） | `.json` | Planner |
| 形式化契约（OpenAPI/Schema） | `.json` | Contract Formalizer (AutoStep) |
| 实现清单 | `.json` | Builders |
| 静态分析报告 | `.json` | Static Analyzer (AutoStep) |
| 变更范围校验报告 | `.json` | Diff Scope Validator (AutoStep) |
| 回归守卫报告 | `.json` | Regression Guard (AutoStep) |
| 测试报告 | `.json` | Tester |
| 性能报告 | `.json` | Optimizer |
| 文档清单 | `.json` | Documenter |
| 部署报告 | `.json` | Deployer |
| 观测报告 | `.json` | Monitor |
| 流水线状态 | `.json` | Pilot |
| 流水线配置 | `.json` | 人工维护 |

---

## 2. 角色命名总览

所有角色采用**职能英文名**命名，语义清晰，便于日志、可视化和流程追踪。角色分为**常驻 Agent**、**条件 Agent** 和**自动化步骤（AutoStep）**。

### 2.1 常驻 Agent 表

| 角色名 | 中文名 | 阶段 | 职责概述 | 可用 Skill |
|--------|--------|------|---------|------------|
| **Clarifier** | 需求澄清师 | 0.clarify | 业务域澄清，输出结构化需求文档；关键项未解决时触发 ESCALATION | `doc-coauthoring` |
| **Architect** | 方案架构师 | 1.design | 技术域澄清，将需求转化为技术方案 | `doc-coauthoring` |
| **Auditor-Biz** | 业务审核官 | gate-a.design-review / **gate-b.plan-review** | 审核业务完整性和合理性 | — |
| **Auditor-Tech** | 技术审核官 | gate-a.design-review / gate-b.plan-review / **gate-e.doc-review**（v4 新增） | 架构合理性、性能、安全；gate-e.doc-review 中审查 API 文档技术准确性和 ADR 决策质量 | — |
| **Auditor-QA** | 测试审核官 | gate-a.design-review / gate-b.plan-review / gate-d.test-review / gate-e.doc-review | 审核测试策略、用例覆盖度；gate-e.doc-review 中审查 CHANGELOG 完整性和测试文档 | — |
| **Auditor-Ops** | 运维审核官 | gate-a.design-review / gate-b.plan-review | 审核部署策略、回滚方案、基础设施影响 | — |
| **Planner** | 任务规划师 | 2.plan | 将 Proposal 拆解为文件级别的具体任务和自然语言接口契约 | — |
| **Contract Formalizer** | 契约形式化师 | 2.5.contract-formalize | 将 tasks.json 中的自然语言契约转为 OpenAPI/JSON Schema | — |
| **Builder-Frontend** | 前端工程师 | 3.build | 实现前端代码 | `frontend-design` |
| **Builder-Backend** | 后端工程师 | 3.build | 实现后端 API、业务逻辑 | — |
| **Builder-DBA** | 数据库工程师 | 3.build | 编写数据库迁移脚本、Schema 变更 | — |
| **Builder-Security** | 安全工程师 | 3.build | 权限控制、安全加固、输入校验；产出 `security-checklist.json`（v4 新增） | — |
| **Builder-Infra** | 基础设施工程师 | 3.build | CI/CD、Docker、K8s 配置 | — |
| **Simplifier** | 代码精简师 | 3.5.simplify | 以静态分析的量化指标为目标，对实现代码进行精简优化 | **`code-simplifier`**（必备） |
| **Inspector** | 代码审查员 | gate-c.code-review | 基于 code-review skill 进行专业代码审查 | **`code-review`**（必备） |
| **Tester** | 测试工程师 | 4a.test | 编写并执行自动化功能测试 | — |
| **Documenter** | 文档工程师 | 5.document | 生成/更新 API 文档、CHANGELOG、用户手册、README、ADR（均为 Markdown） | — |
| **Deployer** | 部署工程师 | 6.deploy | 执行部署、Smoke Test、回滚 | — |
| **Monitor** | 上线观测员 | 7.monitor | 基于量化阈值观测错误率、性能指标、日志异常，输出 NORMAL/ALERT/CRITICAL | — |

### 2.2 条件 Agent 表

| 角色名 | 中文名 | 阶段 | 职责概述 | 激活条件 |
|--------|--------|------|---------|---------|
| **Migrator** | 数据迁移工程师 | 3.build（与 Builders 并行） | 编写存量数据迁移脚本、数据校验逻辑 | `data_migration_required: true` |
| **Resolver** | 冲突协调员 | 任意 Gate | 当 Auditor 反馈存在矛盾时仲裁（可覆盖 rollback 深度） | 矛盾检测算法触发（见 2.4） |
| **Optimizer** | 性能优化师 | 4b.optimize（Tester PASS 后串行） | 性能压测、SQL 慢查询分析、内存 profiling | `performance_sensitive: true` |
| **Translator** | 国际化工程师 | 3.build（与 Builders 并行） | 文案提取、翻译管理、多语言渲染验证 | `i18n_required: true` |

### 2.3 自动化步骤（AutoStep）表

AutoStep 由 Pilot 直接调用脚本/工具执行，**不涉及 LLM**，结果确定，成本极低。

| 步骤名 | 阶段 | 职责 | 输入 | 输出 |
|--------|------|------|------|------|
| **Static Analyzer** | 3.1.static-analyze | linter + 类型检查 + 依赖安全扫描 + 复杂度量化 | 变更文件列表 | `static-analysis-report.json` |
| **Diff Scope Validator** | 3.2.diff-validate | 校验每个 Builder 实际修改文件严格在 tasks.json 授权范围内 | git diff + tasks.json | `scope-validation-report.json` |
| **Regression Guard** | 3.3.regression-guard | 运行现有测试套件，保护已有功能不被新代码破坏 | 测试套件 | `regression-report.json` |
| **API Change Detector** | 5.document（前置） | 对比 contracts/ 与部署产物，判断 API 是否变更，决定 Hotfix 是否跳过文档 | old/new contracts | `api-change-report.json` |
| **Schema Completeness Validator** | 2.6.contract-validate-semantic【v3 新增】 | 验证 Contract Formalizer 输出的 Schema 数量与 tasks.json contracts 一致，且每个文件均为合法 OpenAPI 3.0 格式 | contracts/ + tasks.json | `schema-validation-report.json` |
| **Post-Simplification Verifier** | 3.6.simplify-verify【v3 新增】 | 精简后重新测量复杂度指标验证量化目标达成，同时重跑 Regression Guard 确认精简未破坏现有功能 | 精简后代码 + static-analysis-report.json | `post-simplify-report.json` |
| **Contract Compliance Checker** | 3.7.contract-compliance【v3 新增】 | gate-c.code-review PASS 后，用 dredd/schemathesis 对照 OpenAPI Schema 自动测试 API 实现，机械验证契约合规性 | contracts/ + 运行中的服务 | `contract-compliance-report.json` |
| **Test Coverage Enforcer** | 4.2.coverage-check【v3 新增】 | 检查 Tester 新增测试对 impl-manifest.json 中新增代码的行/分支覆盖率，低于配置阈值则回退 4a.test | 覆盖率报告 + impl-manifest.json | `coverage-report.json` |
| **Hotfix Scope Analyzer** | 7.monitor ALERT 后置【v3 新增】 | 基于置信度规则判断 hotfix 修复范围：HIGH 时机械生成 hotfix-tasks.json；LOW 时向用户单次确认后生成 | monitor-report.json + contracts/ + tasks.json + impl-manifest.json | `hotfix-scope-report.json` + `hotfix-tasks.json` |
| **Assumption Propagation Validator** | 2.1.assumption-check【v4 新增】 | 提取 requirement.md 中所有 `[ASSUMED:...]` 条目，检查 tasks.json 中是否每条假设均有对应任务或 notes 引用；无覆盖则 WARN/FAIL | requirement.md + tasks.json | `assumption-propagation-report.json` |
| **Changelog Consistency Checker** | 5.1.changelog-check【v4 新增】 | 校验 CHANGELOG 中 API 变更条目数 ≥ api-change-report.json 中 changed_contracts 数；校验 CHANGELOG 涉及模块覆盖 impl-manifest.json 中 files_changed 的主要路径 | CHANGELOG.md + api-change-report.json + impl-manifest.json | `changelog-check-report.json` |
| **Pre-Deploy Readiness Check** | 6.0.deploy-readiness【v4 新增】 | 部署前验证：环境变量完整性（对照 proposal.md 依赖清单）、数据迁移脚本存在性（if data_migration_required）、rollback_command 已在 deploy-plan 中定义 | proposal.md + state.json + deploy-plan.md | `deploy-readiness-report.json` |
| **Requirement Completeness Checker** | 0.5.requirement-check【v5 新增】 | 验证 requirement.md 必填 Section 存在且非空、`[CRITICAL-UNRESOLVED]` 数量为 0、`[ASSUMED:...]` 格式合规、最小字数达标 | requirement.md | `requirement-completeness-report.json` |
| **Contract Semantic Validator** | 2.7.contract-validate-schema【v5 新增】 | Spectral 校验 RESTful 语义规则（路径参数 required、operationId、GET 无 requestBody）+ 自定义脚本比对 tasks.json definition 字段类型与 OpenAPI Schema 一致性 | contracts/ + tasks.json | `contract-semantic-report.json` |
| **Test Failure Mapper** | 4a.1.test-failure-map【v5 新增，FAIL 时触发】 | 解析 coverage.lcov 提取失败测试涉及的文件，与 impl-manifest.json 交叉映射到责任 Builder，输出 builders_to_rollback 精确回退列表 | test-report.json + coverage.lcov + impl-manifest.json | `failure-builder-map.json` |

### 2.4 条件角色激活机制

**gate-a.design-review 通过后（进入 2.plan 前）：**

解析 `proposal.md` 中的条件角色标记区域，将激活结果写入 `state.json`：

```
data_migration_required: true  → 激活 Migrator
performance_sensitive: true    → 激活 Optimizer
i18n_required: true            → 激活 Translator
```

**任意 Gate 校验过程中（Resolver 激活逻辑）：**

Pilot 按以下算法检测矛盾：

1. **结论矛盾（机械检测）**：同一 Gate 中，同一组件或同一校验项，一个 Auditor 给出 PASS，另一个给出 FAIL → 立即激活 Resolver。
2. **内容矛盾（关键词算法检测）**：提取所有 Auditor 的 `comments` 字段，Pilot 用关键词对算法检测相互否定的表述（如"必须使用 X"与"禁止使用 X"、"需要 Y"与"不应 Y"），命中则激活 Resolver 仲裁。Resolver 只负责仲裁，不负责判断是否需要仲裁（避免 LLM 判断 LLM 的递归问题）。

**Rollback Depth Rule（多 Auditor rollback_to 冲突）：**

- 默认规则：取所有 Auditor 中最深（最早 Phase）的 `rollback_to` 作为 `overall.rollback_to`。
- 覆盖例外：Resolver 仲裁后，若认为浅层回退足以修复所有问题，可在 `resolver_verdict.rollback_to` 字段覆盖默认值。
- Pilot 优先采用 Resolver 的覆盖值（如存在），否则使用最深规则。
- **下边界保护（v4 新增）**：Pilot 验证 `resolver_verdict.rollback_to` 不得为 `null`；若为 null 且存在任何 FAIL Auditor，Pilot 拒绝该覆盖并回退到默认最深规则，同时在日志中记录 `[WARN] Resolver 试图绕过回退被拒绝`。Resolver 可将深层回退升浅，但不能完全消除回退。

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

### 2.5 问题域划分（Clarifier vs Architect）

为避免用户被重复提问，两个澄清角色有明确的问题域边界：

| 问题类型 | 归属 |
|----------|------|
| 功能是什么（What） | Clarifier |
| 用户是谁（Who） | Clarifier |
| 为什么需要（Why） | Clarifier |
| 验收标准 | Clarifier |
| 范围边界（含/不含） | Clarifier |
| 非功能需求的业务侧（"要快"、"要稳"） | Clarifier |
| 如何实现（How） | Architect |
| 技术选型（Which technology） | Architect |
| 非功能需求的技术指标（p99 < 200ms） | Architect |
| 接口设计细节 | Architect |
| 数据模型设计 | Architect |

**规则**：Clarifier 遇到技术问题时，在需求文档中标注 `[技术待确认]` 而非向用户提问，交由 Architect 在 1.design 处理。

### 2.6 角色标识规范

每个角色在日志和产物中使用统一的标识格式：

```
[Clarifier]          需求澄清完成 → 输出: requirement.md
[Architect]          技术方案生成完成 → 输出: proposal.md
[Contract Formalizer] 契约形式化完成 → 输出: contracts/ (3 个 Schema)
[AutoStep:Static]    静态分析完成: 圈复杂度超标 2 处，依赖漏洞 0 个
[AutoStep:DiffScope] 变更范围校验: PASS (所有变更在授权范围内)
[AutoStep:Regression] 回归守卫: PASS (83 个现有测试全部通过)
[Simplifier]         代码精简完成: 降低圈复杂度 3→1 (2处), 提取公共函数 2 个
[Inspector]          gate-c.code-review 审查: FAIL — 1 个 MAJOR 问题
[Monitor]            上线 30 分钟: 错误率 0.01% (阈值 0.1%), P99 180ms (阈值 200ms) → NORMAL
```

AutoStep 使用 `[AutoStep:<名称>]` 前缀；Pilot 使用 `[Pipeline]` 前缀：

```
[Pipeline] 3.build 完成 → AutoStep:Static (3.1.static-analyze)
[Pipeline] AutoStep:DiffScope PASS → AutoStep:Regression (3.3.regression-guard)
[Pipeline] 3.3.regression-guard PASS → 3.5.simplify (Simplifier)
[Pipeline] gate-c.code-review FAIL → rollback 3.build (attempt 2/3)
[Pipeline] 4b.optimize SKIP (performance_sensitive: false)
```

---

## 3. 必备 Skill 定义

流水线要求以下两个 Skill 必须存在且在对应阶段强制使用，维护在 `.pipeline/skills/` 目录下。

### 3.1 `code-simplifier` Skill（代码精简）

**用途**：在代码审查之前，以静态分析的量化指标为目标，对所有新增和修改的代码进行精简优化。

**使用角色**：`Simplifier`

**Skill 内容**（`.pipeline/skills/code-simplifier/SKILL.md`）：

```markdown
# Skill: code-simplifier

## 目标
以 static-analysis-report.json 中的量化指标为输入，对实现阶段产出的代码进行精简和优化，
降低复杂度，提升可读性和可维护性。
代码精简是 Code Review 的前置必要步骤——Inspector 审查的必须是精简后的代码。

## 量化输入（来自 static-analysis-report.json）

精简前，读取 static-analysis-report.json，提取以下指标作为优化目标：
- complexity_issues: 圈复杂度 > 10 或认知复杂度 > 15 的函数列表 → 必须降低
- long_functions: 行数 > 50 的函数列表 → 必须拆分
- long_files: 行数 > 300 的文件列表 → 考虑拆分
- naming_issues: 单字母变量名、不规范布尔命名等 → 必须修复
- duplicate_blocks: 重复代码块 → 必须提取

## 精简维度

### 1. 冗余消除
- 移除未使用的 import、变量、函数、类型定义
- 移除注释掉的代码（dead code）
- 移除多余的日志输出（仅保留必要的错误日志和关键业务日志）
- 合并重复的条件分支

### 2. 逻辑简化（优先处理量化报告中标记的问题）
- 嵌套超过 3 层的条件判断 → 提前返回（early return）或提取函数
- 超过 50 行的函数 → 拆分为多个职责单一的小函数
- 重复出现 2 次以上的代码块 → 提取公共函数或工具方法
- 复杂的三元表达式 → 改为 if/else 或提取为具名变量

### 3. 命名优化
- 单字母变量名（循环变量除外） → 语义化命名
- 布尔变量/函数命名必须以 is/has/can/should 开头
- 函数命名必须是动词短语，准确反映行为

### 4. 结构优化
- 文件超过 300 行 → 考虑拆分
- 一个模块承担多个职责 → 按职责拆分
- 硬编码的魔法数字/字符串 → 提取为常量

## 输出格式
输出 Markdown 格式的精简报告（simplify-report.md）+ 实际代码修改。
报告必须包含：每处修改前后的对比、对应的量化指标改善（如"圈复杂度 8→3"）。

## 约束
- 精简不得改变任何业务逻辑和功能行为
- 精简不得修改 Regression Guard 已验证通过的现有测试用例
- 每一处修改必须在报告中说明原因和对应的量化改善
- 如果某处代码看似冗余但有合理理由保留，标注 [KEPT] 并说明
```

### 3.2 `code-review` Skill（代码审查）

**用途**：为 Inspector 提供专业、系统的代码审查框架，确保审查的全面性和一致性。

**使用角色**：`Inspector`

**Skill 内容**（`.pipeline/skills/code-review/SKILL.md`）：

```markdown
# Skill: code-review

## 目标
对精简后的代码进行全面、专业的审查，输出结构化的 Review 报告。
Inspector 审查的代码必须已经通过 Simplifier 的精简处理（由 Pilot 机械验证）。

## 前置验证（由 Pilot 执行，非 Inspector 自报）
Pilot 在启动 Inspector 前，自动验证：
1. simplify-report.md 的最后修改时间晚于 impl-manifest.json 的最后修改时间
2. simplify-report.md 文件大小 > 0（非空文件）
以上两项均满足，Pilot 才启动 Inspector，并在 gate-c.code-review.json 中
设置 simplifier_verified: true。Inspector 无需自行判断。

## 审查维度

### 1. 正确性（Correctness）
- 逻辑是否正确实现了 tasks.json 中定义的需求？
- 边界条件是否处理（空值、零值、最大值、并发）？
- 错误处理是否完整（异常捕获、错误码、错误信息）？
- 异步操作是否正确处理（Promise、async/await、竞态条件）？

### 2. 安全性（Security）
- 用户输入是否经过校验和清洗？
- SQL 是否使用参数化查询（防注入）？
- 敏感信息（密码、token、密钥）是否脱敏处理？
- 接口是否有适当的认证和授权检查？
- 是否存在 XSS、CSRF、SSRF 风险？

### 3. 性能（Performance）
- 是否存在 N+1 查询？
- 大数据量操作是否有分页/流式处理？
- 是否有不必要的内存拷贝或对象创建？
- 数据库索引是否充分？
- 是否有潜在的内存泄漏（未释放的连接、未清理的定时器）？

### 4. 可维护性（Maintainability）
- 代码是否符合项目编码规范？
- 关键逻辑是否有适当的注释？
- 接口是否向后兼容？
- 是否有适当的日志便于排查问题？

### 5. 契约一致性（Contract Compliance）
- 实现是否严格符合 contracts/ 中的形式化 Schema？
- 请求/响应的字段名、类型、格式是否与 Schema 一致？
- HTTP 状态码是否符合 RESTful 规范？
- 注意：scope-validation-report.json 已验证文件范围合规，无需重复校验。

### 6. 测试可行性（Testability）
- 代码是否可测试（依赖是否可注入/mock）？
- 复杂逻辑是否有足够的可测试入口？

## 严重级别

| 级别 | 含义 | 是否阻断 |
|------|------|---------|
| CRITICAL | 严重 bug、安全漏洞、数据丢失风险 | 是，必须修复 |
| MAJOR | 逻辑错误、性能隐患、不符合契约 | 是，必须修复 |
| MINOR | 代码风格、命名建议、可选优化 | 否，建议修复 |
| INFO | 表扬好的实践、知识分享 | 否 |

## 审查结果判定
- 存在任何 CRITICAL 或 MAJOR 问题 → verdict: FAIL
- 仅有 MINOR 和 INFO → verdict: PASS（附建议）

## 输出格式
输出 Markdown 格式的 Review 报告（gate-c.code-review.md），其中的结论性数据
（verdict、rollback_to 等）同步写入 gate-c.code-review.json 供 Pilot 解析。
```

---

## 4. 流水线全景

```
   用户输入（需求/Bug）
        │
        ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ 0.clarify: Clarifier（需求澄清）                                  │
  │ 业务域澄清，最多 5 轮；关键项未解决 → ESCALATION（不继续推进）      │
  │ 技术问题标注 [技术待确认]，不向用户提问                           │
  └─────────────────────────┬─────────────────────────────────────┘
                            │ 输出: requirement.md
                            ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ 0.5.requirement-check: Requirement Completeness Checker                   │ ← AutoStep【v5 新增】
  │ 验证 requirement.md 必填字段完整性                              │
  │ FAIL → 回退 0.clarify                                           │
  └─────────────────────────┬─────────────────────────────────────┘
                            │ 输出: requirement-completeness-report.json
                            ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ 1.design: Architect（方案设计）                                  │
  │ 技术域澄清，处理 [技术待确认] 项；有权向用户提问技术问题             │
  └─────────────────────────┬─────────────────────────────────────┘
                            │ 输出: proposal.md
                            ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ gate-a.design-review: Auditor-Biz / Tech / QA / Ops                        │
  │ [Resolver: 矛盾检测算法触发时激活]                              │
  │ rollback_to: 取最深目标（Resolver 可覆盖）                      │
  └─────────────────────────┬─────────────────────────────────────┘
                            │ PASS → 解析 proposal.md 激活条件角色
                            ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ 2.plan: Planner（任务细化）                                    │
  │ 输出自然语言接口契约                                            │
  └─────────────────────────┬─────────────────────────────────────┘
                            │ 输出: tasks.json
                            ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ 2.1.assumption-check: Assumption Propagation Validator                   │ ← AutoStep【v4 新增】
  │ 追踪 requirement.md [ASSUMED:...] 是否在 tasks.json 中被覆盖   │
  │ 未覆盖假设附加给 gate-b.plan-review 的 Auditor-Biz                         │
  └─────────────────────────┬─────────────────────────────────────┘
                            │ 输出: assumption-propagation-report.json
                            ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ gate-b.plan-review: Auditor-Biz / Tech / QA / Ops（全 4 个）              │
  │ [Resolver: 矛盾时激活]                                         │
  └─────────────────────────┬─────────────────────────────────────┘
                            │ PASS
                            ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ 2.5.contract-formalize: Contract Formalizer（契约形式化）【v2 新增】          │
  │ 模板驱动：Pilot 生成骨架，LLM 填充语义字段【v4 改进】     │
  └─────────────────────────┬─────────────────────────────────────┘
                            │ 输出: contracts/ 目录
                            ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ 2.6.contract-validate-semantic: Schema Completeness Validator                      │ ← AutoStep【v3 新增】
  │ 验证 Schema 数量与 tasks.json contracts 一致                   │
  │ 验证每个文件为合法 OpenAPI 3.0 格式                             │
  │ 失败 → 回退 2.5.contract-formalize（不进入 3.build 实现）                    │
  └─────────────────────────┬─────────────────────────────────────┘
                            │ 输出: schema-validation-report.json
                            ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ 2.7.contract-validate-schema: Contract Semantic Validator                        │ ← AutoStep【v5 新增】
  │ Spectral + 字段类型比对脚本                                     │
  │ ERROR → 回退 2.5.contract-formalize                                        │
  └─────────────────────────┬─────────────────────────────────────┘
                            │ 输出: contract-semantic-report.json
                            ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │ 3.build: 并行实现                                                │
  │ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌─────────┐ │
  │ │Builder- │ │Builder- │ │Builder- │ │Builder-  │ │Builder- │ │
  │ │Frontend │ │Backend  │ │  DBA    │ │Security  │ │ Infra   │ │
  │ └─────────┘ └─────────┘ └─────────┘ └──────────┘ └─────────┘ │
  │ ┌────────────┐ ┌──────────────┐                               │
  │ │ [Migrator] │ │ [Translator] │ ← 条件角色                     │
  │ └────────────┘ └──────────────┘                               │
  │ 文件冲突：按 DBA→Backend→Security→Frontend→Infra 依赖层次串行化  │
  └──────────────────────────┬──────────────────────────────────────┘
                             │ 输出: impl-manifest.json
                             ▼
                ┌──────────────────────────────┐
                │ 3.1.static-analyze: Static Analyzer    │ ← AutoStep【新增】
                │ linter + 类型检查 + 依赖安全扫描│
                │ + 复杂度量化（圈/认知复杂度）   │
                └────────────┬─────────────────┘
                             │ 输出: static-analysis-report.json
                             │ 有严重静态错误 → 回退 3.build
                             ▼
                ┌──────────────────────────────┐
                │ 3.2.diff-validate: Diff Scope Validator│ ← AutoStep【新增】
                │ 校验实际变更严格在 tasks.json  │
                │ 授权文件范围内                 │
                └────────────┬─────────────────┘
                             │ 输出: scope-validation-report.json
                             │ 越权变更 → 回退 3.build（指定 Builder）
                             ▼
                ┌──────────────────────────────┐
                │ 3.3.regression-guard: Regression Guard   │ ← AutoStep【新增】
                │ 运行现有测试套件               │
                │ 保护已有功能不被新代码破坏      │
                └────────────┬─────────────────┘
                             │ 输出: regression-report.json
                             │ 有现有测试失败 → 回退 3.build
                             ▼
                ┌──────────────────────────────┐
                │ 3.5.simplify: Simplifier         │ ← code-simplifier skill（必备）
                │ 以量化指标为目标精简代码       │
                │ 输出 simplify-report.md        │
                └────────────┬─────────────────┘
                             │ Pilot 机械验证:
                             │ simplify-report.md 修改时间 > impl-manifest.json 修改时间
                             ▼
                ┌──────────────────────────────┐
                │ 3.6.simplify-verify: Post-Simplification │ ← AutoStep【v3 新增】
                │ Verifier                      │
                │ 重测复杂度指标（验证量化目标达成）│
                │ 重跑 Regression Guard          │
                │ 任一失败 → 回退 3.5.simplify      │
                └────────────┬─────────────────┘
                             │ 输出: post-simplify-report.json
                             ▼
                ┌──────────────────────────────┐
                │  gate-c.code-review: Inspector            │ ← code-review skill（必备）
                │  simplifier_verified 由       │
                │  Pilot 机械设置         │
                │                              │── FAIL → 回退 3.build
                └────────────┬─────────────────┘   （重新经过 3.1 → 3.2 → 3.3 → 3.5 → 3.6）
                             │ PASS
                             ▼
                ┌──────────────────────────────┐
                │ 3.7.contract-compliance: Contract Compliance │ ← AutoStep【v3 新增】
                │ Checker                       │
                │ dredd/schemathesis 对照 OpenAPI│
                │ Schema 自动测试 API 实现        │
                │ FAIL → 回退 3.build（对应 Builder）│
                └────────────┬─────────────────┘
                             │ 输出: contract-compliance-report.json
                             ▼
                ┌──────────────────────────────┐
                │ 4a.test: Tester              │
                │ 功能测试（新功能）             │
                │ 注：Tester 新增测试文件标记为   │
                │ "本次新增"，3.3 回归不纳入      │
                └────────────┬─────────────────┘
                             │ 输出: test-report.json
                             │ FAIL → 4a.1.test-failure-map Test Failure Mapper → 精确/全体回退 3.build
                             ▼
                ┌──────────────────────────────┐
                │ 4.2.coverage-check: Test Coverage      │ ← AutoStep【v3 新增】
                │ Enforcer                      │
                │ 检查新增代码的行/分支覆盖率     │
                │ 低于阈值 → 回退 4a.test       │
                └────────────┬─────────────────┘
                             │ 输出: coverage-report.json
                             ▼
                ┌──────────────────────────────┐
                │ 4b.optimize: [Optimizer]         │ ← 条件角色，等 4a+4.2 PASS 后串行启动
                │ 性能压测（performance_sensitive）│
                └────────────┬─────────────────┘
                             │ 输出: perf-report.json
                             ▼
                       ┌───────────┐
                       │  gate-d.test-review   │
                       │ Auditor-QA│──── FAIL → 回退（4a.test / 3.build，不得超过 2.plan）
                       │ 测试验收   │
                       └─────┬─────┘
                             │ PASS
                             ▼
                ┌──────────────────────────────┐
                │ AutoStep: API Change Detector │ ← 判断是否需要文档更新
                │ 对比 contracts/ 与旧版契约    │
                └────────────┬─────────────────┘
                             │ 输出: api-change-report.json
                             ▼
                       ┌────────────┐
                       │ 5.document    │ Hotfix 时：API 有变更 → 必须更新文档
                       │ Documenter │ Hotfix 时：API 无变更 → 可跳过
                       │ 文档 + ADR │ (基于 adr-draft.md 最终化【v4】)
                       └─────┬──────┘
                             ▼
                ┌──────────────────────────────┐
                │ 5.1.changelog-check: Changelog         │ ← AutoStep【v4 新增】
                │ Consistency Checker          │
                │ FAIL → 回退 5.document          │
                └────────────┬─────────────────┘
                             ▼
                       ┌─────────────────────────┐
                       │  gate-e.doc-review                  │ ← v4: 新增 Auditor-Tech
                       │ Auditor-QA + Auditor-Tech│──── FAIL → 回退 5.document
                       └────────────┬────────────┘
                             │ PASS
                             ▼
                ┌──────────────────────────────┐
                │ 6.0.deploy-readiness: Pre-Deploy        │ ← AutoStep【v4 新增】
                │ Readiness Check              │
                │ FAIL → Escalation            │
                └────────────┬─────────────────┘
                             ▼
                       ┌───────────┐
                       │ 6.deploy   │ FAIL → 明确失败路径【v4 定义】
                       │ Deployer  │
                       └─────┬─────┘
                             ▼
                       ┌───────────────────────────────────────────┐
                       │ 7.monitor: Monitor（量化阈值驱动）           │
                       │ NORMAL   → COMPLETED                      │
                       │ ALERT    → Hotfix Scope Analyzer          │
                       │            HIGH → 机械生成 hotfix-tasks.json│
                       │            LOW  → 单次用户确认后生成        │
                       │            → 3.build hotfix               │
                       │ CRITICAL → Pilot 激活 Deployer 回滚 │
                       │            → 1.design                      │
                       └───────────────────────────────────────────┘
```

---

## 5. 阶段详细设计

### 0.clarify：需求澄清（Clarification）

**负责角色：** `Clarifier`（需求澄清师）

**可用 Skill：** `doc-coauthoring`

**产物：** `.pipeline/artifacts/requirement.md`

**澄清域限制：** Clarifier 仅提业务侧问题。遇到技术问题时，在文档中标注 `[技术待确认: <问题描述>]`，不向用户提问。

**Pilot 行为：**
- Clarifier 每轮生成问题后，Pilot 暂停流水线，将问题展示给用户。
- 用户回答后，Pilot 将回答传回 Clarifier。
- 最多 5 轮澄清（可配置）。
- 5 轮后若仍存在 `[CRITICAL-UNRESOLVED]` 标注的关键项 → **ESCALATION**（不继续推进），请求人工介入。
- 5 轮后若仅存在非关键的 `[ASSUMED: <假设内容>]` 项 → 带假设继续，并在文档中明确列出。

**需求文档格式：**

```markdown
# 需求文档: [标题]

## 原始输入
> [用户原始描述，原样引用]

## 澄清记录

| # | 问题 | 用户回答 | 备注 |
|---|------|---------|------|
| 1 | 是否需要支持批量操作？ | 第一期不需要 | 后续迭代考虑 |

## 未解决项
| # | 项目 | 类型 | 处理方式 |
|---|------|------|---------|
| 1 | 权限范围未确认 | [技术待确认] | 交由 Architect 处理 |
| 2 | 第三方支付回调格式 | [ASSUMED: 遵循标准 Webhook 格式] | 带假设继续 |

## 最终需求定义

### 功能描述
### 用户故事
### 业务规则
### 范围边界（包含 / 不包含）
### 验收标准
### 非功能需求（业务侧：响应要快、数据要准确等）
```

---

### 1.design：方案设计（Proposal）

**负责角色：** `Architect`（方案架构师）

**可用 Skill：** `doc-coauthoring`

**澄清域限制：** Architect 处理 requirement.md 中的 `[技术待确认]` 项，并就技术层面的歧义向用户发起澄清。不重复 Clarifier 已问过的业务问题。

**产物：**
- `.pipeline/artifacts/proposal.md`
- `.pipeline/artifacts/adr-draft.md`（v4 新增）：Architect 在方案确定后立即产出 ADR 草稿，保留决策理由最鲜活的上下文，Documenter 在 5.document 基于此草稿最终化。Pilot 机械验证 adr-draft.md 存在且非空后才放行 gate-a.design-review。

**adr-draft.md 格式：**

```markdown
# ADR 草稿: [需求标题]-[序号]

## 状态
草稿（Documenter 在 5.document 最终化）

## 背景
[本次需求的技术背景和约束，由 Architect 填写]

## 决策选项
| 选项 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| A（选定） | ... | ... | ... |
| B（放弃） | ... | ... | ... |

## 决策理由
[为何选择 A 而非 B，含非功能性权衡]

## 影响
[此决策对架构、运维、测试的影响]
```

**方案文档格式：**

```markdown
# Proposal: [需求标题]

## 条件角色激活标记
- data_migration_required: true/false
- performance_sensitive: true/false
- performance_sla: "p99 < 200ms"
- i18n_required: true/false

## 需求引用
来源: requirement.md（含 [技术待确认] 项的解答）

## 技术澄清记录

| # | 问题 | 用户回答 |
|---|------|---------|
| 1 | 消息队列选型？ | 用 RabbitMQ，团队有经验 |

## 影响面分析
- 涉及服务/模块：...
- 涉及数据库表：...
- 涉及外部依赖/API：...
- 潜在风险点：...

## 技术方案
### 方案描述
### 备选方案（如有）
### 选型理由

## 数据模型变更
## 数据迁移方案（仅 data_migration_required: true）
## 接口设计草案（概要，后续由 Contract Formalizer 形式化）
## 测试策略概要
## 部署策略概要
## 预估工作量
```

---

### 0.5.requirement-check：需求完整性校验（Requirement Completeness Checker）【v5 新增 AutoStep】

**类型：** AutoStep

**触发时机：** 0.clarify（Clarifier）完成 requirement.md 后，gate-a.design-review 审核前。

**执行内容：**

1. **必填 Section 检查**：首先定位 `## 最终需求定义`（H2 标题），提取该节下所有内容（到下一个 H2 或文件末尾）；在提取内容中查找以下 H3 子节标题（使用前缀匹配，允许标题后有括号补充说明）：
   - `### 功能描述`
   - `### 用户故事`
   - `### 业务规则`
   - `### 范围边界`（前缀匹配，兼容"范围边界（包含 / 不包含）"）
   - `### 验收标准`

   以上 5 个 H3 子节全部存在且内容非空 → `sections_check.overall: PASS`；任意缺失 → `FAIL`，列出缺失项。`## 最终需求定义` 本身不存在时，所有子节均标记为 MISSING。

2. **关键项检查**：确认 `[CRITICAL-UNRESOLVED]` 出现次数为 0。

3. **假设格式检查**：所有 `[ASSUMED:...]` 条目符合正则 `\[ASSUMED:[^\]]+\]`，确保 2.1.assumption-check 的关键词提取不受格式异常干扰。

4. **最小字数检查**：需求文档总字数 ≥ `config.json` 中 `requirement_completeness.min_words`（默认 200）。

**产物：** `.pipeline/artifacts/requirement-completeness-report.json`

```json
{
  "autostep": "RequirementCompletenessChecker",
  "timestamp": "2025-01-01T00:00:05Z",
  "sections_check": {
    "最终需求定义_section_found": true,
    "功能描述": "PRESENT",
    "用户故事": "PRESENT",
    "业务规则": "PRESENT",
    "范围边界": "PRESENT",
    "验收标准": "MISSING"
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
- `overall: FAIL` → 回退 0.clarify（Clarifier 补充缺失内容），不进入 gate-a.design-review。
- `overall: PASS` → 进入 gate-a.design-review，Auditor 无需再检查格式问题，专注内容审查。

> **这修复了 v4 遗留漏洞**：需求文档的格式完整性此前依赖 gate-a.design-review Auditor 的主观检查，现升级为机械前置门禁，同时为 2.1.assumption-check 的假设关键词提取提供格式保障。

---

### gate-a.design-review：方案校验

**负责角色：** `Auditor-Biz`、`Auditor-Tech`、`Auditor-QA`、`Auditor-Ops`，以及 `Resolver`（矛盾时激活）

**rollback_to 规则：** 取所有 Auditor 中最深的回退目标；Resolver 仲裁后可覆盖。

**产物：** `.pipeline/artifacts/gate-a.design-review.json`

```json
{
  "gate": "A",
  "timestamp": "2025-01-01T00:00:00Z",
  "attempt": 1,
  "results": [
    {
      "reviewer": "Auditor-Biz",
      "verdict": "PASS",
      "comments": "需求覆盖完整"
    },
    {
      "reviewer": "Auditor-Tech",
      "verdict": "FAIL",
      "comments": "未考虑并发场景下的数据一致性问题",
      "rollback_to": "1.design",
      "rollback_reason": "需要在 Proposal 中补充并发控制方案"
    }
  ],
  "conflict_detected": false,
  "resolver_invoked": false,
  "overall": "FAIL",
  "rollback_to": "1.design"
}
```

**矛盾仲裁时追加：**

```json
{
  "conflict_detected": true,
  "resolver_invoked": true,
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
        "target_phase": "1.design",
        "requirement": "将 Proposal 中的 WebSocket 替换为 SSE 方案，并更新影响面分析",
        "verification_method": "grep",
        "verification_pattern": "SSE|Server-Sent Events",
        "verification_file": ".pipeline/artifacts/proposal.md"
      }
    ]
  }
}
```

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

---

### 2.plan：任务细化（Task Breakdown）

**负责角色：** `Planner`（任务规划师）

**产物：** `.pipeline/artifacts/tasks.json`

任务文件包含自然语言接口契约（后续由 Contract Formalizer 形式化）：

```json
{
  "contracts": [
    {
      "id": "contract-1",
      "type": "api",
      "description": "用户查询接口",
      "definition": {
        "method": "GET",
        "path": "/api/v1/users/:id",
        "request": {},
        "response": { "id": "string", "name": "string", "email": "string" },
        "errors": { "404": "用户不存在", "400": "参数格式错误" }
      }
    }
  ],
  "tasks": [
    {
      "id": "task-1",
      "title": "新增用户查询 API 端点",
      "assigned_to": "Builder-Backend",
      "depends_on": [],
      "contract_refs": ["contract-1"],
      "files": [
        { "path": "src/routes/user.ts", "action": "modify" },
        { "path": "src/services/user.ts", "action": "modify" }
      ],
      "acceptance_criteria": [
        "接口返回正确的用户信息",
        "用户不存在时返回 404",
        "id 参数非 UUID 格式时返回 400"
      ]
    }
  ]
}
```

---

### 2.1.assumption-check：假设传播验证（Assumption Propagation Validator）【v4 新增 AutoStep】

**类型：** AutoStep

**触发时机：** Planner 输出 tasks.json 后，gate-b.plan-review 审核前。

**执行内容：**

1. 从 `requirement.md` 中提取所有 `[ASSUMED: <内容>]` 条目，构建假设列表。
2. 对每条假设，在 `tasks.json` 的所有 `tasks[].notes`、`tasks[].acceptance_criteria` 中搜索关键词匹配。
3. 未命中的假设标记为 `uncovered`，命中的标记为 `covered`。

**产物：** `.pipeline/artifacts/assumption-propagation-report.json`

```json
{
  "autostep": "AssumptionPropagationValidator",
  "timestamp": "2025-01-01T00:00:15Z",
  "assumptions_found": 3,
  "covered": 2,
  "uncovered": [
    {
      "assumption": "第三方支付回调格式遵循标准 Webhook 格式",
      "source_line": "requirement.md:行42",
      "coverage_in_tasks": "无任务引用此假设",
      "severity": "WARN"
    }
  ],
  "overall": "WARN"
}
```

**流转规则：**
- 所有假设均 covered → `overall: PASS`，进入 gate-b.plan-review。
- 存在 uncovered 假设 → `overall: WARN`，Pilot 将未覆盖假设列表附加到 gate-b.plan-review 的输入上下文，由 Auditor-Biz 判断是否需要 Planner 补充；不自动阻断（避免过度严苛），但 Auditor-Biz FAIL 时须说明是否因此原因。

> **这修复了 v3 漏洞 F**：`[ASSUMED: ...]` 不再静默传播，每条假设均有追踪记录。

---

### gate-b.plan-review：任务校验

**负责角色：** `Auditor-Biz`、`Auditor-Tech`、`Auditor-QA`、`Auditor-Ops`（全 4 个）

> **v2 变更**：gate-b.plan-review 新增 Auditor-Biz，确保任务拆解没有遗漏业务规则或误解业务意图。

**流转规则：** 同 gate-a.design-review（含 rollback_to 最深规则和 Resolver 机制）。

**假设处置记录（`assumption_dispositions`，v5 新增）：**

当 2.1.assumption-check Assumption Propagation Validator 存在 `uncovered` 假设时，Auditor-Biz 须在 `gate-b.plan-review.json` 中对每条假设明确标注处置结果：

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

**追加流转规则（v5）：** 若任意假设的 `disposition: REQUIRE_PLANNER_COVERAGE` → gate-b.plan-review FAIL，`rollback_to: 2.plan`，Planner 补充覆盖任务后重新提交 gate-b.plan-review 审核。若 `assumption-propagation-report.json` 中 `uncovered` 为空，`assumption_dispositions` 数组为空，不影响 gate-b.plan-review 结论。

---

### 2.5.contract-formalize：契约形式化（Contract Formalization）【新增】

**负责角色：** `Contract Formalizer`（契约形式化师）

**输入：** `tasks.json`

**产物：** `.pipeline/artifacts/contracts/` 目录

将 tasks.json 中的自然语言接口契约转换为可机械验证的形式化规范：

```
contracts/
├── contract-1.openapi.json    # OpenAPI 3.0 格式
├── contract-1.schema.json     # JSON Schema（请求/响应）
├── contract-2.openapi.json
└── contracts-index.json       # 契约清单
```

**契约示例（`contract-1.openapi.json`）：**

```json
{
  "openapi": "3.0.0",
  "paths": {
    "/api/v1/users/{id}": {
      "get": {
        "operationId": "getUserById",
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "schema": { "type": "string", "format": "uuid" }
          }
        ],
        "responses": {
          "200": {
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "required": ["id", "name", "email"],
                  "properties": {
                    "id": { "type": "string", "format": "uuid" },
                    "name": { "type": "string" },
                    "email": { "type": "string", "format": "email" }
                  }
                }
              }
            }
          },
          "400": { "description": "参数格式错误（id 非 UUID）" },
          "404": { "description": "用户不存在" }
        }
      }
    }
  }
}
```

**模板驱动输出（v4 新增）：** Contract Formalizer 不再从空白开始生成 OpenAPI，而是以 Pilot 预生成的结构化模板为基础：

```json
// 模板（由 Pilot 从 tasks.json 机械生成，Contract Formalizer 仅填充语义字段）
{
  "openapi": "3.0.0",
  "paths": {
    "/api/v1/users/{id}": {      // ← 来自 tasks.json contracts[].definition.path
      "get": {                    // ← 来自 tasks.json contracts[].definition.method
        "operationId": "__FILL__", // ← LLM 填充
        "parameters": [],          // ← LLM 填充
        "responses": {
          "200": { "content": { "application/json": { "schema": "__FILL__" } } },
          "404": { "description": "__FILL__" }  // ← 来自 tasks.json contracts[].definition.errors
        }
      }
    }
  }
}
```

Pilot 机械生成路径、方法、错误码骨架，Contract Formalizer 只填充 `__FILL__` 字段。2.6.contract-validate-semantic 将机械验证所有 `__FILL__` 均已填充且格式合法。

**价值：** Inspector 审查契约一致性时，不再靠 LLM 阅读 Markdown 主观判断，而是直接对比代码实现与 OpenAPI Schema，大幅提升契约检查的准确性。模板驱动进一步降低 LLM 生成错误格式的概率。

---

### 2.6.contract-validate-semantic：Schema 完整性校验（Schema Completeness Validator）【v3 新增 AutoStep】

**类型：** AutoStep

**执行内容：**
1. 统计 `tasks.json` 中 `contracts` 数组长度 N。
2. 检查 `contracts/` 目录中 `*.openapi.json` 文件数量是否等于 N。
3. 对每个 `*.openapi.json` 文件执行 OpenAPI 3.0 格式验证（使用 swagger-parser / openapi-schema-validator）。
4. 检查每个 contract 的 `operationId` 是否能与 `tasks.json` 中的 `contract_refs` 一一对应。

**产物：** `.pipeline/artifacts/schema-validation-report.json`

```json
{
  "autostep": "SchemaCompletenessValidator",
  "timestamp": "2025-01-01T00:00:30Z",
  "expected_contracts": 3,
  "found_contracts": 3,
  "format_errors": [],
  "ref_mismatches": [],
  "overall": "PASS"
}
```

**违规示例：**
```json
{
  "expected_contracts": 3,
  "found_contracts": 2,
  "format_errors": [],
  "ref_mismatches": [
    {
      "contract_ref": "contract-3",
      "task_id": "task-3",
      "issue": "contracts/ 目录中未找到对应 Schema 文件"
    }
  ],
  "overall": "FAIL"
}
```

**流转规则：**
- `overall: PASS` → 进入 3.build（并行实现）。
- 任意失败 → **回退 2.5.contract-formalize**（不进入 3.build 实现，防止用整个实现阶段的成本来验证 Schema 错误）。

> **这修复了 v2 漏洞 4**：v2 中 Contract Formalizer 输出 Schema 后直接进入 3.build，Schema 错误只在 gate-c.code-review（Inspector）才发现，此时整个 3.build 已完成，成本极高。

---

### 2.7.contract-validate-schema：契约语义校验（Contract Semantic Validator）【v5 新增 AutoStep】

**类型：** AutoStep

**触发时机：** 2.6.contract-validate-semantic（Schema Completeness Validator）PASS 后，3.build 并行实现前。

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
- 任意 `severity: ERROR` → 回退 2.5.contract-formalize（Contract Formalizer 基于报告修正 Schema）。
- 仅有 `severity: WARN` → 不阻断，追加到 gate-c.code-review Inspector 的参考输入上下文。
- 无任何问题 → 进入 3.build（并行实现）。

> **这修复了 v4 遗留漏洞 K**：2.6.contract-validate-semantic 只验证 OpenAPI 格式合法性，无法检测"格式合法但语义错误"的 Schema。Contract Formalizer 的字段类型错误（如整数定义为 string）、路径参数 required 遗漏等，此前需等到 3.7.contract-compliance 才能发现，彼时整个 3.build 实现已完成。新增本 AutoStep 将发现点前移，回退成本降至最低（仅 2.5.contract-formalize 重做）。

---

### 3.build：并行代码实现

**文件冲突处理协议：**

Pilot 在 3.build 开始前，根据 tasks.json 计算文件分配矩阵：

1. 检测同一文件被多个 Builder 分配的情况。
2. 冲突文件的执行顺序按依赖层次串行化：**DBA → Backend → Security → Frontend → Infra**。
3. 后执行的 Builder 基于前者完成后的最新文件继续实现。
4. 无冲突的 Builder 仍并行执行。

**产物：** `.pipeline/artifacts/impl-manifest.json`

**写入协议（v4 修复漏洞 B）：** 为避免并行 Builder 同时写入导致竞争覆盖，各 Builder 只写自己的临时文件 `impl-manifest-<builder-id>.json`，所有 Builder 完成后由 **Pilot** 统一合并为最终的 `impl-manifest.json`。Pilot 合并时同时校验所有 Builder 的 `task_id` 不重叠。

```json
// 各 Builder 写入各自的临时文件（示例：impl-manifest-builder-backend.json）
{
  "task_id": "task-1",
  "builder": "Builder-Backend",
  "status": "completed",
  "files_changed": ["src/routes/user.ts", "src/services/user.ts"],
  "authorized_files": ["src/routes/user.ts", "src/services/user.ts"],
  "notes": "新增了 UUID 格式校验"
}

// Pilot 汇总后的最终 impl-manifest.json
{
  "implementations": [
    {
      "task_id": "task-1",
      "builder": "Builder-Backend",
      "status": "completed",
      "files_changed": ["src/routes/user.ts", "src/services/user.ts"],
      "authorized_files": ["src/routes/user.ts", "src/services/user.ts"],
      "notes": "新增了 UUID 格式校验"
    }
  ],
  "new_test_files": [],
  "merged_by": "Pilot",
  "merge_timestamp": "2025-01-01T00:00:50Z"
}
```

**Builder-Security 专属产物（v4 修复漏洞 J）：** Builder-Security 完成代码修改后，额外输出 `.pipeline/artifacts/security-checklist.json`，记录本次处理的安全决策：

```json
{
  "builder": "Builder-Security",
  "task_id": "task-2",
  "threats_considered": [
    { "threat": "SQL 注入", "mitigation": "使用 ORM 参数化查询，见 src/services/user.ts:42" },
    { "threat": "XSS", "mitigation": "响应头已设置 Content-Security-Policy" }
  ],
  "auth_checks_added": ["GET /api/v1/users/:id 添加 JWT 校验中间件"],
  "input_validations_added": ["id 字段 UUID 格式校验，见 src/routes/user.ts:15"],
  "known_gaps": []
}
```

Inspector 在 gate-c.code-review 审查安全性时以此为参考输入，避免重复分析已处理的威胁，聚焦于 Builder-Security 未覆盖的 `known_gaps`。

---

### 3.1.static-analyze：静态分析（Static Analysis）【新增 AutoStep】

**类型：** AutoStep（无 LLM，Pilot 直接调用工具）

**执行内容：**
- Linter（eslint / pylint / golangci-lint）
- 类型检查（tsc / mypy）
- 依赖安全扫描（npm audit / pip-audit / trivy）
- 复杂度测量（圈复杂度、认知复杂度、函数行数、文件行数）
- **SAST 源码安全扫描（v4 新增）**：Semgrep（使用 p/owasp-top-ten 规则集）或 CodeQL 扫描新增代码，检测 SQL 注入模式、XSS sink、SSRF、硬编码凭据等，不依赖 LLM 判断。高危发现（`severity: HIGH`）阻断流程，中低危作为 Inspector 的参考输入。

**产物：** `.pipeline/artifacts/static-analysis-report.json`

```json
{
  "autostep": "StaticAnalyzer",
  "timestamp": "2025-01-01T00:01:00Z",
  "lint_errors": 0,
  "lint_warnings": 2,
  "type_errors": 0,
  "dependency_vulnerabilities": 0,
  "complexity_issues": [
    {
      "file": "src/services/user.ts",
      "function": "processUserData",
      "cyclomatic_complexity": 12,
      "threshold": 10,
      "severity": "MUST_REDUCE"
    }
  ],
  "long_functions": [
    {
      "file": "src/routes/user.ts",
      "function": "handleUserRequest",
      "lines": 67,
      "threshold": 50,
      "severity": "MUST_SPLIT"
    }
  ],
  "naming_issues": [],
  "sast_findings": [
    {
      "file": "src/routes/user.ts",
      "rule": "sql-injection",
      "severity": "LOW",
      "line": 28,
      "message": "潜在的字符串拼接 SQL，建议确认是否使用 ORM"
    }
  ],
  "overall": "WARN",
  "blocking": false
}
```

**流转规则：**
- 有 lint_errors > 0 或 type_errors > 0 或 dependency_vulnerabilities > 0（高危）→ 回退 3.build。
- 有 sast_findings（severity: HIGH）→ 回退 3.build（对应 Builder 修复安全问题）。
- 有 sast_findings（severity: MEDIUM/LOW）→ 不阻断，追加到 gate-c.code-review.json 作为 Inspector 的参考上下文。
- 有 complexity_issues 或 long_functions → 不阻断，但报告作为 Simplifier 的量化目标输入。
- 无任何阻断问题 → 进入 3.2.diff-validate。

---

### 3.2.diff-validate：变更范围校验（Diff Scope Validation）【新增 AutoStep】

**类型：** AutoStep

**执行内容：** 对比 `git diff`（变更文件集合）与 `impl-manifest.json`（授权文件列表），检测越权变更。

**产物：** `.pipeline/artifacts/scope-validation-report.json`

```json
{
  "autostep": "DiffScopeValidator",
  "timestamp": "2025-01-01T00:02:00Z",
  "violations": [],
  "overall": "PASS"
}
```

**违规示例：**

```json
{
  "violations": [
    {
      "file": "src/config/database.ts",
      "modified_by": "Builder-Backend",
      "authorized": false,
      "assigned_task": null,
      "action": "ROLLBACK_BUILDER",
      "rollback_builder": "Builder-Backend"
    }
  ],
  "overall": "FAIL"
}
```

**流转规则：** 任意违规 → 将违规 Builder 的任务回退至 3.build 重新实现（不影响其他 Builder 的成果）。

---

### 3.3.regression-guard：回归守卫（Regression Guard）【新增 AutoStep】

**类型：** AutoStep

**执行内容：** 运行项目中现有的测试套件（排除本次新增的测试文件，即非 impl-manifest.json 中的新增测试）。

**产物：** `.pipeline/artifacts/regression-report.json`

```json
{
  "autostep": "RegressionGuard",
  "timestamp": "2025-01-01T00:03:00Z",
  "existing_tests_run": 83,
  "passed": 83,
  "failed": 0,
  "overall": "PASS"
}
```

**流转规则：** 任意现有测试失败 → 回退 3.build（由失败测试关联的文件追溯到对应 Builder）。

> **这解决了原版漏洞**：Simplifier 的约束"精简不得破坏已有测试"在 3.3.regression-guard 已机械验证，3.5.simplify 执行时也必须保持回归报告有效（Simplifier 约束中引用 regression-report.json 的时间戳）。

---

### 3.5.simplify：代码精简（Code Simplification）

**负责角色：** `Simplifier`（代码精简师）

**必备 Skill：** `code-simplifier`

**输入：**
- `impl-manifest.json`（变更文件列表）
- `static-analysis-report.json`（量化指标，作为精简目标）
- `regression-report.json`（基准，精简后需保持现有测试通过）
- 实际代码文件

**产物：** `.pipeline/artifacts/simplify-report.md`

报告格式同原版，但必须包含量化指标改善（如"圈复杂度 12→4"）。

**流转规则：**
- 精简完成，`simplify-report.md` 落盘 → 进入 3.6.simplify-verify（Post-Simplification Verifier）。
- 发现严重结构问题无法仅通过精简解决 → 回退 3.build。

---

### 3.6.simplify-verify：精简后验证（Post-Simplification Verifier）【v3 新增 AutoStep】

**类型：** AutoStep

**执行内容：**

1. **量化目标验证**：重新测量精简后代码的圈/认知复杂度、函数行数，对比 `static-analysis-report.json` 中 `severity: "MUST_REDUCE"` / `"MUST_SPLIT"` 的条目，验证所有必须处理项是否达标。
2. **回归重跑**：重新运行现有测试套件（与 3.3.regression-guard 相同的范围），确认精简没有破坏现有功能。

**产物：** `.pipeline/artifacts/post-simplify-report.json`

```json
{
  "autostep": "PostSimplificationVerifier",
  "timestamp": "2025-01-01T00:05:00Z",
  "complexity_check": {
    "must_reduce_items": 2,
    "resolved": 2,
    "unresolved": 0,
    "overall": "PASS"
  },
  "regression_recheck": {
    "existing_tests_run": 83,
    "passed": 83,
    "failed": 0,
    "overall": "PASS"
  },
  "overall": "PASS"
}
```

**流转规则：**
- `complexity_check.overall: PASS` 且 `regression_recheck.overall: PASS` → 进入 gate-c.code-review。
- `complexity_check.unresolved > 0` → 回退 3.5.simplify（量化目标未达成，重新精简）。
- `regression_recheck.failed > 0` → 回退 3.build（精简引入了回归，由失败测试追溯对应 Builder）。

> **这替代了 v2 中 Simplifier 对"精简不得破坏已有测试"的 LLM 自我承诺**，将其升级为机械闭环验证。

---

### gate-c.code-review：代码审查（Code Review）

**负责角色：** `Inspector`（代码审查员）

**必备 Skill：** `code-review`

**simplifier_verified 机械验证（Pilot 执行）：**

在启动 Inspector 之前，Pilot 自动检查：
1. `.pipeline/artifacts/simplify-report.md` 存在且非空。
2. `simplify-report.md` 的最后修改时间 ≥ `impl-manifest.json` 的最后修改时间。

两项均满足 → 在 `gate-c.code-review.json` 中设置 `"simplifier_verified": true`，然后启动 Inspector。
任一不满足 → 强制先执行 3.5.simplify。

**输入：**
- `simplify-report.md`
- `contracts/`（形式化 Schema，用于契约一致性审查）
- `scope-validation-report.json`（文件范围已合规，无需重复校验）
- `tasks.json`（任务定义）
- `security-checklist.json`（v4 新增：Builder-Security 已处理威胁清单，Inspector 聚焦 known_gaps）
- `static-analysis-report.json`（含 SAST 中低危发现，作为安全审查参考）
- 实际代码文件（精简后）

**产物：**
- `.pipeline/artifacts/gate-c.code-review.md`（Markdown 详细报告，供 Builder 阅读修复）
- `.pipeline/artifacts/gate-c.code-review.json`（JSON 结论，供 Pilot 流转决策）

```json
{
  "gate": "C",
  "agent": "Inspector",
  "skill": "code-review",
  "attempt": 1,
  "simplifier_verified": true,
  "issues_critical": 0,
  "issues_major": 1,
  "issues_minor": 2,
  "issues_info": 1,
  "overall": "FAIL",
  "rollback_to": "3.build",
  "rollback_reason": "存在 1 个 MAJOR 级别问题（输入校验缺失）"
}
```

**流转规则：**
- 无 CRITICAL 且无 MAJOR → `PASS`，进入 3.7.contract-compliance。
- 存在 CRITICAL 或 MAJOR → `FAIL`，回退后**必须重新经过 3.1.static-analyze → 3.2 → 3.3 → 3.5 → 3.6 → gate-c.code-review**。

---

### 3.7.contract-compliance：契约合规性检查（Contract Compliance Checker）【v3 新增 AutoStep】

**类型：** AutoStep

**执行内容：** 启动本地服务（或 Mock Server），使用 dredd / schemathesis 等工具根据 `contracts/*.openapi.json` 自动生成请求并发送，验证响应是否符合 Schema（字段类型、必填字段、HTTP 状态码、错误响应格式）。

**服务启动失败处理（v4 修复漏洞 D）：** 启动本地服务前，AutoStep 先执行健康检查（最多等待 30 秒，轮询 `/health` 或配置的 startup_probe）。若服务无法启动，在 `contract-compliance-report.json` 中设置 `startup_error: true`，Pilot 将此情况视为**基础设施故障**（而非契约违规）→ 直接触发 **Escalation**，不执行 3.build 回退（服务启动失败通常是环境问题，回退 Builder 无意义）。若服务成功启动后 dredd/schemathesis 测试失败，则按原有规则回退 3.build。

**产物：** `.pipeline/artifacts/contract-compliance-report.json`

```json
{
  "autostep": "ContractComplianceChecker",
  "timestamp": "2025-01-01T00:06:00Z",
  "startup_error": false,
  "contracts_tested": 3,
  "violations": [
    {
      "contract_id": "contract-1",
      "operation": "GET /api/v1/users/{id}",
      "expected_field": "email",
      "actual": "email_address",
      "verdict": "SCHEMA_MISMATCH"
    }
  ],
  "overall": "FAIL"
}
```

**流转规则：**
- `startup_error: true` → **Escalation**（基础设施故障，不回退 Builder）。
- `startup_error: false` 且 `violations` 为空 → 进入 4a.test。
- `startup_error: false` 且存在 `SCHEMA_MISMATCH` → 回退 3.build（对应 Builder），重新实现并经过完整 3.1→3.6→gate-c.code-review→3.7 路径。

> **价值**：比 Inspector LLM 审查契约一致性更可靠（机械执行而非 LLM 阅读 Schema），同时减少 Tester 需要手写的基础契约测试用例。

---

### 4a.test：功能测试

**负责角色：** `Tester`（测试工程师）

**产物：**
- `.pipeline/artifacts/test-report.json`
- `.pipeline/artifacts/coverage/coverage.lcov` ← **必须生成**（4a.1.test-failure-map 的前置依赖）
- `.pipeline/artifacts/coverage/coverage.json`（Istanbul JSON 格式，可选但推荐）

> **覆盖率收集要求（v6 新增）：** Tester 必须在覆盖率收集模式下运行测试（由 `config.json.testing.coverage_required: true` 强制）。若 `coverage.lcov` 不存在，Pilot 跳过 4a.1.test-failure-map，直接触发全体回退，日志记录 `[WARN] coverage.lcov 不存在，跳过 Test Failure Mapper，执行全体回退`。

**关于新增测试文件的生命周期（v6 扩展）：** Tester 新增的测试文件在 `impl-manifest.json` 中标记为 `"new_test_files": [...]`，同时 Pilot 同步写入 `state.json.new_test_files`。**以下任意情况触发 3.build 时，3.3.regression-guard / 3.6.simplify-verify 均排除 state.json.new_test_files 中的文件：**

- 4a.test FAIL → 4a.1.test-failure-map → 3.build 回退
- gate-d.test-review FAIL → 4a.test 或 3.build 回退（若再次经过 3.build）
- gate-c.code-review FAIL → 3.build 回退（即使 4a.test 之前已通过）
- Optimizer SLA 违规（sla_violated: true）→ 3.build 直接回退

排除规则持续有效，直到 Pipeline 状态变为 COMPLETED，毕业操作将 new_test_files 写入 `regression-suite-manifest.json` 并清空 `state.json.new_test_files`。

```json
{
  "summary": { "total": 15, "passed": 15, "failed": 0, "skipped": 0 },
  "failures": [],
  "overall": "PASS"
}
```

---

### 4a.1.test-failure-map：测试失败映射（Test Failure Mapper）【v5 新增 AutoStep，4a.test FAIL 时触发】

**类型：** AutoStep

**触发时机：** 4a.test 功能测试 FAIL 后，3.build 回退前。4a.test PASS 时本步骤跳过。

**前置要求（v6 新增）：** Pilot 在触发 4a.1.test-failure-map 前，验证 `.pipeline/artifacts/coverage/coverage.lcov` 存在且非空。若不存在，跳过 4a.1.test-failure-map，直接触发全体回退（等同 PARTIAL_MAPPED），日志记录 `[WARN] coverage.lcov 不存在，跳过 Test Failure Mapper，执行全体回退`。

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

**流转规则（v6 更新，新增 confidence 维度）：**
- `overall: PRECISE_MAPPED`（所有映射均为 HIGH confidence，unmapped_failures 为空）→ 只回退 `builders_high_confidence` 中的 Builder，其余 Builder 的实现结果保留。
- `overall: LOW_CONFIDENCE_MAPPED`（存在 LOW confidence 映射，unmapped_failures 为空）→ 降级为全体回退，日志记录 `[WARN] 存在 LOW 置信度映射，执行保守全体回退`。
- `overall: PARTIAL_MAPPED`（unmapped_failures 不为空，无论 confidence）→ 回退所有 Builder，日志记录 `[WARN] 测试失败部分无法映射到 Builder，执行全体回退`。

> **这修复了 v4 遗留漏洞 L**：4a.test 测试失败后无法确定责任 Builder，Pilot 只能全体回退。在多 Builder 场景下，无辜 Builder 被强制重做整个 3.build，成本浪费显著。精确映射后，只有真正导致测试失败的 Builder 才需要回退。

---

### 4.2.coverage-check：测试覆盖率门禁（Test Coverage Enforcer）【v3 新增 AutoStep】

**类型：** AutoStep

**执行内容：** 运行覆盖率工具（nyc / coverage.py / go tool cover），提取 `impl-manifest.json` 中 `files_changed` 列表对应的新增代码的行覆盖率和分支覆盖率，与 `config.json` 中配置的阈值对比。

**产物：** `.pipeline/artifacts/coverage-report.json`

```json
{
  "autostep": "TestCoverageEnforcer",
  "timestamp": "2025-01-01T00:07:00Z",
  "thresholds": { "line_coverage_pct": 80, "branch_coverage_pct": 70 },
  "results": [
    {
      "file": "src/services/user.ts",
      "line_coverage_pct": 92,
      "branch_coverage_pct": 85,
      "verdict": "PASS"
    }
  ],
  "overall": "PASS"
}
```

**流转规则：**
- 所有新增文件覆盖率达标 → 进入 4b.optimize（如激活）或 gate-d.test-review。
- 任意文件低于阈值 → 回退 4a.test，Tester 补充测试用例。

---

### 4b.optimize：性能压测（条件，Tester PASS 后串行执行）

**负责角色：** `Optimizer`（性能优化师）

> **v2 变更**：Optimizer 改为在 4a.test PASS 后串行启动，避免在功能有 bug 的代码上产生无效性能数据。

**激活条件：** `performance_sensitive: true`

**产物：** `.pipeline/artifacts/perf-report.json`

**性能达标场景（进入 gate-d.test-review）：**

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

**SLA 违规场景（直接回退 3.build，v5 修复漏洞 P）：**

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
  "rollback_to": "3.build",
  "overall": "FAIL"
}
```

**Pilot 对 perf-report.json 的处理（v5 新增）：**
- `sla_violated: true` → 直接回退 3.build，不等待 gate-d.test-review。Optimizer 标注的 `slow_queries` 和 `rollback_reason` 注入对应 Builder 的输入上下文；递增对应 Builder 的 `builder_attempt_counts`。
- `sla_violated: false` → 正常进入 gate-d.test-review，由 Auditor-QA 做最终验收。

**gate-d.test-review 统一验收 4a + 4b 的结果。**

---

### gate-d.test-review：测试验收

**负责角色：** `Auditor-QA`

**输入：** `test-report.json` + `coverage-report.json` + `perf-report.json`（如 Optimizer 激活）

**rollback_to 范围限制（v3 修复）：** Auditor-QA 的 `rollback_to` 只能为 `4a.test`、`3.build`、`2.plan`，**不得指定 0.clarify 或 1.design**（测试验收失败不涉及业务需求重定义或技术方案重设计）。

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
  "rollback_to": "4a.test",
  "rollback_reason": "功能测试存在 3 个失败用例，Tester 需补充边界条件测试"
}
```

**Pilot 机械验证 rollback_to 合法性（v6 新增）：** gate-d.test-review 的 `rollback_to` 只允许 `null`（PASS 时）、`"4a.test"`、`"3.build"`、`"2.plan"`。若 Auditor-QA 输出超出范围的值（如 `"0.clarify"`），Pilot 拒绝并降级为 `"2.plan"`，日志记录 `[WARN] gate-d.test-review rollback_to 超出允许范围，已降级为 2.plan`。

---

### 5.document：文档生成

**AutoStep 前置：** `API Change Detector`

在 Documenter 启动前，Pilot 运行 API Change Detector 对比 `contracts/` 与上一版本的契约，生成 `api-change-report.json`：

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

**5.document 执行策略（v5 扩展，修复漏洞 M）：**

| 场景 | `api_changed` | `mode` | `phase_5_mode` | 5.document 执行内容 | 5.1.changelog-check 是否运行 |
|------|--------------|--------|---------------|----------------|--------------------|
| 正常流程，API 有变更 | true | normal | `full` | API 文档 + CHANGELOG + ADR 最终化 | 是 |
| 正常流程，API 无变更 | false | normal | `changelog_only` | **仅更新 CHANGELOG**，跳过 API 文档 | 是（验证 CHANGELOG 覆盖 impl-manifest 文件变更） |
| Hotfix，API 有变更 | true | hotfix | `full` | API 文档 + CHANGELOG + ADR 最终化 | 是 |
| Hotfix，API 无变更 | false | hotfix | `skip` | 跳过整个 5.document | 否 |

Documenter 读取 `state.json.phase_5_mode` 决定执行内容。`changelog_only` 模式下，Documenter 只更新 CHANGELOG，跳过 API 文档生成和 ADR 最终化。

**Pilot 写入 state.json（v6 明确，修复漏洞 W）：** AUTOSTEP_API_CHANGE_DETECTOR 完成后，Pilot 读取 `api-change-report.json.phase_5_mode`，同步写入 `state.json.phase_5_mode`。两个文件均保留此字段：`api-change-report.json` 作为产物归档，`state.json` 作为运行时状态（Documenter 运行时的读取来源）。

**负责角色：** `Documenter`

**产物：**
- API 文档、CHANGELOG、用户手册（均为 Markdown）
- **架构决策记录（ADR）**（新增）：记录本次技术决策、选型理由和被放弃的方案，积累为 Architect 下次设计的参考。
- `.pipeline/artifacts/docs-manifest.json`

```json
{
  "documents_generated": [
    { "type": "api_docs", "path": "docs/api/users.md", "action": "updated" },
    { "type": "changelog", "path": "CHANGELOG.md", "action": "updated" },
    { "type": "adr", "path": "docs/adr/008-uuid-validation-middleware.md", "action": "created",
      "source_draft": ".pipeline/artifacts/adr-draft.md" }
  ]
}
```

**ADR 最终化（v4 新增）：** Documenter 读取 1.design Architect 输出的 `adr-draft.md`，补充实现细节、测试结果、实际影响，生成最终 ADR 文件。若 `adr-draft.md` 不存在，Pilot 阻断 5.document 并要求 Architect 补充（回退 1.design）。

---

### 5.1.changelog-check：变更日志一致性检查（Changelog Consistency Checker）【v4 新增 AutoStep】

**类型：** AutoStep

**触发时机：** Documenter 完成 CHANGELOG.md 生成后，gate-e.doc-review 审核前。

**执行内容：**

1. 统计 `api-change-report.json` 中 `changed_contracts` 数组长度 M。
2. 在 `CHANGELOG.md` 最新版本条目中搜索 API 路径关键词（来自 `changed_contracts` 中的 path），统计命中数。
3. 提取 `impl-manifest.json` 中 `files_changed` 涉及的模块/目录（取一级或二级路径），在 CHANGELOG 中查找是否有对应描述。

**产物：** `.pipeline/artifacts/changelog-check-report.json`

```json
{
  "autostep": "ChangelogConsistencyChecker",
  "timestamp": "2025-01-01T00:09:00Z",
  "api_changes_expected": 2,
  "api_changes_in_changelog": 2,
  "module_coverage": {
    "src/services": "COVERED",
    "src/routes": "COVERED"
  },
  "missing_entries": [],
  "overall": "PASS"
}
```

**流转规则：**
- `missing_entries` 为空 → `overall: PASS`，进入 gate-e.doc-review。
- 存在未覆盖的 API 变更或模块 → `overall: FAIL`，回退 5.document（Documenter 补充 CHANGELOG 条目）。

---

### 6.0.deploy-readiness：部署就绪检查（Pre-Deploy Readiness Check）【v4 新增 AutoStep】

**类型：** AutoStep

**触发时机：** gate-e.doc-review PASS 后，Deployer 启动前。

**执行内容：**

1. 检查目标环境所有必需环境变量是否已配置（变量清单来自 `proposal.md` 的"影响面分析 → 外部依赖"）。
2. 若 `data_migration_required: true`，检查 `migrations/` 目录存在对应迁移脚本。
3. 检查部署计划文件（`deploy-plan.md`）存在且包含 `rollback_command` 字段。

**产物：** `.pipeline/artifacts/deploy-readiness-report.json`

```json
{
  "autostep": "PreDeployReadinessCheck",
  "timestamp": "2025-01-01T00:10:00Z",
  "env_vars_check": { "required": 5, "configured": 5, "missing": [] },
  "migration_check": { "required": true, "script_found": true },
  "rollback_command_defined": true,
  "overall": "PASS"
}
```

**流转规则：**
- `overall: PASS` → 启动 Deployer。
- `overall: FAIL`（缺环境变量 / 缺迁移脚本 / 缺回滚命令）→ **Escalation**（配置问题，非代码问题，不触发流程回退）。

---

### 6.deploy：部署

**负责角色：** `Deployer`

**产物：** `.pipeline/artifacts/deploy-report.json`

```json
{
  "deployer": "Deployer",
  "environment": "production",
  "deploy_status": "SUCCESS",
  "smoke_test": "PASS",
  "rollback_command": "kubectl rollout undo deployment/api-service",
  "deployed_version": "v1.4.2",
  "previous_version": "v1.4.1"
}
```

**6.deploy 失败处理（v4 修复漏洞 A）：**

| 失败类型 | 判断条件 | 动作 |
|---------|---------|------|
| 部署脚本执行失败（deploy_status: FAIL） | 部署过程报错，未到达 Smoke Test | 若本次变更已部分应用（partial deploy），Pilot 激活 Deployer 执行 `rollback_command` 回滚；重试最多 `max_attempts["6.deploy"]` 次；超限 → Escalation |
| Smoke Test 失败（smoke_test: FAIL） | 部署完成但健康检查不通过 | Pilot 激活 Deployer 执行 `rollback_command` 回滚，回滚后进入 3.build 排查（此时 state 标记 `mode: post-deploy-smoke-fail`） |
| 部署成功，监控异常 | 7.monitor Monitor 触发 ALERT/CRITICAL | 按 7.monitor 告警动作处理（已有定义） |

---

### 7.monitor：上线观测

**负责角色：** `Monitor`

**v2 变更：量化阈值由 `config.json` 定义，Monitor 基于阈值输出确定性结论，不依赖 LLM 主观判断。**

**产物：** `.pipeline/artifacts/monitor-report.json`

```json
{
  "monitor": "Monitor",
  "observation_window": "30min",
  "thresholds_applied": {
    "normal":   { "error_rate_pct": 0.1, "p99_latency_ms": 200 },
    "alert":    { "error_rate_pct": 0.5, "p99_latency_ms": 500, "unexpected_error_count": 10 },
    "critical": { "error_rate_pct": 5.0, "p99_latency_ms": 2000, "service_down": true }
  },
  "metrics": {
    "error_rate_pct": { "value": 0.03, "verdict": "NORMAL" },
    "p99_latency_ms": { "value": 175,  "verdict": "NORMAL" },
    "unexpected_error_count": { "value": 0, "verdict": "NORMAL" }
  },
  "overall": "STABLE",
  "action": "complete"
}
```

**告警动作定义：**

| 级别 | 条件 | 动作 |
|------|------|------|
| NORMAL / STABLE | 所有指标在 normal 阈值内 | COMPLETED（见下方毕业机制） |
| ALERT | 任意指标超 alert 阈值但未达 critical | AutoStep: Hotfix Scope Analyzer → 生成 hotfix-tasks.json → 3.build hotfix（含 3.1→3.6→gate-c.code-review→3.7） |
| CRITICAL | 任意指标超 critical 阈值，或 service_down | **Pilot 重新激活 Deployer 执行生产环境回滚**（执行 deploy-report.json 中的 rollback_command），回滚成功后进入 1.design 重新设计方案 |

**测试文件毕业机制（v4 修复漏洞 G）：** Pipeline 状态变为 COMPLETED 时，Pilot 自动执行：

1. 读取 `state.json` 中 `new_test_files` 列表。
2. 将其追加写入 `.pipeline/artifacts/regression-suite-manifest.json`（持久化的回归套件清单）。
3. 清空 `state.json.new_test_files`。

后续 Pipeline 运行时，3.3.regression-guard / 3.6.simplify-verify 的 Regression Guard 读取 `regression-suite-manifest.json` 确定应运行的测试范围，而非扫描整个测试目录。这确保本次 Pipeline 写的新测试在下一次运行时已"毕业"为正式回归套件的一部分。

```json
// regression-suite-manifest.json（示例，跨多次 Pipeline 累积）
{
  "test_files": [
    { "path": "tests/user/test_get_user.ts", "graduated_at": "2025-01-01", "pipeline_id": "pipe-20250101-001" },
    { "path": "tests/order/test_create_order.ts", "graduated_at": "2025-01-05", "pipeline_id": "pipe-20250105-001" }
  ]
}
```

---

### 7.monitor-ALERT：Hotfix 范围分析（Hotfix Scope Analyzer）【v3 新增 AutoStep】

**类型：** AutoStep（置信度 HIGH 时全程无 LLM；LOW 时触发单次用户确认）

**触发条件：** 7.monitor Monitor 输出 ALERT

**置信度判定（纯机械规则，无 LLM）：**

以下四条全部满足 → `confidence: HIGH`，否则 → `confidence: LOW`：

1. `monitor-report.json` 中存在 `endpoint` 字段（告警可定位到具体 API 端点）
2. 该端点能在 `contracts/*.openapi.json` 中找到对应 `operationId`
3. 该 contract 在 `tasks.json` 中只关联一个 task（`contract_refs` 唯一）
4. 该 task 只由一个 Builder 负责（`assigned_to` 唯一）

**HIGH 置信度处理（全自动）：**

通过上述映射链路，直接复用原 task 的授权文件范围，机械生成 `hotfix-tasks.json`：

```
monitor-report.json (endpoint: /api/v1/users/{id} 错误率超标)
  → contracts/contract-1.openapi.json (operationId: getUserById)
  → tasks.json (contract_refs: ["contract-1"] → task-1)
  → impl-manifest.json (task-1 → Builder-Backend → files_changed)
  → hotfix-tasks.json (授权范围 = 原 task-1 的文件集合)
```

**LOW 置信度处理（单次用户确认）：**

Pilot 向用户发送结构化确认请求，展示已有的分析结果：

```
[Pipeline] ALERT 触发 Hotfix，置信度：LOW

告警指标: p99_latency_ms 520ms (阈值 500ms)
无法定位具体端点（整体延迟超标，非特定 API）

分析推断（仅供参考，共 3 个 task 涉及 API 层）：
  - task-1: src/routes/user.ts, src/services/user.ts
  - task-2: src/routes/order.ts, src/services/order.ts
  - task-3: src/middleware/auth.ts

请回答：需要修复哪些文件或模块？（直接指定文件路径或选择上述 task）
```

用户回答后，Pilot 机械生成 `hotfix-tasks.json`（不经过 LLM），继续流程。

**产物：** `.pipeline/artifacts/hotfix-tasks.json` + `.pipeline/artifacts/hotfix-scope-report.json`

```json
{
  "autostep": "HotfixScopeAnalyzer",
  "timestamp": "2025-01-01T01:00:00Z",
  "trigger": "ALERT",
  "confidence": "HIGH",
  "mapping_chain": {
    "endpoint": "GET /api/v1/users/{id}",
    "contract_id": "contract-1",
    "task_id": "task-1",
    "builder": "Builder-Backend"
  },
  "authorized_files": ["src/routes/user.ts", "src/services/user.ts"],
  "user_confirmation_required": false
}
```

**3.2.diff-validate 在 hotfix 模式下的行为：** Diff Scope Validator 检测到 `state.json` 中 `mode: "hotfix"` 时，读取 `hotfix-tasks.json` 替代 `tasks.json` 进行范围校验。

---

## 6. Skill 集成机制

### 6.1 内置 Skill 映射

| Skill 名称 | 路径 | 适用角色 | 用途 |
|------------|------|---------|------|
| **`code-simplifier`** | `.pipeline/skills/code-simplifier/SKILL.md` | **Simplifier** | **必备**。量化指标驱动的代码精简 |
| **`code-review`** | `.pipeline/skills/code-review/SKILL.md` | **Inspector** | **必备**。专业代码审查框架 |
| `doc-coauthoring` | `/mnt/skills/examples/doc-coauthoring/SKILL.md` | Clarifier, Architect | 与用户协作撰写需求和方案文档 |
| `frontend-design` | `/mnt/skills/public/frontend-design/SKILL.md` | Builder-Frontend | 生成高质量前端界面 |
| `mcp-builder` | `/mnt/skills/examples/mcp-builder/SKILL.md` | Builder-Backend, Builder-Infra | 构建 MCP 服务器 |
| `skill-creator` | `/mnt/skills/examples/skill-creator/SKILL.md` | 全部 | 创建和迭代自定义 Skill |

### 6.2 自定义 Skill 目录

```
.pipeline/skills/
├── code-simplifier/SKILL.md    # 【必备】量化指标驱动的代码精简规范
├── code-review/SKILL.md        # 【必备】代码审查规范
├── code-style/SKILL.md         # 项目编码规范
├── api-design/SKILL.md         # API 设计规范
├── db-migration/SKILL.md       # 数据库迁移最佳实践
├── security-checklist/SKILL.md # 安全检查清单
├── i18n-guide/SKILL.md         # 国际化规范
├── perf-testing/SKILL.md       # 性能测试规范
└── deploy-runbook/SKILL.md     # 部署手册
```

---

## 7. Pilot 状态机设计

### 7.1 状态定义

```
IDLE
  │
  ▼
PHASE_0_CLARIFICATION ◄──── 业务域澄清，最多 5 轮
  │ 关键项未解决 → ESCALATION
  ▼
PHASE_0_5_REQUIREMENT_COMPLETENESS_CHECKER        ← AutoStep【v5 新增】
  │ FAIL（缺失必填内容）→ 回退 0.clarify
  ▼
PHASE_1_PROPOSAL ◄──────────────────────────────┐
  │                                              │
  ▼                                              │
GATE_A_REVIEW ──┬─ CONFLICT → RESOLVER → 重评估  │
                │   └─ RESOLVER conditions_checklist 非空 → RESOLVER_CONDITIONS_CHECK ← v6 新增
                │         ├─ PASS → PHASE_2
                │         └─ FAIL → rollback_to target_phase
                ├─ PASS ──▶ PHASE_2              │
                └─ FAIL ──▶ (rollback_to) ───────┘

PHASE_2_TASK_BREAKDOWN ◄─────────────────────────┐
  │                                              │
  ▼                                              │
PHASE_2_1_ASSUMPTION_PROPAGATION_VALIDATOR        ← AutoStep【v4 新增】
  │ 未覆盖假设附加给 Auditor-Biz（不自动阻断）
  ▼                                              │
GATE_B_REVIEW (Biz+Tech+QA+Ops) ──┬─ PASS → PHASE_2_5
                                   └─ FAIL → (rollback_to) ─┘

PHASE_2_5_CONTRACT_FORMALIZATION
  │
  ▼
PHASE_2_6_SCHEMA_COMPLETENESS_VALIDATOR           ← AutoStep【v3 新增】
  │ Schema 缺失或格式错误 → 回退 2.5.contract-formalize
  ▼
PHASE_2_7_CONTRACT_SEMANTIC_VALIDATOR             ← AutoStep【v5 新增，修复漏洞 K】
  │ ERROR → 回退 2.5.contract-formalize（语义错误）
  │ WARN  → 不阻断，追加到 gate-c.code-review 参考输入
  ▼
PHASE_3_IMPLEMENTATION ◄──────────────────────────┐
  │ 文件冲突 → 按层次串行化                         │
  ▼                                               │
PHASE_3_1_STATIC_ANALYSIS                         │
  │ lint_error/type_error/vuln → 回退 3.build ───┘│
  ▼                                               │
PHASE_3_2_DIFF_SCOPE_VALIDATION                   │
  │ 越权变更 → 回退违规 Builder 的 3.build ─────────┘
  ▼
PHASE_3_3_REGRESSION_GUARD
  │ 现有测试失败 → 回退 3.build
  ▼
PHASE_3_5_SIMPLIFICATION (code-simplifier skill)
  │
  ▼
PHASE_3_6_POST_SIMPLIFICATION_VERIFIER            ← AutoStep【v3 新增】
  │ 量化目标未达成 → 回退 3.5.simplify
  │ 回归失败 → 回退 3.build
  ▼
GATE_C_CODE_REVIEW (code-review skill)
  │ Pilot 机械验证 simplifier_verified（基于 post-simplify-report.json）
  ├─ PASS ──▶ PHASE_3_7
  └─ FAIL ──▶ 回退（重走 3.1 → 3.2 → 3.3 → 3.5 → 3.6 → gate-c.code-review）

PHASE_3_7_CONTRACT_COMPLIANCE_CHECKER             ← AutoStep【v3 新增】
  │ Schema 不合规 → 回退 3.build（对应 Builder）
  ▼
PHASE_4A_FUNCTIONAL_TESTING
  ├─ PASS → PHASE_4_2_TEST_COVERAGE_ENFORCER
  └─ FAIL → PHASE_4A_1_TEST_FAILURE_MAPPER       ← AutoStep【v5 新增，修复漏洞 L；v6 更新漏洞 R】
               ├─ coverage.lcov 不存在 → 全体回退（跳过 Mapper，降级，v6 新增）
               ├─ PRECISE_MAPPED → 只回退 builders_high_confidence（精确回退）  ← v6
               ├─ LOW_CONFIDENCE_MAPPED → 全体回退（保守降级，v6 新增）
               └─ PARTIAL_MAPPED → 回退所有 Builder（降级，保留 new_test_files 标记）
PHASE_4_2_TEST_COVERAGE_ENFORCER                  ← AutoStep【v3 新增】
  │ 覆盖率不足 → 回退 4a.test
  ▼
PHASE_4B_PERFORMANCE_TESTING (条件，串行)
  ├─ sla_violated: true  → 直接回退 3.build   ← v5 修复漏洞 P
  └─ sla_violated: false → GATE_D_QA_REVIEW
GATE_D_QA_REVIEW
  │ rollback_to 范围限制: 4a.test / 3.build / 2.plan（不得超过 2.plan）
  │ rollback_to 字段由 gate-d.test-review.json 提供（v6 补充，修复漏洞 T）
  ├─ PASS ──▶ AUTOSTEP_API_CHANGE_DETECTOR
  └─ FAIL ──▶ (gate-d.test-review.json.rollback_to)
               Pilot 越界降级：超出允许范围 → 强制 2.plan

AUTOSTEP_API_CHANGE_DETECTOR
  │ 写入 phase_5_mode:                                    ← v5 修复漏洞 M
  │   api_changed: true  + normal  → full          → PHASE_5（完整）
  │   api_changed: false + normal  → changelog_only → PHASE_5（仅 CHANGELOG）
  │   api_changed: true  + hotfix  → full          → PHASE_5（完整）
  │   api_changed: false + hotfix  → skip          → PHASE_6_0（跳过 5.document）
  ▼
PHASE_5_DOCUMENTATION (含 ADR最终化，基于 adr-draft.md)
  │
  ▼
PHASE_5_1_CHANGELOG_CONSISTENCY_CHECKER          ← AutoStep【v4 新增】
  │ CHANGELOG 遗漏 API 变更或模块 → 回退 5.document
  ▼
GATE_E_DOC_REVIEW (Auditor-QA + Auditor-Tech)   ← v4: 新增 Auditor-Tech
  ├─ PASS ──▶ PHASE_6_0
  └─ FAIL ──▶ PHASE_5

PHASE_6_0_PRE_DEPLOY_READINESS_CHECK            ← AutoStep【v4 新增】
  │ 环境变量缺失 / 迁移脚本缺失 / rollback_command 未定义 → ESCALATION
  ▼
PHASE_6_DEPLOY
  ├─ SUCCESS ──▶ PHASE_7
  ├─ DEPLOY_FAIL (partial) ──▶ DEPLOYER 执行 rollback_command → 重试 → 超限 → ESCALATION
  └─ SMOKE_TEST_FAIL ──▶ DEPLOYER 执行 rollback_command → PHASE_3 (mode: post-deploy-smoke-fail)

PHASE_7_MONITORING (量化阈值驱动)
  ├─ STABLE   ──▶ COMPLETED（执行 new_test_files 毕业：写入 regression-suite-manifest.json）
  ├─ ALERT    ──▶ AUTOSTEP_HOTFIX_SCOPE_ANALYZER
  │               ├─ HIGH → 机械生成 hotfix-tasks.json → PHASE_3
  │               └─ LOW  → 单次用户确认 → 生成 hotfix-tasks.json → PHASE_3
  └─ CRITICAL ──▶ PILOT 激活 DEPLOYER 执行生产回滚 ──▶ PHASE_1

ESCALATION ◄──── 超过重试上限 | 0.clarify 关键项未解决
```

### 7.2 Hotfix 流程

即使是 Hotfix，3.1.static-analyze ~ 3.6.simplify-verify 和 gate-c.code-review 也**不可跳过**。5.document 是否执行取决于 API Change Detector 的结果。6.0.deploy-readiness Pre-Deploy Readiness Check 在 Hotfix 中同样不可跳过。

3.2.diff-validate 在 hotfix 模式下（`state.json` 中 `mode: "hotfix"`）改用 `hotfix-tasks.json` 进行范围校验。

```
PHASE_7 (ALERT)
  → AUTOSTEP_HOTFIX_SCOPE_ANALYZER
      HIGH → 机械生成 hotfix-tasks.json（全自动）
      LOW  → 单次用户确认 → 生成 hotfix-tasks.json
  → PHASE_3 (hotfix 修复，state.json: mode=hotfix)
  → PHASE_3_1 (静态分析)
  → PHASE_3_2 (范围校验，使用 hotfix-tasks.json)
  → PHASE_3_3 (回归守卫)
  → PHASE_3_5 (精简)
  → PHASE_3_6 (精简后验证)
  → GATE_C
  → PHASE_3_7 (契约合规检查)
  → PHASE_4A
  → PHASE_4_2 (覆盖率检查)
  → GATE_D
  → AUTOSTEP_API_CHANGE_DETECTOR
  → PHASE_5（api_changed: true 时）
  → PHASE_5_1_CHANGELOG_CONSISTENCY_CHECKER（api_changed: true 时）
  → GATE_E（Auditor-QA + Auditor-Tech）
  → PHASE_6_0_PRE_DEPLOY_READINESS_CHECK
  → PHASE_6
  → PHASE_7
```

### 7.3 状态持久化

`.pipeline/state.json`：

```json
{
  "pipeline_id": "pipe-20250301-001",
  "current_phase": "7.monitor",
  "current_agent": "Monitor",
  "mode": "normal",
  "phase_5_mode": null,
  "new_test_files": [],
  "hotfix": {
    "active": false,
    "scope_confidence": null,
    "hotfix_tasks_file": null
  },
  "attempt_counts": {
    "0.clarify": 1, "1.design": 1, "gate-a.design-review": 1,
    "2.plan": 1, "gate-b.plan-review": 1,
    "2.5.contract-formalize": 1,
    "3.build": 1, "3.1.static-analyze": 1, "3.2.diff-validate": 1, "3.3.regression-guard": 1,
    "3.5.simplify": 1, "gate-c.code-review": 1,
    "4a.test": 1, "4b.optimize": 1, "gate-d.test-review": 1,
    "5.document": 1, "gate-e.doc-review": 1,
    "6.deploy": 1, "7.monitor": 1
  },
  "builder_attempt_counts": {
    "Builder-Frontend": { "3.build": 1 },
    "Builder-Backend":  { "3.build": 1 },
    "Builder-DBA":      { "3.build": 1 },
    "Builder-Security": { "3.build": 1 },
    "Builder-Infra":    { "3.build": 1 }
  },
  "max_attempts": { "default": 3, "0.clarify": 5, "3.build": 5 },
  "last_checkpoint": "7.monitor",
  "active_conditional_agents": {
    "Migrator":   { "active": true,  "reason": "data_migration_required" },
    "Resolver":   { "active": false },
    "Optimizer":  { "active": true,  "reason": "performance_sensitive" },
    "Translator": { "active": false }
  }
}
```

**state.json 新增字段语义（v6，修复漏洞 W）：**

- `phase_5_mode`：值域 `null`（未到 5.document）/ `"full"` / `"changelog_only"` / `"skip"`。写入时机：AUTOSTEP_API_CHANGE_DETECTOR 完成后，Pilot 从 api-change-report.json 同步。读取方：Documenter（决定 5.document 执行内容）、5.1.changelog-check Changelog Consistency Checker（判断是否运行）。

- `new_test_files`：数组，存储本次 Pipeline Tester 新增的测试文件路径列表。写入时机：4a.test 完成后，Pilot 从 impl-manifest.json 同步。清空时机：Pipeline COMPLETED 毕业操作完成。读取方：3.3.regression-guard Regression Guard、3.6.simplify-verify Post-Simplification Verifier（这些文件始终被排除在回归测试范围外，直到毕业）。

**崩溃恢复：** Pilot 启动时检查 `state.json`，若 `current_phase` 处于 `in_progress` 状态，从 `last_checkpoint` 重新执行（AutoStep 幂等，Agent 重新运行）。

**per-Builder 重试计数（v4 修复漏洞 H）：** `builder_attempt_counts` 记录每个 Builder 在 3.build 的独立重试次数。当某个 Builder 因 3.1.static-analyze / 3.2 / 3.3 失败被单独回退时，只递增该 Builder 的计数。Escalation 判断基于单个 Builder 的计数是否超过 `max_attempts["3.build"]`，而非所有 Builder 的全局计数之和。

---

## 8. 目录结构

```
project-root/
├── .pipeline/
│   ├── config.json              # 流水线配置（含监控阈值）
│   ├── state.json               # 当前状态 + 崩溃恢复检查点
│   ├── artifacts/
│   │   ├── requirement.md       # 0.clarify — Markdown
│   │   ├── requirement-completeness-report.json # 0.5.requirement-check AutoStep【v5 新增】
│   │   ├── proposal.md          # 1.design — Markdown
│   │   ├── gate-a.design-review.json   # gate-a.design-review — JSON
│   │   ├── tasks.json           # 2.plan — JSON
│   │   ├── gate-b.plan-review.json   # gate-b.plan-review — JSON
│   │   ├── contracts/           # 2.5.contract-formalize — OpenAPI/Schema【v2 新增】
│   │   │   ├── contract-1.openapi.json
│   │   │   ├── contract-1.schema.json
│   │   │   └── contracts-index.json
│   │   ├── assumption-propagation-report.json # 2.1.assumption-check AutoStep【v4 新增】
│   │   ├── schema-validation-report.json # 2.6.contract-validate-semantic AutoStep【v3 新增】
│   │   ├── contract-semantic-report.json        # 2.7.contract-validate-schema AutoStep【v5 新增】
│   │   ├── impl-manifest.json   # 3.build — JSON（含 new_test_files 字段）
│   │   ├── impl-manifest-builder-*.json # 各 Builder 临时文件【v4 新增，合并后可删除】
│   │   ├── security-checklist.json      # Builder-Security 产物【v4 新增】
│   │   ├── static-analysis-report.json  # 3.1.static-analyze AutoStep【v2 新增】
│   │   ├── scope-validation-report.json # 3.2.diff-validate AutoStep【v2 新增】
│   │   ├── regression-report.json       # 3.3.regression-guard AutoStep【v2 新增】
│   │   ├── simplify-report.md   # 3.5.simplify — Markdown
│   │   ├── post-simplify-report.json    # 3.6.simplify-verify AutoStep【v3 新增】
│   │   ├── gate-c.code-review.md     # gate-c.code-review — Markdown 详细报告
│   │   ├── gate-c.code-review.json   # gate-c.code-review — JSON 结论
│   │   ├── contract-compliance-report.json # 3.7.contract-compliance AutoStep【v3 新增】
│   │   ├── test-report.json     # 4a.test — JSON
│   │   ├── failure-builder-map.json             # 4a.1.test-failure-map AutoStep【v5 新增，4a.test FAIL 时生成】
│   │   ├── coverage-report.json         # 4.2.coverage-check AutoStep【v3 新增】
│   │   ├── perf-report.json     # 4b.optimize — JSON（Optimizer，条件）
│   │   ├── gate-d.test-review.json   # gate-d.test-review — JSON
│   │   ├── api-change-report.json       # 5.document 前置 AutoStep【v2 新增】
│   │   ├── docs-manifest.json   # 5.document — JSON
│   │   ├── changelog-check-report.json  # 5.1.changelog-check AutoStep【v4 新增】
│   │   ├── gate-e.doc-review.json   # gate-e.doc-review — JSON
│   │   ├── deploy-readiness-report.json # 6.0.deploy-readiness AutoStep【v4 新增】
│   │   ├── deploy-report.json   # 6.deploy — JSON
│   │   ├── monitor-report.json  # 7.monitor — JSON
│   │   ├── hotfix-scope-report.json     # Hotfix Scope Analyzer【v3 新增】
│   │   ├── hotfix-tasks.json            # Hotfix 授权范围【v3 新增，hotfix 模式专用】
│   │   ├── adr-draft.md         # 1.design Architect 输出【v4 新增，v5 路径修正】
│   │   └── regression-suite-manifest.json # 累积回归套件清单【v4 新增，跨 Pipeline 持久化】
│   ├── feedback/                # 回溯反馈 — Markdown
│   ├── prompts/                 # 各角色 system prompt — Markdown
│   │   ├── clarifier.md         # 含业务域限制和 ESCALATION 条件
│   │   ├── architect.md         # 含技术域限制（v4: 增加 adr-draft.md 输出要求）
│   │   ├── contract-formalizer.md  # 【新增】
│   │   ├── planner.md
│   │   ├── auditor-biz.md
│   │   ├── auditor-tech.md
│   │   ├── auditor-qa.md
│   │   ├── auditor-ops.md
│   │   ├── builder-frontend.md
│   │   ├── builder-backend.md
│   │   ├── builder-dba.md
│   │   ├── builder-security.md
│   │   ├── builder-infra.md
│   │   ├── simplifier.md        # 含量化指标输入说明
│   │   ├── inspector.md         # 含契约形式化 Schema 使用说明
│   │   ├── tester.md
│   │   ├── documenter.md        # 含 ADR 生成要求
│   │   ├── deployer.md
│   │   ├── monitor.md           # 含量化阈值引用说明
│   │   ├── migrator.md
│   │   ├── resolver.md          # 含矛盾仲裁和 rollback 覆盖逻辑
│   │   ├── optimizer.md
│   │   └── translator.md
│   ├── autosteps/               # AutoStep 脚本
│   │   ├── static-analyzer.sh             # 3.1.static-analyze【v2】（v4 增加 SAST）
│   │   ├── diff-scope-validator.sh        # 3.2.diff-validate【v2】
│   │   ├── regression-guard.sh            # 3.3.regression-guard【v2】（v4 改用 regression-suite-manifest.json）
│   │   ├── api-change-detect.sh         # 5.document 前置【v2】
│   │   ├── schema-completeness-validator.sh  # 2.6.contract-validate-semantic【v3 新增】
│   │   ├── post-simplification-verifier.sh   # 3.6.simplify-verify【v3 新增】
│   │   ├── contract-compliance-checker.sh    # 3.7.contract-compliance【v3 新增】（v4 增加启动失败处理）
│   │   ├── test-coverage-enforcer.sh         # 4.2.coverage-check【v3 新增】
│   │   ├── hotfix-scope-analyzer.sh          # 7.monitor ALERT 后置【v3 新增】
│   │   ├── assumption-propagation-validator.sh # 2.1.assumption-check【v4 新增】
│   │   ├── changelog-consistency-checker.sh    # 5.1.changelog-check【v4 新增】
│   │   ├── pre-deploy-readiness-check.sh       # 6.0.deploy-readiness【v4 新增】
│   │   ├── requirement-completeness-checker.sh  # 0.5.requirement-check【v5 新增】
│   │   ├── contract-semantic-validator.sh        # 2.7.contract-validate-schema【v5 新增】
│   │   └── test-failure-mapper.sh               # 4a.1.test-failure-map【v5 新增】
│   ├── skills/
│   │   ├── code-simplifier/SKILL.md  # 【必备】
│   │   ├── code-review/SKILL.md      # 【必备】
│   │   └── ...
│   └── pilot.sh
├── docs/
│   ├── api/                     # 5.document 产出 — Markdown
│   ├── guides/                  # 5.document 产出 — Markdown
│   └── adr/                     # 5.document 产出 — ADR【新增】
├── CHANGELOG.md
└── src/
```

---

## 9. 配置示例

`.pipeline/config.json`：

```json
{
  "pipeline_name": "default",
  "format_policy": {
    "documents": "markdown",
    "structured_data": "json",
    "forbidden_formats": ["docx", "doc", "pdf", "pptx", "xlsx"]
  },
  "max_attempts": {
    "default": 3,
    "0.clarify": 5,
    "3.build": 5,
    "4a.test": 3,
    "5.document": 2
  },
  "required_skills": ["code-simplifier", "code-review"],
  "clarification_max_rounds": 5,
  "requirement_completeness": {
    "parent_section": "## 最终需求定义",
    "required_sections": ["### 功能描述", "### 用户故事", "### 业务规则", "### 范围边界", "### 验收标准"],
    "section_match_mode": "prefix",
    "min_words": 200,
    "abort_on_critical_unresolved": true
  },
  "clarification_abort_on_critical_unresolved": true,
  "monitoring_window_minutes": 30,
  "monitor_thresholds": {
    "normal":   { "error_rate_pct": 0.1,  "p99_latency_ms": 200 },
    "alert":    { "error_rate_pct": 0.5,  "p99_latency_ms": 500,  "unexpected_error_count": 10 },
    "critical": { "error_rate_pct": 5.0,  "p99_latency_ms": 2000, "service_down": true }
  },
  "static_analysis": {
    "cyclomatic_complexity_threshold": 10,
    "cognitive_complexity_threshold": 15,
    "function_lines_threshold": 50,
    "file_lines_threshold": 300,
    "blocking_on": ["lint_errors", "type_errors", "high_severity_vulnerabilities"]
  },
  "parallel_conflict_resolution_order": ["Builder-DBA", "Builder-Backend", "Builder-Security", "Builder-Frontend", "Builder-Infra"],
  "token_budget": {
    "total": 500000,
    "per_phase_warning_threshold": 50000
  },
  "agents": {
    "Simplifier": {
      "prompt_file": ".pipeline/prompts/simplifier.md",
      "model": "claude-sonnet-4-6",
      "skills": ["code-simplifier"],
      "type": "permanent",
      "note": "读取 static-analysis-report.json 作为量化目标输入，必须在 Inspector 之前执行"
    },
    "Inspector": {
      "prompt_file": ".pipeline/prompts/inspector.md",
      "model": "claude-sonnet-4-6",
      "skills": ["code-review"],
      "type": "permanent",
      "note": "simplifier_verified 由 Pilot 机械设置，Inspector 无需自报；使用 contracts/ 进行契约一致性校验"
    },
    "Contract Formalizer": {
      "prompt_file": ".pipeline/prompts/contract-formalizer.md",
      "model": "claude-sonnet-4-6",
      "skills": [],
      "type": "permanent",
      "note": "输出到 artifacts/contracts/ 目录，格式为 OpenAPI 3.0 + JSON Schema"
    },
    "Documenter": {
      "prompt_file": ".pipeline/prompts/documenter.md",
      "model": "claude-sonnet-4-6",
      "skills": [],
      "type": "permanent",
      "note": "所有输出为 Markdown；必须生成 ADR；Hotfix 时先由 AutoStep:APIChangeDetector 决定是否执行"
    },
    "Monitor": {
      "prompt_file": ".pipeline/prompts/monitor.md",
      "model": "claude-sonnet-4-6",
      "skills": [],
      "type": "permanent",
      "note": "基于 config.json 中的 monitor_thresholds 输出 NORMAL/ALERT/CRITICAL，不依赖主观判断"
    }
  },
  "autosteps": {
    "static-analyzer": {
      "script": ".pipeline/autosteps/static-analyzer.sh",
      "timeout_seconds": 120
    },
    "diff-scope-validator": {
      "script": ".pipeline/autosteps/diff-scope-validator.sh",
      "timeout_seconds": 30
    },
    "regression-guard": {
      "script": ".pipeline/autosteps/regression-guard.sh",
      "timeout_seconds": 300
    },
    "api-change-detect": {
      "script": ".pipeline/autosteps/api-change-detect.sh",
      "timeout_seconds": 30
    },
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
  },
  "testing": {
    "coverage_tool": "nyc",
    "coverage_format": ["lcov", "json"],
    "coverage_output_dir": ".pipeline/artifacts/coverage/",
    "coverage_required": true,
    "note": "4a.test 必须在覆盖率收集模式下运行（v6 新增），coverage.lcov 是 4a.1.test-failure-map 的前置依赖"
  },
  "gates": {
    "gate-b.plan-review": {
      "reviewers": ["Auditor-Biz", "Auditor-Tech", "Auditor-QA", "Auditor-Ops"],
      "pass_strategy": "all",
      "note": "v2 新增 Auditor-Biz，与 gate-a.design-review 保持一致"
    },
    "gate-c.code-review": {
      "reviewers": ["Inspector"],
      "pass_strategy": "all",
      "required_pre_autosteps": ["static-analyzer", "diff-scope-validator", "regression-guard"],
      "required_pre_phase": "3.5.simplify",
      "simplifier_verified_by": "pilot_mechanical_check",
      "required_skill": "code-review",
      "output_formats": { "report": "md", "verdict": "json" },
      "can_rollback_to": ["1.design", "2.plan", "3.build"]
    }
  },
  "hotfix": {
    "phases": [
      "3.build", "3.1.static-analyze", "3.2.diff-validate", "3.3.regression-guard",
      "3.5.simplify", "gate-c.code-review", "4a.test", "gate-d.test-review",
      "autostep-api-change-detect", "5.document-conditional", "6.deploy", "7.monitor"
    ],
    "skip_documentation_if_no_api_change": true,
    "note": "3.1.static-analyze~3.5 和 gate-c.code-review 在 hotfix 中也不可跳过；文档是否跳过由 API Change Detector 决定"
  }
}
```

---

## 10. 实现路径建议

### 10.1 第一阶段：最小可行版本（MVP）

角色精简为 7 个：`Clarifier` → `Architect` → `Auditor-Tech` → `Builder-Backend` → AutoStep（Static + DiffScope + Regression） → `Simplifier` → `Inspector`。

- AutoStep 即使在 MVP 中也不可省略（成本极低，价值高）。
- Simplifier + Inspector 不可省略。
- 使用 `skill-creator` 创建 `code-simplifier` 和 `code-review` 两个必备 Skill。
- Contract Formalizer 可简化为 Planner 直接输出基础 JSON Schema。

### 10.2 第二阶段：完整校验体系

- 接入全部 4 个 Auditor（含 gate-b.plan-review 的 Auditor-Biz）。
- 接入 Contract Formalizer（2.5.contract-formalize）。
- 接入 Resolver 的矛盾检测算法。
- 完善 Monitor 量化阈值配置。

### 10.3 第三阶段：并行实现与条件角色

- 接入所有 Builder（并行执行 + 冲突串行化协议）。
- 接入 Migrator、Optimizer（串行）、Translator。
- Optimizer 确保在 Tester PASS 后启动。

### 10.4 第四阶段：Skill 生态与优化

- 持续迭代 `code-simplifier` 的量化阈值。
- 积累 ADR，为 Architect 提供历史决策参考。
- 优化 AutoStep 脚本，覆盖更多语言和框架。
- 引入 `skill-creator` 建设项目专属 Skill（`api-design`、`security-checklist` 等）。

---

## 11. 风险与缓解措施

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| Simplifier 误改业务逻辑 | 引入 bug | **3.6.simplify-verify Post-Simplification Verifier 重跑 Regression Guard**，机械验证精简未破坏现有功能 |
| Simplifier 精简不足（量化目标未达成） | 复杂代码进入 Code Review | **3.6.simplify-verify 重测复杂度指标**，未达标回退 3.5.simplify 重新精简 |
| 静态分析工具误报 | 大量 WARN 噪音 | 在 config.json 中配置精确阈值；区分 blocking 和 non-blocking 类型 |
| Contract Formalizer 输出错误 Schema | 后续校验失效，3.build 白费 | **2.6.contract-validate-semantic Schema Completeness Validator** 在进入 3.build 前机械验证，回退成本最小化 |
| Diff Scope Validator 误判 | 误回退正常变更 | 白名单机制（如共享 config 文件可由多个 Builder 修改）；Pilot 日志可审计 |
| 4b.optimize Optimizer 串行导致流程变长 | 交付时间增加 | 仅 `performance_sensitive: true` 时激活；简单需求不触发 |
| Monitor 阈值设置不合理 | 误报 ALERT 或漏报 CRITICAL | 阈值通过历史数据校准；支持 per-environment 配置 |
| ADR 积累过多导致 Architect 上下文过长 | token 消耗增加 | Architect 只读取最近 N 条 ADR 和与当前需求相关的 ADR（关键词过滤） |
| Resolver 仲裁覆盖过浅 rollback | 遗留深层问题 | Resolver 须在覆盖时提供明确理由；Gate 失败次数计入 attempt_counts |
| 用户澄清关键项超限 | 流程无法推进 | ESCALATION 中止，人工介入解决后从 0.clarify 重启 |
| 并行 Builder 文件冲突解决后产生集成 bug | 3.3.regression-guard 捕获 | Regression Guard 在串行化完成后运行，发现冲突引入的回归 |
| LLM 校验不稳定 | 流程抖动 | Checklist + 结构化输出；temperature 设为 0；AutoStep 替代机械判断 |
| 上下文窗口溢出 | 丢失信息 | 所有产物落盘为文件；Agent 按需读取；单 Agent token 预算告警 |
| Token 成本失控 | 费用过高 | per-phase 预算告警；AutoStep 替代 LLM 处理机械任务 |

---

## 12. 角色全景汇总

### 12.1 常驻 Agent（19 个）

| # | 角色名 | 类型 | 阶段 | 必备 Skill |
|---|--------|------|------|-----------|
| 1 | Clarifier | Agent | 0.clarify | — |
| 2 | Architect | Agent | 1.design | — |
| 3 | Auditor-Biz | Agent | gate-a.design-review / **gate-b.plan-review** | — |
| 4 | Auditor-Tech | Agent | gate-a.design-review / gate-b.plan-review | — |
| 5 | Auditor-QA | Agent | gate-a.design-review / gate-b.plan-review / gate-d.test-review / gate-e.doc-review | — |
| 6 | Auditor-Ops | Agent | gate-a.design-review / gate-b.plan-review | — |
| 7 | Planner | Agent | 2.plan | — |
| 8 | **Contract Formalizer** | **Agent** | **2.5.contract-formalize** | — |
| 9 | Builder-Frontend | Agent | 3.build | — |
| 10 | Builder-Backend | Agent | 3.build | — |
| 11 | Builder-DBA | Agent | 3.build | — |
| 12 | Builder-Security | Agent | 3.build | — |
| 13 | Builder-Infra | Agent | 3.build | — |
| 14 | **Simplifier** | Agent | 3.5.simplify | **`code-simplifier`** |
| 15 | **Inspector** | Agent | gate-c.code-review | **`code-review`** |
| 16 | Tester | Agent | 4a.test | — |
| 17 | Documenter | Agent | 5.document | — |
| 18 | Deployer | Agent | 6.deploy | — |
| 19 | Monitor | Agent | 7.monitor | — |

### 12.2 条件 Agent（4 个）

| # | 角色名 | 类型 | 阶段 | 激活条件 |
|---|--------|------|------|---------|
| 20 | Migrator | 条件 Agent | 3.build | `data_migration_required: true` |
| 21 | Resolver | 条件 Agent | 任意 Gate | 矛盾检测算法触发 |
| 22 | **Optimizer** | 条件 Agent | **4b.optimize（串行）** | `performance_sensitive: true` |
| 23 | Translator | 条件 Agent | 3.build | `i18n_required: true` |

### 12.3 AutoStep（15 个）

| # | 步骤名 | 类型 | 阶段 | 版本 |
|---|--------|------|------|------|
| 24 | Static Analyzer | AutoStep | 3.1.static-analyze | v2（v4 增加 SAST） |
| 25 | Diff Scope Validator | AutoStep | 3.2.diff-validate | v2 |
| 26 | Regression Guard | AutoStep | 3.3.regression-guard | v2（v4 改用 regression-suite-manifest） |
| 27 | API Change Detector | AutoStep | 5.document 前置 | v2 |
| 28 | **Schema Completeness Validator** | AutoStep | **2.6.contract-validate-semantic** | **v3** |
| 29 | **Post-Simplification Verifier** | AutoStep | **3.6.simplify-verify** | **v3** |
| 30 | **Contract Compliance Checker** | AutoStep | **3.7.contract-compliance** | **v3**（v4 增加启动失败处理） |
| 31 | **Test Coverage Enforcer** | AutoStep | **4.2.coverage-check** | **v3** |
| 32 | **Hotfix Scope Analyzer** | AutoStep | **7.monitor ALERT 后置** | **v3** |
| 33 | **Assumption Propagation Validator** | AutoStep | **2.1.assumption-check** | **v4** |
| 34 | **Changelog Consistency Checker** | AutoStep | **5.1.changelog-check** | **v4** |
| 35 | **Pre-Deploy Readiness Check** | AutoStep | **6.0.deploy-readiness** | **v4** |
| 36 | **Requirement Completeness Checker** | AutoStep | **0.5.requirement-check** | **v5** |
| 37 | **Contract Semantic Validator** | AutoStep | **2.7.contract-validate-schema** | **v5** |
| 38 | **Test Failure Mapper** | AutoStep | **4a.1.test-failure-map（FAIL 时）** | **v5** |

**共计 38 个执行单元：19 个常驻 Agent + 4 个条件 Agent + 15 个 AutoStep。**

---

## 13. 总结

本方案（v4）将软件交付流程建模为一个**带门禁的有限状态机**，通过 35 个执行单元的分工协作，在 Claude Code 中实现接近真实团队协作的开发流水线。

**v2 核心改进要点：**

1. **AutoStep 剥离机械任务**：静态分析、变更范围校验、回归守卫、API 变更检测，4 个 AutoStep 将确定性检查从 LLM 中剥离，降低成本、提升可靠性。

2. **量化驱动精简**：Simplifier 以 static-analysis-report.json 的圈复杂度、认知复杂度、函数行数等量化指标为目标，精简工作不再依赖 LLM 主观判断。

3. **契约形式化（2.5.contract-formalize）**：Contract Formalizer 将自然语言接口契约升级为 OpenAPI/JSON Schema，Inspector 进行契约一致性审查时有机械依据。

4. **gate-b.plan-review 补入 Auditor-Biz**：封堵任务细化阶段的业务偏差，4 个 Auditor 在两个关键 Gate 完整参与。

5. **simplifier_verified 机械化**：由 Pilot 检查文件时间戳，替代 Inspector 的 LLM 自报，消除 hallucination 风险。

6. **Optimizer 串行化**：改为 Tester PASS 后才启动，杜绝在有功能 bug 的代码上产生无效性能数据。

7. **Monitor 量化阈值**：NORMAL/ALERT/CRITICAL 三级告警由配置驱动，Monitor 输出确定性结论。

8. **Hotfix 文档策略精化**：由 API Change Detector 决定是否必须更新文档，取代一刀切的"全跳过"。

9. **问题域分离**：Clarifier（业务域）和 Architect（技术域）问题不重叠，用户不被重复提问。

10. **崩溃恢复机制**：`state.json` 记录 `last_checkpoint`，Pilot 启动时自动恢复中断的流水线。

**v3 新增改进要点：**

11. **精简量化闭环（3.6.simplify-verify）**：Post-Simplification Verifier 在精简后机械验证量化目标是否真正达成，同时重跑 Regression Guard，将 Simplifier 的自我承诺升级为机械验证。

12. **Schema 前置校验（2.6.contract-validate-semantic）**：Schema Completeness Validator 在进入 3.build 实现前验证 Contract Schema 的完整性和格式合法性，防止用整个实现阶段的成本来验证一个 Schema 错误。

13. **契约机械测试（3.7.contract-compliance）**：Contract Compliance Checker 在功能测试前用工具自动验证 API 实现与 OpenAPI Schema 的合规性，比 LLM 审查更可靠，同时降低 Tester 工作量。

14. **覆盖率量化门禁（4.2.coverage-check）**：Test Coverage Enforcer 补充新增代码的行/分支覆盖率机械验证，防止 Tester 只写 happy-path 测试。

15. **gate-d.test-review rollback 范围收敛**：Auditor-QA 的 rollback_to 限制在 3.build/2.plan，避免测试失败触发不合理的深层回退。

16. **CRITICAL 回滚主体明确**：Pilot 重新激活 Deployer 执行生产回滚，明确执行主体。

17. **Resolver 矛盾检测去递归**：内容矛盾改用关键词对算法，Resolver 只做仲裁不做判断，避免 LLM 判断 LLM 的递归问题。

18. **Hotfix Diff Scope 死锁解决（7.monitor-ALERT Hotfix Scope Analyzer）**：引入置信度评估机制，高置信度（告警可定位到具体端点→contract→task→文件）时机械生成 hotfix-tasks.json 全自动完成；低置信度时单次用户确认，3.2.diff-validate 在 hotfix 模式下改用 hotfix-tasks.json 校验，彻底解决原设计的必然死锁。

**v4 新增改进要点：**

19. **6.deploy 失败路径完整定义（修复漏洞 A）**：新增 6.0.deploy-readiness Pre-Deploy Readiness Check 前置 AutoStep；明确区分"部署脚本失败""Smoke Test 失败""监控异常"三种场景的不同处理路径，消除状态机空白。

20. **并行写入竞争消除（修复漏洞 B）**：各 Builder 写独立临时文件 `impl-manifest-<id>.json`，Pilot 统一合并，根除 impl-manifest.json 的并发写入竞争条件。

21. **Resolver 下边界保护（修复漏洞 C）**：Pilot 机械验证 Resolver 不得将 rollback_to 设为 null，防止 LLM 幻觉绕过所有审查。

22. **3.7.contract-compliance 基础设施故障与契约违规分离（修复漏洞 D）**：服务启动失败 → Escalation（非 Builder 问题），契约测试失败 → 回退 3.build（Builder 问题），两种故障类型处理路径不再混淆。

23. **gate-e.doc-review 引入 Auditor-Tech（修复漏洞 E）**：Auditor-Tech 负责 API 文档技术准确性和 ADR 决策质量审查，Auditor-QA 负责 CHANGELOG 完整性和测试文档，文档质量保障不再依赖单一角色。

24. **假设传播追踪（修复漏洞 F + 新活动）**：2.1.assumption-check Assumption Propagation Validator 机械追踪 requirement.md 中每条 `[ASSUMED:...]` 是否在 tasks.json 中有对应引用，无覆盖则提前告警，消除假设漂移。

25. **测试文件毕业机制（修复漏洞 G）**：Pipeline COMPLETED 时，Pilot 自动将 new_test_files 写入跨 Pipeline 持久化的 `regression-suite-manifest.json`，确保新测试在下次运行时正式加入回归套件，消除长期测试盲点。

26. **per-Builder 重试计数（修复漏洞 H）**：state.json 新增 `builder_attempt_counts`，各 Builder 独立计数，防止多 Builder 独立失败时计数合并触发误 Escalation。

27. **Contract Formalizer 模板驱动（修复漏洞 I）**：Pilot 从 tasks.json 机械生成 OpenAPI 骨架，LLM 仅填充语义字段，大幅降低格式错误概率，2.6.contract-validate-semantic 复查效果更可预期。

28. **Builder-Security 安全清单产物（修复漏洞 J）**：security-checklist.json 记录已处理威胁，Inspector 和 Auditor-Tech 可直接引用，避免重复分析，聚焦漏网威胁。

29. **ADR 草稿前置到 1.design（新活动）**：Architect 在 1.design 输出 adr-draft.md，保留决策理由最鲜活的上下文；Documenter 在 5.document 基于草稿最终化，提升 ADR 质量和完整性。

30. **SAST 源码安全扫描（新活动）**：3.1.static-analyze Static Analyzer 集成 Semgrep（OWASP Top 10 规则集），机械检测 SQL 注入、XSS、SSRF 等安全模式，高危发现阻断流程，中低危作为 Inspector 参考。

31. **Changelog 一致性门禁（新活动）**：5.1.changelog-check Changelog Consistency Checker 机械验证 CHANGELOG 中的 API 变更条目覆盖 api-change-report.json 的所有变更，防止遗漏或错误记录。

**v5 新增改进要点：**

32. **需求完整性前置门禁（新活动 0.5.requirement-check）**：Requirement Completeness Checker AutoStep 在进入 gate-a.design-review 前机械验证需求文档的必填 Section、关键项清零、假设格式合规，让 Auditor 聚焦内容审查。

33. **契约语义校验（新活动 2.7.contract-validate-schema，修复漏洞 K）**：Contract Semantic Validator AutoStep 使用 Spectral 和比对脚本，封堵"格式合法但语义错误"的 OpenAPI Schema，将发现点从 3.7.contract-compliance 前移至 2.7.contract-validate-schema，回退成本降至最低。

34. **测试失败精确归因（新活动 4a.1.test-failure-map，修复漏洞 L）**：Test Failure Mapper AutoStep 通过覆盖率数据将测试失败映射到责任 Builder，实现精确回退，避免多 Builder 场景下的无辜全体回退。

35. **5.document 策略完整定义（修复漏洞 M）**：新增 `phase_5_mode` 字段，明确正常流程下 `api_changed: false` 时的 `changelog_only` 路径，消除状态机空白。

36. **gate-b.plan-review 假设处置结构化（修复漏洞 O）**：gate-b.plan-review.json 新增 `assumption_dispositions`，假设的处置决策从自然语言 comments 升级为可机械流转的结构化记录。

37. **Optimizer 直接回退（修复漏洞 P）**：perf-report.json 新增 `sla_violated` 字段，SLA 明确违规时 Pilot 无需等待 gate-d.test-review，直接触发 3.build 回退。

**v6 新增改进要点：**

38. **Resolver 条件承诺机械化（修复漏洞 Q）**：resolver_verdict 新增结构化 `conditions_checklist` 数组，Pilot 在放行前逐条机械验证条件是否满足（grep / exists / field_value），验证结果写入 `resolver-conditions-check.json`，彻底消除 Resolver 条件成空话的风险。

39. **Test Failure Mapper 精确回退的置信度保护（修复漏洞 R）**：4a.1.test-failure-map 新增 `PRECISE_MAPPED`（全部 HIGH confidence）/ `LOW_CONFIDENCE_MAPPED`（存在 LOW confidence）两种 overall 值，LOW confidence 映射触发保守全体回退，防止不确定的 Builder 归属导致无辜 Builder 被精确回退。

40. **0.5.requirement-check 标题层级 bug 修复（修复漏洞 S，高危）**：0.5.requirement-check Section 检查从搜索 H2 标题（`## 功能描述`）修正为搜索 `## 最终需求定义` 下的 H3 子节（`### 功能描述` 等），修复了对所有合法 requirement.md 永远输出 FAIL 的严重 bug。

41. **gate-d.test-review 产物 schema 完整化（修复漏洞 T）**：gate-d.test-review.json 补充结构化 `rollback_to` 字段，与 gate-a.design-review / gate-c.code-review 产物格式对齐，Pilot 机械解析回退目标；超出允许范围的值自动降级并记录警告。

42. **new_test_files 排除规则统一（修复漏洞 U）**：new_test_files 的 Regression Guard 排除规则从"仅 4a.test FAIL 时"扩展为"任意 3.build 回退路径均适用"，消除 gate-c.code-review FAIL 等场景下的排除规则歧义。

43. **4a.test 覆盖率生成强制化（修复漏洞 V）**：4a.test 产物列表新增 coverage.lcov（必须生成），config.json 新增 `testing.coverage_required: true` 配置，消除 4a.1.test-failure-map 对覆盖率数据的隐式依赖，确保精确回退功能真正可用。

44. **state.json schema 完整化（修复漏洞 W）**：state.json 补充 `phase_5_mode` 和 `new_test_files` 两个字段定义，明确写入时机和读取方，修复崩溃恢复时这两个关键字段丢失导致流转失效的问题。

---

## 14. 设计审查记录

本节记录在设计审查过程中发现并修复的逻辑问题。

### 14.1 已修复问题汇总

| 漏洞 | 问题描述 | 修复方式 | 修复版本 |
|------|---------|---------|---------|
| 漏洞 1 | Simplifier 精简后量化目标未机械验证 | 新增 3.6.simplify-verify Post-Simplification Verifier | v3 |
| 漏洞 2 | Simplifier 精简后 Regression Guard 未重跑 | 3.6.simplify-verify 同时重跑回归测试 | v3 |
| 漏洞 3 | Tester 新增测试文件回退后纳入 Regression Guard 导致死锁 | impl-manifest.json 增加 `new_test_files` 字段，3.3/3.6 明确排除 | v3 |
| 漏洞 4 | Contract Formalizer 输出错误 Schema 后整个 3.build 白费 | 新增 2.6.contract-validate-semantic Schema Completeness Validator 前置校验 | v3 |
| 漏洞 5 | Hotfix 时 tasks.json 为旧版导致 Diff Scope Validator 必然判"越权"，形成死锁 | 新增 Hotfix Scope Analyzer（置信度驱动），生成 hotfix-tasks.json，3.2.diff-validate hotfix 模式下改用该文件校验 | v3 |
| 漏洞 6 | CRITICAL 回滚执行主体未定义 | 明确由 Pilot 重新激活 Deployer 执行 | v3 |
| 漏洞 7 | gate-d.test-review 的 Auditor-QA rollback 范围过宽（可回退到 0.clarify） | 限制 rollback_to 范围为 4a.test / 3.build / 2.plan | v3 |
| 漏洞 8 | Resolver 内容矛盾检测依赖 LLM 自判（递归问题） | 改为关键词对算法检测，Resolver 仅做仲裁 | v3 |
| 漏洞 9 | 并行 Builder 集成后契约合规无机械验证 | 新增 3.7.contract-compliance Contract Compliance Checker | v3 |
| 漏洞 A | 6.deploy 部署失败（deploy_status: FAIL / smoke_test: FAIL）的 rollback_to 未定义，状态机存在空白路径 | 新增 6.0.deploy-readiness Pre-Deploy Readiness Check；明确三类失败场景的独立处理路径（脚本失败→重试/Escalation，Smoke Test 失败→回滚+回退 3.build） | v4 |
| 漏洞 B | 多 Builder 并行完成时同时写 impl-manifest.json，后写者覆盖先写者记录（竞争条件） | 各 Builder 写独立临时文件 impl-manifest-\<id\>.json，Pilot 统一合并 | v4 |
| 漏洞 C | Resolver 可将 rollback_to 设为 null，LLM 幻觉可绕过所有 Auditor 审查 | Pilot 机械拦截 null 覆盖，任何存在 FAIL Auditor 的情况下强制采用最深规则 | v4 |
| 漏洞 D | 3.7.contract-compliance 服务启动失败与契约测试失败共享相同处理路径（均回退 3.build），但二者根因完全不同 | 服务启动失败 → startup_error: true → Escalation（基础设施问题，非 Builder 问题）；契约测试失败 → 回退 3.build | v4 |
| 漏洞 E | gate-e.doc-review 仅 Auditor-QA，API 文档技术准确性和 ADR 决策质量缺乏技术视角审核 | gate-e.doc-review 新增 Auditor-Tech，分别负责技术文档准确性（Tech）和完整性（QA） | v4 |
| 漏洞 F | requirement.md 中的 [ASSUMED:...] 假设无下游追踪机制，可能被 Planner 静默违背（假设漂移） | 新增 2.1.assumption-check Assumption Propagation Validator AutoStep | v4 |
| 漏洞 G | Pipeline new_test_files 无"毕业"机制，新写测试永远不加入正式回归套件，形成长期测试盲点 | Pipeline COMPLETED 时自动执行毕业操作，写入 regression-suite-manifest.json | v4 |
| 漏洞 H | attempt_counts 按 Phase 全局计数，多 Builder 独立失败时计数合并，可能误触发 Escalation | state.json 新增 builder_attempt_counts，每个 Builder 独立计数和 Escalation 判断 | v4 |
| 漏洞 I | Contract Formalizer 用 LLM 从头生成 OpenAPI 格式，但路径/方法/错误码均已在 tasks.json 中，LLM 处理格式问题引入不必要的不稳定性 | Pilot 机械生成 OpenAPI 骨架模板，LLM 仅填充语义字段 | v4 |
| 漏洞 J | Builder-Security 只产出代码变更，无安全决策记录，Inspector 无法知道哪些威胁已处理，可能重复审查或漏网 | Builder-Security 新增产物 security-checklist.json，记录已处理威胁和 known_gaps | v4 |
| 漏洞 K | 2.6.contract-validate-semantic 只验证 OpenAPI 格式合法性，无法检测字段类型错误、路径参数 required 遗漏等语义错误，Builder 基于错误 Schema 实现后 3.7.contract-compliance 才发现 | 新增 2.7.contract-validate-schema Contract Semantic Validator（Spectral + 比对脚本） | v5 |
| 漏洞 L | 4a.test 测试失败后 test-report.json 无 Builder 责任映射，Pilot 只能全体回退，浪费无辜 Builder 的重做成本 | 新增 4a.1.test-failure-map Test Failure Mapper（AutoStep），精确映射责任 Builder | v5 |
| 漏洞 M | 正常流程下 api_changed: false 时 5.document 的执行策略未定义（状态机空白路径） | 新增 phase_5_mode: changelog_only，明确只更新 CHANGELOG 的 partial 执行路径 | v5 |
| 漏洞 N | 第 8 节目录结构 .pipeline/artifacts/ 出现两次，adr-draft.md 路径存在二义性 | 统一为单一 artifacts 目录，adr-draft.md 与其他产物并列 | v5 |
| 漏洞 O | gate-b.plan-review.json 无字段记录 Auditor-Biz 对未覆盖假设的处置决策，假设是否被接受仅存于自然语言 comments | 新增 assumption_dispositions 数组，支持 ACCEPTED / REQUIRE_PLANNER_COVERAGE 机械流转 | v5 |
| 漏洞 P | Optimizer SLA 明确违规时无直接回退机制，需等待 gate-d.test-review 的主观审批，产生不必要延迟 | perf-report.json 新增 sla_violated 字段，Pilot 机械检测并直接触发 3.build 回退 | v5 |
| 漏洞 Q | Resolver 的 conditions 字段为纯文本，无机械验证路径；Resolver 说"PASS"并附条件后，Pilot 直接推进，条件是否被执行完全依赖下游 Agent 是否读到文字 | resolver_verdict 新增结构化 conditions_checklist，Pilot 逐条机械验证（grep/exists/field_value），验证结果写入 resolver-conditions-check.json | v6 |
| 漏洞 R | 4a.1.test-failure-map 的 confidence 字段（HIGH/LOW/UNKNOWN）完全不影响流转决策，LOW confidence 的不确定映射与 HIGH confidence 的确定映射被同等对待，可能导致无辜 Builder 被精确回退 | 流转规则新增 confidence 维度：PRECISE_MAPPED（全部 HIGH）→ 只回退 builders_high_confidence；LOW_CONFIDENCE_MAPPED（存在 LOW）→ 降级全体回退 | v6 |
| 漏洞 S | 0.5.requirement-check 检查 `## 功能描述`（H2），但 requirement.md 格式定义的是 `### 功能描述`（H3，位于 `## 最终需求定义` 下），导致所有合法文档永远输出 FAIL（高危 bug） | 0.5.requirement-check 改为在 `## 最终需求定义` 下检查 H3 子节；config.json required_sections 从 H2 改为 H3；新增 `### 业务规则` 检查项 | v6 |
| 漏洞 T | gate-d.test-review 产物 gate-d.test-review.json 缺少 rollback_to 字段，gate-d.test-review FAIL 时 Pilot 无法机械解析回退目标，与 gate-a.design-review / gate-c.code-review 产物格式不一致，违反"产物驱动流转"原则 | gate-d.test-review.json 补充 rollback_to 字段，枚举值限制为 null / 4a.test / 3.build / 2.plan；Pilot 机械验证并在越界时降级 | v6 |
| 漏洞 U | new_test_files 的 Regression Guard 排除规则只定义了"4a.test FAIL 回退"场景，未覆盖 gate-c.code-review FAIL、gate-d.test-review FAIL、Optimizer SLA 违规等其他 3.build 回退路径，语义歧义导致实现时各路径行为不一致 | 明确规定 new_test_files 排除规则适用于当前 Pipeline 内所有 3.build 回退路径，清空时机统一为 Pipeline COMPLETED 毕业操作 | v6 |
| 漏洞 V | 4a.test 产物定义只有 test-report.json，未提及 coverage.lcov；4a.1.test-failure-map 隐式依赖 coverage.lcov；若 Tester 未启用覆盖率收集，4a.1.test-failure-map 全部返回 UNKNOWN，精确回退完全失效 | 4a.test 产物列表新增 coverage.lcov（必须生成）；config.json 新增 testing.coverage_required: true；Pilot 在 4a.1.test-failure-map 前验证 coverage.lcov 存在 | v6 |
| 漏洞 W | state.json schema 缺少 phase_5_mode 和 new_test_files 字段定义，但两者在 5.document 和 7.monitor 毕业机制中均被读取；崩溃恢复后这两个字段丢失，导致 Documenter 无法确定 5.document 执行模式，new_test_files 排除规则失效 | state.json schema 补充 phase_5_mode（枚举：null/full/changelog_only/skip）和 new_test_files（数组）字段；明确 Pilot 写入时机 | v6 |

### 14.2 漏洞 5 设计详记 — Hotfix Diff Scope 死锁

**问题根因：** tasks.json 是原需求的授权文件，hotfix 的修复文件不在其中，3.2.diff-validate 用旧 tasks.json 校验必然触发越权 → 回退 3.build → 再次越权，死循环。

**解决方案：Hotfix Scope Analyzer + 置信度评估**

核心思路：利用流水线已有产物（contracts/ + tasks.json + impl-manifest.json）机械推断 hotfix 范围；推断成功（HIGH）则全自动；推断失败（LOW）则单次用户确认。3.2.diff-validate 在 hotfix 模式下改用 hotfix-tasks.json 校验。

**置信度规则（纯机械，4 条全满足为 HIGH，否则 LOW）：**

1. monitor-report.json 存在 `endpoint` 字段（可定位到具体 API 端点）
2. 该端点在 contracts/ 中有对应 operationId
3. 该 contract 在 tasks.json 中只关联一个 task
4. 该 task 只由一个 Builder 负责

**HIGH 时的自动映射链：** 告警端点 → contract → task → impl-manifest 中的授权文件 → hotfix-tasks.json（无 LLM，全程机械）

**LOW 时的最小人工介入：** Pilot 向用户展示推断结果和候选文件列表，用户单次回答确认范围，Pilot 机械生成 hotfix-tasks.json（不经 LLM）
