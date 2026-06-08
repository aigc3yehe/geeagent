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
                case .telegram:
                    telegramInspector
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
        .navigationTitle(store.localizedString("inspector.title", defaultValue: "Inspector"))
    }

    @ViewBuilder
    private var homeInspector: some View {
        if let item = store.selectedHomeItem {
            WorkbenchInspectorCard(title: item.title) {
                LabeledContent(store.localizedString("inspector.label.type", defaultValue: "Type"), value: item.kind.title)
                LabeledContent(store.localizedString("inspector.label.status", defaultValue: "Status"), value: item.statusLabel)
                LabeledContent(store.localizedString("inspector.label.action", defaultValue: "Action"), value: item.actionLabel)
                Text(item.detail)
                    .foregroundStyle(.secondary)
            }

            WorkbenchInspectorCard(title: store.localizedString("inspector.overview", defaultValue: "Overview")) {
                LabeledContent(store.localizedString("inspector.label.openTasks", defaultValue: "Open tasks"), value: "\(store.openTasksCount)")
                LabeledContent(store.localizedString("inspector.label.approvals", defaultValue: "Approvals"), value: "\(store.approvalsCount)")
                LabeledContent(store.localizedString("inspector.label.nextAutomation", defaultValue: "Next automation"), value: store.homeSummary.nextAutomationLabel)
                LabeledContent(store.localizedString("inspector.label.installedGears", defaultValue: "Installed gears"), value: "\(store.installedApps.count)")
            }
        }
    }

    private var telegramInspector: some View {
        WorkbenchInspectorCard(title: "Telegram") {
            LabeledContent(store.localizedString("inspector.label.gear", defaultValue: "Gear"), value: "telegram.bridge")
            LabeledContent(store.localizedString("inspector.label.surface", defaultValue: "Surface"), value: store.localizedString("inspector.surface.conversationLog", defaultValue: "Conversation log"))
        }
    }

    @ViewBuilder
    private var chatInspector: some View {
        if let conversation = store.selectedDisplayConversation {
            WorkbenchInspectorCard(title: conversation.title) {
                LabeledContent(store.localizedString("inspector.label.preview", defaultValue: "Preview"), value: conversation.previewText)
                LabeledContent(store.localizedString("inspector.label.lastMessage", defaultValue: "Last message"), value: conversation.lastActivityLabel)
            }

            WorkbenchInspectorCard(title: store.localizedString("inspector.linkedContext", defaultValue: "Linked Context")) {
                if let linkedTaskTitle = conversation.linkedTaskTitle {
                    LabeledContent(store.localizedString("common.task", defaultValue: "Task"), value: linkedTaskTitle)
                }
                if let linkedAppName = conversation.linkedAppName {
                    LabeledContent(store.localizedString("common.app", defaultValue: "App"), value: linkedAppName)
                }
                LabeledContent(store.localizedString("inspector.label.messages", defaultValue: "Messages"), value: "\(conversation.messages.count)")
            }

            let attachments = inputAttachments(in: conversation)
            if !attachments.isEmpty {
                WorkbenchInspectorCard(title: store.localizedString("inspector.inputAttachments", defaultValue: "Input Attachments")) {
                    LabeledContent(store.localizedString("inspector.label.count", defaultValue: "Count"), value: "\(attachments.count)")
                    ForEach(attachments) { attachment in
                        Divider()
                        inspectorAttachment(attachment)
                    }
                }
            }

            if let runtimeRunSummary = conversation.runtimeRunSummary {
                runtimeRunInspector(runtimeRunSummary)
            }
        }
    }

    private func runtimeRunInspector(_ summary: ConversationRuntimeRunSummary) -> some View {
        WorkbenchInspectorCard(title: store.localizedString("inspector.runtimeRun", defaultValue: "Runtime Run")) {
            HStack(alignment: .firstTextBaseline) {
                LabeledContent(store.localizedString("inspector.label.run", defaultValue: "Run"), value: compactRunID(summary.runID))
                Spacer(minLength: 8)
                Button {
                    store.refreshSelectedRuntimeRunInspector(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help(store.localizedString("inspector.refreshHelp", defaultValue: "Refresh runtime projection"))
            }

            LabeledContent(store.localizedString("inspector.label.events", defaultValue: "Events"), value: runtimeEventRange(summary))
            if let lastEventKind = summary.lastEventKind {
                LabeledContent(store.localizedString("inspector.label.latest", defaultValue: "Latest"), value: compactRuntimeLabel(lastEventKind))
            }

            if store.isLoadingRuntimeRunInspector {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(store.localizedString("inspector.loadingProjection", defaultValue: "Loading projection"))
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
            LabeledContent(store.localizedString("inspector.label.state", defaultValue: "State"), value: "\(compactRuntimeLabel(wait.waitKind)) · \(compactRuntimeLabel(wait.status))")
            Text(wait.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let pendingHostAction = wait.evidence.pendingHostActionIDs.first {
                LabeledContent(store.localizedString("inspector.label.hostAction", defaultValue: "Host action"), value: compactRunID(pendingHostAction))
            }
            if let pendingTool = wait.evidence.pendingToolUseID {
                LabeledContent(store.localizedString("inspector.label.tool", defaultValue: "Tool"), value: compactRunID(pendingTool))
            }
            if let pendingApproval = wait.evidence.pendingApprovalID {
                LabeledContent(store.localizedString("task.status.approval", defaultValue: "Approval"), value: compactRunID(pendingApproval))
            }
        }
    }

    private func runtimeProjectionSummary(_ projection: WorkbenchRuntimeRunProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(store.localizedString("inspector.label.projection", defaultValue: "Projection"), value: rowCountLabel(projection.rowCount))
            if !projection.artifactRefs.isEmpty {
                LabeledContent(store.localizedString("inspector.label.artifacts", defaultValue: "Artifacts"), value: artifactSummary(projection.artifactRefs))
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
                if let toolName = row.toolName, !toolName.isEmpty, row.projectionKind == "tool_result" {
                    Text(toolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !row.attachmentIDs.isEmpty {
                    Text(attachmentCountLabel(row.attachmentIDs.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !row.artifactIDs.isEmpty {
                    Text(artifactCountLabel(row.artifactIDs.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func inputAttachments(in conversation: ConversationThread) -> [ConversationMessageAttachment] {
        conversation.visibleMessages
            .filter { $0.role == .user && $0.kind == .chat }
            .flatMap(\.attachments)
    }

    private func inspectorAttachment(_ attachment: ConversationMessageAttachment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: attachment.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(attachmentTint(attachment))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(attachment.kind.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(attachment.inspectorDetailItems) { detail in
                LabeledContent(detail.label, value: detail.value)
                    .font(.caption)
            }
        }
    }

    private func attachmentTint(_ attachment: ConversationMessageAttachment) -> Color {
        switch attachment.status {
        case .failed:
            return .red
        case .degraded:
            return .orange
        case .ready:
            switch attachment.kind {
            case .image:
                return .blue
            case .directory:
                return .green
            case .file, .unknown:
                return .secondary
            }
        }
    }

    @ViewBuilder
    private var taskInspector: some View {
        if let task = store.selectedTask {
            WorkbenchInspectorCard(title: task.title) {
                LabeledContent(store.localizedString("inspector.label.status", defaultValue: "Status"), value: task.status.title)
                LabeledContent(store.localizedString("inspector.label.priority", defaultValue: "Priority"), value: task.priorityLabel)
                LabeledContent(store.localizedString("inspector.label.owner", defaultValue: "Owner"), value: task.ownerLabel)
                LabeledContent(store.localizedString("common.app", defaultValue: "App"), value: task.appName)
                LabeledContent(store.localizedString("inspector.label.due", defaultValue: "Due"), value: task.dueLabel)
            }

            WorkbenchInspectorCard(title: store.localizedString("inspector.execution", defaultValue: "Execution")) {
                LabeledContent(store.localizedString("inspector.label.updated", defaultValue: "Updated"), value: task.updatedLabel)
                LabeledContent(store.localizedString("inspector.label.artifacts", defaultValue: "Artifacts"), value: "\(task.artifactCount)")
                Text(task.summary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var automationInspector: some View {
        if let automation = store.selectedAutomation {
            WorkbenchInspectorCard(title: automation.name) {
                LabeledContent(store.localizedString("inspector.label.status", defaultValue: "Status"), value: automation.status.title)
                LabeledContent(store.localizedString("inspector.label.scope", defaultValue: "Scope"), value: automation.scopeLabel)
                LabeledContent(store.localizedString("inspector.label.schedule", defaultValue: "Schedule"), value: automation.scheduleLabel)
                LabeledContent(store.localizedString("inspector.label.nextRun", defaultValue: "Next run"), value: automation.nextRunLabel)
                LabeledContent(store.localizedString("inspector.label.lastRun", defaultValue: "Last run"), value: automation.lastRunLabel)
            }

            WorkbenchInspectorCard(title: store.localizedString("inspector.runContext", defaultValue: "Run Context")) {
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
                    LabeledContent(store.localizedString("inspector.label.surface", defaultValue: "Surface"), value: store.localizedString("inspector.surface.agentSkin", defaultValue: "Agent Skin"))
                    LabeledContent(store.localizedString("inspector.label.tone", defaultValue: "Tone"), value: skin.toneLabel)
                    LabeledContent(store.localizedString("inspector.label.status", defaultValue: "Status"), value: skin.activationLabel)
                    Text(skin.summary)
                        .foregroundStyle(.secondary)
                }
            }
        case .some(.app(_)), .none:
            if let app = store.selectedInstalledApp {
                WorkbenchInspectorCard(title: app.name) {
                    LabeledContent(store.localizedString("inspector.label.surface", defaultValue: "Surface"), value: store.localizedString("inspector.surface.installedApp", defaultValue: "Installed App"))
                    LabeledContent(store.localizedString("inspector.label.category", defaultValue: "Category"), value: app.categoryLabel)
                    LabeledContent(store.localizedString("inspector.label.state", defaultValue: "State"), value: app.installState.title)
                    LabeledContent(store.localizedString("inspector.label.version", defaultValue: "Version"), value: app.versionLabel)
                    LabeledContent(store.localizedString("inspector.label.health", defaultValue: "Health"), value: app.healthLabel)
                }

                WorkbenchInspectorCard(title: store.localizedString("inspector.capabilities", defaultValue: "Capabilities")) {
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
                LabeledContent(store.localizedString("inspector.label.source", defaultValue: "Source"), value: profile.source.title)
                LabeledContent(store.localizedString("inspector.label.appearance", defaultValue: "Appearance"), value: profile.appearanceTitle)
                LabeledContent(store.localizedString("inspector.label.version", defaultValue: "Version"), value: profile.version)
                LabeledContent(store.localizedString("inspector.label.skills", defaultValue: "Skills"), value: profile.skillsSummary)
                LabeledContent(store.localizedString("inspector.label.tools", defaultValue: "Tools"), value: profile.allowedToolsSummary)
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

    private func rowCountLabel(_ count: Int) -> String {
        if count == 1 {
            return store.localizedFormat("inspector.rows.count.one", defaultValue: "%d row", count)
        }
        return store.localizedFormat("inspector.rows.count.other", defaultValue: "%d rows", count)
    }

    private func attachmentCountLabel(_ count: Int) -> String {
        if count == 1 {
            return store.localizedFormat("inspector.attachments.count.one", defaultValue: "%d attachment", count)
        }
        return store.localizedFormat("inspector.attachments.count.other", defaultValue: "%d attachments", count)
    }

    private func artifactCountLabel(_ count: Int) -> String {
        if count == 1 {
            return store.localizedFormat("inspector.artifacts.count.one", defaultValue: "%d artifact", count)
        }
        return store.localizedFormat("inspector.artifacts.count.other", defaultValue: "%d artifacts", count)
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
            parts.append(store.localizedFormat("inspector.diagnostics.duplicate", defaultValue: "%d duplicate", diagnostics.duplicateEventIDs.count))
        }
        if !diagnostics.missingParentEventIDs.isEmpty {
            parts.append(store.localizedFormat("inspector.diagnostics.missingParent", defaultValue: "%d missing parent", diagnostics.missingParentEventIDs.count))
        }
        if !diagnostics.missingSequenceNumbers.isEmpty {
            parts.append(store.localizedFormat("inspector.diagnostics.missingSequence", defaultValue: "%d missing sequence", diagnostics.missingSequenceNumbers.count))
        }
        if !diagnostics.outOfOrderEventIDs.isEmpty {
            parts.append(store.localizedFormat("inspector.diagnostics.outOfOrder", defaultValue: "%d out of order", diagnostics.outOfOrderEventIDs.count))
        }
        return parts.isEmpty ? store.localizedString("inspector.diagnostics.none", defaultValue: "No replay diagnostics") : parts.joined(separator: " · ")
    }
}
