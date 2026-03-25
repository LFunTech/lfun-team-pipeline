#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

TMP_HOME=$(mktemp -d)
TMP_PROJ=$(mktemp -d)
trap 'rm -rf "$TMP_HOME" "$TMP_PROJ" /tmp/team-doctor-before.log /tmp/team-repair.log /tmp/team-doctor-after.log /tmp/team-install-test.log' EXIT

echo "Test: team repair backfills runtime guard state fields"

(cd "$REPO_ROOT" && HOME="$TMP_HOME" bash install.sh >/tmp/team-install-test.log 2>&1)

mkdir -p "$TMP_PROJ/.pipeline/autosteps" "$TMP_PROJ/.pipeline/artifacts"
cp "$REPO_ROOT/templates/.pipeline/playbook.md" "$TMP_PROJ/.pipeline/playbook.md"
cp "$REPO_ROOT/templates/.pipeline/autosteps/runtime-guard-check.py" "$TMP_PROJ/.pipeline/autosteps/"
cp "$REPO_ROOT/templates/.pipeline/autosteps/build-conflict-detector.py" "$TMP_PROJ/.pipeline/autosteps/"
cp "$REPO_ROOT/templates/.pipeline/autosteps/parallel-proposal-detector.py" "$TMP_PROJ/.pipeline/autosteps/"
cp "$REPO_ROOT/templates/.pipeline/autosteps/impl-manifest-merger.sh" "$TMP_PROJ/.pipeline/autosteps/"

python3 - "$TMP_PROJ/.pipeline/state.json" <<'PY'
import json
import sys

state = {
    'pipeline_id': 'test',
    'project_name': 'test',
    'current_phase': '3.build',
    'status': 'running',
}

with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(state, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY

(cd "$TMP_PROJ" && "$TMP_HOME/.local/bin/team" doctor >/tmp/team-doctor-before.log 2>&1 || true)
(cd "$TMP_PROJ" && "$TMP_HOME/.local/bin/team" repair >/tmp/team-repair.log 2>&1)
(cd "$TMP_PROJ" && "$TMP_HOME/.local/bin/team" doctor >/tmp/team-doctor-after.log 2>&1)

KEYS_PRESENT=$(python3 - "$TMP_PROJ/.pipeline/state.json" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1], encoding='utf-8'))
required = ['phase_3_wave_bases', 'phase_3_conflict_files', 'parallel_precheck_report']
print('true' if all(key in state for key in required) else 'false')
PY
)

DOCTOR_BEFORE=$(python3 - <<'PY'
from pathlib import Path
text = Path('/tmp/team-doctor-before.log').read_text(encoding='utf-8')
print('true' if 'state schema drift' in text else 'false')
PY
)

REPAIR_BACKFILL=$(python3 - <<'PY'
from pathlib import Path
text = Path('/tmp/team-repair.log').read_text(encoding='utf-8')
print('true' if 'added runtime guard fields' in text else 'false')
PY
)

DOCTOR_AFTER=$(python3 - <<'PY'
from pathlib import Path
text = Path('/tmp/team-doctor-after.log').read_text(encoding='utf-8')
print('true' if 'Runtime guard files are present and look current.' in text else 'false')
PY
)

assert_eq "doctor reports state drift" "true" "$DOCTOR_BEFORE"
assert_eq "repair backfills state fields" "true" "$REPAIR_BACKFILL"
assert_eq "state contains required fields" "true" "$KEYS_PRESENT"
assert_eq "doctor passes after repair" "true" "$DOCTOR_AFTER"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
