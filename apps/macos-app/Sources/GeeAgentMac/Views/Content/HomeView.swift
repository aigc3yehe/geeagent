import AppKit
import SwiftUI

struct HomeView: View {
    @Bindable var store: WorkbenchStore
    @State private var draftMessage = ""
    @State private var editingConversationTitle = false
    @State private var editedConversationTitle = ""
    @State private var pendingDraftRecovery: String?
    @State private var isChatLauncherHovering = false
    @State private var isDisplayModeSwitcherHovering = false
    @State private var chatLauncherDragTranslation: CGSize = .zero
    @AppStorage("geeagent.home.chatLauncher.position") private var storedChatLauncherPosition = ""
    @AppStorage("geeagent.home.widget.positions") private var storedHomeWidgetPositions = "{}"
    @FocusState private var launcherComposerFocused: Bool
    @FocusState private var chatComposerFocused: Bool
    @FocusState private var chatTitleFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                companionCanvas(in: proxy.size)
                    .opacity(store.homeSurfaceMode.isFocused ? 0.32 : 1)
                    .scaleEffect(store.homeSurfaceMode.isFocused ? 0.98 : 1, anchor: .center)
                    .allowsHitTesting(!store.homeSurfaceMode.isFocused)
                    .animation(.spring(response: 0.34, dampingFraction: 0.88), value: store.homeSurfaceMode)

                if !store.homeSurfaceMode.isFocused {
                    homeTopRightOverlay(in: proxy.size)
                        .zIndex(3)
                }

                if store.homeSurfaceMode.isFocused {
                    focusMask
                        .transition(.opacity)
                        .zIndex(1)

                    focusOverlay(in: proxy.size)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                        .zIndex(2)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onChange(of: store.homeSurfaceMode) { _, newValue in
            guard newValue == .chatFocus else { return }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(230))
                guard store.homeSurfaceMode == .chatFocus else { return }
                chatComposerFocused = true
            }
        }
        .onChange(of: store.selectedConversationID) { _, _ in
            syncConversationTitleDraft()
            store.activateSelectedConversation()
        }
        .onAppear {
            syncConversationTitleDraft()
        }
        .onChange(of: store.lastErrorMessage) { _, newValue in
            guard newValue != nil, let pendingDraftRecovery, draftMessage.isEmpty else {
                return
            }

            draftMessage = pendingDraftRecovery
            self.pendingDraftRecovery = nil
        }
        .onChange(of: store.isSendingMessage) { _, isSending in
            if !isSending, store.lastErrorMessage == nil {
                pendingDraftRecovery = nil
            }
        }
    }

    @ViewBuilder
    private func companionCanvas(in size: CGSize) -> some View {
        let metrics = HomeCanvasMetrics(size: size)

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    launcherComposerFocused = false
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }

            ambientBrandBlock(fontSize: metrics.logoSize)
                .padding(.leading, metrics.leadingInset)
                .padding(.top, metrics.logoTopInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if shouldShowLive2DInteractionSurface {
                Live2DInteractionSurface(
                    viewportState: store.live2DViewportState,
                    catalog: store.live2DActionCatalog,
                    activePosePath: store.activeLive2DPosePath,
                    activeExpressionPath: store.selectedLive2DExpression?.relativePath,
                    onPrimaryClick: { store.triggerRandomLive2DReaction() },
                    onSelectPose: { store.setLive2DPose($0) },
                    onSelectExpression: { store.setLive2DExpression($0) },
                    onPlayAction: { store.triggerLive2DAction($0) },
                    onResetExpression: { store.resetLive2DExpression() },
                    onDrag: { store.translateLive2D(by: $0) },
                    onScale: { store.adjustLive2DScale(by: $0) },
                    onResetViewport: { store.resetLive2DViewport() },
                    excludedHitTestRects: live2DExcludedHitTestRects(in: size, chatLauncherWidth: metrics.chatLauncherWidth)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1.5)
            }

            HomeWidgetLayer(widgets: homeWidgets, canvasSize: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1)

            chatLauncher(width: metrics.chatLauncherWidth, compactLayout: metrics.compactLauncherLayout)
                .position(chatLauncherDisplayPosition(in: size, width: metrics.chatLauncherWidth))
                .gesture(chatLauncherDragGesture(in: size, width: metrics.chatLauncherWidth))
                .zIndex(chatLauncherDragTranslation == .zero ? 2 : 6)
        }
    }

    private var homeWidgets: [InstalledAppRecord] {
        store.installedApps.filter {
            $0.isGearPackage
                && $0.gearKind == .widget
                && $0.installState == .installed
                && GearHost.isEnabled(gearID: $0.id)
        }
    }

    private var shouldShowLive2DInteractionSurface: Bool {
        guard case .live2D = store.effectiveActiveAppearance else { return false }
        return true
    }

    private func ambientLogo(fontSize: CGFloat) -> some View {
        HomeReactiveLogo(fontSize: fontSize, enabled: !store.homeSurfaceMode.isFocused)
    }

    private func ambientBrandBlock(fontSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ambientLogo(fontSize: fontSize)
            ambientTimeDisplay
                .padding(.leading, fontSize * 0.11)
        }
    }

    private func homeTopRightOverlay(in size: CGSize) -> some View {
        let metrics = HomeCanvasMetrics(size: size)
        let trailingInset = max(metrics.contentTrailingInset - 6, 20)

        return ZStack(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                homeDisplayModeSwitcher
                    .opacity(isDisplayModeSwitcherHovering ? 1 : 0)
                    .offset(y: isDisplayModeSwitcherHovering ? 0 : -8)
                    .allowsHitTesting(isDisplayModeSwitcherHovering)
            }
                .frame(
                    width: HomeDisplayModeSwitcherMetrics.activationWidth,
                    height: HomeDisplayModeSwitcherMetrics.activationHeight
                )
                .contentShape(Rectangle())
                .onHover { isHovering in
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        isDisplayModeSwitcherHovering = isHovering
                    }
                }
        }
        .padding(.top, HomeDisplayModeSwitcherMetrics.topInset)
        .padding(.trailing, trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var homeDisplayModeSwitcher: some View {
        HStack(spacing: 8) {
            if !store.availableHomeAppearanceKinds.isEmpty {
                homeAgentAppearanceSwitcher
                Divider()
                    .frame(height: 20)
                    .overlay(Color.white.opacity(0.16))
            }

            ForEach(HomeVisualEffectMode.allCases) { mode in
                Button {
                    store.setHomeVisualEffectMode(mode)
                } label: {
                    Image(systemName: mode.homeSwitcherSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(store.homeVisualEffectMode == mode ? 0.96 : 0.72))
                        .frame(width: 28, height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(store.homeVisualEffectMode == mode ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(mode.homeSwitcherHelpText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial.opacity(0.92), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.9)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Switch display mode")
    }

    private var homeAgentAppearanceSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(store.availableHomeAppearanceKinds) { kind in
                Button {
                    store.setActiveAppearanceKind(kind)
                } label: {
                    Image(systemName: kind.homeAppearanceSwitcherSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(store.effectiveActiveAppearance.kind == kind ? 0.96 : 0.72))
                        .frame(width: 28, height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(store.effectiveActiveAppearance.kind == kind ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(kind.homeAppearanceSwitcherHelpText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Switch agent visual")
    }

    private func logoGlyph(fontSize: CGFloat) -> Text {
        Text("Gee")
            .font(.geeDisplay(fontSize))
            .italic()
            .tracking(fontSize * -0.048)
    }

    private var ambientTimeDisplay: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(
                context.date,
                format: .dateTime
                    .hour(.twoDigits(amPM: .omitted))
                    .minute(.twoDigits)
                    .second(.twoDigits)
            )
            .font(.system(size: 34, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.66))
        }
    }

    private func chatLauncher(width: CGFloat, compactLayout: Bool) -> some View {
        let cardPadding = width < 320 ? CGFloat(10) : CGFloat(12)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 18, height: 18)

                conversationSummaryArea
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                store.openHomeChatFocus()
            }
            .help("Open focused chat")

            launcherControls(compactLayout: compactLayout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.001))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            // Absorb taps on the launcher chrome so they do not fall through to Live2D.
        }
        .glassCard(
            cornerRadius: 10,
            darken: isChatLauncherHovering ? 0.26 : 0.08,
            materialOpacity: isChatLauncherHovering ? 0.78 : 0.38
        )
        .homeBorderGlow(
            cornerRadius: 10,
            glowRadius: 36,
            edgeSensitivity: 34,
            enabled: !store.homeSurfaceMode.isFocused
        )
        .animation(.easeInOut(duration: 0.2), value: isChatLauncherHovering)
        .frame(width: width, alignment: .trailing)
        .overlay(alignment: .topTrailing) {
            if store.runtimeStatus.state == .live {
                EmptyView()
            } else {
                statusPill(text: store.runtimeStatus.state.title.uppercased(), tint: .orange.opacity(0.18))
                    .padding(10)
            }
        }
        .onHover { isChatLauncherHovering = $0 }
    }

    private func chatLauncherDragGesture(in size: CGSize, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                chatLauncherDragTranslation = value.translation
            }
            .onEnded { value in
                let base = storedChatLauncherBasePosition(in: size, width: width)
                let next = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                storedChatLauncherPosition = encodeChatLauncherPosition(clampedChatLauncherPosition(next, in: size, width: width))
                chatLauncherDragTranslation = .zero
            }
    }

    private func chatLauncherDisplayPosition(in size: CGSize, width: CGFloat) -> CGPoint {
        let base = storedChatLauncherBasePosition(in: size, width: width)
        return clampedChatLauncherPosition(
            CGPoint(x: base.x + chatLauncherDragTranslation.width, y: base.y + chatLauncherDragTranslation.height),
            in: size,
            width: width
        )
    }

    private func storedChatLauncherBasePosition(in size: CGSize, width: CGFloat) -> CGPoint {
        if let point = decodedChatLauncherPosition()?.cgPoint {
            return clampedChatLauncherPosition(point, in: size, width: width)
        }

        return defaultChatLauncherPosition(in: size, width: width)
    }

    private func defaultChatLauncherPosition(in size: CGSize, width: CGFloat) -> CGPoint {
        let metrics = HomeCanvasMetrics(size: size)
        let approximateHeight = chatLauncherApproximateHeight(compactLayout: metrics.compactLauncherLayout)
        return clampedChatLauncherPosition(
            CGPoint(
                x: size.width - metrics.contentTrailingInset - width / 2,
                y: size.height - metrics.bottomInset - approximateHeight / 2
            ),
            in: size,
            width: width
        )
    }

    private func live2DExcludedHitTestRects(in size: CGSize, chatLauncherWidth: CGFloat) -> [CGRect] {
        let metrics = HomeCanvasMetrics(size: size)
        let chatCenter = chatLauncherDisplayPosition(in: size, width: chatLauncherWidth)
        let chatHeight = chatLauncherApproximateHeight(compactLayout: metrics.compactLauncherLayout)
        var rects = [
            CGRect(
                x: chatCenter.x - chatLauncherWidth / 2,
                y: chatCenter.y - chatHeight / 2,
                width: chatLauncherWidth,
                height: chatHeight
            ).insetBy(dx: -8, dy: -8)
        ]

        rects.append(contentsOf: homeWidgetHitTestRects(in: size))
        return rects
    }

    private func homeWidgetHitTestRects(in size: CGSize) -> [CGRect] {
        homeWidgets.map { widget in
            let center = homeWidgetStoredPosition(for: widget, in: size)
            return CGRect(x: center.x - 115, y: center.y - 59, width: 230, height: 118)
                .insetBy(dx: -8, dy: -8)
        }
    }

    private func homeWidgetStoredPosition(for widget: InstalledAppRecord, in size: CGSize) -> CGPoint {
        if let point = decodedHomeWidgetPositions()[widget.id]?.cgPoint {
            return clampedHomeWidgetPosition(point, in: size)
        }
        return defaultHomeWidgetPosition(for: widget, in: size)
    }

    private func defaultHomeWidgetPosition(for widget: InstalledAppRecord, in size: CGSize) -> CGPoint {
        let y = min(max(size.height * 0.34, 190), size.height - 160)
        switch widget.id {
        case "btc.price":
            return clampedHomeWidgetPosition(CGPoint(x: min(max(size.width * 0.34, 280), size.width - 160), y: y), in: size)
        case "system.monitor":
            return clampedHomeWidgetPosition(CGPoint(x: min(max(size.width * 0.54, 530), size.width - 160), y: y + 18), in: size)
        default:
            return clampedHomeWidgetPosition(CGPoint(x: size.width * 0.44, y: y + 32), in: size)
        }
    }

    private func clampedHomeWidgetPosition(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 128), max(size.width - 128, 128)),
            y: min(max(point.y, 92), max(size.height - 92, 92))
        )
    }

    private func decodedHomeWidgetPositions() -> [String: HomeStoredPoint] {
        guard let data = storedHomeWidgetPositions.data(using: .utf8),
              let positions = try? JSONDecoder().decode([String: HomeStoredPoint].self, from: data)
        else {
            return [:]
        }
        return positions
    }

    private func chatLauncherApproximateHeight(compactLayout: Bool) -> CGFloat {
        compactLayout ? 122 : 138
    }

    private func clampedChatLauncherPosition(_ point: CGPoint, in size: CGSize, width: CGFloat) -> CGPoint {
        let horizontalMargin = min(width / 2 + 12, max(size.width / 2, 12))
        let verticalMargin: CGFloat = 72

        return CGPoint(
            x: min(max(point.x, horizontalMargin), max(size.width - horizontalMargin, horizontalMargin)),
            y: min(max(point.y, verticalMargin), max(size.height - verticalMargin, verticalMargin))
        )
    }

    private func decodedChatLauncherPosition() -> HomeStoredPoint? {
        guard let data = storedChatLauncherPosition.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(HomeStoredPoint.self, from: data)
    }

    private func encodeChatLauncherPosition(_ point: CGPoint) -> String {
        guard let data = try? JSONEncoder().encode(HomeStoredPoint(point)),
              let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }

    @ViewBuilder
    private func launcherControls(compactLayout: Bool) -> some View {
        inlineChatPrompt
            .frame(maxWidth: .infinity)
    }

    private var inlineChatPrompt: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $draftMessage,
                prompt: Text("Type to continue in focused chat").foregroundStyle(.white.opacity(0.46))
            )
            .textFieldStyle(.plain)
            .font(.geeBodyMedium(13))
            .foregroundStyle(.white.opacity(0.92))
            .focused($launcherComposerFocused)
            .onSubmit {
                sendInlineHomeChatMessage()
            }

            Button {
                store.openHomeChatFocus()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Open focused chat")
        }
        .frame(height: 34)
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .background(Color.black.opacity(0.18), in: Capsule())
    }

    private var conversationSummaryArea: some View {
        conversationSummaryContent
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var conversationSummaryContent: some View {
        Group {
            if store.isSendingMessage {
                ThinkingGradientText(text: "Agent is thinking…")
                    .font(.geeBodyMedium(15))
            } else {
                ChatMarkdownText(
                    content: homeConversationSummaryText,
                    font: .geeBody(14),
                    lineSpacing: 4,
                    color: .white.opacity(0.74),
                    textSelectionEnabled: false
                )
            }
        }
        .lineLimit(2)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var focusMask: some View {
        Rectangle()
            .fill(Color.black.opacity(0.26))
            .background(.regularMaterial.opacity(0.12))
            .padding(-120)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func focusOverlay(in size: CGSize) -> some View {
        let metrics = HomeFocusOverlayMetrics(size: size)

        switch store.homeSurfaceMode {
        case .companion:
            EmptyView()
        case .chatFocus:
            homeChatPanel(width: metrics.chatPanelWidth, height: metrics.chatPanelHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .taskFocus:
            homeTaskPanel(width: metrics.taskPanelWidth, height: metrics.taskPanelHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func homeChatPanel(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            homeChatHeader

            runtimeBanner

            if let conversation = store.selectedDisplayConversation {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ChatTurnBlockList(
                                store: store,
                                conversation: conversation,
                                maxBlocks: 3,
                                prominentBackground: true
                            )

                            Color.clear
                                .frame(height: 1)
                                .id(homeChatBottomID(for: conversation))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .thinScrollIndicator()
                    .onAppear {
                        scrollHomeChatToBottom(scrollProxy, conversation: conversation, animated: false)
                    }
                    .onChange(of: conversationMessageIDs(conversation)) { _, _ in
                        scrollHomeChatToBottom(scrollProxy, conversation: conversation)
                    }
                    .onChange(of: store.isSendingMessage) { _, _ in
                        scrollHomeChatToBottom(scrollProxy, conversation: conversation)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No conversation yet.")
                        .font(.geeDisplaySemibold(20))
                        .foregroundStyle(.white.opacity(0.92))

                    Button {
                        store.createConversation(openSection: false)
                    } label: {
                        Label("New Conversation", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isCreatingConversation || !store.canCreateConversation)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            HStack(spacing: 8) {
                TextField("Ask GeeAgent…", text: $draftMessage)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white.opacity(0.94))
                    .focused($chatComposerFocused)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )

                ContextBudgetIndicator(budget: store.contextBudget)

                Button {
                    sendHomeChatMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(
                    store.isSendingMessage ||
                    draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    !store.canSendMessages
                )
            }
            .onSubmit(sendHomeChatMessage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .frame(width: width, height: height, alignment: .topLeading)
        .glassCard(cornerRadius: 12, darken: 0.3)
        .shadow(color: .black.opacity(0.38), radius: 16, x: 0, y: 10)
    }

    private func homeTaskPanel(width: CGFloat, height: CGFloat) -> some View {
        let usesStackedLayout = height < 470 || width < 760

        return Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: 14) {
                    homeTaskQueueColumn
                        .frame(maxWidth: .infinity, maxHeight: min(height * 0.42, 240), alignment: .topLeading)

                    Divider()
                        .overlay(Color.white.opacity(0.1))

                    homeTaskDetailColumn(compactLayout: true)
                }
            } else {
                HStack(spacing: 18) {
                    homeTaskQueueColumn
                        .frame(width: min(width * 0.38, 330), alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .topLeading)

                    Divider()
                        .overlay(Color.white.opacity(0.1))

                    homeTaskDetailColumn(compactLayout: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(HomeFocusPanelChrome.contentInsets)
        .frame(width: width, height: height, alignment: .topLeading)
        .glassCard(cornerRadius: 12, darken: 0.28)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                iconChromeButton(systemImage: "arrow.up.forward", help: "Open full tasks") {
                    store.openSection(.logs)
                }
                closeButton
            }
            .padding(HomeFocusPanelChrome.closeButtonInset)
        }
        .shadow(color: .black.opacity(0.38), radius: 16, x: 0, y: 10)
    }

    private var homeTaskQueueColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            focusHeader(title: "Task Queue")

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(prioritizedTasks.prefix(6)) { task in
                        Button {
                            store.selectedTaskID = task.id
                        } label: {
                            HomeTaskListRow(task: task, isSelected: task.id == store.selectedTaskID)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .suppressSystemScrollbars()

            statusPill(text: taskStatusSummary, tint: .white.opacity(0.08))
        }
    }

    @ViewBuilder
    private func homeTaskDetailColumn(compactLayout: Bool) -> some View {
        if let task = store.selectedTask ?? prioritizedTasks.first {
            ScrollView {
                VStack(alignment: .leading, spacing: compactLayout ? 14 : 18) {
                    Text(task.title)
                        .font(.geeDisplay(compactLayout ? 24 : 30))
                        .foregroundStyle(.white.opacity(0.96))
                        .fixedSize(horizontal: false, vertical: true)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            statusPill(text: task.status.title.uppercased(), tint: taskTint(for: task).opacity(0.18))
                            statusPill(text: task.priorityLabel.uppercased(), tint: .white.opacity(0.08))
                            statusPill(text: task.appName.uppercased(), tint: .white.opacity(0.08))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            statusPill(text: task.status.title.uppercased(), tint: taskTint(for: task).opacity(0.18))
                            statusPill(text: task.priorityLabel.uppercased(), tint: .white.opacity(0.08))
                            statusPill(text: task.appName.uppercased(), tint: .white.opacity(0.08))
                        }
                    }

                    Text(task.summary)
                        .font(.geeBody(15))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)

                    if !store.selectedTaskActions.isEmpty {
                        approvalActionColumn
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .suppressSystemScrollbars()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView(
                "No active tasks",
                systemImage: "checklist",
                description: Text("Tasks will appear here when the queue starts moving.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var approvalActionColumn: some View {
        VStack(spacing: 10) {
            ForEach(store.selectedTaskActions, id: \.self) { action in
                if action == .deny {
                    Button {
                        store.performSelectedTaskAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(store.isPerformingTaskAction)
                } else {
                    Button {
                        store.performSelectedTaskAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(store.isPerformingTaskAction)
                }
            }
        }
    }

    @ViewBuilder
    private var runtimeBanner: some View {
        switch store.runtimeStatus.state {
        case .live:
            EmptyView()
        case .needsSetup, .degraded, .unavailable:
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.runtimeStatus.state.title)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))

                    Text(store.runtimeStatus.detail)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.66))
                }

                Spacer()

                Button("Settings") {
                    store.openSection(.settings)
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var homeChatHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if editingConversationTitle {
                    TextField("Conversation", text: $editedConversationTitle)
                        .textFieldStyle(.plain)
                        .font(.geeDisplay(34))
                        .foregroundStyle(.white.opacity(0.96))
                        .focused($chatTitleFocused)
                        .onSubmit(saveConversationTitle)
                        .onChange(of: chatTitleFocused) { _, isFocused in
                            if !isFocused && editingConversationTitle {
                                saveConversationTitle()
                            }
                        }
                } else {
                    Text(displayConversationTitle)
                        .font(.geeDisplay(34))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)
                        .onTapGesture {
                            editingConversationTitle = true
                            chatTitleFocused = true
                        }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                iconChromeButton(systemImage: "arrow.up.forward", help: "Open full chat") {
                    store.openSection(.chat)
                }

                closeButton
            }
        }
    }

    private func focusHeader(title: String) -> some View {
        Text(title)
            .font(.geeDisplay(34))
            .foregroundStyle(.white.opacity(0.96))
    }

    private var closeButton: some View {
        iconChromeButton(systemImage: "xmark", help: "Close focused surface") {
            store.closeHomeFocus()
        }
    }

    private func statusPill(text: String, tint: Color) -> some View {
            Text(text)
            .font(.geeDisplaySemibold(11))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint, in: Capsule())
            .foregroundStyle(.white.opacity(0.74))
    }

    private func iconChromeButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var activeTasks: [WorkbenchTaskRecord] {
        prioritizedTasks.filter { $0.status != .completed }
    }

    private var prioritizedTasks: [WorkbenchTaskRecord] {
        store.tasks.sorted { left, right in
            taskSortOrder(left.status) < taskSortOrder(right.status)
        }
    }

    private var selectedConversationTitle: String {
        store.selectedDisplayConversation?.displayTitle ?? "No Active Conversation"
    }

    private var displayConversationTitle: String {
        let trimmed = selectedConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Conversation"
        }

        if trimmed.lowercased().hasPrefix("new conversation") {
            return "Conversation"
        }

        return trimmed
    }

    private var homeConversationSummaryText: String {
        guard let conversation = store.selectedDisplayConversation else {
            return ""
        }

        if let assistantMessage = conversation.visibleMessages.last(where: { $0.role == .assistant && $0.kind == .chat })?.content,
           !assistantMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return assistantMessage
        }

        return ""
    }

    private func conversationMessageIDs(_ conversation: ConversationThread) -> [String] {
        conversation.visibleMessages.map(\.id)
    }

    private func homeChatBottomID(for conversation: ConversationThread) -> String {
        "home-chat-bottom-\(conversation.id)"
    }

    private func scrollHomeChatToBottom(
        _ proxy: ScrollViewProxy,
        conversation: ConversationThread,
        animated: Bool = true
    ) {
        let bottomID = homeChatBottomID(for: conversation)
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

    private var taskStatusSummary: String {
        let approvals = store.tasks(for: .needsApproval).count
        let blocked = store.tasks(for: .blocked).count + store.tasks(for: .failed).count
        if approvals > 0 {
            return "\(approvals) waiting review"
        }
        if blocked > 0 {
            return "\(blocked) need recovery"
        }
        return "\(activeTasks.count) active now"
    }

    private func taskSortOrder(_ status: WorkbenchTaskStatus) -> Int {
        switch status {
        case .needsApproval:
            0
        case .blocked:
            1
        case .failed:
            2
        case .running:
            3
        case .queued:
            4
        case .completed:
            5
        }
    }

    private func taskTint(for task: WorkbenchTaskRecord) -> Color {
        switch task.status {
        case .needsApproval:
            .orange
        case .blocked, .failed:
            .red
        case .running:
            .blue
        case .queued:
            .white
        case .completed:
            .green
        }
    }

    private func sendHomeChatMessage() {
        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return
        }

        pendingDraftRecovery = message
        draftMessage = ""
        store.sendMessage(message, openSection: false)
    }

    private func sendInlineHomeChatMessage() {
        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return
        }

        pendingDraftRecovery = message
        draftMessage = ""
        launcherComposerFocused = false
        store.sendMessage(message, openSection: false)
    }

    private func saveConversationTitle() {
        let trimmed = editedConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.renameSelectedConversation(trimmed)
            editedConversationTitle = trimmed
        } else {
            editedConversationTitle = displayConversationTitle
        }

        editingConversationTitle = false
        chatTitleFocused = false
    }

    private func syncConversationTitleDraft() {
        editedConversationTitle = displayConversationTitle
    }
}

private struct HomeCanvasMetrics {
    let size: CGSize
    private let navRailWidth: CGFloat = 78
    private let navRailTrailingInset: CGFloat = 24
    private let navRailBuffer: CGFloat = 12

    var compactHeight: Bool { size.height < 760 }
    var compactWidth: Bool { size.width < 1220 }
    var compactLauncherLayout: Bool { size.width < 1040 || size.height < 700 }

    var logoSize: CGFloat {
        if compactHeight { return min(max(size.width * 0.1, 118), 144) }
        return min(max(size.width * 0.11, 138), 178)
    }

    var leadingInset: CGFloat {
        compactWidth ? 20 : min(max(size.width * 0.026, 24), 44)
    }

    var logoTopInset: CGFloat {
        compactHeight ? -2 : 2
    }

    var bottomInset: CGFloat {
        compactHeight ? 16 : 24
    }

    var trailingInset: CGFloat {
        compactWidth ? 20 : 28
    }

    var navRailReserve: CGFloat {
        navRailWidth + navRailTrailingInset + navRailBuffer
    }

    var contentTrailingInset: CGFloat {
        trailingInset + navRailReserve
    }

    private var availableCardWidth: CGFloat {
        max(size.width - leadingInset - contentTrailingInset, 220)
    }

    var chatLauncherWidth: CGFloat {
        min(max(availableCardWidth * 0.88, compactLauncherLayout ? 260 : 320), min(620, availableCardWidth))
    }
}

private enum HomeDisplayModeSwitcherMetrics {
    static let topInset: CGFloat = 18
    static let activationWidth: CGFloat = 286
    static let activationHeight: CGFloat = 76
}

private struct HomeFocusOverlayMetrics {
    let size: CGSize

    private var horizontalInset: CGFloat {
        size.width < 820 ? 16 : 24
    }

    private var verticalInset: CGFloat {
        size.height < 560 ? 14 : 22
    }

    var chatPanelWidth: CGFloat {
        min(max(size.width - horizontalInset * 2, 420), 860)
    }

    var chatPanelHeight: CGFloat {
        min(max(size.height * 0.9, 320), max(size.height - verticalInset * 2, 320))
    }

    var taskPanelWidth: CGFloat {
        min(max(size.width - horizontalInset * 2, 520), 980)
    }

    var taskPanelHeight: CGFloat {
        min(max(size.height - verticalInset * 2, 360), 700)
    }
}

private struct HomeStoredPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

private struct HomeGlowState {
    var pointerLocation: CGPoint = .zero
    var proximity: CGFloat = 0
}

private enum HomeFocusPanelChrome {
    static let edgeInset: CGFloat = 14
    static let closeButtonInset: CGFloat = 12
    static let closeButtonSize: CGFloat = 26
    static let closeButtonGap: CGFloat = 8

    static var contentInsets: EdgeInsets {
        EdgeInsets(
            top: closeButtonInset + closeButtonSize + closeButtonGap,
            leading: edgeInset,
            bottom: edgeInset,
            trailing: closeButtonInset + closeButtonSize + closeButtonGap
        )
    }
}

private struct HomeReactiveLogo: View {
    var fontSize: CGFloat
    var enabled: Bool

    @State private var containerSize: CGSize = .zero
    @State private var glowState = HomeGlowState()

    private var glyph: Text {
        Text("Gee")
            .font(.geeDisplay(fontSize))
            .italic()
            .tracking(fontSize * -0.048)
    }

    var body: some View {
        let glowColors = [
            Color(red: 0.75, green: 0.52, blue: 0.99),
            Color(red: 0.96, green: 0.45, blue: 0.71),
            Color(red: 0.22, green: 0.74, blue: 0.97)
        ]

        return glyph
            .foregroundStyle(.clear)
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        Color.white.opacity(0.68),
                        Color.white.opacity(0.26)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .mask(glyph)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.82),
                        Color.white.opacity(0.18),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                .mask(glyph)
                .blendMode(.screen)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        Color.clear,
                        Color.black.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .offset(x: 0.6, y: 0.9)
                .mask(glyph)
                .blur(radius: 0.2)
            }
            .overlay {
                GeometryReader { proxy in
                    let glow = HomeGlowField(
                        location: glowState.pointerLocation,
                        size: proxy.size,
                        colors: glowColors,
                        radius: max(proxy.size.width * 0.18, 58)
                    )

                    ZStack {
                        glow
                            .mask(glyph)
                            .opacity(Double(glowState.proximity) * 0.34)
                            .blendMode(.screen)

                        glow
                            .blur(radius: 6)
                            .mask(glyph)
                            .opacity(Double(glowState.proximity) * 0.1)
                            .blendMode(.screen)
                    }
                    .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 4)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            containerSize = proxy.size
                            if glowState.pointerLocation == .zero {
                                glowState.pointerLocation = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.38)
                            }
                        }
                        .onChange(of: proxy.size) { _, newValue in
                            containerSize = newValue
                            if glowState.pointerLocation == .zero {
                                glowState.pointerLocation = CGPoint(x: newValue.width * 0.5, y: newValue.height * 0.38)
                            }
                        }
                }
            )
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard enabled else { return }

                switch phase {
                case .active(let location):
                    withAnimation(.easeOut(duration: 0.12)) {
                        glowState.pointerLocation = location
                        glowState.proximity = homeGlowProximity(
                            for: location,
                            in: containerSize,
                            edgeSensitivity: 36
                        )
                    }
                case .ended:
                    withAnimation(.easeOut(duration: 0.28)) {
                        glowState.proximity = 0
                    }
                }
            }
            .onChange(of: enabled) { _, newValue in
                guard !newValue else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    glowState.proximity = 0
                }
            }
    }
}

private struct ThinkingGradientText: View {
    var text: String

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate

            Text(text)
                .foregroundStyle(.clear)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(red: 0.76, green: 0.82, blue: 1.0),
                            Color(red: 0.95, green: 0.59, blue: 0.86),
                            Color(red: 0.44, green: 0.86, blue: 0.98),
                            Color(red: 0.76, green: 0.82, blue: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .hueRotation(.degrees((phase * 38).truncatingRemainder(dividingBy: 360)))
                    .mask(Text(text))
                }
                .opacity(0.96)
        }
    }
}

private struct HomeTaskListRow: View {
    var task: WorkbenchTaskRecord
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.title)
                    .font(.geeBodyMedium(15))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Spacer()

                Text(task.status.shortTitle.uppercased())
                    .font(.geeDisplaySemibold(10))
                    .foregroundStyle(.white.opacity(0.52))
            }

            Text(task.summary)
                .font(.geeBody(12))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.black.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.14 : 0.05), lineWidth: 1)
                )
        )
    }
}


extension View {
    func homeBorderGlow(
        cornerRadius: CGFloat,
        glowRadius: CGFloat = 36,
        edgeSensitivity: CGFloat = 30,
        enabled: Bool = true,
        colors: [Color] = [
            Color(red: 0.75, green: 0.52, blue: 0.99),
            Color(red: 0.96, green: 0.45, blue: 0.71),
            Color(red: 0.22, green: 0.74, blue: 0.97)
        ]
    ) -> some View {
        modifier(
            HomeBorderGlowModifier(
                cornerRadius: cornerRadius,
                glowRadius: glowRadius,
                edgeSensitivity: edgeSensitivity,
                enabled: enabled,
                colors: colors
            )
        )
    }

    func thinScrollIndicator() -> some View {
        modifier(ThinScrollIndicatorModifier())
    }

    func suppressSystemScrollbars() -> some View {
        background(SystemScrollbarHider())
    }

    func glassCard(
        cornerRadius: CGFloat,
        darken: Double = 0.2,
        materialOpacity: Double = 0.78
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(darken))
        )
        .background(
            .ultraThinMaterial.opacity(materialOpacity),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.clear, Color.black.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.9)
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: max(cornerRadius - 1, 0), style: .continuous)
                .inset(by: 1)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.6)
                .allowsHitTesting(false)
        )
    }
}

private struct HomeBorderGlowModifier: ViewModifier {
    var cornerRadius: CGFloat
    var glowRadius: CGFloat
    var edgeSensitivity: CGFloat
    var enabled: Bool
    var colors: [Color]

    @State private var containerSize: CGSize = .zero
    @State private var glowState = HomeGlowState()

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            containerSize = proxy.size
                            if glowState.pointerLocation == .zero {
                                glowState.pointerLocation = CGPoint(x: proxy.size.width * 0.74, y: proxy.size.height * 0.22)
                            }
                        }
                        .onChange(of: proxy.size) { _, newValue in
                            containerSize = newValue
                            if glowState.pointerLocation == .zero {
                                glowState.pointerLocation = CGPoint(x: newValue.width * 0.74, y: newValue.height * 0.22)
                            }
                        }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard enabled else { return }

                switch phase {
                case .active(let location):
                    withAnimation(.easeOut(duration: 0.12)) {
                        glowState.pointerLocation = location
                        glowState.proximity = homeGlowProximity(
                            for: location,
                            in: containerSize,
                            edgeSensitivity: edgeSensitivity
                        )
                    }
                case .ended:
                    withAnimation(.easeOut(duration: 0.28)) {
                        glowState.proximity = 0
                    }
                }
            }
            .onChange(of: enabled) { _, newValue in
                guard !newValue else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    glowState.proximity = 0
                }
            }
            .overlay {
                GeometryReader { proxy in
                    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    let glow = HomeGlowField(
                        location: glowState.pointerLocation,
                        size: proxy.size,
                        colors: colors,
                        radius: max(glowRadius * 0.72, 18)
                    )

                    ZStack {
                        glow
                            .mask(shape.inset(by: 1).stroke(lineWidth: 9))
                            .opacity(Double(glowState.proximity) * 0.46)
                            .blendMode(.screen)

                        glow
                            .blur(radius: 4)
                            .mask(shape.inset(by: 1.5).stroke(lineWidth: 13))
                            .opacity(Double(glowState.proximity) * 0.14)
                            .blendMode(.screen)

                        shape
                            .stroke(
                                Color.white.opacity(Double(glowState.proximity) * 0.11),
                                lineWidth: 0.85 + glowState.proximity * 0.45
                            )
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

private struct HomeGlowField: View {
    var location: CGPoint
    var size: CGSize
    var colors: [Color]
    var radius: CGFloat

    var body: some View {
        let palette = colors.isEmpty ? [Color.white] : colors

        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        palette[0].opacity(0.95),
                        palette[min(1, palette.count - 1)].opacity(0.75),
                        palette[min(2, palette.count - 1)].opacity(0.38),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .position(
                x: min(max(location.x, 0), size.width),
                y: min(max(location.y, 0), size.height)
            )
    }
}

private func homeGlowProximity(for location: CGPoint, in size: CGSize, edgeSensitivity: CGFloat) -> CGFloat {
    guard size.width > 0, size.height > 0 else { return 0 }

    let edgeDistance = min(location.x, size.width - location.x, location.y, size.height - location.y)
    let threshold = max(22, min(size.width, size.height) * (edgeSensitivity / 100))
    let proximity = 1 - (edgeDistance / threshold)
    return max(0, min(1, proximity))
}

private struct ThinScrollIndicatorModifier: ViewModifier {
    @State private var contentOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var isActive: Bool = false
    @State private var fadeTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.never)
            .background(SystemScrollbarHider())
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, new in
                contentOffset = new.contentOffset.y
                contentHeight = new.contentSize.height
                containerHeight = new.containerSize.height
                pulse()
            }
            .overlay(alignment: .trailing) {
                indicator
                    .padding(.trailing, 3)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var indicator: some View {
        GeometryReader { proxy in
            let available = proxy.size.height
            if contentHeight > containerHeight + 0.5, available > 0 {
                let visibleFraction = max(min(containerHeight / contentHeight, 1), 0.08)
                let knobHeight = max(18, available * visibleFraction)
                let scrollable = max(contentHeight - containerHeight, 1)
                let progress = min(max(contentOffset / scrollable, 0), 1)
                let travel = max(available - knobHeight, 0)

                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.white.opacity(isActive ? 0.42 : 0.18))
                    .frame(width: 2, height: knobHeight)
                    .offset(y: travel * progress)
                    .animation(.easeOut(duration: 0.18), value: isActive)
            }
        }
        .frame(width: 2)
    }

    private func pulse() {
        isActive = true
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            isActive = false
        }
    }
}

private struct SystemScrollbarHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        hideScrollbars(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        hideScrollbars(from: nsView)
    }

    private func hideScrollbars(from view: NSView) {
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else {
                return
            }

            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
        }
    }
}

private extension HomeVisualEffectMode {
    var homeSwitcherSymbol: String {
        switch self {
        case .rain:
            "cloud.rain"
        case .none:
            "circle.slash"
        }
    }

    var homeSwitcherHelpText: String {
        switch self {
        case .rain:
            "Switch display mode to rain glass"
        case .none:
            "Switch display mode to clean background"
        }
    }
}

private extension AgentAppearanceKind {
    var homeAppearanceSwitcherSymbol: String {
        switch self {
        case .live2D:
            "person.crop.square"
        case .video:
            "video"
        case .staticImage:
            "photo"
        case .abstract:
            "mountain.2"
        }
    }

    var homeAppearanceSwitcherHelpText: String {
        switch self {
        case .live2D:
            "Show agent Live2D visual"
        case .video:
            "Show agent video visual"
        case .staticImage:
            "Show agent image visual"
        case .abstract:
            "Show abstract agent visual"
        }
    }
}
