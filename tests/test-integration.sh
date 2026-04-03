#!/bin/bash
# Integration tests for flow plugin.
# Runs real Claude Code sessions with the plugin loaded.
# Requires: claude CLI with active subscription.
#
# Run: ./tests/test-integration.sh

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_PROJECT=$(mktemp -d)
PASS=0
FAIL=0
SKIP=0
BUILD_SESSION=""

# --- Helpers ---
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1)); echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ $label"; echo "    expected: $expected"; echo "    actual:   $actual"
  fi
}

assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qi "$expected"; then
    PASS=$((PASS + 1)); echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ $label"; echo "    expected to contain: $expected"; echo "    actual: $(echo "$actual" | head -3)"
  fi
}

assert_not_contains() {
  local label="$1" unexpected="$2" actual="$3"
  if ! echo "$actual" | grep -qi "$unexpected"; then
    PASS=$((PASS + 1)); echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ $label"; echo "    should NOT contain: $unexpected"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1)); echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ $label (not found: $path)"
  fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then
    PASS=$((PASS + 1)); echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ $label (should not exist: $path)"
  fi
}

assert_file_contains() {
  local label="$1" expected="$2" path="$3"
  if [ -f "$path" ] && grep -q "$expected" "$path" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ $label (missing or no match: $expected)"
  fi
}

# Run a prompt in the test project
run_prompt() {
  local prompt="$1"
  (cd "$TEST_PROJECT" && claude -p \
    --plugin-dir "$PLUGIN_DIR" \
    --model sonnet \
    --max-turns 5 \
    --permission-mode bypassPermissions \
    "$prompt") 2>/dev/null || true
}

# Continue a session
resume_prompt() {
  local session="$1" prompt="$2"
  (cd "$TEST_PROJECT" && claude -p \
    --plugin-dir "$PLUGIN_DIR" \
    --model sonnet \
    --max-turns 5 \
    --permission-mode bypassPermissions \
    --resume "$session" \
    "$prompt") 2>/dev/null || true
}

# Find session ID from SESSIONS file
get_build_session() {
  if [ -f "$TEST_PROJECT/.flow/SESSIONS" ]; then
    head -1 "$TEST_PROJECT/.flow/SESSIONS" | awk '{print $1}'
  fi
}

# --- Preflight ---
if ! command -v claude &>/dev/null; then
  echo "SKIP: claude CLI not found"
  exit 0
fi

# --- Setup test project ---
echo "Setting up test project: $TEST_PROJECT"
cd "$TEST_PROJECT"
git init -q
echo "test" > README.md
git add -A && git commit -q -m "init"

# Run init directly (has disable-model-invocation)
CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" "$PLUGIN_DIR/scripts/init.sh" "$TEST_PROJECT" > /dev/null 2>&1
echo ""

# ============================================================
echo "=== Test 1: init script ran correctly ==="
# ============================================================
assert_file_exists "always-on rules installed" "$TEST_PROJECT/.flow/rules/always/01-understand-first.md"
assert_file_exists "flow-dev agent installed" "$TEST_PROJECT/.claude/agents/flow-dev.md"
assert_file_not_exists "no stale SESSIONS" "$TEST_PROJECT/.flow/SESSIONS"
echo ""

# ============================================================
echo "=== Test 2: /flow:build creates session + task file ==="
# ============================================================
RESULT=$(run_prompt 'Use the /flow:build skill with this task: TEST MODE. Initialize step 0 only: register the session and create a task file called "integration-test.md". Then stop — do not proceed to step 1. Do not ask questions.')
echo "  (agent responded: $(echo "$RESULT" | head -1))"

assert_file_exists "SESSIONS created" "$TEST_PROJECT/.flow/SESSIONS"

BUILD_SESSION=$(get_build_session)
if [ -n "$BUILD_SESSION" ]; then
  PASS=$((PASS + 1)); echo "  ✓ session registered: ${BUILD_SESSION:0:12}..."
  assert_file_contains "planning phase" "planning" "$TEST_PROJECT/.flow/SESSIONS"
else
  FAIL=$((FAIL + 1)); echo "  ✗ no session in SESSIONS"
fi

TASK_FILE=$(ls "$TEST_PROJECT/.flow/"*.md 2>/dev/null | head -1)
if [ -n "$TASK_FILE" ]; then
  PASS=$((PASS + 1)); echo "  ✓ task file created: $(basename "$TASK_FILE")"
else
  FAIL=$((FAIL + 1)); echo "  ✗ no task file in .flow/"
fi
echo ""

# ============================================================
echo "=== Test 3: phase-gate injects planning reminder ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'What workflow phase am I currently in? Answer with just the phase name.')
  assert_contains "agent knows phase" "planning" "$RESULT"
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 4: code writes blocked during planning ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'TEST: Try to write "hello" to src/test.ts in the project root. Report what happened.')
  if [ -f "$TEST_PROJECT/src/test.ts" ]; then
    assert_contains "acknowledged phase violation" "planning" "$RESULT"
  else
    PASS=$((PASS + 1)); echo "  ✓ agent refused to write code during planning"
  fi
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 5: /flow:approve → implementing ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  # Write a plan so approve doesn't refuse
  TASK_FILE=$(ls "$TEST_PROJECT/.flow/"*.md 2>/dev/null | head -1)
  if [ -n "$TASK_FILE" ]; then
    printf "# Integration Test Plan\n\n## Area A\n- [ ] Task 1\n- [ ] Task 2\n\n## Area B\n- [ ] Task 3\n" > "$TASK_FILE"
  fi
  RESULT=$(resume_prompt "$BUILD_SESSION" 'Run /flow:approve')
  assert_file_contains "phase is implementing" "implementing" "$TEST_PROJECT/.flow/SESSIONS"
  assert_contains "confirmed approval" "implement" "$RESULT"
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 6: /flow:lock → back to planning ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'Run /flow:lock')
  assert_file_contains "phase is planning again" "planning" "$TEST_PROJECT/.flow/SESSIONS"
  assert_contains "confirmed lock" "planning" "$RESULT"
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 7: /flow:phase reports correctly ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'Run /flow:phase')
  assert_contains "shows planning" "planning" "$RESULT"
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 8: /flow:reset archives + cleans up ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'Run /flow:reset -y')
  ARCHIVED=$(ls "$TEST_PROJECT/.flow/archive/"*.md 2>/dev/null | head -1)
  if [ -n "$ARCHIVED" ]; then
    PASS=$((PASS + 1)); echo "  ✓ task file archived: $(basename "$ARCHIVED")"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ no archived task file"
  fi
  if [ -f "$TEST_PROJECT/.flow/SESSIONS" ] && grep -q "$BUILD_SESSION" "$TEST_PROJECT/.flow/SESSIONS" 2>/dev/null; then
    FAIL=$((FAIL + 1)); echo "  ✗ session still in SESSIONS"
  else
    PASS=$((PASS + 1)); echo "  ✓ session cleaned up"
  fi
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 9: side-task session is not affected ==="
# ============================================================
# Create an active build in another session
"$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" fake-build --set planning side-test.md
printf "# Side Test\n" > "$TEST_PROJECT/.flow/side-test.md"

RESULT=$(run_prompt 'Say exactly: SIDE_TASK_OK')
assert_contains "side task runs normally" "SIDE_TASK_OK" "$RESULT"
# Verify side task didn't get registered
if [ -f "$TEST_PROJECT/.flow/SESSIONS" ]; then
  SIDE_SESSION_COUNT=$(wc -l < "$TEST_PROJECT/.flow/SESSIONS" | tr -d ' ')
  assert_eq "no extra sessions added" "1" "$SIDE_SESSION_COUNT"
fi

# Clean up
"$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" fake-build --remove
rm -f "$TEST_PROJECT/.flow/side-test.md"
echo ""

# ============================================================
echo "=== Test 10: branch detection (script-level) ==="
# ============================================================
BUILD_SESS="build-$(date +%s)"
"$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESS" --set planning branch-task.md
printf "# Branch Task\n" > "$TEST_PROJECT/.flow/branch-task.md"

FAKE_TRANSCRIPT=$(mktemp)
echo "{\"role\":\"user\",\"content\":\"/flow:build test task\"}" > "$FAKE_TRANSCRIPT"
echo "{\"role\":\"assistant\",\"content\":\"session $BUILD_SESS registered\"}" >> "$FAKE_TRANSCRIPT"

BRANCHED="branch-$(date +%s)"
echo "{\"source\":\"resume\",\"cwd\":\"$TEST_PROJECT\",\"session_id\":\"$BRANCHED\",\"transcript_path\":\"$FAKE_TRANSCRIPT\"}" \
  | "$PLUGIN_DIR/scripts/branch-detect.sh" > /dev/null

assert_eq "branch phase inherited" "planning" "$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BRANCHED" --get-phase)"
assert_eq "branch task inherited" "branch-task.md" "$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BRANCHED" --get-task)"

rm -f "$FAKE_TRANSCRIPT"
echo ""

# ============================================================
# Cleanup & Report
# ============================================================
rm -rf "$TEST_PROJECT"

echo "================================"
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
