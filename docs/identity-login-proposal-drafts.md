# Identity Login Proposal Drafts

> 面向 `P-102 ~ P-108` 的重写草案。目标不是直接替换用户项目里的 `proposal-queue.json`，而是给 Pilot / Architect 一个可直接复用的 proposal 文本基线。

## P-102

### 标题

学校管理后台身份与登录配置 UI 收口

### 建议保留为单 proposal

### proposal_classification

- `ui-only`

### scope

在不改变后端 contract、保存规则、真实登录链路的前提下，统一学校管理后台“身份与登录配置”页面的术语、列表、编辑抽屉和预览表现。

包含：

- 列表列顺序与字段展示收口
- 四个 Tab 的信息架构固定
- 历史术语清理与统一替换
- 登录预览和注册预览的静态表现收口
- 继承态 / 生效态的只读展示语义收口

不包含：

- 后端业务规则变化
- 保存接口结构变化
- migration / schema 变化
- 真实登录页行为变化

### source_of_truth

- 后端统一聚合接口是唯一数据来源
- 预览仅消费后端已存在的生效态数据，不反向定义真实登录链路

### hidden_coupling

- 继承态展示容易误改为新的业务语义
- 术语收口容易顺手改接口字段名
- 预览稿容易倒逼真实登录流程改造

### contract_matrix

- 只读依赖现有列表 / 详情接口
- 本 proposal 不新增、不修改任何 backend contract

### state_rule_matrix

- 未配置登录方式 -> 预览显示“请选择登录方式”
- 继承态 -> 展示真实生效值，不展示“继承租户配置”等伪选项
- “用户名密码或手机验证码登录” -> 预览使用 tab，且一次只展示一个表单

### forbidden_changes

- 不修改 backend controller / service / migration
- 不修改保存入参 / 出参
- 不调整真实 Keycloak 登录页逻辑

### pre_gate_test_bundle

- UI snapshot suite
- 术语黑名单扫描
- 预览状态矩阵测试

### split_recommendation

- 不拆；前提是严格保持 UI-only

---

## P-103A

### 标题

登录安全与注册/身份核验后端规则闭环

### proposal_classification

- `validation-rules`

### scope

建立学校后台身份与登录配置的后端统一校验规则，并在保存配置与运行时提交路径中强制执行。

包含：

- 登录方式与必填字段依赖规则
- 用户名来源 / 账号策略成立条件
- 注册审批与自助注册的依赖规则
- 身份核验审批与审批角色的依赖规则
- 关闭在线身份核验申请后的提交拒绝逻辑
- `required_fields` 单一真相源落地
- 校验错误契约与错误码

不包含：

- 前端即时联动和风险提示 UI
- 真实审批流落地
- Keycloak 登录链变化

### source_of_truth

- `required_fields` 只允许一个后端真相源
- 保存可行性与运行时提交可行性都以后端规则为准

### hidden_coupling

- 保存规则与运行时提交规则边界
- 用户名生成 / 映射能力与登录方式联动
- 审批依赖规则与后续审批流 proposal 的边界

### contract_matrix

- 保存接口: `200/400/409`
- 提交接口: `200/400/403/409`
- 每类非法组合必须有明确错误码，不允许只返回通用 bad request

### state_rule_matrix

- 含“手机验证码”的登录方式 -> 手机号必填
- 含“用户名密码”的登录方式 -> 用户名来源必须成立
- 开启“注册提交后需要审批” -> 必须允许自助注册
- 开启“身份核验申请需要审批” -> 必须配置 approval_role
- 关闭“开放在线身份核验申请” -> 提交 API 必须拒绝

### forbidden_changes

- 不落地前端联动 UI
- 不落地真实审批流
- 不修改 Keycloak authenticator

### pre_gate_test_bundle

- rule matrix contract suite
- required_fields single-source suite
- uniqueness boundary suite

### split_recommendation

- 已从原 `P-103` 拆出，前端联动另立 `P-103B`

---

## P-103B

### 标题

学校后台身份与登录配置前端联动与风险提示

### proposal_classification

- `ui-only`

### scope

在不新增后端业务规则的前提下，将 `P-103A` 已定义的规则以前端即时联动、提示、禁用态和说明文案的方式呈现给管理员。

包含：

- 配置联动
- 字段禁用与锁定
- 风险提示
- 保存前前置提示

不包含：

- 后端规则新增
- 错误码调整
- 审批流真实落地

### source_of_truth

- 所有联动逻辑以 `P-103A` 的规则为准

### forbidden_changes

- 不新增后端保存规则
- 不修改后端错误体

### pre_gate_test_bundle

- front-end rule hint suite
- disabled-state interaction suite

---

## P-104A

### 标题

注册审批流程落地

### proposal_classification

- `workflow-state-machine`

### scope

落地自助注册申请、审批、建号的完整状态机和接口。

包含：

- 注册申请实体与接口
- `pending/approved/rejected` 状态流转
- 审批动作审计
- 审批通过后建号副作用

不包含：

- 身份核验审批流
- Keycloak 同步
- token claim 变更

### source_of_truth

- 注册申请单状态为唯一真相源

### contract_matrix

- 创建申请: `200/400/409`
- 审批动作: `200/400/403/409`
- 查询详情 / 列表: `200/404`

### state_rule_matrix

- `pending -> approved`
- `pending -> rejected`
- 已审批申请不可再次审批
- 拒绝后是否允许重新提交必须明确

### forbidden_changes

- 不处理身份核验申请
- 不做 Keycloak 同步和补偿任务

### pre_gate_test_bundle

- registration workflow transition suite
- approval authority suite
- idempotency suite

---

## P-104B

### 标题

身份核验审批流程落地

### proposal_classification

- `workflow-state-machine`

### scope

落地身份核验申请、审批、身份结果更新的完整状态机和接口。

包含：

- 身份核验申请实体与接口
- 审批状态流转
- 审批通过后的身份结果更新
- 审批拒绝理由留痕

不包含：

- 注册审批流
- Keycloak 同步
- token claim 变更

### source_of_truth

- 身份核验申请单状态与最终身份结果为真相源

### contract_matrix

- 创建申请: `200/400/403/409`
- 审批动作: `200/400/403/409`

### state_rule_matrix

- 未开放在线身份核验申请 -> 不允许创建申请
- `pending -> approved`
- `pending -> rejected`

### forbidden_changes

- 不处理注册申请状态机
- 不做 Keycloak 同步

### pre_gate_test_bundle

- verification workflow transition suite
- approval routing suite
- result side-effect suite

---

## P-105A

### 标题

身份结果到 Keycloak 的同步主链路

### proposal_classification

- `external-integration`

### scope

将注册结果和身份核验结果按既定规则同步到 Keycloak，先打通主链路，不在本 proposal 内引入补偿任务体系。

包含：

- 同步触发点
- 同步内容映射
- 本地成功 / 外部失败的语义定义
- 与现有 token claim 数据源的兼容性校验

不包含：

- 批量补偿
- 手工补偿 UI
- identity-token-mapper 本体调整

### source_of_truth

- 本地身份数据是真相源
- Keycloak 只接收派生同步结果

### contract_matrix

- 本地结果成功但外部失败时的状态定义
- 同步结果字段与日志字段

### state_rule_matrix

- 无审批直达成功 -> 立即同步
- 审批通过 -> 立即同步
- 审批拒绝 -> 不同步

### forbidden_changes

- 不改 identity-token-mapper 本体
- 不新增新的 claim 结构标准

### pre_gate_test_bundle

- sync trigger suite
- local-vs-keycloak consistency suite
- mapper compatibility verification suite

---

## P-105B

### 标题

身份结果同步补偿机制与任务治理

### proposal_classification

- `external-integration`
- `observability-ops`

### scope

为 `P-105A` 的同步失败场景提供任务状态机、失败重试、手工补偿和批量补偿能力。

包含：

- 同步任务实体
- 单个 / 批量补偿
- 失败重试
- 幂等
- 状态记录和观测

不包含：

- 主同步链路字段设计
- token claim 结构调整

### source_of_truth

- 同步任务状态机为补偿系统真相源

### contract_matrix

- 手工补偿接口
- 批量补偿接口
- 查询任务状态接口

### state_rule_matrix

- `pending -> running -> succeeded`
- `pending/running -> failed`
- `failed -> retried -> running`
- 达到重试上限 -> dead-letter

### forbidden_changes

- 不重写主同步链路
- 不改 Keycloak 数据映射规则

### pre_gate_test_bundle

- retry / compensation suite
- task state machine suite
- idempotency suite

---

## P-106

### 标题

运营后台四身份默认登录配置与继承机制

### 建议保留为单 proposal

### proposal_classification

- `domain-model`
- `observability-ops`

### scope

允许运营后台按四身份分别维护默认登录方式，并与学校侧继承 / 脱继承形成闭环。

包含：

- 四身份默认配置维护
- 学校继承 / 脱继承判定
- 仅对继承态学校身份做异步 fan-out
- 非覆盖保证与审计

不包含：

- 学校侧 UI 收口
- 真实登录页改造
- Keycloak 流程变更

### source_of_truth

- 平台每身份默认配置为默认值真相源
- 学校侧是否仍继承由学校身份记录状态决定

### contract_matrix

- 平台默认配置查询 / 保存接口
- 影响范围说明接口（若有）

### state_rule_matrix

- 学校未显式保存 -> 继承平台默认
- 学校显式保存 -> 立即脱继承
- fan-out 仅作用于继承态
- 已脱继承身份永不被覆盖

### forbidden_changes

- 不扩展到真实登录页行为
- 不顺手调整学校后台预览逻辑

### pre_gate_test_bundle

- inheritance state suite
- fan-out non-overwrite suite
- per-identity default mapping suite

---

## P-107A

### 标题

Keycloak 多身份入口与路由优先级

### proposal_classification

- `external-integration`
- `validation-rules`

### scope

定义未知身份先选身份、已知身份直达、第三方指定身份锁定等入口与路由优先级，不在本 proposal 内落地全部登录方式执行链。

### source_of_truth

- identity_type 路由优先级以后端登录入口规则为准

### state_rule_matrix

- `identity_type` 参数优先
- 无参数时走默认解析逻辑
- 第三方指定身份时锁定，不允许切换

### forbidden_changes

- 不落地六种登录方式的完整执行链
- 不改 captcha / MFA 实现

### pre_gate_test_bundle

- identity routing matrix suite
- locked identity suite

---

## P-107B

### 标题

Keycloak 六种登录方式真实执行链

### proposal_classification

- `external-integration`

### scope

在既有路由规则基础上，真实落地六种登录方式的执行链和输入顺序。

### source_of_truth

- 登录方式编排以后端登录策略真相源为准

### state_rule_matrix

- 六种登录方式逐一列清执行步骤
- 明确 OR / AND 语义
- 手机号 / 用户名唯一性边界

### forbidden_changes

- 不改 identity_type 路由规则
- 不改品牌展示逻辑

### pre_gate_test_bundle

- six-mode execution suite
- login-step ordering suite

---

## P-107C

### 标题

Keycloak 图形验证码与 MFA / TOTP 兼容增强

### proposal_classification

- `external-integration`
- `observability-ops`

### scope

为真实登录链补齐图形验证码、TOTP 引导与现有 authenticator 兼容能力，不在本 proposal 内重写现有扩展。

### source_of_truth

- 现有 Keycloak 扩展链路为兼容基础

### state_rule_matrix

- captcha 生效矩阵
- TOTP 登录方式绑定 / 引导矩阵
- 现有 MFA 兼容路径保留规则

### forbidden_changes

- 不允许推翻重写现有 authenticator
- 不允许无边界修改 `EduPlusPhoneLoginAuthenticator`、`TenantAwareFormAuthenticator`、`LoginPolicyAuthenticator`

### pre_gate_test_bundle

- captcha suite
- MFA compatibility suite
- authenticator regression suite

---

## P-108

### 标题

学校品牌接入 Keycloak 登录页

### 建议保留为单 proposal

### proposal_classification

- `ui-only`
- `external-integration`

### scope

在不改变登录流程判定的前提下，为真实 Keycloak 登录页接入学校品牌展示与默认品牌回退。

包含：

- 学校 logo / 名称 / 页脚文案展示
- 学校品牌缺失时回退平台默认品牌
- 身份切换 / 已知身份直达场景下品牌一致性

不包含：

- 登录链路判断变化
- 验证码 / MFA 行为变化
- 学校后台预览变重

### source_of_truth

- 学校品牌配置为真相源
- 无品牌配置时回退平台默认品牌

### state_rule_matrix

- 学校品牌命中 -> 展示学校品牌
- 学校品牌缺失 -> 回退平台默认
- 品牌加载失败 -> 不阻断登录主流程，回退默认品牌

### forbidden_changes

- 不改变 identity_type 路由
- 不改变真实登录主流程
- 不改变验证码 / MFA 行为

### pre_gate_test_bundle

- brand fallback suite
- identity switch branding suite
- known-identity direct-entry branding suite
