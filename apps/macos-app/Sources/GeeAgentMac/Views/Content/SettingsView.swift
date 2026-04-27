import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: WorkbenchStore
    @State private var rulePendingRemoval: TerminalPermissionRuleRecord?
    @State private var isConfirmingHighestAuthorization = false
    @State private var selectedProvider = ""
    @State private var modelName = ""
    @State private var skillSourceError: SettingsFeedbackMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                highestAuthorizationPanel
                    .padding(.horizontal)
                    .padding(.top)

                providerRoutingPanel
                    .padding(.horizontal)

                conversationRoutingPanel
                    .padding(.horizontal)

                skillSourcesPanel
                    .padding(.horizontal)

                terminalPermissionsPanel
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            syncRoutingDraft()
            if store.chatRoutingSettings == nil {
                store.loadChatRoutingSettings()
            }
        }
        .onChange(of: store.chatRoutingSettings) { _, _ in
            syncRoutingDraft()
        }
        .alert("Remove terminal rule?", isPresented: removalAlertBinding, presenting: rulePendingRemoval) { rule in
            Button("Cancel", role: .cancel) {
                rulePendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                store.deleteTerminalPermissionRule(rule.id)
                rulePendingRemoval = nil
            }
        } message: { rule in
            Text("Future matching terminal commands will return to the normal approval flow. Past runs are not changed.")
        }
        .alert("Enable highest authorization?", isPresented: $isConfirmingHighestAuthorization) {
            Button("Cancel", role: .cancel) {}
            Button("Enable", role: .destructive) {
                store.setHighestAuthorizationEnabled(true)
            }
        } message: {
            Text("When enabled, the agent will receive full computer-control permissions and will stop asking for approval. Are you sure you want to enable this mode?")
        }
        .alert(item: $skillSourceError) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var highestAuthorizationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Highest Authorization", systemImage: "lock.open.trianglebadge.exclamationmark")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Toggle("Highest Authorization", isOn: highestAuthorizationBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(store.isUpdatingHighestAuthorization)
            }

            Text("Off by default. When enabled, GeeAgent automatically approves computer-control and terminal permission requests initiated by the agent, without showing per-action approval prompts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(store.securityPreferences.highestAuthorizationEnabled ? "Enabled: the agent will execute approval-gated actions directly." : "Disabled: sensitive actions still go through approval cards.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(store.securityPreferences.highestAuthorizationEnabled ? Color.red : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (store.securityPreferences.highestAuthorizationEnabled ? Color.red : Color.secondary).opacity(0.12),
                    in: Capsule()
                )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var highestAuthorizationBinding: Binding<Bool> {
        Binding(
            get: { store.securityPreferences.highestAuthorizationEnabled },
            set: { enabled in
                if enabled {
                    isConfirmingHighestAuthorization = true
                } else {
                    store.setHighestAuthorizationEnabled(false)
                }
            }
        )
    }

    private var providerRoutingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Model Routing", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Text(store.runtimeStatus.state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(runtimeTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(runtimeTint.opacity(0.12), in: Capsule())
            }

            Text("Choose the provider and model GeeAgent should use for the default chat route.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Provider")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(providerOptions, id: \.self) { provider in
                            Text(provider).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                }

                GridRow {
                    Text("Model")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. gpt-5.4", text: $modelName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
            }

            HStack {
                if store.isLoadingChatRoutingSettings {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading routing settings…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let route = store.chatRoutingSettings?.selectedRouteClass {
                    Text("Current route: \(route.provider) / \(route.model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Routing settings are not loaded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reload") {
                    store.loadChatRoutingSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isLoadingChatRoutingSettings)

                Button("Save") {
                    store.saveDefaultChatRouting(provider: selectedProvider, model: modelName)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSaveRouting)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var conversationRoutingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Quick Input Destination", systemImage: "arrow.triangle.branch")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Toggle("Automatically choose conversation", isOn: $store.autoConversationRoutingEnabled)
                    .toggleStyle(.switch)
            }

            Text("When enabled, GeeAgent chooses where a Quick Input message belongs. When disabled, Quick Input uses the currently selected conversation session, matching the existing behavior.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(store.autoConversationRoutingEnabled ? "Quick Input: automatic conversation choice" : "Quick Input: selected session")
                .font(.caption.weight(.semibold))
                .foregroundStyle(store.autoConversationRoutingEnabled ? Color.green : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (store.autoConversationRoutingEnabled ? Color.green : Color.secondary).opacity(0.12),
                    in: Capsule()
                )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var skillSourcesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Agent Skills", systemImage: "wand.and.rays")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Button(action: chooseSystemSkillSource) {
                    Label("Add Source", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(store.isAddingSystemSkillSource)
            }

            HStack(spacing: 8) {
                Text("\(store.skillSources.systemSources.count) global")
                Text("Hot updates")
                    .foregroundStyle(.green)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if store.skillSources.systemSources.isEmpty {
                Text("No global skill sources configured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.skillSources.systemSources) { source in
                        skillSourceRow(source) {
                            removeSystemSkillSource(source)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func skillSourceRow(
        _ source: SkillSourceRecord,
        removeAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: source.status == "ready" ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(source.status == "ready" ? Color.green : Color.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(source.skillsSummary)
                        .font(.subheadline.weight(.semibold))
                    Text(source.statusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(source.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if let error = source.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button(role: .destructive, action: removeAction) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove source")
            .disabled(store.isRemovingSkillSource)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        }
    }

    private var providerOptions: [String] {
        var options = store.chatRoutingSettings?.providerChoices ?? []
        if let provider = store.runtimeStatus.providerName,
           !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            options.append(provider)
        }
        options.append(contentsOf: ["xenodia", "openai"])
        return Array(Set(options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private var canSaveRouting: Bool {
        !store.isSavingChatRoutingSettings &&
        !selectedProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var runtimeTint: Color {
        switch store.runtimeStatus.state {
        case .live:
            return .green
        case .needsSetup:
            return .orange
        case .degraded:
            return .yellow
        case .unavailable:
            return .red
        }
    }

    private func syncRoutingDraft() {
        if let route = store.chatRoutingSettings?.selectedRouteClass {
            selectedProvider = route.provider
            modelName = route.model
            return
        }

        if selectedProvider.isEmpty {
            selectedProvider = store.runtimeStatus.providerName ?? providerOptions.first ?? "xenodia"
        }
    }

    private func chooseSystemSkillSource() {
        let panel = NSOpenPanel()
        panel.title = "Add Global Skill Source"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await store.addSystemSkillSource(from: url)
            } catch {
                skillSourceError = SettingsFeedbackMessage(
                    title: "Skill Source Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func removeSystemSkillSource(_ source: SkillSourceRecord) {
        Task {
            do {
                try await store.removeSystemSkillSource(source)
            } catch {
                skillSourceError = SettingsFeedbackMessage(
                    title: "Remove Skill Source Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private var legacySettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricsRow
                .padding(.horizontal)
                .padding(.top)

            profileControlNotice
                .padding(.horizontal)

            terminalPermissionsPanel
                .padding(.horizontal)

            List(selection: $store.selectedSettingsPaneID) {
                Section("System Panes") {
                    ForEach(store.settingsPanes) { pane in
                        SettingsPaneRow(pane: pane)
                            .tag(pane.id)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            WorkbenchMetricTile(
                title: "Chat Runtime",
                value: store.runtimeStatus.state.title,
                systemImage: "terminal"
            )
            WorkbenchMetricTile(
                title: "Provider",
                value: store.runtimeStatus.providerName ?? "Not configured",
                systemImage: "bolt.horizontal.circle"
            )
            WorkbenchMetricTile(
                title: "Workspace Access",
                value: store.interactionCapabilities.canMutateRuntime ? "Ready" : "Read only",
                systemImage: store.interactionCapabilities.canMutateRuntime ? "checkmark.shield" : "lock"
            )
        }
    }

    private var profileControlNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Persona visuals are now controlled from Agents", systemImage: "person.crop.rectangle.stack")
                .font(.geeDisplaySemibold(18))

            Text("Home appearance follows the currently active profile. To inspect files, reload a local profile, or switch the active persona, use the Agents section.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var terminalPermissionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Terminal Permissions", systemImage: "terminal")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Text("\(store.terminalPermissionRules.count) saved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if store.terminalPermissionRules.isEmpty {
                Text("No saved terminal decisions yet. When GeeAgent asks to run a shell command, choosing Always Allow or Deny will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    terminalRuleGroup(
                        title: "Always allowed",
                        rules: store.terminalPermissionRules.filter { $0.decision == .allow }
                    )
                    terminalRuleGroup(
                        title: "Always denied",
                        rules: store.terminalPermissionRules.filter { $0.decision == .deny }
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var removalAlertBinding: Binding<Bool> {
        Binding(
            get: { rulePendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    rulePendingRemoval = nil
                }
            }
        )
    }

    @ViewBuilder
    private func terminalRuleGroup(
        title: String,
        rules: [TerminalPermissionRuleRecord]
    ) -> some View {
        if !rules.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                ForEach(rules) { rule in
                    TerminalPermissionRuleRow(
                        rule: rule,
                        isBusy: store.isDeletingTerminalPermissionRule,
                        onDelete: {
                            rulePendingRemoval = rule
                        }
                    )
                }
            }
        }
    }
}

private struct SettingsFeedbackMessage: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

private struct TerminalPermissionRuleRow: View {
    var rule: TerminalPermissionRuleRecord
    var isBusy: Bool
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            decisionBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(primaryText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let cwd = rule.cwd, !cwd.isEmpty {
                    Text(cwd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(rule.kind) · \(rule.updatedAt)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button(role: .destructive, action: onDelete) {
                Text("Remove")
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var primaryText: String {
        if let command = rule.command, !command.isEmpty {
            return command
        }
        return rule.label
    }

    private var decisionBadge: some View {
        Text(rule.decision.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(rule.decision == .allow ? Color.green : Color.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (rule.decision == .allow ? Color.green : Color.red).opacity(0.14),
                in: Capsule()
            )
    }
}

private struct SettingsPaneRow: View {
    var pane: SettingsPaneSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(pane.title)
                    .font(.headline)
                Text(pane.summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}
