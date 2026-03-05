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
import json, os, glob

pipeline_dir = os.environ.get('PIPELINE_DIR', '.pipeline')
timestamp = os.environ.get('TIMESTAMP', '')
artifacts_dir = f'{pipeline_dir}/artifacts'
output_file = f'{artifacts_dir}/impl-manifest.json'

manifests = sorted(glob.glob(f'{artifacts_dir}/impl-manifest-*.json'))
builders = []
all_files = {}

for mpath in manifests:
    data = json.load(open(mpath))
    builder_name = os.path.basename(mpath)\
        .replace('impl-manifest-', '').replace('.json', '')
    files = data.get('files_changed', data.get('files', []))
    builders.append({'builder': builder_name, 'files_changed': files})
    for f in files:
        key = f['path']
        if key not in all_files:
            all_files[key] = f

result = {
    'autostep': 'ImplManifestMerger',
    'timestamp': timestamp,
    'builders': builders,
    'files_changed': list(all_files.values()),
    'overall': 'PASS'
}

with open(output_file, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
PYEOF

exit 0
