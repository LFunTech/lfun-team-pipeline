# CLAUDE.md — 多角色软件交付流水线

本项目使用基于 Claude Code 的多角色软件交付流水线（v6.5）。

## 快速启动

```bash
# 启动流水线（每次执行一个批次，完成后自动退出）
claude --dangerously-skip-permissions --agent pilot

# 流水线会输出 [EXIT] 提示，再次运行即可继续下一批次
claude --dangerously-skip-permissions --agent pilot

# 查看当前状态
cat .pipeline/state.json | python3 -c "import json,sys; s=json.load(sys.stdin); print(f'Phase: {s[\"current_phase\"]}, Status: {s[\"status\"]}')"
```

## 目录结构

```
.pipeline/
├── config.json          ← 流水线配置（编辑此文件以自定义行为）
├── playbook.md          ← 阶段执行手册（Pilot 按需加载，勿手动修改）
├── project-memory.json  ← 项目记忆（跨流水线约束清单，自动维护）
├── history/             ← 历次流水线产物归档（按需查阅）
├── state.json           ← 运行时状态（Pilot 自动管理，勿手动修改）
├── autosteps/           ← AutoStep Shell 脚本（20 个）
└── artifacts/           ← 运行时产物（所有 Agent 和 AutoStep 的输出）
    ├── requirement.md
    ├── proposal.md
    ├── adr-draft.md
    ├── tasks.json
    ├── contracts/       ← OpenAPI Schema 文件
    ├── impl-manifest.json
    ├── gate-*.json
    ├── ...
    └── ...

.worktrees/              ← 3.build 临时目录（自动创建和清理，勿手动修改）
├── builder-dba/
├── builder-backend/
├── builder-frontend/
├── builder-security/
├── builder-infra/
├── builder-migrator/    ← 仅条件激活时存在
└── builder-translator/  ← 仅条件激活时存在
（3.build 完成后自动删除）
```

## 阶段顺序参考

```
System Planning → 系统规划（交互式拆解系统为提案队列 + 并行拓扑计算）
Pick Proposal   → 选取下一个/组待执行提案（同 parallel_group 可并行）
Memory Load     → 项目记忆加载（注入约束给 Clarifier/Architect）
0.clarify    → Clarifier（需求澄清，最多 5 轮）
0.5.requirement-check  → Requirement Completeness Checker（AutoStep）
1.design    → Architect（方案设计）
gate-a.design-review     → Auditor-Gate（四视角方案审核）
2.0a.repo-setup → GitHub Repo Creator（github-ops Agent）
2.0b.depend-collect → Depend Collector（AutoStep + 暂停等凭证）
2.plan    → Planner（任务细化）
2.1.assumption-check  → Assumption Propagation Validator（AutoStep）
gate-b.plan-review     → Auditor-Gate（四视角任务审核）
2.5.contract-formalize  → Contract Formalizer（契约形式化）
2.6.contract-validate-semantic ∥ 2.7.contract-validate-schema → 契约验证（并行 AutoStep）
3.build    → Builders 波次内并行实现（Frontend/Backend/DBA/Security/Infra）
             + 条件角色（Migrator/Translator）
3.0b.build-verify → Build Verifier（AutoStep，编译验证）
3.0d.duplicate-detect ∥ 3.1.static-analyze ∥ 3.2.diff-validate ∥ 3.3.regression-guard → 构建后分析（并行 AutoStep）
3.5.simplify  → Simplifier（代码精简）
3.6.simplify-verify  → Post-Simplification Verifier（AutoStep）
gate-c.code-review     → Inspector（代码审查）
3.7.contract-compliance  → Contract Compliance Checker（AutoStep）
4a.test   → Tester（功能测试）
4a.1.test-failure-map → Test Failure Mapper（AutoStep，FAIL 时）
4.2.coverage-check  → Test Coverage Enforcer（AutoStep）
4b.optimize   → Optimizer（性能优化，条件角色）
gate-d.test-review     → Auditor-QA（测试验收）
AutoStep   → API Change Detector
5.document    → Documenter（文档）
5.1.changelog-check  → Changelog Consistency Checker（AutoStep）
gate-e.doc-review     → Auditor-QA ∥ Auditor-Tech（并行文档审核）
5.9.ci-push  → GitHub Woodpecker Push（github-ops Agent）
6.0.deploy-readiness  → Pre-Deploy Readiness Check（AutoStep）
6.deploy    → Deployer（部署）
7.monitor    → Monitor（上线观测）
Memory Consolidation → 项目记忆固化（提取约束，用户确认后写入）
Mark Completed  → 标记提案完成，循环取下一个
```

## 配置说明（.pipeline/config.json）

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `project_name` | 项目名称 | `YOUR_PROJECT_NAME` |
| `autonomous_mode` | 自治模式：跳过所有人工确认，全自动执行提案队列 | `false` |
| `max_attempts.default` | 未单独配置的阶段的最大重试次数（兜底值） | `3` |
| `requirement_completeness.min_words` | 需求文档最小字数 | `200` |
| `testing.coverage_tool` | 测试覆盖率工具 | `nyc` |
| `testing.coverage_threshold` | 覆盖率阈值（百分比） | `80` |

## 模型路由（Model Routing）

设置 `"model_routing.enabled": true` 后，部分 Agent 交由外部 LLM 执行，大幅降低 Claude token 消耗。
按**上下文需求**和**质量需求**双维度分配模型：

- **Kimi-K2.5（2M 上下文，快）**：builder-backend、builder-frontend、planner、tester、documenter
- **GLM-5（200K 上下文，深度思考）**：builder-dba、builder-security、builder-infra、contract-formalizer、optimizer、migrator、translator
- **Claude（老大）**：Pilot、Clarifier、Architect、Simplifier、Inspector、所有 Auditor、Resolver、Deployer、Monitor

**配置方式（二选一）：**

```bash
# 方式 A：全局配置（一次设好，所有项目生效）
# 编辑 ~/.config/team-pipeline/routing.json
{
  "enabled": true,
  "providers": {
    "dashscope-glm5": {
      "api_key": "sk-your-key-here",
      ...
    }
  }
}

# 方式 B：项目级配置（仅当前项目生效，可覆盖全局）
# 编辑 .pipeline/config.json 的 model_routing 部分
```

```bash
# 正常运行流水线（自动识别路由配置）
claude --dangerously-skip-permissions --agent pilot
```

**配置合并优先级：** 项目 `config.json` > 全局 `routing.json`。项目可覆盖个别 agent 的路由。

**API Key 优先级：** `api_key`（直接值）> `api_key_env`（环境变量）> `.depend/llm.env`

**支持的 Provider：**

| Provider | 说明 | 默认路由 | 配置 |
|----------|------|----------|------|
| `dashscope-glm5` | GLM-5（代码质量高，思考深） | Builder/Planner/Tester/Optimizer | `base_url` + `DASHSCOPE_API_KEY` |
| `dashscope-kimi` | Kimi-K2.5（响应快，文档优） | Documenter | 同上（共享 key） |
| `ollama` | 本地 Ollama（qwen3:32b 等） | — | `base_url`（无需 key） |

> DashScope 统一网关：`dashscope-glm5` 和 `dashscope-kimi` 共享同一个 API Key，仅 model 名不同。

## 自治模式（Autonomous Mode）

设置 `"autonomous_mode": true` 后，流水线在 System Planning 完成（用户确认蓝图）后全自动执行：

- **0.clarify**：Clarifier 跳过交互式 Q&A，直接从提案 scope 生成 requirement.md
- **2.0b.depend-collect**：跳过凭证填写等待，输出 WARN 继续执行
- **Memory Consolidation**：自动接受新约束，冲突约束保留旧值（不自动推翻）

```bash
# 启用自治模式
cd your-project
# 编辑 .pipeline/config.json，设置 "autonomous_mode": true
claude --dangerously-skip-permissions --agent pilot   # System Planning 交互完成后，所有提案自动执行
```

> **注意**：System Planning 始终需要人工交互（描述系统、确认蓝图）。自治模式仅影响后续提案执行阶段。

## 常见操作

### 继续执行流水线

流水线采用批次执行模式，每次启动执行一个批次后自动退出。直接再次运行即可继续：

```bash
# 查看当前阶段
cat .pipeline/state.json | python3 -c "import json,sys; s=json.load(sys.stdin); print(f'Phase: {s[\"current_phase\"]}, Status: {s[\"status\"]}')"

# 继续下一批次
claude --dangerously-skip-permissions --agent pilot
```

### 手动回退到指定阶段

```bash
# 编辑 state.json，将 current_phase 改为目标阶段，status 改为 running
python3 -c "
import json
s = json.load(open('.pipeline/state.json'))
s['current_phase'] = '3.build'
s['status'] = 'running'
with open('.pipeline/state.json', 'w') as f:
  json.dump(s, f, indent=2)
"
claude --dangerously-skip-permissions --agent pilot
```

### 升级流水线版本

在正在执行的项目中原地升级（保留 state.json、产物、提案队列）：

```bash
# 1. 先更新全局 agents 和模板
cd /path/to/team-creator && bash install.sh

# 2. 在项目目录中升级 playbook 和 autosteps
cd /path/to/my-project && team upgrade

# 3. 继续执行
claude --dangerously-skip-permissions --agent pilot
```

### 查看 Gate 审核结果

```bash
cat .pipeline/artifacts/gate-a.design-review.json | python3 -m json.tool
```

### 必备 Skills 安装

流水线要求以下两个 Skill 已安装：

```bash
# 检查
ls ~/.claude/skills/ | grep -E "code-simplifier|code-review"
```

如缺失，请参考 Claude Code Skill 安装文档。

### 3.build Worktree 异常恢复

如流水线在 3.build 中断，残留 worktree：

```bash
# 查看残余
git worktree list

# 重启 Pilot（自动检测并清理残余后重新 3.build）
claude --dangerously-skip-permissions --agent pilot

# 如自动清理失败，手动执行：
git worktree remove .worktrees/builder-<name> --force
git branch -D pipeline/3.build/builder-<name>
```

## 安装 Agents

```bash
# 从本 repo 安装最新 Agents 到 ~/.claude/agents/
bash install.sh
```

## 凭证管理（.depend/ 目录）

流水线在 2.0b.depend-collect 会自动扫描项目依赖，在项目根目录生成 `.depend/` 目录。

**目录用途：** 存储外部服务凭证（数据库、Redis、GPU 服务器、对象存储等）。

**文件类型：**
- `.depend/*.env.template`：模板文件，列出所需的环境变量名（可提交到 git）
- `.depend/*.env`：真实凭证文件，**已加入 .gitignore，绝不提交到版本控制**
- `.depend/README.md`：填写说明（可提交到 git）

**使用流程：**
1. 2.0b.depend-collect 完成后，流水线暂停并提示填写凭证
2. 将各 `.env.template` 复制为 `.env` 并填入真实值
3. 在 Claude Code 对话中回复"继续"，流水线恢复执行

**注意：** 部署时，将 `.depend/*.env` 中的凭证手动配置到 Woodpecker CI 的 repo secrets 中，与 `.woodpecker/` 中的 secrets 字段对应。

### 查看执行记录

```bash
# 查看所有步骤的执行结果
python3 -c "
import json
s = json.load(open('.pipeline/state.json'))
for e in s.get('execution_log', []):
    rb = f' → {e[\"rollback_to\"]}' if e.get('rollback_to') else ''
    print(f'[{e[\"step\"]}] {e[\"result\"]}{rb} (attempt {e[\"attempt\"]})')
"
```

### 项目记忆

流水线自动维护 `.pipeline/project-memory.json`，存储跨流水线的项目约束。

```bash
# 查看当前约束
python3 -c "
import json
m = json.load(open('.pipeline/project-memory.json'))
print(f'项目定位: {m.get(\"project_purpose\", \"未定义\")}')
print(f'约束数量: {len(m.get(\"constraints\", []))}')
print(f'历史运行: {len(m.get(\"runs\", []))} 次')
for c in m.get('constraints', []):
    tags = ', '.join(c.get('tags', []))
    print(f'  [{c[\"id\"]}]({tags}) {c[\"text\"]}')
"

# 查看历次运行
ls .pipeline/history/
```

约束在每次流水线成功完成（7.monitor NORMAL）后自动提取，经用户确认后写入。
不建议手动编辑此文件——通过流水线管理以确保一致性。

### 提案队列

多提案系统使用提案队列管理交付顺序：

```bash
# 查看提案队列状态
python3 -c "
import json
q = json.load(open('.pipeline/proposal-queue.json'))
print(f'系统: {q[\"system_name\"]}')
for p in q['proposals']:
    status = '✓' if p['status'] == 'completed' else ('▶' if p['status'] == 'running' else '○')
    print(f'  {status} [{p[\"id\"]}] {p[\"title\"]} ({p[\"status\"]})')
"

# 重新规划（保留已完成的工作）
team replan
```
