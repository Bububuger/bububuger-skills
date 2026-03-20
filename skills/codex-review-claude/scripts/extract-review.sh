#!/bin/bash
# Extract clean review findings from codex exec output.
# Usage: extract-review.sh <raw-output-file> [clean-output-file]
#
# Strategy:
#   1. Try boundary markers <<<REVIEW_BEGIN/END>>>
#   2. Fallback: find last structured review block (### 上轮问题验证 or P0/P1/P2 section)
#   3. Last resort: strip known noise patterns

set -euo pipefail

RAW="${1:?usage: extract-review.sh <raw-file> [output-file]}"
OUT="${2:-/tmp/cross-review-result.md}"

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
# Look for the last occurrence of review conclusion patterns
BLOCK=$(python3 -c "
import sys
with open('$RAW') as f:
    lines = f.readlines()

noise = {'opentelemetry_sdk', 'BatchSpanProcessor', 'ERROR opentelemetry',
         'exec\n', '/bin/zsh -lc', 'mcp startup', 'warning: Under-development'}

# Find last structured review start
last_start = -1
for i, line in enumerate(lines):
    stripped = line.strip()
    if any(k in stripped for k in ['### 上轮问题验证', '**P0**', 'P0:', 'NO_P0']):
        # Check it's not inside a codex prompt echo
        if i > 30:  # skip early prompt echo
            last_start = i

if last_start == -1:
    # Try finding last P0/P1 block
    for i in range(len(lines)-1, -1, -1):
        stripped = lines[i].strip()
        if ('P0' in stripped and ('阻塞' in stripped or ':' in stripped or '：' in stripped)) or \
           ('### 上轮问题验证' in stripped):
            last_start = max(0, i - 2)
            break

if last_start == -1:
    sys.exit(1)

# Collect from last_start, filtering noise
result = []
for line in lines[last_start:]:
    if any(n in line for n in noise):
        continue
    result.append(line.rstrip())

print('\n'.join(result))
" 2>/dev/null || true)

if [ -n "$BLOCK" ] && [ "$(echo "$BLOCK" | wc -l)" -gt 3 ]; then
  echo "$BLOCK" > "$OUT"
  echo "extract=structured lines=$(echo "$BLOCK" | wc -l | tr -d ' ')" >&2
  exit 0
fi

# Strategy 3: full noise strip
grep -v 'opentelemetry_sdk\|BatchSpanProcessor\|^exec$\|^codex$\|^Plan update\|^mcp startup\|^warning:\|/bin/zsh -lc\|succeeded in\|exited [0-9]' \
  "$RAW" > "$OUT" 2>/dev/null || true

LINES=$(wc -l < "$OUT" | tr -d ' ')
echo "extract=fallback lines=$LINES" >&2
