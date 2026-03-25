#!/bin/bash
# Phase 3 后置: Impl Manifest Merger
# 输入: PIPELINE_DIR（含 impl-manifest-*.json）
# 输出: .pipeline/artifacts/impl-manifest.json
# 退出码: 0=PASS 1=FAIL 2=ERROR

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
ARTIFACTS_DIR="$PIPELINE_DIR/artifacts"
OUTPUT_FILE="$ARTIFACTS_DIR/impl-manifest.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$ARTIFACTS_DIR"

# 收集所有 impl-manifest-*.json
MANIFESTS=()
for f in "$ARTIFACTS_DIR"/impl-manifest-*.json; do
  [ -f "$f" ] && MANIFESTS+=("$f")
done

if [ ${#MANIFESTS[@]} -eq 0 ]; then
  cat > "$OUTPUT_FILE" << EOF
{"autostep":"ImplManifestMerger","timestamp":"$TIMESTAMP","error":"no impl-manifest-*.json found","overall":"ERROR"}
EOF
  exit 2
fi

# Python 合并
PIPELINE_DIR="$PIPELINE_DIR" TIMESTAMP="$TIMESTAMP" python3 << 'PYEOF'
import glob
import json
import os

pipeline_dir = os.environ.get('PIPELINE_DIR', '.pipeline')
timestamp = os.environ.get('TIMESTAMP', '')
artifacts_dir = f'{pipeline_dir}/artifacts'
output_file = f'{artifacts_dir}/impl-manifest.json'
state_file = f'{pipeline_dir}/state.json'

current_proposal_id = ''
if os.path.exists(state_file):
    with open(state_file, encoding='utf-8') as fh:
        current_proposal_id = json.load(fh).get('current_proposal_id', '') or ''

def normalize_files(data):
    candidates = []
    for key in ('files_changed', 'files', 'modified_files', 'files_modified', 'files_created'):
        value = data.get(key, [])
        if isinstance(value, list):
            candidates.extend(value)

    normalized = []
    seen = set()
    for entry in candidates:
        if isinstance(entry, str):
            path = entry
            item = {'path': path}
        elif isinstance(entry, dict):
            path = entry.get('path') or entry.get('file') or entry.get('name')
            if not path:
                continue
            item = dict(entry)
            item['path'] = path
        else:
            continue

        if path in seen:
            continue
        seen.add(path)
        normalized.append(item)
    return normalized

manifests = sorted(glob.glob(f'{artifacts_dir}/impl-manifest-*.json'))
builders = []
all_files = {}
ignored_manifests = []
duplicate_paths = []
seen_task_ids = {}
duplicate_task_ids = []

for mpath in manifests:
    with open(mpath, encoding='utf-8') as fh:
        data = json.load(fh)

    manifest_proposal_id = data.get('proposal_id', '') or ''
    if current_proposal_id and manifest_proposal_id and manifest_proposal_id != current_proposal_id:
        ignored_manifests.append({
            'file': os.path.basename(mpath),
            'proposal_id': manifest_proposal_id,
        })
        continue

    builder_name = (data.get('builder') or os.path.basename(mpath)
        .replace('impl-manifest-', '').replace('.json', ''))
    files = normalize_files(data)
    task_ids = []
    raw_tasks = data.get('tasks_completed', [])
    if isinstance(raw_tasks, list):
        task_ids = [task_id for task_id in raw_tasks if isinstance(task_id, str) and task_id]

    builders.append({
        'builder': builder_name,
        'proposal_id': manifest_proposal_id,
        'tasks_completed': task_ids,
        'files_changed': files,
    })

    for task_id in task_ids:
        if task_id in seen_task_ids:
            duplicate_task_ids.append({
                'task_id': task_id,
                'builders': sorted({seen_task_ids[task_id], builder_name}),
            })
        else:
            seen_task_ids[task_id] = builder_name

    for item in files:
        key = item['path']
        if key in all_files:
            duplicate_paths.append({
                'path': key,
                'builders': sorted({all_files[key]['builder'], builder_name}),
            })
            continue
        item_with_builder = dict(item)
        item_with_builder['builder'] = builder_name
        all_files[key] = item_with_builder

dedup_duplicate_paths = []
seen_dupe_path_keys = set()
for entry in duplicate_paths:
    signature = (entry['path'], tuple(entry['builders']))
    if signature in seen_dupe_path_keys:
        continue
    seen_dupe_path_keys.add(signature)
    dedup_duplicate_paths.append(entry)

dedup_duplicate_task_ids = []
seen_dupe_task_keys = set()
for entry in duplicate_task_ids:
    signature = (entry['task_id'], tuple(entry['builders']))
    if signature in seen_dupe_task_keys:
        continue
    seen_dupe_task_keys.add(signature)
    dedup_duplicate_task_ids.append(entry)

overall = 'FAIL' if dedup_duplicate_paths or dedup_duplicate_task_ids else 'PASS'

result = {
    'autostep': 'ImplManifestMerger',
    'timestamp': timestamp,
    'proposal_id': current_proposal_id,
    'builders': builders,
    'files_changed': list(all_files.values()),
    'overall': overall,
}
if ignored_manifests:
    result['ignored_manifests'] = ignored_manifests
if dedup_duplicate_paths:
    result['duplicate_paths'] = dedup_duplicate_paths
if dedup_duplicate_task_ids:
    result['duplicate_task_ids'] = dedup_duplicate_task_ids

with open(output_file, 'w', encoding='utf-8') as fh:
    json.dump(result, fh, indent=2, ensure_ascii=False)
    fh.write('\n')

if overall != 'PASS':
    raise SystemExit(1)
PYEOF

exit 0
