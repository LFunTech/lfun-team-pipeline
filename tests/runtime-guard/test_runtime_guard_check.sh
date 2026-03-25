#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECKER="$REPO_ROOT/templates/.pipeline/autosteps/runtime-guard-check.py"

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

echo "Test 1: 完整运行时 -> PASS"
TMPDIR_T1=$(mktemp -d)
mkdir -p "$TMPDIR_T1/autosteps" "$TMPDIR_T1/artifacts"
cp "$REPO_ROOT/templates/.pipeline/playbook.md" "$TMPDIR_T1/playbook.md"
cp "$REPO_ROOT/templates/.pipeline/autosteps/build-conflict-detector.py" "$TMPDIR_T1/autosteps/"
cp "$REPO_ROOT/templates/.pipeline/autosteps/parallel-proposal-detector.py" "$TMPDIR_T1/autosteps/"
cp "$REPO_ROOT/templates/.pipeline/autosteps/impl-manifest-merger.sh" "$TMPDIR_T1/autosteps/"
python3 - <<PY
import json
state = {
  "phase_3_wave_bases": {},
  "phase_3_conflict_files": [],
  "parallel_precheck_report": None,
}
json.dump(state, open("$TMPDIR_T1/state.json", "w"))
PY
if PIPELINE_DIR="$TMPDIR_T1" python3 "$CHECKER" >/dev/null 2>&1; then
  RESULT="PASS"
else
  RESULT="FAIL"
fi
assert_eq "checker pass" "PASS" "$RESULT"
rm -rf "$TMPDIR_T1"

echo "Test 2: 缺少 detector -> FAIL"
TMPDIR_T2=$(mktemp -d)
mkdir -p "$TMPDIR_T2/autosteps" "$TMPDIR_T2/artifacts"
cp "$REPO_ROOT/templates/.pipeline/playbook.md" "$TMPDIR_T2/playbook.md"
cp "$REPO_ROOT/templates/.pipeline/autosteps/impl-manifest-merger.sh" "$TMPDIR_T2/autosteps/"
python3 - <<PY
import json
state = {
  "phase_3_wave_bases": {},
  "phase_3_conflict_files": [],
  "parallel_precheck_report": None,
}
json.dump(state, open("$TMPDIR_T2/state.json", "w"))
PY
if PIPELINE_DIR="$TMPDIR_T2" python3 "$CHECKER" >/dev/null 2>&1; then
  RESULT="PASS"
else
  RESULT="FAIL"
fi
assert_eq "checker fail on missing file" "FAIL" "$RESULT"
rm -rf "$TMPDIR_T2"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
