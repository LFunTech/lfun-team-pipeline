#!/usr/bin/env bash
# depend-collector.sh — 解析 proposal.md 关键词，生成 .depend/ 凭证模板
# 用法：PIPELINE_DIR=.pipeline bash .pipeline/autosteps/depend-collector.sh
set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-.pipeline}"
PROPOSAL="$PIPELINE_DIR/artifacts/proposal.md"
DEPEND_DIR=".depend"
REPORT="$PIPELINE_DIR/artifacts/depend-collection-report.json"

# 检查 proposal.md 存在
if [ ! -f "$PROPOSAL" ]; then
  echo "ERROR: $PROPOSAL 不存在" >&2
  exit 1
fi

mkdir -p "$DEPEND_DIR"

DETECTED=()
GENERATED=()
SKIPPED=()
UNFILLED=()

# ── 检测函数 ──────────────────────────────────────────────
detect() {
  local keywords=("$@")
  for kw in "${keywords[@]}"; do
    if grep -qi "$kw" "$PROPOSAL"; then
      return 0
    fi
  done
  return 1
}

generate_template() {
  local name="$1"
  local content="$2"
  local template_file="$DEPEND_DIR/${name}.env.template"
  local env_file="$DEPEND_DIR/${name}.env"

  # 无论 .env 是否已存在，都将该依赖加入 detected_deps
  # builder-infra 需要完整的依赖列表来生成 Woodpecker secrets
  DETECTED+=("$name")

  if [ -f "$env_file" ]; then
    SKIPPED+=("$env_file（已存在）")
    return
  fi

  # .env 不存在，需要用户填写
  UNFILLED+=("$name")
  if [ ! -f "$template_file" ]; then
    printf '%s\n' "$content" > "$template_file"
    GENERATED+=("$template_file")
  fi
}

# ── 关键词检测 ────────────────────────────────────────────
if detect "PostgreSQL" "MySQL" "MariaDB" "MongoDB"; then
  generate_template "db" "# 数据库连接配置
DB_HOST=
DB_PORT=
DB_USER=
DB_PASSWORD=
DB_NAME="
fi

if detect "Redis"; then
  generate_template "redis" "# Redis 连接配置
REDIS_HOST=
REDIS_PORT=6379
REDIS_PASSWORD="
fi

if detect "Woodpecker"; then
  generate_template "woodpecker" "# Woodpecker CI 配置
WOODPECKER_URL=
WOODPECKER_TOKEN="
fi

if detect "GPU" "V100" "A100" "H100" "CUDA" "nvidia"; then
  generate_template "server" "# GPU 服务器 SSH 配置
SSH_HOST=
SSH_PORT=22
SSH_USER=
SSH_KEY_PATH=~/.ssh/id_rsa"
fi

if detect "MinIO" "S3" "OSS" "对象存储" "object storage"; then
  generate_template "storage" "# 对象存储配置
STORAGE_ENDPOINT=
STORAGE_ACCESS_KEY=
STORAGE_SECRET_KEY=
STORAGE_BUCKET="
fi

if detect "SMTP" "邮件" "email" "sendmail"; then
  generate_template "smtp" "# 邮件服务配置
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD="
fi

# ── 生成 .depend/.gitignore ───────────────────────────────
cat > "$DEPEND_DIR/.gitignore" << 'GITIGNORE_EOF'
# 凭证文件不进入版本控制
*.env
# 模板文件可以提交
!*.env.template
!README.md
!.gitignore
GITIGNORE_EOF

# ── 生成 README.md ────────────────────────────────────────
{
  echo "# .depend — 项目凭证配置"
  echo ""
  echo "> 此目录存储项目运行所需的外部凭证。**.env 文件已加入 .gitignore，不会进入版本控制。**"
  echo ""
  echo "## 使用方法"
  echo ""
  echo "将各 \`.env.template\` 文件复制并重命名为 \`.env\`，填入真实值："
  echo ""
  echo "\`\`\`bash"
  for tmpl in "$DEPEND_DIR"/*.env.template; do
    [ -f "$tmpl" ] || continue
    base=$(basename "$tmpl" .template)
    echo "cp $tmpl $DEPEND_DIR/$base"
  done
  echo "\`\`\`"
  echo ""
  echo "## 各文件说明"
  echo ""
  [ -f "$DEPEND_DIR/db.env.template" ] && echo "- **db.env**：数据库连接信息（主机、端口、用户名、密码、库名）"
  [ -f "$DEPEND_DIR/redis.env.template" ] && echo "- **redis.env**：Redis 连接信息"
  [ -f "$DEPEND_DIR/woodpecker.env.template" ] && echo "- **woodpecker.env**：Woodpecker CI 服务地址和访问 Token"
  [ -f "$DEPEND_DIR/server.env.template" ] && echo "- **server.env**：GPU 服务器 SSH 连接信息"
  [ -f "$DEPEND_DIR/storage.env.template" ] && echo "- **storage.env**：对象存储（MinIO/S3/OSS）连接信息"
  [ -f "$DEPEND_DIR/smtp.env.template" ] && echo "- **smtp.env**：邮件服务器配置"
  echo ""
  echo "## 填写完成后"
  echo ""
  echo "在 Claude Code 对话中回复 **继续**，流水线将恢复执行。"
} > "$DEPEND_DIR/README.md"

# 用 bash 方式输出报告（更可靠）
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# 构建 JSON 数组
detected_json=$(printf '%s\n' "${DETECTED[@]+"${DETECTED[@]}"}" | python3 -c "
import sys, json
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items, ensure_ascii=False))
")

generated_json=$(printf '%s\n' "${GENERATED[@]+"${GENERATED[@]}"}" | python3 -c "
import sys, json
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items, ensure_ascii=False))
")

skipped_json=$(printf '%s\n' "${SKIPPED[@]+"${SKIPPED[@]}"}" | python3 -c "
import sys, json
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items, ensure_ascii=False))
")

unfilled_json=$(printf '%s\n' "${UNFILLED[@]+"${UNFILLED[@]}"}" | python3 -c "
import sys, json
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items, ensure_ascii=False))
")

cat > "$REPORT" << REPORT_EOF
{
  "autostep": "depend-collector",
  "timestamp": "$TIMESTAMP",
  "detected_deps": $detected_json,
  "unfilled_deps": $unfilled_json,
  "templates_generated": $generated_json,
  "skipped": $skipped_json,
  "overall": "PASS"
}
REPORT_EOF

echo "[depend-collector] 检测到依赖：${DETECTED[*]:-无}"
echo "[depend-collector] 未填写凭证：${UNFILLED[*]:-无}"
echo "[depend-collector] 生成模板：${GENERATED[*]:-无}"
echo "[depend-collector] 跳过（已存在）：${SKIPPED[*]:-无}"
echo "[depend-collector] 报告：$REPORT"
