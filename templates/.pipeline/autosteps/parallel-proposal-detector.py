#!/usr/bin/env python3
"""并行提案预检查：缺少 detail 或存在共享足迹时，保守降级为串行。"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


PIPELINE_DIR = Path(os.environ.get("PIPELINE_DIR", ".pipeline"))
QUEUE_FILE = PIPELINE_DIR / "proposal-queue.json"
ARTIFACTS_DIR = PIPELINE_DIR / "artifacts"
OUTPUT_FILE = ARTIFACTS_DIR / "parallel-proposal-report.json"

SHARED_KEYWORDS = {
    "auth", "authentication", "login", "permission", "permissions", "role", "roles",
    "config", "settings", "env", "environment", "shared", "common", "core", "framework",
    "router", "routing", "layout", "app", "shell", "schema", "contract", "openapi",
    "认证", "登录", "权限", "角色", "配置", "环境", "共享", "公共", "核心", "框架",
    "路由", "布局", "壳层", "契约", "接口", "文档",
}


def normalize_text(value: str) -> str:
    return value.strip().lower()


def extract_keywords(text: str) -> set[str]:
    text = normalize_text(text)
    hits = set(re.findall(r"[a-zA-Z][a-zA-Z0-9_-]{2,}|[\u4e00-\u9fff]{2,}", text))
    return hits


def extract_api_segments(items: list[str]) -> set[str]:
    segments = set()
    for item in items:
        for path in re.findall(r"/[a-zA-Z0-9_./{}-]+", item):
            for seg in path.split("/"):
                seg = seg.strip("{} ").lower()
                if len(seg) >= 2 and seg not in {"api", "v1", "v2"}:
                    segments.add(seg)
    return segments


def extract_entities(items: list[str]) -> set[str]:
    entities = set()
    for item in items:
        m = re.match(r"\s*([a-zA-Z_][a-zA-Z0-9_]*|[\u4e00-\u9fff]{2,})\s*\(", item)
        if m:
            entities.add(m.group(1).lower())
            continue
        entities |= extract_keywords(item)
    return entities


def proposal_summary(proposal: dict) -> dict:
    detail = proposal.get("detail") or {}
    api_overview = detail.get("api_overview") or []
    data_entities = detail.get("data_entities") or []
    text_chunks = [proposal.get("title", ""), proposal.get("scope", "")]
    for key in ("user_stories", "business_rules", "acceptance_criteria", "api_overview", "data_entities", "non_functional"):
        value = detail.get(key) or []
        if isinstance(value, list):
            text_chunks.extend(str(item) for item in value)
    keywords = set()
    for chunk in text_chunks:
        keywords |= extract_keywords(str(chunk))
    domains = {normalize_text(d) for d in (proposal.get("domains") or []) if isinstance(d, str) and d.strip()}
    return {
        "id": proposal.get("id"),
        "title": proposal.get("title", ""),
        "has_detail": bool(detail),
        "has_domains": bool(domains),
        "domains": domains,
        "api_segments": extract_api_segments([str(item) for item in api_overview if isinstance(item, str)]),
        "entities": extract_entities([str(item) for item in data_entities if isinstance(item, str)]),
        "shared_keywords": keywords & SHARED_KEYWORDS,
    }


def main() -> int:
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)

    if not QUEUE_FILE.exists():
        OUTPUT_FILE.write_text(json.dumps({
            "autostep": "ParallelProposalDetector",
            "overall": "ERROR",
            "error": "proposal-queue.json not found",
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return 2

    queue = json.loads(QUEUE_FILE.read_text(encoding="utf-8"))
    selected_ids = [item.strip() for item in os.environ.get("PROPOSAL_IDS", "").split(",") if item.strip()]
    proposals = [p for p in queue.get("proposals", []) if not selected_ids or p.get("id") in selected_ids]
    proposals.sort(key=lambda item: item.get("id", ""))

    summaries = [proposal_summary(proposal) for proposal in proposals]
    reasons = []

    for summary in summaries:
        if not summary["has_detail"]:
            reasons.append({"type": "missing_detail", "proposal_id": summary["id"]})
        if not summary["has_domains"]:
            reasons.append({"type": "missing_domains", "proposal_id": summary["id"]})

    for idx, left in enumerate(summaries):
        for right in summaries[idx + 1:]:
            domain_overlap = sorted(left["domains"] & right["domains"])
            if domain_overlap:
                reasons.append({
                    "type": "domain_overlap",
                    "proposals": [left["id"], right["id"]],
                    "values": domain_overlap,
                })

            api_overlap = sorted(left["api_segments"] & right["api_segments"])
            if api_overlap:
                reasons.append({
                    "type": "api_overlap",
                    "proposals": [left["id"], right["id"]],
                    "values": api_overlap,
                })

            entity_overlap = sorted(left["entities"] & right["entities"])
            if entity_overlap:
                reasons.append({
                    "type": "entity_overlap",
                    "proposals": [left["id"], right["id"]],
                    "values": entity_overlap[:10],
                })

            shared_overlap = sorted(left["shared_keywords"] & right["shared_keywords"])
            if shared_overlap:
                reasons.append({
                    "type": "shared_keyword_overlap",
                    "proposals": [left["id"], right["id"]],
                    "values": shared_overlap,
                })

    result = {
        "autostep": "ParallelProposalDetector",
        "overall": "OVERLAP" if reasons else "PASS",
        "proposal_ids": [summary["id"] for summary in summaries],
        "reasons": reasons,
        "safe_parallel_ids": [summary["id"] for summary in summaries] if not reasons else [],
        "serial_fallback_ids": [summary["id"] for summary in summaries],
    }
    OUTPUT_FILE.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(result["overall"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
