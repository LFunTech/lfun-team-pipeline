#!/usr/bin/env bash
# build-verifier.sh — Phase 3.0b 编译验证 AutoStep
# 在所有 Builder merge 完成后、Phase 3.1 之前运行
# 两阶段验证：① 生产代码编译 ② 测试代码编译（--no-run / -run='^$' / tsc --noEmit）
# 支持：Rust (cargo) / Go (go) / Node.js+TypeScript (npm+tsc) / Python (无编译，直接 PASS)
# 输出：.pipeline/artifacts/build-verifier-report.json
# exit 0 = PASS, exit 1 = FAIL

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
REPORT="$PIPELINE_DIR/artifacts/build-verifier-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

write_report() {
  local overall="$1" tool="$2" output="$3" errors="$4" test_compile="$5" test_errors="$6"
  OVERALL="$overall" TOOL="$tool" BUILD_OUTPUT="$output" ERRORS="$errors" \
  TEST_COMPILE="$test_compile" TEST_ERRORS="$test_errors" \
  TIMESTAMP="$TIMESTAMP" REPORT="$REPORT" python3 - <<'PYEOF'
import json, os
data = {
    "autostep": "BuildVerifier",
    "timestamp": os.environ["TIMESTAMP"],
    "tool": os.environ["TOOL"],
    "overall": os.environ["OVERALL"],
    "build_output_tail": os.environ["BUILD_OUTPUT"],
    "errors": json.loads(os.environ["ERRORS"]),
    "test_compile": os.environ["TEST_COMPILE"],
    "test_compile_errors": json.loads(os.environ["TEST_ERRORS"])
}
with open(os.environ["REPORT"], "w") as f:
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
    write_report "FAIL" "cargo" "$(echo "$BUILD_OUTPUT" | tail -30 | tr '\"' "'")" "$ERRORS" "SKIP" "[]"
    echo "[BuildVerifier] FAIL: 生产编译错误，详见 build-verifier-report.json"
    exit 1
  }
  echo "[BuildVerifier] 生产编译 PASS，执行 cargo test --no-run（测试代码编译）"
  TEST_OUTPUT=$(cargo test --no-run 2>&1) || {
    TEST_ERRORS=$(echo "$TEST_OUTPUT" | grep -E "^error" | head -20 | python3 -c "
import sys, json
lines = sys.stdin.read().splitlines()
print(json.dumps(lines))
" || echo "[]")
    write_report "FAIL" "cargo" "$(echo "$BUILD_OUTPUT" | tail -5 | tr '\"' "'")" "[]" "FAIL" "$TEST_ERRORS"
    echo "[BuildVerifier] FAIL: 测试代码编译错误，详见 build-verifier-report.json"
    exit 1
  }
  write_report "PASS" "cargo" "$(echo "$BUILD_OUTPUT" | tail -5 | tr '\"' "'")" "[]" "PASS" "[]"
  echo "[BuildVerifier] PASS: Rust 项目生产+测试编译均通过"

elif [ -f "go.mod" ]; then
  echo "[BuildVerifier] 检测到 Go 项目，执行 go build ./..."
  BUILD_OUTPUT=$(go build ./... 2>&1) || {
    ERRORS=$(echo "$BUILD_OUTPUT" | head -20 | python3 -c "
import sys, json
lines = sys.stdin.read().splitlines()
print(json.dumps(lines))
")
    write_report "FAIL" "go" "$(echo "$BUILD_OUTPUT" | tail -30 | tr '\"' "'")" "$ERRORS" "SKIP" "[]"
    echo "[BuildVerifier] FAIL: 生产编译错误，详见 build-verifier-report.json"
    exit 1
  }
  echo "[BuildVerifier] 生产编译 PASS，执行 go test -run='^$' ./...（测试代码编译）"
  TEST_OUTPUT=$(go test -run='^$' ./... 2>&1) || {
    TEST_ERRORS=$(echo "$TEST_OUTPUT" | head -20 | python3 -c "
import sys, json
lines = sys.stdin.read().splitlines()
print(json.dumps(lines))
")
    write_report "FAIL" "go" "" "[]" "FAIL" "$TEST_ERRORS"
    echo "[BuildVerifier] FAIL: 测试代码编译错误，详见 build-verifier-report.json"
    exit 1
  }
  write_report "PASS" "go" "" "[]" "PASS" "[]"
  echo "[BuildVerifier] PASS: Go 项目生产+测试编译均通过"

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
      write_report "FAIL" "npm" "$(echo "$BUILD_OUTPUT" | tail -30 | tr '\"' "'")" "$ERRORS" "SKIP" "[]"
      echo "[BuildVerifier] FAIL: 构建错误，详见 build-verifier-report.json"
      exit 1
    }
    # TypeScript 项目：追加 tsc --noEmit 覆盖测试代码类型检查
    if [ -f "tsconfig.json" ]; then
      echo "[BuildVerifier] 检测到 TypeScript，执行 npx tsc --noEmit（测试代码类型检查）"
      TEST_OUTPUT=$(npx tsc --noEmit 2>&1) || {
        TEST_ERRORS=$(echo "$TEST_OUTPUT" | head -20 | python3 -c "
import sys, json
lines = sys.stdin.read().splitlines()
print(json.dumps(lines))
" || echo "[]")
        write_report "FAIL" "npm+tsc" "$(echo "$BUILD_OUTPUT" | tail -5 | tr '\"' "'")" "[]" "FAIL" "$TEST_ERRORS"
        echo "[BuildVerifier] FAIL: TypeScript 类型检查失败，详见 build-verifier-report.json"
        exit 1
      }
      write_report "PASS" "npm+tsc" "$(echo "$BUILD_OUTPUT" | tail -5 | tr '\"' "'")" "[]" "PASS" "[]"
      echo "[BuildVerifier] PASS: Node.js 项目构建+TypeScript 类型检查均通过"
    else
      write_report "PASS" "npm" "$(echo "$BUILD_OUTPUT" | tail -5 | tr '\"' "'")" "[]" "SKIP" "[]"
      echo "[BuildVerifier] PASS: Node.js 项目构建成功（无 TypeScript，跳过测试编译）"
    fi
  else
    echo "[BuildVerifier] Node.js 项目无 build 脚本，跳过编译验证（PASS）"
    write_report "PASS" "npm-skip" "无 build 脚本，跳过" "[]" "SKIP" "[]"
  fi

elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || ls *.py 2>/dev/null | grep -q .; then
  echo "[BuildVerifier] 检测到 Python 项目，Python 无需编译验证（PASS）"
  write_report "PASS" "python-skip" "Python 动态语言，无需编译" "[]" "SKIP" "[]"

else
  echo "[BuildVerifier] 未识别的项目类型，跳过编译验证（PASS）"
  write_report "PASS" "unknown-skip" "未识别项目类型，跳过" "[]" "SKIP" "[]"
fi

exit 0
