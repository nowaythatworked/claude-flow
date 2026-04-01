#!/bin/bash
# Stop hook: block first stop to force rule compliance check
# First stop → block, inject "verify compliance with all loaded rules"
# Second stop → allow (agent already verified)
# Uses a flag file to track state. Flag resets on each new user prompt via UserPromptSubmit.

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
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
else
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  SESSION_ID=""
fi

if [ -z "$CWD" ]; then
  echo '{}'
  exit 0
fi

# Only activate if flow rules exist in this project
if [ ! -d "${CWD}/.flow/rules/always" ]; then
  echo '{}'
  exit 0
fi

# Check if there are uncommitted changes (no changes = nothing to check)
HAS_CHANGES=$(cd "$CWD" && git diff --name-only 2>/dev/null | head -1 || true)
HAS_STAGED=$(cd "$CWD" && git diff --cached --name-only 2>/dev/null | head -1 || true)
if [ -z "$HAS_CHANGES" ] && [ -z "$HAS_STAGED" ]; then
  echo '{}'
  exit 0
fi

# --- Flag logic ---
FLAG_DIR="/tmp/flow-stop-check"
mkdir -p "$FLAG_DIR" 2>/dev/null || true
FLAG_FILE="${FLAG_DIR}/${SESSION_ID:-default}.checked"

if [ -f "$FLAG_FILE" ]; then
  # Second stop — already verified, allow it
  rm -f "$FLAG_FILE" 2>/dev/null || true
  echo '{}'
  exit 0
fi

# First stop — set flag and block
touch "$FLAG_FILE" 2>/dev/null || true

if command -v jq &>/dev/null; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "Stop",
      decision: "block",
      reason: "Before finishing: review your changes against ALL loaded quality rules (always-on and dynamic). Verify type safety, test coverage, DRY compliance, and scope. If everything is compliant, confirm and finish."
    }
  }'
else
  echo '{"hookSpecificOutput":{"hookEventName":"Stop","decision":"block","reason":"Before finishing: review your changes against ALL loaded quality rules (always-on and dynamic). Verify type safety, test coverage, DRY compliance, and scope. If everything is compliant, confirm and finish."}}'
fi

exit 0
