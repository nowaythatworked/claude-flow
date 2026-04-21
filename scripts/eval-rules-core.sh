#!/bin/bash
# Shared evaluation core for dynamic rule selection.
# Replaces duplicated logic in evaluate-dynamic-rules.sh and periodic-rule-eval.sh.
# Uses --json-schema for structured output instead of parsing freeform text.
#
# Usage:
#   eval-rules-core.sh --cwd <dir> --session-id <id> [--transcript <path>] [--prompt <text>]
#
# Stdout: selected rule filenames, one per line
# Exit codes: 0 = success (even if no rules selected), 1 = missing args/no rules dir

set -euo pipefail

# --- Parse arguments ---
CWD=""
SESSION_ID=""
TRANSCRIPT=""
PROMPT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd)
      CWD="$2"
      shift 2
      ;;
    --session-id)
      SESSION_ID="$2"
      shift 2
      ;;
    --transcript)
      TRANSCRIPT="$2"
      shift 2
      ;;
    --prompt)
      PROMPT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# --- Validate required args ---
if [ -z "$CWD" ]; then
  echo "Error: --cwd is required" >&2
  exit 1
fi

if [ -z "$SESSION_ID" ]; then
  echo "Error: --session-id is required" >&2
  exit 1
fi

# --- Check rules directory ---
DYNAMIC_DIR="${CWD}/.flow/rules/dynamic"
if [ ! -d "$DYNAMIC_DIR" ]; then
  exit 0
fi

# --- Build rule catalog from frontmatter ---
RULE_CATALOG=""
for rule_file in "$DYNAMIC_DIR"/*.md; do
  [ -f "$rule_file" ] || continue
  RULE_ID=$(basename "$rule_file")

  # Extract description from YAML frontmatter
  DESCRIPTION=""
  if head -1 "$rule_file" 2>/dev/null | grep -q '^---$'; then
    DESCRIPTION=$(awk '
      /^---$/ { count++; next }
      count == 1 && /^description:/ {
        sub(/^description:[[:space:]]*/, "")
        gsub(/^["'"'"']|["'"'"']$/, "")
        print
        exit
      }
      count >= 2 { exit }
    ' "$rule_file" 2>/dev/null || true)
  fi

  # Fallback: first 3 lines if no frontmatter description
  if [ -z "$DESCRIPTION" ]; then
    DESCRIPTION=$(head -3 "$rule_file" 2>/dev/null | tr '\n' ' ' || true)
  fi

  RULE_CATALOG="${RULE_CATALOG}  - ${RULE_ID}: ${DESCRIPTION}
"
done

if [ -z "$RULE_CATALOG" ]; then
  exit 0
fi

# --- Extract transcript context ---
CONTEXT=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  CONTEXT=$(python3 -c "
import sys, json

MAX_CHARS = 150_000
MSG_CAP = 10_000

messages = []
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        if d.get('type') == 'human':
            content = d.get('message', {}).get('content', '')
            if isinstance(content, list):
                texts = [p['text'][:MSG_CAP] for p in content
                         if isinstance(p, dict) and p.get('type') == 'text']
                if texts:
                    messages.append('USER: ' + '\n'.join(texts))
            elif isinstance(content, str):
                messages.append('USER: ' + content[:MSG_CAP])
        elif d.get('type') == 'assistant':
            content = d.get('message', {}).get('content', [])
            if isinstance(content, list):
                texts = [p['text'][:MSG_CAP] for p in content
                         if isinstance(p, dict) and p.get('type') == 'text']
                if texts:
                    messages.append('ASSISTANT: ' + '\n'.join(texts))
    except:
        pass

result = '\n\n'.join(messages)
if len(result) > MAX_CHARS:
    result = result[-MAX_CHARS:]
print(result)
" < "$TRANSCRIPT" 2>/dev/null || true)
fi

# Fall back to --prompt text if no transcript context
if [ -z "$CONTEXT" ] && [ -n "$PROMPT" ]; then
  CONTEXT="USER: ${PROMPT}"
fi

# --- JSON schema for structured output ---
SCHEMA='{
  "type": "object",
  "properties": {
    "task_type": {
      "type": "string",
      "description": "Brief classification of the work (e.g. ui-component, backend-api, infrastructure, data-pipeline)"
    },
    "selected": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "rule": { "type": "string", "description": "Filename of the selected rule" },
          "reason": { "type": "string", "description": "Why this rule is relevant" }
        },
        "required": ["rule", "reason"]
      }
    }
  },
  "required": ["task_type", "selected"]
}'

# --- Build prompt ---
EVAL_PROMPT="You are a rule selector for a coding assistant. Given the conversation context and working directory, select which dynamic quality rules are relevant to the current task.

Available rules:
${RULE_CATALOG}
Working directory: ${CWD}

Conversation context:
${CONTEXT:-none}

Select rules that are relevant. Be selective — only pick rules that directly apply to the type of work being done."

# --- Call model with structured output ---
RESPONSE=$(echo "$EVAL_PROMPT" | claude -p --model haiku --output-format json --no-session-persistence \
  --json-schema "$SCHEMA" \
  2>/dev/null || true)

# --- Parse structured output ---
SELECTED_JSON=""
if [ -n "$RESPONSE" ]; then
  SELECTED_JSON=$(echo "$RESPONSE" | jq '.structured_output // empty' 2>/dev/null || true)
fi

# Fallback: if structured_output is empty, try .result with markdown fence stripping
if [ -z "$SELECTED_JSON" ] || [ "$SELECTED_JSON" = "null" ]; then
  if [ -n "$RESPONSE" ]; then
    RAW_RESULT=$(echo "$RESPONSE" | jq -r '.result // empty' 2>/dev/null || true)
    if [ -n "$RAW_RESULT" ]; then
      # Strip markdown code fences (compatible with macOS and GNU sed)
      STRIPPED=$(echo "$RAW_RESULT" | grep -v '^```' || true)
      if [ -z "$STRIPPED" ]; then
        STRIPPED="$RAW_RESULT"
      fi
      # Try to parse as the expected schema
      SELECTED_JSON=$(echo "$STRIPPED" | jq '.' 2>/dev/null || true)
    fi
  fi
fi

if [ -z "$SELECTED_JSON" ] || [ "$SELECTED_JSON" = "null" ]; then
  exit 0
fi

# --- Write cache and debug log ---
CACHE_DIR="/tmp/flow-rule-cache"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# Cache: full structured output
CACHE_FILE="${CACHE_DIR}/last-selection-${SESSION_ID}.json"
echo "$SELECTED_JSON" > "$CACHE_FILE" 2>/dev/null || true

# Debug log: append one JSONL line
LOG_FILE="${CACHE_DIR}/eval-log-${SESSION_ID}.jsonl"
TASK_TYPE=$(echo "$SELECTED_JSON" | jq -r '.task_type // "unknown"' 2>/dev/null || echo "unknown")
SELECTED_ARRAY=$(echo "$SELECTED_JSON" | jq -c '[.selected[].rule]' 2>/dev/null || echo "[]")
PROMPT_SNIPPET=""
if [ -n "$CONTEXT" ]; then
  PROMPT_SNIPPET=$(echo "$CONTEXT" | head -c 200)
fi
LOG_ENTRY=$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg task_type "$TASK_TYPE" \
  --argjson selected "$SELECTED_ARRAY" \
  --arg prompt_snippet "$PROMPT_SNIPPET" \
  '{ts: $ts, task_type: $task_type, selected: $selected, prompt_snippet: $prompt_snippet}' \
  2>/dev/null || true)
if [ -n "$LOG_ENTRY" ]; then
  echo "$LOG_ENTRY" >> "$LOG_FILE" 2>/dev/null || true
fi

# --- Output selected rule filenames ---
echo "$SELECTED_JSON" | jq -r '.selected[].rule' 2>/dev/null || true

exit 0
