---
name: claude-review-codex
description:
  Cross-model review gate for Codex-authored code. After implementation and
  local validation pass, invoke Claude (Opus) via local CLI to review the diff
  against AGENTS.md constraints and exec-plan acceptance criteria. Write→Review→Fix
  loop runs at most 3 rounds; P0-free exits with APPROVE, otherwise escalates to
  Human Review. Use this skill after self-review (Step 3a) passes but before
  approving the PR. Trigger immediately — do not skip this gate.
---

# Cross-Model Review (Claude reviews Codex)

After Codex completes development and local validation passes, invoke the local Claude CLI for heterogeneous-model review. Different models have different blind spots; cross-model review surfaces issues that self-review cannot catch.

## Prerequisites

- Code is implemented and passes local validation (`npm run check && npm test`)
- Changes are committed to the current branch
- `claude` CLI is available (`which claude` should return a path)
- `ANTHROPIC_API_KEY` is set in the environment (`shell_environment_policy.inherit=all` configured)

## Invocation Timing

Invoke **after** WORKFLOW.md Step 3a (auto-review) self-review passes and **before** approving the PR.

## Input Collection

Collect the following context before invoking:

```bash
# 1. diff (relative to main)
DIFF_FILE=$(mktemp /tmp/cross-review-diff-XXXXXX.md)
git diff origin/main...HEAD > "$DIFF_FILE"

# 2. AGENTS.md constraints
AGENTS_FILE="AGENTS.md"

# 3. exec-plan (parse path from issue description, if present)
# EXEC_PLAN_FILE="docs/exec-plans/bub-xxx.md"
```

## Review Loop (max 3 rounds)

Maintain state:
- `round`: current round number (1–3)
- `review_history`: accumulated results from all previous rounds
- `fix_summary`: summary of changes made this round

### Round 1 — Initial Review

```bash
REVIEW_RAW=$(mktemp /tmp/claude-review-raw-XXXXXX.md)
REVIEW_CLEAN=$(mktemp /tmp/claude-review-clean-XXXXXX.md)

claude -p "You are a senior code reviewer (Claude Opus). You are reviewing code produced by another AI agent (Codex/GPT).

## Project Constraints
$(cat "$AGENTS_FILE")

## Change Diff
$(cat "$DIFF_FILE")

Please review comprehensively:
1. Correctness — Is the logic correct? Are edge cases handled?
2. Architecture compliance — Does it follow AGENTS.md constraints (Contract-First, immutable design, field registry, adapter isolation, etc.)?
3. Type safety — Is TypeScript strict mode satisfied? Does 'any' leak?
4. Cross-package boundaries — Are there direct internal file imports that violate rootDir rules?
5. Test coverage — Are new logic paths covered by tests?
6. Security — Are there secret leaks or injection risks?

Classify each issue as P0 (blocking) / P1 (important) / P2 (suggestion).
Attach the specific file path and line number for each issue.
If there are no P0 issues, write NO_P0 at the end.

<<<REVIEW_BEGIN>>>
(Output structured review findings between these markers)
<<<REVIEW_END>>>" 2>&1 | tee "$REVIEW_RAW"

# Extract clean result
bash "{skill_dir}/scripts/extract-review.sh" "$REVIEW_RAW" "$REVIEW_CLEAN"
```

Read `$REVIEW_CLEAN` to determine the outcome.

### Round 2/3 — Incremental Review

```bash
claude -p "You are a senior code reviewer (Claude Opus), conducting round {round} of review.

## Previous Review Results
{review_history}

## Changes Made This Round
{fix_summary}

## Project Constraints
$(cat "$AGENTS_FILE")

## Change Diff
$(git diff origin/main...HEAD)

Please complete:
1. Verify whether each P0/P1 issue from the previous round has been fixed — mark each as [FIXED] or [NOT FIXED]
2. Check whether the changes introduced any new issues
3. Overall incremental review

Output format:
### Previous Issue Verification
- [FIXED/NOT FIXED] Issue description

### New Issues Found
Classified as P0/P1/P2. Write NO_P0 if no new P0 issues.

### Outstanding Issues Summary
List of unresolved issues.

<<<REVIEW_BEGIN>>>
<<<REVIEW_END>>>" 2>&1 | tee "$REVIEW_RAW"

bash "{skill_dir}/scripts/extract-review.sh" "$REVIEW_RAW" "$REVIEW_CLEAN"
```

## Judgment Logic

- **No P0** (result contains `NO_P0`) → **PASS** — record P1 issues in workpad for reference
- **P0 present and round < 3** → fix issues, commit, proceed to next round
- **P0 still present after round 3** → abort, escalate to `Human Review`
- **Convergence check** → if P0 count increases compared to the previous round, abort immediately (wrong direction)

## Fix Principles

- Only fix the issues that were flagged — do not take the opportunity to refactor
- Re-run local validation after each fix (`npm run check && npm test`) to confirm no regressions
- Record `fix_summary` for use in the next review round

## Actions on Pass

After review passes:
1. Record in workpad under `### Cross-Review` section:
   ```
   - Reviewer: Claude Opus
   - Rounds: {n}/3
   - Result: APPROVED
   - P1 remaining: {list or "none"}
   ```
2. Continue with the approve → merge flow in WORKFLOW.md

## Actions on Failure (after 3 rounds)

1. Record review failure and outstanding P0 issues in workpad
2. Escalate to `Human Review`

## Per-Round Output

> Output in Chinese for the human user

```
--- Round {n}/3 · Cross-Model Review ---
Reviewer: Claude Opus (local CLI)
Result: P0:{x} P1:{x} P2:{x}
{Previous round fix verification (from round 2 onward)}
{Issue list}
Changes: {fix_summary}
```

## Rules

1. **Self-review must pass first** — this skill is the second gate after self-review, not a replacement for it.
2. **Local execution** — invoked via `claude -p` on the local CLI; the API key never leaves the machine.
3. **Hard 3-round limit** — hand off to Human Review after 3 rounds to prevent infinite loops.
4. **Convergence first** — abort immediately if P0 count increases.
5. **Small targeted fixes** — only fix what was flagged; do not expand scope.
6. **P0-free = pass** — P1 issues are listed for reference but do not block.
7. **Wait for process exit** — `claude -p` is a synchronous call; wait for it to return before parsing output.

## Claude CLI Notes

| Issue | Mitigation |
|-------|------------|
| `claude -p` output may contain ANSI escape codes | Piping through `tee` strips them automatically |
| Diff too large for context window | Pass only the diff for changed files, not the entire repo |
| `claude` CLI not found | Check with `which claude`; if absent, skip cross-review and fall back to auto-review only |
| API call fails | Retry once; if still failing, skip cross-review and note it in workpad |
