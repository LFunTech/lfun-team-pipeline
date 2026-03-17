# Memory Load 分层注入 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Memory Load 从全量注入改为按 tier/domain 分层过滤注入，降低信噪比

**Architecture:** 新建 AutoStep 脚本 `memory-load.sh` 实现确定性过滤逻辑，替换 playbook 中的 LLM 伪代码。约束对象增加 `tier`/`domain` 字段，proposal 增加 `domains` 字段，匹配策略为 domains + scope 文本取并集。

**Tech Stack:** Bash + 内嵌 Python3, JSON

**Spec:** `docs/superpowers/specs/2026-03-16-memory-load-tiered-injection-design.md`

---

## 文件结构

| 操作 | 文件 | 职责 |
|------|------|------|
| Create | `templates/.pipeline/autosteps/memory-load.sh` | 分层过滤 AutoStep 脚本 |
| Create | `tests/memory-load/test_memory_load.sh` | 集成测试 |
| Create | `tests/memory-load/fixtures/` | 测试用 JSON fixtures |
| Modify | `templates/.pipeline/playbook.md:103-133` | Memory Load 章节替换 |
| Modify | `templates/.pipeline/playbook.md:729` | Memory Consolidation Step 4 格式扩展 |
| Modify | `templates/.pipeline/playbook.md:20-22` | System Planning 提案格式增加 domains |
| Modify | `templates/CLAUDE.md` | 更新 autosteps 计数 |

---

## Chunk 1: AutoStep 脚本实现

### Task 1: 创建测试 fixtures

**Files:**
- Create: `tests/memory-load/fixtures/project-memory.json`
- Create: `tests/memory-load/fixtures/proposal-queue.json`

- [ ] **Step 1: 创建测试用 project-memory.json**

```bash
mkdir -p tests/memory-load/fixtures
```

写入 `tests/memory-load/fixtures/project-memory.json`：

```json
{
  "version": 1,
  "project_purpose": "运维管理平台",
  "constraints": [
    {"id": "C-001", "text": "所有 API 统一返回 {code, message, data} 格式", "tags": ["API规范"], "source": "pipe-001", "tier": 1},
    {"id": "C-002", "text": "密码策略必须包含大小写+数字+特殊字符", "tags": ["安全基线"], "source": "pipe-001", "tier": 1},
    {"id": "C-003", "text": "配置节点变更必须记录审计日志", "tags": ["配置管理", "审计"], "source": "pipe-002", "tier": 2, "domain": "配置管理"},
    {"id": "C-004", "text": "配置快照对比使用 JSON diff", "tags": ["配置管理"], "source": "pipe-002", "tier": 2, "domain": "配置管理"},
    {"id": "C-005", "text": "SQL 执行必须设置 30 秒超时", "tags": ["数据库操作台", "安全"], "source": "pipe-003", "tier": 2, "domain": "数据库操作台"},
    {"id": "C-006", "text": "Webhook 重试策略为指数退避最多 5 次", "tags": ["通知/Webhook"], "source": "pipe-004", "tier": 2, "domain": "通知/Webhook"},
    {"id": "C-007", "text": "Redis 键前缀必须包含环境标识", "tags": ["Redis操作台"], "source": "pipe-005", "tier": 2, "domain": "Redis操作台"},
    {"id": "C-008", "text": "无 tier 字段的旧约束", "tags": ["旧格式"], "source": "pipe-001"}
  ],
  "superseded": [
    {"id": "C-099", "text": "旧密码策略", "superseded_by": "C-002", "reason": "安全要求升级"}
  ],
  "runs": [
    {"pipeline_id": "pipe-001", "date": "2026-01-01", "feature": "基础框架"},
    {"pipeline_id": "pipe-002", "date": "2026-01-15", "feature": "配置管理", "footprint": {"api_endpoints": ["/api/config-nodes", "/api/config-snapshots"], "db_tables": ["config_nodes", "config_snapshots"]}}
  ]
}
```

- [ ] **Step 2: 创建测试用 proposal-queue.json**

写入 `tests/memory-load/fixtures/proposal-queue.json`：

```json
{
  "version": 1,
  "system_name": "ops-platform",
  "proposals": [
    {"id": "P-001", "title": "基础框架", "scope": "基础框架搭建", "status": "completed"},
    {"id": "P-002", "title": "配置管理", "scope": "配置节点 CRUD、配置快照对比、配置推进", "domains": ["配置管理", "审批流"], "status": "running"},
    {"id": "P-003", "title": "通知系统", "scope": "Webhook 管理和通知推送", "status": "pending"}
  ]
}
```

- [ ] **Step 3: Commit fixtures**

```bash
git add tests/memory-load/
git commit -m "test: add memory-load test fixtures"
```

---

### Task 2: 创建 memory-load.sh AutoStep 脚本

**Files:**
- Create: `templates/.pipeline/autosteps/memory-load.sh`

- [ ] **Step 1: 创建脚本文件**

写入 `templates/.pipeline/autosteps/memory-load.sh`：

```bash
#!/usr/bin/env bash
# memory-load.sh — Memory Load 分层过滤 AutoStep
# 在 Phase 0 之前运行，按 tier/domain 过滤约束后生成注入块
# 输入: project-memory.json, proposal-queue.json
# 输出: .pipeline/artifacts/memory-injection.txt
# exit 0 + stdout PASS/SKIP/WARN

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
OUTPUT="$PIPELINE_DIR/artifacts/memory-injection.txt"

mkdir -p "$(dirname "$OUTPUT")"

# project-memory.json 不存在 → SKIP
if [ ! -f "$PIPELINE_DIR/project-memory.json" ]; then
  echo "SKIP"
  exit 0
fi

python3 - "$PIPELINE_DIR" "$OUTPUT" << 'PYEOF'
import json, sys, os

PIPELINE_DIR = sys.argv[1]
OUTPUT = sys.argv[2]

# proposal-queue.json 不存在 → SKIP
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

# 7. 组装输出
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

# 若只有"项目定位：未定义"且无其他内容
if len(lines) <= 1 and "未定义" in lines[0]:
    print("SKIP")
    sys.exit(0)

# 8. 写入
content = "=== Project Memory ===\n" + "\n".join(lines) + "\n=== End Memory ==="
with open(OUTPUT, "w") as f:
    f.write(content)

print(f"PASS — 注入 {len(injected)}/{total} 条约束，跳过 {skipped} 条")
PYEOF
```

- [ ] **Step 2: 设置执行权限**

```bash
chmod +x templates/.pipeline/autosteps/memory-load.sh
```

- [ ] **Step 3: Commit**

```bash
git add templates/.pipeline/autosteps/memory-load.sh
git commit -m "feat: add memory-load.sh autostep for tiered constraint filtering"
```

---

### Task 3: 编写集成测试

**Files:**
- Create: `tests/memory-load/test_memory_load.sh`

- [ ] **Step 1: 编写测试脚本**

写入 `tests/memory-load/test_memory_load.sh`：

```bash
#!/usr/bin/env bash
# memory-load.sh 集成测试
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTOSTEP="$REPO_ROOT/templates/.pipeline/autosteps/memory-load.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (not found: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (should not contain: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# --- Test 1: 无 project-memory.json → SKIP ---
echo "Test 1: 无 project-memory.json → SKIP"
TMPDIR_T1=$(mktemp -d)
mkdir -p "$TMPDIR_T1/artifacts"
RESULT=$(PIPELINE_DIR="$TMPDIR_T1" bash "$AUTOSTEP")
assert_eq "输出 SKIP" "SKIP" "$RESULT"
rm -rf "$TMPDIR_T1"

# --- Test 2: 无 proposal-queue.json → SKIP ---
echo "Test 2: 无 proposal-queue.json → SKIP"
TMPDIR_T2=$(mktemp -d)
mkdir -p "$TMPDIR_T2/artifacts"
cp "$FIXTURES/project-memory.json" "$TMPDIR_T2/"
RESULT=$(PIPELINE_DIR="$TMPDIR_T2" bash "$AUTOSTEP")
assert_eq "输出 SKIP" "SKIP" "$RESULT"
rm -rf "$TMPDIR_T2"

# --- Test 3: 无 running 提案 → SKIP ---
echo "Test 3: 无 running 提案 → SKIP"
TMPDIR_T3=$(mktemp -d)
mkdir -p "$TMPDIR_T3/artifacts"
cp "$FIXTURES/project-memory.json" "$TMPDIR_T3/"
# 创建一个无 running 提案的队列
python3 -c "
import json
q = json.load(open('$FIXTURES/proposal-queue.json'))
for p in q['proposals']:
    if p['status'] == 'running':
        p['status'] = 'pending'
json.dump(q, open('$TMPDIR_T3/proposal-queue.json', 'w'))
"
RESULT=$(PIPELINE_DIR="$TMPDIR_T3" bash "$AUTOSTEP")
assert_eq "输出 SKIP" "SKIP" "$RESULT"
rm -rf "$TMPDIR_T3"

# --- Test 4: 正常过滤 — 配置管理提案 ---
echo "Test 4: 配置管理提案 — 过滤注入"
TMPDIR_T4=$(mktemp -d)
mkdir -p "$TMPDIR_T4/artifacts"
cp "$FIXTURES/project-memory.json" "$TMPDIR_T4/"
cp "$FIXTURES/proposal-queue.json" "$TMPDIR_T4/"
RESULT=$(PIPELINE_DIR="$TMPDIR_T4" bash "$AUTOSTEP")
OUTPUT=$(cat "$TMPDIR_T4/artifacts/memory-injection.txt")

assert_contains "输出 PASS" "PASS" "$RESULT"
assert_contains "包含 Project Memory 头" "=== Project Memory ===" "$OUTPUT"
assert_contains "包含 tier=1 全局约束 C-001" "[C-001]" "$OUTPUT"
assert_contains "包含 tier=1 全局约束 C-002" "[C-002]" "$OUTPUT"
assert_contains "包含配置管理约束 C-003" "[C-003]" "$OUTPUT"
assert_contains "包含配置管理约束 C-004" "[C-004]" "$OUTPUT"
assert_not_contains "不包含数据库操作台约束 C-005" "[C-005]" "$OUTPUT"
assert_not_contains "不包含通知约束 C-006" "[C-006]" "$OUTPUT"
assert_not_contains "不包含 Redis 约束 C-007" "[C-007]" "$OUTPUT"
assert_contains "包含无 tier 旧约束 C-008（默认 tier=1）" "[C-008]" "$OUTPUT"
assert_contains "包含注入统计" "[Memory Filter]" "$OUTPUT"
assert_contains "包含匹配领域" "配置管理" "$OUTPUT"
assert_contains "包含推翻记录" "[C-099]" "$OUTPUT"
assert_contains "包含交付足迹" "pipe-002" "$OUTPUT"
rm -rf "$TMPDIR_T4"

# --- Test 5: 无 domains 字段 — fallback 到 scope 匹配 ---
echo "Test 5: 无 domains 字段 — scope fallback"
TMPDIR_T5=$(mktemp -d)
mkdir -p "$TMPDIR_T5/artifacts"
cp "$FIXTURES/project-memory.json" "$TMPDIR_T5/"
# 创建无 domains 的通知提案
python3 -c "
import json
q = json.load(open('$FIXTURES/proposal-queue.json'))
for p in q['proposals']:
    p['status'] = 'completed' if p['id'] != 'P-003' else 'running'
q['proposals'][2]['status'] = 'running'
json.dump(q, open('$TMPDIR_T5/proposal-queue.json', 'w'))
"
RESULT=$(PIPELINE_DIR="$TMPDIR_T5" bash "$AUTOSTEP")
OUTPUT=$(cat "$TMPDIR_T5/artifacts/memory-injection.txt")

assert_contains "输出 PASS" "PASS" "$RESULT"
assert_contains "通过 scope 匹配到通知约束 C-006" "[C-006]" "$OUTPUT"
assert_not_contains "不包含配置管理约束 C-003" "[C-003]" "$OUTPUT"
assert_not_contains "不包含 Redis 约束 C-007" "[C-007]" "$OUTPUT"
rm -rf "$TMPDIR_T5"

# --- Test 6: 向后兼容 — 全部无 tier/domain ---
echo "Test 6: 向后兼容 — 全部无 tier/domain"
TMPDIR_T6=$(mktemp -d)
mkdir -p "$TMPDIR_T6/artifacts"
# 创建无 tier/domain 的 memory
python3 -c "
import json
m = {
  'version': 1, 'project_purpose': '测试项目',
  'constraints': [
    {'id': 'C-001', 'text': '约束1', 'tags': [], 'source': 'pipe-001'},
    {'id': 'C-002', 'text': '约束2', 'tags': [], 'source': 'pipe-001'},
    {'id': 'C-003', 'text': '约束3', 'tags': [], 'source': 'pipe-001'}
  ],
  'superseded': [], 'runs': []
}
json.dump(m, open('$TMPDIR_T6/project-memory.json', 'w'))
q = {'version': 1, 'system_name': 'test', 'proposals': [
  {'id': 'P-001', 'title': 'test', 'scope': 'test scope', 'status': 'running'}
]}
json.dump(q, open('$TMPDIR_T6/proposal-queue.json', 'w'))
"
RESULT=$(PIPELINE_DIR="$TMPDIR_T6" bash "$AUTOSTEP")
OUTPUT=$(cat "$TMPDIR_T6/artifacts/memory-injection.txt")

assert_contains "全部注入" "注入 3/3" "$RESULT"
assert_contains "包含 C-001" "[C-001]" "$OUTPUT"
assert_contains "包含 C-002" "[C-002]" "$OUTPUT"
assert_contains "包含 C-003" "[C-003]" "$OUTPUT"
rm -rf "$TMPDIR_T6"

# --- 结果 ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: 设置执行权限并运行测试**

```bash
chmod +x tests/memory-load/test_memory_load.sh
bash tests/memory-load/test_memory_load.sh
```

Expected: 所有测试 PASS

- [ ] **Step 3: Commit**

```bash
git add tests/memory-load/test_memory_load.sh
git commit -m "test: add integration tests for memory-load autostep"
```

---

## Chunk 2: playbook 改动

### Task 4: 替换 playbook Memory Load 章节

**Files:**
- Modify: `templates/.pipeline/playbook.md:103-133`

- [ ] **Step 1: 替换 Memory Load 章节**

将 `templates/.pipeline/playbook.md` 第 103-133 行（从 `## Memory Load` 到 `输出格式` 行）替换为：

```markdown
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
```

- [ ] **Step 2: 验证 playbook 格式**

```bash
# 确认替换后前后文衔接正确
head -140 templates/.pipeline/playbook.md | tail -40
```

- [ ] **Step 3: Commit**

```bash
git add templates/.pipeline/playbook.md
git commit -m "feat: replace Memory Load with AutoStep-based tiered filtering"
```

---

### Task 5: 修改 Memory Consolidation Step 4

**Files:**
- Modify: `templates/.pipeline/playbook.md:729`

- [ ] **Step 1: 扩展约束格式**

将 playbook.md 第 729 行：
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
     - "所有 API 统一返回 {code, message, data} 格式" → tier=1, domain 留空
     - "密码策略必须包含大小写+数字+特殊字符" → tier=1, domain 留空
     - "POST /api/config-nodes 必须校验环境权限" → tier=2, domain="配置管理"
     - "数据库操作台 SQL 执行必须设置 30 秒超时" → tier=2, domain="数据库操作台"
     - "Webhook 重试策略为指数退避，最多 5 次" → tier=2, domain="通知/Webhook"
```

- [ ] **Step 2: Commit**

```bash
git add templates/.pipeline/playbook.md
git commit -m "feat: extend Memory Consolidation to tag constraints with tier/domain"
```

---

### Task 6: System Planning 增加 domains 字段引导

**Files:**
- Modify: `templates/.pipeline/playbook.md:54-66`（提案 detail 结构示例）

- [ ] **Step 1: 在提案结构中增加 domains 字段**

在 playbook.md System Planning 的提案 detail 结构示例（约第 54-66 行的 JSON 块）中，在 `"scope"` 行后增加 `"domains"` 字段：

```json
{
  "id": "P-001", "title": "基础框架与用户体系",
  "scope": "包含/不包含描述",
  "domains": ["用户/团队/环境"],
  "depends_on": [], "status": "pending",
  "detail": { ... }
}
```

在第 22 行 scope 描述后增加说明：
```
   - `domains`（可选但推荐）：该提案涉及的业务领域列表，从已有约束的 domain 值中选取或新建简短中文领域名
```

- [ ] **Step 2: Commit**

```bash
git add templates/.pipeline/playbook.md
git commit -m "feat: add domains field guidance to System Planning proposal format"
```

---

## Chunk 3: 安装与验收

### Task 7: 验证 install.sh 兼容性

**Files:**
- 无需修改（install.sh 自动发现 `*.sh` 文件）

- [ ] **Step 1: 确认新脚本会被自动安装**

```bash
# install.sh 使用 find 自动发现 autosteps/*.sh
# 确认 memory-load.sh 在列表中
find templates/.pipeline/autosteps -name "*.sh" | sort | grep memory-load
```

Expected: `templates/.pipeline/autosteps/memory-load.sh`

- [ ] **Step 2: 运行 install.sh 验证**

```bash
bash install.sh
```

Expected: autostep 数量显示 20 scripts（当前 19 个 + 新增 memory-load.sh）

---

### Task 8: 端到端验证

- [ ] **Step 1: 运行集成测试**

```bash
bash tests/memory-load/test_memory_load.sh
```

Expected: 所有测试 PASS

- [ ] **Step 2: 用真实项目数据验证（如有）**

如果有正在执行的项目（如 ops-platform），可手动测试：

```bash
cd /path/to/ops-platform
PIPELINE_DIR=.pipeline bash .pipeline/autosteps/memory-load.sh
cat .pipeline/artifacts/memory-injection.txt | head -20
```

- [ ] **Step 3: 最终 commit（如有调整）**

---

### Task 9: 更新 CLAUDE.md autosteps 计数

**Files:**
- Modify: `templates/CLAUDE.md`

- [ ] **Step 1: 更新 autosteps 计数**

在 `templates/CLAUDE.md` 目录结构中，将 `autosteps/` 的注释从 `17 个` 更新为 `20 个`。

- [ ] **Step 2: Commit**

```bash
git add templates/CLAUDE.md
git commit -m "docs: update autosteps count in CLAUDE.md"
```
