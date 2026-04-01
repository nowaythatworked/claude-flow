# Type Safety — No Shortcuts

Never use:
- `any` types
- `as unknown as X` assertions
- `Record<string, unknown>` as a lazy type
- Hardcoded type assertions that mask the real type

When fixing type errors:
- Trace the issue to its ROOT CAUSE — don't bandaid at the error site
- If a field is required, type it as required — not optional
- If a Zod schema defines the type, derive the TypeScript type from the schema — don't hardcode a parallel type

When CI typechecks fail: READ the CI output before proposing fixes.
