#!/bin/bash
# PostToolUse hook: periodically re-evaluate optional rules
# Debounced — only fires every N tool uses.
# When it fires, uses claude -p with Sonnet to re-evaluate which optional
# rules are relevant, reading the conversation transcript for full context.
# Only injects new rules if the selection changed.

set -euo pipefail

DEBOUNCE_INTERVAL=15
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

# --- Parse input ---
if command -v jq &>/dev/null; then
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
else
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  SESSION_ID=""
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

# --- Debounce ---
mkdir -p "$CACHE_DIR" 2>/dev/null || true
COUNTER_FILE="${CACHE_DIR}/tool-counter-${SESSION_ID:-default}.txt"

COUNTER=0
if [ -f "$COUNTER_FILE" ]; then
  COUNTER=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
fi
COUNTER=$((COUNTER + 1))
echo "$COUNTER" > "$COUNTER_FILE" 2>/dev/null || true

if [ $((COUNTER % DEBOUNCE_INTERVAL)) -ne 0 ]; then
  echo '{}'
  exit 0
fi

# --- Build rule catalog ---
RULE_CATALOG=""
for rule_file in "$OPTIONAL_DIR"/*.md; do
  [ -f "$rule_file" ] || continue
  RULE_ID=$(basename "$rule_file")
  SUMMARY=$(head -5 "$rule_file" 2>/dev/null | tr '\n' ' ')
  RULE_CATALOG="${RULE_CATALOG}  - ${RULE_ID}: ${SUMMARY}\n"
done

if [ -z "$RULE_CATALOG" ]; then
  echo '{}'
  exit 0
fi

# --- Extract recent conversation from transcript ---
RECENT_CONTEXT=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # Extract user messages and assistant text from last ~100 lines of JSONL
  RECENT_CONTEXT=$(tail -100 "$TRANSCRIPT" 2>/dev/null | \
    python3 -c "
import sys, json
lines = []
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        if d.get('type') == 'user':
            msg = d.get('message', {}).get('content', '')
            if isinstance(msg, list):
                for part in msg:
                    if isinstance(part, dict) and part.get('type') == 'text':
                        lines.append('USER: ' + part['text'][:200])
                    elif isinstance(part, str):
                        lines.append('USER: ' + part[:200])
            elif isinstance(msg, str):
                lines.append('USER: ' + msg[:200])
        elif d.get('type') == 'assistant':
            msg = d.get('message', {}).get('content', [])
            for part in msg if isinstance(msg, list) else []:
                if isinstance(part, dict) and part.get('type') == 'text':
                    lines.append('AGENT: ' + part['text'][:200])
    except: pass
# Last 20 exchanges max
for l in lines[-20:]:
    print(l)
" 2>/dev/null || true)
fi

# --- Previous selection ---
PREV_FILE="${CACHE_DIR}/last-selection-${SESSION_ID:-default}.json"
PREV_SELECTION=""
if [ -f "$PREV_FILE" ]; then
  PREV_SELECTION=$(cat "$PREV_FILE" 2>/dev/null || true)
fi

# --- Ask Sonnet to re-evaluate ---
EVAL_PROMPT="You are a rule selector for a coding assistant. Based on the conversation so far, determine which optional quality rules should be active.

Available rules:
$(echo -e "$RULE_CATALOG")

Previously selected: ${PREV_SELECTION:-none}
Working directory: ${CWD}

Recent conversation:
${RECENT_CONTEXT:-no transcript available}

Respond with ONLY a JSON array of relevant rule filenames. Example: [\"decode-pipeline.md\", \"ui-quality.md\"]
If no rules are relevant, respond with: []"

SELECTED=$(echo "$EVAL_PROMPT" | claude -p --model sonnet --output-format json 2>/dev/null | jq -r ".result // empty" 2>/dev/null || echo "[]")

# --- Check if selection changed ---
if [ "$SELECTED" = "$PREV_SELECTION" ]; then
  echo '{}'
  exit 0
fi

echo "$SELECTED" > "$PREV_FILE" 2>/dev/null || true

# --- Load selected rules ---
if command -v jq &>/dev/null; then
  SELECTED_FILES=$(echo "$SELECTED" | jq -r '.[]' 2>/dev/null || true)
else
  SELECTED_FILES=$(echo "$SELECTED" | tr -d '[]"' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
fi

if [ -z "$SELECTED_FILES" ]; then
  echo '{}'
  exit 0
fi

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

MATCHED_RULES="# Optional Rules Updated (periodic re-evaluation)
Rules were re-evaluated based on your recent activity.
Follow them. Adjust your approach where needed.
If you already have a plan, re-evaluate it against these rules and adjust where needed.
When encountering ambiguity that cannot be resolved by reading the codebase, raise it before proceeding.

${MATCHED_RULES}"
MATCHED_RULES=$(echo "$MATCHED_RULES" | sed '/^$/N;/^\n$/d')

if command -v jq &>/dev/null; then
  jq -n --arg ctx "$MATCHED_RULES" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }'
else
  ESCAPED=$(printf '%s' "$MATCHED_RULES" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$MATCHED_RULES")
  echo "{\"hookSpecificOutput\":{\"additionalContext\":${ESCAPED}}}"
fi

exit 0
