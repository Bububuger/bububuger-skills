---
name: exec-plan
description: "创建 exec-plan 并同步录入 Linear issue。丞相设计完方案后调用此 skill，将设计意图编码为 Codex 可执行的自包含任务规格。触发词：exec-plan、创建任务、录入Linear、新建issue、派发任务、拆分任务。即使用户只说'这个功能交给codex做'或'录一个ticket'，只要涉及创建给 Codex 执行的任务，都应使用本 skill。"
---

# Exec-Plan: 任务规格创建

将丞相的设计意图编码为自包含的 exec-plan 文件，同步创建 Linear issue。
exec-plan 先于 issue 存在，issue 是 exec-plan 的副产品——这样不存在"有 issue 但没 exec-plan"的可能。

## 输入

`/exec-plan [feature-name] [requirement]`

- **feature-name**（可选）：kebab-case 标识，如 `otlp-metrics-export`。未提供则从需求中推导。
- **requirement**（可选）：需求描述。未提供则从当前对话上下文提取。

## 前置条件

- 当前工作目录为目标项目的 repo（含 `docs/standards/exec-plan-template.md`）
- Linear MCP 工具可用（`mcp__linear__save_issue` 等）
- 项目的 Linear project 信息可从 `WORKFLOW.md` 的 `tracker.project_slug` 获取

## 执行流程

### Step 1: 定位项目信息

```
1. 读取 WORKFLOW.md frontmatter，提取:
   - tracker.project_slug（Linear 项目 ID）
   - tracker.kind（确认是 linear）
2. 读取 docs/standards/exec-plan-template.md 获取模板结构
3. 读取 AGENTS.md 了解项目约束（填写 exec-plan 时需引用）
```

### Step 2: 评估任务粒度

在写 exec-plan 之前，先评估任务是否需要拆分：

- 涉及 **3 个以上文件变更** → 考虑拆分
- 涉及 **多个 packages/** → 必须拆分（避免跨包 rootDir 违规）
- 预估超过 **8-12 turns** → 必须拆分
- 描述超过 **2-3 句话** → 考虑拆分

如果需要拆分，为每个子任务分别创建 exec-plan，用 Linear 的 `blockedBy` 编排依赖顺序。

### Step 3: 创建 exec-plan 文件

```
文件路径: docs/exec-plans/{feature-name}.md
```

按模板填写所有章节，从当前对话上下文中提取信息：

```markdown
---
tags: [exec-plan]
created: {today}
modified: {today}
author: chancellor
status: active
---

## 目标
{从对话中提取的设计目标，一句话}

## 设计参考
{指向 docs/design/ 的指针，指向 AGENTS.md 约束}

## 变更范围
{具体文件路径，标注修改/新建}

## 禁止触碰
{不应改动的模块/文件}

## 验证指令
npm run check && npm test
{按范围追加: telemetry:check, test:bdd}

## 验收标准
- [ ] {可机器验证的标准}
- [ ] npm run typecheck passes
- [ ] 新增测试覆盖率 ≥ 80%

## 注意事项
{参考的现有模式、特别注意的约束}
```

**填写原则：**
- 设计参考用指针而非复述（`docs/design/xxx.md §章节` 而非把内容抄过来）
- 验收标准必须可机器验证（不写"工作正常"，写"`npm test` 通过"）
- 变更范围精确到文件级（不写"改 cli 包"，写 `packages/cli/src/commands/report.ts`）

### Step 4: Git commit

```bash
git add docs/exec-plans/{feature-name}.md
git commit -m "docs: add exec-plan for {feature-name}"
```

### Step 5: 创建 Linear issue

使用 Linear MCP 工具创建 issue：

```
工具: mcp__linear__save_issue (或 mcp__claude_ai_Linear__save_issue)
参数:
  title: {从 exec-plan 目标推导的简洁标题}
  description: "exec-plan → docs/exec-plans/{feature-name}.md"
  projectId: {从 WORKFLOW.md 的 tracker.project_slug 获取}
  state: "Todo"
```

如果是拆分后的多个子任务：
- 每个子任务各自创建 issue
- 后续 issue 设置 `blockedBy` 指向前置 issue

### Step 6: 确认输出

```
--- exec-plan 已创建 ---
文件: docs/exec-plans/{feature-name}.md
Issue: {identifier} - {title}
URL: {issue URL}
状态: Todo（等待 Symphony 派发）
{如有拆分: 列出所有子任务及依赖关系}
```

## 从对话上下文提取信息

丞相通常在调用此 skill 之前已经和主公讨论了设计方案。提取以下信息：

1. **目标** — 主公要做什么？为什么做？
2. **技术方案** — 丞相设计的实现方式
3. **涉及的文件** — 讨论中提到的模块/文件
4. **约束** — 讨论中提到的限制条件
5. **验收标准** — 主公说"做完后应该怎样"的部分

如果信息不足以填写完整的 exec-plan，向主公提问补全，不要猜测。

## 规则

1. **exec-plan 先于 issue** — 永远先创建文件再创建 issue，确保不存在无 exec-plan 的 issue。
2. **不跳过字段** — 模板中的每个章节都要填写。信息不足时问主公，不留空。
3. **粒度把控** — 宁可拆成多个小任务也不做一个大任务。Codex 只有 8-12 turns。
4. **指针非复述** — 设计参考写路径指针，不把设计文档内容抄到 exec-plan 中。
5. **commit 先于 issue** — exec-plan 必须先 commit 到 repo，Codex 才能在 workspace 中读取。
