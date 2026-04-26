import { resolveConfigDir } from "../paths.js";
import { loadRuntimeStore, persistRuntimeStore } from "./persistence.js";
import type { RuntimeStore } from "./types.js";

const staleApprovalSummary =
  "The paused SDK runtime session is no longer alive, so GeeAgent cannot resume this approval inside the same run.";
const staleInProgressSummary =
  "The SDK runtime was interrupted while a turn was still running. GeeAgent stopped the stale run instead of leaving the conversation loading forever.";

type JsonRecord = Record<string, unknown>;

export async function reconcileStaleApprovals(
  configDirOverride?: string,
): Promise<void> {
  const configDir = resolveConfigDir(configDirOverride);
  const store = await loadRuntimeStore(configDir);
  if (expireStaleSdkApprovals(store)) {
    await persistRuntimeStore(configDir, store);
  }
}

export function expireStaleSdkApprovals(store: RuntimeStore): boolean {
  const expiredTaskIds = new Set<string>();
  let changed = false;

  store.approval_requests = store.approval_requests.map((approval) => {
    if (!isOpenSdkRuntimeApproval(approval)) {
      return approval;
    }
    const taskId = stringField(approval, "task_id");
    if (taskId) {
      expiredTaskIds.add(taskId);
    }
    changed = true;
    return {
      ...approval,
      status: "expired",
      reason: staleApprovalSummary,
    };
  });

  const staleInProgressTaskId = expireStaleInProgressRun(store);
  if (staleInProgressTaskId) {
    expiredTaskIds.add(staleInProgressTaskId);
    changed = true;
  }

  if (!changed) {
    return false;
  }

  const summary = staleInProgressTaskId ? staleInProgressSummary : staleApprovalSummary;
  if (expiredTaskIds.size > 0) {
    expireTasks(
      store,
      expiredTaskIds,
      summary,
      staleInProgressTaskId
        ? "stale_sdk_runtime_interrupted"
        : "stale_sdk_approval_expired",
    );
    expireModuleRuns(store, expiredTaskIds, summary);
  }
  store.quick_reply = summary;
  store.last_run_state = {
    conversation_id: store.active_conversation_id,
    status: "failed",
    stop_reason: staleInProgressTaskId
      ? "sdk_runtime_interrupted"
      : "terminal_approval_resume_failed",
    detail: summary,
    resumable: false,
    task_id: [...expiredTaskIds][0] ?? null,
    module_run_id: null,
  };
  return true;
}

function expireStaleInProgressRun(store: RuntimeStore): string | null {
  if (!isRecord(store.last_run_state) || store.last_run_state.status !== "running") {
    return null;
  }
  const stopReason = stringField(store.last_run_state, "stop_reason");
  if (
    stopReason !== "terminal_approval_resume_in_progress" &&
    stopReason !== "terminal_denial_resume_in_progress"
  ) {
    return null;
  }
  return stringField(store.last_run_state, "task_id") || null;
}

function expireTasks(
  store: RuntimeStore,
  taskIds: Set<string>,
  summary: string,
  stage: string,
): void {
  store.tasks = store.tasks.map((task) => {
    if (!isRecord(task) || !taskIds.has(stringField(task, "task_id"))) {
      return task;
    }
    return {
      ...task,
      summary,
      current_stage: stage,
      status: "failed",
      progress_percent: 72,
      approval_request_id: null,
    };
  });
}

function expireModuleRuns(
  store: RuntimeStore,
  taskIds: Set<string>,
  summary: string,
): void {
  store.module_runs = store.module_runs.map((item) => {
    if (!isRecord(item) || !isRecord(item.module_run)) {
      return item;
    }
    const moduleRun = item.module_run;
    if (!taskIds.has(stringField(moduleRun, "task_id"))) {
      return item;
    }
    return {
      ...item,
      module_run: {
        ...moduleRun,
        status: "failed",
        stage: "finalized",
        result_summary: summary,
      },
      recoverability: {
        retry_safe: false,
        resume_supported: false,
        hint: summary,
      },
    };
  });
}

function isOpenSdkRuntimeApproval(value: unknown): value is JsonRecord {
  if (!isRecord(value) || value.status !== "open") {
    return false;
  }
  return (
    isRecord(value.machine_context) &&
    isSdkRuntimeTerminalApprovalKind(value.machine_context.kind)
  );
}

function isSdkRuntimeTerminalApprovalKind(kind: unknown): boolean {
  return kind === "sdk_runtime_terminal" || kind === "sdk_bridge_terminal";
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringField(record: JsonRecord, field: string): string {
  const value = record[field];
  return typeof value === "string" ? value : "";
}
