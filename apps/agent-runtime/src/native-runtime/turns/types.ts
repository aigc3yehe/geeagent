import type { AgentProfile } from "../store/types.js";
import type { ContextProjection } from "../context/types.js";

export type TurnReplayCursor = {
  sessionId: string;
  userMessageId: string;
  assistantMessageId: string;
  stepCount: number;
};

export type PreparedTurnContext = {
  activeAgentProfile: AgentProfile;
  workspaceMessages: Array<{ role: string; content: string }>;
  stageCapsuleMessages: Array<{ role: "assistant"; content: string }>;
  contextProjection: ContextProjection;
  shouldReuseActiveConversation: boolean;
};

export type JsonRecord = Record<string, unknown>;
