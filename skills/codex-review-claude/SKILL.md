---
name: codex-review-claude
description: 跨模型协作流水线：Claude 撰写（设计文档/代码），Codex(GPT-5.4) 全面审查，写→审→改循环最多3轮。当用户需要撰写技术方案、设计文档、代码实现，或提到跨模型审查、双模型、cross-review、代码评审时触发。即使用户只说"帮我写个方案"或"实现这个功能"，如果任务复杂度值得交叉审查，也应考虑使用本技能。
---

# Cross-Model Review

你是跨模型协作的执行者。你（Claude）负责撰写，Codex（GPT-5.4）负责审查，形成"写→审→改"闭环。

不同模型有不同的知识盲区和推理偏好，交叉审查能暴露单一模型无法发现的问题——这是本技能存在的核心理由。

## 输入

`/cross-review [mode] [requirement]`

- **mode**（可选）：`doc` / `code` / `full`（默认）
  - `doc`：仅生成并审查设计文档
  - `code`：仅编写并审查代码
  - `full`：先设计文档，通过后再编写代码，两阶段各自独立审查
- **requirement**：需求文本，或文件路径（自动读取内容）

未指定 mode 时，根据需求性质判断：纯设计用 `doc`，纯实现用 `code`，否则 `full`。

## 结果提取约定

Codex 输出夹杂大量 OTEL error、exec 日志、plan 输出。为可靠提取审查结论：

**1. Prompt 中追加边界标记指令**（所有非 `review` 的 codex exec prompt 末尾加）：
```
请在你的最终审查结论前输出一行 <<<REVIEW_BEGIN>>>，结论结束后输出一行 <<<REVIEW_END>>>。
边界标记之间只放结构化审查结论，不放思考过程。
```

**2. 执行完成后用提取脚本**（三级 fallback：边界标记 → 结构化块匹配 → 全文去噪）：
```bash
bash {skill_dir}/scripts/extract-review.sh /tmp/cross-review-raw.md /tmp/cross-review-result.md
```
其中 `{skill_dir}` 为本 skill 目录路径（`~/.claude/skills/cross-model-review`）。

脚本输出提取策略和行数到 stderr，便于判断质量：
- `extract=boundary lines=N` — 命中边界标记，最可靠
- `extract=structured lines=N` — 匹配到 P0/P1/P2 结构化块
- `extract=fallback lines=N` — 仅做了噪声过滤

**3. 完成检测**：等待 codex 进程退出（前台执行或 background task notification），不要用 grep 轮询 `NO_P0` 或 `tokens used` 等字符串——这些可能出现在中间输出中导致误判。

## Phase 1: 设计文档（doc / full）

1. 根据需求撰写技术设计文档，保存到当前目录（命名：`design-{topic}.md`）
2. 告知用户文档已生成，进入审查循环

### 审查循环（最多 3 轮）

维护两个状态变量：
- `review_history`：历轮审查结果的累积摘要
- `fix_summary`：本轮修改内容摘要

**第 1 轮 — 初始审查：**

```bash
cd {project_dir} && codex exec "你是资深技术架构师。请阅读文件 {doc_path}，全面评审：
1. 技术可行性 — 方案是否可落地
2. 架构合理性 — 模块划分、依赖关系
3. 边界条件与异常处理 — 失败场景覆盖
4. 安全性 — 潜在隐患
5. 可扩展性 — 未来演进空间
6. 逻辑完整性 — 遗漏或矛盾

按 P0(阻塞)/P1(重要)/P2(建议) 分级列出问题。
如果无 P0 问题，在末尾注明 NO_P0。

请在你的最终审查结论前输出一行 <<<REVIEW_BEGIN>>>，结论结束后输出一行 <<<REVIEW_END>>>。
边界标记之间只放结构化审查结论，不放思考过程。" \
  -s read-only --full-auto --ephemeral \
  2>&1 | tee /tmp/cross-review-raw.md
```

执行完后提取干净结果：
```bash
bash {skill_dir}/scripts/extract-review.sh /tmp/cross-review-raw.md /tmp/cross-review-result.md
```

**第 2/3 轮 — 带上下文的增量审查：**

```bash
cd {project_dir} && codex exec "你是资深技术架构师，正在进行第 {n} 轮审查。

## 上轮审查结果
{review_history}

## 本轮修改摘要
{fix_summary}

请阅读文件 {doc_path}，完成以下工作：
1. 验证上轮 P0/P1 问题是否已修复，逐条标注 [已修复] 或 [未修复]
2. 检查修改是否引入新问题
3. 对文档整体做增量评审

输出格式：
### 上轮问题验证
- [已修复/未修复] 问题描述

### 新发现问题
按 P0/P1/P2 分级列出。如果无新 P0，注明 NO_P0。

### 遗留问题汇总
仍未解决的问题列表。

请在你的最终审查结论前输出一行 <<<REVIEW_BEGIN>>>，结论结束后输出一行 <<<REVIEW_END>>>。
边界标记之间只放结构化审查结论，不放思考过程。" \
  -s read-only --full-auto --ephemeral \
  2>&1 | tee /tmp/cross-review-raw.md
```

同样执行上述 sed 提取。

**判断逻辑：**
- 无 P0（包含 NO_P0 标记） → **通过**，P1 列出供用户参考
- 有 P0 且轮次 < 3 → 修改文档，下一轮
- 第 3 轮仍有 P0 → **中断，交给用户处理**
- **收敛检测**：如果 P0 数量较上轮不减反增，立即中断，说明修改方向有误，需要用户介入

**修改原则：**
- 只改被指出的问题，不借机重构未被质疑的部分
- 每次修改记录清晰的 fix_summary，便于下轮审查验证
- 避免大范围重写——小步修改更容易收敛

**每轮输出：**

```
--- 第 {n}/3 轮 · 文档审查 ---
审查方: Codex (GPT-5.4) | tokens: {N}
结果: P0:{x} P1:{x} P2:{x}
{上轮修复验证结果（第2轮起）}
{新发现问题列表}
修改: {fix_summary}
```

## Phase 衔接（full 模式）

full 模式下，Phase 1（文档）通过后，自动进入 Phase 2（代码）。不要等用户指示，直接：

1. 输出文档审查通过的汇总（每轮输出格式）
2. 告知用户"文档审查通过，进入代码实现阶段"
3. 根据已通过的设计文档编写代码
4. 代码写完后自动进入代码审查循环

将文档审查中发现的 P1 问题作为代码实现的参考（如有架构建议，在编码时采纳），但不需要再次审查文档。

## Phase 2: 代码实现（code / full）

1. full 模式：根据已通过的设计文档编写代码
2. code 模式：根据需求直接编写代码
3. 代码写完后进入审查循环

### 代码审查前置准备

代码写完后、调用 Codex 审查前，必须确保变更对 git 可见：

```bash
cd {project_dir} && git add -N .  # 将未跟踪文件注册到 index（不暂存内容）
```

这样 `codex exec review --uncommitted` 才能看到新文件的 diff。

### 审查循环（最多 3 轮）

**第 1 轮 — 初始审查：**

`codex exec review` 不支持 `-C` 参数，且 `-o` 可能不写入文件（结果在 stdout 中），需用管道捕获：

```bash
cd {project_dir} && codex exec review --uncommitted \
  --full-auto --ephemeral \
  2>&1 | tee /tmp/cross-review-raw.md
```

`review` 子命令不接受自定义 prompt，无法注入边界标记。用提取脚本（会自动 fallback 到结构化块匹配）：
```bash
bash {skill_dir}/scripts/extract-review.sh /tmp/cross-review-raw.md /tmp/cross-review-result.md
```

**第 2/3 轮 — 带上下文的增量审查：**

后续轮次不再使用 `codex exec review`（它不接受上下文），改用通用 `codex exec`：

```bash
cd {project_dir} && codex exec "你是资深代码审查者，正在进行第 {n} 轮代码审查。

## 上轮审查结果
{review_history}

## 本轮修改摘要
{fix_summary}

请执行 git diff 查看当前未提交的代码变更，完成：
1. 验证上轮问题是否已修复，逐条标注 [已修复] 或 [未修复]
2. 检查修改是否引入新问题
3. 整体代码质量评审（正确性、安全性、性能、可维护性）

输出格式：
### 上轮问题验证
- [已修复/未修复] 问题描述

### 新发现问题
按 P0/P1/P2 分级列出。如果无新 P0，注明 NO_P0。

### 遗留问题汇总
仍未解决的问题列表。

请在你的最终审查结论前输出一行 <<<REVIEW_BEGIN>>>，结论结束后输出一行 <<<REVIEW_END>>>。
边界标记之间只放结构化审查结论，不放思考过程。" \
  -s read-only --full-auto --ephemeral \
  2>&1 | tee /tmp/cross-review-raw.md
```

同样执行提取脚本：
```bash
bash {skill_dir}/scripts/extract-review.sh /tmp/cross-review-raw.md /tmp/cross-review-result.md
```

判断逻辑、修改原则、收敛检测同文档阶段。

## 完成输出

```
--- 跨模型审查完成 ---
模式: {doc/code/full}
文档: {n}/3 轮 · {通过/需介入}
代码: {n}/3 轮 · {通过/需介入}
总 tokens: {累计}
产物: {文件路径列表}
{P1 遗留问题列表（如有）}
```

## Token 统计

每次 codex exec 执行后，从输出中提取 `tokens used` 数值，累加并在每轮输出和最终汇总中展示。便于用户评估跨模型协作的成本。

## Codex CLI 注意事项

经实测验证的行为差异，编写审查命令时务必注意：

| 问题 | 说明 | 应对 |
|------|------|------|
| `-C` 不支持 | `codex exec review` 不接受 `-C` 参数 | 用 `cd {dir} &&` 前置切换目录 |
| `-o` 不可靠 | `codex exec review` 的 `-o` 可能写空文件 | 用 `2>&1 \| tee` 从 stdout 捕获 |
| 未跟踪文件不可见 | `--uncommitted` 只看 git tracked 文件的变更 | 审查前执行 `git add -N .` |
| review 无上下文能力 | `codex exec review` 不接受自定义 prompt 上下文 | 第 2 轮起改用 `codex exec` 通用模式 |
| stderr 噪音 | otel exporter 错误会混入输出 | 用边界标记 `<<<REVIEW_BEGIN/END>>>` 提取；fallback 用 grep 过滤 |
| 边界标记可能被忽略 | Codex 有时不输出请求的标记 | 检测提取结果是否为空，为空则 fallback 到全文过滤 |
| 完成检测 | grep 轮询 `NO_P0` 可能误匹配中间输出 | 等进程退出（前台执行或 background task notification） |

## 规则

1. **不跳过审查** — 即使你认为完美，也必须走 Codex。你的盲区正是审查的价值。
2. **小步修改** — 只修被指出的问题，不顺手重构。大改不收敛，小改稳收敛。
3. **3 轮硬限** — 超过 3 轮必须交用户，防止无限循环。
4. **收敛优先** — P0 不减反增时立即中断，方向错了越改越远。
5. **上下文传递** — 第 2 轮起必须传上轮结果和修改摘要，让 Codex 做增量审查。
6. **通过标准** — 无 P0 即通过。P1 列出供用户参考，不阻塞流程。
7. **过程透明** — 每轮结果、修改内容、token 消耗都展示给用户。
8. **错误处理** — 若 codex exec 失败，报告错误并询问用户是否重试。
9. **等进程退出再读结果** — 不要用 grep 轮询中间输出做完成判断，等 codex 进程结束后再提取。
