import SwiftUI

struct FunctionalStageModule: View {
    @Bindable var store: WorkbenchStore
    var section: WorkbenchSection

    var body: some View {
        sectionContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .background(
                        .regularMaterial.opacity(0.78),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.9)
                    )
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
                    .blendMode(.screen)
            }
            .shadow(color: Color.black.opacity(0.24), radius: 8, x: 0, y: 4)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .id("functional-stage-\(section.rawValue)")
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .home:
            EmptyView()
        case .chat:
            ChatView(store: store)
        case .tasks:
            LogsView(store: store)
        case .automations:
            AutomationsView(store: store)
        case .apps:
            EmptyView()
        case .agents:
            AgentsView(store: store)
        case .logs:
            LogsView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }
}
