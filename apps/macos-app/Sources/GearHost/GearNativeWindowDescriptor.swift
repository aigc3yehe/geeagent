import Foundation
import SwiftUI

struct GearNativeWindowDescriptor: Hashable, Sendable {
    var gearID: String
    var windowID: String
    var title: String
    var defaultWidth: CGFloat
    var defaultHeight: CGFloat
}

struct GearHostNativeWindowScenes: Scene {
    var body: some Scene {
        Window(GearHost.mediaLibraryWindowDescriptor.title, id: GearHost.mediaLibraryWindowDescriptor.windowID) {
            GearHost.makeNativeWindowView(for: GearHost.mediaLibraryWindowDescriptor.gearID)
        }
        .defaultSize(
            width: GearHost.mediaLibraryWindowDescriptor.defaultWidth,
            height: GearHost.mediaLibraryWindowDescriptor.defaultHeight
        )

        Window(GearHost.hyperframesStudioWindowDescriptor.title, id: GearHost.hyperframesStudioWindowDescriptor.windowID) {
            GearHost.makeNativeWindowView(for: GearHost.hyperframesStudioWindowDescriptor.gearID)
        }
        .defaultSize(
            width: GearHost.hyperframesStudioWindowDescriptor.defaultWidth,
            height: GearHost.hyperframesStudioWindowDescriptor.defaultHeight
        )

        Window(GearHost.smartYTMediaWindowDescriptor.title, id: GearHost.smartYTMediaWindowDescriptor.windowID) {
            GearHost.makeNativeWindowView(for: GearHost.smartYTMediaWindowDescriptor.gearID)
        }
        .defaultSize(
            width: GearHost.smartYTMediaWindowDescriptor.defaultWidth,
            height: GearHost.smartYTMediaWindowDescriptor.defaultHeight
        )

        Window(GearHost.twitterCaptureWindowDescriptor.title, id: GearHost.twitterCaptureWindowDescriptor.windowID) {
            GearHost.makeNativeWindowView(for: GearHost.twitterCaptureWindowDescriptor.gearID)
        }
        .defaultSize(
            width: GearHost.twitterCaptureWindowDescriptor.defaultWidth,
            height: GearHost.twitterCaptureWindowDescriptor.defaultHeight
        )

        Window(GearHost.bookmarkVaultWindowDescriptor.title, id: GearHost.bookmarkVaultWindowDescriptor.windowID) {
            GearHost.makeNativeWindowView(for: GearHost.bookmarkVaultWindowDescriptor.gearID)
        }
        .defaultSize(
            width: GearHost.bookmarkVaultWindowDescriptor.defaultWidth,
            height: GearHost.bookmarkVaultWindowDescriptor.defaultHeight
        )

        Window(GearHost.weSpyReaderWindowDescriptor.title, id: GearHost.weSpyReaderWindowDescriptor.windowID) {
            GearHost.makeNativeWindowView(for: GearHost.weSpyReaderWindowDescriptor.gearID)
        }
        .defaultSize(
            width: GearHost.weSpyReaderWindowDescriptor.defaultWidth,
            height: GearHost.weSpyReaderWindowDescriptor.defaultHeight
        )

        Window(GearHost.mediaGeneratorWindowDescriptor.title, id: GearHost.mediaGeneratorWindowDescriptor.windowID) {
            GearHost.makeNativeWindowView(for: GearHost.mediaGeneratorWindowDescriptor.gearID)
        }
        .defaultSize(
            width: GearHost.mediaGeneratorWindowDescriptor.defaultWidth,
            height: GearHost.mediaGeneratorWindowDescriptor.defaultHeight
        )

        Window(GearHost.appIconForgeWindowDescriptor.title, id: GearHost.appIconForgeWindowDescriptor.windowID) {
            GearHost.makeNativeWindowView(for: GearHost.appIconForgeWindowDescriptor.gearID)
        }
        .defaultSize(
            width: GearHost.appIconForgeWindowDescriptor.defaultWidth,
            height: GearHost.appIconForgeWindowDescriptor.defaultHeight
        )

        Window(GearHost.telegramBridgeWindowDescriptor.title, id: GearHost.telegramBridgeWindowDescriptor.windowID) {
            GearHost.makeNativeWindowView(for: GearHost.telegramBridgeWindowDescriptor.gearID)
        }
        .defaultSize(
            width: GearHost.telegramBridgeWindowDescriptor.defaultWidth,
            height: GearHost.telegramBridgeWindowDescriptor.defaultHeight
        )

        Window(GearHost.todoManagerWindowDescriptor.title, id: GearHost.todoManagerWindowDescriptor.windowID) {
            GearHost.makeNativeWindowView(for: GearHost.todoManagerWindowDescriptor.gearID)
        }
        .defaultSize(
            width: GearHost.todoManagerWindowDescriptor.defaultWidth,
            height: GearHost.todoManagerWindowDescriptor.defaultHeight
        )
    }
}

struct GearUnavailableWindowView: View {
    var title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox.circle")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text("This gear is not installed, enabled, or ready to open.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
