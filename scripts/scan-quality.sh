#!/bin/bash
# PostToolUse hook for Write|Edit: scan written content for quality violations
# Lightweight grep-based scanning — no LLM calls.

set -euo pipefail

# --- Stdin timeout guard (3 seconds) ---
INPUT=""
if read -t 3 -r INPUT; then
  while IFS= read -t 1 -r line; do
    INPUT="${INPUT}${line}"
  done
fi

if [ -z "$INPUT" ]; then
  echo '{}'
  exit 0
fi

# --- Parse input JSON ---
# Extract file_path and content from tool_input
if command -v jq &>/dev/null; then
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || true)
  # For Edit tool, also check new_string
  if [ -z "$CONTENT" ]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || true)
  fi
else
  TOOL_NAME=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  CONTENT=""
fi

# Only scan TypeScript/JavaScript files
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.mts|*.cts) ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

if [ -z "$CONTENT" ]; then
  # If we couldn't get content from JSON, try reading the file directly
  if [ -f "$FILE_PATH" ]; then
    CONTENT=$(cat "$FILE_PATH" 2>/dev/null || true)
  fi
fi

if [ -z "$CONTENT" ]; then
  echo '{}'
  exit 0
fi

# --- Scan for violations ---
VIOLATIONS=""
VIOLATION_COUNT=0

# Helper: scan content line-by-line, skip comments and strings for some checks
# We use a simple approach: grep with line numbers, then filter obvious false positives.

# 1. `any` type usage (: any, <any>, as any — but not in comments or string literals)
#    Match patterns like ": any", ": any;", ": any)", "<any>", "any[]"
ANY_HITS=$(echo "$CONTENT" | grep -n -E ':\s*any\b|<any>|any\[\]' 2>/dev/null | grep -v -E '^\s*//' | grep -v -E '^\s*\*' | grep -v -E "//.*:\s*any" || true)
if [ -n "$ANY_HITS" ]; then
  COUNT=$(echo "$ANY_HITS" | wc -l | tr -d ' ')
  VIOLATIONS="${VIOLATIONS}- **\`any\` type usage** (${COUNT} occurrence(s)):
$(echo "$ANY_HITS" | head -5 | sed 's/^/  line /')
"
  VIOLATION_COUNT=$((VIOLATION_COUNT + COUNT))
fi

# 2. `as unknown` assertions
AS_UNKNOWN_HITS=$(echo "$CONTENT" | grep -n -E '\bas\s+unknown\b' 2>/dev/null | grep -v -E '^\s*//' || true)
if [ -n "$AS_UNKNOWN_HITS" ]; then
  COUNT=$(echo "$AS_UNKNOWN_HITS" | wc -l | tr -d ' ')
  VIOLATIONS="${VIOLATIONS}- **\`as unknown\` assertion** (${COUNT} occurrence(s)):
$(echo "$AS_UNKNOWN_HITS" | head -5 | sed 's/^/  line /')
"
  VIOLATION_COUNT=$((VIOLATION_COUNT + COUNT))
fi

# 3. `as any` assertions
AS_ANY_HITS=$(echo "$CONTENT" | grep -n -E '\bas\s+any\b' 2>/dev/null | grep -v -E '^\s*//' || true)
if [ -n "$AS_ANY_HITS" ]; then
  COUNT=$(echo "$AS_ANY_HITS" | wc -l | tr -d ' ')
  VIOLATIONS="${VIOLATIONS}- **\`as any\` assertion** (${COUNT} occurrence(s)):
$(echo "$AS_ANY_HITS" | head -5 | sed 's/^/  line /')
"
  VIOLATION_COUNT=$((VIOLATION_COUNT + COUNT))
fi

# 4. Record<string, unknown> as lazy typing
RECORD_HITS=$(echo "$CONTENT" | grep -n -E 'Record<string,\s*unknown>' 2>/dev/null | grep -v -E '^\s*//' || true)
if [ -n "$RECORD_HITS" ]; then
  COUNT=$(echo "$RECORD_HITS" | wc -l | tr -d ' ')
  VIOLATIONS="${VIOLATIONS}- **\`Record<string, unknown>\` lazy typing** (${COUNT} occurrence(s)):
$(echo "$RECORD_HITS" | head -5 | sed 's/^/  line /')
"
  VIOLATION_COUNT=$((VIOLATION_COUNT + COUNT))
fi

# 5. @ts-ignore or @ts-expect-error without explanation
#    Match lines that have the directive but nothing meaningful after it
TS_IGNORE_HITS=$(echo "$CONTENT" | grep -n -E '//\s*@ts-(ignore|expect-error)\s*$' 2>/dev/null || true)
if [ -n "$TS_IGNORE_HITS" ]; then
  COUNT=$(echo "$TS_IGNORE_HITS" | wc -l | tr -d ' ')
  VIOLATIONS="${VIOLATIONS}- **\`@ts-ignore\`/\`@ts-expect-error\` without explanation** (${COUNT} occurrence(s)):
$(echo "$TS_IGNORE_HITS" | head -5 | sed 's/^/  line /')
"
  VIOLATION_COUNT=$((VIOLATION_COUNT + COUNT))
fi

# --- Output ---
if [ -z "$VIOLATIONS" ] || [ "$VIOLATION_COUNT" -eq 0 ]; then
  echo '{}'
  exit 0
fi

WARNING="Quality scan found ${VIOLATION_COUNT} violation(s) in \`${FILE_PATH}\`:

${VIOLATIONS}
Please fix these issues. Use proper types instead of \`any\`, avoid unsafe type assertions, and add explanations to type-error suppressions."

if command -v jq &>/dev/null; then
  jq -n --arg ctx "$WARNING" '{
    hookSpecificOutput: {
      additionalContext: $ctx
    }
  }'
else
  ESCAPED=$(printf '%s' "$WARNING" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$WARNING")
  echo "{\"hookSpecificOutput\":{\"additionalContext\":${ESCAPED}}}"
fi

exit 0
