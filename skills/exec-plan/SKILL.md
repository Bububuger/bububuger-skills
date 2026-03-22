---
name: exec-plan
description: "Create an exec-plan and sync it to a Linear issue. Invoke this skill after the Chancellor finishes designing a solution, to encode design intent into a self-contained task spec that Codex can execute. Trigger words: exec-plan, create task, record in Linear, new issue, dispatch task, split task. Even if the user just says 'hand this feature to Codex' or 'log a ticket', use this skill whenever a task for Codex needs to be created. Trigger aggressively — if there is any task to dispatch, this skill should run."
---

# Exec-Plan: Task Spec Creation

Encode the Chancellor's design intent into a self-contained exec-plan file and create a matching Linear issue.
The exec-plan always comes before the issue — the issue is a byproduct of the exec-plan. This ensures it is impossible to have an issue with no exec-plan.

## Input

`/exec-plan [feature-name] [requirement]`

- **feature-name** (optional): kebab-case identifier, e.g. `otlp-metrics-export`. If not provided, derive it from the requirement.
- **requirement** (optional): requirement description. If not provided, extract from the current conversation context.

## Prerequisites

- Current working directory is the target project repo (containing `docs/standards/exec-plan-template.md`)
- Linear MCP tools are available (`mcp__linear__save_issue`, etc.)
- The project's Linear project info can be read from `WORKFLOW.md` under `tracker.project_slug`

## Execution Steps

### Step 1: Locate Project Info

```
1. Read WORKFLOW.md frontmatter and extract:
   - tracker.project_slug (Linear project ID)
   - tracker.kind (confirm it is "linear")
2. Read docs/standards/exec-plan-template.md to get the template structure
3. Read AGENTS.md to understand project constraints (needed when filling in the exec-plan)
```

### Step 2: Assess Task Granularity

Before writing the exec-plan, evaluate whether the task needs to be split:

- Involves **more than 3 file changes** → consider splitting
- Spans **multiple packages/** → must split (to avoid cross-package rootDir violations)
- Estimated to exceed **8–12 turns** → must split
- Description is longer than **2–3 sentences** → consider splitting

If splitting is required, create a separate exec-plan for each subtask and use Linear's `blockedBy` to sequence dependencies.

### Step 3: Create the Exec-Plan File

```
File path: docs/exec-plans/{feature-name}.md
```

Fill in all sections from the template using information extracted from the current conversation:

```markdown
---
tags: [exec-plan]
created: {today}
modified: {today}
author: chancellor
status: active
---

## 目标
{Design goal extracted from conversation — one sentence}

## 设计参考
{Pointer to docs/design/, pointer to AGENTS.md constraints}

## 变更范围
{Specific file paths, annotated as modify/create}

## 禁止触碰
{Modules/files that must not be changed}

## 验证指令
npm run check && npm test
{Append scope-specific commands as needed: telemetry:check, test:bdd}

## 验收标准
- [ ] {Machine-verifiable criterion}
- [ ] npm run typecheck passes
- [ ] New test coverage ≥ 80%

## 注意事项
{Existing patterns to reference, special constraints to observe}
```

**Filling principles:**
- Design references use pointers, not transcription (`docs/design/xxx.md §section`, not copying content)
- Acceptance criteria must be machine-verifiable (not "works correctly", write "`npm test` passes")
- Change scope must be file-level precise (not "change the cli package", write `packages/cli/src/commands/report.ts`)

### Step 4: Git Commit

```bash
git add docs/exec-plans/{feature-name}.md
git commit -m "docs: add exec-plan for {feature-name}"
```

### Step 5: Create Linear Issue

Use the Linear MCP tool to create the issue:

```
Tool: mcp__linear__save_issue (or mcp__claude_ai_Linear__save_issue)
Parameters:
  title: {concise title derived from exec-plan goal}
  description: "exec-plan → docs/exec-plans/{feature-name}.md"
  projectId: {from WORKFLOW.md tracker.project_slug}
  state: "Todo"
```

If the task was split into multiple subtasks:
- Create a separate issue for each subtask
- Set `blockedBy` on later issues to point to their prerequisites

### Step 6: Confirm Output

> Output in Chinese for the human user

```
--- exec-plan created ---
File: docs/exec-plans/{feature-name}.md
Issue: {identifier} - {title}
URL: {issue URL}
State: Todo (waiting for Symphony to dispatch)
{If split: list all subtasks and their dependencies}
```

## Extracting Information from Conversation Context

The Chancellor typically discusses the design with the user before invoking this skill. Extract the following:

1. **Goal** — What does the user want to do? Why?
2. **Technical approach** — The implementation design the Chancellor has devised
3. **Files involved** — Modules/files mentioned in the discussion
4. **Constraints** — Restrictions raised in the discussion
5. **Acceptance criteria** — What the user described as "how it should look when done"

If there is not enough information to fill in a complete exec-plan, ask the user for the missing details. Do not guess.

## Rules

1. **Exec-plan before issue** — Always create the file first, then create the issue. It must be impossible for an issue to exist without an exec-plan.
2. **No skipped fields** — Every section in the template must be filled in. Ask the user if information is missing; do not leave fields blank.
3. **Granularity control** — Prefer splitting into multiple small tasks over one large task. Codex only has 8–12 turns.
4. **Pointers, not transcription** — Design references must be path pointers; do not copy design document content into the exec-plan.
5. **Commit before issue** — The exec-plan must be committed to the repo first so Codex can read it in its workspace.
