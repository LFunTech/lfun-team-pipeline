# Pipeline Bug Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复流水线 v6 在完整执行 demo 过程中发现的所有 Bug，涵盖 AutoStep 脚本、新增合并工具、Orchestrator 提示词、Builder/Formalizer/Documenter agent 提示词。

**Architecture:** 按文件纵向切割——每个文件的所有改动一次完成后验证，再进入下一文件。脚本 Bug 修复（Section 1）→ 新增 AutoStep（Section 2）→ Orchestrator 提示词（Section 3）→ Agent 提示词（Section 4）。

**Tech Stack:** Bash（AutoStep 脚本）、Python3（嵌入脚本）、Markdown（agent 提示词）

---

## 背景说明

所有文件均在 `templates/` 或 `agents/` 下，是流水线的**模板/提示词**，不是可执行项目代码。
"验证"手段是直接运行脚本（传入构造好的 fixtures）或肉眼检查 diff。

`set -euo pipefail` + `[ cond ] && VAR="FAIL"` 的 Bug 根因：
函数体内该表达式当 cond 为 false 时以 exit 1 返回，调用方的 set -e 捕获后终止脚本。
修复方式：在表达式末尾追加 `|| true`，使函数始终以 0 退出。

---

## Task 1: 修复 requirement-completeness-checker.sh

**Files:**
- Modify: `templates/.pipeline/autosteps/requirement-completeness-checker.sh:76,82`

**Step 1: 确认 Bug 位置**

```bash
grep -n '&& SECTIONS_OVERALL' \
  templates/.pipeline/autosteps/requirement-completeness-checker.sh
```

Expected：输出第 76 行和第 82 行。

**Step 2: 应用修复**

在第 76 行末尾追加 `|| true`：
```bash
# 修复前
[ "$CRITICAL_COUNT" -gt 0 ] && SECTIONS_OVERALL="FAIL"
# 修复后
[ "$CRITICAL_COUNT" -gt 0 ] && SECTIONS_OVERALL="FAIL" || true
```

在第 82 行末尾追加 `|| true`：
```bash
# 修复前
[ "$WORD_COUNT" -lt "$MIN_WORDS" ] && SECTIONS_OVERALL="FAIL"
# 修复后
[ "$WORD_COUNT" -lt "$MIN_WORDS" ] && SECTIONS_OVERALL="FAIL" || true
```

**Step 3: 验证修复**

```bash
# 构造最小 fixture：requirement.md 不含所需章节（会触发 SECTIONS_OVERALL=FAIL 路径）
mkdir -p /tmp/fix-test/.pipeline/artifacts
echo "hello world" > /tmp/fix-test/.pipeline/artifacts/requirement.md
PIPELINE_DIR=/tmp/fix-test/.pipeline \
REQUIREMENT_FILE=/tmp/fix-test/.pipeline/artifacts/requirement.md \
  bash templates/.pipeline/autosteps/requirement-completeness-checker.sh
echo "Exit: $?"
```

Expected：脚本正常运行到结束（不因 set -e 中途退出），exit code 1（FAIL，符合预期）。

**Step 4: Commit**

```bash
git add templates/.pipeline/autosteps/requirement-completeness-checker.sh
git commit -m "fix: add || true to set-e-safe conditions in requirement-completeness-checker"
```

---

## Task 2: 修复 static-analyzer.sh

**Files:**
- Modify: `templates/.pipeline/autosteps/static-analyzer.sh:43,46,55`

**Step 1: 确认 Bug 位置**

```bash
grep -n '&& OVERALL' templates/.pipeline/autosteps/static-analyzer.sh
```

Expected：输出第 43、46、55 行。

**Step 2: 应用修复**

三处均追加 `|| true`：
```bash
# 第 43 行（eslint 分支）
[ "$LINT_ERRORS" -gt 0 ] && OVERALL="FAIL" || true
# 第 46 行（flake8 分支）
[ "$LINT_ERRORS" -gt 0 ] && OVERALL="FAIL" || true
# 第 55 行（npm audit 分支）
[ "$DEPENDENCY_VULNS" -gt 0 ] && OVERALL="FAIL" || true
```

**Step 3: 验证修复**

```bash
mkdir -p /tmp/fix-test-sa/.pipeline/artifacts
# 构造 impl-manifest.json（无 changed files，触发工具缺失分支）
echo '{"files_changed":[]}' \
  > /tmp/fix-test-sa/.pipeline/artifacts/impl-manifest.json
PIPELINE_DIR=/tmp/fix-test-sa/.pipeline \
  bash templates/.pipeline/autosteps/static-analyzer.sh
echo "Exit: $?"
```

Expected：正常完成，exit 0 或 1（不中途崩溃）。

**Step 4: Commit**

```bash
git add templates/.pipeline/autosteps/static-analyzer.sh
git commit -m "fix: add || true to set-e-safe conditions in static-analyzer"
```

---

## Task 3: 修复 assumption-propagation-validator.sh

**Files:**
- Modify: `templates/.pipeline/autosteps/assumption-propagation-validator.sh:60`

**Step 1: 确认 Bug 位置**

```bash
grep -n '&& OVERALL' \
  templates/.pipeline/autosteps/assumption-propagation-validator.sh
```

Expected：输出第 60 行。

**Step 2: 应用修复**

```bash
# 修复前
[ "$UNCOVERED_COUNT" -gt 0 ] && OVERALL="WARN"
# 修复后
[ "$UNCOVERED_COUNT" -gt 0 ] && OVERALL="WARN" || true
```

**Step 3: 验证修复**

```bash
mkdir -p /tmp/fix-test-apv/.pipeline/artifacts
# requirement.md 含 ASSUMED 标记但 tasks.json 不覆盖它
cat > /tmp/fix-test-apv/.pipeline/artifacts/requirement.md << 'EOF'
[ASSUMED: SQLite 足够满足并发需求]
EOF
echo '{"tasks":[]}' \
  > /tmp/fix-test-apv/.pipeline/artifacts/tasks.json
PIPELINE_DIR=/tmp/fix-test-apv/.pipeline \
  bash templates/.pipeline/autosteps/assumption-propagation-validator.sh
echo "Exit: $?"
```

Expected：正常完成，exit 0（WARN 不导致脚本退出）。

**Step 4: Commit**

```bash
git add templates/.pipeline/autosteps/assumption-propagation-validator.sh
git commit -m "fix: add || true to set-e-safe condition in assumption-propagation-validator"
```

---

## Task 4: 修复 regression-guard.sh

**Files:**
- Modify: `templates/.pipeline/autosteps/regression-guard.sh:46`

**Step 1: 确认 Bug 位置**

```bash
grep -n '&& OVERALL' templates/.pipeline/autosteps/regression-guard.sh
```

Expected：输出第 46 行。

**Step 2: 应用修复**

```bash
# 修复前
[ "$TEST_EXIT" -ne 0 ] && OVERALL="FAIL"
# 修复后
[ "$TEST_EXIT" -ne 0 ] && OVERALL="FAIL" || true
```

**Step 3: 验证修复**

```bash
mkdir -p /tmp/fix-test-rg/.pipeline/artifacts
# 使用不存在的测试命令触发 TEST_EXIT≠0 路径
PIPELINE_DIR=/tmp/fix-test-rg/.pipeline \
TEST_COMMAND="exit 1" \
  bash templates/.pipeline/autosteps/regression-guard.sh
echo "Exit: $?"
```

Expected：正常完成，exit 1（FAIL，不中途崩溃）。

**Step 4: Commit**

```bash
git add templates/.pipeline/autosteps/regression-guard.sh
git commit -m "fix: add || true to set-e-safe condition in regression-guard"
```

---

## Task 5: 修复 schema-completeness-validator.sh

**Files:**
- Modify: `templates/.pipeline/autosteps/schema-completeness-validator.sh:64`

**Step 1: 确认 Bug 位置**

```bash
grep -n '&& OVERALL' \
  templates/.pipeline/autosteps/schema-completeness-validator.sh
```

Expected：输出第 64 行（链式 `[ ... ] && [ ... ] && OVERALL="FAIL"`）。

**Step 2: 应用修复**

```bash
# 修复前
[ "$EXPECTED_COUNT" -ge 0 ] && [ "$ACTUAL_COUNT" -ne "$EXPECTED_COUNT" ] && OVERALL="FAIL"
# 修复后
[ "$EXPECTED_COUNT" -ge 0 ] && [ "$ACTUAL_COUNT" -ne "$EXPECTED_COUNT" ] && OVERALL="FAIL" || true
```

**Step 3: 验证修复**

```bash
mkdir -p /tmp/fix-test-scv/.pipeline/artifacts
# tasks.json 声明 contracts: [] (expected=0)，但 contracts/ 目录不存在（actual=0）
echo '{"contracts":[]}' > /tmp/fix-test-scv/.pipeline/artifacts/tasks.json
PIPELINE_DIR=/tmp/fix-test-scv/.pipeline \
  bash templates/.pipeline/autosteps/schema-completeness-validator.sh
echo "Exit: $?"
```

Expected：正常完成，exit 0（expected=actual=0，PASS）。

**Step 4: Commit**

```bash
git add templates/.pipeline/autosteps/schema-completeness-validator.sh
git commit -m "fix: add || true to set-e-safe chain condition in schema-completeness-validator"
```

---

## Task 6: 新增 impl-manifest-merger.sh

**Files:**
- Create: `templates/.pipeline/autosteps/impl-manifest-merger.sh`

**Step 1: 创建脚本**

```bash
cat > templates/.pipeline/autosteps/impl-manifest-merger.sh << 'SCRIPT'
#!/bin/bash
# Phase 3 后置: Impl Manifest Merger
# 输入: PIPELINE_DIR（含 impl-manifest-*.json）
# 输出: .pipeline/artifacts/impl-manifest.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
ARTIFACTS_DIR="$PIPELINE_DIR/artifacts"
OUTPUT_FILE="$ARTIFACTS_DIR/impl-manifest.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$ARTIFACTS_DIR"

# 收集所有 impl-manifest-*.json
MANIFESTS=()
for f in "$ARTIFACTS_DIR"/impl-manifest-*.json; do
  [ -f "$f" ] && MANIFESTS+=("$f")
done

if [ ${#MANIFESTS[@]} -eq 0 ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"ImplManifestMerger","timestamp":"$TIMESTAMP","error":"no impl-manifest-*.json found","overall":"ERROR"}
EOF
  exit 2
fi

# Python 合并
PIPELINE_DIR="$PIPELINE_DIR" TIMESTAMP="$TIMESTAMP" python3 << 'PYEOF'
import json, os, glob

pipeline_dir = os.environ.get('PIPELINE_DIR', '.pipeline')
timestamp = os.environ.get('TIMESTAMP', '')
artifacts_dir = f'{pipeline_dir}/artifacts'
output_file = f'{artifacts_dir}/impl-manifest.json'

manifests = sorted(glob.glob(f'{artifacts_dir}/impl-manifest-*.json'))
builders = []
all_files = {}

for mpath in manifests:
    data = json.load(open(mpath))
    builder_name = os.path.basename(mpath)\
        .replace('impl-manifest-', '').replace('.json', '')
    files = data.get('files_changed', [])
    builders.append({'builder': builder_name, 'files_changed': files})
    for f in files:
        key = f['path']
        if key not in all_files:
            all_files[key] = f

result = {
    'autostep': 'ImplManifestMerger',
    'timestamp': timestamp,
    'builders': builders,
    'files_changed': list(all_files.values()),
    'overall': 'PASS'
}

with open(output_file, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
PYEOF

exit 0
SCRIPT
chmod +x templates/.pipeline/autosteps/impl-manifest-merger.sh
```

**Step 2: 验证脚本**

```bash
mkdir -p /tmp/fix-test-imm/.pipeline/artifacts
# 模拟两个 Builder 的输出
cat > /tmp/fix-test-imm/.pipeline/artifacts/impl-manifest-dba.json << 'EOF'
{"files_changed":[{"path":"src/db/database.js","action":"created"}]}
EOF
cat > /tmp/fix-test-imm/.pipeline/artifacts/impl-manifest-backend.json << 'EOF'
{"files_changed":[{"path":"src/routes/notes.js","action":"created"}]}
EOF

PIPELINE_DIR=/tmp/fix-test-imm/.pipeline \
  bash templates/.pipeline/autosteps/impl-manifest-merger.sh

echo "Exit: $?"
cat /tmp/fix-test-imm/.pipeline/artifacts/impl-manifest.json | python3 -m json.tool
```

Expected：exit 0，impl-manifest.json 包含 `builders` 数组（dba、backend）和合并后的 `files_changed`（2 个文件）。

**Step 3: 验证空输入的 ERROR 处理**

```bash
mkdir -p /tmp/fix-test-imm-empty/.pipeline/artifacts
PIPELINE_DIR=/tmp/fix-test-imm-empty/.pipeline \
  bash templates/.pipeline/autosteps/impl-manifest-merger.sh
echo "Exit: $?"
```

Expected：exit 2，输出含 `"overall":"ERROR"`。

**Step 4: Commit**

```bash
git add templates/.pipeline/autosteps/impl-manifest-merger.sh
git commit -m "feat: add impl-manifest-merger AutoStep to replace inline LLM merge"
```

---

## Task 7: 更新 orchestrator.md（三处修复）

**Files:**
- Modify: `agents/orchestrator.md`（worktree 创建命令、Phase 3.7 启停、impl-manifest 合并改为 AutoStep）

**Step 1: 定位三处需要改动的位置**

```bash
# 找 worktree 创建命令位置
grep -n 'git checkout -b\|git worktree add' agents/orchestrator.md

# 找 impl-manifest 合并位置
grep -n 'impl-manifest\|合并 impl' agents/orchestrator.md

# 找 Phase 3.7 位置
grep -n 'Phase 3.7\|3\.7\|contract-compliance\|SERVICE_BASE_URL' agents/orchestrator.md
```

**Step 2: 修复 worktree 创建命令**

找到如下三行：
```
git checkout -b pipeline/phase-3/builder-<name> "$BASE_SHA"
git worktree add "$(pwd)/.worktrees/builder-<name>" pipeline/phase-3/builder-<name>
git checkout "$MAIN_BRANCH"
```

替换为：
```
git worktree add -b pipeline/phase-3/builder-<name> \
  "$(pwd)/.worktrees/builder-<name>" "$BASE_SHA"
```

**Step 3: 修复 Phase 3.7 启停**

找到 Phase 3.7 调用段，在 AutoStep 调用前后包裹服务启停：

```
#### Phase 3.7 — Contract Compliance Checker（AutoStep）

启动服务（后台）：
  npm start &
  SERVICE_PID=$!
  等待就绪（最多 10s）：轮询 curl -sf http://localhost:3000/health，间隔 1s
  若 10s 内未就绪：写入 WARN 报告跳过，kill $SERVICE_PID 2>/dev/null || true，继续

运行 AutoStep：
  SERVICE_BASE_URL=http://localhost:3000 \
  PIPELINE_DIR=... \
  bash .pipeline/autosteps/contract-compliance-checker.sh

停止服务：
  kill $SERVICE_PID 2>/dev/null || true
```

**Step 4: 将 impl-manifest 合并改为 AutoStep 调用**

找到「合并 impl-manifest」段（LLM inline 操作说明），替换为：

```
**合并 impl-manifest**（AutoStep）：
  PIPELINE_DIR=.pipeline bash .pipeline/autosteps/impl-manifest-merger.sh
  若 exit ≠ 0：ESCALATION，停止流水线
  进入 Phase 3.1。
```

**Step 5: 验证改动**

```bash
# 确认三处关键词已更新
grep -n 'worktree add -b' agents/orchestrator.md
grep -n 'impl-manifest-merger' agents/orchestrator.md
grep -n 'SERVICE_PID\|kill.*SERVICE' agents/orchestrator.md
```

Expected：三条命令各有输出。

**Step 6: Commit**

```bash
git add agents/orchestrator.md
git commit -m "fix: correct worktree creation, add Phase 3.7 service lifecycle, use merger AutoStep"
```

---

## Task 8: 更新 builder-backend.md 和 builder-dba.md（文件边界隔离）

**Files:**
- Modify: `agents/builder-backend.md`
- Modify: `agents/builder-dba.md`

**Step 1: 查看两个文件的约束节**

```bash
grep -n '文件\|files\|范围\|scope\|boundary\|只修改\|禁止' \
  agents/builder-backend.md agents/builder-dba.md | head -20
```

**Step 2: 更新 builder-dba.md**

在「约束」节（通常含「严格文件范围」）添加文件所有权声明：

```markdown
**文件所有权（DBA）：**
- 拥有目录：`src/db/`、`src/repositories/`、`src/models/`
- **禁止**修改上述目录以外的任何文件
- 如需向 Backend 暴露接口，在 tasks.json 声明的接口契约中定义函数签名，不直接修改 Backend 文件
```

**Step 3: 更新 builder-backend.md**

在「约束」节添加对称声明：

```markdown
**文件所有权（Backend）：**
- 拥有目录：`src/routes/`、`src/services/`、`src/middleware/`
- **禁止**修改上述目录以外的任何文件（包括 `src/db/`、`src/repositories/`）
- 跨层调用只能依赖 tasks.json 中声明的接口契约（函数名 + 参数 + 返回类型）
```

**Step 4: 验证**

```bash
grep -n '文件所有权\|拥有目录\|禁止' \
  agents/builder-dba.md agents/builder-backend.md
```

Expected：两个文件各有对应行输出。

**Step 5: Commit**

```bash
git add agents/builder-backend.md agents/builder-dba.md
git commit -m "fix: add file ownership constraints to builder-backend and builder-dba"
```

---

## Task 9: 更新 contract-formalizer.md（内部模块接口定义）

**Files:**
- Modify: `agents/contract-formalizer.md`

**Step 1: 查看当前输出格式**

```bash
grep -n 'contracts\|output\|tasks.json\|输出' agents/contract-formalizer.md | head -20
```

**Step 2: 新增「内部接口定义」节**

在输出说明节（描述 tasks.json 写法的地方）追加：

```markdown
#### 内部模块接口（contracts 字段补充）

除 HTTP API 的 OpenAPI schema 文件外，还需在 `tasks.json` 的 `contracts` 字段中为
**跨 Builder 边界的内部模块**补充接口定义条目，格式如下：

```json
{
  "type": "internal",
  "module": "noteRepository",
  "owner": "builder-dba",
  "consumers": ["builder-backend"],
  "functions": [
    {
      "name": "findAll",
      "params": [{"name": "limit", "type": "number"}, {"name": "offset", "type": "number"}],
      "returns": "{ items: Note[], total: number }"
    },
    {
      "name": "create",
      "params": [{"name": "data", "type": "{ title: string, content?: string }"}],
      "returns": "Note"
    }
  ]
}
```

此条目由 DBA 的所有权模块 owner 负责实现，Backend 等消费方**只能按此签名调用，不得自行实现同名模块**。
```

**Step 3: 验证**

```bash
grep -n '内部模块接口\|internal\|owner\|consumers\|functions' \
  agents/contract-formalizer.md | head -10
```

Expected：有对应行输出。

**Step 4: Commit**

```bash
git add agents/contract-formalizer.md
git commit -m "fix: add internal module interface definition to contract-formalizer"
```

---

## Task 10: 更新 documenter.md（明确 CHANGELOG 格式）

**Files:**
- Modify: `agents/documenter.md`

**Step 1: 查看当前 CHANGELOG 相关说明**

```bash
grep -n 'CHANGELOG\|Unreleased\|Keep a Changelog' agents/documenter.md
```

**Step 2: 在 CHANGELOG 说明处明确格式**

找到「CHANGELOG：按 Keep a Changelog 规范添加本次变更条目」一行，扩展为：

```markdown
2. **CHANGELOG**：按 Keep a Changelog 规范添加本次变更条目

   **必须使用以下格式**（Changelog Checker 严格校验）：

   ```markdown
   ## [Unreleased]

   ### Added
   - 新增 XXX API（对应 api-change-report.json 中的变更契约）

   ### Changed
   - 修改 YYY 行为

   ### Fixed
   - 修复 ZZZ 问题
   ```

   **约束：**
   - `## [Unreleased]` 节**必须存在**，即使当前无变更也保留空节头
   - 不得将 Unreleased 内容合并到版本节（如 `## [1.0.0]`）
   - `api-change-report.json` 中每个 `changed_contracts` 条目必须在此节有对应条目
```

**Step 3: 验证**

```bash
grep -n 'Unreleased\|必须存在\|必须使用' agents/documenter.md
```

Expected：有对应行输出。

**Step 4: Commit**

```bash
git add agents/documenter.md
git commit -m "fix: clarify CHANGELOG format requirement in documenter to match changelog-checker"
```

---

## 完成验证

所有 10 个任务完成后，运行以下检查确认无遗漏：

```bash
# 1. 确认所有 || true 修复
grep -rn '&& OVERALL\|&& SECTIONS_OVERALL' \
  templates/.pipeline/autosteps/*.sh | grep -v '|| true'
# Expected: 无输出

# 2. 确认新文件存在
ls -la templates/.pipeline/autosteps/impl-manifest-merger.sh

# 3. 确认 orchestrator 三处关键词
grep -c 'worktree add -b\|impl-manifest-merger\|SERVICE_PID' \
  agents/orchestrator.md
# Expected: 3

# 4. 确认 builder 文件所有权约束
grep -l '文件所有权' agents/builder-backend.md agents/builder-dba.md | wc -l
# Expected: 2

# 5. 确认 contract-formalizer 内部接口节
grep -c 'internal' agents/contract-formalizer.md
# Expected: ≥1

# 6. 确认 documenter CHANGELOG 格式
grep -c 'Unreleased.*必须' agents/documenter.md
# Expected: ≥1
```
