import Foundation
import Security
import SwiftUI

private enum TelegramBridgeGearRuntimeConstants {
    static let gearID = "telegram.bridge"
}

struct TelegramBridgeAccountConfig: Codable, Hashable {
    struct Transport: Codable, Hashable {
        var mode: String
    }

    struct Push: Codable, Hashable {
        var acceptInbound: Bool?
    }

    var id: String
    var role: String
    var botUsername: String?
    var transport: Transport
    var push: Push?
}

struct TelegramBridgePushTargetConfig: Codable, Hashable {
    var kind: String
    var value: String
}

struct TelegramBridgePushChannelConfig: Codable, Hashable, Identifiable {
    struct Format: Codable, Hashable {
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

struct TelegramBridgeConfigFile: Codable, Hashable {
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

struct TelegramBridgeDeliveryRecord: Codable, Hashable {
    var channelId: String
    var accountId: String
    var telegramMessageId: String
    var sentAt: String
    var idempotencyKey: String
}

struct TelegramBridgeDeliveryLog: Codable {
    var deliveries: [String: TelegramBridgeDeliveryRecord] = [:]
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
final class TelegramBridgeGearStore: ObservableObject {
    static let shared = TelegramBridgeGearStore()

    @Published private(set) var config: TelegramBridgeConfigFile = TelegramBridgeConfigFile()
    @Published private(set) var lastStatusMessage: String = "Ready"

    private let database: TelegramBridgeFileDatabase
    private let tokenStore: TelegramBridgeTokenStore
    private let sender: TelegramBridgeSender

    init(
        database: TelegramBridgeFileDatabase = TelegramBridgeFileDatabase(),
        tokenStore: TelegramBridgeTokenStore = TelegramBridgeTokenStore(),
        sender: TelegramBridgeSender = TelegramBridgeSender()
    ) {
        self.database = database
        self.tokenStore = tokenStore
        self.sender = sender
        loadConfig()
    }

    func loadConfig() {
        do {
            config = try database.loadConfig()
            lastStatusMessage = "Loaded \(config.pushChannels.count) channel(s)."
        } catch {
            config = TelegramBridgeConfigFile()
            lastStatusMessage = error.localizedDescription
        }
    }

    func saveBotToken(accountID: String, token: String) throws {
        try tokenStore.saveToken(token, accountID: accountID)
        lastStatusMessage = "Token saved for \(accountID)."
    }

    func setStatusMessage(_ message: String) {
        lastStatusMessage = message
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
        self.config = config
        return [
            "gear_id": TelegramBridgeGearRuntimeConstants.gearID,
            "capability_id": "telegram_bridge.status",
            "status": "success",
            "fallback_attempted": false,
            "config_path": database.configURL.path,
            "account_count": config.accounts.count,
            "push_channel_count": config.pushChannels.count,
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
                    push: .init(acceptInbound: false)
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
            "token_binding": "Save the bot token in Keychain for account \(accountID); tokens are not stored in config."
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
        guard message.count <= 4096 else {
            return failurePayload(status: "blocked", code: "message_too_large", message: "Telegram text messages must be 4096 characters or fewer.", capabilityID: "telegram_push.send_message", channelID: channelID)
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
            let response = try await sender.sendMessage(
                token: token,
                target: channel.target,
                text: message,
                parseMode: normalizedParseMode(stringArg(args, "parse_mode") ?? stringArg(args, "parseMode") ?? channel.format?.parseMode),
                disableWebPreview: boolArg(args, "disable_web_preview") ?? boolArg(args, "disableWebPreview") ?? channel.format?.disableWebPreview
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
                "sentAt": delivery.sentAt,
                "idempotencyKey": delivery.idempotencyKey,
                "reused": reused
            ],
            "error": NSNull()
        ]
    }
}

struct TelegramBridgeFileDatabase {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    var dataDirectoryURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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

    private func loadDeliveryLog() throws -> TelegramBridgeDeliveryLog {
        guard fileManager.fileExists(atPath: deliveryLogURL.path) else {
            return TelegramBridgeDeliveryLog()
        }
        return try decoder.decode(TelegramBridgeDeliveryLog.self, from: Data(contentsOf: deliveryLogURL))
    }
}

struct TelegramBridgeTokenStore {
    private let service = "GeeAgent/Gear/telegram.bridge"

    func token(accountID: String) throws -> String? {
        var query = baseQuery(accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw TelegramBridgeGearError.tokenUnavailable("Keychain token lookup failed for account `\(accountID)` with status \(status).")
        }
        guard let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let data = Data(trimmed.utf8)
        let query = baseQuery(accountID: accountID)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw TelegramBridgeGearError.tokenUnavailable("Keychain token update failed for account `\(accountID)` with status \(status).")
        }
        var add = query
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw TelegramBridgeGearError.tokenUnavailable("Keychain token save failed for account `\(accountID)` with status \(addStatus).")
        }
    }

    private func baseQuery(accountID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID
        ]
    }
}

struct TelegramBridgeSender {
    enum Result {
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

    func sendMessage(
        token: String,
        target: TelegramBridgePushTargetConfig,
        text: String,
        parseMode: String?,
        disableWebPreview: Bool?
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
}

struct FlexibleID: Decodable, Hashable {
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

private func failurePayload(
    status: String,
    code: String,
    message: String,
    capabilityID: String,
    channelID: String? = nil,
    accountID: String? = nil,
    target: TelegramBridgePushTargetConfig? = nil,
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
