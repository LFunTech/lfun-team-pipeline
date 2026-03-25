#!/usr/bin/env bash
# sync-micro-changes-to-memory.sh — 将已判定为长期规则的小改同步到 project-memory

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
MEMORY_PATH="$PIPELINE_DIR/project-memory.json"
CHANGES_PATH="$PIPELINE_DIR/micro-changes.json"
REPORT_PATH="$PIPELINE_DIR/artifacts/micro-change-sync-report.json"

mkdir -p "$PIPELINE_DIR/artifacts"

if [ ! -f "$MEMORY_PATH" ] || [ ! -f "$CHANGES_PATH" ]; then
  echo "SKIP"
  exit 0
fi

python3 - "$MEMORY_PATH" "$CHANGES_PATH" "$REPORT_PATH" <<'PYEOF'
import json
import re
import sys

memory_path, changes_path, report_path = sys.argv[1:]

with open(memory_path, "r", encoding="utf-8") as f:
    memory = json.load(f)
with open(changes_path, "r", encoding="utf-8") as f:
    changes_data = json.load(f)

memory.setdefault("constraints", [])
changes_data.setdefault("changes", [])

def normalize(text):
    return re.sub(r"\s+", " ", (text or "").strip().lower())

existing_texts = {normalize(item.get("text", "")) for item in memory["constraints"]}

max_constraint_id = 0
for item in memory["constraints"]:
    item_id = item.get("id", "")
    if item_id.startswith("C-"):
        try:
            max_constraint_id = max(max_constraint_id, int(item_id[2:]))
        except ValueError:
            pass

added = []
duplicates = []
skipped = []

for change in changes_data["changes"]:
    if not change.get("memory_candidate"):
        continue
    if change.get("consumed_by_memory"):
        continue
    if change.get("status") != "recorded":
        continue

    text = (change.get("proposed_constraint") or change.get("normalized_change") or "").strip()
    if not text:
        skipped.append({"id": change.get("id"), "reason": "empty-text"})
        continue

    normalized = normalize(text)
    if normalized in existing_texts:
        change["consumed_by_memory"] = True
        duplicates.append(change.get("id"))
        continue

    max_constraint_id += 1
    domains = change.get("domains") or []
    domain = domains[0] if len(domains) == 1 else ""
    tier = 2 if domain else 1
    tags = ["micro-change"]
    for domain_item in domains:
        if domain_item not in tags:
            tags.append(domain_item)

    constraint = {
        "id": f"C-{max_constraint_id:03d}",
        "text": text,
        "tags": tags,
        "source": f"micro-change:{change.get('id', 'unknown')}",
        "tier": tier,
    }
    if domain:
        constraint["domain"] = domain

    memory["constraints"].append(constraint)
    existing_texts.add(normalized)
    change["consumed_by_memory"] = True
    added.append({"change_id": change.get("id"), "constraint_id": constraint["id"], "text": text})

report = {
    "added": added,
    "duplicates": duplicates,
    "skipped": skipped,
}

if not added and not duplicates and not skipped:
    print("SKIP")
    sys.exit(0)

with open(memory_path, "w", encoding="utf-8") as f:
    json.dump(memory, f, ensure_ascii=False, indent=2)
    f.write("\n")
with open(changes_path, "w", encoding="utf-8") as f:
    json.dump(changes_data, f, ensure_ascii=False, indent=2)
    f.write("\n")
with open(report_path, "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"PASS — added {len(added)}, duplicates {len(duplicates)}, skipped {len(skipped)}")
PYEOF
