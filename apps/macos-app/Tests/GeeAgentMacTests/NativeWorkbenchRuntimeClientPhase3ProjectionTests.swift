import XCTest
@testable import GeeAgentMac

final class NativeWorkbenchRuntimeClientPhase3ProjectionTests: XCTestCase {
    func testProjectsPhase3TranscriptEventsAsActivityRows() throws {
        let snapshot = try NativeWorkbenchRuntimeClient.projectSnapshotForTesting(
            from: Data(Self.phase3SnapshotJSON.utf8)
        )
        let messages = try XCTUnwrap(snapshot.conversations.first?.messages)
        let activityRows = messages.filter { $0.kind == .action && $0.id.hasPrefix("phase3-") }

        XCTAssertEqual(
            activityRows.map(\.headerTitle),
            [
                "Plan created",
                "Plan updated",
                "Focus locked",
                "Stage started",
                "Stage blocked",
            ]
        )
        XCTAssertEqual(activityRows.first?.statusLabel, "2 stages")
        XCTAssertEqual(activityRows.first?.content, "Capture a tweet into the media library.")
        XCTAssertTrue(activityRows[2].detailItems.contains(.init(label: "Capabilities", value: "twitter.capture/twitter.fetch_tweet")))
        XCTAssertEqual(activityRows.last?.tone, .critical)
        XCTAssertFalse(
            messages.contains { $0.kind == .thinking && $0.content.contains("Run plan created") },
            "Typed Phase 3 events should not collapse into generic Thinking rows."
        )
        XCTAssertFalse(
            messages.contains { $0.kind == .thinking && $0.content.contains("same agent run") },
            "Low-signal same-run host bridge breadcrumbs should not render as repeated Thinking rows."
        )
        XCTAssertFalse(
            messages.contains { $0.kind == .chat && $0.content.contains("Stage complete:") },
            "Model-authored stage progress text is already represented by typed stage rows and should not render as chat."
        )
        XCTAssertTrue(
            messages.contains { $0.kind == .chat && $0.content == "Done." }
        )
        XCTAssertEqual(snapshot.conversations.first?.runtimeRunSummary?.runID, "run_phase3")
        XCTAssertEqual(snapshot.conversations.first?.runtimeRunSummary?.lastSequence, 12)
        XCTAssertEqual(snapshot.conversations.first?.runtimeRunSummary?.lastEventKind, "assistant_message")
    }

    func testProjectsExternalInvocationFractionalArgsWithoutTruncation() throws {
        let json = Self.phase3SnapshotJSON.replacingOccurrences(
            of: #""tasks": []"#,
            with: #"""
      "external_invocations": [
        {
          "external_invocation_id": "gee_ext_icon",
          "tool": "gee_invoke_capability",
          "status": "pending",
          "gear_id": "app.icon.forge",
          "capability_id": "app_icon.generate",
          "surface_id": null,
          "args": {
            "source_path": "/tmp/source.png",
            "content_scale": 0.95,
            "corner_radius_ratio": 0.22,
            "shadow": true
          }
        }
      ],
      "tasks": []
"""#
        )
        let snapshot = try NativeWorkbenchRuntimeClient.projectSnapshotForTesting(from: Data(json.utf8))
        let invocation = try XCTUnwrap(snapshot.externalInvocations.first)

        XCTAssertEqual(invocation.args["source_path"], .string("/tmp/source.png"))
        XCTAssertEqual(invocation.args["content_scale"], .double(0.95))
        XCTAssertEqual(invocation.args["corner_radius_ratio"], .double(0.22))
        XCTAssertEqual(invocation.args["shadow"], .bool(true))
    }

    func testProjectsWorkspaceMessageAttachmentsAsUserMessageDetails() throws {
        let json = Self.phase3SnapshotJSON.replacingOccurrences(
            of: #""content": "Capture this tweet and preserve media.""#,
            with: #"""
            "content": "Capture this tweet and preserve media.",
            "attachments": [
              {
                "attachment_id": "att_image_01",
                "kind": "image",
                "source": "workspace_chat",
                "display_name": "tree.png",
                "original_path": "/tmp/tree.png",
                "resolved_path": "/tmp/tree.png",
                "mime_type": "image/png",
                "size_bytes": 2048,
                "created_at": "2026-05-07T00:00:00.000Z",
                "status": "ready",
                "access": {
                  "scope": "run",
                  "mode": "read",
                  "root": "/tmp"
                },
                "image": {
                  "width": 1440,
                  "height": 900
                },
                "limits": {
                  "max_bytes": 10485760
                },
                "fallback_attempted": false
              }
            ]
"""#
        )
        let snapshot = try NativeWorkbenchRuntimeClient.projectSnapshotForTesting(from: Data(json.utf8))
        let userMessage = try XCTUnwrap(
            snapshot.conversations.first?.messages.first { $0.id == "msg_user" }
        )

        XCTAssertEqual(userMessage.detailItems, [
            ConversationMessageDetailItem(
                label: "Attachment",
                value: "image · tree.png · /tmp/tree.png"
            )
        ])
        XCTAssertEqual(userMessage.attachments, [
            ConversationMessageAttachment(
                id: "att_image_01",
                kind: .image,
                displayName: "tree.png",
                originalPath: "/tmp/tree.png",
                resolvedPath: "/tmp/tree.png",
                mimeType: "image/png",
                sizeBytes: 2048,
                status: .ready,
                source: "workspace_chat",
                createdAt: "2026-05-07T00:00:00.000Z",
                accessScope: "run",
                accessMode: "read",
                accessRoot: "/tmp",
                imageWidth: 1440,
                imageHeight: 900,
                maxBytes: 10485760,
                fallbackAttempted: false
            )
        ])
        XCTAssertEqual(userMessage.attachments.first?.inspectorDetailItems, [
            ConversationMessageDetailItem(label: "Status", value: "ready"),
            ConversationMessageDetailItem(label: "Source", value: "workspace_chat"),
            ConversationMessageDetailItem(label: "Created", value: "2026-05-07T00:00:00.000Z"),
            ConversationMessageDetailItem(label: "Original path", value: "/tmp/tree.png"),
            ConversationMessageDetailItem(label: "Resolved path", value: "/tmp/tree.png"),
            ConversationMessageDetailItem(label: "MIME", value: "image/png"),
            ConversationMessageDetailItem(label: "Size", value: "2 KB"),
            ConversationMessageDetailItem(label: "Access", value: "run · read · /tmp"),
            ConversationMessageDetailItem(label: "Image", value: "1440 x 900"),
            ConversationMessageDetailItem(label: "Limits", value: "max 10.5 MB"),
            ConversationMessageDetailItem(label: "Fallback attempted", value: "No")
        ])
    }

    func testStoppedSessionStateDoesNotRenderAsThinkingRow() throws {
        let json = Self.phase3SnapshotJSON.replacingOccurrences(
            of: #"""
        {
          "event_id": "evt_assistant_delta",
"""#,
            with: #"""
        {
          "event_id": "evt_stopped_state",
          "session_id": "session_phase3",
          "parent_event_id": "evt_host_completed_state",
          "created_at": "now",
          "payload": {
            "kind": "session_state_changed",
            "summary": "Stopped by the user. GeeAgent interrupted the active run and did not mark the request complete."
          }
        },
        {
          "event_id": "evt_assistant_delta",
"""#
        )
        let snapshot = try NativeWorkbenchRuntimeClient.projectSnapshotForTesting(from: Data(json.utf8))
        let messages = try XCTUnwrap(snapshot.conversations.first?.messages)

        XCTAssertFalse(
            messages.contains {
                $0.kind == .thinking && $0.content.localizedCaseInsensitiveContains("Stopped by the user")
            },
            "The final stopped assistant reply already tells the user what happened; the runtime state must not create a Worked/Thinking row."
        )
    }

    func testDecodesRuntimeRunProjectionForInspectorMinimumState() throws {
        let projection = try NativeWorkbenchRuntimeClient.projectRuntimeRunProjectionForTesting(
            from: Data(Self.runtimeRunProjectionJSON.utf8)
        )

        XCTAssertEqual(projection.runID, "run_projection_minimum")
        XCTAssertEqual(projection.rowCount, 5)
        XCTAssertFalse(projection.hasDiagnostics)
        XCTAssertEqual(projection.artifactIDs, ["artifact_runtime_log_read"])
        XCTAssertEqual(projection.artifactRefs.first?.artifactID, "artifact_runtime_log_read")
        XCTAssertEqual(projection.artifactRefs.first?.path, "/tmp/geeagent/golden/runtime-log-read.json")
        XCTAssertEqual(projection.artifactRefs.first?.sourceInvocationID, "toolu_read_runtime_log")

        XCTAssertEqual(
            projection.rows.map(\.projectionKind),
            ["user_message", "stage", "tool", "tool_result", "assistant_message"]
        )
        XCTAssertEqual(projection.rows[1].status, "blocked")
        XCTAssertEqual(projection.rows[1].stageID, "stage_read_log")
        XCTAssertEqual(projection.rows[0].attachmentIDs, ["att_screenshot_tree", "att_actual_dir"])
        XCTAssertEqual(projection.rows[0].attachmentStatuses, ["ready", "ready"])
        XCTAssertEqual(projection.rows[3].toolName, "Read")
        XCTAssertEqual(projection.rows[3].artifactIDs, ["artifact_runtime_log_read"])
        XCTAssertTrue(projection.rows[3].expandable)
        XCTAssertEqual(projection.rows.last?.projectionScope, "main_timeline")
    }

    func testDecodesRuntimeRunWaitClassificationForInspectorMinimumStates() throws {
        let approval = try NativeWorkbenchRuntimeClient.classifyRuntimeRunWaitForTesting(
            from: Data(Self.approvalWaitClassificationJSON.utf8)
        )
        XCTAssertEqual(approval.runID, "run_wait_approval")
        XCTAssertEqual(approval.waitKind, "approval_wait")
        XCTAssertEqual(approval.status, "waiting")
        XCTAssertEqual(approval.evidence.pendingApprovalID, "approval_golden_bash")
        XCTAssertEqual(approval.evidence.sdkSessionID, "sdk_golden_phase3_approval")
        XCTAssertFalse(approval.evidence.diagnostics.hasIssuesForTesting)

        let sessionLost = try NativeWorkbenchRuntimeClient.classifyRuntimeRunWaitForTesting(
            from: Data(Self.sessionLostClassificationJSON.utf8)
        )
        XCTAssertEqual(sessionLost.runID, "run_wait_session_lost")
        XCTAssertEqual(sessionLost.waitKind, "session_lost")
        XCTAssertEqual(sessionLost.status, "failed")
        XCTAssertEqual(sessionLost.evidence.pendingToolUseID, "toolu_pending_when_lost")
        XCTAssertEqual(sessionLost.evidence.lastToolUseID, "toolu_pending_when_lost")
        XCTAssertFalse(sessionLost.evidence.diagnostics.hasIssuesForTesting)
    }

    private static let phase3SnapshotJSON = """
    {
      "quick_input_hint": "Ask GeeAgent",
      "quick_reply": "",
      "chat_runtime": {
        "status": "live",
        "active_provider": "Claude",
        "detail": "Runtime live"
      },
      "conversations": [
        {
          "conversation_id": "conv_phase3",
          "title": "Phase 3 run",
          "status": "active",
          "tags": [],
          "last_message_preview": "Phase 3 event projection",
          "last_timestamp": "now",
          "is_active": true
        }
      ],
      "active_conversation": {
        "conversation_id": "conv_phase3",
        "title": "Phase 3 run",
        "status": "active",
        "tags": [],
        "messages": []
      },
      "module_runs": [],
      "execution_sessions": [
        {
          "session_id": "session_phase3",
          "conversation_id": "conv_phase3"
        }
      ],
      "transcript_events": [
        {
          "event_id": "evt_user",
          "session_id": "session_phase3",
          "parent_event_id": null,
          "created_at": "now",
          "payload": {
            "kind": "user_message",
            "message_id": "msg_user",
            "content": "Capture this tweet and preserve media."
          }
        },
        {
          "event_id": "evt_plan_created",
          "session_id": "session_phase3",
          "parent_event_id": "evt_user",
          "created_at": "now",
          "payload": {
            "kind": "run_plan_created",
            "summary": "Run plan created with 2 stage(s).",
            "run_plan": {
              "plan_id": "plan_001",
              "phase": "phase3.6",
              "source": "deterministic_runtime_seed",
              "user_goal": "Capture a tweet into the media library.",
              "success_criteria": [
                "tweet metadata fetched",
                "media imported"
              ],
              "current_stage_id": "stage_fetch",
              "focus": {
                "stage_id": "stage_fetch",
                "focus_gear_ids": [
                  "twitter.capture"
                ],
                "focus_capability_ids": [
                  "twitter.capture/twitter.fetch_tweet"
                ],
                "disclosure_level": "summary"
              },
              "reopen_capability_discovery_when": [
                "a locked capability is unavailable"
              ],
              "stages": [
                {
                  "stage_id": "stage_fetch",
                  "title": "Fetch tweet",
                  "objective": "Fetch tweet metadata and media candidates.",
                  "required_capabilities": [
                    "twitter.capture/twitter.fetch_tweet"
                  ],
                  "input_contract": [
                    "tweet URL is known"
                  ],
                  "completion_signal": "metadata returned",
                  "blocked_signal": "tweet fetch unavailable"
                },
                {
                  "stage_id": "stage_verify",
                  "title": "Verify result",
                  "objective": "Verify imported media before final reply.",
                  "required_capabilities": [],
                  "input_contract": [
                    "prior stage outputs"
                  ],
                  "completion_signal": "result verified",
                  "blocked_signal": "verification cannot inspect outputs"
                }
              ]
            }
          }
        },
        {
          "event_id": "evt_plan_updated",
          "session_id": "session_phase3",
          "parent_event_id": "evt_plan_created",
          "created_at": "now",
          "payload": {
            "kind": "run_plan_updated",
            "summary": "Plan advanced after fetching metadata.",
            "run_plan_id": "plan_001",
            "current_stage_id": "stage_verify",
            "run_plan": {
              "plan_id": "plan_001",
              "phase": "phase3.6",
              "source": "deterministic_runtime_seed",
              "user_goal": "Capture a tweet into the media library.",
              "success_criteria": [
                "tweet metadata fetched",
                "media imported"
              ],
              "current_stage_id": "stage_verify",
              "focus": {
                "stage_id": "stage_verify",
                "focus_gear_ids": [],
                "focus_capability_ids": [],
                "disclosure_level": "summary"
              },
              "reopen_capability_discovery_when": [
                "a locked capability is unavailable"
              ],
              "stages": []
            }
          }
        },
        {
          "event_id": "evt_focus",
          "session_id": "session_phase3",
          "parent_event_id": "evt_plan_updated",
          "created_at": "now",
          "payload": {
            "kind": "capability_focus_locked",
            "summary": "Capability focus locked to twitter.capture/twitter.fetch_tweet.",
            "run_plan_id": "plan_001",
            "stage_id": "stage_fetch",
            "focus_gear_ids": [
              "twitter.capture"
            ],
            "focus_capability_ids": [
              "twitter.capture/twitter.fetch_tweet"
            ]
          }
        },
        {
          "event_id": "evt_stage_started",
          "session_id": "session_phase3",
          "parent_event_id": "evt_focus",
          "created_at": "now",
          "payload": {
            "kind": "stage_started",
            "summary": "Stage started: Fetch tweet. Fetch tweet metadata and media candidates.",
            "run_plan_id": "plan_001",
            "stage_id": "stage_fetch",
            "title": "Fetch tweet",
            "objective": "Fetch tweet metadata and media candidates.",
            "required_capabilities": [
              "twitter.capture/twitter.fetch_tweet"
            ]
          }
        },
        {
          "event_id": "evt_stage_blocked",
          "session_id": "session_phase3",
          "parent_event_id": "evt_stage_started",
          "created_at": "now",
          "payload": {
            "kind": "stage_concluded",
            "summary": "Twitter capability unavailable.",
            "run_plan_id": "plan_001",
            "stage_id": "stage_fetch",
            "title": "Fetch tweet",
            "status": "blocked"
          }
        },
        {
          "event_id": "evt_host_bridge_state",
          "session_id": "session_phase3",
          "parent_event_id": "evt_stage_blocked",
          "created_at": "now",
          "payload": {
            "kind": "session_state_changed",
            "summary": "the agent inspected the Gear result and requested another native Gear host action inside the same agent run"
          }
        },
        {
          "event_id": "evt_finalize_state",
          "session_id": "session_phase3",
          "parent_event_id": "evt_host_bridge_state",
          "created_at": "now",
          "payload": {
            "kind": "session_state_changed",
            "summary": "Turn finalized after 2 grounded steps: the agent runtime is waiting on native Gear host action results before continuing this same user turn"
          }
        },
        {
          "event_id": "evt_host_result_return_state",
          "session_id": "session_phase3",
          "parent_event_id": "evt_finalize_state",
          "created_at": "now",
          "payload": {
            "kind": "session_state_changed",
            "summary": "native Gear actions completed; returning structured host results to the active agent run so the agent can write the user-facing reply"
          }
        },
        {
          "event_id": "evt_host_completed_state",
          "session_id": "session_phase3",
          "parent_event_id": "evt_host_result_return_state",
          "created_at": "now",
          "payload": {
            "kind": "session_state_changed",
            "summary": "the agent runtime continued after Gear host results and completed the active user turn"
          }
        },
        {
          "event_id": "evt_assistant_delta",
          "session_id": "session_phase3",
          "parent_event_id": "evt_host_completed_state",
          "created_at": "now",
          "payload": {
            "kind": "assistant_message_delta",
            "message_id": "msg_assistant_01",
            "delta": "Stage complete: fetched the tweet and found one video media URL."
          }
        },
        {
          "event_id": "evt_assistant_final",
          "session_id": "session_phase3",
          "parent_event_id": "evt_assistant_delta",
          "run_id": "run_phase3",
          "sequence": 12,
          "created_at": "now",
          "payload": {
            "kind": "assistant_message",
            "message_id": "msg_assistant_01",
            "content": "Stage complete: saved the bookmark with the imported local media path attached.Done."
          }
        }
      ],
      "tasks": [],
      "approval_requests": [],
      "workspace_focus": {
        "mode": "conversation",
        "task_id": null
      }
    }
    """

    private static let runtimeRunProjectionJSON = """
    {
      "schema_version": 1,
      "run_id": "run_projection_minimum",
      "row_count": 5,
      "artifact_ids": [
        "artifact_runtime_log_read"
      ],
      "artifact_refs": [
        {
          "artifact_id": "artifact_runtime_log_read",
          "kind": "tool_result_artifact",
          "title": "Runtime log read result",
          "path": "/tmp/geeagent/golden/runtime-log-read.json",
          "summary": "Large runtime log output stored outside prompt context.",
          "sha256": "93bc1f5d7d26b85b5f189e7e0000000000000000000000000000000000000000",
          "byte_count": 24000,
          "token_estimate": 4800,
          "mime_type": "application/json",
          "source_event_id": "evt_file_003_result",
          "source_event_sequence": 3,
          "source_invocation_id": "toolu_read_runtime_log",
          "source_tool_name": "Read",
          "source_host_action_id": null
        }
      ],
      "diagnostics": {
        "duplicate_event_ids": [],
        "missing_parent_event_ids": [],
        "missing_sequence_numbers": [],
        "out_of_order_event_ids": []
      },
      "rows": [
        {
          "row_id": "row_run_projection_minimum_0001",
          "run_id": "run_projection_minimum",
          "sequence": 1,
          "event_id": "evt_file_001_user",
          "event_kind": "user_message",
          "projection_kind": "user_message",
          "label": "User",
          "status": null,
          "summary": "Read the runtime log and summarize it without inlining the full file. (2 attachments)",
          "stage_id": null,
          "tool_name": null,
          "projection_scope": "main_timeline",
          "expandable": false,
          "artifact_ids": [],
          "attachment_ids": [
            "att_screenshot_tree",
            "att_actual_dir"
          ],
          "attachment_statuses": [
            "ready",
            "ready"
          ]
        },
        {
          "row_id": "row_run_projection_minimum_0002",
          "run_id": "run_projection_minimum",
          "sequence": 2,
          "event_id": "evt_stage_blocked",
          "event_kind": "stage_concluded",
          "projection_kind": "stage",
          "label": "Stage concluded",
          "status": "blocked",
          "summary": "Waiting for file approval before reading the log.",
          "stage_id": "stage_read_log",
          "tool_name": null,
          "projection_scope": "worked",
          "expandable": true,
          "artifact_ids": []
        },
        {
          "row_id": "row_run_projection_minimum_0003",
          "run_id": "run_projection_minimum",
          "sequence": 3,
          "event_id": "evt_file_002_tool",
          "event_kind": "tool_invocation",
          "projection_kind": "tool",
          "label": "Tool invocation",
          "status": "running",
          "summary": "Read runtime.log",
          "stage_id": "stage_read_log",
          "tool_name": "Read",
          "projection_scope": "worked",
          "expandable": true,
          "artifact_ids": []
        },
        {
          "row_id": "row_run_projection_minimum_0004",
          "run_id": "run_projection_minimum",
          "sequence": 4,
          "event_id": "evt_file_003_result",
          "event_kind": "tool_result",
          "projection_kind": "tool_result",
          "label": "Tool result",
          "status": "succeeded",
          "summary": "Runtime log was materialized as an artifact because it was too large for prompt context.",
          "stage_id": "stage_read_log",
          "tool_name": "Read",
          "projection_scope": "worked",
          "expandable": true,
          "artifact_ids": [
            "artifact_runtime_log_read"
          ]
        },
        {
          "row_id": "row_run_projection_minimum_0005",
          "run_id": "run_projection_minimum",
          "sequence": 5,
          "event_id": "evt_file_004_assistant",
          "event_kind": "assistant_message",
          "projection_kind": "assistant_message",
          "label": "Assistant",
          "status": null,
          "summary": "The runtime log was read and summarized from the artifact reference.",
          "stage_id": null,
          "tool_name": null,
          "projection_scope": "main_timeline",
          "expandable": false,
          "artifact_ids": []
        }
      ]
    }
    """

    private static let approvalWaitClassificationJSON = """
    {
      "run_id": "run_wait_approval",
      "wait_kind": "approval_wait",
      "status": "waiting",
      "detail": "The run is waiting for an approval decision.",
      "evidence": {
        "run_id": "run_wait_approval",
        "last_event_kind": "tool_invocation",
        "last_event_sequence": 2,
        "last_tool_use_id": "toolu_approval_bash",
        "pending_tool_use_id": null,
        "pending_host_action_ids": [],
        "pending_approval_id": "approval_golden_bash",
        "sdk_session_id": "sdk_golden_phase3_approval",
        "gateway_request_id": "gateway_req_golden_approval",
        "diagnostics": {
          "duplicate_event_ids": [],
          "missing_parent_event_ids": [],
          "missing_sequence_numbers": [],
          "out_of_order_event_ids": []
        }
      }
    }
    """

    private static let sessionLostClassificationJSON = """
    {
      "run_id": "run_wait_session_lost",
      "wait_kind": "session_lost",
      "status": "failed",
      "detail": "The SDK session lineage was lost while GeeAgent was handling host-action results.",
      "evidence": {
        "run_id": "run_wait_session_lost",
        "last_event_kind": "tool_invocation",
        "last_event_sequence": 2,
        "last_tool_use_id": "toolu_pending_when_lost",
        "pending_tool_use_id": "toolu_pending_when_lost",
        "pending_host_action_ids": [],
        "pending_approval_id": null,
        "sdk_session_id": "sdk_golden_phase3_lost",
        "gateway_request_id": null,
        "diagnostics": {
          "duplicate_event_ids": [],
          "missing_parent_event_ids": [],
          "missing_sequence_numbers": [],
          "out_of_order_event_ids": []
        }
      }
    }
    """
}

private extension WorkbenchRuntimeRunDiagnostics {
    var hasIssuesForTesting: Bool {
        !duplicateEventIDs.isEmpty
            || !missingParentEventIDs.isEmpty
            || !missingSequenceNumbers.isEmpty
            || !outOfOrderEventIDs.isEmpty
    }
}
