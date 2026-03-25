#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTOSTEP="$REPO_ROOT/templates/.pipeline/autosteps/build-conflict-detector.py"

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

echo "Test 1: 无重叠文件 -> PASS"
TMPDIR_T1=$(mktemp -d)
mkdir -p "$TMPDIR_T1/artifacts"
python3 - <<PY
import json
tasks = {
  "tasks": [
    {"id": "task-1", "assigned_to": "Builder-Backend", "files": [{"path": "src/api.ts", "action": "modify"}]},
    {"id": "task-2", "assigned_to": "Builder-Frontend", "files": [{"path": "src/page.tsx", "action": "modify"}]}
  ]
}
json.dump(tasks, open("$TMPDIR_T1/artifacts/tasks.json", "w"))
PY
RESULT=$(PIPELINE_DIR="$TMPDIR_T1" BUILDERS="backend,frontend" python3 "$AUTOSTEP")
OVERALL=$(python3 - <<PY
import json
print(json.load(open("$TMPDIR_T1/artifacts/build-conflict-report.json"))["overall"])
PY
)
assert_eq "stdout PASS" "PASS" "$RESULT"
assert_eq "report overall PASS" "PASS" "$OVERALL"
rm -rf "$TMPDIR_T1"

echo "Test 2: 同波次重叠文件 -> OVERLAP"
TMPDIR_T2=$(mktemp -d)
mkdir -p "$TMPDIR_T2/artifacts"
python3 - <<PY
import json
tasks = {
  "tasks": [
    {"id": "task-1", "assigned_to": "Builder-Security", "files": [{"path": "src/shared.ts", "action": "modify"}]},
    {"id": "task-2", "assigned_to": "Builder-Frontend", "files": [{"path": "src/shared.ts", "action": "modify"}]}
  ]
}
json.dump(tasks, open("$TMPDIR_T2/artifacts/tasks.json", "w"))
PY
RESULT=$(PIPELINE_DIR="$TMPDIR_T2" BUILDERS="security,frontend" python3 "$AUTOSTEP")
CHECK=$(python3 - <<PY
import json
data = json.load(open("$TMPDIR_T2/artifacts/build-conflict-report.json"))
print(data["overall"])
print(",".join(data["overlap_builders"]))
print(data["overlap_paths"][0]["path"])
PY
)
OVERALL=$(python3 - <<PY
data = """$CHECK""".splitlines()
print(data[0])
PY
)
BUILDERS=$(python3 - <<PY
data = """$CHECK""".splitlines()
print(data[1])
PY
)
PATH_HIT=$(python3 - <<PY
data = """$CHECK""".splitlines()
print(data[2])
PY
)
assert_eq "stdout OVERLAP" "OVERLAP" "$RESULT"
assert_eq "report overall OVERLAP" "OVERLAP" "$OVERALL"
assert_eq "重叠 builders" "security,frontend" "$BUILDERS"
assert_eq "重叠路径" "src/shared.ts" "$PATH_HIT"
rm -rf "$TMPDIR_T2"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
