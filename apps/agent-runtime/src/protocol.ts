export type RuntimeHostActionIntent = {
  host_action_id: string;
  tool_id: string;
  arguments?: Record<string, unknown>;
};

export type RuntimeHostActionCompletion = {
  host_action_id: string;
  tool_id: string;
  status: "succeeded" | "failed";
  summary?: string;
  error?: string;
  result_json?: string;
};

export type RuntimeContext = {
  localTime?: string;
  timezone?: string;
  surface?: string;
  cwd?: string;
  approvalPosture?: string;
  capabilities?: string[];
};

export type RuntimeCommand =
  | {
      type: "runtime.init";
      defaultModel?: string;
    }
  | {
      type: "session.create";
      sessionId: string;
      cwd?: string;
      model?: string;
      maxTurns?: number;
      systemPrompt?: string;
      runtimeContext?: RuntimeContext;
      availableTools?: string[];
      autoApproveTools?: string[];
      disallowedTools?: string[];
    }
  | {
      type: "session.send";
      sessionId: string;
      content: string;
    }
  | {
      type: "session.approval";
      sessionId: string;
      requestId: string;
      decision: "allow" | "deny";
      message?: string;
      updatedInput?: Record<string, unknown>;
    }
  | {
      type: "session.close";
      sessionId: string;
    }
  | {
      type: "runtime.shutdown";
    };

export type RuntimeEvent =
  | {
      type: "runtime.ready";
      protocolVersion: string;
      pid: number;
    }
  | {
      type: "runtime.initialized";
      defaultModel?: string;
    }
  | {
      type: "session.created";
      sessionId: string;
      model: string;
      cwd: string;
    }
  | {
      type: "session.system";
      sessionId: string;
      subtype?: string;
      sessionSdkId?: string;
      raw: unknown;
    }
  | {
      type: "session.assistant_text";
      sessionId: string;
      text: string;
      raw: unknown;
    }
  | {
      type: "session.tool_use";
      sessionId: string;
      toolUseId: string;
      toolName: string;
      input: unknown;
      raw: unknown;
    }
  | {
      type: "session.tool_result";
      sessionId: string;
      toolUseId: string;
      status: "succeeded" | "failed";
      summary?: string;
      error?: string;
      raw: unknown;
    }
  | {
      type: "session.user";
      sessionId: string;
      raw: unknown;
    }
  | {
      type: "session.result";
      sessionId: string;
      subtype?: string;
      durationMs?: number;
      totalCostUsd?: number;
      result?: string;
      raw: unknown;
    }
  | {
      type: "session.approval_requested";
      sessionId: string;
      requestId: string;
      toolName: string;
      input: unknown;
    }
  | {
      type: "session.host_action_requested";
      sessionId: string;
      hostAction: RuntimeHostActionIntent;
    }
  | {
      type: "session.closed";
      sessionId: string;
    }
  | {
      type: "session.error";
      sessionId?: string;
      error: string;
    };
