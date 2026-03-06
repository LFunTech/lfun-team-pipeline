#!/usr/bin/env bash
# build-verifier.sh — Phase 3.0b 编译验证 AutoStep
# 在所有 Builder merge 完成后、Phase 3.1 之前运行
# 支持：Rust (cargo) / Go (go build) / Node.js (npm run build) / Python (无编译，直接 PASS)
# 输出：.pipeline/artifacts/build-verifier-report.json
# exit 0 = PASS, exit 1 = FAIL

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
REPORT="$PIPELINE_DIR/artifacts/build-verifier-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

write_report() {
  local overall="$1" tool="$2" output="$3" errors="$4"
  python3 - <<PYEOF
import json
data = {
    "autostep": "BuildVerifier",
    "timestamp": "$TIMESTAMP",
    "tool": "$tool",
    "overall": "$overall",
    "build_output_tail": """$output""",
    "errors": $errors
}
with open("$REPORT", "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PYEOF
}

# 检测项目类型（优先级：Rust > Go > Node > Python > 未知）
if [ -f "Cargo.toml" ]; then
  echo "[BuildVerifier] 检测到 Rust 项目，执行 cargo build --release"
  BUILD_OUTPUT=$(cargo build --release 2>&1) || {
    ERRORS=$(echo "$BUILD_OUTPUT" | grep -E "^error" | head -20 | python3 -c "
import sys, json
lines = sys.stdin.read().splitlines()
print(json.dumps(lines))
" || echo "[]")
    write_report "FAIL" "cargo" "$(echo "$BUILD_OUTPUT" | tail -30 | tr '\"' "'")" "$ERRORS"
    echo "[BuildVerifier] FAIL: 编译错误，详见 build-verifier-report.json"
    exit 1
  }
  write_report "PASS" "cargo" "$(echo "$BUILD_OUTPUT" | tail -5 | tr '\"' "'")" "[]"
  echo "[BuildVerifier] PASS: Rust 项目编译成功"

elif [ -f "go.mod" ]; then
  echo "[BuildVerifier] 检测到 Go 项目，执行 go build ./..."
  BUILD_OUTPUT=$(go build ./... 2>&1) || {
    ERRORS=$(echo "$BUILD_OUTPUT" | head -20 | python3 -c "
import sys, json
lines = sys.stdin.read().splitlines()
print(json.dumps(lines))
")
    write_report "FAIL" "go" "$(echo "$BUILD_OUTPUT" | tail -30 | tr '\"' "'")" "$ERRORS"
    echo "[BuildVerifier] FAIL: 编译错误，详见 build-verifier-report.json"
    exit 1
  }
  write_report "PASS" "go" "" "[]"
  echo "[BuildVerifier] PASS: Go 项目编译成功"

elif [ -f "package.json" ]; then
  # 检查是否有 build 脚本
  if python3 -c "import json; s=json.load(open('package.json')).get('scripts',{}); exit(0 if 'build' in s else 1)" 2>/dev/null; then
    echo "[BuildVerifier] 检测到 Node.js 项目（含 build 脚本），执行 npm run build"
    BUILD_OUTPUT=$(npm run build 2>&1) || {
      ERRORS=$(echo "$BUILD_OUTPUT" | grep -iE "error|Error" | head -20 | python3 -c "
import sys, json
lines = sys.stdin.read().splitlines()
print(json.dumps(lines))
" || echo "[]")
      write_report "FAIL" "npm" "$(echo "$BUILD_OUTPUT" | tail -30 | tr '\"' "'")" "$ERRORS"
      echo "[BuildVerifier] FAIL: 构建错误，详见 build-verifier-report.json"
      exit 1
    }
    write_report "PASS" "npm" "$(echo "$BUILD_OUTPUT" | tail -5 | tr '\"' "'")" "[]"
    echo "[BuildVerifier] PASS: Node.js 项目构建成功"
  else
    echo "[BuildVerifier] Node.js 项目无 build 脚本，跳过编译验证（PASS）"
    write_report "PASS" "npm-skip" "无 build 脚本，跳过" "[]"
  fi

elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || ls *.py 2>/dev/null | grep -q .; then
  echo "[BuildVerifier] 检测到 Python 项目，Python 无需编译验证（PASS）"
  write_report "PASS" "python-skip" "Python 动态语言，无需编译" "[]"

else
  echo "[BuildVerifier] 未识别的项目类型，跳过编译验证（PASS）"
  write_report "PASS" "unknown-skip" "未识别项目类型，跳过" "[]"
fi

exit 0
