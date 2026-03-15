---
name: project-reviewer
description: "Multi-role project audit team that reviews codebases from 12 specialized perspectives (type safety, architecture, security, testing, performance, error handling, dependencies, API design, code standards, engineering governance, documentation freshness, setup/teardown symmetry) and produces a comprehensive fault-finding report with prioritized issues. Use this skill whenever the user asks to review a project, audit code quality, find problems in a codebase, do a health check, 挑毛病, 代码审查, 项目体检, or wants a comprehensive analysis of what's wrong with their project. Also trigger when users say things like 'what's wrong with this project', 'review my code', 'find issues', 'code audit', 'quality check', '审视项目', 'check docs match code', or 'verify install/uninstall alignment'."
---

# Project Reviewer — 挑毛病天团

A multi-perspective project audit skill that assembles a team of 10 specialized reviewers to examine a codebase from every angle that matters. Each reviewer is an independent expert who runs in parallel, producing findings that are then synthesized into a single prioritized report.

## Why This Approach Works

Real code review suffers from tunnel vision — a security expert misses architecture issues, a performance engineer overlooks test gaps. By splitting the audit into independent roles with clear mandates, each reviewer goes deep in their domain without distraction. The synthesis step then cross-references findings and eliminates duplicates, producing a report that no single reviewer could.

## Workflow

### Phase 1: Reconnaissance (you do this yourself)

Before spawning reviewers, gather the project context they'll all need:

1. **Read project metadata** — package.json (or equivalent), README, any ARCHITECTURE.md
2. **Map the structure** — `ls` top-level dirs, identify language/framework/build system
3. **Check git health** — recent commits, branch count, commit message patterns
4. **Identify tech stack** — languages, frameworks, key dependencies

Compile this into a **Project Brief** (a few paragraphs). Every reviewer gets this brief so they don't waste time re-discovering basics.

### Phase 2: Parallel Review (spawn 10 reviewer agents)

Launch ALL reviewers in a single message as parallel subagents. Each reviewer:
- Receives the Project Brief + their role-specific instructions
- Has full read access to the codebase
- Returns structured findings in a consistent format

Read `references/reviewers.md` for the detailed instructions for each role. The 10 roles are:

| # | Role | Codename | Focus |
|---|------|----------|-------|
| 1 | Type Guardian | `type-guardian` | Type safety, strict mode, type coverage |
| 2 | Architect | `architect` | Module structure, file sizes, dependency direction, coupling |
| 3 | Code Sheriff | `code-sheriff` | Lint config, formatting, naming conventions, style consistency |
| 4 | Test Inspector | `test-inspector` | Coverage, test types, boundary cases, test quality |
| 5 | Security Auditor | `security-auditor` | Vulnerabilities, secret leaks, dependency CVEs, OWASP |
| 6 | Error Wrangler | `error-wrangler` | Error handling, empty catches, error propagation, user messages |
| 7 | Governance Officer | `governance-officer` | CI/CD, versioning, changelog, docs, release process |
| 8 | Performance Strategist | `perf-strategist` | Bundle size, startup time, memory, algorithmic complexity |
| 9 | API Critic | `api-critic` | CLI/API design, parameter consistency, public interface quality |
| 10 | Dependency Steward | `dep-steward` | Outdated packages, duplicates, licenses, supply chain risk |
| 11 | Doc Freshness Auditor | `doc-freshness` | README vs code drift, stale docs, missing commands in docs |
| 12 | Setup Symmetry Auditor | `setup-symmetry` | apply/doctor/teardown alignment, orphaned operations |

**Reviewer agent prompt template:**

```
You are the {role_name} ({codename}) on a project audit team.

## Project Brief
{project_brief}

## Your Mission
{role_specific_instructions from references/reviewers.md}

## Output Format
Return your findings as structured markdown:

# {Role Name} Review

## Summary
One paragraph overall assessment for this dimension.

## Findings

### [P0/P1/P2/P3] Finding title
- **Location**: file path(s) and line number(s)
- **Issue**: What's wrong
- **Impact**: Why it matters
- **Recommendation**: How to fix it
- **Effort**: Low / Medium / High

(Repeat for each finding, ordered by severity)

## Score: X/10
Brief justification for the score.

## Commendations
What the project does WELL in this dimension (important for balance).
```

Use `model: "sonnet"` for each reviewer agent to keep cost efficient while maintaining quality.

**CRITICAL: You MUST use the Agent tool to spawn all reviewers in a single message as parallel subagents.** Do NOT delegate to a single agent that then sub-dispatches (this causes serial execution via codex/MCP and is 5x slower). The main session orchestrates directly:

```
# In ONE message, spawn all 12 agents:
Agent(prompt="You are the Type Guardian...", model="sonnet", run_in_background=true)
Agent(prompt="You are the Architect...", model="sonnet", run_in_background=true)
Agent(prompt="You are the Code Sheriff...", model="sonnet", run_in_background=true)
... (all 12 in parallel)
```

This ensures all reviewers run concurrently (~5 min total vs ~60 min serial).

### Phase 3: Synthesis (you do this yourself)

After all 12 reviewers return, synthesize their findings:

1. **Collect** all findings from all reviewers
2. **Deduplicate** — merge findings that describe the same underlying issue from different angles
3. **Cross-reference** — note when multiple reviewers flag the same area (stronger signal)
4. **Prioritize** — final priority based on:
   - P0 (Critical): Blocks production safety, data loss risk, security vulnerability
   - P1 (High): Significant maintainability/reliability risk, should fix soon
   - P2 (Medium): Quality improvement, fix when convenient
   - P3 (Low): Nice-to-have, polish items
5. **Score** — compute overall project health score (average of 12 dimension scores)

### Phase 4: Report Generation

Produce the final report in this structure:

```markdown
# 项目体检报告 — {Project Name}

**审查日期**: {date}
**审查版本**: {git commit hash}
**技术栈**: {tech stack summary}

## 综合评分: X.X / 10

| 维度 | 评分 | 关键发现 |
|------|------|----------|
| 类型安全 | X/10 | 一句话 |
| 架构设计 | X/10 | 一句话 |
| ... | ... | ... |

## 问题总览

| 优先级 | 数量 | 占比 |
|--------|------|------|
| P0 Critical | N | xx% |
| P1 High | N | xx% |
| P2 Medium | N | xx% |
| P3 Low | N | xx% |

## P0 — 必须立即修复
{findings}

## P1 — 尽快修复
{findings}

## P2 — 计划修复
{findings}

## P3 — 锦上添花
{findings}

## 亮点与表扬
Things the project does well — important for morale and to avoid
making the report feel purely negative.

## 治理建议路线图
Suggested order of remediation, grouped into phases:
- Phase 1 (This week): P0 items
- Phase 2 (This sprint): P1 items
- Phase 3 (This quarter): P2 items
- Phase 4 (Backlog): P3 items

## 各维度详细报告
Append each reviewer's full report as a collapsible section.
```

Save the report to the project root as `PROJECT_REVIEW_REPORT.md` (or a user-specified path).

## Customization

The user can customize the review:
- **Skip roles**: "skip the performance review" → omit that reviewer
- **Add roles**: "also check i18n" → add a custom reviewer
- **Focus areas**: "focus on security and testing" → only spawn those reviewers
- **Language**: Report can be in Chinese (default if user speaks Chinese) or English
- **Scope**: Can target a subdirectory instead of the whole project
