#!/usr/bin/env bash
# list-micro-changes.sh — 查看 micro-change 记录

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
CHANGES_PATH="$PIPELINE_DIR/micro-changes.json"
MODE="all"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pending)
      MODE="pending"
      shift
      ;;
    --all)
      MODE="all"
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$CHANGES_PATH" ]; then
  echo "SKIP"
  exit 0
fi

python3 - "$CHANGES_PATH" "$MODE" <<'PYEOF'
import json
import sys

path, mode = sys.argv[1:]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

changes = data.get("changes", [])
if mode == "pending":
    changes = [c for c in changes if c.get("memory_candidate") and not c.get("consumed_by_memory")]

if not changes:
    print("EMPTY")
    sys.exit(0)

for change in changes:
    domains = ", ".join(change.get("domains") or []) or "-"
    print(f"[{change.get('id', '-')}] source={change.get('source', '-')} memory_candidate={change.get('memory_candidate', False)} consumed={change.get('consumed_by_memory', False)} domains={domains}")
    print(f"  raw: {change.get('raw_request', '')}")
    print(f"  normalized: {change.get('normalized_change', '')}")
    if change.get("proposed_constraint"):
        print(f"  constraint: {change['proposed_constraint']}")
PYEOF
