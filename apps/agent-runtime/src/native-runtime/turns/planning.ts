import { createHash } from "node:crypto";

export type RuntimePlanPhase = "phase3.6";
export type RuntimePlanningMode = "direct" | "light" | "structured" | "recovery";

export type RuntimePlanningDecision = {
  mode: RuntimePlanningMode;
  boundary_mode: "default" | "gear_first";
  reason: string;
  should_create_run_plan: boolean;
};

export type RuntimePlanStage = {
  stage_id: string;
  title: string;
  objective: string;
  required_capabilities: string[];
  focus_gear_ids?: string[];
  focus_capability_ids?: string[];
  capability_args?: Record<string, Record<string, unknown>>;
  input_contract: string[];
  completion_signal: string;
  blocked_signal: string;
};

export type RuntimeCapabilityFocus = {
  stage_id: string;
  focus_gear_ids: string[];
  focus_capability_ids: string[];
  disclosure_level: "summary";
};

export type RuntimeRunPlan = {
  plan_id: string;
  phase: RuntimePlanPhase;
  planning_mode: "structured";
  source: "deterministic_runtime_seed";
  user_goal: string;
  success_criteria: string[];
  stages: RuntimePlanStage[];
  current_stage_id: string;
  focus: RuntimeCapabilityFocus;
  reopen_capability_discovery_when: string[];
};

const COMMON_REOPEN_TRIGGERS = [
  "a locked capability is unavailable, disabled, or unauthorized",
  "strict schema validation fails and the selected schema is insufficient to correct it",
  "a tool result reveals a new required capability or artifact dependency",
  "the user changes the objective",
  "the active stage is explicitly replanned",
];

export function selectRuntimePlanningMode(
  userRequest: string,
  boundaryMode: "default" | "gear_first",
): RuntimePlanningDecision {
  const trimmed = userRequest.trim();
  if (!trimmed || boundaryMode === "default") {
    return {
      mode: "direct",
      boundary_mode: boundaryMode,
      reason: "ordinary SDK turn; no Gear-first runtime boundary was selected",
      should_create_run_plan: false,
    };
  }

  if (isStructuredGearPlanningRequest(trimmed)) {
    return {
      mode: "structured",
      boundary_mode: boundaryMode,
      reason: "multi-stage Gear or cross-domain request needs stage proof and focused capability disclosure",
      should_create_run_plan: true,
    };
  }

  return {
    mode: "light",
    boundary_mode: boundaryMode,
    reason: "Gear-first task can use the bridge boundary without a full deterministic stage plan",
    should_create_run_plan: false,
  };
}

export function buildRuntimeRunPlan(
  userRequest: string,
  boundaryMode: "default" | "gear_first",
): RuntimeRunPlan | null {
  const trimmed = userRequest.trim();
  if (!trimmed || boundaryMode !== "gear_first") {
    return null;
  }

  const mediaGeneration = mediaGenerationPlan(trimmed);
  if (mediaGeneration) {
    return mediaGeneration;
  }

  const twitterPlan = twitterBookmarkMediaPlan(trimmed);
  if (twitterPlan) {
    return twitterPlan;
  }

  const weChatPlan = weChatReaderPlan(trimmed);
  if (weChatPlan) {
    return weChatPlan;
  }

  return genericGearPlan(trimmed);
}

export function capabilityFocusArgsForPlan(
  plan: RuntimeRunPlan | null,
  stageID?: string,
): Record<string, unknown> {
  if (!plan) {
    return { detail: "summary" };
  }
  const focus = capabilityFocusForStage(plan, stageID ?? plan.current_stage_id);
  const args: Record<string, unknown> = {
    detail: focus.disclosure_level,
    run_plan_id: plan.plan_id,
    stage_id: focus.stage_id,
  };
  if (focus.focus_gear_ids.length > 0) {
    args.focus_gear_ids = focus.focus_gear_ids;
  }
  if (focus.focus_capability_ids.length > 0) {
    args.focus_capability_ids = focus.focus_capability_ids;
  }
  return args;
}

export function capabilityFocusForStage(
  plan: RuntimeRunPlan,
  stageID: string,
): RuntimeCapabilityFocus {
  const stage = plan.stages.find((candidate) => candidate.stage_id === stageID);
  if (!stage) {
    return plan.focus;
  }
  return {
    stage_id: stage.stage_id,
    focus_gear_ids: stage.focus_gear_ids ?? [],
    focus_capability_ids: stage.focus_capability_ids ?? [],
    disclosure_level: "summary",
  };
}

export function currentRuntimePlanStage(plan: RuntimeRunPlan): RuntimePlanStage | null {
  return plan.stages.find((stage) => stage.stage_id === plan.current_stage_id) ?? null;
}

export function deterministicArgsForCapability(
  plan: RuntimeRunPlan | null | undefined,
  gearID: string,
  capabilityID: string,
  stageID?: string,
): Record<string, unknown> | null {
  if (!plan || !gearID.trim() || !capabilityID.trim()) {
    return null;
  }
  const targetStageID = stageID ?? plan.current_stage_id;
  const stage = plan.stages.find((candidate) => candidate.stage_id === targetStageID);
  const args = stage?.capability_args?.[`${gearID}/${capabilityID}`];
  return args ? { ...args } : null;
}

export function mergeDeterministicArgsForCapability(
  plan: RuntimeRunPlan | null | undefined,
  gearID: string,
  capabilityID: string,
  args: Record<string, unknown>,
  stageID?: string,
):
  | { ok: true; args: Record<string, unknown>; recovered_arg_keys: string[] }
  | { ok: false; code: string; message: string } {
  const deterministicArgs = deterministicArgsForCapability(plan, gearID, capabilityID, stageID);
  if (!deterministicArgs) {
    return { ok: true, args: { ...args }, recovered_arg_keys: [] };
  }

  const merged = { ...args };
  const recovered: string[] = [];
  for (const [key, value] of Object.entries(deterministicArgs)) {
    if (merged[key] === undefined) {
      merged[key] = value;
      recovered.push(key);
      continue;
    }
    if (JSON.stringify(merged[key]) !== JSON.stringify(value)) {
      return {
        ok: false,
        code: "gear.args.envelope",
        message:
          `conflicting \`args.${key}\` value for ${gearID} ${capabilityID}; ` +
          "the runtime plan has a deterministic stage argument and the tool call supplied a different value.",
      };
    }
  }

  return { ok: true, args: merged, recovered_arg_keys: recovered };
}

export function nextRuntimeRunPlan(plan: RuntimeRunPlan): RuntimeRunPlan | null {
  const currentIndex = plan.stages.findIndex(
    (stage) => stage.stage_id === plan.current_stage_id,
  );
  if (currentIndex < 0 || currentIndex + 1 >= plan.stages.length) {
    return null;
  }
  return runtimeRunPlanWithCurrentStage(plan, plan.stages[currentIndex + 1]?.stage_id);
}

export function runtimeRunPlanWithCurrentStage(
  plan: RuntimeRunPlan,
  stageID: string | undefined,
): RuntimeRunPlan | null {
  if (!stageID || !plan.stages.some((stage) => stage.stage_id === stageID)) {
    return null;
  }
  return {
    ...plan,
    current_stage_id: stageID,
    focus: capabilityFocusForStage(plan, stageID),
  };
}

export function renderRuntimeRunPlanForPrompt(plan: RuntimeRunPlan | null): string {
  if (!plan) {
    return [
      "[GeeAgent Runtime Plan]",
      "No focused plan seed is available for this turn. Use the Gear bridge deliberately and surface missing capability information as a real blockage.",
      "[/GeeAgent Runtime Plan]",
    ].join("\n");
  }

  return [
    "[GeeAgent Runtime Plan]",
    "Treat this compact plan as deterministic runtime state, not hidden reasoning.",
    JSON.stringify(compactRuntimeRunPlanForPrompt(plan), null, 2),
    "Execution rules:",
    "- Start with the current stage and its locked capability focus set.",
    "- When the current stage includes `capability_args` for the selected capability, pass those fields inside the direct Gear `args` object.",
    "- Do not browse the unscoped full Gear capability list while a focus set is locked.",
    "- Reopen capability discovery only when one of the listed reopen triggers occurs.",
    "- After each stage reaches completed, blocked, or plan_changed, produce a concise stage conclusion before continuing.",
    "- Never claim final completion until the success criteria are satisfied by structured tool results or artifacts.",
    "[/GeeAgent Runtime Plan]",
  ].join("\n");
}

function compactRuntimeRunPlanForPrompt(plan: RuntimeRunPlan): Record<string, unknown> {
  const currentStage = currentRuntimePlanStage(plan);
  return {
    plan_id: plan.plan_id,
    phase: plan.phase,
    planning_mode: plan.planning_mode,
    user_goal: truncateForPrompt(plan.user_goal, 500),
    success_criteria: plan.success_criteria.map((item) => truncateForPrompt(item, 220)),
    current_stage_id: plan.current_stage_id,
    focus: plan.focus,
    current_stage: currentStage
      ? {
          stage_id: currentStage.stage_id,
          title: currentStage.title,
          objective: truncateForPrompt(currentStage.objective, 320),
          required_capabilities: currentStage.required_capabilities,
          focus_gear_ids: currentStage.focus_gear_ids ?? [],
          focus_capability_ids: currentStage.focus_capability_ids ?? [],
          capability_args: currentStage.capability_args ?? {},
          input_contract: currentStage.input_contract.map((item) => truncateForPrompt(item, 220)),
          completion_signal: truncateForPrompt(currentStage.completion_signal, 220),
          blocked_signal: truncateForPrompt(currentStage.blocked_signal, 220),
        }
      : null,
    stage_order: plan.stages.map((stage) => ({
      stage_id: stage.stage_id,
      title: stage.title,
      required_capabilities: stage.required_capabilities,
    })),
    reopen_capability_discovery_when: plan.reopen_capability_discovery_when,
  };
}

function twitterBookmarkMediaPlan(userRequest: string): RuntimeRunPlan | null {
  const url = firstTwitterStatusUrl(userRequest);
  if (!url) {
    return null;
  }
  const wantsBookmark = mentionsBookmark(userRequest);
  const wantsMedia = mentionsMediaPreservation(userRequest);
  const wantsResearch = mentionsResearchOrExplanation(userRequest);
  if (!wantsBookmark && !wantsMedia) {
    return null;
  }

  const stages: RuntimePlanStage[] = [
    {
      stage_id: "stage_fetch_tweet",
      title: "Fetch tweet",
      objective: "Fetch the X/Twitter post and collect structured tweet metadata plus media candidates.",
      required_capabilities: ["twitter.capture/twitter.fetch_tweet"],
      capability_args: {
        "twitter.capture/twitter.fetch_tweet": { url },
      },
      input_contract: [`tweet URL is known: ${url}`],
      completion_signal: "tweet metadata and media candidate URLs are available",
      blocked_signal: "twitter.fetch_tweet is unavailable or cannot return the tweet",
    },
  ];

  if (wantsMedia) {
    stages.push(
      {
        stage_id: "stage_download_media",
        title: "Download media",
        objective: "Download tweet media using concrete media URLs returned by the tweet fetch stage.",
        required_capabilities: ["smartyt.media/smartyt.download_now"],
        input_contract: ["one or more remote media URLs from stage_fetch_tweet"],
        completion_signal: "local downloaded media file paths are available",
        blocked_signal: "no media URL exists or smartyt.download_now cannot download the media",
      },
      {
        stage_id: "stage_import_media",
        title: "Import media",
        objective: "Import downloaded local media files into the active Media Library.",
        required_capabilities: ["media.library/media.import_files"],
        input_contract: ["local downloaded media file paths from stage_download_media"],
        completion_signal: "Media Library returns imported media paths or item records",
        blocked_signal: "Media Library is unavailable or authorization is required",
      },
    );
  }

  if (wantsBookmark) {
    stages.push({
      stage_id: "stage_save_bookmark",
      title: "Save bookmark",
      objective: "Save the tweet as a bookmark and attach local imported media paths when media was requested.",
      required_capabilities: ["bookmark.vault/bookmark.save"],
      input_contract: wantsMedia
        ? ["tweet metadata from stage_fetch_tweet", "local imported media paths from stage_import_media"]
        : ["tweet metadata from stage_fetch_tweet"],
      completion_signal: "Bookmark Vault returns a saved bookmark id",
      blocked_signal: "bookmark.save is unavailable or required bookmark content is missing",
    });
  }

  if (wantsResearch) {
    stages.push(
      {
        stage_id: "stage_research_technologies",
        title: "Research technologies",
        objective:
          "Search current public information about technologies mentioned in the fetched tweet.",
        required_capabilities: [],
        input_contract: ["tweet text and technology names from stage_fetch_tweet"],
        completion_signal: "research evidence is available for the technologies mentioned in the tweet",
        blocked_signal: "no approved web or local-network research capability is available in the active run",
        focus_gear_ids: [],
        focus_capability_ids: [],
      },
      {
        stage_id: "stage_synthesize_explanation",
        title: "Explain technologies",
        objective:
          "Explain the technologies using the fetched tweet evidence and current research evidence.",
        required_capabilities: [],
        input_contract: ["tweet evidence from stage_fetch_tweet", "research evidence from stage_research_technologies"],
        completion_signal: "final explanation cites the tweet evidence and research evidence",
        blocked_signal: "tweet evidence or research evidence is missing",
        focus_gear_ids: [],
        focus_capability_ids: [],
      },
    );
  }

  stages.push({
    stage_id: "stage_verify",
    title: "Verify result",
    objective: wantsResearch
      ? "Verify storage locations and explanation evidence before final reply."
      : "Verify all requested storage locations are represented in structured results before final reply.",
    required_capabilities: [],
    input_contract: ["all prior requested stage outputs"],
    completion_signal: wantsResearch
      ? "final reply can cite saved storage results and research evidence"
      : "final reply can cite saved bookmark and media import results",
    blocked_signal: "one requested result is missing or only available as unverified prose",
  });

  const focusCapabilityIDs = [
    "twitter.fetch_tweet",
    ...(wantsMedia ? ["smartyt.download_now", "media.import_files"] : []),
    ...(wantsBookmark ? ["bookmark.save"] : []),
  ];
  const focusGearIDs = [
    "twitter.capture",
    ...(wantsMedia ? ["smartyt.media", "media.library"] : []),
    ...(wantsBookmark ? ["bookmark.vault"] : []),
  ];

  return planFromStages({
    userRequest,
    kind: "twitter-bookmark-media",
    successCriteria: [
      "tweet content is fetched from the Gear bridge",
      ...(wantsMedia
        ? ["tweet media is downloaded to local files", "downloaded media is imported into Media Library"]
        : []),
      ...(wantsBookmark ? ["bookmark is saved in Bookmark Vault"] : []),
      ...(wantsResearch
        ? [
            "current public information is searched for technologies mentioned in the tweet",
            "final explanation reflects tweet evidence and research evidence",
          ]
        : []),
      "final answer reflects structured tool results and any recovered failures",
    ],
    stages,
    focusGearIDs,
    focusCapabilityIDs,
  });
}

function mediaGenerationPlan(userRequest: string): RuntimeRunPlan | null {
  if (!mentionsMediaGenerationRequest(userRequest)) {
    return null;
  }

  const args = mediaGenerationCapabilityArgs(userRequest);
  return planFromStages({
    userRequest,
    kind: "media-generation",
    successCriteria: [
      "Media Generator receives a structured create_task request through the Gear bridge",
      "the provider-backed generation task id, status, and artifact references are returned as structured runtime state",
      "the final answer reports the real task state without claiming completion before Gee returns it",
    ],
    stages: [
      {
        stage_id: "stage_create_media_generation_task",
        title: "Create media generation task",
        objective: "Create the requested media generation task through Media Generator.",
        required_capabilities: ["media.generator/media_generator.create_task"],
        capability_args: {
          "media.generator/media_generator.create_task": args,
        },
        input_contract: ["user-provided prompt and generation parameters are available"],
        completion_signal: "Media Generator returns a task id, status, and any generated artifact references",
        blocked_signal: "Media Generator or the requested model/provider is unavailable",
      },
    ],
    focusGearIDs: ["media.generator"],
    focusCapabilityIDs: ["media_generator.create_task"],
  });
}

function mediaGenerationCapabilityArgs(userRequest: string): Record<string, unknown> {
  const text = userRequest.toLowerCase();
  const requestedModel = requestedMediaGenerationModel(text);
  const category = requestedMediaGenerationCategory(text, requestedModel);
  const args: Record<string, unknown> = {
    category,
    model: requestedModel ?? (category === "video" ? "veo3.1_fast" : "nano-banana-pro"),
    prompt: generationPrompt(userRequest),
  };
  if (category === "image") {
    args.response_format = "url";
    args.n = 1;
  }
  const batchCount = requestedMediaGenerationBatchCount(userRequest);
  if (batchCount) {
    args.batch_count = batchCount;
  }
  const aspectRatio = requestedAspectRatio(userRequest);
  if (aspectRatio) {
    args.aspect_ratio = aspectRatio;
  }
  const resolution = requestedResolution(userRequest);
  if (resolution) {
    args.resolution = resolution;
  }
  if (category === "video") {
    const duration = requestedVideoDuration(text);
    if (duration) {
      args.duration = duration;
    }
    const generationType = requestedVideoGenerationType(text);
    if (generationType) {
      args.generation_type = generationType;
    }
  }
  return args;
}

function requestedMediaGenerationModel(text: string): string | null {
  if (/\bveo[-_\s]*3(?:\.?1)?[-_\s]*fast\b/.test(text)) {
    return "veo3.1_fast";
  }
  if (/\bveo[-_\s]*3(?:\.?1)?[-_\s]*lite\b/.test(text)) {
    return "veo3.1_lite";
  }
  if (/\bveo[-_\s]*3(?:\.?1)?\b/.test(text)) {
    return "veo3.1";
  }
  if (/\bseedance[-_\s]*2(?:\.?0)?(?:[-_\s]*fast)?\b/.test(text)) {
    return /\bseedance[-_\s]*2(?:\.?0)?[-_\s]*fast\b/.test(text)
      ? "seedance-2-fast"
      : "seedance-2";
  }
  if (/\b(?:gpt[-_\s]*)?image[-_\s]*2\b/.test(text)) {
    return "gpt-image-2";
  }
  if (/nano[-_\s]*banana[-_\s]*pro/.test(text)) {
    return "nano-banana-pro";
  }
  return null;
}

function requestedMediaGenerationCategory(
  text: string,
  requestedModel: string | null,
): "image" | "video" {
  if (requestedModel && /^(?:veo3\.1|seedance-2)/.test(requestedModel)) {
    return "video";
  }
  return /\b(videos?|movies?|clips?|teasers?|trailers?)\b/.test(text) ? "video" : "image";
}

function requestedMediaGenerationBatchCount(userRequest: string): number | null {
  const text = userRequest.toLowerCase();
  const numericMatch = text.match(
    /(?:^|[^\d])([1-4])\s*(?:images?|imgs?|pictures?|photos?|videos?|clips?|tasks?|results?)(?:[^\d]|$)/i,
  );
  if (numericMatch?.[1]) {
    return Number(numericMatch[1]);
  }
  const wordCounts: Array<[RegExp, number]> = [
    [/\b(?:two|couple)\s+(?:images?|pictures?|photos?|videos?|clips?|tasks?|results?)\b/, 2],
    [/\bthree\s+(?:images?|pictures?|photos?|videos?|clips?|tasks?|results?)\b/, 3],
    [/\bfour\s+(?:images?|pictures?|photos?|videos?|clips?|tasks?|results?)\b/, 4],
  ];
  for (const [pattern, count] of wordCounts) {
    if (pattern.test(text)) {
      return count;
    }
  }
  return null;
}

function requestedAspectRatio(text: string): string | null {
  const match = text.match(/(^|[^\d])(\d{1,2})\s*[:\uFF1A\u00D7x]\s*(\d{1,2})([^\d]|$)/);
  if (!match?.[2] || !match?.[3]) {
    return null;
  }
  return `${match[2]}:${match[3]}`;
}

function requestedResolution(text: string): string | null {
  const videoMatch = text.match(/(^|[^\d])(480|720|1080)\s*p([^\d]|$)/i);
  if (videoMatch?.[2]) {
    return `${videoMatch[2]}p`;
  }
  const match = text.match(/(^|[^\d])([124])\s*k([^\d]|$)/i);
  return match?.[2] ? `${match[2]}K` : null;
}

function requestedVideoDuration(text: string): number | null {
  const match = text.match(/(^|[^\d])(\d{1,2})\s*(?:s|sec|secs|second|seconds)\b/i);
  if (!match?.[2]) {
    return null;
  }
  const duration = Number(match[2]);
  return duration >= 4 && duration <= 15 ? duration : null;
}

function requestedVideoGenerationType(text: string): string | null {
  if (/\b(first\s*(?:and|&)\s*last|first[-_\s]*last)\b/.test(text)) {
    return "FIRST_AND_LAST_FRAMES_2_VIDEO";
  }
  if (/\b(reference|references|reference[-_\s]*to[-_\s]*video|image[-_\s]*to[-_\s]*video)\b/.test(text)) {
    return "REFERENCE_2_VIDEO";
  }
  return null;
}

function generationPrompt(userRequest: string): string {
  const marker = userRequest.match(
    /(?:prompt)\s*(?:follows|below)?\s*[:\uFF1A]\s*/i,
  );
  if (marker?.index !== undefined) {
    const prompt = userRequest.slice(marker.index + marker[0].length).trim();
    if (prompt) {
      return prompt;
    }
  }
  return userRequest.trim();
}

function weChatReaderPlan(userRequest: string): RuntimeRunPlan | null {
  const url = firstUrl(userRequest);
  if (!url || !/https?:\/\/mp\.weixin\.qq\.com\//i.test(url)) {
    return null;
  }
  const isAlbum = /\/mp\/appmsgalbum/i.test(url);
  const capabilityID = isAlbum ? "wespy.fetch_album" : "wespy.fetch_article";
  const stageTitle = isAlbum ? "Fetch WeChat album" : "Fetch WeChat article";

  return planFromStages({
    userRequest,
    kind: isAlbum ? "wechat-album" : "wechat-article",
    successCriteria: [
      "WeSpy Reader fetches the requested WeChat URL",
      "requested article or album artifacts are represented as structured results",
      "final answer cites saved or summarized artifact state without claiming unverified work",
    ],
    stages: [
      {
        stage_id: "stage_fetch_wespy",
        title: stageTitle,
        objective: "Fetch the WeChat content through the installed WeSpy Reader Gear.",
        required_capabilities: [`wespy.reader/${capabilityID}`],
        capability_args: {
          [`wespy.reader/${capabilityID}`]: { url },
        },
        input_contract: [`WeChat URL is known: ${url}`],
        completion_signal: "WeSpy Reader returns article or album artifacts",
        blocked_signal: "WeSpy Reader is unavailable or cannot fetch the URL",
      },
      {
        stage_id: "stage_finish_user_request",
        title: "Finish requested output",
        objective: "Use the fetched WeSpy artifacts to summarize or save exactly what the user requested.",
        required_capabilities: [],
        input_contract: ["structured WeSpy result and artifact references from stage_fetch_wespy"],
        completion_signal: "user-requested summary or local artifact state is verified",
        blocked_signal: "the fetched result lacks the artifact needed for the requested output",
      },
    ],
    focusGearIDs: ["wespy.reader"],
    focusCapabilityIDs: [capabilityID],
  });
}

function genericGearPlan(userRequest: string): RuntimeRunPlan {
  return planFromStages({
    userRequest,
    kind: "generic-gear",
    successCriteria: [
      "the active Gear bridge is verified",
      "the selected capability result is returned as structured runtime state",
      "missing capabilities are exposed as structured failures",
    ],
    stages: [
      {
        stage_id: "stage_select_capability",
        title: "Select Gear capability",
        objective: "Inspect enabled Gear capabilities only as much as needed to choose the right capability.",
        required_capabilities: [],
        input_contract: ["latest user request"],
        completion_signal: "one or more relevant capabilities are selected or a capability gap is reported",
        blocked_signal: "no enabled Gear capability matches the user request",
      },
      {
        stage_id: "stage_execute_capability",
        title: "Execute capability",
        objective: "Invoke the selected Gear capability with validated arguments.",
        required_capabilities: [],
        input_contract: ["selected capability id and required arguments"],
        completion_signal: "capability result is available as structured state",
        blocked_signal: "required arguments or capability availability are missing",
      },
    ],
    focusGearIDs: [],
    focusCapabilityIDs: [],
  });
}

function planFromStages(input: {
  userRequest: string;
  kind: string;
  successCriteria: string[];
  stages: RuntimePlanStage[];
  focusGearIDs: string[];
  focusCapabilityIDs: string[];
}): RuntimeRunPlan {
  const stages = input.stages.map(enrichStageFocus);
  const currentStageID = stages[0]?.stage_id ?? "stage_start";
  const currentStage = stages.find((stage) => stage.stage_id === currentStageID);
  return {
    plan_id: `run_plan_${stableHash(`${input.kind}:${input.userRequest}`)}`,
    phase: "phase3.6",
    planning_mode: "structured",
    source: "deterministic_runtime_seed",
    user_goal: input.userRequest,
    success_criteria: input.successCriteria,
    stages,
    current_stage_id: currentStageID,
    focus: {
      stage_id: currentStageID,
      focus_gear_ids: currentStage?.focus_gear_ids ?? dedupe(input.focusGearIDs),
      focus_capability_ids: currentStage?.focus_capability_ids ?? dedupe(input.focusCapabilityIDs),
      disclosure_level: "summary",
    },
    reopen_capability_discovery_when: COMMON_REOPEN_TRIGGERS,
  };
}

function isStructuredGearPlanningRequest(userRequest: string): boolean {
  const text = userRequest.toLowerCase();
  if (mentionsMediaGenerationRequest(userRequest)) {
    return true;
  }
  const twitterStatusURL = firstTwitterStatusUrl(userRequest);
  if (twitterStatusURL) {
    const wantsBookmark = mentionsBookmark(userRequest);
    const wantsMedia = mentionsMediaPreservation(userRequest);
    const wantsResearch = mentionsResearchOrExplanation(userRequest);
    return (
      wantsBookmark ||
      wantsMedia ||
      mentionsInfoCaptureWorkflow(text)
    );
  }

  const url = firstUrl(userRequest);
  if (url && /https?:\/\/mp\.weixin\.qq\.com\//i.test(url)) {
    return /summari[sz]e|save|archive|album|article|download|collect/.test(text);
  }

  return false;
}

function mentionsInfoCaptureWorkflow(text: string): boolean {
  return text.includes("info capture") || text.includes("information capture");
}

function enrichStageFocus(stage: RuntimePlanStage): RuntimePlanStage {
  if ((stage.focus_gear_ids?.length ?? 0) > 0 || (stage.focus_capability_ids?.length ?? 0) > 0) {
    return {
      ...stage,
      focus_gear_ids: dedupe(stage.focus_gear_ids ?? []),
      focus_capability_ids: dedupe(stage.focus_capability_ids ?? []),
    };
  }
  const parsed = parseCapabilityRefs(stage.required_capabilities);
  return {
    ...stage,
    focus_gear_ids: parsed.gearIDs,
    focus_capability_ids: parsed.capabilityIDs,
  };
}

function parseCapabilityRefs(refs: string[]): {
  gearIDs: string[];
  capabilityIDs: string[];
} {
  const gearIDs: string[] = [];
  const capabilityIDs: string[] = [];
  for (const ref of refs) {
    const [gearID, capabilityID] = ref.split("/");
    if (gearID) {
      gearIDs.push(gearID);
    }
    if (capabilityID) {
      capabilityIDs.push(capabilityID);
    }
  }
  return {
    gearIDs: dedupe(gearIDs),
    capabilityIDs: dedupe(capabilityIDs),
  };
}

function mentionsBookmark(text: string): boolean {
  return /bookmark|favorite|save|store|remember|archive/.test(text.toLowerCase());
}

function mentionsMediaPreservation(text: string): boolean {
  return /media|video|image|photo|download|browser|library/.test(text.toLowerCase());
}

function mentionsMediaGenerationRequest(rawText: string): boolean {
  const text = rawText.toLowerCase();
  if (isMediaGenerationInfoQuestion(rawText, text)) {
    return false;
  }
  return (
    (mentionsMediaGenerationPromptMarker(rawText) && mentionsMediaGenerationProvider(rawText, text)) ||
    /\b(generate|create|draw|render|make)\b.{0,80}\b(images?|pictures?|illustrations?|posters?|artworks?)\b/.test(text) ||
    /\b(images?|pictures?|illustrations?|posters?|artworks?)\b.{0,80}\b(generate|create|draw|render|make)\b/.test(text) ||
    /\b(generate|create|render|make)\b.{0,80}\b(videos?|clips?|teasers?|trailers?)\b/.test(text) ||
    /\b(videos?|clips?|teasers?|trailers?)\b.{0,80}\b(generate|create|render|make)\b/.test(text)
  );
}

function isMediaGenerationInfoQuestion(rawText: string, text: string): boolean {
  if (!mentionsMediaGenerationProvider(rawText, text) || mentionsMediaGenerationPromptMarker(rawText)) {
    return false;
  }
  return (
    /\b(how\s+(?:do|to|can|should)|what(?:'s|\s+is)|why|whether|explain|describe|compare|pricing|price|limits?|parameters?|docs?)\b/.test(text) ||
    /\b(?:can|does)\s+(?:gpt[-_\s]*image[-_\s]*2|image[-_\s]*2|veo[-_\s]*3(?:\.?1)?|seedance[-_\s]*2(?:\.?0)?)\b/.test(text)
  );
}

function mentionsMediaGenerationPromptMarker(rawText: string): boolean {
  return /(?:prompt)\s*(?:follows|below)?\s*[:\uFF1A]/i.test(rawText);
}

function mentionsMediaGenerationProvider(rawText: string, text: string): boolean {
  return (
    text.includes("media generator") ||
    text.includes("image generator") ||
    text.includes("video generator") ||
    /\b(?:gpt[-_\s]*)?image[-_\s]*2\b/.test(text) ||
    /\bveo[-_\s]*3(?:\.?1)?\b/.test(text) ||
    /\bseedance[-_\s]*2(?:\.?0)?\b/.test(text)
  );
}

function mentionsResearchOrExplanation(text: string): boolean {
  return /search|research|look\s+up|web|internet|explain|technology|context|background|related\s+information/.test(
    text.toLowerCase(),
  );
}

function firstTwitterStatusUrl(text: string): string | null {
  const url = firstUrl(text);
  if (!url) {
    return null;
  }
  return /https?:\/\/(?:www\.)?(?:x|twitter)\.com\/(?:i\/)?(?:[a-z0-9_]{1,15}\/)?status(?:es)?\/\d+/i.test(
    url,
  )
    ? url
    : null;
}

function firstUrl(text: string): string | null {
  return text.match(/https?:\/\/[^\s,，。！？、；）)】\]}]+/i)?.[0] ?? null;
}

function stableHash(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 12);
}

function dedupe(values: string[]): string[] {
  return [...new Set(values.filter((value) => value.trim().length > 0))];
}

function truncateForPrompt(value: string, limit: number): string {
  const trimmed = value.trim();
  if ([...trimmed].length <= limit) {
    return trimmed;
  }
  return `${[...trimmed].slice(0, Math.max(0, limit - 3)).join("")}...`;
}
