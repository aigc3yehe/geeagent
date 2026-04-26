import AppKit
import SwiftUI

struct Live2DInteractionSurface: NSViewRepresentable {
    var viewportState: Live2DViewportState
    var catalog: Live2DActionCatalog
    var activePosePath: String?
    var activeExpressionPath: String?
    var onPrimaryClick: () -> Void
    var onSelectPose: (Live2DMotionRecord?) -> Void
    var onSelectExpression: (Live2DExpressionRecord?) -> Void
    var onPlayAction: (Live2DMotionRecord) -> Void
    var onResetExpression: () -> Void
    var onDrag: (CGSize) -> Void
    var onScale: (Double) -> Void
    var onResetViewport: () -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.configure(
            viewportState: viewportState,
            catalog: catalog,
            activePosePath: activePosePath,
            activeExpressionPath: activeExpressionPath,
            onPrimaryClick: onPrimaryClick,
            onSelectPose: onSelectPose,
            onSelectExpression: onSelectExpression,
            onPlayAction: onPlayAction,
            onResetExpression: onResetExpression,
            onDrag: onDrag,
            onScale: onScale,
            onResetViewport: onResetViewport
        )
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.configure(
            viewportState: viewportState,
            catalog: catalog,
            activePosePath: activePosePath,
            activeExpressionPath: activeExpressionPath,
            onPrimaryClick: onPrimaryClick,
            onSelectPose: onSelectPose,
            onSelectExpression: onSelectExpression,
            onPlayAction: onPlayAction,
            onResetExpression: onResetExpression,
            onDrag: onDrag,
            onScale: onScale,
            onResetViewport: onResetViewport
        )
    }
}

final class InteractionView: NSView {
    private var viewportState: Live2DViewportState = .default
    private var catalog: Live2DActionCatalog = .empty
    private var activePosePath: String?
    private var activeExpressionPath: String?
    private var onPrimaryClick: (() -> Void)?
    private var onSelectPose: ((Live2DMotionRecord?) -> Void)?
    private var onSelectExpression: ((Live2DExpressionRecord?) -> Void)?
    private var onPlayAction: ((Live2DMotionRecord) -> Void)?
    private var onResetExpression: (() -> Void)?
    private var onDrag: ((CGSize) -> Void)?
    private var onScale: ((Double) -> Void)?
    private var onResetViewport: (() -> Void)?

    private var initialMouseDownPoint: NSPoint?
    private var lastDragPoint: NSPoint?
    private var draggedDuringMouseDown = false

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return interactionPath.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        buildMenu()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        initialMouseDownPoint = point
        lastDragPoint = point
        draggedDuringMouseDown = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let lastDragPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = CGSize(width: point.x - lastDragPoint.x, height: -(point.y - lastDragPoint.y))
        if abs(delta.width) > 0.5 || abs(delta.height) > 0.5 {
            draggedDuringMouseDown = true
            onDrag?(delta)
            self.lastDragPoint = point
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            initialMouseDownPoint = nil
            lastDragPoint = nil
            draggedDuringMouseDown = false
        }
        guard !draggedDuringMouseDown else { return }
        if event.modifierFlags.contains(.control) {
            presentContextMenu(at: convert(event.locationInWindow, from: nil))
            return
        }
        onPrimaryClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        // Swallow the down event so the menu opens once on mouse-up, matching standard macOS
        // context-menu timing and avoiding duplicate show/dismiss cycles.
    }

    override func rightMouseUp(with event: NSEvent) {
        presentContextMenu(at: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? -event.scrollingDeltaY : -(event.deltaY * 10)
        guard abs(delta) > 0.01 else { return }
        let multiplier = pow(1.0035, Double(delta))
        onScale?(multiplier)
    }

    func configure(
        viewportState: Live2DViewportState,
        catalog: Live2DActionCatalog,
        activePosePath: String?,
        activeExpressionPath: String?,
        onPrimaryClick: @escaping () -> Void,
        onSelectPose: @escaping (Live2DMotionRecord?) -> Void,
        onSelectExpression: @escaping (Live2DExpressionRecord?) -> Void,
        onPlayAction: @escaping (Live2DMotionRecord) -> Void,
        onResetExpression: @escaping () -> Void,
        onDrag: @escaping (CGSize) -> Void,
        onScale: @escaping (Double) -> Void,
        onResetViewport: @escaping () -> Void
    ) {
        self.viewportState = viewportState
        self.catalog = catalog
        self.activePosePath = activePosePath
        self.activeExpressionPath = activeExpressionPath
        self.onPrimaryClick = onPrimaryClick
        self.onSelectPose = onSelectPose
        self.onSelectExpression = onSelectExpression
        self.onPlayAction = onPlayAction
        self.onResetExpression = onResetExpression
        self.onDrag = onDrag
        self.onScale = onScale
        self.onResetViewport = onResetViewport
        needsDisplay = true
    }

    private var interactionPath: NSBezierPath {
        let bounds = self.bounds
        let scaleFactor = sqrt(max(viewportState.scale, 0.65))
        let width = max(bounds.width * 0.34, bounds.width * 0.52 * scaleFactor)
        let height = max(bounds.height * 0.56, bounds.height * 0.9 * scaleFactor)
        let rect = CGRect(
            x: bounds.midX - width / 2 + viewportState.offsetX,
            y: bounds.midY - height / 2 + (bounds.height * 0.02) + viewportState.offsetY,
            width: width,
            height: height
        )
        return NSBezierPath(roundedRect: rect, xRadius: 72, yRadius: 72)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if let defaultPose = catalog.defaultPose {
            appendSectionHeader("Poses", to: menu)
            let defaultItem = NSMenuItem(title: "Default Pose", action: #selector(handleDefaultPose), keyEquivalent: "")
            defaultItem.target = self
            defaultItem.state = (activePosePath == nil || activePosePath == defaultPose.relativePath) ? .on : .off
            menu.addItem(defaultItem)

            for pose in catalog.poses where pose.relativePath != defaultPose.relativePath {
                let item = NSMenuItem(title: pose.title, action: #selector(handlePoseSelection(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pose
                item.state = activePosePath == pose.relativePath ? .on : .off
                menu.addItem(item)
            }
        }

        if !catalog.expressions.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            appendSectionHeader("Expressions", to: menu)

            let defaultStateItem = NSMenuItem(title: "Default Expression", action: #selector(handleDefaultExpression), keyEquivalent: "")
            defaultStateItem.target = self
            defaultStateItem.state = activeExpressionPath == nil ? .on : .off
            menu.addItem(defaultStateItem)

            for expression in catalog.expressions {
                let item = NSMenuItem(title: expression.title, action: #selector(handleExpressionSelection(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = expression
                item.state = activeExpressionPath == expression.relativePath ? .on : .off
                menu.addItem(item)
            }
        }

        if !catalog.actions.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            appendSectionHeader("Actions", to: menu)
            for action in catalog.actions {
                let item = NSMenuItem(title: action.title, action: #selector(handleActionSelection(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action
                menu.addItem(item)
            }
        }

        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let resetViewportItem = NSMenuItem(title: "Reset Position and Zoom", action: #selector(handleResetViewport), keyEquivalent: "")
        resetViewportItem.target = self
        menu.addItem(resetViewportItem)

        return menu
    }

    private func presentContextMenu(at point: NSPoint?) {
        let menu = buildMenu()
        menu.popUp(positioning: nil, at: point ?? NSPoint(x: bounds.midX, y: bounds.midY), in: self)
    }

    private func appendSectionHeader(_ title: String, to menu: NSMenu) {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
    }

    @objc
    private func handleDefaultPose() {
        onSelectPose?(catalog.defaultPose)
    }

    @objc
    private func handlePoseSelection(_ sender: NSMenuItem) {
        guard let pose = sender.representedObject as? Live2DMotionRecord else { return }
        onSelectPose?(pose)
    }

    @objc
    private func handleDefaultExpression() {
        onResetExpression?()
    }

    @objc
    private func handleExpressionSelection(_ sender: NSMenuItem) {
        guard let expression = sender.representedObject as? Live2DExpressionRecord else { return }
        onSelectExpression?(expression)
    }

    @objc
    private func handleActionSelection(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? Live2DMotionRecord else { return }
        onPlayAction?(action)
    }

    @objc
    private func handleResetViewport() {
        onResetViewport?()
    }
}
