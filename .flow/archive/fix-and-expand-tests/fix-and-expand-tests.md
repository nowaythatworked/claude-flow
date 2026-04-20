# Fix and Expand Test Suite

All work committed in 06fba13.

## Fix phase-guard.sh test failure
- [x] Add `|| true` to command substitutions where phase-guard.sh exits with code 2
  Used `|| EXIT_CODE=$?` pattern to capture both output and exit code
- [x] Add exit code assertions to verify blocking behavior (exit 2)
  Added `assert_eq "blocks with exit code 2"` for both planning and planned phases

## Shared infrastructure
- [x] Extract helpers.sh from test-scripts.sh
  Created `tests/helpers.sh` with all assert functions, setup(), and report()
- [x] Refactor test-scripts.sh to source helpers.sh
- [x] Create run-all.sh test runner
  Runs all `test-*.sh` files, skips `test-integration.sh`, reports pass/fail

## Add tests for flow-next-lock.sh
- [x] Non-`/flow:next` prompts → silent
- [x] `/flow:next` in implementing phase → locks to planned, clears focus, injects context
- [x] `/flow:next --no-lock` → silent (respects flag)
- [x] Non-implementing phase and missing SESSIONS.json → silent
  8 assertions, all passing

## Add tests for rule-reminder.sh
- [x] Rules exist → outputs "Quality rules are active" reminder
- [x] No rules or empty directory → silent
  5 assertions, all passing

## Add tests for inject-session-rules.sh
- [x] Source `startup` with always-on rules → injects rule content
- [x] Source `compact` → re-injects rules
- [x] Source `resume` → silent (not startup/compact)
- [x] Dynamic rules listed in output when present
  8 assertions, all passing

## Add tests for stop-rule-check.sh
- [x] First stop (stop_hook_active=false) → blocks with compliance reason
- [x] Second stop (stop_hook_active=true) → allows (exit 0)
  5 assertions, all passing

## Add tests for scan-quality.sh
- [x] Clean TS content → silent
- [x] Content with `any` type, `as any`, `@ts-ignore` → reports violations
- [x] Non-TS file → silent (skipped)
  14 assertions (includes bonus Edit new_string test), all passing

## Add tests for init.sh
- [x] Creates directory structure and copies rules
- [x] Installs agents with `__FLOW_PLUGIN_ROOT__` substitution
- [x] Idempotent — skips existing files
- [x] Cleans stale state files
  14 assertions, all passing
