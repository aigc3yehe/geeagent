import AppKit
import SwiftUI

struct WorkbenchRootView: View {
    private enum ChromeMetrics {
        static let topDragStripHeight: CGFloat = 32
        static let reservedTrailingInteractionWidth: CGFloat = 240
    }

    @State var store: WorkbenchStore
    @Environment(\.openWindow) private var openWindow
    @State private var presentedSection: WorkbenchSection = .home
    @State private var transitionCoverOpacity = 0.0
    @State private var transitionTask: Task<Void, Never>?
    @AppStorage("geeagent.home.widget.positions") private var storedHomeWidgetPositions = "{}"

    init(store: WorkbenchStore? = nil) {
        _store = State(
            initialValue: store ?? WorkbenchStore(runtimeClient: NativeWorkbenchRuntimeClient())
        )
    }

    private var isHomeFocused: Bool {
        presentedSection == .home && store.homeSurfaceMode.isFocused
    }

    private var usesTopLevelNavigation: Bool {
        presentedSection == .home || presentedSection == .apps
    }

    private var shouldShowLive2DInteractionSurface: Bool {
        guard presentedSection == .home else { return false }
        guard !isHomeFocused else { return false }
        guard case .live2D = store.effectiveActiveAppearance else { return false }
        return true
    }

    var body: some View {
        ZStack {
            WorkbenchSceneBackground(
                isHomeActive: presentedSection == .home,
                isHomeFocused: isHomeFocused,
                activeAppearance: store.effectiveActiveAppearance,
                globalBackground: store.effectiveGlobalBackground,
                homeVisualEffectMode: store.homeVisualEffectMode,
                live2DMotionPlaybackRequest: store.live2DMotionPlaybackRequest,
                live2DViewportState: store.live2DViewportState,
                live2DIdlePosePath: store.activeLive2DPosePath,
                live2DExpressionPath: store.activeLive2DExpressionPath,
                live2DActionCatalog: store.live2DActionCatalog,
                selectedLive2DExpressionPath: store.selectedLive2DExpression?.relativePath,
                onTriggerRandomLive2DReaction: { store.triggerRandomLive2DReaction() },
                onSelectLive2DPose: { store.setLive2DPose($0) },
                onSelectLive2DExpression: { store.setLive2DExpression($0) },
                onPlayLive2DAction: { store.triggerLive2DAction($0) },
                onResetLive2DExpression: { store.resetLive2DExpression() },
                onMoveLive2D: { store.translateLive2D(by: $0) },
                onScaleLive2D: { store.adjustLive2DScale(by: $0) },
                onResetLive2DViewport: { store.resetLive2DViewport() }
            )
            .ignoresSafeArea()

            if shouldShowLive2DInteractionSurface {
                GeometryReader { proxy in
                    Live2DInteractionSurface(
                        viewportState: store.live2DViewportState,
                        catalog: store.live2DActionCatalog,
                        activePosePath: store.activeLive2DPosePath,
                        activeExpressionPath: store.selectedLive2DExpression?.relativePath,
                        excludedRects: live2DInteractionExcludedRects(in: proxy.size),
                        onPrimaryClick: { store.triggerRandomLive2DReaction() },
                        onSelectPose: { store.setLive2DPose($0) },
                        onSelectExpression: { store.setLive2DExpression($0) },
                        onPlayAction: { store.triggerLive2DAction($0) },
                        onResetExpression: { store.resetLive2DExpression() },
                        onDrag: { store.translateLive2D(by: $0) },
                        onScale: { store.adjustLive2DScale(by: $0) },
                        onResetViewport: { store.resetLive2DViewport() }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                    .ignoresSafeArea()
                    .zIndex(1.4)
            }

            if store.presentedStandaloneModuleID != nil {
                StandaloneModuleStage(store: store)
                    .padding(.leading, 14)
                    .padding(.trailing, 14)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                    .zIndex(4)
            } else {
                contentStage
                    .padding(.leading, usesTopLevelNavigation ? 12 : 14)
                    .padding(.trailing, presentedSection == .home ? 12 : (usesTopLevelNavigation ? 92 : 112))
                    .padding(.top, presentedSection == .home ? 10 : 22)
                    .padding(.bottom, 18)
                    .zIndex(isHomeFocused ? 2 : 1)

                WorkbenchTopNavigation(
                    store: store,
                    mode: presentedSection == .home ? .home : (presentedSection == .apps ? .apps : .workbench)
                )
                    .frame(width: 60)
                    .padding(.trailing, usesTopLevelNavigation ? 22 : 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .allowsHitTesting(!isHomeFocused)
                    .opacity(isHomeFocused ? 0.3 : 1)
                    .zIndex(isHomeFocused ? 0 : 2)
                    .animation(.easeInOut(duration: 0.24), value: isHomeFocused)
            }

            if transitionCoverOpacity > 0 {
                Color.black
                    .opacity(transitionCoverOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                Color.clear
                    .frame(
                        width: max(proxy.size.width - ChromeMetrics.reservedTrailingInteractionWidth, 0),
                        height: ChromeMetrics.topDragStripHeight,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: ChromeMetrics.topDragStripHeight)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(minWidth: 630, minHeight: 410)
        .onAppear {
            presentedSection = store.selectedSection
        }
        .onChange(of: store.selectedSection) { oldValue, newValue in
            coordinateTransition(from: oldValue, to: newValue)
        }
        .onChange(of: store.pendingGearWindowRequest) { _, request in
            guard let request else {
                return
            }
            openWindow(id: request.windowID)
            store.clearGearWindowRequest(request.id)
        }
        .sheet(
            isPresented: Binding(
                get: { store.pendingToolApproval != nil },
                set: { newValue in
                    if !newValue && store.pendingToolApproval != nil {
                        store.resolvePendingApproval(accept: false)
                    }
                }
            )
        ) {
            if let pending = store.pendingToolApproval {
                ToolApprovalSheet(
                    pending: pending,
                    onCancel: { store.resolvePendingApproval(accept: false) },
                    onApprove: { store.resolvePendingApproval(accept: true) }
                )
            }
        }
    }

    @ViewBuilder
    private var contentStage: some View {
        ZStack {
            if presentedSection == .home {
                HomeStageModule(store: store)
                    .transition(homeStageTransition)
            } else if presentedSection == .apps {
                AppsView(store: store)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .transition(functionalStageTransition)
            } else {
                FunctionalStageModule(store: store, section: presentedSection)
                    .transition(functionalStageTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: presentedSection)
    }

    private var homeStageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 1.02)).combined(with: .offset(y: 16)),
            removal: .opacity.combined(with: .scale(scale: 0.985)).combined(with: .offset(y: -18))
        )
    }

    private var functionalStageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 1.01))
        )
    }

    private var activeHomeWidgets: [InstalledAppRecord] {
        store.installedApps.filter {
            $0.isGearPackage
                && $0.gearKind == .widget
                && $0.installState == .installed
                && GearHost.isEnabled(gearID: $0.id)
        }
    }

    private func live2DInteractionExcludedRects(in size: CGSize) -> [CGRect] {
        guard presentedSection == .home, !isHomeFocused else { return [] }

        let contentInset = homeContentInset
        let contentSize = CGSize(
            width: max(size.width - contentInset.leading - contentInset.trailing, 0),
            height: max(size.height - contentInset.top - contentInset.bottom, 0)
        )

        return activeHomeWidgets.map { widget in
            let centerInContent = HomeWidgetPlacement.storedPosition(
                for: widget.id,
                canvasSize: contentSize,
                storedPositions: storedHomeWidgetPositions
            )
            let centerInRootTopOrigin = CGPoint(
                x: contentInset.leading + centerInContent.x,
                y: contentInset.top + centerInContent.y
            )
            let centerInRootBottomOrigin = CGPoint(
                x: centerInRootTopOrigin.x,
                y: size.height - centerInRootTopOrigin.y
            )

            return CGRect(
                x: centerInRootBottomOrigin.x - HomeWidgetPlacement.size.width / 2,
                y: centerInRootBottomOrigin.y - HomeWidgetPlacement.size.height / 2,
                width: HomeWidgetPlacement.size.width,
                height: HomeWidgetPlacement.size.height
            )
        }
    }

    private var homeContentInset: EdgeInsets {
        EdgeInsets(top: 10, leading: 12, bottom: 18, trailing: 12)
    }

    private func coordinateTransition(from oldValue: WorkbenchSection, to newValue: WorkbenchSection) {
        guard oldValue != newValue else {
            return
        }

        transitionTask?.cancel()

        if oldValue == .home || newValue == .home {
            transitionTask = Task {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        transitionCoverOpacity = 0.94
                    }
                }

                try? await Task.sleep(for: .milliseconds(210))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    presentedSection = newValue
                }

                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.32)) {
                        transitionCoverOpacity = 0
                    }
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                presentedSection = newValue
            }
        }
    }
}

private struct WorkbenchTopNavigation: View {
    enum Mode {
        case home
        case apps
        case workbench
    }

    @Bindable var store: WorkbenchStore
    var mode: Mode

    private let primarySections: [WorkbenchSection] = [.chat, .telegram, .automations, .agents, .settings]

    var body: some View {
        VStack(spacing: 7) {
            if mode == .home || mode == .apps {
                RuntimeStatusIndicator(
                    statusColor: statusColor,
                    statusLabel: statusLabel,
                    compact: false,
                    action: mode == .home ? nil : { store.openSection(.home) }
                )

                HomeTopLevelNavigationButton(
                    title: "Gears",
                    systemImage: WorkbenchSection.apps.systemImage,
                    isSelected: store.selectedSection == .apps,
                    action: { store.openSection(.apps) }
                )

                HomeTopLevelNavigationButton(
                    title: "Workbench",
                    systemImage: "rectangle.3.group",
                    isSelected: store.selectedSection != .home && store.selectedSection != .apps,
                    action: { store.openSection(.chat) }
                )
            } else {
                RuntimeStatusIndicator(
                    statusColor: statusColor,
                    statusLabel: statusLabel,
                    compact: true,
                    action: { store.openSection(.home) }
                )

                navButton(for: .apps)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 14, height: 1)
                    .padding(.vertical, 4)

                ForEach(primarySections, id: \.self) { section in
                    navButton(for: section)
                }

                Spacer(minLength: 10)

                navButton(for: .logs)
            }
        }
        .frame(maxHeight: mode == .workbench ? .infinity : nil, alignment: .top)
        .padding(.horizontal, mode == .workbench ? 8 : 0)
        .padding(.vertical, mode == .workbench ? 8 : 0)
        .background(
            Group {
                if mode == .workbench {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.62))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.06), Color.clear, Color.black.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.9)
                        )
                } else {
                    Color.clear
                }
            }
        )
        .shadow(color: .black.opacity(mode == .workbench ? 0.18 : 0), radius: mode == .workbench ? 6 : 0, x: 0, y: mode == .workbench ? 3 : 0)
    }

    private func navButton(for section: WorkbenchSection) -> some View {
        Button {
            store.openSection(section)
        } label: {
            Image(systemName: section.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(store.selectedSection == section ? Color.white : Color.white.opacity(0.72))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(store.selectedSection == section ? Color.white.opacity(0.12) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.title)
    }

    private var statusColor: Color {
        switch store.runtimeStatus.state {
        case .live:
            Color(red: 0.74, green: 0.9, blue: 0.0)
        case .needsSetup:
            .orange
        case .degraded:
            .yellow
        case .unavailable:
            .red
        }
    }

    private var statusLabel: String {
        switch store.runtimeStatus.state {
        case .live: "LIVE"
        case .needsSetup: "SETUP"
        case .degraded: "DEGRADED"
        case .unavailable: "OFFLINE"
        }
    }

}

private struct HomeTopLevelNavigationButton: View {
    var title: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))

                Text(title)
                    .font(.geeDisplaySemibold(8))
                    .tracking(title.count > 5 ? 0.1 : 0.8)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 52, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(isHovering || isSelected ? 0.92 : 0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), .clear, Color.black.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isHovering || isSelected ? 0.22 : 0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 11, x: 0, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeInOut(duration: 0.18), value: isHovering)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
    }
}

private struct RuntimeStatusIndicator: View {
    var statusColor: Color
    var statusLabel: String
    var compact: Bool
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    indicatorContent
                }
                .buttonStyle(.plain)
            } else {
                indicatorContent
            }
        }
        .help(action == nil ? "Home runtime \(statusLabel)" : "Back to Home — \(statusLabel)")
    }

    private var indicatorContent: some View {
        VStack(spacing: compact ? 4 : 2) {
            StatusPulseLight(statusColor: statusColor)

            Text(statusLabel)
                .font(.geeDisplaySemibold(compact ? 8 : 9))
                .tracking(compact ? 1.2 : 1.4)
                .foregroundStyle(statusColor.opacity(0.9))
                .lineLimit(1)
        }
        .contentShape(RoundedRectangle(cornerRadius: compact ? 8 : 11, style: .continuous))
        .frame(width: compact ? 36 : 52, height: compact ? 34 : 38)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 11, style: .continuous)
                .fill(Color.white.opacity(compact ? 0.07 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 8 : 11, style: .continuous)
                .stroke(statusColor.opacity(compact ? 0.22 : 0.28), lineWidth: 0.9)
        )
    }
}


private struct StatusPulseLight: View {
    var statusColor: Color

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(isPulsing ? 0.18 : 0.3))
                .frame(width: isPulsing ? 16 : 12, height: isPulsing ? 16 : 12)

            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(0.95), radius: isPulsing ? 8 : 5)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            guard !isPulsing else { return }
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct WorkbenchSceneBackground: View {
    var isHomeActive: Bool
    var isHomeFocused: Bool
    var activeAppearance: AgentProfileAppearanceRecord
    var globalBackground: AgentProfileGlobalBackgroundRecord
    var homeVisualEffectMode: HomeVisualEffectMode
    var live2DMotionPlaybackRequest: Live2DMotionPlaybackRequest?
    var live2DViewportState: Live2DViewportState
    var live2DIdlePosePath: String?
    var live2DExpressionPath: String?
    var live2DActionCatalog: Live2DActionCatalog
    var selectedLive2DExpressionPath: String?
    var onTriggerRandomLive2DReaction: () -> Void
    var onSelectLive2DPose: (Live2DMotionRecord?) -> Void
    var onSelectLive2DExpression: (Live2DExpressionRecord?) -> Void
    var onPlayLive2DAction: (Live2DMotionRecord) -> Void
    var onResetLive2DExpression: () -> Void
    var onMoveLive2D: (CGSize) -> Void
    var onScaleLive2D: (Double) -> Void
    var onResetLive2DViewport: () -> Void

    var body: some View {
        ZStack {
            if isHomeActive {
                homeBackground
            } else {
                nonHomeBackground
            }
        }
        .overlay {
            Color.black.opacity(isHomeFocused ? 0.16 : (isHomeActive ? 0.03 : 0.1))
        }
        .blur(radius: isHomeFocused ? 12 : 0)
        .animation(.easeInOut(duration: 0.24), value: isHomeFocused)
        .animation(.easeInOut(duration: 0.24), value: isHomeActive)
    }

    private var imageAssetPath: String? {
        if case .staticImage(let path) = activeAppearance, !path.isEmpty { return path }
        return nil
    }

    private var videoAssetPath: String? {
        if case .video(let path) = activeAppearance, !path.isEmpty { return path }
        return nil
    }

    private var live2DBundlePath: String? {
        if case .live2D(let path) = activeAppearance, !path.isEmpty { return path }
        return nil
    }

    private var globalBackgroundImagePath: String? {
        if case .staticImage(let path) = globalBackground, !path.isEmpty { return path }
        return nil
    }

    private var globalBackgroundVideoPath: String? {
        if case .video(let path) = globalBackground, !path.isEmpty { return path }
        return nil
    }

    @ViewBuilder
    private var homeBackground: some View {
        ZStack {
            globalBackgroundLayer

            switch activeAppearance {
            case .abstract:
                if case .none = globalBackground {
                    AbstractHomeBackground()
                }
            case .live2D:
                if case .none = globalBackground {
                    AbstractHomeBackground()
                }
                bannerLayer
            case .staticImage, .video:
                bannerLayer
                if case .none = globalBackground {
                    AbstractHomeBackground(baseOpacity: 0, accentOpacity: 0)
                }
            }

            if homeVisualEffectMode == .rain {
                HomeRainGlassEffect()
                    .opacity(0.85)
                    .blendMode(.screen)
            }
        }
    }

    @ViewBuilder
    private var globalBackgroundLayer: some View {
        if let path = globalBackgroundVideoPath {
            HomeBannerVideoPlayer(url: URL(fileURLWithPath: path))
        } else if let image = BackgroundImageProvider.originalBackground(customPath: globalBackgroundImagePath) {
            GeometryReader { geo in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
    }

    @ViewBuilder
    private var nonHomeBackground: some View {
        Color(red: 0.085, green: 0.095, blue: 0.11)
    }

    @ViewBuilder
    private var bannerLayer: some View {
        if let path = videoAssetPath {
            HomeBannerVideoPlayer(url: URL(fileURLWithPath: path))
        } else if case .staticImage = activeAppearance,
                  let image = BackgroundImageProvider.originalBackground(customPath: imageAssetPath) {
            GeometryReader { geo in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else if let bundlePath = live2DBundlePath {
            PersonaLive2DWebView(
                bundlePath: bundlePath,
                isActive: isHomeActive,
                playbackRequest: live2DMotionPlaybackRequest,
                viewportState: live2DViewportState,
                idlePosePath: live2DIdlePosePath,
                expressionPath: live2DExpressionPath
            )
        } else if case .live2D = activeAppearance {
            // Baseline persona declares Live2D but the bundle path isn't populated yet (e.g. the
            // asset hasn't been imported). Keep the abstract hero so the frame never goes black.
            AbstractHomeBackground()
        } else {
            fallbackBackground
        }
    }

    private var fallbackBackground: some View {
        Color(red: 0.28, green: 0.32, blue: 0.38)
    }
}

struct WorkbenchMetricTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.geeDisplaySemibold(11))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.geeDisplaySemibold(22))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }
}

struct WorkbenchStatusBadge: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.geeDisplaySemibold(10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            }
    }
}

struct WorkbenchInspectorCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}
