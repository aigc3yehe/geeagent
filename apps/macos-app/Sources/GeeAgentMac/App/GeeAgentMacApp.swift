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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let controller = MenuBarController(store: workbenchStore)
        controller.install()
        self.menuBarController = controller

        let store = workbenchStore
        TelegramBridgeGearStore.shared.startInboundService { [weak store] payload in
            guard let store else {
                throw RuntimeProcessError.runtimeUnavailable("GeeAgent workbench store is unavailable for Telegram channel ingress.")
            }
            return try await store.submitTelegramChannelMessage(payload)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        TelegramBridgeGearStore.shared.stopInboundService()
        workbenchStore.shutdownRuntime()
        menuBarController?.uninstall()
    }
}

@main
struct GeeAgentMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("GeeAgent") {
            WorkbenchRootView(store: appDelegate.workbenchStore)
        }
        .defaultSize(width: 1380, height: 860)

        GearHostNativeWindowScenes()
    }
}
