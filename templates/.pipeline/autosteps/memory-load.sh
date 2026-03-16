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
