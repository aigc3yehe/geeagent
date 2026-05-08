import Foundation
import Darwin
import SwiftUI

private enum TelegramBridgeGearRuntimeConstants {
    static let gearID = "telegram.bridge"
}

struct TelegramBridgeAccountConfig: Codable, Hashable, Sendable {
    struct Transport: Codable, Hashable, Sendable {
        var mode: String
    }

    struct Security: Codable, Hashable, Sendable {
        var allowUserIds: [String]?
        var allowChatIds: [String]?
        var requirePairing: Bool?
        var groupPolicy: String?
    }

    struct Push: Codable, Hashable, Sendable {
        var acceptInbound: Bool?
    }

    struct Codex: Codable, Hashable, Sendable {
        var threadSource: String?
        var sendMode: String?
    }

    var id: String
    var role: String
    var botUsername: String?
    var transport: Transport
    var security: Security?
    var push: Push?
    var codex: Codex?
}

struct TelegramBridgePushTargetConfig: Codable, Hashable, Sendable {
    var kind: String
    var value: String
}

struct TelegramBridgeInlineKeyboardButton: Codable, Hashable, Sendable {
    var text: String
    var callbackData: String

    enum CodingKeys: String, CodingKey {
        case text
        case callbackData = "callback_data"
    }
}

struct TelegramBridgeReplyMarkup: Codable, Hashable, Sendable {
    var inlineKeyboard: [[TelegramBridgeInlineKeyboardButton]]

    enum CodingKeys: String, CodingKey {
        case inlineKeyboard = "inline_keyboard"
    }

    var jsonObject: [String: Any] {
        [
            "inline_keyboard": inlineKeyboard.map { row in
                row.map { button in
                    [
                        "text": button.text,
                        "callback_data": button.callbackData
                    ]
                }
            }
        ]
    }
}

struct TelegramBridgeBotCommand: Codable, Hashable, Sendable {
    var command: String
    var description: String
}

struct TelegramBridgePushChannelConfig: Codable, Hashable, Identifiable, Sendable {
    struct Format: Codable, Hashable, Sendable {
        var parseMode: String?
        var disableWebPreview: Bool?
    }

    var id: String
    var title: String?
    var accountId: String
    var enabled: Bool
    var target: TelegramBridgePushTargetConfig
    var format: Format?
}

struct TelegramBridgeConfigFile: Codable, Hashable, Sendable {
    static let currentVersion = 1

    var version: Int
    var accounts: [TelegramBridgeAccountConfig]
    var pushChannels: [TelegramBridgePushChannelConfig]

    init(
        version: Int = Self.currentVersion,
        accounts: [TelegramBridgeAccountConfig] = [],
        pushChannels: [TelegramBridgePushChannelConfig] = []
    ) {
        self.version = version
        self.accounts = accounts
        self.pushChannels = pushChannels
    }

    enum CodingKeys: String, CodingKey {
        case version
        case accounts
        case pushChannels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        accounts = try container.decodeIfPresent([TelegramBridgeAccountConfig].self, forKey: .accounts) ?? []
        pushChannels = try container.decodeIfPresent([TelegramBridgePushChannelConfig].self, forKey: .pushChannels) ?? []
    }
}

struct TelegramBridgeDeliveryRecord: Codable, Hashable, Sendable {
    var channelId: String
    var accountId: String
    var telegramMessageId: String
    var sentAt: String
    var idempotencyKey: String
}

struct TelegramBridgeDeliveryLog: Codable, Sendable {
    var deliveries: [String: TelegramBridgeDeliveryRecord] = [:]
}

struct TelegramBridgePollingState: Codable, Sendable {
    var offsets: [String: Int] = [:]
}

struct TelegramBridgeConversationMessage: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var direction: String
    var accountId: String
    var chatId: String
    var fromUserId: String? = nil
    var messageId: String?
    var updateId: Int?
    var text: String
    var timestamp: String
    var status: String
}

struct TelegramBridgeConversationThread: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var accountId: String
    var accountRole: String?
    var chatId: String
    var title: String
    var updatedAt: String
    var messages: [TelegramBridgeConversationMessage]
}

struct TelegramBridgeConversationLog: Codable, Sendable {
    var threads: [TelegramBridgeConversationThread] = []
}

struct TelegramBridgeGatewayEnvelope: Hashable, Sendable {
    var accountID: String
    var accountRole: String
    var updateID: Int
    var idempotencyKey: String
    var chatID: String
    var chatType: String?
    var fromUserID: String?
    var messageID: String?
    var runtimeMessageID: String
    var text: String
    var inboundLogText: String
    var channelIdentity: String
    var attachments: [TelegramChannelMessageAttachmentRef]
}

struct TelegramBridgeGatewaySecurityDecision: Hashable, Sendable {
    var decision: String
    var policyID: String

    var isAllowed: Bool {
        decision == "allowed"
    }
}

enum TelegramBridgeGatewayNormalization: Hashable, Sendable {
    case accepted(TelegramBridgeGatewayEnvelope)
    case dropped(updateID: Int, code: String)
}

struct TelegramBridgeGatewayOutboundProjection: Hashable, Sendable {
    var chatID: String
    var text: String
    var parseMode: String?
    var disableWebPreview: Bool?
    var successStatus: String
    var successUpdateID: Int?
    var failureUpdateID: Int?
}

struct TelegramBridgeGatewayOutboundEvidence: Hashable, Sendable {
    var chatID: String
    var text: String
    var messageID: String?
    var updateID: Int?
    var status: String
}

enum TelegramBridgeGateway {
    static func normalize(
        account: TelegramBridgeAccountConfig,
        update: TelegramBridgeSender.Update
    ) -> TelegramBridgeGatewayNormalization {
        let updateID = update.updateId
        guard let message = update.messagePayload else {
            return .dropped(updateID: updateID, code: "telegram.message_missing")
        }
        let callbackCommandText = update.callbackCommandText
        let attachments = callbackCommandText == nil
            ? telegramMediaAttachmentRefs(account: account, updateID: updateID, message: message)
            : []
        if callbackCommandText == nil,
           message.unsupportedAttachmentKey != nil ||
            (attachments.isEmpty &&
                message.text?.trimmedForGateway.nilIfEmpty == nil &&
                message.caption?.trimmedForGateway.nilIfEmpty != nil) {
            return .dropped(updateID: updateID, code: "telegram.message_attachment_unsupported")
        }
        let rawText = callbackCommandText ?? message.text ?? message.caption ?? (attachments.isEmpty ? nil : "Telegram media attachment received.")
        guard let text = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return .dropped(updateID: updateID, code: "telegram.message_text_missing")
        }

        let chatID = message.chat.id.value
        let messageID = message.messageId?.value
        let runtimeMessageID = messageID ?? "update-\(updateID)"
        return .accepted(
            TelegramBridgeGatewayEnvelope(
                accountID: account.id,
                accountRole: account.role,
                updateID: updateID,
                idempotencyKey: "telegram:update:\(updateID)",
                chatID: chatID,
                chatType: message.chat.type,
                fromUserID: update.actorUserID,
                messageID: messageID,
                runtimeMessageID: runtimeMessageID,
                text: text,
                inboundLogText: update.callbackQuery == nil ? text : "[button] \(text)",
                channelIdentity: "telegram:\(account.id):chat:\(chatID)",
                attachments: attachments
            )
        )
    }

    private static func telegramMediaAttachmentRefs(
        account: TelegramBridgeAccountConfig,
        updateID: Int,
        message: TelegramBridgeSender.Update.MessageLike
    ) -> [TelegramChannelMessageAttachmentRef] {
        var refs: [TelegramChannelMessageAttachmentRef] = []
        if let photo = message.photo?.last(where: { !$0.fileID.trimmedForGateway.isEmpty }) {
            refs.append(
                telegramMediaAttachmentRef(
                    account: account,
                    updateID: updateID,
                    message: message,
                    mediaKind: "photo",
                    media: photo,
                    type: "image",
                    title: "Telegram photo",
                    mimeType: "image/*"
                )
            )
        }
        let singleMedia: [(String, TelegramBridgeSender.Update.MessageLike.MediaFile?, String, String, String?)] = [
            ("document", message.document, "document", "Telegram document", nil),
            ("video", message.video, "video", "Telegram video", "video/*"),
            ("animation", message.animation, "video", "Telegram animation", "image/gif"),
            ("audio", message.audio, "audio", "Telegram audio", "audio/*"),
            ("voice", message.voice, "audio", "Telegram voice message", "audio/*"),
            ("video_note", message.videoNote, "video", "Telegram video note", "video/*"),
            ("sticker", message.sticker, "image", "Telegram sticker", "image/*")
        ]
        for (mediaKind, media, type, title, mimeType) in singleMedia {
            guard let media, !media.fileID.trimmedForGateway.isEmpty else {
                continue
            }
            refs.append(
                telegramMediaAttachmentRef(
                    account: account,
                    updateID: updateID,
                    message: message,
                    mediaKind: mediaKind,
                    media: media,
                    type: type,
                    title: title,
                    mimeType: mimeType
                )
            )
        }
        return refs
    }

    private static func telegramMediaAttachmentRef(
        account: TelegramBridgeAccountConfig,
        updateID: Int,
        message: TelegramBridgeSender.Update.MessageLike,
        mediaKind: String,
        media: TelegramBridgeSender.Update.MessageLike.MediaFile,
        type: String,
        title: String,
        mimeType: String?
    ) -> TelegramChannelMessageAttachmentRef {
        let fileID = media.fileID.trimmedForGateway
        let fileUniqueID = media.fileUniqueID?.trimmedForGateway.nilIfEmpty
        let artifactIdentity = fileUniqueID ?? fileID
        return TelegramChannelMessageAttachmentRef(
            artifactId: "telegram:\(account.id):\(updateID):\(mediaKind):\(artifactIdentity)",
            kind: "telegram_file",
            type: type,
            title: title,
            uri: "telegram://file/\(fileID)",
            summary: "\(title) attachment from chat \(message.chat.id.value) message \(message.messageId?.value ?? "update-\(updateID)").",
            mimeType: mimeType,
            telegramFileId: fileID,
            telegramFileUniqueId: fileUniqueID,
            telegramMediaKind: mediaKind,
            width: media.width,
            height: media.height
        )
    }

    static func authorize(
        account: TelegramBridgeAccountConfig,
        envelope: TelegramBridgeGatewayEnvelope
    ) -> TelegramBridgeGatewaySecurityDecision {
        let allowUserIDs = Set(account.security?.allowUserIds ?? [])
        let allowChatIDs = Set(account.security?.allowChatIds ?? [])
        if account.security?.requirePairing == true {
            return .init(decision: "denied", policyID: "telegram.pairing_required_unavailable")
        }
        if !allowUserIDs.isEmpty {
            guard let fromUserID = envelope.fromUserID,
                  allowUserIDs.contains(fromUserID)
            else {
                return .init(decision: "denied", policyID: "telegram.user_not_allowed")
            }
        }
        if !allowChatIDs.isEmpty, !allowChatIDs.contains(envelope.chatID) {
            return .init(decision: "denied", policyID: "telegram.chat_not_allowed")
        }
        let isGroupLike = envelope.chatID.hasPrefix("-") || ["group", "supergroup", "channel"].contains(envelope.chatType ?? "")
        if isGroupLike {
            switch account.security?.groupPolicy ?? "deny" {
            case "allow":
                break
            case "mention_required":
                let botUsername = account.botUsername?.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespacesAndNewlines)) ?? ""
                guard !botUsername.isEmpty else {
                    return .init(decision: "denied", policyID: "telegram.bot_username_required")
                }
                guard envelope.text.localizedCaseInsensitiveContains("@\(botUsername)") else {
                    return .init(decision: "denied", policyID: "telegram.group_mention_required")
                }
            default:
                return .init(decision: "denied", policyID: "telegram.group_denied")
            }
        }
        return .init(decision: "allowed", policyID: "telegram.allowlist")
    }

    static func runtimePayload(
        envelope: TelegramBridgeGatewayEnvelope,
        security: TelegramBridgeGatewaySecurityDecision
    ) -> TelegramChannelMessagePayload {
        TelegramChannelMessagePayload(
            channelIdentity: envelope.channelIdentity,
            message: .init(
                idempotencyKey: envelope.idempotencyKey,
                telegramUpdateId: envelope.updateID,
                chatId: envelope.chatID,
                messageId: envelope.runtimeMessageID,
                fromUserId: envelope.fromUserID,
                text: envelope.text,
                attachments: envelope.attachments
            ),
            security: .init(decision: security.decision, policyId: security.policyID),
            projection: .init(
                surface: "telegram",
                replyTarget: .init(chatId: envelope.chatID, messageId: envelope.runtimeMessageID)
            )
        )
    }

    static func outboundEvidence(
        projection: TelegramBridgeGatewayOutboundProjection,
        result: TelegramBridgeSender.Result
    ) -> TelegramBridgeGatewayOutboundEvidence {
        switch result {
        case .success(let telegramMessageID, _):
            return .init(
                chatID: projection.chatID,
                text: projection.text,
                messageID: telegramMessageID,
                updateID: projection.successUpdateID,
                status: projection.successStatus
            )
        case .failure(_, let code, let failureMessage, _):
            return .init(
                chatID: projection.chatID,
                text: failureMessage,
                messageID: nil,
                updateID: projection.failureUpdateID,
                status: code
            )
        }
    }

    static func outboundExceptionEvidence(
        projection: TelegramBridgeGatewayOutboundProjection,
        errorMessage: String
    ) -> TelegramBridgeGatewayOutboundEvidence {
        .init(
            chatID: projection.chatID,
            text: errorMessage,
            messageID: nil,
            updateID: projection.failureUpdateID,
            status: "telegram_send_failed"
        )
    }
}

struct TelegramBridgeTokenFile: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var tokens: [String: String]

    init(version: Int = Self.currentVersion, tokens: [String: String] = [:]) {
        self.version = version
        self.tokens = tokens
    }
}

enum TelegramBridgeGearError: LocalizedError {
    case configInvalid(String)
    case unsupportedCapability(String)
    case tokenUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .configInvalid(let message), .unsupportedCapability(let message), .tokenUnavailable(let message):
            message
        }
    }
}

@MainActor
protocol TelegramBridgeSending {
    func getUpdates(token: String, offset: Int?, limit: Int, timeout: Int) async throws -> [TelegramBridgeSender.Update]
    func latestChatID(token: String) async throws -> String
    func latestUserID(token: String) async throws -> String
    func sendMessage(
        token: String,
        target: TelegramBridgePushTargetConfig,
        text: String,
        parseMode: String?,
        disableWebPreview: Bool?,
        replyMarkup: TelegramBridgeReplyMarkup?
    ) async throws -> TelegramBridgeSender.Result
    func sendLocalFile(
        token: String,
        target: TelegramBridgePushTargetConfig,
        fileURL: URL,
        caption: String?
    ) async throws -> TelegramBridgeSender.Result
    func setMyCommands(token: String, commands: [TelegramBridgeBotCommand]) async throws
    func answerCallbackQuery(token: String, callbackQueryID: String, text: String?) async throws
}

@MainActor
final class TelegramBridgeGearStore: ObservableObject {
    static let shared = TelegramBridgeGearStore()
    private static let inboundPollIntervalNanoseconds: UInt64 = 2_000_000_000
    private static let inboundPollIntervalMilliseconds = 2_000

    @Published private(set) var config: TelegramBridgeConfigFile = TelegramBridgeConfigFile()
    @Published private(set) var lastStatusMessage: String = "Ready"
    @Published private(set) var conversationLog: TelegramBridgeConversationLog = TelegramBridgeConversationLog()

    private let database: TelegramBridgeFileDatabase
    private let tokenStore: TelegramBridgeTokenStore
    private let sender: any TelegramBridgeSending
    private let codexRemote: TelegramCodexRemoteBridge
    private let telegramSendTimeoutSeconds: TimeInterval
    private var inboundTask: Task<Void, Never>?
    private var configuredCommandMenuAccountIDs: Set<String> = []

    init(
        database: TelegramBridgeFileDatabase = TelegramBridgeFileDatabase(),
        tokenStore: TelegramBridgeTokenStore = TelegramBridgeTokenStore(),
        sender: any TelegramBridgeSending = TelegramBridgeSender(),
        codexRemote: TelegramCodexRemoteBridge = TelegramCodexRemoteBridge(),
        telegramSendTimeoutSeconds: TimeInterval = 20
    ) {
        self.database = database
        self.tokenStore = tokenStore
        self.sender = sender
        self.codexRemote = codexRemote
        self.telegramSendTimeoutSeconds = telegramSendTimeoutSeconds
        loadConfig()
    }

    func loadConfig() {
        do {
            config = try database.loadConfig()
            conversationLog = try database.loadConversationLog()
            let conversationCount = config.accounts.filter { $0.role != "push_only" }.count
            lastStatusMessage = "Loaded \(conversationCount) conversation bot(s), \(config.pushChannels.count) push channel(s)."
        } catch {
            config = TelegramBridgeConfigFile()
            conversationLog = TelegramBridgeConversationLog()
            lastStatusMessage = error.localizedDescription
        }
    }

    func startInboundService(
        runtimeHandler: @escaping @MainActor (TelegramChannelMessagePayload) async throws -> String?
    ) {
        guard inboundTask == nil else {
            return
        }
        inboundTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollInboundOnce(runtimeHandler: runtimeHandler)
                try? await Task.sleep(nanoseconds: Self.inboundPollIntervalNanoseconds)
            }
        }
        lastStatusMessage = "Telegram inbound service started."
    }

    func stopInboundService() {
        inboundTask?.cancel()
        inboundTask = nil
        lastStatusMessage = "Telegram inbound service stopped."
    }

    func saveBotToken(accountID: String, token: String) throws {
        try tokenStore.saveToken(token, accountID: accountID)
        invalidateCommandMenuCache(accountID: accountID)
        lastStatusMessage = "Token saved for \(accountID)."
    }

    func tokenStatus(accountID: String) -> (configured: Bool, status: String, error: String?) {
        tokenStore.status(accountID: accountID)
    }

    func deleteBotToken(accountID: String) throws {
        let trimmedAccountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountID.isEmpty else {
            throw TelegramBridgeGearError.configInvalid("Account ID is required.")
        }
        try tokenStore.deleteToken(accountID: trimmedAccountID)
        invalidateCommandMenuCache(accountID: trimmedAccountID)
        lastStatusMessage = "Deleted local token for \(trimmedAccountID)."
    }

    func setStatusMessage(_ message: String) {
        lastStatusMessage = message
    }

    func fetchLatestChatID(token: String) async {
        do {
            let chatID = try await sender.latestChatID(token: token)
            lastStatusMessage = "Fetched latest Telegram chat ID \(chatID)."
        } catch {
            lastStatusMessage = error.localizedDescription
        }
    }

    func latestChatID(token: String) async throws -> String {
        try await sender.latestChatID(token: token)
    }

    func latestUserID(token: String, accountID: String? = nil) async throws -> String {
        if let userID = latestLocalConversationUserID(accountID: accountID) {
            lastStatusMessage = "Fetched latest Telegram sender user ID \(userID) from local conversation history."
            return userID
        }
        if let userID = latestRuntimeChannelUserID(accountID: accountID) {
            lastStatusMessage = "Fetched latest Telegram sender user ID \(userID) from runtime channel history."
            return userID
        }
        return try await sender.latestUserID(token: token)
    }

    func pollInboundOnce(
        runtimeHandler: @escaping @MainActor (TelegramChannelMessagePayload) async throws -> String?
    ) async {
        let accounts: [TelegramBridgeAccountConfig]
        do {
            let loaded = try database.loadConfig()
            config = loaded
            accounts = loaded.accounts.filter {
                ["gee_direct", "codex_remote"].contains($0.role) && $0.transport.mode == "polling"
            }
        } catch {
            lastStatusMessage = error.localizedDescription
            return
        }

        guard !accounts.isEmpty else {
            return
        }

        var state = (try? database.loadPollingState()) ?? TelegramBridgePollingState()
        for account in accounts {
            guard !Task.isCancelled else { return }
            do {
                guard let token = try tokenStore.token(accountID: account.id), !token.isEmpty else {
                    lastStatusMessage = "Telegram bot token is missing for \(account.id)."
                    continue
                }
                await ensureBotCommandMenu(account: account, token: token)
                let updates = try await sender.getUpdates(
                    token: token,
                    offset: state.offsets[account.id],
                    limit: 10,
                    timeout: 1
                )
                guard !updates.isEmpty else {
                    continue
                }
                for update in updates.sorted(by: { $0.updateId < $1.updateId }) {
                    let nextOffset = update.updateId + 1
                    let envelope: TelegramBridgeGatewayEnvelope
                    switch TelegramBridgeGateway.normalize(account: account, update: update) {
                    case .accepted(let acceptedEnvelope):
                        envelope = acceptedEnvelope
                    case .dropped:
                        state.offsets[account.id] = nextOffset
                        try database.savePollingState(state)
                        continue
                    }
                    let security = TelegramBridgeGateway.authorize(account: account, envelope: envelope)
                    if let callbackQueryID = update.callbackQuery?.id {
                        try? await sender.answerCallbackQuery(
                            token: token,
                            callbackQueryID: callbackQueryID,
                            text: security.isAllowed ? nil : "Not authorized"
                        )
                    }
                    if security.isAllowed, isTelegramNewConversationCommand(envelope.text) {
                        try resetConversationThread(
                            accountID: account.id,
                            accountRole: account.role,
                            chatID: envelope.chatID
                        )
                    }
                    recordConversationMessage(
                        accountID: account.id,
                        accountRole: account.role,
                        chatID: envelope.chatID,
                        fromUserID: envelope.fromUserID,
                        direction: "inbound",
                        text: envelope.inboundLogText,
                        messageID: envelope.messageID,
                        updateID: envelope.updateID,
                        status: security.decision
                    )
                    guard security.isAllowed else {
                        state.offsets[account.id] = nextOffset
                        try database.savePollingState(state)
                        continue
                    }
                    if account.role == "codex_remote" {
                        do {
                            try await handleCodexRemoteMessage(
                                account: account,
                                token: token,
                                chatID: envelope.chatID,
                                text: envelope.text,
                                updateID: envelope.updateID
                            )
                        } catch {
                            recordConversationMessage(
                                accountID: account.id,
                                accountRole: account.role,
                                chatID: envelope.chatID,
                                direction: "outbound",
                                text: error.localizedDescription,
                                messageID: nil,
                                updateID: envelope.updateID,
                                status: "codex_remote_failed"
                            )
                            lastStatusMessage = error.localizedDescription
                        }
                        state.offsets[account.id] = nextOffset
                        try database.savePollingState(state)
                        continue
                    }
                    let payload = TelegramBridgeGateway.runtimePayload(envelope: envelope, security: security)
                    let reply: String?
                    do {
                        reply = try await runtimeHandler(payload)
                    } catch let runtimeError {
                        await sendRuntimeFailureReply(
                            account: account,
                            token: token,
                            chatID: envelope.chatID,
                            updateID: envelope.updateID,
                            error: runtimeError
                        )
                        state.offsets[account.id] = nextOffset
                        try database.savePollingState(state)
                        lastStatusMessage = runtimeError.localizedDescription
                        continue
                    }
                    guard let rawReplyText = reply?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !rawReplyText.isEmpty
                    else {
                        state.offsets[account.id] = nextOffset
                        try database.savePollingState(state)
                        continue
                    }
                    let replyText = normalizedTelegramReply(rawReplyText)
                    let projection = TelegramBridgeGatewayOutboundProjection(
                        chatID: envelope.chatID,
                        text: replyText,
                        parseMode: nil,
                        disableWebPreview: nil,
                        successStatus: "sent",
                        successUpdateID: nil,
                        failureUpdateID: nil
                    )
                    let sendResult: TelegramBridgeSender.Result
                    do {
                        sendResult = try await sendTelegramMessageChunks(
                            token: token,
                            target: .init(kind: "chat_id", value: projection.chatID),
                            text: projection.text,
                            parseMode: projection.parseMode,
                            disableWebPreview: projection.disableWebPreview,
                            replyMarkup: nil
                        )
                    } catch {
                        recordOutboundEvidence(
                            accountID: account.id,
                            accountRole: account.role,
                            evidence: TelegramBridgeGateway.outboundExceptionEvidence(
                                projection: projection,
                                errorMessage: error.localizedDescription
                            )
                        )
                        state.offsets[account.id] = nextOffset
                        try database.savePollingState(state)
                        lastStatusMessage = error.localizedDescription
                        continue
                    }
                    recordOutboundEvidence(
                        accountID: account.id,
                        accountRole: account.role,
                        evidence: TelegramBridgeGateway.outboundEvidence(
                            projection: projection,
                            result: sendResult
                        )
                    )
                    state.offsets[account.id] = nextOffset
                    try database.savePollingState(state)
                }
            } catch {
                lastStatusMessage = error.localizedDescription
            }
        }
    }

    private func sendRuntimeFailureReply(
        account: TelegramBridgeAccountConfig,
        token: String,
        chatID: String,
        updateID: Int,
        error: Error
    ) async {
        let replyText = runtimeFailureTelegramReplyText(for: error, token: token)
        let projection = TelegramBridgeGatewayOutboundProjection(
            chatID: chatID,
            text: replyText,
            parseMode: nil,
            disableWebPreview: nil,
            successStatus: "runtime_failed",
            successUpdateID: updateID,
            failureUpdateID: updateID
        )
        do {
            let sendResult = try await sendTelegramMessageChunks(
                token: token,
                target: .init(kind: "chat_id", value: projection.chatID),
                text: projection.text,
                parseMode: projection.parseMode,
                disableWebPreview: projection.disableWebPreview,
                replyMarkup: nil
            )
            recordOutboundEvidence(
                accountID: account.id,
                accountRole: account.role,
                evidence: TelegramBridgeGateway.outboundEvidence(
                    projection: projection,
                    result: sendResult
                )
            )
        } catch {
            recordOutboundEvidence(
                accountID: account.id,
                accountRole: account.role,
                evidence: TelegramBridgeGateway.outboundExceptionEvidence(
                    projection: projection,
                    errorMessage: error.localizedDescription
                )
            )
            lastStatusMessage = error.localizedDescription
        }
    }

    func runtimeFailureTelegramReplyText(for error: Error, token: String) -> String {
        let message = sanitizeSensitiveText(error.localizedDescription, token: token)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = message.isEmpty ? "The runtime did not provide a failure reason." : message
        return normalizedTelegramReply(
            [
                "GeeAgent runtime failed before it could produce a reply.",
                "",
                detail
            ].joined(separator: "\n")
        )
    }

    private func ensureBotCommandMenu(account: TelegramBridgeAccountConfig, token: String) async {
        let key = "\(account.id):\(account.role)"
        guard !configuredCommandMenuAccountIDs.contains(key) else {
            return
        }
        let commands = TelegramBridgeSender.botCommands(for: account.role)
        guard !commands.isEmpty else {
            configuredCommandMenuAccountIDs.insert(key)
            return
        }
        do {
            try await sender.setMyCommands(token: token, commands: commands)
            configuredCommandMenuAccountIDs.insert(key)
        } catch {
            lastStatusMessage = "Telegram bot menu update failed for \(account.id): \(error.localizedDescription)"
        }
    }

    private func invalidateCommandMenuCache(accountID: String) {
        configuredCommandMenuAccountIDs = configuredCommandMenuAccountIDs.filter { key in
            !key.hasPrefix("\(accountID):")
        }
    }

    private func sendTelegramMessageChunks(
        token: String,
        target: TelegramBridgePushTargetConfig,
        text: String,
        parseMode: String?,
        disableWebPreview: Bool?,
        replyMarkup: TelegramBridgeReplyMarkup?
    ) async throws -> TelegramBridgeSender.Result {
        let chunks = splitTelegramMessage(text)
        var messageIDs: [String] = []
        var sentAt = ISO8601DateFormatter().string(from: Date())
        for (index, chunk) in chunks.enumerated() {
            let result = try await withTelegramSendTimeout {
                try await self.sender.sendMessage(
                    token: token,
                    target: target,
                    text: chunk,
                    parseMode: parseMode,
                    disableWebPreview: disableWebPreview,
                    replyMarkup: index == 0 ? replyMarkup : nil
                )
            }
            switch result {
            case .success(let telegramMessageID, let chunkSentAt):
                messageIDs.append(telegramMessageID)
                sentAt = chunkSentAt
            case .failure:
                return result
            }
        }
        return .success(telegramMessageID: messageIDs.joined(separator: ","), sentAt: sentAt)
    }

    private func withTelegramSendTimeout(
        operation: @escaping @MainActor () async throws -> TelegramBridgeSender.Result
    ) async throws -> TelegramBridgeSender.Result {
        guard telegramSendTimeoutSeconds > 0 else {
            return try await operation()
        }
        let timeoutNanoseconds = UInt64(telegramSendTimeoutSeconds * 1_000_000_000)
        let timeoutDescription = formatSeconds(telegramSendTimeoutSeconds)
        return try await withThrowingTaskGroup(of: TelegramBridgeSender.Result.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw TelegramBridgeGearError.tokenUnavailable(
                    "Telegram send timed out after \(timeoutDescription) seconds."
                )
            }
            guard let result = try await group.next() else {
                throw TelegramBridgeGearError.tokenUnavailable("Telegram send timed out.")
            }
            group.cancelAll()
            return result
        }
    }

    private func handleCodexRemoteMessage(
        account: TelegramBridgeAccountConfig,
        token: String,
        chatID: String,
        text: String,
        updateID: Int
    ) async throws {
        let reply = await codexRemote.reply(
            for: account,
            text: text,
            chatID: chatID
        )
        let replyText = normalizedTelegramReply(reply.text)
        let projection = TelegramBridgeGatewayOutboundProjection(
            chatID: chatID,
            text: replyText,
            parseMode: nil,
            disableWebPreview: true,
            successStatus: reply.status,
            successUpdateID: nil,
            failureUpdateID: updateID
        )
        let sendResult = try await sendTelegramMessageChunks(
            token: token,
            target: .init(kind: "chat_id", value: projection.chatID),
            text: projection.text,
            parseMode: projection.parseMode,
            disableWebPreview: projection.disableWebPreview,
            replyMarkup: reply.replyMarkup
        )
        recordOutboundEvidence(
            accountID: account.id,
            accountRole: account.role,
            evidence: TelegramBridgeGateway.outboundEvidence(
                projection: projection,
                result: sendResult
            )
        )
    }

    private func recordOutboundEvidence(
        accountID: String,
        accountRole: String?,
        evidence: TelegramBridgeGatewayOutboundEvidence
    ) {
        recordConversationMessage(
            accountID: accountID,
            accountRole: accountRole,
            chatID: evidence.chatID,
            direction: "outbound",
            text: evidence.text,
            messageID: evidence.messageID,
            updateID: evidence.updateID,
            status: evidence.status
        )
    }

    private func recordConversationMessage(
        accountID: String,
        accountRole: String?,
        chatID: String,
        fromUserID: String? = nil,
        direction: String,
        text: String,
        messageID: String?,
        updateID: Int?,
        status: String
    ) {
        do {
            var log = try database.loadConversationLog()
            let threadID = "\(accountID):\(chatID)"
            let now = ISO8601DateFormatter().string(from: Date())
            let message = TelegramBridgeConversationMessage(
                id: UUID().uuidString,
                direction: direction,
                accountId: accountID,
                chatId: chatID,
                fromUserId: fromUserID,
                messageId: messageID,
                updateId: updateID,
                text: text,
                timestamp: now,
                status: status
            )
            if let index = log.threads.firstIndex(where: { $0.id == threadID }) {
                if shouldSkipDuplicateConversationMessage(log.threads[index], candidate: message) {
                    conversationLog = log
                    return
                }
                log.threads[index].accountRole = accountRole ?? log.threads[index].accountRole
                log.threads[index].messages.append(message)
                log.threads[index].messages = Array(log.threads[index].messages.suffix(80))
                log.threads[index].updatedAt = now
            } else {
                log.threads.insert(
                    TelegramBridgeConversationThread(
                        id: threadID,
                        accountId: accountID,
                        accountRole: accountRole,
                        chatId: chatID,
                        title: "Telegram \(chatID)",
                        updatedAt: now,
                        messages: [message]
                    ),
                    at: 0
                )
            }
            log.threads.sort { $0.updatedAt > $1.updatedAt }
            log.threads = Array(log.threads.prefix(60))
            try database.saveConversationLog(log)
            conversationLog = log
        } catch {
            lastStatusMessage = error.localizedDescription
        }
    }

    func resetConversationThread(
        accountID: String,
        accountRole: String?,
        chatID: String
    ) throws {
        let threadID = "\(accountID):\(chatID)"
        var log = try database.loadConversationLog()
        log.threads.removeAll { $0.id == threadID }
        try database.saveConversationLog(log)
        conversationLog = log
    }

    func shouldSkipDuplicateConversationMessage(
        _ thread: TelegramBridgeConversationThread,
        candidate: TelegramBridgeConversationMessage
    ) -> Bool {
        thread.messages.contains { existing in
            guard existing.direction == candidate.direction,
                  existing.status == candidate.status
            else {
                return false
            }
            if let updateID = candidate.updateId {
                return existing.updateId == updateID
            }
            if let messageID = candidate.messageId {
                return existing.messageId == messageID
            }
            return false
        }
    }

    private func latestLocalConversationUserID(accountID: String?) -> String? {
        let trimmedAccountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        do {
            let log = try database.loadConversationLog()
            conversationLog = log
            let sortedThreads = log.threads.sorted { $0.updatedAt > $1.updatedAt }
            for thread in sortedThreads {
                if let trimmedAccountID, thread.accountId != trimmedAccountID {
                    continue
                }
                for message in thread.messages.reversed() where message.direction == "inbound" {
                    if let userID = message.fromUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !userID.isEmpty {
                        return userID
                    }
                }
            }
            return nil
        } catch {
            lastStatusMessage = error.localizedDescription
            return nil
        }
    }

    private func latestRuntimeChannelUserID(accountID: String?) -> String? {
        let trimmedAccountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let runtimeURL = runtimeStoreURL()
        guard FileManager.default.fileExists(atPath: runtimeURL.path),
              let data = try? Data(contentsOf: runtimeURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["transcript_events"] as? [[String: Any]]
        else {
            return nil
        }
        for event in events.reversed() {
            guard let payload = event["payload"] as? [String: Any],
                  payload["kind"] as? String == "channel_message_received",
                  let channel = payload["channel"] as? [String: Any],
                  let userID = (channel["from_user_id"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
            else {
                continue
            }
            let channelIdentity = channel["channel_identity"] as? String ?? ""
            guard channelIdentity.hasPrefix("telegram:") else {
                continue
            }
            if let trimmedAccountID,
               !channelIdentity.contains("telegram:\(trimmedAccountID):") {
                continue
            }
            return userID
        }
        return nil
    }

    private func runtimeStoreURL() -> URL {
        let gearDirectory = database.dataDirectoryURL.standardizedFileURL
        if gearDirectory.lastPathComponent == TelegramBridgeGearRuntimeConstants.gearID,
           gearDirectory.deletingLastPathComponent().lastPathComponent == "gear-data" {
            return gearDirectory
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("runtime-store.json", isDirectory: false)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GeeAgent", isDirectory: true)
            .appendingPathComponent("runtime-store.json", isDirectory: false)
    }

    func upsertConversationBot(
        role: String,
        accountID: String,
        botUsername: String?,
        allowUserIds: [String],
        allowChatIds: [String],
        groupPolicy: String,
        codexThreadSource: String?,
        codexSendMode: String?,
        token: String?
    ) throws {
        guard ["gee_direct", "codex_remote"].contains(role) else {
            throw TelegramBridgeGearError.configInvalid("Conversation bot role must be gee_direct or codex_remote.")
        }
        let trimmedAccountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountID.isEmpty else {
            throw TelegramBridgeGearError.configInvalid("Account ID is required.")
        }
        guard ["deny", "mention_required", "allow"].contains(groupPolicy) else {
            throw TelegramBridgeGearError.configInvalid("Group policy must be deny, mention_required, or allow.")
        }

        var next = try database.loadConfig()
        let account = TelegramBridgeAccountConfig(
            id: trimmedAccountID,
            role: role,
            botUsername: botUsername?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            transport: .init(mode: "polling"),
            security: .init(
                allowUserIds: allowUserIds.isEmpty ? nil : allowUserIds,
                allowChatIds: allowChatIds.isEmpty ? nil : allowChatIds,
                requirePairing: false,
                groupPolicy: groupPolicy
            ),
            push: nil,
            codex: role == "codex_remote"
                ? .init(threadSource: codexThreadSource, sendMode: codexSendMode)
                : nil
        )
        if let index = next.accounts.firstIndex(where: { $0.id == trimmedAccountID }) {
            guard next.accounts[index].role != "push_only" else {
                throw TelegramBridgeGearError.configInvalid("Account `\(trimmedAccountID)` is already used by a push-only channel.")
            }
            next.accounts[index] = account
        } else {
            next.accounts.append(account)
        }
        try database.saveConfig(next)
        if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try tokenStore.saveToken(token, accountID: trimmedAccountID)
        }
        invalidateCommandMenuCache(accountID: trimmedAccountID)
        config = next
        lastStatusMessage = "Saved \(role == "gee_direct" ? "Gee Direct" : "Codex Remote") bot \(trimmedAccountID)."
    }

    func deleteConversationBot(accountID: String) throws {
        let trimmedAccountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountID.isEmpty else {
            throw TelegramBridgeGearError.configInvalid("Account ID is required.")
        }
        var next = try database.loadConfig()
        guard let index = next.accounts.firstIndex(where: { $0.id == trimmedAccountID }) else {
            throw TelegramBridgeGearError.configInvalid("Conversation bot `\(trimmedAccountID)` was not found.")
        }
        guard next.accounts[index].role != "push_only" else {
            throw TelegramBridgeGearError.configInvalid("Account `\(trimmedAccountID)` is push-only. Delete it from Push Only.")
        }
        next.accounts.remove(at: index)
        try database.saveConfig(next)
        try tokenStore.deleteToken(accountID: trimmedAccountID)
        invalidateCommandMenuCache(accountID: trimmedAccountID)
        config = next
        lastStatusMessage = "Deleted conversation bot \(trimmedAccountID)."
    }

    func deletePushChannel(channelID: String) throws {
        let trimmedChannelID = channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChannelID.isEmpty else {
            throw TelegramBridgeGearError.configInvalid("Channel ID is required.")
        }
        var next = try database.loadConfig()
        guard let index = next.pushChannels.firstIndex(where: { $0.id == trimmedChannelID }) else {
            throw TelegramBridgeGearError.configInvalid("Push channel `\(trimmedChannelID)` was not found.")
        }
        next.pushChannels.remove(at: index)
        try database.saveConfig(next)
        config = next
        lastStatusMessage = "Deleted push channel \(trimmedChannelID)."
    }

    func deletePushAccount(accountID: String) throws {
        let trimmedAccountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountID.isEmpty else {
            throw TelegramBridgeGearError.configInvalid("Account ID is required.")
        }
        var next = try database.loadConfig()
        guard let index = next.accounts.firstIndex(where: { $0.id == trimmedAccountID }) else {
            throw TelegramBridgeGearError.configInvalid("Push account `\(trimmedAccountID)` was not found.")
        }
        guard next.accounts[index].role == "push_only" else {
            throw TelegramBridgeGearError.configInvalid("Account `\(trimmedAccountID)` is not push-only.")
        }
        guard !next.pushChannels.contains(where: { $0.accountId == trimmedAccountID }) else {
            throw TelegramBridgeGearError.configInvalid("Delete push channels using `\(trimmedAccountID)` before deleting the account.")
        }
        next.accounts.remove(at: index)
        try database.saveConfig(next)
        try tokenStore.deleteToken(accountID: trimmedAccountID)
        config = next
        lastStatusMessage = "Deleted push account \(trimmedAccountID)."
    }

    func runAgentAction(capabilityID: String, args: [String: Any]) async -> [String: Any] {
        do {
            switch capabilityID {
            case "telegram_bridge.status":
                return try statusPayload()
            case "telegram_push.list_channels":
                return try listChannelsPayload(enabledOnly: boolArg(args, "enabled_only") ?? boolArg(args, "enabledOnly") ?? false)
            case "telegram_push.upsert_channel":
                return try upsertChannelPayload(args: args)
            case "telegram_push.send_message":
                return await sendMessagePayload(args: args)
            case "telegram_push.send_file":
                return await sendPushFilePayload(args: args)
            case "telegram_direct.send_file":
                return await sendFilePayload(args: args)
            default:
                throw TelegramBridgeGearError.unsupportedCapability(
                    "telegram.bridge does not support `\(capabilityID)`."
                )
            }
        } catch {
            return failurePayload(
                status: "failed",
                code: "telegram_bridge.action_failed",
                message: error.localizedDescription,
                capabilityID: capabilityID
            )
        }
    }

    private func statusPayload() throws -> [String: Any] {
        let config = try database.loadConfig()
        let pollingState = (try? database.loadPollingState()) ?? TelegramBridgePollingState()
        let gatewayHealth = gatewayHealthPayload(config: config, pollingState: pollingState)
        self.config = config
        return [
            "gear_id": TelegramBridgeGearRuntimeConstants.gearID,
            "capability_id": "telegram_bridge.status",
            "status": "success",
            "fallback_attempted": false,
            "config_path": database.configURL.path,
            "state_path": database.pollingStateURL.path,
            "account_count": config.accounts.count,
            "push_channel_count": config.pushChannels.count,
            "polling_offsets": pollingState.offsets,
            "gateway_health": gatewayHealth,
            "accounts": config.accounts.map { account in
                let tokenStatus = tokenStore.status(accountID: account.id)
                var payload: [String: Any] = [
                    "id": account.id,
                    "role": account.role,
                    "transport": account.transport.mode,
                    "token_configured": tokenStatus.configured,
                    "token_status": tokenStatus.status
                ]
                if let error = tokenStatus.error {
                    payload["token_error"] = error
                }
                if let botUsername = account.botUsername {
                    payload["bot_username"] = botUsername
                }
                return payload
            },
            "channels": channelSummaries(config.pushChannels)
        ]
    }

    private func gatewayHealthPayload(
        config: TelegramBridgeConfigFile,
        pollingState: TelegramBridgePollingState
    ) -> [String: Any] {
        var issues: [[String: Any]] = []
        var missingTokenAccountIDs: [String] = []
        var webhookAccountIDs: [String] = []
        let accounts = config.accounts.map { account -> [String: Any] in
            let tokenStatus = tokenStore.status(accountID: account.id)
            if !tokenStatus.configured {
                missingTokenAccountIDs.append(account.id)
                issues.append([
                    "code": tokenStatus.status == "error" ? "token_status_unavailable" : "token_missing",
                    "severity": "failed",
                    "account_id": account.id,
                    "message": tokenStatus.error ?? "Telegram bot token is missing for account `\(account.id)`."
                ])
            }
            if account.transport.mode == "webhook", account.role != "push_only" {
                webhookAccountIDs.append(account.id)
                issues.append([
                    "code": "webhook_transport_not_ready",
                    "severity": "blocked",
                    "account_id": account.id,
                    "message": "Telegram webhook transport is configured for account `\(account.id)`, but webhook ingress is not enabled in this release."
                ])
            }
            var payload: [String: Any] = [
                "id": account.id,
                "role": account.role,
                "transport": account.transport.mode,
                "token_configured": tokenStatus.configured,
                "token_status": tokenStatus.status
            ]
            if let error = tokenStatus.error {
                payload["token_error"] = error
            }
            if let offset = pollingState.offsets[account.id] {
                payload["polling_offset"] = offset
            }
            return payload
        }

        return [
            "status": gatewayHealthStatus(issues: issues),
            "fallback_attempted": false,
            "lifecycle": gatewayLifecyclePayload(),
            "polling_account_count": config.accounts.filter { $0.transport.mode == "polling" }.count,
            "webhook_account_count": config.accounts.filter { $0.transport.mode == "webhook" }.count,
            "push_only_account_count": config.accounts.filter { $0.role == "push_only" }.count,
            "enabled_push_channel_count": config.pushChannels.filter(\.enabled).count,
            "disabled_push_channel_count": config.pushChannels.filter { !$0.enabled }.count,
            "missing_token_account_ids": missingTokenAccountIDs,
            "webhook_account_ids": webhookAccountIDs,
            "accounts": accounts,
            "issues": issues
        ]
    }

    private func gatewayLifecyclePayload() -> [String: Any] {
        [
            "mode": "native_app",
            "polling_loop": inboundTask == nil ? "stopped" : "running",
            "poll_interval_ms": Self.inboundPollIntervalMilliseconds,
            "webhook_ready": false,
            "webhook_status": "not_implemented",
            "fallback_attempted": false
        ]
    }

    private func gatewayHealthStatus(issues: [[String: Any]]) -> String {
        issues.reduce("success") { current, issue in
            guard let severity = issue["severity"] as? String else {
                return current
            }
            return gatewayHealthStatusRank(severity) > gatewayHealthStatusRank(current) ? severity : current
        }
    }

    private func gatewayHealthStatusRank(_ status: String) -> Int {
        switch status {
        case "blocked":
            return 1
        case "degraded":
            return 2
        case "failed":
            return 3
        default:
            return 0
        }
    }

    private func listChannelsPayload(enabledOnly: Bool) throws -> [String: Any] {
        let config = try database.loadConfig()
        let channels = config.pushChannels.filter { !enabledOnly || $0.enabled }
        return [
            "gear_id": TelegramBridgeGearRuntimeConstants.gearID,
            "capability_id": "telegram_push.list_channels",
            "status": "success",
            "fallback_attempted": false,
            "channels": channelSummaries(channels)
        ]
    }

    private func upsertChannelPayload(args: [String: Any]) throws -> [String: Any] {
        let channelID = stringArg(args, "channel_id") ?? stringArg(args, "channelId") ?? ""
        let accountID = stringArg(args, "account_id") ?? stringArg(args, "accountId") ?? ""
        let targetKind = stringArg(args, "target_kind") ?? stringArg(args, "targetKind") ?? ""
        let targetValue = stringArg(args, "target_value") ?? stringArg(args, "targetValue") ?? ""
        guard !channelID.isEmpty else {
            return failurePayload(status: "failed", code: "channel_id_missing", message: "`channel_id` is required.", capabilityID: "telegram_push.upsert_channel")
        }
        guard !accountID.isEmpty else {
            return failurePayload(status: "failed", code: "account_id_missing", message: "`account_id` is required.", capabilityID: "telegram_push.upsert_channel")
        }
        guard ["chat_id", "group_id", "channel_id", "channel_username"].contains(targetKind) else {
            return failurePayload(status: "failed", code: "target_kind_invalid", message: "`target_kind` must be chat_id, group_id, channel_id, or channel_username.", capabilityID: "telegram_push.upsert_channel")
        }
        guard !targetValue.isEmpty else {
            return failurePayload(status: "failed", code: "target_value_missing", message: "`target_value` is required.", capabilityID: "telegram_push.upsert_channel")
        }

        var next = try database.loadConfig()
        if let existing = next.accounts.first(where: { $0.id == accountID }) {
            guard existing.role == "push_only" else {
                return failurePayload(status: "failed", code: "account_not_push_only", message: "Account `\(accountID)` is not push_only.", capabilityID: "telegram_push.upsert_channel")
            }
            guard existing.transport.mode == "outbound_only" else {
                return failurePayload(status: "failed", code: "push_only.transport_not_outbound_only", message: "Push-only account `\(accountID)` must use outbound_only transport.", capabilityID: "telegram_push.upsert_channel")
            }
            if let index = next.accounts.firstIndex(where: { $0.id == accountID }) {
                next.accounts[index].botUsername = stringArg(args, "bot_username") ?? stringArg(args, "botUsername") ?? next.accounts[index].botUsername
                next.accounts[index].push = .init(acceptInbound: false)
            }
        } else {
            next.accounts.append(
                TelegramBridgeAccountConfig(
                    id: accountID,
                    role: "push_only",
                    botUsername: stringArg(args, "bot_username") ?? stringArg(args, "botUsername"),
                    transport: .init(mode: "outbound_only"),
                    security: nil,
                    push: .init(acceptInbound: false),
                    codex: nil
                )
            )
        }

        let channel = TelegramBridgePushChannelConfig(
            id: channelID,
            title: stringArg(args, "title"),
            accountId: accountID,
            enabled: boolArg(args, "enabled") ?? true,
            target: .init(kind: targetKind, value: targetValue),
            format: TelegramBridgePushChannelConfig.Format(
                parseMode: stringArg(args, "parse_mode") ?? stringArg(args, "parseMode"),
                disableWebPreview: boolArg(args, "disable_web_preview") ?? boolArg(args, "disableWebPreview")
            )
        )
        if let index = next.pushChannels.firstIndex(where: { $0.id == channelID }) {
            next.pushChannels[index] = channel
        } else {
            next.pushChannels.append(channel)
        }
        try database.saveConfig(next)
        config = next
        return [
            "gear_id": TelegramBridgeGearRuntimeConstants.gearID,
            "capability_id": "telegram_push.upsert_channel",
            "status": "success",
            "fallback_attempted": false,
            "channelId": channelID,
            "accountId": accountID,
            "target": redactedTarget(channel.target),
            "token_binding": "Save the bot token in GeeAgent local app data for account \(accountID); tokens are not stored in config."
        ]
    }

    private func sendMessagePayload(args: [String: Any]) async -> [String: Any] {
        let channelID = stringArg(args, "channel_id") ?? stringArg(args, "channelId") ?? ""
        let message = rawStringArg(args, "message") ?? ""
        let idempotencyKey = stringArg(args, "idempotency_key") ?? stringArg(args, "idempotencyKey") ?? ""
        guard !channelID.isEmpty else {
            return failurePayload(status: "failed", code: "channel_id_missing", message: "`channel_id` is required.", capabilityID: "telegram_push.send_message")
        }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return failurePayload(status: "blocked", code: "message_missing", message: "`message` is required.", capabilityID: "telegram_push.send_message", channelID: channelID)
        }
        guard !idempotencyKey.isEmpty else {
            return failurePayload(status: "blocked", code: "idempotency_key_missing", message: "`idempotency_key` is required.", capabilityID: "telegram_push.send_message", channelID: channelID)
        }

        do {
            let config = try database.loadConfig()
            guard let channel = config.pushChannels.first(where: { $0.id == channelID }) else {
                return failurePayload(status: "failed", code: "channel_not_found", message: "Push-only channel `\(channelID)` was not found.", capabilityID: "telegram_push.send_message", channelID: channelID)
            }
            guard channel.enabled else {
                return failurePayload(status: "failed", code: "channel_disabled", message: "Push-only channel `\(channelID)` is disabled.", capabilityID: "telegram_push.send_message", channelID: channelID)
            }
            guard let account = config.accounts.first(where: { $0.id == channel.accountId }) else {
                return failurePayload(status: "failed", code: "account_not_found", message: "Push-only channel `\(channelID)` references a missing account.", capabilityID: "telegram_push.send_message", channelID: channelID)
            }
            guard account.role == "push_only", account.transport.mode == "outbound_only", account.push?.acceptInbound == false else {
                return failurePayload(status: "failed", code: "account_not_push_only", message: "Channel `\(channelID)` must use a push_only outbound_only account with inbound disabled.", capabilityID: "telegram_push.send_message", channelID: channelID)
            }
            if let existing = try database.delivery(idempotencyKey: idempotencyKey) {
                return successSendPayload(channel: channel, delivery: existing, reused: true)
            }
            guard let token = try tokenStore.token(accountID: account.id), !token.isEmpty else {
                return failurePayload(status: "failed", code: "token_missing", message: "Telegram bot token is missing for account `\(account.id)`.", capabilityID: "telegram_push.send_message", channelID: channelID, accountID: account.id, target: channel.target)
            }
            let parseMode = normalizedParseMode(stringArg(args, "parse_mode") ?? stringArg(args, "parseMode") ?? channel.format?.parseMode)
            let chunks = splitTelegramMessage(message)
            if chunks.count > 1, parseMode != nil {
                return failurePayload(
                    status: "blocked",
                    code: "message_too_large_with_parse_mode",
                    message: "Telegram push messages with parse mode must be 4096 characters or fewer. Send long push text without parse mode so GeeAgent can split it safely.",
                    capabilityID: "telegram_push.send_message",
                    channelID: channelID,
                    accountID: account.id,
                    target: channel.target
                )
            }
            let response = try await sendTelegramMessageChunks(
                token: token,
                target: channel.target,
                text: message,
                parseMode: parseMode,
                disableWebPreview: boolArg(args, "disable_web_preview") ?? boolArg(args, "disableWebPreview") ?? channel.format?.disableWebPreview,
                replyMarkup: nil
            )
            switch response {
            case .success(let telegramMessageID, let sentAt):
                let delivery = TelegramBridgeDeliveryRecord(
                    channelId: channel.id,
                    accountId: account.id,
                    telegramMessageId: telegramMessageID,
                    sentAt: sentAt,
                    idempotencyKey: idempotencyKey
                )
                try database.saveDelivery(delivery)
                return successSendPayload(channel: channel, delivery: delivery, reused: false)
            case .failure(let status, let code, let message, let retryAfterMs):
                return failurePayload(status: status, code: code, message: message, capabilityID: "telegram_push.send_message", channelID: channelID, accountID: account.id, target: channel.target, retryAfterMs: retryAfterMs)
            }
        } catch {
            return failurePayload(status: "failed", code: "telegram_push_failed", message: error.localizedDescription, capabilityID: "telegram_push.send_message", channelID: channelID)
        }
    }

    private func sendPushFilePayload(args: [String: Any]) async -> [String: Any] {
        let capabilityID = "telegram_push.send_file"
        let channelID = stringArg(args, "channel_id") ?? stringArg(args, "channelId") ?? ""
        let rawFilePath = stringArg(args, "file_path") ?? stringArg(args, "filePath") ?? stringArg(args, "path") ?? ""
        let caption = rawStringArg(args, "caption")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let idempotencyKey = stringArg(args, "idempotency_key") ?? stringArg(args, "idempotencyKey") ?? ""
        guard !channelID.isEmpty else {
            return failurePayload(status: "failed", code: "channel_id_missing", message: "`channel_id` is required.", capabilityID: capabilityID)
        }
        guard !rawFilePath.isEmpty else {
            return failurePayload(status: "failed", code: "file_path_missing", message: "`file_path` is required.", capabilityID: capabilityID, channelID: channelID)
        }
        guard !idempotencyKey.isEmpty else {
            return failurePayload(status: "blocked", code: "idempotency_key_missing", message: "`idempotency_key` is required.", capabilityID: capabilityID, channelID: channelID, filePath: rawFilePath)
        }

        let fileURL = localFileURL(from: rawFilePath)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return failurePayload(status: "failed", code: "file_not_found", message: "Local file `\(fileURL.path)` was not found.", capabilityID: capabilityID, channelID: channelID, filePath: fileURL.path)
        }
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            return failurePayload(status: "failed", code: "file_not_readable", message: "Local file `\(fileURL.path)` is not readable by GeeAgent.", capabilityID: capabilityID, channelID: channelID, filePath: fileURL.path)
        }

        do {
            let config = try database.loadConfig()
            guard let channel = config.pushChannels.first(where: { $0.id == channelID }) else {
                return failurePayload(status: "failed", code: "channel_not_found", message: "Push-only channel `\(channelID)` was not found.", capabilityID: capabilityID, channelID: channelID, filePath: fileURL.path)
            }
            guard channel.enabled else {
                return failurePayload(status: "failed", code: "channel_disabled", message: "Push-only channel `\(channelID)` is disabled.", capabilityID: capabilityID, channelID: channelID, filePath: fileURL.path)
            }
            guard let account = config.accounts.first(where: { $0.id == channel.accountId }) else {
                return failurePayload(status: "failed", code: "account_not_found", message: "Push-only channel `\(channelID)` references a missing account.", capabilityID: capabilityID, channelID: channelID, filePath: fileURL.path)
            }
            guard account.role == "push_only", account.transport.mode == "outbound_only", account.push?.acceptInbound == false else {
                return failurePayload(status: "failed", code: "account_not_push_only", message: "Channel `\(channelID)` must use a push_only outbound_only account with inbound disabled.", capabilityID: capabilityID, channelID: channelID, filePath: fileURL.path)
            }
            if let existing = try database.delivery(idempotencyKey: idempotencyKey) {
                return successPushFilePayload(channel: channel, fileURL: fileURL, delivery: existing, reused: true)
            }
            guard let token = try tokenStore.token(accountID: account.id), !token.isEmpty else {
                return failurePayload(status: "failed", code: "token_missing", message: "Telegram bot token is missing for account `\(account.id)`.", capabilityID: capabilityID, channelID: channelID, accountID: account.id, target: channel.target, filePath: fileURL.path)
            }
            let response = try await sender.sendLocalFile(
                token: token,
                target: channel.target,
                fileURL: fileURL,
                caption: caption?.nilIfEmpty
            )
            switch response {
            case .success(let telegramMessageID, let sentAt):
                let delivery = TelegramBridgeDeliveryRecord(
                    channelId: channel.id,
                    accountId: account.id,
                    telegramMessageId: telegramMessageID,
                    sentAt: sentAt,
                    idempotencyKey: idempotencyKey
                )
                try database.saveDelivery(delivery)
                return successPushFilePayload(channel: channel, fileURL: fileURL, delivery: delivery, reused: false)
            case .failure(let status, let code, let message, let retryAfterMs):
                return failurePayload(status: status, code: code, message: message, capabilityID: capabilityID, channelID: channelID, accountID: account.id, target: channel.target, filePath: fileURL.path, retryAfterMs: retryAfterMs)
            }
        } catch {
            return failurePayload(status: "failed", code: "telegram_push_file_failed", message: error.localizedDescription, capabilityID: capabilityID, channelID: channelID, filePath: fileURL.path)
        }
    }

    private func sendFilePayload(args: [String: Any]) async -> [String: Any] {
        let accountID = stringArg(args, "account_id") ?? stringArg(args, "accountId")
        let chatID = stringArg(args, "chat_id") ?? stringArg(args, "chatId")
        let rawFilePath = stringArg(args, "file_path") ?? stringArg(args, "filePath") ?? stringArg(args, "path") ?? ""
        let caption = rawStringArg(args, "caption")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let idempotencyKey = stringArg(args, "idempotency_key") ?? stringArg(args, "idempotencyKey") ?? ""
        guard !rawFilePath.isEmpty else {
            return failurePayload(status: "failed", code: "file_path_missing", message: "`file_path` is required.", capabilityID: "telegram_direct.send_file", accountID: accountID, chatID: chatID)
        }
        guard !idempotencyKey.isEmpty else {
            return failurePayload(status: "blocked", code: "idempotency_key_missing", message: "`idempotency_key` is required.", capabilityID: "telegram_direct.send_file", accountID: accountID, chatID: chatID, filePath: rawFilePath)
        }

        let fileURL = localFileURL(from: rawFilePath)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return failurePayload(status: "failed", code: "file_not_found", message: "Local file `\(fileURL.path)` was not found.", capabilityID: "telegram_direct.send_file", accountID: accountID, chatID: chatID, filePath: fileURL.path)
        }
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            return failurePayload(status: "failed", code: "file_not_readable", message: "Local file `\(fileURL.path)` is not readable by GeeAgent.", capabilityID: "telegram_direct.send_file", accountID: accountID, chatID: chatID, filePath: fileURL.path)
        }

        do {
            let config = try database.loadConfig()
            let target = try resolveDirectConversationTarget(config: config, accountID: accountID, chatID: chatID)
            let channel = TelegramBridgePushTargetConfig(kind: "chat_id", value: target.chatID)
            if let existing = try database.delivery(idempotencyKey: idempotencyKey) {
                return successDirectFilePayload(account: target.account, chatID: target.chatID, fileURL: fileURL, delivery: existing, reused: true)
            }
            guard let token = try tokenStore.token(accountID: target.account.id), !token.isEmpty else {
                return failurePayload(status: "failed", code: "token_missing", message: "Telegram bot token is missing for account `\(target.account.id)`.", capabilityID: "telegram_direct.send_file", accountID: target.account.id, target: channel, chatID: target.chatID, filePath: fileURL.path)
            }
            let response = try await sender.sendLocalFile(
                token: token,
                target: channel,
                fileURL: fileURL,
                caption: caption?.nilIfEmpty
            )
            switch response {
            case .success(let telegramMessageID, let sentAt):
                let delivery = TelegramBridgeDeliveryRecord(
                    channelId: "direct:\(target.account.id):\(target.chatID)",
                    accountId: target.account.id,
                    telegramMessageId: telegramMessageID,
                    sentAt: sentAt,
                    idempotencyKey: idempotencyKey
                )
                try database.saveDelivery(delivery)
                let logText = directFileLogText(fileURL: fileURL, caption: caption)
                recordConversationMessage(
                    accountID: target.account.id,
                    accountRole: target.account.role,
                    chatID: target.chatID,
                    direction: "outbound",
                    text: logText,
                    messageID: telegramMessageID,
                    updateID: nil,
                    status: "sent_file"
                )
                return successDirectFilePayload(account: target.account, chatID: target.chatID, fileURL: fileURL, delivery: delivery, reused: false)
            case .failure(let status, let code, let message, let retryAfterMs):
                return failurePayload(status: status, code: code, message: message, capabilityID: "telegram_direct.send_file", accountID: target.account.id, target: channel, chatID: target.chatID, filePath: fileURL.path, retryAfterMs: retryAfterMs)
            }
        } catch {
            return failurePayload(status: "failed", code: "telegram_direct_file_failed", message: error.localizedDescription, capabilityID: "telegram_direct.send_file", accountID: accountID, chatID: chatID, filePath: fileURL.path)
        }
    }

    private func resolveDirectConversationTarget(
        config: TelegramBridgeConfigFile,
        accountID: String?,
        chatID: String?
    ) throws -> (account: TelegramBridgeAccountConfig, chatID: String) {
        let trimmedAccountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedChatID = chatID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let directAccounts = config.accounts.filter { $0.role == "gee_direct" && $0.transport.mode == "polling" }

        if let trimmedAccountID {
            guard let account = directAccounts.first(where: { $0.id == trimmedAccountID }) else {
                throw TelegramBridgeGearError.configInvalid("Gee Direct account `\(trimmedAccountID)` was not found.")
            }
            if let trimmedChatID {
                return (account, trimmedChatID)
            }
            if let inferred = try latestDirectConversationThread(accountID: trimmedAccountID, chatID: nil) {
                return (account, inferred.chatId)
            }
            throw TelegramBridgeGearError.configInvalid("`chat_id` is required because no recent Gee Direct Telegram thread exists for account `\(trimmedAccountID)`.")
        }

        if let inferred = try latestDirectConversationThread(accountID: nil, chatID: trimmedChatID),
           let account = directAccounts.first(where: { $0.id == inferred.accountId }) {
            return (account, inferred.chatId)
        }

        if let trimmedChatID, directAccounts.count == 1, let account = directAccounts.first {
            return (account, trimmedChatID)
        }

        throw TelegramBridgeGearError.configInvalid("`account_id` and `chat_id` are required unless a recent Gee Direct Telegram inbound thread can identify the current chat.")
    }

    private func latestDirectConversationThread(
        accountID: String?,
        chatID: String?
    ) throws -> TelegramBridgeConversationThread? {
        let log = try database.loadConversationLog()
        return log.threads.first { thread in
            (thread.accountRole ?? "") == "gee_direct" &&
                (accountID == nil || thread.accountId == accountID) &&
                (chatID == nil || thread.chatId == chatID) &&
                thread.messages.contains { $0.direction == "inbound" }
        }
    }

    private func successSendPayload(
        channel: TelegramBridgePushChannelConfig,
        delivery: TelegramBridgeDeliveryRecord,
        reused: Bool
    ) -> [String: Any] {
        [
            "gear_id": TelegramBridgeGearRuntimeConstants.gearID,
            "capability_id": "telegram_push.send_message",
            "status": "success",
            "fallback_attempted": false,
            "channelId": channel.id,
            "accountId": channel.accountId,
            "target": redactedTarget(channel.target),
            "delivery": [
                "telegramMessageId": delivery.telegramMessageId,
                "telegramMessageIds": delivery.telegramMessageId.split(separator: ",").map(String.init),
                "messageCount": max(delivery.telegramMessageId.split(separator: ",").count, 1),
                "sentAt": delivery.sentAt,
                "idempotencyKey": delivery.idempotencyKey,
                "reused": reused
            ],
            "error": NSNull()
        ]
    }

    private func successPushFilePayload(
        channel: TelegramBridgePushChannelConfig,
        fileURL: URL,
        delivery: TelegramBridgeDeliveryRecord,
        reused: Bool
    ) -> [String: Any] {
        [
            "gear_id": TelegramBridgeGearRuntimeConstants.gearID,
            "capability_id": "telegram_push.send_file",
            "status": "success",
            "fallback_attempted": false,
            "channelId": channel.id,
            "accountId": channel.accountId,
            "target": redactedTarget(channel.target),
            "file": [
                "path": fileURL.path,
                "name": fileURL.lastPathComponent
            ],
            "delivery": [
                "telegramMessageId": delivery.telegramMessageId,
                "sentAt": delivery.sentAt,
                "idempotencyKey": delivery.idempotencyKey,
                "reused": reused
            ],
            "error": NSNull()
        ]
    }

    private func successDirectFilePayload(
        account: TelegramBridgeAccountConfig,
        chatID: String,
        fileURL: URL,
        delivery: TelegramBridgeDeliveryRecord,
        reused: Bool
    ) -> [String: Any] {
        [
            "gear_id": TelegramBridgeGearRuntimeConstants.gearID,
            "capability_id": "telegram_direct.send_file",
            "status": "success",
            "fallback_attempted": false,
            "accountId": account.id,
            "chatId": chatID,
            "target": redactedTarget(.init(kind: "chat_id", value: chatID)),
            "file": [
                "path": fileURL.path,
                "name": fileURL.lastPathComponent
            ],
            "delivery": [
                "telegramMessageId": delivery.telegramMessageId,
                "sentAt": delivery.sentAt,
                "idempotencyKey": delivery.idempotencyKey,
                "reused": reused
            ],
            "error": NSNull()
        ]
    }

    private func localFileURL(from path: String) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expanded, isDirectory: false)
            .standardizedFileURL
    }

    private func directFileLogText(fileURL: URL, caption: String?) -> String {
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCaption.isEmpty else {
            return "Sent file \(fileURL.lastPathComponent)"
        }
        return "Sent file \(fileURL.lastPathComponent)\n\(trimmedCaption)"
    }
}

struct TelegramBridgeFileDatabase {
    private let fileManager: FileManager
    private let dataDirectoryOverrideURL: URL?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    init(dataDirectoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.dataDirectoryOverrideURL = dataDirectoryURL
        self.fileManager = fileManager
    }

    var dataDirectoryURL: URL {
        if let dataDirectoryOverrideURL {
            return dataDirectoryOverrideURL
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GeeAgent", isDirectory: true)
            .appendingPathComponent("gear-data", isDirectory: true)
            .appendingPathComponent(TelegramBridgeGearRuntimeConstants.gearID, isDirectory: true)
    }

    var configURL: URL {
        dataDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    }

    var deliveryLogURL: URL {
        dataDirectoryURL.appendingPathComponent("delivery-log.json", isDirectory: false)
    }

    var pollingStateURL: URL {
        dataDirectoryURL.appendingPathComponent("polling-state.json", isDirectory: false)
    }

    var conversationLogURL: URL {
        dataDirectoryURL.appendingPathComponent("telegram-conversations.json", isDirectory: false)
    }

    func loadConfig() throws -> TelegramBridgeConfigFile {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return TelegramBridgeConfigFile()
        }
        let config = try decoder.decode(TelegramBridgeConfigFile.self, from: Data(contentsOf: configURL))
        guard config.version == TelegramBridgeConfigFile.currentVersion else {
            throw TelegramBridgeGearError.configInvalid("Telegram Bridge config version must be 1.")
        }
        return config
    }

    func saveConfig(_ config: TelegramBridgeConfigFile) throws {
        try fileManager.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        try encoder.encode(config).write(to: configURL, options: .atomic)
    }

    func delivery(idempotencyKey: String) throws -> TelegramBridgeDeliveryRecord? {
        try loadDeliveryLog().deliveries[idempotencyKey]
    }

    func saveDelivery(_ delivery: TelegramBridgeDeliveryRecord) throws {
        var log = try loadDeliveryLog()
        log.deliveries[delivery.idempotencyKey] = delivery
        try fileManager.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        try encoder.encode(log).write(to: deliveryLogURL, options: .atomic)
    }

    func loadPollingState() throws -> TelegramBridgePollingState {
        guard fileManager.fileExists(atPath: pollingStateURL.path) else {
            return TelegramBridgePollingState()
        }
        return try decoder.decode(TelegramBridgePollingState.self, from: Data(contentsOf: pollingStateURL))
    }

    func savePollingState(_ state: TelegramBridgePollingState) throws {
        try fileManager.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        try encoder.encode(state).write(to: pollingStateURL, options: .atomic)
    }

    func loadConversationLog() throws -> TelegramBridgeConversationLog {
        guard fileManager.fileExists(atPath: conversationLogURL.path) else {
            return TelegramBridgeConversationLog()
        }
        return try decoder.decode(TelegramBridgeConversationLog.self, from: Data(contentsOf: conversationLogURL))
    }

    func saveConversationLog(_ log: TelegramBridgeConversationLog) throws {
        try fileManager.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        try encoder.encode(log).write(to: conversationLogURL, options: .atomic)
    }

    private func loadDeliveryLog() throws -> TelegramBridgeDeliveryLog {
        guard fileManager.fileExists(atPath: deliveryLogURL.path) else {
            return TelegramBridgeDeliveryLog()
        }
        return try decoder.decode(TelegramBridgeDeliveryLog.self, from: Data(contentsOf: deliveryLogURL))
    }
}

struct TelegramBridgeTokenStore {
    private let fileManager: FileManager
    private let storageURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GeeAgent", isDirectory: true)
            .appendingPathComponent("gear-data", isDirectory: true)
            .appendingPathComponent(TelegramBridgeGearRuntimeConstants.gearID, isDirectory: true)
            .appendingPathComponent("tokens.json", isDirectory: false)
    }

    func token(accountID: String) throws -> String? {
        let trimmedAccountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountID.isEmpty else {
            return nil
        }
        let tokenFile = try loadTokenFile()
        return tokenFile.tokens[trimmedAccountID]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    func status(accountID: String) -> (configured: Bool, status: String, error: String?) {
        do {
            let token = try token(accountID: accountID)
            return (token?.isEmpty == false, token?.isEmpty == false ? "configured" : "missing", nil)
        } catch {
            return (false, "error", error.localizedDescription)
        }
    }

    func saveToken(_ token: String, accountID: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram bot token cannot be empty.")
        }
        let trimmedAccountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountID.isEmpty else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram account id cannot be empty.")
        }
        var tokenFile = try loadTokenFile()
        tokenFile.tokens[trimmedAccountID] = trimmed
        try saveTokenFile(tokenFile)
    }

    func deleteToken(accountID: String) throws {
        let trimmedAccountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountID.isEmpty else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram account id cannot be empty.")
        }
        var tokenFile = try loadTokenFile()
        tokenFile.tokens.removeValue(forKey: trimmedAccountID)
        if tokenFile.tokens.isEmpty {
            if fileManager.fileExists(atPath: storageURL.path) {
                try fileManager.removeItem(at: storageURL)
            }
            return
        }
        try saveTokenFile(tokenFile)
    }

    private func loadTokenFile() throws -> TelegramBridgeTokenFile {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return TelegramBridgeTokenFile()
        }
        let tokenFile = try decoder.decode(TelegramBridgeTokenFile.self, from: Data(contentsOf: storageURL))
        guard tokenFile.version == TelegramBridgeTokenFile.currentVersion else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram token store version must be 1.")
        }
        return tokenFile
    }

    private func saveTokenFile(_ tokenFile: TelegramBridgeTokenFile) throws {
        let directoryURL = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        try encoder.encode(tokenFile).write(to: storageURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
    }
}

struct TelegramBridgeSender {
    enum Result: Sendable {
        case success(telegramMessageID: String, sentAt: String)
        case failure(status: String, code: String, message: String, retryAfterMs: Int?)
    }

    struct TelegramResponse: Decodable {
        struct Message: Decodable {
            var messageId: FlexibleID?
            var date: Double?

            enum CodingKeys: String, CodingKey {
                case messageId = "message_id"
                case date
            }
        }

        struct Parameters: Decodable {
            var retryAfter: Double?

            enum CodingKeys: String, CodingKey {
                case retryAfter = "retry_after"
            }
        }

        var ok: Bool?
        var description: String?
        var result: Message?
        var parameters: Parameters?

        init(
            ok: Bool? = nil,
            description: String? = nil,
            result: Message? = nil,
            parameters: Parameters? = nil
        ) {
            self.ok = ok
            self.description = description
            self.result = result
            self.parameters = parameters
        }
    }

    struct GenericResponse: Decodable {
        var ok: Bool?
        var description: String?
        var result: Bool?
        var parameters: TelegramResponse.Parameters?

        init(ok: Bool? = nil, description: String? = nil, result: Bool? = nil, parameters: TelegramResponse.Parameters? = nil) {
            self.ok = ok
            self.description = description
            self.result = result
            self.parameters = parameters
        }
    }

    struct Update: Decodable {
        struct MessageLike: Decodable {
            struct AttachmentPresence: Decodable {
                init(from decoder: Decoder) throws {}
            }

            struct MediaFile: Decodable {
                var fileID: String
                var fileUniqueID: String?
                var width: Int?
                var height: Int?

                enum CodingKeys: String, CodingKey {
                    case fileID = "file_id"
                    case fileUniqueID = "file_unique_id"
                    case width
                    case height
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    fileID = try container.decodeIfPresent(String.self, forKey: .fileID) ?? ""
                    fileUniqueID = try container.decodeIfPresent(String.self, forKey: .fileUniqueID)
                    width = try container.decodeIfPresent(Int.self, forKey: .width)
                    height = try container.decodeIfPresent(Int.self, forKey: .height)
                }
            }

            struct Chat: Decodable {
                var id: FlexibleID
                var type: String?
                var username: String?
                var title: String?
            }

            struct User: Decodable {
                var id: FlexibleID
                var username: String?
            }

            var messageId: FlexibleID?
            var from: User?
            var chat: Chat
            var text: String?
            var caption: String?
            var photo: [MediaFile]?
            var document: MediaFile?
            var video: MediaFile?
            var animation: MediaFile?
            var audio: MediaFile?
            var voice: MediaFile?
            var videoNote: MediaFile?
            var sticker: MediaFile?
            var paidMedia: AttachmentPresence?
            var contact: AttachmentPresence?
            var location: AttachmentPresence?
            var venue: AttachmentPresence?
            var poll: AttachmentPresence?
            var dice: AttachmentPresence?
            var game: AttachmentPresence?

            enum CodingKeys: String, CodingKey {
                case messageId = "message_id"
                case from
                case chat
                case text
                case caption
                case photo
                case document
                case video
                case animation
                case audio
                case voice
                case videoNote = "video_note"
                case sticker
                case paidMedia = "paid_media"
                case contact
                case location
                case venue
                case poll
                case dice
                case game
            }

            var unsupportedAttachmentKey: String? {
                let unsupportedKeys: [(String, AttachmentPresence?)] = [
                    ("paid_media", paidMedia),
                    ("contact", contact),
                    ("location", location),
                    ("venue", venue),
                    ("poll", poll),
                    ("dice", dice),
                    ("game", game)
                ]
                for (key, value) in unsupportedKeys where value != nil {
                    return key
                }
                return nil
            }
        }

        struct CallbackQuery: Decodable {
            var id: String
            var from: MessageLike.User?
            var message: MessageLike?
            var data: String?
        }

        var updateId: Int
        var message: MessageLike?
        var editedMessage: MessageLike?
        var channelPost: MessageLike?
        var editedChannelPost: MessageLike?
        var callbackQuery: CallbackQuery?

        enum CodingKeys: String, CodingKey {
            case updateId = "update_id"
            case message
            case editedMessage = "edited_message"
            case channelPost = "channel_post"
            case editedChannelPost = "edited_channel_post"
            case callbackQuery = "callback_query"
        }

        var chatID: String? {
            messagePayload?.chat.id.value
        }

        var fromUserID: String? {
            actorUserID
        }

        var messagePayload: MessageLike? {
            message ?? editedMessage ?? channelPost ?? editedChannelPost ?? callbackQuery?.message
        }

        var actorUserID: String? {
            callbackQuery?.from?.id.value ?? messagePayload?.from?.id.value
        }

        var callbackCommandText: String? {
            TelegramCodexRemoteBridge.commandText(forCallbackData: callbackQuery?.data)
        }
    }

    struct UpdatesResponse: Decodable {
        var ok: Bool?
        var description: String?
        var result: [Update]?
    }

    func getUpdates(token: String, offset: Int?, limit: Int, timeout: Int) async throws -> [Update] {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram bot token is required before polling updates.")
        }
        var components = URLComponents(string: "https://api.telegram.org/bot\(trimmed)/getUpdates")
        components?.queryItems = [
            offset.map { URLQueryItem(name: "offset", value: "\($0)") },
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "timeout", value: "\(timeout)"),
            URLQueryItem(name: "allowed_updates", value: "[\"message\",\"edited_message\",\"channel_post\",\"edited_channel_post\",\"callback_query\"]")
        ].compactMap(\.self)
        guard let url = components?.url else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram Bot API URL could not be constructed.")
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let payload = (try? JSONDecoder().decode(UpdatesResponse.self, from: data)) ?? UpdatesResponse(ok: nil, description: nil, result: nil)
            guard statusCode >= 200, statusCode < 300, payload.ok == true else {
                let description = sanitizeSensitiveText(payload.description ?? "Telegram returned HTTP \(statusCode).", token: trimmed)
                throw TelegramBridgeGearError.tokenUnavailable(description)
            }
            return payload.result ?? []
        } catch let error as TelegramBridgeGearError {
            throw error
        } catch {
            throw TelegramBridgeGearError.tokenUnavailable(sanitizeSensitiveText(error.localizedDescription, token: trimmed))
        }
    }

    func latestChatID(token: String) async throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram bot token is required before fetching a chat ID.")
        }
        do {
            let updates = try await getUpdates(token: trimmed, offset: nil, limit: 100, timeout: 0)
            guard let chatID = updates.compactMap(\.chatID).last, !chatID.isEmpty else {
                throw TelegramBridgeGearError.configInvalid("No Telegram updates with a chat ID were found. Send a message to this bot, then try again.")
            }
            return chatID
        } catch let error as TelegramBridgeGearError {
            throw error
        } catch {
            throw TelegramBridgeGearError.tokenUnavailable(sanitizeSensitiveText(error.localizedDescription, token: trimmed))
        }
    }

    func latestUserID(token: String) async throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram bot token is required before fetching a user ID.")
        }
        do {
            let updates = try await getUpdates(token: trimmed, offset: nil, limit: 100, timeout: 0)
            guard let userID = updates.compactMap(\.fromUserID).last, !userID.isEmpty else {
                throw TelegramBridgeGearError.configInvalid("No Telegram updates with a sender user ID were found. Send a direct message to this bot, then try again.")
            }
            return userID
        } catch let error as TelegramBridgeGearError {
            throw error
        } catch {
            throw TelegramBridgeGearError.tokenUnavailable(sanitizeSensitiveText(error.localizedDescription, token: trimmed))
        }
    }

    func sendMessage(
        token: String,
        target: TelegramBridgePushTargetConfig,
        text: String,
        parseMode: String?,
        disableWebPreview: Bool?,
        replyMarkup: TelegramBridgeReplyMarkup? = nil
    ) async throws -> Result {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            return .failure(status: "failed", code: "telegram_url_invalid", message: "Telegram Bot API URL could not be constructed.", retryAfterMs: nil)
        }
        var body: [String: Any] = [
            "chat_id": target.value,
            "text": text
        ]
        if let parseMode {
            body["parse_mode"] = parseMode
        }
        if let disableWebPreview {
            body["disable_web_page_preview"] = disableWebPreview
        }
        if let replyMarkup {
            body["reply_markup"] = replyMarkup.jsonObject
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let payload = (try? JSONDecoder().decode(TelegramResponse.self, from: data)) ?? TelegramResponse()
            if statusCode >= 200,
               statusCode < 300,
               payload.ok == true,
               let messageID = payload.result?.messageId?.value,
               !messageID.isEmpty,
               let date = payload.result?.date
            {
                return .success(
                    telegramMessageID: messageID,
                    sentAt: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: date))
                )
            }
            return apiFailure(statusCode: statusCode, payload: payload, token: token)
        } catch {
            return .failure(
                status: "degraded",
                code: "network_unavailable",
                message: sanitizeSensitiveText(error.localizedDescription, token: token),
                retryAfterMs: nil
            )
        }
    }

    static func botCommands(for role: String) -> [TelegramBridgeBotCommand] {
        switch role {
        case "codex_remote":
            return [
                .init(command: "start", description: "Show Codex Remote help"),
                .init(command: "help", description: "Show Codex Remote help"),
                .init(command: "list", description: "Show projects with recent Codex Desktop sessions"),
                .init(command: "recent", description: "Same as /list"),
                .init(command: "tracked", description: "Show tracked Codex projects"),
                .init(command: "open", description: "Open a listed Codex thread"),
                .init(command: "latest", description: "Fetch the latest Codex reply"),
                .init(command: "desktop", description: "Open the thread in Codex Desktop"),
                .init(command: "send", description: "Send a prompt to a selected thread"),
                .init(command: "cancel", description: "Cancel pending Codex Remote state")
            ]
        case "gee_direct":
            return [
                .init(command: "new", description: "Start a fresh GeeAgent Telegram conversation")
            ]
        default:
            return []
        }
    }

    func setMyCommands(token: String, commands: [TelegramBridgeBotCommand]) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram bot token is required before updating the bot command menu.")
        }
        guard let url = URL(string: "https://api.telegram.org/bot\(trimmed)/setMyCommands") else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram Bot API URL could not be constructed.")
        }
        let body: [String: Any] = [
            "commands": commands.map { command in
                [
                    "command": command.command,
                    "description": command.description
                ]
            }
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let payload = (try? JSONDecoder().decode(GenericResponse.self, from: data)) ?? GenericResponse()
            guard statusCode >= 200, statusCode < 300, payload.ok == true else {
                throw TelegramBridgeGearError.tokenUnavailable(
                    sanitizeSensitiveText(payload.description ?? "Telegram returned HTTP \(statusCode).", token: trimmed)
                )
            }
        } catch let error as TelegramBridgeGearError {
            throw error
        } catch {
            throw TelegramBridgeGearError.tokenUnavailable(sanitizeSensitiveText(error.localizedDescription, token: trimmed))
        }
    }

    func answerCallbackQuery(token: String, callbackQueryID: String, text: String? = nil) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram bot token is required before answering a callback query.")
        }
        guard let url = URL(string: "https://api.telegram.org/bot\(trimmed)/answerCallbackQuery") else {
            throw TelegramBridgeGearError.tokenUnavailable("Telegram Bot API URL could not be constructed.")
        }
        var body: [String: Any] = ["callback_query_id": callbackQueryID]
        if let text, !text.isEmpty {
            body["text"] = text
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let payload = (try? JSONDecoder().decode(GenericResponse.self, from: data)) ?? GenericResponse()
            guard statusCode >= 200, statusCode < 300, payload.ok == true else {
                throw TelegramBridgeGearError.tokenUnavailable(
                    sanitizeSensitiveText(payload.description ?? "Telegram returned HTTP \(statusCode).", token: trimmed)
                )
            }
        } catch let error as TelegramBridgeGearError {
            throw error
        } catch {
            throw TelegramBridgeGearError.tokenUnavailable(sanitizeSensitiveText(error.localizedDescription, token: trimmed))
        }
    }

    func sendLocalFile(
        token: String,
        target: TelegramBridgePushTargetConfig,
        fileURL: URL,
        caption: String?
    ) async throws -> Result {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let upload = uploadEndpoint(for: fileURL)
        guard let url = URL(string: "https://api.telegram.org/bot\(trimmed)/\(upload.endpoint)") else {
            return .failure(status: "failed", code: "telegram_url_invalid", message: "Telegram Bot API URL could not be constructed.", retryAfterMs: nil)
        }
        let boundary = "GeeAgentTelegramBoundary\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        var fields = ["chat_id": target.value]
        if let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
            fields["caption"] = caption
        }
        request.httpBody = try multipartBody(
            boundary: boundary,
            fields: fields,
            fileFieldName: upload.fieldName,
            fileURL: fileURL,
            mimeType: mimeType(for: fileURL)
        )
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let payload = (try? JSONDecoder().decode(TelegramResponse.self, from: data)) ?? TelegramResponse()
            if statusCode >= 200,
               statusCode < 300,
               payload.ok == true,
               let messageID = payload.result?.messageId?.value,
               !messageID.isEmpty,
               let date = payload.result?.date
            {
                return .success(
                    telegramMessageID: messageID,
                    sentAt: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: date))
                )
            }
            return apiFailure(statusCode: statusCode, payload: payload, token: trimmed)
        } catch {
            return .failure(
                status: "degraded",
                code: "network_unavailable",
                message: sanitizeSensitiveText(error.localizedDescription, token: trimmed),
                retryAfterMs: nil
            )
        }
    }

    private func apiFailure(statusCode: Int, payload: TelegramResponse, token: String) -> Result {
        let retryAfterMs = payload.parameters?.retryAfter.map { Int($0 * 1000) }
        let description = sanitizeSensitiveText(payload.description ?? "Telegram returned HTTP \(statusCode).", token: token)
        if statusCode == 429 || retryAfterMs != nil {
            return .failure(status: "degraded", code: "telegram_rate_limited", message: description, retryAfterMs: retryAfterMs)
        }
        switch statusCode {
        case 400:
            return .failure(status: "failed", code: "telegram_bad_request", message: description, retryAfterMs: nil)
        case 401:
            return .failure(status: "failed", code: "telegram_unauthorized", message: description, retryAfterMs: nil)
        case 403:
            return .failure(status: "failed", code: "telegram_forbidden", message: description, retryAfterMs: nil)
        default:
            return .failure(status: "failed", code: "telegram_api_error", message: description, retryAfterMs: nil)
        }
    }

    private func uploadEndpoint(for fileURL: URL) -> (endpoint: String, fieldName: String) {
        switch fileURL.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "webp":
            return ("sendPhoto", "photo")
        case "gif":
            return ("sendAnimation", "animation")
        case "mp4", "m4v", "mov", "webm":
            return ("sendVideo", "video")
        default:
            return ("sendDocument", "document")
        }
    }

    private func multipartBody(
        boundary: String,
        fields: [String: String],
        fileFieldName: String,
        fileURL: URL,
        mimeType: String
    ) throws -> Data {
        var body = Data()
        for (name, value) in fields {
            append("--\(boundary)\r\n", to: &body)
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &body)
            append("\(value)\r\n", to: &body)
        }
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(escapedMultipartFilename(fileURL.lastPathComponent))\"\r\n", to: &body)
        append("Content-Type: \(mimeType)\r\n\r\n", to: &body)
        body.append(try Data(contentsOf: fileURL))
        append("\r\n--\(boundary)--\r\n", to: &body)
        return body
    }

    private func append(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }

    private func escapedMultipartFilename(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "webm":
            return "video/webm"
        case "pdf":
            return "application/pdf"
        case "txt", "log", "md":
            return "text/plain"
        case "json":
            return "application/json"
        case "csv":
            return "text/csv"
        case "zip":
            return "application/zip"
        default:
            return "application/octet-stream"
        }
    }
}

extension TelegramBridgeSender: TelegramBridgeSending {}

struct TelegramCodexRemoteReply: Hashable, Sendable {
    var status: String
    var text: String
    var replyMarkup: TelegramBridgeReplyMarkup? = nil
}

struct TelegramCodexRemotePendingPrompt: Hashable, Sendable {
    var sessionID: String
    var prompt: String
}

enum TelegramCodexRemoteProjectListMode: String, Hashable, Sendable {
    case all
    case tracked
}

struct TelegramCodexRemoteSessionState: Hashable, Sendable {
    var selectedThreadID: String?
    var pendingPrompt: TelegramCodexRemotePendingPrompt?
    var projectListMode: TelegramCodexRemoteProjectListMode = .all
    var lastThreadIDs: [String] = []

    mutating func clearActiveSelection() {
        selectedThreadID = nil
        pendingPrompt = nil
        lastThreadIDs = []
    }

    mutating func prepareProjectList(mode: TelegramCodexRemoteProjectListMode) {
        clearActiveSelection()
        projectListMode = mode
    }

    mutating func rememberThreadList(_ threadIDs: [String]) {
        lastThreadIDs = threadIDs
    }

    mutating func selectThread(_ threadID: String) {
        selectedThreadID = threadID
    }

    mutating func stagePrompt(sessionID: String, prompt: String) {
        pendingPrompt = TelegramCodexRemotePendingPrompt(sessionID: sessionID, prompt: prompt)
    }

    mutating func clearPendingPrompt() {
        pendingPrompt = nil
    }

    mutating func popPendingPrompt(matching selector: String?) -> TelegramCodexRemotePendingPrompt? {
        guard let pendingPrompt,
              selector == nil || selector == pendingPrompt.sessionID
        else {
            return nil
        }
        self.pendingPrompt = nil
        return pendingPrompt
    }
}

enum TelegramCodexRemoteRoute: Hashable, Sendable {
    case usage
    case plainText(prompt: String)
    case help
    case list
    case tracked
    case projectPage(page: Int)
    case project(selector: String?)
    case threadPage(selector: String?, page: Int)
    case track(selector: String?)
    case untrack(selector: String?)
    case open(selector: String?)
    case latest(selector: String?)
    case desktop(selector: String?)
    case send(arguments: String?)
    case confirm(selector: String?)
    case cancel
    case unsupported
}

enum TelegramCodexRemoteSendDecision: Hashable, Sendable {
    case blocked
    case stageSelected(sessionID: String, prompt: String)
    case sendExplicit(sessionID: String, prompt: String)
}

enum TelegramCodexRemoteSendPlanner {
    static func decision(
        arguments: String?,
        selectedSessionID: String?,
        explicitSessionExists: (String) -> Bool
    ) -> TelegramCodexRemoteSendDecision {
        guard let arguments = arguments?.trimmingCharacters(in: .whitespacesAndNewlines),
              !arguments.isEmpty
        else {
            return .blocked
        }

        let pieces = arguments.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        if let sessionID = pieces.first,
           pieces.count >= 2,
           explicitSessionExists(sessionID)
        {
            return .sendExplicit(sessionID: sessionID, prompt: pieces[1])
        }

        if let selectedSessionID {
            return .stageSelected(sessionID: selectedSessionID, prompt: arguments)
        }

        guard let sessionID = pieces.first,
              pieces.count >= 2
        else {
            return .blocked
        }
        return .sendExplicit(sessionID: sessionID, prompt: pieces[1])
    }
}

enum TelegramCodexRemoteRouter {
    static func commandText(forCallbackData data: String?) -> String? {
        guard let data = data?.trimmingCharacters(in: .whitespacesAndNewlines), !data.isEmpty else {
            return nil
        }
        let pieces = data.split(separator: ":").map(String.init)
        guard let action = pieces.first else {
            return nil
        }
        let value = pieces.dropFirst().first ?? ""
        switch action {
        case "project":
            return "/project \(value)"
        case "projectPage":
            return "/projectPage \(value)"
        case "threadPage":
            guard pieces.count >= 3 else { return nil }
            return "/threadPage \(pieces[1]) \(pieces[2])"
        case "track":
            return "/track \(value)"
        case "untrack":
            return "/untrack \(value)"
        case "open":
            return "/open \(value)"
        case "latest":
            return "/latest \(value)"
        case "desktop":
            return "/desktop \(value)"
        case "confirm":
            return "/confirm \(value)"
        case "cancel":
            return "/cancel"
        default:
            return nil
        }
    }

    static func route(forCallbackData data: String?) -> TelegramCodexRemoteRoute? {
        commandText(forCallbackData: data).map { route($0) }
    }

    static func route(_ text: String) -> TelegramCodexRemoteRoute {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 2, whereSeparator: \.isWhitespace).map(String.init)
        guard let rawCommand = parts.first else {
            return .usage
        }
        let command = normalizedCommand(rawCommand)
        guard command.hasPrefix("/") else {
            return .plainText(prompt: trimmed)
        }
        switch command {
        case "/start", "/help":
            return .help
        case "/list", "/recent":
            return .list
        case "/tracked":
            return .tracked
        case "/projectpage":
            return .projectPage(page: Int(parts.dropFirst().first ?? "") ?? 1)
        case "/project":
            return .project(selector: argument(parts.dropFirst()))
        case "/threadpage":
            let selector = parts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let page = Int(parts.dropFirst(2).first ?? "") ?? 1
            return .threadPage(selector: selector, page: page)
        case "/track":
            return .track(selector: argument(parts.dropFirst()))
        case "/untrack":
            return .untrack(selector: argument(parts.dropFirst()))
        case "/open":
            return .open(selector: argument(parts.dropFirst()))
        case "/latest":
            return .latest(selector: argument(parts.dropFirst()))
        case "/desktop":
            return .desktop(selector: argument(parts.dropFirst()))
        case "/send":
            return .send(arguments: argument(parts.dropFirst()))
        case "/confirm":
            return .confirm(selector: argument(parts.dropFirst()))
        case "/cancel":
            return .cancel
        default:
            return .unsupported
        }
    }

    private static func normalizedCommand(_ value: String) -> String {
        guard let command = value.split(separator: "@", maxSplits: 1).first else {
            return ""
        }
        return String(command).lowercased()
    }

    private static func argument<S: Sequence>(_ parts: S) -> String? where S.Element == String {
        parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

@MainActor
final class TelegramCodexRemoteBridge {
    struct Project: Hashable, Sendable {
        var key: String
        var name: String
        var cwd: String
    }

    struct ProjectGroup: Hashable, Sendable {
        var project: Project
        var items: [Thread]
    }

    struct PageData<Item>: Sendable where Item: Sendable {
        var items: [Item]
        var page: Int
        var pageCount: Int
        var start: Int
    }

    struct TrackedProject: Codable, Hashable, Sendable {
        var key: String
        var name: String
        var cwd: String
        var trackedAt: String

        var project: Project {
            Project(key: key, name: name, cwd: cwd)
        }
    }

    struct TrackingState: Codable, Sendable {
        var trackedProjectsByChat: [String: [String: TrackedProject]] = [:]
    }

    struct Thread: Hashable, Sendable {
        var id: String
        var title: String
        var cwd: String?
        var updatedAt: String?
        var filePath: String
        var originator: String?
        var agentRole: String?
        var agentNickname: String?
        var sourceSubagent: Bool

        var isCodexDesktopVisible: Bool {
            originator?.trimmingCharacters(in: .whitespacesAndNewlines) == "Codex Desktop" &&
                agentRole?.nilIfEmpty == nil &&
                agentNickname?.nilIfEmpty == nil &&
                !sourceSubagent
        }
    }

    private static let globalProject = Project(key: "global", name: "Global", cwd: "")
    private static let projectMarkerNames = [".git", "package.json", "pyproject.toml", "Cargo.toml", "go.mod", "AGENTS.md"]
    private static let projectPageSize = 6
    private static let threadPageSize = 6
    private static let fileScanRecentDirectoryLimit = 14
    private static let fileScanMaximumFilesPerDirectory = 60
    private static let fileScanMaximumDirectoryEntryReads = 240
    private static let fileScanMaximumCandidateCount = 300
    private static let fileScanThreadReadLineLimit = 400
    private static let fileScanLatestReplyTailBytes = 512 * 1024
    private static let fileScanLatestReplyLineLimit = 600

    private let fileManager: FileManager
    private let codexHomeURL: URL
    private let codexBinaryURL: URL
    private let trackingStateURL: URL
    private let runner: any GearCommandRunning
    private let timeoutSeconds: TimeInterval
    private var sessionStatesByChat: [String: TelegramCodexRemoteSessionState] = [:]

    init(
        fileManager: FileManager = .default,
        codexHomeURL: URL? = nil,
        codexBinaryURL: URL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
        trackingStateURL: URL? = nil,
        runner: any GearCommandRunning = GearShellCommandRunner(),
        timeoutSeconds: TimeInterval = 20 * 60
    ) {
        self.fileManager = fileManager
        self.codexHomeURL = codexHomeURL ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        self.codexBinaryURL = codexBinaryURL
        self.trackingStateURL = trackingStateURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GeeAgent", isDirectory: true)
            .appendingPathComponent("gear-data", isDirectory: true)
            .appendingPathComponent(TelegramBridgeGearRuntimeConstants.gearID, isDirectory: true)
            .appendingPathComponent("codex-remote-tracking.json", isDirectory: false)
        self.runner = runner
        self.timeoutSeconds = timeoutSeconds
    }

    nonisolated static func commandText(forCallbackData data: String?) -> String? {
        TelegramCodexRemoteRouter.commandText(forCallbackData: data)
    }

    func reply(
        for account: TelegramBridgeAccountConfig,
        text: String,
        chatID: String? = nil
    ) async -> TelegramCodexRemoteReply {
        let stateKey = chatStateKey(account: account, chatID: chatID)
        let source = account.codex?.threadSource ?? "file_scan"
        let mode = account.codex?.sendMode ?? "cli_resume"
        func clearActiveSelection() {
            updateSessionState(stateKey) { state in
                state.clearActiveSelection()
            }
        }
        switch TelegramCodexRemoteRouter.route(text) {
        case .usage:
            return .init(status: "codex_blocked", text: codexUsageText())
        case .plainText(let prompt):
            guard let sessionID = sessionState(for: stateKey).selectedThreadID else {
                return .init(status: "codex_blocked", text: "No session selected. Use `/list`, choose a project, then Open a thread.")
            }
            return stagePromptReply(
                sessionID: sessionID,
                prompt: prompt,
                source: source,
                stateKey: stateKey
            )
        case .help:
            return .init(status: "codex_success", text: codexHelpText())
        case .list:
            updateSessionState(stateKey) { state in
                state.prepareProjectList(mode: .all)
            }
            return projectListReply(source: source, stateKey: stateKey, mode: .all, page: 1)
        case .tracked:
            updateSessionState(stateKey) { state in
                state.prepareProjectList(mode: .tracked)
            }
            return projectListReply(source: source, stateKey: stateKey, mode: .tracked, page: 1)
        case .projectPage(let page):
            let listMode = sessionState(for: stateKey).projectListMode
            return projectListReply(source: source, stateKey: stateKey, mode: listMode, page: page)
        case .project(let selector):
            clearActiveSelection()
            return projectThreadsReply(
                selector: selector,
                page: 1,
                source: source,
                stateKey: stateKey
            )
        case .threadPage(let selector, let page):
            clearActiveSelection()
            return projectThreadsReply(
                selector: selector,
                page: page,
                source: source,
                stateKey: stateKey
            )
        case .track(let selector):
            return trackProjectReply(selector: selector, source: source, stateKey: stateKey)
        case .untrack(let selector):
            return untrackProjectReply(selector: selector, source: source, stateKey: stateKey)
        case .open(let selector):
            return latestThreadReply(
                selector: selector,
                source: source,
                opened: true,
                stateKey: stateKey
            )
        case .latest(let selector):
            return latestThreadReply(
                selector: selector,
                source: source,
                opened: false,
                stateKey: stateKey
            )
        case .desktop(let selector):
            return await openDesktopThreadReply(
                selector: selector,
                source: source,
                stateKey: stateKey
            )
        case .send(let arguments):
            return await sendPromptRouteReply(
                arguments: arguments,
                source: source,
                mode: mode,
                stateKey: stateKey
            )
        case .confirm(let selector):
            return await confirmPromptReply(selector: selector, mode: mode, stateKey: stateKey)
        case .cancel:
            updateSessionState(stateKey) { state in
                state.clearPendingPrompt()
            }
            return .init(status: "codex_success", text: "Cancelled pending Codex Remote prompt.")
        case .unsupported:
            return .init(status: "codex_blocked", text: codexUsageText())
        }
    }

    private func sessionState(for stateKey: String) -> TelegramCodexRemoteSessionState {
        sessionStatesByChat[stateKey] ?? TelegramCodexRemoteSessionState()
    }

    private func updateSessionState(
        _ stateKey: String,
        _ update: (inout TelegramCodexRemoteSessionState) -> Void
    ) {
        var state = sessionState(for: stateKey)
        update(&state)
        sessionStatesByChat[stateKey] = state
    }

    private func openDesktopThreadReply(selector: String?, source: String, stateKey: String) async -> TelegramCodexRemoteReply {
        guard source == "file_scan" else {
            return .init(
                status: "codex_failed",
                text: "Codex desktop open failed: Codex app-server thread reading is not configured for Telegram Bridge."
            )
        }
        guard let selector = selector?.nilIfEmpty ?? sessionState(for: stateKey).selectedThreadID else {
            return .init(status: "codex_blocked", text: "Pick a thread from `/list` or pass a session id to `/desktop`.")
        }
        do {
            guard let thread = try resolveFileScanThread(selector: selector, stateKey: stateKey) else {
                return .init(status: "codex_failed", text: "Session not found: \(selector)")
            }
            updateSessionState(stateKey) { state in
                state.selectThread(thread.id)
            }
            let encodedID = thread.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? thread.id
            let url = "codex://threads/\(encodedID)"
            let openResult = await runner.run("/usr/bin/open", arguments: ["-a", "Codex", url], timeoutSeconds: 5)
            guard openResult.exitCode == 0 else {
                return .init(
                    status: "codex_failed",
                    text: "Codex desktop open failed: \(truncateOneLine(openResult.combinedOutput, limit: 1200))"
                )
            }
            _ = await runner.run("/usr/bin/osascript", arguments: ["-e", #"tell application "Codex" to activate"#], timeoutSeconds: 5)
            return .init(status: "codex_success", text: "Opened in Codex Desktop: \(thread.title)")
        } catch {
            return .init(status: "codex_failed", text: "Codex desktop open failed: \(error.localizedDescription)")
        }
    }

    private func projectListReply(
        source: String,
        stateKey: String,
        mode: TelegramCodexRemoteProjectListMode,
        page: Int
    ) -> TelegramCodexRemoteReply {
        guard source == "file_scan" else {
            return .init(
                status: "codex_failed",
                text: "Codex thread list failed: Codex app-server thread listing is not configured for Telegram Bridge."
            )
        }
        do {
            let groups = try projectGroups(source: source, stateKey: stateKey, mode: mode)
            guard !groups.isEmpty else {
                switch mode {
                case .tracked:
                    return .init(status: "codex_success", text: "No tracked projects yet. Use `/list`, then Track.")
                case .all:
                    return .init(status: "codex_success", text: "No Codex threads found.")
                }
            }
            let pageData = paginate(groups, requestedPage: page, pageSize: Self.projectPageSize)
            let title = mode == .tracked ? "Tracked projects" : "Projects"
            let heading = pageData.pageCount > 1
                ? "\(title) (page \(pageData.page) of \(pageData.pageCount)):"
                : "\(title):"
            let trackedKeys = trackedProjectKeys(stateKey: stateKey)
            let lines = pageData.items.enumerated().flatMap { offset, group -> [String] in
                let index = pageData.start + offset + 1
                return [
                    "\(index). \(truncateOneLine(group.project.name, limit: 48))",
                    "   \(group.items.count) thread(s)",
                    group.project.cwd.isEmpty
                        ? "   no project root"
                        : "   \(truncateMiddlePath(group.project.cwd, limit: 96))"
                ]
            }
            let projectRows = pageData.items.enumerated().map { offset, group in
                let index = pageData.start + offset + 1
                let tracked = trackedKeys.contains(group.project.key)
                let action = tracked ? "untrack" : "track"
                return [
                    TelegramBridgeInlineKeyboardButton(
                        text: "\(index). \(buttonTitle(group.project.name)) (\(group.items.count))",
                        callbackData: "project:\(index)"
                    ),
                    TelegramBridgeInlineKeyboardButton(
                        text: tracked ? "Untrack" : "Track",
                        callbackData: "\(action):\(index)"
                    )
                ]
            }
            let keyboard = projectRows + navigationRow(prefix: "projectPage", pageData: pageData)
            return .init(
                status: "codex_success",
                text: ([heading] + lines).joined(separator: "\n"),
                replyMarkup: TelegramBridgeReplyMarkup(inlineKeyboard: keyboard)
            )
        } catch {
            return .init(status: "codex_failed", text: "Codex thread list failed: \(error.localizedDescription)")
        }
    }

    private func projectThreadsReply(
        selector: String?,
        page: Int,
        source: String,
        stateKey: String
    ) -> TelegramCodexRemoteReply {
        guard source == "file_scan" else {
            return .init(
                status: "codex_failed",
                text: "Codex project listing failed: Codex app-server thread reading is not configured for Telegram Bridge."
            )
        }
        guard let selector, let selectedIndex = Int(selector), selectedIndex > 0 else {
            return .init(status: "codex_blocked", text: "Choose a project button from `/list` or pass `/project <number>`.")
        }
        do {
            let groups = try projectGroups(
                source: source,
                stateKey: stateKey,
                mode: sessionState(for: stateKey).projectListMode
            )
            guard selectedIndex <= groups.count else {
                return .init(status: "codex_failed", text: "Project not found. Use `/list` to refresh projects.")
            }
            let group = groups[selectedIndex - 1]
            guard !group.items.isEmpty else {
                return .init(status: "codex_success", text: "No recent Codex threads found for \(group.project.name).")
            }
            let pageData = paginate(group.items, requestedPage: page, pageSize: Self.threadPageSize)
            updateSessionState(stateKey) { state in
                state.rememberThreadList(group.items.map(\.id))
            }
            let lines = pageData.items.enumerated().map { offset, thread in
                formatThreadLine(thread, index: pageData.start + offset + 1)
            }
            let threadRows = pageData.items.map { thread in
                [
                    TelegramBridgeInlineKeyboardButton(text: buttonTitle(thread.title), callbackData: "open:\(thread.id)"),
                    TelegramBridgeInlineKeyboardButton(text: "Latest", callbackData: "latest:\(thread.id)"),
                    TelegramBridgeInlineKeyboardButton(text: "Desktop", callbackData: "desktop:\(thread.id)")
                ]
            }
            let keyboard = threadRows + navigationRow(prefix: "threadPage:\(selectedIndex)", pageData: pageData)
            return .init(
                status: "codex_success",
                text: ([threadListHeading(group, pageData: pageData)] + lines).joined(separator: "\n"),
                replyMarkup: TelegramBridgeReplyMarkup(inlineKeyboard: keyboard)
            )
        } catch {
            return .init(status: "codex_failed", text: "Codex project listing failed: \(error.localizedDescription)")
        }
    }

    private func trackProjectReply(selector: String?, source: String, stateKey: String) -> TelegramCodexRemoteReply {
        guard let selector, let selectedIndex = Int(selector), selectedIndex > 0 else {
            return .init(status: "codex_blocked", text: "Choose Track from `/list` or pass `/track <number>`.")
        }
        do {
            let mode = sessionState(for: stateKey).projectListMode
            let groups = try projectGroups(source: source, stateKey: stateKey, mode: mode)
            guard selectedIndex <= groups.count else {
                return .init(status: "codex_failed", text: "Project not found. Use `/list` to refresh projects.")
            }
            let project = groups[selectedIndex - 1].project
            var state = loadTrackingState()
            var projects = state.trackedProjectsByChat[stateKey] ?? [:]
            projects[project.key] = TrackedProject(
                key: project.key,
                name: project.name,
                cwd: project.cwd,
                trackedAt: ISO8601DateFormatter().string(from: Date())
            )
            state.trackedProjectsByChat[stateKey] = projects
            try saveTrackingState(state)
            return .init(status: "codex_success", text: "Tracking project: \(project.name)")
        } catch {
            return .init(status: "codex_failed", text: "Track project failed: \(error.localizedDescription)")
        }
    }

    private func untrackProjectReply(selector: String?, source: String, stateKey: String) -> TelegramCodexRemoteReply {
        guard let selector, let selectedIndex = Int(selector), selectedIndex > 0 else {
            return .init(status: "codex_blocked", text: "Choose Untrack from `/list` or pass `/untrack <number>`.")
        }
        do {
            let mode = sessionState(for: stateKey).projectListMode
            let groups = try projectGroups(source: source, stateKey: stateKey, mode: mode)
            guard selectedIndex <= groups.count else {
                return .init(status: "codex_failed", text: "Project not found. Use `/list` to refresh projects.")
            }
            let project = groups[selectedIndex - 1].project
            var state = loadTrackingState()
            var projects = state.trackedProjectsByChat[stateKey] ?? [:]
            projects.removeValue(forKey: project.key)
            state.trackedProjectsByChat[stateKey] = projects
            try saveTrackingState(state)
            return .init(status: "codex_success", text: "Stopped tracking project: \(project.name)")
        } catch {
            return .init(status: "codex_failed", text: "Untrack project failed: \(error.localizedDescription)")
        }
    }

    private func latestThreadReply(
        selector: String?,
        source: String,
        opened: Bool,
        stateKey: String
    ) -> TelegramCodexRemoteReply {
        guard source == "file_scan" else {
            return .init(
                status: "codex_failed",
                text: "Codex latest failed: Codex app-server thread reading is not configured for Telegram Bridge."
            )
        }
        guard let selector = selector?.nilIfEmpty ?? sessionState(for: stateKey).selectedThreadID else {
            return .init(status: "codex_blocked", text: "No session selected. Use `/list`, choose a project, then Open a thread.")
        }
        do {
            guard let thread = try resolveFileScanThread(selector: selector, stateKey: stateKey) else {
                return .init(status: "codex_failed", text: "Session not found: \(selector)")
            }
            updateSessionState(stateKey) { state in
                state.selectThread(thread.id)
            }
            let latest = readLatestCodexReply(fileURL: URL(fileURLWithPath: thread.filePath))
            let header = opened ? "Opened: \(thread.title)" : "Latest: \(thread.title)"
            let meta = [
                thread.cwd?.nilIfEmpty,
                thread.updatedAt.flatMap { GeeAgentTimeFormatting.conversationTimestampLabel($0).nilIfEmpty },
                thread.id
            ].compactMap(\.self).joined(separator: "\n")
            let body = latest?.nilIfEmpty ?? "No Codex reply found yet."
            return .init(
                status: "codex_success",
                text: [header, meta.nilIfEmpty, body].compactMap(\.self).joined(separator: "\n\n"),
                replyMarkup: TelegramBridgeReplyMarkup(
                    inlineKeyboard: [
                        [
                            TelegramBridgeInlineKeyboardButton(text: "Refresh", callbackData: "latest:\(thread.id)"),
                            TelegramBridgeInlineKeyboardButton(text: "Send here", callbackData: "open:\(thread.id)")
                        ],
                        [
                            TelegramBridgeInlineKeyboardButton(text: "Desktop", callbackData: "desktop:\(thread.id)")
                        ]
                    ]
                )
            )
        } catch {
            return .init(status: "codex_failed", text: "Codex latest failed: \(error.localizedDescription)")
        }
    }

    private func stagePromptReply(
        sessionID: String,
        prompt: String,
        source: String,
        stateKey: String
    ) -> TelegramCodexRemoteReply {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return .init(status: "codex_blocked", text: "Usage: `/send your instruction`")
        }
        do {
            let thread = try resolveFileScanThread(selector: sessionID, stateKey: stateKey)
            let title = thread?.title ?? "session \(truncateOneLine(sessionID, limit: 12))"
            let meta = thread.map(shortThreadMeta) ?? "Session: \(sessionID)"
            updateSessionState(stateKey) { state in
                state.stagePrompt(sessionID: sessionID, prompt: trimmedPrompt)
            }
            return .init(
                status: "codex_confirmation_required",
                text: "Confirm sending to \(title):\n\(meta)\n\n\(trimmedPrompt)",
                replyMarkup: TelegramBridgeReplyMarkup(
                    inlineKeyboard: [
                        [
                            TelegramBridgeInlineKeyboardButton(text: "Send", callbackData: "confirm:\(sessionID)"),
                            TelegramBridgeInlineKeyboardButton(text: "Cancel", callbackData: "cancel:pending")
                        ]
                    ]
                )
            )
        } catch {
            return .init(status: "codex_failed", text: "Codex prompt staging failed: \(error.localizedDescription)")
        }
    }

    private func sendPromptRouteReply(
        arguments: String?,
        source: String,
        mode: String,
        stateKey: String
    ) async -> TelegramCodexRemoteReply {
        guard let arguments = arguments?.trimmingCharacters(in: .whitespacesAndNewlines),
              !arguments.isEmpty
        else {
            return .init(status: "codex_blocked", text: "Select a thread first or use `/send <session_id> <text>`.\n\n\(codexUsageText())")
        }

        let decision = TelegramCodexRemoteSendPlanner.decision(
            arguments: arguments,
            selectedSessionID: sessionState(for: stateKey).selectedThreadID
        ) { candidate in
            shouldTreatSendArgumentAsSessionID(candidate, source: source, stateKey: stateKey)
        }
        switch decision {
        case .sendExplicit(let sessionID, let prompt):
            return await sendPromptReply(mode: mode, sessionID: sessionID, prompt: prompt)
        case .stageSelected(let sessionID, let prompt):
            return stagePromptReply(
                sessionID: sessionID,
                prompt: prompt,
                source: source,
                stateKey: stateKey
            )
        case .blocked:
            return .init(status: "codex_blocked", text: "Select a thread first or use `/send <session_id> <text>`.\n\n\(codexUsageText())")
        }
    }

    private func shouldTreatSendArgumentAsSessionID(
        _ value: String,
        source: String,
        stateKey: String
    ) -> Bool {
        guard source == "file_scan" else {
            return false
        }
        return (try? resolveFileScanThread(selector: value, stateKey: stateKey)) != nil
    }

    private func confirmPromptReply(selector: String?, mode: String, stateKey: String) async -> TelegramCodexRemoteReply {
        var state = sessionState(for: stateKey)
        guard let pending = state.popPendingPrompt(matching: selector) else {
            return .init(status: "codex_blocked", text: "No matching pending prompt.")
        }
        sessionStatesByChat[stateKey] = state
        return await sendPromptReply(mode: mode, sessionID: pending.sessionID, prompt: pending.prompt)
    }

    private func resolveFileScanThread(selector: String, stateKey: String? = nil) throws -> Thread? {
        let threads = try listFileScanThreads(limit: 1000)
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = Int(trimmed), index > 0 {
            if let stateKey {
                let threadIDs = sessionState(for: stateKey).lastThreadIDs
                guard !threadIDs.isEmpty else {
                    if index <= threads.count {
                        return threads[index - 1]
                    }
                    return nil
                }
                guard index <= threadIDs.count else {
                    return nil
                }
                let threadID = threadIDs[index - 1]
                return threads.first { $0.id == threadID }
            }
            if index <= threads.count {
                return threads[index - 1]
            }
        }
        return threads.first { thread in
            thread.id == trimmed || thread.id.hasPrefix(trimmed)
        }
    }

    private func readLatestCodexReply(fileURL: URL) -> String? {
        var latest: String?
        readJSONLTailLines(
            fileURL: fileURL,
            maxBytes: Self.fileScanLatestReplyTailBytes,
            maxLines: Self.fileScanLatestReplyLineLimit
        ) { line in
            guard let event = parseJSONLObject(line),
                  let payload = event["payload"] as? [String: Any]
            else {
                return true
            }
            switch event["type"] as? String {
            case "event_msg" where payload["type"] as? String == "agent_message":
                latest = extractTelegramCodexText(fromEventMessage: payload).nilIfEmpty ?? latest
            case "response_item":
                switch (payload["type"] as? String, payload["role"] as? String) {
                case ("message", "assistant"):
                    latest = extractTelegramCodexText(fromContent: payload["content"]).nilIfEmpty ?? latest
                default:
                    break
                }
            default:
                break
            }
            return true
        }
        return latest
    }

    private func sendPromptReply(mode: String, sessionID: String, prompt: String) async -> TelegramCodexRemoteReply {
        guard mode == "cli_resume" else {
            return .init(
                status: "codex_failed",
                text: "Codex send failed: Codex app-server send is not configured for Telegram Bridge."
            )
        }
        let trimmedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSessionID.isEmpty, !trimmedPrompt.isEmpty else {
            return .init(status: "codex_blocked", text: "`/send` requires a session id and prompt.\n\n\(codexUsageText())")
        }
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: codexBinaryURL.path) else {
            return .init(
                status: "codex_failed",
                text: "Codex send failed: Codex CLI was not found at \(codexBinaryURL.path)."
            )
        }

        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("geeagent-telegram-codex-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }
            let promptURL = tempDir.appendingPathComponent("prompt.txt", isDirectory: false)
            let outputURL = tempDir.appendingPathComponent("last-message.txt", isDirectory: false)
            try trimmedPrompt.write(to: promptURL, atomically: true, encoding: .utf8)
            let command = [
                "cat \(shellQuote(promptURL.path))",
                "|",
                "\(shellQuote(codexBinaryURL.path)) exec resume",
                "-o \(shellQuote(outputURL.path))",
                shellQuote(trimmedSessionID),
                "-"
            ].joined(separator: " ")
            let result = await runner.run("/bin/zsh", arguments: ["-lc", command], timeoutSeconds: timeoutSeconds)
            guard result.exitCode == 0 else {
                return .init(
                    status: "codex_failed",
                    text: "Codex send failed: \(truncateOneLine(result.combinedOutput, limit: 1200))"
                )
            }
            let outputText = ((try? String(contentsOf: outputURL, encoding: .utf8)) ?? result.stdout)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !outputText.isEmpty else {
                return .init(status: "codex_empty_result", text: "Codex accepted the prompt.")
            }
            return .init(status: "codex_success", text: "Codex replied:\n\(outputText)")
        } catch {
            return .init(status: "codex_failed", text: "Codex send failed: \(error.localizedDescription)")
        }
    }

    private func listFileScanThreads(limit: Int) throws -> [Thread] {
        let sessionsURL = codexHomeURL.appendingPathComponent("sessions", isDirectory: true)
        let candidateLimit = min(max(limit * 3, 80), Self.fileScanMaximumCandidateCount)
        var files: [(url: URL, modifiedAt: Date)] = []
        for directoryURL in recentSessionDirectories(sessionsURL: sessionsURL) {
            files.append(
                contentsOf: directSessionJSONLFiles(
                    in: directoryURL,
                    limit: min(Self.fileScanMaximumFilesPerDirectory, max(candidateLimit - files.count, 0))
                )
            )
            trimRecentFileCandidates(&files, keeping: candidateLimit)
            if files.count >= candidateLimit {
                break
            }
        }

        var threads: [Thread] = []
        for file in files {
            if let thread = readThread(fileURL: file.url, modifiedAt: file.modifiedAt),
               thread.isCodexDesktopVisible {
                threads.append(thread)
            }
            if threads.count >= limit {
                break
            }
        }
        return threads
    }

    private func recentSessionDirectories(sessionsURL: URL) -> [URL] {
        guard directoryExists(sessionsURL) else {
            return []
        }

        var candidates: [URL] = []
        if !directSessionJSONLFiles(in: sessionsURL, limit: 1).isEmpty {
            candidates.append(sessionsURL)
        }

        for yearURL in childDirectories(in: sessionsURL, limit: 6) {
            if !directSessionJSONLFiles(in: yearURL, limit: 1).isEmpty {
                candidates.append(yearURL)
            }
            for monthURL in childDirectories(in: yearURL, limit: 12) {
                if !directSessionJSONLFiles(in: monthURL, limit: 1).isEmpty {
                    candidates.append(monthURL)
                }
                candidates.append(contentsOf: childDirectories(in: monthURL, limit: 31))
            }
        }

        return Array(
            candidates
                .sorted { sessionDirectorySortKey($0, root: sessionsURL) > sessionDirectorySortKey($1, root: sessionsURL) }
                .prefix(Self.fileScanRecentDirectoryLimit)
        )
    }

    private func childDirectories(in directoryURL: URL, limit: Int) -> [URL] {
        guard limit > 0, let directory = opendir(directoryURL.path) else {
            return []
        }
        defer { closedir(directory) }

        var directories: [URL] = []
        var readCount = 0
        let entryReadLimit = max(Self.fileScanMaximumDirectoryEntryReads, limit)
        while directories.count < limit, readCount < entryReadLimit {
            guard let entry = readdir(directory) else {
                break
            }
            readCount += 1
            let name = directoryEntryName(entry)
            guard !name.hasPrefix(".") else {
                continue
            }
            let childURL = directoryURL.appendingPathComponent(name, isDirectory: true)
            var statBuffer = stat()
            let isDirectory = childURL.withUnsafeFileSystemRepresentation { path in
                guard let path else {
                    return false
                }
                return lstat(path, &statBuffer) == 0 &&
                    (statBuffer.st_mode & S_IFMT) == S_IFDIR
            }
            guard isDirectory else {
                continue
            }
            directories.append(childURL)
        }
        return Array(
            directories
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .prefix(limit)
        )
    }

    private func directSessionJSONLFiles(in directoryURL: URL, limit: Int) -> [(url: URL, modifiedAt: Date)] {
        guard limit > 0, let directory = opendir(directoryURL.path) else {
            return []
        }
        defer { closedir(directory) }

        var files: [(url: URL, modifiedAt: Date)] = []
        var readCount = 0
        let entryReadLimit = max(Self.fileScanMaximumDirectoryEntryReads, limit)
        while files.count < limit, readCount < entryReadLimit {
            guard let entry = readdir(directory) else {
                break
            }
            readCount += 1
            let name = directoryEntryName(entry)
            guard !name.hasPrefix("."), name.hasSuffix(".jsonl") else {
                continue
            }
            let fileURL = directoryURL.appendingPathComponent(name, isDirectory: false)
            var statBuffer = stat()
            let isRegularFile = fileURL.withUnsafeFileSystemRepresentation { path in
                guard let path else {
                    return false
                }
                return lstat(path, &statBuffer) == 0 &&
                    (statBuffer.st_mode & S_IFMT) == S_IFREG
            }
            guard isRegularFile else {
                continue
            }
            let modifiedAt = Date(
                timeIntervalSince1970: TimeInterval(statBuffer.st_mtimespec.tv_sec) +
                    TimeInterval(statBuffer.st_mtimespec.tv_nsec) / 1_000_000_000
            )
            files.append((fileURL, modifiedAt))
        }
        trimRecentFileCandidates(&files, keeping: limit)
        return files
    }

    private func directoryExists(_ directoryURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func sessionDirectorySortKey(_ directoryURL: URL, root: URL) -> String {
        let relativePath = directoryURL.path
            .replacingOccurrences(of: root.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relativePath.nilIfEmpty ?? ""
    }

    private func trimRecentFileCandidates(
        _ files: inout [(url: URL, modifiedAt: Date)],
        keeping limit: Int
    ) {
        files.sort { $0.modifiedAt > $1.modifiedAt }
        guard files.count > limit else { return }
        files.removeLast(files.count - limit)
    }

    private func readThread(fileURL: URL, modifiedAt: Date) -> Thread? {
        var id = ""
        var title = ""
        var cwd = ""
        var firstUserText = ""
        var updatedAt: String? = ISO8601DateFormatter().string(from: modifiedAt)
        var originator = ""
        var agentRole = ""
        var agentNickname = ""
        var sourceSubagent = false
        var scannedLines = 0
        readJSONLLines(fileURL: fileURL, maxLines: Self.fileScanThreadReadLineLimit) { line in
            scannedLines += 1
            guard let event = parseJSONLObject(line) else {
                return true
            }
            if let timestamp = event["timestamp"] as? String {
                updatedAt = timestamp
            }
            guard let payload = event["payload"] as? [String: Any] else {
                return true
            }
            switch event["type"] as? String {
            case "session_meta":
                id = (payload["id"] as? String)?.nilIfEmpty ?? id
                cwd = (payload["cwd"] as? String)?.nilIfEmpty ?? cwd
                originator = (payload["originator"] as? String)?.nilIfEmpty ?? originator
                agentRole = (payload["agent_role"] as? String)?.nilIfEmpty ?? agentRole
                agentNickname = (payload["agent_nickname"] as? String)?.nilIfEmpty ?? agentNickname
                if let source = payload["source"] as? [String: Any],
                   source["subagent"] as? Bool == true {
                    sourceSubagent = true
                }
            case "event_msg":
                switch payload["type"] as? String {
                case "thread_name_updated":
                    title = (payload["thread_name"] as? String)?.nilIfEmpty ?? title
                case "user_message" where title.isEmpty:
                    firstUserText = extractTelegramCodexText(fromEventMessage: payload).nilIfEmpty ?? firstUserText
                default:
                    break
                }
            case "response_item":
                switch (payload["type"] as? String, payload["role"] as? String) {
                case ("message", "user") where title.isEmpty && firstUserText.isEmpty:
                    firstUserText = extractTelegramCodexText(fromContent: payload["content"]).nilIfEmpty ?? firstUserText
                default:
                    break
                }
            default:
                break
            }
            if !id.isEmpty, !title.isEmpty || !firstUserText.isEmpty || scannedLines >= 200 {
                return false
            }
            return true
        }
        guard !id.isEmpty else {
            return nil
        }
        return Thread(
            id: id,
            title: truncateOneLine(
                title.nilIfEmpty ?? firstUserText.nilIfEmpty ?? fileURL.deletingPathExtension().lastPathComponent,
                limit: 80
            ),
            cwd: cwd.nilIfEmpty,
            updatedAt: updatedAt,
            filePath: fileURL.path,
            originator: originator.nilIfEmpty,
            agentRole: agentRole.nilIfEmpty,
            agentNickname: agentNickname.nilIfEmpty,
            sourceSubagent: sourceSubagent
        )
    }

    private func projectGroups(
        source: String,
        stateKey: String,
        mode: TelegramCodexRemoteProjectListMode
    ) throws -> [ProjectGroup] {
        guard source == "file_scan" else {
            throw TelegramBridgeGearError.configInvalid("Codex app-server thread listing is not configured for Telegram Bridge.")
        }
        let groups = groupThreadsByProject(try listFileScanThreads(limit: 100))
        guard mode == .tracked else {
            return groups
        }

        let trackedProjects = trackedProjects(stateKey: stateKey)
        guard !trackedProjects.isEmpty else {
            return []
        }
        let trackedKeys = Set(trackedProjects.map(\.key))
        var trackedGroups = groups.filter { trackedKeys.contains($0.project.key) }
        let presentKeys = Set(trackedGroups.map(\.project.key))
        for tracked in trackedProjects where !presentKeys.contains(tracked.key) {
            trackedGroups.append(ProjectGroup(project: tracked.project, items: []))
        }
        return trackedGroups
    }

    private func groupThreadsByProject(_ threads: [Thread]) -> [ProjectGroup] {
        var groups: [ProjectGroup] = []
        var indexesByProjectKey: [String: Int] = [:]
        for thread in threads {
            let project = projectFromCwd(thread.cwd)
            if let index = indexesByProjectKey[project.key] {
                groups[index].items.append(thread)
            } else {
                indexesByProjectKey[project.key] = groups.count
                groups.append(ProjectGroup(project: project, items: [thread]))
            }
        }
        return groups
    }

    private func loadTrackingState() -> TrackingState {
        guard fileManager.fileExists(atPath: trackingStateURL.path),
              let data = try? Data(contentsOf: trackingStateURL),
              let state = try? JSONDecoder().decode(TrackingState.self, from: data)
        else {
            return TrackingState()
        }
        return state
    }

    private func saveTrackingState(_ state: TrackingState) throws {
        try fileManager.createDirectory(at: trackingStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: trackingStateURL, options: .atomic)
    }

    private func trackedProjects(stateKey: String) -> [TrackedProject] {
        Array((loadTrackingState().trackedProjectsByChat[stateKey] ?? [:]).values)
            .sorted { left, right in
                if left.trackedAt == right.trackedAt {
                    return left.name < right.name
                }
                return left.trackedAt < right.trackedAt
            }
    }

    private func trackedProjectKeys(stateKey: String) -> Set<String> {
        Set((loadTrackingState().trackedProjectsByChat[stateKey] ?? [:]).keys)
    }

    private func projectFromCwd(_ cwd: String?) -> Project {
        let trimmed = cwd?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""
        guard !trimmed.isEmpty else {
            return Self.globalProject
        }
        let normalized = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory) else {
            return Self.globalProject
        }
        let startingDirectory = isDirectory.boolValue ? normalized : normalized.deletingLastPathComponent()
        guard let root = findProjectRoot(startingDirectory) else {
            return Self.globalProject
        }
        return Project(key: root.path, name: root.lastPathComponent.nilIfEmpty ?? "Project", cwd: root.path)
    }

    private func findProjectRoot(_ directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            for marker in Self.projectMarkerNames {
                if FileManager.default.fileExists(atPath: current.appendingPathComponent(marker).path) {
                    return current
                }
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private func threadListHeading(_ group: ProjectGroup, pageData: PageData<Thread>) -> String {
        let heading = pageData.pageCount > 1
            ? "Threads in \(group.project.name) (page \(pageData.page) of \(pageData.pageCount))"
            : "Threads in \(group.project.name)"
        let lines: [String?] = [
            heading,
            group.project.cwd.isEmpty ? nil : "Path: \(group.project.cwd)"
        ]
        return lines.compactMap(\.self).joined(separator: "\n")
    }

    private func formatThreadLine(_ thread: Thread, index: Int) -> String {
        let meta = [
            thread.id,
            thread.updatedAt.flatMap { GeeAgentTimeFormatting.conversationTimestampLabel($0).nilIfEmpty }
        ].compactMap(\.self).joined(separator: " | ")
        return "  \(index). \(thread.title)\(meta.isEmpty ? "" : "\n     \(meta)")"
    }

    private func buttonTitle(_ value: String) -> String {
        truncateOneLine(value, limit: 28)
    }

    private func chatStateKey(account: TelegramBridgeAccountConfig, chatID: String?) -> String {
        "\(account.id):\(chatID?.nilIfEmpty ?? "default")"
    }

    private func paginate<Item: Sendable>(_ items: [Item], requestedPage: Int, pageSize: Int) -> PageData<Item> {
        let pageCount = max(1, Int(ceil(Double(items.count) / Double(pageSize))))
        let page = min(max(requestedPage, 1), pageCount)
        let start = (page - 1) * pageSize
        let end = min(start + pageSize, items.count)
        let pageItems = start < end ? Array(items[start..<end]) : []
        return PageData(items: pageItems, page: page, pageCount: pageCount, start: start)
    }

    private func navigationRow<Item>(prefix: String, pageData: PageData<Item>) -> [[TelegramBridgeInlineKeyboardButton]] {
        var row: [TelegramBridgeInlineKeyboardButton] = []
        if pageData.page > 1 {
            row.append(TelegramBridgeInlineKeyboardButton(text: "Prev", callbackData: "\(prefix):\(pageData.page - 1)"))
        }
        if pageData.page < pageData.pageCount {
            row.append(TelegramBridgeInlineKeyboardButton(text: "Next", callbackData: "\(prefix):\(pageData.page + 1)"))
        }
        return row.isEmpty ? [] : [row]
    }

    private func shortThreadMeta(_ thread: Thread) -> String {
        [
            thread.updatedAt.flatMap { "Updated: \(GeeAgentTimeFormatting.conversationTimestampLabel($0))" },
            thread.cwd.flatMap { "Project: \($0)" },
            "Session: \(truncateOneLine(thread.id, limit: 12))"
        ].compactMap(\.self).joined(separator: " | ")
    }

    private func codexUsageText() -> String {
        "Use `/list` to show projects, pick a project, then use Open/Latest/Desktop buttons. You can also use `/latest <session_id>` or `/send <session_id> <prompt>`."
    }

    private func codexHelpText() -> String {
        [
            "Codex Telegram Remote",
            "",
            "/list - show projects with recent Codex Desktop sessions",
            "/recent - same as /list",
            "/open <session_id> - select a thread",
            "/latest [session_id] - show the latest Codex reply",
            "/send <text> - send an instruction to the selected session",
            "/send <session_id> <text> - send directly to a session",
            "/desktop [session_id] - open a thread in Codex Desktop on this Mac",
            "/cancel - clear the selected Codex Remote thread",
            "",
            "Only Codex Desktop sessions visible in the Codex app are listed; subagent/internal sessions are hidden."
        ].joined(separator: "\n")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

struct FlexibleID: Decodable, Hashable, Sendable {
    var value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else {
            value = ""
        }
    }
}

private func channelSummaries(_ channels: [TelegramBridgePushChannelConfig]) -> [[String: Any]] {
    channels.map { channel in
        var payload: [String: Any] = [
            "id": channel.id,
            "accountId": channel.accountId,
            "enabled": channel.enabled,
            "target": redactedTarget(channel.target)
        ]
        if let title = channel.title {
            payload["title"] = title
        }
        return payload
    }
}

private func redactedTarget(_ target: TelegramBridgePushTargetConfig) -> [String: Any] {
    [
        "kind": target.kind,
        "redacted": redactIdentifier(target.value)
    ]
}

private func redactIdentifier(_ value: String) -> String {
    if value.count <= 4 {
        return "****"
    }
    let prefixCount = value.hasPrefix("@") ? 4 : 3
    return "\(value.prefix(prefixCount))***\(value.suffix(3))"
}

private func normalizedParseMode(_ parseMode: String?) -> String? {
    guard let parseMode, parseMode != "plain" else {
        return nil
    }
    return ["Markdown", "MarkdownV2", "HTML"].contains(parseMode) ? parseMode : nil
}

private func sanitizeSensitiveText(_ text: String, token: String) -> String {
    text.replacingOccurrences(of: token, with: "[redacted-token]")
}

private func normalizedTelegramReply(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "No reply content was produced." : trimmed
}

private func formatSeconds(_ seconds: TimeInterval) -> String {
    seconds.rounded() == seconds ? "\(Int(seconds))" : String(format: "%.2f", seconds)
}

func splitTelegramMessage(_ text: String, maxLength: Int = 3900) -> [String] {
    let trimmed = normalizedTelegramReply(text)
    guard maxLength > 0, trimmed.count > maxLength else {
        return [trimmed]
    }

    var chunks: [String] = []
    var rest = trimmed
    while rest.count > maxLength {
        let maxIndex = rest.index(rest.startIndex, offsetBy: maxLength)
        let prefix = String(rest[..<maxIndex])
        var splitDistance = maxLength
        if let paragraphRange = prefix.range(of: "\n\n", options: .backwards) {
            let distance = prefix.distance(from: prefix.startIndex, to: paragraphRange.lowerBound)
            if distance >= maxLength / 2 {
                splitDistance = distance
            }
        }
        if splitDistance == maxLength,
           let lineRange = prefix.range(of: "\n", options: .backwards) {
            let distance = prefix.distance(from: prefix.startIndex, to: lineRange.lowerBound)
            if distance >= maxLength / 2 {
                splitDistance = distance
            }
        }
        let splitIndex = rest.index(rest.startIndex, offsetBy: splitDistance)
        let chunk = String(rest[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !chunk.isEmpty {
            chunks.append(chunk)
        }
        rest = String(rest[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if !rest.isEmpty {
        chunks.append(rest)
    }
    return chunks.isEmpty ? ["No reply content was produced."] : chunks
}

private func isTelegramNewConversationCommand(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .range(
            of: #"^/new(?:@[A-Za-z0-9_]{1,64})?(?:\s|$)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
}

private func truncateOneLine(_ value: String, limit: Int) -> String {
    let singleLine = value
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard singleLine.count > limit else {
        return singleLine
    }
    return "\(singleLine.prefix(max(limit - 1, 1)))..."
}

private func truncateMiddlePath(_ value: String, limit: Int) -> String {
    let singleLine = value
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard singleLine.count > limit, limit > 8 else {
        return singleLine
    }
    let edgeCount = max((limit - 3) / 2, 1)
    return "\(singleLine.prefix(edgeCount))...\(singleLine.suffix(edgeCount))"
}

private func directoryEntryName(_ entry: UnsafeMutablePointer<dirent>) -> String {
    withUnsafePointer(to: &entry.pointee.d_name.0) { namePointer in
        namePointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
            String(cString: $0)
        }
    }
}

private func readJSONLLines(fileURL: URL, maxLines: Int? = nil, _ body: (String) -> Bool) {
    guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
        return
    }
    defer { try? handle.close() }

    var buffer = Data()
    var lineCount = 0
    while true {
        let chunk = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        if chunk.isEmpty {
            _ = readJSONLLineData(buffer, lineCount: &lineCount, maxLines: maxLines, body)
            return
        }
        buffer.append(chunk)
        while let newlineIndex = buffer.firstIndex(of: 0x0a) {
            let lineData = Data(buffer[..<newlineIndex])
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            guard readJSONLLineData(lineData, lineCount: &lineCount, maxLines: maxLines, body) else {
                return
            }
        }
        if buffer.count > 1_000_000 {
            buffer.removeAll(keepingCapacity: true)
        }
    }
}

private func readJSONLTailLines(
    fileURL: URL,
    maxBytes: Int,
    maxLines: Int,
    _ body: (String) -> Bool
) {
    guard maxBytes > 0, maxLines > 0,
          let handle = try? FileHandle(forReadingFrom: fileURL)
    else {
        return
    }
    defer { try? handle.close() }

    let fileSize = (try? handle.seekToEnd()) ?? 0
    guard fileSize > 0 else {
        return
    }
    let readSize = min(UInt64(maxBytes), fileSize)
    let startOffset = fileSize - readSize
    try? handle.seek(toOffset: startOffset)
    let tailData: Data?
    do {
        tailData = try handle.readToEnd()
    } catch {
        return
    }
    guard var data = tailData, !data.isEmpty else {
        return
    }
    if startOffset > 0 {
        guard let newlineIndex = data.firstIndex(of: 0x0a) else {
            return
        }
        data.removeSubrange(data.startIndex...newlineIndex)
    }
    guard let text = String(data: data, encoding: .utf8) else {
        return
    }
    let lines = text
        .split(separator: "\n", omittingEmptySubsequences: true)
        .suffix(maxLines)
    for rawLine in lines {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            continue
        }
        guard body(line) else {
            return
        }
    }
}

private func readJSONLLineData(
    _ lineData: Data,
    lineCount: inout Int,
    maxLines: Int?,
    _ body: (String) -> Bool
) -> Bool {
    guard !lineData.isEmpty,
          lineData.count <= 1_000_000,
          let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !line.isEmpty
    else {
        return true
    }
    lineCount += 1
    if let maxLines, lineCount > maxLines {
        return false
    }
    return body(line)
}

private func parseJSONLObject(_ line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8) else {
        return nil
    }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

private func extractTelegramCodexText(fromEventMessage payload: [String: Any]) -> String {
    if let message = payload["message"] as? String {
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return extractTelegramCodexText(fromContent: payload["content"])
}

private func extractTelegramCodexText(fromContent content: Any?) -> String {
    guard let parts = content as? [[String: Any]] else {
        return ""
    }
    return parts
        .compactMap { $0["text"] as? String }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private extension String {
    var trimmedForGateway: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private func failurePayload(
    status: String,
    code: String,
    message: String,
    capabilityID: String,
    channelID: String? = nil,
    accountID: String? = nil,
    target: TelegramBridgePushTargetConfig? = nil,
    chatID: String? = nil,
    filePath: String? = nil,
    retryAfterMs: Int? = nil
) -> [String: Any] {
    var error: [String: Any] = [
        "code": code,
        "message": message
    ]
    if let retryAfterMs {
        error["retryAfterMs"] = retryAfterMs
    }
    var payload: [String: Any] = [
        "gear_id": TelegramBridgeGearRuntimeConstants.gearID,
        "capability_id": capabilityID,
        "status": status,
        "fallback_attempted": false,
        "error": error
    ]
    if let channelID {
        payload["channelId"] = channelID
    }
    if let accountID {
        payload["accountId"] = accountID
    }
    if let target {
        payload["target"] = redactedTarget(target)
    }
    if let chatID {
        payload["chatId"] = chatID
    }
    if let filePath {
        payload["file"] = [
            "path": filePath
        ]
    }
    return payload
}

private func stringArg(_ args: [String: Any], _ key: String) -> String? {
    guard let value = args[key] as? String else {
        return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func rawStringArg(_ args: [String: Any], _ key: String) -> String? {
    args[key] as? String
}

private func boolArg(_ args: [String: Any], _ key: String) -> Bool? {
    args[key] as? Bool
}
