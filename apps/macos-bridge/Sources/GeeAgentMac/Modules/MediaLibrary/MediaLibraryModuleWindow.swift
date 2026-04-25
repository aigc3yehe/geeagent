import SwiftUI

struct MediaLibraryModuleWindow: View {
    var body: some View {
        MediaLibraryModuleView()
            .frame(minWidth: 920, minHeight: 620)
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}
