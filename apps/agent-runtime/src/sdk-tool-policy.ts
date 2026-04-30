export const GEE_HOST_SDK_TOOLS = [
  "mcp__gee__app_open_surface",
  "mcp__gee__gear_list_capabilities",
  "mcp__gee__gear_invoke",
];

export const DEFAULT_SDK_AVAILABLE_TOOLS = [
  "Bash",
  "BashOutput",
  "Edit",
  "Glob",
  "Grep",
  "KillBash",
  "LS",
  "MultiEdit",
  "Read",
  "Write",
  ...GEE_HOST_SDK_TOOLS,
];

export const DEFAULT_SDK_AUTO_APPROVE_TOOLS = [
  "Read",
  "Glob",
  "Grep",
  "LS",
  "BashOutput",
  "KillBash",
  ...GEE_HOST_SDK_TOOLS,
];

export const DEFAULT_SDK_DISALLOWED_TOOLS = [
  "TodoWrite",
  "Skill",
  "Agent",
  "Task",
  "RemoteTrigger",
  "WebSearch",
  "WebFetch",
];

export function isGeeHostSdkTool(toolName: string): boolean {
  return GEE_HOST_SDK_TOOLS.includes(toolName);
}
