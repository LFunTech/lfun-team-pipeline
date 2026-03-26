# Identity Login Proposal Rewrite Guide

> 用于重写 `P-102 ~ P-108`，避免复现 `P-101` 那种“目标没错，但 proposal 过宽、边界过虚、Gate C 反复打回”的情况。

## 总原则

- 不再用“一个 proposal 同时做 UI、后端规则、migration、外部系统、ready/安全契约”这种写法
- 每个 proposal 必须先声明 `source_of_truth`
- 每个 proposal 必须明确 `forbidden_changes`
- 每个 proposal 必须给出最小 `pre_gate_test_bundle`
- 涉及外部系统、状态机、兼容迁移时，优先拆 proposal，而不是在一个 scope 里靠“包含/不包含”硬控

---

## P-102 重写建议

### 建议保留为单 proposal

`P-102` 可以保留为单 proposal，但必须强约束为 `ui-only`。

### proposal_classification

- `ui-only`

### source_of_truth

- 身份与登录配置的数据真相源来自 `P-101` 后端统一聚合接口
- 本 proposal 不新增或改变任何后端业务规则

### hidden_coupling

- 继承态 / 生效态显示语义
- 术语收口容易顺手改后端字段名
- 预览 UI 容易反向要求改真实登录流程

### forbidden_changes

- 不修改 backend controller / service / migration
- 不新增后端字段
- 不改变保存入参与响应契约
- 不改变真实登录链路逻辑

### 必补矩阵

- `state_rule_matrix`
  - 未配置登录方式 → 预览显示“请选择登录方式”
  - 继承态 → 只展示真实生效值，不展示伪选项
- `contract_matrix`
  - 仅列前端依赖的只读接口；注明“本 proposal 不改 contract”

### pre_gate_test_bundle

- UI snapshot / visual regression
- 术语黑名单扫描
- 预览态矩阵测试

---

## P-103 重写建议

### 必须拆分

拆为：

- `P-103A` 登录安全与注册/核验后端规则闭环
- `P-103B` 学校后台前端联动与风险提示

### 为什么必须拆

原 proposal 同时包含：

- 保存校验
- 提交校验
- required_fields 真相源
- 唯一性规则
- TOTP 风险提示
- 前端即时联动

这是标准的 `validation-rules + ui-only` 混合 proposal，极易复刻 `P-101`。

### P-103A 要求

#### proposal_classification

- `validation-rules`

#### source_of_truth

- `required_fields` 仅允许一个后端真相源
- 保存可行性和运行时提交可行性由后端规则统一定义

#### 必补矩阵

- `state_rule_matrix`
  - 登录方式 -> 手机号必填要求
  - 用户名密码 -> 用户名生成/映射要求
  - 注册审批 -> 自助注册依赖
  - 核验审批 -> approval_role 必填依赖
  - TOTP -> 保存提示 / 登录引导边界
- `contract_matrix`
  - 保存接口 200/400/409
  - 提交接口 200/400/403/409

#### forbidden_changes

- 不改 UI 预览视觉结构
- 不落地真实审批流
- 不改 Keycloak 登录链

#### pre_gate_test_bundle

- rule matrix contract tests
- single source of truth tests for required_fields
- uniqueness boundary tests

### P-103B 要求

#### proposal_classification

- `ui-only`

#### source_of_truth

- 所有联动提示以 `P-103A` 规则输出为准

#### forbidden_changes

- 不新增后端业务规则
- 不修改后端错误码

---

## P-104 重写建议

### 必须拆分

拆为：

- `P-104A` 注册审批流落地
- `P-104B` 身份核验审批流落地

### 为什么必须拆

这两个流程虽然看起来相似，但状态、触发点、结果副作用都不同；混在一个 proposal 里会让状态机、权限、审计、幂等边界失焦。

### 两个 proposal 的共同要求

#### proposal_classification

- `workflow-state-machine`

#### source_of_truth

- 本地申请单状态机为真相源
- 审批结果驱动后续副作用，而不是前端按钮状态

#### 必补矩阵

- `state_rule_matrix`
  - `pending -> approved`
  - `pending -> rejected`
  - 是否允许重复提交 / 撤回 / 重试
- `contract_matrix`
  - 创建申请
  - 查询申请
  - 审批动作
  - 重复审批 / 非法状态迁移错误码

#### forbidden_changes

- 不在本 proposal 内做 Keycloak 同步
- 不在本 proposal 内做 token claim 调整

#### pre_gate_test_bundle

- state transition suite
- approval authority suite
- idempotency suite

---

## P-105 重写建议

### 必须拆分

拆为：

- `P-105A` 身份结果本地到 Keycloak 的同步主链路
- `P-105B` 同步任务与补偿机制

### 为什么必须拆

原 proposal 同时包含：

- 本地数据正确性
- Keycloak 同步
- token claim 数据源兼容
- 单个/批量补偿
- 失败重试和状态记录

这是典型的 `external-integration + async compensation` 混合 proposal。

### P-105A 要求

#### source_of_truth

- 本地身份数据是真相源
- Keycloak 为派生目标系统

#### 必补矩阵

- `state_rule_matrix`
  - 哪些事件触发同步
  - 审批通过 / 无审批直达场景的同步时机
- `contract_matrix`
  - 同步结果状态字段
  - 外部失败的本地返回语义

#### forbidden_changes

- 不直接修改 identity-token-mapper 本体
- 不在本 proposal 内定义新的 token claim 结构

### P-105B 要求

#### proposal_classification

- `external-integration`
- `observability-ops`

#### 必补矩阵

- `state_rule_matrix`
  - pending/running/succeeded/failed/dead-letter
- `contract_matrix`
  - 手动补偿接口
  - 批量补偿接口

#### pre_gate_test_bundle

- idempotency suite
- retry / compensation suite
- task state machine suite

---

## P-106 重写建议

### 可保留为单 proposal，但必须补矩阵

#### proposal_classification

- `domain-model`
- `observability-ops`

#### source_of_truth

- 运营后台的每身份默认配置是真相源
- 学校身份是否继承由学校侧状态决定

#### hidden_coupling

- 继承/脱继承
- fan-out 推送
- 非覆盖保证

#### 必补矩阵

- `state_rule_matrix`
  - 继承态 -> 接收 fan-out
  - 已脱继承 -> 永不覆盖
- `contract_matrix`
  - 平台默认配置更新接口
  - 影响范围预览接口（如有）

#### forbidden_changes

- 不扩展到学校 UI 预览
- 不顺手修改真实登录页

#### pre_gate_test_bundle

- fan-out non-overwrite suite
- inheritance state suite

---

## P-107 重写建议

### 必须拆分，且是最高优先级风险项

至少拆为：

- `P-107A` 多身份入口与路由优先级
- `P-107B` 六种登录方式真实执行链
- `P-107C` 图形验证码与 MFA / TOTP 兼容

### 为什么必须拆

原 proposal 同时混入：

- Keycloak authenticator 改造
- identity_type 路由
- 六种真实登录方式
- 图形验证码
- TOTP / MFA
- 第三方 identity 锁定
- client_id 语义边界

这是当前最像会复刻 `P-101` 的 proposal。

### P-107A 要求

#### proposal_classification

- `external-integration`
- `validation-rules`

#### source_of_truth

- identity_type 路由优先级由后端登录入口规则定义

#### 必补矩阵

- `state_rule_matrix`
  - identity_type 参数优先级
  - 默认身份解析逻辑
  - 指定身份锁定逻辑

### P-107B 要求

#### proposal_classification

- `external-integration`

#### 必补矩阵

- 每种登录方式的真实执行步骤矩阵
- 哪些是 OR，哪些是 AND
- 用户名/手机号唯一性边界

### P-107C 要求

#### proposal_classification

- `external-integration`
- `observability-ops`

#### 必补矩阵

- captcha 生效矩阵
- TOTP 绑定引导矩阵
- 与现有 authenticator 的兼容边界

#### forbidden_changes

- 不允许“推翻重写”现有 authenticator，只能按 proposal 明示边界增量扩展

#### pre_gate_test_bundle

- e2e flow matrix
- authenticator compatibility suite
- captcha / MFA edge-case suite

---

## P-108 重写建议

### 可保留为单 proposal

#### proposal_classification

- `ui-only`
- `external-integration`

#### source_of_truth

- 学校品牌配置为真相源，无配置时回退平台默认品牌

#### hidden_coupling

- tenant / school 识别
- 身份切换时品牌保持
- 加载失败回退

#### forbidden_changes

- 不改变登录流程判定
- 不改变 identity_type 路由
- 不改变验证码 / MFA 行为

#### 必补矩阵

- `state_rule_matrix`
  - 学校品牌命中
  - 默认品牌回退
  - 加载失败回退
- `contract_matrix`
  - 品牌加载来源接口或模板注入点

#### pre_gate_test_bundle

- brand fallback suite
- identity switch branding suite
- known identity direct-entry branding suite

---

## 建议执行顺序

按 proposal 加固优先级：

1. 先重写 `P-107`
2. 再重写 `P-103`
3. 再重写 `P-104`
4. 再重写 `P-105`
5. 然后补强 `P-106`
6. 最后处理 `P-102`、`P-108`

一句话：

> `P-102` 和 `P-108` 更像边界收紧；`P-103`、`P-104`、`P-105`、`P-107` 则必须先拆，再做。

## 对应草案

- 可直接参考 `docs/identity-login-proposal-drafts.md` 作为 proposal 文本基线
