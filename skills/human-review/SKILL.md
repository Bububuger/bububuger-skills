---
name: human-review
description: "Chancellor reviews Human Review issues submitted by Codex. Read each workpad, inspect the PR, and decide (Merging or Rework) based on checkpoint_type. Trigger words: human review, review PR, process review, review items, check PR, acceptance, approve. When the user says 'handle the human review items' or 'check the PR', this skill MUST be used. Even with a single issue, run the full protocol. Trigger immediately — never skip this skill when review work is present."
---

# Human Review

The Chancellor acts as Harness Engineer. The focus is design intent, not code quality — CI, self-review, and cross-model review already ensure the code runs.

Every step of this skill has a corresponding output format. If a step is skipped, its output block cannot be filled in. This is intentional — it ensures every step is actually executed.

## Fetch Issues

```
Linear MCP: list_issues(team: "Bububuger", state: "Human Review")
```

Then process **each issue one at a time**. Do not batch-process — complete all steps and produce the full output record for one issue before moving to the next.

---

## Review Protocol (must be executed in full for each issue)

### Gate 1: Collect Facts

**All 3 queries below must be completed and their output written before proceeding to Gate 2.**

**1a. Read the workpad**

Use Linear MCP `list_comments` to fetch issue comments and find the comment marked `## Codex Workpad`.

Output (fill in accurately — omission is not allowed):
```
[BUB-xxx] Workpad Status:
  - Workpad exists: yes / no
  - Risk Assessment: {copy risk_level and checkpoint_type exactly, or "missing"}
  - Plan completion: {checked/total, e.g. "5/5" or "3/7"}
  - Acceptance Criteria: {checked/total}
  - Validation: {commands run, result pass/fail}
  - Cross-Review: {APPROVED / ESCALATED / not executed / missing}
  - Blockers: {yes/no, summary}
  - Confusions: {yes/no, summary}
```

**1b. Check the PR**

```bash
gh pr list --repo Bububuger/spanory --state open --json number,headRefName,title \
  --jq '.[] | select(.headRefName | contains("{issue-id-lowercase}"))'
```

Output:
```
  - PR exists: yes (#XX) / no
  - CI status: pass / fail / pending
```

**1c. Read the exec-plan**

Parse the `exec-plan →` path from the issue description and read the file.

Output:
```
  - exec-plan exists: yes (path) / no
  - Acceptance criteria count: {N items}
```

**Gate 1 check: All 3 output blocks must be filled in before continuing. If you jumped to Gate 2, come back and fill them in.**

---

### Gate 2: Identify Situation and Decide

Using the facts collected in Gate 1, match the situation against the table below and apply the only valid state transition:

```
Situation A: workpad exists + PR exists + CI pass
  → Standard review. Proceed to Gate 3 to review design intent.

Situation B: workpad exists + PR exists + CI fail
  → Do not review. Move to Rework with comment "CI failing, fix before re-review".

Situation C: workpad exists + no PR
  → Read the Blockers section in the workpad.
  → If blocker exists → help resolve it, then move to In Progress.
  → If no blocker → this is an anomaly; move to In Progress for Codex to continue.

Situation D: no workpad + PR exists
  → Harness anomaly (Codex skipped the workpad). Log to the failure ledger.
  → Still review the PR diff; move to Merging or Rework based on findings.

Situation E: no workpad + no PR
  → Codex has not started work. Move to In Progress (not Todo).
  → Exception: if the issue was never picked up by Codex (status jumped directly from created to Human Review),
    moving to Todo is the only permitted exception — but the reason must be stated in the output.

Situation F: human-action requires Chancellor to act on Codex's behalf (apply patch / create PR / etc.)
  → Chancellor must judge: after completing the human-action, does Codex still need to continue?

  F1: human-action is an auxiliary operation (make a decision / configure secrets / grant authorization) → Codex still needs to continue
    → Execute the operation, then move to In Progress

  F2: human-action is a completion operation (apply patch / create branch / push / create PR) → Chancellor has done all remaining work for Codex
    → Chancellor directly: apply patch → commit → push → create PR → merge PR → move to Done
    → Do NOT use Merging (Merging is for Codex's land skill; a PR created by the Chancellor is outside Codex's workspace)
```

Output:
```
  - Situation: A / B / C / D / E / F1 / F2
  - Valid transition: → Merging / → Rework / → In Progress / → Done (F2) / → Todo (Situation E unstarted only)
```

**Valid state transitions from Human Review (quick reference):**
- → **Merging**: Review passed; PR created by Codex is ready to merge (executed by Codex's land skill)
- → **Rework**: Review failed or CI failing; Codex must revise
- → **In Progress**: Codex work is incomplete, or human-action assistance is done and Codex must continue
- → **Done**: Chancellor completed all remaining work (apply patch + create PR + merge); task is finished
- → **Todo**: Only when the issue was never picked up by Codex (Situation E exception)

---

### Gate 3: Review Design Intent (Situation A only)

Quickly scan the PR diff (`gh pr diff`) against the exec-plan acceptance criteria and answer:

1. Is the change scope within the bounds specified in the exec-plan? (Any out-of-scope modifications?)
2. Are all acceptance criteria satisfied? (Check each one)
3. Is there any architectural deviation? (Violation of AGENTS.md constraints)

Output:
```
  - Scope compliant: yes / no (out-of-scope: {file list})
  - Acceptance criteria: {satisfied}/{total}
  - Architectural deviation: none / {description}
  - Decision: APPROVE → Merging / REJECT → Rework
  - Reason: {one sentence}
```

**Execute the decision:**
- APPROVE: `gh pr review --approve` + move issue to Merging
- REJECT: Leave a PR comment (specify which acceptance criterion failed or where the architectural deviation is) + move issue to Rework

---

### Gate 4: Harness Improvement (run for every issue)

Regardless of the decision outcome, answer:

```
  - Engineerable improvement found: yes / no
  - Improvement details: {description} or "none"
  - Action: {added linter rule / updated AGENTS.md / logged to failure ledger / no action needed}
```

If there is an improvement, execute it immediately (edit the file) or log it to `docs/operations/agent-failure-log.md`.

The `### Confusions` section in the Codex workpad is an important signal for Harness improvement — read it even when the review passes.

---

## Full Output Format (one record per issue)

> Output in Chinese for the human user

```
========== BUB-xxx: {title} ==========

[Gate 1: Fact Collection]
  - Workpad exists: ...
  - Risk Assessment: ...
  - Plan completion: ...
  - Acceptance Criteria: ...
  - Validation: ...
  - Cross-Review: ...
  - Blockers: ...
  - Confusions: ...
  - PR exists: ...
  - CI status: ...
  - exec-plan exists: ...
  - Acceptance criteria count: ...

[Gate 2: Situation]
  - Situation: ...
  - Valid transition: ...

[Gate 3: Design Intent Review]  (Situation A only)
  - Scope compliant: ...
  - Acceptance criteria: ...
  - Architectural deviation: ...
  - Decision: ...
  - Reason: ...

[Gate 4: Harness Improvement]
  - Engineerable improvement found: ...
  - Improvement details: ...
  - Action: ...

→ State transition: Human Review → {Merging / Rework / In Progress}
==========================================
```

After all issues are processed, output a summary table:

> Output in Chinese for the human user

```
--- Human Review Complete ---
| Issue | Situation | Decision | Transition | Harness Improvement |
```
