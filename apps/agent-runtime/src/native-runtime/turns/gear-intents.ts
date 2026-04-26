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
  const text = prompt.trim().toLowerCase();
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
