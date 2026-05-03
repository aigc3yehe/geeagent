import SwiftUI

struct WorkbenchInspectorView: View {
    @Bindable var store: WorkbenchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch store.selectedSection {
                case .home:
                    homeInspector
                case .chat:
                    chatInspector
                case .tasks:
                    taskInspector
                case .logs:
                    taskInspector
                case .automations:
                    automationInspector
                case .apps:
                    appsInspector
                case .agents:
                    agentsInspector
                case .settings:
                    settingsInspector
                }
            }
            .padding()
        }
        .navigationTitle("Inspector")
    }

    @ViewBuilder
    private var homeInspector: some View {
        if let item = store.selectedHomeItem {
            WorkbenchInspectorCard(title: item.title) {
                LabeledContent("Type", value: item.kind.title)
                LabeledContent("Status", value: item.statusLabel)
                LabeledContent("Action", value: item.actionLabel)
                Text(item.detail)
                    .foregroundStyle(.secondary)
            }

            WorkbenchInspectorCard(title: "Overview") {
                LabeledContent("Open tasks", value: "\(store.openTasksCount)")
                LabeledContent("Approvals", value: "\(store.approvalsCount)")
                LabeledContent("Next automation", value: store.homeSummary.nextAutomationLabel)
                LabeledContent("Installed gears", value: "\(store.installedApps.count)")
            }
        }
    }

    @ViewBuilder
    private var chatInspector: some View {
        if let conversation = store.selectedConversation {
            WorkbenchInspectorCard(title: conversation.title) {
                LabeledContent("Preview", value: conversation.previewText)
                LabeledContent("Last message", value: conversation.lastActivityLabel)
            }

            WorkbenchInspectorCard(title: "Linked Context") {
                if let linkedTaskTitle = conversation.linkedTaskTitle {
                    LabeledContent("Task", value: linkedTaskTitle)
                }
                if let linkedAppName = conversation.linkedAppName {
                    LabeledContent("App", value: linkedAppName)
                }
                LabeledContent("Messages", value: "\(conversation.messages.count)")
            }

            if let runtimeRunSummary = conversation.runtimeRunSummary {
                runtimeRunInspector(runtimeRunSummary)
            }
        }
    }

    private func runtimeRunInspector(_ summary: ConversationRuntimeRunSummary) -> some View {
        WorkbenchInspectorCard(title: "Runtime Run") {
            HStack(alignment: .firstTextBaseline) {
                LabeledContent("Run", value: compactRunID(summary.runID))
                Spacer(minLength: 8)
                Button {
                    store.refreshSelectedRuntimeRunInspector(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help("Refresh runtime projection")
            }

            LabeledContent("Events", value: runtimeEventRange(summary))
            if let lastEventKind = summary.lastEventKind {
                LabeledContent("Latest", value: compactRuntimeLabel(lastEventKind))
            }

            if store.isLoadingRuntimeRunInspector {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading projection")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            if let error = store.runtimeRunInspectorErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            if let wait = store.selectedRuntimeRunWait, wait.runID == summary.runID {
                runtimeStateSummary(wait)
            }

            if let projection = store.selectedRuntimeRunProjection, projection.runID == summary.runID {
                runtimeProjectionSummary(projection)
            }
        }
        .task(id: summary.runID) {
            store.refreshSelectedRuntimeRunInspector()
        }
    }

    private func runtimeStateSummary(_ wait: WorkbenchRuntimeRunWaitClassification) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("State", value: "\(compactRuntimeLabel(wait.waitKind)) · \(compactRuntimeLabel(wait.status))")
            Text(wait.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let pendingHostAction = wait.evidence.pendingHostActionIDs.first {
                LabeledContent("Host action", value: compactRunID(pendingHostAction))
            }
            if let pendingTool = wait.evidence.pendingToolUseID {
                LabeledContent("Tool", value: compactRunID(pendingTool))
            }
            if let pendingApproval = wait.evidence.pendingApprovalID {
                LabeledContent("Approval", value: compactRunID(pendingApproval))
            }
        }
    }

    private func runtimeProjectionSummary(_ projection: WorkbenchRuntimeRunProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Projection", value: "\(projection.rowCount) rows")
            if !projection.artifactRefs.isEmpty {
                LabeledContent("Artifacts", value: artifactSummary(projection.artifactRefs))
            }
            if projection.hasDiagnostics {
                Text(runtimeDiagnosticsSummary(projection.diagnostics))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
            ForEach(projection.rows.prefix(5)) { row in
                runtimeProjectionRow(row)
            }
        }
    }

    private func runtimeProjectionRow(_ row: WorkbenchRuntimeRunProjectionRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("#\(row.sequence)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.label)
                        .font(.caption.weight(.semibold))
                    if let status = row.status, !status.isEmpty {
                        Text(compactRuntimeLabel(status))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
                Text(row.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !row.artifactIDs.isEmpty {
                    Text("\(row.artifactIDs.count) artifact\(row.artifactIDs.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var taskInspector: some View {
        if let task = store.selectedTask {
            WorkbenchInspectorCard(title: task.title) {
                LabeledContent("Status", value: task.status.title)
                LabeledContent("Priority", value: task.priorityLabel)
                LabeledContent("Owner", value: task.ownerLabel)
                LabeledContent("App", value: task.appName)
                LabeledContent("Due", value: task.dueLabel)
            }

            WorkbenchInspectorCard(title: "Execution") {
                LabeledContent("Updated", value: task.updatedLabel)
                LabeledContent("Artifacts", value: "\(task.artifactCount)")
                Text(task.summary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var automationInspector: some View {
        if let automation = store.selectedAutomation {
            WorkbenchInspectorCard(title: automation.name) {
                LabeledContent("Status", value: automation.status.title)
                LabeledContent("Scope", value: automation.scopeLabel)
                LabeledContent("Schedule", value: automation.scheduleLabel)
                LabeledContent("Next run", value: automation.nextRunLabel)
                LabeledContent("Last run", value: automation.lastRunLabel)
            }

            WorkbenchInspectorCard(title: "Run Context") {
                Text(automation.summary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var appsInspector: some View {
        switch store.selectedExtension {
        case .some(.skin(_)):
            if let skin = store.selectedAgentSkin {
                WorkbenchInspectorCard(title: skin.name) {
                    LabeledContent("Surface", value: "Agent Skin")
                    LabeledContent("Tone", value: skin.toneLabel)
                    LabeledContent("Status", value: skin.activationLabel)
                    Text(skin.summary)
                        .foregroundStyle(.secondary)
                }
            }
        case .some(.app(_)), .none:
            if let app = store.selectedInstalledApp {
                WorkbenchInspectorCard(title: app.name) {
                    LabeledContent("Surface", value: "Installed App")
                    LabeledContent("Category", value: app.categoryLabel)
                    LabeledContent("State", value: app.installState.title)
                    LabeledContent("Version", value: app.versionLabel)
                    LabeledContent("Health", value: app.healthLabel)
                }

                WorkbenchInspectorCard(title: "Capabilities") {
                    Text(app.summary)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var agentsInspector: some View {
        if let profile = store.selectedAgentProfile {
            WorkbenchInspectorCard(title: profile.name) {
                LabeledContent("Source", value: profile.source.title)
                LabeledContent("Appearance", value: profile.appearanceTitle)
                LabeledContent("Version", value: profile.version)
                LabeledContent("Skills", value: profile.skillsSummary)
                LabeledContent("Tools", value: profile.allowedToolsSummary)
                Text(profile.personalityPrompt)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var settingsInspector: some View {
        if let pane = store.selectedSettingsPane {
            WorkbenchInspectorCard(title: pane.title) {
                Text(pane.summary)
                    .foregroundStyle(.secondary)
                ForEach(pane.items) { item in
                    Divider()
                    LabeledContent(item.label, value: item.value)
                }
            }
        }
    }

    private func runtimeEventRange(_ summary: ConversationRuntimeRunSummary) -> String {
        guard let first = summary.firstSequence, let last = summary.lastSequence else {
            return "\(summary.eventCount)"
        }
        if first == last {
            return "\(summary.eventCount) · #\(last)"
        }
        return "\(summary.eventCount) · #\(first)-#\(last)"
    }

    private func compactRunID(_ value: String) -> String {
        guard value.count > 18 else {
            return value
        }
        return "\(value.prefix(8))…\(value.suffix(6))"
    }

    private func compactRuntimeLabel(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { part in
                String(part.prefix(1)).uppercased() + String(part.dropFirst())
            }
            .joined(separator: " ")
    }

    private func artifactSummary(_ artifacts: [WorkbenchRuntimeRunArtifactRef]) -> String {
        let visible = artifacts.prefix(2).map { artifact in
            let title = artifact.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = artifact.path?.split(separator: "/").last.map(String.init)
            let label = title?.isEmpty == false ? title! : fallback ?? artifact.artifactID
            if let sourceTool = artifact.sourceToolName, !sourceTool.isEmpty {
                return "\(label) · \(sourceTool)"
            }
            return label
        }
        let suffix = artifacts.count > visible.count ? " · +\(artifacts.count - visible.count)" : ""
        return "\(artifacts.count) · \(visible.joined(separator: " · "))\(suffix)"
    }

    private func runtimeDiagnosticsSummary(_ diagnostics: WorkbenchRuntimeRunDiagnostics) -> String {
        var parts = [String]()
        if !diagnostics.duplicateEventIDs.isEmpty {
            parts.append("\(diagnostics.duplicateEventIDs.count) duplicate")
        }
        if !diagnostics.missingParentEventIDs.isEmpty {
            parts.append("\(diagnostics.missingParentEventIDs.count) missing parent")
        }
        if !diagnostics.missingSequenceNumbers.isEmpty {
            parts.append("\(diagnostics.missingSequenceNumbers.count) missing sequence")
        }
        if !diagnostics.outOfOrderEventIDs.isEmpty {
            parts.append("\(diagnostics.outOfOrderEventIDs.count) out of order")
        }
        return parts.isEmpty ? "No replay diagnostics" : parts.joined(separator: " · ")
    }
}
