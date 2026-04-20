#!/bin/bash
# Automated tests for flow scripts.
# Run: ./tests/test-scripts.sh
# Exit code 0 = all passed, 1 = failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_DIR=$(mktemp -d)

source "$(dirname "$0")/helpers.sh"

# ============================================================
echo "=== session.sh ==="
# ============================================================

echo "-- set & get --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --set planning my-task.md
assert_eq "set creates entry" "planning my-task.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get)"
assert_eq "get-phase" "planning" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-phase)"
assert_eq "get-task" "my-task.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-task)"
assert_eq "get-focus default" "[]" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-focus)"

echo "-- JSON format --"
assert_file_exists "SESSIONS.json created" "$TEST_DIR/.flow/SESSIONS.json"
JSON=$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-json)
assert_contains "json has phase" "planning" "$JSON"
assert_contains "json has task_file" "my-task.md" "$JSON"

echo "-- multiple sessions --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --set implementing other-task.md
assert_eq "sess-1 still planning" "planning" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-phase)"
assert_eq "sess-2 implementing" "implementing" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --get-phase)"
assert_eq "sess-2 task" "other-task.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --get-task)"

echo "-- set-phase --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --set-phase planned
assert_eq "phase updated" "planned" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-phase)"
assert_eq "task unchanged" "my-task.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-task)"

echo "-- focus --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --set-focus "Auth Middleware" "Rate Limiting"
FOCUS=$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-focus)
assert_contains "focus has first item" "Auth Middleware" "$FOCUS"
assert_contains "focus has second item" "Rate Limiting" "$FOCUS"

"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --clear-focus
assert_eq "focus cleared" "[]" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get-focus)"

echo "-- parent --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --set-parent sess-1
JSON=$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --get-json)
assert_contains "parent set" "sess-1" "$JSON"

echo "-- dump --"
DUMP=$("$SCRIPT_DIR/session.sh" "$TEST_DIR" --dump)
assert_contains "dump has sess-1" "sess-1" "$DUMP"
assert_contains "dump has sess-2" "sess-2" "$DUMP"

echo "-- list --"
LIST=$("$SCRIPT_DIR/session.sh" "$TEST_DIR" --list)
assert_contains "list has sess-1" "sess-1" "$LIST"
assert_contains "list has sess-2" "sess-2" "$LIST"

echo "-- remove --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --remove
assert_empty "sess-1 removed" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-1 --get)"
assert_eq "sess-2 still exists" "implementing" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --get-phase)"

echo "-- remove last entry cleans file --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-2 --remove
assert_file_not_exists "SESSIONS.json removed when empty" "$TEST_DIR/.flow/SESSIONS.json"

echo "-- get on nonexistent --"
assert_empty "get on missing session" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" sess-99 --get)"

# ============================================================
echo ""
echo "=== phase-gate.sh ==="
# ============================================================

echo "-- no SESSIONS.json file --"
setup
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hi"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_json_empty "no SESSIONS.json = silent" "$RESULT"

echo "-- unregistered session --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" other-sess --set planning task.md
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hi"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_json_empty "unregistered = silent" "$RESULT"

echo "-- planning session --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set planning task.md
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hi"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_contains "planning reminder" "planning" "$RESULT"
assert_contains "mentions approve" "approve" "$RESULT"

echo "-- planned session (no focus) --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set-phase planned
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hi"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_contains "planned reminder" "planned" "$RESULT"
assert_contains "mentions next" "next" "$RESULT"

echo "-- planned session (with focus) --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set-focus "Auth Middleware"
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hi"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_contains "focus in reminder" "Auth Middleware" "$RESULT"
assert_contains "mentions implement" "implement" "$RESULT"

echo "-- implementing session --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set-phase implementing
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hi"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_contains "implementing reminder" "implementing" "$RESULT"
assert_contains "mentions next" "next" "$RESULT"

echo "-- /flow: commands skip injection --"
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"/flow:next"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_json_empty "flow command = skip" "$RESULT"
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"/flow:implement"}' | "$SCRIPT_DIR/phase-gate.sh")
assert_json_empty "flow implement = skip" "$RESULT"

# ============================================================
echo ""
echo "=== phase-guard.sh ==="
# ============================================================

echo "-- planning: write outside .flow/ --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set planning task.md
EXIT_CODE=0
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","tool_input":{"file_path":"'"$TEST_DIR"'/src/app.ts"}}' | "$SCRIPT_DIR/phase-guard.sh") || EXIT_CODE=$?
assert_eq "blocks with exit code 2 (planning)" "2" "$EXIT_CODE"
assert_contains "warns on code write (planning)" "planning" "$RESULT"

echo "-- planned: write outside .flow/ --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set-phase planned
EXIT_CODE=0
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","tool_input":{"file_path":"'"$TEST_DIR"'/src/app.ts"}}' | "$SCRIPT_DIR/phase-guard.sh") || EXIT_CODE=$?
assert_eq "blocks with exit code 2 (planned)" "2" "$EXIT_CODE"
assert_contains "warns on code write (planned)" "planned" "$RESULT"

echo "-- planning: write inside .flow/ --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set-phase planning
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
assert_eq "auto-registered phase" "planning" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" branched --get-phase)"
assert_eq "auto-registered task" "task.md" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" branched --get-task)"
# Check parent was set
BRANCH_JSON=$("$SCRIPT_DIR/session.sh" "$TEST_DIR" branched --get-json)
assert_contains "parent set" "parent" "$BRANCH_JSON"

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
assert_eq "matched parent session" "planning" "$PHASE"
assert_eq "matched parent task" "task.md" "$TASK"

echo "-- resume: no SESSIONS.json file --"
setup
RESULT=$(echo '{"source":"resume","cwd":"'"$TEST_DIR"'","session_id":"orphan","transcript_path":"'"$TRANSCRIPT"'"}' | "$SCRIPT_DIR/branch-detect.sh")
assert_json_empty "no SESSIONS.json = skip" "$RESULT"

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
assert_file_exists "archived in folder" "$TEST_DIR/.flow/archive/my-task/my-task.md"
assert_file_exists "sessions.json created" "$TEST_DIR/.flow/archive/my-task/sessions.json"
assert_file_not_exists "original removed" "$TEST_DIR/.flow/my-task.md"
assert_empty "session removed" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --get)"
# Verify sessions.json contains keyed session entry with archived_at
S1_PHASE=$(jq -r '.s1.phase' "$TEST_DIR/.flow/archive/my-task/sessions.json")
assert_eq "s1 phase in json" "planning" "$S1_PHASE"
ARCHIVED_AT=$(jq -r '.s1.archived_at' "$TEST_DIR/.flow/archive/my-task/sessions.json")
assert_not_empty "archived_at present" "$ARCHIVED_AT"

echo "-- archive collision --"
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s2 --set planning my-task.md
printf "# Round 2\n" > "$TEST_DIR/.flow/my-task.md"
"$SCRIPT_DIR/reset.sh" --session s2 "$TEST_DIR" > /dev/null
ARCHIVED=$(ls -d "$TEST_DIR/.flow/archive/my-task"* | wc -l | tr -d ' ')
assert_eq "two archived versions" "2" "$ARCHIVED"

echo "-- delete --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set implementing task.md
printf "# Task\n" > "$TEST_DIR/.flow/task.md"
"$SCRIPT_DIR/reset.sh" --delete --session s1 "$TEST_DIR" > /dev/null
assert_file_not_exists "deleted" "$TEST_DIR/.flow/task.md"
assert_dir_not_exists "not archived" "$TEST_DIR/.flow/archive/task"

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

echo "-- shared task file: all sessions archived --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set implementing shared.md
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s2 --set implementing shared.md
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s2 --set-parent s1
printf "# Shared Task\n" > "$TEST_DIR/.flow/shared.md"
"$SCRIPT_DIR/reset.sh" --session s1 "$TEST_DIR" > /dev/null
assert_file_exists "task file archived" "$TEST_DIR/.flow/archive/shared/shared.md"
assert_file_exists "sessions.json created" "$TEST_DIR/.flow/archive/shared/sessions.json"
# Both sessions in archive
S1_IN_ARCHIVE=$(jq -r '.s1.phase' "$TEST_DIR/.flow/archive/shared/sessions.json")
assert_eq "s1 in archive" "implementing" "$S1_IN_ARCHIVE"
S2_IN_ARCHIVE=$(jq -r '.s2.phase' "$TEST_DIR/.flow/archive/shared/sessions.json")
assert_eq "s2 in archive" "implementing" "$S2_IN_ARCHIVE"
S2_PARENT=$(jq -r '.s2.parent' "$TEST_DIR/.flow/archive/shared/sessions.json")
assert_eq "s2 parent preserved" "s1" "$S2_PARENT"
# Both removed from SESSIONS.json
assert_empty "s1 removed" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --get)"
assert_empty "s2 removed" "$("$SCRIPT_DIR/session.sh" "$TEST_DIR" s2 --get)"

echo "-- auto-commit after archive --"
setup
# Init a git repo so auto-commit works
git init "$TEST_DIR" --quiet
printf "" > "$TEST_DIR/.flow/.gitkeep"
git -C "$TEST_DIR" add .flow/ && git -C "$TEST_DIR" commit -m "init" --quiet
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set planning commit-test.md
printf "# Commit Test\n" > "$TEST_DIR/.flow/commit-test.md"
git -C "$TEST_DIR" add .flow/ && git -C "$TEST_DIR" commit -m "add task" --quiet
"$SCRIPT_DIR/reset.sh" --session s1 "$TEST_DIR" > /dev/null
LAST_MSG=$(git -C "$TEST_DIR" log --oneline -1 --format="%s")
assert_eq "auto-commit message" "chore: archive commit-test" "$LAST_MSG"

# ============================================================
# Cleanup & Report
# ============================================================
rm -rf "$TEST_DIR"

report
