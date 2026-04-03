#!/bin/bash
# UserPromptSubmit hook: remind the agent to follow injected quality rules.
# Global — fires for all sessions, not just flow:build.
# Pure bash — no LLM calls.

set -euo pipefail

# --- Stdin guard ---
if [ -t 0 ]; then
  INPUT=""
else
  INPUT=$(cat 2>/dev/null) || INPUT=""
fi

if [ -z "$INPUT" ]; then
  echo '{}'
  exit 0
fi

# --- Parse input ---
if command -v jq &>/dev/null; then
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
else
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

if [ -z "$CWD" ]; then
  echo '{}'
  exit 0
fi

# --- Check if any rules exist ---
HAS_RULES=false
for dir in "$CWD/.flow/rules/always" "$CWD/.flow/rules/dynamic"; do
  if [ -d "$dir" ]; then
    for f in "$dir"/*.md; do
      [ -f "$f" ] && HAS_RULES=true && break 2
    done
  fi
done

if [ "$HAS_RULES" = false ]; then
  echo '{}'
  exit 0
fi

# --- Build reminder ---
CONTEXT='**Quality rules are active.** Rules have been injected into your context — look for `--- Rule [...] ---` and `--- Dynamic Rule [...] ---` blocks. Follow all of them. If you cannot find them or they have been lost to context compression, run `/flow:reload-rules` to re-read them.'

# --- Output ---
if command -v jq &>/dev/null; then
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $ctx
    }
  }'
else
  ESCAPED=$(printf '%s' "$CONTEXT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$CONTEXT")
  echo "{\"hookSpecificOutput\":{\"additionalContext\":${ESCAPED}}}"
fi

exit 0
