# Fix "stale sessions" mischaracterization in /flow:next

## skills/next/SKILL.md — Reframe how the agent interprets other session entries
- [x] Step 1 `--dump` instruction: replaced "check what other sessions are working on" with language explaining entries persist until `/flow:reset` and should only be used for focus collision avoidance (a9c5f8e)
- [x] Step 2 analysis: reframed "Are any tasks claimed by other sessions?" to check active focus conflicts, ignoring entries with empty focus (a9c5f8e)
- [x] Verified remaining wording (lines 58, 120) talks about task claims via focus fields, not session liveness — no change needed
