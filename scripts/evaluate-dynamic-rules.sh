#!/bin/bash
# UserPromptSubmit hook: evaluate which dynamic rules are relevant
# Delegates to eval-rules-core.sh for catalog building, LLM evaluation,
# and result parsing. This script handles stdin parsing, early exits,
# short-prompt skip, and rule injection formatting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="/tmp/flow-rule-cache"

# --- Stdin timeout guard ---
if [ -t 0 ]; then
  INPUT=""
else
  INPUT=$(cat 2>/dev/null) || INPUT=""
fi

if [ -z "$INPUT" ]; then
  echo '{}'
  exit 0
fi

# --- Parse input JSON ---
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)

if [ -z "$CWD" ]; then
  echo '{}'
  exit 0
fi

OPTIONAL_DIR="${CWD}/.flow/rules/dynamic"
if [ ! -d "$OPTIONAL_DIR" ]; then
  echo '{}'
  exit 0
fi

# --- Skip short prompts if we already have a selection ---
PREV_FILE="${CACHE_DIR}/last-selection-${SESSION_ID:-default}.json"
PROMPT_LEN=${#PROMPT}

if [ "$PROMPT_LEN" -lt 30 ] && [ -f "$PREV_FILE" ]; then
  # Short follow-up (yes, commit, /rewind, etc.) and we already evaluated — skip
  echo '{}'
  exit 0
fi

# --- Call shared evaluation core ---
CORE_ARGS=(--cwd "$CWD" --session-id "${SESSION_ID:-default}")
if [ -n "$TRANSCRIPT" ]; then
  CORE_ARGS+=(--transcript "$TRANSCRIPT")
fi
if [ -n "$PROMPT" ]; then
  CORE_ARGS+=(--prompt "$PROMPT")
fi

SELECTED_FILES=$("$SCRIPT_DIR/eval-rules-core.sh" "${CORE_ARGS[@]}" 2>/dev/null || true)

if [ -z "$SELECTED_FILES" ]; then
  echo '{}'
  exit 0
fi

# --- Reset tool counter for periodic-rule-eval debounce ---
mkdir -p "$CACHE_DIR" 2>/dev/null || true
echo "0" > "${CACHE_DIR}/tool-counter-${SESSION_ID:-default}.txt" 2>/dev/null || true

# --- Load selected rules ---
MATCHED_RULES=""
while IFS= read -r rule_id; do
  [ -z "$rule_id" ] && continue
  rule_path="${OPTIONAL_DIR}/${rule_id}"
  if [ -f "$rule_path" ]; then
    CONTENT=$(cat "$rule_path" 2>/dev/null || true)
    if [ -n "$CONTENT" ]; then
      MATCHED_RULES="${MATCHED_RULES}--- Dynamic Rule [${rule_id}] (auto-selected) ---
${CONTENT}

"
    fi
  fi
done <<< "$SELECTED_FILES"

if [ -z "$MATCHED_RULES" ]; then
  echo '{}'
  exit 0
fi

# Add instruction header
MATCHED_RULES="# Dynamic Rules (auto-selected for this task)
These rules were loaded because they are relevant to your current task context.
Follow them. Adjust your approach where needed.
If you already have a plan, re-evaluate it against these rules and adjust where needed.
When encountering ambiguity that cannot be resolved by reading the codebase, raise it before proceeding.

${MATCHED_RULES}"
MATCHED_RULES=$(echo "$MATCHED_RULES" | sed '/^$/N;/^\n$/d')

jq -n --arg ctx "$MATCHED_RULES" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'

exit 0
