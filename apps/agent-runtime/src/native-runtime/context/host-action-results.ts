import type { RuntimeHostActionCompletion } from "../../protocol.js";
import {
  materializeToolResult,
  type ToolArtifactRef,
} from "./tool-artifacts.js";

export type ModelHostActionCompletion = {
  host_action_id: string;
  tool_id: string;
  status: "succeeded" | "failed";
  summary?: string;
  error?: string;
  result?: unknown;
  result_artifact?: ModelHostActionArtifactRef;
};

export type ModelHostActionArtifactRef = {
  artifact_id: string;
  path: string;
  sha256: string;
  byte_count: number;
  token_estimate: number;
  mime_type: string;
  summary: string;
};

export type PreparedHostActionCompletions = {
  completions: ModelHostActionCompletion[];
  artifacts: ToolArtifactRef[];
};

const HOST_ACTION_MAX_INLINE_BYTES = 8_000;
const HOST_ACTION_MAX_INLINE_TOKENS = 1_500;

export async function prepareHostActionCompletionsForModel(
  completions: RuntimeHostActionCompletion[],
  artifactRoot: string,
): Promise<PreparedHostActionCompletions> {
  const prepared: ModelHostActionCompletion[] = [];
  const artifacts: ToolArtifactRef[] = [];

  for (const completion of completions) {
    const modelCompletion = baseModelCompletion(completion);
    if (!completion.result_json) {
      prepared.push(modelCompletion);
      continue;
    }

    const parsed = parseHostActionResultJSON(completion.result_json);
    const materialized = await materializeToolResult({
      artifactRoot,
      invocationId: completion.host_action_id,
      toolName: completion.tool_id,
      status: completion.status,
      result: parsed.value,
      error: undefined,
      summary: completion.summary,
      mimeType: parsed.mimeType,
      maxInlineBytes: HOST_ACTION_MAX_INLINE_BYTES,
      maxInlineTokens: HOST_ACTION_MAX_INLINE_TOKENS,
    });

    if (materialized.artifact) {
      artifacts.push(materialized.artifact);
      prepared.push({
        ...modelCompletion,
        result_artifact: modelArtifactRef(materialized.artifact),
      });
    } else {
      prepared.push({
        ...modelCompletion,
        result: parsed.value,
      });
    }
  }

  return { completions: prepared, artifacts };
}

function baseModelCompletion(
  completion: RuntimeHostActionCompletion,
): ModelHostActionCompletion {
  return {
    host_action_id: completion.host_action_id,
    tool_id: completion.tool_id,
    status: completion.status,
    ...(completion.summary ? { summary: completion.summary } : {}),
    ...(completion.error ? { error: completion.error } : {}),
  };
}

function parseHostActionResultJSON(raw: string): {
  value: unknown;
  mimeType: string;
} {
  try {
    return { value: JSON.parse(raw), mimeType: "application/json" };
  } catch {
    return { value: raw, mimeType: "text/plain" };
  }
}

function modelArtifactRef(artifact: ToolArtifactRef): ModelHostActionArtifactRef {
  return {
    artifact_id: artifact.artifact_id,
    path: artifact.path,
    sha256: artifact.sha256,
    byte_count: artifact.byteCount,
    token_estimate: artifact.tokenEstimate,
    mime_type: artifact.mimeType,
    summary: artifact.summary,
  };
}

export const __hostActionResultsTestHooks = {
  parseHostActionResultJSON,
};
