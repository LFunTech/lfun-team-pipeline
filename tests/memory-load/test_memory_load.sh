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
