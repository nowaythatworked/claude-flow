#!/bin/bash
# Tests for inject-session-rules.sh
# Run: ./tests/test-inject-rules.sh
# Exit code 0 = all passed, 1 = failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_DIR=$(mktemp -d)

source "$(dirname "$0")/helpers.sh"

# ============================================================
echo "=== inject-session-rules.sh ==="
# ============================================================

echo "-- no rules directory -> silent --"
setup
RESULT=$(echo '{"source":"startup","cwd":"'"$TEST_DIR"'"}' | "$SCRIPT_DIR/inject-session-rules.sh")
assert_json_empty "no rules dir = {}" "$RESULT"

echo "-- source startup with always-on rules --"
setup
mkdir -p "$TEST_DIR/.flow/rules/always"
printf "Always follow this rule" > "$TEST_DIR/.flow/rules/always/test-rule.md"
RESULT=$(echo '{"source":"startup","cwd":"'"$TEST_DIR"'"}' | "$SCRIPT_DIR/inject-session-rules.sh")
assert_contains "output has rule filename" "test-rule.md" "$RESULT"
assert_contains "output has rule content" "Always follow this rule" "$RESULT"

echo "-- source compact re-injects rules --"
RESULT=$(echo '{"source":"compact","cwd":"'"$TEST_DIR"'"}' | "$SCRIPT_DIR/inject-session-rules.sh")
assert_contains "compact has rule filename" "test-rule.md" "$RESULT"
assert_contains "compact has rule content" "Always follow this rule" "$RESULT"

echo "-- source resume -> silent --"
RESULT=$(echo '{"source":"resume","cwd":"'"$TEST_DIR"'"}' | "$SCRIPT_DIR/inject-session-rules.sh")
assert_json_empty "resume = {}" "$RESULT"

echo "-- dynamic rules listed --"
setup
mkdir -p "$TEST_DIR/.flow/rules/always"
mkdir -p "$TEST_DIR/.flow/rules/dynamic"
printf "Some always rule" > "$TEST_DIR/.flow/rules/always/base.md"
printf "Dynamic rule content" > "$TEST_DIR/.flow/rules/dynamic/my-dynamic.md"
RESULT=$(echo '{"source":"startup","cwd":"'"$TEST_DIR"'"}' | "$SCRIPT_DIR/inject-session-rules.sh")
assert_contains "dynamic rule listed" "my-dynamic.md" "$RESULT"

echo "-- empty input -> silent --"
RESULT=$(echo -n "" | "$SCRIPT_DIR/inject-session-rules.sh")
assert_json_empty "empty input = {}" "$RESULT"

# ============================================================
# Cleanup & Report
# ============================================================
rm -rf "$TEST_DIR"

report
