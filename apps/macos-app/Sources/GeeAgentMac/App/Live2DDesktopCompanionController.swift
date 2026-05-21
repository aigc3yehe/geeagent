import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class Live2DDesktopCompanionController {
    private enum PreferenceKey {
        static let windowFrame = "geeagent.live2dDesktop.windowFrame"
    }

    private struct StoredFrame: Codable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        init(_ frame: CGRect) {
            x = frame.origin.x
            y = frame.origin.y
            width = frame.width
            height = frame.height
        }

        var cgRect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    private let store: WorkbenchStore
    private var panel: Live2DDesktopCompanionWindow?
    private var poseRestoreTask: Task<Void, Never>?
    private var expressionRestoreTask: Task<Void, Never>?

    private(set) var isPresented = false
    private(set) var currentBundlePath: String?
    private(set) var actionCatalog: Live2DActionCatalog = .empty
    private(set) var playbackRequest: Live2DMotionPlaybackRequest?
    private(set) var selectedIdlePosePath: String?
    private(set) var selectedExpressionPath: String?
    var viewportState: Live2DViewportState = .default
    @ObservationIgnored
    var quickInputPresenter: (() -> Void)?
    @ObservationIgnored
    var audioCapturePresenter: (() -> Void)?

    init(store: WorkbenchStore) {
        self.store = store
    }

    var canPresent: Bool {
        store.activeLive2DBundlePath != nil
    }

    func toggle() {
        if isPresented {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let bundlePath = store.activeLive2DBundlePath else {
            hide()
            return
        }

        refresh(bundlePath: bundlePath)

        let panel: Live2DDesktopCompanionWindow
        if let existing = self.panel {
            panel = existing
        } else {
            panel = Live2DDesktopCompanionWindow(controller: self)
            self.panel = panel
        }

        panel.setFrame(clampedFrame(storedFrame() ?? defaultFrame()), display: true, animate: false)
        panel.onDismiss = { [weak self] in
            self?.hide()
        }
        isPresented = true
        panel.present()
    }

    func hide() {
        poseRestoreTask?.cancel()
        expressionRestoreTask?.cancel()
        poseRestoreTask = nil
        expressionRestoreTask = nil
        playbackRequest = nil
        isPresented = false
        panel?.dismiss()
    }

    func refreshFromStoreOrHide() {
        guard isPresented else { return }
        guard let bundlePath = store.activeLive2DBundlePath else {
            hide()
            return
        }
        refresh(bundlePath: bundlePath)
    }

    func triggerClickReaction() {
        if let motion = Self.preferredClickMotion(in: actionCatalog) {
            playMotion(motion)
            return
        }

        let expressionCandidates = actionCatalog.expressions.filter {
            $0.relativePath != selectedExpressionPath
        }
        guard let expression = (expressionCandidates.isEmpty ? actionCatalog.expressions : expressionCandidates).randomElement() else {
            return
        }

        expressionRestoreTask?.cancel()
        selectedExpressionPath = expression.relativePath
        expressionRestoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard let self, !Task.isCancelled else { return }
            self.selectedExpressionPath = self.preferredStoredExpressionPath(in: self.actionCatalog)
        }
    }

    func setIdlePose(_ pose: Live2DMotionRecord?) {
        poseRestoreTask?.cancel()
        store.setLive2DPose(pose)
        selectedIdlePosePath = pose?.relativePath ?? preferredIdlePosePath(in: actionCatalog)
    }

    func setExpression(_ expression: Live2DExpressionRecord?) {
        expressionRestoreTask?.cancel()
        store.setLive2DExpression(expression)
        selectedExpressionPath = expression?.relativePath
    }

    func resetExpression() {
        setExpression(nil)
    }

    func presentQuickInput() {
        quickInputPresenter?()
    }

    func presentAudioCapture() {
        audioCapturePresenter?()
    }

    func playMotion(_ motion: Live2DMotionRecord) {
        guard let bundlePath = currentBundlePath else { return }

        poseRestoreTask?.cancel()
        playbackRequest = Live2DMotionPlaybackRequest(bundlePath: bundlePath, motion: motion)
        guard motion.category == .action else { return }

        let restoreDelay = motion.durationSeconds ?? (motion.isLoop ? 2.4 : 1.6)
        schedulePoseRestore(after: restoreDelay)
    }

    func movePanel(by delta: CGSize) {
        guard let panel else { return }
        var frame = panel.frame
        frame.origin.x += delta.width
        frame.origin.y -= delta.height
        frame = clampedFrame(frame, preferredScreenPoint: NSEvent.mouseLocation)
        panel.setFrame(frame, display: true, animate: false)
        persist(frame: frame)
    }

    func adjustViewportScale(by multiplier: Double) {
        viewportState = Live2DViewportState(
            offsetX: viewportState.offsetX,
            offsetY: viewportState.offsetY,
            scale: viewportState.scale * multiplier
        ).clamped()
    }

    func resetPlacementAndViewport() {
        viewportState = .default
        let frame = defaultFrame()
        panel?.setFrame(frame, display: true, animate: true)
        persist(frame: frame)
    }

    nonisolated static func preferredClickMotion(in catalog: Live2DActionCatalog) -> Live2DMotionRecord? {
        let actions = catalog.actions.filter { $0.category == .action }
        guard !actions.isEmpty else { return nil }

        let preferredKeywords = [
            "tapbody",
            "tap body",
            "tap_body",
            "tap",
            "click",
            "touch",
            "poke",
            "body"
        ]

        return actions.first { motion in
            let haystack = "\(motion.title) \(motion.relativePath)"
                .lowercased()
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
            let compact = haystack.replacingOccurrences(of: " ", with: "")
            return preferredKeywords.contains { keyword in
                haystack.contains(keyword) || compact.contains(keyword.replacingOccurrences(of: " ", with: ""))
            }
        } ?? actions.first
    }

    private func refresh(bundlePath: String) {
        let standardizedPath = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        let bundleChanged = standardizedPath != currentBundlePath
        currentBundlePath = standardizedPath

        if bundleChanged || actionCatalog == .empty {
            actionCatalog = Live2DMotionCatalog.discoverCatalog(bundlePath: standardizedPath)
        }

        selectedIdlePosePath = preferredIdlePosePath(in: actionCatalog)
        selectedExpressionPath = preferredStoredExpressionPath(in: actionCatalog)

        if bundleChanged {
            viewportState = .default
            playbackRequest = nil
        }
    }

    private func preferredIdlePosePath(in catalog: Live2DActionCatalog) -> String? {
        let storedPath = store.activeProfileAppearancePreference.live2DIdlePosePath
        if let storedPath,
           catalog.poses.contains(where: { $0.relativePath == storedPath }) {
            return storedPath
        }
        return catalog.defaultPose?.relativePath ?? catalog.poses.first?.relativePath
    }

    private func preferredStoredExpressionPath(in catalog: Live2DActionCatalog) -> String? {
        let storedPath = store.activeProfileAppearancePreference.live2DExpressionPath
        if let storedPath,
           catalog.expressions.contains(where: { $0.relativePath == storedPath }) {
            return storedPath
        }
        return nil
    }

    private func schedulePoseRestore(after seconds: Double) {
        poseRestoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0.2, seconds)))
            guard let self, !Task.isCancelled, let bundlePath = self.currentBundlePath else { return }

            if let idlePath = self.selectedIdlePosePath,
               let idle = self.actionCatalog.poses.first(where: { $0.relativePath == idlePath }) {
                self.playbackRequest = Live2DMotionPlaybackRequest(bundlePath: bundlePath, motion: idle)
            } else {
                self.playbackRequest = .stop(bundlePath: bundlePath)
            }
        }
    }

    private func defaultFrame() -> CGRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 420, height: 620)
        return CGRect(
            x: visible.maxX - size.width - 72,
            y: visible.minY + 72,
            width: size.width,
            height: size.height
        )
    }

    private func clampedFrame(_ frame: CGRect, preferredScreenPoint: CGPoint? = nil) -> CGRect {
        let screen = preferredScreenPoint.flatMap(screen(containing:))
            ?? screenWithLargestIntersection(for: frame)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return frame }
        let visible = screen.visibleFrame
        let width = min(max(frame.width, 300), min(visible.width, 620))
        let height = min(max(frame.height, 420), min(visible.height, 760))
        let x = min(max(frame.origin.x, visible.minX + 12), visible.maxX - width - 12)
        let y = min(max(frame.origin.y, visible.minY + 12), visible.maxY - height - 12)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.visibleFrame.contains(point) || screen.frame.contains(point)
        }
    }

    private func screenWithLargestIntersection(for frame: CGRect) -> NSScreen? {
        NSScreen.screens
            .map { screen in
                (screen: screen, area: screen.visibleFrame.intersection(frame).area)
            }
            .filter { $0.area > 0 }
            .max { lhs, rhs in lhs.area < rhs.area }?
            .screen
    }

    private func storedFrame() -> CGRect? {
        guard let data = UserDefaults.standard.data(forKey: PreferenceKey.windowFrame),
              let stored = try? JSONDecoder().decode(StoredFrame.self, from: data)
        else {
            return nil
        }
        return stored.cgRect
    }

    private func persist(frame: CGRect) {
        guard let data = try? JSONEncoder().encode(StoredFrame(frame)) else { return }
        UserDefaults.standard.set(data, forKey: PreferenceKey.windowFrame)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard width > 0, height > 0 else { return 0 }
        return width * height
    }
}
