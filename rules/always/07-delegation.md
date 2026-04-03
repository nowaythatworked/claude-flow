# Delegation — Subagents & Agent Teams

Delegate work that benefits from a focused context or parallelism. Keep the orchestrator context clean for reasoning, planning, and verification.

## When to delegate

- Substantial code changes — multiple files, complex logic
- Codebase exploration that produces verbose output
- Parallel independent tasks
- Anything where a focused agent context is more effective than the orchestrator's broad context

## When the orchestrator can do it directly

- Quick operations where spawning an agent costs more than doing it: a single shell command, a small config edit, a git merge
- Simple verification (running a test, checking a build)
- Updating the task file or .flow/ state

## Subagents vs agentteam

- **Subagents** — independent tasks, no cross-dependencies, focused single-concern work
- **Agentteam** — related files that could conflict, agents that should coordinate or cross-check

## For all delegated agents

- Be specific about what to implement — don't give vague instructions
- Pass relevant quality rules and project context
- Instruct them to search for existing patterns before writing new code
- Instruct them to write tests (TDD)
- Verify their work after completion — don't trust blindly
- Keep tasks focused and small — one concern per agent
