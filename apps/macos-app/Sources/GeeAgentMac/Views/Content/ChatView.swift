import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Bindable var store: WorkbenchStore
    @State private var draftMessage = ""
    @State private var draftAttachments: [ChatAttachmentDraft] = []
    @State private var pendingDraftRecovery: String?
    @State private var pendingAttachmentRecovery: [ChatAttachmentDraft] = []
    @State private var isAttachmentDropTargeted = false
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
                } else if store.isSendingMessage {
                    ContentUnavailableView {
                        Label(store.localizedString("chat.starting.title", defaultValue: "Starting Chat"), systemImage: "brain.head.profile")
                    } description: {
                        Text(store.localizedString("chat.starting.description", defaultValue: "Request sent. Waiting for the first agent event..."))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        store.localizedString("chat.empty.title", defaultValue: "No Chat Selected"),
                        systemImage: "bubble.left",
                        description: Text(store.localizedString("chat.empty.description", defaultValue: "Start a new chat to run work through GeeAgent."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(18)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .navigationTitle(store.localizedString("chat.title", defaultValue: "Chat"))
        .onDrop(
            of: ChatAttachmentTransfer.fileDropTypes,
            isTargeted: $isAttachmentDropTargeted,
            perform: handleAttachmentDrop
        )
        .onChange(of: store.selectedConversationID) { _, _ in
            store.activateSelectedConversation()
        }
        .onChange(of: store.lastErrorMessage) { _, newValue in
            guard newValue != nil else {
                return
            }

            if let pendingDraftRecovery, draftMessage.isEmpty {
                draftMessage = pendingDraftRecovery
                self.pendingDraftRecovery = nil
            }
            if draftAttachments.isEmpty {
                draftAttachments = pendingAttachmentRecovery
            }
            pendingAttachmentRecovery = []
        }
        .onChange(of: store.isSendingMessage) { _, isSending in
            if !isSending, store.lastErrorMessage == nil {
                pendingDraftRecovery = nil
                pendingAttachmentRecovery = []
            }
        }
        .onChange(of: store.audioCapture.chatVoiceText) { _, recognizedText in
            let trimmed = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let existingDraft = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            draftMessage = existingDraft.isEmpty ? trimmed : "\(existingDraft) \(trimmed)"
        }
    }

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.localizedString("chat.title", defaultValue: "Chat"))
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Button {
                    store.createConversation()
                } label: {
                    Label(store.localizedString("chat.new", defaultValue: "New"), systemImage: "plus")
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
                                Label(store.localizedString("chat.deleteChat", defaultValue: "Delete Chat"), systemImage: "trash")
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

                            if store.shouldShowChatActivityFallback(for: conversation) {
                                TransientAgentActivityCard(label: store.chatActivityFallbackLabel(for: conversation))
                            }

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

            Text(store.localizedString("chat.prompt", defaultValue: "What would you like to do?"))
                .font(.geeDisplaySemibold(22))
                .foregroundStyle(.primary.opacity(0.92))

            if store.isSendingMessage {
                TransientAgentActivityCard(label: store.localizedString("chat.activity.starting", defaultValue: "Request sent. GeeAgent is starting the run..."))
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
            if !draftAttachments.isEmpty {
                attachmentDraftStrip
            }

            HStack(spacing: 12) {
                Button {
                    showAttachmentPicker()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(store.localizedString("chat.attachHelp", defaultValue: "Attach files or folders"))
                .disabled(store.isSendingMessage || !store.canSendMessages)

                Button {
                    toggleVoiceInput()
                } label: {
                    Image(systemName: store.audioCapture.isChatVoiceInputActive ? "mic.fill" : "mic")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(store.audioCapture.isChatVoiceInputActive ? Color.red : Color.primary.opacity(0.82))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(
                    store.audioCapture.isChatVoiceInputActive
                        ? store.localizedString("chat.voice.stop", defaultValue: "Stop voice input")
                        : store.localizedFormat("chat.voice.start", defaultValue: "Start voice input with %@", store.audioCapture.selectedProvider.title)
                )
                .disabled(store.isSendingMessage || !store.canSendMessages)

                TextField(
                    "",
                    text: $draftMessage,
                    prompt: Text(store.localizedString("chat.composer.placeholder", defaultValue: "Ask GeeAgent to chat or run a simple task"))
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

                if store.isSendingMessage {
                    Button {
                        store.stopActiveChatRun()
                    } label: {
                        Label(store.isStoppingMessage
                            ? store.localizedString("common.stopping", defaultValue: "Stopping")
                            : store.localizedString("common.stop", defaultValue: "Stop"), systemImage: "stop.fill")
                            .font(.geeDisplaySemibold(11))
                            .frame(height: 38)
                            .padding(.horizontal, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(store.isStoppingMessage ? Color.secondary.opacity(0.24) : Color.red.opacity(0.78))
                            )
                            .foregroundStyle(store.isStoppingMessage ? Color.secondary : Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isStoppingMessage)
                    .help(store.isStoppingMessage
                        ? store.localizedString("chat.stop.stoppingHelp", defaultValue: "Stopping the current run")
                        : store.localizedString("chat.stop.help", defaultValue: "Stop the current run"))
                } else {
                    Button {
                        sendDraftMessage()
                    } label: {
                        Label(store.localizedString("chat.send", defaultValue: "Send"), systemImage: "arrow.up")
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

            if let voiceStatus = store.audioCapture.chatVoiceStatusMessage,
               !voiceStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: store.audioCapture.isChatVoiceInputActive ? "waveform" : "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(voiceStatus)
                        .lineLimit(1)
                }
                .font(.geeBody(11))
                .foregroundStyle(store.audioCapture.isChatVoiceInputActive ? Color.red.opacity(0.78) : Color.secondary)
                .padding(.horizontal, 4)
            }

        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: -4)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: isAttachmentDropTargeted 
                            ? [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.5)]
                            : [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isAttachmentDropTargeted ? 1.2 : 0.8
                )
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isAttachmentDropTargeted,
            perform: handleAttachmentDrop
        )
        .onPasteCommand(
            of: [.fileURL, .image, .png, .jpeg],
            perform: handleAttachmentPaste
        )
    }

    private var attachmentDraftStrip: some View {
        ChatAttachmentDraftStrip(attachments: draftAttachments) { id in
            draftAttachments.removeAll { $0.id == id }
        }
    }

    private var canSendDraft: Bool {
        !store.isSendingMessage &&
            (!draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasSendableAttachmentDraft) &&
            store.canSendMessages
    }

    private var hasSendableAttachmentDraft: Bool {
        draftAttachments.contains { $0.isSendable }
    }

    private func sendDraftMessage() {
        guard canSendDraft else {
            return
        }

        let message = draftMessage
        let attachments = sendableAttachmentDrafts.map(\.runtimeAttachment)
        pendingDraftRecovery = message
        pendingAttachmentRecovery = draftAttachments
        draftMessage = ""
        draftAttachments = []
        store.sendMessage(message, attachments: attachments)
    }

    private func toggleVoiceInput() {
        if store.audioCapture.isChatVoiceInputActive {
            store.audioCapture.stopChatVoiceInput()
        } else {
            store.audioCapture.startChatVoiceInput()
        }
    }

    private var sendableAttachmentDrafts: [ChatAttachmentDraft] {
        draftAttachments.filter(\.isSendable)
    }

    private func handleAttachmentDrop(_ providers: [NSItemProvider]) -> Bool {
        ChatAttachmentTransfer.handleFileDrop(providers, appendURLs: appendAttachmentURLs)
    }

    private func handleAttachmentPaste(_ providers: [NSItemProvider]) {
        ChatAttachmentTransfer.handlePaste(
            providers,
            appendURLs: appendAttachmentURLs,
            appendDrafts: appendAttachmentDrafts
        )
    }

    private func showAttachmentPicker() {
        ChatAttachmentTransfer.showAttachmentPicker(appendURLs: appendAttachmentURLs)
    }

    private func appendAttachmentURLs(_ urls: [URL]) {
        appendAttachmentDrafts(urls.map(ChatAttachmentDraft.make(fileURL:)))
    }

    private func appendAttachmentDrafts(_ drafts: [ChatAttachmentDraft]) {
        draftAttachments.appendUniqueAttachmentDrafts(drafts)
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
                title: store.localizedString("chat.runtime.needsSetup", defaultValue: "Chat needs setup"),
                detail: store.runtimeStatus.detail,
                systemImage: store.runtimeStatus.state.systemImage,
                tint: .orange,
                actionLabel: store.localizedString("chat.runtime.openSettings", defaultValue: "Open Settings")
            ) {
                store.openSection(.settings)
            }
        case .degraded:
            InlineStatusCard(
                title: store.localizedString("chat.runtime.degraded", defaultValue: "Chat is degraded"),
                detail: store.runtimeStatus.detail,
                systemImage: store.runtimeStatus.state.systemImage,
                tint: .yellow,
                actionLabel: store.localizedString("chat.runtime.openSettings", defaultValue: "Open Settings")
            ) {
                store.openSection(.settings)
            }
        case .unavailable:
            InlineStatusCard(
                title: store.localizedString("chat.runtime.unavailable", defaultValue: "Runtime unavailable"),
                detail: store.runtimeStatus.detail,
                systemImage: store.runtimeStatus.state.systemImage,
                tint: .red,
                actionLabel: store.localizedString("chat.runtime.openSettings", defaultValue: "Open Settings")
            ) {
                store.openSection(.settings)
            }
        }
    }

    @ViewBuilder
    private var errorCard: some View {
        if let chatErrorMessage = store.chatErrorMessage {
            InlineStatusCard(
                title: store.localizedString("chat.error.couldNotFinish", defaultValue: "Couldn’t finish that request"),
                detail: chatErrorMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .red,
                actionLabel: store.localizedString("chat.error.dismiss", defaultValue: "Dismiss")
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

    @State private var isHovering = false

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
                .fill(isSelected ? Color.accentColor.opacity(0.16) : (isHovering ? Color.white.opacity(0.06) : Color.white.opacity(0.035)))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: isSelected 
                            ? [Color.accentColor.opacity(0.38), Color.accentColor.opacity(0.18)]
                            : [Color.white.opacity(isHovering ? 0.18 : 0.08), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .scaleEffect(isHovering && !isSelected ? 1.01 : 1.0)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var previewText: String {
        let trimmed = conversation.displayPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppLocalization.string("chat.noMessages", defaultValue: "No messages yet.") : trimmed
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
