import type { RuntimeHostActionIntent } from "../store/types.js";

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

  const extensions = requestedExtensions(text);
  const mediaKind = requestedMediaKind(text, extensions);
  if (!mediaKind) {
    return null;
  }

  const filterArgs: Record<string, unknown> = { kind: mediaKind };
  if (extensions.length > 0) {
    filterArgs.extensions = extensions;
  }
  if (text.includes("starred") || text.includes("favorite")) {
    filterArgs.starred_only = true;
  }

  return {
    hostActions: [
      {
        host_action_id: hostActionID("open_media_library", text),
        tool_id: "gee.app.openSurface",
        arguments: { gear_id: "media.library" },
      },
      {
        host_action_id: hostActionID(`media_filter_${mediaKind}`, text),
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

function routeBookmarkVaultIntent(rawText: string, text: string): RoutedGearIntent | null {
  if (!mentionsBookmarkVault(text)) {
    return null;
  }

  const content = bookmarkContent(rawText);
  if (!content) {
    return null;
  }

  return {
    hostActions: [
      {
        host_action_id: hostActionID("open_bookmark_vault", text),
        tool_id: "gee.app.openSurface",
        arguments: { gear_id: "bookmark.vault" },
      },
      {
        host_action_id: hostActionID("bookmark_save", text),
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
    text.includes("书签") ||
    text.includes("收藏") ||
    (hasURL && /\b(save|store|remember)\b/.test(text)) ||
    (hasURL && (text.includes("保存") || text.includes("存起来") || text.includes("存一下")))
  );
}

function bookmarkContent(rawText: string): string {
  return rawText
    .replace(/^(?:please\s+)?(?:bookmark|save|store|remember)\s+(?:this\s+)?(?:bookmark|link|url|content|note)?\s*[:：-]?\s*/i, "")
    .replace(/^(?:请|帮我)?(?:把|将)?\s*(?:这个|这条|该)?(?:链接|网址|内容|文本)?\s*(?:存进|存到|存为|保存到|保存为|加入|添加到)?(?:书签|收藏)?\s*[:：-]?\s*/u, "")
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

  return {
    hostActions: [
      {
        host_action_id: hostActionID("open_twitter_capture", text),
        tool_id: "gee.app.openSurface",
        arguments: { gear_id: "twitter.capture" },
      },
      {
        host_action_id: hostActionID(capabilityID.replace(".", "_"), text),
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
    text.includes("tweet") ||
    text.includes("推文") ||
    text.includes("推特")
  );
}

function firstURL(text: string): string | null {
  const match = text.match(/https?:\/\/[^\s"'<>，。]+/);
  return match?.[0] ?? null;
}

function requestedLimit(text: string): number {
  const patterns = [
    /(?:first|latest|top)\s+(\d{1,3})/,
    /(?:前|最近)\s*(\d{1,3})/,
    /(\d{1,3})\s*(?:tweets|tweet|条|个)/,
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
  if (
    text.includes("video")
  ) {
    return "video";
  }
  if (
    text.includes("image") ||
    text.includes("photo")
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

function hostActionID(prefix: string, text: string): string {
  return `host_action_${prefix}_${stableHash(text)}`;
}

function stableHash(value: string): string {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}
