#!/usr/bin/env node

const readline = require("node:readline");

const sessions = new Map();

function emit(event) {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

function scenarioForContent(content) {
  const forced = process.env.GEEAGENT_MOCK_CLAUDE_SDK_SCENARIO;
  if (forced && forced.trim()) {
    return forced.trim();
  }

  const lower = String(content || "").toLowerCase();
  if (lower.includes("fail")) return "error";
  if (lower.includes("approve")) return "approval";
  if (lower.includes("tool")) return "tool";
  return "direct";
}

function completeDirect(sessionId) {
  emit({
    type: "session.assistant_text",
    sessionId,
    text: "Mock bridge completed the turn directly.",
  });
  emit({
    type: "session.result",
    sessionId,
    result: "Mock bridge completed the turn directly.",
    raw: { is_error: false },
  });
}

function completeToolRun(sessionId) {
  emit({
    type: "session.tool_use",
    sessionId,
    toolUseId: "mock_tool_1",
    toolName: "Bash",
    input: { command: "pwd" },
  });
  emit({
    type: "session.tool_result",
    sessionId,
    toolUseId: "mock_tool_1",
    status: "succeeded",
    summary: "Printed the current working directory.",
  });
  emit({
    type: "session.assistant_text",
    sessionId,
    text: "Mock bridge used Bash, observed the local workspace, and finished the run.",
  });
  emit({
    type: "session.result",
    sessionId,
    result: "Mock bridge used Bash, observed the local workspace, and finished the run.",
    raw: { is_error: false },
  });
}

function completeApprovalRun(sessionId) {
  emit({
    type: "session.tool_use",
    sessionId,
    toolUseId: "mock_tool_after_approval",
    toolName: "Bash",
    input: { command: "echo approved" },
  });
  emit({
    type: "session.tool_result",
    sessionId,
    toolUseId: "mock_tool_after_approval",
    status: "succeeded",
    summary: "Ran the approved command.",
  });
  emit({
    type: "session.assistant_text",
    sessionId,
    text: "Mock bridge resumed after approval and completed the run.",
  });
  emit({
    type: "session.result",
    sessionId,
    result: "Mock bridge resumed after approval and completed the run.",
    raw: { is_error: false },
  });
}

function completeUnsupportedToolRecovery(sessionId) {
  emit({
    type: "session.assistant_text",
    sessionId,
    text: "Mock bridge accepted the host denial for Write and recovered without running that tool.",
  });
  emit({
    type: "session.result",
    sessionId,
    result: "Mock bridge accepted the host denial for Write and recovered without running that tool.",
    raw: { is_error: false },
  });
}

function completeWebSearchRun(sessionId) {
  emit({
    type: "session.tool_use",
    sessionId,
    toolUseId: "mock_websearch_1",
    toolName: "WebSearch",
    input: { query: "AxonChain official website 2026" },
  });
  emit({
    type: "session.tool_result",
    sessionId,
    toolUseId: "mock_websearch_1",
    status: "succeeded",
    summary: "Searched the web and found a candidate official AxonChain website.",
  });
  emit({
    type: "session.assistant_text",
    sessionId,
    text: "Mock bridge used WebSearch and summarized the website result.",
  });
  emit({
    type: "session.result",
    sessionId,
    result: "Mock bridge used WebSearch and summarized the website result.",
    raw: { is_error: false },
  });
}

emit({ type: "bridge.ready" });

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

rl.on("line", (line) => {
  if (!line.trim()) return;

  let command;
  try {
    command = JSON.parse(line);
  } catch (error) {
    emit({ type: "session.error", error: `Invalid JSON: ${error.message}` });
    return;
  }

  switch (command.type) {
    case "bridge.init":
      emit({ type: "bridge.initialized", defaultModel: command.defaultModel || "sonnet" });
      break;
    case "session.create":
      sessions.set(command.sessionId, {
        scenario: "direct",
        waitingApproval: false,
        approvalCount: 0,
      });
      emit({ type: "session.created", sessionId: command.sessionId });
      break;
    case "session.send": {
      const session = sessions.get(command.sessionId) || {
        scenario: "direct",
        waitingApproval: false,
        approvalCount: 0,
      };
      session.scenario = scenarioForContent(command.content);
      session.approvalCount = 0;
      sessions.set(command.sessionId, session);

      if (session.scenario === "error") {
        emit({
          type: "session.result",
          sessionId: command.sessionId,
          result: "Mock bridge failed the run.",
          raw: { is_error: true },
        });
      } else if (session.scenario === "approval") {
        session.waitingApproval = true;
        session.approvalCount = 1;
        emit({
          type: "session.approval_requested",
          sessionId: command.sessionId,
          requestId: "mock_approval_1",
          toolName: "Bash",
          input: { command: "echo approved", cwd: "/tmp/geeagent-mock" },
          reason: "Mock approval required before running Bash.",
        });
      } else if (session.scenario === "approval-chain") {
        session.waitingApproval = true;
        session.approvalCount = 1;
        emit({
          type: "session.approval_requested",
          sessionId: command.sessionId,
          requestId: "mock_approval_1",
          toolName: "Bash",
          input: { command: "echo first", cwd: "/tmp/geeagent-mock" },
          reason: "Mock approval required before the first Bash boundary.",
        });
      } else if (session.scenario === "nonbash") {
        session.waitingApproval = true;
        session.approvalCount = 1;
        emit({
          type: "session.approval_requested",
          sessionId: command.sessionId,
          requestId: "mock_write_approval_1",
          toolName: "Write",
          input: { file_path: "/tmp/geeagent-mock.txt", content: "mock" },
          reason: "Mock Write approval should not be host-approved by default.",
        });
      } else if (session.scenario === "websearch") {
        session.waitingApproval = true;
        session.approvalCount = 1;
        emit({
          type: "session.approval_requested",
          sessionId: command.sessionId,
          requestId: "mock_websearch_approval_1",
          toolName: "WebSearch",
          input: { query: "AxonChain official website 2026" },
          reason: "Mock WebSearch should be host-approved as a read-only web lookup.",
        });
      } else if (session.scenario === "tool") {
        completeToolRun(command.sessionId);
      } else {
        completeDirect(command.sessionId);
      }
      break;
    }
    case "session.approval": {
      const session = sessions.get(command.sessionId);
      if (!session || !session.waitingApproval) {
        emit({
          type: "session.error",
          sessionId: command.sessionId,
          error: "No pending approval exists for this mock session.",
        });
        break;
      }

      session.waitingApproval = false;
      if (command.decision === "allow") {
        if (session.scenario === "websearch") {
          completeWebSearchRun(command.sessionId);
          break;
        }
        if (session.scenario === "approval-chain" && session.approvalCount === 1) {
          session.waitingApproval = true;
          session.approvalCount = 2;
          emit({
            type: "session.tool_use",
            sessionId: command.sessionId,
            toolUseId: "mock_tool_after_first_approval",
            toolName: "Bash",
            input: { command: "echo first" },
          });
          emit({
            type: "session.tool_result",
            sessionId: command.sessionId,
            toolUseId: "mock_tool_after_first_approval",
            status: "succeeded",
            summary: "Ran the first approved command.",
          });
          emit({
            type: "session.approval_requested",
            sessionId: command.sessionId,
            requestId: "mock_approval_2",
            toolName: "Bash",
            input: { command: "echo second", cwd: "/tmp/geeagent-mock" },
            reason: "Mock approval required before the second Bash boundary.",
          });
          break;
        }
        completeApprovalRun(command.sessionId);
      } else if (session.scenario === "nonbash") {
        completeUnsupportedToolRecovery(command.sessionId);
      } else {
        emit({
          type: "session.result",
          sessionId: command.sessionId,
          result: "Mock bridge approval was denied.",
          raw: { is_error: true },
        });
      }
      break;
    }
    case "session.close":
      sessions.delete(command.sessionId);
      emit({ type: "session.closed", sessionId: command.sessionId });
      break;
    case "bridge.shutdown":
      emit({ type: "bridge.stopped" });
      process.exit(0);
      break;
    default:
      emit({
        type: "session.error",
        error: `Unsupported mock bridge command: ${command.type || "<missing>"}`,
      });
  }
});
