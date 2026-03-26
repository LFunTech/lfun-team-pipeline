# Proposal Hardening Guide

> 适用于 Pilot 在 `system-planning`、`replan`、自治模式 detail 生成、以及 Gate A 之前的 proposal 质量加固。

## 目标

避免产出“目标没错，但耦合过宽、边界过虚、验收不硬”的 proposal，减少类似 `P-101` 这类在 Gate C 反复因契约、兼容、迁移、外部系统边界而返工的情况。

## 一、先分类，再决定是否拆分

每个 proposal 至少标注一个 `proposal_classification`：

- `ui-only`
- `domain-model`
- `validation-rules`
- `workflow-state-machine`
- `migration-compatibility`
- `external-integration`
- `observability-ops`

若一个 proposal 同时命中以下任意 2 项，默认必须拆分，或明确给出不拆理由：

- API / error contract 变化
- 数据库 schema / migration / legacy 兼容
- 权限语义 / 安全边界 / `/ready` / `/health`
- 异步 fan-out / 补偿 / 重试 / 任务状态机
- 外部系统集成
- 前端 UI 与后端规则同时落地

## 二、必须补齐的 detail 字段

命中中高风险的 proposal，detail 至少要有：

- `proposal_classification`
- `hidden_coupling`
- `source_of_truth`
- `contract_matrix`
- `state_rule_matrix`
- `migration_compatibility`（如适用）
- `forbidden_changes`
- `pre_gate_test_bundle`
- `split_recommendation`

这些字段的要求不是“写上就行”，而是必须具体到路径、字段、状态码、历史来源或失败语义。

## 三、禁止空泛表述

以下表述单独出现时一律视为不合格，必须展开：

- “统一错误体”
- “保留兼容”
- “补 migration”
- “优化体验”
- “保持现有逻辑”
- “按已有规则执行”

必须回答：

- 哪些接口 / 路径
- 哪些状态码 / 错误码
- 哪些字段 / schema
- 哪些旧列 / 历史版本
- 哪些失败语义 / fallback
- 哪些模块禁止顺手改

## 四、拆分规则

### 1. UI 收口 + 后端规则

默认拆分：

- `UI-only proposal`
- `backend rules / validation proposal`

除非前端只是消费已稳定的后端契约，不引入任何新规则。

### 2. 统一模型 + migration / legacy 兼容

默认拆分：

- `domain-model proposal`
- `migration-compatibility proposal`

除非迁移只是机械字段搬运，且无历史脏数据、无在线写竞争、无旧值兼容语义。

### 3. 外部系统集成 + 本地业务规则

默认拆分：

- `local source-of-truth / business state proposal`
- `external sync / compensation proposal`

### 4. 工作流 + 补偿/重试

默认拆分：

- `workflow-state-machine proposal`
- `async jobs / retry / compensation proposal`

### 5. `/ready` / 安全边界 / 统一错误体

不得作为“顺手实现”混入普通业务 proposal；必须明确写入：

- `contract_matrix`
- `pre_gate_test_bundle`
- `forbidden_changes`

## 五、四张矩阵怎么写

### 1. Contract Matrix

至少写清：

- 路径
- 方法
- 关键状态码
- 关键错误码
- 关键响应字段
- 特殊路径前缀（如 `/api`）

示例：

```text
GET /api/v1/foo/{id}
- 200: FooResponse
- 400: FOO_BAD_REQUEST, details.id 为合法枚举或 null
- 404: FOO_NOT_FOUND
```

### 2. State / Rule Matrix

适用于审批流、联动校验、保存规则、配置不变量。

至少写清：

- 输入条件
- 系统判断
- 允许行为
- 拒绝行为
- 返回语义

### 3. Migration / Compatibility Matrix

适用于 schema / legacy proposal。

至少写清：

- 旧字段 / 旧列真实来源
- 历史上是否真实存在
- 缺列时回退策略
- 新结构映射目标
- 双写 / 兼容读 / 回填一致性要求

### 4. Forbidden Changes / Non-goals

至少写清：

- 不允许顺手改哪些接口
- 不允许顺手改哪些页面
- 不允许顺手改哪些协议 / mapper / authenticator
- 哪些问题即使发现也必须另起 proposal

## 六、Pre-Gate Test Bundle 规则

Gate A 前 proposal 必须写出最小预检包，至少覆盖 proposal 的最高风险边界。

常见组合：

- `contract suite`
- `migration snapshot suite`
- `security contract suite`
- `ready / health suite`
- `external integration contract suite`
- `workflow transition suite`

原则：

- 不是“有测试即可”
- 而是“Gate C 最容易打回的点，必须在 proposal 阶段先指定怎么测”

## 七、Pilot 自检清单

在 proposal 入队前，Pilot 至少自检：

1. 这个 proposal 是否同时改了 UI、后端规则、迁移、外部系统中的两类以上？
2. 是否已经写清 source of truth？
3. 是否已经写清哪些模块禁止顺手修改？
4. 是否已经写清错误契约，而不是只写“统一错误体”？
5. 是否已经写清真实历史 schema / legacy 来源，而不是默认旧列存在？
6. 是否已经指定 pre-gate test bundle？
7. 若不拆 proposal，是否已经写清为什么能安全不拆？

任意 2 项答不上来，就不应让 proposal 直接进入普通设计/实施流程。

## 八、P-102 ~ P-108 这类提案的直接建议

- `P-102`：UI-only，禁止顺手改 backend 契约
- `P-103`：拆成后端规则和前端联动
- `P-104`：拆成注册审批流和身份核验审批流
- `P-105`：拆成本地同步主链路和补偿机制
- `P-106`：保留，但必须补 fan-out / non-overwrite matrix
- `P-107`：必须拆成入口路由、登录方式执行链、验证码/MFA 兼容
- `P-108`：展示层为主，禁止登录流判定变化

## 九、推荐写法

一句话原则：

> 先把 proposal 写成“可验证的边界说明书”，再把它当实现任务。

## 十、参考重写

- 身份与登录配置链路的重写样例见 `docs/identity-login-proposal-rewrite-guide.md`
