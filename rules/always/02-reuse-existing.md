# Reuse & Refactor — Reshape Before Adding

Before writing new code, search the codebase for existing implementations of similar logic. Check utilities, helpers, hooks, and existing packages.

**When existing code is close but not quite right — refactor it.** Don't add a parallel implementation. Break open the existing function, improve its typing, split its responsibilities, generalize its interface. Make it serve both the old and new use case. This is almost always better than adding new code alongside it.

LLMs default to leaving existing code untouched and writing something new next to it. Fight this instinct. The codebase gets better when you reshape existing code, not when you pile new code on top.

Refactoring is safe here — we use TDD and test coverage keeps growing. Small refactors (rename, split, re-type, extract) are always safe. Larger refactors are safe when tests cover the behavior.

Follow existing patterns. If the codebase uses ElectroDB entities, use them. If there's an existing helper, use it. If there's an existing test pattern, follow it.

When in doubt: "Can I change what exists to do what I need?" before "Should I write something new?"
