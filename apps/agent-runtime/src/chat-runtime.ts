import { existsSync, statSync } from "node:fs";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { parse as parseToml, stringify as stringifyToml } from "smol-toml";

const MODEL_ROUTING_FILE_NAME = "model-routing.toml";
const CHAT_RUNTIME_FILE_NAME = "chat-runtime.toml";
const CHAT_RUNTIME_SECRETS_FILE_NAME = "chat-runtime-secrets.toml";

type TomlRecord = Record<string, unknown>;

export type ChatProviderConfig = {
  enabled: boolean;
  api_key_env: string;
  chat_completions_url: string;
  model_discovery_url: string;
  image_generations_url?: string;
  video_generations_url?: string;
  task_retrieval_url?: string;
  storage_upload_url?: string;
  model_override_env: string;
  default_model: string;
};

export type ChatRuntimeConfig = {
  version: number;
  request_timeout_seconds: number;
  temperature: number;
  max_completion_tokens: number;
  providers: Record<string, ChatProviderConfig>;
};

export type ChatProviderSecrets = {
  api_key?: string;
  model_override?: string;
};

export type ChatRuntimeSecretsConfig = {
  version: number;
  providers: Record<string, ChatProviderSecrets>;
};

export type ChatReadiness = {
  status: string;
  active_provider?: string | null;
  detail: string;
};

export type XenodiaGatewayBackend = {
  api_key: string;
  chat_completions_url: string;
  model: string;
  request_timeout_seconds: number;
  max_completion_tokens: number;
  temperature: number;
};

export type XenodiaMediaBackend = {
  api_key: string;
  image_generations_url: string;
  video_generations_url: string;
  task_retrieval_url: string;
  storage_upload_url?: string;
  request_timeout_seconds: number;
};

export type RouteClass = {
  provider: string;
  model: string;
  reasoning_effort: string;
};

type ContinuationConfig = {
  min_confidence_to_resume: number;
};

type ProfileRoutingPolicy = {
  default_route_class: string;
  upgrade_when: string[];
  downgrade_when: string[];
};

type TaskTypeRoutingPolicy = {
  default_profile: string;
  default_route_class: string;
};

export type RoutingConfig = {
  version?: number;
  default_route_class: string;
  allow_user_overrides: boolean;
  continuation: ContinuationConfig;
  route_classes: Record<string, RouteClass>;
  profiles: Record<string, ProfileRoutingPolicy>;
  task_types: Record<string, TaskTypeRoutingPolicy>;
};

export type RouteClassSetting = {
  name: string;
  provider: string;
  model: string;
  reasoningEffort: string;
};

export type ProfileRouteSetting = {
  name: string;
  defaultRouteClass: string;
};

export type ChatRoutingSettings = {
  defaultRouteClass: string;
  allowUserOverrides: boolean;
  providerChoices: string[];
  routeClasses: RouteClassSetting[];
  profiles: ProfileRouteSetting[];
};

function repoRoot(): string {
  const configuredRoot = process.env.GEEAGENT_REPO_ROOT?.trim();
  if (configuredRoot) {
    return resolve(configuredRoot);
  }

  const currentDir = dirname(fileURLToPath(import.meta.url));
  return discoverRepoRoot(currentDir) ?? resolve(currentDir, "../../..");
}

function discoverRepoRoot(startingDirectory: string): string | undefined {
  let candidate = resolve(startingDirectory);
  for (let index = 0; index < 14; index += 1) {
    if (
      isDirectory(resolve(candidate, "apps", "agent-runtime")) &&
      isDirectory(resolve(candidate, "config"))
    ) {
      return candidate;
    }
    const parent = dirname(candidate);
    if (parent === candidate) {
      break;
    }
    candidate = parent;
  }
  return undefined;
}

function isDirectory(path: string): boolean {
  try {
    return existsSync(path) && statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function defaultConfigPath(fileName: string): string {
  return resolve(repoRoot(), "config", fileName);
}

function embeddedDefaultConfigText(fileName: string): string | undefined {
  if (fileName === MODEL_ROUTING_FILE_NAME) {
    return process.env.GEEAGENT_DEFAULT_MODEL_ROUTING_TOML;
  }
  if (fileName === CHAT_RUNTIME_FILE_NAME) {
    return process.env.GEEAGENT_DEFAULT_CHAT_RUNTIME_TOML;
  }
  return undefined;
}

async function fileExists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

function isRecord(value: unknown): value is TomlRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireRecord(value: unknown, path: string): TomlRecord {
  if (!isRecord(value)) {
    throw new Error(`${path} must be a table`);
  }
  return value;
}

function requireString(value: unknown, path: string): string {
  if (typeof value !== "string") {
    throw new Error(`${path} must be a string`);
  }
  return value;
}

function optionalString(value: unknown, path: string): string | undefined {
  if (value === undefined) {
    return undefined;
  }
  return requireString(value, path);
}

function requireBoolean(value: unknown, path: string): boolean {
  if (typeof value !== "boolean") {
    throw new Error(`${path} must be a boolean`);
  }
  return value;
}

function requireNumber(value: unknown, path: string): number {
  if (typeof value !== "number" || Number.isNaN(value)) {
    throw new Error(`${path} must be a number`);
  }
  return value;
}

function optionalNumber(value: unknown, path: string): number | undefined {
  if (value === undefined) {
    return undefined;
  }
  return requireNumber(value, path);
}

function optionalStringArray(value: unknown, path: string): string[] {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    throw new Error(`${path} must be an array of strings`);
  }
  return [...value];
}

function parseTomlRecord(raw: string, fileName: string): TomlRecord {
  return requireRecord(parseToml(raw), fileName);
}

async function loadConfigText(
  configDir: string | undefined,
  fileName: string,
): Promise<string> {
  const envConfigDir = process.env.GEEAGENT_CONFIG_DIR?.trim();
  if (envConfigDir) {
    const envPath = resolve(envConfigDir, fileName);
    if (await fileExists(envPath)) {
      return readFile(envPath, "utf8");
    }
  }

  if (configDir) {
    const overridePath = resolve(configDir, fileName);
    if (await fileExists(overridePath)) {
      return readFile(overridePath, "utf8");
    }
  }

  const embeddedDefault = embeddedDefaultConfigText(fileName);
  if (embeddedDefault !== undefined) {
    return embeddedDefault;
  }

  return readFile(defaultConfigPath(fileName), "utf8");
}

async function loadOptionalConfigText(
  configDir: string | undefined,
  fileName: string,
): Promise<string | undefined> {
  const envConfigDir = process.env.GEEAGENT_CONFIG_DIR?.trim();
  if (envConfigDir) {
    const envPath = resolve(envConfigDir, fileName);
    if (await fileExists(envPath)) {
      return readFile(envPath, "utf8");
    }
  }

  if (configDir) {
    const overridePath = resolve(configDir, fileName);
    if (await fileExists(overridePath)) {
      return readFile(overridePath, "utf8");
    }
  }

  return undefined;
}

export async function loadRoutingConfig(
  configDir?: string,
): Promise<RoutingConfig> {
  const raw = await loadConfigText(configDir, MODEL_ROUTING_FILE_NAME);
  return parseRoutingConfig(raw);
}

export async function loadChatRuntimeConfig(
  configDir?: string,
): Promise<ChatRuntimeConfig> {
  const raw = await loadConfigText(configDir, CHAT_RUNTIME_FILE_NAME);
  return parseChatRuntimeConfig(raw);
}

export async function loadChatRuntimeSecretsConfig(
  configDir?: string,
): Promise<ChatRuntimeSecretsConfig> {
  const raw = await loadOptionalConfigText(
    configDir,
    CHAT_RUNTIME_SECRETS_FILE_NAME,
  );
  if (raw === undefined) {
    return { version: 1, providers: {} };
  }
  return parseChatRuntimeSecretsConfig(raw);
}

export function parseRoutingConfig(raw: string): RoutingConfig {
  const value = parseTomlRecord(raw, MODEL_ROUTING_FILE_NAME);
  const continuation = requireRecord(value.continuation, "continuation");
  const routeClassesRaw = requireRecord(value.route_classes, "route_classes");
  const profilesRaw = requireRecord(value.profiles, "profiles");
  const taskTypesRaw = isRecord(value.task_types) ? value.task_types : {};

  const routing: RoutingConfig = {
    version: optionalNumber(value.version, "version"),
    default_route_class: requireString(
      value.default_route_class,
      "default_route_class",
    ),
    allow_user_overrides: requireBoolean(
      value.allow_user_overrides,
      "allow_user_overrides",
    ),
    continuation: {
      min_confidence_to_resume: requireNumber(
        continuation.min_confidence_to_resume,
        "continuation.min_confidence_to_resume",
      ),
    },
    route_classes: {},
    profiles: {},
    task_types: {},
  };

  for (const [name, routeClassRaw] of Object.entries(routeClassesRaw)) {
    const routeClass = requireRecord(routeClassRaw, `route_classes.${name}`);
      routing.route_classes[name] = {
        provider: requireString(
          routeClass.provider,
          `route_classes.${name}.provider`,
        ),
        model: requireString(routeClass.model, `route_classes.${name}.model`),
        reasoning_effort: requireString(
          routeClass.reasoning_effort,
          `route_classes.${name}.reasoning_effort`,
        ),
      };
  }

  for (const [name, profileRaw] of Object.entries(profilesRaw)) {
    const profile = requireRecord(profileRaw, `profiles.${name}`);
    routing.profiles[name] = {
      default_route_class: requireString(
        profile.default_route_class,
        `profiles.${name}.default_route_class`,
      ),
      upgrade_when: optionalStringArray(
        profile.upgrade_when,
        `profiles.${name}.upgrade_when`,
      ),
      downgrade_when: optionalStringArray(
        profile.downgrade_when,
        `profiles.${name}.downgrade_when`,
      ),
    };
  }

  for (const [name, taskTypeRaw] of Object.entries(taskTypesRaw)) {
    const taskType = requireRecord(taskTypeRaw, `task_types.${name}`);
    routing.task_types[name] = {
      default_profile: requireString(
        taskType.default_profile,
        `task_types.${name}.default_profile`,
      ),
      default_route_class: requireString(
        taskType.default_route_class,
        `task_types.${name}.default_route_class`,
      ),
    };
  }

  validateRoutingConfig(routing);
  return routing;
}

export function parseChatRuntimeConfig(raw: string): ChatRuntimeConfig {
  const value = parseTomlRecord(raw, CHAT_RUNTIME_FILE_NAME);
  const providersRaw = requireRecord(value.providers, "providers");
  const providers: Record<string, ChatProviderConfig> = {};

  for (const [name, providerRaw] of Object.entries(providersRaw)) {
    const provider = requireRecord(providerRaw, `providers.${name}`);
    providers[name] = {
      enabled: requireBoolean(provider.enabled, `providers.${name}.enabled`),
      api_key_env: requireString(
        provider.api_key_env,
        `providers.${name}.api_key_env`,
      ),
      chat_completions_url: requireString(
        provider.chat_completions_url,
        `providers.${name}.chat_completions_url`,
      ),
      model_discovery_url: requireString(
        provider.model_discovery_url,
        `providers.${name}.model_discovery_url`,
      ),
      image_generations_url: optionalString(
        provider.image_generations_url,
        `providers.${name}.image_generations_url`,
      ),
      video_generations_url: optionalString(
        provider.video_generations_url,
        `providers.${name}.video_generations_url`,
      ),
      task_retrieval_url: optionalString(
        provider.task_retrieval_url,
        `providers.${name}.task_retrieval_url`,
      ),
      storage_upload_url: optionalString(
        provider.storage_upload_url,
        `providers.${name}.storage_upload_url`,
      ),
      model_override_env: requireString(
        provider.model_override_env,
        `providers.${name}.model_override_env`,
      ),
      default_model: requireString(
        provider.default_model,
        `providers.${name}.default_model`,
      ),
    };
  }

  return {
    version: requireNumber(value.version, "version"),
    request_timeout_seconds: requireNumber(
      value.request_timeout_seconds,
      "request_timeout_seconds",
    ),
    temperature: requireNumber(value.temperature, "temperature"),
    max_completion_tokens: requireNumber(
      value.max_completion_tokens,
      "max_completion_tokens",
    ),
    providers,
  };
}

export function parseChatRuntimeSecretsConfig(
  raw: string,
): ChatRuntimeSecretsConfig {
  const value = parseTomlRecord(raw, CHAT_RUNTIME_SECRETS_FILE_NAME);
  const providersRaw = isRecord(value.providers) ? value.providers : {};
  const providers: Record<string, ChatProviderSecrets> = {};

  for (const [name, providerRaw] of Object.entries(providersRaw)) {
    const provider = requireRecord(providerRaw, `providers.${name}`);
    const apiKey =
      provider.api_key === undefined
        ? undefined
        : requireString(provider.api_key, `providers.${name}.api_key`);
    const modelOverride =
      provider.model_override === undefined
        ? undefined
        : requireString(
            provider.model_override,
            `providers.${name}.model_override`,
          );
    providers[name] = {
      ...(apiKey === undefined ? {} : { api_key: apiKey }),
      ...(modelOverride === undefined ? {} : { model_override: modelOverride }),
    };
  }

  return {
    version: optionalNumber(value.version, "version") ?? 1,
    providers,
  };
}

function validateRoutingConfig(routing: RoutingConfig): void {
  if (!routing.route_classes[routing.default_route_class]) {
    throw new Error(
      `default_route_class \`${routing.default_route_class}\` must reference a defined route class`,
    );
  }

  for (const [profileName, profile] of Object.entries(routing.profiles)) {
    if (!routing.route_classes[profile.default_route_class]) {
      throw new Error(
        `profile \`${profileName}\` default_route_class \`${profile.default_route_class}\` must reference a defined route class`,
      );
    }
  }

  for (const [taskTypeName, taskType] of Object.entries(routing.task_types)) {
    if (!routing.profiles[taskType.default_profile]) {
      throw new Error(
        `task_type \`${taskTypeName}\` default_profile \`${taskType.default_profile}\` must reference a defined profile`,
      );
    }
    if (!routing.route_classes[taskType.default_route_class]) {
      throw new Error(
        `task_type \`${taskTypeName}\` default_route_class \`${taskType.default_route_class}\` must reference a defined route class`,
      );
    }
  }
}

export function chatRoutingSettingsFromConfig(
  routing: RoutingConfig,
  chatRuntime: ChatRuntimeConfig,
): ChatRoutingSettings {
  return {
    defaultRouteClass: routing.default_route_class,
    allowUserOverrides: routing.allow_user_overrides,
    providerChoices: Object.keys(chatRuntime.providers).sort(),
    routeClasses: Object.entries(routing.route_classes)
      .map(([name, routeClass]) => ({
        name,
        provider: routeClass.provider,
        model: routeClass.model,
        reasoningEffort: routeClass.reasoning_effort,
      }))
      .sort((left, right) => left.name.localeCompare(right.name)),
    profiles: Object.entries(routing.profiles)
      .map(([name, profile]) => ({
        name,
        defaultRouteClass: profile.default_route_class,
      }))
      .sort((left, right) => left.name.localeCompare(right.name)),
  };
}

export async function loadChatRoutingSettings(
  configDir?: string,
): Promise<ChatRoutingSettings> {
  const [routing, chatRuntime] = await Promise.all([
    loadRoutingConfig(configDir),
    loadChatRuntimeConfig(configDir),
  ]);
  return chatRoutingSettingsFromConfig(routing, chatRuntime);
}

function resolveRouteClass(
  routing: RoutingConfig,
  profileName = "main",
): RouteClass {
  const profile = routing.profiles[profileName];
  if (!profile) {
    throw new Error(`profile \`${profileName}\` is not defined in model routing`);
  }

  const routeClass = routing.route_classes[profile.default_route_class];
  if (!routeClass) {
    throw new Error(
      `route class \`${profile.default_route_class}\` is not defined in model routing`,
    );
  }

  return routeClass;
}

function nonEmptyTrimmed(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function resolveProvider(
  routeClass: RouteClass,
  chatRuntime: ChatRuntimeConfig,
  secrets: ChatRuntimeSecretsConfig,
  environment: NodeJS.ProcessEnv = process.env,
): { name: string; apiKey: string; chatCompletionsUrl: string; model: string } {
  const providerName = routeClass.provider.toLowerCase();
  const providerConfig = chatRuntime.providers[providerName];
  if (!providerConfig?.enabled) {
    throw new Error(`chat provider \`${providerName}\` is not enabled`);
  }

  const providerSecrets = secrets.providers[providerName];
  const apiKey =
    nonEmptyTrimmed(environment[providerConfig.api_key_env]) ??
    nonEmptyTrimmed(providerSecrets?.api_key);
  if (!apiKey) {
    throw new Error(
      `chat provider \`${providerName}\` is missing an API key. Expected ${providerConfig.api_key_env} or a saved ${providerName} key`,
    );
  }

  const configuredModel =
    nonEmptyTrimmed(environment[providerConfig.model_override_env]) ??
    nonEmptyTrimmed(providerSecrets?.model_override);
  return {
    name: providerName,
    apiKey,
    chatCompletionsUrl: providerConfig.chat_completions_url,
    model: configuredModel ?? routeClass.model,
  };
}

export async function loadChatReadiness(
  configDir?: string,
): Promise<ChatReadiness> {
  const [routing, chatRuntime, secrets] = await Promise.all([
    loadRoutingConfig(configDir),
    loadChatRuntimeConfig(configDir),
    loadChatRuntimeSecretsConfig(configDir),
  ]);

  try {
    const routeClass = resolveRouteClass(routing);
    try {
      const provider = resolveProvider(routeClass, chatRuntime, secrets);
      return {
        status: "live",
        active_provider: provider.name,
        detail: `Live chat via ${provider.name}. Ready for workspace chat and quick replies.`,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (message.includes("API key") || message.includes("not configured")) {
        return {
          status: "needs_setup",
          active_provider: null,
          detail: "Live chat is waiting for provider configuration.",
        };
      }
      return {
        status: "degraded",
        active_provider: null,
        detail: `Chat runtime is degraded. ${message}`,
      };
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      status: "degraded",
      active_provider: null,
      detail: `Chat routing is degraded. ${message}`,
    };
  }
}

export async function loadXenodiaGatewayBackend(
  configDir?: string,
): Promise<XenodiaGatewayBackend> {
  const [routing, chatRuntime, secrets] = await Promise.all([
    loadRoutingConfig(configDir),
    loadChatRuntimeConfig(configDir),
    loadChatRuntimeSecretsConfig(configDir),
  ]);

  const providerName = "xenodia";
  const providerConfig = chatRuntime.providers[providerName];
  if (!providerConfig) {
    throw new Error("xenodia provider is not defined in chat runtime config");
  }
  if (!providerConfig.enabled) {
    throw new Error("xenodia provider is disabled in chat runtime config");
  }

  const providerSecrets = secrets.providers[providerName];
  const apiKey =
    nonEmptyTrimmed(process.env[providerConfig.api_key_env]) ??
    nonEmptyTrimmed(providerSecrets?.api_key);
  if (!apiKey) {
    throw new Error(
      `xenodia provider is missing an API key. Expected ${providerConfig.api_key_env} or a saved xenodia key`,
    );
  }

  let routedModel: string | undefined;
  try {
    const routeClass = resolveRouteClass(routing);
    if (routeClass.provider.toLowerCase() === providerName) {
      routedModel = routeClass.model;
    }
  } catch {
    routedModel = undefined;
  }

  const model =
    nonEmptyTrimmed(process.env[providerConfig.model_override_env]) ??
    nonEmptyTrimmed(providerSecrets?.model_override) ??
    routedModel ??
    providerConfig.default_model;

  return {
    api_key: apiKey,
    chat_completions_url: providerConfig.chat_completions_url,
    model,
    request_timeout_seconds: chatRuntime.request_timeout_seconds,
    max_completion_tokens: chatRuntime.max_completion_tokens,
    temperature: chatRuntime.temperature,
  };
}

export async function loadXenodiaMediaBackend(
  configDir?: string,
): Promise<XenodiaMediaBackend> {
  const [chatRuntime, secrets] = await Promise.all([
    loadChatRuntimeConfig(configDir),
    loadChatRuntimeSecretsConfig(configDir),
  ]);

  const providerName = "xenodia";
  const providerConfig = chatRuntime.providers[providerName];
  if (!providerConfig) {
    throw new Error("xenodia provider is not defined in chat runtime config");
  }
  if (!providerConfig.enabled) {
    throw new Error("xenodia provider is disabled in chat runtime config");
  }

  const providerSecrets = secrets.providers[providerName];
  const apiKey =
    nonEmptyTrimmed(process.env[providerConfig.api_key_env]) ??
    nonEmptyTrimmed(providerSecrets?.api_key);
  if (!apiKey) {
    throw new Error(
      `xenodia provider is missing an API key. Expected ${providerConfig.api_key_env} or a saved xenodia key`,
    );
  }

  return {
    api_key: apiKey,
    image_generations_url:
      providerConfig.image_generations_url ??
      "https://api.xenodia.xyz/v1/images/generations",
    video_generations_url:
      providerConfig.video_generations_url ??
      "https://api.xenodia.xyz/v1/videos/generations",
    task_retrieval_url:
      providerConfig.task_retrieval_url ?? "https://api.xenodia.xyz/v1/tasks",
    ...(providerConfig.storage_upload_url
      ? { storage_upload_url: providerConfig.storage_upload_url }
      : {}),
    request_timeout_seconds: chatRuntime.request_timeout_seconds,
  };
}

function validateChatRoutingSettings(
  settings: ChatRoutingSettings,
  chatRuntime: ChatRuntimeConfig,
): void {
  if (settings.routeClasses.length === 0) {
    throw new Error("at least one route class is required");
  }

  const providerChoices = new Set(Object.keys(chatRuntime.providers));
  const routeClassNames = new Set<string>();
  for (const routeClass of settings.routeClasses) {
    if (!routeClass.name.trim()) {
      throw new Error("route class names cannot be empty");
    }
    if (!routeClass.model.trim()) {
      throw new Error(`route class \`${routeClass.name}\` requires a model`);
    }
    if (!providerChoices.has(routeClass.provider)) {
      throw new Error(
        `route class \`${routeClass.name}\` references unknown provider \`${routeClass.provider}\``,
      );
    }
    if (routeClassNames.has(routeClass.name)) {
      throw new Error("route class names must be unique");
    }
    routeClassNames.add(routeClass.name);
  }

  if (!routeClassNames.has(settings.defaultRouteClass)) {
    throw new Error("default route class must reference a defined route class");
  }

  const profileNames = new Set<string>();
  for (const profile of settings.profiles) {
    if (!profile.name.trim()) {
      throw new Error("profile names cannot be empty");
    }
    if (!routeClassNames.has(profile.defaultRouteClass)) {
      throw new Error(
        `profile \`${profile.name}\` references unknown route class \`${profile.defaultRouteClass}\``,
      );
    }
    if (profileNames.has(profile.name)) {
      throw new Error("profile names must be unique");
    }
    profileNames.add(profile.name);
  }
}

export async function persistChatRoutingSettings(
  configDir: string,
  settings: ChatRoutingSettings,
): Promise<void> {
  await mkdir(configDir, { recursive: true });
  const [routing, chatRuntime] = await Promise.all([
    loadRoutingConfig(configDir),
    loadChatRuntimeConfig(configDir),
  ]);

  validateChatRoutingSettings(settings, chatRuntime);

  routing.default_route_class = settings.defaultRouteClass;
  routing.allow_user_overrides = settings.allowUserOverrides;
  routing.route_classes = Object.fromEntries(
    settings.routeClasses.map((routeClass) => [
      routeClass.name,
      {
        provider: routeClass.provider,
        model: routeClass.model,
        reasoning_effort: routeClass.reasoningEffort,
      },
    ]),
  );

  for (const profile of settings.profiles) {
    const existingProfile = routing.profiles[profile.name];
    if (!existingProfile) {
      throw new Error(
        `profile \`${profile.name}\` is not defined in the current routing config`,
      );
    }
    existingProfile.default_route_class = profile.defaultRouteClass;
  }

  validateRoutingConfig(routing);
  await writeFile(
    resolve(configDir, MODEL_ROUTING_FILE_NAME),
    stringifyToml(routing),
    "utf8",
  );
}
