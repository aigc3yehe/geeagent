import SwiftUI

struct HomeStageModule: View {
    @Bindable var store: WorkbenchStore
    var live2DDesktopCompanionController: Live2DDesktopCompanionController?

    var body: some View {
        HomeView(
            store: store,
            live2DDesktopCompanionController: live2DDesktopCompanionController
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id("home-stage-module")
    }
}
