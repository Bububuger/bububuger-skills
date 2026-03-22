#!/bin/bash
# Extract clean review findings from claude -p output.
# Usage: extract-review.sh <raw-output-file> [clean-output-file]
#
# Strategy (same as codex-review-claude, adapted for Claude CLI output):
#   1. Try boundary markers <<<REVIEW_BEGIN/END>>>
#   2. Fallback: find last structured review block (P0/P1/P2 section)
#   3. Last resort: return full output (Claude CLI output is cleaner than codex exec)

set -euo pipefail

RAW="${1:?usage: extract-review.sh <raw-file> [output-file]}"
OUT="${2:-/tmp/claude-review-result.md}"

if [ ! -f "$RAW" ]; then
  echo "error: $RAW not found" >&2
  exit 1
fi

# Strategy 1: boundary markers
MARKED=$(sed -n '/<<<REVIEW_BEGIN>>>/,/<<<REVIEW_END>>>/p' "$RAW" \
  | grep -v '<<<REVIEW_' 2>/dev/null || true)

if [ -n "$MARKED" ] && [ "$(echo "$MARKED" | wc -l)" -gt 3 ]; then
  echo "$MARKED" > "$OUT"
  echo "extract=boundary lines=$(echo "$MARKED" | wc -l | tr -d ' ')" >&2
  exit 0
fi

# Strategy 2: find last structured P0/P1/P2 block
BLOCK=$(python3 -c "
import sys
with open('$RAW') as f:
    lines = f.readlines()

# Find last structured review start
last_start = -1
for i, line in enumerate(lines):
    stripped = line.strip()
    if any(k in stripped for k in ['### 上轮问题验证', '**P0**', 'P0:', 'NO_P0',
                                    '## P0', '## 问题', '### 新发现问题']):
        last_start = i

if last_start == -1:
    for i in range(len(lines)-1, -1, -1):
        stripped = lines[i].strip()
        if ('P0' in stripped or 'P1' in stripped) and \
           (':' in stripped or '：' in stripped or '阻塞' in stripped):
            last_start = max(0, i - 2)
            break

if last_start == -1:
    sys.exit(1)

# Collect from last_start
result = [line.rstrip() for line in lines[last_start:]]
print('\n'.join(result))
" 2>/dev/null || true)

if [ -n "$BLOCK" ] && [ "$(echo "$BLOCK" | wc -l)" -gt 3 ]; then
  echo "$BLOCK" > "$OUT"
  echo "extract=structured lines=$(echo "$BLOCK" | wc -l | tr -d ' ')" >&2
  exit 0
fi

# Strategy 3: Claude CLI output is relatively clean, return as-is
# Just strip any ANSI escape sequences
sed 's/\x1b\[[0-9;]*m//g' "$RAW" > "$OUT"
LINES=$(wc -l < "$OUT" | tr -d ' ')
echo "extract=fulltext lines=$LINES" >&2
