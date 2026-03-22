---
name: claude-review-codex
description:
  Cross-model review gate for Codex-authored code. After implementation and
  local validation pass, invoke Claude (Opus) via local CLI to review the diff
  against AGENTS.md constraints and exec-plan acceptance criteria. Write→Review→Fix
  loop runs at most 3 rounds; P0-free exits with APPROVE, otherwise escalates to
  Human Review. Use this skill after self-review (Step 3a) passes but before
  approving the PR.
---

# Cross-Model Review (Claude reviews Codex)

Codex 完成开发 + 本地验证后，调用本地 Claude CLI 进行异构模型审查。
不同模型有不同的知识盲区，交叉审查能暴露自审无法发现的问题。

## 前置条件

- 代码已实现并通过本地验证（`npm run check && npm test`）
- 变更已 commit 到当前分支
- `claude` CLI 可用（`which claude` 应返回路径）
- `ANTHROPIC_API_KEY` 在环境变量中（`shell_environment_policy.inherit=all` 已配置）

## 调用时机

在 WORKFLOW.md Step 3a（auto-review）**自审通过后、approve 前**调用。

## 输入收集

调用前收集以下上下文：

```bash
# 1. diff（相对于 main）
DIFF_FILE=$(mktemp /tmp/cross-review-diff-XXXXXX.md)
git diff origin/main...HEAD > "$DIFF_FILE"

# 2. AGENTS.md 约束
AGENTS_FILE="AGENTS.md"

# 3. exec-plan（从 issue description 中解析路径，如有）
# EXEC_PLAN_FILE="docs/exec-plans/bub-xxx.md"
```

## 审查循环（最多 3 轮）

维护状态：
- `round`：当前轮次（1-3）
- `review_history`：历轮审查结果累积
- `fix_summary`：本轮修改摘要

### 第 1 轮 — 初始审查

```bash
REVIEW_RAW=$(mktemp /tmp/claude-review-raw-XXXXXX.md)
REVIEW_CLEAN=$(mktemp /tmp/claude-review-clean-XXXXXX.md)

claude -p "你是资深代码审查者（Claude Opus）。你正在审查另一个 AI Agent（Codex/GPT）的代码产出。

## 项目约束
$(cat "$AGENTS_FILE")

## 变更 Diff
$(cat "$DIFF_FILE")

请全面审查：
1. 正确性 — 逻辑是否正确，边界条件是否处理
2. 架构合规 — 是否遵守 AGENTS.md 中的约束（Contract-First、不可变设计、字段注册制、适配器隔离等）
3. 类型安全 — TypeScript strict 是否满足，any 是否泄露
4. 跨包边界 — 是否有 rootDir 违规的直接内部文件 import
5. 测试覆盖 — 新增逻辑是否有对应测试
6. 安全性 — 是否有密钥泄露、注入风险

按 P0(阻塞)/P1(重要)/P2(建议) 分级列出问题。
每个问题附具体文件路径和行号。
如果无 P0 问题，在末尾注明 NO_P0。

<<<REVIEW_BEGIN>>>
（在此标记之间输出结构化审查结论）
<<<REVIEW_END>>>" 2>&1 | tee "$REVIEW_RAW"

# 提取干净结果
bash "{skill_dir}/scripts/extract-review.sh" "$REVIEW_RAW" "$REVIEW_CLEAN"
```

读取 `$REVIEW_CLEAN` 判断结果。

### 第 2/3 轮 — 增量审查

```bash
claude -p "你是资深代码审查者（Claude Opus），正在进行第 {round} 轮审查。

## 上轮审查结果
{review_history}

## 本轮修改摘要
{fix_summary}

## 项目约束
$(cat "$AGENTS_FILE")

## 变更 Diff
$(git diff origin/main...HEAD)

请完成：
1. 验证上轮 P0/P1 问题是否已修复，逐条标注 [已修复] 或 [未修复]
2. 检查修改是否引入新问题
3. 整体增量评审

输出格式：
### 上轮问题验证
- [已修复/未修复] 问题描述

### 新发现问题
按 P0/P1/P2 分级。无新 P0 注明 NO_P0。

### 遗留问题汇总
仍未解决的问题列表。

<<<REVIEW_BEGIN>>>
<<<REVIEW_END>>>" 2>&1 | tee "$REVIEW_RAW"

bash "{skill_dir}/scripts/extract-review.sh" "$REVIEW_RAW" "$REVIEW_CLEAN"
```

## 判断逻辑

- **无 P0**（结果含 `NO_P0`） → **通过**，在 workpad 记录 P1 供参考
- **有 P0 且轮次 < 3** → 修复问题，commit，下一轮
- **第 3 轮仍有 P0** → 中断，移至 `Human Review`
- **收敛检测** → P0 数量较上轮不减反增，立即中断（方向有误）

## 修复原则

- 只改被指出的问题，不借机重构
- 每次修改后重跑本地验证（`npm run check && npm test`），确认不引入回归
- 记录 `fix_summary` 供下轮审查用

## 通过后动作

审查通过后：
1. 在 workpad `### Cross-Review` section 记录：
   ```
   - Reviewer: Claude Opus
   - Rounds: {n}/3
   - Result: APPROVED
   - P1 remaining: {列表或"无"}
   ```
2. 继续 WORKFLOW.md 的 approve → merge 流程

## 未通过（3轮后）动作

1. 在 workpad 记录审查未通过及遗留 P0
2. 移至 `Human Review`

## 每轮输出

```
--- 第 {n}/3 轮 · 跨模型审查 ---
审查方: Claude Opus (local CLI)
结果: P0:{x} P1:{x} P2:{x}
{上轮修复验证（第2轮起）}
{问题列表}
修改: {fix_summary}
```

## 规则

1. **自审通过才调用** — 本 skill 是自审之后的第二道门，不替代自审。
2. **本地执行** — 通过 `claude -p` 调用本地 CLI，API key 不离开机器。
3. **3 轮硬限** — 超过 3 轮交 Human Review，防止无限循环。
4. **收敛优先** — P0 不减反增时立即中断。
5. **小步修复** — 只改被指出的问题，不扩大范围。
6. **P0-free 即通过** — P1 列出供参考，不阻塞。
7. **等进程退出** — `claude -p` 是同步调用，等返回后再解析。

## Claude CLI 注意事项

| 问题 | 应对 |
|------|------|
| `claude -p` 输出可能含 ANSI escape | 管道到 `tee` 会自动去除 |
| diff 过大超 context | 只传改动文件的 diff，不传整个 repo |
| claude CLI 不存在 | `which claude` 检查，不存在则跳过 cross-review，走原有 auto-review |
| API 调用失败 | 重试 1 次，仍失败则跳过 cross-review 并在 workpad 注明 |
