#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTOSTEP="$REPO_ROOT/templates/.pipeline/autosteps/impl-manifest-merger.sh"

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

echo "Test 1: 无重复 -> PASS"
TMPDIR_T1=$(mktemp -d)
mkdir -p "$TMPDIR_T1/artifacts"
python3 - <<PY
import json
json.dump({
  "builder": "Builder-Backend",
  "tasks_completed": ["task-1"],
  "files_changed": [{"path": "src/api.ts", "action": "modify"}]
}, open("$TMPDIR_T1/artifacts/impl-manifest-backend.json", "w"))
json.dump({
  "builder": "Builder-Frontend",
  "tasks_completed": ["task-2"],
  "files_changed": [{"path": "src/page.tsx", "action": "modify"}]
}, open("$TMPDIR_T1/artifacts/impl-manifest-frontend.json", "w"))
PY
PIPELINE_DIR="$TMPDIR_T1" bash "$AUTOSTEP" >/dev/null
OVERALL=$(python3 - <<PY
import json
print(json.load(open("$TMPDIR_T1/artifacts/impl-manifest.json"))["overall"])
PY
)
assert_eq "overall PASS" "PASS" "$OVERALL"
rm -rf "$TMPDIR_T1"

echo "Test 2: 重复文件路径 -> FAIL"
TMPDIR_T2=$(mktemp -d)
mkdir -p "$TMPDIR_T2/artifacts"
python3 - <<PY
import json
json.dump({
  "builder": "Builder-Security",
  "tasks_completed": ["task-1"],
  "files_changed": [{"path": "src/shared.ts", "action": "modify"}]
}, open("$TMPDIR_T2/artifacts/impl-manifest-security.json", "w"))
json.dump({
  "builder": "Builder-Frontend",
  "tasks_completed": ["task-2"],
  "files_changed": [{"path": "src/shared.ts", "action": "modify"}]
}, open("$TMPDIR_T2/artifacts/impl-manifest-frontend.json", "w"))
PY
if PIPELINE_DIR="$TMPDIR_T2" bash "$AUTOSTEP" >/dev/null 2>&1; then
  RESULT="PASS"
else
  RESULT="FAIL"
fi
DUP_PATH=$(python3 - <<PY
import json
data = json.load(open("$TMPDIR_T2/artifacts/impl-manifest.json"))
print(data["overall"])
print(data["duplicate_paths"][0]["path"])
PY
)
OVERALL=$(python3 - <<PY
data = """$DUP_PATH""".splitlines()
print(data[0])
PY
)
PATH_HIT=$(python3 - <<PY
data = """$DUP_PATH""".splitlines()
print(data[1])
PY
)
assert_eq "脚本返回 FAIL" "FAIL" "$RESULT"
assert_eq "overall FAIL" "FAIL" "$OVERALL"
assert_eq "重复路径记录" "src/shared.ts" "$PATH_HIT"
rm -rf "$TMPDIR_T2"

echo "Test 3: 重复 task_id -> FAIL"
TMPDIR_T3=$(mktemp -d)
mkdir -p "$TMPDIR_T3/artifacts"
python3 - <<PY
import json
json.dump({
  "builder": "Builder-Backend",
  "tasks_completed": ["task-1"],
  "files_changed": [{"path": "src/api.ts", "action": "modify"}]
}, open("$TMPDIR_T3/artifacts/impl-manifest-backend.json", "w"))
json.dump({
  "builder": "Builder-Infra",
  "tasks_completed": ["task-1"],
  "files_changed": [{"path": "deploy/app.yaml", "action": "modify"}]
}, open("$TMPDIR_T3/artifacts/impl-manifest-infra.json", "w"))
PY
if PIPELINE_DIR="$TMPDIR_T3" bash "$AUTOSTEP" >/dev/null 2>&1; then
  RESULT="PASS"
else
  RESULT="FAIL"
fi
DUP_TASK=$(python3 - <<PY
import json
data = json.load(open("$TMPDIR_T3/artifacts/impl-manifest.json"))
print(data["overall"])
print(data["duplicate_task_ids"][0]["task_id"])
PY
)
OVERALL=$(python3 - <<PY
data = """$DUP_TASK""".splitlines()
print(data[0])
PY
)
TASK_ID=$(python3 - <<PY
data = """$DUP_TASK""".splitlines()
print(data[1])
PY
)
assert_eq "脚本返回 FAIL(task)" "FAIL" "$RESULT"
assert_eq "overall FAIL(task)" "FAIL" "$OVERALL"
assert_eq "重复 task_id 记录" "task-1" "$TASK_ID"
rm -rf "$TMPDIR_T3"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
