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
