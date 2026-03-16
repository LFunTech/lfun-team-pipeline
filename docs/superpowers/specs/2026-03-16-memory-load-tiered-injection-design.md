# Memory Load 分层注入设计

> Issue: #3
> 日期: 2026-03-16
> 状态: Draft

## 问题

当前 Memory Load 将 `project-memory.json` 全部约束一次性注入 Clarifier 和 Architect。随着项目迭代约束增长（如 109 条），大量无关领域约束导致信噪比恶化。

## 方案概述

- **实现路径**：纯 AutoStep 脚本（确定性过滤逻辑，不依赖 LLM 解释执行）
- **匹配策略**：proposal.domains 显式声明 + scope 文本匹配取并集
- **向后兼容**：无 tier/domain 字段的约束默认 tier=1 全量注入

## §1 数据层 — project-memory.json 约束扩展

每个约束对象新增两个可选字段：

```json
{
  "id": "C-067",
  "text": "数据库操作台 SQL 执行必须设置 30 秒超时限制...",
  "tags": ["业务规则", "数据库操作台", "安全"],
  "source": "pipe-20260310-010",
  "tier": 2,
  "domain": "数据库操作台"
}
```

| 字段 | 说明 |
|------|------|
| `tier: 1` | 全局约束，每次必注入（技术栈、规范、架构模式） |
| `tier: 2` | 领域约束，按 domain 匹配后注入 |
| 缺少 `tier` | 默认 `tier: 1`（向后兼容） |
| `domain` 为空/缺失 | 归入全局 |

模板 `templates/.pipeline/project-memory.json` 保持 `constraints: []` 不变，字段在运行时按需出现。

## §2 proposal-queue.json 扩展 + 领域匹配策略

### proposal 新增 `domains` 字段

```json
{
  "id": "P-017",
  "title": "配置推进与导出",
  "scope": "...",
  "domains": ["配置管理", "审批流"]
}
```

- `domains` 为可选数组，System Planning 阶段由 LLM 填写
- 缺失或空数组 → fallback 到 scope 文本匹配

### 匹配策略

1. 读取 `proposal.domains`（如有）
2. 用 `DOMAIN_KEYWORDS` 映射表对 `scope` 做文本匹配
3. **取并集**（domains + scope 匹配合并）

## §3 AutoStep `memory-load.sh` 核心逻辑

新建 `.pipeline/autosteps/memory-load.sh`，内嵌 Python 脚本。

### Shell 包装

```bash
#!/bin/bash
# Phase: memory-load
# 输入: PIPELINE_DIR, project-memory.json, proposal-queue.json
# 输出: .pipeline/artifacts/memory-injection.txt
set -euo pipefail
PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"

if [ ! -f "$PIPELINE_DIR/project-memory.json" ]; then
  echo "SKIP"
  exit 0
fi

python3 - "$PIPELINE_DIR" << 'PYTHON_SCRIPT'
# ... Python 核心流程见下方 ...
PYTHON_SCRIPT
```

### 输入/输出

| 输入 | 文件 |
|------|------|
| 约束库 | `$PIPELINE_DIR/project-memory.json` |
| 提案队列 | `$PIPELINE_DIR/proposal-queue.json` |

**输出**：`$PIPELINE_DIR/artifacts/memory-injection.txt`

### Python 核心流程

```python
import json, sys, os

PIPELINE_DIR = sys.argv[1]  # 从 shell 传入

# 文件不存在检查（shell 层已处理 project-memory.json，这里处理 proposal-queue.json）
if not os.path.exists(f"{PIPELINE_DIR}/proposal-queue.json"):
    print("SKIP")
    sys.exit(0)

memory = json.load(open(f"{PIPELINE_DIR}/project-memory.json"))
queue = json.load(open(f"{PIPELINE_DIR}/proposal-queue.json"))

# 1. 找到 status=running 的提案
current = next((p for p in queue["proposals"] if p["status"] == "running"), None)
if not current:
    print("SKIP")
    sys.exit(0)

scope = current.get("scope", "").lower()
explicit_domains = set(current.get("domains", []))

# 2. DOMAIN_KEYWORDS 映射表
DOMAIN_KEYWORDS = {
    "配置管理": ["配置", "config", "config_nodes", "config_snapshot"],
    "审批流": ["审批", "approval"],
    "数据库操作台": ["数据库操作台", "db-console", "sql编辑"],
    "Redis操作台": ["redis操作台", "redis-console"],
    "通知/Webhook": ["通知", "webhook", "notification", "smtp"],
    "密钥管理": ["密钥", "轮换", "credential_key"],
    "API Token": ["api token", "token管理"],
    "资源管理": ["资源实例", "资源开设", "resource", "provisioner"],
    "用户/团队/环境": ["用户", "团队", "环境管理", "environment"],
    "项目管理": ["项目管理", "project"],
}

# 3. scope 文本匹配
matched_domains = set()
for domain, keywords in DOMAIN_KEYWORDS.items():
    if any(kw in scope for kw in keywords):
        matched_domains.add(domain)

# 4. 自动 fallback：从 memory 中提取所有 domain 值，对 scope 做精确子串匹配
all_domains = {c["domain"] for c in memory.get("constraints", []) if c.get("domain")}
for domain in all_domains:
    if domain.lower() in scope:
        matched_domains.add(domain)

# 5. 取并集，统一小写用于匹配
relevant_domains = explicit_domains | matched_domains
relevant_domains_lower = {d.lower() for d in relevant_domains}

# 6. 过滤约束（大小写无关比较）
injected = []
skipped = 0
for c in memory.get("constraints", []):
    tier = c.get("tier", 1)
    if tier == 1 or not c.get("domain"):
        injected.append(c)
    elif c.get("domain", "").lower() in relevant_domains_lower:
        injected.append(c)
    else:
        skipped += 1

# 7. 组装输出（格式与现有一致）
lines = [f"项目定位：{memory.get('project_purpose', '未定义')}"]

runs = memory.get("runs", [])
if runs:
    features = "、".join(r["feature"] for r in runs[-10:])
    lines.append(f"已完成 {len(runs)} 次交付：{features}")

for r in [r for r in runs if r.get("footprint")][-5:]:
    fp = r["footprint"]
    lines.append(f"  [{r['pipeline_id']}] {r['feature']}")
    if fp.get("api_endpoints"):
        lines.append(f"    API: {', '.join(fp['api_endpoints'][:5])}")
    if fp.get("db_tables"):
        lines.append(f"    DB: {', '.join(fp['db_tables'])}")

for c in injected:
    tags = ", ".join(c.get("tags", []))
    lines.append(f"  [{c['id']}]({tags}) {c['text']}")

for s in memory.get("superseded", [])[-5:]:
    lines.append(f"  [{s['id']}] {s['text']} → 被 {s['superseded_by']} 推翻：{s['reason']}")

# 注入统计
total = len(memory.get("constraints", []))
lines.append(f"[Memory Filter] 总约束 {total} 条，注入 {len(injected)} 条，跳过 {skipped} 条")
if relevant_domains:
    lines.append(f"[Memory Filter] 匹配领域：{', '.join(sorted(relevant_domains))}")

# 8. 写入
content = "=== Project Memory ===\n" + "\n".join(lines) + "\n=== End Memory ==="

# 若只有"项目定位：未定义"且无其他内容
if len(lines) <= 1 and "未定义" in lines[0]:
    print("SKIP")
    sys.exit(0)

with open(f"{PIPELINE_DIR}/artifacts/memory-injection.txt", "w") as f:
    f.write(content)

print(f"PASS — 注入 {len(injected)}/{total} 条约束，跳过 {skipped} 条")
```

### 退出状态

| 条件 | 输出 | 退出码 |
|------|------|--------|
| 无 project-memory.json | `SKIP` | 0 |
| 无 running 提案 | `SKIP` | 0 |
| 仅"项目定位：未定义"无其他内容 | `SKIP` | 0 |
| 正常注入 | `PASS — 注入 X/Y 条约束，跳过 Z 条` | 0 |

## §4 playbook + orchestrator 改动

### playbook.md Memory Load 章节

替换现有 `build_memory_injection` 伪代码（第 103-133 行）为：

```markdown
## Memory Load — 项目记忆加载

run: PIPELINE_DIR=.pipeline bash .pipeline/autosteps/memory-load.sh

输出: .pipeline/artifacts/memory-injection.txt

- SKIP → 跳过注入，直接进入 Phase 0
- PASS → Orchestrator 读取 memory-injection.txt 全文，
         作为 Phase 0（Clarifier）和 Phase 1（Architect）spawn 消息的最前方内容
```

### orchestrator.md

Orchestrator 通过加载 playbook 章节来执行 Memory Load。`build_memory_injection` 伪代码在 playbook.md 中而非 orchestrator.md 中，因此 **orchestrator.md 本身无需改动**。playbook 替换后，Orchestrator 自然切换到 autostep 模式。

### Clarifier / Architect 无改动

注入格式不变（`=== Project Memory === ... === End Memory ===`），只是内容经过过滤。

## §5 Memory Consolidation 改动

Phase 7 后写入新约束时，Orchestrator 自动标注 `tier` 和 `domain`：

| 字段 | 规则 |
|------|------|
| `tier` | 全局规范/技术栈/架构模式 → 1；特定功能域规则 → 2 |
| `domain` | tier=1 时留空；tier=2 时必填，使用标准领域名 |

新领域处理：使用简短中文名（如"Kafka操作台"），memory-load.sh 的自动 fallback 机制（从 memory 提取所有 domain 值做精确子串匹配）确保新领域无需改脚本即可生效。

### playbook Memory Consolidation Step 4 具体替换

原文（playbook.md 第 729 行）：
```
3. 每条约束：`{id, text, tags, source: <pipeline_id>}`
```

替换为：
```
3. 每条约束：`{id, text, tags, source: <pipeline_id>, tier, domain}`
   - tier 分类规则：
     - tier=1（全局）：技术栈选型、API 规范、命名约定、安全基线、架构模式
     - tier=2（领域）：特定功能域的业务规则、数据约束、交互约束
   - domain：tier=2 时必填，从当前提案的 scope/domains 推断，使用简短中文名
   - 分类示例：
     - "所有 API 统一返回 {code, message, data} 格式" → tier=1, domain=空
     - "密码策略必须包含大小写+数字+特殊字符" → tier=1, domain=空
     - "POST /api/config-nodes 必须校验环境权限" → tier=2, domain="配置管理"
     - "数据库操作台 SQL 执行必须设置 30 秒超时" → tier=2, domain="数据库操作台"
     - "Webhook 重试策略为指数退避，最多 5 次" → tier=2, domain="通知/Webhook"
```

## §6 System Planning 改动

playbook System Planning 章节的提案输出格式中增加 `domains` 字段说明：

```
domains: 该提案涉及的业务领域列表（可选但推荐）。
         从已有 project-memory.json 的约束 domain 值中选取，
         或新建简短中文领域名。
```

软性引导，不填不影响流程（fallback 到 scope 匹配）。模板 `proposal-queue.json` 不改。

## §7 向后兼容

| 场景 | 处理方式 |
|------|---------|
| 旧 project-memory.json 无 tier/domain | 全部约束默认 tier=1，全量注入（行为不变） |
| 旧 proposal-queue.json 无 domains | fallback 到 scope 文本匹配 |
| memory-load.sh 不存在（未升级 autosteps） | Orchestrator 沿用旧 playbook 逻辑 |

**零破坏性**：未标注 tier/domain 的项目升级后行为完全不变，逐步标注后才开始过滤。

## 预期效果

| 场景 | 当前注入 | 优化后注入 | 节省 |
|------|---------|-----------|------|
| 配置管理提案 | 109 条 | ~50 条 | 54% |
| 通知系统提案 | 109 条 | ~35 条 | 68% |
| 新领域提案 | 109 条 | ~25 条 | 77% |

## 不纳入本次范围

1. `team audit-constraints` 命令 — 独立功能，另开 issue
2. 约束总数上限区分 tier — 可后续优化
