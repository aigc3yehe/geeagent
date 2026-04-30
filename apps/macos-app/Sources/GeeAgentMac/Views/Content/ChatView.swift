import SwiftUI

struct ChatView: View {
    @Bindable var store: WorkbenchStore
    @State private var draftMessage = ""
    @State private var chatViewportHeight: CGFloat = 0
    @State private var chatBottomMaxY: CGFloat = 0
    @State private var isChatScrolledNearBottom = true

    private let chatScrollCoordinateSpaceName = "GeeAgentChatTranscriptScroll"
    private let chatBottomAutoFollowTolerance: CGFloat = 96

    var body: some View {
        GeometryReader { proxy in
            let listWidth = min(max(proxy.size.width * 0.28, 270), 332)

            HStack(spacing: 0) {
                conversationColumn
                    .frame(width: listWidth, alignment: .topLeading)
                    .padding(.trailing, 18)

                if let conversation = store.selectedDisplayConversation {
                    conversationDetail(conversation)
                } else {
                    ContentUnavailableView(
                        "No Chat Selected",
                        systemImage: "bubble.left",
                        description: Text("Start a new chat to run work through GeeAgent.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(18)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .navigationTitle("Chat")
        .onChange(of: store.selectedConversationID) { _, _ in
            store.activateSelectedConversation()
        }
    }

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Button {
                    store.createConversation()
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.geeDisplaySemibold(11))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.16))
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.accentColor.opacity(0.28), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
                .disabled(store.isCreatingConversation || !store.canCreateConversation)
                .opacity(store.isCreatingConversation || !store.canCreateConversation ? 0.46 : 1)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.displayConversations) { conversation in
                        Button {
                            store.selectedConversationID = conversation.id
                        } label: {
                            ConversationRow(
                                conversation: conversation,
                                isSelected: conversation.id == store.selectedConversationID
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.deleteConversation(conversation.id)
                            } label: {
                                Label("Delete Chat", systemImage: "trash")
                            }
                            .disabled(!store.canMutateRuntime || store.isDeletingConversation)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .thinScrollIndicator()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func conversationDetail(_ conversation: ConversationThread) -> some View {
        let bottomID = chatBottomID(for: conversation)

        return VStack(spacing: 8) {
            ConversationHeader(conversation: conversation, runtimeStatus: store.runtimeStatus)

            if conversation.turnBlocks.isEmpty {
                emptyConversationBody
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            runtimeCard
                            errorCard

                            ChatTurnBlockList(store: store, conversation: conversation)

                            Color.clear
                                .frame(height: 1)
                                .id(bottomID)
                                .background(
                                    GeometryReader { bottomProxy in
                                        Color.clear.preference(
                                            key: ChatBottomMaxYPreferenceKey.self,
                                            value: bottomProxy.frame(in: .named(chatScrollCoordinateSpaceName)).maxY
                                        )
                                    }
                                )
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    }
                    .coordinateSpace(name: chatScrollCoordinateSpaceName)
                    .background(
                        GeometryReader { viewportProxy in
                            Color.clear.preference(
                                key: ChatViewportHeightPreferenceKey.self,
                                value: viewportProxy.size.height
                            )
                        }
                    )
                    .thinScrollIndicator()
                    .onAppear {
                        isChatScrolledNearBottom = true
                        scrollToChatBottom(scrollProxy, conversation: conversation, animated: false)
                    }
                    .onChange(of: conversationMessageSignatures(conversation)) { oldSignatures, newSignatures in
                        guard shouldAutoFollowChat(
                            conversation: conversation,
                            oldSignatures: oldSignatures,
                            newSignatures: newSignatures
                        ) else {
                            return
                        }
                        scrollToChatBottom(scrollProxy, conversation: conversation)
                    }
                    .onPreferenceChange(ChatViewportHeightPreferenceKey.self) { height in
                        chatViewportHeight = height
                        updateChatScrollPosition()
                    }
                    .onPreferenceChange(ChatBottomMaxYPreferenceKey.self) { bottomMaxY in
                        chatBottomMaxY = bottomMaxY
                        updateChatScrollPosition()
                    }
                }
                .id(conversation.id)

                composer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyConversationBody: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                runtimeCard
                errorCard
            }
            .frame(maxWidth: 720)

            Spacer(minLength: 0)

            Text("What would you like to do?")
                .font(.geeDisplaySemibold(22))
                .foregroundStyle(.primary.opacity(0.92))

            if store.isSendingMessage {
                TransientAgentActivityCard(label: "Request sent. GeeAgent is starting the run…")
                    .frame(maxWidth: 720)
            }

            composer
                .frame(maxWidth: 720)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField(
                    "",
                    text: $draftMessage,
                    prompt: Text("Ask GeeAgent to chat or run a simple task")
                        .foregroundStyle(.secondary.opacity(0.72))
                )
                .textFieldStyle(.plain)
                .font(.geeBodyMedium(14))
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.9)
                }
                .onSubmit(sendDraftMessage)

                ContextBudgetIndicator(budget: store.contextBudget)

                Button {
                    sendDraftMessage()
                } label: {
                    Label("Send", systemImage: "arrow.up")
                        .font(.geeDisplaySemibold(11))
                        .frame(height: 38)
                        .padding(.horizontal, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(canSendDraft ? Color.accentColor : Color.secondary.opacity(0.22))
                        )
                        .foregroundStyle(canSendDraft ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSendDraft)
            }

        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var canSendDraft: Bool {
        !store.isSendingMessage &&
        !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        store.canSendMessages
    }

    private func sendDraftMessage() {
        guard canSendDraft else {
            return
        }

        let message = draftMessage
        draftMessage = ""
        store.sendMessage(message)
    }

    private func conversationMessageSignatures(_ conversation: ConversationThread) -> [String] {
        conversation.visibleMessages.map { message in
            "\(message.id):\(message.content.count):\(message.statusLabel ?? "")"
        }
    }

    private func shouldAutoFollowChat(
        conversation: ConversationThread,
        oldSignatures: [String],
        newSignatures: [String]
    ) -> Bool {
        isChatScrolledNearBottom || didAppendUserMessage(
            conversation: conversation,
            oldSignatures: oldSignatures,
            newSignatures: newSignatures
        )
    }

    private func didAppendUserMessage(
        conversation: ConversationThread,
        oldSignatures: [String],
        newSignatures: [String]
    ) -> Bool {
        let oldIDs = Set(oldSignatures.map(messageIDFromSignature))
        let newIDs = Set(newSignatures.map(messageIDFromSignature))
        let appendedIDs = newIDs.subtracting(oldIDs)
        guard !appendedIDs.isEmpty else {
            return false
        }

        return conversation.visibleMessages.contains { message in
            appendedIDs.contains(message.id) && message.role == .user
        }
    }

    private func messageIDFromSignature(_ signature: String) -> String {
        signature.split(separator: ":", maxSplits: 1).first.map(String.init) ?? signature
    }

    private func updateChatScrollPosition() {
        guard chatViewportHeight > 0 else {
            isChatScrolledNearBottom = true
            return
        }

        isChatScrolledNearBottom = chatBottomMaxY <= chatViewportHeight + chatBottomAutoFollowTolerance
    }

    private func chatBottomID(for conversation: ConversationThread) -> String {
        "chat-bottom-\(conversation.id)"
    }

    private func scrollToChatBottom(
        _ proxy: ScrollViewProxy,
        conversation: ConversationThread,
        animated: Bool = true
    ) {
        let bottomID = chatBottomID(for: conversation)
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var runtimeCard: some View {
        switch store.runtimeStatus.state {
        case .live:
            EmptyView()
        case .needsSetup:
            InlineStatusCard(
                title: "Chat needs setup",
                detail: store.runtimeStatus.detail,
                systemImage: store.runtimeStatus.state.systemImage,
                tint: .orange,
                actionLabel: "Open Settings"
            ) {
                store.openSection(.settings)
            }
        case .degraded:
            InlineStatusCard(
                title: "Chat is degraded",
                detail: store.runtimeStatus.detail,
                systemImage: store.runtimeStatus.state.systemImage,
                tint: .yellow,
                actionLabel: "Open Settings"
            ) {
                store.openSection(.settings)
            }
        case .unavailable:
            InlineStatusCard(
                title: "Runtime unavailable",
                detail: store.runtimeStatus.detail,
                systemImage: store.runtimeStatus.state.systemImage,
                tint: .red,
                actionLabel: "Open Settings"
            ) {
                store.openSection(.settings)
            }
        }
    }

    @ViewBuilder
    private var errorCard: some View {
        if let lastErrorMessage = store.lastErrorMessage {
            InlineStatusCard(
                title: "Couldn’t finish that request",
                detail: lastErrorMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .red,
                actionLabel: "Dismiss"
            ) {
                store.dismissError()
            }
        } else {
            EmptyView()
        }
    }
}

private struct ConversationRow: View {
    var conversation: ConversationThread
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "bubble.left.fill" : "bubble.left")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(conversation.displayTitle)
                        .font(.geeBodyMedium(14))
                        .lineLimit(1)

                    ConversationTagStrip(tags: conversation.tags)

                    Spacer(minLength: 8)

                    Text(conversation.lastActivityLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.06), lineWidth: 0.8)
        }
    }

    private var previewText: String {
        let trimmed = conversation.displayPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No messages yet." : trimmed
    }
}

private struct ConversationHeader: View {
    var conversation: ConversationThread
    var runtimeStatus: WorkbenchRuntimeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(conversation.displayTitle)
                            .font(.geeDisplaySemibold(22))
                            .lineLimit(1)

                        ConversationTagStrip(tags: conversation.tags)
                    }

                    Label(conversation.lastActivityLabel, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if runtimeStatus.state != .live {
                    WorkbenchStatusBadge(
                        title: runtimeStatus.state.title,
                        systemImage: runtimeStatus.state.systemImage
                    )
                }
            }

            if conversation.linkedTaskTitle != nil || conversation.linkedAppName != nil {
                HStack(spacing: 12) {
                    if let linkedTaskTitle = conversation.linkedTaskTitle {
                        Label(linkedTaskTitle, systemImage: "checklist")
                            .foregroundStyle(.secondary)
                    }

                    if let linkedAppName = conversation.linkedAppName {
                        Label(linkedAppName, systemImage: "square.grid.2x2")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct ChatViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatBottomMaxYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ConversationTagStrip: View {
    var tags: [String]

    private var visibleTags: [String] {
        tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if !visibleTags.isEmpty {
            HStack(spacing: 4) {
                ForEach(visibleTags, id: \.self) { tag in
                    Text(tag)
                        .font(.geeBodyMedium(10))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            .lineLimit(1)
        }
    }
}

private struct InlineStatusCard: View {
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color
    var actionLabel: String?
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.geeDisplaySemibold(13))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let actionLabel {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}
