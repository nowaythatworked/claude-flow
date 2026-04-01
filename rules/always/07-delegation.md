# Delegation — Subagents & Agent Teams

Use agentteam or subagents for both research AND implementation. Keep the orchestrator context clean for reasoning, planning, and verification — delegate heavy lifting.

When to delegate research/exploration:
- Codebase exploration that produces verbose output
- Investigating how existing code works before planning
- Parallel research into multiple approaches

When to use agentteam (agents can communicate):
- Multiple agents working on related files that could conflict
- Agents that should cross-check each other's work
- Coordinated multi-file changes

When to use subagents (independent parallel work):
- Independent tasks with no cross-dependencies
- Focused single-file or single-concern work

For ALL delegated agents:
- Pass the relevant quality rules and project context
- Be specific about what to implement — don't give vague instructions
- Instruct them to search for existing patterns before writing new code
- Instruct them to write tests (TDD)
- Verify their work after completion — don't trust blindly
- Keep tasks focused and small — one concern per agent
