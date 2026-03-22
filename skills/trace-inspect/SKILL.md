---
name: trace-inspect
description: "Inspect Codex agent execution traces via local Langfuse ClickHouse. Diagnose what an agent is doing, whether it follows the Harness workflow, and where it's stuck. Trigger on: trace, check trace, inspect trace, what is codex doing, agent stuck, bub stuck, check bub, look at bub, 排查, 看看, 卡住了, 在干嘛. Use this skill whenever the user asks about agent execution status, wants to verify Harness compliance, or reports an agent running too long."
---

# Trace Inspect

Diagnose Codex agent execution by querying local Langfuse ClickHouse traces. Answers: what is the agent doing, is it following the Harness workflow, and where is it stuck.

## Prerequisites

- Local Langfuse with ClickHouse running (`localhost:8123`)
- Credentials: `clickhouse:clickhouse` (default local setup)
- Spanory project traces being collected

## Input

`/trace-inspect [issue-id or trace-id]`

- **issue-id** (e.g. `BUB-134`): finds the latest trace for that issue
- **trace-id** (e.g. `8c21e30b...`): inspects a specific trace
- **no argument**: lists recent Codex traces to choose from

## Inspection Protocol

### Step 1: Locate the trace

**If issue-id given** — find the main WORKFLOW.md turn:
```bash
curl -s "http://localhost:8123" -u "clickhouse:clickhouse" --data-binary "
SELECT trace_id, name, start_time
FROM observations
WHERE type = 'AGENT'
AND toString(input) LIKE '%You are working on a Linear ticket%{ISSUE_ID}%'
ORDER BY start_time DESC
LIMIT 3
FORMAT JSONEachRow"
```

**If no argument** — list recent Codex main turns:
```bash
curl -s "http://localhost:8123" -u "clickhouse:clickhouse" --data-binary "
SELECT trace_id, name, start_time,
       substring(toString(input), 1, 120) as preview
FROM observations
WHERE start_time > now() - INTERVAL 2 HOUR
AND type = 'AGENT'
AND toString(input) LIKE '%You are working on a Linear ticket%'
ORDER BY start_time DESC
LIMIT 10
FORMAT JSONEachRow"
```

### Step 2: Get the execution timeline

List all tool calls in chronological order:
```bash
curl -s "http://localhost:8123" -u "clickhouse:clickhouse" --data-binary "
SELECT name, type, start_time,
       substring(toString(input), 1, 200) as inp,
       substring(toString(output), 1, 150) as out
FROM observations
WHERE trace_id = '{TRACE_ID}'
AND type IN ('TOOL', 'AGENT')
ORDER BY start_time ASC
FORMAT JSONEachRow"
```

Parse and display as a numbered timeline with timestamps.

### Step 3: Harness compliance check

Verify the agent followed the v4.1 Harness workflow by checking for these markers in the tool call sequence:

```
[Step 0.5: Context Loading]
  □ Read AGENTS.md (look for: Bash sed/cat AGENTS.md)
  □ Read exec-plan (look for: Bash sed/cat docs/exec-plans/)
  □ Read progress.txt (look for: Bash cat/sed progress.txt)
  □ Baseline check (look for: Bash npm run check)

[Step 1: Planning]
  □ Linear state query (look for: linear_graphql with issue query)
  □ Workpad create/update (look for: linear_graphql with commentUpdate)
  □ update_plan tool call

[Step 2: Implementation]
  □ Code changes (look for: apply_patch or Bash with file edits)
  □ Local validation (look for: Bash npm run check && npm test)
  □ Goal-backward verification (look for: Bash rg TODO/FIXME/console.log)

[Step 3a: Review]
  □ Self-review (look for: Bash gh pr diff)
  □ Cross-review (look for: spawn_agent with "cross-review" or "claude -p")
  □ PR approve (look for: Bash gh pr review --approve)

[Wrap-up]
  □ progress.txt update (look for: Bash with progress.txt write)
  □ Commit + push (look for: Bash git commit, git push)
  □ PR creation (look for: Bash gh pr create)
```

### Step 4: Identify problems

Check for these common failure patterns:

| Pattern | How to detect | Meaning |
|---------|--------------|---------|
| Sandbox denied | output contains "Sandbox(Denied" | turn_sandbox_policy not dangerFullAccess |
| Agent thread limit | output contains "thread limit reached" | too many sub-agents spawned, close old ones |
| Stuck in test loop | 3+ consecutive spawn_agent for same test | test keeps failing, hit fix attempt limit? |
| No context loading | No AGENTS.md/exec-plan reads in first 5 calls | old WORKFLOW.md without Step 0.5 |
| No cross-review | No claude -p or cross-review in Step 3a | skill not available or graceful degradation triggered |
| Stalled | last observation > 5 min ago | check Symphony stall detection or Codex hang |
| Empty turns | multiple turns < 5s | circuit breaker should trigger |

### Step 5: Check current state

If the agent appears to still be running:
```bash
# Check latest activity timestamp
curl -s "http://localhost:8123" -u "clickhouse:clickhouse" --data-binary "
SELECT max(start_time) as last_activity,
       dateDiff('minute', max(start_time), now()) as minutes_ago
FROM observations
WHERE trace_id = '{TRACE_ID}'
FORMAT JSONEachRow"
```

```bash
# Check Linear issue current state
# Use Linear MCP: get_issue({ISSUE_ID})
```

```bash
# Check Symphony logs for errors
grep "{ISSUE_ID}" ~/code/symphony/elixir/log/symphony.log.* | grep -i "error\|fail\|exited" | tail -5
```

## Output Format

> Output in Chinese for the human user

```
========== {ISSUE_ID}: {title} ==========
Trace: {trace_id}
Started: {start_time}  Duration: {minutes}min  Turns: {turn_count}

[Harness Compliance]
  ✓/✗ Context Loading (AGENTS.md, exec-plan, progress.txt, baseline)
  ✓/✗ Planning (workpad, plan)
  ✓/✗ Implementation (code changes, validation)
  ✓/✗ Review (self-review, cross-review)
  ✓/✗ Wrap-up (progress.txt, commit, PR)

[Current State]
  Last activity: {timestamp} ({N} min ago)
  Linear status: {state}
  Phase: {current step in workflow}

[Problems Found]
  - {problem description and suggested fix}

[Timeline Summary]
  {timestamp} Step 0.5: read AGENTS.md, exec-plan, baseline pass
  {timestamp} Step 2: implementing... {N} file changes
  {timestamp} Step 2: validation fail → fix attempt 1/3
  {timestamp} Step 2: validation pass
  {timestamp} Step 3a: self-review clean
  {timestamp} Step 3a: cross-review round 1...
  ...
==========================================
```

## Quick Commands

For rapid diagnosis without full protocol:

**What is agent doing right now?**
```bash
curl -s "http://localhost:8123" -u "clickhouse:clickhouse" --data-binary "
SELECT name, type, start_time, substring(toString(input), 1, 100) as what
FROM observations
WHERE trace_id = '{TRACE_ID}'
ORDER BY start_time DESC LIMIT 3
FORMAT JSONEachRow"
```

**Did cross-review run?**
```bash
curl -s "http://localhost:8123" -u "clickhouse:clickhouse" --data-binary "
SELECT count() as cross_review_calls
FROM observations
WHERE trace_id = '{TRACE_ID}'
AND (toString(input) LIKE '%cross-review%' OR toString(input) LIKE '%claude -p%' OR toString(input) LIKE '%senior code reviewer%')
FORMAT JSONEachRow"
```

**How many turns consumed?**
```bash
curl -s "http://localhost:8123" -u "clickhouse:clickhouse" --data-binary "
SELECT count() as turns
FROM observations
WHERE trace_id = '{TRACE_ID}'
AND type = 'AGENT'
AND name LIKE 'codex - Turn%'
FORMAT JSONEachRow"
```
