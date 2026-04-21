# Fix Dynamic Rule Evaluation

Root cause: `claude -p --output-format json` returns model response in `.result` as a string.
Model wraps JSON in markdown fences (`` ```json ... ``` ``). The `jq` parsing chain fails
silently (`|| true`), so no dynamic rules are ever injected. Reproduced and confirmed.

## Shared evaluation core (`scripts/eval-rules-core.sh`)
- [x] Extract shared evaluation logic into one function/script
- [x] Switch from freeform `.result` parsing to `--json-schema` structured output
- [x] Schema: `{task_type: string, selected: [{rule: string, reason: string}]}`
- [x] Parse via `.structured_output.selected[].rule`
- [x] Use `--model haiku` (sufficient for classification, faster, cheaper)
- [x] Transcript extraction: parse JSONL, pull user messages + assistant text, 150k char budget, truncate from start, cap individual messages at 10k chars
- [x] Write full structured output to debug log (`/tmp/flow-rule-cache/eval-log-{session}.jsonl`)

## Refactor `evaluate-dynamic-rules.sh` (UserPromptSubmit)
- [x] Replace inline evaluation with call to shared core
- [x] Keep: short-prompt skip logic, cache write, injection formatting

## Refactor `periodic-rule-eval.sh` (PostToolUse)
- [x] Replace inline evaluation with call to shared core
- [x] Keep: debounce logic, changed-selection check, injection formatting

## Fix `subagent-inject.sh` (SubagentStart)
- [x] Read cached selection instead of dumping all dynamic rules
- [x] Inject only the rules selected by the parent session's evaluation
- [x] Always-on rules: keep injecting all (unchanged)

## Integration tests
- [x] Test structured output parsing (valid response, empty selection, single rule, all rules)
- [x] Test cache read/write (subagent reads parent's cached selection)
- [x] Test transcript extraction (small session, large session, missing transcript)
- [x] Test edge cases (no dynamic rules dir, no cache file, corrupt cache)
