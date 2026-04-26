export type ToolBlastRadius = "safe" | "local" | "external";

export type ToolRequest = {
  tool_id: string;
  arguments?: Record<string, unknown>;
  allowed_tool_ids?: string[];
  approval_token?: string;
  files_root?: string;
};

export type ToolOutcome =
  | { kind: "completed"; tool_id: string; payload: Record<string, unknown> }
  | {
      kind: "needs_approval";
      tool_id: string;
      blast_radius: ToolBlastRadius;
      prompt: string;
    }
  | { kind: "denied"; tool_id: string; reason: string }
  | { kind: "error"; tool_id: string; code: string; message: string };

export type ToolSpec = {
  id: string;
  title: string;
  description: string;
  needsApproval: boolean;
  blastRadius: ToolBlastRadius;
};

export type ShellCommandPolicy = "allowed_no_approval" | "allowed_needs_approval" | "denied";
