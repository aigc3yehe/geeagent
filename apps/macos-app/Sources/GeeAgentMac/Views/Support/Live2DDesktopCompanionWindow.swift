import AppKit
import SwiftUI

final class Live2DDesktopCompanionWindow: NSPanel {
    var onDismiss: (() -> Void)?

    private weak var companionController: Live2DDesktopCompanionController?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(controller: Live2DDesktopCompanionController) {
        companionController = controller

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        isMovableByWindowBackground = false
        worksWhenModal = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true

        let hosting = Live2DDesktopHostingView(
            rootView: Live2DDesktopCompanionView(controller: controller),
            controller: controller
        )
        hosting.frame = contentRect(forFrameRect: frame)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }

    func present() {
        startMouseTracking()
        updateMouseEventAcceptance()
        orderFrontRegardless()
    }

    func dismiss() {
        stopMouseTracking()
        ignoresMouseEvents = false
        guard isVisible else { return }
        orderOut(nil)
    }

    private func startMouseTracking() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            if event.type == .mouseMoved {
                self?.updateMouseEventAcceptance()
            } else {
                Task { @MainActor in
                    self?.updateMouseEventAcceptance()
                }
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.updateMouseEventAcceptance()
            }
        }
    }

    private func stopMouseTracking() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func updateMouseEventAcceptance() {
        guard !isMiniaturized else { return }
        guard let companionController,
              let contentView
        else {
            ignoresMouseEvents = true
            return
        }

        let windowPoint = convertPoint(fromScreen: NSEvent.mouseLocation)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        let acceptsMouse = Live2DDesktopCompanionHitTesting.accepts(
            point: contentPoint,
            in: contentView.bounds,
            viewportState: companionController.viewportState
        )
        ignoresMouseEvents = !acceptsMouse
    }
}

private struct Live2DDesktopCompanionView: View {
    var controller: Live2DDesktopCompanionController

    var body: some View {
        ZStack {
            if let bundlePath = controller.currentBundlePath {
                PersonaLive2DWebView(
                    bundlePath: bundlePath,
                    isActive: controller.isPresented,
                    playbackRequest: controller.playbackRequest,
                    viewportState: controller.viewportState,
                    idlePosePath: controller.selectedIdlePosePath,
                    expressionPath: controller.selectedExpressionPath
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

                Live2DInteractionSurface(
                    viewportState: controller.viewportState,
                    catalog: controller.actionCatalog,
                    activePosePath: controller.selectedIdlePosePath,
                    activeExpressionPath: controller.selectedExpressionPath,
                    dragCoordinateSpace: .screen,
                    defersPrimaryClickForMultipleClicks: true,
                    onPrimaryClick: { controller.triggerClickReaction() },
                    onDoubleClick: { controller.presentQuickInput() },
                    onTripleClick: { controller.presentAudioCapture() },
                    onSelectPose: { controller.setIdlePose($0) },
                    onSelectExpression: { controller.setExpression($0) },
                    onPlayAction: { controller.playMotion($0) },
                    onResetExpression: { controller.resetExpression() },
                    onDrag: { controller.movePanel(by: $0) },
                    onScale: { controller.adjustViewportScale(by: $0) },
                    onResetViewport: { controller.resetPlacementAndViewport() },
                    onClose: { controller.hide() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.clear)
    }
}

enum Live2DDesktopCompanionHitTesting {
    static func accepts(point: CGPoint, in bounds: CGRect, viewportState: Live2DViewportState) -> Bool {
        let rect = InteractionView.interactionRect(in: bounds, viewportState: viewportState)
        guard rect.width > 0, rect.height > 0 else { return false }

        return NSBezierPath(
            roundedRect: rect,
            xRadius: min(rect.width * 0.38, 96),
            yRadius: min(rect.height * 0.24, 96)
        )
        .contains(point)
    }
}

private final class Live2DDesktopHostingView: NSHostingView<Live2DDesktopCompanionView> {
    private weak var companionController: Live2DDesktopCompanionController?

    init(rootView: Live2DDesktopCompanionView, controller: Live2DDesktopCompanionController) {
        companionController = controller
        super.init(rootView: rootView)
    }

    required init(rootView: Live2DDesktopCompanionView) {
        companionController = nil
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let companionController else { return nil }
        guard Live2DDesktopCompanionHitTesting.accepts(
            point: point,
            in: bounds,
            viewportState: companionController.viewportState
        ) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
