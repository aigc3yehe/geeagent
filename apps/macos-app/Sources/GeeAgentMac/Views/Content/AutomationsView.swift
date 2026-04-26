import SwiftUI

struct AutomationsView: View {
    @Bindable var store: WorkbenchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricsRow
                .padding(.horizontal)
                .padding(.top)

            List(selection: $store.selectedAutomationID) {
                ForEach(store.automations) { automation in
                    AutomationRow(automation: automation)
                        .tag(automation.id)
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Automations")
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            WorkbenchMetricTile(
                title: "Active",
                value: "\(store.automations.filter { $0.status == .active }.count)",
                systemImage: "play.circle"
            )
            WorkbenchMetricTile(
                title: "Attention",
                value: "\(store.automations.filter { $0.status == .attention }.count)",
                systemImage: "exclamationmark.circle"
            )
            WorkbenchMetricTile(
                title: "Paused",
                value: "\(store.automations.filter { $0.status == .paused }.count)",
                systemImage: "pause.circle"
            )
        }
    }
}

private struct AutomationRow: View {
    var automation: AutomationRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: automation.status.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(automation.name)
                    .font(.body.weight(.medium))

                Text(automation.summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label(automation.scopeLabel, systemImage: "tray.full")
                    Label(automation.scheduleLabel, systemImage: "calendar")
                    Text(automation.lastRunLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                WorkbenchStatusBadge(title: automation.status.title, systemImage: automation.status.systemImage)
                Text(automation.nextRunLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
