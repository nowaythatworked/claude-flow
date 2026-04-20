#!/bin/bash
# Tests for init.sh
# Run: ./tests/test-init.sh
# Exit code 0 = all passed, 1 = failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_DIR=$(mktemp -d)

source "$(dirname "$0")/helpers.sh"

export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ============================================================
echo "=== init.sh ==="
# ============================================================

echo "-- creates directory structure --"
setup
"$SCRIPT_DIR/init.sh" "$TEST_DIR" > /dev/null

[ -d "$TEST_DIR/.flow/rules/always" ]
assert_eq ".flow/rules/always/ exists" "yes" "$([ -d "$TEST_DIR/.flow/rules/always" ] && echo yes || echo no)"
assert_eq ".flow/rules/dynamic/ exists" "yes" "$([ -d "$TEST_DIR/.flow/rules/dynamic" ] && echo yes || echo no)"
assert_eq ".claude/agents/ exists" "yes" "$([ -d "$TEST_DIR/.claude/agents" ] && echo yes || echo no)"
assert_eq ".flow/archive/ exists" "yes" "$([ -d "$TEST_DIR/.flow/archive" ] && echo yes || echo no)"

echo "-- copies always-on rules --"
RULE_COUNT=$(ls "$TEST_DIR/.flow/rules/always/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "at least one rule copied" "yes" "$([ "$RULE_COUNT" -gt 0 ] && echo yes || echo no)"

echo "-- installs agents with substitution --"
AGENT_COUNT=$(ls "$TEST_DIR/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "at least one agent installed" "yes" "$([ "$AGENT_COUNT" -gt 0 ] && echo yes || echo no)"

# Verify __FLOW_PLUGIN_ROOT__ was substituted in all installed agents
for f in "$TEST_DIR/.claude/agents/"*.md; do
  [ -f "$f" ] || continue
  CONTENT=$(cat "$f")
  assert_not_contains "no placeholder in $(basename "$f")" "__FLOW_PLUGIN_ROOT__" "$CONTENT"
done

echo "-- idempotent: skips existing --"
OUTPUT=$("$SCRIPT_DIR/init.sh" "$TEST_DIR" 2>&1)
assert_contains "mentions already existed for rules" "already existed" "$OUTPUT"
assert_contains "mentions already exists for agents" "already exists" "$OUTPUT"
# Directories and files still present
assert_eq ".flow/rules/always/ still exists" "yes" "$([ -d "$TEST_DIR/.flow/rules/always" ] && echo yes || echo no)"
RULE_COUNT_AFTER=$(ls "$TEST_DIR/.flow/rules/always/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "rule count unchanged" "$RULE_COUNT" "$RULE_COUNT_AFTER"

echo "-- cleans stale state files --"
setup
# Create stale files before running init
mkdir -p "$TEST_DIR/.flow"
echo '{}' > "$TEST_DIR/.flow/SESSIONS.json"
echo 'planning' > "$TEST_DIR/.flow/PHASE"
"$SCRIPT_DIR/init.sh" "$TEST_DIR" > /dev/null
assert_file_not_exists "SESSIONS.json removed" "$TEST_DIR/.flow/SESSIONS.json"
assert_file_not_exists "PHASE removed" "$TEST_DIR/.flow/PHASE"

echo "-- missing CLAUDE_PLUGIN_ROOT errors --"
EXIT_CODE=0
(unset CLAUDE_PLUGIN_ROOT; "$SCRIPT_DIR/init.sh" "$TEST_DIR" 2>/dev/null) || EXIT_CODE=$?
assert_eq "exits with non-zero" "yes" "$([ "$EXIT_CODE" -ne 0 ] && echo yes || echo no)"

# ============================================================
# Cleanup & Report
# ============================================================
rm -rf "$TEST_DIR"

report
