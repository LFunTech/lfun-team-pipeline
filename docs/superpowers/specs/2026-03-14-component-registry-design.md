# Component Registry — 组件注册表设计

## 概述

为多角色软件交付流水线新增**组件注册表**机制，解决同一项目内跨提案重复开发问题。通过登记已有的函数、方法、类、组件、中间件等可复用单元，让后续提案的 Architect 和 Builder 能发现并复用已有代码。

## 问题

当前流水线的 Memory Injection 只向 Architect 注入 API 端点和数据库表名。Builder 拿到的是 tasks.json 任务清单，不包含"项目中已有哪些可复用的函数/组件"。导致 P-002 的 Builder 无法发现 P-001 已实现的工具函数、中间件等，造成重复开发。

## 设计决策

- **独立文件**，不混入 project-memory.json（约束是规则，组件是资产，生命周期不同）
- **带摘要的注册表**（签名 + 一句话用途），Builder 无需读源码即可判断能否复用
- **分层存储**（索引 + 按提案分片），防止文件膨胀
- **编译器级提取**，非 ctags 正则匹配（签名准确、导出判断可靠）
- **本地小模型优先**生成摘要/标签，降级到 Claude Haiku，再降级到路径推断

## ID 生成策略

组件 ID 格式：`<shard>-<sequence>`，如 `LEGACY-001`、`P-001-001`、`P-002-015`。

- 每个分片内部从 `001` 开始自增（三位数，超出后自动扩展为四位）
- 跨分片天然不冲突（前缀不同）
- 索引文件中的 `id` 全局唯一
- 条目被清理删除后，序号不回收（避免历史引用混淆）

## 存储结构

```
.pipeline/artifacts/
├── component-registry.json          ← 索引文件（始终轻量）
└── component-registry/
    ├── LEGACY.json                   ← 存量代码初始化
    ├── P-001.json                    ← 按提案分片
    ├── P-002.json
    └── raw/                          ← 编译器原始输出（临时）
        ├── rust.json
        ├── typescript.json
        └── ...
```

### 索引文件 schema（component-registry.json）

```jsonc
{
  "version": 1,
  "last_updated": "ISO-8601",
  "stats": {
    "total_components": 156,
    "by_type": {
      "function": 89,
      "component": 34,
      "middleware": 12,
      "class": 21
    }
  },
  "index": [
    {
      "id": "P-001-001",
      "name": "validateEmail",
      "type": "function",             // function | method | class | component | middleware | hook | trait | interface | enum
      "path": "src/utils/validation.ts:25",
      "signature": "validateEmail(email: string): boolean",
      "tags": ["validation", "email"],
      "exported": true,
      "shard": "P-001"               // 指向分片文件名
    }
  ]
}
```

**索引条目约 ~120 字节/条，1000 个组件 ≈ 120KB，可控。**

### 分片文件 schema（component-registry/P-001.json）

```jsonc
{
  "proposal_id": "P-001",
  "pipeline_id": "pipe-20260314-001",
  "extracted_at": "ISO-8601",
  "components": [
    {
      "id": "P-001-001",
      "name": "validateEmail",
      "type": "function",
      "path": "src/utils/validation.ts:25",
      "signature": "validateEmail(email: string): boolean",
      "summary": "校验邮箱格式，支持国际化域名",
      "tags": ["validation", "email"],
      "dependencies": [],             // 外部依赖（包名）
      "exported": true,
      "usage_example": "if (validateEmail(input)) { ... }"
    }
  ]
}
```

### 存量初始化分片（component-registry/LEGACY.json）

与普通分片 schema 相同，`proposal_id` 固定为 `"LEGACY"`。

## 提取机制

### 编译器工具链（per-language）

| 语言 | 工具 | 命令 | 产出 |
|------|------|------|------|
| Rust | rustdoc JSON | `cargo +nightly rustdoc -- --output-format json`（需 nightly；stable 降级到 ctags） | 完整 API（签名、可见性、trait 实现） |
| TypeScript | tsc | `tsc --declaration --emitDeclarationOnly` | `.d.ts` 声明文件 |
| Java | javap | `javap -public -classpath <cp> <class>` | 公共类/方法签名 |
| Python | ast 标准库 | `python3 -c "import ast; ..."` | AST 级函数签名 + docstring |
| Go | go/ast 脚本 | 小型 Go 脚本使用 `go/packages` + `go/ast` 提取导出符号 | 导出符号 + 文档注释 |
| C/C++ | clang | `clang -Xclang -ast-dump=json` | 完整 AST（含类型、可见性） |

### 语言检测

通过项目标志文件自动识别：

| 标志文件 | 语言 |
|----------|------|
| `Cargo.toml` | Rust |
| `package.json` / `tsconfig.json` | TypeScript/JavaScript |
| `pom.xml` / `build.gradle` / `build.gradle.kts` | Java |
| `pyproject.toml` / `setup.py` / `requirements.txt` | Python |
| `go.mod` | Go |
| `CMakeLists.txt` / `Makefile` + `*.c`/`*.cpp` | C/C++ |

### 提取降级策略

```
编译器工具链可用？
  ├─ 是 → 编译器提取（精确）
  └─ 否 → ctags 可用？
            ├─ 是 → ctags 提取（够用）
            └─ 否 → 跳过，提示安装
```

## 摘要生成

### 降级链

```
Ollama 运行中且有 coder 模型？
  ├─ 是 → 本地模型生成 summary + tags（免费、快速）
  └─ 否 → Claude CLI 可用？
            ├─ 是 → Claude Haiku 批量生成（便宜）
            └─ 否 → summary 留空，tags 从文件路径推断
```

### 本地模型

- 推荐：`qwen2.5-coder:7b`（代码理解强、中英文好、M1/M2 流畅）
- 备选：`codellama:7b`、`deepseek-coder-v2:16b`
- 检测：`curl -s http://localhost:11434/api/tags`

### Claude Haiku 批量调用

- 每次请求打包 20-30 个符号（附签名 + 文件上下文片段）
- Prompt 模板：

```
给以下导出符号写一句话中文摘要和 2-3 个标签。
输出 JSON 数组，每个元素 {"id": "...", "summary": "...", "tags": [...]}

符号列表：
1. [P-001-001] pub fn validate_email(email: &str) -> Result<bool, ValidationError>
   文件：src/utils/validation.rs:25
   上下文：[±5 行代码]

2. [P-001-002] export class AuthMiddleware { handle(req, res, next) }
   文件：src/middleware/auth.ts:1
   上下文：[±5 行代码]
...
```

### 路径推断降级

当没有模型可用时，从文件路径提取 tags：
- `src/auth/middleware.ts` → `["auth", "middleware"]`
- `src/utils/date.rs` → `["utils", "date"]`
- summary 留空字符串

## 流水线集成

### 新增阶段/步骤

| 位置 | 名称 | 阶段编号 | 类型 | 触发条件 |
|------|------|----------|------|----------|
| Phase 3.0b（Build Verifier）之后，Phase 3.1（Static Analyzer）之前 | Component Extractor | phase-3.0c | AutoStep | `component_registry.enabled == true` |

**前置条件：** Phase 3.0b 编译验证通过后才执行，确保只登记能编译的代码。

**执行上下文：** 此时 Builder worktrees 已合并回主分支，extractor 在主工作树上运行。

**失败行为：** 非阻塞。FAIL 输出 WARN 并继续后续阶段（组件提取是增强功能，不应阻塞交付）。不触发回滚。

### AutoStep 逻辑（component-extractor.sh）

1. **清理失效条目** — 读取 `impl-manifest.json` 中本提案修改过的文件列表，检查注册表中这些文件对应的已有条目，移除签名已消失或文件已删除的条目（先清理再提取，避免重构后出现同一功能的新旧两个条目）
2. **提取新组件** — 对修改/新增的文件执行编译器级提取（按语言分派）
3. **生成摘要** — 调用摘要降级链（Ollama → Claude Haiku → 路径推断）
4. **写入分片** — 写入 `component-registry/<proposal-id>.json`
5. **更新索引** — 追加新条目、移除已清理条目、更新 stats
6. **输出结果** — PASS（提取失败时输出 WARN，附失败原因，不阻塞流水线）

`team scan --refresh` 执行全量清理（检查所有条目的路径有效性），而 phase-3.0c 只做增量清理（仅检查本提案涉及的文件）。

### 注入时机与内容

| 角色 | 注入时机 | 注入内容 |
|------|----------|----------|
| Architect（Phase 1） | Memory Load | 索引文件全量（name/type/signature/tags） |
| Builder（Phase 3） | 任务分配时 | 索引文件 + 按任务描述关键词匹配的相关分片详情 |

### Builder 过滤算法

Builder 注入时从 tasks.json 的 `description` 字段提取关键词，与组件 tags 进行匹配：

1. 对当前 Builder 分配到的所有 task，提取 `description` 中的名词/关键词
2. 与 component-registry.json 索引中的 `tags` + `name` 做交集匹配
3. 命中的组件加载对应分片的完整详情（summary、usage_example）
4. 无命中时注入索引全量（让 Builder 自行判断）

### 集成修改点

| 文件 | 修改内容 |
|------|----------|
| `playbook.md` Memory Load 段 | 扩展 `build_memory_injection`，读取 component-registry.json 并追加到注入文本 |
| `playbook.md` Phase 3 段 | Builder spawn 消息中追加过滤后的组件详情 |
| `pilot.md` 路由表 | 新增 `phase-3.0c` → `component-extractor.sh` 路由 |
| `config.json` | 新增 `component_registry` 配置块 |

### Architect 注入格式

```
=== Component Registry (156 components) ===
[function] validateEmail(email: string): boolean  #validation #email  → src/utils/validation.ts:25
[middleware] AuthMiddleware(req, res, next): void  #auth #middleware  → src/middleware/auth.ts:1
[class] DatabasePool { getConnection(), release() }  #database #pool  → src/db/pool.ts:1
...
=== End Registry ===
```

### Builder 注入格式

```
=== Reusable Components (filtered by: auth, user) ===
[middleware] AuthMiddleware(req, res, next): void
  摘要：JWT 认证中间件，从 header 提取 token 并验证，失败返回 401
  路径：src/middleware/auth.ts:1
  依赖：jsonwebtoken
  用法：app.use(AuthMiddleware)

[function] hashPassword(password: string): Promise<string>
  摘要：使用 bcrypt 哈希密码，salt rounds=12
  路径：src/utils/crypto.ts:10
  依赖：bcrypt
  用法：const hashed = await hashPassword(raw)
=== End Components ===
```

## 存量项目初始化

### 新增命令

```bash
team scan [--refresh]
```

### 执行流程

```
team scan
  │
  ├─ 1. 语言检测
  │     扫描项目根目录的标志文件
  │     输出：检测到的语言列表
  │
  ├─ 2. 编译器提取（per-language dispatcher）
  │     对每种检测到的语言调用对应编译器工具
  │     输出 → .pipeline/artifacts/component-registry/raw/<lang>.json
  │
  ├─ 3. 统一标准化
  │     各语言 raw 输出 → 统一 component schema
  │     过滤：排除 test/*、vendor/*、node_modules/*、target/*、build/*
  │     过滤：排除非导出/非公共符号
  │     输出 → 标准化符号清单
  │
  ├─ 4. 摘要生成（Ollama → Claude Haiku → 路径推断）
  │     批量处理：每批 20-30 个符号
  │     输出 → summary + tags
  │
  └─ 5. 写入注册表
        分片 → component-registry/LEGACY.json
        索引 → component-registry.json
        清理 → 删除 raw/ 临时目录
```

### --refresh 模式

```
team scan --refresh
  │
  ├─ 读取现有 component-registry.json
  ├─ 检查每个条目的 path 是否仍然存在
  ├─ 移除失效条目
  ├─ 扫描新增的导出符号（增量）
  └─ 更新索引和分片
```

## 失效清理

组件注册表中的条目可能因代码重构而失效（文件删除、函数重命名）。

### 清理策略

| 场景 | 触发方式 | 范围 |
|------|----------|------|
| 流水线内（phase-3.0c） | 自动，Component Extractor 第一步 | 增量 — 仅检查本提案 `impl-manifest.json` 涉及的文件 |
| 手动维护 | `team scan --refresh` | 全量 — 检查注册表中所有条目的路径有效性 |

### 清理逻辑

- 检查 `path` 指向的文件是否存在
- 如果文件存在但符号不在了（重命名/删除），标记移除
- 从索引和对应分片中同步删除
- 日志输出：`[ComponentRegistry] 清理 3 个失效条目：P-001-005, P-001-012, P-002-003`

## 配置扩展

在 `.pipeline/config.json` 中新增：

```jsonc
{
  "component_registry": {
    "enabled": true,                          // 是否启用组件注册表
    "summary_provider": "auto",               // "auto" | "ollama" | "claude" | "none"
    "ollama_model": "qwen2.5-coder:7b",       // Ollama 模型名
    "ollama_url": "http://localhost:11434",    // Ollama 地址
    "exclude_patterns": [                     // 额外排除路径
      "test/**",
      "bench/**",
      "examples/**"
    ],
    "min_complexity": 3                        // 最少 N 行的函数才登记（过滤 trivial getter/setter）
  }
}
```

## team scan 命令集成

`team scan` 作为新子命令添加到现有 `team` CLI（`~/.local/bin/team`）和 `install.sh` 中。

实现方式：在 team 脚本中新增 `cmd_scan()` 函数，调用 `.pipeline/autosteps/component-extractor.sh` 的全量扫描模式（传入 `--mode=full` 参数区别于流水线内的增量模式）。

```bash
team scan             # 全量扫描，初始化 LEGACY 分片
team scan --refresh   # 增量校验，清理失效 + 发现新增
```

## 规模控制

- **软上限**：组件数超过 2000 时，`team scan` 和 Component Extractor 输出警告，建议审查和清理
- **自然淘汰**：`--refresh` 模式自动移除路径已失效的条目
- **不做强制归档**：项目如果真有 2000+ 公共符号，那是项目本身的复杂度，不应人为隐藏

## 不做的事情

- **不做跨项目共享** — 每个项目独立的注册表，不建公共组件库
- **不做版本追踪** — 不记录组件的修改历史，git 已经做了
- **不做运行时依赖图** — 只记录直接外部依赖（包名），不做传递依赖分析
- **不做自动重构** — 只提供发现能力，复用决策由 Architect/Builder 做
