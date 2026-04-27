#!/usr/bin/env bun
const out = {
  result: null,
  structured_output: {
    task_type: "test",
    selected_rules: ["llm-rule.md"],
    reason: "fixture",
  },
};
process.stdout.write(JSON.stringify(out));
