# Duplicate Detector — 重复组件检测与整改设计

## 概述

为组件注册表（Component Registry）新增**重复检测与自动整改**能力。在 `team scan` 扫描完成后，自动识别重复的组件/方法，由 LLM 生成可执行的整改方案（含 patch），经独立审计 Agent 审核后，用户确认即可自动应用。

## 问题

组件注册表解决了"让后续提案发现已有组件"的**预防**问题，但缺少对**存量重复**的检测能力。一个长期迭代的项目中，不同开发者（或不同提案的 Builder）可能已经写出了功能重叠的代码：

- 签名完全相同的函数散落在不同模块
- 名称相似、参数类型相同的近似重复（`validateEmail` vs `checkEmail`）
- 实现不同但功能等价的语义重复（`AuthMiddleware` vs `AuthGuard`）

仅靠注册表的"发现"能力不足以解决已有的重复，需要主动检测并提供整改方案。

## 设计决策

- **三层检测**：精确匹配（规则）→ 近似匹配（规则）→ 语义匹配（LLM），逐层递进
- **Python 脚本做规则分析**：Layer 1/2 的检测（签名比对、编辑距离、Jaccard 系数）是确定性计算，用 Python 脚本实现，可测试、可靠、快速。Skill 用于协调调用和结果格式化
- **生成与审计严格隔离**：生成整改方案和审计方案必须是两个独立 Agent（独立 claude 进程），不共享上下文
- **逐步升级的重试策略**：生成模型重试 → 升级到高阶模型重试 → 人工介入
- **审计模型不可配**：固定使用当前 Claude Code 会话模型，确保审计质量
- **整改方案必须有 LLM**：不提供无模型降级，模板化建议没有实际价值

## 架构

### 三层协作

```
Shell 脚本（duplicate-detector.sh）
  → 流程编排、重试/升级控制、入口

Python 脚本（duplicate-analyzer.py）
  → 确定性规则检测：签名比对、Levenshtein 编辑距离、Jaccard 系数、排除规则
  → 由 Skill 或 Shell 调用，输出 duplicate-candidates.json

Claude Agent（duplicate-generator / duplicate-auditor）
  → LLM 生成 patch、LLM 审计 patch
```

### 执行流程

```
team scan / team scan --refresh / phase-3.0d（流水线自动触发）
  └─ duplicate-detector.sh（Shell 编排）
       │
       ├─ Step 1: 调用 Skill（duplicate-analysis）
       │    → 读取 component-registry.json
       │    → 规则检测（签名匹配、名称相似度、tag 重叠）
       │    → 输出 duplicate-candidates.json
       │
       ├─ Step 2: 调用 claude --agent duplicate-generator
       │    → 输入：duplicate-candidates.json + 源码上下文
       │    → 输出：remediation-plan.json（含 patch）
       │    → 失败重试 ≤ 3 次
       │    → 仍失败：升级到会话模型重试 ≤ 3 次
       │    → 仍失败：人工介入
       │
       ├─ Step 3: 调用 claude --agent duplicate-auditor
       │    → 输入：remediation-plan.json（不含生成过程上下文）
       │    → 输出：audit-result.json（PASS/FAIL + 理由）
       │    → FAIL → 将审计意见反馈回 Step 2 重新生成
       │
       └─ Step 4: 输出最终报告
            → duplicate-report.json
            → --check-only 模式到此结束
            → 正常模式：等用户确认后应用 patch
```

### 模型升级链

```
生成模型（config.json 配置，如 Ollama 或 Haiku）
  → 生成 patch
  → 审计模型（当前 Claude Code 会话模型）审计
    → FAIL: 生成模型重试（≤ 3 次）
      → 仍 FAIL: 升级到会话模型作为生成模型（≤ 3 次）
        → 仍 FAIL: 输出报告，人工介入

注意：升级后生成和审计使用同一模型，但仍为两个独立 Agent，
上下文完全隔离，审计 Agent 不会受生成 Agent 思路影响。

最坏情况：2 层 × 3 次重试 = 6 次生成 + 6 次审计 = 12 次 LLM 调用。
使用付费 Claude 模型时需注意成本。实际项目中多数重复在首次生成即通过审计。
```

## 触发时机

| 触发方式 | 命令/阶段 | 行为 |
|----------|-----------|------|
| 手动全量扫描 | `team scan` | 扫描完成后自动执行重复检测 + 整改 |
| 手动增量刷新 | `team scan --refresh` | 刷新完成后自动执行重复检测 + 整改 |
| 手动仅检测 | `team scan --check-only` | 只检测重复并输出报告，不生成整改方案 |
| 流水线自动 | Phase 3.0d（Component Extractor phase-3.0c 之后） | 增量检测 + 整改，范围限于本提案涉及的文件 |

### `--check-only` 模式

快速查看重复状态，不调用 LLM，不生成 patch：

```bash
team scan --check-only
```

仅执行 Step 1（Skill 规则检测），输出 `duplicate-candidates.json` 后终止。适用于 CI 集成或快速审视。

## 检测策略

### Layer 1: 精确重复（高置信度，纯规则）

- **签名完全相同**：函数签名（名称 + 参数类型 + 返回类型）完全一致
- **函数体 hash 相同**：对函数体做规范化 hash（去除空白和注释），hash 相同即为精确重复
- **置信度**：≥ 0.95
- **默认建议**：删除其中一个，保留引用更多的

### Layer 2: 近似重复（中置信度，纯规则）

- **名称编辑距离 ≤ 3 + 参数类型相同**：如 `validateEmail` vs `checkEmail`，参数都是 `(email: string): boolean`
- **同名函数在不同模块**：同名且签名兼容，散落在不同目录
- **置信度**：0.7 ~ 0.9
- **默认建议**：合并到公共模块

### Layer 3: 语义重复（需 LLM，仅非 `--check-only` 模式）

- **tags 重叠 ≥ 70% + summary 语义相似**：功能标签高度重叠
- **实现不同但功能等价**：如 `AuthMiddleware` vs `AuthGuard`
- **置信度**：0.5 ~ 0.8（由 LLM 判断）
- **默认建议**：人工评审，附 LLM 分析理由

### 排除规则

以下情况不标记为重复：

- 接口/trait 的不同实现（多态是有意设计）
- test 文件中的同名辅助函数
- 不同平台的条件编译变体（`#[cfg(target_os)]`）
- 显式标注为非重复的组件（通过配置 `exclude_pairs`）

## 存储结构

### 新增产物文件

```
.pipeline/artifacts/
├── duplicate-candidates.json    ← Step 1 规则检测输出
├── remediation-plan.json        ← Step 2 LLM 生成的整改方案
├── audit-result.json            ← Step 3 审计结果
└── duplicate-report.json        ← Step 4 最终报告
```

### duplicate-candidates.json schema

```jsonc
{
  "scan_time": "ISO-8601",
  "mode": "full",                 // "full" | "refresh" | "incremental"
  "candidates": [
    {
      "group_id": "DUP-001",
      "level": "exact",           // "exact" | "similar" | "semantic"
      "confidence": 0.98,
      "components": [
        {
          "id": "LEGACY-012",
          "name": "validateEmail",
          "path": "src/utils/validation.ts:25",
          "signature": "validateEmail(email: string): boolean"
        },
        {
          "id": "LEGACY-045",
          "name": "validateEmail",
          "path": "src/auth/helpers.ts:30",
          "signature": "validateEmail(email: string): boolean"
        }
      ],
      "reason": "签名完全相同"
    }
  ],
  "stats": {
    "total_scanned": 156,
    "exact_groups": 3,
    "similar_groups": 7,
    "semantic_groups": 0            // --check-only 模式下语义层为 0
  }
}
```

### remediation-plan.json schema

```jsonc
{
  "generated_at": "ISO-8601",
  "generator_model": "qwen2.5-coder:7b",
  "remediations": [
    {
      "group_id": "DUP-001",
      "action": "merge",            // "merge" | "delete" | "refactor"
      "keep": {
        "id": "LEGACY-012",
        "path": "src/utils/validation.ts:25",
        "rationale": "位于 utils 目录，被 5 个文件引用"
      },
      "remove": [
        {
          "id": "LEGACY-045",
          "path": "src/auth/helpers.ts:30"
        }
      ],
      "steps": [
        {
          "order": 1,
          "type": "update_imports",
          "description": "将 src/auth/login.ts 中的 import 从 ./helpers 改为 ../../utils/validation",
          "file": "src/auth/login.ts",
          "patch": "--- a/src/auth/login.ts\n+++ b/src/auth/login.ts\n@@ -1,2 +1,2 @@\n-import { validateEmail } from './helpers'\n+import { validateEmail } from '../../utils/validation'"
        },
        {
          "order": 2,
          "type": "delete_function",
          "description": "删除 src/auth/helpers.ts 中的 validateEmail 函数",
          "file": "src/auth/helpers.ts",
          "patch": "--- a/src/auth/helpers.ts\n+++ b/src/auth/helpers.ts\n@@ -30,10 +30,0 @@\n-export function validateEmail(email: string): boolean {\n-  ...\n-}"
        }
      ],
      "impact_analysis": {
        "files_affected": 2,
        "imports_updated": 1,
        "functions_removed": 1,
        "risk": "low"
      }
    }
  ],
  "summary": {
    "total_remediations": 3,
    "total_patches": 7,
    "estimated_lines_removed": 45
  }
}
```

### audit-result.json schema

```jsonc
{
  "audited_at": "ISO-8601",
  "auditor_model": "claude-opus-4-6",
  "overall": "PASS",               // "PASS" | "FAIL"
  "remediations": [
    {
      "group_id": "DUP-001",
      "verdict": "PASS",           // "PASS" | "FAIL"
      "issues": [],
      "notes": "整改方案合理，import 路径正确"
    },
    {
      "group_id": "DUP-003",
      "verdict": "FAIL",
      "issues": [
        "patch 中遗漏了 src/api/routes.ts 对该函数的引用",
        "合并后的函数缺少原函数的错误处理分支"
      ],
      "notes": "需要补充遗漏的引用更新和错误处理"
    }
  ]
}
```

### duplicate-report.json schema

```jsonc
{
  "report_time": "ISO-8601",
  "mode": "full",
  "status": "ready",               // "ready" | "partial" | "manual_needed"
  "duplicates": [
    {
      "group_id": "DUP-001",
      "level": "exact",
      "confidence": 0.98,
      "components": ["LEGACY-012", "LEGACY-045"],
      "reason": "签名完全相同：validateEmail(email: string): boolean",
      "remediation": {
        "action": "merge",
        "status": "approved",       // "approved" | "rejected" | "manual"
        "keep": "LEGACY-012",
        "patches_count": 2,
        "files_affected": 2
      }
    }
  ],
  "stats": {
    "total_scanned": 156,
    "exact_duplicates": 3,
    "similar_duplicates": 7,
    "semantic_duplicates": 2,
    "auto_remediated": 10,
    "manual_needed": 2
  },
  "retry_history": [
    {
      "attempt": 1,
      "model": "qwen2.5-coder:7b",
      "audit_result": "FAIL",
      "reason": "遗漏 import 引用"
    },
    {
      "attempt": 2,
      "model": "qwen2.5-coder:7b",
      "audit_result": "PASS"
    }
  ]
}
```

## 新增 Agent

### duplicate-generator

```yaml
name: duplicate-generator
description: "重复组件整改方案生成器。读取重复候选列表和源码上下文，生成含 patch 的整改方案。"
tools: Read, Glob, Grep, Bash
model: inherit
```

**职责**：
- 读取 `duplicate-candidates.json` 和相关源码文件
- 分析每组重复的引用关系（谁引用了被删除的组件）
- 生成 unified diff 格式的 patch
- 对语义重复组（Layer 3），判断功能是否等价并生成合并方案
- 输出 `remediation-plan.json`

**输入 prompt 模板**：

```
你是一个代码重构专家。以下是检测到的重复组件列表和相关源码。
请为每组重复生成整改方案，包含：
1. 保留哪个实现（选择被引用更多、位置更合理的）
2. 具体的 patch（unified diff 格式）
3. 影响分析（涉及文件数、风险等级）

重复候选：
<duplicate-candidates.json 内容>

相关源码：
<各文件的相关代码片段>

输出严格遵循 remediation-plan.json schema。
```

### duplicate-auditor

```yaml
name: duplicate-auditor
description: "重复组件整改方案审计员。独立审核整改方案的正确性和完整性。"
tools: Read, Glob, Grep, Bash
model: inherit
```

**职责**：
- 读取 `remediation-plan.json`（不接收生成过程的上下文）
- 独立验证每个 patch 的正确性：
  - patch 应用后语法是否正确
  - 是否遗漏了对被删除组件的引用
  - 合并后的组件是否保留了所有功能分支
  - import 路径是否正确
- 输出 `audit-result.json`

**输入 prompt 模板**：

```
你是一个代码审计专家。以下是一份重复组件的整改方案，请独立审核：
1. 每个 patch 应用后是否保持语法正确
2. 是否遗漏了对被删除组件的引用（搜索整个项目）
3. 合并后的组件是否保留了原有的所有功能
4. import/require 路径是否正确
5. 是否引入了循环依赖

整改方案：
<remediation-plan.json 内容>

对于每个整改项，给出 PASS 或 FAIL，FAIL 必须附具体问题描述。
输出严格遵循 audit-result.json schema。
```

## 规则检测脚本设计

### duplicate-analyzer.py

**用途**：执行 Layer 1 和 Layer 2 的确定性规则检测，输出 `duplicate-candidates.json`。

**选择 Python 而非 Skill 的原因**：编辑距离（Levenshtein）、Jaccard 系数、字符串精确比对等是确定性算法，用 Python 实现比 LLM Skill 更可靠、更快、可单元测试。`--check-only` 模式因此完全不依赖任何模型。

**能力**：
- 读取 `component-registry.json` 索引
- 按需加载分片文件获取完整签名和 tags
- 签名精确匹配（字符串比较）
- 名称相似度计算（Levenshtein 编辑距离，使用 Python 标准库 `difflib.SequenceMatcher` 或内联实现）
- 参数类型兼容性检查
- tags 重叠度计算（Jaccard 系数：`len(A∩B) / len(A∪B)`）
- 应用排除规则（接口实现、测试文件、配置中的 `exclude_pairs`）
- 输出结构化的 `duplicate-candidates.json`

**排除键**：`exclude_pairs` 配置使用 `name+path` 对而非组件 ID，因为 ID 在 `--refresh` 重扫时可能变化：

```jsonc
"exclude_pairs": [
  { "a": "AuthMiddleware@src/middleware/auth.ts", "b": "AuthGuard@src/guards/auth.ts" }
]
```

**调用方式**：

```bash
# 由 duplicate-detector.sh 调用
python3 "$PIPELINE_DIR/autosteps/duplicate-analyzer.py" \
  --registry "$PIPELINE_DIR/artifacts/component-registry.json" \
  --config "$PIPELINE_DIR/config.json" \
  --output "$PIPELINE_DIR/artifacts/duplicate-candidates.json" \
  --mode full    # full | refresh | incremental
```

**不做的事**：
- 不做语义判断（交给 LLM Agent）
- 不生成 patch（交给 duplicate-generator）
- 不读取源码文件（只处理注册表数据）

## Shell 编排逻辑

### duplicate-detector.sh

```bash
#!/bin/bash
# duplicate-detector.sh
# 输入: MODE (full|refresh|incremental|check-only), PIPELINE_DIR
# 输出: duplicate-report.json
# 退出码: 0=完成 1=人工介入 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
MODE="${MODE:-full}"
ARTIFACTS="$PIPELINE_DIR/artifacts"
REGISTRY="$ARTIFACTS/component-registry.json"
CANDIDATES="$ARTIFACTS/duplicate-candidates.json"
REMEDIATION="$ARTIFACTS/remediation-plan.json"
AUDIT="$ARTIFACTS/audit-result.json"
REPORT="$ARTIFACTS/duplicate-report.json"

# ── Step 1: Python 规则检测（确定性，无需模型） ──
python3 "$PIPELINE_DIR/autosteps/duplicate-analyzer.py" \
  --registry "$REGISTRY" \
  --config "$PIPELINE_DIR/config.json" \
  --output "$CANDIDATES" \
  --mode "$MODE"

# --check-only 模式到此结束
if [ "$MODE" = "check-only" ]; then
  echo "[DuplicateDetector] 规则检测完成，报告：$CANDIDATES"
  exit 0
fi

# 无候选则跳过
CANDIDATE_COUNT=$(python3 -c "import json; print(len(json.load(open('$CANDIDATES')).get('candidates',[])))")
if [ "$CANDIDATE_COUNT" -eq 0 ]; then
  echo "[DuplicateDetector] 未发现重复组件"
  exit 0
fi

# ── Step 2 + 3: 生成 + 审计循环 ──
# 从 config.json 读取配置
CONFIGURED_MODEL=$(python3 -c "
import json
c = json.load(open('$PIPELINE_DIR/config.json'))
dd = c.get('component_registry',{}).get('duplicate_detection',{})
print(dd.get('generator_model', 'auto'))
")
MAX_RETRIES=$(python3 -c "
import json
c = json.load(open('$PIPELINE_DIR/config.json'))
dd = c.get('component_registry',{}).get('duplicate_detection',{})
print(dd.get('max_retries_per_tier', 3))
")

AUDIT_RESULT="FAIL"
FEEDBACK_FILE="$ARTIFACTS/audit-feedback.txt"
echo "" > "$FEEDBACK_FILE"

for TIER in "configured" "session"; do
  if [ "$TIER" = "configured" ]; then
    MODEL_FLAG="--model $CONFIGURED_MODEL"
  else
    MODEL_FLAG=""  # inherit = 当前会话模型
  fi

  for ATTEMPT in $(seq 1 $MAX_RETRIES); do
    echo "[DuplicateDetector] Tier=$TIER, Attempt=$ATTEMPT"

    # Step 2: 生成（将审计反馈作为附加上下文传入）
    FEEDBACK_CONTENT=$(cat "$FEEDBACK_FILE")
    GENERATOR_PROMPT="读取 $CANDIDATES 和相关源码，生成整改方案到 $REMEDIATION。"
    if [ -n "$FEEDBACK_CONTENT" ]; then
      GENERATOR_PROMPT="$GENERATOR_PROMPT

上一次审计未通过，审计意见如下，请据此修正方案：
$FEEDBACK_CONTENT"
    fi

    claude --dangerously-skip-permissions --agent duplicate-generator \
      $MODEL_FLAG \
      -p "$GENERATOR_PROMPT"

    # Step 3: 审计（始终用会话模型，独立进程，不传入生成上下文）
    claude --dangerously-skip-permissions --agent duplicate-auditor \
      -p "审核 $REMEDIATION 中的整改方案，输出到 $AUDIT。"

    AUDIT_RESULT=$(python3 -c "import json; print(json.load(open('$AUDIT')).get('overall','FAIL'))")
    if [ "$AUDIT_RESULT" = "PASS" ]; then
      break 2
    fi

    # 提取审计意见供下次生成使用
    python3 -c "
import json
r = json.load(open('$AUDIT'))
issues = []
for rem in r.get('remediations', []):
    if rem.get('verdict') == 'FAIL':
        for issue in rem.get('issues', []):
            issues.append(f\"[{rem['group_id']}] {issue}\")
print('\n'.join(issues))
" > "$FEEDBACK_FILE"
  done
done

# ── 全部重试失败 ──
if [ "$AUDIT_RESULT" != "PASS" ]; then
  echo "[DuplicateDetector] 整改方案审计未通过（已重试 2 x $MAX_RETRIES 次），需人工介入"
  # 生成 partial 报告（status=manual_needed）
  python3 -c "
import json
candidates = json.load(open('$CANDIDATES'))
report = {
    'status': 'manual_needed',
    'mode': '$MODE',
    'duplicates': candidates.get('candidates', []),
    'stats': candidates.get('stats', {})
}
with open('$REPORT', 'w') as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
"
  exit 1
fi

# ── Step 4: 生成最终报告 ──
# 合并 candidates + remediation + audit 为最终报告
python3 -c "
import json, datetime
candidates = json.load(open('$CANDIDATES'))
remediation = json.load(open('$REMEDIATION'))
audit = json.load(open('$AUDIT'))
report = {
    'report_time': datetime.datetime.utcnow().isoformat() + 'Z',
    'mode': '$MODE',
    'status': 'ready',
    'duplicates': candidates.get('candidates', []),
    'stats': candidates.get('stats', {}),
    'remediation_summary': remediation.get('summary', {}),
    'audit_model': audit.get('auditor_model', '')
}
with open('$REPORT', 'w') as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
"
echo "[DuplicateDetector] 报告：$REPORT"
echo "[DuplicateDetector] 整改方案：$REMEDIATION"

# auto_apply 检查
AUTO_APPLY=$(python3 -c "
import json
c = json.load(open('$PIPELINE_DIR/config.json'))
print(str(c.get('component_registry',{}).get('duplicate_detection',{}).get('auto_apply', False)).lower())
")
if [ "$AUTO_APPLY" = "true" ]; then
  echo "[DuplicateDetector] auto_apply=true，自动应用整改"
  # 应用 patch（实现细节略）
else
  echo "[DuplicateDetector] 请查看报告后手动确认应用"
fi
```

## 配置扩展

在 `.pipeline/config.json` 的 `component_registry` 块中新增：

```jsonc
{
  "component_registry": {
    "enabled": true,
    "summary_provider": "auto",
    "ollama_model": "qwen2.5-coder:7b",
    "ollama_url": "http://localhost:11434",
    "exclude_patterns": ["test/**", "bench/**", "examples/**"],
    "min_complexity": 3,
    "duplicate_detection": {
      "enabled": true,
      "generator_model": "auto",       // "auto" | "ollama" | "claude-haiku" | "claude-sonnet"
                                        // auto: 按降级链 Ollama → Claude CLI
      "similarity_threshold": 0.7,      // 名称相似度阈值（Layer 2）
      "tag_overlap_threshold": 0.7,     // tags 重叠阈值（Layer 3 候选）
      "max_retries_per_tier": 3,        // 每个模型层级的最大重试次数
      "exclude_pairs": [                // 手动排除的组件对（不标记为重复）
        {                               // 使用 name@path 格式，因 ID 在重扫时可能变化
          "a": "AuthMiddleware@src/middleware/auth.ts",
          "b": "AuthGuard@src/guards/auth.ts"
        }
      ],
      "auto_apply": false               // 审计通过后是否自动应用（不等用户确认）
    }
  }
}
```

## team scan 命令扩展

在现有 `team` CLI 的 `cmd_scan()` 函数中扩展参数：

```bash
team scan                # 全量扫描 + 重复检测 + 整改
team scan --refresh      # 增量刷新 + 重复检测 + 整改
team scan --check-only   # 仅规则检测，不调用 LLM，不生成 patch
```

### 终端输出示例

```
$ team scan

▶ Component Registry — 全量扫描
  ✓ 检测到语言：TypeScript, Rust
  ✓ 提取组件：156 个
  ✓ 生成摘要：156/156

▶ Duplicate Detector — 重复检测
  ✓ Layer 1（精确匹配）：3 组
  ✓ Layer 2（近似匹配）：7 组
  ✓ Layer 3（语义匹配）：2 组

▶ 整改方案生成（模型：qwen2.5-coder:7b）
  ✓ 生成 12 组整改方案

▶ 整改方案审计（模型：claude-opus-4-6）
  ⚠ 第 1 次审计：FAIL（DUP-003 遗漏引用）
  ✓ 第 2 次审计：PASS

▶ 最终报告
  ⚠ EXACT  validateEmail (LEGACY-012 ↔ LEGACY-045)
           → 合并到 src/utils/validation.ts，删除 src/auth/helpers.ts:30
  ⚠ SIMILAR formatDate / formatDateTime (LEGACY-023 ↔ LEGACY-067)
           → 合并为 formatDate(date, options?)
  ℹ SEMANTIC AuthMiddleware / AuthGuard (LEGACY-001 ↔ LEGACY-089)
           → 评审建议：功能重叠 80%，建议合并

  详细报告：.pipeline/artifacts/duplicate-report.json
  整改方案：.pipeline/artifacts/remediation-plan.json

  应用整改？[y/N]
```

## 流水线集成

### Phase 3.0d — Duplicate Detector

在 Component Extractor（phase-3.0c）之后，作为独立阶段 **phase-3.0d** 执行。失败行为与 Component Extractor 一致：**非阻塞**，FAIL 输出 WARN 继续后续阶段。

### 集成修改点

| 文件 | 修改内容 |
|------|----------|
| `install.sh`（内嵌 `team` CLI 脚本） | `cmd_scan()` 新增 `--check-only` 参数路由 |
| `agents/duplicate-generator.md` | 新增 Agent 定义 |
| `agents/duplicate-auditor.md` | 新增 Agent 定义 |
| `templates/.pipeline/autosteps/duplicate-detector.sh` | 新增 AutoStep |
| `templates/.pipeline/config.json` | `component_registry.duplicate_detection` 配置块 |
| `playbook.md` Phase 3.0c 段 | Component Extractor 后追加 duplicate-detector 调用 |
| `orchestrator.md` 路由表 | 新增 `phase-3.0d` → `duplicate-detector.sh` 路由 |
| `templates/.pipeline/autosteps/duplicate-analyzer.py` | 新增 Python 规则检测脚本 |

## 与组件注册表的边界

组件注册表（Component Registry）设计明确声明"不做自动重构——只提供发现能力，复用决策由 Architect/Builder 做"。本 Duplicate Detector 是注册表之上的**独立扩展层**，负责注册表刻意不做的"行动"部分：

- **注册表**：资产登记 + 发现（预防重复）
- **Duplicate Detector**：检测已有重复 + 生成整改方案 + 审计 + 应用（修复重复）

两者数据流方向：注册表产出 → Detector 消费。Detector 依赖注册表的数据但不修改注册表本身（整改应用的是源码，不是注册表）。注册表会在下次 `team scan --refresh` 或 phase-3.0c 时自然更新。

## 不做的事情

- **不做自动应用**（默认） — `auto_apply` 默认 false，需用户确认
- **不做跨项目去重** — 仅项目内检测
- **不做整改方案的无模型降级** — 没有 LLM 就不生成整改方案，模板化建议没有实际价值
- **不做实时检测** — 不在编辑器层面做 lint-time 检测，只在 scan 和流水线阶段触发
- **不做历史追踪** — 不记录"曾经有过重复但已修复"，git 已记录
