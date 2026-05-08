import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared store wired through the environment so the menu-bar controller
    /// and the main window point at the same snapshot.
    let workbenchStore: WorkbenchStore = WorkbenchStore(runtimeClient: NativeWorkbenchRuntimeClient())
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GeeTypography.registerBundledFonts()
        Self.presentMainWindow()
        Self.presentMainWindow(after: 0.15)

        let controller = MenuBarController(store: workbenchStore)
        controller.install()
        self.menuBarController = controller

        let store = workbenchStore
        Task { @MainActor in
            Self.presentMainWindow()
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            TelegramBridgeGearStore.shared.startInboundService { [weak store] payload in
                guard let store else {
                    throw RuntimeProcessError.runtimeUnavailable("GeeAgent workbench store is unavailable for Telegram channel ingress.")
                }
                return try await store.submitTelegramChannelMessage(payload)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.presentMainWindow()
        Self.presentMainWindow(after: 0.15)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        TelegramBridgeGearStore.shared.stopInboundService()
        workbenchStore.shutdownRuntime()
        menuBarController?.uninstall()
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
            WorkbenchRootView(store: appDelegate.workbenchStore)
        }
        .defaultSize(width: 1380, height: 860)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        GearHostNativeWindowScenes()
    }
}
