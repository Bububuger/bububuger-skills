---
name: review-dispatcher
description: "Dispatch structured findings from any review/audit report to a project management tool (Linear, Plane, GitHub Issues, etc.) as individual issues. Infers the source document and target platform from conversation context — no hardcoded file names or platforms. Use when user says 'dispatch review', 'create issues from review', 'dispatch findings', '报告转工单', '体检报告派发', '创建issue', 'send findings to tracker', '派发', or after running project-reviewer. Also trigger when user has a review report open and asks to turn findings into tickets, even if they don't say 'dispatch' explicitly."
---

# Review Dispatcher — 审查报告 → 工单

Reads a structured review/audit report, extracts findings, lets the user pick which ones to dispatch, and batch-creates issues in their project management tool.

## Step 1: Identify the Source Document

The source is whatever document contains structured findings the user wants to dispatch. Don't assume a fixed filename.

**Resolution order:**

1. **Explicit path** — user said "dispatch findings from X.md" → use that file
2. **Conversation context** — a report was just generated (e.g., by `project-reviewer`) or the user was just discussing a specific report → use that
3. **Working directory scan** — look for likely candidates: `*REVIEW*`, `*REPORT*`, `*AUDIT*` (case-insensitive glob in cwd). If exactly one match, propose it. If multiple, list them and ask.
4. **Ask** — if nothing found, ask the user for the path

**Confirm before proceeding:**

```
找到报告: PROJECT_REVIEW_REPORT.md (32 findings)
确认使用此文件？或指定其他路径？
```

The user's confirmation can be brief ("可", "yes", "对") — don't require elaborate answers.

## Step 2: Parse Findings

Extract all structured findings from the report. Support these common formats:

**Heading-based** (project-reviewer style):
```
### [P0|P1|P2|P3] <title>
- **Location**: ...
- **Issue**: ...
- **Impact**: ...
- **Recommendation**: ...
- **Effort**: Low | Medium | High
```

**Table-based:**
```
| Priority | Title | Location | Description |
```

**Numbered list with priority tags:**
```
1. [P0] Title — description
```

Build a structured list with fields: `priority`, `title`, `location`, `issue`, `impact`, `recommendation`, `effort`, `reviewer_role` (from section heading if available). Missing fields are OK — work with what the report provides.

## Step 3: Identify the Target Platform

The target is where the issues will be created. Don't assume Linear.

**Resolution order:**

1. **Explicit request** — user said "dispatch to Plane" or "create Linear issues" → use that
2. **Conversation context** — prior discussion mentions a specific tracker, or the project's config (e.g., Symphony's `WORKFLOW.md`) references a tracker → use that
3. **Available MCP tools** — check which project management MCPs are connected:
   - `mcp__linear__*` → Linear is available
   - `mcp__plane__*` → Plane is available
   - GitHub CLI (`gh`) → GitHub Issues is available
   - If exactly one platform is available, propose it
   - If multiple, list them and ask
4. **Running processes** — if no MCP clues, check for running services:
   ```
   ps aux | grep -iE 'linear|plane|jira' (lightweight check)
   ```
5. **Ask** — if still ambiguous, ask the user

**Confirm before proceeding — show the full dispatch plan:**

```
派发计划:
  来源: PROJECT_REVIEW_REPORT.md (32 findings)
  目标: Linear (MCP 已连接)
  团队: Bububuger
  项目: spanory
  初始状态: Todo

确认？或需要调整？
```

For Linear specifically, these defaults apply unless overridden:
- **Team**: Bububuger
- **Project**: spanory
- **Initial Status**: Todo

For other platforms, ask the user for the equivalent target settings (project/workspace/repo).

## Step 4: Present Findings for Selection

Show a summary grouped by priority:

```
## P0 Critical (2 items)
  1. [P0] SQL injection in login endpoint — src/auth.ts:42 — Effort: Low
  2. [P0] Unencrypted secrets in config — .env.example — Effort: Medium

## P1 High (5 items)
  3. [P1] Missing rate limiting — src/api/router.ts — Effort: Medium
  ...

## P2 Medium (8 items) ...
## P3 Low (4 items) ...
```

Ask:
- Which findings to dispatch? (e.g., "all P0+P1", "1,3,5-8", "all")
- Assignee? (default: none)

## Step 5: Create Issues

### Linear (via MCP)

Map priorities and create issues:

| Review | Linear Priority | Value |
|--------|----------------|-------|
| P0     | Urgent         | 1     |
| P1     | High           | 2     |
| P2     | Normal         | 3     |
| P3     | Low            | 4     |

Label mapping:
| Pattern | Label |
|---------|-------|
| Security, vulnerability, CVE, leak | Bug |
| Missing feature, not implemented | Feature |
| Refactor, cleanup, docs, style | Improvement |
| Default | Improvement |

Issue format:
```yaml
title: "[P{n}] {title}"
description: |
  **来源**: {report_filename} ({date})
  **审查角色**: {reviewer_role}
  **位置**: {location}

  ## 问题
  {issue}

  ## 影响
  {impact}

  ## 建议修复
  {recommendation}

  **预估工作量**: {effort}
priority: {mapped_value}
labels: [{mapped_label}]
```

### GitHub Issues (via `gh`)

```bash
gh issue create --title "[P{n}] {title}" --body "..." --label "{label}"
```

Map P0→critical, P1→high-priority, P2→medium, P3→low-priority (create labels if missing).

### Other Platforms (Plane, Jira, etc.)

If there's an MCP for the platform, use it. If not, generate a structured output file (e.g., `dispatch-output.json` or CSV) that the user can bulk-import, and explain how.

## Step 6: Summary

```
## 派发完成

已创建 N 个工单 (Linear):

| # | Issue ID  | Priority   | Title          |
|---|-----------|------------|----------------|
| 1 | BUB-123   | P0 Urgent  | Finding title  |
| 2 | BUB-124   | P1 High    | Finding title  |

跳过: M 个 (用户未选择)
```

## Error Handling

- Platform MCP not connected → inform user, suggest alternatives (e.g., "Linear MCP 未连接，可输出为 JSON 供手动导入")
- Finding parse failure → include with `[PARSE WARNING]` tag, let user decide
- Individual issue creation failure → log error, continue with rest, report failures at end
- Never silently skip findings
- Never create issues the user didn't approve
