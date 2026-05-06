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
        XCTAssertTrue(buttons.contains { $0.callbackData == "desktop:thread_fast" })
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
        try "visible marker".write(to: projectURL.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)

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
        XCTAssertTrue(listReply.text.contains("2 thread(s)"))
        XCTAssertFalse(listReply.text.contains("Hidden subagent"))
        XCTAssertFalse(listReply.text.contains("Hidden CLI"))

        let projectReply = await bridge.reply(for: account, text: "/project 1")
        XCTAssertTrue(projectReply.text.contains("Visible one"))
        XCTAssertTrue(projectReply.text.contains("Visible two"))
        XCTAssertFalse(projectReply.text.contains("Hidden subagent"))
        XCTAssertFalse(projectReply.text.contains("Hidden CLI"))
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
        XCTAssertTrue(buttons.contains { $0.callbackData == "desktop:thread_latest" })
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

        XCTAssertEqual(commands, ["start", "help", "list", "recent", "tracked", "open", "latest", "desktop", "send", "cancel"])
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

    var updates: [TelegramBridgeSender.Update]
    var sentMessages: [SentMessage] = []
    var sentLocalFiles: [SentLocalFile] = []
    var commandMenuUpdates: [[TelegramBridgeBotCommand]] = []
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

    func answerCallbackQuery(token: String, callbackQueryID: String, text: String?) async throws {}
}

private func telegramTextUpdate(
    updateID: Int,
    messageID: Int,
    chatID: String,
    fromUserID: String,
    text: String
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
                "type": "private"
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

private func telegramButtons(_ reply: TelegramCodexRemoteReply) -> [TelegramBridgeInlineKeyboardButton] {
    reply.replyMarkup?.inlineKeyboard.flatMap { $0 } ?? []
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
