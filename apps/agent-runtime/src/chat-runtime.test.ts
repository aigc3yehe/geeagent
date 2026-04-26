import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import {
  loadChatReadiness,
  loadChatRoutingSettings,
  loadRoutingConfig,
  loadXenodiaGatewayBackend,
  persistChatRoutingSettings,
} from "./chat-runtime.js";

async function tempConfigDir(): Promise<string> {
  return mkdtemp(join(tmpdir(), "geeagent-chat-runtime-ts-"));
}

async function withCleanProviderEnv<T>(fn: () => Promise<T>): Promise<T> {
  const keys = [
    "OPENAI_API_KEY",
    "XENODIA_API_KEY",
    "GEEAGENT_OPENAI_MODEL",
    "GEEAGENT_XENODIA_MODEL",
  ];
  const previous = Object.fromEntries(
    keys.map((key) => [key, process.env[key]]),
  );
  for (const key of keys) {
    delete process.env[key];
  }

  try {
    return await fn();
  } finally {
    for (const key of keys) {
      const value = previous[key];
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

describe("chat runtime routing settings", () => {
  it("loads embedded default routing text without touching repo config files", async () => {
    const previousRoot = process.env.GEEAGENT_REPO_ROOT;
    const previousRouting = process.env.GEEAGENT_DEFAULT_MODEL_ROUTING_TOML;
    const previousRuntime = process.env.GEEAGENT_DEFAULT_CHAT_RUNTIME_TOML;

    process.env.GEEAGENT_REPO_ROOT = "/path/that/does/not/exist";
    process.env.GEEAGENT_DEFAULT_MODEL_ROUTING_TOML = `
version = 1
default_route_class = "balanced"
allow_user_overrides = true

[continuation]
min_confidence_to_resume = 0.85
fallback_action = "new_conversation"

[route_classes.balanced]
provider = "xenodia"
model = "gpt-5.4"
reasoning_effort = "medium"
fallback_model = "gpt-5.4-mini"

[profiles.main]
default_route_class = "balanced"
upgrade_when = []
downgrade_when = []

[task_types.conversation]
default_profile = "main"
default_route_class = "balanced"
`;
    process.env.GEEAGENT_DEFAULT_CHAT_RUNTIME_TOML = `
version = 1
request_timeout_seconds = 30
temperature = 0.3
max_completion_tokens = 600
fallback_provider_order = ["xenodia"]

[providers.xenodia]
enabled = true
api_key_env = "XENODIA_API_KEY"
chat_completions_url = "https://api.xenodia.xyz/v1/chat/completions"
model_discovery_url = "https://api.xenodia.xyz/v1/models"
model_override_env = "GEEAGENT_XENODIA_MODEL"
default_model = "gpt-5.4"
`;

    try {
      const settings = await loadChatRoutingSettings();

      assert.equal(settings.defaultRouteClass, "balanced");
      assert.deepEqual(settings.providerChoices, ["xenodia"]);
      assert.equal(settings.routeClasses[0]?.provider, "xenodia");
    } finally {
      if (previousRoot === undefined) {
        delete process.env.GEEAGENT_REPO_ROOT;
      } else {
        process.env.GEEAGENT_REPO_ROOT = previousRoot;
      }
      if (previousRouting === undefined) {
        delete process.env.GEEAGENT_DEFAULT_MODEL_ROUTING_TOML;
      } else {
        process.env.GEEAGENT_DEFAULT_MODEL_ROUTING_TOML = previousRouting;
      }
      if (previousRuntime === undefined) {
        delete process.env.GEEAGENT_DEFAULT_CHAT_RUNTIME_TOML;
      } else {
        process.env.GEEAGENT_DEFAULT_CHAT_RUNTIME_TOML = previousRuntime;
      }
    }
  });

  it("loads the default routing settings as Swift-compatible JSON fields", async () => {
    const configDir = await tempConfigDir();
    try {
      const settings = await loadChatRoutingSettings(configDir);

      assert.equal(settings.defaultRouteClass, "balanced");
      assert.equal(settings.allowUserOverrides, true);
      assert.deepEqual(settings.providerChoices, ["openai", "xenodia"]);
      assert.ok(
        settings.routeClasses.some(
          (routeClass) =>
            routeClass.name === "balanced" &&
            routeClass.provider === "openai" &&
            routeClass.reasoningEffort === "medium",
        ),
      );
      assert.ok(
        settings.profiles.some(
          (profile) =>
            profile.name === "main" &&
            profile.defaultRouteClass === "balanced",
        ),
      );
    } finally {
      await rm(configDir, { recursive: true, force: true });
    }
  });

  it("reports live readiness from saved provider secrets", async () => {
    const configDir = await tempConfigDir();
    try {
      await writeFile(
        join(configDir, "chat-runtime-secrets.toml"),
        `
version = 1

[providers.xenodia]
api_key = "saved-xenodia-key"
`,
        "utf8",
      );

      const readiness = await withCleanProviderEnv(() =>
        loadChatReadiness(configDir),
      );

      assert.equal(readiness.status, "live");
      assert.equal(readiness.active_provider, "xenodia");
      assert.match(readiness.detail, /Live chat via xenodia/);
    } finally {
      await rm(configDir, { recursive: true, force: true });
    }
  });

  it("reports setup-needed readiness when provider keys are missing", async () => {
    const configDir = await tempConfigDir();
    try {
      const readiness = await withCleanProviderEnv(() =>
        loadChatReadiness(configDir),
      );

      assert.equal(readiness.status, "needs_setup");
      assert.equal(readiness.active_provider, null);
    } finally {
      await rm(configDir, { recursive: true, force: true });
    }
  });

  it("resolves the Xenodia gateway backend from saved secrets", async () => {
    const configDir = await tempConfigDir();
    try {
      await writeFile(
        join(configDir, "chat-runtime-secrets.toml"),
        `
version = 1

[providers.xenodia]
api_key = "saved-xenodia-key"
model_override = "gpt-5.4"
`,
        "utf8",
      );

      const backend = await withCleanProviderEnv(() =>
        loadXenodiaGatewayBackend(configDir),
      );

      assert.equal(backend.api_key, "saved-xenodia-key");
      assert.equal(backend.model, "gpt-5.4");
      assert.equal(backend.request_timeout_seconds, 45);
      assert.equal(
        backend.chat_completions_url,
        "https://api.xenodia.xyz/v1/chat/completions",
      );
    } finally {
      await rm(configDir, { recursive: true, force: true });
    }
  });

  it("persists routing edits while preserving non-settings routing sections", async () => {
    const configDir = await tempConfigDir();
    try {
      const settings = await loadChatRoutingSettings(configDir);
      const balanced = settings.routeClasses.find(
        (routeClass) => routeClass.name === "balanced",
      );
      assert.ok(balanced);
      balanced.provider = "xenodia";
      balanced.model = "gpt-5.4";
      balanced.fallbackModel = "gpt-5.4-mini";

      const worker = settings.profiles.find(
        (profile) => profile.name === "worker",
      );
      assert.ok(worker);
      worker.defaultRouteClass = "cheap";

      await persistChatRoutingSettings(configDir, settings);

      const reloaded = await loadRoutingConfig(configDir);
      assert.equal(reloaded.route_classes.balanced?.provider, "xenodia");
      assert.equal(reloaded.route_classes.balanced?.model, "gpt-5.4");
      assert.equal(reloaded.profiles.worker?.default_route_class, "cheap");
      assert.equal(
        reloaded.task_types.conversation?.default_profile,
        "main",
      );
      assert.ok(
        reloaded.profiles.worker?.upgrade_when.includes(
          "multi_step_recovery",
        ),
      );

      const raw = await readFile(join(configDir, "model-routing.toml"), "utf8");
      assert.match(raw, /\[task_types\.conversation\]/);
    } finally {
      await rm(configDir, { recursive: true, force: true });
    }
  });
});
