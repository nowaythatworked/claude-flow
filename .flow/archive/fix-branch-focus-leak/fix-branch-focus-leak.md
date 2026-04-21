# Fix branched session focus leak

When branching after `/flow:next`, the LLM in the branched session uses the parent's session ID (from template-expanded skill text) for `session.sh` commands. Focus gets written to the main session instead of the branch.

Fix: inject a `CURRENT_SESSION_ID` variable via phase-gate.sh on every prompt, and reference it in all skills instead of `${CLAUDE_SESSION_ID}`.

## phase-gate.sh — inject session ID
- [x] Add `CURRENT_SESSION_ID=<id>` with usage hint to additionalContext output (1d7e3e5)

## Skills — replace session ID references
- [x] Replace `${CLAUDE_SESSION_ID}` → `$CURRENT_SESSION_ID` in all 7 skills (1d7e3e5)
  build (1, kept bootstrap), next (5), implement (3), phase (7), approve (3), lock (5), reset (2)

Version bump to 0.4.3 (a1a756d)
