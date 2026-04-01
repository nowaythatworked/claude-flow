# TDD — Always

All code must have tests. Develop test-driven whenever possible:
1. Write the test first (or at minimum, alongside the implementation)
2. Run the tests to confirm they fail for the right reason
3. Implement the code
4. Run the tests to confirm they pass

Exceptions — files that should NOT be tested:
- Pure type definition files (types only, no logic)
- Schema-only files (Zod schemas with no runtime behavior)
- Configuration/constant files with no logic
- Reference: the ariadne gateway agent's file classification logic for what is/isn't testable

After ANY implementation:
- Run affected tests before reporting completion
- Never claim "tests pass" without actually running them
- If tests fail, investigate the failure — don't just retry
