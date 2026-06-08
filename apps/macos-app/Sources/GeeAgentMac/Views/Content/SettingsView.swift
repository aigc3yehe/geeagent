import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: WorkbenchStore
    @State private var rulePendingRemoval: TerminalPermissionRuleRecord?
    @State private var isConfirmingHighestAuthorization = false
    @State private var selectedProvider = ""
    @State private var modelName = ""
    @State private var providerKeyDrafts: [String: String] = [:]
    @State private var skillSourceError: SettingsFeedbackMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                highestAuthorizationPanel
                    .padding(.horizontal)
                    .padding(.top)

                languagePanel
                    .padding(.horizontal)

                providerRoutingPanel
                    .padding(.horizontal)

                providerKeysPanel
                    .padding(.horizontal)

                audioTranscriptionPanel
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
        .navigationTitle(store.localizedString("settings.title", defaultValue: "Settings"))
        .onAppear {
            syncRoutingDraft()
            if store.chatRoutingSettings == nil {
                store.loadChatRoutingSettings()
            }
            store.loadProviderSecretSettings()
        }
        .onChange(of: store.chatRoutingSettings) { _, _ in
            syncRoutingDraft()
        }
        .alert(store.localizedString("settings.terminal.removeRuleTitle", defaultValue: "Remove terminal rule?"), isPresented: removalAlertBinding, presenting: rulePendingRemoval) { rule in
            Button(store.localizedString("common.cancel", defaultValue: "Cancel"), role: .cancel) {
                rulePendingRemoval = nil
            }
            Button(store.localizedString("common.remove", defaultValue: "Remove"), role: .destructive) {
                store.deleteTerminalPermissionRule(rule.id)
                rulePendingRemoval = nil
            }
        } message: { rule in
            Text(store.localizedString("settings.terminal.removeRuleMessage", defaultValue: "Future matching terminal commands will return to the normal approval flow. Past runs are not changed."))
        }
        .alert(store.localizedString("settings.highestAuthorization.alertTitle", defaultValue: "Enable highest authorization?"), isPresented: $isConfirmingHighestAuthorization) {
            Button(store.localizedString("common.cancel", defaultValue: "Cancel"), role: .cancel) {}
            Button(store.localizedString("common.enable", defaultValue: "Enable"), role: .destructive) {
                store.setHighestAuthorizationEnabled(true)
            }
        } message: {
            Text(store.localizedString("settings.highestAuthorization.alertMessage", defaultValue: "When enabled, the agent will receive full computer-control permissions and will stop asking for approval. Are you sure you want to enable this mode?"))
        }
        .alert(item: $skillSourceError) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.message),
                dismissButton: .default(Text(store.localizedString("common.ok", defaultValue: "OK")))
            )
        }
    }

    private var highestAuthorizationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(store.localizedString("settings.highestAuthorization.title", defaultValue: "Highest Authorization"), systemImage: "lock.open.trianglebadge.exclamationmark")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Toggle(store.localizedString("settings.highestAuthorization.title", defaultValue: "Highest Authorization"), isOn: highestAuthorizationBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(store.isUpdatingHighestAuthorization)
            }

            Text(store.localizedString("settings.highestAuthorization.description", defaultValue: "Off by default. When enabled, GeeAgent automatically approves computer-control and terminal permission requests initiated by the agent, without showing per-action approval prompts."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(store.securityPreferences.highestAuthorizationEnabled
                ? store.localizedString("settings.highestAuthorization.enabled", defaultValue: "Enabled: the agent will execute approval-gated actions directly.")
                : store.localizedString("settings.highestAuthorization.disabled", defaultValue: "Disabled: sensitive actions still go through approval cards."))
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial.opacity(0.78))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
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

    private var languagePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(store.localizedString("settings.language.title", defaultValue: "Language"), systemImage: "globe")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Text(store.appLanguage.localizedDisplayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }

            Text(store.localizedString("settings.language.description", defaultValue: "Choose the language used by GeeAgent's main app surfaces. Gear content and agent replies keep their original language."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(store.localizedString("settings.language.current", defaultValue: "Current language"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker(store.localizedString("settings.language.title", defaultValue: "Language"), selection: $store.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.localizedDisplayTitle)
                                .tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial.opacity(0.78))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }

    private var providerRoutingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(store.localizedString("settings.routing.title", defaultValue: "Model Routing"), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Text(store.runtimeStatus.state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(runtimeTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(runtimeTint.opacity(0.12), in: Capsule())
            }

            Text(store.localizedString("settings.routing.description", defaultValue: "Choose the provider and model GeeAgent should use for the default chat route."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(store.localizedString("settings.routing.provider", defaultValue: "Provider"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker(store.localizedString("settings.routing.provider", defaultValue: "Provider"), selection: $selectedProvider) {
                        ForEach(providerOptions, id: \.self) { provider in
                            Text(provider).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                }

                GridRow {
                    Text(store.localizedString("settings.routing.model", defaultValue: "Model"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(store.localizedString("settings.routing.modelPlaceholder", defaultValue: "e.g. gpt-5.4"), text: $modelName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
            }

            HStack {
                if store.isLoadingChatRoutingSettings {
                    ProgressView()
                        .controlSize(.small)
                    Text(store.localizedString("settings.routing.loading", defaultValue: "Loading routing settings..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let route = store.chatRoutingSettings?.selectedRouteClass {
                    Text(store.localizedFormat("settings.routing.currentRoute", defaultValue: "Current route: %@ / %@", route.provider, route.model))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(store.localizedString("settings.routing.notLoaded", defaultValue: "Routing settings are not loaded yet."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(store.localizedString("common.reload", defaultValue: "Reload")) {
                    store.loadChatRoutingSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isLoadingChatRoutingSettings)

                Button(store.localizedString("common.save", defaultValue: "Save")) {
                    store.saveDefaultChatRouting(provider: selectedProvider, model: modelName)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSaveRouting)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial.opacity(0.78))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }

    private var audioTranscriptionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(store.localizedString("settings.stt.title", defaultValue: "Speech To Text"), systemImage: "waveform.and.mic")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Text(store.audioCapture.selectedProvider.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }

            Text(store.localizedString("settings.stt.description", defaultValue: "Choose the default STT service used by Chat voice input and the Audio Capture shortcut bar. Realtime transcription is used only when the selected service reports streaming support."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(store.localizedString("settings.stt.defaultService", defaultValue: "Default STT Service"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker(store.localizedString("settings.stt.defaultService", defaultValue: "Default STT Service"), selection: audioProviderBinding) {
                        ForEach(SpeechTranscriptionProviderID.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                }

                GridRow {
                    Text(store.localizedString("common.status", defaultValue: "Status"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(store.audioCapture.selectedProvider.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial.opacity(0.78))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }

    private var providerKeysPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(store.localizedString("settings.keys.title", defaultValue: "Provider Keys"), systemImage: "key")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                if store.isLoadingProviderSecretSettings {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(store.localizedFormat("common.configuredCount", defaultValue: "%d configured", configuredProviderKeyCount))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(configuredProviderKeyCount > 0 ? Color.green : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (configuredProviderKeyCount > 0 ? Color.green : Color.secondary).opacity(0.12),
                            in: Capsule()
                        )
                }
            }

            Text(store.localizedString("settings.keys.description", defaultValue: "Keys are saved only in GeeAgent's local app settings file, not in system Keychain or environment variables. Existing values are never shown; paste a new key to replace one."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(providerKeyRows) { status in
                    providerKeyRow(status)
                }
            }

            HStack {
                Text(store.localizedString("settings.keys.usedBy", defaultValue: "Used by chat/provider routing and online speech providers such as ElevenLabs."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(store.localizedString("common.reload", defaultValue: "Reload")) {
                    store.loadProviderSecretSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isLoadingProviderSecretSettings)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial.opacity(0.78))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }

    private func providerKeyRow(_ status: ProviderSecretStatus) -> some View {
        let isSaving = store.savingProviderSecretIDs.contains(status.providerID)
        let draft = providerKeyDrafts[status.providerID, default: ""]
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                    .font(.subheadline.weight(.semibold))
                Text(status.sourceTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 130, alignment: .leading)

            SecureField(store.localizedString("settings.keys.pastePlaceholder", defaultValue: "Paste API key"), text: providerKeyBinding(status.providerID))
                .textFieldStyle(.roundedBorder)
                .disabled(isSaving)

            Text(status.apiKeyConfigured
                ? store.localizedString("common.ready", defaultValue: "Ready")
                : store.localizedString("settings.keys.missing", defaultValue: "Missing"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.apiKeyConfigured ? Color.green : Color.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (status.apiKeyConfigured ? Color.green : Color.orange).opacity(0.12),
                    in: Capsule()
                )

            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }

            Button(store.localizedString("common.save", defaultValue: "Save")) {
                store.saveProviderAPIKey(providerID: status.providerID, apiKey: draft)
                providerKeyDrafts[status.providerID] = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isSaving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(store.localizedString("common.clear", defaultValue: "Clear")) {
                store.clearProviderAPIKey(providerID: status.providerID)
                providerKeyDrafts[status.providerID] = ""
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isSaving || !status.savedAPIKeyConfigured)
            .help(status.source == "environment"
                ? store.localizedString("settings.keys.removeSavedHelpEnvironment", defaultValue: "Remove the saved key. The environment variable will still be used.")
                : store.localizedString("settings.keys.removeSavedHelp", defaultValue: "Remove saved key"))
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }

    private var conversationRoutingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(store.localizedString("settings.conversationRouting.title", defaultValue: "Conversation Routing"), systemImage: "arrow.triangle.branch")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Toggle(store.localizedString("settings.conversationRouting.toggle", defaultValue: "Automatically choose conversation"), isOn: $store.autoConversationRoutingEnabled)
                    .toggleStyle(.switch)
            }

            Text(store.localizedString("settings.conversationRouting.description", defaultValue: "This controls main app conversation auto-routing. Quick Input always starts a fresh conversation tagged quick-input, and tagged quick conversations are excluded from auto-routing targets."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(store.autoConversationRoutingEnabled
                ? store.localizedString("settings.conversationRouting.auto", defaultValue: "Main app: automatic conversation choice")
                : store.localizedString("settings.conversationRouting.selectedOnly", defaultValue: "Main app: selected conversation only"))
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial.opacity(0.78))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }

    private var skillSourcesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(store.localizedString("settings.skills.title", defaultValue: "Agent Skills"), systemImage: "wand.and.rays")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Button(action: chooseSystemSkillSource) {
                    Label(store.localizedString("common.addSource", defaultValue: "Add Source"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(store.isAddingSystemSkillSource)
            }

            HStack(spacing: 8) {
                Text(store.localizedFormat("settings.skills.globalCount", defaultValue: "%d global", store.skillSources.systemSources.count))
                Text(store.localizedString("settings.skills.hotUpdates", defaultValue: "Hot updates"))
                    .foregroundStyle(.green)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if store.skillSources.systemSources.isEmpty {
                Text(store.localizedString("settings.skills.none", defaultValue: "No global skill sources configured."))
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial.opacity(0.78))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
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
            .help(store.localizedString("settings.skills.removeSource", defaultValue: "Remove source"))
            .disabled(store.isRemovingSkillSource)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
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

    private var providerKeyRows: [ProviderSecretStatus] {
        let statuses = store.providerSecretSettings.providers.isEmpty
            ? ProviderSecretSettings.defaultSettings.providers
            : store.providerSecretSettings.providers
        let order = Dictionary(uniqueKeysWithValues: ProviderSecretSettings.managedProviderIDs.enumerated().map { ($0.element, $0.offset) })
        return statuses.sorted {
            let leftOrder = order[$0.providerID] ?? Int.max
            let rightOrder = order[$1.providerID] ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return $0.title < $1.title
        }
    }

    private var configuredProviderKeyCount: Int {
        providerKeyRows.filter(\.apiKeyConfigured).count
    }

    private func providerKeyBinding(_ providerID: String) -> Binding<String> {
        Binding(
            get: { providerKeyDrafts[providerID, default: ""] },
            set: { providerKeyDrafts[providerID] = $0 }
        )
    }

    private var audioProviderBinding: Binding<SpeechTranscriptionProviderID> {
        Binding(
            get: { store.audioCapture.selectedProvider },
            set: { store.audioCapture.selectedProvider = $0 }
        )
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
        panel.title = store.localizedString("settings.skills.addGlobalPanelTitle", defaultValue: "Add Global Skill Source")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await store.addSystemSkillSource(from: url)
            } catch {
                skillSourceError = SettingsFeedbackMessage(
                    title: store.localizedString("settings.skills.addFailed", defaultValue: "Skill Source Failed"),
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
                    title: store.localizedString("settings.skills.removeFailed", defaultValue: "Remove Skill Source Failed"),
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
            Label(store.localizedString("settings.personaMoved.title", defaultValue: "Persona visuals are now controlled from Agents"), systemImage: "person.crop.rectangle.stack")
                .font(.geeDisplaySemibold(18))

            Text(store.localizedString("settings.personaMoved.description", defaultValue: "Home appearance follows the currently active profile. To inspect files, reload a local profile, or switch the active persona, use the Agents section."))
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
                Label(store.localizedString("settings.terminal.title", defaultValue: "Terminal Permissions"), systemImage: "terminal")
                    .font(.geeDisplaySemibold(18))

                Spacer()

                Text(store.localizedFormat("settings.terminal.savedCount", defaultValue: "%d saved", store.terminalPermissionRules.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if store.terminalPermissionRules.isEmpty {
                Text(store.localizedString("settings.terminal.empty", defaultValue: "No saved terminal decisions yet. When GeeAgent asks to run a shell command, choosing Always Allow or Deny will appear here."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    terminalRuleGroup(
                        title: store.localizedString("settings.terminal.alwaysAllowed", defaultValue: "Always allowed"),
                        rules: store.terminalPermissionRules.filter { $0.decision == .allow }
                    )
                    terminalRuleGroup(
                        title: store.localizedString("settings.terminal.alwaysDenied", defaultValue: "Always denied"),
                        rules: store.terminalPermissionRules.filter { $0.decision == .deny }
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial.opacity(0.78))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
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
                Text(AppLocalization.string("common.remove", defaultValue: "Remove"))
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
