#!/usr/bin/env python3
"""
build-agents.py — Multi-platform Agent Transpiler

Reads canonical agent definitions from agents/*.md (Claude Code format)
and generates platform-specific variants for CC, Codex, Cursor, and OpenCode.

Usage:
    python3 scripts/build-agents.py [--platforms cc,codex,cursor,opencode] [--output dist/]
"""

import argparse
import os
import re
import sys
import textwrap
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
AGENTS_DIR = REPO_ROOT / "agents"
DEFAULT_OUTPUT = REPO_ROOT / "dist"

ALL_PLATFORMS = ["cc", "codex", "cursor", "opencode"]


def parse_frontmatter(content: str) -> tuple[dict, str]:
    """Parse YAML frontmatter and body from a markdown agent file."""
    if not content.startswith("---"):
        return {}, content

    end = content.index("---", 3)
    fm_text = content[3:end].strip()
    body = content[end + 3:].strip()

    fm = {}
    current_key = None
    current_list = None

    for line in fm_text.split("\n"):
        stripped = line.strip()

        if stripped.startswith("- ") and current_list is not None:
            current_list.append(stripped[2:].strip())
            continue

        if current_list is not None:
            fm[current_key] = current_list
            current_list = None

        if ":" not in stripped:
            if current_key and current_key in fm and isinstance(fm[current_key], str):
                fm[current_key] += " " + stripped
            continue

        key, _, val = stripped.partition(":")
        key = key.strip()
        val = val.strip()

        if val == "" or val == ">":
            if val == ">":
                fm[key] = ""
                current_key = key
            else:
                current_key = key
                current_list = []
            continue

        if val.startswith('"') and val.endswith('"'):
            val = val[1:-1]

        fm[key] = val
        current_key = key

    if current_list is not None:
        fm[current_key] = current_list

    # Handle multi-line folded strings (tools with >)
    for key in fm:
        if isinstance(fm[key], str) and fm[key] == "":
            lines = []
            in_fold = False
            for line in fm_text.split("\n"):
                if line.strip().startswith(f"{key}:") and line.strip().endswith(">"):
                    in_fold = True
                    continue
                if in_fold:
                    if line.startswith("  "):
                        lines.append(line.strip())
                    else:
                        break
            if lines:
                fm[key] = " ".join(lines)

    return fm, body


def render_frontmatter_yaml(fm: dict) -> str:
    """Render a dict as YAML frontmatter."""
    lines = ["---"]
    for key, val in fm.items():
        if isinstance(val, list):
            lines.append(f"{key}:")
            for item in val:
                lines.append(f"  - {item}")
        elif isinstance(val, bool):
            lines.append(f"{key}: {'true' if val else 'false'}")
        elif "\n" in str(val):
            lines.append(f"{key}: >")
            for vline in str(val).split("\n"):
                lines.append(f"  {vline}")
        else:
            lines.append(f"{key}: {val}")
    lines.append("---")
    return "\n".join(lines)


def escape_toml_string(s: str) -> str:
    """Escape a string for TOML triple-quoted values."""
    return s.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')


def transpile_cc(fm: dict, body: str, filename: str) -> str:
    """CC: keep original format as-is."""
    return render_frontmatter_yaml(fm) + "\n\n" + body + "\n"


def transpile_codex(fm: dict, body: str, filename: str) -> str:
    """CC .md -> Codex .toml"""
    name = fm.get("name", filename.replace(".md", ""))
    desc = fm.get("description", "").replace('"', '\\"')
    model = fm.get("model", "inherit")

    codex_model = "inherit"
    reasoning_effort = ""
    if model == "sonnet":
        reasoning_effort = 'model_reasoning_effort = "medium"'

    if "sandbox_mode" in fm:
        sandbox = fm["sandbox_mode"]
    else:
        has_write = ("permissionMode" in fm
                     or "Write" in fm.get("tools", "")
                     or "write" in fm.get("tools", ""))
        sandbox = "workspace-write" if has_write else "read-only"

    lines = [
        f'name = "{name}"',
        f'description = "{desc}"',
    ]

    if codex_model != "inherit":
        lines.append(f'model = "{codex_model}"')
    if reasoning_effort:
        lines.append(reasoning_effort)
    lines.append(f'sandbox_mode = "{sandbox}"')

    skills = fm.get("skills", [])
    if isinstance(skills, list) and skills:
        for skill in skills:
            lines.append("")
            lines.append("[[skills.config]]")
            lines.append(f'path = "~/.codex/skills/{skill}/SKILL.md"')

    adapted_body = adapt_body_for_platform(body, "codex")
    escaped_body = escape_toml_string(adapted_body)
    lines.append(f'developer_instructions = """\n{escaped_body}\n"""')

    return "\n".join(lines) + "\n"


CURSOR_SKILL_MAP = {
    "code-review": "code-reviewer",
    "code-simplifier": "code-simplifier",
}

CODEX_SKILL_INSTRUCTIONS = {
    "code-review": "运行 `coderabbit review --plain` 进行代码审查（需已安装 CodeRabbit CLI）",
    "code-simplifier": "按照 code-simplifier skill 指导进行代码精简",
}

OPENCODE_SKILL_INSTRUCTIONS = CODEX_SKILL_INSTRUCTIONS


def adapt_body_for_platform(body: str, platform: str) -> str:
    """Replace CC-specific Skill("xxx") calls with platform-native equivalents."""
    if platform == "cc":
        return body

    adapted = body

    if platform == "cursor":
        for cc_skill, cursor_type in CURSOR_SKILL_MAP.items():
            adapted = adapted.replace(
                f'Skill("{cc_skill}")',
                f'Task(subagent_type="{cursor_type}")',
            )
    elif platform == "codex":
        for cc_skill, instruction in CODEX_SKILL_INSTRUCTIONS.items():
            adapted = adapted.replace(
                f'Skill("{cc_skill}")',
                instruction,
            )
    elif platform == "opencode":
        for cc_skill, instruction in OPENCODE_SKILL_INSTRUCTIONS.items():
            adapted = adapted.replace(
                f'Skill("{cc_skill}")',
                instruction,
            )

    return adapted


def transpile_cursor(fm: dict, body: str, filename: str) -> str:
    """CC .md -> Cursor .md (adjusted frontmatter)."""
    name = fm.get("name", filename.replace(".md", ""))
    desc = fm.get("description", "")
    model = fm.get("model", "inherit")

    cursor_model = "fast" if model == "sonnet" else "inherit"

    if "readonly" in fm:
        readonly = fm["readonly"] in ("true", True)
    else:
        has_write = ("permissionMode" in fm
                     or "Write" in fm.get("tools", "")
                     or "write" in fm.get("tools", "")
                     or "sandbox_mode" in fm)
        readonly = not has_write

    new_fm = {"name": name, "description": desc, "model": cursor_model}
    if readonly:
        new_fm["readonly"] = True

    skills = fm.get("skills", [])
    if isinstance(skills, list) and skills:
        new_fm["skills"] = skills

    adapted_body = adapt_body_for_platform(body, "cursor")

    return render_frontmatter_yaml(new_fm) + "\n\n" + adapted_body + "\n"


def transpile_opencode(fm: dict, body: str, filename: str) -> str:
    """CC .md -> OpenCode .md (adjusted frontmatter)."""
    name = fm.get("name", filename.replace(".md", ""))
    desc = fm.get("description", "")
    model = fm.get("model", "inherit")

    oc_model = "fast" if model == "sonnet" else "inherit"

    is_pilot = (name == "pilot")
    new_fm = {
        "description": desc,
        "mode": "primary" if is_pilot else "subagent",
        "agent": "pilot" if is_pilot else "build",
        "model": oc_model,
    }

    skills = fm.get("skills", [])
    if isinstance(skills, list) and skills:
        new_fm["skills"] = skills

    adapted_body = adapt_body_for_platform(body, "opencode")

    return render_frontmatter_yaml(new_fm) + "\n\n" + adapted_body + "\n"


TRANSPILERS = {
    "cc": (transpile_cc, ".md"),
    "codex": (transpile_codex, ".toml"),
    "cursor": (transpile_cursor, ".md"),
    "opencode": (transpile_opencode, ".md"),
}


def process_agent(filepath: Path, output_dir: Path, platforms: list[str], platforms_dir: Path):
    """Transpile a single agent file to all requested platforms."""
    content = filepath.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(content)
    filename = filepath.name

    for platform in platforms:
        transpile_fn, ext = TRANSPILERS[platform]
        out_name = filepath.stem + ext

        if filepath.stem == "pilot" and platform != "cc":
            platform_pilot = platforms_dir / platform / "pilot.md"
            if platform_pilot.exists():
                pilot_content = platform_pilot.read_text(encoding="utf-8")
                pilot_fm, pilot_body = parse_frontmatter(pilot_content)
                result = transpile_fn(pilot_fm, pilot_body, "pilot.md")
            else:
                continue
        else:
            result = transpile_fn(fm, body, filename)

        platform_dir = output_dir / platform
        platform_dir.mkdir(parents=True, exist_ok=True)
        out_path = platform_dir / out_name
        out_path.write_text(result, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Multi-platform Agent Transpiler")
    parser.add_argument(
        "--platforms",
        default=",".join(ALL_PLATFORMS),
        help=f"Comma-separated list of target platforms (default: {','.join(ALL_PLATFORMS)})",
    )
    parser.add_argument(
        "--output", "-o",
        default=str(DEFAULT_OUTPUT),
        help=f"Output directory (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--agents-dir",
        default=str(AGENTS_DIR),
        help=f"Source agents directory (default: {AGENTS_DIR})",
    )
    args = parser.parse_args()

    platforms = [p.strip() for p in args.platforms.split(",")]
    for p in platforms:
        if p not in ALL_PLATFORMS:
            print(f"Error: unknown platform '{p}'. Valid: {ALL_PLATFORMS}", file=sys.stderr)
            sys.exit(1)

    agents_dir = Path(args.agents_dir)
    output_dir = Path(args.output)
    platforms_dir = agents_dir / "platforms"

    if not agents_dir.exists():
        print(f"Error: agents directory not found: {agents_dir}", file=sys.stderr)
        sys.exit(1)

    agent_files = sorted(agents_dir.glob("*.md"))
    if not agent_files:
        print(f"Error: no .md files found in {agents_dir}", file=sys.stderr)
        sys.exit(1)

    for pdir in platforms:
        (output_dir / pdir).mkdir(parents=True, exist_ok=True)

    count = 0
    for agent_file in agent_files:
        process_agent(agent_file, output_dir, platforms, platforms_dir)
        count += 1

    # Also process platform-specific pilots
    for platform in platforms:
        if platform == "cc":
            continue
        platform_pilot = platforms_dir / platform / "pilot.md"
        if platform_pilot.exists():
            content = platform_pilot.read_text(encoding="utf-8")
            fm, body = parse_frontmatter(content)
            transpile_fn, ext = TRANSPILERS[platform]
            result = transpile_fn(fm, body, "pilot.md")
            out_path = output_dir / platform / ("pilot" + ext)
            out_path.write_text(result, encoding="utf-8")

    print(f"Transpiled {count} agents to {len(platforms)} platforms → {output_dir}/")
    for p in platforms:
        files = list((output_dir / p).iterdir())
        print(f"  {p}: {len(files)} files")


if __name__ == "__main__":
    main()
