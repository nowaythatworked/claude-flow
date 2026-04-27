export interface RuleFrontmatter {
  relevance?: string;
  patterns?: string[];
  keywords?: string[];
}

export interface ParsedRule {
  frontmatter: RuleFrontmatter | null;
  body: string;
}

export interface CatalogEntry {
  id: string;
  frontmatter: RuleFrontmatter;
  body: string;
}

export type RuleCatalog = Map<string, CatalogEntry>;

export interface SessionWatermark {
  watermark_uuid: string;
  last_seen_ts: string;
}

export interface CacheState {
  schema_version: 1;
  task_file: string;
  focus: string[];
  focus_hash: string;
  selected_via_pattern: string[];
  selected_via_keyword: string[];
  selected_via_llm: string[];
  task_type: string;
  trigger_reason: string;
  last_eval_ts: string;
  last_eval_duration_ms: number;
  per_session: Record<string, SessionWatermark>;
}

export interface LockInfo {
  pid: number;
  started_at: string;
  trigger: string;
  session_id: string;
  covers_up_to_uuid: string | null;
}

export interface LockInspection {
  pid: number;
  startedAt: string;
  coversUpToUuid: string | null;
  fresh: boolean;
}

export interface ExtractedReadEntry {
  path: string;
  content: string;
}

export interface ExtractedEditEntry {
  old: string;
  new: string;
}

export interface ExtractedContent {
  filesInScope: {
    reads: Map<string, string>;
    edits: Map<string, ExtractedEditEntry[]>;
  };
  globResults: string[][];
  recentUserText: string[];
  recentAssistantText: string[];
  newWatermarkCandidate: string;
}

export interface HaikuOutput {
  task_type: string;
  selected_rules: string[];
  reason: string;
}

export interface LLMCatalogEntry {
  id: string;
  relevance: string;
}

export interface EvalLogEntry {
  ts: string;
  trigger_reason: string;
  task_type: string;
  selected_via_pattern: string[];
  selected_via_keyword: string[];
  selected_via_llm: string[];
  duration_ms: number;
  digest_chars: number;
  watermark_uuid: string | null;
}
