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
}
