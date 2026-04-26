import { hasValidApprovalToken } from "./tools/args.js";
import { TOOL_SPECS } from "./tools/catalog.js";
import { coreFind, coreGrep, coreLs, filesEditText, filesReadText, filesWriteText } from "./tools/files.js";
import { geeGearInvoke, geeGearListCapabilities } from "./tools/gears.js";
import { geeAppOpenSurface, navigateOpenModule, navigateOpenSection } from "./tools/navigation.js";
import { shellRequestNeedsApproval, shellRun } from "./tools/shell.js";
import { clipboardRead, clipboardWrite, notifyPost, urlOpen } from "./tools/system.js";
import type { ToolOutcome, ToolRequest } from "./tools/types.js";

export type { ToolBlastRadius, ToolOutcome, ToolRequest } from "./tools/types.js";

export async function invokeTool(request: ToolRequest): Promise<ToolOutcome> {
  const gate = preExecutionGate(request);
  if (gate) {
    return gate;
  }
  return runTool(request);
}

function preExecutionGate(request: ToolRequest): ToolOutcome | null {
  const spec = TOOL_SPECS.get(request.tool_id);
  if (!spec) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "tool.unknown",
      message: `\`${request.tool_id}\` is not a registered v1 tool`,
    };
  }

  if (!personaAllows(request.allowed_tool_ids, request.tool_id)) {
    return {
      kind: "denied",
      tool_id: request.tool_id,
      reason: `the active persona's allow-list does not include \`${request.tool_id}\``,
    };
  }

  const needsApproval =
    request.tool_id === "shell.run"
      ? shellRequestNeedsApproval(request)
      : spec.needsApproval;

  if (needsApproval && !hasValidApprovalToken(request.approval_token)) {
    return {
      kind: "needs_approval",
      tool_id: request.tool_id,
      blast_radius: spec.blastRadius,
      prompt: `"${spec.title}" requires your approval. Reason: ${spec.description}`,
    };
  }

  return null;
}

function personaAllows(allowList: string[] | undefined, toolID: string): boolean {
  return (
    allowList === undefined ||
    allowList.some((pattern) =>
      pattern.endsWith("*") ? toolID.startsWith(pattern.slice(0, -1)) : pattern === toolID,
    )
  );
}

async function runTool(request: ToolRequest): Promise<ToolOutcome> {
  switch (request.tool_id) {
    case "core.read":
    case "files.readText":
      return filesReadText(request);
    case "core.write":
    case "files.writeText":
      return filesWriteText(request);
    case "core.edit":
      return filesEditText(request);
    case "core.bash":
    case "shell.run":
      return shellRun(request);
    case "core.grep":
      return coreGrep(request);
    case "core.find":
      return coreFind(request);
    case "core.ls":
      return coreLs(request);
    case "navigate.openSection":
    case "gee.app.openSection":
      return navigateOpenSection(request);
    case "navigate.openModule":
      return navigateOpenModule(request);
    case "gee.app.openSurface":
      return geeAppOpenSurface(request);
    case "gee.gear.listCapabilities":
      return geeGearListCapabilities(request);
    case "gee.gear.invoke":
      return geeGearInvoke(request);
    case "clipboard.read":
      return clipboardRead(request);
    case "clipboard.write":
      return clipboardWrite(request);
    case "url.open":
      return urlOpen(request);
    case "notify.post":
      return notifyPost(request);
    default:
      return {
        kind: "error",
        tool_id: request.tool_id,
        code: "tool.unknown",
        message: `no executor registered for tool \`${request.tool_id}\``,
      };
  }
}
