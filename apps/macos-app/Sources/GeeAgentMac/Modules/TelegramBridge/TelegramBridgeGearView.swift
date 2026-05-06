import SwiftUI

struct TelegramBridgeGearModuleView: View {
    var body: some View {
        TelegramBridgeGearWindow()
    }
}

struct TelegramBridgeGearWindow: View {
    @StateObject private var model = TelegramBridgeGearStore.shared

    var body: some View {
        TelegramBridgeRootView(model: model)
            .frame(minWidth: 940, minHeight: 620)
            .task {
                model.loadConfig()
            }
    }
}

private struct TelegramBridgeRootView: View {
    @ObservedObject var model: TelegramBridgeGearStore
    @State private var setupMode = "gee_direct"

    @State private var conversationRole = "gee_direct"
    @State private var conversationAccountID = "gee_direct_default"
    @State private var conversationBotUsername = ""
    @State private var conversationToken = ""
    @State private var conversationAllowUserIDs = ""
    @State private var conversationAllowChatIDs = ""
    @State private var conversationGroupPolicy = "deny"
    @State private var codexThreadSource = "file_scan"
    @State private var codexSendMode = "cli_resume"
    @State private var isFetchingConversationUserID = false

    @State private var pushChannelID = "morning_news"
    @State private var pushAccountID = "news_push"
    @State private var pushTitle = "Morning News"
    @State private var pushBotUsername = ""
    @State private var pushTargetKind = "chat_id"
    @State private var pushTargetValue = ""
    @State private var pushToken = ""
    @State private var isFetchingPushTarget = false
    @State private var testingPushChannelID: String?

    private var conversationAccounts: [TelegramBridgeAccountConfig] {
        model.config.accounts.filter { $0.role != "push_only" }
    }

    private var selectedConversationAccounts: [TelegramBridgeAccountConfig] {
        conversationAccounts.filter { $0.role == setupMode }
    }

    private var pushAccounts: [TelegramBridgeAccountConfig] {
        model.config.accounts.filter { $0.role == "push_only" }
    }

    private var roles: [TelegramBridgeRoleSummary] {
        [
            TelegramBridgeRoleSummary(
                mode: "gee_direct",
                title: "Gee Direct",
                systemImage: "bubble.left.and.bubble.right",
                state: "\(model.config.accounts.filter { $0.role == "gee_direct" }.count) bot",
                detail: "Conversation bot"
            ),
            TelegramBridgeRoleSummary(
                mode: "codex_remote",
                title: "Codex Remote",
                systemImage: "terminal",
                state: "\(model.config.accounts.filter { $0.role == "codex_remote" }.count) bot",
                detail: "Conversation bot"
            ),
            TelegramBridgeRoleSummary(
                mode: "push_only",
                title: "Push Only",
                systemImage: "paperplane",
                state: "\(model.config.pushChannels.count) channel",
                detail: "Outbound only"
            )
        ]
    }

    var body: some View {
        ZStack {
            TelegramBridgePalette.background
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 300)
                Rectangle()
                    .fill(TelegramBridgePalette.border)
                    .frame(width: 1)
                mainPanel
            }
        }
        .foregroundStyle(.white)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Image(systemName: "paperplane.circle")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(TelegramBridgePalette.accent)
                    Text("Telegram Bridge")
                        .font(.system(size: 24, weight: .semibold))
                }
                Text(model.config.accounts.isEmpty ? "Not Configured" : "Configured")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.config.accounts.isEmpty ? .orange : .green)
            }

            VStack(spacing: 9) {
                ForEach(roles) { role in
                    Button {
                        selectSetupMode(role.mode)
                    } label: {
                        TelegramBridgeRoleRow(role: role, isSelected: setupMode == role.mode)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            TelegramBridgeStatusBlock(
                title: "Worker",
                value: "Ready",
                systemImage: "checkmark.seal"
            )
            TelegramBridgeStatusBlock(
                title: "Inbound",
                value: "\(model.config.accounts.filter { $0.role != "push_only" }.count) polling",
                systemImage: "arrow.down.circle"
            )
            TelegramBridgeStatusBlock(
                title: "Config",
                value: model.lastStatusMessage,
                systemImage: "doc.text"
            )
        }
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.18))
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Telegram Bridge")
                        .font(.system(size: 22, weight: .semibold))
                    Text(selectedModeSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.46))
                }
                Spacer()
                Button {
                    model.loadConfig()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(TelegramBridgeIconButtonStyle())
                .help("Refresh")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if setupMode == "gee_direct" || setupMode == "codex_remote" {
                        conversationSetupPanel
                        conversationAccountsPanel
                    } else {
                        pushSetupPanel
                        channelListPanel
                        pushAccountsPanel
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.visible)

        }
        .padding(22)
    }

    private var selectedModeTitle: String {
        switch setupMode {
        case "codex_remote":
            "Codex Remote"
        case "push_only":
            "Push Only"
        default:
            "Gee Direct"
        }
    }

    private var selectedModeSubtitle: String {
        switch setupMode {
        case "codex_remote":
            "\(selectedConversationAccounts.count) Codex Remote bot account(s)"
        case "push_only":
            "\(model.config.pushChannels.count) push channel(s), \(pushAccounts.count) push bot account(s)"
        default:
            "\(selectedConversationAccounts.count) Gee Direct bot account(s)"
        }
    }

    private var conversationSetupPanel: some View {
        TelegramBridgeSectionCard(
            title: selectedModeTitle,
            subtitle: setupMode == "codex_remote" ? "Remote control for Codex desktop sessions." : "Two-way Telegram channel for GeeAgent chat.",
            systemImage: "bubble.left.and.bubble.right"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TelegramBridgeLabeledTextField(
                        title: "Account ID",
                        requirement: "Required",
                        placeholder: "gee_direct_default",
                        help: "Gee internal account ID for this conversation bot. It is used by GeeAgent to find the bot config and local token. It is not a Telegram user ID, chat ID, bot ID, or @username.",
                        text: $conversationAccountID
                    )
                    TelegramBridgeLabeledTextField(title: "Bot Username", requirement: "Optional", placeholder: "my_gee_bot", text: $conversationBotUsername)
                }

                HStack(spacing: 12) {
                    TelegramBridgeLabeledSecureField(title: "Bot Token", requirement: "Required first setup / stored locally", placeholder: "123456:ABC...", text: $conversationToken)
                    TelegramBridgeLabeledPicker(title: "Group Policy", requirement: "Required") {
                        Picker("", selection: $conversationGroupPolicy) {
                            Text("Deny").tag("deny")
                            Text("Mention Required").tag("mention_required")
                            Text("Allow").tag("allow")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TelegramBridgeLabeledTextField(
                            title: "Allowed User IDs",
                            requirement: "Optional",
                            placeholder: "1234, 5678",
                            help: "Telegram sender user IDs allowed to talk to this conversation bot. Leave empty to allow any sender for this bot.",
                            text: $conversationAllowUserIDs
                        )
                        Button {
                            fetchLatestConversationUserID()
                        } label: {
                            Label(isFetchingConversationUserID ? "Fetching..." : "Fetch user ID", systemImage: "person.badge.key")
                                .frame(minWidth: 118)
                        }
                        .buttonStyle(TelegramBridgeSecondaryButtonStyle())
                        .disabled(isFetchingConversationUserID || conversationToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.top, 19)
                    }
                    TelegramBridgeLabeledTextField(
                        title: "Allowed Chat IDs",
                        requirement: "Optional",
                        placeholder: "777, -100...",
                        help: "Telegram chat IDs allowed to use this bot. Direct chats are positive numbers; groups and channels are usually negative. Leave empty to allow any chat that also passes the user ID rule.",
                        text: $conversationAllowChatIDs
                    )
                }

                if setupMode == "codex_remote" {
                    HStack(spacing: 12) {
                        TelegramBridgeLabeledPicker(title: "Codex Send", requirement: "Required") {
                            Picker("", selection: $codexSendMode) {
                                Text("CLI Resume").tag("cli_resume")
                                Text("App Server").tag("app_server")
                            }
                            .pickerStyle(.segmented)
                        }
                        TelegramBridgeLabeledPicker(title: "Thread Source", requirement: "Required") {
                            Picker("", selection: $codexThreadSource) {
                                Text("File Scan").tag("file_scan")
                                Text("App Server").tag("app_server")
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        saveConversationBot()
                    } label: {
                        Label("Save \(selectedModeTitle)", systemImage: "checkmark.circle")
                            .frame(minWidth: 190)
                    }
                    .buttonStyle(TelegramBridgePrimaryButtonStyle())
                    .disabled(conversationAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var pushSetupPanel: some View {
        TelegramBridgeSectionCard(
            title: "Push Channel",
            subtitle: "One-way Telegram delivery. Push channels do not accept Telegram messages and do not use user allowlists.",
            systemImage: "paperplane"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TelegramBridgeLabeledTextField(
                        title: "Channel ID",
                        requirement: "Required",
                        placeholder: "morning_news",
                        help: "Gee internal push channel ID. Codex/Gee uses this ID when sending a push, for example channel_id = morning_news. It is not the Telegram chat ID or channel @username.",
                        text: $pushChannelID
                    )
                    TelegramBridgeLabeledTextField(
                        title: "Account ID",
                        requirement: "Required",
                        placeholder: "news_push",
                        help: "Gee internal bot account ID for the Telegram bot token used by this push channel. Multiple push channels can reuse one Account ID. It is not a Telegram user ID, chat ID, or bot ID.",
                        text: $pushAccountID
                    )
                    TelegramBridgeLabeledTextField(title: "Display Title", requirement: "Optional", placeholder: "Morning News", text: $pushTitle)
                }

                HStack(spacing: 12) {
                    TelegramBridgeLabeledTextField(title: "Bot Username", requirement: "Optional", placeholder: "news_push_bot", text: $pushBotUsername)
                    TelegramBridgeLabeledSecureField(title: "Bot Token", requirement: "Required first setup / stored locally", placeholder: "123456:ABC...", text: $pushToken)
                }

                HStack(spacing: 12) {
                    TelegramBridgeLabeledPicker(
                        title: "Target Type",
                        requirement: "Required",
                        help: "The kind of Telegram destination stored in Target Value."
                    ) {
                        Picker("", selection: $pushTargetKind) {
                            Text("Chat ID").tag("chat_id")
                            Text("Group ID").tag("group_id")
                            Text("Channel ID").tag("channel_id")
                            Text("@Channel").tag("channel_username")
                        }
                        .pickerStyle(.segmented)
                    }
                    TelegramBridgeLabeledTextField(
                        title: "Target Value",
                        requirement: "Required",
                        placeholder: "777 or @channel",
                        help: "Telegram destination value. Use a chat/group/channel numeric ID such as 777 or -100..., or a public channel username such as @my_channel when Target Type is @Channel.",
                        text: $pushTargetValue
                    )
                }

                HStack {
                    Button {
                        fetchLatestPushTarget()
                    } label: {
                        Label(isFetchingPushTarget ? "Fetching..." : "Fetch and fill", systemImage: "arrow.down.doc")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(TelegramBridgeSecondaryButtonStyle())
                    .disabled(isFetchingPushTarget || pushToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                    Button {
                        savePushToken()
                    } label: {
                        Label("Save Push Bot Token", systemImage: "key")
                            .frame(minWidth: 175)
                    }
                    .buttonStyle(TelegramBridgeSecondaryButtonStyle())
                    .disabled(pushAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pushToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        upsertPushChannel()
                    } label: {
                        Label("Save Push Channel", systemImage: "paperplane.circle")
                            .frame(minWidth: 170)
                    }
                    .buttonStyle(TelegramBridgePrimaryButtonStyle())
                    .disabled(pushChannelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pushAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pushTargetValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var channelListPanel: some View {
        TelegramBridgeSectionCard(
            title: "Configured Push Channels",
            subtitle: "\(model.config.pushChannels.count) outbound channels",
            systemImage: "list.bullet.rectangle"
        ) {
            VStack(spacing: 0) {
                if model.config.pushChannels.isEmpty {
                    TelegramBridgeEmptyRow(
                        systemImage: "paperplane",
                        title: "No push channels",
                        detail: "Saved push channels will appear here."
                    )
                } else {
                    ForEach(model.config.pushChannels) { channel in
                        TelegramBridgeChannelRow(
                            channel: channel,
                            tokenStatus: model.tokenStatus(accountID: channel.accountId),
                            isTesting: testingPushChannelID == channel.id,
                            onTest: { testPushChannel(channel) },
                            onEdit: { editPushChannel(channel) },
                            onDelete: { deletePushChannel(channel) }
                        )
                        if channel.id != model.config.pushChannels.last?.id {
                            Rectangle()
                                .fill(TelegramBridgePalette.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var conversationAccountsPanel: some View {
        TelegramBridgeSectionCard(
            title: "Configured \(selectedModeTitle) Bots",
            subtitle: "\(selectedConversationAccounts.count) account(s)",
            systemImage: "person.crop.circle.badge.checkmark"
        ) {
            VStack(spacing: 0) {
                if selectedConversationAccounts.isEmpty {
                    TelegramBridgeEmptyRow(
                        systemImage: "bubble.left.and.bubble.right",
                        title: "No \(selectedModeTitle) bots",
                        detail: "Saved \(selectedModeTitle) bot accounts will appear here."
                    )
                } else {
                    ForEach(selectedConversationAccounts, id: \.id) { account in
                        TelegramBridgeAccountRow(
                            account: account,
                            tokenStatus: model.tokenStatus(accountID: account.id),
                            onEdit: { editConversationAccount(account) },
                            onClearToken: { deleteBotToken(account.id) },
                            onDelete: { deleteConversationBot(account) }
                        )
                        if account.id != selectedConversationAccounts.last?.id {
                            Rectangle()
                                .fill(TelegramBridgePalette.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var pushAccountsPanel: some View {
        TelegramBridgeSectionCard(
            title: "Push Bot Accounts",
            subtitle: "\(pushAccounts.count) local outbound bot account(s)",
            systemImage: "key"
        ) {
            VStack(spacing: 0) {
                if pushAccounts.isEmpty {
                    TelegramBridgeEmptyRow(
                        systemImage: "key",
                        title: "No push bot accounts",
                        detail: "Push bot accounts are created when you save a push channel."
                    )
                } else {
                    ForEach(pushAccounts, id: \.id) { account in
                        TelegramBridgePushAccountRow(
                            account: account,
                            tokenStatus: model.tokenStatus(accountID: account.id),
                            channelCount: model.config.pushChannels.filter { $0.accountId == account.id }.count,
                            onEdit: { editPushAccount(account) },
                            onClearToken: { deleteBotToken(account.id) },
                            onDelete: { deletePushAccount(account) }
                        )
                        if account.id != pushAccounts.last?.id {
                            Rectangle()
                                .fill(TelegramBridgePalette.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func saveConversationBot() {
        do {
            try model.upsertConversationBot(
                role: setupMode == "codex_remote" ? "codex_remote" : "gee_direct",
                accountID: conversationAccountID,
                botUsername: conversationBotUsername,
                allowUserIds: splitIDs(conversationAllowUserIDs),
                allowChatIds: splitIDs(conversationAllowChatIDs),
                groupPolicy: conversationGroupPolicy,
                codexThreadSource: setupMode == "codex_remote" ? codexThreadSource : nil,
                codexSendMode: setupMode == "codex_remote" ? codexSendMode : nil,
                token: conversationToken
            )
            conversationToken = ""
            model.loadConfig()
        } catch {
            model.setStatusMessage(error.localizedDescription)
        }
    }

    private func savePushToken() {
        do {
            try model.saveBotToken(accountID: pushAccountID, token: pushToken)
            pushToken = ""
            model.loadConfig()
        } catch {
            model.setStatusMessage(error.localizedDescription)
        }
    }

    private func upsertPushChannel() {
        Task {
            do {
                if !pushToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try model.saveBotToken(accountID: pushAccountID, token: pushToken)
                    pushToken = ""
                }
            } catch {
                model.setStatusMessage(error.localizedDescription)
                return
            }
            _ = await model.runAgentAction(
                capabilityID: "telegram_push.upsert_channel",
                args: [
                    "channel_id": pushChannelID,
                    "account_id": pushAccountID,
                    "title": pushTitle,
                    "bot_username": pushBotUsername,
                    "target_kind": pushTargetKind,
                    "target_value": pushTargetValue
                ]
            )
            model.loadConfig()
        }
    }

    private func fetchLatestPushTarget() {
        let token = pushToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            model.setStatusMessage("Bot Token is required before fetching a Telegram chat ID.")
            return
        }
        isFetchingPushTarget = true
        Task {
            do {
                let chatID = try await model.latestChatID(token: token)
                pushTargetValue = chatID
                if chatID.hasPrefix("-") {
                    pushTargetKind = "group_id"
                } else {
                    pushTargetKind = "chat_id"
                }
                model.setStatusMessage("Filled Target Value with latest Telegram chat ID \(chatID).")
            } catch {
                model.setStatusMessage(error.localizedDescription)
            }
            isFetchingPushTarget = false
        }
    }

    private func fetchLatestConversationUserID() {
        let token = conversationToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            model.setStatusMessage("Bot Token is required before fetching a Telegram user ID.")
            return
        }
        isFetchingConversationUserID = true
        Task {
            do {
                let userID = try await model.latestUserID(token: token, accountID: conversationAccountID)
                conversationAllowUserIDs = mergedIDListValue(conversationAllowUserIDs, userID)
                model.setStatusMessage("Filled Allowed User IDs with latest Telegram sender user ID \(userID).")
            } catch {
                model.setStatusMessage(error.localizedDescription)
            }
            isFetchingConversationUserID = false
        }
    }

    private func testPushChannel(_ channel: TelegramBridgePushChannelConfig) {
        guard testingPushChannelID == nil else {
            return
        }
        testingPushChannelID = channel.id
        model.setStatusMessage("Sending test message to \(channel.id)...")
        Task {
            let result = await model.runAgentAction(
                capabilityID: "telegram_push.send_message",
                args: [
                    "channel_id": channel.id,
                    "message": "GeeAgent Telegram Bridge test message for push channel `\(channel.id)`.",
                    "idempotency_key": "manual-test-\(channel.id)-\(UUID().uuidString)",
                    "disable_web_preview": true
                ]
            )
            let status = result["status"] as? String
            if status == "success" {
                model.setStatusMessage("Test message sent through push channel \(channel.id).")
            } else {
                let code = result["code"] as? String ?? status ?? "failed"
                let message = result["message"] as? String ?? "Test message could not be sent."
                model.setStatusMessage("Test failed for \(channel.id): \(code) - \(message)")
            }
            testingPushChannelID = nil
        }
    }

    private func selectSetupMode(_ mode: String) {
        setupMode = mode
        guard mode == "gee_direct" || mode == "codex_remote" else {
            return
        }
        conversationRole = mode
        if conversationAccountID.isEmpty ||
            conversationAccountID == "gee_direct_default" ||
            conversationAccountID == "codex_remote_default" {
            conversationAccountID = mode == "gee_direct" ? "gee_direct_default" : "codex_remote_default"
        }
    }

    private func editConversationAccount(_ account: TelegramBridgeAccountConfig) {
        setupMode = account.role
        conversationRole = account.role
        conversationAccountID = account.id
        conversationBotUsername = account.botUsername ?? ""
        conversationAllowUserIDs = (account.security?.allowUserIds ?? []).joined(separator: ", ")
        conversationAllowChatIDs = (account.security?.allowChatIds ?? []).joined(separator: ", ")
        conversationGroupPolicy = account.security?.groupPolicy ?? "deny"
        codexThreadSource = account.codex?.threadSource ?? "file_scan"
        codexSendMode = account.codex?.sendMode ?? "cli_resume"
        conversationToken = ""
        model.setStatusMessage("Loaded \(account.id). Paste a new token only if you want to replace the local token.")
    }

    private func editPushChannel(_ channel: TelegramBridgePushChannelConfig) {
        setupMode = "push_only"
        pushChannelID = channel.id
        pushAccountID = channel.accountId
        pushTitle = channel.title ?? ""
        pushTargetKind = channel.target.kind
        pushTargetValue = channel.target.value
        pushToken = ""
        if let account = pushAccounts.first(where: { $0.id == channel.accountId }) {
            pushBotUsername = account.botUsername ?? ""
        }
        model.setStatusMessage("Loaded push channel \(channel.id). Paste a token only if you want to replace it.")
    }

    private func editPushAccount(_ account: TelegramBridgeAccountConfig) {
        setupMode = "push_only"
        pushAccountID = account.id
        pushBotUsername = account.botUsername ?? ""
        pushToken = ""
        model.setStatusMessage("Loaded push account \(account.id). Delete its channels before deleting the account.")
    }

    private func deleteBotToken(_ accountID: String) {
        do {
            try model.deleteBotToken(accountID: accountID)
            model.loadConfig()
        } catch {
            model.setStatusMessage(error.localizedDescription)
        }
    }

    private func deleteConversationBot(_ account: TelegramBridgeAccountConfig) {
        do {
            try model.deleteConversationBot(accountID: account.id)
            if conversationAccountID == account.id {
                conversationAccountID = setupMode == "codex_remote" ? "codex_remote_default" : "gee_direct_default"
                conversationBotUsername = ""
                conversationToken = ""
                conversationAllowUserIDs = ""
                conversationAllowChatIDs = ""
                conversationGroupPolicy = "deny"
            }
            model.loadConfig()
        } catch {
            model.setStatusMessage(error.localizedDescription)
        }
    }

    private func deletePushChannel(_ channel: TelegramBridgePushChannelConfig) {
        do {
            try model.deletePushChannel(channelID: channel.id)
            if pushChannelID == channel.id {
                pushChannelID = "morning_news"
                pushTitle = "Morning News"
                pushTargetValue = ""
            }
            model.loadConfig()
        } catch {
            model.setStatusMessage(error.localizedDescription)
        }
    }

    private func deletePushAccount(_ account: TelegramBridgeAccountConfig) {
        do {
            try model.deletePushAccount(accountID: account.id)
            if pushAccountID == account.id {
                pushAccountID = "news_push"
                pushBotUsername = ""
                pushToken = ""
            }
            model.loadConfig()
        } catch {
            model.setStatusMessage(error.localizedDescription)
        }
    }

    private func splitIDs(_ value: String) -> [String] {
        value
            .split { character in
                character == "," || character == " " || character == "\n" || character == "\t"
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func mergedIDListValue(_ current: String, _ newID: String) -> String {
        let existing = splitIDs(current)
        guard !existing.contains(newID) else {
            return current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? newID : current
        }
        guard !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return newID
        }
        return "\(current), \(newID)"
    }
}

private struct TelegramBridgeRoleSummary: Identifiable {
    let id = UUID()
    var mode: String
    var title: String
    var systemImage: String
    var state: String
    var detail: String
}

private struct TelegramBridgeRoleRow: View {
    var role: TelegramBridgeRoleSummary
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: role.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : TelegramBridgePalette.accent)
                .frame(width: 24, height: 24)
                .background(isSelected ? TelegramBridgePalette.accent.opacity(0.72) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(role.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(role.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer()
            Text(role.state)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(10)
        .background(isSelected ? TelegramBridgePalette.accent.opacity(0.18) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? TelegramBridgePalette.accent.opacity(0.44) : Color.clear, lineWidth: 0.9)
        }
    }
}

private struct TelegramBridgeStatusBlock: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
            }
            Spacer()
        }
    }
}

private struct TelegramBridgeMetric: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TelegramBridgePalette.accent)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TelegramBridgePalette.border, lineWidth: 0.8)
        }
    }
}

private struct TelegramBridgeTextField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TelegramBridgePalette.border, lineWidth: 0.8)
            }
    }
}

private struct TelegramBridgeSectionCard<Content: View>: View {
    var title: String
    var subtitle: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TelegramBridgePalette.accent)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
            }
            content
        }
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(TelegramBridgePalette.border, lineWidth: 0.8)
        }
    }
}

private struct TelegramBridgeLabeledTextField: View {
    var title: String
    var requirement: String
    var placeholder: String
    var help: String? = nil
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TelegramBridgeFieldLabel(title: title, requirement: requirement, help: help)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TelegramBridgePalette.border, lineWidth: 0.8)
                }
                .help(help ?? "")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help ?? "")
    }
}

private struct TelegramBridgeLabeledSecureField: View {
    var title: String
    var requirement: String
    var placeholder: String
    var help: String? = nil
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TelegramBridgeFieldLabel(title: title, requirement: requirement, help: help)
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TelegramBridgePalette.border, lineWidth: 0.8)
                }
                .help(help ?? "")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help ?? "")
    }
}

private struct TelegramBridgeLabeledPicker<Content: View>: View {
    var title: String
    var requirement: String
    var help: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TelegramBridgeFieldLabel(title: title, requirement: requirement, help: help)
            content
                .frame(height: 34)
                .help(help ?? "")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help ?? "")
    }
}

private struct TelegramBridgeFieldLabel: View {
    var title: String
    var requirement: String
    var help: String?

    var body: some View {
        let isRequired = requirement.hasPrefix("Required")
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
            if let help {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.46))
                    .help(help)
            }
            Text(requirement)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isRequired ? Color.orange : .white.opacity(0.42))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (isRequired ? Color.orange.opacity(0.12) : Color.white.opacity(0.045)),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
            Spacer(minLength: 0)
        }
    }
}

private struct TelegramBridgeEmptyRow: View {
    var systemImage: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.34))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
        }
        .padding(14)
    }
}

private struct TelegramBridgeChannelRow: View {
    var channel: TelegramBridgePushChannelConfig
    var tokenStatus: (configured: Bool, status: String, error: String?)
    var isTesting: Bool
    var onTest: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: channel.enabled ? "paperplane.fill" : "paperplane")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(channel.enabled ? TelegramBridgePalette.accent : .white.opacity(0.35))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.title ?? channel.id)
                    .font(.system(size: 13, weight: .semibold))
                Text(channel.accountId)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            TelegramBridgeTokenStatusBadge(status: tokenStatus)
            Text(channel.target.kind)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            TelegramBridgeRowActionButton(
                title: isTesting ? "Testing" : "Test",
                systemImage: isTesting ? "hourglass" : "paperplane.circle",
                isDisabled: isTesting || !tokenStatus.configured,
                action: onTest
            )
            TelegramBridgeRowActionButton(title: "Edit", systemImage: "pencil", action: onEdit)
            TelegramBridgeRowActionButton(title: "Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .padding(14)
    }
}

private struct TelegramBridgeAccountRow: View {
    var account: TelegramBridgeAccountConfig
    var tokenStatus: (configured: Bool, status: String, error: String?)
    var onEdit: () -> Void
    var onClearToken: () -> Void
    var onDelete: () -> Void

    private var title: String {
        account.role == "codex_remote" ? "Codex Remote" : "Gee Direct"
    }

    private var icon: String {
        account.role == "codex_remote" ? "terminal" : "bubble.left.and.bubble.right"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TelegramBridgePalette.accent)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(account.id)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            TelegramBridgeTokenStatusBadge(status: tokenStatus)
            Text(account.transport.mode)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            TelegramBridgeRowActionButton(title: "Edit", systemImage: "pencil", action: onEdit)
            TelegramBridgeRowActionButton(title: "Clear Token", systemImage: "key.slash", action: onClearToken)
            TelegramBridgeRowActionButton(title: "Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .padding(14)
    }
}

private struct TelegramBridgePushAccountRow: View {
    var account: TelegramBridgeAccountConfig
    var tokenStatus: (configured: Bool, status: String, error: String?)
    var channelCount: Int
    var onEdit: () -> Void
    var onClearToken: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TelegramBridgePalette.accent)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(account.botUsername ?? account.id)
                    .font(.system(size: 13, weight: .semibold))
                Text(account.id)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            TelegramBridgeTokenStatusBadge(status: tokenStatus)
            Text("\(channelCount) channel")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            TelegramBridgeRowActionButton(title: "Edit", systemImage: "pencil", action: onEdit)
            TelegramBridgeRowActionButton(title: "Clear Token", systemImage: "key.slash", action: onClearToken)
            TelegramBridgeRowActionButton(title: "Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .padding(14)
    }
}

private struct TelegramBridgeTokenStatusBadge: View {
    var status: (configured: Bool, status: String, error: String?)

    var body: some View {
        Text(status.configured ? "token configured" : status.status)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(status.configured ? .green : .orange)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((status.configured ? Color.green : Color.orange).opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .help(status.error ?? (status.configured ? "Local token is configured." : "Local token is missing."))
    }
}

private struct TelegramBridgeRowActionButton: View {
    var title: String
    var systemImage: String
    var role: ButtonRole?
    var isDisabled: Bool
    var action: () -> Void

    init(title: String, systemImage: String, role: ButtonRole? = nil, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(TelegramBridgeIconButtonStyle())
        .disabled(isDisabled)
        .help(isDisabled && title != "Testing" ? "Save a bot token for this push account before sending a test message." : title)
    }
}

private struct TelegramBridgeConversationThreadRow: View {
    var thread: TelegramBridgeConversationThread

    private var latestMessages: [TelegramBridgeConversationMessage] {
        Array(thread.messages.suffix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "message.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TelegramBridgePalette.accent)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(thread.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(thread.accountId) • \(thread.messages.count) messages")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Text(thread.updatedAt)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(latestMessages) { message in
                    HStack(alignment: .top, spacing: 8) {
                        Text(message.direction == "outbound" ? outboundLabel : "TG")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(message.direction == "outbound" ? TelegramBridgePalette.accent : .white.opacity(0.72))
                            .frame(width: 42, alignment: .leading)
                        Text(message.text)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(3)
                        Spacer()
                        Text(message.status)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(14)
    }

    private var outboundLabel: String {
        switch thread.accountRole {
        case "codex_remote":
            return "Codex"
        case "gee_direct":
            return "Gee"
        default:
            return "Bot"
        }
    }
}

private struct TelegramBridgeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.9))
            .background(Color.white.opacity(configuration.isPressed ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TelegramBridgePalette.border, lineWidth: 0.8)
            }
    }
}

private struct TelegramBridgePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.76 : 0.96))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(TelegramBridgePalette.accent.opacity(configuration.isPressed ? 0.68 : 0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TelegramBridgeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.9))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.white.opacity(configuration.isPressed ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TelegramBridgePalette.border, lineWidth: 0.8)
            }
    }
}

private enum TelegramBridgePalette {
    static let background = Color(red: 0.08, green: 0.095, blue: 0.11)
    static let border = Color.white.opacity(0.08)
    static let accent = Color(red: 0.26, green: 0.64, blue: 0.95)
}
