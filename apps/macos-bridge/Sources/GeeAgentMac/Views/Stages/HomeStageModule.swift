import SwiftUI

struct HomeStageModule: View {
    @Bindable var store: WorkbenchStore

    var body: some View {
        HomeView(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id("home-stage-module")
    }
}
