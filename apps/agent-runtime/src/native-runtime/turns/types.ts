import type { AgentProfile } from "../store/types.js";

export type TurnReplayCursor = {
  sessionId: string;
  userMessageId: string;
  stepCount: number;
};

export type PreparedTurnContext = {
  activeAgentProfile: AgentProfile;
  workspaceMessages: Array<{ role: string; content: string }>;
  shouldReuseActiveConversation: boolean;
};

export type JsonRecord = Record<string, unknown>;
