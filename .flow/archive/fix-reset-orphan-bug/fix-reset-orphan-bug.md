# Fix reset.sh orphan bug when multiple sessions share a task file

## reset.sh — archive all sibling sessions together
- [x] Collect all session IDs from SESSIONS.json where `task_file` matches the resolved task name
- [x] Archive mode: write all matching sessions into `sessions.json` (keyed by session ID, each with `archived_at`) instead of single `session.json`
- [x] Delete mode: remove all matching sessions from SESSIONS.json (no archive writing)
- [x] `--phase-only` path: unchanged (already exits early, only removes calling session)
- [x] Auto-commit after archive/delete: `git add` changed files, commit with `chore: archive <task-name>` or `chore: reset <task-name>`. Skip silently if not in a git repo.

## tests/test-scripts.sh — update existing + add shared-file tests
- [x] Update "archive (default)" test to expect `sessions.json` (plural, keyed format)
- [x] Add "shared task file" test: two sessions same file, reset archives both sessions and the file, both entries removed from SESSIONS.json
- [x] Add test for auto-commit after archive

## tests/test-integration.sh — filename update
- [x] Update `session.json` filename check to `sessions.json`
