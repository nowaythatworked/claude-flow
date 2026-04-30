#!/bin/bash
# UserPromptSubmit hook: inject phase-appropriate reminders.
# Reads .flow/SESSIONS.json for the current session's phase and focus.
# Pure bash + jq — no LLM calls.

set -euo pipefail

# Skip when invoked from a nested claude -p (e.g. async eval kickoff).
[ "${FLOW_NO_HOOKS:-}" = "1" ] && exit 0

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
if ! command -v jq &>/dev/null; then
  echo '{}'
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)

if [ -z "$CWD" ] || [ -z "$SESSION_ID" ]; then
  echo '{}'
  exit 0
fi

# Flag /flow: commands — they skip phase reminders but still get sessionTitle
IS_FLOW_COMMAND=false
case "$PROMPT" in
  /flow:*) IS_FLOW_COMMAND=true ;;
esac

SESSIONS_FILE="${CWD}/.flow/SESSIONS.json"

if [ ! -f "$SESSIONS_FILE" ]; then
  echo '{}'
  exit 0
fi

# --- Look up this session ---
ENTRY=$(jq -r --arg id "$SESSION_ID" '.[$id] // empty' "$SESSIONS_FILE" 2>/dev/null || true)

if [ -z "$ENTRY" ] || [ "$ENTRY" = "null" ]; then
  echo '{}'
  exit 0
fi

PHASE=$(echo "$ENTRY" | jq -r '.phase' 2>/dev/null || true)
FOCUS=$(echo "$ENTRY" | jq -r '.focus // [] | if length > 0 then join(", ") else "" end' 2>/dev/null || true)
TASK_FILE=$(echo "$ENTRY" | jq -r '.task_file // empty' 2>/dev/null || true)

SESSION_HINT="CURRENT_SESSION_ID=${SESSION_ID} — use in all session.sh commands."

# --- Build phase reminder ---
if [ "$IS_FLOW_COMMAND" = true ]; then
  CONTEXT="$SESSION_HINT"
  # For /flow: commands, still validate the phase exists
  case "$PHASE" in
    planning|planned|implementing) ;;
    *)
      echo '{}'
      exit 0
      ;;
  esac
else
  case "$PHASE" in
    planning)
      CONTEXT="${SESSION_HINT}
**Phase: planning.** Follow \`/flow:build\` § 1 (Understand), § 2 (Plan in conversation), § 3 (Explore impact), § 4 (Self-check & iterate). Before suggesting \`/flow:approve\`, you MUST run § 5 (Checkpoint before /flow:approve), every time, even if you ran it earlier in this conversation. If you can't recall a section, re-invoke \`/flow:build\` or Read \`\${CLAUDE_PLUGIN_ROOT}/skills/build/SKILL.md\`."
      ;;
    planned)
      if [ -n "$FOCUS" ]; then
        CONTEXT="${SESSION_HINT}
**Phase: planned | Focus: ${FOCUS}.** Follow \`/flow:next\` § 5 (Deep-dive process), § 6 (Self-check & iterate). Before suggesting \`/flow:implement\`, you MUST run § 7 (Checkpoint before /flow:implement), every time. If you can't recall a section, re-invoke \`/flow:next\` or Read \`\${CLAUDE_PLUGIN_ROOT}/skills/next/SKILL.md\`."
      else
        CONTEXT="${SESSION_HINT}
**Phase: planned.** Follow \`/flow:next\` § 1 (Orient & lock), § 2 (Analyze), § 3 (Suggest), § 4 (Set focus). After picking focus, proceed to § 5 (Deep-dive process). If you can't recall a section, re-invoke \`/flow:next\` or Read \`\${CLAUDE_PLUGIN_ROOT}/skills/next/SKILL.md\`."
      fi
      ;;
    implementing)
      CONTEXT="${SESSION_HINT}
**Phase: implementing.** Follow \`/flow:implement\` § Implementation rules and § 1 (Validate), § 2 (Transition), § 3 (Create granular tasks), § 4 (Execute), § 5 (Document), § 6 (Suggest next). When done, suggest \`/flow:next\`. If you can't recall a section, re-invoke \`/flow:implement\` or Read \`\${CLAUDE_PLUGIN_ROOT}/skills/implement/SKILL.md\`."
      ;;
    *)
      echo '{}'
      exit 0
      ;;
  esac
fi

# --- Build session title ---
# Derive from task filename + focus so it updates as work progresses
SESSION_TITLE=""
if [ -n "$TASK_FILE" ]; then
  TASK_SLUG="${TASK_FILE%.md}"
  if [ -n "$FOCUS" ]; then
    SESSION_TITLE="flow: ${TASK_SLUG} | ${FOCUS}"
  else
    SESSION_TITLE="flow: ${TASK_SLUG}"
  fi
fi

# --- Output ---
if [ -n "$CONTEXT" ] && [ -n "$SESSION_TITLE" ]; then
  jq -n --arg ctx "$CONTEXT" --arg title "$SESSION_TITLE" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $ctx,
      sessionTitle: $title
    }
  }'
elif [ -n "$CONTEXT" ]; then
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $ctx
    }
  }'
elif [ -n "$SESSION_TITLE" ]; then
  jq -n --arg title "$SESSION_TITLE" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      sessionTitle: $title
    }
  }'
else
  echo '{}'
fi

exit 0
