#!/bin/bash
# Automated tests for flow scripts.
# Run: ./tests/test-scripts.sh
# Exit code 0 = all passed, 1 = failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0

# --- Helpers ---
setup() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR/.flow"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label (file not found: $path)"
  fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label (file should not exist: $path)"
  fi
}

assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label"
    echo "    expected to contain: $expected"
    echo "    actual: $actual"
  fi
}

assert_empty() {
  local label="$1" actual="$2"
  if [ -z "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label (expected empty, got: $actual)"
  fi
}

assert_json_empty() {
  local label="$1" actual="$2"
  if [ "$actual" = "{}" ] || [ -z "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label (expected {}, got: $actual)"
  fi
}

# ============================================================
echo "=== session.sh ==="
# ============================================================

echo "-- set & get --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --set planning my-task.md
assert_eq "set creates entry" "planning my-task.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get)"
assert_eq "get-phase" "planning" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-phase)"
assert_eq "get-task" "my-task.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-task)"

echo "-- multiple sessions --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --set implementing other-task.md
assert_eq "sess-1 still planning" "planning" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-phase)"
assert_eq "sess-2 implementing" "implementing" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --get-phase)"
assert_eq "sess-2 task" "other-task.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --get-task)"

echo "-- set-phase --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --set-phase implementing
assert_eq "phase updated" "implementing" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-phase)"
assert_eq "task unchanged" "my-task.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-task)"

echo "-- remove --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --remove
assert_empty "sess-1 removed" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get)"
assert_eq "sess-2 still exists" "implementing" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --get-phase)"

echo "-- remove last entry cleans file --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --remove
assert_file_not_exists "SESSIONS removed when empty" "$TEST_DIR/.flow/SESSIONS"

echo "-- get on nonexistent --"
assert_empty "get on missing session" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-99 --get)"

# ============================================================
echo ""
echo "=== phase-gate.sh ==="
# ============================================================

echo "-- no SESSIONS file --"
setup
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hi"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_json_empty "no SESSIONS = silent" "$RESULT"

echo "-- unregistered session --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" other-sess --set planning task.md
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hi"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_json_empty "unregistered = silent" "$RESULT"

echo "-- planning session --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set planning task.md
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hi"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_contains "planning reminder" "planning" "$RESULT"
assert_contains "mentions steps 1-4" "steps 1-4" "$RESULT"

echo "-- implementing session --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set-phase implementing
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hi"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_contains "implementing reminder" "implementing" "$RESULT"
assert_contains "mentions steps 5-6" "steps 5-6" "$RESULT"

# ============================================================
echo ""
echo "=== phase-guard.sh ==="
# ============================================================

echo "-- planning: write outside .flow/ --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set planning task.md
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","tool_input":{"file_path":"'"$TEST_DIR"'/src/app.ts"}}' | "$SCRIPT_DIR/phase-guard.sh")
assert_contains "warns on code write" "planning" "$RESULT"

echo "-- planning: write inside .flow/ --"
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","tool_input":{"file_path":"'"$TEST_DIR"'/.flow/task.md"}}' | "$SCRIPT_DIR/phase-guard.sh")
assert_json_empty ".flow/ writes allowed" "$RESULT"

echo "-- implementing: write outside .flow/ --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set-phase implementing
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","tool_input":{"file_path":"'"$TEST_DIR"'/src/app.ts"}}' | "$SCRIPT_DIR/phase-guard.sh")
assert_json_empty "implementing = silent" "$RESULT"

echo "-- unregistered session: write --"
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"unknown","tool_input":{"file_path":"'"$TEST_DIR"'/src/app.ts"}}' | "$SCRIPT_DIR/phase-guard.sh")
assert_json_empty "unregistered = silent" "$RESULT"

# ============================================================
echo ""
echo "=== branch-detect.sh ==="
# ============================================================

echo "-- startup source (not resume) --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" parent --set planning task.md
TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"/flow:build test"}' > "$TRANSCRIPT"
RESULT=$(echo '{"source":"startup","cwd":"'"$TEST_DIR"'","session_id":"new-sess","transcript_path":"'"$TRANSCRIPT"'"}' | "$SCRIPT_DIR/branch-detect.sh")
assert_json_empty "startup = skip" "$RESULT"
assert_empty "not registered" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" new-sess --get)"

echo "-- resume: already registered --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" new-sess --set implementing task.md
RESULT=$(echo '{"source":"resume","cwd":"'"$TEST_DIR"'","session_id":"new-sess","transcript_path":"'"$TRANSCRIPT"'"}' | "$SCRIPT_DIR/branch-detect.sh")
assert_json_empty "already registered = skip" "$RESULT"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" new-sess --remove

echo "-- resume: branch from build session (single task) --"
RESULT=$(echo '{"source":"resume","cwd":"'"$TEST_DIR"'","session_id":"branched","transcript_path":"'"$TRANSCRIPT"'"}' | "$SCRIPT_DIR/branch-detect.sh")
assert_eq "auto-registered" "planning task.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" branched --get)"

echo "-- resume: non-build transcript --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" branched --remove
NO_BUILD=$(mktemp)
echo '{"role":"user","content":"hello world"}' > "$NO_BUILD"
RESULT=$(echo '{"source":"resume","cwd":"'"$TEST_DIR"'","session_id":"branched","transcript_path":"'"$NO_BUILD"'"}' | "$SCRIPT_DIR/branch-detect.sh")
assert_empty "not registered for non-build" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" branched --get)"
rm -f "$NO_BUILD"

echo "-- resume: multi-task, match by session ID --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" parent2 --set implementing other.md
echo '{"role":"user","content":"session parent flow:build"}' > "$TRANSCRIPT"
RESULT=$(echo '{"source":"resume","cwd":"'"$TEST_DIR"'","session_id":"branched2","transcript_path":"'"$TRANSCRIPT"'"}' | "$SCRIPT_DIR/branch-detect.sh")
PHASE=$("$SCRIPT_DIR/session.sh" "$TEST_DIR" branched2 --get-phase)
TASK=$("$SCRIPT_DIR/session.sh" "$TEST_DIR" branched2 --get-task)
# Should match one of the parents — the one whose ID is in the transcript
assert_eq "matched parent session" "planning" "$PHASE"
assert_eq "matched parent task" "task.md" "$TASK"

echo "-- resume: no SESSIONS file --"
setup
RESULT=$(echo '{"source":"resume","cwd":"'"$TEST_DIR"'","session_id":"orphan","transcript_path":"'"$TRANSCRIPT"'"}' | "$SCRIPT_DIR/branch-detect.sh")
assert_json_empty "no SESSIONS = skip" "$RESULT"

rm -f "$TRANSCRIPT"

# ============================================================
echo ""
echo "=== reset.sh ==="
# ============================================================

echo "-- archive (default) --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set planning my-task.md
printf "# My Task\n- [x] Done\n" > "$TEST_DIR/.flow/my-task.md"
"$SCRIPT_DIR/reset.sh" --session s1 "$TEST_DIR" > /dev/null
assert_file_exists "archived" "$TEST_DIR/.flow/archive/my-task.md"
assert_file_not_exists "original removed" "$TEST_DIR/.flow/my-task.md"
assert_empty "session removed" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --get)"

echo "-- archive collision --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s2 --set planning my-task.md
printf "# Round 2\n" > "$TEST_DIR/.flow/my-task.md"
"$SCRIPT_DIR/reset.sh" --session s2 "$TEST_DIR" > /dev/null
ARCHIVED=$(ls "$TEST_DIR/.flow/archive/" | grep "my-task" | wc -l | tr -d ' ')
assert_eq "two archived versions" "2" "$ARCHIVED"

echo "-- delete --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set implementing task.md
printf "# Task\n" > "$TEST_DIR/.flow/task.md"
"$SCRIPT_DIR/reset.sh" --delete --session s1 "$TEST_DIR" > /dev/null
assert_file_not_exists "deleted" "$TEST_DIR/.flow/task.md"
assert_file_not_exists "not archived" "$TEST_DIR/.flow/archive/task.md"

echo "-- phase-only --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set planning task.md
printf "# Keep me\n" > "$TEST_DIR/.flow/task.md"
"$SCRIPT_DIR/reset.sh" --phase-only --session s1 "$TEST_DIR" > /dev/null
assert_file_exists "task file kept" "$TEST_DIR/.flow/task.md"
assert_empty "session removed" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --get)"

echo "-- other sessions unaffected --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set planning task1.md
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s2 --set implementing task2.md
printf "# Task 1\n" > "$TEST_DIR/.flow/task1.md"
printf "# Task 2\n" > "$TEST_DIR/.flow/task2.md"
"$SCRIPT_DIR/reset.sh" --session s1 "$TEST_DIR" > /dev/null
assert_eq "s2 untouched" "implementing task2.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" s2 --get)"
assert_file_exists "task2 still exists" "$TEST_DIR/.flow/task2.md"

# ============================================================
# Cleanup & Report
# ============================================================
rm -rf "$TEST_DIR"

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
echo "================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
