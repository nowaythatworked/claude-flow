#!/bin/bash
# UserPromptSubmit hook: evaluate which optional rules are relevant
# Uses deterministic keyword matching on prompt text and cwd path.
# Will be upgraded to Haiku prompt hook in the future.

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
if command -v jq &>/dev/null; then
  PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
else
  PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
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

# Lowercase prompt and cwd for case-insensitive matching
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
CWD_LOWER=$(echo "$CWD" | tr '[:upper:]' '[:lower:]')

# --- Generic keyword matching ---
# Each rule file can have a `keywords:` line in YAML-like frontmatter.
# Format: keywords: decode, extraction, pipeline
# If no keywords line, fall back to matching the filename against prompt/cwd.
MATCHED_RULES=""

for rule_file in "$OPTIONAL_DIR"/*.md; do
  [ -f "$rule_file" ] || continue
  RULE_NAME=$(basename "$rule_file")
  RULE_NAME_LOWER=$(echo "$RULE_NAME" | tr '[:upper:]' '[:lower:]' | tr '-' ' ')

  MATCH=false

  # Extract keywords from frontmatter (line starting with "keywords:")
  KEYWORDS_LINE=$(head -10 "$rule_file" | grep -i '^keywords:' | head -1 | sed 's/^keywords:[[:space:]]*//' || true)

  if [ -n "$KEYWORDS_LINE" ]; then
    # Split by comma, trim whitespace, check each keyword
    IFS=',' read -ra KW_ARRAY <<< "$KEYWORDS_LINE"
    for kw in "${KW_ARRAY[@]}"; do
      kw_trimmed=$(echo "$kw" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -n "$kw_trimmed" ] && echo "$PROMPT_LOWER $CWD_LOWER" | grep -q "$kw_trimmed"; then
        MATCH=true
        break
      fi
    done
  else
    # Fallback: match filename words against prompt/cwd
    for word in $RULE_NAME_LOWER; do
      if [ ${#word} -ge 3 ] && echo "$PROMPT_LOWER $CWD_LOWER" | grep -q "$word"; then
        MATCH=true
        break
      fi
    done
  fi

  if [ "$MATCH" = true ]; then
    CONTENT=$(cat "$rule_file" 2>/dev/null || true)
    if [ -n "$CONTENT" ]; then
      MATCHED_RULES="${MATCHED_RULES}--- Optional Rule [${RULE_NAME}] (auto-selected) ---
${CONTENT}

"
    fi
  fi
done

# --- Output ---
if [ -z "$MATCHED_RULES" ]; then
  echo '{}'
  exit 0
fi

# Add instruction header
MATCHED_RULES="# Optional Rules (auto-selected for this task)
These rules were loaded because they match your current task context.
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
