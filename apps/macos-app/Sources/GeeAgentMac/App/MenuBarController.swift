import AppKit
import SwiftUI

/// Owns the `NSStatusItem`, the floating menu-bar panel, and the floating
/// quick-input panel. Everything here runs on the main actor — mutating
/// `NSStatusItem.button.frame` or `NSPanel` state off-main is unsupported.
@MainActor
final class MenuBarController {
    private let store: WorkbenchStore
    private var statusItem: NSStatusItem?
    private var menuPanel: FloatingPanelWindow?
    private var quickInputPanel: FloatingPanelWindow?
    private var shortcutRegistrar: GlobalShortcutRegistrar?

    init(store: WorkbenchStore) {
        self.store = store
    }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.statusIcon()
            button.imagePosition = .imageOnly
            button.action = #selector(handleStatusClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item

        // Register the global quick-input toggle.
        shortcutRegistrar = GlobalShortcutRegistrar { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleQuickInput()
            }
        }
        shortcutRegistrar?.register()
    }

    func uninstall() {
        shortcutRegistrar?.unregister()
        shortcutRegistrar = nil

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }

        menuPanel?.close()
        menuPanel = nil
        quickInputPanel?.close()
        quickInputPanel = nil
    }

    // MARK: click routing

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            toggleMenuPanel()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu(title: "GeeAgent")
        menu.addItem(
            NSMenuItem(
                title: "Open GeeAgent",
                action: #selector(openMainWindow),
                keyEquivalent: ""
            ).configured(target: self)
        )
        menu.addItem(
            NSMenuItem(
                title: "Quick Input",
                action: #selector(showQuickInput),
                keyEquivalent: "g"
            ).configured(target: self, modifiers: [.control, .option])
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit GeeAgent",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        statusItem?.menu = menu
        button.performClick(nil)
        // Detach menu so the next left-click re-enters `handleStatusClick`.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    @objc private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.contentViewController != nil && !($0 is FloatingPanelWindow) }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: panel toggles

    func toggleMenuPanel() {
        if let panel = menuPanel, panel.isVisible {
            panel.dismiss()
            return
        }
        showMenuPanel()
    }

    @objc func showQuickInput() {
        toggleQuickInput()
    }

    func toggleQuickInput() {
        if let panel = quickInputPanel, panel.isVisible {
            panel.dismiss()
            return
        }
        showQuickInputPanel()
    }

    // MARK: menu panel

    private func showMenuPanel() {
        quickInputPanel?.dismiss()

        let panel: FloatingPanelWindow
        if let existing = menuPanel {
            panel = existing
        } else {
            panel = FloatingPanelWindow(size: CGSize(width: 380, height: 420)) {
                MenuBarPanelView(
                    store: self.store,
                    onOpenQuickInput: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.menuPanel?.dismiss()
                            self?.showQuickInputPanel()
                        }
                    },
                    onOpenMainWindow: { [weak self] section in
                        Task { @MainActor [weak self] in
                            self?.menuPanel?.dismiss()
                            self?.openMainWindow()
                            self?.store.openSection(section)
                        }
                    },
                    onDismiss: { [weak self] in
                        self?.menuPanel?.dismiss()
                    }
                )
            }
            panel.onDismiss = { [weak panel] in panel?.dismiss() }
            menuPanel = panel
        }

        positionMenuPanel(panel)
        panel.present(at: panel.frame.origin)
    }

    private func positionMenuPanel(_ panel: FloatingPanelWindow) {
        guard
            let button = statusItem?.button,
            let buttonWindow = button.window,
            let screen = buttonWindow.screen ?? NSScreen.main
        else { return }

        let buttonFrameOnScreen = buttonWindow.convertToScreen(button.frame)
        let panelSize = panel.frame.size
        // Anchor: right-align with button, 6pt gap below the menu bar.
        var x = buttonFrameOnScreen.maxX - panelSize.width
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - panelSize.width - 8)
        let y = buttonFrameOnScreen.minY - panelSize.height - 6
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    // MARK: quick-input panel

    private func showQuickInputPanel() {
        menuPanel?.dismiss()

        let panel: FloatingPanelWindow
        if let existing = quickInputPanel {
            panel = existing
        } else {
            panel = FloatingPanelWindow(size: CGSize(width: 720, height: 112), cornerRadius: 14) {
                QuickInputPanelView(
                    store: self.store,
                    onOpenChat: { [weak self] in
                        self?.quickInputPanel?.dismiss()
                        self?.openMainWindow()
                        self?.store.openSection(.chat)
                    },
                    onDismiss: { [weak self] in
                        self?.quickInputPanel?.dismiss()
                    }
                )
            }
            panel.onDismiss = { [weak self, weak panel] in
                panel?.dismiss()
                // Clear any transient state so the next open is clean.
                self?.store.resetQuickInput()
            }
            quickInputPanel = panel
        }

        positionQuickInputPanel(panel)
        panel.present(at: panel.frame.origin)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func positionQuickInputPanel(_ panel: FloatingPanelWindow) {
        let screen = NSScreen.main ?? statusItem?.button?.window?.screen ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        // Sits in the upper third, leaving room for the latest-result card
        // when it expands below.
        let y = visible.maxY - (visible.height * 0.28) - size.height
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    // MARK: bundled icon

    private static func statusIcon() -> NSImage {
        if let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "GeeAgent") {
            image.isTemplate = true
            return image
        }
        // Fallback to a plain square if the symbol isn't available.
        return NSImage(size: NSSize(width: 18, height: 18))
    }
}

private extension NSMenuItem {
    @discardableResult
    func configured(
        target: AnyObject,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        self.target = target
        self.keyEquivalentModifierMask = modifiers
        return self
    }
}
