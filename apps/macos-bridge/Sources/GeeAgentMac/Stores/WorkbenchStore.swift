import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class WorkbenchStore {
    private enum PreferenceKey {
        static let activeAgentProfileId = "geeagent.activeAgentProfileId"
        /// Legacy key — superseded by per-persona `profileAppearancePreferences`.
        /// Kept for one-shot migration of existing users.
        static let legacyHomeVisualMode = "geeagent.home.visualMode"
        static let homeVisualEffect = "geeagent.home.visualEffect"
        /// Legacy key — superseded by per-persona `profileAppearancePreferences`.
        static let legacyHomeBannerImagePath = "geeagent.home.bannerImagePath"
        static let profileAppearancePreferences = "geeagent.profileAppearancePreferences"
        static let autoConversationRouting = "geeagent.quickInput.autoConversationRouting"
    }

    let runtimeClient: any WorkbenchRuntimeClient
    private var conversationTitleOverrides: [ConversationThread.ID: String] = [:]

    var snapshot: WorkbenchSnapshot {
        didSet {
            normalizeSelections()
            refreshActiveLive2DState()
        }
    }
    var lastErrorMessage: String?
    var isCreatingConversation = false
    var isActivatingConversation = false
    var isDeletingConversation = false
    var isSendingMessage = false
    var isPerformingTaskAction = false
    var isDeletingTerminalPermissionRule = false
    var isUpdatingHighestAuthorization = false
    var isLoadingChatRoutingSettings = false
    var isSavingChatRoutingSettings = false
    var chatRoutingSettings: ChatRoutingSettings?
    var autoConversationRoutingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoConversationRoutingEnabled, forKey: PreferenceKey.autoConversationRouting)
        }
    }
    var selectedSection: WorkbenchSection
    var homeSurfaceMode: HomeSurfaceMode = .companion
    var homeVisualEffectMode: HomeVisualEffectMode {
        didSet {
            UserDefaults.standard.set(homeVisualEffectMode.rawValue, forKey: PreferenceKey.homeVisualEffect)
        }
    }
    /// Per-persona appearance overrides. Keyed by persona id.
    /// The snapshot's `AgentProfile.appearance` is the baseline; these entries override it
    /// locally so the user can customize a persona's look without mutating the shared profile.
    var profileAppearancePreferences: [String: ProfileAppearancePreference] = [:] {
        didSet {
            persistProfileAppearancePreferences()
            refreshActiveLive2DState()
        }
    }
    var selectedHomeItemID: WorkbenchHomeItem.ID? {
        didSet {
            normalizeSelectedHomeItem()
        }
    }
    var selectedConversationID: ConversationThread.ID? {
        didSet {
            normalizeSelectedConversation()
        }
    }
    var selectedTaskID: WorkbenchTaskRecord.ID? {
        didSet {
            normalizeSelectedTask()
        }
    }
    var selectedAutomationID: AutomationRecord.ID? {
        didSet {
            normalizeSelectedAutomation()
        }
    }
    var selectedExtension: WorkbenchExtensionSelection? {
        didSet {
            normalizeSelectedExtension()
        }
    }
    var selectedSettingsPaneID: SettingsPaneSummary.ID? {
        didSet {
            normalizeSelectedSettingsPane()
        }
    }
    var activeAgentProfileID: AgentProfileRecord.ID? {
        didSet {
            persistActiveAgentProfileID()
            refreshActiveLive2DState()
        }
    }
    var selectedAgentProfileID: AgentProfileRecord.ID? {
        didSet {
            normalizeSelectedAgentProfile()
        }
    }
    var isImportingAgentPack = false
    var live2DActionCatalog: Live2DActionCatalog = .empty
    var live2DMotionPlaybackRequest: Live2DMotionPlaybackRequest?
    var temporaryLive2DExpressionPath: String?
    private var live2DExpressionRestoreTask: Task<Void, Never>?
    private var live2DPoseRestoreTask: Task<Void, Never>?

    // MARK: Plan 6 — full-canvas module slot (session-only)

    /// When set, `WorkbenchRootView` presents `StandaloneModuleStage` and hides the nav rail.
    var presentedStandaloneModuleID: String?
    var pendingGearWindowRequest: GearWindowRequest?
    private var sectionBeforeStandaloneModule: WorkbenchSection?

    /// Resolved catalog row for the standalone surface, if any.
    var presentedStandaloneModule: InstalledAppRecord? {
        guard let presentedStandaloneModuleID else { return nil }
        return installedApps.first(where: { $0.id == presentedStandaloneModuleID })
    }

    init(runtimeClient: any WorkbenchRuntimeClient) {
        self.runtimeClient = runtimeClient
        let snapshot = runtimeClient.loadSnapshot()
        let defaults = UserDefaults.standard
        let storedActiveAgentProfileID = defaults.string(forKey: PreferenceKey.activeAgentProfileId)
        self.snapshot = snapshot
        self.selectedSection = snapshot.preferredSection
        self.autoConversationRoutingEnabled = defaults.object(forKey: PreferenceKey.autoConversationRouting) as? Bool ?? true
        self.homeVisualEffectMode = HomeVisualEffectMode(rawValue: defaults.string(forKey: PreferenceKey.homeVisualEffect) ?? "") ?? .none
        self.profileAppearancePreferences = Self.loadAppearancePreferences(from: defaults)
        self.selectedHomeItemID = snapshot.homeItems.first?.id
        self.selectedConversationID = snapshot.conversations.first(where: \.isActive)?.id ?? snapshot.conversations.first?.id
        self.selectedTaskID = snapshot.tasks.first(where: { $0.status == .needsApproval || $0.status == .running || $0.status == .blocked })?.id ?? snapshot.tasks.first?.id
        self.selectedAutomationID = snapshot.automations.first?.id
        self.selectedExtension = snapshot.installedApps.first.map { .app($0.id) } ?? snapshot.agentSkins.first.map { .skin($0.id) }
        self.selectedSettingsPaneID = snapshot.settings.first?.id
        self.activeAgentProfileID = snapshot.activeAgentProfileID ?? storedActiveAgentProfileID ?? Self.defaultBundledAgentProfile.id
        self.selectedAgentProfileID = snapshot.activeAgentProfileID ?? storedActiveAgentProfileID ?? Self.defaultBundledAgentProfile.id
        normalizeSelections()
        migrateLegacyHomeAppearancePreferences(defaults: defaults)
        refreshActiveLive2DState()
    }

    var homeSummary: WorkbenchHomeSummary {
        WorkbenchHomeSummary(
            openTasksCount: openTasksCount,
            approvalsCount: approvalsCount,
            nextAutomationLabel: nextAutomationLabel,
            installedAppsCount: installedApps.count
        )
    }
    var homeItems: [WorkbenchHomeItem] { snapshot.homeItems }
    var conversations: [ConversationThread] {
        snapshot.conversations.map { conversation in
            var updated = conversation
            if let override = conversationTitleOverrides[conversation.id], !override.isEmpty {
                updated.title = override
            }
            return updated
        }
    }
    var tasks: [WorkbenchTaskRecord] { snapshot.tasks }
    var automations: [AutomationRecord] { snapshot.automations }
    var installedApps: [InstalledAppRecord] { snapshot.installedApps }
    var agentSkins: [AgentSkinRecord] { snapshot.agentSkins }
    var availableAgentProfiles: [AgentProfileRecord] {
        resolvedAgentProfiles(from: snapshot)
    }
    var settingsPanes: [SettingsPaneSummary] { snapshot.settings }
    var terminalPermissionRules: [TerminalPermissionRuleRecord] { snapshot.terminalPermissionRules }
    var securityPreferences: WorkbenchSecurityPreferences { snapshot.securityPreferences }
    var runtimeStatus: WorkbenchRuntimeStatus { snapshot.runtimeStatus }
    var interactionCapabilities: WorkbenchInteractionCapabilities { snapshot.interactionCapabilities }
    var contextBudget: ContextBudgetRecord { snapshot.contextBudget }
    var lastOutcome: WorkbenchRequestOutcome? { snapshot.lastOutcome }
    var activeAgentProfile: AgentProfileRecord? {
        guard let activeAgentProfileID else {
            return availableAgentProfiles.first
        }

        return availableAgentProfiles.first(where: { $0.id == activeAgentProfileID }) ?? availableAgentProfiles.first
    }
    var selectedAgentProfile: AgentProfileRecord? {
        guard let selectedAgentProfileID else {
            return activeAgentProfile
        }

        return availableAgentProfiles.first(where: { $0.id == selectedAgentProfileID }) ?? activeAgentProfile
    }
    var isUsingPlaceholderAgentProfiles: Bool {
        snapshot.availableAgentProfiles.isEmpty
    }

    var selectedHomeItem: WorkbenchHomeItem? {
        homeItems.first(where: { $0.id == selectedHomeItemID }) ?? homeItems.first
    }

    var selectedConversation: ConversationThread? {
        conversations.first(where: { $0.id == selectedConversationID }) ?? conversations.first
    }

    var selectedTask: WorkbenchTaskRecord? {
        tasks.first(where: { $0.id == selectedTaskID }) ?? tasks.first
    }

    var selectedTaskActions: [WorkbenchTaskAction] {
        guard let task = selectedTask else {
            return []
        }

        return taskActions(for: task)
    }

    func taskActions(for task: WorkbenchTaskRecord) -> [WorkbenchTaskAction] {
        switch task.status {
        case .needsApproval where task.approvalRequestID != nil:
            return [.allowOnce, .alwaysAllow, .deny]
        case .blocked where task.canRetry && task.moduleRunID != nil:
            return [.retry]
        case .failed where task.canRetry && task.moduleRunID != nil:
            return [.retry]
        case .running, .queued:
            return []
        case .completed:
            return []
        default:
            return []
        }
    }

    var selectedAutomation: AutomationRecord? {
        automations.first(where: { $0.id == selectedAutomationID }) ?? automations.first
    }

    var selectedInstalledApp: InstalledAppRecord? {
        guard case let .app(id) = selectedExtension else { return installedApps.first }
        return installedApps.first(where: { $0.id == id }) ?? installedApps.first
    }

    var selectedAgentSkin: AgentSkinRecord? {
        guard case let .skin(id) = selectedExtension else { return nil }
        return agentSkins.first(where: { $0.id == id }) ?? agentSkins.first
    }

    var selectedSettingsPane: SettingsPaneSummary? {
        settingsPanes.first(where: { $0.id == selectedSettingsPaneID }) ?? settingsPanes.first
    }

    var openTasksCount: Int {
        tasks.filter { $0.status != .completed }.count
    }

    var approvalsCount: Int {
        tasks.filter { $0.status == .needsApproval }.count
    }

    var nextAutomationLabel: String {
        guard let automation = nextAutomation else {
            return "No schedules"
        }

        return "\(automation.name) - \(automation.nextRunLabel)"
    }

    func tasks(for status: WorkbenchTaskStatus) -> [WorkbenchTaskRecord] {
        tasks.filter { $0.status == status }
    }

    func setActiveAgentProfile(_ profile: AgentProfileRecord) {
        guard availableAgentProfiles.contains(where: { $0.id == profile.id }) else {
            return
        }

        selectedAgentProfileID = profile.id
        let previousActiveProfileID = activeAgentProfileID

        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot
        let targetProfileID = profile.id

        Task { [weak self, runtimeClient, currentSnapshot, targetProfileID] in
            do {
                let nextSnapshot = try await runtimeClient.setActiveAgentProfile(
                    targetProfileID,
                    in: currentSnapshot
                )
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = nextSnapshot
                    self.selectedAgentProfileID = targetProfileID
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    if self?.activeAgentProfileID == targetProfileID {
                        self?.activeAgentProfileID = previousActiveProfileID
                    }
                }
            }
        }
    }

    func importAgentPack(from packURL: URL) async throws -> AgentProfileRecord.ID? {
        guard !isImportingAgentPack else { return nil }
        let packPath = packURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !packPath.isEmpty else { return nil }

        isImportingAgentPack = true
        lastErrorMessage = nil

        let existingIDs = Set(availableAgentProfiles.map(\.id))
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot
        defer {
            isImportingAgentPack = false
        }

        do {
            let nextSnapshot = try await runtimeClient.installAgentPack(at: packPath, in: currentSnapshot)
            snapshot = nextSnapshot
            let nextIDs = Set(nextSnapshot.availableAgentProfiles.map(\.id))
            let importedID = nextIDs.subtracting(existingIDs).first
            if let importedID {
                selectedAgentProfileID = importedID
            }
            return importedID
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func reloadAgentProfile(_ profile: AgentProfileRecord) async throws {
        guard profile.fileState.canReload else { return }
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot
        let nextSnapshot = try await runtimeClient.reloadAgentProfile(profile.id, in: currentSnapshot)
        snapshot = nextSnapshot
        selectedAgentProfileID = profile.id
    }

    func deleteAgentProfile(_ profile: AgentProfileRecord) async throws {
        guard profile.fileState.canDelete else { return }
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot
        let nextSnapshot = try await runtimeClient.deleteAgentProfile(profile.id, in: currentSnapshot)
        snapshot = nextSnapshot
    }

    func deleteTerminalPermissionRule(_ ruleID: TerminalPermissionRuleRecord.ID) {
        guard !isDeletingTerminalPermissionRule else { return }
        isDeletingTerminalPermissionRule = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot

        Task { [weak self, runtimeClient, currentSnapshot, ruleID] in
            do {
                let nextSnapshot = try await runtimeClient.deleteTerminalPermissionRule(
                    ruleID,
                    in: currentSnapshot
                )
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = nextSnapshot
                    self.isDeletingTerminalPermissionRule = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isDeletingTerminalPermissionRule = false
                }
            }
        }
    }

    func setHighestAuthorizationEnabled(_ enabled: Bool) {
        guard !isUpdatingHighestAuthorization else { return }
        isUpdatingHighestAuthorization = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot

        Task { [weak self, runtimeClient, currentSnapshot, enabled] in
            do {
                let nextSnapshot = try await runtimeClient.setHighestAuthorizationEnabled(
                    enabled,
                    in: currentSnapshot
                )
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = nextSnapshot
                    self.isUpdatingHighestAuthorization = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isUpdatingHighestAuthorization = false
                }
            }
        }
    }

    func loadChatRoutingSettings() {
        guard !isLoadingChatRoutingSettings else {
            return
        }

        isLoadingChatRoutingSettings = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient

        Task { [weak self, runtimeClient] in
            do {
                let settings = try await runtimeClient.loadChatRoutingSettings()
                await MainActor.run {
                    self?.chatRoutingSettings = settings
                    self?.isLoadingChatRoutingSettings = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isLoadingChatRoutingSettings = false
                }
            }
        }
    }

    func saveDefaultChatRouting(provider: String, model: String) {
        guard !isSavingChatRoutingSettings else {
            return
        }

        let currentSettings = chatRoutingSettings ?? ChatRoutingSettings(
            defaultRouteClass: "default",
            allowUserOverrides: true,
            providerChoices: [provider].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            routeClasses: [],
            profiles: []
        )
        let nextSettings = currentSettings.updatingDefaultRoute(provider: provider, model: model)

        isSavingChatRoutingSettings = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot

        Task { [weak self, runtimeClient, currentSnapshot, nextSettings] in
            do {
                let nextSnapshot = try await runtimeClient.saveChatRoutingSettings(
                    nextSettings,
                    in: currentSnapshot
                )
                await MainActor.run {
                    guard let self else { return }
                    self.chatRoutingSettings = nextSettings
                    self.snapshot = nextSnapshot
                    self.isSavingChatRoutingSettings = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isSavingChatRoutingSettings = false
                }
            }
        }
    }

    func openAgentProfileFolder(_ profile: AgentProfileRecord) {
        guard let path = profile.fileState.workspaceRootPath, !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func revealAgentProfilePath(_ path: String?) {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // ------------------------------------------------------------------
    // Plan 4 — tool invocation
    // ------------------------------------------------------------------

    /// Pending approval surfaced from a `NeedsApproval` outcome. When non-nil,
    /// `ToolApprovalSheet` is displayed by `WorkbenchRootView`. User accept
    /// triggers `resolvePendingApproval(accept: true)`; cancel triggers `false`.
    var pendingToolApproval: PendingToolApproval?
    var isInvokingTool = false
    /// Last outcome applied by `invokeTool` — used by tests and by chat surfaces
    /// that want to annotate the conversation with tool traces.
    var lastToolOutcome: WorkbenchToolOutcome?

    /// Entry point for the agent-to-system tool bridge. The store dispatches
    /// through `runtimeClient.invokeTool` and applies the returned outcome:
    /// navigation intents mutate `selectedSection` / open modules directly;
    /// `NeedsApproval` stores a `PendingToolApproval` for the sheet to consume.
    func invokeTool(_ invocation: ToolInvocation) {
        guard !isInvokingTool else { return }
        isInvokingTool = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        Task { [weak self, runtimeClient, invocation] in
            do {
                let outcome = try await runtimeClient.invokeTool(invocation)
                await MainActor.run {
                    guard let self else { return }
                    self.applyToolOutcome(outcome, from: invocation)
                    self.isInvokingTool = false
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.lastErrorMessage = error.localizedDescription
                    self.isInvokingTool = false
                }
            }
        }
    }

    /// Called when the approval sheet resolves.
    func resolvePendingApproval(accept: Bool) {
        guard let pending = pendingToolApproval else { return }
        pendingToolApproval = nil
        guard accept else {
            lastToolOutcome = .denied(
                toolID: pending.invocation.toolID,
                reason: "User cancelled the approval."
            )
            return
        }
        var replay = pending.invocation
        replay.approvalToken = pending.generatedToken
        invokeTool(replay)
    }

    private func applyToolOutcome(
        _ outcome: WorkbenchToolOutcome,
        from invocation: ToolInvocation
    ) {
        lastToolOutcome = outcome
        switch outcome {
        case .completed:
            if let intent = outcome.navigationIntent {
                applyNavigationIntent(intent)
            }
        case let .needsApproval(_, blastRadius, prompt):
            pendingToolApproval = PendingToolApproval(
                invocation: invocation,
                blastRadius: blastRadius,
                prompt: prompt,
                generatedToken: UUID().uuidString
            )
        case let .denied(_, reason):
            lastErrorMessage = reason
        case let .error(_, _, message):
            lastErrorMessage = message
        }
    }

    private func applyNavigationIntent(_ intent: WorkbenchToolNavigationIntent) {
        switch intent {
        case let .section(section):
            selectedSection = section
        case let .module(id):
            lastErrorMessage = nil
            if let app = installedApps.first(where: { $0.id == id }) {
                guard GearRegistry.isEnabled(gearID: id) else {
                    selectedSection = .apps
                    lastErrorMessage = "`\(app.name)` is disabled. Enable it from Apps before opening it."
                    return
                }
                switch app.displayMode {
                case .fullCanvas:
                    openStandaloneModule(id: id)
                case .inNav:
                    selectedSection = .apps
                    selectedExtension = .app(id)
                }
            } else {
                selectedSection = .apps
                lastErrorMessage = "No installed module matches `\(id)`."
            }
        }
    }

    /// Presents a full-canvas module by id (e.g. Apps → Modules → Open, or chat tool `navigate.openModule`).
    func openStandaloneModule(id: String) {
        guard GearRegistry.isEnabled(gearID: id) else {
            return
        }

        if let windowID = GearRegistry.dedicatedWindowID(gearID: id) {
            presentedStandaloneModuleID = nil
            sectionBeforeStandaloneModule = nil
            pendingGearWindowRequest = GearWindowRequest(gearID: id, windowID: windowID)
            return
        }

        if presentedStandaloneModuleID == nil {
            sectionBeforeStandaloneModule = selectedSection
        }
        presentedStandaloneModuleID = id
    }

    func clearGearWindowRequest(_ requestID: GearWindowRequest.ID) {
        guard pendingGearWindowRequest?.id == requestID else {
            return
        }
        pendingGearWindowRequest = nil
    }

    func closeStandaloneModule() {
        presentedStandaloneModuleID = nil
        if let previous = sectionBeforeStandaloneModule {
            selectedSection = previous
        }
        sectionBeforeStandaloneModule = nil
    }

    // ------------------------------------------------------------------
    // Plan 5 — menu-bar quick input
    // ------------------------------------------------------------------

    /// Live text in the floating quick-input field. Exposed as state so the
    /// same draft survives showing/hiding the panel within a session.
    var quickInputDraft: String = ""
    /// Whether a quick-prompt is currently in flight. Drives the disabled
    /// state on the text field + busy indicator in the panel.
    var isSubmittingQuickInput: Bool = false
    /// The most recent quick-prompt outcome. Rendered as a "Latest result"
    /// card inside the panel; cleared when the draft changes.
    var quickInputLatestResult: WorkbenchRequestOutcome?

    var quickInputHint: String { snapshot.quickInputHint }
    var quickReply: String { snapshot.quickReply }
    var canUseQuickInput: Bool { snapshot.interactionCapabilities.canUseQuickInput }

    /// Derives the menu-bar state ring label (idle / working / waiting_review
    /// / waiting_input / degraded). Mirrors the TS `deriveMenuState` helper
    /// so the UX matches the legacy shell.
    var menuBarState: WorkbenchMenuBarState {
        if tasks.contains(where: { $0.status == .needsApproval }) {
            return .waitingReview
        }
        if tasks.contains(where: { $0.status == .blocked }) {
            return .waitingInput
        }
        if tasks.contains(where: { $0.status == .failed }) {
            return .degraded
        }
        if tasks.contains(where: { $0.status == .queued || $0.status == .running }) {
            return .working
        }
        if snapshot.runtimeStatus.state != .live {
            return .degraded
        }
        return .idle
    }

    /// Submits the current `quickInputDraft` (or an explicit override). When
    /// automatic conversation routing is disabled, this preserves the current
    /// explicit selected-session behavior.
    func submitQuickInput(_ prompt: String? = nil) {
        let raw = prompt ?? quickInputDraft
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              canUseQuickInput,
              !isSubmittingQuickInput
        else { return }

        isSubmittingQuickInput = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot
        let useAutoConversationRouting = autoConversationRoutingEnabled
        let conversationID = selectedConversation?.id ?? conversations.first?.id

        Task { [weak self, runtimeClient, currentSnapshot, trimmed, useAutoConversationRouting, conversationID] in
            do {
                let nextSnapshot: WorkbenchSnapshot
                if useAutoConversationRouting {
                    nextSnapshot = try await runtimeClient.submitQuickPrompt(
                        trimmed,
                        in: currentSnapshot
                    )
                } else {
                    guard let conversationID else {
                        await MainActor.run {
                            guard let self else { return }
                            self.lastErrorMessage = "No conversation available to carry the quick prompt."
                            self.isSubmittingQuickInput = false
                        }
                        return
                    }
                    nextSnapshot = try await runtimeClient.sendMessage(
                        trimmed,
                        in: currentSnapshot,
                        conversationID: conversationID
                    )
                }
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = nextSnapshot
                    if useAutoConversationRouting,
                       let routedConversationID = nextSnapshot.conversations.first(where: \.isActive)?.id {
                        self.selectedConversationID = routedConversationID
                    }
                    self.quickInputLatestResult = nextSnapshot.lastOutcome
                    self.quickInputDraft = ""
                    self.isSubmittingQuickInput = false
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.lastErrorMessage = error.localizedDescription
                    self.isSubmittingQuickInput = false
                }
            }
        }
    }

    /// Resets the quick input to a fresh state (used on panel dismissal).
    func resetQuickInput() {
        quickInputDraft = ""
        quickInputLatestResult = nil
        isSubmittingQuickInput = false
    }

    var canCreateConversation: Bool {
        interactionCapabilities.canMutateRuntime
    }

    var canSendMessages: Bool {
        interactionCapabilities.canSendMessages
    }

    var canMutateRuntime: Bool {
        interactionCapabilities.canMutateRuntime
    }

    func createConversation(openSection: Bool = true) {
        guard !isCreatingConversation else {
            return
        }

        isCreatingConversation = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot

        Task { [weak self, runtimeClient, currentSnapshot] in
            do {
                let nextSnapshot = try await runtimeClient.createConversation(in: currentSnapshot)
                await MainActor.run {
                    guard let self else { return }
                    let newConversationID = nextSnapshot.conversations.first(where: \.isActive)?.id
                        ?? nextSnapshot.conversations.first?.id
                    self.snapshot = nextSnapshot
                    self.selectedConversationID = newConversationID
                    if openSection {
                        self.selectedSection = .chat
                    }
                    self.isCreatingConversation = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isCreatingConversation = false
                }
            }
        }
    }

    func sendMessage(_ message: String, openSection: Bool = true) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, canSendMessages else {
            return
        }

        if let conversationID = selectedConversation?.id {
            sendMessage(trimmedMessage, in: snapshot, conversationID: conversationID, openSection: openSection)
            return
        }

        guard canCreateConversation, !isCreatingConversation else {
            return
        }

        isCreatingConversation = true
        isSendingMessage = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot

        Task { [weak self, runtimeClient, currentSnapshot] in
            do {
                let createdSnapshot = try await runtimeClient.createConversation(in: currentSnapshot)
                guard let conversationID = createdSnapshot.conversations.first(where: \.isActive)?.id ?? createdSnapshot.conversations.first?.id else {
                    throw NSError(domain: "GeeAgentMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create a conversation."])
                }
                let nextSnapshot = try await runtimeClient.sendMessage(
                    trimmedMessage,
                    in: createdSnapshot,
                    conversationID: conversationID
                )
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = nextSnapshot
                    if openSection {
                        self.selectedSection = .chat
                    }
                    self.isCreatingConversation = false
                    self.isSendingMessage = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isCreatingConversation = false
                    self?.isSendingMessage = false
                }
            }
        }
    }

    func renameSelectedConversation(_ title: String) {
        guard let conversationID = selectedConversation?.id else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        conversationTitleOverrides[conversationID] = trimmedTitle
    }

    func performSelectedTaskAction(_ action: WorkbenchTaskAction) {
        guard let taskID = selectedTask?.id else {
            return
        }

        performTaskAction(action, taskID: taskID)
    }

    func performTaskAction(
        _ action: WorkbenchTaskAction,
        taskID: WorkbenchTaskRecord.ID,
        openSection: Bool = true
    ) {
        guard canMutateRuntime, !isPerformingTaskAction else {
            return
        }

        isPerformingTaskAction = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot

        Task { [weak self, runtimeClient, currentSnapshot] in
            do {
                let nextSnapshot = try await runtimeClient.performTaskAction(
                    action,
                    in: currentSnapshot,
                    taskID: taskID
                )
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = nextSnapshot
                    if openSection {
                        self.selectedSection = .logs
                    }
                    self.isPerformingTaskAction = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isPerformingTaskAction = false
                }
            }
        }
    }

    func activateSelectedConversation() {
        guard
            let conversationID = selectedConversationID,
            selectedConversation?.isActive != true,
            !isActivatingConversation
        else {
            return
        }

        isActivatingConversation = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot
        Task { [weak self, runtimeClient] in
            do {
                let nextSnapshot = try await runtimeClient.activateConversation(
                    conversationID,
                    in: currentSnapshot
                )
                await MainActor.run {
                    self?.snapshot = nextSnapshot
                    self?.isActivatingConversation = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isActivatingConversation = false
                }
            }
        }
    }

    func deleteConversation(_ conversationID: ConversationThread.ID) {
        guard canMutateRuntime, !isDeletingConversation else {
            return
        }

        isDeletingConversation = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot

        Task { [weak self, runtimeClient, currentSnapshot] in
            do {
                let nextSnapshot = try await runtimeClient.deleteConversation(
                    conversationID,
                    in: currentSnapshot
                )
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = nextSnapshot
                    self.selectedSection = .chat
                    self.isDeletingConversation = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isDeletingConversation = false
                }
            }
        }
    }

    func dismissError() {
        lastErrorMessage = nil
    }

    func copyMessageContent(_ content: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
    }

    func deleteMessage(_ messageID: ConversationMessage.ID, from conversationID: ConversationThread.ID) {
        guard canMutateRuntime,
              let conversationIndex = snapshot.conversations.firstIndex(where: { $0.id == conversationID })
        else {
            return
        }

        var nextSnapshot = snapshot
        nextSnapshot.conversations[conversationIndex].messages.removeAll { $0.id == messageID }
        snapshot = nextSnapshot
    }

    func openSection(_ section: WorkbenchSection) {
        if section != .home {
            homeSurfaceMode = .companion
        }
        selectedSection = section
    }

    func openTask(_ taskID: WorkbenchTaskRecord.ID?) {
        guard let taskID else { return }
        selectedTaskID = taskID
        openSection(.logs)
    }

    func openHomeChatFocus() {
        selectedSection = .home
        homeSurfaceMode = .chatFocus
    }

    func openHomeTaskFocus() {
        selectedSection = .home
        homeSurfaceMode = .taskFocus
    }

    func closeHomeFocus() {
        homeSurfaceMode = .companion
    }

    func openLastOutcomeTarget() {
        selectedSection = .logs
        homeSurfaceMode = .companion

        guard let taskID = lastOutcome?.taskID, tasks.contains(where: { $0.id == taskID }) else {
            return
        }

        selectedTaskID = taskID
    }

    func setHomeVisualEffectMode(_ mode: HomeVisualEffectMode) {
        homeVisualEffectMode = mode
    }

    // MARK: - Active persona appearance

    /// The appearance the home hero layer should render for the active persona.
    ///
    /// This is now fully driven by the loaded profile definition. Local
    /// `profileAppearancePreferences` are still used for Live2D viewport and
    /// motion state, but they no longer override the profile's base appearance.
    var effectiveActiveAppearance: AgentProfileAppearanceRecord {
        activeAgentProfile?.appearance ?? .abstract
    }

    /// Internal render enum used by the scene background to branch between
    /// "banner-style media" (image/video/live2d) and the procedural abstract field.
    var effectiveHomeVisualMode: HomeHeroVisualMode {
        switch effectiveActiveAppearance {
        case .abstract: return .abstract
        default: return .banner
        }
    }

    /// File path for the active persona's banner asset, if the current appearance carries one.
    var effectiveBannerAssetPath: String? {
        switch effectiveActiveAppearance {
        case .staticImage(let path), .video(let path):
            return path
        case .live2D, .abstract:
            return nil
        }
    }

    /// Preference record describing how the user has customized the active persona's appearance.
    var activeProfileAppearancePreference: ProfileAppearancePreference {
        guard let profile = activeAgentProfile else { return .abstractDefault }
        if let pref = profileAppearancePreferences[profile.id] { return pref }
        return ProfileAppearancePreference.from(appearance: profile.appearance)
    }

    var live2DViewportState: Live2DViewportState {
        Live2DViewportState(
            offsetX: activeProfileAppearancePreference.live2DOffsetX ?? 0,
            offsetY: activeProfileAppearancePreference.live2DOffsetY ?? 0,
            scale: activeProfileAppearancePreference.live2DScale ?? 1
        ).clamped()
    }

    var availableLive2DPoses: [Live2DMotionRecord] {
        live2DActionCatalog.poses
    }

    var availableLive2DActionMotions: [Live2DMotionRecord] {
        live2DActionCatalog.actions
    }

    var availableLive2DExpressions: [Live2DExpressionRecord] {
        live2DActionCatalog.expressions
    }

    var activeLive2DPosePath: String? {
        let preferredPath = activeProfileAppearancePreference.live2DIdlePosePath
        if let preferredPath,
           availableLive2DPoses.contains(where: { $0.relativePath == preferredPath }) {
            return preferredPath
        }

        return live2DActionCatalog.defaultPose?.relativePath ?? availableLive2DPoses.first?.relativePath
    }

    var activeLive2DExpressionPath: String? {
        temporaryLive2DExpressionPath ?? activeProfileAppearancePreference.live2DExpressionPath
    }

    var selectedLive2DPose: Live2DMotionRecord? {
        guard let activeLive2DPosePath else { return nil }
        return availableLive2DPoses.first(where: { $0.relativePath == activeLive2DPosePath })
    }

    var selectedLive2DExpression: Live2DExpressionRecord? {
        guard let expressionPath = activeProfileAppearancePreference.live2DExpressionPath else { return nil }
        return availableLive2DExpressions.first(where: { $0.relativePath == expressionPath })
    }

    /// Switch the active persona to a new appearance kind, preserving any per-kind asset paths
    /// the user picked earlier.
    func setActiveAppearanceKind(_ kind: AgentAppearanceKind) {
        guard let profile = activeAgentProfile else { return }
        var pref = profileAppearancePreferences[profile.id] ?? ProfileAppearancePreference.from(appearance: profile.appearance)
        pref.kind = kind
        profileAppearancePreferences[profile.id] = pref
    }

    /// Update the active persona's remembered asset path for a specific kind. If `kind` matches the
    /// current active kind, it becomes the rendered appearance immediately.
    func setActiveAppearanceAssetPath(_ path: String?, for kind: AgentAppearanceKind) {
        guard let profile = activeAgentProfile else { return }
        var pref = profileAppearancePreferences[profile.id] ?? ProfileAppearancePreference.from(appearance: profile.appearance)
        switch kind {
        case .staticImage: pref.staticImagePath = path
        case .video: pref.videoPath = path
        case .live2D: pref.live2DBundlePath = path
        case .abstract: break
        }
        profileAppearancePreferences[profile.id] = pref
    }

    /// Replace the active persona's appearance preference outright.
    func updateActiveProfileAppearance(_ preference: ProfileAppearancePreference) {
        guard let profile = activeAgentProfile else { return }
        profileAppearancePreferences[profile.id] = preference
    }

    /// Clear any local override for the active persona, reverting to the baseline appearance
    /// carried by `AgentProfile.appearance` in the runtime snapshot. Safe to call when there is
    /// no override — it's a no-op.
    func clearActiveProfileAppearanceOverride() {
        guard let profile = activeAgentProfile else { return }
        guard profileAppearancePreferences[profile.id] != nil else { return }
        profileAppearancePreferences.removeValue(forKey: profile.id)
    }

    func setLive2DPose(_ pose: Live2DMotionRecord?) {
        guard let profile = activeAgentProfile else { return }
        var pref = profileAppearancePreferences[profile.id] ?? ProfileAppearancePreference.from(appearance: profile.appearance)
        pref.live2DIdlePosePath = pose?.relativePath
        profileAppearancePreferences[profile.id] = pref
    }

    func setLive2DExpression(_ expression: Live2DExpressionRecord?) {
        guard let profile = activeAgentProfile else { return }
        live2DExpressionRestoreTask?.cancel()
        temporaryLive2DExpressionPath = nil
        var pref = profileAppearancePreferences[profile.id] ?? ProfileAppearancePreference.from(appearance: profile.appearance)
        pref.live2DExpressionPath = expression?.relativePath
        profileAppearancePreferences[profile.id] = pref
    }

    func resetLive2DExpression() {
        setLive2DExpression(nil)
    }

    func translateLive2D(by delta: CGSize) {
        guard let profile = activeAgentProfile else { return }
        var pref = profileAppearancePreferences[profile.id] ?? ProfileAppearancePreference.from(appearance: profile.appearance)
        let next = Live2DViewportState(
            offsetX: (pref.live2DOffsetX ?? 0) + delta.width,
            offsetY: (pref.live2DOffsetY ?? 0) + delta.height,
            scale: pref.live2DScale ?? 1
        ).clamped()
        pref.live2DOffsetX = next.offsetX
        pref.live2DOffsetY = next.offsetY
        pref.live2DScale = next.scale
        profileAppearancePreferences[profile.id] = pref
    }

    func adjustLive2DScale(by multiplier: Double) {
        guard let profile = activeAgentProfile else { return }
        var pref = profileAppearancePreferences[profile.id] ?? ProfileAppearancePreference.from(appearance: profile.appearance)
        let next = Live2DViewportState(
            offsetX: pref.live2DOffsetX ?? 0,
            offsetY: pref.live2DOffsetY ?? 0,
            scale: (pref.live2DScale ?? 1) * multiplier
        ).clamped()
        pref.live2DOffsetX = next.offsetX
        pref.live2DOffsetY = next.offsetY
        pref.live2DScale = next.scale
        profileAppearancePreferences[profile.id] = pref
    }

    func resetLive2DViewport() {
        guard let profile = activeAgentProfile else { return }
        var pref = profileAppearancePreferences[profile.id] ?? ProfileAppearancePreference.from(appearance: profile.appearance)
        pref.live2DOffsetX = nil
        pref.live2DOffsetY = nil
        pref.live2DScale = nil
        profileAppearancePreferences[profile.id] = pref
    }

    func triggerRandomLive2DReaction() {
        guard case .live2D = effectiveActiveAppearance else { return }

        if !availableLive2DActionMotions.isEmpty {
            let candidates = availableLive2DActionMotions.filter { $0.category == .action }
            if let motion = candidates.randomElement() {
                triggerLive2DAction(motion)
                return
            }
        }

        let expressionCandidates = availableLive2DExpressions.filter {
            $0.relativePath != activeLive2DExpressionPath
        }
        if let expression = (expressionCandidates.isEmpty ? availableLive2DExpressions : expressionCandidates).randomElement() {
            live2DExpressionRestoreTask?.cancel()
            temporaryLive2DExpressionPath = expression.relativePath
            live2DExpressionRestoreTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.4))
                guard let self, !Task.isCancelled else { return }
                self.temporaryLive2DExpressionPath = nil
            }
            return
        }

        let poseCandidates = availableLive2DPoses.filter {
            $0.relativePath != activeLive2DPosePath
        }
        guard let pose = poseCandidates.randomElement() else { return }
        playLive2DMotion(pose)
        if let defaultPosePath = live2DActionCatalog.defaultPose?.relativePath ?? activeLive2DPosePath {
            schedulePoseRestore(to: defaultPosePath, after: pose.durationSeconds ?? 2.4)
        }
    }

    func triggerLive2DAction(_ motion: Live2DMotionRecord) {
        guard motion.category == .action else {
            playLive2DMotion(motion)
            return
        }

        playLive2DMotion(motion)
        if let posePath = activeLive2DPosePath {
            schedulePoseRestore(to: posePath, after: motion.durationSeconds ?? (motion.isLoop ? 2.4 : 1.6))
        }
    }

    func playLive2DMotion(_ motion: Live2DMotionRecord) {
        guard case let .live2D(bundlePath) = effectiveActiveAppearance, !bundlePath.isEmpty else {
            return
        }

        live2DMotionPlaybackRequest = Live2DMotionPlaybackRequest(bundlePath: bundlePath, motion: motion)
    }

    /// True when the active persona currently has any local appearance override — useful for
    /// deciding whether a "Revert to profile default" action should be enabled.
    var activeProfileHasAppearanceOverride: Bool {
        guard let profile = activeAgentProfile else { return false }
        return profileAppearancePreferences[profile.id] != nil
    }

    /// True when an appearance kind is selectable for the active persona given current state.
    /// - `staticImage`, `video`, `abstract` are always selectable (image/video fall back to the
    ///   bundled hero; abstract never needs an asset).
    /// - `live2D` is selectable when either the persona's baseline appearance is `.live2D` or
    ///   the override has remembered a bundle path. Prevents locking users into a one-way
    ///   downgrade when a Live2D-first persona is flipped to another kind.
    func isAppearanceKindSelectable(_ kind: AgentAppearanceKind) -> Bool {
        switch kind {
        case .staticImage, .video, .abstract:
            return true
        case .live2D:
            if let profile = activeAgentProfile, profile.appearance.kind == .live2D {
                return true
            }
            if let pref = activeAgentProfile.flatMap({ profileAppearancePreferences[$0.id] }),
               let path = pref.live2DBundlePath, !path.isEmpty {
                return true
            }
            return false
        }
    }

    private func persistProfileAppearancePreferences() {
        let defaults = UserDefaults.standard
        if profileAppearancePreferences.isEmpty {
            defaults.removeObject(forKey: PreferenceKey.profileAppearancePreferences)
            return
        }
        if let data = try? JSONEncoder().encode(profileAppearancePreferences) {
            defaults.set(data, forKey: PreferenceKey.profileAppearancePreferences)
        }
    }

    private static func loadAppearancePreferences(from defaults: UserDefaults) -> [String: ProfileAppearancePreference] {
        guard let data = defaults.data(forKey: PreferenceKey.profileAppearancePreferences) else { return [:] }
        return (try? JSONDecoder().decode([String: ProfileAppearancePreference].self, from: data)) ?? [:]
    }

    private func refreshActiveLive2DState() {
        guard case let .live2D(bundlePath) = effectiveActiveAppearance, !bundlePath.isEmpty else {
            live2DActionCatalog = .empty
            live2DMotionPlaybackRequest = nil
            temporaryLive2DExpressionPath = nil
            live2DExpressionRestoreTask?.cancel()
            live2DPoseRestoreTask?.cancel()
            return
        }

        live2DActionCatalog = Live2DMotionCatalog.discoverCatalog(bundlePath: bundlePath)

        if let request = live2DMotionPlaybackRequest,
           request.bundlePath != URL(fileURLWithPath: bundlePath).standardizedFileURL.path {
            live2DMotionPlaybackRequest = nil
        }

        sanitizeActiveLive2DSelections()
    }

    private func sanitizeActiveLive2DSelections() {
        guard let profile = activeAgentProfile else { return }
        guard case .live2D = effectiveActiveAppearance else { return }

        var pref = profileAppearancePreferences[profile.id] ?? ProfileAppearancePreference.from(appearance: profile.appearance)
        var didChange = false

        if let posePath = pref.live2DIdlePosePath,
           !live2DActionCatalog.poses.contains(where: { $0.relativePath == posePath }) {
            pref.live2DIdlePosePath = nil
            didChange = true
        }

        if let expressionPath = pref.live2DExpressionPath,
           !live2DActionCatalog.expressions.contains(where: { $0.relativePath == expressionPath }) {
            pref.live2DExpressionPath = nil
            didChange = true
        }

        if let temporaryLive2DExpressionPath,
           !live2DActionCatalog.expressions.contains(where: { $0.relativePath == temporaryLive2DExpressionPath }) {
            self.temporaryLive2DExpressionPath = nil
        }

        if didChange {
            profileAppearancePreferences[profile.id] = pref
        }
    }

    private func schedulePoseRestore(to relativePath: String, after seconds: Double) {
        live2DPoseRestoreTask?.cancel()
        live2DPoseRestoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0.2, seconds)))
            guard let self, !Task.isCancelled else { return }
            guard let pose = self.availableLive2DPoses.first(where: { $0.relativePath == relativePath }) else { return }
            self.playLive2DMotion(pose)
        }
    }

    /// One-shot migration: the pre-persona build stored a global `homeVisualMode` and
    /// `homeBannerImagePath`. Translate them into an override for the active persona on first
    /// launch after upgrade, then delete the legacy keys so we never migrate twice.
    private func migrateLegacyHomeAppearancePreferences(defaults: UserDefaults) {
        let legacyMode = defaults.string(forKey: PreferenceKey.legacyHomeVisualMode)
        let legacyBannerPath = defaults.string(forKey: PreferenceKey.legacyHomeBannerImagePath)

        guard legacyMode != nil || legacyBannerPath != nil else { return }
        guard let profile = activeAgentProfile else { return }

        // Only seed the override if the user hasn't already customized this persona.
        if profileAppearancePreferences[profile.id] == nil {
            var pref = ProfileAppearancePreference.from(appearance: profile.appearance)

            switch legacyMode {
            case "abstract":
                pref.kind = .abstract
            case "banner", .some(_):
                if let path = legacyBannerPath, !path.isEmpty {
                    applyLegacyBanner(path: path, into: &pref, personaID: profile.id)
                } else {
                    pref.kind = .staticImage
                }
            default:
                if let path = legacyBannerPath, !path.isEmpty {
                    applyLegacyBanner(path: path, into: &pref, personaID: profile.id)
                }
            }

            profileAppearancePreferences[profile.id] = pref
        }

        defaults.removeObject(forKey: PreferenceKey.legacyHomeVisualMode)
        defaults.removeObject(forKey: PreferenceKey.legacyHomeBannerImagePath)
        PersonaAssetManager.cleanupLegacyBannersDirectory()
    }

    /// Mutates `pref` so the legacy banner (under `GeeAgent/Banners/`) is re-homed under the
    /// persona's own directory. Falls back to the raw path if the copy fails so we never
    /// silently drop an in-use asset.
    private func applyLegacyBanner(path: String, into pref: inout ProfileAppearancePreference, personaID: String) {
        let migrated = PersonaAssetManager.migrateLegacyBanner(path: path, forPersona: personaID) ?? path
        if PersonaAssetManager.isVideoPath(path) {
            pref.kind = .video
            pref.videoPath = migrated
        } else {
            pref.kind = .staticImage
            pref.staticImagePath = migrated
        }
    }

    private var nextAutomation: AutomationRecord? {
        automations.first(where: { $0.status != .paused }) ?? automations.first
    }

    private func sendMessage(
        _ message: String,
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        openSection: Bool
    ) {
        isSendingMessage = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient

        Task { [weak self, runtimeClient, snapshot] in
            do {
                let nextSnapshot = try await runtimeClient.sendMessage(
                    message,
                    in: snapshot,
                    conversationID: conversationID
                )
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = nextSnapshot
                    if openSection {
                        self.selectedSection = .chat
                    }
                    self.isSendingMessage = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isSendingMessage = false
                }
            }
        }
    }

    private func normalizeSelections() {
        normalizeSelectedHomeItem()
        normalizeSelectedConversation()
        normalizeSelectedTask()
        normalizeSelectedAutomation()
        normalizeSelectedExtension()
        normalizeSelectedSettingsPane()
        normalizeActiveAgentProfile()
        normalizeSelectedAgentProfile()
    }

    private func normalizeSelectedHomeItem() {
        let normalizedID = normalizedID(selectedHomeItemID, validIDs: homeItems.map(\.id))
        if selectedHomeItemID != normalizedID {
            selectedHomeItemID = normalizedID
        }
    }

    private func normalizeSelectedConversation() {
        let preferredID = conversations.first(where: \.isActive)?.id ?? conversations.first?.id
        let normalizedID = normalizedID(
            selectedConversationID,
            validIDs: conversations.map(\.id),
            preferredID: preferredID
        )
        if selectedConversationID != normalizedID {
            selectedConversationID = normalizedID
        }
    }

    private func normalizeSelectedTask() {
        let preferredID = tasks.first(where: { $0.status == .needsApproval || $0.status == .running || $0.status == .blocked })?.id
            ?? tasks.first?.id
        let normalizedID = normalizedID(selectedTaskID, validIDs: tasks.map(\.id), preferredID: preferredID)
        if selectedTaskID != normalizedID {
            selectedTaskID = normalizedID
        }
    }

    private func normalizeSelectedAutomation() {
        let preferredID = nextAutomation?.id
        let normalizedID = normalizedID(selectedAutomationID, validIDs: automations.map(\.id), preferredID: preferredID)
        if selectedAutomationID != normalizedID {
            selectedAutomationID = normalizedID
        }
    }

    private func normalizeSelectedExtension() {
        let normalizedSelection: WorkbenchExtensionSelection?

        switch selectedExtension {
        case let .some(.app(id)):
            if installedApps.contains(where: { $0.id == id }) {
                normalizedSelection = .app(id)
            } else {
                normalizedSelection = installedApps.first.map { .app($0.id) }
                    ?? agentSkins.first.map { .skin($0.id) }
            }
        case let .some(.skin(id)):
            if agentSkins.contains(where: { $0.id == id }) {
                normalizedSelection = .skin(id)
            } else {
                normalizedSelection = agentSkins.first.map { .skin($0.id) }
                    ?? installedApps.first.map { .app($0.id) }
            }
        case .none:
            normalizedSelection = installedApps.first.map { .app($0.id) }
                ?? agentSkins.first.map { .skin($0.id) }
        }

        if selectedExtension != normalizedSelection {
            selectedExtension = normalizedSelection
        }
    }

    private func normalizeSelectedSettingsPane() {
        let normalizedID = normalizedID(selectedSettingsPaneID, validIDs: settingsPanes.map(\.id))
        if selectedSettingsPaneID != normalizedID {
            selectedSettingsPaneID = normalizedID
        }
    }

    private func normalizeActiveAgentProfile() {
        let validIDs = availableAgentProfiles.map(\.id)
        let resolvedID: AgentProfileRecord.ID?
        if let snapshotPreferredID = snapshot.activeAgentProfileID,
           validIDs.contains(snapshotPreferredID) {
            resolvedID = snapshotPreferredID
        } else if let currentID = activeAgentProfileID,
                  validIDs.contains(currentID) {
            resolvedID = currentID
        } else {
            resolvedID = validIDs.first
        }

        if activeAgentProfileID != resolvedID {
            activeAgentProfileID = resolvedID
        }
    }

    private func normalizeSelectedAgentProfile() {
        let normalizedID = normalizedID(
            selectedAgentProfileID,
            validIDs: availableAgentProfiles.map(\.id),
            preferredID: activeAgentProfileID
        )

        if selectedAgentProfileID != normalizedID {
            selectedAgentProfileID = normalizedID
        }
    }

    private func persistActiveAgentProfileID() {
        if let activeAgentProfileID, !activeAgentProfileID.isEmpty {
            UserDefaults.standard.set(activeAgentProfileID, forKey: PreferenceKey.activeAgentProfileId)
        } else {
            UserDefaults.standard.removeObject(forKey: PreferenceKey.activeAgentProfileId)
        }
    }

    private func resolvedAgentProfiles(from snapshot: WorkbenchSnapshot) -> [AgentProfileRecord] {
        var profiles = snapshot.availableAgentProfiles

        if profiles.isEmpty {
            profiles = snapshot.agentSkins.map(\.asAgentProfileRecord)
        }

        if !profiles.contains(where: { $0.id == Self.defaultBundledAgentProfile.id }) {
            profiles.insert(Self.defaultBundledAgentProfile, at: 0)
        }

        return uniqueAgentProfiles(profiles)
    }

    private func uniqueAgentProfiles(_ profiles: [AgentProfileRecord]) -> [AgentProfileRecord] {
        var seenIDs = Set<AgentProfileRecord.ID>()
        var uniqueProfiles: [AgentProfileRecord] = []

        for profile in profiles where seenIDs.insert(profile.id).inserted {
            uniqueProfiles.append(profile)
        }

        return uniqueProfiles
    }

    private func normalizedID<ID: Equatable>(_ currentID: ID?, validIDs: [ID], preferredID: ID? = nil) -> ID? {
        if let currentID, validIDs.contains(currentID) {
            return currentID
        }

        if let preferredID, validIDs.contains(preferredID) {
            return preferredID
        }

        return validIDs.first
    }
}

private extension WorkbenchStore {
    static let defaultBundledAgentProfile = AgentProfileRecord(
        id: "gee",
        name: "Gee",
        tagline: "Calm native operator for chat, tasks, and desktop workflows.",
        personalityPrompt: "You are Gee, the default first-party persona for the GeeAgent macOS workbench. Stay warm, concise, and operationally grounded while keeping chat history global across persona changes.",
        appearance: .abstract,
        skills: [
            AgentSkillReferenceRecord(id: "chat-routing", name: "Chat Routing"),
            AgentSkillReferenceRecord(id: "task-handoffs", name: "Task Handoffs"),
            AgentSkillReferenceRecord(id: "workflow-triage", name: "Workflow Triage"),
        ],
        allowedToolIDs: nil,
        source: .firstParty,
        version: "1.0.0"
    )
}
