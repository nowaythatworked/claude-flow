---
description: "Git operation safety rules. Load when doing commits, merges, branch management, or worktree operations."
---
# Git Workflow Rules

Before ANY git operation: verify the current branch with `git branch`.

- Never commit without explicit user instruction
- When told to use a worktree, use a worktree — not a branch on the main repo
- When told "don't merge yet", don't merge
- If multiple branches have been discussed, confirm which one before operating

Commit practices:
- Separate commits per logical change when possible
- Don't commit generated files, .env files, or state files unless asked
- Commit messages should describe WHY, not WHAT
