import SwiftUI

struct LogsView: View {
    @Bindable var store: WorkbenchStore
    @State private var selectedTab: LogsTab = .agentWork

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Logs")
                    .font(.geeDisplaySemibold(22))

                Spacer()

                Picker("Logs", selection: $selectedTab) {
                    ForEach(LogsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            switch selectedTab {
            case .agentWork:
                TasksView(store: store)
            case .systemPanes:
                systemPanes
            }
        }
        .navigationTitle("Logs")
    }

    private var systemPanes: some View {
        List(selection: $store.selectedSettingsPaneID) {
            ForEach(store.settingsPanes) { pane in
                SettingsPaneLogRow(pane: pane)
                    .tag(pane.id)
            }
        }
        .listStyle(.inset)
    }
}

private enum LogsTab: String, CaseIterable, Identifiable {
    case agentWork
    case systemPanes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agentWork: "Agent Work"
        case .systemPanes: "System"
        }
    }
}

private struct SettingsPaneLogRow: View {
    var pane: SettingsPaneSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.title)
                        .font(.geeBodyMedium(14))
                    Text(pane.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !pane.items.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    ForEach(pane.items) { item in
                        GridRow {
                            Text(item.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(item.value)
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.82))
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 6)
    }
}
