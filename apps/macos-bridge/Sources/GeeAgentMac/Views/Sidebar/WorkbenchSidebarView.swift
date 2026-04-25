import SwiftUI

struct WorkbenchSidebarView: View {
    @Bindable var store: WorkbenchStore

    private var sectionSelection: Binding<WorkbenchSection?> {
        Binding(
            get: { store.selectedSection },
            set: { store.selectedSection = $0 ?? .home }
        )
    }

    var body: some View {
        List(WorkbenchSection.allCases, selection: sectionSelection) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("GeeAgent")
    }
}
