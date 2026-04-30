import { formatRulesInjection } from "../inject.ts";
import { unionAllSelected } from "../eval.ts";
import { appendInjected, readInjectedLedger } from "../injected-ledger.ts";
import type { CacheState } from "../types.ts";

export function computeDeltaInjection(
  state: CacheState | null,
  sessionId: string,
  cwd: string,
  hookEventName: string,
): object {
  if (!state) return {};
  const current = unionAllSelected(state);
  const prior = readInjectedLedger(sessionId, cwd);
  const isInitial = prior.length === 0;
  const priorSet = new Set(prior);
  const delta = current.filter((id) => !priorSet.has(id));
  if (delta.length === 0) return {};
  const injection = formatRulesInjection(delta, cwd, { isInitial });
  if (injection === "") return {};
  appendInjected(sessionId, state.task_file, state.focus_hash, delta, cwd);
  return {
    hookSpecificOutput: {
      hookEventName,
      additionalContext: injection,
    },
  };
}
