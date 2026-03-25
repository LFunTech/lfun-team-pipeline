#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTOSTEP="$REPO_ROOT/templates/.pipeline/autosteps/parallel-proposal-detector.py"

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

echo "Test 1: detail 完整且足迹独立 -> PASS"
TMPDIR_T1=$(mktemp -d)
mkdir -p "$TMPDIR_T1/artifacts"
python3 - <<PY
import json
queue = {
  "proposals": [
    {
      "id": "P-002",
      "title": "商品目录",
      "scope": "商品列表与分类展示",
      "domains": ["商品"],
      "detail": {
        "api_overview": ["GET /api/catalog/products - 商品列表"],
        "data_entities": ["products(id, name, price)"]
      }
    },
    {
      "id": "P-003",
      "title": "订单追踪",
      "scope": "订单查询与物流状态",
      "domains": ["订单"],
      "detail": {
        "api_overview": ["GET /api/orders/list - 订单列表"],
        "data_entities": ["orders(id, status, total_amount)"]
      }
    }
  ]
}
json.dump(queue, open("$TMPDIR_T1/proposal-queue.json", "w"), ensure_ascii=False)
PY
RESULT=$(PIPELINE_DIR="$TMPDIR_T1" PROPOSAL_IDS="P-002,P-003" python3 "$AUTOSTEP")
OVERALL=$(python3 - <<PY
import json
print(json.load(open("$TMPDIR_T1/artifacts/parallel-proposal-report.json"))["overall"])
PY
)
assert_eq "stdout PASS" "PASS" "$RESULT"
assert_eq "report PASS" "PASS" "$OVERALL"
rm -rf "$TMPDIR_T1"

echo "Test 2: 缺少 detail -> OVERLAP"
TMPDIR_T2=$(mktemp -d)
mkdir -p "$TMPDIR_T2/artifacts"
python3 - <<PY
import json
queue = {
  "proposals": [
    {"id": "P-002", "title": "商品目录", "scope": "商品列表", "domains": ["商品"]},
    {"id": "P-003", "title": "订单追踪", "scope": "订单列表", "domains": ["订单"], "detail": {"api_overview": ["GET /api/orders/list"], "data_entities": ["orders(id)"]}}
  ]
}
json.dump(queue, open("$TMPDIR_T2/proposal-queue.json", "w"), ensure_ascii=False)
PY
RESULT=$(PIPELINE_DIR="$TMPDIR_T2" PROPOSAL_IDS="P-002,P-003" python3 "$AUTOSTEP")
CHECK=$(python3 - <<PY
import json
data = json.load(open("$TMPDIR_T2/artifacts/parallel-proposal-report.json"))
print(data["overall"])
print(data["reasons"][0]["type"])
PY
)
OVERALL=$(python3 - <<PY
data = """$CHECK""".splitlines()
print(data[0])
PY
)
REASON=$(python3 - <<PY
data = """$CHECK""".splitlines()
print(data[1])
PY
)
assert_eq "stdout OVERLAP" "OVERLAP" "$RESULT"
assert_eq "report OVERLAP" "OVERLAP" "$OVERALL"
assert_eq "原因 missing_detail" "missing_detail" "$REASON"
rm -rf "$TMPDIR_T2"

echo "Test 3: 独立 domain 但共享认证关键词 -> OVERLAP"
TMPDIR_T3=$(mktemp -d)
mkdir -p "$TMPDIR_T3/artifacts"
python3 - <<PY
import json
queue = {
  "proposals": [
    {
      "id": "P-010",
      "title": "商家中心登录审计",
      "scope": "补充登录审计与认证失败提示",
      "domains": ["商家"],
      "detail": {
        "api_overview": ["POST /api/merchant/login - 商家登录"],
        "data_entities": ["merchant_audit_logs(id, user_id)"]
      }
    },
    {
      "id": "P-011",
      "title": "运维后台权限设置",
      "scope": "运维后台认证与权限配置",
      "domains": ["运维"],
      "detail": {
        "api_overview": ["POST /api/admin/auth/login - 管理员登录"],
        "data_entities": ["admin_roles(id, name)"]
      }
    }
  ]
}
json.dump(queue, open("$TMPDIR_T3/proposal-queue.json", "w"), ensure_ascii=False)
PY
RESULT=$(PIPELINE_DIR="$TMPDIR_T3" PROPOSAL_IDS="P-010,P-011" python3 "$AUTOSTEP")
CHECK=$(python3 - <<PY
import json
data = json.load(open("$TMPDIR_T3/artifacts/parallel-proposal-report.json"))
print(data["overall"])
print(data["reasons"][0]["type"])
PY
)
OVERALL=$(python3 - <<PY
data = """$CHECK""".splitlines()
print(data[0])
PY
)
REASON=$(python3 - <<PY
data = """$CHECK""".splitlines()
print(data[1])
PY
)
assert_eq "stdout OVERLAP(shared)" "OVERLAP" "$RESULT"
assert_eq "report OVERLAP(shared)" "OVERLAP" "$OVERALL"
if [ "$REASON" = "shared_keyword_overlap" ] || [ "$REASON" = "api_overlap" ]; then
  echo "  ✓ 共享原因"
  PASS=$((PASS + 1))
else
  echo "  ✗ 共享原因"
  echo "    expected: shared_keyword_overlap|api_overlap"
  echo "    actual:   $REASON"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR_T3"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
