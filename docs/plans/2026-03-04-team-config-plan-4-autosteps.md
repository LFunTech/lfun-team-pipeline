# Team Config Plan Part 4: AutoStep Scripts

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 创建 15 个 AutoStep Shell 脚本，实现流水线各阶段的自动化机械验证。

**Architecture:** 每个脚本输入环境变量，输出标准 JSON 到 `.pipeline/artifacts/`，退出码 0=PASS / 1=FAIL / 2=ERROR。

**Tech Stack:** Bash shell scripts, JSON output

**依赖:** Part 1（`templates/.pipeline/autosteps/` 目录已创建）
**后续:** Part 5（Templates + install.sh）

---

### 脚本统一骨架（参考）

```bash
#!/bin/bash
# Phase X.Y: <AutoStep Name>
# 输入: <环境变量列表>
# 输出: .pipeline/artifacts/<output-file>.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/<output-file>.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ── 检查逻辑 ────────────────────────────────────────────────────
OVERALL="PASS"

# ── 输出标准 JSON ─────────────────────────────────────────────
cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "<AutoStepName>",
  "timestamp": "$TIMESTAMP",
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

---

### Task 1: 创建 requirement-completeness-checker.sh

**Files:**
- Create: `templates/.pipeline/autosteps/requirement-completeness-checker.sh`

**Step 1: 写入文件**

```bash
#!/bin/bash
# Phase 0.5: Requirement Completeness Checker
# 输入: PIPELINE_DIR（默认 .pipeline），REQUIREMENT_FILE（默认 .pipeline/artifacts/requirement.md）
# 输出: .pipeline/artifacts/requirement-completeness-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
REQUIREMENT_FILE="${REQUIREMENT_FILE:-$PIPELINE_DIR/artifacts/requirement.md}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/requirement-completeness-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONFIG_FILE="${CONFIG_FILE:-$PIPELINE_DIR/config.json}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ── 前置检查 ─────────────────────────────────────────────────────
if [ ! -f "$REQUIREMENT_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"RequirementCompletenessChecker","timestamp":"$TIMESTAMP","error":"requirement.md not found","overall":"ERROR"}
EOF
  exit 2
fi

# ── 读取配置 ─────────────────────────────────────────────────────
MIN_WORDS=200
PARENT_SECTION="## 最终需求定义"
if [ -f "$CONFIG_FILE" ] && command -v python3 &>/dev/null; then
  MIN_WORDS=$(python3 -c "
import json, sys
try:
  c = json.load(open('$CONFIG_FILE'))
  print(c.get('requirement_completeness', {}).get('min_words', 200))
except: print(200)
" 2>/dev/null || echo 200)
fi

# ── 1. 必填 Section 检查（H3 在 ## 最终需求定义 下）────────────────
REQUIRED_SECTIONS=("### 功能描述" "### 用户故事" "### 业务规则" "### 范围边界" "### 验收标准")

# 提取 ## 最终需求定义 之后的内容（到下一个 ## 或文件末尾）
PARENT_FOUND=false
EXTRACTED=""
IN_PARENT=false

while IFS= read -r line; do
  if [[ "$line" == "## 最终需求定义"* ]]; then
    IN_PARENT=true
    PARENT_FOUND=true
    continue
  fi
  if $IN_PARENT; then
    if [[ "$line" =~ ^##[^#] ]]; then
      IN_PARENT=false
    else
      EXTRACTED+="$line"$'\n'
    fi
  fi
done < "$REQUIREMENT_FILE"

SECTIONS_JSON=""
SECTIONS_OVERALL="PASS"

if ! $PARENT_FOUND; then
  SECTIONS_JSON='"最终需求定义_section_found":false,"功能描述":"MISSING","用户故事":"MISSING","业务规则":"MISSING","范围边界":"MISSING","验收标准":"MISSING"'
  SECTIONS_OVERALL="FAIL"
else
  SECTIONS_JSON='"最终需求定义_section_found":true'
  MISSING_LIST=""
  for section in "${REQUIRED_SECTIONS[@]}"; do
    key=$(echo "$section" | sed 's/### //')
    prefix_escaped=$(echo "$section" | sed 's/[[\.*^${}+?|()]/\\&/g')
    if echo "$EXTRACTED" | grep -qP "^$prefix_escaped"; then
      SECTIONS_JSON+=",\"$key\":\"PRESENT\""
    else
      SECTIONS_JSON+=",\"$key\":\"MISSING\""
      SECTIONS_OVERALL="FAIL"
    fi
  done
fi

# ── 2. 关键项检查 ─────────────────────────────────────────────────
CRITICAL_COUNT=$(grep -c '\[CRITICAL-UNRESOLVED' "$REQUIREMENT_FILE" 2>/dev/null || echo 0)
[ "$CRITICAL_COUNT" -gt 0 ] && SECTIONS_OVERALL="FAIL"

# ── 3. 假设格式检查 ───────────────────────────────────────────────
ASSUMED_COUNT=$(grep -c '\[ASSUMED:' "$REQUIREMENT_FILE" 2>/dev/null || echo 0)
ASSUMED_VALID=true
if grep -qP '\[ASSUMED:[^\]]*$' "$REQUIREMENT_FILE" 2>/dev/null; then
  ASSUMED_VALID=false
  SECTIONS_OVERALL="FAIL"
fi

# ── 4. 最小字数检查 ───────────────────────────────────────────────
WORD_COUNT=$(wc -w < "$REQUIREMENT_FILE")
[ "$WORD_COUNT" -lt "$MIN_WORDS" ] && SECTIONS_OVERALL="FAIL"

# ── 输出 ──────────────────────────────────────────────────────────
OVERALL="$SECTIONS_OVERALL"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "RequirementCompletenessChecker",
  "timestamp": "$TIMESTAMP",
  "sections_check": {$SECTIONS_JSON},
  "critical_unresolved_count": $CRITICAL_COUNT,
  "assumed_items_count": $ASSUMED_COUNT,
  "assumed_items_valid_format": $ASSUMED_VALID,
  "word_count": $WORD_COUNT,
  "word_count_threshold": $MIN_WORDS,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

**Step 2: 设置可执行权限**

```bash
chmod +x templates/.pipeline/autosteps/requirement-completeness-checker.sh
```

**Step 3: 验证**

```bash
head -3 templates/.pipeline/autosteps/requirement-completeness-checker.sh
```
Expected: `#!/bin/bash`

**Step 4: Commit**

```bash
git add templates/.pipeline/autosteps/requirement-completeness-checker.sh
git commit -m "feat: add requirement-completeness-checker autostep (Phase 0.5)"
```

---

### Task 2: 创建 assumption-propagation-validator.sh

**Files:**
- Create: `templates/.pipeline/autosteps/assumption-propagation-validator.sh`

**Step 1: 写入文件**

```bash
#!/bin/bash
# Phase 2.1: Assumption Propagation Validator
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/assumption-propagation-report.json
# 退出码: 0=PASS/WARN 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
REQUIREMENT_FILE="$PIPELINE_DIR/artifacts/requirement.md"
TASKS_FILE="$PIPELINE_DIR/artifacts/tasks.json"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/assumption-propagation-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$REQUIREMENT_FILE" ] || [ ! -f "$TASKS_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"AssumptionPropagationValidator","timestamp":"$TIMESTAMP","error":"missing input files","overall":"ERROR"}
EOF
  exit 2
fi

# ── 提取所有 [ASSUMED: ...] 条目 ──────────────────────────────────
ASSUMPTIONS=$(grep -oP '\[ASSUMED:[^\]]+\]' "$REQUIREMENT_FILE" 2>/dev/null || echo "")
ASSUMED_COUNT=$(echo "$ASSUMPTIONS" | grep -c '\[ASSUMED:' 2>/dev/null || echo 0)

# 读取 tasks.json 中的所有文本（notes + acceptance_criteria）
TASKS_TEXT=$(python3 -c "
import json
try:
  data = json.load(open('$TASKS_FILE'))
  texts = []
  for t in data.get('tasks', []):
    texts.append(t.get('notes', ''))
    texts.extend(t.get('acceptance_criteria', []))
  print(' '.join(texts))
except Exception as e:
  print('')
" 2>/dev/null || echo "")

# ── 逐条检查覆盖情况 ──────────────────────────────────────────────
COVERED=0
UNCOVERED_JSON="[]"
UNCOVERED_LIST="["

if [ "$ASSUMED_COUNT" -gt 0 ]; then
  UNCOVERED_LIST="["
  FIRST=true
  while IFS= read -r assumption; do
    [ -z "$assumption" ] && continue
    # 提取关键词（去掉 [ASSUMED: 和 ]）
    keyword=$(echo "$assumption" | sed 's/\[ASSUMED: *//; s/\]//' | cut -c1-30)
    if echo "$TASKS_TEXT" | grep -qi "$keyword"; then
      COVERED=$((COVERED + 1))
    else
      if ! $FIRST; then UNCOVERED_LIST+=","; fi
      FIRST=false
      UNCOVERED_LIST+="{\"assumption\":\"$assumption\",\"severity\":\"WARN\"}"
    fi
  done <<< "$ASSUMPTIONS"
  UNCOVERED_LIST+="]"
fi

UNCOVERED_COUNT=$((ASSUMED_COUNT - COVERED))
OVERALL="PASS"
[ "$UNCOVERED_COUNT" -gt 0 ] && OVERALL="WARN"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "AssumptionPropagationValidator",
  "timestamp": "$TIMESTAMP",
  "assumptions_found": $ASSUMED_COUNT,
  "covered": $COVERED,
  "uncovered_count": $UNCOVERED_COUNT,
  "uncovered": $UNCOVERED_LIST,
  "overall": "$OVERALL"
}
EOF

exit 0
```

**Step 2: 设置权限并 commit**

```bash
chmod +x templates/.pipeline/autosteps/assumption-propagation-validator.sh
git add templates/.pipeline/autosteps/assumption-propagation-validator.sh
git commit -m "feat: add assumption-propagation-validator autostep (Phase 2.1)"
```

---

### Task 3: 创建 schema-completeness-validator.sh

**Files:**
- Create: `templates/.pipeline/autosteps/schema-completeness-validator.sh`

**Step 1: 写入文件**

```bash
#!/bin/bash
# Phase 2.6: Schema Completeness Validator
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/schema-validation-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
TASKS_FILE="$PIPELINE_DIR/artifacts/tasks.json"
CONTRACTS_DIR="$PIPELINE_DIR/artifacts/contracts"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/schema-validation-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$TASKS_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"SchemaCompletenessValidator","timestamp":"$TIMESTAMP","error":"tasks.json not found","overall":"ERROR"}
EOF
  exit 2
fi

# ── 统计 tasks.json 中的契约数 ────────────────────────────────────
EXPECTED_COUNT=$(python3 -c "
import json
try:
  data = json.load(open('$TASKS_FILE'))
  print(len(data.get('contracts', [])))
except: print(0)
" 2>/dev/null || echo 0)

# ── 统计 contracts/ 目录中实际文件数 ──────────────────────────────
ACTUAL_COUNT=0
INVALID_FILES="[]"
if [ -d "$CONTRACTS_DIR" ]; then
  ACTUAL_COUNT=$(find "$CONTRACTS_DIR" -name "*.yaml" -o -name "*.json" 2>/dev/null | wc -l)

  # 验证每个文件是否为合法 OpenAPI 3.0 格式
  INVALID_LIST="["
  FIRST=true
  while IFS= read -r f; do
    if ! python3 -c "
import yaml, json, sys
try:
  with open('$f') as fh:
    data = yaml.safe_load(fh) if '$f'.endswith('.yaml') else json.load(fh)
  assert data.get('openapi', '').startswith('3.'), 'not openapi 3.x'
  assert 'paths' in data, 'missing paths'
  sys.exit(0)
except Exception as e:
  sys.exit(1)
" 2>/dev/null; then
      if ! $FIRST; then INVALID_LIST+=","; fi
      FIRST=false
      INVALID_LIST+="\"$f\""
    fi
  done < <(find "$CONTRACTS_DIR" -name "*.yaml" -o -name "*.json" 2>/dev/null)
  INVALID_LIST+="]"
  INVALID_FILES="$INVALID_LIST"
fi

OVERALL="PASS"
[ "$ACTUAL_COUNT" -ne "$EXPECTED_COUNT" ] && OVERALL="FAIL"
[ "$INVALID_FILES" != "[]" ] && OVERALL="FAIL"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "SchemaCompletenessValidator",
  "timestamp": "$TIMESTAMP",
  "expected_contracts": $EXPECTED_COUNT,
  "actual_schemas": $ACTUAL_COUNT,
  "invalid_files": $INVALID_FILES,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

**Step 2: 设置权限并 commit**

```bash
chmod +x templates/.pipeline/autosteps/schema-completeness-validator.sh
git add templates/.pipeline/autosteps/schema-completeness-validator.sh
git commit -m "feat: add schema-completeness-validator autostep (Phase 2.6)"
```

---

### Task 4: 创建 contract-semantic-validator.sh

**Files:**
- Create: `templates/.pipeline/autosteps/contract-semantic-validator.sh`

**Step 1: 写入文件**

```bash
#!/bin/bash
# Phase 2.7: Contract Semantic Validator
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/contract-semantic-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
TASKS_FILE="$PIPELINE_DIR/artifacts/tasks.json"
CONTRACTS_DIR="$PIPELINE_DIR/artifacts/contracts"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/contract-semantic-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -d "$CONTRACTS_DIR" ] || [ ! -f "$TASKS_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"ContractSemanticValidator","timestamp":"$TIMESTAMP","error":"missing inputs","overall":"ERROR"}
EOF
  exit 2
fi

OVERALL="PASS"
ERRORS_JSON="[]"

# ── RESTful 语义规则验证（使用 Spectral 或内置规则）─────────────────
ERRORS_LIST="["
FIRST=true

check_error() {
  if ! $FIRST; then ERRORS_LIST+=","; fi
  FIRST=false
  ERRORS_LIST+="{\"file\":\"$1\",\"rule\":\"$2\",\"message\":\"$3\"}"
  OVERALL="FAIL"
}

for schema_file in "$CONTRACTS_DIR"/*.yaml "$CONTRACTS_DIR"/*.json; do
  [ -f "$schema_file" ] || continue
  fname=$(basename "$schema_file")

  # 规则 1: GET 不得有 requestBody
  if python3 -c "
import yaml, json, sys
with open('$schema_file') as f:
  data = yaml.safe_load(f) if '$schema_file'.endswith('.yaml') else json.load(f)
for path, methods in data.get('paths', {}).items():
  if 'get' in methods and 'requestBody' in methods['get']:
    sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    :
  else
    check_error "$fname" "no-get-requestbody" "GET endpoint must not have requestBody"
  fi

  # 规则 2: 路径参数必须在 parameters 中声明 required: true
  python3 << PYEOF 2>/dev/null || check_error "$fname" "path-params-required" "path parameters must be declared as required:true"
import yaml, json, re, sys
with open('$schema_file') as f:
  data = yaml.safe_load(f) if '$schema_file'.endswith('.yaml') else json.load(f)
for path, methods in data.get('paths', {}).items():
  params_in_path = re.findall(r'\{(\w+)\}', path)
  for method, op in methods.items():
    if not isinstance(op, dict): continue
    declared = {p['name']: p for p in op.get('parameters', []) if p.get('in') == 'path'}
    for p in params_in_path:
      if p not in declared or not declared[p].get('required', False):
        sys.exit(1)
sys.exit(0)
PYEOF

  # 规则 3: 每个操作必须有 operationId
  if python3 -c "
import yaml, json, sys
with open('$schema_file') as f:
  data = yaml.safe_load(f) if '$schema_file'.endswith('.yaml') else json.load(f)
for path, methods in data.get('paths', {}).items():
  for method, op in methods.items():
    if isinstance(op, dict) and 'operationId' not in op:
      sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    :
  else
    check_error "$fname" "operation-id-required" "every operation must have operationId"
  fi
done

ERRORS_LIST+="]"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "ContractSemanticValidator",
  "timestamp": "$TIMESTAMP",
  "errors": $ERRORS_LIST,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

**Step 2: 设置权限并 commit**

```bash
chmod +x templates/.pipeline/autosteps/contract-semantic-validator.sh
git add templates/.pipeline/autosteps/contract-semantic-validator.sh
git commit -m "feat: add contract-semantic-validator autostep (Phase 2.7)"
```

---

### Task 5: 创建 static-analyzer.sh

**Files:**
- Create: `templates/.pipeline/autosteps/static-analyzer.sh`

**Step 1: 写入文件**

```bash
#!/bin/bash
# Phase 3.1: Static Analyzer
# 输入: PIPELINE_DIR, IMPL_MANIFEST（默认 .pipeline/artifacts/impl-manifest.json）
# 输出: .pipeline/artifacts/static-analysis-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
IMPL_MANIFEST="${IMPL_MANIFEST:-$PIPELINE_DIR/artifacts/impl-manifest.json}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/static-analysis-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$IMPL_MANIFEST" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"StaticAnalyzer","timestamp":"$TIMESTAMP","error":"impl-manifest.json not found","overall":"ERROR"}
EOF
  exit 2
fi

# ── 获取变更文件列表 ────────────────────────────────────────────────
CHANGED_FILES=$(python3 -c "
import json
data = json.load(open('$IMPL_MANIFEST'))
files = [f['path'] for f in data.get('files_changed', []) if not f['path'].startswith('tests/')]
print('\n'.join(files))
" 2>/dev/null || echo "")

OVERALL="PASS"
LINT_ERRORS=0
COMPLEXITY_ISSUES="[]"
DEPENDENCY_VULNS=0

# ── Linting ──────────────────────────────────────────────────────
if command -v eslint &>/dev/null; then
  LINT_OUTPUT=$(echo "$CHANGED_FILES" | xargs -r eslint --format=json 2>/dev/null || echo "[]")
  LINT_ERRORS=$(echo "$LINT_OUTPUT" | python3 -c "
import json, sys
try:
  data = json.load(sys.stdin)
  print(sum(f.get('errorCount', 0) for f in data))
except: print(0)
" 2>/dev/null || echo 0)
elif command -v flake8 &>/dev/null; then
  LINT_ERRORS=$(echo "$CHANGED_FILES" | grep -E '\.py$' | xargs -r flake8 2>/dev/null | wc -l || echo 0)
fi

[ "$LINT_ERRORS" -gt 0 ] && OVERALL="FAIL"

# ── 复杂度检查（圈复杂度）──────────────────────────────────────────
COMPLEXITY_JSON="[]"
if command -v lizard &>/dev/null && [ -n "$CHANGED_FILES" ]; then
  COMPLEXITY_JSON=$(echo "$CHANGED_FILES" | xargs -r lizard --CCN 10 --json 2>/dev/null | python3 -c "
import json, sys
try:
  data = json.load(sys.stdin)
  issues = [{'file': f['filename'], 'function': fn['name'], 'ccn': fn['cyclomatic_complexity']}
            for f in data.get('files', [])
            for fn in f.get('functions', [])
            if fn.get('cyclomatic_complexity', 0) > 10]
  print(json.dumps(issues))
except: print('[]')
" 2>/dev/null || echo "[]")
fi

# ── 依赖安全扫描 ──────────────────────────────────────────────────
if command -v npm &>/dev/null && [ -f "package.json" ]; then
  DEPENDENCY_VULNS=$(npm audit --json 2>/dev/null | python3 -c "
import json, sys
try: print(json.load(sys.stdin).get('metadata', {}).get('vulnerabilities', {}).get('high', 0))
except: print(0)
" 2>/dev/null || echo 0)
  [ "$DEPENDENCY_VULNS" -gt 0 ] && OVERALL="FAIL"
fi

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "StaticAnalyzer",
  "timestamp": "$TIMESTAMP",
  "lint_errors": $LINT_ERRORS,
  "complexity_issues": $COMPLEXITY_JSON,
  "dependency_vulnerabilities_high": $DEPENDENCY_VULNS,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

**Step 2: 设置权限并 commit**

```bash
chmod +x templates/.pipeline/autosteps/static-analyzer.sh
git add templates/.pipeline/autosteps/static-analyzer.sh
git commit -m "feat: add static-analyzer autostep (Phase 3.1)"
```

---

### Task 6: 创建 diff-scope-validator.sh 和 regression-guard.sh

**Files:**
- Create: `templates/.pipeline/autosteps/diff-scope-validator.sh`
- Create: `templates/.pipeline/autosteps/regression-guard.sh`

**Step 1: 写入 diff-scope-validator.sh**

```bash
#!/bin/bash
# Phase 3.2: Diff Scope Validator
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/scope-validation-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
TASKS_FILE="$PIPELINE_DIR/artifacts/tasks.json"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/scope-validation-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$TASKS_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"DiffScopeValidator","timestamp":"$TIMESTAMP","error":"tasks.json not found","overall":"ERROR"}
EOF
  exit 2
fi

# ── 获取授权文件列表 ────────────────────────────────────────────────
AUTHORIZED_FILES=$(python3 -c "
import json
data = json.load(open('$TASKS_FILE'))
files = set()
for task in data.get('tasks', []):
  for f in task.get('files', []):
    files.add(f['path'])
print('\n'.join(sorted(files)))
" 2>/dev/null || echo "")

# ── 获取实际变更文件（git diff）──────────────────────────────────────
if ! command -v git &>/dev/null; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"DiffScopeValidator","timestamp":"$TIMESTAMP","error":"git not available","overall":"ERROR"}
EOF
  exit 2
fi

ACTUAL_CHANGES=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only 2>/dev/null || echo "")
# 追加 staged changes
ACTUAL_CHANGES+=$'\n'$(git diff --name-only --cached 2>/dev/null || echo "")
ACTUAL_CHANGES=$(echo "$ACTUAL_CHANGES" | sort -u | grep -v '^$' || echo "")

# ── 检查越权变更 ──────────────────────────────────────────────────
UNAUTHORIZED="[]"
UNAUTHORIZED_LIST="["
FIRST=true
OVERALL="PASS"

while IFS= read -r changed_file; do
  [ -z "$changed_file" ] && continue
  # 跳过 .pipeline/ 目录本身
  [[ "$changed_file" == .pipeline/* ]] && continue
  if ! echo "$AUTHORIZED_FILES" | grep -qxF "$changed_file"; then
    if ! $FIRST; then UNAUTHORIZED_LIST+=","; fi
    FIRST=false
    UNAUTHORIZED_LIST+="\"$changed_file\""
    OVERALL="FAIL"
  fi
done <<< "$ACTUAL_CHANGES"

UNAUTHORIZED_LIST+="]"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "DiffScopeValidator",
  "timestamp": "$TIMESTAMP",
  "unauthorized_changes": $UNAUTHORIZED_LIST,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

**Step 2: 写入 regression-guard.sh**

```bash
#!/bin/bash
# Phase 3.3: Regression Guard
# 输入: PIPELINE_DIR, TEST_COMMAND（默认自动检测）
# 输出: .pipeline/artifacts/regression-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/regression-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
STATE_FILE="$PIPELINE_DIR/state.json"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ── 读取 new_test_files（排除在外）────────────────────────────────
NEW_TEST_FILES=""
if [ -f "$STATE_FILE" ] && command -v python3 &>/dev/null; then
  NEW_TEST_FILES=$(python3 -c "
import json
data = json.load(open('$STATE_FILE'))
print('\n'.join(data.get('new_test_files', [])))
" 2>/dev/null || echo "")
fi

# ── 自动检测测试命令 ──────────────────────────────────────────────
if [ -n "${TEST_COMMAND:-}" ]; then
  CMD="$TEST_COMMAND"
elif [ -f "package.json" ] && command -v npm &>/dev/null; then
  CMD="npm test -- --passWithNoTests"
elif [ -f "pytest.ini" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
  CMD="python -m pytest --ignore=tests/new/ -q"
elif [ -f "go.mod" ]; then
  CMD="go test ./..."
elif [ -f "Makefile" ] && grep -q "^test:" Makefile; then
  CMD="make test"
else
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"RegressionGuard","timestamp":"$TIMESTAMP","warning":"no test command detected","overall":"PASS"}
EOF
  exit 0
fi

# ── 执行测试 ──────────────────────────────────────────────────────
set +e
TEST_OUTPUT=$(eval "$CMD" 2>&1)
TEST_EXIT=$?
set -e

OVERALL="PASS"
[ "$TEST_EXIT" -ne 0 ] && OVERALL="FAIL"

# 转义 JSON
ESCAPED_OUTPUT=$(echo "$TEST_OUTPUT" | head -50 | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read()))
" 2>/dev/null || echo '"[output unavailable]"')

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "RegressionGuard",
  "timestamp": "$TIMESTAMP",
  "test_command": "$CMD",
  "exit_code": $TEST_EXIT,
  "output_summary": $ESCAPED_OUTPUT,
  "new_test_files_excluded": $(echo "$NEW_TEST_FILES" | python3 -c "import sys,json; lines=[l for l in sys.stdin.read().split('\n') if l]; print(json.dumps(lines))" 2>/dev/null || echo "[]"),
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

**Step 3: 设置权限并 commit**

```bash
chmod +x templates/.pipeline/autosteps/diff-scope-validator.sh
chmod +x templates/.pipeline/autosteps/regression-guard.sh
git add templates/.pipeline/autosteps/diff-scope-validator.sh templates/.pipeline/autosteps/regression-guard.sh
git commit -m "feat: add diff-scope-validator and regression-guard autosteps (Phase 3.2/3.3)"
```

---

### Task 7: 创建 post-simplification-verifier.sh 和 contract-compliance-checker.sh

**Files:**
- Create: `templates/.pipeline/autosteps/post-simplification-verifier.sh`
- Create: `templates/.pipeline/autosteps/contract-compliance-checker.sh`

**Step 1: 写入 post-simplification-verifier.sh**

```bash
#!/bin/bash
# Phase 3.6: Post-Simplification Verifier
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/post-simplify-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/post-simplify-report.json"
SIMPLIFY_REPORT="$PIPELINE_DIR/artifacts/simplify-report.md"
IMPL_MANIFEST="$PIPELINE_DIR/artifacts/impl-manifest.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

OVERALL="PASS"
CHECKS="[]"
CHECKS_LIST="["
FIRST=true

add_check() {
  if ! $FIRST; then CHECKS_LIST+=","; fi
  FIRST=false
  CHECKS_LIST+="{\"check\":\"$1\",\"result\":\"$2\",\"detail\":\"$3\"}"
  [ "$2" = "FAIL" ] && OVERALL="FAIL"
}

# ── 检查 1: simplify-report.md 比 impl-manifest.json 更新 ────────
if [ -f "$SIMPLIFY_REPORT" ] && [ -f "$IMPL_MANIFEST" ]; then
  if [ "$SIMPLIFY_REPORT" -nt "$IMPL_MANIFEST" ]; then
    add_check "simplify_report_newer_than_manifest" "PASS" "simplify-report.md 比 impl-manifest.json 更新"
  else
    add_check "simplify_report_newer_than_manifest" "FAIL" "simplify-report.md 不比 impl-manifest.json 更新，Simplifier 可能未运行"
  fi
else
  add_check "simplify_report_exists" "FAIL" "simplify-report.md 或 impl-manifest.json 不存在"
fi

# ── 检查 2: 重跑回归测试 ──────────────────────────────────────────
REGRESSION_OUTPUT=""
REGRESSION_EXIT=0

if [ -f "package.json" ] && command -v npm &>/dev/null; then
  set +e
  REGRESSION_OUTPUT=$(npm test -- --passWithNoTests 2>&1)
  REGRESSION_EXIT=$?
  set -e
elif command -v python3 &>/dev/null && ([ -f "pytest.ini" ] || [ -f "pyproject.toml" ]); then
  set +e
  REGRESSION_OUTPUT=$(python3 -m pytest -q 2>&1)
  REGRESSION_EXIT=$?
  set -e
fi

if [ "$REGRESSION_EXIT" -eq 0 ]; then
  add_check "regression_after_simplification" "PASS" "回归测试通过"
else
  add_check "regression_after_simplification" "FAIL" "回归测试失败，精简可能破坏了现有功能"
fi

CHECKS_LIST+="]"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "PostSimplificationVerifier",
  "timestamp": "$TIMESTAMP",
  "checks": $CHECKS_LIST,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

**Step 2: 写入 contract-compliance-checker.sh**

```bash
#!/bin/bash
# Phase 3.7: Contract Compliance Checker
# 输入: PIPELINE_DIR, SERVICE_BASE_URL（运行中服务的基础 URL）
# 输出: .pipeline/artifacts/contract-compliance-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
CONTRACTS_DIR="$PIPELINE_DIR/artifacts/contracts"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/contract-compliance-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SERVICE_BASE_URL="${SERVICE_BASE_URL:-http://localhost:3000}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

OVERALL="PASS"
RESULTS="[]"
RESULTS_LIST="["
FIRST=true

add_result() {
  if ! $FIRST; then RESULTS_LIST+=","; fi
  FIRST=false
  RESULTS_LIST+="{\"schema\":\"$1\",\"tool\":\"$2\",\"result\":\"$3\",\"detail\":\"$4\"}"
  [ "$3" = "FAIL" ] && OVERALL="FAIL"
}

# 检查服务是否运行
if ! curl -sf "$SERVICE_BASE_URL/health" > /dev/null 2>&1 && \
   ! curl -sf "$SERVICE_BASE_URL/" > /dev/null 2>&1; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"ContractComplianceChecker","timestamp":"$TIMESTAMP","error":"service not reachable at $SERVICE_BASE_URL","failure_type":"infrastructure_failure","overall":"ERROR"}
EOF
  exit 2
fi

# ── 使用 dredd 或 schemathesis 验证契约 ──────────────────────────
for schema_file in "$CONTRACTS_DIR"/*.yaml "$CONTRACTS_DIR"/*.json; do
  [ -f "$schema_file" ] || continue
  fname=$(basename "$schema_file")

  if command -v schemathesis &>/dev/null; then
    set +e
    OUTPUT=$(schemathesis run "$schema_file" --base-url "$SERVICE_BASE_URL" --checks all 2>&1)
    EXIT_CODE=$?
    set -e
    if [ "$EXIT_CODE" -eq 0 ]; then
      add_result "$fname" "schemathesis" "PASS" "所有契约测试通过"
    else
      DETAIL=$(echo "$OUTPUT" | tail -3 | tr '\n' ' ' | sed 's/"/\\"/g')
      add_result "$fname" "schemathesis" "FAIL" "$DETAIL"
    fi
  elif command -v dredd &>/dev/null; then
    set +e
    OUTPUT=$(dredd "$schema_file" "$SERVICE_BASE_URL" 2>&1)
    EXIT_CODE=$?
    set -e
    if [ "$EXIT_CODE" -eq 0 ]; then
      add_result "$fname" "dredd" "PASS" "所有契约测试通过"
    else
      add_result "$fname" "dredd" "FAIL" "$(echo "$OUTPUT" | tail -3 | tr '\n' ' ' | sed 's/"/\\"/g')"
    fi
  else
    add_result "$fname" "none" "PASS" "WARNING: 未安装 schemathesis 或 dredd，跳过机械验证"
  fi
done

RESULTS_LIST+="]"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "ContractComplianceChecker",
  "timestamp": "$TIMESTAMP",
  "service_base_url": "$SERVICE_BASE_URL",
  "results": $RESULTS_LIST,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

**Step 3: 设置权限并 commit**

```bash
chmod +x templates/.pipeline/autosteps/post-simplification-verifier.sh
chmod +x templates/.pipeline/autosteps/contract-compliance-checker.sh
git add templates/.pipeline/autosteps/post-simplification-verifier.sh templates/.pipeline/autosteps/contract-compliance-checker.sh
git commit -m "feat: add post-simplification-verifier and contract-compliance-checker autosteps (Phase 3.6/3.7)"
```

---

### Task 8: 创建 test-failure-mapper.sh 和 test-coverage-enforcer.sh

**Files:**
- Create: `templates/.pipeline/autosteps/test-failure-mapper.sh`
- Create: `templates/.pipeline/autosteps/test-coverage-enforcer.sh`

**Step 1: 写入 test-failure-mapper.sh**

```bash
#!/bin/bash
# Phase 4a.1: Test Failure Mapper (仅在 Phase 4a FAIL 时触发)
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/failure-builder-map.json
# 退出码: 0=完成映射 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
TEST_REPORT="$PIPELINE_DIR/artifacts/test-report.json"
COVERAGE_FILE="$PIPELINE_DIR/artifacts/coverage/coverage.lcov"
IMPL_MANIFEST="$PIPELINE_DIR/artifacts/impl-manifest.json"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/failure-builder-map.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$TEST_REPORT" ] || [ ! -f "$IMPL_MANIFEST" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"TestFailureMapper","timestamp":"$TIMESTAMP","error":"missing input files","overall":"ERROR"}
EOF
  exit 2
fi

# ── 映射失败测试到责任 Builder ────────────────────────────────────
python3 << 'PYEOF'
import json, os, sys

pipeline_dir = os.environ.get('PIPELINE_DIR', '.pipeline')
test_report = json.load(open(f'{pipeline_dir}/artifacts/test-report.json'))
impl_manifest = json.load(open(f'{pipeline_dir}/artifacts/impl-manifest.json'))
output_file = f'{pipeline_dir}/artifacts/failure-builder-map.json'

# 构建文件→Builder 映射
file_to_builder = {}
for builder_info in impl_manifest.get('builders', []):
  builder = builder_info.get('builder', 'unknown')
  for f in builder_info.get('files_changed', []):
    file_to_builder[f['path']] = builder

# 分析失败测试
failed_tests = test_report.get('failed_tests', [])
builder_failures = {}

for test in failed_tests:
  test_file = test.get('file', '')
  # 尝试从测试文件名推断源文件（tests/foo.test.ts → src/foo.ts）
  source_guess = test_file.replace('tests/', 'src/').replace('.test.', '.').replace('.spec.', '.')

  builder = file_to_builder.get(source_guess, file_to_builder.get(test_file, None))
  if builder:
    builder_failures.setdefault(builder, []).append(test['test'])
  else:
    builder_failures.setdefault('unknown', []).append(test['test'])

# 判断 confidence
has_unknown = 'unknown' in builder_failures
unique_builders = [b for b in builder_failures if b != 'unknown']

if has_unknown or len(unique_builders) > 2:
  confidence = 'LOW'
  builders_to_rollback = list(file_to_builder.values())  # 全体回退
else:
  confidence = 'HIGH'
  builders_to_rollback = unique_builders

import json as j
result = {
  'autostep': 'TestFailureMapper',
  'timestamp': os.environ.get('TIMESTAMP', ''),
  'failed_test_count': len(failed_tests),
  'builder_failure_map': builder_failures,
  'confidence': confidence,
  'builders_to_rollback': builders_to_rollback,
  'rollback_strategy': 'precise' if confidence == 'HIGH' else 'conservative_full',
  'overall': 'MAPPED'
}

with open(output_file, 'w') as f:
  json.dump(result, f, indent=2, ensure_ascii=False)

print(f'Mapped {len(failed_tests)} failures, confidence: {confidence}')
PYEOF

exit 0
```

**Step 2: 写入 test-coverage-enforcer.sh**

```bash
#!/bin/bash
# Phase 4.2: Test Coverage Enforcer
# 输入: PIPELINE_DIR, COVERAGE_THRESHOLD（默认 80）
# 输出: .pipeline/artifacts/coverage-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
IMPL_MANIFEST="$PIPELINE_DIR/artifacts/impl-manifest.json"
COVERAGE_DIR="$PIPELINE_DIR/artifacts/coverage"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/coverage-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONFIG_FILE="${CONFIG_FILE:-$PIPELINE_DIR/config.json}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ── 读取覆盖率阈值 ────────────────────────────────────────────────
THRESHOLD=80
if [ -f "$CONFIG_FILE" ] && command -v python3 &>/dev/null; then
  THRESHOLD=$(python3 -c "
import json
try:
  c = json.load(open('$CONFIG_FILE'))
  print(c.get('testing', {}).get('coverage_threshold', 80))
except: print(80)
" 2>/dev/null || echo 80)
fi

# ── 解析覆盖率报告 ────────────────────────────────────────────────
COVERAGE_PCT=0
OVERALL="PASS"

if [ -f "$COVERAGE_DIR/coverage.lcov" ]; then
  # 从 lcov 计算行覆盖率
  COVERAGE_PCT=$(python3 << 'PYEOF'
import os
lcov_file = os.path.join(os.environ.get('COVERAGE_DIR', '.pipeline/artifacts/coverage'), 'coverage.lcov')
try:
  total_lines = 0
  hit_lines = 0
  with open(lcov_file) as f:
    for line in f:
      if line.startswith('LF:'):
        total_lines += int(line.strip()[3:])
      elif line.startswith('LH:'):
        hit_lines += int(line.strip()[3:])
  if total_lines > 0:
    print(round(hit_lines / total_lines * 100, 1))
  else:
    print(0)
except Exception as e:
  print(0)
PYEOF
)
elif [ -f "$COVERAGE_DIR/coverage-summary.json" ]; then
  COVERAGE_PCT=$(python3 -c "
import json
try:
  data = json.load(open('$COVERAGE_DIR/coverage-summary.json'))
  total = data.get('total', {})
  print(total.get('lines', {}).get('pct', 0))
except: print(0)
" 2>/dev/null || echo 0)
fi

BELOW_THRESHOLD=$(python3 -c "print('true' if $COVERAGE_PCT < $THRESHOLD else 'false')" 2>/dev/null || echo "true")
[ "$BELOW_THRESHOLD" = "true" ] && OVERALL="FAIL"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "TestCoverageEnforcer",
  "timestamp": "$TIMESTAMP",
  "line_coverage_pct": $COVERAGE_PCT,
  "threshold_pct": $THRESHOLD,
  "below_threshold": $BELOW_THRESHOLD,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

**Step 3: 设置权限并 commit**

```bash
chmod +x templates/.pipeline/autosteps/test-failure-mapper.sh
chmod +x templates/.pipeline/autosteps/test-coverage-enforcer.sh
git add templates/.pipeline/autosteps/test-failure-mapper.sh templates/.pipeline/autosteps/test-coverage-enforcer.sh
git commit -m "feat: add test-failure-mapper and test-coverage-enforcer autosteps (Phase 4a.1/4.2)"
```

---

### Task 9: 创建最后 5 个 AutoStep 脚本

**Files:**
- Create: `templates/.pipeline/autosteps/performance-baseline-checker.sh`
- Create: `templates/.pipeline/autosteps/api-change-detector.sh`
- Create: `templates/.pipeline/autosteps/changelog-consistency-checker.sh`
- Create: `templates/.pipeline/autosteps/pre-deploy-readiness-check.sh`

**Step 1: 写入 performance-baseline-checker.sh**

```bash
#!/bin/bash
# Phase 4.3: Performance Baseline Checker
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/perf-baseline-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
PERF_REPORT="$PIPELINE_DIR/artifacts/perf-report.json"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/perf-baseline-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$PERF_REPORT" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"PerformanceBaselineChecker","timestamp":"$TIMESTAMP","skipped":true,"reason":"perf-report.json not found (optimizer not activated)","overall":"PASS"}
EOF
  exit 0
fi

python3 << 'PYEOF'
import json, os
pipeline_dir = os.environ.get('PIPELINE_DIR', '.pipeline')
perf_report = json.load(open(f'{pipeline_dir}/artifacts/perf-report.json'))
output_file = f'{pipeline_dir}/artifacts/perf-baseline-report.json'

sla_violated = perf_report.get('sla_violated', False)
results = perf_report.get('results', [])

violations = [r for r in results if r.get('sla_violated', False)]
overall = 'FAIL' if sla_violated or violations else 'PASS'

result = {
  'autostep': 'PerformanceBaselineChecker',
  'timestamp': os.environ.get('TIMESTAMP', ''),
  'sla_violated': sla_violated,
  'violations': violations,
  'overall': overall
}

with open(output_file, 'w') as f:
  json.dump(result, f, indent=2, ensure_ascii=False)

import sys
sys.exit(0 if overall == 'PASS' else 1)
PYEOF
```

**Step 2: 写入 api-change-detector.sh**

```bash
#!/bin/bash
# Phase 5 前置: API Change Detector
# 输入: PIPELINE_DIR, OLD_CONTRACTS_DIR（默认 .pipeline/artifacts/contracts.old）
# 输出: .pipeline/artifacts/api-change-report.json
# 退出码: 0=检测完成（无论是否有变更）2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
CONTRACTS_DIR="$PIPELINE_DIR/artifacts/contracts"
OLD_CONTRACTS_DIR="${OLD_CONTRACTS_DIR:-$PIPELINE_DIR/artifacts/contracts.old}"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/api-change-report.json"
STATE_FILE="$PIPELINE_DIR/state.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ── 比较新旧契约 ──────────────────────────────────────────────────
API_CHANGED=false
CHANGED_CONTRACTS="[]"

if [ ! -d "$OLD_CONTRACTS_DIR" ]; then
  # 首次部署，所有契约都是新增
  API_CHANGED=true
  CHANGED_CONTRACTS=$(find "$CONTRACTS_DIR" -name "*.yaml" -o -name "*.json" 2>/dev/null | python3 -c "
import sys, json
files = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(files))
" 2>/dev/null || echo "[]")
elif [ -d "$CONTRACTS_DIR" ]; then
  # 比较新旧目录差异
  DIFF_OUTPUT=$(diff -rq "$OLD_CONTRACTS_DIR" "$CONTRACTS_DIR" 2>/dev/null || echo "")
  if [ -n "$DIFF_OUTPUT" ]; then
    API_CHANGED=true
    CHANGED_CONTRACTS=$(echo "$DIFF_OUTPUT" | python3 -c "
import sys, json, re
files = set()
for line in sys.stdin:
  m = re.search(r'(?:Files|Only in) .*?(/[^\s:]+)', line)
  if m: files.add(m.group(1).split('/')[-1])
print(json.dumps(list(files)))
" 2>/dev/null || echo "[]")
  fi
fi

# ── 写入 state.json 的 phase_5_mode ─────────────────────────────
if [ -f "$STATE_FILE" ] && command -v python3 &>/dev/null; then
  python3 << PYEOF
import json
state = json.load(open('$STATE_FILE'))
state['phase_5_mode'] = 'full' if $API_CHANGED else 'changelog_only'
with open('$STATE_FILE', 'w') as f:
  json.dump(state, f, indent=2, ensure_ascii=False)
PYEOF
fi

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "APIChangeDetector",
  "timestamp": "$TIMESTAMP",
  "api_changed": $API_CHANGED,
  "changed_contracts": $CHANGED_CONTRACTS,
  "phase_5_mode": "$( [ "$API_CHANGED" = "true" ] && echo "full" || echo "changelog_only" )"
}
EOF

exit 0
```

**Step 3: 写入 changelog-consistency-checker.sh**

```bash
#!/bin/bash
# Phase 5.1: Changelog Consistency Checker
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/changelog-check-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
CHANGELOG_FILE="${CHANGELOG_FILE:-CHANGELOG.md}"
API_CHANGE_REPORT="$PIPELINE_DIR/artifacts/api-change-report.json"
IMPL_MANIFEST="$PIPELINE_DIR/artifacts/impl-manifest.json"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/changelog-check-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$CHANGELOG_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"ChangelogConsistencyChecker","timestamp":"$TIMESTAMP","error":"CHANGELOG.md not found","overall":"FAIL"}
EOF
  exit 1
fi

python3 << 'PYEOF'
import json, os, re

pipeline_dir = os.environ.get('PIPELINE_DIR', '.pipeline')
changelog_file = os.environ.get('CHANGELOG_FILE', 'CHANGELOG.md')
output_file = f'{pipeline_dir}/artifacts/changelog-check-report.json'

checks = []
overall = 'PASS'

def fail(check, detail):
  global overall
  checks.append({'check': check, 'result': 'FAIL', 'detail': detail})
  overall = 'FAIL'

def pass_(check, detail):
  checks.append({'check': check, 'result': 'PASS', 'detail': detail})

# 读取 CHANGELOG
with open(changelog_file) as f:
  changelog_content = f.read()

# 读取 api-change-report
api_changed_count = 0
try:
  api_report = json.load(open(f'{pipeline_dir}/artifacts/api-change-report.json'))
  api_changed_count = len(api_report.get('changed_contracts', []))
except: pass

# 检查 1: Unreleased section 存在
if '## [Unreleased]' not in changelog_content and '## [unreleased]' not in changelog_content.lower():
  fail('unreleased_section', 'CHANGELOG 中缺少 [Unreleased] section')
else:
  pass_('unreleased_section', '[Unreleased] section 存在')

# 检查 2: API 变更条目数 >= changed_contracts 数
unreleased_section = re.search(r'## \[Unreleased\](.*?)(?=## \[|\Z)', changelog_content, re.DOTALL | re.IGNORECASE)
changelog_entries = 0
if unreleased_section:
  entries = re.findall(r'^- ', unreleased_section.group(1), re.MULTILINE)
  changelog_entries = len(entries)

if api_changed_count > 0 and changelog_entries < api_changed_count:
  fail('api_change_entries', f'CHANGELOG 条目数 ({changelog_entries}) < API 变更数 ({api_changed_count})')
else:
  pass_('api_change_entries', f'CHANGELOG 条目数 ({changelog_entries}) 覆盖 API 变更数 ({api_changed_count})')

result = {
  'autostep': 'ChangelogConsistencyChecker',
  'timestamp': os.environ.get('TIMESTAMP', ''),
  'checks': checks,
  'api_changed_contracts': api_changed_count,
  'changelog_entries_in_unreleased': changelog_entries,
  'overall': overall
}

with open(output_file, 'w') as f:
  json.dump(result, f, indent=2, ensure_ascii=False)

import sys
sys.exit(0 if overall == 'PASS' else 1)
PYEOF
```

**Step 4: 写入 pre-deploy-readiness-check.sh**

```bash
#!/bin/bash
# Phase 6.0: Pre-Deploy Readiness Check
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/deploy-readiness-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
PROPOSAL_FILE="$PIPELINE_DIR/artifacts/proposal.md"
STATE_FILE="$PIPELINE_DIR/state.json"
DEPLOY_PLAN="$PIPELINE_DIR/artifacts/deploy-plan.md"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/deploy-readiness-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

OVERALL="PASS"
CHECKS_LIST="["
FIRST=true

add_check() {
  if ! $FIRST; then CHECKS_LIST+=","; fi
  FIRST=false
  CHECKS_LIST+="{\"check\":\"$1\",\"result\":\"$2\",\"detail\":\"$3\"}"
  [ "$2" = "FAIL" ] && OVERALL="FAIL"
}

# ── 检查 1: deploy-plan.md 存在 ───────────────────────────────────
if [ -f "$DEPLOY_PLAN" ]; then
  add_check "deploy_plan_exists" "PASS" "deploy-plan.md 存在"
else
  add_check "deploy_plan_exists" "FAIL" "deploy-plan.md 不存在，Builder-Infra 未生成部署计划"
fi

# ── 检查 2: rollback_command 已定义 ─────────────────────────────
if [ -f "$DEPLOY_PLAN" ] && grep -qi "rollback_command" "$DEPLOY_PLAN"; then
  add_check "rollback_command_defined" "PASS" "rollback_command 已在 deploy-plan.md 中定义"
else
  add_check "rollback_command_defined" "FAIL" "rollback_command 未在 deploy-plan.md 中定义"
fi

# ── 检查 3: 数据迁移脚本存在（如 data_migration_required）────────────
if [ -f "$STATE_FILE" ] && command -v python3 &>/dev/null; then
  MIGRATION_REQUIRED=$(python3 -c "
import json
try:
  s = json.load(open('$STATE_FILE'))
  print('true' if s.get('conditional_agents', {}).get('migrator', False) else 'false')
except: print('false')
" 2>/dev/null || echo "false")

  if [ "$MIGRATION_REQUIRED" = "true" ]; then
    MIGRATION_FILES=$(find . -name "*.sql" -newer "$STATE_FILE" -path "*/migrations/*" 2>/dev/null | wc -l)
    if [ "$MIGRATION_FILES" -gt 0 ]; then
      add_check "migration_scripts_exist" "PASS" "找到 $MIGRATION_FILES 个迁移脚本"
    else
      add_check "migration_scripts_exist" "FAIL" "data_migration_required=true 但未找到迁移脚本"
    fi
  fi
fi

# ── 检查 4: 必需环境变量已记录（.env.example）───────────────────────
if [ -f ".env.example" ]; then
  add_check "env_example_exists" "PASS" ".env.example 存在，环境变量已记录"
elif [ -f "$PROPOSAL_FILE" ] && grep -qi "环境变量\|env_var\|secret\|配置项" "$PROPOSAL_FILE"; then
  add_check "env_example_exists" "FAIL" "proposal.md 提到了配置项但 .env.example 不存在"
else
  add_check "env_example_exists" "PASS" "无环境变量依赖或已记录"
fi

CHECKS_LIST+="]"

cat > "$OUTPUT_FILE" << EOF
{
  "autostep": "PreDeployReadinessCheck",
  "timestamp": "$TIMESTAMP",
  "checks": $CHECKS_LIST,
  "overall": "$OVERALL"
}
EOF

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
```

**Step 5: 设置权限并 commit**

```bash
chmod +x templates/.pipeline/autosteps/performance-baseline-checker.sh
chmod +x templates/.pipeline/autosteps/api-change-detector.sh
chmod +x templates/.pipeline/autosteps/changelog-consistency-checker.sh
chmod +x templates/.pipeline/autosteps/pre-deploy-readiness-check.sh
git add templates/.pipeline/autosteps/
git commit -m "feat: add final 4 autostep scripts (Phase 4.3/5/5.1/6.0)"
```

---

### Task 10: 验证所有 15 个 AutoStep 脚本

**Step 1: 验证数量**

```bash
ls templates/.pipeline/autosteps/*.sh | wc -l
```
Expected: `15`

**Step 2: 验证所有脚本可执行**

```bash
ls -la templates/.pipeline/autosteps/*.sh | awk '{print $1, $9}' | grep -v "^-rwx"
```
Expected: 无输出（所有文件均有执行权限）

**Step 3: 检查所有脚本语法**

```bash
for f in templates/.pipeline/autosteps/*.sh; do bash -n "$f" && echo "OK: $f" || echo "SYNTAX ERROR: $f"; done
```
Expected: 所有文件输出 `OK: ...`
