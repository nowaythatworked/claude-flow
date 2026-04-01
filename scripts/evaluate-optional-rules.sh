#!/bin/bash
# UserPromptSubmit hook: evaluate which optional rules are relevant
# Uses claude -p (headless) with Haiku to analyze the prompt + transcript
# and select relevant optional rules.

set -euo pipefail

# --- Stdin timeout guard ---
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
if command -v jq &>/dev/null; then
  PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
else
  PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  TRANSCRIPT=""
fi

if [ -z "$CWD" ]; then
  echo '{}'
  exit 0
fi

OPTIONAL_DIR="${CWD}/.flow/rules/optional"
if [ ! -d "$OPTIONAL_DIR" ]; then
  echo '{}'
  exit 0
fi

# --- Skip short prompts if we already have a selection ---
CACHE_DIR="/tmp/flow-rule-cache"
SESSION_ID=""
if command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
fi
PREV_FILE="${CACHE_DIR}/last-selection-${SESSION_ID:-default}.json"
PROMPT_LEN=${#PROMPT}

if [ "$PROMPT_LEN" -lt 30 ] && [ -f "$PREV_FILE" ]; then
  # Short follow-up (yes, commit, /rewind, etc.) and we already evaluated — skip
  echo '{}'
  exit 0
fi

# --- Build rule catalog ---
RULE_CATALOG=""
for rule_file in "$OPTIONAL_DIR"/*.md; do
  [ -f "$rule_file" ] || continue
  RULE_ID=$(basename "$rule_file")
  # First 5 lines as summary (includes keywords if present)
  SUMMARY=$(head -5 "$rule_file" 2>/dev/null | tr '\n' ' ')
  RULE_CATALOG="${RULE_CATALOG}  - ${RULE_ID}: ${SUMMARY}\n"
done

if [ -z "$RULE_CATALOG" ]; then
  echo '{}'
  exit 0
fi

# --- Build context for evaluation ---
RECENT_CONTEXT=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  RECENT_CONTEXT=$(tail -50 "$TRANSCRIPT" 2>/dev/null | head -c 4000 || true)
fi

# --- Ask Haiku to evaluate ---
EVAL_PROMPT="You are a rule selector for a coding assistant. Given the user's prompt, working directory, and recent conversation context, select which optional quality rules are relevant.

Available rules:
$(echo -e "$RULE_CATALOG")

User prompt: ${PROMPT}
Working directory: ${CWD}
Recent context: ${RECENT_CONTEXT:-none}

Respond with ONLY a JSON array of relevant rule filenames. Example: [\"decode-pipeline.md\", \"ui-quality.md\"]
If no rules are relevant, respond with: []"

# Use claude CLI in headless mode with haiku for fast evaluation
SELECTED=$(echo "$EVAL_PROMPT" | claude -p --model sonnet --output-format json 2>/dev/null || echo "[]")

# Parse selection
if command -v jq &>/dev/null; then
  SELECTED_FILES=$(echo "$SELECTED" | jq -r '.[]' 2>/dev/null || true)
else
  SELECTED_FILES=$(echo "$SELECTED" | tr -d '[]"' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
fi

if [ -z "$SELECTED_FILES" ]; then
  echo '{}'
  exit 0
fi

# --- Load selected rules ---
MATCHED_RULES=""
while IFS= read -r rule_id; do
  [ -z "$rule_id" ] && continue
  rule_path="${OPTIONAL_DIR}/${rule_id}"
  if [ -f "$rule_path" ]; then
    CONTENT=$(cat "$rule_path" 2>/dev/null || true)
    if [ -n "$CONTENT" ]; then
      MATCHED_RULES="${MATCHED_RULES}--- Optional Rule [${rule_id}] (auto-selected) ---
${CONTENT}

"
    fi
  fi
done <<< "$SELECTED_FILES"

if [ -z "$MATCHED_RULES" ]; then
  echo '{}'
  exit 0
fi

# --- Write selection to cache for debounce comparison ---
CACHE_DIR="/tmp/flow-rule-cache"
mkdir -p "$CACHE_DIR" 2>/dev/null || true
echo "$SELECTED" > "${CACHE_DIR}/last-selection.json" 2>/dev/null || true
echo "0" > "${CACHE_DIR}/tool-counter.txt" 2>/dev/null || true

# Add instruction header
MATCHED_RULES="# Optional Rules (auto-selected for this task)
These rules were loaded because they are relevant to your current task context.
Follow them. Adjust your approach where needed.
If you already have a plan, re-evaluate it against these rules and adjust where needed.
When encountering ambiguity that cannot be resolved by reading the codebase, raise it before proceeding.

${MATCHED_RULES}"
MATCHED_RULES=$(echo "$MATCHED_RULES" | sed '/^$/N;/^\n$/d')

if command -v jq &>/dev/null; then
  jq -n --arg ctx "$MATCHED_RULES" '{
    hookSpecificOutput: {
      additionalContext: $ctx
    }
  }'
else
  ESCAPED=$(printf '%s' "$MATCHED_RULES" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$MATCHED_RULES")
  echo "{\"hookSpecificOutput\":{\"additionalContext\":${ESCAPED}}}"
fi

exit 0
