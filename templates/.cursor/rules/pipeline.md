---
description: 多角色软件交付流水线规则。当用户提到流水线、pipeline、/pilot 或涉及 .pipeline/ 目录时应用。
globs:
  - .pipeline/**
  - CLAUDE.md
  - AGENTS.md
---

# 多角色软件交付流水线

本项目使用多角色软件交付流水线（v6.5）。

## 关键规则

1. **不要手动修改** `.pipeline/state.json` 和 `.pipeline/playbook.md`，它们由 Pilot 管理
2. **不要修改** `.pipeline/autosteps/` 中的脚本
3. **可以编辑** `.pipeline/config.json` 来自定义项目配置
4. **产物目录** `.pipeline/artifacts/` 存放所有阶段输出

## 启动流水线

在 Cursor Agent 模式中调用 `/pilot` 子 Agent 来启动或继续流水线。
Pilot 每次执行一个批次后退出，再次调用 `/pilot` 继续下一批次。

## 查看状态

```bash
team status
```

## 目录结构

- `.pipeline/config.json` — 项目配置
- `.pipeline/state.json` — 运行时状态（Pilot 管理）
- `.pipeline/playbook.md` — 阶段手册（Pilot 按需加载）
- `.pipeline/artifacts/` — 各阶段产物
- `.pipeline/autosteps/` — AutoStep 脚本
- `.worktrees/` — 3.build 阶段的临时 worktree

## Agent 角色

| 类别 | Agent |
|------|-------|
| 主控 | pilot |
| 需求 | clarifier |
| 设计 | architect |
| 审核 | auditor-gate, auditor-qa, auditor-tech |
| 规划 | planner, resolver |
| 构建 | builder-frontend, builder-backend, builder-dba, builder-security, builder-infra |
| 精简/审查 | simplifier, inspector |
| 测试 | tester, optimizer |
| 发布 | documenter, deployer, monitor |
