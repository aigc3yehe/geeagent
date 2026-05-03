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
            messages.contains { $0.kind == .thinking && $0.content.contains("same SDK run") },
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
            "summary": "the agent inspected the Gear result and requested another native Gear host action inside the same SDK run"
          }
        },
        {
          "event_id": "evt_finalize_state",
          "session_id": "session_phase3",
          "parent_event_id": "evt_host_bridge_state",
          "created_at": "now",
          "payload": {
            "kind": "session_state_changed",
            "summary": "Turn finalized after 2 grounded steps: the SDK runtime is waiting on native Gear host action results before continuing this same user turn"
          }
        },
        {
          "event_id": "evt_host_result_return_state",
          "session_id": "session_phase3",
          "parent_event_id": "evt_finalize_state",
          "created_at": "now",
          "payload": {
            "kind": "session_state_changed",
            "summary": "native Gear actions completed; returning structured host results to the SDK runtime so the agent can write the user-facing reply"
          }
        },
        {
          "event_id": "evt_host_completed_state",
          "session_id": "session_phase3",
          "parent_event_id": "evt_host_result_return_state",
          "created_at": "now",
          "payload": {
            "kind": "session_state_changed",
            "summary": "the SDK runtime continued after Gear host results and completed the active user turn"
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
}
