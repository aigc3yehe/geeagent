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

    private struct PendingChatTurn: Identifiable, Hashable {
        let id: String
        let conversationID: ConversationThread.ID
        let content: String
        let attachments: [WorkspaceInputAttachment]
        let createdAt: Date
        let previousMessageIDs: Set<ConversationMessage.ID>

        var userMessageID: String {
            "pending-user-\(id)"
        }

        var thinkingMessageID: String {
            "pending-thinking-\(id)"
        }
    }

    let runtimeClient: any WorkbenchRuntimeClient
    let audioCapture = AudioCaptureCoordinator()
    private var conversationTitleOverrides: [ConversationThread.ID: String] = [:]
    private var pendingChatTurn: PendingChatTurn?
    private var scheduledHostActionBatches: Set<String> = []
    private var inFlightHostActionIDs: Set<String> = []
    private var completedHostActionCompletions: [String: WorkbenchHostActionCompletion] = [:]
    private var activeChatRequestID: String?
    private var cancelledChatRequestIDs: Set<String> = []
    private var scheduledExternalInvocationIDs: Set<String> = []
    private var liveSnapshotPollingTask: Task<Void, Never>?
    private var externalInvocationPollingTask: Task<Void, Never>?

    var snapshot: WorkbenchSnapshot {
        didSet {
            normalizeSelections()
            refreshActiveLive2DState()
            if snapshot.hostActionIntents.isEmpty {
                scheduledHostActionBatches.removeAll()
            } else {
                applyHostActionIntents(snapshot.hostActionIntents)
            }
            applyExternalInvocations(snapshot.externalInvocations)
            resetRuntimeRunInspectorIfNeeded()
        }
    }
    var lastErrorMessage: String?
    var chatErrorMessage: String?
    var isCreatingConversation = false
    var isActivatingConversation = false
    var isDeletingConversation = false
    var isSendingMessage = false
    var isStoppingMessage = false
    var isPerformingTaskAction = false
    var isDeletingTerminalPermissionRule = false
    var isAddingSystemSkillSource = false
    var isAddingPersonaSkillSource = false
    var isRemovingSkillSource = false
    var isUpdatingHighestAuthorization = false
    var isLoadingChatRoutingSettings = false
    var isSavingChatRoutingSettings = false
    var isLoadingRuntimeRunInspector = false
    var chatRoutingSettings: ChatRoutingSettings?
    var providerSecretSettings = ProviderSecretSettings.defaultSettings
    var isLoadingProviderSecretSettings = false
    var savingProviderSecretIDs: Set<String> = []
    var selectedRuntimeRunProjection: WorkbenchRuntimeRunProjection?
    var selectedRuntimeRunWait: WorkbenchRuntimeRunWaitClassification?
    var runtimeRunInspectorErrorMessage: String?
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
            resetRuntimeRunInspectorIfNeeded()
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
        expireLoadedHostActionIntents(snapshot.hostActionIntents, loadedSnapshot: snapshot)
        applyExternalInvocations(snapshot.externalInvocations)
        startExternalInvocationPolling()
    }

    func shutdownRuntime() {
        liveSnapshotPollingTask?.cancel()
        externalInvocationPollingTask?.cancel()
        TelegramBridgeGearStore.shared.stopInboundService()
        (runtimeClient as? NativeWorkbenchRuntimeClient)?.shutdown()
    }

    func startEnabledGearBackgroundServices() {
        startTelegramBridgeInboundServiceIfEnabled()
    }

    func setGearEnabled(_ isEnabled: Bool, gearID: String) {
        GearHost.setEnabled(isEnabled, gearID: gearID)
        if isEnabled {
            startBackgroundServiceIfNeeded(for: gearID)
        } else {
            stopBackgroundServiceIfNeeded(for: gearID)
            closeDisabledGearSurfaceIfNeeded(gearID: gearID)
        }
    }

    private func startBackgroundServiceIfNeeded(for gearID: String) {
        switch gearID {
        case TelegramBridgeGearDescriptor.gearID:
            startTelegramBridgeInboundServiceIfEnabled()
        default:
            break
        }
    }

    private func stopBackgroundServiceIfNeeded(for gearID: String) {
        switch gearID {
        case TelegramBridgeGearDescriptor.gearID:
            TelegramBridgeGearStore.shared.stopInboundService()
        default:
            break
        }
    }

    private func closeDisabledGearSurfaceIfNeeded(gearID: String) {
        if presentedStandaloneModuleID == gearID {
            closeStandaloneModule()
        }
        if selectedExtension == .app(gearID) {
            selectedExtension = firstSelectableExtensionSelection(excluding: gearID)
        }
    }

    private func firstSelectableExtensionSelection(excluding gearID: String? = nil) -> WorkbenchExtensionSelection? {
        firstSelectableInstalledApp(excluding: gearID).map { .app($0.id) }
            ?? agentSkins.first.map { .skin($0.id) }
    }

    private func firstSelectableInstalledApp(excluding gearID: String? = nil) -> InstalledAppRecord? {
        installedApps.first { app in
            app.id != gearID && isSelectableInstalledApp(app)
        }
    }

    private func isSelectableInstalledApp(_ app: InstalledAppRecord) -> Bool {
        !app.isGearPackage || GearHost.isEnabled(gearID: app.id)
    }

    private func startTelegramBridgeInboundServiceIfEnabled() {
        guard GearHost.isEnabled(gearID: TelegramBridgeGearDescriptor.gearID) else {
            TelegramBridgeGearStore.shared.stopInboundService()
            return
        }
        TelegramBridgeGearStore.shared.startInboundService { [weak self] payload in
            guard let self else {
                throw RuntimeProcessError.runtimeUnavailable("GeeAgent workbench store is unavailable for Telegram channel ingress.")
            }
            return try await self.submitTelegramChannelMessage(payload)
        }
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
    private var userFacingChatConversations: [ConversationThread] {
        conversations.filter { !isTelegramBridgeConversation($0) }
    }
    var displayConversations: [ConversationThread] {
        userFacingChatConversations.map(displayConversation)
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
    var skillSources: SkillSourcesRecord { snapshot.skillSources }
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
        userFacingChatConversations.first(where: { $0.id == selectedConversationID }) ?? userFacingChatConversations.first
    }

    var selectedRuntimeRunID: String? {
        selectedConversation?.runtimeRunSummary?.runID
    }

    var selectedDisplayConversation: ConversationThread? {
        selectedConversation.map(displayConversation)
    }

    func displayConversation(_ conversation: ConversationThread) -> ConversationThread {
        guard let pendingChatTurn,
              pendingChatTurn.conversationID == conversation.id
        else {
            return conversation
        }

        var updated = conversation
        let hasRuntimeUser = updated.messages.contains { message in
            message.id != pendingChatTurn.userMessageID
                && !pendingChatTurn.previousMessageIDs.contains(message.id)
                && message.role == .user
                && message.kind == .chat
                && message.content == pendingChatTurn.content
        }
        let hasPendingUser = hasRuntimeUser || updated.messages.contains { message in
            message.id == pendingChatTurn.userMessageID
        }

        if !hasPendingUser {
            updated.messages.append(
                ConversationMessage(
                    id: pendingChatTurn.userMessageID,
                    role: .user,
                    kind: .chat,
                    content: pendingChatTurn.content,
                    timestampLabel: "Sending...",
                    attachments: pendingChatTurn.attachments.map(conversationAttachment),
                    detailItems: pendingChatTurn.attachments.map { attachment in
                        ConversationMessageDetailItem(
                            label: "Attachment",
                            value: "\(attachment.kind.rawValue) · \(attachment.displayName)"
                        )
                    }
                )
            )
        }

        let pendingTurnUserIndex = updated.messages.lastIndex { message in
            if message.id == pendingChatTurn.userMessageID {
                return true
            }
            return message.id != pendingChatTurn.userMessageID
                && !pendingChatTurn.previousMessageIDs.contains(message.id)
                && message.role == .user
                && message.kind == .chat
                && message.content == pendingChatTurn.content
        }
        let messagesAfterPendingUser: ArraySlice<ConversationMessage>
        if let pendingTurnUserIndex {
            messagesAfterPendingUser = updated.messages[updated.messages.index(after: pendingTurnUserIndex)...]
        } else {
            messagesAfterPendingUser = updated.messages[updated.messages.endIndex...]
        }
        let hasAssistantReplyAfterPendingUser = messagesAfterPendingUser.contains { message in
            message.role == .assistant
                && message.kind == .chat
                && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if !hasAssistantReplyAfterPendingUser,
           !updated.messages.contains(where: { $0.id == pendingChatTurn.thinkingMessageID }) {
            let hasToolActivityAfterPendingUser = messagesAfterPendingUser.contains { message in
                message.kind == .action || message.kind == .approval
            }
            let statusLabel: String
            let content: String
            if !hasRuntimeUser {
                statusLabel = "waiting for first event"
                content = "Request sent. Waiting for the runtime to return the first agent event."
            } else if hasToolActivityAfterPendingUser {
                statusLabel = "waiting for reply"
                content = "Tool activity finished. Waiting for the assistant to write the reply."
            } else {
                statusLabel = "thinking"
                content = "GeeAgent is thinking about the reply."
            }
            updated.messages.append(
                ConversationMessage(
                    id: pendingChatTurn.thinkingMessageID,
                    role: .assistant,
                    kind: .thinking,
                    headerTitle: "Thinking",
                    content: content,
                    timestampLabel: "Now",
                    statusLabel: statusLabel,
                    systemImage: "brain.head.profile",
                    tone: .info
                )
            )
        }

        updated.previewText = pendingChatTurn.content
        updated.lastActivityLabel = "Now"
        return updated
    }

    func shouldShowChatActivityFallback(for conversation: ConversationThread) -> Bool {
        guard isSendingMessage else {
            return false
        }
        return selectedConversationID == conversation.id
    }

    func chatActivityFallbackLabel(for conversation: ConversationThread) -> String {
        guard isSendingMessage else {
            return ""
        }
        guard let lastVisibleMessage = conversation.visibleMessages.last else {
            return "Request sent. GeeAgent is starting the run..."
        }

        switch lastVisibleMessage.kind {
        case .action:
            return "Tool activity is running. Waiting for GeeAgent to continue..."
        case .approval:
            return "Waiting for approval before GeeAgent can continue..."
        case .thinking:
            return "GeeAgent is thinking..."
        case .chat:
            switch lastVisibleMessage.role {
            case .user:
                return "GeeAgent is thinking..."
            case .assistant:
                return "GeeAgent is continuing the reply..."
            case .system:
                return "Request sent. Waiting for GeeAgent..."
            }
        }
    }

    private func conversationAttachment(_ attachment: WorkspaceInputAttachment) -> ConversationMessageAttachment {
        ConversationMessageAttachment(
            id: attachment.attachmentId,
            kind: conversationAttachmentKind(attachment.kind),
            displayName: attachment.displayName,
            originalPath: attachment.originalPath,
            resolvedPath: attachment.resolvedPath,
            mimeType: attachment.mimeType,
            sizeBytes: attachment.sizeBytes,
            status: conversationAttachmentStatus(attachment.status),
            source: attachment.source.rawValue,
            createdAt: attachment.createdAt,
            accessScope: attachment.access.scope,
            accessMode: attachment.access.mode,
            accessRoot: attachment.access.root,
            accessExpiresAt: attachment.access.expiresAt,
            imageWidth: attachment.image?.width,
            imageHeight: attachment.image?.height,
            maxBytes: attachment.limits?.maxBytes,
            maxEntries: attachment.limits?.maxEntries,
            maxDepth: attachment.limits?.maxDepth,
            errorCode: attachment.error?.code,
            errorMessage: attachment.error?.message,
            fallbackAttempted: attachment.fallbackAttempted
        )
    }

    private func conversationAttachmentKind(_ kind: WorkspaceInputAttachment.Kind) -> ConversationMessageAttachment.Kind {
        switch kind {
        case .image:
            return .image
        case .file:
            return .file
        case .directory:
            return .directory
        }
    }

    private func conversationAttachmentStatus(_ status: WorkspaceInputAttachment.Status) -> ConversationMessageAttachment.Status {
        switch status {
        case .ready:
            return .ready
        case .degraded:
            return .degraded
        case .failed:
            return .failed
        }
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
        guard case let .app(id) = selectedExtension else { return firstSelectableInstalledApp() }
        let app = installedApps.first(where: { $0.id == id })
        return app.flatMap { isSelectableInstalledApp($0) ? $0 : nil } ?? firstSelectableInstalledApp()
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
        let previousProfile = availableAgentProfiles.first { $0.id == profile.id }
        let nextSnapshot = try await runtimeClient.reloadAgentProfile(profile.id, in: currentSnapshot)
        snapshot = nextSnapshot
        reconcileReloadedAppearancePreference(profileID: profile.id, previousProfile: previousProfile)
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

    func addSystemSkillSource(from folderURL: URL) async throws {
        guard !isAddingSystemSkillSource else { return }
        isAddingSystemSkillSource = true
        lastErrorMessage = nil
        defer { isAddingSystemSkillSource = false }

        do {
            snapshot = try await runtimeClient.addSystemSkillSource(
                at: folderURL.path,
                in: snapshot
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func removeSystemSkillSource(_ source: SkillSourceRecord) async throws {
        guard !isRemovingSkillSource else { return }
        isRemovingSkillSource = true
        lastErrorMessage = nil
        defer { isRemovingSkillSource = false }

        do {
            snapshot = try await runtimeClient.removeSystemSkillSource(
                source.id,
                in: snapshot
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func addPersonaSkillSource(from folderURL: URL, to profile: AgentProfileRecord) async throws {
        guard !isAddingPersonaSkillSource else { return }
        isAddingPersonaSkillSource = true
        lastErrorMessage = nil
        defer { isAddingPersonaSkillSource = false }

        do {
            snapshot = try await runtimeClient.addPersonaSkillSource(
                profileID: profile.id,
                sourcePath: folderURL.path,
                in: snapshot
            )
            selectedAgentProfileID = profile.id
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func removePersonaSkillSource(_ source: SkillSourceRecord, from profile: AgentProfileRecord) async throws {
        guard !isRemovingSkillSource else { return }
        isRemovingSkillSource = true
        lastErrorMessage = nil
        defer { isRemovingSkillSource = false }

        do {
            snapshot = try await runtimeClient.removePersonaSkillSource(
                profileID: profile.id,
                sourceID: source.id,
                in: snapshot
            )
            selectedAgentProfileID = profile.id
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
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

    func loadProviderSecretSettings() {
        guard !isLoadingProviderSecretSettings else {
            return
        }

        isLoadingProviderSecretSettings = true
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient

        Task { [weak self, runtimeClient] in
            do {
                let settings = try await runtimeClient.loadProviderSecretSettings()
                await MainActor.run {
                    self?.providerSecretSettings = settings
                    self?.isLoadingProviderSecretSettings = false
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isLoadingProviderSecretSettings = false
                }
            }
        }
    }

    func saveProviderAPIKey(providerID: String, apiKey: String) {
        guard !savingProviderSecretIDs.contains(providerID) else {
            return
        }

        savingProviderSecretIDs.insert(providerID)
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient

        Task { [weak self, runtimeClient, providerID, apiKey] in
            do {
                let settings = try await runtimeClient.saveProviderAPIKey(
                    providerID: providerID,
                    apiKey: apiKey
                )
                await MainActor.run {
                    guard let self else { return }
                    self.providerSecretSettings = settings
                    self.savingProviderSecretIDs.remove(providerID)
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.savingProviderSecretIDs.remove(providerID)
                }
            }
        }
    }

    func clearProviderAPIKey(providerID: String) {
        guard !savingProviderSecretIDs.contains(providerID) else {
            return
        }

        savingProviderSecretIDs.insert(providerID)
        lastErrorMessage = nil
        let runtimeClient = self.runtimeClient

        Task { [weak self, runtimeClient, providerID] in
            do {
                let settings = try await runtimeClient.clearProviderAPIKey(providerID: providerID)
                await MainActor.run {
                    guard let self else { return }
                    self.providerSecretSettings = settings
                    self.savingProviderSecretIDs.remove(providerID)
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.savingProviderSecretIDs.remove(providerID)
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

    /// Entry point for agent-to-system tool calls. The store dispatches
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
                let resolvedOutcome = await GeeHostToolRouter.resolveCompletedIntent(outcome) ?? outcome
                await MainActor.run {
                    guard let self else { return }
                    self.applyToolOutcome(resolvedOutcome, from: invocation)
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
        case let .completed(_, payload):
            if (payload["status"] as? String)?.lowercased() == "failed" {
                lastErrorMessage = payload["error"] as? String
            } else {
                lastErrorMessage = nil
            }
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

    private func applyHostActionIntents(_ intents: [WorkbenchHostActionIntent]) {
        let runnableIntents = intents.filter {
            completedHostActionCompletions[$0.id] == nil &&
                !inFlightHostActionIDs.contains($0.id)
        }
        guard !runnableIntents.isEmpty else {
            return
        }
        let batchID = runnableIntents.map(\.id).joined(separator: "|")
        guard !scheduledHostActionBatches.contains(batchID) else {
            return
        }
        scheduledHostActionBatches.insert(batchID)
        runnableIntents.forEach { inFlightHostActionIDs.insert($0.id) }

        let currentSnapshot = snapshot
        Task { [weak self, runnableIntents, currentSnapshot] in
            do {
                guard let self else { return }
                let nextSnapshot = try await self.completeHostActionIntents(
                    runnableIntents,
                    in: currentSnapshot
                )
                await MainActor.run {
                    runnableIntents.forEach { self.inFlightHostActionIDs.remove($0.id) }
                    self.snapshot = nextSnapshot
                    self.quickInputLatestResult = nextSnapshot.lastOutcome
                    self.applyHostActionIntents(nextSnapshot.hostActionIntents)
                }
            } catch {
                await MainActor.run {
                    runnableIntents.forEach { self?.inFlightHostActionIDs.remove($0.id) }
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func resetCompletedHostActionsForFreshRuntimeTurn() {
        scheduledHostActionBatches.removeAll()
        completedHostActionCompletions.removeAll()
    }

    private func completeHostActionIntents(
        _ initialIntents: [WorkbenchHostActionIntent],
        in initialSnapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var workingSnapshot = initialSnapshot
        var intents = initialIntents
        var seenBatchIDs: Set<String> = []

        while !intents.isEmpty {
            let batchID = intents.map(\.id).joined(separator: "|")
            guard !seenBatchIDs.contains(batchID) else {
                throw RuntimeProcessError.runtimeInvocation(
                    "The runtime returned the same native Gear action batch more than once; refusing to repeat side effects."
                )
            }
            seenBatchIDs.insert(batchID)

            let completions = await hostActionCompletions(for: intents)
            guard !completions.isEmpty else {
                return workingSnapshot
            }

            workingSnapshot = try await runtimeClient.completeHostActionTurn(
                completions,
                in: workingSnapshot
            )
            intents = workingSnapshot.hostActionIntents
        }

        return workingSnapshot
    }

    private func hostActionCompletions(
        for intents: [WorkbenchHostActionIntent]
    ) async -> [WorkbenchHostActionCompletion] {
        var completions: [WorkbenchHostActionCompletion] = []
        for intent in intents {
            if let existing = completedHostActionCompletions[intent.id] {
                completions.append(existing)
                continue
            }
            let invocation = ToolInvocation(
                toolID: intent.toolID,
                arguments: intent.arguments
            )
            do {
                let rawOutcome = try await runtimeClient.invokeTool(invocation)
                let outcome = await GeeHostToolRouter.resolveCompletedIntent(rawOutcome) ?? rawOutcome
                let completion = Self.hostActionCompletion(for: intent, outcome: outcome)
                completedHostActionCompletions[intent.id] = completion
                completions.append(completion)
                applyToolOutcome(outcome, from: invocation)
            } catch {
                let completion = WorkbenchHostActionCompletion(
                    hostActionID: intent.id,
                    toolID: intent.toolID,
                    status: "failed",
                    summary: nil,
                    error: error.localizedDescription,
                    resultJSON: nil
                )
                completedHostActionCompletions[intent.id] = completion
                completions.append(completion)
                lastErrorMessage = error.localizedDescription
            }
        }
        return completions
    }

    private func applyExternalInvocations(_ invocations: [WorkbenchExternalInvocation]) {
        let pending = invocations.filter {
            $0.status == .pending && !scheduledExternalInvocationIDs.contains($0.id)
        }
        guard !pending.isEmpty else {
            return
        }
        pending.forEach { scheduledExternalInvocationIDs.insert($0.id) }
        let orderedPending = pending.sorted {
            Self.externalInvocationDrainPriority($0) < Self.externalInvocationDrainPriority($1)
        }

        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot
        Task { [weak self, runtimeClient, orderedPending, currentSnapshot] in
            var latestSnapshot = currentSnapshot
            for invocation in orderedPending {
                let toolInvocation = Self.toolInvocation(for: invocation)
                if toolInvocation == nil && !Self.canFastDrainExternalInvocation(invocation) {
                    let completion = WorkbenchExternalInvocationCompletion(
                        externalInvocationID: invocation.id,
                        status: .failed,
                        resultJSON: nil,
                        code: "gee.external_invocation.invalid",
                        message: "External invocation payload could not be converted into a Gee host tool invocation."
                    )
                    if let completedSnapshot = await self?.completeExternalInvocation(
                        completion,
                        runtimeClient: runtimeClient,
                        snapshot: latestSnapshot
                    ) {
                        latestSnapshot = completedSnapshot
                    }
                    continue
                }

                let runningCompletion = WorkbenchExternalInvocationCompletion(
                    externalInvocationID: invocation.id,
                    status: .running,
                    resultJSON: nil,
                    code: nil,
                    message: nil
                )
                let runningSnapshot: WorkbenchSnapshot
                do {
                    runningSnapshot = try await runtimeClient.completeExternalInvocation(
                        runningCompletion,
                        in: latestSnapshot
                    )
                    latestSnapshot = runningSnapshot
                    await MainActor.run {
                        guard let self else { return }
                        self.snapshot = runningSnapshot
                    }
                } catch {
                    await MainActor.run {
                        self?.lastErrorMessage = error.localizedDescription
                    }
                    continue
                }

                do {
                    let outcome: WorkbenchToolOutcome
                    if Self.canFastDrainExternalInvocation(invocation) {
                        outcome = await Self.fastExternalInvocationOutcome(for: invocation)
                    } else if let toolInvocation {
                        let rawOutcome = try await runtimeClient.invokeTool(toolInvocation)
                        outcome = await GeeHostToolRouter.resolveCompletedIntent(rawOutcome) ?? rawOutcome
                    } else {
                        outcome = .error(
                            toolID: "gee.gear.invoke",
                            code: "gee.external_invocation.invalid",
                            message: "External invocation payload could not be converted into a Gee host tool invocation."
                        )
                    }
                    let completion = Self.externalInvocationCompletion(for: invocation, outcome: outcome)
                    await MainActor.run {
                        guard let self else { return }
                        if let toolInvocation {
                            self.applyToolOutcome(outcome, from: toolInvocation)
                        }
                    }
                    if let completedSnapshot = await self?.completeExternalInvocation(
                        completion,
                        runtimeClient: runtimeClient,
                        snapshot: runningSnapshot
                    ) {
                        latestSnapshot = completedSnapshot
                    }
                } catch {
                    let completion = WorkbenchExternalInvocationCompletion(
                        externalInvocationID: invocation.id,
                        status: .failed,
                        resultJSON: nil,
                        code: "gee.external_invocation.host_error",
                        message: error.localizedDescription
                    )
                    if let completedSnapshot = await self?.completeExternalInvocation(
                        completion,
                        runtimeClient: runtimeClient,
                        snapshot: runningSnapshot
                    ) {
                        latestSnapshot = completedSnapshot
                    }
                }
            }
        }
    }

    private static func externalInvocationDrainPriority(_ invocation: WorkbenchExternalInvocation) -> Int {
        canFastDrainExternalInvocation(invocation) ? 0 : 1
    }

    private static func canFastDrainExternalInvocation(_ invocation: WorkbenchExternalInvocation) -> Bool {
        guard let capabilityID = invocation.capabilityID else {
            return false
        }
        return invocation.tool == .invokeCapability
            && invocation.gearID == MediaGeneratorGearDescriptor.gearID
            && (
                capabilityID == "media_generator.get_task" ||
                capabilityID == "media_generator.list_models"
            )
    }

    private static func fastExternalInvocationOutcome(
        for invocation: WorkbenchExternalInvocation
    ) async -> WorkbenchToolOutcome {
        guard let gearID = invocation.gearID,
              let capabilityID = invocation.capabilityID
        else {
            return .error(
                toolID: "gee.gear.invoke",
                code: "gee.external_invocation.invalid",
                message: "External invocation payload could not be converted into a Gee host tool invocation."
            )
        }
        return await GeeHostToolRouter.invokeExternalCapability(
            gearID: gearID,
            capabilityID: capabilityID,
            args: WorkbenchToolArgumentCodec.encode(invocation.args)
        )
    }

    private func completeExternalInvocation(
        _ completion: WorkbenchExternalInvocationCompletion,
        runtimeClient: any WorkbenchRuntimeClient,
        snapshot: WorkbenchSnapshot
    ) async -> WorkbenchSnapshot? {
        do {
            let nextSnapshot = try await runtimeClient.completeExternalInvocation(
                completion,
                in: snapshot
            )
            await MainActor.run {
                self.snapshot = nextSnapshot
            }
            return nextSnapshot
        } catch {
            await MainActor.run {
                self.lastErrorMessage = error.localizedDescription
            }
            return nil
        }
    }

    func refreshSelectedRuntimeRunInspector(force: Bool = false) {
        guard let runID = selectedRuntimeRunID else {
            selectedRuntimeRunProjection = nil
            selectedRuntimeRunWait = nil
            runtimeRunInspectorErrorMessage = nil
            isLoadingRuntimeRunInspector = false
            return
        }

        if !force,
           selectedRuntimeRunProjection?.runID == runID,
           selectedRuntimeRunWait?.runID == runID {
            return
        }

        isLoadingRuntimeRunInspector = true
        runtimeRunInspectorErrorMessage = nil
        let runtimeClient = self.runtimeClient

        Task { [weak self, runtimeClient, runID] in
            do {
                async let projection = runtimeClient.projectRuntimeRun(runID)
                async let wait = runtimeClient.classifyRuntimeRunWait(runID)
                let result = try await (projection, wait)
                await MainActor.run {
                    guard let self, self.selectedRuntimeRunID == runID else {
                        return
                    }
                    self.selectedRuntimeRunProjection = result.0
                    self.selectedRuntimeRunWait = result.1
                    self.runtimeRunInspectorErrorMessage = nil
                    self.isLoadingRuntimeRunInspector = false
                }
            } catch {
                await MainActor.run {
                    guard let self, self.selectedRuntimeRunID == runID else {
                        return
                    }
                    self.selectedRuntimeRunProjection = nil
                    self.selectedRuntimeRunWait = nil
                    self.runtimeRunInspectorErrorMessage = error.localizedDescription
                    self.isLoadingRuntimeRunInspector = false
                }
            }
        }
    }

    private func resetRuntimeRunInspectorIfNeeded() {
        guard let runID = selectedRuntimeRunID else {
            selectedRuntimeRunProjection = nil
            selectedRuntimeRunWait = nil
            runtimeRunInspectorErrorMessage = nil
            isLoadingRuntimeRunInspector = false
            return
        }
        let projectionMatches = selectedRuntimeRunProjection?.runID == runID
        let waitMatches = selectedRuntimeRunWait?.runID == runID
        if projectionMatches && waitMatches {
            return
        }
        if !projectionMatches {
            selectedRuntimeRunProjection = nil
        }
        if !waitMatches {
            selectedRuntimeRunWait = nil
        }
        runtimeRunInspectorErrorMessage = nil
        isLoadingRuntimeRunInspector = false
    }

    private static func toolInvocation(for invocation: WorkbenchExternalInvocation) -> ToolInvocation? {
        switch invocation.tool {
        case .invokeCapability:
            guard let gearID = invocation.gearID,
                  let capabilityID = invocation.capabilityID
            else {
                return nil
            }
            return ToolInvocation(
                toolID: "gee.gear.invoke",
                arguments: [
                    "gear_id": .string(gearID),
                    "capability_id": .string(capabilityID),
                    "args": .object(invocation.args)
                ]
            )
        case .openSurface:
            guard let surfaceID = invocation.surfaceID ?? invocation.gearID else {
                return nil
            }
            return ToolInvocation(
                toolID: "gee.app.openSurface",
                arguments: [
                    "surface_id": .string(surfaceID)
                ]
            )
        }
    }

    private static func externalInvocationCompletion(
        for invocation: WorkbenchExternalInvocation,
        outcome: WorkbenchToolOutcome
    ) -> WorkbenchExternalInvocationCompletion {
        switch outcome {
        case let .completed(_, payload):
            let payloadStatus = (payload["status"] as? String)?.lowercased()
            let failed = payloadStatus == "failed"
            return WorkbenchExternalInvocationCompletion(
                externalInvocationID: invocation.id,
                status: failed ? .failed : .success,
                resultJSON: hostActionResultJSON(from: payload),
                code: failed ? ((payload["code"] as? String) ?? "gear.external_invocation.failed") : nil,
                message: failed ? ((payload["error"] as? String) ?? "Gear action failed.") : nil
            )
        case let .needsApproval(_, _, prompt):
            return WorkbenchExternalInvocationCompletion(
                externalInvocationID: invocation.id,
                status: .blocked,
                resultJSON: nil,
                code: "gee.external_invocation.approval_required",
                message: "The Gear action needs approval before it can complete: \(prompt)"
            )
        case let .denied(_, reason):
            return WorkbenchExternalInvocationCompletion(
                externalInvocationID: invocation.id,
                status: .blocked,
                resultJSON: nil,
                code: "gee.external_invocation.denied",
                message: reason
            )
        case let .error(_, code, message):
            return WorkbenchExternalInvocationCompletion(
                externalInvocationID: invocation.id,
                status: .failed,
                resultJSON: nil,
                code: code,
                message: message
            )
        }
    }

    private func expireLoadedHostActionIntents(
        _ intents: [WorkbenchHostActionIntent],
        loadedSnapshot: WorkbenchSnapshot
    ) {
        guard !intents.isEmpty else {
            return
        }
        let completions = intents.map { intent in
            WorkbenchHostActionCompletion(
                hostActionID: intent.id,
                toolID: intent.toolID,
                status: "failed",
                summary: nil,
                error: "GeeAgent restarted before this native Gear action could complete. The action was not retried automatically to avoid repeating side effects.",
                resultJSON: nil
            )
        }
        let runtimeClient = self.runtimeClient
        Task { [weak self, runtimeClient, completions, loadedSnapshot] in
            do {
                let nextSnapshot = try await runtimeClient.completeHostActionTurn(
                    completions,
                    in: loadedSnapshot
                )
                var sanitizedSnapshot = nextSnapshot
                sanitizedSnapshot.hostActionIntents = []
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = sanitizedSnapshot
                    self.quickInputLatestResult = sanitizedSnapshot.lastOutcome
                }
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private static func hostActionCompletion(
        for intent: WorkbenchHostActionIntent,
        outcome: WorkbenchToolOutcome
    ) -> WorkbenchHostActionCompletion {
        switch outcome {
        case let .completed(_, payload):
            let payloadStatus = (payload["status"] as? String)?.lowercased()
            let payloadError = payload["error"] as? String
            return WorkbenchHostActionCompletion(
                hostActionID: intent.id,
                toolID: intent.toolID,
                status: payloadStatus == "failed" ? "failed" : "succeeded",
                summary: hostActionSummary(for: intent, payload: payload),
                error: payloadStatus == "failed" ? payloadError : nil,
                resultJSON: hostActionResultJSON(from: payload)
            )
        case let .needsApproval(_, _, prompt):
            return WorkbenchHostActionCompletion(
                hostActionID: intent.id,
                toolID: intent.toolID,
                status: "failed",
                summary: nil,
                error: "The Gear action needs approval before it can complete: \(prompt)",
                resultJSON: nil
            )
        case let .denied(_, reason):
            return WorkbenchHostActionCompletion(
                hostActionID: intent.id,
                toolID: intent.toolID,
                status: "failed",
                summary: nil,
                error: reason,
                resultJSON: nil
            )
        case let .error(_, _, message):
            return WorkbenchHostActionCompletion(
                hostActionID: intent.id,
                toolID: intent.toolID,
                status: "failed",
                summary: nil,
                error: message,
                resultJSON: nil
            )
        }
    }

    private static func hostActionSummary(
        for intent: WorkbenchHostActionIntent,
        payload: [String: Any]
    ) -> String {
        if let gearID = payload["gear_id"] as? String,
           let capabilityID = payload["capability_id"] as? String
        {
            var parts = ["\(gearID) \(capabilityID) completed"]
            if let action = payload["action"] as? String {
                parts.append("action: \(action)")
            }
            if let visibleSummary = payload["visible_summary"] as? String,
               !visibleSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                parts.append("visible media: \(visibleSummary)")
            }
            if let filteredCount = payload["filtered_count"],
               let totalCount = payload["total_count"]
            {
                parts.append("visible count: \(filteredCount) of \(totalCount)")
            }
            if let taskID = payload["task_id"] as? String {
                parts.append("task: \(taskID)")
            }
            if let tweetCount = payload["tweet_count"] {
                parts.append("tweets: \(tweetCount)")
            }
            if let articleCount = payload["article_count"] {
                parts.append("articles: \(articleCount)")
            }
            if let articleLinks = articleLinkSummary(payload["articles"]) {
                parts.append("article links: \(articleLinks)")
            }
            if let files = payload["files"] as? [String] {
                parts.append("files: \(files.count)")
            }
            if let outputDirectory = payload["output_dir"] as? String {
                parts.append("output: \(outputDirectory)")
            }
            if let taskPath = payload["task_path"] as? String {
                parts.append("task path: \(taskPath)")
            }
            if let status = payload["status"] as? String, status == "failed",
               let error = payload["error"] as? String
            {
                parts.append("error: \(error)")
            }
            return parts.joined(separator: "; ")
        }

        if let intentName = payload["intent"] as? String {
            if let moduleID = payload["module_id"] as? String {
                return "\(intent.toolID) completed \(intentName) for \(moduleID)"
            }
            if let section = payload["section"] as? String {
                return "\(intent.toolID) completed \(intentName) for \(section)"
            }
            return "\(intent.toolID) completed \(intentName)"
        }

        return "\(intent.toolID) completed."
    }

    private static func articleLinkSummary(_ value: Any?) -> String? {
        guard let articles = value as? [[String: Any]], !articles.isEmpty else {
            return nil
        }
        let links = articles.prefix(3).compactMap { article -> String? in
            let title = (article["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let url = (article["url"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let title, !title.isEmpty, let url, !url.isEmpty {
                return "\(title) \(url)"
            }
            if let url, !url.isEmpty {
                return url
            }
            if let title, !title.isEmpty {
                return title
            }
            return nil
        }
        guard !links.isEmpty else {
            return nil
        }
        return links.joined(separator: " | ")
    }

    private static func hostActionResultJSON(from payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              var text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let maxLength = 30_000
        if text.count > maxLength {
            text = String(text.prefix(maxLength)) + "...[truncated]"
        }
        return text
    }

    private func applyNavigationIntent(_ intent: WorkbenchToolNavigationIntent) {
        switch intent {
        case let .section(section):
            selectedSection = section
        case let .module(id):
            lastErrorMessage = nil
            if let app = installedApps.first(where: { $0.id == id }) {
                guard GearHost.isEnabled(gearID: id) else {
                    selectedSection = .apps
                    lastErrorMessage = "`\(app.name)` is disabled. Enable it from Gears before opening it."
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

    /// Presents a full-canvas module by id (e.g. Gears → Modules → Open, or chat tool `navigate.openModule`).
    func openStandaloneModule(id: String) {
        guard GearHost.isEnabled(gearID: id) else {
            return
        }

        if let windowID = GearHost.dedicatedWindowID(gearID: id) {
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

    /// Submits the current `quickInputDraft` (or an explicit override) as a
    /// fresh quick conversation. Quick Input intentionally avoids reusing the
    /// currently selected chat so lightweight prompts stay easy to separate.
    func submitQuickInput(_ prompt: String? = nil) {
        let raw = prompt ?? quickInputDraft
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              canUseQuickInput,
              !isSubmittingQuickInput
        else { return }

        isSubmittingQuickInput = true
        isSendingMessage = true
        selectedSection = .chat
        lastErrorMessage = nil
        chatErrorMessage = nil
        resetCompletedHostActionsForFreshRuntimeTurn()
        let requestID = beginActiveChatRequest()
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot
        startLiveSnapshotPolling()

        Task { [weak self, runtimeClient, currentSnapshot, trimmed, requestID] in
            do {
                let shouldStart = await MainActor.run {
                    guard let self else { return false }
                    if self.isCancelledChatRequest(requestID) {
                        self.forgetCancelledChatRequest(requestID)
                        return false
                    }
                    return true
                }
                guard shouldStart else { return }

                let nextSnapshot = try await runtimeClient.submitQuickPrompt(
                    trimmed,
                    in: currentSnapshot
                )
                await MainActor.run {
                    guard let self else { return }
                    if self.consumeCancelledChatRequest(requestID) {
                        return
                    }
                    self.finishActiveChatRequest(requestID)
                    self.isSubmittingQuickInput = false
                    self.isSendingMessage = false
                    self.chatErrorMessage = nil
                    self.stopLiveSnapshotPolling()
                    self.snapshot = nextSnapshot
                    self.applyHostActionIntents(nextSnapshot.hostActionIntents)
                    if let routedConversationID = nextSnapshot.conversations.first(where: \.isActive)?.id {
                        self.selectedConversationID = routedConversationID
                    }
                    self.quickInputLatestResult = nextSnapshot.lastOutcome
                    self.quickInputDraft = ""
                }
            } catch {
                let recoverySnapshot = runtimeClient.loadSnapshot()
                await MainActor.run {
                    guard let self else { return }
                    if self.consumeCancelledChatRequest(requestID) {
                        return
                    }
                    self.finishActiveChatRequest(requestID)
                    self.chatErrorMessage = error.localizedDescription
                    self.lastErrorMessage = error.localizedDescription
                    self.snapshot = recoverySnapshot
                    self.isSubmittingQuickInput = false
                    self.isSendingMessage = false
                    self.stopLiveSnapshotPolling()
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

    func submitTelegramChannelMessage(_ payload: TelegramChannelMessagePayload) async throws -> String? {
        resetCompletedHostActionsForFreshRuntimeTurn()
        let currentSnapshot = snapshot
        var nextSnapshot = try await runtimeClient.submitChannelMessage(payload, in: currentSnapshot)
        if !nextSnapshot.hostActionIntents.isEmpty {
            nextSnapshot = try await completeHostActionIntents(
                nextSnapshot.hostActionIntents,
                in: nextSnapshot
            )
        }
        snapshot = nextSnapshot
        return telegramReplyText(for: payload, in: nextSnapshot)
    }

    private func telegramReplyText(
        for payload: TelegramChannelMessagePayload,
        in snapshot: WorkbenchSnapshot
    ) -> String? {
        let currentMessageIsResetCommand = isTelegramNewConversationCommand(payload.message.text)
        let messages = snapshot.conversations
            .first(where: \.isActive)?
            .visibleMessages ?? []
        let userMessageIndex = messages.lastIndex { message in
            message.role == .user &&
                message.content == payload.message.text
        }
        if let userMessageIndex {
            let reply = messages[messages.index(after: userMessageIndex)...]
                .last { message in
                    message.role == .assistant &&
                        message.kind == .chat &&
                        !message.isSeedPlaceholder &&
                        (currentMessageIsResetCommand || !isTelegramNewConversationReply(message.content)) &&
                        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }?
                .content
            if let reply {
                return reply
            }
        }
        let quickReply = snapshot.quickReply.trimmingCharacters(in: .whitespacesAndNewlines)
        return quickReply.isEmpty ? nil : quickReply
    }

    private func isTelegramNewConversationCommand(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(
                of: #"^/new(?:@[A-Za-z0-9_]{1,64})?(?:\s|$)"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
    }

    private func isTelegramNewConversationReply(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) ==
            "Started a new Telegram conversation. Previous Telegram context has been cleared."
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

    func sendMessage(
        _ message: String,
        attachments: [WorkspaceInputAttachment] = [],
        openSection: Bool = true
    ) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMessage = trimmedMessage.isEmpty && !attachments.isEmpty
            ? "Please review the attached item(s)."
            : trimmedMessage
        guard !resolvedMessage.isEmpty, canSendMessages else {
            return
        }

        if let conversationID = selectedConversation?.id {
            sendMessage(
                resolvedMessage,
                attachments: attachments,
                in: snapshot,
                conversationID: conversationID,
                openSection: openSection
            )
            return
        }

        guard canCreateConversation, !isCreatingConversation else {
            return
        }

        isCreatingConversation = true
        isSendingMessage = true
        lastErrorMessage = nil
        chatErrorMessage = nil
        resetCompletedHostActionsForFreshRuntimeTurn()
        let requestID = beginActiveChatRequest()
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot
        let allowAutoRouting = autoConversationRoutingEnabled
        startLiveSnapshotPolling()

        Task { [weak self, runtimeClient, currentSnapshot, allowAutoRouting, attachments, requestID] in
            do {
                let createdSnapshot = try await runtimeClient.createConversation(in: currentSnapshot)
                guard let conversationID = createdSnapshot.conversations.first(where: \.isActive)?.id ?? createdSnapshot.conversations.first?.id else {
                    throw NSError(domain: "GeeAgentMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create a conversation."])
                }
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = createdSnapshot
                    self.selectedConversationID = conversationID
                    self.beginPendingChatTurn(
                        message: resolvedMessage,
                        attachments: attachments,
                        conversationID: conversationID
                    )
                    if openSection {
                        self.selectedSection = .chat
                    }
                    self.isCreatingConversation = false
                }
                let shouldSend = await MainActor.run {
                    guard let self else { return false }
                    if self.isCancelledChatRequest(requestID) {
                        self.clearPendingChatTurn(conversationID: conversationID)
                        self.forgetCancelledChatRequest(requestID)
                        return false
                    }
                    return true
                }
                guard shouldSend else { return }

                let nextSnapshot = try await runtimeClient.sendMessage(
                    resolvedMessage,
                    attachments: attachments,
                    in: createdSnapshot,
                    conversationID: conversationID,
                    allowAutoRouting: allowAutoRouting
                )
                await MainActor.run {
                    guard let self else { return }
                    if self.consumeCancelledChatRequest(requestID) {
                        self.clearPendingChatTurn(conversationID: conversationID)
                        return
                    }
                    self.finishActiveChatRequest(requestID)
                    self.clearPendingChatTurn(conversationID: conversationID)
                    self.isCreatingConversation = false
                    self.isSendingMessage = false
                    self.chatErrorMessage = nil
                    self.stopLiveSnapshotPolling()
                    self.snapshot = nextSnapshot
                    self.applyHostActionIntents(nextSnapshot.hostActionIntents)
                    if openSection {
                        self.selectedSection = .chat
                    }
                }
            } catch {
                let recoverySnapshot = runtimeClient.loadSnapshot()
                await MainActor.run {
                    guard let self else { return }
                    if self.consumeCancelledChatRequest(requestID) {
                        self.clearPendingChatTurn()
                        return
                    }
                    self.finishActiveChatRequest(requestID)
                    self.clearPendingChatTurn()
                    self.chatErrorMessage = error.localizedDescription
                    self.lastErrorMessage = error.localizedDescription
                    self.snapshot = recoverySnapshot
                    self.isCreatingConversation = false
                    self.isSendingMessage = false
                    self.stopLiveSnapshotPolling()
                }
            }
        }
    }

    func stopActiveChatRun() {
        guard isSendingMessage, !isStoppingMessage else {
            return
        }

        isStoppingMessage = true
        chatErrorMessage = nil
        lastErrorMessage = nil
        let requestID = activeChatRequestID
        if let requestID {
            cancelledChatRequestIDs.insert(requestID)
        }
        let runtimeClient = self.runtimeClient
        let currentSnapshot = snapshot
        stopLiveSnapshotPolling()

        Task { [weak self, runtimeClient, currentSnapshot] in
            do {
                let nextSnapshot = try await runtimeClient.cancelActiveRun(in: currentSnapshot)
                await MainActor.run {
                    guard let self else { return }
                    self.clearPendingChatTurn()
                    self.finishStoppedChatRequest(requestID)
                    self.snapshot = nextSnapshot
                    self.isSendingMessage = false
                    self.isSubmittingQuickInput = false
                    self.isCreatingConversation = false
                    self.isStoppingMessage = false
                    self.quickInputLatestResult = nextSnapshot.lastOutcome
                    self.applyHostActionIntents(nextSnapshot.hostActionIntents)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.clearPendingChatTurn()
                    self.finishStoppedChatRequest(requestID)
                    self.isSendingMessage = false
                    self.isSubmittingQuickInput = false
                    self.isCreatingConversation = false
                    self.isStoppingMessage = false
                    self.chatErrorMessage = "GeeAgent could not stop the run cleanly. You can retry from a new message."
                    self.lastErrorMessage = error.localizedDescription
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
                let recoverySnapshot = runtimeClient.loadSnapshot()
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.snapshot = recoverySnapshot
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
                    self.conversationTitleOverrides.removeValue(forKey: conversationID)
                    self.clearPendingChatTurn(conversationID: conversationID)
                    self.snapshot = nextSnapshot
                    self.selectedConversationID = nextSnapshot.conversations.first(where: \.isActive)?.id
                        ?? nextSnapshot.conversations.first?.id
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
        chatErrorMessage = nil
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
    /// The loaded profile supplies the available visual resources. Local
    /// `profileAppearancePreferences` choose which available resource is shown
    /// and still carry Live2D viewport and motion state.
    var effectiveActiveAppearance: AgentProfileAppearanceRecord {
        guard let profile = activeAgentProfile else { return .abstract }
        guard let pref = profileAppearancePreferences[profile.id] else {
            return profile.appearance
        }
        return resolvedAppearance(for: pref.kind, profile: profile, preference: pref)
    }

    var effectiveGlobalBackground: AgentProfileGlobalBackgroundRecord {
        activeAgentProfile?.globalBackground ?? .none
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

    var availableHomeAppearanceKinds: [AgentAppearanceKind] {
        guard let profile = activeAgentProfile else { return [.abstract] }
        var kinds: [AgentAppearanceKind] = []
        if profile.visualOptions.path(for: .live2D) != nil
            || profile.appearance.kind == .live2D
            || activeProfileAppearancePreference.live2DBundlePath?.nilIfBlank != nil
        {
            kinds.append(.live2D)
        }
        if profile.visualOptions.path(for: .video) != nil {
            kinds.append(.video)
        }
        if profile.visualOptions.path(for: .staticImage) != nil {
            kinds.append(.staticImage)
        }
        kinds.append(.abstract)
        return kinds
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
        switch kind {
        case .staticImage:
            pref.staticImagePath = pref.staticImagePath ?? profile.visualOptions.imageAssetPath
        case .video:
            pref.videoPath = pref.videoPath ?? profile.visualOptions.videoAssetPath
        case .live2D:
            pref.live2DBundlePath = pref.live2DBundlePath ?? profile.visualOptions.live2DBundlePath
        case .abstract:
            break
        }
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
        schedulePoseRestore(to: activeLive2DPosePath, after: motion.durationSeconds ?? (motion.isLoop ? 2.4 : 1.6))
    }

    func playLive2DMotion(_ motion: Live2DMotionRecord) {
        guard case let .live2D(bundlePath) = effectiveActiveAppearance, !bundlePath.isEmpty else {
            return
        }

        live2DMotionPlaybackRequest = Live2DMotionPlaybackRequest(bundlePath: bundlePath, motion: motion)
    }

    private func stopLive2DMotion() {
        guard case let .live2D(bundlePath) = effectiveActiveAppearance, !bundlePath.isEmpty else {
            return
        }

        live2DMotionPlaybackRequest = .stop(bundlePath: bundlePath)
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
        availableHomeAppearanceKinds.contains(kind)
    }

    private func resolvedAppearance(
        for kind: AgentAppearanceKind,
        profile: AgentProfileRecord,
        preference: ProfileAppearancePreference
    ) -> AgentProfileAppearanceRecord {
        switch kind {
        case .live2D:
            if let path = preference.live2DBundlePath?.nilIfBlank ?? profile.visualOptions.live2DBundlePath?.nilIfBlank {
                return .live2D(bundlePath: path)
            }
            if case .live2D = profile.appearance {
                return profile.appearance
            }
        case .video:
            if let path = profile.visualOptions.videoAssetPath?.nilIfBlank {
                return .video(assetPath: path)
            }
            if case .video = profile.appearance {
                return profile.appearance
            }
        case .staticImage:
            if let path = profile.visualOptions.imageAssetPath?.nilIfBlank {
                return .staticImage(assetPath: path)
            }
            if case .staticImage = profile.appearance {
                return profile.appearance
            }
        case .abstract:
            return .abstract
        }
        return profile.appearance
    }

    private func reconcileReloadedAppearancePreference(
        profileID: AgentProfileRecord.ID,
        previousProfile: AgentProfileRecord?
    ) {
        guard var preference = profileAppearancePreferences[profileID],
              let nextProfile = availableAgentProfiles.first(where: { $0.id == profileID })
        else {
            return
        }

        var didChange = false
        didChange = reconcileReloadedAppearancePath(
            &preference.live2DBundlePath,
            for: .live2D,
            activeKind: preference.kind,
            previousProfile: previousProfile,
            nextProfile: nextProfile
        ) || didChange
        didChange = reconcileReloadedAppearancePath(
            &preference.videoPath,
            for: .video,
            activeKind: preference.kind,
            previousProfile: previousProfile,
            nextProfile: nextProfile
        ) || didChange
        didChange = reconcileReloadedAppearancePath(
            &preference.staticImagePath,
            for: .staticImage,
            activeKind: preference.kind,
            previousProfile: previousProfile,
            nextProfile: nextProfile
        ) || didChange

        if didChange {
            profileAppearancePreferences[profileID] = preference
        }
    }

    private func reconcileReloadedAppearancePath(
        _ path: inout String?,
        for kind: AgentAppearanceKind,
        activeKind: AgentAppearanceKind,
        previousProfile: AgentProfileRecord?,
        nextProfile: AgentProfileRecord
    ) -> Bool {
        let currentPath = path?.nilIfBlank
        let previousDefault = previousProfile.flatMap { defaultAppearancePath(for: kind, in: $0) }
        let nextDefault = defaultAppearancePath(for: kind, in: nextProfile)

        let shouldRefresh = currentPath == nil && activeKind == kind
            || currentPath.map { pathsEqual($0, previousDefault) } == true
            || currentPath.map { !FileManager.default.fileExists(atPath: $0) } == true

        guard shouldRefresh else { return false }
        path = nextDefault
        return currentPath != nextDefault
    }

    private func defaultAppearancePath(
        for kind: AgentAppearanceKind,
        in profile: AgentProfileRecord
    ) -> String? {
        if let optionPath = profile.visualOptions.path(for: kind) {
            return optionPath
        }

        switch (kind, profile.appearance) {
        case (.live2D, .live2D(let path)),
             (.video, .video(let path)),
             (.staticImage, .staticImage(let path)):
            return path.nilIfBlank
        case (.abstract, _):
            return nil
        default:
            return nil
        }
    }

    private func pathsEqual(_ left: String, _ right: String?) -> Bool {
        guard let right else { return false }
        return URL(fileURLWithPath: left).standardizedFileURL.path
            == URL(fileURLWithPath: right).standardizedFileURL.path
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

    private func schedulePoseRestore(to relativePath: String?, after seconds: Double) {
        live2DPoseRestoreTask?.cancel()
        live2DPoseRestoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0.2, seconds)))
            guard let self, !Task.isCancelled else { return }
            guard let relativePath else {
                self.stopLive2DMotion()
                return
            }
            guard let pose = self.availableLive2DPoses.first(where: { $0.relativePath == relativePath }) else {
                self.stopLive2DMotion()
                return
            }
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
        attachments: [WorkspaceInputAttachment],
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        openSection: Bool
    ) {
        isSendingMessage = true
        lastErrorMessage = nil
        chatErrorMessage = nil
        let requestID = beginActiveChatRequest()
        beginPendingChatTurn(message: message, attachments: attachments, conversationID: conversationID)
        resetCompletedHostActionsForFreshRuntimeTurn()
        if openSection {
            selectedSection = .chat
        }
        let runtimeClient = self.runtimeClient
        let allowAutoRouting = autoConversationRoutingEnabled
        startLiveSnapshotPolling()

        Task { [weak self, runtimeClient, snapshot, allowAutoRouting, attachments, requestID] in
            do {
                let shouldStart = await MainActor.run {
                    guard let self else { return false }
                    if self.isCancelledChatRequest(requestID) {
                        self.clearPendingChatTurn(conversationID: conversationID)
                        self.forgetCancelledChatRequest(requestID)
                        return false
                    }
                    return true
                }
                guard shouldStart else { return }

                let nextSnapshot = try await runtimeClient.sendMessage(
                    message,
                    attachments: attachments,
                    in: snapshot,
                    conversationID: conversationID,
                    allowAutoRouting: allowAutoRouting
                )
                await MainActor.run {
                    guard let self else { return }
                    if self.consumeCancelledChatRequest(requestID) {
                        self.clearPendingChatTurn(conversationID: conversationID)
                        return
                    }
                    self.finishActiveChatRequest(requestID)
                    self.clearPendingChatTurn(conversationID: conversationID)
                    self.isSendingMessage = false
                    self.chatErrorMessage = nil
                    self.stopLiveSnapshotPolling()
                    self.snapshot = nextSnapshot
                    self.applyHostActionIntents(nextSnapshot.hostActionIntents)
                    if openSection {
                        self.selectedSection = .chat
                    }
                }
            } catch {
                let recoverySnapshot = runtimeClient.loadSnapshot()
                await MainActor.run {
                    guard let self else { return }
                    if self.consumeCancelledChatRequest(requestID) {
                        self.clearPendingChatTurn(conversationID: conversationID)
                        return
                    }
                    self.finishActiveChatRequest(requestID)
                    self.clearPendingChatTurn(conversationID: conversationID)
                    self.chatErrorMessage = error.localizedDescription
                    self.lastErrorMessage = error.localizedDescription
                    self.snapshot = recoverySnapshot
                    self.isSendingMessage = false
                    self.stopLiveSnapshotPolling()
                }
            }
        }
    }

    private func startLiveSnapshotPolling() {
        liveSnapshotPollingTask?.cancel()
        let runtimeClient = self.runtimeClient
        liveSnapshotPollingTask = Task { [weak self, runtimeClient] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled {
                    return
                }
                let latestSnapshot = await Task.detached(priority: .utility) {
                    runtimeClient.loadLiveSnapshot()
                }.value
                await MainActor.run {
                    guard let self,
                          self.isSendingMessage || self.isSubmittingQuickInput || self.isCreatingConversation
                    else { return }
                    self.snapshot = latestSnapshot
                    self.applyHostActionIntents(latestSnapshot.hostActionIntents)
                }
            }
        }
    }

    private func stopLiveSnapshotPolling() {
        liveSnapshotPollingTask?.cancel()
        liveSnapshotPollingTask = nil
    }

    private func startExternalInvocationPolling() {
        externalInvocationPollingTask?.cancel()
        let runtimeClient = self.runtimeClient
        externalInvocationPollingTask = Task { [weak self, runtimeClient] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            while !Task.isCancelled {
                if Task.isCancelled {
                    return
                }
                let currentSnapshot = await MainActor.run { [weak self] in
                    self?.snapshot
                }
                guard let currentSnapshot else {
                    return
                }
                let latestSnapshot = await Task.detached(priority: .utility) {
                    runtimeClient.loadExternalInvocationSnapshot(from: currentSnapshot)
                }.value
                let hasPendingExternalInvocation = latestSnapshot.externalInvocations.contains { $0.status == .pending }
                let externalInvocationsChanged = latestSnapshot.externalInvocations != currentSnapshot.externalInvocations
                if externalInvocationsChanged || hasPendingExternalInvocation {
                    await MainActor.run {
                        guard let self else { return }
                        self.snapshot = latestSnapshot
                        if hasPendingExternalInvocation {
                            self.applyExternalInvocations(latestSnapshot.externalInvocations)
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: hasPendingExternalInvocation ? 1_000_000_000 : 5_000_000_000)
            }
        }
    }

    private func beginActiveChatRequest() -> String {
        let requestID = UUID().uuidString
        activeChatRequestID = requestID
        return requestID
    }

    private func finishActiveChatRequest(_ requestID: String) {
        if activeChatRequestID == requestID {
            activeChatRequestID = nil
        }
        cancelledChatRequestIDs.remove(requestID)
    }

    private func finishStoppedChatRequest(_ requestID: String?) {
        if let requestID {
            if activeChatRequestID == requestID {
                activeChatRequestID = nil
            }
        } else {
            activeChatRequestID = nil
        }
    }

    private func isCancelledChatRequest(_ requestID: String) -> Bool {
        cancelledChatRequestIDs.contains(requestID) ||
            (isStoppingMessage && activeChatRequestID == requestID)
    }

    private func forgetCancelledChatRequest(_ requestID: String) {
        cancelledChatRequestIDs.remove(requestID)
        if activeChatRequestID == requestID {
            activeChatRequestID = nil
        }
    }

    private func consumeCancelledChatRequest(_ requestID: String) -> Bool {
        if cancelledChatRequestIDs.remove(requestID) != nil {
            return true
        }
        return isStoppingMessage && activeChatRequestID == requestID
    }

    @discardableResult
    private func beginPendingChatTurn(
        message: String,
        attachments: [WorkspaceInputAttachment],
        conversationID: ConversationThread.ID
    ) -> String {
        let previousMessageIDs = Set(
            conversations
                .first(where: { $0.id == conversationID })?
                .visibleMessages
                .map(\.id) ?? []
        )
        let pendingID = UUID().uuidString
        pendingChatTurn = PendingChatTurn(
            id: pendingID,
            conversationID: conversationID,
            content: message,
            attachments: attachments,
            createdAt: Date(),
            previousMessageIDs: previousMessageIDs
        )
        selectedConversationID = conversationID
        return pendingID
    }

    private func clearPendingChatTurn(conversationID: ConversationThread.ID? = nil) {
        guard let pendingChatTurn else {
            return
        }
        if let conversationID, pendingChatTurn.conversationID != conversationID {
            return
        }
        self.pendingChatTurn = nil
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
        let preferredID = userFacingChatConversations.first(where: \.isActive)?.id ?? userFacingChatConversations.first?.id
        let normalizedID = normalizedID(
            selectedConversationID,
            validIDs: userFacingChatConversations.map(\.id),
            preferredID: preferredID
        )
        if selectedConversationID != normalizedID {
            selectedConversationID = normalizedID
        }
    }

    private func isTelegramBridgeConversation(_ conversation: ConversationThread) -> Bool {
        conversation.tags.contains("telegram.bridge")
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
            if let app = installedApps.first(where: { $0.id == id }),
               isSelectableInstalledApp(app) {
                normalizedSelection = .app(id)
            } else {
                normalizedSelection = firstSelectableExtensionSelection()
            }
        case let .some(.skin(id)):
            if agentSkins.contains(where: { $0.id == id }) {
                normalizedSelection = .skin(id)
            } else {
                normalizedSelection = agentSkins.first.map { .skin($0.id) }
                    ?? firstSelectableInstalledApp().map { .app($0.id) }
            }
        case .none:
            normalizedSelection = firstSelectableExtensionSelection()
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
        globalBackground: .none,
        visualOptions: .empty,
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
