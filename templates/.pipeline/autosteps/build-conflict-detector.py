#!/usr/bin/env python3
"""3.build 波次内文件冲突检测。"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


PIPELINE_DIR = Path(os.environ.get("PIPELINE_DIR", ".pipeline"))
ARTIFACTS_DIR = PIPELINE_DIR / "artifacts"
TASKS_FILE = ARTIFACTS_DIR / "tasks.json"
OUTPUT_FILE = ARTIFACTS_DIR / "build-conflict-report.json"

ORDER = ["dba", "migrator", "backend", "security", "frontend", "translator", "infra"]
BUILDER_MAP = {
    "Builder-DBA": "dba",
    "Builder-Migrator": "migrator",
    "Builder-Backend": "backend",
    "Builder-Security": "security",
    "Builder-Frontend": "frontend",
    "Builder-Translator": "translator",
    "Builder-Infra": "infra",
}


def sort_key(name: str) -> tuple[int, str]:
    try:
        return (ORDER.index(name), name)
    except ValueError:
        return (len(ORDER), name)


def normalize_selected_builders(raw: str | None) -> list[str]:
    if not raw:
        return []
    selected = []
    for item in raw.split(","):
        name = item.strip().lower()
        if name and name not in selected:
            selected.append(name)
    return sorted(selected, key=sort_key)


def main() -> int:
    if not TASKS_FILE.exists():
        OUTPUT_FILE.write_text(
            json.dumps(
                {
                    "autostep": "BuildConflictDetector",
                    "overall": "ERROR",
                    "error": "tasks.json not found",
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        return 2

    data = json.loads(TASKS_FILE.read_text(encoding="utf-8"))
    selected = normalize_selected_builders(os.environ.get("BUILDERS"))

    builder_files: dict[str, set[str]] = {name: set() for name in selected}
    task_ids: dict[str, list[str]] = {name: [] for name in selected}

    for task in data.get("tasks", []):
        short = BUILDER_MAP.get(task.get("assigned_to", ""))
        if not short:
            continue
        if selected and short not in builder_files:
            continue
        builder_files.setdefault(short, set())
        task_ids.setdefault(short, [])
        if task.get("id"):
            task_ids[short].append(task["id"])
        for file_item in task.get("files", []):
            path = file_item.get("path") if isinstance(file_item, dict) else None
            if path:
                builder_files[short].add(path)

    if not selected:
        selected = sorted(builder_files.keys(), key=sort_key)

    path_to_builders: dict[str, list[str]] = {}
    for builder, paths in builder_files.items():
        for path in paths:
            path_to_builders.setdefault(path, []).append(builder)

    overlap_paths = []
    overlap_builders = set()
    for path, builders in sorted(path_to_builders.items()):
        uniq = sorted(set(builders), key=sort_key)
        if len(uniq) > 1:
            overlap_paths.append({"path": path, "builders": uniq})
            overlap_builders.update(uniq)

    result = {
        "autostep": "BuildConflictDetector",
        "overall": "OVERLAP" if overlap_paths else "PASS",
        "selected_builders": selected,
        "builder_files": {k: sorted(v) for k, v in sorted(builder_files.items(), key=lambda item: sort_key(item[0]))},
        "task_ids": {k: sorted(v) for k, v in sorted(task_ids.items(), key=lambda item: sort_key(item[0]))},
        "overlap_paths": overlap_paths,
        "overlap_builders": sorted(overlap_builders, key=sort_key),
        "serial_execution_order": sorted(overlap_builders, key=sort_key),
    }

    OUTPUT_FILE.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(result["overall"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
