---
name: human-review
description: "丞相审查 Codex 提交的 Human Review issue。逐个读 workpad、检查 PR、根据 checkpoint_type 裁决（Merging 或 Rework）。触发词：human review、审查PR、处理review、review items、看下PR、验收、approve。当主公说'处理下human review的item'或'看下PR'时必须使用本skill。即使只有一个issue也要走完整流程。"
---

# Human Review

丞相是 Harness Engineer。审的是设计意图，不是代码质量——CI、自审、交叉审查已经保证了代码能跑。

这个 skill 的每一步都有对应的输出格式。如果跳过某步，输出格式就填不出来，这是有意设计的——确保每步都被执行。

## 获取 issues

```
Linear MCP: list_issues(team: "Bububuger", state: "Human Review")
```

然后对**每个 issue 逐个**执行下面的审查协议。不要批量处理——一个 issue 走完全部步骤、输出完整记录后，再处理下一个。

---

## 审查协议（每个 issue 必须完整执行）

### Gate 1: 收集事实

**必须完成以下 3 项查询，并输出结果，才能进入 Gate 2。**

**1a. 读 workpad**

用 Linear MCP 的 `list_comments` 获取 issue 的评论，找到 `## Codex Workpad` 标记的评论。

输出（照实填写，不可省略）：
```
[BUB-xxx] Workpad 状态:
  - workpad 存在: yes / no
  - Risk Assessment: {照抄 risk_level 和 checkpoint_type，或 "缺失"}
  - Plan 完成度: {已勾选/总数，如 "5/5" 或 "3/7"}
  - Acceptance Criteria: {已勾选/总数}
  - Validation: {跑了什么命令，结果 pass/fail}
  - Cross-Review: {APPROVED/ESCALATED/未执行/缺失}
  - Blockers: {有/无，摘要}
  - Confusions: {有/无，摘要}
```

**1b. 检查 PR**

```bash
gh pr list --repo Bububuger/spanory --state open --json number,headRefName,title \
  --jq '.[] | select(.headRefName | contains("{issue-id-lowercase}"))'
```

输出：
```
  - PR 存在: yes (#XX) / no
  - CI 状态: pass / fail / pending
```

**1c. 读 exec-plan**

从 issue description 中解析 `exec-plan →` 路径，读取文件。

输出：
```
  - exec-plan 存在: yes (路径) / no
  - 验收标准数: {N 条}
```

**Gate 1 检查：以上 3 项输出都填写后才继续。如果直接跳到 Gate 2，回来补。**

---

### Gate 2: 判断情况并裁决

根据 Gate 1 收集的事实，对照下表确定情况和唯一合法的状态流转：

```
情况 A: workpad 存在 + PR 存在 + CI pass
  → 这是标准审查。进入 Gate 3 审查设计意图。

情况 B: workpad 存在 + PR 存在 + CI fail
  → 不审查。移到 Rework，附评论 "CI failing, fix before re-review"。

情况 C: workpad 存在 + 无 PR
  → 读 workpad Blockers 节。如果有 blocker → 帮助解决后移到 In Progress。
  → 如果无 blocker → 这是异常，移到 In Progress 让 Codex 继续。

情况 D: 无 workpad + PR 存在
  → Harness 异常（Codex 跳过了 workpad）。记录到失败台账。
  → 仍然审查 PR diff，裁决后移到 Merging 或 Rework。

情况 E: 无 workpad + 无 PR
  → Codex 还没开始工作。移到 In Progress（不是 Todo）。
  → 如果 issue 从未被 Codex 领取过（状态直接从创建跳到 Human Review），
    移到 Todo 是唯一允许的例外——但必须在输出中注明原因。
```

输出：
```
  - 情况: A / B / C / D / E
  - 合法流转: → Merging / → Rework / → In Progress / → Todo(仅情况E且未领取)
```

**合法状态流转速查（从 Human Review 出发）：**
- → **Merging**：审查通过，PR可合并
- → **Rework**：审查不通过或CI失败，需要Codex修改
- → **In Progress**：Codex工作未完成，需继续
- → **Todo**：仅当 issue 从未被 Codex 领取过（情况 E 特例）

---

### Gate 3: 审查设计意图（仅情况 A）

快速浏览 PR diff（`gh pr diff`），对照 exec-plan 的验收标准，回答：

1. 变更范围是否在 exec-plan 指定范围内？（有无越界修改）
2. 验收标准是否全部满足？（逐条对照）
3. 有无架构偏离？（违反 AGENTS.md 约束）

输出：
```
  - 范围合规: yes / no (越界: {文件列表})
  - 验收标准: {满足数}/{总数}
  - 架构偏离: none / {描述}
  - 裁决: APPROVE → Merging / REJECT → Rework
  - 原因: {一句话}
```

**裁决执行：**
- APPROVE: `gh pr review --approve` + 移 issue 到 Merging
- REJECT: PR 上留评论（指出哪条验收标准未满足或哪里架构偏离）+ 移 issue 到 Rework

---

### Gate 4: Harness 改进（每个 issue 都做）

不管裁决通过还是不通过，回答：

```
  - 发现可工程化的改进: yes / no
  - 改进内容: {描述} 或 "无"
  - 行动: {已加 linter 规则 / 已更新 AGENTS.md / 记录到失败台账 / 无需行动}
```

如果有改进，当场执行（修改文件）或记录到 `docs/operations/agent-failure-log.md`。

Codex workpad 的 `### Confusions` 节是改进 Harness 的重要信号——即使 review 通过也要看。

---

## 完整输出格式（每个 issue 一份）

```
========== BUB-xxx: {title} ==========

[Gate 1: 事实收集]
  - workpad 存在: ...
  - Risk Assessment: ...
  - Plan 完成度: ...
  - Acceptance Criteria: ...
  - Validation: ...
  - Cross-Review: ...
  - Blockers: ...
  - Confusions: ...
  - PR 存在: ...
  - CI 状态: ...
  - exec-plan 存在: ...
  - 验收标准数: ...

[Gate 2: 情况判断]
  - 情况: ...
  - 合法流转: ...

[Gate 3: 设计意图审查]  (仅情况 A)
  - 范围合规: ...
  - 验收标准: ...
  - 架构偏离: ...
  - 裁决: ...
  - 原因: ...

[Gate 4: Harness 改进]
  - 发现可工程化的改进: ...
  - 改进内容: ...
  - 行动: ...

→ 状态流转: Human Review → {Merging / Rework / In Progress}
==========================================
```

处理完所有 issue 后，输出汇总表：

```
--- Human Review 完成 ---
| Issue | 情况 | 裁决 | 流转 | Harness 改进 |
```
