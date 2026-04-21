#!/bin/bash
# Tests for eval-rules-core.sh
# Run: ./tests/test-eval-rules-core.sh
# Exit code 0 = all passed, 1 = failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_DIR=$(mktemp -d)
MOCK_DIR=$(mktemp -d)

source "$(dirname "$0")/helpers.sh"

# --- Mock claude CLI ---
# Creates a mock that reads from MOCK_CLAUDE_RESPONSE_FILE
MOCK_CLAUDE="$MOCK_DIR/claude"
cat > "$MOCK_CLAUDE" << 'MOCK_EOF'
#!/bin/bash
# Mock claude: output predetermined response from file
if [ -n "${MOCK_CLAUDE_RESPONSE_FILE:-}" ] && [ -f "$MOCK_CLAUDE_RESPONSE_FILE" ]; then
  cat "$MOCK_CLAUDE_RESPONSE_FILE"
else
  echo '{}'
fi
MOCK_EOF
chmod +x "$MOCK_CLAUDE"

# Prepend mock dir to PATH so eval-rules-core.sh finds our mock
export PATH="$MOCK_DIR:$PATH"

# Override cache dir for test isolation
CACHE_DIR=$(mktemp -d)
export FLOW_TEST_CACHE_DIR="$CACHE_DIR"

# Helper: set up a rules directory with sample rules
setup_rules() {
  setup
  mkdir -p "$TEST_DIR/.flow/rules/dynamic"
  cat > "$TEST_DIR/.flow/rules/dynamic/design-system.md" << 'EOF'
---
description: "Rules for UI component development and design system usage"
---
# Design System Rules

Follow the design system tokens for all UI work.
EOF

  cat > "$TEST_DIR/.flow/rules/dynamic/react-components.md" << 'EOF'
---
description: "React component patterns and best practices"
---
# React Component Rules

Use functional components with hooks.
EOF

  cat > "$TEST_DIR/.flow/rules/dynamic/api-contracts.md" << 'EOF'
---
description: "API contract and schema validation rules"
---
# API Contract Rules

All API changes must update the OpenAPI spec.
EOF
}

# Helper: write mock claude response to a temp file
set_mock_response() {
  local response_file
  response_file=$(mktemp)
  echo "$1" > "$response_file"
  export MOCK_CLAUDE_RESPONSE_FILE="$response_file"
}

# ============================================================
echo "=== eval-rules-core.sh ==="
# ============================================================

# --- Test 1: No rules directory -> exit 0, empty stdout ---
echo "-- no rules directory -> exit 0, empty stdout --"
setup
RESULT=$("$SCRIPT_DIR/eval-rules-core.sh" --cwd "$TEST_DIR" --session-id "test1" 2>/dev/null || true)
assert_empty "no rules dir = empty stdout" "$RESULT"

# --- Test 2: Valid structured output -> correct filenames ---
echo "-- valid structured output -> correct filenames --"
setup_rules
set_mock_response '{"type":"result","result":"","structured_output":{"task_type":"ui","selected":[{"rule":"design-system.md","reason":"UI work detected"}]}}'
RESULT=$("$SCRIPT_DIR/eval-rules-core.sh" --cwd "$TEST_DIR" --session-id "test2" --prompt "build a modal component")
assert_contains "stdout has design-system.md" "design-system.md" "$RESULT"
assert_not_contains "stdout does NOT have api-contracts.md" "api-contracts.md" "$RESULT"

# --- Test 3: Empty selection -> exit 0, empty stdout ---
echo "-- empty selection -> exit 0, empty stdout --"
setup_rules
set_mock_response '{"type":"result","result":"","structured_output":{"task_type":"backend","selected":[]}}'
RESULT=$("$SCRIPT_DIR/eval-rules-core.sh" --cwd "$TEST_DIR" --session-id "test3" --prompt "update readme")
assert_empty "empty selection = empty stdout" "$RESULT"

# --- Test 4: Multiple rules selected -> all on stdout ---
echo "-- multiple rules selected -> all on stdout --"
setup_rules
set_mock_response '{"type":"result","result":"","structured_output":{"task_type":"fullstack","selected":[{"rule":"design-system.md","reason":"UI work"},{"rule":"react-components.md","reason":"React patterns"},{"rule":"api-contracts.md","reason":"API changes"}]}}'
RESULT=$("$SCRIPT_DIR/eval-rules-core.sh" --cwd "$TEST_DIR" --session-id "test4" --prompt "build a new feature page with API")
assert_contains "has design-system.md" "design-system.md" "$RESULT"
assert_contains "has react-components.md" "react-components.md" "$RESULT"
assert_contains "has api-contracts.md" "api-contracts.md" "$RESULT"
# Verify one per line
LINE_COUNT=$(echo "$RESULT" | wc -l | tr -d ' ')
assert_eq "three lines of output" "3" "$LINE_COUNT"

# --- Test 5: Cache file written with full structured output ---
echo "-- cache file written --"
setup_rules
set_mock_response '{"type":"result","result":"","structured_output":{"task_type":"ui","selected":[{"rule":"design-system.md","reason":"UI work"}]}}'
"$SCRIPT_DIR/eval-rules-core.sh" --cwd "$TEST_DIR" --session-id "test5" --prompt "style the button" >/dev/null
CACHE_FILE="/tmp/flow-rule-cache/last-selection-test5.json"
assert_file_exists "cache file exists" "$CACHE_FILE"
CACHE_TASK=$(jq -r '.task_type' "$CACHE_FILE" 2>/dev/null || echo "")
assert_eq "cache has task_type" "ui" "$CACHE_TASK"
CACHE_RULE=$(jq -r '.selected[0].rule' "$CACHE_FILE" 2>/dev/null || echo "")
assert_eq "cache has selected rule" "design-system.md" "$CACHE_RULE"
CACHE_REASON=$(jq -r '.selected[0].reason' "$CACHE_FILE" 2>/dev/null || echo "")
assert_eq "cache has reason" "UI work" "$CACHE_REASON"

# --- Test 6: Debug log appended ---
echo "-- debug log appended --"
setup_rules
set_mock_response '{"type":"result","result":"","structured_output":{"task_type":"infra","selected":[{"rule":"api-contracts.md","reason":"API changes"}]}}'
"$SCRIPT_DIR/eval-rules-core.sh" --cwd "$TEST_DIR" --session-id "test6" --prompt "deploy to staging" >/dev/null
LOG_FILE="/tmp/flow-rule-cache/eval-log-test6.jsonl"
assert_file_exists "log file exists" "$LOG_FILE"
LOG_TASK=$(tail -1 "$LOG_FILE" | jq -r '.task_type' 2>/dev/null || echo "")
assert_eq "log has task_type" "infra" "$LOG_TASK"
LOG_SELECTED=$(tail -1 "$LOG_FILE" | jq -r '.selected[0]' 2>/dev/null || echo "")
assert_eq "log has selected rule" "api-contracts.md" "$LOG_SELECTED"
LOG_TS=$(tail -1 "$LOG_FILE" | jq -r '.ts' 2>/dev/null || echo "")
assert_not_empty "log has timestamp" "$LOG_TS"
LOG_SNIPPET=$(tail -1 "$LOG_FILE" | jq -r '.prompt_snippet' 2>/dev/null || echo "")
assert_not_empty "log has prompt_snippet" "$LOG_SNIPPET"

# Run again to verify appending (not overwriting)
"$SCRIPT_DIR/eval-rules-core.sh" --cwd "$TEST_DIR" --session-id "test6" --prompt "deploy again" >/dev/null
LOG_LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')
assert_eq "log has 2 lines after second eval" "2" "$LOG_LINES"

# --- Test 7: Missing --cwd -> exit 1 ---
echo "-- missing --cwd -> exit 1 --"
EXIT_CODE=0
"$SCRIPT_DIR/eval-rules-core.sh" --session-id "test7" 2>/dev/null || EXIT_CODE=$?
assert_eq "missing cwd = exit 1" "1" "$EXIT_CODE"

# --- Test 8: Transcript extraction ---
echo "-- transcript extraction (Python) --"
TRANSCRIPT_FILE=$(mktemp)
cat > "$TRANSCRIPT_FILE" << 'JSONL'
{"type":"human","message":{"content":"implement a login form"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I'll create a login form component."},{"type":"tool_use","id":"t1","name":"Write","input":{}}]}}
{"type":"human","message":{"content":[{"type":"text","text":"add validation"},{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Adding form validation now."}]}}
JSONL

# Test the Python extraction directly
EXTRACTED=$(python3 -c "
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
" < "$TRANSCRIPT_FILE")

assert_contains "extracts user text message" "implement a login form" "$EXTRACTED"
assert_contains "extracts assistant text" "login form component" "$EXTRACTED"
assert_contains "extracts second user text" "add validation" "$EXTRACTED"
assert_not_contains "skips tool_use blocks" "tool_use" "$EXTRACTED"
assert_not_contains "skips tool_result blocks" "tool_result" "$EXTRACTED"
assert_contains "labels user messages" "USER:" "$EXTRACTED"
assert_contains "labels assistant messages" "ASSISTANT:" "$EXTRACTED"
rm -f "$TRANSCRIPT_FILE"

# --- Test 9: Transcript passed through to core script ---
echo "-- transcript used as context --"
setup_rules
TRANSCRIPT_FILE=$(mktemp)
cat > "$TRANSCRIPT_FILE" << 'JSONL'
{"type":"human","message":{"content":"build a dashboard with charts"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Creating a dashboard component."}]}}
JSONL
set_mock_response '{"type":"result","result":"","structured_output":{"task_type":"ui","selected":[{"rule":"design-system.md","reason":"Dashboard UI"}]}}'
RESULT=$("$SCRIPT_DIR/eval-rules-core.sh" --cwd "$TEST_DIR" --session-id "test9" --transcript "$TRANSCRIPT_FILE")
assert_contains "transcript mode returns rules" "design-system.md" "$RESULT"
rm -f "$TRANSCRIPT_FILE"

# --- Test 10: Frontmatter description extraction ---
echo "-- frontmatter description extraction --"
setup
mkdir -p "$TEST_DIR/.flow/rules/dynamic"
cat > "$TEST_DIR/.flow/rules/dynamic/test-rule.md" << 'EOF'
---
description: "Custom description for testing"
---
# Test Rule
Some content.
EOF

# Verify the catalog building by running the script (it will fail at claude call, but we can check catalog)
# Instead, test the awk extraction directly
DESCRIPTION=$(awk '
  /^---$/ { count++; next }
  count == 1 && /^description:/ {
    sub(/^description:[[:space:]]*/, "")
    gsub(/^["'"'"']|["'"'"']$/, "")
    print
    exit
  }
  count >= 2 { exit }
' "$TEST_DIR/.flow/rules/dynamic/test-rule.md" 2>/dev/null || true)
assert_eq "frontmatter description extracted" "Custom description for testing" "$DESCRIPTION"

# Test without frontmatter — fallback to first 3 lines
cat > "$TEST_DIR/.flow/rules/dynamic/no-frontmatter.md" << 'EOF'
# No Frontmatter Rule
This rule has no YAML frontmatter.
It should use first 3 lines as description.
Fourth line ignored.
EOF

DESCRIPTION=$(head -1 "$TEST_DIR/.flow/rules/dynamic/no-frontmatter.md" 2>/dev/null)
FIRST_LINE_CHECK=""
if echo "$DESCRIPTION" | grep -q '^---$'; then
  FIRST_LINE_CHECK="has frontmatter"
else
  FIRST_LINE_CHECK="no frontmatter"
fi
assert_eq "no-frontmatter file detected" "no frontmatter" "$FIRST_LINE_CHECK"

# --- Test 11: Missing --session-id -> exit 1 ---
echo "-- missing --session-id -> exit 1 --"
EXIT_CODE=0
"$SCRIPT_DIR/eval-rules-core.sh" --cwd "$TEST_DIR" 2>/dev/null || EXIT_CODE=$?
assert_eq "missing session-id = exit 1" "1" "$EXIT_CODE"

# ============================================================
# Cleanup
# ============================================================
rm -rf "$TEST_DIR" "$MOCK_DIR"
# Clean up test cache files
rm -f /tmp/flow-rule-cache/last-selection-test*.json
rm -f /tmp/flow-rule-cache/eval-log-test*.jsonl

report
