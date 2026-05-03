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
    @State private var setupChannelID = "morning_news"
    @State private var setupAccountID = "news_push"
    @State private var setupTitle = "Morning News"
    @State private var setupBotUsername = ""
    @State private var setupTargetKind = "chat_id"
    @State private var setupTargetValue = ""
    @State private var setupToken = ""

    private let roles: [TelegramBridgeRoleSummary] = [
        TelegramBridgeRoleSummary(
            title: "Codex Remote",
            systemImage: "terminal",
            state: "Worker Ready",
            detail: "Codex session control"
        ),
        TelegramBridgeRoleSummary(
            title: "Gee Direct",
            systemImage: "bubble.left.and.bubble.right",
            state: "Runtime Ingress",
            detail: "Phase 3 channel ingress"
        ),
        TelegramBridgeRoleSummary(
            title: "Push Only",
            systemImage: "paperplane",
            state: "Live Send",
            detail: "Outbound reports"
        )
    ]

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
                    TelegramBridgeRoleRow(role: role)
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
                    Text("Channels")
                        .font(.system(size: 22, weight: .semibold))
                    Text("\(model.config.pushChannels.count) configured")
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

            HStack(spacing: 12) {
                TelegramBridgeMetric(title: "Accounts", value: "\(model.config.accounts.count)", systemImage: "person.crop.circle")
                TelegramBridgeMetric(title: "Push Channels", value: "\(model.config.pushChannels.count)", systemImage: "paperplane")
                TelegramBridgeMetric(title: "Last Delivery", value: "None", systemImage: "clock")
            }

            setupPanel

            VStack(spacing: 0) {
                if model.config.pushChannels.isEmpty {
                    TelegramBridgeEmptyRow(
                        systemImage: "paperplane",
                        title: "No push channels",
                        detail: "Configured channels will appear here."
                    )
                } else {
                    ForEach(model.config.pushChannels) { channel in
                        TelegramBridgeChannelRow(channel: channel)
                        if channel.id != model.config.pushChannels.last?.id {
                            Rectangle()
                                .fill(TelegramBridgePalette.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(TelegramBridgePalette.border, lineWidth: 0.8)
            }

            Spacer()
        }
        .padding(22)
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TelegramBridgeTextField(title: "Channel", text: $setupChannelID)
                TelegramBridgeTextField(title: "Account", text: $setupAccountID)
                TelegramBridgeTextField(title: "Title", text: $setupTitle)
            }
            HStack(spacing: 10) {
                TelegramBridgeTextField(title: "Bot", text: $setupBotUsername)
                Picker("", selection: $setupTargetKind) {
                    Text("Chat").tag("chat_id")
                    Text("Group").tag("group_id")
                    Text("Channel").tag("channel_id")
                    Text("@Channel").tag("channel_username")
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                TelegramBridgeTextField(title: "Target", text: $setupTargetValue)
            }
            HStack(spacing: 10) {
                SecureField("Bot Token", text: $setupToken)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TelegramBridgePalette.border, lineWidth: 0.8)
                    }
                Button {
                    saveSetupToken()
                } label: {
                    Image(systemName: "key")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(TelegramBridgeIconButtonStyle())
                .help("Save token")
                Button {
                    upsertSetupChannel()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(TelegramBridgeIconButtonStyle())
                .help("Save channel")
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TelegramBridgePalette.border, lineWidth: 0.8)
        }
    }

    private func saveSetupToken() {
        do {
            try model.saveBotToken(accountID: setupAccountID, token: setupToken)
            setupToken = ""
            model.loadConfig()
        } catch {
            model.setStatusMessage(error.localizedDescription)
        }
    }

    private func upsertSetupChannel() {
        Task {
            _ = await model.runAgentAction(
                capabilityID: "telegram_push.upsert_channel",
                args: [
                    "channel_id": setupChannelID,
                    "account_id": setupAccountID,
                    "title": setupTitle,
                    "bot_username": setupBotUsername,
                    "target_kind": setupTargetKind,
                    "target_value": setupTargetValue
                ]
            )
            model.loadConfig()
        }
    }
}

private struct TelegramBridgeRoleSummary: Identifiable {
    let id = UUID()
    var title: String
    var systemImage: String
    var state: String
    var detail: String
}

private struct TelegramBridgeRoleRow: View {
    var role: TelegramBridgeRoleSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: role.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TelegramBridgePalette.accent)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            Text(channel.target.kind)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(14)
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

private enum TelegramBridgePalette {
    static let background = Color(red: 0.08, green: 0.095, blue: 0.11)
    static let border = Color.white.opacity(0.08)
    static let accent = Color(red: 0.26, green: 0.64, blue: 0.95)
}
