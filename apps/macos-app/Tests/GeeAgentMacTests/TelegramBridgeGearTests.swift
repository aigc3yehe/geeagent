import XCTest
@testable import GeeAgentMac

final class TelegramBridgeGearTests: XCTestCase {
    func testManifestDeclaresPushOnlyCapabilities() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/telegram.bridge/gear.json")
        let data = try Data(contentsOf: manifestURL)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rawAgent = try XCTUnwrap(raw["agent"] as? [String: Any])
        let rawCapabilities = try XCTUnwrap(rawAgent["capabilities"] as? [[String: Any]])

        XCTAssertEqual(manifest.id, TelegramBridgeGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.nativeID, TelegramBridgeGearDescriptor.gearID)
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(manifest.agent?.capabilities.map(\.id), [
            "telegram_bridge.status",
            "telegram_push.list_channels",
            "telegram_push.upsert_channel",
            "telegram_push.send_message",
            "telegram_push.send_file",
            "telegram_direct.send_file"
        ])
        XCTAssertEqual(rawAgent["enabled"] as? Bool, true)
        let exportsByID = Dictionary(
            uniqueKeysWithValues: rawCapabilities.compactMap { capability -> (String, Bool)? in
                guard let id = capability["id"] as? String,
                      let exports = capability["exports"] as? [String: Any],
                      let codex = exports["codex"] as? [String: Any],
                      let enabled = codex["enabled"] as? Bool
                else {
                    return nil
                }
                return (id, enabled)
            }
        )
        XCTAssertEqual(exportsByID["telegram_bridge.status"], true)
        XCTAssertEqual(exportsByID["telegram_push.list_channels"], true)
        XCTAssertEqual(exportsByID["telegram_push.upsert_channel"], false)
        XCTAssertEqual(exportsByID["telegram_push.send_message"], true)
        XCTAssertEqual(exportsByID["telegram_push.send_file"], true)
        XCTAssertEqual(exportsByID["telegram_direct.send_file"], false)
    }

    func testNativeWindowDescriptorIsRegistered() {
        XCTAssertTrue(
            GearHost.nativeWindowDescriptors.contains { descriptor in
                descriptor.gearID == TelegramBridgeGearDescriptor.gearID &&
                descriptor.windowID == GearHost.telegramBridgeWindowID
            }
        )
    }

    func testNativeGatewayEnvelopeBuildsRuntimePayload() throws {
        let account = TelegramBridgeAccountConfig(
            id: "gee_direct_default",
            role: "gee_direct",
            botUsername: "gee_bot",
            transport: .init(mode: "polling"),
            security: .init(
                allowUserIds: ["7973901539"],
                allowChatIds: ["7973901539"],
                requirePairing: false,
                groupPolicy: "deny"
            ),
            push: nil,
            codex: nil
        )
        let update = try telegramTextUpdate(
            updateID: 491738609,
            messageID: 35,
            chatID: "7973901539",
            fromUserID: "7973901539",
            text: "hello gee"
        )

        guard case .accepted(let envelope) = TelegramBridgeGateway.normalize(account: account, update: update) else {
            return XCTFail("Expected Telegram update to normalize into a Gateway envelope.")
        }
        let security = TelegramBridgeGateway.authorize(account: account, envelope: envelope)
        let payload = TelegramBridgeGateway.runtimePayload(envelope: envelope, security: security)

        XCTAssertEqual(envelope.idempotencyKey, "telegram:update:491738609")
        XCTAssertEqual(envelope.channelIdentity, "telegram:gee_direct_default:chat:7973901539")
        XCTAssertEqual(envelope.messageID, "35")
        XCTAssertEqual(envelope.runtimeMessageID, "35")
        XCTAssertEqual(security.decision, "allowed")
        XCTAssertEqual(security.policyID, "telegram.allowlist")
        XCTAssertEqual(payload.channelIdentity, "telegram:gee_direct_default:chat:7973901539")
        XCTAssertEqual(payload.message.telegramUpdateId, 491738609)
        XCTAssertEqual(payload.message.messageId, "35")
        XCTAssertEqual(payload.message.fromUserId, "7973901539")
        XCTAssertEqual(payload.message.text, "hello gee")
        XCTAssertEqual(payload.security.decision, "allowed")
        XCTAssertEqual(payload.security.policyId, "telegram.allowlist")
        XCTAssertEqual(payload.projection.replyTarget.chatId, "7973901539")
    }

    func testNativeGatewayMentionRequiredGroupPolicy() throws {
        let account = TelegramBridgeAccountConfig(
            id: "gee_direct_default",
            role: "gee_direct",
            botUsername: "@gee_bot",
            transport: .init(mode: "polling"),
            security: .init(
                allowUserIds: ["7973901539"],
                allowChatIds: [],
                requirePairing: false,
                groupPolicy: "mention_required"
            ),
            push: nil,
            codex: nil
        )
        let blockedUpdate = try telegramTextUpdate(
            updateID: 491738610,
            messageID: 36,
            chatID: "-1001",
            fromUserID: "7973901539",
            text: "hello gee",
            chatType: "supergroup"
        )
        guard case .accepted(let blockedEnvelope) = TelegramBridgeGateway.normalize(account: account, update: blockedUpdate) else {
            return XCTFail("Expected group update to normalize.")
        }

        let blocked = TelegramBridgeGateway.authorize(account: account, envelope: blockedEnvelope)

        XCTAssertEqual(blocked.decision, "denied")
        XCTAssertEqual(blocked.policyID, "telegram.group_mention_required")

        let allowedUpdate = try telegramTextUpdate(
            updateID: 491738611,
            messageID: 37,
            chatID: "-1001",
            fromUserID: "7973901539",
            text: "@gee_bot hello",
            chatType: "supergroup"
        )
        guard case .accepted(let allowedEnvelope) = TelegramBridgeGateway.normalize(account: account, update: allowedUpdate) else {
            return XCTFail("Expected mentioned group update to normalize.")
        }

        let allowed = TelegramBridgeGateway.authorize(account: account, envelope: allowedEnvelope)

        XCTAssertEqual(allowed.decision, "allowed")
        XCTAssertEqual(allowed.policyID, "telegram.allowlist")
    }

    func testNativeGatewayBuildsMediaArtifactReferences() throws {
        let account = TelegramBridgeAccountConfig(
            id: "gee_direct_default",
            role: "gee_direct",
            botUsername: "gee_bot",
            transport: .init(mode: "polling"),
            security: .init(
                allowUserIds: ["7973901539"],
                allowChatIds: ["7973901539"],
                requirePairing: false,
                groupPolicy: "deny"
            ),
            push: nil,
            codex: nil
        )
        let updateData = Data(
            """
            {
              "update_id": 491738612,
              "message": {
                "message_id": 38,
                "chat": { "id": 7973901539, "type": "private" },
                "from": { "id": 7973901539 },
                "caption": "photo caption",
                "photo": [
                  { "file_id": "photo_file_id", "file_unique_id": "photo_unique_id", "width": 800, "height": 600 }
                ]
              }
            }
            """.utf8
        )
        let update = try JSONDecoder().decode(TelegramBridgeSender.Update.self, from: updateData)

        guard case .accepted(let envelope) = TelegramBridgeGateway.normalize(account: account, update: update) else {
            return XCTFail("Expected media updates to normalize into Telegram artifact references.")
        }
        let payload = TelegramBridgeGateway.runtimePayload(
            envelope: envelope,
            security: .init(decision: "allowed", policyID: "telegram.allowlist")
        )

        XCTAssertEqual(envelope.text, "photo caption")
        XCTAssertEqual(payload.message.attachments, [
            TelegramChannelMessageAttachmentRef(
                artifactId: "telegram:gee_direct_default:491738612:photo:photo_unique_id",
                kind: "telegram_file",
                type: "image",
                title: "Telegram photo",
                uri: "telegram://file/photo_file_id",
                summary: "Telegram photo attachment from chat 7973901539 message 38.",
                mimeType: "image/*",
                telegramFileId: "photo_file_id",
                telegramFileUniqueId: "photo_unique_id",
                telegramMediaKind: "photo",
                width: 800,
                height: 600
            )
        ])
    }

    func testNativeGatewayDropsUnsupportedMediaAttachments() throws {
        let account = TelegramBridgeAccountConfig(
            id: "gee_direct_default",
            role: "gee_direct",
            botUsername: "gee_bot",
            transport: .init(mode: "polling"),
            security: .init(
                allowUserIds: ["7973901539"],
                allowChatIds: ["7973901539"],
                requirePairing: false,
                groupPolicy: "deny"
            ),
            push: nil,
            codex: nil
        )
        let updateData = Data(
            """
            {
              "update_id": 491738613,
              "message": {
                "message_id": 39,
                "chat": { "id": 7973901539, "type": "private" },
                "from": { "id": 7973901539 },
                "caption": "paid media caption",
                "paid_media": {}
              }
            }
            """.utf8
        )
        let update = try JSONDecoder().decode(TelegramBridgeSender.Update.self, from: updateData)

        guard case .dropped(let updateID, let code) = TelegramBridgeGateway.normalize(account: account, update: update) else {
            return XCTFail("Expected unsupported media to be dropped before caption-only runtime forwarding.")
        }

        XCTAssertEqual(updateID, 491738613)
        XCTAssertEqual(code, "telegram.message_attachment_unsupported")
    }

    func testNativeGatewayOutboundEvidenceMapsDeliveryResult() {
        let projection = TelegramBridgeGatewayOutboundProjection(
            chatID: "7973901539",
            text: "reply text",
            parseMode: nil,
            disableWebPreview: true,
            successStatus: "codex_replied",
            successUpdateID: nil,
            failureUpdateID: 491738612
        )

        let success = TelegramBridgeGateway.outboundEvidence(
            projection: projection,
            result: .success(telegramMessageID: "42", sentAt: "2026-05-07T02:40:01Z")
        )
        XCTAssertEqual(success.chatID, "7973901539")
        XCTAssertEqual(success.text, "reply text")
        XCTAssertEqual(success.messageID, "42")
        XCTAssertNil(success.updateID)
        XCTAssertEqual(success.status, "codex_replied")

        let failure = TelegramBridgeGateway.outboundEvidence(
            projection: projection,
            result: .failure(
                status: "degraded",
                code: "network_unavailable",
                message: "network down",
                retryAfterMs: nil
            )
        )
        XCTAssertEqual(failure.text, "network down")
        XCTAssertNil(failure.messageID)
        XCTAssertEqual(failure.updateID, 491738612)
        XCTAssertEqual(failure.status, "network_unavailable")

        let thrown = TelegramBridgeGateway.outboundExceptionEvidence(
            projection: projection,
            errorMessage: "send threw"
        )
        XCTAssertEqual(thrown.text, "send threw")
        XCTAssertNil(thrown.messageID)
        XCTAssertEqual(thrown.updateID, 491738612)
        XCTAssertEqual(thrown.status, "telegram_send_failed")
    }

    func testCodexRemoteSessionStateTransitionsAreSingleRecord() {
        var state = TelegramCodexRemoteSessionState()

        XCTAssertNil(state.selectedThreadID)
        XCTAssertNil(state.pendingPrompt)
        XCTAssertEqual(state.projectListMode, .all)
        XCTAssertFalse(state.awaitingNewCodexPrompt)
        XCTAssertTrue(state.lastThreadIDs.isEmpty)
        XCTAssertNil(state.lastThreadListSource)

        state.selectThread("thread-a")
        state.stagePrompt(sessionID: "thread-a", prompt: "please continue")
        state.rememberThreadList(["thread-a", "thread-b"])

        XCTAssertEqual(state.selectedThreadID, "thread-a")
        XCTAssertEqual(state.pendingPrompt?.prompt, "please continue")
        XCTAssertEqual(state.lastThreadIDs, ["thread-a", "thread-b"])
        XCTAssertEqual(state.lastThreadListSource, .desktop)

        XCTAssertNil(state.popPendingPrompt(matching: "thread-b"))
        XCTAssertEqual(state.pendingPrompt?.sessionID, "thread-a")

        let pending = state.popPendingPrompt(matching: "thread-a")
        XCTAssertEqual(pending?.prompt, "please continue")
        XCTAssertNil(state.pendingPrompt)

        state.stagePrompt(sessionID: "thread-a", prompt: "draft")
        state.prepareProjectList(mode: .tracked)

        XCTAssertNil(state.selectedThreadID)
        XCTAssertNil(state.pendingPrompt)
        XCTAssertEqual(state.projectListMode, .tracked)
        XCTAssertFalse(state.awaitingNewCodexPrompt)
        XCTAssertTrue(state.lastThreadIDs.isEmpty)
        XCTAssertNil(state.lastThreadListSource)

        state.requestNewCodexPrompt()
        XCTAssertTrue(state.awaitingNewCodexPrompt)
        XCTAssertNil(state.lastThreadListSource)
        state.stageNewCodexPrompt("start fresh")
        XCTAssertFalse(state.awaitingNewCodexPrompt)
        XCTAssertEqual(state.pendingPrompt?.sessionID, "newcodex")
        XCTAssertEqual(state.pendingPrompt?.prompt, "start fresh")
    }

    func testCodexRemoteRouterParsesTextAndCallbackRoutes() {
        XCTAssertEqual(TelegramCodexRemoteRouter.route("  /LIST@gee_bot  "), .list)
        XCTAssertEqual(TelegramCodexRemoteRouter.route("/newcodex start fresh"), .newCodex(prompt: "start fresh"))
        XCTAssertEqual(TelegramCodexRemoteRouter.route("/codexdesktop capture this"), .unsupported)
        XCTAssertEqual(TelegramCodexRemoteRouter.route("/mycodex"), .myCodex)
        XCTAssertEqual(TelegramCodexRemoteRouter.route("/mycodexPage 2"), .myCodexPage(page: 2))
        XCTAssertEqual(TelegramCodexRemoteRouter.route("please continue"), .plainText(prompt: "please continue"))
        XCTAssertEqual(
            TelegramCodexRemoteRouter.route("have Codex download this page video and summarize it"),
            .plainText(prompt: "have Codex download this page video and summarize it")
        )
        XCTAssertEqual(
            TelegramCodexRemoteRouter.route("/send thread-a please continue"),
            .send(arguments: "thread-a please continue")
        )
        XCTAssertEqual(
            TelegramCodexRemoteRouter.route("/send please continue"),
            .send(arguments: "please continue")
        )
        XCTAssertEqual(
            TelegramCodexRemoteRouter.commandText(forCallbackData: "threadPage:3:2"),
            "/threadPage 3 2"
        )
        XCTAssertEqual(
            TelegramCodexRemoteRouter.route(forCallbackData: "threadPage:3:2"),
            .threadPage(selector: "3", page: 2)
        )
        XCTAssertEqual(
            TelegramCodexRemoteRouter.route(forCallbackData: "confirm:thread-a"),
            .confirm(selector: "thread-a")
        )
        XCTAssertEqual(
            TelegramCodexRemoteRouter.route(forCallbackData: "mycodexPage:2"),
            .myCodexPage(page: 2)
        )
        XCTAssertNil(TelegramCodexRemoteRouter.route(forCallbackData: "unknown:1"))
    }

    func testCodexRemoteSendPlannerDisambiguatesSelectedAndExplicitSession() {
        let existingSessions: Set<String> = ["thread-a"]
        let exists: (String) -> Bool = { existingSessions.contains($0) }

        XCTAssertEqual(
            TelegramCodexRemoteSendPlanner.decision(
                arguments: "please continue",
                selectedSessionID: "selected-thread",
                explicitSessionExists: exists
            ),
            .stageSelected(sessionID: "selected-thread", prompt: "please continue")
        )
        XCTAssertEqual(
            TelegramCodexRemoteSendPlanner.decision(
                arguments: "thread-a please continue",
                selectedSessionID: "selected-thread",
                explicitSessionExists: exists
            ),
            .sendExplicit(sessionID: "thread-a", prompt: "please continue")
        )
        XCTAssertEqual(
            TelegramCodexRemoteSendPlanner.decision(
                arguments: "thread-b please continue",
                selectedSessionID: nil,
                explicitSessionExists: exists
            ),
            .sendExplicit(sessionID: "thread-b", prompt: "please continue")
        )
        XCTAssertEqual(
            TelegramCodexRemoteSendPlanner.decision(
                arguments: "thread-b",
                selectedSessionID: nil,
                explicitSessionExists: exists
            ),
            .blocked
        )
    }

    func testSoftwareTokenStorePersistsTokenInAppDataFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-token-store-\(UUID().uuidString)", isDirectory: true)
        let tokenURL = directory.appendingPathComponent("tokens.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TelegramBridgeTokenStore(storageURL: tokenURL)
        try store.saveToken("123456:secret", accountID: "gee_direct_default")

        XCTAssertEqual(try store.token(accountID: "gee_direct_default"), "123456:secret")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tokenURL.path))

        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: tokenURL)) as? [String: Any])
        let tokens = try XCTUnwrap(raw["tokens"] as? [String: String])
        XCTAssertEqual(tokens["gee_direct_default"], "123456:secret")

        let attributes = try FileManager.default.attributesOfItem(atPath: tokenURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: Int16(0o600)))
    }

    func testSoftwareTokenStoreReportsMissingTokenWithoutSystemPrompt() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-token-store-\(UUID().uuidString)", isDirectory: true)
        let tokenURL = directory.appendingPathComponent("tokens.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TelegramBridgeTokenStore(storageURL: tokenURL)
        let status = store.status(accountID: "gee_direct_default")

        XCTAssertFalse(status.configured)
        XCTAssertEqual(status.status, "missing")
        XCTAssertNil(status.error)
    }

    @MainActor
    func testStatusPayloadReportsGatewayHealthDiagnostics() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = TelegramBridgeFileDatabase(dataDirectoryURL: directory)
        let tokenStore = TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        try database.saveConfig(
            TelegramBridgeConfigFile(
                accounts: [
                    TelegramBridgeAccountConfig(
                        id: "gee_direct_default",
                        role: "gee_direct",
                        botUsername: "gee_bot",
                        transport: .init(mode: "polling"),
                        security: nil,
                        push: nil,
                        codex: nil
                    ),
                    TelegramBridgeAccountConfig(
                        id: "codex_remote_default",
                        role: "codex_remote",
                        botUsername: "codex_bot",
                        transport: .init(mode: "webhook"),
                        security: nil,
                        push: nil,
                        codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
                    ),
                    TelegramBridgeAccountConfig(
                        id: "news_push",
                        role: "push_only",
                        botUsername: nil,
                        transport: .init(mode: "outbound_only"),
                        security: nil,
                        push: .init(acceptInbound: false),
                        codex: nil
                    )
                ],
                pushChannels: [
                    TelegramBridgePushChannelConfig(
                        id: "morning_news",
                        title: "Morning News",
                        accountId: "news_push",
                        enabled: true,
                        target: .init(kind: "chat_id", value: "123456"),
                        format: nil
                    ),
                    TelegramBridgePushChannelConfig(
                        id: "quiet_news",
                        title: "Quiet News",
                        accountId: "news_push",
                        enabled: false,
                        target: .init(kind: "chat_id", value: "789000"),
                        format: nil
                    )
                ]
            )
        )
        try database.savePollingState(TelegramBridgePollingState(offsets: ["gee_direct_default": 120]))
        try tokenStore.saveToken("123456:codex", accountID: "codex_remote_default")
        try tokenStore.saveToken("123456:push", accountID: "news_push")
        let store = TelegramBridgeGearStore(database: database, tokenStore: tokenStore)

        let result = await store.runAgentAction(capabilityID: "telegram_bridge.status", args: [:])

        XCTAssertEqual(result["status"] as? String, "success")
        let health = try XCTUnwrap(result["gateway_health"] as? [String: Any])
        XCTAssertEqual(health["status"] as? String, "failed")
        XCTAssertEqual(health["fallback_attempted"] as? Bool, false)
        XCTAssertEqual(health["polling_account_count"] as? Int, 1)
        XCTAssertEqual(health["webhook_account_count"] as? Int, 1)
        XCTAssertEqual(health["push_only_account_count"] as? Int, 1)
        XCTAssertEqual(health["enabled_push_channel_count"] as? Int, 1)
        XCTAssertEqual(health["disabled_push_channel_count"] as? Int, 1)
        XCTAssertEqual(health["missing_token_account_ids"] as? [String], ["gee_direct_default"])
        XCTAssertEqual(health["webhook_account_ids"] as? [String], ["codex_remote_default"])
        let issues = try XCTUnwrap(health["issues"] as? [[String: Any]])
        XCTAssertEqual(issues.compactMap { $0["code"] as? String }, [
            "token_missing",
            "webhook_transport_not_ready"
        ])
        let accounts = try XCTUnwrap(health["accounts"] as? [[String: Any]])
        XCTAssertEqual(accounts.first?["polling_offset"] as? Int, 120)
        let lifecycle = try XCTUnwrap(health["lifecycle"] as? [String: Any])
        XCTAssertEqual(lifecycle["mode"] as? String, "native_app")
        XCTAssertEqual(lifecycle["polling_loop"] as? String, "stopped")
        XCTAssertEqual(lifecycle["poll_interval_ms"] as? Int, 2_000)
        XCTAssertEqual(lifecycle["webhook_ready"] as? Bool, false)
        XCTAssertEqual(lifecycle["webhook_status"] as? String, "not_implemented")
        XCTAssertEqual(lifecycle["fallback_attempted"] as? Bool, false)
    }

    @MainActor
    func testStatusPayloadReportsRunningInboundLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = TelegramBridgeFileDatabase(dataDirectoryURL: directory)
        try database.saveConfig(TelegramBridgeConfigFile())
        let store = TelegramBridgeGearStore(
            database: database,
            tokenStore: TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        )

        store.startInboundService { _ in nil }
        defer { store.stopInboundService() }

        let result = await store.runAgentAction(capabilityID: "telegram_bridge.status", args: [:])

        XCTAssertEqual(result["status"] as? String, "success")
        let health = try XCTUnwrap(result["gateway_health"] as? [String: Any])
        let lifecycle = try XCTUnwrap(health["lifecycle"] as? [String: Any])
        XCTAssertEqual(lifecycle["mode"] as? String, "native_app")
        XCTAssertEqual(lifecycle["polling_loop"] as? String, "running")
        XCTAssertEqual(lifecycle["poll_interval_ms"] as? Int, 2_000)
        XCTAssertEqual(lifecycle["webhook_ready"] as? Bool, false)
        XCTAssertEqual(lifecycle["webhook_status"] as? String, "not_implemented")
        XCTAssertEqual(lifecycle["fallback_attempted"] as? Bool, false)
    }

    @MainActor
    func testDeletesConversationBotAndItsLocalToken() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TelegramBridgeGearStore(
            database: TelegramBridgeFileDatabase(dataDirectoryURL: directory),
            tokenStore: TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        )
        try store.upsertConversationBot(
            role: "gee_direct",
            accountID: "gee_direct_default",
            botUsername: "gee_bot",
            allowUserIds: ["123"],
            allowChatIds: [],
            groupPolicy: "mention_required",
            codexThreadSource: nil,
            codexSendMode: nil,
            token: "123456:secret"
        )

        XCTAssertTrue(store.tokenStatus(accountID: "gee_direct_default").configured)

        try store.deleteConversationBot(accountID: "gee_direct_default")

        XCTAssertFalse(store.config.accounts.contains { $0.id == "gee_direct_default" })
        XCTAssertFalse(store.tokenStatus(accountID: "gee_direct_default").configured)
    }

    @MainActor
    func testDeletesPushChannelAndThenUnusedPushAccount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TelegramBridgeGearStore(
            database: TelegramBridgeFileDatabase(dataDirectoryURL: directory),
            tokenStore: TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        )
        try store.saveBotToken(accountID: "news_push", token: "123456:secret")
        let result = await store.runAgentAction(
            capabilityID: "telegram_push.upsert_channel",
            args: [
                "channel_id": "morning_news",
                "account_id": "news_push",
                "target_kind": "chat_id",
                "target_value": "123"
            ]
        )
        XCTAssertEqual(result["status"] as? String, "success")

        try store.deletePushChannel(channelID: "morning_news")

        XCTAssertFalse(store.config.pushChannels.contains { $0.id == "morning_news" })
        XCTAssertTrue(store.config.accounts.contains { $0.id == "news_push" })

        try store.deletePushAccount(accountID: "news_push")

        XCTAssertFalse(store.config.accounts.contains { $0.id == "news_push" })
        XCTAssertFalse(store.tokenStatus(accountID: "news_push").configured)
    }

    @MainActor
    func testPushSendAllowsLongPlainTextToReachDeliveryPath() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TelegramBridgeGearStore(
            database: TelegramBridgeFileDatabase(dataDirectoryURL: directory),
            tokenStore: TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        )
        _ = await store.runAgentAction(
            capabilityID: "telegram_push.upsert_channel",
            args: [
                "channel_id": "morning_news",
                "account_id": "news_push",
                "target_kind": "chat_id",
                "target_value": "123"
            ]
        )

        let result = await store.runAgentAction(
            capabilityID: "telegram_push.send_message",
            args: [
                "channel_id": "morning_news",
                "message": String(repeating: "morning news ", count: 450),
                "idempotency_key": "long-push-\(UUID().uuidString)"
            ]
        )

        XCTAssertEqual(result["status"] as? String, "failed")
        let error = try XCTUnwrap(result["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "token_missing")
    }

    @MainActor
    func testPushFileCapabilitySendsReadableLocalFileToConfiguredChannel() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("report.mp4", isDirectory: false)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x00, 0x01, 0x02]).write(to: fileURL)

        let sender = RecordingTelegramBridgeSender(
            updates: [],
            sendResult: .success(telegramMessageID: "2002", sentAt: "2026-05-06T08:00:00Z")
        )
        let database = TelegramBridgeFileDatabase(dataDirectoryURL: directory)
        let store = TelegramBridgeGearStore(
            database: database,
            tokenStore: TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json")),
            sender: sender
        )
        try store.saveBotToken(accountID: "news_push", token: "123456:secret")
        _ = await store.runAgentAction(
            capabilityID: "telegram_push.upsert_channel",
            args: [
                "channel_id": "morning_news",
                "account_id": "news_push",
                "target_kind": "chat_id",
                "target_value": "123"
            ]
        )

        let result = await store.runAgentAction(
            capabilityID: "telegram_push.send_file",
            args: [
                "channel_id": "morning_news",
                "file_path": fileURL.path,
                "caption": "Daily clip",
                "idempotency_key": "push-file-\(UUID().uuidString)"
            ]
        )

        XCTAssertEqual(result["status"] as? String, "success")
        XCTAssertEqual(result["capability_id"] as? String, "telegram_push.send_file")
        XCTAssertEqual(result["fallback_attempted"] as? Bool, false)
        XCTAssertEqual(result["channelId"] as? String, "morning_news")
        XCTAssertEqual(result["accountId"] as? String, "news_push")
        let file = try XCTUnwrap(result["file"] as? [String: Any])
        XCTAssertEqual(file["path"] as? String, fileURL.path)
        XCTAssertEqual(file["name"] as? String, "report.mp4")
        let delivery = try XCTUnwrap(result["delivery"] as? [String: Any])
        XCTAssertEqual(delivery["telegramMessageId"] as? String, "2002")
        XCTAssertEqual(delivery["reused"] as? Bool, false)

        XCTAssertEqual(sender.sentLocalFiles.count, 1)
        let sentFile = try XCTUnwrap(sender.sentLocalFiles.first)
        XCTAssertEqual(sentFile.target.value, "123")
        XCTAssertEqual(sentFile.fileURL, fileURL.standardizedFileURL)
        XCTAssertEqual(sentFile.caption, "Daily clip")
    }

    @MainActor
    func testDirectFileCapabilityBlocksMissingLocalFileBeforeNetworkSend() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TelegramBridgeGearStore(
            database: TelegramBridgeFileDatabase(dataDirectoryURL: directory),
            tokenStore: TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        )
        try store.upsertConversationBot(
            role: "gee_direct",
            accountID: "gee_direct_default",
            botUsername: "gee_bot",
            allowUserIds: [],
            allowChatIds: [],
            groupPolicy: "deny",
            codexThreadSource: nil,
            codexSendMode: nil,
            token: "123456:secret"
        )

        let missingPath = directory.appendingPathComponent("missing-image.png").path
        let result = await store.runAgentAction(
            capabilityID: "telegram_direct.send_file",
            args: [
                "account_id": "gee_direct_default",
                "chat_id": "7973901539",
                "file_path": missingPath,
                "idempotency_key": "direct-file-\(UUID().uuidString)"
            ]
        )

        XCTAssertEqual(result["status"] as? String, "failed")
        XCTAssertEqual(result["capability_id"] as? String, "telegram_direct.send_file")
        XCTAssertEqual(result["fallback_attempted"] as? Bool, false)
        let error = try XCTUnwrap(result["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "file_not_found")
        XCTAssertEqual(result["accountId"] as? String, "gee_direct_default")
        XCTAssertEqual(result["chatId"] as? String, "7973901539")
    }

    @MainActor
    func testResetConversationThreadClearsTelegramTabHistoryForChat() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = TelegramBridgeFileDatabase(dataDirectoryURL: directory)
        try database.saveConversationLog(
            TelegramBridgeConversationLog(
                threads: [
                    TelegramBridgeConversationThread(
                        id: "gee_direct_default:7973901539",
                        accountId: "gee_direct_default",
                        accountRole: "gee_direct",
                        chatId: "7973901539",
                        title: "Telegram 7973901539",
                        updatedAt: "2026-05-04T01:55:27Z",
                        messages: [
                            TelegramBridgeConversationMessage(
                                id: "old-message",
                                direction: "inbound",
                                accountId: "gee_direct_default",
                                chatId: "7973901539",
                                messageId: "1",
                                updateId: 1,
                                text: "old context",
                                timestamp: "2026-05-04T01:55:27Z",
                                status: "allowed"
                            )
                        ]
                    )
                ]
            )
        )
        let store = TelegramBridgeGearStore(
            database: database,
            tokenStore: TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        )

        try store.resetConversationThread(
            accountID: "gee_direct_default",
            accountRole: "gee_direct",
            chatID: "7973901539"
        )

        let log = try database.loadConversationLog()
        XCTAssertFalse(log.threads.contains { $0.id == "gee_direct_default:7973901539" })
        XCTAssertFalse(store.conversationLog.threads.contains { $0.id == "gee_direct_default:7973901539" })
    }

    @MainActor
    func testGeeDirectRuntimeFailureIsSentBackToTelegram() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let update = try telegramTextUpdate(
            updateID: 491738609,
            messageID: 35,
            chatID: "7973901539",
            fromUserID: "7973901539",
            text: "hello gee"
        )
        let sender = RecordingTelegramBridgeSender(
            updates: [update],
            sendResult: .success(telegramMessageID: "36", sentAt: "2026-05-06T07:28:59Z")
        )
        let database = TelegramBridgeFileDatabase(dataDirectoryURL: directory)
        let store = TelegramBridgeGearStore(
            database: database,
            tokenStore: TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json")),
            sender: sender
        )
        try store.upsertConversationBot(
            role: "gee_direct",
            accountID: "gee_direct_default",
            botUsername: "gee_bot",
            allowUserIds: ["7973901539"],
            allowChatIds: [],
            groupPolicy: "deny",
            codexThreadSource: nil,
            codexSendMode: nil,
            token: "123456:secret"
        )

        await store.pollInboundOnce { payload in
            XCTAssertEqual(payload.channelIdentity, "telegram:gee_direct_default:chat:7973901539")
            throw TelegramBridgeGearError.configInvalid("native runtime timed out")
        }

        XCTAssertEqual(sender.sentMessages.count, 1)
        let sentMessage = try XCTUnwrap(sender.sentMessages.first)
        XCTAssertEqual(sentMessage.target.value, "7973901539")
        XCTAssertTrue(sentMessage.text.contains("GeeAgent runtime failed before it could produce a reply."))
        XCTAssertTrue(sentMessage.text.contains("native runtime timed out"))
        XCTAssertFalse(sentMessage.text.contains("123456:secret"))

        let log = try database.loadConversationLog()
        let thread = try XCTUnwrap(log.threads.first { $0.id == "gee_direct_default:7973901539" })
        XCTAssertEqual(thread.messages.count, 2)
        XCTAssertEqual(thread.messages[0].direction, "inbound")
        XCTAssertEqual(thread.messages[0].status, "allowed")
        XCTAssertEqual(thread.messages[1].direction, "outbound")
        XCTAssertEqual(thread.messages[1].status, "runtime_failed")
        XCTAssertEqual(thread.messages[1].messageId, "36")
        XCTAssertEqual(thread.messages[1].updateId, 491738609)

        let state = try database.loadPollingState()
        XCTAssertEqual(state.offsets["gee_direct_default"], 491738610)
    }

    @MainActor
    func testGeeDirectEmptyRuntimeReplyStillRepliesToTelegram() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let update = try telegramTextUpdate(
            updateID: 491738620,
            messageID: 40,
            chatID: "7973901539",
            fromUserID: "7973901539",
            text: "please do a thing"
        )
        let sender = RecordingTelegramBridgeSender(
            updates: [update],
            sendResult: .success(telegramMessageID: "41", sentAt: "2026-05-06T07:29:59Z")
        )
        let database = TelegramBridgeFileDatabase(dataDirectoryURL: directory)
        let store = TelegramBridgeGearStore(
            database: database,
            tokenStore: TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json")),
            sender: sender
        )
        try store.upsertConversationBot(
            role: "gee_direct",
            accountID: "gee_direct_default",
            botUsername: "gee_bot",
            allowUserIds: ["7973901539"],
            allowChatIds: [],
            groupPolicy: "deny",
            codexThreadSource: nil,
            codexSendMode: nil,
            token: "123456:secret"
        )

        await store.pollInboundOnce { _ in nil }

        XCTAssertEqual(sender.sentMessages.count, 1)
        let sentMessage = try XCTUnwrap(sender.sentMessages.first)
        XCTAssertTrue(sentMessage.text.contains("GeeAgent runtime finished without a reply."))

        let log = try database.loadConversationLog()
        let thread = try XCTUnwrap(log.threads.first { $0.id == "gee_direct_default:7973901539" })
        XCTAssertEqual(thread.messages.last?.status, "runtime_empty_reply")
        let state = try database.loadPollingState()
        XCTAssertEqual(state.offsets["gee_direct_default"], 491738621)
    }

    @MainActor
    func testCodexRemoteTelegramSendTimeoutDoesNotBlockPollingOffset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let update = try telegramTextUpdate(
            updateID: 809369456,
            messageID: 133,
            chatID: "7973901539",
            fromUserID: "7973901539",
            text: "/list"
        )
        let sender = HangingTelegramBridgeSender(updates: [update])
        let database = TelegramBridgeFileDatabase(dataDirectoryURL: directory)
        try database.saveConfig(
            TelegramBridgeConfigFile(
                accounts: [
                    TelegramBridgeAccountConfig(
                        id: "codex_remote_default",
                        role: "codex_remote",
                        botUsername: nil,
                        transport: .init(mode: "polling"),
                        security: .init(
                            allowUserIds: ["7973901539"],
                            allowChatIds: [],
                            requirePairing: false,
                            groupPolicy: "deny"
                        ),
                        push: nil,
                        codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
                    )
                ],
                pushChannels: []
            )
        )
        let tokenStore = TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        try tokenStore.saveToken("123456:secret", accountID: "codex_remote_default")
        let codexRemote = TelegramCodexRemoteBridge(
            codexHomeURL: directory.appendingPathComponent(".codex", isDirectory: true),
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )
        let store = TelegramBridgeGearStore(
            database: database,
            tokenStore: tokenStore,
            sender: sender,
            codexRemote: codexRemote,
            telegramSendTimeoutSeconds: 0.05
        )

        await store.pollInboundOnce { _ -> String? in nil }

        let state = try database.loadPollingState()
        XCTAssertEqual(state.offsets["codex_remote_default"], 809369457)
        let log = try database.loadConversationLog()
        let thread = try XCTUnwrap(log.threads.first { $0.id == "codex_remote_default:7973901539" })
        XCTAssertEqual(thread.messages.map(\.status), ["allowed", "codex_remote_failed"])
        XCTAssertTrue(thread.messages.last?.text.contains("Telegram send timed out") == true)
    }

    @MainActor
    func testCodexRemotePollingRegistersNewCodexBotCommands() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sender = RecordingTelegramBridgeSender(
            updates: [],
            sendResult: .success(telegramMessageID: "36", sentAt: "2026-05-06T07:28:59Z")
        )
        let database = TelegramBridgeFileDatabase(dataDirectoryURL: directory)
        try database.saveConfig(
            TelegramBridgeConfigFile(
                accounts: [
                    TelegramBridgeAccountConfig(
                        id: "codex_remote_default",
                        role: "codex_remote",
                        botUsername: nil,
                        transport: .init(mode: "polling"),
                        security: nil,
                        push: nil,
                        codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
                    )
                ],
                pushChannels: []
            )
        )
        let tokenStore = TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        try tokenStore.saveToken("123456:secret", accountID: "codex_remote_default")
        let store = TelegramBridgeGearStore(
            database: database,
            tokenStore: tokenStore,
            sender: sender
        )

        await store.pollInboundOnce { _ -> String? in nil }

        let commands = try XCTUnwrap(sender.commandMenuUpdates.first).map(\.command)
        XCTAssertTrue(commands.contains("newcodex"))
        XCTAssertTrue(commands.contains("mycodex"))
    }

    @MainActor
    func testConversationDuplicateCheckUsesUpdateIDBeforeMessageID() {
        let store = TelegramBridgeGearStore()
        let existing = TelegramBridgeConversationMessage(
            id: "callback-1",
            direction: "inbound",
            accountId: "codex_remote_default",
            chatId: "7973901539",
            messageId: "10",
            updateId: 100,
            text: "[button] /project 1",
            timestamp: "2026-05-04T01:55:27Z",
            status: "allowed"
        )
        let thread = TelegramBridgeConversationThread(
            id: "codex_remote_default:7973901539",
            accountId: "codex_remote_default",
            accountRole: "codex_remote",
            chatId: "7973901539",
            title: "Telegram 7973901539",
            updatedAt: "2026-05-04T01:55:27Z",
            messages: [existing]
        )
        let secondCallback = TelegramBridgeConversationMessage(
            id: "callback-2",
            direction: "inbound",
            accountId: "codex_remote_default",
            chatId: "7973901539",
            messageId: "10",
            updateId: 101,
            text: "[button] /latest thread",
            timestamp: "2026-05-04T01:56:27Z",
            status: "allowed"
        )
        let sameUpdate = TelegramBridgeConversationMessage(
            id: "callback-duplicate",
            direction: "inbound",
            accountId: "codex_remote_default",
            chatId: "7973901539",
            messageId: "10",
            updateId: 100,
            text: "[button] /project 1",
            timestamp: "2026-05-04T01:56:27Z",
            status: "allowed"
        )

        XCTAssertFalse(store.shouldSkipDuplicateConversationMessage(thread, candidate: secondCallback))
        XCTAssertTrue(store.shouldSkipDuplicateConversationMessage(thread, candidate: sameUpdate))
    }

    @MainActor
    func testLatestUserIDUsesLocalConsumedConversationUpdateBeforeTelegramQueue() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = TelegramBridgeFileDatabase(dataDirectoryURL: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rawLog = """
        {
          "threads": [
            {
              "id": "gee_direct_default:7973901539",
              "accountId": "gee_direct_default",
              "accountRole": "gee_direct",
              "chatId": "7973901539",
              "title": "Telegram 7973901539",
              "updatedAt": "2026-05-04T01:55:27Z",
              "messages": [
                {
                  "id": "inbound-message",
                  "direction": "inbound",
                  "accountId": "gee_direct_default",
                  "chatId": "7973901539",
                  "messageId": "5",
                  "updateId": 491738594,
                  "fromUserId": "7973901539",
                  "text": "hello",
                  "timestamp": "2026-05-04T01:55:27Z",
                  "status": "allowed"
                }
              ]
            }
          ]
        }
        """
        try rawLog.write(to: database.conversationLogURL, atomically: true, encoding: .utf8)
        let store = TelegramBridgeGearStore(
            database: database,
            tokenStore: TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        )

        let userID = try await store.latestUserID(token: "")

        XCTAssertEqual(userID, "7973901539")
        XCTAssertEqual(store.conversationLog.threads.first?.messages.first?.fromUserId, "7973901539")
    }

    @MainActor
    func testLatestUserIDUsesRuntimeChannelIngressHistoryForOlderLocalLogs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        let gearDirectory = directory
            .appendingPathComponent("gear-data", isDirectory: true)
            .appendingPathComponent("telegram.bridge", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = TelegramBridgeFileDatabase(dataDirectoryURL: gearDirectory)
        try FileManager.default.createDirectory(at: gearDirectory, withIntermediateDirectories: true)
        let oldLocalLog = """
        {
          "threads": [
            {
              "id": "gee_direct_default:7973901539",
              "accountId": "gee_direct_default",
              "accountRole": "gee_direct",
              "chatId": "7973901539",
              "title": "Telegram 7973901539",
              "updatedAt": "2026-05-04T01:55:27Z",
              "messages": [
                {
                  "id": "old-inbound-message",
                  "direction": "inbound",
                  "accountId": "gee_direct_default",
                  "chatId": "7973901539",
                  "messageId": "5",
                  "updateId": 491738594,
                  "text": "hello",
                  "timestamp": "2026-05-04T01:55:27Z",
                  "status": "allowed"
                }
              ]
            }
          ]
        }
        """
        try oldLocalLog.write(to: database.conversationLogURL, atomically: true, encoding: .utf8)
        let runtimeStore = """
        {
          "transcript_events": [
            {
              "payload": {
                "kind": "channel_message_received",
                "channel": {
                  "source": "telegram.bridge",
                  "role": "gee_direct",
                  "channel_identity": "telegram:gee_direct_default:chat:7973901539",
                  "from_user_id": "7973901539"
                }
              }
            }
          ]
        }
        """
        try runtimeStore.write(to: directory.appendingPathComponent("runtime-store.json"), atomically: true, encoding: .utf8)
        let store = TelegramBridgeGearStore(
            database: database,
            tokenStore: TelegramBridgeTokenStore(storageURL: gearDirectory.appendingPathComponent("tokens.json"))
        )

        let userID = try await store.latestUserID(token: "", accountID: "gee_direct_default")

        XCTAssertEqual(userID, "7973901539")
    }

    @MainActor
    func testCodexRemoteListUsesEarlySessionMetadataWhenFileTailIsNotUTF8() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/04", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let sessionURL = sessions.appendingPathComponent("rollout-thread-fast.jsonl", isDirectory: false)
        let projectURL = directory.appendingPathComponent("fast-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try "codex test project".write(to: projectURL.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        var data = Data(
            """
            {"timestamp":"2026-05-04T10:00:00.000Z","type":"session_meta","payload":{"id":"thread_fast","cwd":"\(projectURL.path)","originator":"Codex Desktop","timestamp":"2026-05-04T10:00:00.000Z"}}
            {"timestamp":"2026-05-04T10:01:00.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Fast Codex thread"}}

            """.utf8
        )
        data.append(contentsOf: [0xff, 0xfe, 0xfd, 0x0a])
        try data.write(to: sessionURL)
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let reply = await bridge.reply(
            for: TelegramBridgeAccountConfig(
                id: "codex_remote_default",
                role: "codex_remote",
                botUsername: nil,
                transport: .init(mode: "polling"),
                security: nil,
                push: nil,
                codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
            ),
            text: "/list"
        )

        XCTAssertEqual(reply.status, "codex_success")
        XCTAssertTrue(reply.text.contains("Projects:"))
        XCTAssertTrue(reply.text.contains("fast-project"))

        let projectReply = await bridge.reply(
            for: TelegramBridgeAccountConfig(
                id: "codex_remote_default",
                role: "codex_remote",
                botUsername: nil,
                transport: .init(mode: "polling"),
                security: nil,
                push: nil,
                codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
            ),
            text: "/project 1"
        )

        XCTAssertEqual(projectReply.status, "codex_success")
        XCTAssertTrue(projectReply.text.contains("Fast Codex thread"))
        XCTAssertTrue(projectReply.text.contains("thread_fast"))
        let buttons = projectReply.replyMarkup?.inlineKeyboard.flatMap { $0 } ?? []
        XCTAssertTrue(buttons.contains { $0.callbackData == "open:thread_fast" })
        XCTAssertTrue(buttons.contains { $0.callbackData == "latest:thread_fast" })
        XCTAssertFalse(buttons.contains { $0.callbackData == "desktop:thread_fast" })
    }

    @MainActor
    func testCodexRemoteListGroupsByProjectAndHidesNonDesktopSessions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/04", isDirectory: true)
        let projectURL = directory.appendingPathComponent("visible-project", isDirectory: true)
        let nestedURL = projectURL.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        try """
        {"timestamp":"2026-05-04T10:00:00.000Z","type":"session_meta","payload":{"id":"visible_one","cwd":"\(nestedURL.path)","originator":"Codex Desktop","timestamp":"2026-05-04T10:00:00.000Z"}}
        {"timestamp":"2026-05-04T10:01:00.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Visible one"}}
        """.write(
            to: sessions.appendingPathComponent("rollout-visible-one.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {"timestamp":"2026-05-04T10:02:00.000Z","type":"session_meta","payload":{"id":"visible_two","cwd":"\(projectURL.path)","originator":"Codex Desktop","timestamp":"2026-05-04T10:02:00.000Z"}}
        {"timestamp":"2026-05-04T10:03:00.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Visible two"}}
        """.write(
            to: sessions.appendingPathComponent("rollout-visible-two.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {"timestamp":"2026-05-04T10:04:00.000Z","type":"session_meta","payload":{"id":"hidden_subagent","cwd":"\(projectURL.path)","originator":"Codex Desktop","agent_role":"explorer","timestamp":"2026-05-04T10:04:00.000Z"}}
        {"timestamp":"2026-05-04T10:05:00.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Hidden subagent"}}
        """.write(
            to: sessions.appendingPathComponent("rollout-hidden-subagent.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {"timestamp":"2026-05-04T10:06:00.000Z","type":"session_meta","payload":{"id":"hidden_cli","cwd":"\(projectURL.path)","originator":"Codex CLI","timestamp":"2026-05-04T10:06:00.000Z"}}
        {"timestamp":"2026-05-04T10:07:00.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Hidden CLI"}}
        """.write(
            to: sessions.appendingPathComponent("rollout-hidden-cli.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )
        let account = TelegramBridgeAccountConfig(
            id: "codex_remote_default",
            role: "codex_remote",
            botUsername: nil,
            transport: .init(mode: "polling"),
            security: nil,
            push: nil,
            codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
        )

        let listReply = await bridge.reply(for: account, text: "/list")

        XCTAssertEqual(listReply.status, "codex_success")
        XCTAssertTrue(listReply.text.contains("visible-project"))
        XCTAssertTrue(listReply.text.contains("App"))
        XCTAssertTrue(listReply.text.contains("1 thread(s)"))
        XCTAssertFalse(listReply.text.contains("Hidden subagent"))
        XCTAssertFalse(listReply.text.contains("Hidden CLI"))

        let firstProjectReply = await bridge.reply(for: account, text: "/project 1")
        let secondProjectReply = await bridge.reply(for: account, text: "/project 2")
        let combinedProjectText = [firstProjectReply.text, secondProjectReply.text].joined(separator: "\n")
        XCTAssertTrue(combinedProjectText.contains("Visible one"))
        XCTAssertTrue(combinedProjectText.contains("Visible two"))
        XCTAssertFalse(combinedProjectText.contains("Hidden subagent"))
        XCTAssertFalse(combinedProjectText.contains("Hidden CLI"))
    }

    @MainActor
    func testCodexRemoteThreadListSkipsSyntheticContextTitles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/08", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let projectURL = directory.appendingPathComponent("power-video-2026", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try """
        {"timestamp":"2026-05-08T04:10:28.377Z","type":"session_meta","payload":{"id":"thread_context_title","cwd":"\(projectURL.path)","originator":"Codex Desktop","timestamp":"2026-05-08T04:10:28.377Z","source":"vscode"}}
        {"timestamp":"2026-05-08T04:10:28.379Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>\\n  <cwd>\(projectURL.path)</cwd>\\n</environment_context>"}]}}
        {"timestamp":"2026-05-08T04:10:28.380Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# Files mentioned by the user:\\n\\n## gee-power-video: \(projectURL.path)/gee-power-video\\n\\n## My request for Codex:\\nUse the gee power video skill to produce the video."}]}}
        """.write(
            to: sessions.appendingPathComponent("rollout-context-title.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        _ = await bridge.reply(for: codexRemoteAccount(), text: "/list", chatID: "chat-1")
        let projectReply = await bridge.reply(for: codexRemoteAccount(), text: "/project 1", chatID: "chat-1")

        XCTAssertEqual(projectReply.status, "codex_success")
        XCTAssertTrue(projectReply.text.contains("Use the gee power video skill to produce the video."))
        XCTAssertFalse(projectReply.text.contains("<environment_context>"))
    }

    @MainActor
    func testCodexRemoteListKeepsProjectSummariesCompact() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/07", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let longProjectName = "project-" + String(repeating: "very-long-name-", count: 12)
        let projectURL = try makeCodexRemoteProjectRoot(directory: directory, name: longProjectName)
        let nestedURL = projectURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(String(repeating: "deep-folder-", count: 16), isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try writeCodexRemoteSession(
            sessionsDirectory: sessions,
            id: "compact_list_thread",
            title: String(repeating: "Huge title ", count: 80),
            cwd: nestedURL.path,
            timestamp: "2026-05-07T08:30:00.000Z"
        )
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let reply = await bridge.reply(for: codexRemoteAccount(), text: "/list", chatID: "chat-1")

        XCTAssertEqual(reply.status, "codex_success")
        XCTAssertLessThan(reply.text.count, 320)
        XCTAssertFalse(reply.text.contains(String(repeating: "deep-folder-", count: 8)))
        XCTAssertFalse(reply.text.contains(String(repeating: "Huge title ", count: 8)))
    }

    @MainActor
    func testCodexRemoteListUsesPersistedSessionIndexAcrossBridgeRestarts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/09", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let projectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "cached-index-project")
        try writeCodexRemoteSession(
            sessionsDirectory: sessions,
            id: "cached_index_thread",
            title: "Cached index thread",
            cwd: projectURL.path,
            timestamp: "2026-05-09T08:30:00.000Z"
        )
        let sessionIndexURL = directory.appendingPathComponent("codex-remote-session-index.json")
        let firstBridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex"),
            sessionIndexURL: sessionIndexURL
        )

        let firstReply = await firstBridge.reply(for: codexRemoteAccount(), text: "/list", chatID: "chat-1")
        XCTAssertEqual(firstReply.status, "codex_success")
        XCTAssertTrue(firstReply.text.contains("cached-index-project"))

        try FileManager.default.removeItem(at: codexHome.appendingPathComponent("sessions", isDirectory: true))
        let restartedBridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex"),
            sessionIndexURL: sessionIndexURL
        )

        let cachedReply = await restartedBridge.reply(
            for: codexRemoteAccount(),
            text: "/latest cached_index_thread",
            chatID: "chat-1"
        )

        XCTAssertEqual(cachedReply.status, "codex_success")
        XCTAssertTrue(cachedReply.text.contains("Cached index thread"))
        XCTAssertTrue(cachedReply.text.contains("No Codex reply found yet."))
    }

    @MainActor
    func testCodexRemoteExplicitListRefreshesRecentSessionIndex() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/09", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let oldProjectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "old-project")
        try writeCodexRemoteSession(
            sessionsDirectory: sessions,
            id: "old_project_thread",
            title: "Old project thread",
            cwd: oldProjectURL.path,
            timestamp: "2026-05-09T08:00:00.000Z"
        )
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let firstReply = await bridge.reply(for: codexRemoteAccount(), text: "/list", chatID: "chat-1")
        XCTAssertEqual(firstReply.status, "codex_success")
        XCTAssertTrue(firstReply.text.contains("old-project"))

        let freshProjectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "fresh-project")
        try writeCodexRemoteSession(
            sessionsDirectory: sessions,
            id: "fresh_project_thread",
            title: "Fresh project thread",
            cwd: freshProjectURL.path,
            timestamp: "2026-05-09T09:00:00.000Z"
        )

        let refreshedReply = await bridge.reply(for: codexRemoteAccount(), text: "/list", chatID: "chat-1")

        XCTAssertEqual(refreshedReply.status, "codex_success")
        XCTAssertTrue(refreshedReply.text.contains("fresh-project"))
    }

    @MainActor
    func testCodexRemoteListUsesRecordedCwdEvenWhenWorkspaceIsMissing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/09", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let missingWorkspaceURL = directory.appendingPathComponent("missing-workspace", isDirectory: true)
        try writeCodexRemoteSession(
            sessionsDirectory: sessions,
            id: "missing_workspace_thread",
            title: "Missing workspace thread",
            cwd: missingWorkspaceURL.path,
            timestamp: "2026-05-09T08:30:00.000Z"
        )
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let reply = await bridge.reply(for: codexRemoteAccount(), text: "/list", chatID: "chat-1")

        XCTAssertEqual(reply.status, "codex_success")
        XCTAssertTrue(reply.text.contains("missing-workspace"))
        XCTAssertFalse(reply.text.contains("Global"))
    }

    @MainActor
    func testCodexRemoteListParsesHugeSessionMetaAndPaginatesWorkspaceProjects() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/09", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let parentRepo = try makeCodexRemoteProjectRoot(directory: directory, name: "skills-uniteyoo")
        let anyaProject = parentRepo.appendingPathComponent("anya2026", isDirectory: true)
        try FileManager.default.createDirectory(at: anyaProject, withIntermediateDirectories: true)
        try writeCodexRemoteHugeSessionMeta(
            sessionsDirectory: sessions,
            id: "anya_direct_thread",
            cwd: anyaProject.path,
            timestamp: "2026-05-09T09:22:00.000Z"
        )

        for index in 1...7 {
            let projectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "other-project-\(index)")
            try writeCodexRemoteSession(
                sessionsDirectory: sessions,
                id: "other_project_\(index)",
                title: "Other \(index)",
                cwd: projectURL.path,
                timestamp: String(format: "2026-05-09T09:%02d:00.000Z", index)
            )
        }

        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let firstPage = await bridge.reply(for: codexRemoteAccount(), text: "/list", chatID: "chat-1")

        XCTAssertEqual(firstPage.status, "codex_success")
        XCTAssertTrue(firstPage.text.contains("Projects (page 1 of 2):"))
        XCTAssertTrue(firstPage.text.contains("anya2026"))
        XCTAssertFalse(firstPage.text.contains("skills-uniteyoo\n   1 thread(s)"))
        XCTAssertTrue(telegramButtons(firstPage).contains { $0.callbackData == "projectPage:2" })
    }

    @MainActor
    func testCodexRemoteFileScanOnlyUsesRecentBoundedSessionDirectories() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let projectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "bounded-scan-project")
        for day in 1...20 {
            let dayString = String(format: "%02d", day)
            let sessions = codexHome
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent("2026/05/\(dayString)", isDirectory: true)
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            try writeCodexRemoteSession(
                sessionsDirectory: sessions,
                id: day == 1 ? "old_thread" : "thread_\(dayString)",
                title: "Thread \(dayString)",
                cwd: projectURL.path,
                timestamp: "2026-05-\(dayString)T10:00:00.000Z"
            )
        }
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let recentReply = await bridge.reply(for: codexRemoteAccount(), text: "/latest thread_20", chatID: "chat-1")
        let oldReply = await bridge.reply(for: codexRemoteAccount(), text: "/latest old_thread", chatID: "chat-1")

        XCTAssertEqual(recentReply.status, "codex_success")
        XCTAssertEqual(oldReply.status, "codex_failed")
        XCTAssertTrue(oldReply.text.contains("Session not found: old_thread"))
    }

    @MainActor
    func testCodexRemotePaginatesProjectAndThreadLists() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/05", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        for index in 1...8 {
            let projectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "project-\(index)")
            try writeCodexRemoteSession(
                sessionsDirectory: sessions,
                id: "project_\(index)",
                title: "Project \(index) thread",
                cwd: projectURL.path,
                timestamp: String(format: "2026-05-05T10:%02d:00.000Z", index)
            )
        }

        let manyThreadsProjectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "many-threads")
        for index in 1...8 {
            try writeCodexRemoteSession(
                sessionsDirectory: sessions,
                id: "thread_\(index)",
                title: "Thread \(index)",
                cwd: manyThreadsProjectURL.path,
                timestamp: String(format: "2026-05-05T11:%02d:00.000Z", index)
            )
        }

        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )
        let account = codexRemoteAccount()

        let firstProjectPage = await bridge.reply(for: account, text: "/list", chatID: "chat-1")

        XCTAssertEqual(firstProjectPage.status, "codex_success")
        XCTAssertTrue(firstProjectPage.text.contains("Projects (page 1 of 2):"))
        XCTAssertTrue(firstProjectPage.text.contains("many-threads"))
        XCTAssertFalse(firstProjectPage.text.contains("project-2\n   1 thread(s)"))
        XCTAssertTrue((firstProjectPage.replyMarkup?.inlineKeyboard.flatMap { $0 } ?? []).contains { $0.callbackData == "projectPage:2" })

        let secondProjectPage = await bridge.reply(for: account, text: "/projectPage 2", chatID: "chat-1")

        XCTAssertTrue(secondProjectPage.text.contains("Projects (page 2 of 2):"))
        XCTAssertTrue(secondProjectPage.text.contains("project-2"))
        XCTAssertTrue((secondProjectPage.replyMarkup?.inlineKeyboard.flatMap { $0 } ?? []).contains { $0.callbackData == "projectPage:1" })

        let firstThreadPage = await bridge.reply(for: account, text: "/project 1", chatID: "chat-1")

        XCTAssertTrue(firstThreadPage.text.contains("Threads in many-threads (page 1 of 2)"))
        XCTAssertTrue(firstThreadPage.text.contains("Thread 8"))
        XCTAssertFalse(firstThreadPage.text.contains("Thread 2"))
        XCTAssertTrue((firstThreadPage.replyMarkup?.inlineKeyboard.flatMap { $0 } ?? []).contains { $0.callbackData == "threadPage:1:2" })

        let secondThreadPage = await bridge.reply(for: account, text: "/threadPage 1 2", chatID: "chat-1")

        XCTAssertTrue(secondThreadPage.text.contains("Threads in many-threads (page 2 of 2)"))
        XCTAssertTrue(secondThreadPage.text.contains("Thread 2"))
        XCTAssertTrue(secondThreadPage.text.contains("Thread 1"))
        XCTAssertFalse(secondThreadPage.text.contains("Thread 8"))
        XCTAssertTrue((secondThreadPage.replyMarkup?.inlineKeyboard.flatMap { $0 } ?? []).contains { $0.callbackData == "threadPage:1:1" })
    }

    @MainActor
    func testCodexRemoteRejectsOutOfRangeThreadSelectionForCurrentProject() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/05", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let firstProjectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "first-project")
        let secondProjectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "second-project")
        try writeCodexRemoteSession(sessionsDirectory: sessions, id: "first_thread", title: "First thread", cwd: firstProjectURL.path, timestamp: "2026-05-05T10:00:00.000Z")
        try writeCodexRemoteSession(sessionsDirectory: sessions, id: "second_thread", title: "Second thread", cwd: secondProjectURL.path, timestamp: "2026-05-05T09:00:00.000Z")
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )
        let account = codexRemoteAccount()

        _ = await bridge.reply(for: account, text: "/list", chatID: "chat-1")
        _ = await bridge.reply(for: account, text: "/project 1", chatID: "chat-1")
        let invalidReply = await bridge.reply(for: account, text: "/latest 2", chatID: "chat-1")

        XCTAssertEqual(invalidReply.status, "codex_failed")
        XCTAssertTrue(invalidReply.text.contains("Session not found: 2"))
        XCTAssertFalse(invalidReply.text.contains("Second thread"))
    }

    @MainActor
    func testCodexRemoteTracksAndUntracksProjects() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/05", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let trackedProjectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "tracked-project")
        let otherProjectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "other-project")
        try writeCodexRemoteSession(sessionsDirectory: sessions, id: "tracked_thread", title: "Tracked thread", cwd: trackedProjectURL.path, timestamp: "2026-05-05T10:00:00.000Z")
        try writeCodexRemoteSession(sessionsDirectory: sessions, id: "other_thread", title: "Other thread", cwd: otherProjectURL.path, timestamp: "2026-05-05T09:00:00.000Z")
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex"),
            trackingStateURL: directory.appendingPathComponent("tracking.json")
        )
        let account = codexRemoteAccount()

        let listReply = await bridge.reply(for: account, text: "/list", chatID: "chat-1")
        XCTAssertTrue(telegramButtons(listReply).contains { $0.callbackData == "track:1" })

        let trackReply = await bridge.reply(for: account, text: "/track 1", chatID: "chat-1")
        XCTAssertTrue(trackReply.text.contains("Tracking project: tracked-project"))

        let trackedReply = await bridge.reply(for: account, text: "/tracked", chatID: "chat-1")
        XCTAssertTrue(trackedReply.text.contains("Tracked projects:"))
        XCTAssertTrue(trackedReply.text.contains("tracked-project"))
        XCTAssertFalse(trackedReply.text.contains("other-project"))
        XCTAssertTrue(telegramButtons(trackedReply).contains { $0.callbackData == "untrack:1" })

        let untrackReply = await bridge.reply(for: account, text: "/untrack 1", chatID: "chat-1")
        XCTAssertTrue(untrackReply.text.contains("Stopped tracking project: tracked-project"))

        let emptyTrackedReply = await bridge.reply(for: account, text: "/tracked", chatID: "chat-1")
        XCTAssertTrue(emptyTrackedReply.text.contains("No tracked projects yet."))
    }

    @MainActor
    func testCodexRemoteStagesSelectedSessionPromptUntilConfirmed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/05", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let projectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "confirm-project")
        try writeCodexRemoteSession(
            sessionsDirectory: sessions,
            id: "confirm_thread",
            title: "Confirm thread",
            cwd: projectURL.path,
            timestamp: "2026-05-05T10:00:00.000Z"
        )
        let fakeCodex = directory.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        let runner = RecordingGearCommandRunner()
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: fakeCodex,
            runner: runner
        )
        let account = codexRemoteAccount()

        _ = await bridge.reply(for: account, text: "/open confirm_thread", chatID: "chat-1")
        let stagedReply = await bridge.reply(for: account, text: "please continue", chatID: "chat-1")

        XCTAssertEqual(runner.calls.count, 0)
        XCTAssertTrue(stagedReply.text.contains("Confirm sending to Confirm thread"))
        XCTAssertTrue(stagedReply.text.contains("please continue"))
        let stagedButtons = stagedReply.replyMarkup?.inlineKeyboard.flatMap { $0 } ?? []
        XCTAssertTrue(stagedButtons.contains { $0.callbackData == "confirm:confirm_thread" })
        XCTAssertTrue(stagedButtons.contains { $0.callbackData == "cancel:pending" })

        let confirmedReply = await bridge.reply(for: account, text: "/confirm confirm_thread", chatID: "chat-1")

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls.first?.arguments.joined(separator: " ").contains("confirm_thread") == true)
        XCTAssertEqual(confirmedReply.status, "codex_empty_result")

        let stagedCommandReply = await bridge.reply(for: account, text: "/send please continue again", chatID: "chat-1")

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(stagedCommandReply.text.contains("Confirm sending to Confirm thread"))
        XCTAssertTrue(stagedCommandReply.text.contains("please continue again"))

        let confirmedCommandReply = await bridge.reply(for: account, text: "/confirm confirm_thread", chatID: "chat-1")

        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertTrue(runner.calls.last?.arguments.joined(separator: " ").contains("confirm_thread") == true)
        XCTAssertEqual(confirmedCommandReply.status, "codex_empty_result")
    }

    @MainActor
    func testCodexRemoteSendUsesSelectedSessionWhenSourceCannotResolveExplicitIDs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/05", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let projectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "app-server-project")
        try writeCodexRemoteSession(
            sessionsDirectory: sessions,
            id: "selected_thread",
            title: "Selected thread",
            cwd: projectURL.path,
            timestamp: "2026-05-05T10:00:00.000Z"
        )
        let fakeCodex = directory.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        let runner = RecordingGearCommandRunner()
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: fakeCodex,
            runner: runner
        )
        let fileScanAccount = codexRemoteAccount()
        let appServerSourceAccount = TelegramBridgeAccountConfig(
            id: fileScanAccount.id,
            role: fileScanAccount.role,
            botUsername: fileScanAccount.botUsername,
            transport: fileScanAccount.transport,
            security: fileScanAccount.security,
            push: fileScanAccount.push,
            codex: .init(threadSource: "app_server", sendMode: "cli_resume")
        )

        _ = await bridge.reply(for: fileScanAccount, text: "/open selected_thread", chatID: "chat-1")
        let stagedReply = await bridge.reply(for: appServerSourceAccount, text: "/send please continue", chatID: "chat-1")

        XCTAssertEqual(runner.calls.count, 0)
        XCTAssertEqual(stagedReply.status, "codex_confirmation_required")
        XCTAssertTrue(stagedReply.text.contains("Confirm sending to Selected thread"))
        XCTAssertTrue(stagedReply.text.contains("please continue"))
    }

    @MainActor
    func testCodexRemoteSendResolvesMyCodexNumericSelectorToSessionID() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let registryURL = directory.appendingPathComponent("telegram-created-sessions.json")
        let fakeCodex = directory.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        let account = codexRemoteAccount()
        let stateKey = "\(account.id):chat-1"
        let registry = TelegramCodexRemoteBridge.TelegramCreatedSessionRegistry(
            sessionsByChat: [
                stateKey: [
                    "tg_cli_thread": TelegramCodexRemoteBridge.TelegramCreatedSession(
                        id: "tg_cli_thread",
                        title: "Telegram CLI thread",
                        cwd: directory.path,
                        createdAt: "2026-05-09T08:00:00.000Z",
                        updatedAt: "2026-05-09T08:00:00.000Z",
                        filePath: nil,
                        source: "telegram_cli"
                    )
                ]
            ]
        )
        let encodedRegistry = try JSONEncoder().encode(registry)
        try encodedRegistry.write(to: registryURL, options: .atomic)
        let runner = RecordingGearCommandRunner()
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: directory.appendingPathComponent(".codex", isDirectory: true),
            codexBinaryURL: fakeCodex,
            telegramSessionRegistryURL: registryURL,
            runner: runner
        )

        let myCodexReply = await bridge.reply(for: account, text: "/mycodex", chatID: "chat-1")
        XCTAssertEqual(myCodexReply.status, "codex_success")
        XCTAssertTrue(myCodexReply.text.contains("Telegram CLI thread"))

        let sendReply = await bridge.reply(for: account, text: "/send 1 please continue", chatID: "chat-1")

        XCTAssertEqual(sendReply.status, "codex_empty_result")
        XCTAssertEqual(runner.calls.count, 1)
        let commandLine = runner.calls[0].arguments.joined(separator: " ")
        XCTAssertTrue(commandLine.contains("tg_cli_thread"))
        XCTAssertTrue(commandLine.contains("--skip-git-repo-check"))
        XCTAssertFalse(commandLine.contains(" '1' -"))
    }

    @MainActor
    func testCodexRemoteSendCapsCodexCommandOutput() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/09", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let projectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "bounded-output-project")
        try writeCodexRemoteSession(
            sessionsDirectory: sessions,
            id: "bounded_output_thread",
            title: "Bounded output thread",
            cwd: projectURL.path,
            timestamp: "2026-05-09T08:00:00.000Z"
        )
        let longReply = String(repeating: "codex-output ", count: 400)
        let fakeCodex = directory.appendingPathComponent("codex", isDirectory: false)
        try """
        #!/bin/sh
        out=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-o" ]; then
            shift
            out="$1"
          fi
          shift || break
        done
        cat >/dev/null
        if [ -n "$out" ]; then
          cat > "$out" <<'TEXT'
        \(longReply)
        TEXT
        fi
        exit 0
        """.write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: fakeCodex,
            timeoutSeconds: 5
        )

        let reply = await bridge.reply(
            for: codexRemoteAccount(),
            text: "/send bounded_output_thread please continue",
            chatID: "chat-1"
        )

        XCTAssertEqual(reply.status, "codex_success")
        XCTAssertTrue(reply.text.contains("...[truncated]"))
        XCTAssertLessThan(reply.text.count, 2_000)
    }

    @MainActor
    func testCodexRemoteNewCodexCreatesRegistrySessionOutsideDesktopList() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/09", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let workspaceURL = try makeCodexRemoteProjectRoot(directory: directory, name: "telegram-cli-workspace")
        let desktopWorkspaceURL = try makeCodexRemoteProjectRoot(directory: directory, name: "desktop-workspace")
        try writeCodexRemoteSession(
            sessionsDirectory: sessions,
            id: "desktop_thread",
            title: "Desktop thread",
            cwd: desktopWorkspaceURL.path,
            timestamp: "2026-05-09T08:00:00.000Z"
        )
        let sessionFileURL = sessions.appendingPathComponent("rollout-tg_new_thread.jsonl", isDirectory: false)
        let fakeCodex = directory.appendingPathComponent("codex", isDirectory: false)
        try """
        #!/bin/sh
        out=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-o" ]; then
            shift
            out="$1"
          fi
          shift || break
        done
        cat >/dev/null
        timestamp="$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
        cat > '\(sessionFileURL.path)' <<JSON
        {"timestamp":"$timestamp","type":"session_meta","payload":{"id":"tg_new_thread","cwd":"\(workspaceURL.path)","originator":"Codex CLI","timestamp":"$timestamp"}}
        {"timestamp":"$timestamp","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Telegram fresh thread"}}
        {"timestamp":"$timestamp","type":"event_msg","payload":{"type":"agent_message","message":"New session answer"}}
        JSON
        if [ -n "$out" ]; then
          printf 'New session answer\\n' > "$out"
        fi
        exit 0
        """.write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: fakeCodex,
            telegramSessionRegistryURL: directory.appendingPathComponent("telegram-created-sessions.json"),
            timeoutSeconds: 5
        )
        let account = codexRemoteAccount()

        let stagedReply = await bridge.reply(for: account, text: "/newcodex start a fresh task", chatID: "chat-1")
        XCTAssertEqual(stagedReply.status, "codex_confirmation_required")
        XCTAssertTrue(stagedReply.text.contains("Confirm starting a new Codex session"))
        XCTAssertTrue(telegramButtons(stagedReply).contains { $0.callbackData == "confirm:newcodex" })

        let confirmedReply = await bridge.reply(for: account, text: "/confirm newcodex", chatID: "chat-1")

        XCTAssertEqual(confirmedReply.status, "codex_success")
        XCTAssertTrue(confirmedReply.text.contains("Started new Codex session"))
        XCTAssertTrue(confirmedReply.text.contains("tg_new_thread"))
        XCTAssertTrue(confirmedReply.text.contains("New session answer"))

        let desktopListReply = await bridge.reply(for: account, text: "/list", chatID: "chat-1")
        XCTAssertEqual(desktopListReply.status, "codex_success")
        XCTAssertFalse(desktopListReply.text.contains("tg_new_thread"))
        XCTAssertFalse(desktopListReply.text.contains("Telegram fresh thread"))

        let myCodexReply = await bridge.reply(for: account, text: "/mycodex", chatID: "chat-1")
        XCTAssertEqual(myCodexReply.status, "codex_success")
        XCTAssertTrue(myCodexReply.text.contains("Telegram fresh thread"))
        XCTAssertTrue(myCodexReply.text.contains("tg_new_thread"))
        XCTAssertTrue(telegramButtons(myCodexReply).contains { $0.callbackData == "open:tg_new_thread" })

        let latestByTelegramNumberReply = await bridge.reply(for: account, text: "/latest 1", chatID: "chat-1")
        XCTAssertEqual(latestByTelegramNumberReply.status, "codex_success")
        XCTAssertTrue(latestByTelegramNumberReply.text.contains("Latest: Telegram fresh thread"))
        XCTAssertFalse(latestByTelegramNumberReply.text.contains("Latest: Desktop thread"))

        let latestReply = await bridge.reply(for: account, text: "/latest tg_new_thread", chatID: "chat-1")
        XCTAssertEqual(latestReply.status, "codex_success")
        XCTAssertTrue(latestReply.text.contains("Latest: Telegram fresh thread"))
        XCTAssertTrue(latestReply.text.contains("New session answer"))

        let numericDesktopReply = await bridge.reply(for: account, text: "/desktop 1", chatID: "chat-1")
        XCTAssertEqual(numericDesktopReply.status, "codex_blocked")
        XCTAssertTrue(numericDesktopReply.text.contains("Telegram-created Codex CLI session"))

        let desktopReply = await bridge.reply(for: account, text: "/desktop tg_new_thread", chatID: "chat-1")
        XCTAssertEqual(desktopReply.status, "codex_blocked")
        XCTAssertTrue(desktopReply.text.contains("Telegram-created Codex CLI session"))
    }

    @MainActor
    func testCodexRemoteNewCodexUsesExplicitNonRepoWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeCodex = directory.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        let runner = RecordingGearCommandRunner()
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: directory.appendingPathComponent(".codex", isDirectory: true),
            codexBinaryURL: fakeCodex,
            telegramSessionRegistryURL: directory.appendingPathComponent("telegram-created-sessions.json"),
            runner: runner,
            timeoutSeconds: 5
        )
        let account = codexRemoteAccount()

        let stagedReply = await bridge.reply(for: account, text: "/newcodex start from telegram", chatID: "chat-1")
        XCTAssertEqual(stagedReply.status, "codex_confirmation_required")
        let confirmedReply = await bridge.reply(for: account, text: "/confirm newcodex", chatID: "chat-1")

        XCTAssertEqual(confirmedReply.status, "codex_degraded")
        XCTAssertEqual(runner.calls.count, 1)
        let commandLine = runner.calls[0].arguments.joined(separator: " ")
        XCTAssertTrue(commandLine.contains(" exec --cd "))
        XCTAssertTrue(commandLine.contains("codex-remote-workspace"))
        XCTAssertTrue(commandLine.contains("--skip-git-repo-check"))
    }

    @MainActor
    func testCodexRemoteDoesNotOwnNativeAppControlCommand() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: directory.appendingPathComponent(".codex", isDirectory: true),
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let reply = await bridge.reply(
            for: codexRemoteAccount(),
            text: "/codexdesktop capture this",
            chatID: "chat-1"
        )

        XCTAssertEqual(reply.status, "codex_blocked")
        XCTAssertTrue(reply.text.contains("Native app control belongs to GeeAgent runtime/App Chat"))
    }

    @MainActor
    func testCodexRemoteCallbackStartDoesNotWaitForCallbackAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-config-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeCodex = directory.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        let sender = RecordingTelegramBridgeSender(
            updates: [
                try telegramTextUpdate(
                    updateID: 911,
                    messageID: 21,
                    chatID: "7973901539",
                    fromUserID: "7973901539",
                    text: "/newcodex start from button"
                )
            ],
            sendResult: .success(telegramMessageID: "36", sentAt: "2026-05-06T07:28:59Z")
        )
        let database = TelegramBridgeFileDatabase(dataDirectoryURL: directory)
        try database.saveConfig(
            TelegramBridgeConfigFile(
                accounts: [
                    TelegramBridgeAccountConfig(
                        id: "codex_remote_default",
                        role: "codex_remote",
                        botUsername: nil,
                        transport: .init(mode: "polling"),
                        security: .init(
                            allowUserIds: ["7973901539"],
                            allowChatIds: [],
                            requirePairing: false,
                            groupPolicy: "deny"
                        ),
                        push: nil,
                        codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
                    )
                ],
                pushChannels: []
            )
        )
        let tokenStore = TelegramBridgeTokenStore(storageURL: directory.appendingPathComponent("tokens.json"))
        try tokenStore.saveToken("123456:secret", accountID: "codex_remote_default")
        let runner = RecordingGearCommandRunner()
        let codexRemote = TelegramCodexRemoteBridge(
            codexHomeURL: directory.appendingPathComponent(".codex", isDirectory: true),
            codexBinaryURL: fakeCodex,
            telegramSessionRegistryURL: directory.appendingPathComponent("telegram-created-sessions.json"),
            runner: runner,
            timeoutSeconds: 5
        )
        let store = TelegramBridgeGearStore(
            database: database,
            tokenStore: tokenStore,
            sender: sender,
            codexRemote: codexRemote
        )

        await store.pollInboundOnce { _ -> String? in nil }
        XCTAssertEqual(sender.sentMessages.count, 1)
        XCTAssertTrue(telegramButtonsInMessage(sender.sentMessages[0]).contains { $0.callbackData == "confirm:newcodex" })

        sender.suspendCallbackAnswers = true
        sender.updates = [
            try telegramCallbackUpdate(
                updateID: 912,
                callbackID: "callback-start",
                messageID: 36,
                chatID: "7973901539",
                fromUserID: "7973901539",
                data: "confirm:newcodex"
            )
        ]

        await store.pollInboundOnce { _ -> String? in nil }
        for _ in 0..<10 where sender.callbackAnswers.isEmpty {
            await Task.yield()
        }
        sender.releaseSuspendedCallbackAnswers()

        XCTAssertEqual(sender.callbackAnswers.map(\.callbackQueryID), ["callback-start"])
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(sender.sentMessages.count, 2)
        XCTAssertTrue(sender.sentMessages[1].text.contains("Codex replied, but the new session id could not be captured"))
    }

    @MainActor
    func testCodexRemoteUnavailableAppServerModesFailWithoutCliFallback() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runner = RecordingGearCommandRunner()
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: directory.appendingPathComponent(".codex", isDirectory: true),
            codexBinaryURL: directory.appendingPathComponent("codex"),
            runner: runner
        )
        let account = TelegramBridgeAccountConfig(
            id: "codex_remote_default",
            role: "codex_remote",
            botUsername: nil,
            transport: .init(mode: "polling"),
            security: nil,
            push: nil,
            codex: .init(threadSource: "app_server", sendMode: "app_server")
        )

        let listReply = await bridge.reply(for: account, text: "/list", chatID: "chat-1")
        let latestReply = await bridge.reply(for: account, text: "/latest session-1", chatID: "chat-1")
        let desktopReply = await bridge.reply(for: account, text: "/desktop session-1", chatID: "chat-1")
        let sendReply = await bridge.reply(for: account, text: "/send session-1 please continue", chatID: "chat-1")

        XCTAssertEqual(listReply.status, "codex_failed")
        XCTAssertTrue(listReply.text.contains("app-server thread listing is not configured"))
        XCTAssertEqual(latestReply.status, "codex_failed")
        XCTAssertTrue(latestReply.text.contains("app-server thread reading is not configured"))
        XCTAssertEqual(desktopReply.status, "codex_failed")
        XCTAssertTrue(desktopReply.text.contains("app-server thread reading is not configured"))
        XCTAssertEqual(sendReply.status, "codex_failed")
        XCTAssertTrue(sendReply.text.contains("app-server send is not configured"))
        XCTAssertEqual(runner.calls.count, 0)
    }

    @MainActor
    func testCodexRemoteFileScanIgnoresThreadMetadataBeyondLargeJSONLScanBudget() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/05", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let visibleProjectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "visible-large-jsonl-project")
        let lateProjectURL = try makeCodexRemoteProjectRoot(directory: directory, name: "late-large-jsonl-project")
        try writeCodexRemoteSession(
            sessionsDirectory: sessions,
            id: "visible_thread",
            title: "Visible thread",
            cwd: visibleProjectURL.path,
            timestamp: "2026-05-05T10:00:00.000Z"
        )
        var lateLines = (0..<450).map { index in
            #"{"timestamp":"2026-05-05T11:00:00.000Z","type":"event_msg","payload":{"type":"noise","index":\#(index)}}"#
        }
        lateLines.append(
            #"{"timestamp":"2026-05-05T11:01:00.000Z","type":"session_meta","payload":{"id":"late_thread","cwd":"\#(lateProjectURL.path)","originator":"Codex Desktop","timestamp":"2026-05-05T11:01:00.000Z"}}"#
        )
        lateLines.append(
            #"{"timestamp":"2026-05-05T11:02:00.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Late hidden thread"}}"#
        )
        try lateLines.joined(separator: "\n").write(
            to: sessions.appendingPathComponent("rollout-late-thread.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let reply = await bridge.reply(for: codexRemoteAccount(), text: "/list", chatID: "chat-1")

        XCTAssertEqual(reply.status, "codex_success")
        XCTAssertTrue(reply.text.contains("visible-large-jsonl-project"))
        XCTAssertFalse(reply.text.contains("late-large-jsonl-project"))
        XCTAssertFalse(reply.text.contains("late_thread"))
    }

    @MainActor
    func testCodexRemoteStartShowsLegacyCommandHelp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: directory.appendingPathComponent(".codex", isDirectory: true),
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let reply = await bridge.reply(
            for: TelegramBridgeAccountConfig(
                id: "codex_remote_default",
                role: "codex_remote",
                botUsername: nil,
                transport: .init(mode: "polling"),
                security: nil,
                push: nil,
                codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
            ),
            text: "/start"
        )

        XCTAssertEqual(reply.status, "codex_success")
        XCTAssertTrue(reply.text.contains("Codex Telegram Remote"))
        XCTAssertTrue(reply.text.contains("/open"))
        XCTAssertTrue(reply.text.contains("/latest"))
        XCTAssertFalse(reply.text.contains("/codexdesktop"))
        XCTAssertTrue(reply.text.contains("native_app_control"))
        XCTAssertTrue(reply.text.contains("/send"))
    }

    @MainActor
    func testCodexRemoteLatestReadsAssistantReplyFromSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/04", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try """
        {"timestamp":"2026-05-04T10:00:00.000Z","type":"session_meta","payload":{"id":"thread_latest","cwd":"/tmp/latest","originator":"Codex Desktop","timestamp":"2026-05-04T10:00:00.000Z"}}
        {"timestamp":"2026-05-04T10:01:00.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Latest thread"}}
        {"timestamp":"2026-05-04T10:02:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"Old reply"}}
        {"timestamp":"2026-05-04T10:03:00.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Newest Codex reply"}]}}
        """.write(
            to: sessions.appendingPathComponent("rollout-thread-latest.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let reply = await bridge.reply(
            for: TelegramBridgeAccountConfig(
                id: "codex_remote_default",
                role: "codex_remote",
                botUsername: nil,
                transport: .init(mode: "polling"),
                security: nil,
                push: nil,
                codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
            ),
            text: "/latest thread_latest"
        )

        XCTAssertEqual(reply.status, "codex_success")
        XCTAssertTrue(reply.text.contains("Latest: Latest thread"))
        XCTAssertTrue(reply.text.contains("Newest Codex reply"))
        let buttons = reply.replyMarkup?.inlineKeyboard.flatMap { $0 } ?? []
        XCTAssertTrue(buttons.contains { $0.callbackData == "latest:thread_latest" })
        XCTAssertFalse(buttons.contains { $0.callbackData == "desktop:thread_latest" })
    }

    @MainActor
    func testCodexRemoteLatestCapsReturnedAssistantReplyVolume() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/09", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let longReply = String(repeating: "latest-public-reply ", count: 260)
        try """
        {"timestamp":"2026-05-09T10:00:00.000Z","type":"session_meta","payload":{"id":"thread_latest_capped","cwd":"/tmp/latest","originator":"Codex Desktop","timestamp":"2026-05-09T10:00:00.000Z"}}
        {"timestamp":"2026-05-09T10:01:00.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Latest capped thread"}}
        {"timestamp":"2026-05-09T10:02:00.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"\(longReply)"}]}}
        """.write(
            to: sessions.appendingPathComponent("rollout-thread-latest-capped.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex")
        )

        let reply = await bridge.reply(for: codexRemoteAccount(), text: "/latest thread_latest_capped")

        XCTAssertEqual(reply.status, "codex_success")
        XCTAssertTrue(reply.text.contains("Latest: Latest capped thread"))
        XCTAssertTrue(reply.text.contains("...[truncated]"))
        XCTAssertLessThan(reply.text.count, 2_200)
    }

    @MainActor
    func testCodexRemoteDesktopOpensCodexThreadDeeplink() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-codex-remote-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let codexHome = directory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/04", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try """
        {"timestamp":"2026-05-04T10:00:00.000Z","type":"session_meta","payload":{"id":"thread_desktop","cwd":"/tmp/desktop","originator":"Codex Desktop","timestamp":"2026-05-04T10:00:00.000Z"}}
        {"timestamp":"2026-05-04T10:01:00.000Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Desktop thread"}}
        """.write(
            to: sessions.appendingPathComponent("rollout-thread-desktop.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let runner = RecordingGearCommandRunner()
        let bridge = TelegramCodexRemoteBridge(
            codexHomeURL: codexHome,
            codexBinaryURL: directory.appendingPathComponent("missing-codex"),
            runner: runner
        )

        let reply = await bridge.reply(
            for: TelegramBridgeAccountConfig(
                id: "codex_remote_default",
                role: "codex_remote",
                botUsername: nil,
                transport: .init(mode: "polling"),
                security: nil,
                push: nil,
                codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
            ),
            text: "/desktop thread_desktop"
        )

        XCTAssertEqual(reply.status, "codex_success")
        XCTAssertTrue(reply.text.contains("Desktop thread"))
        XCTAssertTrue(runner.calls.contains { call in
            call.command == "/usr/bin/open" &&
                call.arguments.contains("Codex") &&
                call.arguments.contains("codex://threads/thread_desktop")
        })
    }

    func testCodexRemoteBotCommandMenuIncludesLegacyCommands() {
        let commands = TelegramBridgeSender.botCommands(for: "codex_remote").map(\.command)

        XCTAssertEqual(commands, ["start", "help", "list", "recent", "tracked", "open", "latest", "desktop", "newcodex", "mycodex", "send", "cancel"])
    }

    func testTelegramMessageSplitterKeepsChunksUnderTelegramLimit() {
        let text = [
            String(repeating: "A", count: 1800),
            String(repeating: "B", count: 1800),
            String(repeating: "C", count: 1800)
        ].joined(separator: "\n\n")

        let chunks = splitTelegramMessage(text, maxLength: 3900)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 3900 })
        XCTAssertTrue(chunks[0].contains(String(repeating: "A", count: 20)))
        XCTAssertTrue(chunks[1].contains(String(repeating: "C", count: 20)))
    }
}

private func codexRemoteAccount() -> TelegramBridgeAccountConfig {
    TelegramBridgeAccountConfig(
        id: "codex_remote_default",
        role: "codex_remote",
        botUsername: nil,
        transport: .init(mode: "polling"),
        security: nil,
        push: nil,
        codex: .init(threadSource: "file_scan", sendMode: "cli_resume")
    )
}

private func makeCodexRemoteProjectRoot(directory: URL, name: String) throws -> URL {
    let projectURL = directory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)
    return projectURL
}

private final class RecordingTelegramBridgeSender: TelegramBridgeSending {
    struct SentMessage {
        var target: TelegramBridgePushTargetConfig
        var text: String
        var parseMode: String?
        var disableWebPreview: Bool?
        var replyMarkup: TelegramBridgeReplyMarkup?
    }

    struct SentLocalFile {
        var target: TelegramBridgePushTargetConfig
        var fileURL: URL
        var caption: String?
    }

    struct CallbackAnswer {
        var callbackQueryID: String
        var text: String?
    }

    var updates: [TelegramBridgeSender.Update]
    var sentMessages: [SentMessage] = []
    var sentLocalFiles: [SentLocalFile] = []
    var commandMenuUpdates: [[TelegramBridgeBotCommand]] = []
    var callbackAnswers: [CallbackAnswer] = []
    var suspendCallbackAnswers = false
    private var suspendedCallbackAnswerContinuations: [CheckedContinuation<Void, Never>] = []
    var sendResult: TelegramBridgeSender.Result

    init(
        updates: [TelegramBridgeSender.Update],
        sendResult: TelegramBridgeSender.Result
    ) {
        self.updates = updates
        self.sendResult = sendResult
    }

    func getUpdates(token: String, offset: Int?, limit: Int, timeout: Int) async throws -> [TelegramBridgeSender.Update] {
        let next = updates
        updates = []
        return next
    }

    func latestChatID(token: String) async throws -> String {
        throw TelegramBridgeGearError.configInvalid("No Telegram updates with a chat ID were found. Send a message to this bot, then try again.")
    }

    func latestUserID(token: String) async throws -> String {
        throw TelegramBridgeGearError.configInvalid("No Telegram updates with a sender user ID were found. Send a direct message to this bot, then try again.")
    }

    func sendMessage(
        token: String,
        target: TelegramBridgePushTargetConfig,
        text: String,
        parseMode: String?,
        disableWebPreview: Bool?,
        replyMarkup: TelegramBridgeReplyMarkup?
    ) async throws -> TelegramBridgeSender.Result {
        sentMessages.append(
            SentMessage(
                target: target,
                text: text,
                parseMode: parseMode,
                disableWebPreview: disableWebPreview,
                replyMarkup: replyMarkup
            )
        )
        return sendResult
    }

    func sendLocalFile(
        token: String,
        target: TelegramBridgePushTargetConfig,
        fileURL: URL,
        caption: String?
    ) async throws -> TelegramBridgeSender.Result {
        sentLocalFiles.append(
            SentLocalFile(
                target: target,
                fileURL: fileURL,
                caption: caption
            )
        )
        return sendResult
    }

    func setMyCommands(token: String, commands: [TelegramBridgeBotCommand]) async throws {
        commandMenuUpdates.append(commands)
    }

    func answerCallbackQuery(token: String, callbackQueryID: String, text: String?) async throws {
        callbackAnswers.append(.init(callbackQueryID: callbackQueryID, text: text))
        if suspendCallbackAnswers {
            await withCheckedContinuation { continuation in
                suspendedCallbackAnswerContinuations.append(continuation)
            }
        }
    }

    func releaseSuspendedCallbackAnswers() {
        let continuations = suspendedCallbackAnswerContinuations
        suspendedCallbackAnswerContinuations = []
        suspendCallbackAnswers = false
        continuations.forEach { $0.resume() }
    }
}

private final class HangingTelegramBridgeSender: TelegramBridgeSending {
    var updates: [TelegramBridgeSender.Update]

    init(updates: [TelegramBridgeSender.Update]) {
        self.updates = updates
    }

    func getUpdates(token: String, offset: Int?, limit: Int, timeout: Int) async throws -> [TelegramBridgeSender.Update] {
        let next = updates
        updates = []
        return next
    }

    func latestChatID(token: String) async throws -> String {
        throw TelegramBridgeGearError.configInvalid("No Telegram updates with a chat ID were found. Send a message to this bot, then try again.")
    }

    func latestUserID(token: String) async throws -> String {
        throw TelegramBridgeGearError.configInvalid("No Telegram updates with a sender user ID were found. Send a direct message to this bot, then try again.")
    }

    func sendMessage(
        token: String,
        target: TelegramBridgePushTargetConfig,
        text: String,
        parseMode: String?,
        disableWebPreview: Bool?,
        replyMarkup: TelegramBridgeReplyMarkup?
    ) async throws -> TelegramBridgeSender.Result {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return .failure(status: "failed", code: "unexpected", message: "send should have timed out", retryAfterMs: nil)
    }

    func sendLocalFile(
        token: String,
        target: TelegramBridgePushTargetConfig,
        fileURL: URL,
        caption: String?
    ) async throws -> TelegramBridgeSender.Result {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return .failure(status: "failed", code: "unexpected", message: "send should have timed out", retryAfterMs: nil)
    }

    func setMyCommands(token: String, commands: [TelegramBridgeBotCommand]) async throws {}

    func answerCallbackQuery(token: String, callbackQueryID: String, text: String?) async throws {}
}

private func telegramTextUpdate(
    updateID: Int,
    messageID: Int,
    chatID: String,
    fromUserID: String,
    text: String,
    chatType: String = "private"
) throws -> TelegramBridgeSender.Update {
    let payload: [String: Any] = [
        "update_id": updateID,
        "message": [
            "message_id": messageID,
            "from": [
                "id": fromUserID,
                "username": "telegram_user"
            ],
            "chat": [
                "id": chatID,
                "type": chatType
            ],
            "text": text
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    return try JSONDecoder().decode(TelegramBridgeSender.Update.self, from: data)
}

private func writeCodexRemoteSession(
    sessionsDirectory: URL,
    id: String,
    title: String,
    cwd: String,
    timestamp: String
) throws {
    let fileURL = sessionsDirectory.appendingPathComponent("rollout-\(id).jsonl", isDirectory: false)
    try """
    {"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(id)","cwd":"\(cwd)","originator":"Codex Desktop","timestamp":"\(timestamp)"}}
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"\(title)"}}
    """.write(
        to: fileURL,
        atomically: true,
        encoding: .utf8
    )
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: timestamp) {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path)
    }
}

private func writeCodexRemoteHugeSessionMeta(
    sessionsDirectory: URL,
    id: String,
    cwd: String,
    timestamp: String
) throws {
    let fileURL = sessionsDirectory.appendingPathComponent("rollout-\(id).jsonl", isDirectory: false)
    let escapedCwd = cwd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let hugeInstructions = String(repeating: "large instructions ", count: 10_000)
    try """
    {"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(id)","cwd":"\(escapedCwd)","originator":"Codex Desktop","timestamp":"\(timestamp)","source":"vscode","base_instructions":{"text":"\(hugeInstructions)"}}}
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Huge meta thread"}}
    """.write(
        to: fileURL,
        atomically: true,
        encoding: .utf8
    )
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: timestamp) {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path)
    }
}

private func telegramButtons(_ reply: TelegramCodexRemoteReply) -> [TelegramBridgeInlineKeyboardButton] {
    reply.replyMarkup?.inlineKeyboard.flatMap { $0 } ?? []
}

private func telegramButtonsInMessage(_ message: RecordingTelegramBridgeSender.SentMessage) -> [TelegramBridgeInlineKeyboardButton] {
    message.replyMarkup?.inlineKeyboard.flatMap { $0 } ?? []
}

private func telegramCallbackUpdate(
    updateID: Int,
    callbackID: String,
    messageID: Int,
    chatID: String,
    fromUserID: String,
    data: String,
    chatType: String = "private"
) throws -> TelegramBridgeSender.Update {
    let payload: [String: Any] = [
        "update_id": updateID,
        "callback_query": [
            "id": callbackID,
            "from": [
                "id": fromUserID,
                "username": "telegram_user"
            ],
            "message": [
                "message_id": messageID,
                "chat": [
                    "id": chatID,
                    "type": chatType
                ],
                "date": 1_778_000_000,
                "text": "Confirm starting a new Codex session"
            ],
            "data": data
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    return try JSONDecoder().decode(TelegramBridgeSender.Update.self, from: data)
}

private final class RecordingGearCommandRunner: GearCommandRunning, @unchecked Sendable {
    struct Call: Hashable {
        var command: String
        var arguments: [String]
        var timeoutSeconds: TimeInterval?
    }

    private(set) var calls: [Call] = []

    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        await run(command, arguments: arguments, timeoutSeconds: nil)
    }

    func run(_ command: String, arguments: [String], timeoutSeconds: TimeInterval?) async -> GearCommandResult {
        calls.append(.init(command: command, arguments: arguments, timeoutSeconds: timeoutSeconds))
        return GearCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}
