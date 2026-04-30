export type ModelFacingMessage = {
  role: string;
  content: string;
};

export type ContextProjectionMode = "latest_only" | "full_recent" | "compacted";

export type ContextProjectionOptions = {
  maxContextTokens?: number;
  reservedOutputTokens?: number;
  recentTokenBudget?: number;
  compactTriggerTokens?: number;
  latestUserRequest: string;
};

export type ContextProjection = {
  mode: ContextProjectionMode;
  messages: ModelFacingMessage[];
  compactedMessagesCount: number;
  rawHistoryTokens: number;
  projectedHistoryTokens: number;
  recentTokens: number;
  summaryTokens: number;
  latestRequestTokens: number;
  estimatedInputTokens: number;
  maxContextTokens: number;
  reservedOutputTokens: number;
};

export type ContextBudgetRecord = {
  max_tokens: number;
  used_tokens: number;
  reserved_output_tokens: number;
  usage_ratio: number;
  estimate_source: "estimated";
  summary_state: "watching" | "projecting";
  next_summary_at_ratio: number;
  compacted_messages_count: number;
  projection_mode: ContextProjectionMode;
  raw_history_tokens: number;
  projected_history_tokens: number;
  recent_tokens: number;
  summary_tokens: number;
  latest_request_tokens: number;
};
