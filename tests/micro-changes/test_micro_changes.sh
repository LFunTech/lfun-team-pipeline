#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RECORD_SCRIPT="$REPO_ROOT/templates/.pipeline/autosteps/record-micro-change.sh"
SYNC_SCRIPT="$REPO_ROOT/templates/.pipeline/autosteps/sync-micro-changes-to-memory.sh"
LIST_SCRIPT="$REPO_ROOT/templates/.pipeline/autosteps/list-micro-changes.sh"

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

echo "Test 1: record-micro-change 写入记录"
TMPDIR_T1=$(mktemp -d)
RESULT=$(PIPELINE_DIR="$TMPDIR_T1" bash "$RECORD_SCRIPT" \
  --raw "这里默认改成7天吧" \
  --normalized "将导出链接默认有效期调整为7天" \
  --domain "导出" \
  --memory-candidate true \
  --constraint "导出链接默认有效期必须为7天")
CONTENT=$(python3 - "$TMPDIR_T1/micro-changes.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(data['changes'][0]['id'])
print(data['changes'][0]['raw_request'])
print(data['changes'][0]['memory_candidate'])
print(data['changes'][0]['consumed_by_memory'])
PY
)
assert_contains "输出 PASS" "PASS" "$RESULT"
assert_contains "生成 MC-001" "MC-001" "$CONTENT"
assert_contains "保留原始请求" "这里默认改成7天吧" "$CONTENT"
assert_contains "标记 memory_candidate" "True" "$CONTENT"
assert_contains "初始未消费" "False" "$CONTENT"
rm -rf "$TMPDIR_T1"

echo "Test 2: sync-micro-changes-to-memory 同步长期规则"
TMPDIR_T2=$(mktemp -d)
mkdir -p "$TMPDIR_T2/artifacts"
cat > "$TMPDIR_T2/project-memory.json" <<'EOF'
{
  "version": 1,
  "project_purpose": "测试项目",
  "constraints": [
    {
      "id": "C-001",
      "text": "所有 API 统一返回 {code, message, data} 格式",
      "tags": ["API规范"],
      "source": "pipe-001",
      "tier": 1
    }
  ],
  "superseded": [],
  "runs": []
}
EOF
cat > "$TMPDIR_T2/micro-changes.json" <<'EOF'
{
  "version": 1,
  "changes": [
    {
      "id": "MC-001",
      "date": "2026-03-24",
      "source": "chat",
      "raw_request": "这里默认改成7天吧",
      "normalized_change": "将导出链接默认有效期调整为7天",
      "domains": ["导出"],
      "kind": "business-small-change",
      "memory_candidate": true,
      "proposed_constraint": "导出链接默认有效期必须为7天",
      "status": "recorded",
      "related_files": [],
      "related_commit": "",
      "consumed_by_memory": false
    },
    {
      "id": "MC-002",
      "date": "2026-03-24",
      "source": "chat",
      "raw_request": "接口返回统一格式",
      "normalized_change": "所有 API 统一返回 {code, message, data} 格式",
      "domains": [],
      "kind": "business-small-change",
      "memory_candidate": true,
      "proposed_constraint": "所有 API 统一返回 {code, message, data} 格式",
      "status": "recorded",
      "related_files": [],
      "related_commit": "",
      "consumed_by_memory": false
    }
  ]
}
EOF
RESULT=$(PIPELINE_DIR="$TMPDIR_T2" bash "$SYNC_SCRIPT")
CONTENT=$(python3 - "$TMPDIR_T2/project-memory.json" "$TMPDIR_T2/micro-changes.json" "$TMPDIR_T2/artifacts/micro-change-sync-report.json" <<'PY'
import json, sys
memory = json.load(open(sys.argv[1]))
changes = json.load(open(sys.argv[2]))
report = json.load(open(sys.argv[3]))
print(len(memory['constraints']))
print(memory['constraints'][-1]['id'])
print(memory['constraints'][-1]['text'])
print(memory['constraints'][-1]['domain'])
print(changes['changes'][0]['consumed_by_memory'])
print(changes['changes'][1]['consumed_by_memory'])
print(report['duplicates'][0])
PY
)
assert_contains "输出 PASS" "PASS" "$RESULT"
assert_contains "新增一条约束" $'2\nC-002' "$CONTENT"
assert_contains "写入长期规则文本" "导出链接默认有效期必须为7天" "$CONTENT"
assert_contains "写入领域" "导出" "$CONTENT"
assert_contains "新增记录已消费" "True" "$CONTENT"
assert_contains "重复记录已消费" "MC-002" "$CONTENT"
rm -rf "$TMPDIR_T2"

echo "Test 3: list-micro-changes 查看待处理记录"
TMPDIR_T3=$(mktemp -d)
cat > "$TMPDIR_T3/micro-changes.json" <<'EOF'
{
  "version": 1,
  "changes": [
    {
      "id": "MC-001",
      "date": "2026-03-24",
      "source": "chat",
      "raw_request": "这里默认改成7天吧",
      "normalized_change": "将导出链接默认有效期调整为7天",
      "domains": ["导出"],
      "kind": "business-small-change",
      "memory_candidate": true,
      "proposed_constraint": "导出链接默认有效期必须为7天",
      "status": "recorded",
      "related_files": [],
      "related_commit": "",
      "consumed_by_memory": false
    },
    {
      "id": "MC-002",
      "date": "2026-03-24",
      "source": "chat",
      "raw_request": "按钮右移一点",
      "normalized_change": "将按钮向右微调",
      "domains": [],
      "kind": "business-small-change",
      "memory_candidate": false,
      "proposed_constraint": "",
      "status": "recorded",
      "related_files": [],
      "related_commit": "",
      "consumed_by_memory": false
    }
  ]
}
EOF
RESULT=$(PIPELINE_DIR="$TMPDIR_T3" bash "$LIST_SCRIPT" --pending)
assert_contains "仅列出待处理 memory 候选" "MC-001" "$RESULT"
assert_contains "包含约束文本" "导出链接默认有效期必须为7天" "$RESULT"
assert_eq "不列出非候选记录数量" "0" "$(printf '%s' "$RESULT" | python3 -c "import sys; print(1 if 'MC-002' in sys.stdin.read() else 0)")"
rm -rf "$TMPDIR_T3"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
