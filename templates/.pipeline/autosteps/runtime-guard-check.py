#!/usr/bin/env python3
"""Check whether parallel conflict guards are present in the current repo runtime."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


PIPELINE_DIR = Path(os.environ.get("PIPELINE_DIR", ".pipeline"))
ARTIFACTS_DIR = PIPELINE_DIR / "artifacts"
OUTPUT_FILE = ARTIFACTS_DIR / "runtime-guard-check.json"


def contains(path: Path, needle: str) -> bool:
    if not path.exists():
        return False
    try:
        return needle in path.read_text(encoding="utf-8")
    except Exception:
        return False


def main() -> int:
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)

    checks = []

    required_files = [
        (PIPELINE_DIR / "autosteps" / "build-conflict-detector.py", "build conflict detector exists"),
        (PIPELINE_DIR / "autosteps" / "parallel-proposal-detector.py", "parallel proposal detector exists"),
        (PIPELINE_DIR / "autosteps" / "impl-manifest-merger.sh", "impl manifest merger exists"),
    ]
    for path, label in required_files:
        checks.append({
            "name": label,
            "ok": path.exists(),
            "path": str(path),
        })

    playbook = PIPELINE_DIR / "playbook.md"
    checks.extend([
        {
            "name": "playbook mentions build conflict detector",
            "ok": contains(playbook, "build-conflict-detector.py"),
            "path": str(playbook),
        },
        {
            "name": "playbook mentions parallel proposal detector",
            "ok": contains(playbook, "parallel-proposal-detector.py"),
            "path": str(playbook),
        },
        {
            "name": "playbook tracks phase_3_wave_bases",
            "ok": contains(playbook, "phase_3_wave_bases"),
            "path": str(playbook),
        },
    ])

    impl_merger = PIPELINE_DIR / "autosteps" / "impl-manifest-merger.sh"
    checks.extend([
        {
            "name": "impl merger checks duplicate paths",
            "ok": contains(impl_merger, "duplicate_paths"),
            "path": str(impl_merger),
        },
        {
            "name": "impl merger checks duplicate task ids",
            "ok": contains(impl_merger, "duplicate_task_ids"),
            "path": str(impl_merger),
        },
    ])

    state_path = PIPELINE_DIR / "state.json"
    if state_path.exists():
        try:
            state = json.loads(state_path.read_text(encoding="utf-8"))
            checks.extend([
                {
                    "name": "state has phase_3_wave_bases",
                    "ok": "phase_3_wave_bases" in state,
                    "path": str(state_path),
                },
                {
                    "name": "state has phase_3_conflict_files",
                    "ok": "phase_3_conflict_files" in state,
                    "path": str(state_path),
                },
                {
                    "name": "state has parallel_precheck_report",
                    "ok": "parallel_precheck_report" in state,
                    "path": str(state_path),
                },
            ])
        except Exception as exc:
            checks.append({
                "name": "state.json parseable",
                "ok": False,
                "path": str(state_path),
                "error": str(exc),
            })
    else:
        checks.append({
            "name": "state.json exists",
            "ok": False,
            "path": str(state_path),
        })

    overall = "PASS" if all(item["ok"] for item in checks) else "FAIL"
    result = {"autostep": "RuntimeGuardCheck", "overall": overall, "checks": checks}
    OUTPUT_FILE.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    for item in checks:
        prefix = "OK" if item["ok"] else "MISS"
        print(f"[{prefix}] {item['name']}: {item['path']}")
    print(overall)
    return 0 if overall == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
