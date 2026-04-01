keywords: review, coderabbit, feedback, comment, pr review, unresolved
# Responding to PR Reviews

When the user pastes review comments (CodeRabbit, human, or other LLM):
1. Don't blindly fix all comments — TRIAGE first
2. For each comment: is it valid? Does it align with codebase patterns?
3. Discuss findings with the user before implementing fixes
4. When fixing: do it properly, not dirty — "the fixes were dirty" is a recurring issue

For CodeRabbit specifically:
- When told "unresolved comments only" — only address unresolved ones
- After fixing: commit and resolve addressed comments
- Don't resolve comments you didn't address

For human reviews:
- Verify the review's validity before acting: "is this actually a bug or a misunderstanding?"
- Consider if the suggestion aligns with existing architecture decisions
