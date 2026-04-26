import type { ToolSpec } from "./types.js";

const TOOL_CATALOG: ToolSpec[] = [
  {
    id: "core.read",
    title: "Read file",
    description: "Read a UTF-8 file from the local filesystem and return its contents.",
    needsApproval: false,
    blastRadius: "local",
  },
  {
    id: "core.write",
    title: "Write file",
    description: "Write UTF-8 content to the local filesystem. Requires approval.",
    needsApproval: true,
    blastRadius: "external",
  },
  {
    id: "core.edit",
    title: "Edit file",
    description: "Apply a bounded text replacement to a UTF-8 file. Requires approval.",
    needsApproval: true,
    blastRadius: "external",
  },
  {
    id: "core.bash",
    title: "Run bash command",
    description:
      "Run a guarded local command. Read-only inspections may proceed directly; broader commands require approval.",
    needsApproval: true,
    blastRadius: "external",
  },
  {
    id: "core.grep",
    title: "Search file contents",
    description: "Search UTF-8 files under a directory for a literal text pattern.",
    needsApproval: false,
    blastRadius: "local",
  },
  {
    id: "core.find",
    title: "Find files",
    description: "Find filesystem entries under a directory by literal name substring.",
    needsApproval: false,
    blastRadius: "local",
  },
  {
    id: "core.ls",
    title: "List directory",
    description: "List entries in a local directory.",
    needsApproval: false,
    blastRadius: "local",
  },
  {
    id: "navigate.openSection",
    title: "Open workbench section",
    description:
      "Switch the workbench nav to a known section (home, chat, tasks, agents, settings, apps).",
    needsApproval: false,
    blastRadius: "safe",
  },
  {
    id: "navigate.openModule",
    title: "Open installed module",
    description: "Open an installed capability module by id.",
    needsApproval: false,
    blastRadius: "safe",
  },
  {
    id: "gee.app.openSection",
    title: "Open Gee section",
    description:
      "Switch the Gee workbench to a known section. Stable alias for navigate.openSection.",
    needsApproval: false,
    blastRadius: "safe",
  },
  {
    id: "gee.app.openSurface",
    title: "Open Gee surface",
    description:
      "Open a Gee app or gear surface by id, such as media.library. Stable alias for opening module-like surfaces.",
    needsApproval: false,
    blastRadius: "safe",
  },
  {
    id: "gee.gear.listCapabilities",
    title: "List Gear capabilities",
    description:
      "Progressively disclose enabled Gear capabilities. Use summary first, then request one gear or capability schema as needed.",
    needsApproval: false,
    blastRadius: "safe",
  },
  {
    id: "gee.gear.invoke",
    title: "Invoke Gear capability",
    description:
      "Invoke one enabled Gear capability through Gee's host protocol. Gear-specific actions remain inside the gear boundary.",
    needsApproval: false,
    blastRadius: "safe",
  },
  {
    id: "files.readText",
    title: "Read text file",
    description: "Read a UTF-8 file from the local filesystem and return its contents.",
    needsApproval: false,
    blastRadius: "local",
  },
  {
    id: "files.writeText",
    title: "Write text file",
    description: "Write UTF-8 content to the local filesystem. Requires approval.",
    needsApproval: true,
    blastRadius: "external",
  },
  {
    id: "shell.run",
    title: "Run shell command",
    description:
      "Run one of the guarded shell commands. Read-only inspections may proceed directly; broader commands require approval.",
    needsApproval: true,
    blastRadius: "external",
  },
  {
    id: "clipboard.read",
    title: "Read clipboard",
    description: "Read the current pasteboard text.",
    needsApproval: false,
    blastRadius: "local",
  },
  {
    id: "clipboard.write",
    title: "Write clipboard",
    description: "Replace the pasteboard text.",
    needsApproval: false,
    blastRadius: "local",
  },
  {
    id: "url.open",
    title: "Open URL",
    description: "Open a URL in the user's default handler.",
    needsApproval: false,
    blastRadius: "external",
  },
  {
    id: "notify.post",
    title: "Post system notification",
    description: "Post a system notification via `osascript`.",
    needsApproval: false,
    blastRadius: "external",
  },
];

export const TOOL_SPECS = new Map(TOOL_CATALOG.map((spec) => [spec.id, spec]));
