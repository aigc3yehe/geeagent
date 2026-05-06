import SwiftUI

struct TelegramConversationsView: View {
    @StateObject private var telegramStore = TelegramBridgeGearStore.shared
    @State private var selectedThreadID: String?

    private var threads: [TelegramBridgeConversationThread] {
        telegramStore.conversationLog.threads
    }

    private var selectedThread: TelegramBridgeConversationThread? {
        guard let selectedThreadID else {
            return threads.first
        }
        return threads.first { $0.id == selectedThreadID } ?? threads.first
    }

    var body: some View {
        GeometryReader { proxy in
            let listWidth = min(max(proxy.size.width * 0.30, 280), 360)

            HStack(spacing: 0) {
                threadColumn
                    .frame(width: listWidth, alignment: .topLeading)
                    .padding(.trailing, 18)

                if let thread = selectedThread {
                    threadDetail(thread)
                } else {
                    ContentUnavailableView(
                        "No Telegram Conversations",
                        systemImage: "paperplane",
                        description: Text("Messages will appear after a configured conversation bot receives an allowed Telegram message.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(18)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .navigationTitle("Telegram")
        .onAppear {
            telegramStore.loadConfig()
            normalizeSelection()
        }
        .onChange(of: threadIDs) { _, _ in
            normalizeSelection()
        }
    }

    private var threadColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Telegram")
                        .font(.geeDisplaySemibold(18))
                    Text(telegramStore.lastStatusMessage)
                        .font(.geeBody(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    telegramStore.loadConfig()
                    normalizeSelection()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh Telegram conversations")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(threads) { thread in
                        Button {
                            selectedThreadID = thread.id
                        } label: {
                            TelegramConversationRow(
                                thread: thread,
                                isSelected: thread.id == selectedThread?.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .thinScrollIndicator()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func threadDetail(_ thread: TelegramBridgeConversationThread) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: thread.accountRole == "codex_remote" ? "terminal" : "paperplane")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.title)
                        .font(.geeDisplaySemibold(18))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        TelegramConversationBadge(text: thread.accountRole ?? "telegram")
                        TelegramConversationBadge(text: thread.accountId)
                        Text(thread.chatId)
                            .font(.geeBody(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(GeeAgentTimeFormatting.conversationTimestampLabel(thread.updatedAt))
                    .font(.geeBody(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()
                .opacity(0.18)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(thread.messages) { message in
                        TelegramConversationMessageRow(message: message)
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 6)
            }
            .thinScrollIndicator()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var threadIDs: [String] {
        threads.map(\.id)
    }

    private func normalizeSelection() {
        guard !threads.isEmpty else {
            selectedThreadID = nil
            return
        }
        if selectedThreadID == nil || !threads.contains(where: { $0.id == selectedThreadID }) {
            selectedThreadID = threads.first?.id
        }
    }
}

private struct TelegramConversationRow: View {
    var thread: TelegramBridgeConversationThread
    var isSelected: Bool

    private var latestMessage: TelegramBridgeConversationMessage? {
        thread.messages.last
    }

    private var iconName: String {
        thread.accountRole == "codex_remote" ? "terminal" : "paperplane"
    }

    private var iconForeground: Color {
        isSelected ? Color.white : Color.accentColor
    }

    private var iconBackground: Color {
        isSelected ? Color.white.opacity(0.12) : Color.accentColor.opacity(0.12)
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.20) : Color.white.opacity(0.05)
    }

    private var rowBorder: Color {
        isSelected ? Color.accentColor.opacity(0.36) : Color.white.opacity(0.08)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            rowHeader
            latestPreview
            rowFooter
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rowBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(rowBorder, lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var rowHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconForeground)
                .frame(width: 24, height: 24)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(thread.title)
                    .font(.geeDisplaySemibold(13))
                    .lineLimit(1)
                Text(thread.accountId)
                    .font(.geeBody(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var latestPreview: some View {
        if let latestMessage {
            Text(latestMessage.text)
                .font(.geeBodyMedium(12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var rowFooter: some View {
        HStack(spacing: 8) {
            TelegramConversationBadge(text: thread.accountRole ?? "telegram")
            Text(GeeAgentTimeFormatting.conversationTimestampLabel(thread.updatedAt))
                .font(.geeBody(10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct TelegramConversationMessageRow: View {
    var message: TelegramBridgeConversationMessage

    private var isOutbound: Bool {
        message.direction == "outbound"
    }

    var body: some View {
        HStack {
            if isOutbound {
                Spacer(minLength: 40)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(isOutbound ? outboundLabel : "Telegram")
                        .font(.geeBody(10))
                        .foregroundStyle(isOutbound ? Color.accentColor : .secondary)
                    TelegramConversationBadge(text: message.status)
                    Spacer(minLength: 0)
                }

                Text(message.text)
                    .font(.geeBodyMedium(13))
                    .foregroundStyle(.primary.opacity(0.92))
                    .textSelection(.enabled)

                Text(GeeAgentTimeFormatting.conversationTimestampLabel(message.timestamp))
                    .font(.geeBody(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(maxWidth: 620, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOutbound ? Color.accentColor.opacity(0.13) : Color.white.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isOutbound ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.08), lineWidth: 0.8)
            }

            if !isOutbound {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOutbound ? .trailing : .leading)
    }

    private var outboundLabel: String {
        switch message.status {
        case "codex_success", "codex_failed", "codex_blocked", "codex_empty_result":
            "Codex"
        default:
            "Gee"
        }
    }
}

private struct TelegramConversationBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.geeBody(10))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12), in: Capsule(style: .continuous))
    }
}
