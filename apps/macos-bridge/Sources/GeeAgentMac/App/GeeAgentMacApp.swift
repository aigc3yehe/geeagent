import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared store wired through the environment so the menu-bar controller
    /// and the main window point at the same snapshot.
    let workbenchStore: WorkbenchStore = WorkbenchStore(runtimeClient: RustWorkbenchRuntimeClient())
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GeeTypography.registerBundledFonts()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let controller = MenuBarController(store: workbenchStore)
        controller.install()
        self.menuBarController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
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

        Window("Media Library", id: GearRegistry.mediaLibraryWindowID) {
            MediaLibraryModuleWindow()
        }
        .defaultSize(width: 1180, height: 780)

        Window("Hyperframes Studio", id: GearRegistry.hyperframesStudioWindowID) {
            HyperframesStudioModuleWindow()
        }
        .defaultSize(width: 1280, height: 820)
    }
}
