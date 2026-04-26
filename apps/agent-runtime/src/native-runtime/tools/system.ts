import { argError, errorMessage, getStringArg } from "./args.js";
import { applescriptStringLiteral, runProcess } from "./process.js";
import type { ToolOutcome, ToolRequest } from "./types.js";

export async function clipboardRead(request: ToolRequest): Promise<ToolOutcome> {
  try {
    const result = await runProcess("pbpaste", []);
    if (result.exitCode === 0) {
      return {
        kind: "completed",
        tool_id: request.tool_id,
        payload: { text: result.stdout },
      };
    }
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "clipboard.read_failed",
      message: `pbpaste exited with ${result.exitCode}: ${result.stderr}`,
    };
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "clipboard.spawn_failed",
      message: errorMessage(error),
    };
  }
}

export async function clipboardWrite(request: ToolRequest): Promise<ToolOutcome> {
  const text = getStringArg(request, "text");
  if (text === undefined) {
    return argError(request.tool_id, "text", "required string `text` is missing");
  }
  try {
    const result = await runProcess("pbcopy", [], { input: text });
    if (result.exitCode === 0) {
      return {
        kind: "completed",
        tool_id: request.tool_id,
        payload: { bytes_written: Buffer.byteLength(text) },
      };
    }
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "clipboard.write_failed",
      message: `pbcopy exited with ${result.exitCode}`,
    };
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "clipboard.spawn_failed",
      message: errorMessage(error),
    };
  }
}

export async function urlOpen(request: ToolRequest): Promise<ToolOutcome> {
  const url = getStringArg(request, "url");
  if (url === undefined) {
    return argError(request.tool_id, "url", "required string `url` is missing");
  }
  if (!(url.startsWith("http://") || url.startsWith("https://") || url.startsWith("mailto:"))) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "url.scheme_not_allowed",
      message: `url \`${url}\` must start with http://, https://, or mailto: in v1`,
    };
  }
  try {
    const result = await runProcess("open", [url]);
    if (result.exitCode === 0) {
      return {
        kind: "completed",
        tool_id: request.tool_id,
        payload: { url },
      };
    }
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "url.open_failed",
      message: `\`open\` exited with ${result.exitCode}`,
    };
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "url.spawn_failed",
      message: errorMessage(error),
    };
  }
}

export async function notifyPost(request: ToolRequest): Promise<ToolOutcome> {
  const title = getStringArg(request, "title");
  if (title === undefined) {
    return argError(request.tool_id, "title", "required string `title` is missing");
  }
  const body = getStringArg(request, "body") ?? "";
  const script = `display notification ${applescriptStringLiteral(
    body,
  )} with title ${applescriptStringLiteral(title)}`;
  try {
    const result = await runProcess("osascript", ["-e", script]);
    if (result.exitCode === 0) {
      return {
        kind: "completed",
        tool_id: request.tool_id,
        payload: { title, body },
      };
    }
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "notify.osascript_failed",
      message: `osascript exited with ${result.exitCode}`,
    };
  } catch (error) {
    return {
      kind: "error",
      tool_id: request.tool_id,
      code: "notify.spawn_failed",
      message: errorMessage(error),
    };
  }
}
