# Duplicate Detector 实现计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为组件注册表新增重复检测与自动整改能力，包括 Python 规则检测脚本、两个 Claude Agent（生成器 + 审计器）、Shell 编排脚本，以及 `team scan` CLI 集成。

**Architecture:** Python 脚本做确定性规则检测（签名比对、编辑距离、tag 重叠），Shell 脚本编排整体流程（重试、模型升级），两个独立 Claude Agent 分别负责整改方案生成和审计。

**Tech Stack:** Python 3 (标准库 difflib, json, sys, argparse), Bash, Claude Code Agent (Markdown), jq (仅做简单值提取)

**Spec:** `docs/superpowers/specs/2026-03-14-duplicate-detector-design.md`

---

## 文件结构

| 操作 | 文件路径 | 职责 |
|------|----------|------|
| Create | `templates/.pipeline/autosteps/duplicate-analyzer.py` | Python 规则检测脚本（Layer 1 + Layer 2） |
| Create | `templates/.pipeline/autosteps/duplicate-detector.sh` | Shell 编排脚本（调用 Python + Agent，控制重试/升级） |
| Create | `agents/duplicate-generator.md` | 整改方案生成 Agent |
| Create | `agents/duplicate-auditor.md` | 整改方案审计 Agent |
| Modify | `templates/.pipeline/config.json` | 新增 `component_registry.duplicate_detection` 配置块 |
| Modify | `install.sh:78-98` | `usage()` 新增 scan 命令说明 |
| Modify | `install.sh:100-160` | `cmd_init()` 支持复制 `.py` autostep 文件 |
| Modify | `install.sh:176-238` | `cmd_upgrade()` 支持复制 `.py` autostep 文件 |
| Modify | `install.sh:630-638` | case 路由新增 `scan` |
| Create | (install.sh 内嵌) `cmd_scan()` | `team scan` / `--refresh` / `--check-only` 命令实现 |
| Modify | `agents/orchestrator.md:34-36` | batch-build 或 batch-post-build 新增 phase-3.0d |
| Modify | `agents/orchestrator.md:65` | 线性流路由表插入 phase-3.0d |
| Create | `tests/test_duplicate_analyzer.py` | Python 规则检测单元测试 |

---

## Chunk 1: Python 规则检测脚本

### Task 1: 创建 duplicate-analyzer.py 测试

**Files:**
- Create: `tests/test_duplicate_analyzer.py`

- [ ] **Step 1: 编写 Layer 1 精确匹配测试**

```python
#!/usr/bin/env python3
"""duplicate-analyzer.py 单元测试"""
import json
import os
import sys
import tempfile
import unittest

# 将 templates 目录加入 path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'templates', '.pipeline', 'autosteps'))

from duplicate_analyzer import find_exact_duplicates, find_similar_duplicates, build_candidates_report


class TestExactDuplicates(unittest.TestCase):
    """Layer 1: 签名完全相同的精确重复"""

    def test_identical_signatures_detected(self):
        components = [
            {"id": "L-001", "name": "validateEmail", "type": "function",
             "path": "src/utils/validation.ts:25",
             "signature": "validateEmail(email: string): boolean",
             "tags": ["validation"], "exported": True, "shard": "LEGACY"},
            {"id": "L-002", "name": "validateEmail", "type": "function",
             "path": "src/auth/helpers.ts:30",
             "signature": "validateEmail(email: string): boolean",
             "tags": ["auth"], "exported": True, "shard": "LEGACY"},
        ]
        groups = find_exact_duplicates(components)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["level"], "exact")
        self.assertGreaterEqual(groups[0]["confidence"], 0.95)
        ids = {c["id"] for c in groups[0]["components"]}
        self.assertEqual(ids, {"L-001", "L-002"})

    def test_different_signatures_not_detected(self):
        components = [
            {"id": "L-001", "name": "validateEmail", "type": "function",
             "path": "src/utils/validation.ts:25",
             "signature": "validateEmail(email: string): boolean",
             "tags": [], "exported": True, "shard": "LEGACY"},
            {"id": "L-002", "name": "validatePhone", "type": "function",
             "path": "src/utils/validation.ts:50",
             "signature": "validatePhone(phone: string): boolean",
             "tags": [], "exported": True, "shard": "LEGACY"},
        ]
        groups = find_exact_duplicates(components)
        self.assertEqual(len(groups), 0)

    def test_three_way_duplicate(self):
        components = [
            {"id": "L-001", "name": "hash", "type": "function",
             "path": "a.ts:1", "signature": "hash(s: string): string",
             "tags": [], "exported": True, "shard": "LEGACY"},
            {"id": "L-002", "name": "hash", "type": "function",
             "path": "b.ts:1", "signature": "hash(s: string): string",
             "tags": [], "exported": True, "shard": "LEGACY"},
            {"id": "L-003", "name": "hash", "type": "function",
             "path": "c.ts:1", "signature": "hash(s: string): string",
             "tags": [], "exported": True, "shard": "LEGACY"},
        ]
        groups = find_exact_duplicates(components)
        self.assertEqual(len(groups), 1)
        self.assertEqual(len(groups[0]["components"]), 3)


class TestSimilarDuplicates(unittest.TestCase):
    """Layer 2: 名称相似 + 参数类型相同"""

    def test_similar_names_same_params(self):
        components = [
            {"id": "L-001", "name": "validateEmail", "type": "function",
             "path": "src/utils/v.ts:1",
             "signature": "validateEmail(email: string): boolean",
             "tags": ["validation"], "exported": True, "shard": "LEGACY"},
            {"id": "L-002", "name": "checkEmail", "type": "function",
             "path": "src/auth/v.ts:1",
             "signature": "checkEmail(email: string): boolean",
             "tags": ["auth"], "exported": True, "shard": "LEGACY"},
        ]
        # 已排除精确匹配的 IDs
        groups = find_similar_duplicates(components, exact_ids=set(), threshold=0.7)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["level"], "similar")

    def test_similar_names_different_params_not_detected(self):
        components = [
            {"id": "L-001", "name": "validateEmail", "type": "function",
             "path": "a.ts:1",
             "signature": "validateEmail(email: string): boolean",
             "tags": [], "exported": True, "shard": "LEGACY"},
            {"id": "L-002", "name": "validateEmails", "type": "function",
             "path": "b.ts:1",
             "signature": "validateEmails(emails: string[]): boolean[]",
             "tags": [], "exported": True, "shard": "LEGACY"},
        ]
        groups = find_similar_duplicates(components, exact_ids=set(), threshold=0.7)
        self.assertEqual(len(groups), 0)


class TestExclusionRules(unittest.TestCase):
    """排除规则测试"""

    def test_test_files_excluded(self):
        components = [
            {"id": "L-001", "name": "helper", "type": "function",
             "path": "src/utils/helper.ts:1",
             "signature": "helper(): void",
             "tags": [], "exported": True, "shard": "LEGACY"},
            {"id": "L-002", "name": "helper", "type": "function",
             "path": "tests/utils/helper.ts:1",
             "signature": "helper(): void",
             "tags": [], "exported": True, "shard": "LEGACY"},
        ]
        groups = find_exact_duplicates(components)
        # test 文件中的同名函数不算重复
        self.assertEqual(len(groups), 0)

    def test_exclude_pairs_respected(self):
        components = [
            {"id": "L-001", "name": "AuthMiddleware", "type": "middleware",
             "path": "src/middleware/auth.ts:1",
             "signature": "AuthMiddleware(req, res, next): void",
             "tags": ["auth"], "exported": True, "shard": "LEGACY"},
            {"id": "L-002", "name": "AuthMiddleware", "type": "middleware",
             "path": "src/guards/auth.ts:1",
             "signature": "AuthMiddleware(req, res, next): void",
             "tags": ["auth"], "exported": True, "shard": "LEGACY"},
        ]
        exclude = [{"a": "AuthMiddleware@src/middleware/auth.ts",
                     "b": "AuthMiddleware@src/guards/auth.ts"}]
        groups = find_exact_duplicates(components, exclude_pairs=exclude)
        self.assertEqual(len(groups), 0)


class TestBuildReport(unittest.TestCase):
    """候选报告生成"""

    def test_report_structure(self):
        groups = [
            {"level": "exact", "confidence": 0.98,
             "components": [
                 {"id": "L-001", "name": "fn", "path": "a.ts:1", "signature": "fn(): void"},
                 {"id": "L-002", "name": "fn", "path": "b.ts:1", "signature": "fn(): void"},
             ],
             "reason": "签名完全相同"}
        ]
        report = build_candidates_report(groups, total_scanned=10, mode="full")
        self.assertEqual(report["mode"], "full")
        self.assertEqual(report["stats"]["total_scanned"], 10)
        self.assertEqual(report["stats"]["exact_groups"], 1)
        self.assertIn("scan_time", report)
        self.assertTrue(report["candidates"][0]["group_id"].startswith("DUP-"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd /Users/minwang/RustroverProjects/lfun-team-pipeline && python3 -m pytest tests/test_duplicate_analyzer.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'duplicate_analyzer'`

- [ ] **Step 3: Commit 测试文件**

```bash
git add tests/test_duplicate_analyzer.py
git commit -m "test: add duplicate-analyzer unit tests (red)"
```

---

### Task 2: 实现 duplicate-analyzer.py

**Files:**
- Create: `templates/.pipeline/autosteps/duplicate_analyzer.py`

- [ ] **Step 1: 实现核心检测逻辑**

```python
#!/usr/bin/env python3
"""
duplicate-analyzer.py — 重复组件规则检测脚本
Layer 1: 精确重复（签名完全相同）
Layer 2: 近似重复（名称编辑距离 ≤ 3 + 参数类型兼容）

输入: component-registry.json
输出: duplicate-candidates.json
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from difflib import SequenceMatcher


def load_registry(registry_path):
    """加载组件注册表索引"""
    with open(registry_path) as f:
        data = json.load(f)
    return data.get("index", [])


def load_config(config_path):
    """加载配置中的 duplicate_detection 设置"""
    defaults = {
        "similarity_threshold": 0.7,
        "tag_overlap_threshold": 0.7,
        "exclude_pairs": []
    }
    try:
        with open(config_path) as f:
            cfg = json.load(f)
        dd = cfg.get("component_registry", {}).get("duplicate_detection", {})
        for k, v in dd.items():
            if k in defaults:
                defaults[k] = v
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    return defaults


def normalize_signature(sig):
    """规范化签名：去除空白差异"""
    return re.sub(r'\s+', ' ', sig.strip())


def extract_param_types(sig):
    """从签名中提取参数类型列表（粗略匹配括号内内容）"""
    m = re.search(r'\(([^)]*)\)', sig)
    if not m:
        return ""
    return re.sub(r'\s+', '', m.group(1))


def name_similarity(a, b):
    """使用 SequenceMatcher 计算名称相似度 (0.0 ~ 1.0)"""
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()


def is_excluded(c1, c2, exclude_pairs):
    """检查组件对是否在排除列表中"""
    key1 = f"{c1['name']}@{c1['path'].split(':')[0]}"
    key2 = f"{c2['name']}@{c2['path'].split(':')[0]}"
    for pair in exclude_pairs:
        a, b = pair.get("a", ""), pair.get("b", "")
        if {a, b} == {key1, key2}:
            return True
    return False


def is_test_path(path):
    """检查路径是否为测试文件"""
    lower = path.lower()
    return any(seg in lower for seg in ['/test/', '/tests/', '/__tests__/', '.test.', '.spec.', '_test.'])


def find_exact_duplicates(components, exclude_pairs=None):
    """Layer 1: 签名完全相同的精确重复"""
    if exclude_pairs is None:
        exclude_pairs = []

    sig_groups = defaultdict(list)
    for c in components:
        if not c.get("exported", True):
            continue
        if is_test_path(c.get("path", "")):
            continue
        norm_sig = normalize_signature(c.get("signature", ""))
        if norm_sig:
            sig_groups[norm_sig].append(c)

    groups = []
    for sig, members in sig_groups.items():
        if len(members) < 2:
            continue
        # 过滤排除对
        filtered = []
        skip_ids = set()
        for i, c1 in enumerate(members):
            for c2 in members[i + 1:]:
                if is_excluded(c1, c2, exclude_pairs):
                    skip_ids.add(c1["id"])
                    skip_ids.add(c2["id"])
        filtered = [c for c in members if c["id"] not in skip_ids]
        if len(filtered) < 2:
            continue

        groups.append({
            "level": "exact",
            "confidence": 0.98,
            "components": [
                {"id": c["id"], "name": c["name"],
                 "path": c["path"], "signature": c.get("signature", "")}
                for c in filtered
            ],
            "reason": f"签名完全相同：{sig}"
        })
    return groups


def find_similar_duplicates(components, exact_ids=None, threshold=0.7, exclude_pairs=None):
    """Layer 2: 名称相似 + 参数类型兼容"""
    if exact_ids is None:
        exact_ids = set()
    if exclude_pairs is None:
        exclude_pairs = []

    eligible = [
        c for c in components
        if c["id"] not in exact_ids
        and c.get("exported", True)
        and not is_test_path(c.get("path", ""))
    ]

    groups = []
    seen = set()

    for i, c1 in enumerate(eligible):
        if c1["id"] in seen:
            continue
        cluster = [c1]
        for c2 in eligible[i + 1:]:
            if c2["id"] in seen:
                continue
            if is_excluded(c1, c2, exclude_pairs):
                continue

            sim = name_similarity(c1["name"], c2["name"])
            if sim < threshold:
                continue

            # 参数类型必须兼容
            params1 = extract_param_types(c1.get("signature", ""))
            params2 = extract_param_types(c2.get("signature", ""))
            if params1 != params2:
                continue

            cluster.append(c2)
            seen.add(c2["id"])

        if len(cluster) >= 2:
            seen.add(c1["id"])
            sim_val = name_similarity(cluster[0]["name"], cluster[1]["name"])
            groups.append({
                "level": "similar",
                "confidence": round(0.7 + (sim_val - threshold) * 0.3 / (1 - threshold), 2)
                             if sim_val < 1.0 else 0.89,
                "components": [
                    {"id": c["id"], "name": c["name"],
                     "path": c["path"], "signature": c.get("signature", "")}
                    for c in cluster
                ],
                "reason": f"名称相似度 {sim_val:.2f}，参数类型相同"
            })
    return groups


def build_candidates_report(groups, total_scanned, mode):
    """构建 duplicate-candidates.json 报告"""
    # 分配 group_id
    for i, g in enumerate(groups, 1):
        g["group_id"] = f"DUP-{i:03d}"

    exact_count = sum(1 for g in groups if g["level"] == "exact")
    similar_count = sum(1 for g in groups if g["level"] == "similar")
    semantic_count = sum(1 for g in groups if g["level"] == "semantic")

    return {
        "scan_time": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "mode": mode,
        "candidates": groups,
        "stats": {
            "total_scanned": total_scanned,
            "exact_groups": exact_count,
            "similar_groups": similar_count,
            "semantic_groups": semantic_count
        }
    }


def main():
    parser = argparse.ArgumentParser(description="Duplicate component analyzer")
    parser.add_argument("--registry", required=True, help="Path to component-registry.json")
    parser.add_argument("--config", required=True, help="Path to config.json")
    parser.add_argument("--output", required=True, help="Output path for duplicate-candidates.json")
    parser.add_argument("--mode", default="full", choices=["full", "refresh", "incremental"])
    args = parser.parse_args()

    components = load_registry(args.registry)
    config = load_config(args.config)

    if not components:
        report = build_candidates_report([], 0, args.mode)
        with open(args.output, "w") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        print(f"[DuplicateAnalyzer] 注册表为空，跳过检测")
        return

    exclude_pairs = config.get("exclude_pairs", [])
    threshold = config.get("similarity_threshold", 0.7)

    # Layer 1
    exact_groups = find_exact_duplicates(components, exclude_pairs)
    exact_ids = set()
    for g in exact_groups:
        for c in g["components"]:
            exact_ids.add(c["id"])

    # Layer 2
    similar_groups = find_similar_duplicates(
        components, exact_ids=exact_ids, threshold=threshold, exclude_pairs=exclude_pairs
    )

    all_groups = exact_groups + similar_groups
    report = build_candidates_report(all_groups, len(components), args.mode)

    with open(args.output, "w") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(f"[DuplicateAnalyzer] 扫描 {len(components)} 个组件，"
          f"发现 {len(exact_groups)} 组精确重复，{len(similar_groups)} 组近似重复")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 运行测试确认通过**

Run: `cd /Users/minwang/RustroverProjects/lfun-team-pipeline && python3 -m pytest tests/test_duplicate_analyzer.py -v`
Expected: 所有测试 PASS

- [ ] **Step 3: Commit**

```bash
git add templates/.pipeline/autosteps/duplicate_analyzer.py tests/test_duplicate_analyzer.py
git commit -m "feat: implement duplicate-analyzer.py with Layer 1/2 detection"
```

---

## Chunk 2: Agent 定义

### Task 3: 创建 duplicate-generator Agent

**Files:**
- Create: `agents/duplicate-generator.md`

- [ ] **Step 1: 编写 Agent 定义**

```markdown
---
name: duplicate-generator
description: "重复组件整改方案生成器。读取重复候选列表和源码上下文，生成含 unified diff patch 的整改方案。仅在多角色软件交付流水线中使用。"
tools: Read, Glob, Grep, Bash
model: inherit
---

# Duplicate Generator — 整改方案生成器

## 角色

你是代码重构专家。根据重复组件检测结果，生成具体的整改方案（含 patch）。

## 输入

- `.pipeline/artifacts/duplicate-candidates.json` — 重复候选列表
- 项目源码文件（通过 Read/Grep 工具访问）
- 如有上次审计反馈，会附在 prompt 中

## 工作流程

1. 读取 `duplicate-candidates.json`
2. 对每组重复：
   a. 读取涉及的源码文件
   b. 使用 Grep 搜索项目中所有对被删除组件的引用（import/require/use）
   c. 决定保留哪个实现（优先选：位于公共目录、被引用更多、实现更完整的）
   d. 生成 unified diff 格式的 patch
3. 输出 `remediation-plan.json`

## 保留决策优先级

1. 位于 `utils/`、`shared/`、`common/` 等公共目录的
2. 被更多文件引用的（用 Grep 计数）
3. 实现更完整的（更多错误处理、更好的类型定义）
4. 有文档注释的

## 输出

写入 `.pipeline/artifacts/remediation-plan.json`，schema 见设计文档。

每个整改项必须包含：
- `action`：merge / delete / refactor
- `keep`：保留的组件及理由
- `remove`：删除的组件列表
- `steps`：有序的操作步骤，每步含 `patch`（unified diff）
- `impact_analysis`：影响分析

## 约束

- patch 必须是合法的 unified diff 格式
- 不能遗漏任何对被删除组件的引用更新
- 合并后的组件必须保留所有原有功能分支
- 不能引入循环依赖
```

- [ ] **Step 2: Commit**

```bash
git add agents/duplicate-generator.md
git commit -m "feat: add duplicate-generator agent definition"
```

---

### Task 4: 创建 duplicate-auditor Agent

**Files:**
- Create: `agents/duplicate-auditor.md`

- [ ] **Step 1: 编写 Agent 定义**

```markdown
---
name: duplicate-auditor
description: "重复组件整改方案审计员。独立审核整改方案的正确性和完整性，输出 audit-result.json。仅在多角色软件交付流水线中使用。"
tools: Read, Glob, Grep, Bash
model: inherit
---

# Duplicate Auditor — 整改方案审计员

## 角色

你是代码审计专家。独立审核重复组件整改方案的正确性，不接收生成过程的上下文。

## 输入

- `.pipeline/artifacts/remediation-plan.json` — 待审核的整改方案
- 项目源码文件（通过 Read/Grep 工具独立验证）

## 审核维度

对每个整改项（remediation），逐一验证：

1. **patch 语法正确性**：patch 应用后文件是否保持合法语法
2. **引用完整性**：使用 Grep 搜索整个项目，确认没有遗漏对被删除组件的引用
3. **功能完整性**：合并后的组件是否保留了原有的所有功能分支和错误处理
4. **路径正确性**：import/require 路径是否指向正确位置
5. **循环依赖**：整改是否引入了循环依赖

## 工作流程

1. 读取 `remediation-plan.json`
2. 对每个整改项：
   a. 读取涉及的源码文件，验证 patch 中的上下文行是否与实际文件匹配
   b. 用 Grep 搜索被删除组件的所有引用，对比 patch 中的引用更新是否完整
   c. 比较保留组件和被删除组件的功能，确认无丢失
   d. 验证新的 import 路径是否存在
3. 输出 `audit-result.json`

## 输出

写入 `.pipeline/artifacts/audit-result.json`：

```json
{
  "audited_at": "ISO-8601",
  "auditor_model": "当前模型名",
  "overall": "PASS 或 FAIL",
  "remediations": [
    {
      "group_id": "DUP-001",
      "verdict": "PASS 或 FAIL",
      "issues": ["具体问题描述（仅 FAIL 时）"],
      "notes": "审核备注"
    }
  ]
}
```

存在任何 verdict=FAIL → overall=FAIL。

## 约束

- **严格独立审核**：不要假设生成器的逻辑正确，独立验证每一项
- **宁严勿松**：有疑问时判 FAIL，附具体问题描述
- **不修改方案**：只审核，不尝试修复（修复是生成器的职责）
```

- [ ] **Step 2: Commit**

```bash
git add agents/duplicate-auditor.md
git commit -m "feat: add duplicate-auditor agent definition"
```

---

## Chunk 3: Shell 编排脚本

### Task 5: 创建 duplicate-detector.sh

**Files:**
- Create: `templates/.pipeline/autosteps/duplicate-detector.sh`

- [ ] **Step 1: 编写 Shell 编排脚本**

```bash
#!/usr/bin/env bash
# duplicate-detector.sh — Phase 3.0d 重复组件检测与整改
# 输入: MODE (full|refresh|incremental|check-only), PIPELINE_DIR
# 输出: .pipeline/artifacts/duplicate-report.json
# 退出码: 0=PASS(完成或无重复) 1=WARN(人工介入) 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
MODE="${MODE:-full}"
ARTIFACTS="$PIPELINE_DIR/artifacts"
CONFIG="$PIPELINE_DIR/config.json"
REGISTRY="$ARTIFACTS/component-registry.json"
CANDIDATES="$ARTIFACTS/duplicate-candidates.json"
REMEDIATION="$ARTIFACTS/remediation-plan.json"
AUDIT="$ARTIFACTS/audit-result.json"
REPORT="$ARTIFACTS/duplicate-report.json"
FEEDBACK_FILE="$ARTIFACTS/audit-feedback.txt"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$ARTIFACTS"

# ── 前置检查 ──
if [ ! -f "$REGISTRY" ]; then
  echo "[DuplicateDetector] component-registry.json 不存在，跳过"
  cat > "$REPORT" << EOF
{"autostep":"DuplicateDetector","timestamp":"$TIMESTAMP","status":"skipped","reason":"registry not found"}
EOF
  exit 0
fi

# 检查是否启用
DD_ENABLED=$(python3 -c "
import json
try:
    c = json.load(open('$CONFIG'))
    print(str(c.get('component_registry',{}).get('duplicate_detection',{}).get('enabled', True)).lower())
except: print('true')
" 2>/dev/null || echo "true")

if [ "$DD_ENABLED" = "false" ]; then
  echo "[DuplicateDetector] duplicate_detection.enabled=false，跳过"
  cat > "$REPORT" << EOF
{"autostep":"DuplicateDetector","timestamp":"$TIMESTAMP","status":"disabled"}
EOF
  exit 0
fi

# ── Step 1: Python 规则检测 ──
echo "[DuplicateDetector] Step 1: 规则检测（模式：$MODE）"
python3 "$PIPELINE_DIR/autosteps/duplicate_analyzer.py" \
  --registry "$REGISTRY" \
  --config "$CONFIG" \
  --output "$CANDIDATES" \
  --mode "$MODE"

if [ "$MODE" = "check-only" ]; then
  echo "[DuplicateDetector] --check-only 模式，仅输出候选列表"
  cp "$CANDIDATES" "$REPORT"
  exit 0
fi

# 检查是否有候选
CANDIDATE_COUNT=$(python3 -c "import json; print(len(json.load(open('$CANDIDATES')).get('candidates',[])))")
if [ "$CANDIDATE_COUNT" -eq 0 ]; then
  echo "[DuplicateDetector] 未发现重复组件"
  cat > "$REPORT" << EOF
{"autostep":"DuplicateDetector","timestamp":"$TIMESTAMP","status":"clean","stats":{"total_duplicates":0}}
EOF
  exit 0
fi

echo "[DuplicateDetector] 发现 $CANDIDATE_COUNT 组重复候选"

# ── 读取配置 ──
read -r CONFIGURED_MODEL MAX_RETRIES AUTO_APPLY <<< $(python3 -c "
import json
c = json.load(open('$CONFIG'))
dd = c.get('component_registry',{}).get('duplicate_detection',{})
model = dd.get('generator_model', 'auto')
retries = dd.get('max_retries_per_tier', 3)
auto = str(dd.get('auto_apply', False)).lower()
print(f'{model} {retries} {auto}')
")

# ── Step 2 + 3: 生成 + 审计循环 ──
AUDIT_RESULT="FAIL"
echo "" > "$FEEDBACK_FILE"

for TIER in "configured" "session"; do
  if [ "$TIER" = "configured" ] && [ "$CONFIGURED_MODEL" != "auto" ]; then
    MODEL_HINT="使用模型：$CONFIGURED_MODEL。"
  else
    MODEL_HINT=""
  fi

  for ATTEMPT in $(seq 1 "$MAX_RETRIES"); do
    echo "[DuplicateDetector] Tier=$TIER, Attempt=$ATTEMPT/$MAX_RETRIES"

    # Step 2: 生成
    FEEDBACK_CONTENT=$(cat "$FEEDBACK_FILE" 2>/dev/null || echo "")
    GENERATOR_PROMPT="读取 $CANDIDATES 中的重复候选列表和项目源码，为每组重复生成整改方案。输出到 $REMEDIATION。${MODEL_HINT}"
    if [ -n "$FEEDBACK_CONTENT" ]; then
      GENERATOR_PROMPT="$GENERATOR_PROMPT

上一次审计未通过，审计意见如下，请据此修正方案：
$FEEDBACK_CONTENT"
    fi

    echo "[DuplicateDetector]   生成整改方案..."
    claude --dangerously-skip-permissions --agent duplicate-generator \
      -p "$GENERATOR_PROMPT" 2>/dev/null || {
      echo "[DuplicateDetector]   生成器执行失败"
      continue
    }

    if [ ! -f "$REMEDIATION" ]; then
      echo "[DuplicateDetector]   remediation-plan.json 未生成"
      continue
    fi

    # Step 3: 审计（独立进程）
    echo "[DuplicateDetector]   审计整改方案..."
    claude --dangerously-skip-permissions --agent duplicate-auditor \
      -p "审核 $REMEDIATION 中的整改方案正确性，独立验证每个 patch。输出到 $AUDIT。" 2>/dev/null || {
      echo "[DuplicateDetector]   审计器执行失败"
      continue
    }

    if [ ! -f "$AUDIT" ]; then
      echo "[DuplicateDetector]   audit-result.json 未生成"
      continue
    fi

    AUDIT_RESULT=$(python3 -c "import json; print(json.load(open('$AUDIT')).get('overall','FAIL'))")
    if [ "$AUDIT_RESULT" = "PASS" ]; then
      echo "[DuplicateDetector]   审计通过！"
      break 2
    fi

    echo "[DuplicateDetector]   审计未通过，提取反馈..."
    python3 -c "
import json
r = json.load(open('$AUDIT'))
issues = []
for rem in r.get('remediations', []):
    if rem.get('verdict') == 'FAIL':
        for issue in rem.get('issues', []):
            issues.append(f\"[{rem['group_id']}] {issue}\")
with open('$FEEDBACK_FILE', 'w') as f:
    f.write('\n'.join(issues))
"
  done
done

# ── Step 4: 生成最终报告 ──
if [ "$AUDIT_RESULT" = "PASS" ]; then
  STATUS="ready"
else
  STATUS="manual_needed"
fi

python3 -c "
import json, datetime
candidates = json.load(open('$CANDIDATES'))
status = '$STATUS'
report = {
    'report_time': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'mode': '$MODE',
    'status': status,
    'duplicates': candidates.get('candidates', []),
    'stats': candidates.get('stats', {})
}
try:
    remediation = json.load(open('$REMEDIATION'))
    report['remediation_summary'] = remediation.get('summary', {})
except: pass
try:
    audit = json.load(open('$AUDIT'))
    report['audit_model'] = audit.get('auditor_model', '')
except: pass
with open('$REPORT', 'w') as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
"

echo "[DuplicateDetector] 最终报告：$REPORT"

if [ "$STATUS" = "manual_needed" ]; then
  echo "[DuplicateDetector] WARN: 整改方案审计未通过，需人工介入"
  exit 1
fi

if [ "$AUTO_APPLY" = "true" ]; then
  echo "[DuplicateDetector] auto_apply=true，自动应用（实现待 patch apply 机制）"
fi

exit 0
```

- [ ] **Step 2: 设置可执行权限并 Commit**

```bash
chmod +x templates/.pipeline/autosteps/duplicate-detector.sh
git add templates/.pipeline/autosteps/duplicate-detector.sh
git commit -m "feat: add duplicate-detector.sh shell orchestration script"
```

---

## Chunk 4: CLI 与配置集成

### Task 6: 更新 config.json 模板

**Files:**
- Modify: `templates/.pipeline/config.json`

- [ ] **Step 1: 在 config.json 末尾添加 component_registry 配置块**

先检查 `templates/.pipeline/config.json` 是否已有 `component_registry` 块（可能由 Component Registry spec 先行添加）。

**如果不存在**：在 `"autosteps"` 块之后，最外层 `}` 之前追加完整块：

```jsonc
  "component_registry": {
    "enabled": true,
    "summary_provider": "auto",
    "ollama_model": "qwen2.5-coder:7b",
    "ollama_url": "http://localhost:11434",
    "exclude_patterns": ["test/**", "bench/**", "examples/**"],
    "min_complexity": 3,
    "duplicate_detection": {
      "enabled": true,
      "generator_model": "auto",
      "similarity_threshold": 0.7,
      "tag_overlap_threshold": 0.7,
      "max_retries_per_tier": 3,
      "exclude_pairs": [],
      "auto_apply": false
    }
  }
```

**如果已存在**：只在现有 `component_registry` 块内追加 `duplicate_detection` 子块。

- [ ] **Step 2: Commit**

```bash
git add templates/.pipeline/config.json
git commit -m "feat: add component_registry config block with duplicate_detection"
```

---

### Task 7: 更新 install.sh — cmd_scan() 和路由

**Files:**
- Modify: `install.sh:78-98` (usage)
- Modify: `install.sh:139-143` (cmd_init, 支持 .py)
- Modify: `install.sh:196` (cmd_upgrade, 支持 .py)
- Modify: `install.sh:630-638` (case 路由)
- 新增 `cmd_scan()` 函数

- [ ] **Step 1: 在 usage() 中添加 scan 命令**

在 `install.sh` 的 `usage()` 函数中，`run` 行之后添加：

```
    echo "    scan      Scan codebase for components and detect duplicates"
```

- [ ] **Step 2: 在 cmd_init() 中支持 .py autostep 文件**

将 `install.sh` 中 `cmd_init()` 的 autostep 复制逻辑从只匹配 `*.sh` 改为匹配 `*.sh` 和 `*.py`：

```bash
  done < <(find "$TEAM_HOME/.pipeline/autosteps" -name "*.sh" -o -name "*.py" | sort)
```

- [ ] **Step 3: 在 cmd_upgrade() 中支持 .py autostep 文件**

在 `install.sh` 中 `cmd_upgrade()` 的 autostep 升级行添加 .py 支持：

```bash
  cp "$TEAM_HOME/.pipeline/autosteps/"*.sh "$TEAM_HOME/.pipeline/autosteps/"*.py .pipeline/autosteps/ 2>/dev/null || true
  AUTOSTEP_COUNT=$(ls .pipeline/autosteps/*.sh .pipeline/autosteps/*.py 2>/dev/null | wc -l)
```

- [ ] **Step 4: 添加 cmd_scan() 函数**

在最后一个 `cmd_*` 函数定义之后、`case "${1:-}" in` 之前添加：

```bash
cmd_scan() {
  if [ ! -d ".pipeline" ]; then
    echo "❌ No .pipeline/ directory found. Run: team init"
    exit 1
  fi

  if [ ! -f ".pipeline/artifacts/component-registry.json" ]; then
    echo "❌ No component registry found. Run the pipeline first to generate component-registry.json"
    exit 1
  fi

  local MODE="full"
  case "${1:-}" in
    --refresh)    MODE="refresh" ;;
    --check-only) MODE="check-only" ;;
    "")           MODE="full" ;;
    *)
      echo "Usage: team scan [--refresh|--check-only]"
      exit 1
      ;;
  esac

  echo ""
  echo "  ▶ Duplicate Detector — mode: $MODE"
  echo ""

  MODE="$MODE" PIPELINE_DIR=".pipeline" \
    bash .pipeline/autosteps/duplicate-detector.sh

  echo ""
}
```

- [ ] **Step 5: 在 case 路由中添加 scan**

在 `install.sh` 的 case 语句中添加：

```bash
  scan)    cmd_scan "${2:-}" ;;
```

- [ ] **Step 6: Commit**

```bash
git add install.sh
git commit -m "feat: integrate team scan command with --check-only and --refresh flags"
```

---

## Chunk 5: Orchestrator 集成

### Task 8: 更新 orchestrator.md 路由表

**前置说明：** phase-3.0c（Component Extractor）尚未实现，属于组件注册表 spec 的范围。当前 orchestrator 路由从 `phase-3.0b → phase-3.1`。Duplicate Detector 直接插入为 `phase-3.0b → phase-3.0d → phase-3.1`。待 Component Extractor 实现后，顺序变为 `phase-3.0b → phase-3.0c → phase-3.0d → phase-3.1`。

**注意：** duplicate-generator 和 duplicate-auditor 由 `duplicate-detector.sh` Shell 脚本通过 `claude --agent` 调用，不由 Orchestrator 直接调度。因此**不需要**在 Orchestrator 的 tools 声明中添加这两个 Agent。Orchestrator 只通过 Bash 工具运行 `duplicate-detector.sh`。

**Files:**
- Modify: `agents/orchestrator.md` (batch-post-build 新增 phase-3.0d)
- Modify: `agents/orchestrator.md` (线性流路由表插入 phase-3.0d)

- [ ] **Step 1: 先读取 orchestrator.md 确认当前路由表内容**

Run: `head -100 agents/orchestrator.md`
找到 batch-post-build 行和线性流路由表的精确内容。

- [ ] **Step 2: 在 batch-post-build 中添加 phase-3.0d**

在 orchestrator.md 的批次表中，将 batch-post-build 从：
```
| batch-post-build | phase-3.1 + phase-3.2 + phase-3.3 + phase-3.5 + phase-3.6 |
```
改为：
```
| batch-post-build | phase-3.0d + phase-3.1 + phase-3.2 + phase-3.3 + phase-3.5 + phase-3.6 |
```

- [ ] **Step 3: 在线性流路由表中插入 phase-3.0d**

在 `phase-3.0b → phase-3.1` 之间插入 `phase-3.0d`：
```
phase-3.0b → phase-3.0d → phase-3.1
```

- [ ] **Step 4: 添加 phase-3.0d 的分支/回滚规则**

phase-3.0d 非阻塞，不回滚：
```
- phase-3.0d FAIL → WARN 继续 phase-3.1（非阻塞，不触发回滚）
```

- [ ] **Step 5: 添加 phase-3.0d 的 AutoStep 执行说明**

在 orchestrator.md 中与其他 AutoStep（如 phase-3.0b）类似的位置，添加 phase-3.0d 的执行方式：
```
phase-3.0d: MODE="${MODE:-incremental}" PIPELINE_DIR=".pipeline" bash .pipeline/autosteps/duplicate-detector.sh
```

- [ ] **Step 6: Commit**

```bash
git add agents/orchestrator.md
git commit -m "feat: add phase-3.0d duplicate-detector to orchestrator routing"
```

---

### Task 9: 更新 install.sh Agent 安装

**Files:**
- 无需修改 — `install.sh` 的 Step 1 已通过 `find "$AGENTS_SRC" -maxdepth 1 -name "*.md" | sort` 自动安装所有 `agents/*.md` 文件。新增的 `duplicate-generator.md` 和 `duplicate-auditor.md` 会自动包含。

- [ ] **Step 1: 验证自动安装**

Run: `ls agents/*.md | wc -l`
Expected: 28（原 26 + 新增 2）

- [ ] **Step 2: 运行完整测试套件**

Run: `cd /Users/minwang/RustroverProjects/lfun-team-pipeline && python3 -m pytest tests/ -v`
Expected: 所有测试 PASS

- [ ] **Step 3: 最终 Commit（如有遗漏修改）**

```bash
git status
# 如有遗漏，补充 add + commit
```
