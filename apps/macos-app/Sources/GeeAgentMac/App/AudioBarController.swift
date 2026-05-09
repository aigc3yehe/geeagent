import AppKit
import SwiftUI

@MainActor
final class AudioBarController {
    private let store: WorkbenchStore
    private var panel: FloatingPanelWindow?
    private var shortcutRegistrar: GlobalShortcutRegistrar?

    init(store: WorkbenchStore) {
        self.store = store
    }

    func install() {
        guard shortcutRegistrar == nil else { return }
        shortcutRegistrar = GlobalShortcutRegistrar(
            bindings: GlobalShortcutRegistrar.Binding.audioCaptureBindings,
            hotKeySignature: OSType(UInt32(ascii: "GAUD")),
            hotKeyIDBase: 1,
            logLabel: "audio-capture"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleAudioBar()
            }
        }
        shortcutRegistrar?.register()
    }

    func uninstall() {
        shortcutRegistrar?.unregister()
        shortcutRegistrar = nil
        panel?.close()
        panel = nil
    }

    func toggleAudioBar() {
        if let panel, panel.isVisible {
            if panel.isKeyWindow {
                panel.dismiss()
            } else {
                position(panel)
                panel.present(at: panel.frame.origin)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }
        showAudioBar()
    }

    func showAudioBar() {
        let panel: FloatingPanelWindow
        if let existing = self.panel {
            panel = existing
        } else {
            panel = FloatingPanelWindow(
                size: CGSize(width: 680, height: 286),
                cornerRadius: 14,
                level: .statusBar,
                dismissesOnResignKey: false
            ) {
                AudioCaptureBarView(
                    audio: self.store.audioCapture,
                    onDismiss: { [weak self] in
                        self?.panel?.dismiss()
                    }
                )
            }
            panel.onDismiss = { [weak panel] in panel?.dismiss() }
            self.panel = panel
        }

        position(panel)
        panel.present(at: panel.frame.origin)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func position(_ panel: FloatingPanelWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - (visible.height * 0.28) - size.height
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }
}
