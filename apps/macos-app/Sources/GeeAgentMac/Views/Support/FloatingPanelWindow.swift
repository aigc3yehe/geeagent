import AppKit
import SwiftUI

/// A lightweight `NSPanel` wrapper for menu-bar-style surfaces.
///
/// Responsibilities (kept deliberately minimal so the menu-bar controller
/// drives positioning):
/// - Hosts a SwiftUI view via `AutoSizingHostingView`, a tiny `NSHostingView`
///   subclass whose `layout()` override reports the latest fitting size so
///   the panel can keep itself exactly as tall as its SwiftUI content —
///   needed once the quick-input panel grows to include a latest-result card.
/// - Non-activating so the host app doesn't steal focus when the panel shows.
/// - Can optionally hide on resignKey for menu popovers; command surfaces such
///   as Quick Input stay open until an explicit dismiss.
/// - Honors `Escape` via a cheap `keyDown` override (no global handlers).
final class FloatingPanelWindow: NSPanel {
    var onDismiss: (() -> Void)?

    /// Minimum width — width is authoritative since the SwiftUI content is
    /// given a fixed `.frame(width:)` by each panel surface.
    private let contentWidth: CGFloat
    private let contentCornerRadius: CGFloat
    private let dismissesOnResignKey: Bool

    init<Content: View>(
        size: CGSize,
        cornerRadius: CGFloat = 12,
        level: NSWindow.Level = .floating,
        dismissesOnResignKey: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.contentWidth = size.width
        self.contentCornerRadius = cornerRadius
        self.dismissesOnResignKey = dismissesOnResignKey
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = level
        self.becomesKeyOnlyIfNeeded = false
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.animationBehavior = .utilityWindow
        self.backgroundColor = .clear
        self.hasShadow = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        // Allow the whole panel to be dragged by clicking anywhere on the
        // panel surface (the text field / submit button still intercept their
        // own clicks because they're real NSViews). Combined with the
        // `AutoSizingHostingView.mouseDownCanMoveWindow` override below.
        self.isMovable = true
        self.isMovableByWindowBackground = true
        self.worksWhenModal = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let hosting = AutoSizingHostingView(rootView: AnyView(content()))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = cornerRadius
        hosting.layer?.masksToBounds = true
        hosting.onFittingSizeChange = { [weak self] fittingSize in
            self?.resizeToContentHeight(fittingSize.height)
        }
        self.contentView = hosting

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResignKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }

    @objc private func handleResignKey(_ notification: Notification) {
        guard dismissesOnResignKey else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.onDismiss?()
        }
    }

    func present(at origin: CGPoint) {
        setFrameOrigin(origin)
        orderFrontRegardless()
        makeKey()
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
    }

    /// Resizes the panel vertically to match the SwiftUI content's reported
    /// fitting height, anchoring to the current top edge (so the panel
    /// appears to grow downward when the latest-result card expands rather
    /// than jumping off the bottom of the screen).
    private func resizeToContentHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        let rounded = ceil(height)
        let currentFrame = self.frame
        if abs(currentFrame.height - rounded) < 0.5 { return }
        let topY = currentFrame.maxY
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: topY - rounded,
            width: contentWidth,
            height: rounded
        )
        setFrame(newFrame, display: true, animate: false)
    }
}

/// `NSHostingView` that reports its SwiftUI fitting size on every layout
/// pass. Used by `FloatingPanelWindow` to auto-resize around dynamic
/// content (e.g. the quick-input latest-result card appearing/disappearing).
private final class AutoSizingHostingView<Root: View>: NSHostingView<Root> {
    var onFittingSizeChange: ((CGSize) -> Void)?
    private var lastReportedHeight: CGFloat = 0

    override func layout() {
        super.layout()
        let size = self.fittingSize
        guard size.height > 0, abs(size.height - lastReportedHeight) > 0.5 else { return }
        lastReportedHeight = size.height
        onFittingSizeChange?(size)
    }

    /// Let AppKit treat the hosting surface as a drag handle for the window.
    /// AppKit only consults this on the *target* view of a mouse-down, so
    /// real NSView subviews (NSTextField, NSButton) still receive their
    /// clicks normally — drag only kicks in when the click lands on the
    /// SwiftUI panel backgrounds (which have no backing NSView).
    override var mouseDownCanMoveWindow: Bool { true }
}
