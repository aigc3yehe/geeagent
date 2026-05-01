import {
  loadChatRoutingSettings,
  loadXenodiaMediaBackend,
  persistChatRoutingSettings,
  type ChatRoutingSettings,
} from "../chat-runtime.js";
import {
  codexExportStatus,
  describeCodexExportCapability,
  listCodexExportCapabilities,
  parseCodexExportOptions,
} from "./codex-export.js";
import {
  completeExternalInvocation,
  parseExternalInvocationCompletion,
} from "./codex-external-invocations.js";
import {
  generateCodexPluginPackage,
  parseCodexPluginGenerationOptions,
} from "./codex-plugin.js";
import { resolveConfigDir } from "./paths.js";
import {
  deleteAgentProfile,
  installAgentPack,
  reloadAgentProfile,
  setActiveAgentProfile,
} from "./store/agent-profiles.js";
import {
  activateConversation,
  createConversation,
  deleteConversation,
} from "./store/conversations.js";
import {
  deleteTerminalAccessRule,
} from "./store/terminal-permissions.js";
import {
  completeHostActionTurn,
  performTaskAction,
  submitQuickPrompt,
  submitRoutedWorkspaceMessage,
  submitWorkspaceMessage,
} from "./turns.js";
import type { RuntimeHostActionCompletion } from "../protocol.js";

import {
  loadRuntimeStore,
  loadSecurityPreferences,
  persistRuntimeStore,
  persistSecurityPreferences,
} from "./store/persistence.js";
import {
  addPersonaSkillSource,
  addSystemSkillSource,
  refreshPersonaSkillSources,
  removePersonaSkillSource,
  removePersonaSkillSourcesForProfile,
  removeSystemSkillSource,
} from "./store/skill-sources.js";
import { loadSnapshot, snapshotFromStore } from "./store/snapshot.js";
import type { RuntimeCommandContext } from "./protocol.js";
import { invokeTool, type ToolRequest } from "./tools.js";

export async function handleNativeRuntimeCommand(
  command: string,
  args: string[] = [],
  context: RuntimeCommandContext = {},
): Promise<string> {
  const configDir = resolveConfigDir(context.configDir);

  switch (command) {
    case "snapshot":
      assertArgCount(command, args, 0);
      return stringify(await loadSnapshot(configDir));
    case "list-agent-profiles": {
      assertArgCount(command, args, 0);
      const snapshot = await loadSnapshot(configDir);
      return stringify(snapshot.agent_profiles);
    }
    case "set-active-agent-profile":
      assertArgCount(command, args, 1);
      return mutateStore(configDir, async (store) => {
        await setActiveAgentProfile(store, configDir, args[0]);
      });
    case "install-agent-pack":
      assertArgCount(command, args, 1);
      return mutateStore(configDir, async (store) => {
        await installAgentPack(store, configDir, args[0]);
      });
    case "reload-agent-profile":
      assertArgCount(command, args, 1);
      return mutateStore(configDir, async (store) => {
        await reloadAgentProfile(store, configDir, args[0]);
        await refreshPersonaSkillSources(configDir, args[0]);
      });
    case "delete-agent-profile":
      assertArgCount(command, args, 1);
      return mutateStore(configDir, async (store) => {
        await deleteAgentProfile(store, configDir, args[0]);
        await removePersonaSkillSourcesForProfile(configDir, args[0]);
      });
    case "create-conversation":
      assertArgCount(command, args, 0);
      return mutateStore(configDir, (store) => {
        createConversation(store);
      });
    case "set-active-conversation":
      assertArgCount(command, args, 1);
      return mutateStore(configDir, (store) => {
        activateConversation(store, args[0]);
      });
    case "delete-conversation":
      assertArgCount(command, args, 1);
      return mutateStore(configDir, (store) => {
        deleteConversation(store, args[0]);
      });
    case "get-chat-routing-settings":
      assertArgCount(command, args, 0);
      return stringify(await loadChatRoutingSettings(configDir));
    case "get-xenodia-media-backend":
      assertArgCount(command, args, 0);
      return stringify(await loadXenodiaMediaBackend(configDir));
    case "save-chat-routing-settings":
      assertArgCount(command, args, 1);
      await persistChatRoutingSettings(configDir, parseSettings(args[0]));
      return stringify(await loadSnapshot(configDir));
    case "set-highest-authorization": {
      assertArgCount(command, args, 1);
      const current = await loadSecurityPreferences(configDir);
      await persistSecurityPreferences(configDir, {
        ...current,
        highest_authorization_enabled: parseBoolean(args[0]),
      });
      return stringify(await loadSnapshot(configDir));
    }
    case "delete-terminal-access-rule":
      assertArgCount(command, args, 1);
      await deleteTerminalAccessRule(configDir, args[0]);
      return stringify(await loadSnapshot(configDir));
    case "add-system-skill-source":
      assertArgCount(command, args, 1);
      await addSystemSkillSource(configDir, args[0]);
      return stringify(await loadSnapshot(configDir));
    case "remove-system-skill-source":
      assertArgCount(command, args, 1);
      await removeSystemSkillSource(configDir, args[0]);
      return stringify(await loadSnapshot(configDir));
    case "add-persona-skill-source":
      assertArgCount(command, args, 2);
      await requireKnownAgentProfile(configDir, args[0]);
      await addPersonaSkillSource(configDir, args[0], args[1]);
      return stringify(await loadSnapshot(configDir));
    case "remove-persona-skill-source":
      assertArgCount(command, args, 2);
      await removePersonaSkillSource(configDir, args[0], args[1]);
      return stringify(await loadSnapshot(configDir));
    case "submit-workspace-message":
      assertArgCount(command, args, 1);
      return stringify(await submitWorkspaceMessage(configDir, args[0]));
    case "submit-routed-workspace-message":
      assertArgCount(command, args, 1);
      return stringify(await submitRoutedWorkspaceMessage(configDir, args[0]));
    case "submit-quick-prompt":
      assertArgCount(command, args, 1);
      return stringify(await submitQuickPrompt(configDir, args[0]));
    case "perform-task-action":
      assertArgCount(command, args, 2);
      return stringify(await performTaskAction(configDir, args[0], args[1]));
    case "complete-host-action-turn":
      assertArgCount(command, args, 1);
      return stringify(await completeHostActionTurn(configDir, parseHostActionCompletions(args[0])));
    case "invoke-tool": {
      assertArgCount(command, args, 1);
      const request = parseToolRequest(args[0]);
      const store = await loadRuntimeStore(configDir);
      const activeProfile = store.agent_profiles.find(
        (profile) => profile.id === store.active_agent_profile_id,
      );
      request.allowed_tool_ids = activeProfile?.allowed_tool_ids;
      const security = await loadSecurityPreferences(configDir);
      if (
        security.highest_authorization_enabled &&
        request.approval_token?.trim()
      ) {
        // Keep the explicit frontend approval token intact.
      } else if (security.highest_authorization_enabled) {
        request.approval_token = "highest_authorization";
      }
      return stringify(await invokeTool(request));
    }
    case "codex-export-status":
      assertArgCount(command, args, 0);
      return stringify(codexExportStatus());
    case "codex-export-list-capabilities":
      assertArgCount(command, args, 1);
      return stringify(await listCodexExportCapabilities(parseCodexExportOptions(args[0])));
    case "codex-export-describe-capability":
      assertArgCount(command, args, 1);
      return stringify(await describeCodexExportCapability(parseCodexExportOptions(args[0])));
    case "codex-export-generate-plugin":
      assertArgCount(command, args, 1);
      return stringify(await generateCodexPluginPackage(parseCodexPluginGenerationOptions(args[0])));
    case "codex-external-invocation-complete":
      assertArgCount(command, args, 1);
      await completeExternalInvocation(configDir, parseExternalInvocationCompletion(args[0]));
      return stringify(await loadSnapshot(configDir));
    default:
      throw new Error("unsupported command or wrong argument count");
  }
}

async function requireKnownAgentProfile(
  configDir: string,
  profileId: string,
): Promise<void> {
  const store = await loadRuntimeStore(configDir);
  if (!store.agent_profiles.some((profile) => profile.id === profileId.trim())) {
    throw new Error(`unknown agent profile \`${profileId.trim()}\``);
  }
}

async function mutateStore(
  configDir: string,
  mutate: (store: Awaited<ReturnType<typeof loadRuntimeStore>>) => void | Promise<void>,
): Promise<string> {
  const store = await loadRuntimeStore(configDir);
  await mutate(store);
  await persistRuntimeStore(configDir, store);
  return stringify(await snapshotFromStore(store, configDir));
}

function parseHostActionCompletions(raw: string): RuntimeHostActionCompletion[] {
  const parsed = JSON.parse(raw) as unknown;
  if (!Array.isArray(parsed)) {
    throw new Error("host action completions JSON must be an array");
  }
  return parsed.map((item, index) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error(`host action completion at index ${index} must be an object`);
    }
    const record = item as Record<string, unknown>;
    if (typeof record.host_action_id !== "string" || !record.host_action_id.trim()) {
      throw new Error(`host action completion at index ${index} is missing host_action_id`);
    }
    if (typeof record.tool_id !== "string" || !record.tool_id.trim()) {
      throw new Error(`host action completion at index ${index} is missing tool_id`);
    }
    if (record.status !== "succeeded" && record.status !== "failed") {
      throw new Error(`host action completion at index ${index} has invalid status`);
    }
    return {
      host_action_id: record.host_action_id,
      tool_id: record.tool_id,
      status: record.status,
      summary: typeof record.summary === "string" ? record.summary : undefined,
      error: typeof record.error === "string" ? record.error : undefined,
      result_json: typeof record.result_json === "string" ? record.result_json : undefined,
    };
  });
}

function parseSettings(raw: string): ChatRoutingSettings {
  const parsed = JSON.parse(raw) as ChatRoutingSettings;
  if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.routeClasses)) {
    throw new Error("chat routing settings JSON is invalid");
  }
  return parsed;
}

function parseToolRequest(raw: string): ToolRequest {
  const parsed = JSON.parse(raw) as Partial<ToolRequest>;
  if (!parsed || typeof parsed !== "object" || typeof parsed.tool_id !== "string") {
    throw new Error("invalid tool request JSON: missing string `tool_id`");
  }
  return {
    tool_id: parsed.tool_id,
    arguments:
      parsed.arguments && typeof parsed.arguments === "object" && !Array.isArray(parsed.arguments)
        ? (parsed.arguments as Record<string, unknown>)
        : {},
    approval_token:
      typeof parsed.approval_token === "string" ? parsed.approval_token : undefined,
    files_root: typeof parsed.files_root === "string" ? parsed.files_root : undefined,
  };
}

function parseBoolean(raw: string): boolean {
  switch (raw.trim().toLowerCase()) {
    case "true":
    case "1":
    case "yes":
    case "on":
      return true;
    case "false":
    case "0":
    case "no":
    case "off":
      return false;
    default:
      throw new Error(`expected true or false, got \`${raw}\``);
  }
}

function assertArgCount(command: string, args: string[], expected: number): void {
  if (args.length !== expected) {
    throw new Error(`${command} expects ${expected} argument(s)`);
  }
}

function stringify(value: unknown): string {
  return `${JSON.stringify(value)}\n`;
}
