import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared store wired through the environment so the menu-bar controller
    /// and the main window point at the same snapshot.
    let workbenchStore: WorkbenchStore = WorkbenchStore(runtimeClient: NativeWorkbenchRuntimeClient())
    lazy var live2DDesktopCompanionController = Live2DDesktopCompanionController(store: workbenchStore)
    private var menuBarController: MenuBarController?
    private var audioBarController: AudioBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GeeTypography.registerBundledFonts()
        Self.presentMainWindow()
        Self.presentMainWindow(after: 0.15)

        let audioController = AudioBarController(store: workbenchStore)
        audioController.install()
        self.audioBarController = audioController

        let controller = MenuBarController(store: workbenchStore, audioBarController: audioController)
        controller.install()
        self.menuBarController = controller
        live2DDesktopCompanionController.quickInputPresenter = { [weak controller] in
            controller?.presentQuickInput()
        }
        live2DDesktopCompanionController.audioCapturePresenter = { [weak audioController] in
            audioController?.showAudioBar()
        }

        let store = workbenchStore
        Task { @MainActor in
            Self.presentMainWindow()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            store.startEnabledGearBackgroundServices()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.presentMainWindow()
        Self.presentMainWindow(after: 0.15)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        TelegramBridgeGearStore.shared.stopInboundService()
        live2DDesktopCompanionController.hide()
        workbenchStore.shutdownRuntime()
        menuBarController?.uninstall()
        audioBarController?.uninstall()
    }

    static func presentMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let window = NSApp.windows.first(where: isMainWorkbenchWindow) else {
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func presentMainWindow(after delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            presentMainWindow()
        }
    }

    private static func isMainWorkbenchWindow(_ window: NSWindow) -> Bool {
        window.contentViewController != nil &&
            !(window is FloatingPanelWindow) &&
            window.title == "GeeAgent"
    }
}

@main
struct GeeAgentMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("GeeAgent", id: "main") {
            WorkbenchRootView(
                store: appDelegate.workbenchStore,
                live2DDesktopCompanionController: appDelegate.live2DDesktopCompanionController
            )
        }
        .defaultSize(width: 1380, height: 860)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        GearHostNativeWindowScenes()
    }
}
