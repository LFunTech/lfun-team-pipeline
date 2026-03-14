#!/usr/bin/env python3
"""
duplicate_analyzer.py — 重复组件规则检测脚本
Layer 1: 精确重复（签名完全相同）
Layer 2: 近似重复（名称相似 + 参数类型兼容）

输入: component-registry.json
输出: duplicate-candidates.json

仅使用 Python 标准库，无外部依赖。
"""

import argparse
import copy
import json
import re
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
    """规范化签名：去除多余空白"""
    return re.sub(r'\s+', ' ', sig.strip())


def extract_param_types(sig):
    """从签名中提取参数类型列表（括号内内容，去除空白）"""
    m = re.search(r'\(([^)]*)\)', sig)
    if not m:
        return ""
    return re.sub(r'\s+', '', m.group(1))


def _split_name_tokens(name):
    """将 camelCase/snake_case/PascalCase 名称拆分为小写 token 集合"""
    # 先按 snake_case 拆分
    parts = name.replace('-', '_').split('_')
    tokens = []
    for part in parts:
        # 按 camelCase 边界拆分: "validateEmail" → ["validate", "Email"]
        words = re.findall(r'[A-Z]?[a-z]+|[A-Z]+(?=[A-Z][a-z]|\d|\b)', part)
        tokens.extend(w.lower() for w in words)
    return tokens


def name_similarity(a, b):
    """计算名称相似度 (0.0 ~ 1.0)

    综合多种策略取较高值：
    1. SequenceMatcher 字符级相似度
    2. camelCase token Jaccard 相似度
    3. 去除常见动词前缀后比较剩余部分（捕获 validateEmail vs checkEmail 场景）
    """
    # 策略 1: 字符级
    char_sim = SequenceMatcher(None, a.lower(), b.lower()).ratio()

    # 策略 2: token 级 Jaccard
    tokens_a = _split_name_tokens(a)
    tokens_b = _split_name_tokens(b)
    set_a = set(tokens_a)
    set_b = set(tokens_b)
    if set_a and set_b:
        union = set_a | set_b
        intersection = set_a & set_b
        token_sim = len(intersection) / len(union) if union else 0.0
    else:
        token_sim = 0.0

    # 策略 3: 去除首个 token（通常是动词前缀），比较剩余部分
    # 捕获 validateEmail vs checkEmail, getUser vs fetchUser 等场景
    suffix_sim = 0.0
    if len(tokens_a) >= 2 and len(tokens_b) >= 2:
        suffix_a = ''.join(tokens_a[1:])
        suffix_b = ''.join(tokens_b[1:])
        if suffix_a and suffix_b:
            suffix_ratio = SequenceMatcher(None, suffix_a, suffix_b).ratio()
            # 如果去掉动词后剩余部分高度相似，给予较高分
            # 0.8 * suffix_ratio 确保完全匹配的后缀得到 0.8 分
            suffix_sim = 0.8 * suffix_ratio

    return max(char_sim, token_sim, suffix_sim)


def is_excluded(c1, c2, exclude_pairs):
    """检查组件对是否在排除列表中（使用 name@path 格式）"""
    key1 = f"{c1['name']}@{c1['path'].split(':')[0]}"
    key2 = f"{c2['name']}@{c2['path'].split(':')[0]}"
    for pair in exclude_pairs:
        a, b = pair.get("a", ""), pair.get("b", "")
        if {a, b} == {key1, key2}:
            return True
    return False


def is_test_path(path):
    """检查路径是否为测试文件"""
    # 去除行号后缀（如 :25）
    file_path = path.split(':')[0].lower()
    # 路径以 test/ 或 tests/ 开头
    if file_path.startswith(('test/', 'tests/', '__tests__/')):
        return True
    # 路径中包含 /test/ /tests/ /__tests__/ 目录
    if any(seg in file_path for seg in ['/test/', '/tests/', '/__tests__/']):
        return True
    # 文件名包含 .test. .spec. _test.
    basename = file_path.rsplit('/', 1)[-1] if '/' in file_path else file_path
    if any(seg in basename for seg in ['.test.', '.spec.', '_test.']):
        return True
    return False


def find_exact_duplicates(components, exclude_pairs=None):
    """Layer 1: 签名完全相同的精确重复检测

    按规范化签名分组，同组内 ≥ 2 个组件即为精确重复。
    排除测试文件和 exclude_pairs 中的组件对。
    """
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
        # 过滤排除对：仅当组恰好为 2 成员且该对被排除时才跳过整组
        # 对于 3+ 成员组，排除对不适用（组比排除对大，仍有真正重复）
        if len(members) == 2:
            if is_excluded(members[0], members[1], exclude_pairs):
                continue
            filtered = members
        else:
            # 3+ 成员：保留所有成员，排除对不影响整组
            filtered = members

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
    """Layer 2: 名称相似 + 参数类型兼容的近似重复检测

    对未被 Layer 1 覆盖的组件，两两比较名称相似度和参数类型。
    名称相似度 ≥ threshold 且参数类型完全相同时，归为一组。
    """
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
            # 置信度：0.7 ~ 0.89，按相似度线性插值
            if threshold >= 1.0 or sim_val >= 1.0:
                confidence = 0.89
            else:
                confidence = round(0.7 + (sim_val - threshold) * 0.3 / (1 - threshold), 2)
            groups.append({
                "level": "similar",
                "confidence": confidence,
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
    # 深拷贝避免修改调用者的原始数据
    groups = copy.deepcopy(groups)
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
        print("[DuplicateAnalyzer] 注册表为空，跳过检测")
        return

    exclude_pairs = config.get("exclude_pairs", [])
    threshold = config.get("similarity_threshold", 0.7)

    # Layer 1: 精确重复
    exact_groups = find_exact_duplicates(components, exclude_pairs)
    exact_ids = set()
    for g in exact_groups:
        for c in g["components"]:
            exact_ids.add(c["id"])

    # Layer 2: 近似重复
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
