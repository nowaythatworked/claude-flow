# Reuse Existing Code — Never Duplicate

Before writing ANY new code:
1. Search the codebase for existing implementations of similar logic
2. Check if a utility, helper, or hook already handles this
3. Check if an existing package/dependency provides the functionality before adding new ones

If similar code exists: extend, refactor, or split it to be reusable — don't write a parallel implementation.

Follow existing patterns. If the codebase uses ElectroDB entities, use them — don't write raw DB queries. If there's an existing address matching function, use it. If there's an existing pattern for dropdown interactions in tests, follow it.

When in doubt: "Does something like this already exist?" — search first, write second.
