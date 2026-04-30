import AppKit
import SwiftUI

struct ChatMarkdownText: View {
    var content: String
    var font: Font = .geeBody(14)
    var lineSpacing: CGFloat = 7
    var color: Color = .primary
    var textSelectionEnabled: Bool = true

    @ViewBuilder
    var body: some View {
        if textSelectionEnabled {
            textBody
                .textSelection(.enabled)
        } else {
            textBody
                .textSelection(.disabled)
        }
    }

    private var textBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(markdownRows) { row in
                switch row.kind {
                case .blank:
                    Color.clear
                        .frame(height: max(lineSpacing * 1.8, 8))
                case .paragraph(let text):
                    markdownLineView(text)
                case .heading(let text):
                    markdownLineView(text)
                        .font(.geeDisplaySemibold(15))
                        .padding(.bottom, 4)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                            .font(font)
                        markdownLineView(text)
                    }
                case .numbered(let marker, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(marker)
                            .font(font)
                        markdownLineView(text)
                    }
                case .code(let text):
                    Text(text)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(color.opacity(0.86))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 1)
                }
            }
        }
        .font(font)
        .lineSpacing(lineSpacing)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdownLine(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }

    @ViewBuilder
    private func markdownLineView(_ text: String) -> some View {
        if let path = localFilePath(from: text) {
            FilePathInlineLink(path: path, font: font, color: color)
        } else {
            markdownLine(text)
        }
    }

    private var normalizedContent: String {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var markdownRows: [ChatMarkdownRow] {
        var rows = [ChatMarkdownRow]()
        var isInsideCodeBlock = false

        for (index, rawLine) in normalizedContent.components(separatedBy: "\n").enumerated() {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                isInsideCodeBlock.toggle()
                continue
            }

            let kind: ChatMarkdownRow.Kind
            if isInsideCodeBlock {
                kind = .code(rawLine)
            } else if trimmedLine.isEmpty {
                kind = .blank
            } else if trimmedLine.hasPrefix("#") {
                kind = .heading(trimmedLine.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
            } else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                kind = .bullet(String(trimmedLine.dropFirst(2)))
            } else if let numbered = numberedListParts(from: trimmedLine) {
                kind = .numbered(numbered.marker, numbered.text)
            } else {
                kind = .paragraph(rawLine.trimmingCharacters(in: .whitespaces))
            }

            rows.append(ChatMarkdownRow(id: index, kind: kind))
        }

        return rows
    }

    private func numberedListParts(from line: String) -> (marker: String, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }

        let prefix = line[..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else {
            return nil
        }

        let textStart = line.index(after: dotIndex)
        let text = line[textStart...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            return nil
        }

        return ("\(prefix).", text)
    }

    private func localFilePath(from text: String) -> String? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingCharacters = CharacterSet(charactersIn: ".,;:，。；：)]}＞>」』")
        trimmed = trimmed.trimmingCharacters(in: trailingCharacters)
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") else {
            return nil
        }

        return trimmed.contains(" ") ? nil : trimmed
    }
}

private struct ChatMarkdownRow: Identifiable {
    enum Kind {
        case blank
        case paragraph(String)
        case heading(String)
        case bullet(String)
        case numbered(String, String)
        case code(String)
    }

    let id: Int
    var kind: Kind
}

private struct FilePathInlineLink: View {
    var path: String
    var font: Font
    var color: Color

    private var expandedPath: String {
        (path as NSString).expandingTildeInPath
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: expandedPath))
        } label: {
            Text(path)
                .font(font)
                .foregroundStyle(Color.accentColor.opacity(0.92))
                .underline()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                revealInFinder()
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }
        }
        .help("Open \(path)")
    }

    private func revealInFinder() {
        let url = URL(fileURLWithPath: expandedPath)
        if FileManager.default.fileExists(atPath: expandedPath) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

struct ChatMessageCard: View {
    @Bindable var store: WorkbenchStore
    var conversationID: ConversationThread.ID
    var message: ConversationMessage
    var prominentBackground: Bool = false

    @State private var copyFeedbackActive = false
    @State private var deleteFeedbackActive = false
    @State private var isDeleting = false
    @State private var feedbackResetTask: Task<Void, Never>?

    var body: some View {
        Group {
            if message.kind == .chat {
                chatMessageLayout
            } else if message.kind == .thinking {
                AgentThinkingDisclosure(messages: [message], prominentBackground: prominentBackground)
            } else {
                structuredMessageLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardPadding)
        .background(backgroundShape)
        .overlay(chatBorderOverlay)
        .opacity(isDeleting ? 0.01 : 1)
        .scaleEffect(isDeleting ? 0.985 : 1, anchor: .center)
        .animation(.easeOut(duration: 0.16), value: isDeleting)
        .onDisappear {
            feedbackResetTask?.cancel()
        }
    }

    @ViewBuilder
    private var chatBorderOverlay: some View {
        if showsChatBubble || message.kind != .chat {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var chatMessageLayout: some View {
        if message.role == .user {
            userChatMessageLayout
        } else {
            assistantChatMessageLayout
        }
    }

    private var userChatMessageLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            ChatMarkdownText(
                content: message.content,
                font: .geeBody(14),
                lineSpacing: 7,
                color: prominentBackground ? .white.opacity(0.94) : .primary
            )
            .layoutPriority(1)

            if message.canDelete {
                deleteMessageButton
                    .padding(.top, -1)
            }
        }
    }

    private var assistantChatMessageLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChatMarkdownText(
                content: displayChatContent,
                font: .geeBody(14),
                lineSpacing: 7,
                color: prominentBackground ? .white.opacity(0.94) : .primary
            )

            HStack {
                Spacer(minLength: 0)
                chatActionButtons
            }
        }
    }

    private var displayChatContent: String {
        guard message.role == .assistant else {
            return message.content
        }
        return stripHardStageConclusionPrefix(message.content)
    }

    private var structuredMessageLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Label(message.displayTitle, systemImage: headerSystemImage)
                    .font(.geeDisplaySemibold(10))
                    .foregroundStyle(headerTint)

                Spacer(minLength: 0)
            }

            messageBody

            if let taskID = message.primaryActionTaskID {
                if message.kind == .approval,
                   let task = store.tasks.first(where: { $0.id == taskID }) {
                    approvalActionRow(task: task)
                } else if let primaryActionLabel = message.primaryActionLabel {
                    Button {
                        store.openTask(taskID)
                    } label: {
                        Label(primaryActionLabel, systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
    }

    private func approvalActionRow(task: WorkbenchTaskRecord) -> some View {
        let actions = store.taskActions(for: task)
        return HStack(spacing: 8) {
            ForEach(actions, id: \.self) { action in
                if action == .deny {
                    approvalDenyButton(action, taskID: task.id)
                } else {
                    approvalPrimaryButton(action, taskID: task.id)
                }
            }
        }
    }

    private func approvalPrimaryButton(
        _ action: WorkbenchTaskAction,
        taskID: WorkbenchTaskRecord.ID
    ) -> some View {
        Button {
            store.performTaskAction(action, taskID: taskID, openSection: false)
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(store.isPerformingTaskAction)
    }

    private func approvalDenyButton(
        _ action: WorkbenchTaskAction,
        taskID: WorkbenchTaskRecord.ID
    ) -> some View {
        Button {
            store.performTaskAction(action, taskID: taskID, openSection: false)
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.red)
        .disabled(store.isPerformingTaskAction)
    }

    @ViewBuilder
    private var chatActionButtons: some View {
        HStack(spacing: 6) {
            if message.role != .user,
               !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                actionButton(
                    systemImage: copyFeedbackActive ? "checkmark" : "doc.on.doc",
                    tint: copyFeedbackActive ? .green : .secondary,
                    help: copyFeedbackActive ? "Copied" : "Copy message",
                    compact: true
                ) {
                    store.copyMessageContent(message.content)
                    pulseCopyFeedback()
                }
            }

            if message.canDelete {
                deleteMessageButton
            }
        }
    }

    private var deleteMessageButton: some View {
        actionButton(
            systemImage: deleteFeedbackActive ? "checkmark" : "trash",
            tint: deleteFeedbackActive ? .red : .secondary,
            help: store.canMutateRuntime ? "Delete message" : "Message deletion is unavailable",
            compact: true
        ) {
            guard store.canMutateRuntime else {
                return
            }
            deleteMessageWithFeedback()
        }
        .disabled(!store.canMutateRuntime || isDeleting)
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if prominentBackground {
            switch message.kind {
            case .chat:
                return message.role == .user ? Color.white.opacity(0.12) : Color.clear
            case .thinking:
                return Color.white.opacity(0.04)
            case .action:
                return accentColor.opacity(0.16)
            case .approval:
                return accentColor.opacity(0.2)
            }
        }
        switch message.kind {
        case .chat:
            return message.role == .user ? Color.white.opacity(0.08) : Color.clear
        case .thinking:
            return Color.black.opacity(0.025)
        case .action:
            return accentColor.opacity(0.08)
        case .approval:
            return accentColor.opacity(0.11)
        }
    }

    private var borderColor: Color {
        switch message.kind {
        case .chat:
            return message.role == .user ? Color.white.opacity(prominentBackground ? 0.1 : 0.08) : Color.clear
        case .thinking:
            return Color.white.opacity(prominentBackground ? 0.08 : 0.05)
        case .action, .approval:
            return accentColor.opacity(prominentBackground ? 0.34 : 0.28)
        }
    }

    private var showsChatBubble: Bool {
        message.kind == .chat && message.role == .user
    }

    private var cardPadding: EdgeInsets {
        if message.kind == .chat && !showsChatBubble {
            return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        }
        return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    }

    private func actionButton(
        systemImage: String,
        tint: Color,
        help: String,
        compact: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 8.25 : 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: compact ? 18 : 24, height: compact ? 18 : 24)
        }
        .buttonStyle(.plain)
        .help(help)
        .contentTransition(.symbolEffect(.replace))
    }

    private func pulseCopyFeedback() {
        feedbackResetTask?.cancel()
        withAnimation(.easeOut(duration: 0.14)) {
            copyFeedbackActive = true
        }

        feedbackResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                copyFeedbackActive = false
            }
        }
    }

    private func deleteMessageWithFeedback() {
        feedbackResetTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            deleteFeedbackActive = true
            isDeleting = true
        }

        let conversationID = conversationID
        let messageID = message.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            store.deleteMessage(messageID, from: conversationID)
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        switch message.kind {
        case .chat:
            EmptyView()
        case .thinking:
            Text(message.content)
                .font(.caption)
                .foregroundStyle(prominentBackground ? .white.opacity(0.7) : .secondary)
        case .action, .approval:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let systemImage = message.systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }

                    if let statusLabel = message.statusLabel {
                        Text(statusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accentColor.opacity(prominentBackground ? 0.18 : 0.12), in: Capsule())
                    }
                }

                Text(message.content)
                    .font(.geeBodyMedium(14))
                    .foregroundStyle(prominentBackground ? .white.opacity(0.94) : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let secondaryContent = message.secondaryContent,
                   !secondaryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(secondaryContent)
                        .font(.caption)
                        .foregroundStyle(prominentBackground ? .white.opacity(0.66) : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                if !message.detailItems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.detailItems) { detail in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(detail.label):")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(prominentBackground ? .white.opacity(0.74) : .secondary)
                                Text(detail.value)
                                    .font(.caption)
                                    .foregroundStyle(prominentBackground ? .white.opacity(0.9) : .primary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var headerSystemImage: String {
        switch message.kind {
        case .chat:
            switch message.role {
            case .user:
                return "person.crop.circle"
            case .assistant:
                return "sparkles"
            case .system:
                return "circle.grid.2x2"
            }
        case .thinking:
            return "brain.head.profile"
        case .action:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .approval:
            return "hand.raised.square.on.square"
        }
    }

    private var headerTint: Color {
        switch message.kind {
        case .chat:
            return .secondary
        case .thinking:
            return .secondary
        case .action, .approval:
            return accentColor
        }
    }

    private var accentColor: Color {
        switch message.tone {
        case .neutral:
            return .secondary
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
}

struct ChatTurnBlockList: View {
    @Bindable var store: WorkbenchStore
    var conversation: ConversationThread
    var maxBlocks: Int? = nil
    var prominentBackground: Bool = false

    private var visibleBlocks: [ConversationTurnBlock] {
        let blocks = conversation.turnBlocks
        guard let maxBlocks, blocks.count > maxBlocks else {
            return blocks
        }
        return Array(blocks.suffix(maxBlocks))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: prominentBackground ? 14 : 18) {
            ForEach(visibleBlocks) { block in
                ChatTurnBlockView(
                    store: store,
                    conversationID: conversation.id,
                    block: block,
                    prominentBackground: prominentBackground
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatTurnBlockView: View {
    @Bindable var store: WorkbenchStore
    var conversationID: ConversationThread.ID
    var block: ConversationTurnBlock
    var prominentBackground: Bool

    fileprivate enum AgentFlowItem: Identifiable {
        case response(ConversationMessage)
        case thinkingGroup([ConversationMessage])
        case activityGroup(AgentActivityGroup)

        var id: String {
            switch self {
            case .response(let message):
                return message.id
            case .thinkingGroup(let messages):
                return messages.map(\.id).joined(separator: "-")
            case .activityGroup(let group):
                return group.id
            }
        }
    }

    private var flowItems: [AgentFlowItem] {
        var items = [AgentFlowItem]()
        var consumedActivityRefs = Set<String>()
        var pendingActivities = [AgentActivityItem]()
        var pendingThinking = [ConversationMessage]()

        func flushPendingActivities(explanation: ConversationMessage? = nil) {
            guard !pendingActivities.isEmpty else {
                return
            }
            items.append(.activityGroup(AgentActivityGroup(items: pendingActivities, explanation: explanation)))
            pendingActivities = []
        }

        func flushPendingThinking() {
            guard !pendingThinking.isEmpty else {
                return
            }
            items.append(.thinkingGroup(pendingThinking))
            pendingThinking = []
        }

        for message in block.agentMessages {
            switch message.kind {
            case .chat:
                flushPendingThinking()
                if pendingActivities.contains(where: \.isApproval),
                   isApprovalExplanation(message) {
                    flushPendingActivities(explanation: message)
                } else {
                    flushPendingActivities()
                    items.append(.response(message))
                }
            case .action:
                flushPendingThinking()
                if !isToolActivityMessage(message) {
                    pendingActivities.append(AgentActivityItem(invocation: message, result: nil, approval: nil))
                    continue
                }
                let ref = message.sourceReferenceID ?? message.id
                guard !consumedActivityRefs.contains(ref) else {
                    continue
                }
                consumedActivityRefs.insert(ref)

                let related = block.agentMessages.filter {
                    $0.kind == .action && isToolActivityMessage($0) && ($0.sourceReferenceID ?? $0.id) == ref
                }
                let invocation = related.first { $0.id.hasPrefix("action-") } ?? message
                let result = related.first { $0.id.hasPrefix("result-") }
                pendingActivities.append(AgentActivityItem(invocation: invocation, result: result, approval: nil))
            case .approval:
                flushPendingThinking()
                pendingActivities.append(AgentActivityItem(invocation: nil, result: nil, approval: message))
            case .thinking:
                flushPendingActivities()
                if !isLowSignalRuntimeThinking(message) {
                    pendingThinking.append(message)
                }
            }
        }

        flushPendingThinking()
        flushPendingActivities()
        return items
    }

    private var visibleFlowItems: [AgentFlowItem] {
        guard shouldFoldWorkTrace else {
            return flowItems
        }

        return Array(flowItems.suffix(1))
    }

    private var workTraceItems: [AgentFlowItem] {
        guard shouldFoldWorkTrace else {
            return []
        }

        return Array(flowItems.dropLast())
    }

    private var shouldFoldWorkTrace: Bool {
        guard flowItems.count > 1, case .response(let message) = flowItems.last else {
            return false
        }
        return message.role == .assistant && message.kind == .chat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: prominentBackground ? 10 : 12) {
            if let userMessage = block.userMessage {
                ChatMessageCard(
                    store: store,
                    conversationID: conversationID,
                    message: userMessage,
                    prominentBackground: prominentBackground
                )
            }

            if !flowItems.isEmpty {
                VStack(alignment: .leading, spacing: prominentBackground ? 8 : 10) {
                    if !workTraceItems.isEmpty {
                        WorkedTraceDisclosure(
                            store: store,
                            conversationID: conversationID,
                            items: workTraceItems,
                            prominentBackground: prominentBackground
                        )
                    }

                    ForEach(visibleFlowItems) { item in
                        flowItemView(item)
                    }
                }
                .padding(.leading, prominentBackground ? 0 : 6)
            }
        }
        .padding(prominentBackground ? .zero : 12)
        .background(blockBackground)
        .overlay(blockBorder)
    }

    private var blockBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(prominentBackground ? Color.clear : Color.white.opacity(0.025))
    }

    private var blockBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(prominentBackground ? Color.clear : Color.white.opacity(0.045), lineWidth: 0.8)
    }

    @ViewBuilder
    fileprivate func flowItemView(_ item: AgentFlowItem) -> some View {
        switch item {
        case .response(let message):
            ChatMessageCard(
                store: store,
                conversationID: conversationID,
                message: message,
                prominentBackground: prominentBackground
            )
        case .thinkingGroup(let messages):
            AgentThinkingDisclosure(
                messages: messages,
                prominentBackground: prominentBackground
            )
        case .activityGroup(let group):
            AgentActivityTraceGroup(
                store: store,
                group: group,
                prominentBackground: prominentBackground
            )
        }
    }
}

private struct WorkedTraceDisclosure: View {
    @Bindable var store: WorkbenchStore
    var conversationID: ConversationThread.ID
    var items: [ChatTurnBlockView.AgentFlowItem]
    var prominentBackground: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(rowTint.opacity(0.72))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Image(systemName: "checklist.checked")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(rowTint.opacity(0.76))

                    Text("Worked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(prominentBackground ? .white.opacity(0.76) : .secondary)

                    Text(workedSummary)
                        .font(.caption)
                        .foregroundStyle(prominentBackground ? .white.opacity(0.5) : .secondary.opacity(0.78))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        flowItemView(item)
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(prominentBackground ? Color.white.opacity(0.025) : Color.black.opacity(0.018))
        )
    }

    private var rowTint: Color {
        prominentBackground ? .white : .secondary
    }

    private var workedSummary: String {
        let count = activityCount(in: items)
        return count == 1 ? "1 step" : "\(count) steps"
    }

    private func activityCount(in items: [ChatTurnBlockView.AgentFlowItem]) -> Int {
        items.reduce(0) { count, item in
            switch item {
            case .response, .thinkingGroup:
                return count + 1
            case .activityGroup(let group):
                return count + group.items.count
            }
        }
    }

    @ViewBuilder
    private func flowItemView(_ item: ChatTurnBlockView.AgentFlowItem) -> some View {
        switch item {
        case .response(let message):
            ChatMessageCard(
                store: store,
                conversationID: conversationID,
                message: message,
                prominentBackground: prominentBackground
            )
        case .thinkingGroup(let messages):
            AgentThinkingDisclosure(
                messages: messages,
                prominentBackground: prominentBackground
            )
        case .activityGroup(let group):
            AgentActivityTraceGroup(
                store: store,
                group: group,
                prominentBackground: prominentBackground
            )
        }
    }
}

private struct AgentActivityItem: Identifiable, Hashable {
    var invocation: ConversationMessage?
    var result: ConversationMessage?
    var approval: ConversationMessage?

    var id: String {
        approval?.id ?? invocation?.sourceReferenceID ?? result?.sourceReferenceID ?? invocation?.id ?? result?.id ?? "activity"
    }

    var displayMessage: ConversationMessage {
        approval ?? result ?? invocation!
    }

    var sourceLabel: String {
        approval?.headerTitle
            ?? invocation?.secondaryContent
            ?? result?.secondaryContent
            ?? result?.headerTitle
            ?? invocation?.headerTitle
            ?? "Tool"
    }

    var summary: String {
        if isSuccessfulResult,
           let invocationSummary = invocation?.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !invocationSummary.isEmpty {
            return invocationSummary
        }
        return displayMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var detailMessages: [ConversationMessage] {
        if isSuccessfulResult, invocation != nil {
            return [invocation, approval].compactMap(\.self)
        }
        return [invocation, result, approval].compactMap(\.self)
    }

    var isApproval: Bool {
        approval != nil
    }

    var isSuccessfulResult: Bool {
        result?.tone == .success
    }
}

private struct AgentActivityGroup: Identifiable, Hashable {
    var items: [AgentActivityItem]
    var explanation: ConversationMessage? = nil

    var id: String {
        (items.map(\.id) + [explanation?.id].compactMap(\.self)).joined(separator: "-")
    }

    var isApprovalGroup: Bool {
        items.contains(where: \.isApproval)
    }
}

private func isApprovalExplanation(_ message: ConversationMessage) -> Bool {
    guard message.role == .assistant, message.kind == .chat else {
        return false
    }

    let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    return content.localizedCaseInsensitiveContains("needs your approval")
        || content.localizedCaseInsensitiveContains("terminal access")
        || content.localizedCaseInsensitiveContains("host decision")
        || content.localizedCaseInsensitiveContains("approval")
}

private func stripHardStageConclusionPrefix(_ content: String) -> String {
    content
        .replacingOccurrences(
            of: #"(?m)^\s*(Stage conclusion|Stage summary)\s*[:：]\s*"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func isLowSignalRuntimeThinking(_ message: ConversationMessage) -> Bool {
    let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    return content.localizedCaseInsensitiveContains("Turn setup complete.")
        || content.localizedCaseInsensitiveContains("delegating this turn into the SDK loop")
        || content.localizedCaseInsensitiveContains("the agent inspected the Gear result and requested another native Gear host action inside the same SDK run")
        || content.localizedCaseInsensitiveContains("the agent requested native Gear host action(s)")
        || content.localizedCaseInsensitiveContains("GeeAgent paused the same SDK run until the macOS host returns structured results")
        || content.localizedCaseInsensitiveContains("the SDK runtime is waiting on native Gear host action results")
        || content.localizedCaseInsensitiveContains("native Gear actions completed; returning structured host results to the SDK runtime")
        || content.localizedCaseInsensitiveContains("the SDK runtime continued after Gear host results and completed the active user turn")
        || content.localizedCaseInsensitiveContains("Turn finalized after")
        || content.localizedCaseInsensitiveContains("the SDK runtime completed")
        || content.localizedCaseInsensitiveContains("the host auto-approved")
        || content.localizedCaseInsensitiveContains("completed the active turn")
        || content.localizedCaseInsensitiveContains("completed the active user turn")
        || content.localizedCaseInsensitiveContains("committed the resulting tool trace")
        || content.localizedCaseInsensitiveContains("committed that failed turn")
        || content.localizedCaseInsensitiveContains("finalized")
}

private func isToolActivityMessage(_ message: ConversationMessage) -> Bool {
    message.id.hasPrefix("action-") || message.id.hasPrefix("result-")
}

private struct AgentThinkingDisclosure: View {
    var messages: [ConversationMessage]
    var prominentBackground: Bool = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(prominentBackground ? .white.opacity(0.66) : .secondary.opacity(0.86))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(prominentBackground ? .white.opacity(0.44) : .secondary.opacity(0.7))

                    Text(thinkingTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(prominentBackground ? .white.opacity(0.72) : .secondary)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(messages) { message in
                        Text(cleanThinkingText(message.content))
                            .font(.caption)
                            .foregroundStyle(prominentBackground ? .white.opacity(0.62) : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(prominentBackground ? Color.white.opacity(0.035) : Color.black.opacity(0.025))
        )
    }

    private var thinkingTitle: String {
        if messages.count == 1,
           let statusLabel = messages.first?.statusLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !statusLabel.isEmpty {
            return "Thinking · \(statusLabel)"
        }
        return messages.count == 1 ? "Thinking" : "Thinking · \(messages.count) steps"
    }

    private func cleanThinkingText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Preparing the agent run."
        }

        if trimmed.localizedCaseInsensitiveContains("delegating this turn") {
            return "Preparing the agent run."
        }
        if trimmed.localizedCaseInsensitiveContains("completed")
            || trimmed.localizedCaseInsensitiveContains("finalized")
            || trimmed.localizedCaseInsensitiveContains("committed") {
            return "Finished the agent run."
        }
        return trimmed
    }
}

private struct AgentActivityTraceGroup: View {
    @Bindable var store: WorkbenchStore
    var group: AgentActivityGroup
    var prominentBackground: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let explanation = group.explanation {
                approvalExplanation(explanation)

                Rectangle()
                    .fill(Color.white.opacity(prominentBackground ? 0.055 : 0.04))
                    .frame(height: 1)
                    .padding(.leading, 10)
            }

            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, activity in
                AgentActivityTraceRow(
                    store: store,
                    activity: activity,
                    prominentBackground: prominentBackground
                )

                if index < group.items.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(prominentBackground ? 0.055 : 0.04))
                        .frame(height: 1)
                        .padding(.leading, 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(prominentBackground ? 0.075 : 0.045), lineWidth: 0.8)
        }
    }

    private var backgroundColor: Color {
        if prominentBackground {
            return group.isApprovalGroup ? Color.orange.opacity(0.13) : Color.white.opacity(0.035)
        }
        return group.isApprovalGroup ? Color.orange.opacity(0.075) : Color.black.opacity(0.025)
    }

    private func approvalExplanation(_ message: ConversationMessage) -> some View {
        ChatMarkdownText(
            content: message.content,
            font: .geeBodyMedium(13),
            lineSpacing: 3,
            color: prominentBackground ? .white.opacity(0.78) : .primary.opacity(0.78)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.orange.opacity(prominentBackground ? 0.13 : 0.08))
        )
        .padding(10)
        .padding(.bottom, -2)
    }
}

private struct AgentActivityTraceRow: View {
    @Bindable var store: WorkbenchStore
    var activity: AgentActivityItem
    var prominentBackground: Bool = false
    @State private var isExpanded = false

    private var message: ConversationMessage {
        activity.displayMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    if !activity.isSuccessfulResult {
                        Image(systemName: message.systemImage ?? fallbackSystemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accentColor.opacity(prominentBackground ? 0.78 : 0.72))
                            .frame(width: 16)
                    }

                    Text(activity.sourceLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(prominentBackground ? .white.opacity(0.74) : .secondary)
                        .lineLimit(1)

                    Text(activity.summary)
                        .font(.caption)
                        .foregroundStyle(prominentBackground ? .white.opacity(0.55) : .secondary.opacity(0.82))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let statusLabel = message.statusLabel, !statusLabel.isEmpty {
                        Text(statusLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accentColor.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accentColor.opacity(prominentBackground ? 0.12 : 0.08), in: Capsule())
                    } else if activity.isSuccessfulResult {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(prominentBackground ? .white.opacity(0.45) : .secondary.opacity(0.62))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(prominentBackground ? .white.opacity(0.36) : .secondary.opacity(0.7))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activity.detailMessages) { detailMessage in
                        activityDetail(detailMessage)
                    }

                    if let approval = activity.approval,
                       let taskID = approval.primaryActionTaskID,
                       let task = store.tasks.first(where: { $0.id == taskID }),
                       !store.taskActions(for: task).isEmpty {
                        approvalActionRow(task: task)
                    }
                }
                .padding(.leading, 25)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onAppear(perform: expandIfApprovalNeedsAction)
        .onChange(of: store.tasks) { _, _ in
            expandIfApprovalNeedsAction()
        }
    }

    private func expandIfApprovalNeedsAction() {
        guard activity.isApproval,
              let taskID = activity.approval?.primaryActionTaskID,
              let task = store.tasks.first(where: { $0.id == taskID }),
              !store.taskActions(for: task).isEmpty
        else {
            return
        }

        isExpanded = true
    }

    private func activityDetail(_ detailMessage: ConversationMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(detailMessage.headerTitle ?? detailMessage.displayTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(prominentBackground ? .white.opacity(0.54) : .secondary)

            Text(detailMessage.content)
                .font(.caption)
                .foregroundStyle(prominentBackground ? .white.opacity(0.72) : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if let secondaryContent = detailMessage.secondaryContent,
               !secondaryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(secondaryContent)
                    .font(.caption2)
                    .foregroundStyle(prominentBackground ? .white.opacity(0.5) : .secondary.opacity(0.78))
                    .textSelection(.enabled)
            }

            if !detailMessage.detailItems.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(detailMessage.detailItems) { detail in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(detail.label):")
                                .font(.caption2.weight(.semibold))
                            Text(detail.value)
                                .font(.caption2)
                        }
                        .foregroundStyle(prominentBackground ? .white.opacity(0.62) : .secondary)
                    }
                }
            }
        }
    }

    private func approvalActionRow(task: WorkbenchTaskRecord) -> some View {
        HStack(spacing: 8) {
            ForEach(store.taskActions(for: task), id: \.self) { action in
                if action == .deny {
                    approvalDenyButton(action, taskID: task.id)
                } else {
                    approvalPrimaryButton(action, taskID: task.id)
                }
            }
        }
    }

    private func approvalPrimaryButton(
        _ action: WorkbenchTaskAction,
        taskID: WorkbenchTaskRecord.ID
    ) -> some View {
        Button {
            store.performTaskAction(action, taskID: taskID, openSection: false)
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(store.isPerformingTaskAction)
    }

    private func approvalDenyButton(
        _ action: WorkbenchTaskAction,
        taskID: WorkbenchTaskRecord.ID
    ) -> some View {
        Button {
            store.performTaskAction(action, taskID: taskID, openSection: false)
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.red)
        .disabled(store.isPerformingTaskAction)
    }

    private var fallbackSystemImage: String {
        activity.isApproval ? "hand.raised.fill" : "terminal"
    }

    private var accentColor: Color {
        switch message.tone {
        case .neutral:
            return .secondary
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
}

struct TransientAgentActivityCard: View {
    var label: String
    var prominentBackground: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text(label)
                .font(.caption)
                .foregroundStyle(prominentBackground ? .white.opacity(0.72) : .secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(prominentBackground ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(prominentBackground ? 0.08 : 0.05), lineWidth: 0.8)
        }
    }
}
