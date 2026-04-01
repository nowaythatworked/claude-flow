#!/bin/bash
# Stop hook: block first stop to force rule compliance check
# Uses stop_hook_active field (built-in) instead of flag files.
# First stop (stop_hook_active=false) → block
# Second stop (stop_hook_active=true) → allow

set -euo pipefail

if [ -t 0 ]; then
  INPUT=""
else
  INPUT=$(cat 2>/dev/null) || INPUT=""
fi

if [ -z "$INPUT" ]; then
  exit 0
fi

# Check if stop hook already blocked once — always allow second attempt
if command -v jq &>/dev/null; then
  ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
else
  ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active"[[:space:]]*:[[:space:]]*true' | head -1)
  [ -n "$ACTIVE" ] && ACTIVE="true" || ACTIVE="false"
fi

if [ "$ACTIVE" = "true" ]; then
  # Second stop — allow
  exit 0
fi

# First stop — block and request compliance check
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
