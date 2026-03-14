#!/usr/bin/env python3
"""duplicate_analyzer.py 单元测试"""
import json
import os
import sys
import tempfile
import unittest

# 将 templates 目录加入 path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'templates', '.pipeline', 'autosteps'))

from duplicate_analyzer import (
    find_exact_duplicates,
    find_similar_duplicates,
    build_candidates_report,
    normalize_signature,
    extract_param_types,
    name_similarity,
    is_excluded,
    is_test_path,
    load_registry,
    load_config,
)


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


class TestHelperFunctions(unittest.TestCase):
    """辅助函数测试"""

    def test_normalize_signature_strips_whitespace(self):
        sig = "  validateEmail(  email:  string  ):  boolean  "
        result = normalize_signature(sig)
        self.assertEqual(result, "validateEmail( email: string ): boolean")

    def test_extract_param_types(self):
        sig = "validateEmail(email: string): boolean"
        result = extract_param_types(sig)
        self.assertEqual(result, "email:string")

    def test_extract_param_types_no_params(self):
        sig = "doSomething"
        result = extract_param_types(sig)
        self.assertEqual(result, "")

    def test_name_similarity_identical(self):
        self.assertAlmostEqual(name_similarity("hello", "hello"), 1.0)

    def test_name_similarity_different(self):
        self.assertLess(name_similarity("abc", "xyz"), 0.5)

    def test_is_excluded_match(self):
        c1 = {"name": "Foo", "path": "src/a.ts:10"}
        c2 = {"name": "Bar", "path": "src/b.ts:20"}
        pairs = [{"a": "Foo@src/a.ts", "b": "Bar@src/b.ts"}]
        self.assertTrue(is_excluded(c1, c2, pairs))

    def test_is_excluded_no_match(self):
        c1 = {"name": "Foo", "path": "src/a.ts:10"}
        c2 = {"name": "Bar", "path": "src/b.ts:20"}
        pairs = [{"a": "Baz@src/c.ts", "b": "Qux@src/d.ts"}]
        self.assertFalse(is_excluded(c1, c2, pairs))

    def test_is_test_path_various(self):
        self.assertTrue(is_test_path("tests/utils/helper.ts:1"))
        self.assertTrue(is_test_path("src/__tests__/foo.ts:1"))
        self.assertTrue(is_test_path("src/foo.test.ts:1"))
        self.assertTrue(is_test_path("src/foo.spec.ts:1"))
        self.assertFalse(is_test_path("src/utils/helper.ts:1"))

    def test_load_registry(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump({"version": 1, "index": [{"id": "L-001"}]}, f)
            f.flush()
            result = load_registry(f.name)
        os.unlink(f.name)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["id"], "L-001")

    def test_load_config_defaults(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump({}, f)
            f.flush()
            result = load_config(f.name)
        os.unlink(f.name)
        self.assertEqual(result["similarity_threshold"], 0.7)
        self.assertEqual(result["exclude_pairs"], [])

    def test_load_config_missing_file(self):
        result = load_config("/nonexistent/path.json")
        self.assertEqual(result["similarity_threshold"], 0.7)


if __name__ == "__main__":
    unittest.main()
