export type GearCapabilityValidationResult =
  | { ok: true }
  | {
      ok: false;
      code: string;
      message: string;
      field: string;
      expected: string;
    };

export type RuntimeCapabilityRequirement = {
  code: string;
  field: string;
  expected: string;
  kind: "non_empty_string" | "non_empty_string_array";
  aliases: string[];
};

export type RuntimeCapabilityContract = {
  id: string;
  provider: "gear";
  gear_id: string;
  capability_id: string;
  required_args: RuntimeCapabilityRequirement[];
  permission_policy: "gear_host";
  progress_policy: "host_events";
  artifact_policy: "structured_result";
  resumability: "same_run";
};

const GEAR_CAPABILITY_CONTRACTS: RuntimeCapabilityContract[] = [
  gearContract("bookmark.vault", "bookmark.save", [
    requiredString("content", ["content", "raw_content"]),
  ]),
  gearContract("app.icon.forge", "app_icon.generate", [
    requiredString("source_path", ["source_path", "path"]),
  ]),
  gearContract("media.generator", "media_generator.create_task", [
    requiredString("prompt", ["prompt"]),
  ]),
  gearContract("media.library", "media.focus_folder", [
    requiredString("folder_name", ["folder_name"]),
  ]),
  gearContract("media.library", "media.import_files", [
    requiredStringArray("paths", ["paths", "file_paths"]),
  ]),
  gearContract("telegram.bridge", "telegram_push.upsert_channel", [
    requiredString("channel_id", ["channel_id", "channelId"]),
    requiredString("account_id", ["account_id", "accountId"]),
    requiredString("target_kind", ["target_kind", "targetKind"]),
    requiredString("target_value", ["target_value", "targetValue"]),
  ]),
  gearContract("telegram.bridge", "telegram_push.send_message", [
    requiredString("channel_id", ["channel_id", "channelId"]),
    requiredString("message", ["message"]),
    requiredString("idempotency_key", ["idempotency_key", "idempotencyKey"]),
  ]),
  gearContract("smartyt.media", "smartyt.download", [requiredString("url", ["url"])]),
  gearContract("smartyt.media", "smartyt.download_now", [requiredString("url", ["url"])]),
  gearContract("smartyt.media", "smartyt.sniff", [requiredString("url", ["url"])]),
  gearContract("smartyt.media", "smartyt.transcribe", [requiredString("url", ["url"])]),
  gearContract("twitter.capture", "twitter.fetch_list", [
    requiredString("url", ["url", "list_url"]),
  ]),
  gearContract("twitter.capture", "twitter.fetch_tweet", [
    requiredString("url", ["url", "tweet_url"]),
  ]),
  gearContract("twitter.capture", "twitter.fetch_user", [
    requiredString("username", ["username", "handle", "url"]),
  ]),
  gearContract("wespy.reader", "wespy.fetch_album", [
    requiredString("url", ["url", "album_url"]),
  ]),
  gearContract("wespy.reader", "wespy.fetch_article", [
    requiredString("url", ["url", "article_url"]),
  ]),
  gearContract("wespy.reader", "wespy.list_album", [
    requiredString("url", ["url", "album_url"]),
  ]),
];

const GEAR_CAPABILITY_CONTRACTS_BY_KEY = new Map(
  GEAR_CAPABILITY_CONTRACTS.map((contract) => [
    gearCapabilityKey(contract.gear_id, contract.capability_id),
    contract,
  ]),
);

export function gearCapabilityContracts(): RuntimeCapabilityContract[] {
  return GEAR_CAPABILITY_CONTRACTS.map((contract) => ({
    ...contract,
    required_args: [...contract.required_args],
  }));
}

export function validateGearCapabilityArgs(
  gearID: string,
  capabilityID: string,
  args: Record<string, unknown>,
): GearCapabilityValidationResult {
  const contract = GEAR_CAPABILITY_CONTRACTS_BY_KEY.get(
    gearCapabilityKey(gearID, capabilityID),
  );
  const failedRequirement = contract?.required_args.find(
    (requirement) => !matchesRequirement(requirement, args),
  );
  if (!failedRequirement) {
    return { ok: true };
  }

  return {
    ok: false,
    code: failedRequirement.code,
    field: failedRequirement.field,
    expected: failedRequirement.expected,
    message: `${failedRequirement.expected} for ${gearID} ${capabilityID}.`,
  };
}

function gearContract(
  gearID: string,
  capabilityID: string,
  requiredArgs: RuntimeCapabilityRequirement[],
): RuntimeCapabilityContract {
  return {
    id: `gear.${gearID}.${capabilityID}`,
    provider: "gear",
    gear_id: gearID,
    capability_id: capabilityID,
    required_args: requiredArgs,
    permission_policy: "gear_host",
    progress_policy: "host_events",
    artifact_policy: "structured_result",
    resumability: "same_run",
  };
}

function gearCapabilityKey(gearID: string, capabilityID: string): string {
  return `${gearID}/${capabilityID}`;
}

function requiredString(field: string, aliases: string[]): RuntimeCapabilityRequirement {
  return {
    code: `gear.args.${field}`,
    field,
    expected: `required string \`${field}\` is missing`,
    kind: "non_empty_string",
    aliases,
  };
}

function requiredStringArray(field: string, aliases: string[]): RuntimeCapabilityRequirement {
  return {
    code: `gear.args.${field}`,
    field,
    expected: `required string array \`${field}\` is missing`,
    kind: "non_empty_string_array",
    aliases,
  };
}

function matchesRequirement(
  requirement: RuntimeCapabilityRequirement,
  args: Record<string, unknown>,
): boolean {
  switch (requirement.kind) {
    case "non_empty_string":
      return requirement.aliases.some((alias) => nonEmptyString(args[alias]));
    case "non_empty_string_array":
      return requirement.aliases.some((alias) => {
        const value = args[alias];
        return Array.isArray(value) && value.some((item) => nonEmptyString(item));
      });
  }
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}
