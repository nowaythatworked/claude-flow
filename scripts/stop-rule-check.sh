#!/bin/bash
# Stop hook: remind agent to verify rule compliance before finishing
# Only fires when there are loaded rules AND recent file changes.
# Lightweight — just checks if files were modified and injects a reminder.

set -euo pipefail

if [ -t 0 ]; then
  INPUT=""
else
  INPUT=$(cat 2>/dev/null) || INPUT=""
fi

if [ -z "$INPUT" ]; then
  echo '{}'
  exit 0
fi

if command -v jq &>/dev/null; then
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
else
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

if [ -z "$CWD" ]; then
  echo '{}'
  exit 0
fi

# Only inject if flow rules exist in this project
RULES_DIR="${CWD}/.flow/rules/always"
if [ ! -d "$RULES_DIR" ]; then
  echo '{}'
  exit 0
fi

# Check if there are uncommitted changes (indicates implementation happened)
HAS_CHANGES=$(cd "$CWD" && git diff --name-only HEAD 2>/dev/null | head -1 || true)
if [ -z "$HAS_CHANGES" ]; then
  echo '{}'
  exit 0
fi

CONTEXT="Before finishing: verify your changes comply with all loaded quality rules. Check for type safety, test coverage, DRY violations, and scope compliance."

if command -v jq &>/dev/null; then
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      hookEventName: "Stop",
      additionalContext: $ctx
    }
  }'
else
  ESCAPED=$(printf '%s' "$CONTEXT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$CONTEXT")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":${ESCAPED}}}"
fi

exit 0
