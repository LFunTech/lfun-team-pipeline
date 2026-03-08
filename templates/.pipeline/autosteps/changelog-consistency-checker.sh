#!/bin/bash
# Phase 5.1: Changelog Consistency Checker
# 输入: PIPELINE_DIR
# 输出: .pipeline/artifacts/changelog-check-report.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
CHANGELOG_FILE="${CHANGELOG_FILE:-CHANGELOG.md}"
API_CHANGE_REPORT="$PIPELINE_DIR/artifacts/api-change-report.json"
OUTPUT_FILE="$PIPELINE_DIR/artifacts/changelog-check-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ ! -f "$CHANGELOG_FILE" ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"ChangelogConsistencyChecker","timestamp":"$TIMESTAMP","error":"CHANGELOG.md not found","overall":"FAIL"}
EOF
  exit 1
fi

PIPELINE_DIR="$PIPELINE_DIR" CHANGELOG_FILE="$CHANGELOG_FILE" TIMESTAMP="$TIMESTAMP" python3 << 'PYEOF'
import json, os, re, sys

pipeline_dir = os.environ.get('PIPELINE_DIR', '.pipeline')
changelog_file = os.environ.get('CHANGELOG_FILE', 'CHANGELOG.md')
timestamp = os.environ.get('TIMESTAMP', '')
output_file = f'{pipeline_dir}/artifacts/changelog-check-report.json'

checks = []
overall = 'PASS'

def fail(check, detail):
  global overall
  checks.append({'check': check, 'result': 'FAIL', 'detail': detail})
  overall = 'FAIL'

def pass_(check, detail):
  checks.append({'check': check, 'result': 'PASS', 'detail': detail})

with open(changelog_file) as f:
  changelog_content = f.read()

api_changed_count = 0
try:
  api_report = json.load(open(f'{pipeline_dir}/artifacts/api-change-report.json'))
  api_changed_count = len(api_report.get('changed_contracts', []))
except Exception: pass

if '## [Unreleased]' not in changelog_content and '## [unreleased]' not in changelog_content.lower():
  fail('unreleased_section', 'CHANGELOG 中缺少 [Unreleased] section')
else:
  pass_('unreleased_section', '[Unreleased] section 存在')

unreleased_section = re.search(r'## \[Unreleased\](.*?)(?=## \[|\Z)', changelog_content, re.DOTALL | re.IGNORECASE)
changelog_entries = 0
if unreleased_section:
  entries = re.findall(r'^- ', unreleased_section.group(1), re.MULTILINE)
  changelog_entries = len(entries)

if api_changed_count > 0 and changelog_entries < api_changed_count:
  fail('api_change_entries', f'CHANGELOG 条目数 ({changelog_entries}) < API 变更数 ({api_changed_count})')
else:
  pass_('api_change_entries', f'CHANGELOG 条目数 ({changelog_entries}) 覆盖 API 变更数 ({api_changed_count})')

result = {
  'autostep': 'ChangelogConsistencyChecker',
  'timestamp': timestamp,
  'checks': checks,
  'api_changed_contracts': api_changed_count,
  'changelog_entries_in_unreleased': changelog_entries,
  'overall': overall
}

with open(output_file, 'w') as f:
  json.dump(result, f, indent=2, ensure_ascii=False)

sys.exit(0 if overall == 'PASS' else 1)
PYEOF
