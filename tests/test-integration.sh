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

# Find session ID from SESSIONS.json
get_build_session() {
  if [ -f "$TEST_PROJECT/.flow/SESSIONS.json" ]; then
    jq -r 'keys[0]' "$TEST_PROJECT/.flow/SESSIONS.json" 2>/dev/null
  fi
}

# --- Preflight ---
if ! command -v claude &>/dev/null; then
  echo "SKIP: claude CLI not found"
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "SKIP: jq not found (required for JSON session management)"
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
assert_file_not_exists "no stale SESSIONS.json" "$TEST_PROJECT/.flow/SESSIONS.json"
echo ""

# ============================================================
echo "=== Test 2: /flow:build creates session (planning phase) ==="
# ============================================================
RESULT=$(run_prompt 'Use the /flow:build skill with this task: TEST MODE. Initialize step 0 only: register the session and pick a task filename. Then stop — do not proceed to step 1. Do not ask questions. Do not create the task file.')
echo "  (agent responded: $(echo "$RESULT" | head -1))"

assert_file_exists "SESSIONS.json created" "$TEST_PROJECT/.flow/SESSIONS.json"

BUILD_SESSION=$(get_build_session)
if [ -n "$BUILD_SESSION" ]; then
  PASS=$((PASS + 1)); echo "  ✓ session registered: ${BUILD_SESSION:0:12}..."
  PHASE=$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESSION" --get-phase)
  assert_eq "planning phase" "planning" "$PHASE"
else
  FAIL=$((FAIL + 1)); echo "  ✗ no session in SESSIONS.json"
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
echo "=== Test 5: /flow:approve → planned ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  # Simulate a plan discussion by telling the agent what the plan is
  RESULT=$(resume_prompt "$BUILD_SESSION" 'The plan we discussed is: ## Area A - Task 1 - Task 2. Now run /flow:approve to write this plan to the task file.')
  PHASE=$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESSION" --get-phase)
  assert_eq "phase is planned" "planned" "$PHASE"
  TASK=$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESSION" --get-task)
  if [ -n "$TASK" ] && [ -f "$TEST_PROJECT/.flow/$TASK" ]; then
    PASS=$((PASS + 1)); echo "  ✓ task file created: $TASK"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ task file not created"
  fi
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 6: code writes blocked during planned ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'TEST: Try to write "hello" to src/test.ts. Report what happened.')
  if [ -f "$TEST_PROJECT/src/test.ts" ]; then
    assert_contains "acknowledged planned violation" "planned" "$RESULT"
  else
    PASS=$((PASS + 1)); echo "  ✓ agent refused to write code during planned phase"
  fi
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 7: /flow:next → analyze + set focus ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'Run /flow:next. The task file has Area A with Task 1 and Task 2. I want to focus on "Area A". Set that as focus and do a brief deep-dive. Keep it short.')
  FOCUS=$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESSION" --get-focus)
  if [ "$FOCUS" != "[]" ] && [ -n "$FOCUS" ]; then
    PASS=$((PASS + 1)); echo "  ✓ focus set: $FOCUS"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ focus not set (got: $FOCUS)"
  fi
  # Phase should still be planned (not implementing yet)
  PHASE=$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESSION" --get-phase)
  assert_eq "still in planned phase" "planned" "$PHASE"
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 8: /flow:implement → implementing ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'Run /flow:implement. This is a test — just confirm the transition, do not actually write any code.')
  PHASE=$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESSION" --get-phase)
  assert_eq "phase is implementing" "implementing" "$PHASE"
  assert_contains "confirmed implement" "implement" "$RESULT"
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 9: /flow:lock from implementing → planned ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'Run /flow:lock')
  PHASE=$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESSION" --get-phase)
  assert_eq "phase is planned" "planned" "$PHASE"
  FOCUS=$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESSION" --get-focus)
  assert_eq "focus cleared" "[]" "$FOCUS"
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 10: /flow:lock from planned → planning ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'Run /flow:lock')
  PHASE=$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESSION" --get-phase)
  assert_eq "phase is planning" "planning" "$PHASE"
  assert_contains "confirmed lock" "planning" "$RESULT"
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 11: /flow:phase reports correctly ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'Run /flow:phase')
  assert_contains "shows planning" "planning" "$RESULT"
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 12: /flow:reset archives + cleans up ==="
# ============================================================
if [ -n "$BUILD_SESSION" ]; then
  RESULT=$(resume_prompt "$BUILD_SESSION" 'Run /flow:reset -y')
  ARCHIVED=$(ls "$TEST_PROJECT/.flow/archive/"*.md 2>/dev/null | head -1)
  if [ -n "$ARCHIVED" ]; then
    PASS=$((PASS + 1)); echo "  ✓ task file archived: $(basename "$ARCHIVED")"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ no archived task file"
  fi
  if [ -f "$TEST_PROJECT/.flow/SESSIONS.json" ] && jq -e --arg id "$BUILD_SESSION" '.[$id]' "$TEST_PROJECT/.flow/SESSIONS.json" &>/dev/null; then
    FAIL=$((FAIL + 1)); echo "  ✗ session still in SESSIONS.json"
  else
    PASS=$((PASS + 1)); echo "  ✓ session cleaned up"
  fi
else
  SKIP=$((SKIP + 1)); echo "  ~ skipped (no session)"
fi
echo ""

# ============================================================
echo "=== Test 13: side-task session is not affected ==="
# ============================================================
# Create an active build in another session
"$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" fake-build --set planning side-test.md
printf "# Side Test\n" > "$TEST_PROJECT/.flow/side-test.md"

RESULT=$(run_prompt 'Say exactly: SIDE_TASK_OK')
assert_contains "side task runs normally" "SIDE_TASK_OK" "$RESULT"
# Verify side task didn't get registered
if [ -f "$TEST_PROJECT/.flow/SESSIONS.json" ]; then
  SESSION_COUNT=$(jq 'length' "$TEST_PROJECT/.flow/SESSIONS.json" 2>/dev/null || echo "0")
  assert_eq "no extra sessions added" "1" "$SESSION_COUNT"
fi

# Clean up
"$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" fake-build --remove
rm -f "$TEST_PROJECT/.flow/side-test.md"
echo ""

# ============================================================
echo "=== Test 14: branch detection (script-level) ==="
# ============================================================
BUILD_SESS="build-$(date +%s)"
"$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BUILD_SESS" --set planned branch-task.md
printf "# Branch Task\n" > "$TEST_PROJECT/.flow/branch-task.md"

FAKE_TRANSCRIPT=$(mktemp)
echo "{\"role\":\"user\",\"content\":\"/flow:build test task\"}" > "$FAKE_TRANSCRIPT"
echo "{\"role\":\"assistant\",\"content\":\"session $BUILD_SESS registered\"}" >> "$FAKE_TRANSCRIPT"

BRANCHED="branch-$(date +%s)"
echo "{\"source\":\"resume\",\"cwd\":\"$TEST_PROJECT\",\"session_id\":\"$BRANCHED\",\"transcript_path\":\"$FAKE_TRANSCRIPT\"}" \
  | "$PLUGIN_DIR/scripts/branch-detect.sh" > /dev/null

assert_eq "branch phase inherited" "planned" "$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BRANCHED" --get-phase)"
assert_eq "branch task inherited" "branch-task.md" "$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BRANCHED" --get-task)"
# Check parent relationship
BRANCH_JSON=$("$PLUGIN_DIR/scripts/session.sh" "$TEST_PROJECT" "$BRANCHED" --get-json)
assert_contains "parent set on branch" "$BUILD_SESS" "$BRANCH_JSON"

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
