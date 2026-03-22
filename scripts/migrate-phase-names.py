#!/usr/bin/env python3
"""
Phase 名称语义化迁移脚本

用法:
  # 预览变更（不写入文件）
  python3 scripts/migrate-phase-names.py --dry-run

  # 执行迁移（修改文件）
  python3 scripts/migrate-phase-names.py

  # 迁移已有项目的 state.json / config.json
  python3 scripts/migrate-phase-names.py --migrate-state /path/to/project/.pipeline/state.json
  python3 scripts/migrate-phase-names.py --migrate-config /path/to/project/.pipeline/config.json
"""

import json
import re
import sys
import os
from pathlib import Path

# ============================================================
# 完整映射表（旧 ID → 新 ID）
# ============================================================
PHASE_MAPPING = {
    # phase-X.Y 格式（按长度降序排列，避免子串误替换）
    "phase-4a.1":  "4a.1.test-failure-map",
    "phase-3.0b":  "3.0b.build-verify",
    "phase-3.0d":  "3.0d.duplicate-detect",
    "phase-2.0a":  "2.0a.repo-setup",
    "phase-2.0b":  "2.0b.depend-collect",
    "phase-0.5":   "0.5.requirement-check",
    "phase-3.5":   "3.5.simplify",
    "phase-3.6":   "3.6.simplify-verify",
    "phase-3.7":   "3.7.contract-compliance",
    "phase-3.1":   "3.1.static-analyze",
    "phase-3.2":   "3.2.diff-validate",
    "phase-3.3":   "3.3.regression-guard",
    "phase-2.5":   "2.5.contract-formalize",
    "phase-2.6":   "2.6.contract-validate-semantic",
    "phase-2.7":   "2.7.contract-validate-schema",
    "phase-2.1":   "2.1.assumption-check",
    "phase-5.1":   "5.1.changelog-check",
    "phase-5.9":   "5.9.ci-push",
    "phase-6.0":   "6.0.deploy-readiness",
    "phase-4.2":   "4.2.coverage-check",
    "phase-4a":    "4a.test",
    "phase-4b":    "4b.optimize",
    "phase-0":     "0.clarify",
    "phase-1":     "1.design",
    "phase-2":     "2.plan",
    "phase-3":     "3.build",
    "phase-5":     "5.document",
    "phase-6":     "6.deploy",
    "phase-7":     "7.monitor",
}

GATE_MAPPING = {
    "gate-a": "gate-a.design-review",
    "gate-b": "gate-b.plan-review",
    "gate-c": "gate-c.code-review",
    "gate-d": "gate-d.test-review",
    "gate-e": "gate-e.doc-review",
}

OTHER_MAPPING = {
    "api-change-detector": "api-change-detect",
}

# "Phase X" 格式（大写，用于 prose/playbook 标题）
PROSE_PHASE_MAPPING = {
    "Phase 4a.1":  "4a.1.test-failure-map",
    "Phase 3.0b":  "3.0b.build-verify",
    "Phase 3.0d":  "3.0d.duplicate-detect",
    "Phase 2.0a":  "2.0a.repo-setup",
    "Phase 2.0b":  "2.0b.depend-collect",
    "Phase 0.5":   "0.5.requirement-check",
    "Phase 3.5":   "3.5.simplify",
    "Phase 3.6":   "3.6.simplify-verify",
    "Phase 3.7":   "3.7.contract-compliance",
    "Phase 3.1":   "3.1.static-analyze",
    "Phase 3.2":   "3.2.diff-validate",
    "Phase 3.3":   "3.3.regression-guard",
    "Phase 2.5":   "2.5.contract-formalize",
    "Phase 2.6":   "2.6.contract-validate-semantic",
    "Phase 2.7":   "2.7.contract-validate-schema",
    "Phase 2.1":   "2.1.assumption-check",
    "Phase 5.1":   "5.1.changelog-check",
    "Phase 5.9":   "5.9.ci-push",
    "Phase 6.0":   "6.0.deploy-readiness",
    "Phase 4.2":   "4.2.coverage-check",
    "Phase 4a":    "4a.test",
    "Phase 4b":    "4b.optimize",
    "Phase 0":     "0.clarify",
    "Phase 1":     "1.design",
    "Phase 2":     "2.plan",
    "Phase 3":     "3.build",
    "Phase 5":     "5.document",
    "Phase 6":     "6.deploy",
    "Phase 7":     "7.monitor",
}

PROSE_GATE_MAPPING = {
    "Gate A": "gate-a.design-review",
    "Gate B": "gate-b.plan-review",
    "Gate C": "gate-c.code-review",
    "Gate D": "gate-d.test-review",
    "Gate E": "gate-e.doc-review",
}


def build_replacement_pairs():
    """构建替换对列表，按旧值长度降序排列（防止子串误替换）"""
    pairs = []
    # ID 形式
    for old, new in PHASE_MAPPING.items():
        pairs.append((old, new))
    for old, new in GATE_MAPPING.items():
        pairs.append((old, new))
    for old, new in OTHER_MAPPING.items():
        pairs.append((old, new))
    # Prose 形式
    for old, new in PROSE_PHASE_MAPPING.items():
        pairs.append((old, new))
    for old, new in PROSE_GATE_MAPPING.items():
        pairs.append((old, new))
    # 按旧值长度降序（长的先替换）
    pairs.sort(key=lambda x: len(x[0]), reverse=True)
    return pairs


def apply_replacements(text, pairs):
    """
    安全替换：用占位符两阶段替换，避免链式替换问题。
    例如 "phase-3" 替换为 "3.build" 后，不会被后续规则再次匹配。
    """
    placeholders = {}
    result = text

    # 阶段 1：用唯一占位符替换所有旧值
    for i, (old, new) in enumerate(pairs):
        placeholder = f"\x00MIGRATE_{i}\x00"
        placeholders[placeholder] = new
        # 使用 word boundary 避免部分匹配
        # 但要小心：phase-3.0b 中的 "phase-3" 不应被匹配
        # 由于我们按长度降序，长的先替换，所以 phase-3.0b 会先被替换为占位符
        # 之后 phase-3 就不会匹配到已被替换的位置了
        result = result.replace(old, placeholder)

    # 阶段 2：用新值替换占位符
    for placeholder, new in placeholders.items():
        result = result.replace(placeholder, new)

    return result


def get_target_files(repo_root):
    """获取需要迁移的文件列表"""
    targets = []

    # agents/*.md
    agents_dir = repo_root / "agents"
    if agents_dir.exists():
        for f in agents_dir.glob("*.md"):
            targets.append(f)

    # templates/.pipeline/playbook.md
    playbook = repo_root / "templates" / ".pipeline" / "playbook.md"
    if playbook.exists():
        targets.append(playbook)

    # templates/.pipeline/config.json
    config_tpl = repo_root / "templates" / ".pipeline" / "config.json"
    if config_tpl.exists():
        targets.append(config_tpl)

    # templates/CLAUDE.md
    claude_tpl = repo_root / "templates" / "CLAUDE.md"
    if claude_tpl.exists():
        targets.append(claude_tpl)

    # CLAUDE.md (项目根)
    claude_root = repo_root / "CLAUDE.md"
    if claude_root.exists():
        targets.append(claude_root)

    # claude-code-multi-agent-team-design.md
    design_doc = repo_root / "claude-code-multi-agent-team-design.md"
    if design_doc.exists():
        targets.append(design_doc)

    return targets


def migrate_file(filepath, pairs, dry_run=False):
    """迁移单个文件"""
    with open(filepath, "r", encoding="utf-8") as f:
        original = f.read()

    migrated = apply_replacements(original, pairs)

    if original == migrated:
        return 0  # 无变更

    if dry_run:
        # 统计变更数量
        changes = 0
        for old, new in pairs:
            changes += original.count(old)
        print(f"  [DRY-RUN] {filepath}: {changes} 处替换")
        return changes
    else:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(migrated)
        changes = 0
        for old, new in pairs:
            changes += original.count(old)
        print(f"  [DONE] {filepath}: {changes} 处替换")
        return changes


def migrate_state_json(filepath):
    """迁移已有项目的 state.json"""
    with open(filepath, "r", encoding="utf-8") as f:
        state = json.load(f)

    pairs = build_replacement_pairs()
    changed = False

    # current_phase
    if "current_phase" in state:
        old = state["current_phase"]
        new = apply_replacements(old, pairs)
        if old != new:
            state["current_phase"] = new
            changed = True

    # last_completed_phase
    if "last_completed_phase" in state:
        old = state["last_completed_phase"]
        if old:
            new = apply_replacements(old, pairs)
            if old != new:
                state["last_completed_phase"] = new
                changed = True

    # attempt_counts
    if "attempt_counts" in state:
        new_counts = {}
        for key, val in state["attempt_counts"].items():
            new_key = apply_replacements(key, pairs)
            new_counts[new_key] = val
            if new_key != key:
                changed = True
        state["attempt_counts"] = new_counts

    # execution_log
    if "execution_log" in state:
        for entry in state["execution_log"]:
            if "step" in entry:
                old = entry["step"]
                new = apply_replacements(old, pairs)
                if old != new:
                    entry["step"] = new
                    changed = True
            if "rollback_to" in entry and entry["rollback_to"]:
                old = entry["rollback_to"]
                new = apply_replacements(old, pairs)
                if old != new:
                    entry["rollback_to"] = new
                    changed = True

    if changed:
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2, ensure_ascii=False)
        print(f"  [DONE] state.json 迁移完成: {filepath}")
    else:
        print(f"  [SKIP] state.json 无需迁移: {filepath}")


def migrate_config_json(filepath):
    """迁移已有项目的 config.json"""
    with open(filepath, "r", encoding="utf-8") as f:
        config = json.load(f)

    pairs = build_replacement_pairs()
    changed = False

    # max_attempts — 兼容 int（旧版简单值）和 dict（按阶段配置）两种格式
    if "max_attempts" in config and isinstance(config["max_attempts"], dict):
        new_attempts = {}
        for key, val in config["max_attempts"].items():
            new_key = apply_replacements(key, pairs)
            new_attempts[new_key] = val
            if new_key != key:
                changed = True
        config["max_attempts"] = new_attempts

    # phases.enabled — 数组中的旧 phase 名替换
    if "phases" in config and isinstance(config["phases"], dict):
        if "enabled" in config["phases"] and isinstance(config["phases"]["enabled"], list):
            new_enabled = []
            for item in config["phases"]["enabled"]:
                if isinstance(item, str):
                    new_item = apply_replacements(item, pairs)
                    if new_item != item:
                        changed = True
                    new_enabled.append(new_item)
                else:
                    new_enabled.append(item)
            config["phases"]["enabled"] = new_enabled

    # gates
    if "gates" in config:
        new_gates = {}
        for gate_key, gate_val in config["gates"].items():
            new_gate_key = apply_replacements(gate_key, pairs)
            new_gate_val = {}
            for k, v in gate_val.items():
                if isinstance(v, list):
                    new_v = [apply_replacements(item, pairs) if isinstance(item, str) else item for item in v]
                    if new_v != v:
                        changed = True
                    new_gate_val[k] = new_v
                elif isinstance(v, str):
                    new_v = apply_replacements(v, pairs)
                    if new_v != v:
                        changed = True
                    new_gate_val[k] = new_v
                else:
                    new_gate_val[k] = v
            new_gates[new_gate_key] = new_gate_val
            if new_gate_key != gate_key:
                changed = True
        config["gates"] = new_gates

    if changed:
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        print(f"  [DONE] config.json 迁移完成: {filepath}")
    else:
        print(f"  [SKIP] config.json 无需迁移: {filepath}")


def main():
    args = sys.argv[1:]
    dry_run = "--dry-run" in args

    # 迁移已有项目的 state.json
    if "--migrate-state" in args:
        idx = args.index("--migrate-state")
        if idx + 1 < len(args):
            migrate_state_json(args[idx + 1])
        return

    # 迁移已有项目的 config.json
    if "--migrate-config" in args:
        idx = args.index("--migrate-config")
        if idx + 1 < len(args):
            migrate_config_json(args[idx + 1])
        return

    # 默认：迁移模板和 agent 文件
    repo_root = Path(__file__).parent.parent
    pairs = build_replacement_pairs()
    targets = get_target_files(repo_root)

    if not targets:
        print("未找到需要迁移的文件")
        return

    print(f"发现 {len(targets)} 个文件需要迁移")
    if dry_run:
        print("（预览模式，不写入文件）\n")
    else:
        print()

    total = 0
    for f in sorted(targets):
        total += migrate_file(f, pairs, dry_run=dry_run)

    print(f"\n总计 {total} 处替换")

    if dry_run:
        print("\n运行 `python3 scripts/migrate-phase-names.py` 执行迁移")
    else:
        print("\n迁移完成！请检查文件变更。")
        print("\n对于已有项目，另需运行：")
        print("  python3 scripts/migrate-phase-names.py --migrate-state /path/to/.pipeline/state.json")
        print("  python3 scripts/migrate-phase-names.py --migrate-config /path/to/.pipeline/config.json")


if __name__ == "__main__":
    main()
