#!/usr/bin/env bash
# record-micro-change.sh — 记录一句话级别业务小改
# 用法：
#   PIPELINE_DIR=.pipeline bash .pipeline/autosteps/record-micro-change.sh \
#     --raw "这里默认改成7天吧" \
#     --normalized "将导出链接默认有效期调整为7天" \
#     --domain "导出" \
#     --memory-candidate true \
#     --constraint "导出链接默认有效期必须为7天"

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
CHANGES_PATH="$PIPELINE_DIR/micro-changes.json"

RAW_REQUEST=""
NORMALIZED_CHANGE=""
SOURCE="chat"
KIND="business-small-change"
MEMORY_CANDIDATE="false"
PROPOSED_CONSTRAINT=""
RELATED_COMMIT=""
RELATED_FILES=()
DOMAINS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --raw)
      RAW_REQUEST="$2"
      shift 2
      ;;
    --normalized)
      NORMALIZED_CHANGE="$2"
      shift 2
      ;;
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --kind)
      KIND="$2"
      shift 2
      ;;
    --memory-candidate)
      MEMORY_CANDIDATE="$2"
      shift 2
      ;;
    --constraint)
      PROPOSED_CONSTRAINT="$2"
      shift 2
      ;;
    --domain)
      DOMAINS+=("$2")
      shift 2
      ;;
    --file)
      RELATED_FILES+=("$2")
      shift 2
      ;;
    --commit)
      RELATED_COMMIT="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$RAW_REQUEST" ] || [ -z "$NORMALIZED_CHANGE" ]; then
  echo "ERROR: --raw and --normalized are required" >&2
  exit 1
fi

mkdir -p "$PIPELINE_DIR"

python3 - "$CHANGES_PATH" "$RAW_REQUEST" "$NORMALIZED_CHANGE" "$SOURCE" "$KIND" "$MEMORY_CANDIDATE" "$PROPOSED_CONSTRAINT" "$RELATED_COMMIT" "${DOMAINS[*]:-}" "${RELATED_FILES[*]:-}" <<'PYEOF'
import json
import os
import sys
from datetime import date

path, raw_request, normalized_change, source, kind, memory_candidate_raw, proposed_constraint, related_commit, domains_raw, related_files_raw = sys.argv[1:]

memory_candidate = memory_candidate_raw.lower() == "true"
domains = [item for item in domains_raw.split(" ") if item]
related_files = [item for item in related_files_raw.split(" ") if item]

if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {"version": 1, "changes": []}

changes = data.setdefault("changes", [])
max_id = 0
for item in changes:
    item_id = item.get("id", "")
    if item_id.startswith("MC-"):
        try:
            max_id = max(max_id, int(item_id[3:]))
        except ValueError:
            pass

record = {
    "id": f"MC-{max_id + 1:03d}",
    "date": str(date.today()),
    "source": source,
    "raw_request": raw_request,
    "normalized_change": normalized_change,
    "domains": domains,
    "kind": kind,
    "memory_candidate": memory_candidate,
    "proposed_constraint": proposed_constraint,
    "status": "recorded",
    "related_files": related_files,
    "related_commit": related_commit,
    "consumed_by_memory": False,
}
changes.append(record)

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"PASS — recorded {record['id']}")
PYEOF
