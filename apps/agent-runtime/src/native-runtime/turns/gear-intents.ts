import { randomUUID } from "node:crypto";
import type { RuntimeHostActionIntent } from "../../protocol.js";

export type RoutedGearIntent = {
  hostActions: RuntimeHostActionIntent[];
};

const MEDIA_EXTENSION_KIND: Record<string, "image" | "video"> = {
  jpg: "image",
  jpeg: "image",
  png: "image",
  gif: "image",
  webp: "image",
  bmp: "image",
  tiff: "image",
  heic: "image",
  mp4: "video",
  mov: "video",
  m4v: "video",
  webm: "video",
  avi: "video",
  mkv: "video",
};

export function routeLocalGearIntent(prompt: string): RoutedGearIntent | null {
  const rawText = prompt.trim();
  const text = rawText.toLowerCase();
  if (shouldDeferToAgentPlannedGearWorkflow(rawText, text)) {
    return null;
  }

  const bookmarkIntent = routeBookmarkVaultIntent(rawText, text);
  if (bookmarkIntent) {
    return bookmarkIntent;
  }

  const twitterIntent = routeTwitterCaptureIntent(text);
  if (twitterIntent) {
    return twitterIntent;
  }

  if (!mentionsMediaLibrary(text)) {
    return null;
  }

  const runID = uniqueHostActionRunID();
  const extensions = requestedExtensions(text);
  const mediaKind = requestedMediaKind(text, extensions);
  if (!mediaKind) {
    return null;
  }

  const filterArgs: Record<string, unknown> = { kind: mediaKind };
  if (extensions.length > 0) {
    filterArgs.extensions = extensions;
  }
  if (mentionsStarredFilter(rawText, text)) {
    filterArgs.starred_only = true;
  }

  return {
    hostActions: [
      {
        host_action_id: hostActionID("open_media_library", text, runID),
        tool_id: "gee.app.openSurface",
        arguments: { gear_id: "media.library" },
      },
      {
        host_action_id: hostActionID(`media_filter_${mediaKind}`, text, runID),
        tool_id: "gee.gear.invoke",
        arguments: {
          gear_id: "media.library",
          capability_id: "media.filter",
          args: filterArgs,
        },
      },
    ],
  };
}

function shouldDeferToAgentPlannedGearWorkflow(rawText: string, text: string): boolean {
  const url = firstURL(text);
  if (!isTwitterStatusURL(url)) {
    return false;
  }

  return (
    mentionsInfoCaptureWorkflow(text) ||
    mentionsCollectionWorkflow(rawText, text) ||
    mentionsMediaAcquisitionWorkflow(rawText, text)
  );
}

function isTwitterStatusURL(url: string | null): boolean {
  return (
    url !== null &&
    /https?:\/\/(?:www\.)?(?:x|twitter)\.com\/(?:i\/)?(?:[a-z0-9_]{1,15}\/)?status(?:es)?\/\d+/i.test(url)
  );
}

function mentionsInfoCaptureWorkflow(text: string): boolean {
  return (
    text.includes("info capture") ||
    text.includes("information capture")
  );
}

function mentionsCollectionWorkflow(rawText: string, text: string): boolean {
  return (
    text.includes("bookmark") ||
    text.includes("favorite") ||
    /\b(save|store|remember|archive)\b/.test(text)
  );
}

function mentionsMediaAcquisitionWorkflow(rawText: string, text: string): boolean {
  return (
    /\b(download|media|video|audio|mp4|mov)\b/.test(text)
  );
}

function routeBookmarkVaultIntent(rawText: string, text: string): RoutedGearIntent | null {
  if (!mentionsBookmarkVault(text)) {
    return null;
  }

  const content = bookmarkContent(rawText);
  if (!content) {
    return null;
  }
  const runID = uniqueHostActionRunID();

  return {
    hostActions: [
      {
        host_action_id: hostActionID("open_bookmark_vault", text, runID),
        tool_id: "gee.app.openSurface",
        arguments: { gear_id: "bookmark.vault" },
      },
      {
        host_action_id: hostActionID("bookmark_save", text, runID),
        tool_id: "gee.gear.invoke",
        arguments: {
          gear_id: "bookmark.vault",
          capability_id: "bookmark.save",
          args: { content },
        },
      },
    ],
  };
}

function mentionsBookmarkVault(text: string): boolean {
  const hasURL = firstURL(text) !== null;
  return (
    text.includes("bookmark") ||
    text.includes("favorite") ||
    (hasURL && /\b(save|store|remember|archive|capture)\b/.test(text))
  );
}

function bookmarkContent(rawText: string): string {
  return rawText
    .replace(/^(?:please\s+)?(?:bookmark|save|store|remember|archive|capture)\s+(?:this\s+)?(?:bookmark|link|url|content|note)?\s*[:\uFF1A-]?\s*/i, "")
    .trim() || rawText.trim();
}

function routeTwitterCaptureIntent(text: string): RoutedGearIntent | null {
  if (!mentionsTwitterCapture(text)) {
    return null;
  }

  const url = firstURL(text);
  const limit = requestedLimit(text);
  let capabilityID: "twitter.fetch_tweet" | "twitter.fetch_list" | "twitter.fetch_user" | null = null;
  const args: Record<string, unknown> = {};

  if (url && /\/status(?:es)?\/\d+|\/i\/status\/\d+/.test(url)) {
    capabilityID = "twitter.fetch_tweet";
    args.url = url;
  } else if (url && /\/lists\/\d+/.test(url)) {
    capabilityID = "twitter.fetch_list";
    args.url = url;
    args.limit = limit;
  } else {
    const handle = requestedHandle(text, url);
    if (handle) {
      capabilityID = "twitter.fetch_user";
      args.username = handle;
      args.limit = limit;
    }
  }

  if (!capabilityID) {
    return null;
  }
  const runID = uniqueHostActionRunID();

  return {
    hostActions: [
      {
        host_action_id: hostActionID("open_twitter_capture", text, runID),
        tool_id: "gee.app.openSurface",
        arguments: { gear_id: "twitter.capture" },
      },
      {
        host_action_id: hostActionID(capabilityID.replace(".", "_"), text, runID),
        tool_id: "gee.gear.invoke",
        arguments: {
          gear_id: "twitter.capture",
          capability_id: capabilityID,
          args,
        },
      },
    ],
  };
}

function mentionsTwitterCapture(text: string): boolean {
  return (
    text.includes("twitter") ||
    text.includes("x.com") ||
    text.includes("tweet")
  );
}

function firstURL(text: string): string | null {
  const match = text.match(/https?:\/\/[^\s"'<>]+/);
  return match?.[0]?.replace(/[.,;:!?)\]\uFF0C\u3002\uFF1B\uFF1A\uFF01\uFF09\u3011]+$/, "") ?? null;
}

function requestedLimit(text: string): number {
  const patterns = [
    /(?:first|latest|top)\s+(\d{1,3})/,
    /(\d{1,3})\s*(?:tweets|tweet|items|posts)/,
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match?.[1]) {
      return Math.min(Math.max(Number.parseInt(match[1], 10) || 30, 1), 200);
    }
  }
  return 30;
}

function requestedHandle(text: string, url: string | null): string | null {
  const mention = text.match(/@([a-z0-9_]{1,15})/i)?.[1];
  if (mention) {
    return mention;
  }
  if (!url) {
    return null;
  }
  const match = url.match(/https?:\/\/(?:www\.)?(?:x|twitter)\.com\/([a-z0-9_]{1,15})(?:[/?#]|$)/i);
  const handle = match?.[1];
  if (!handle || ["i", "home", "search"].includes(handle.toLowerCase())) {
    return null;
  }
  return handle;
}

function mentionsMediaLibrary(text: string): boolean {
  return (
    text.includes("media manager") ||
    text.includes("media browser") ||
    text.includes("media library")
  );
}

function requestedExtensions(text: string): string[] {
  return Object.keys(MEDIA_EXTENSION_KIND).filter((ext) => {
    const escaped = ext.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`(^|[^a-z0-9])${escaped}([^a-z0-9]|$)`, "i").test(text);
  });
}

function requestedMediaKind(
  text: string,
  extensions: string[],
): "all" | "image" | "video" | null {
  if (text.includes("video") || text.includes("movie") || text.includes("film")) {
    return "video";
  }
  if (
    text.includes("image") ||
    text.includes("photo") ||
    text.includes("picture")
  ) {
    return "image";
  }
  if (text.includes("all")) {
    return "all";
  }
  const extensionKinds = new Set(extensions.map((extension) => MEDIA_EXTENSION_KIND[extension]));
  if (extensionKinds.size === 1) {
    return [...extensionKinds][0];
  }
  return null;
}

function mentionsStarredFilter(rawText: string, text: string): boolean {
  return (
    text.includes("starred") ||
    text.includes("favorite")
  );
}

function hostActionID(prefix: string, text: string, runID: string): string {
  return `host_action_${prefix}_${stableHash(text)}_${runID}`;
}

function uniqueHostActionRunID(): string {
  return randomUUID().replaceAll("-", "").slice(0, 8);
}

function stableHash(value: string): string {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}
