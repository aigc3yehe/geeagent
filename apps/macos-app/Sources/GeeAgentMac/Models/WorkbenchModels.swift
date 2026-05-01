import Foundation

enum WorkbenchSection: String, CaseIterable, Identifiable {
    case home
    case chat
    case tasks
    case automations
    case apps
    case agents
    case logs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .chat: "Chat"
        case .tasks: "Tasks"
        case .automations: "Automations"
        case .apps: "Gears"
        case .agents: "Agents"
        case .logs: "Logs"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .chat: "bubble.left"
        case .tasks: "checklist"
        case .automations: "bolt"
        case .apps: "square.grid.2x2"
        case .agents: "person.2"
        case .logs: "doc.text.magnifyingglass"
        case .settings: "gearshape"
        }
    }
}

struct ChatRoutingSettings: Codable, Hashable {
    var defaultRouteClass: String
    var allowUserOverrides: Bool
    var providerChoices: [String]
    var routeClasses: [RouteClassSetting]
    var profiles: [ProfileRouteSetting]

    var selectedRouteClass: RouteClassSetting? {
        routeClasses.first { $0.name == defaultRouteClass } ?? routeClasses.first
    }

    func updatingDefaultRoute(provider: String, model: String) -> ChatRoutingSettings {
        var next = self
        let trimmedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProvider.isEmpty, !trimmedModel.isEmpty else {
            return next
        }

        if let index = next.routeClasses.firstIndex(where: { $0.name == next.defaultRouteClass }) ?? next.routeClasses.indices.first {
            next.defaultRouteClass = next.routeClasses[index].name
            next.routeClasses[index].provider = trimmedProvider
            next.routeClasses[index].model = trimmedModel
        } else {
            let route = RouteClassSetting(
                name: "default",
                provider: trimmedProvider,
                model: trimmedModel,
                reasoningEffort: "medium"
            )
            next.defaultRouteClass = route.name
            next.routeClasses = [route]
        }

        if !next.providerChoices.contains(trimmedProvider) {
            next.providerChoices.append(trimmedProvider)
            next.providerChoices.sort()
        }

        return next
    }
}

struct RouteClassSetting: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var provider: String
    var model: String
    var reasoningEffort: String
}

struct ProfileRouteSetting: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var defaultRouteClass: String
}

enum HomeSurfaceMode: Hashable {
    case companion
    case chatFocus
    case taskFocus

    var isFocused: Bool {
        switch self {
        case .companion:
            false
        case .chatFocus, .taskFocus:
            true
        }
    }
}

enum HomeHeroVisualMode: String, CaseIterable, Hashable, Identifiable {
    case banner
    case abstract

    var id: String { rawValue }

    var title: String {
        switch self {
        case .banner: "Banner"
        case .abstract: "Abstract"
        }
    }
}

enum AgentAppearanceKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case staticImage = "static_image"
    case video
    case live2D = "live2d"
    case abstract

    var id: String { rawValue }

    var title: String {
        switch self {
        case .staticImage: "Image"
        case .video: "Video"
        case .live2D: "Live2D"
        case .abstract: "Abstract"
        }
    }

    var systemImage: String {
        switch self {
        case .staticImage: "photo"
        case .video: "video"
        case .live2D: "person.crop.square"
        case .abstract: "mountain.2"
        }
    }
}

extension AgentProfileAppearanceRecord {
    var kind: AgentAppearanceKind {
        switch self {
        case .staticImage: .staticImage
        case .video: .video
        case .live2D: .live2D
        case .abstract: .abstract
        }
    }
}

enum AgentProfileGlobalBackgroundRecord: Hashable {
    case video(assetPath: String)
    case staticImage(assetPath: String)
    case none

    var title: String {
        switch self {
        case .video: "Global Video"
        case .staticImage: "Global Image"
        case .none: "None"
        }
    }

    var assetPath: String? {
        switch self {
        case let .video(assetPath), let .staticImage(assetPath):
            assetPath
        case .none:
            nil
        }
    }
}

struct AgentProfileVisualOptionsRecord: Hashable {
    var live2DBundlePath: String?
    var videoAssetPath: String?
    var imageAssetPath: String?

    static let empty = AgentProfileVisualOptionsRecord(
        live2DBundlePath: nil,
        videoAssetPath: nil,
        imageAssetPath: nil
    )

    func path(for kind: AgentAppearanceKind) -> String? {
        switch kind {
        case .live2D:
            live2DBundlePath?.nilIfBlank
        case .video:
            videoAssetPath?.nilIfBlank
        case .staticImage:
            imageAssetPath?.nilIfBlank
        case .abstract:
            nil
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ProfileAppearancePreference: Codable, Hashable {
    var kind: AgentAppearanceKind
    var staticImagePath: String?
    var videoPath: String?
    var live2DBundlePath: String?
    var live2DIdlePosePath: String?
    var live2DExpressionPath: String?
    var live2DOffsetX: Double?
    var live2DOffsetY: Double?
    var live2DScale: Double?

    static let abstractDefault = ProfileAppearancePreference(
        kind: .abstract,
        staticImagePath: nil,
        videoPath: nil,
        live2DBundlePath: nil,
        live2DIdlePosePath: nil,
        live2DExpressionPath: nil,
        live2DOffsetX: nil,
        live2DOffsetY: nil,
        live2DScale: nil
    )

    static func from(appearance: AgentProfileAppearanceRecord) -> ProfileAppearancePreference {
        switch appearance {
        case .staticImage(let path):
            return ProfileAppearancePreference(kind: .staticImage, staticImagePath: path, videoPath: nil, live2DBundlePath: nil, live2DIdlePosePath: nil, live2DExpressionPath: nil, live2DOffsetX: nil, live2DOffsetY: nil, live2DScale: nil)
        case .video(let path):
            return ProfileAppearancePreference(kind: .video, staticImagePath: nil, videoPath: path, live2DBundlePath: nil, live2DIdlePosePath: nil, live2DExpressionPath: nil, live2DOffsetX: nil, live2DOffsetY: nil, live2DScale: nil)
        case .live2D(let path):
            return ProfileAppearancePreference(kind: .live2D, staticImagePath: nil, videoPath: nil, live2DBundlePath: path, live2DIdlePosePath: nil, live2DExpressionPath: nil, live2DOffsetX: nil, live2DOffsetY: nil, live2DScale: nil)
        case .abstract:
            return .abstractDefault
        }
    }

    /// Resolve the preference into a concrete appearance record. Falls back to the provided
    /// baseline when the chosen kind has no asset path remembered for this persona yet.
    func resolvedAppearance(fallback: AgentProfileAppearanceRecord) -> AgentProfileAppearanceRecord {
        switch kind {
        case .staticImage:
            if let path = staticImagePath, !path.isEmpty { return .staticImage(assetPath: path) }
            if case .staticImage = fallback { return fallback }
            return .staticImage(assetPath: "")
        case .video:
            if let path = videoPath, !path.isEmpty { return .video(assetPath: path) }
            if case .video = fallback { return fallback }
            return .video(assetPath: "")
        case .live2D:
            if let path = live2DBundlePath, !path.isEmpty { return .live2D(bundlePath: path) }
            if case .live2D = fallback { return fallback }
            return .abstract
        case .abstract:
            return .abstract
        }
    }
}

enum HomeVisualEffectMode: String, CaseIterable, Hashable, Identifiable {
    case rain
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rain: "Rain"
        case .none: "No Effect"
        }
    }
}

struct WorkbenchSnapshot {
    var homeSummary: WorkbenchHomeSummary
    var homeItems: [WorkbenchHomeItem]
    var conversations: [ConversationThread]
    var tasks: [WorkbenchTaskRecord]
    var automations: [AutomationRecord]
    var installedApps: [InstalledAppRecord]
    var agentSkins: [AgentSkinRecord]
    var availableAgentProfiles: [AgentProfileRecord] = []
    var activeAgentProfileID: AgentProfileRecord.ID? = nil
    var terminalPermissionRules: [TerminalPermissionRuleRecord] = []
    var securityPreferences: WorkbenchSecurityPreferences = .disabled
    var skillSources: SkillSourcesRecord = .empty
    var settings: [SettingsPaneSummary]
    var preferredSection: WorkbenchSection = .home
    var runtimeStatus: WorkbenchRuntimeStatus = WorkbenchRuntimeStatus(
        state: .live,
        detail: "GeeAgent is ready.",
        providerName: nil
    )
    var interactionCapabilities: WorkbenchInteractionCapabilities = WorkbenchInteractionCapabilities(
        canSendMessages: true,
        canMutateRuntime: true,
        readOnlyReason: nil
    )
    /// Placeholder shown inside the menu-bar quick-input box when the user
    /// has not yet typed anything. Plumbed through from the runtime snapshot.
    var quickInputHint: String = "Ask GeeAgent to review a draft, check your queue, or run a task."
    /// One-liner the menu-bar panel renders as the idle "ready for the next
    /// request" detail.
    var quickReply: String = "Ready for the next request."
    var contextBudget: ContextBudgetRecord = .empty
    var lastOutcome: WorkbenchRequestOutcome? = nil
    var hostActionIntents: [WorkbenchHostActionIntent] = []
    var externalInvocations: [WorkbenchExternalInvocation] = []
}

struct WorkbenchHostActionIntent: Hashable, Identifiable {
    var id: String
    var toolID: String
    var arguments: [String: WorkbenchToolArgumentValue]
}

enum WorkbenchExternalInvocationTool: String, Hashable, Sendable {
    case invokeCapability = "gee_invoke_capability"
    case openSurface = "gee_open_surface"
}

enum WorkbenchExternalInvocationStatus: String, Hashable, Sendable {
    case pending
    case running
    case success
    case partial
    case blocked
    case failed
    case degraded

    var isTerminal: Bool {
        switch self {
        case .success, .partial, .blocked, .failed, .degraded:
            true
        case .pending, .running:
            false
        }
    }
}

struct WorkbenchExternalInvocation: Hashable, Identifiable, Sendable {
    var id: String
    var tool: WorkbenchExternalInvocationTool
    var status: WorkbenchExternalInvocationStatus
    var gearID: String?
    var capabilityID: String?
    var surfaceID: String?
    var args: [String: WorkbenchToolArgumentValue]
}

struct WorkbenchExternalInvocationCompletion: Hashable, Sendable {
    var externalInvocationID: String
    var status: WorkbenchExternalInvocationStatus
    var resultJSON: String?
    var code: String?
    var message: String?
}

struct WorkbenchSecurityPreferences: Hashable {
    var highestAuthorizationEnabled: Bool = false

    static let disabled = WorkbenchSecurityPreferences()
}

struct ContextBudgetRecord: Hashable {
    enum SummaryState: String, Hashable {
        case idle
        case watching
        case scheduled
        case projecting
        case summarizing
        case summarized
        case failed
        case disabled

        var title: String {
            switch self {
            case .idle: "Idle"
            case .watching: "Watching"
            case .scheduled: "Summary soon"
            case .projecting: "Projecting"
            case .summarizing: "Summarizing"
            case .summarized: "Summarized"
            case .failed: "Summary failed"
            case .disabled: "Disabled"
            }
        }
    }

    var maxTokens: Int
    var usedTokens: Int
    var reservedOutputTokens: Int
    var usageRatio: Double
    var estimateSource: String
    var summaryState: SummaryState
    var lastSummarizedAt: String?
    var nextSummaryAtRatio: Double
    var compactedMessagesCount: Int
    var projectionMode: String
    var rawHistoryTokens: Int
    var projectedHistoryTokens: Int
    var recentTokens: Int
    var summaryTokens: Int
    var latestRequestTokens: Int

    static let empty = ContextBudgetRecord(
        maxTokens: 256_000,
        usedTokens: 0,
        reservedOutputTokens: 8_192,
        usageRatio: 0,
        estimateSource: "estimated",
        summaryState: .idle,
        lastSummarizedAt: nil,
        nextSummaryAtRatio: 0.95,
        compactedMessagesCount: 0,
        projectionMode: "latest_only",
        rawHistoryTokens: 0,
        projectedHistoryTokens: 0,
        recentTokens: 0,
        summaryTokens: 0,
        latestRequestTokens: 0
    )

    var percentageLabel: String {
        "\(Int((usageRatio * 100).rounded()))%"
    }

    var tokenLabel: String {
        "\(Self.formatTokens(usedTokens)) / \(Self.formatTokens(maxTokens))"
    }

    private static func formatTokens(_ value: Int) -> String {
        if value >= 1_000 {
            return "\(value / 1_000)k"
        }
        return "\(value)"
    }
}

struct TerminalPermissionRuleRecord: Identifiable, Hashable {
    enum Decision: String, Hashable {
        case allow
        case deny

        var title: String {
            switch self {
            case .allow: "Always allow"
            case .deny: "Always deny"
            }
        }
    }

    var id: String
    var decision: Decision
    var kind: String
    var label: String
    var command: String?
    var cwd: String?
    var updatedAt: String
}

/// Menu-bar state ring: the single source of truth for the menu-bar panel's
/// pill and primary CTA.
enum WorkbenchMenuBarState: String, Hashable {
    case idle
    case working
    case waitingReview
    case waitingInput
    case degraded

    /// Lowercased, space-separated label for the state pill.
    var pillLabel: String {
        switch self {
        case .idle: return "idle"
        case .working: return "working"
        case .waitingReview: return "waiting review"
        case .waitingInput: return "waiting input"
        case .degraded: return "degraded"
        }
    }
}

enum WorkbenchRuntimeState: String, Hashable {
    case live
    case needsSetup
    case degraded
    case unavailable

    var title: String {
        switch self {
        case .live: "Live"
        case .needsSetup: "Needs Setup"
        case .degraded: "Degraded"
        case .unavailable: "Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .live: "checkmark.circle.fill"
        case .needsSetup: "wrench.and.screwdriver"
        case .degraded: "exclamationmark.triangle.fill"
        case .unavailable: "bolt.horizontal.circle"
        }
    }
}

struct WorkbenchRuntimeStatus: Hashable {
    var state: WorkbenchRuntimeState
    var detail: String
    var providerName: String?
}

struct WorkbenchInteractionCapabilities: Hashable {
    var canSendMessages: Bool
    var canMutateRuntime: Bool
    var readOnlyReason: String?
    /// Gate for the menu-bar quick-input panel. Mirrors the runtime's
    /// `can_use_quick_input` flag; preview/read-only surfaces set this to
    /// false so the panel renders a non-interactive hint.
    var canUseQuickInput: Bool = true
}

enum WorkbenchRequestOutcomeKind: String, Hashable {
    case chatReply
    case taskHandoff
    case firstPartyAction
    case clarifyNeeded
    case needsSetup
    case error
}

struct WorkbenchRequestOutcome: Hashable {
    var kind: WorkbenchRequestOutcomeKind
    var detail: String
    var taskID: String?
}

struct WorkbenchHomeSummary {
    var openTasksCount: Int
    var approvalsCount: Int
    var nextAutomationLabel: String
    var installedAppsCount: Int
}

struct WorkbenchHomeItem: Identifiable, Hashable {
    enum Kind: String {
        case approval
        case task
        case automation
        case app

        var title: String {
            switch self {
            case .approval: "Approval"
            case .task: "Task"
            case .automation: "Automation"
            case .app: "App"
            }
        }

        var systemImage: String {
            switch self {
            case .approval: "checkmark.shield"
            case .task: "list.bullet.rectangle"
            case .automation: "calendar.badge.clock"
            case .app: "shippingbox"
            }
        }
    }

    let id: String
    var title: String
    var detail: String
    var statusLabel: String
    var actionLabel: String
    var kind: Kind
}

struct ConversationThread: Identifiable, Hashable {
    let id: String
    var title: String
    var participantLabel: String
    var previewText: String
    var statusLabel: String
    var lastActivityLabel: String
    var unreadCount: Int
    var linkedTaskTitle: String?
    var linkedAppName: String?
    var messages: [ConversationMessage]
    var tags: [String] = []
    var isActive: Bool = false
}

struct ConversationMessageDetailItem: Identifiable, Hashable {
    var id: String { "\(label):\(value)" }
    var label: String
    var value: String
}

struct ConversationMessage: Identifiable, Hashable {
    enum Role: String {
        case user
        case assistant
        case system

        var title: String {
            switch self {
            case .user: "You"
            case .assistant: "GeeAgent"
            case .system: "System"
            }
        }
    }

    enum Kind: Hashable {
        case chat
        case thinking
        case action
        case approval
    }

    enum Tone: Hashable {
        case neutral
        case info
        case success
        case warning
        case critical
    }

    let id: String
    var role: Role
    var kind: Kind = .chat
    var headerTitle: String? = nil
    var content: String
    var timestampLabel: String
    var statusLabel: String? = nil
    var systemImage: String? = nil
    var secondaryContent: String? = nil
    var detailItems: [ConversationMessageDetailItem] = []
    var primaryActionLabel: String? = nil
    var primaryActionTaskID: String? = nil
    var sourceReferenceID: String? = nil
    var tone: Tone = .neutral

    static let seedPlaceholderTexts = [
        "New conversation ready. Tell GeeAgent what you need next.",
        "New conversation ready. Tell GeeAgent what to do next.",
        "New conversation ready. Tell GeeAgent what to do next, or use quick input for a lighter command.",
        "Fresh conversation ready. Tell GeeAgent what to do next."
    ]

    static func isSeedPlaceholderContent(_ content: String) -> Bool {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return false
        }

        return seedPlaceholderTexts.contains(normalized)
            || normalized.hasPrefix("New conversation ready.")
            || normalized.hasPrefix("Fresh conversation ready.")
    }

    var isSeedPlaceholder: Bool {
        role == .assistant && Self.isSeedPlaceholderContent(content)
    }

    var displayTitle: String {
        headerTitle ?? role.title
    }

    var canDelete: Bool {
        kind == .chat
    }
}

struct ConversationTurnBlock: Identifiable, Hashable {
    var id: String
    var userMessage: ConversationMessage?
    var agentMessages: [ConversationMessage]

    var isEmpty: Bool {
        userMessage == nil && agentMessages.isEmpty
    }
}

extension ConversationThread {
    var visibleMessages: [ConversationMessage] {
        messages.filter { !$0.isSeedPlaceholder }
    }

    var turnBlocks: [ConversationTurnBlock] {
        var blocks = [ConversationTurnBlock]()
        var currentUserMessage: ConversationMessage?
        var currentAgentMessages = [ConversationMessage]()

        func flushCurrentBlock() {
            let blockID = currentUserMessage?.id ?? currentAgentMessages.first?.id ?? "turn-\(blocks.count)"
            let block = ConversationTurnBlock(
                id: blockID,
                userMessage: currentUserMessage,
                agentMessages: currentAgentMessages
            )
            if !block.isEmpty {
                blocks.append(block)
            }
            currentUserMessage = nil
            currentAgentMessages = []
        }

        for message in visibleMessages {
            if message.role == .user && message.kind == .chat {
                flushCurrentBlock()
                currentUserMessage = message
            } else {
                currentAgentMessages.append(message)
            }
        }

        flushCurrentBlock()
        return blocks
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Conversation"
        }

        if trimmed.hasPrefix("Quick:") {
            let stripped = trimmed.dropFirst("Quick:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? "Conversation" : stripped
        }

        return trimmed
    }

    var displayPreviewText: String {
        let trimmed = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        return ConversationMessage.isSeedPlaceholderContent(trimmed) ? "" : trimmed
    }
}

enum WorkbenchTaskStatus: String, CaseIterable, Hashable {
    case needsApproval
    case running
    case blocked
    case queued
    case completed
    case failed

    var title: String {
        switch self {
        case .needsApproval: "Needs Approval"
        case .running: "Running"
        case .blocked: "Blocked"
        case .queued: "Queued"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }

    var shortTitle: String {
        switch self {
        case .needsApproval: "Approval"
        case .running: "Running"
        case .blocked: "Blocked"
        case .queued: "Queued"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .needsApproval: "hand.raised"
        case .running: "play.circle"
        case .blocked: "exclamationmark.triangle"
        case .queued: "clock"
        case .completed: "checkmark.circle"
        case .failed: "xmark.octagon"
        }
    }
}

struct WorkbenchTaskRecord: Identifiable, Hashable {
    let id: String
    var title: String
    var ownerLabel: String
    var appName: String
    var status: WorkbenchTaskStatus
    var priorityLabel: String
    var dueLabel: String
    var updatedLabel: String
    var summary: String
    var artifactCount: Int
    var approvalRequestID: String? = nil
    var moduleRunID: String? = nil
    var canRetry: Bool = false
}

enum WorkbenchTaskAction: Hashable {
    case allowOnce
    case alwaysAllow
    case deny
    case complete
    case retry

    var title: String {
        switch self {
        case .allowOnce: "Allow once"
        case .alwaysAllow: "Always allow"
        case .deny: "Deny"
        case .complete: "Complete"
        case .retry: "Retry"
        }
    }

    var systemImage: String {
        switch self {
        case .allowOnce: "play.circle.fill"
        case .alwaysAllow: "checkmark.shield.fill"
        case .deny: "hand.raised.fill"
        case .complete: "checkmark.circle"
        case .retry: "arrow.clockwise"
        }
    }
}

enum AutomationStatus: String, Hashable {
    case active
    case paused
    case attention

    var title: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .attention: "Attention"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "checkmark.circle"
        case .paused: "pause.circle"
        case .attention: "exclamationmark.circle"
        }
    }
}

struct AutomationRecord: Identifiable, Hashable {
    let id: String
    var name: String
    var scopeLabel: String
    var scheduleLabel: String
    var nextRunLabel: String
    var lastRunLabel: String
    var status: AutomationStatus
    var summary: String
}

enum AppInstallState: String, Hashable, Sendable {
    case installed
    case updateAvailable
    case needsPermission
    case installError

    var title: String {
        switch self {
        case .installed: "Installed"
        case .updateAvailable: "Update Available"
        case .needsPermission: "Needs Permission"
        case .installError: "Install Issue"
        }
    }

    var systemImage: String {
        switch self {
        case .installed: "checkmark.seal"
        case .updateAvailable: "arrow.triangle.2.circlepath"
        case .needsPermission: "lock.shield"
        case .installError: "exclamationmark.triangle"
        }
    }
}

struct InstalledAppRecord: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var categoryLabel: String
    var versionLabel: String
    var healthLabel: String
    var installState: AppInstallState
    var summary: String
    /// Defaults to `inNav` when the runtime omits the field (older snapshots).
    var displayMode: ModuleDisplayMode
    var developerLabel: String = ""
    var coverURL: URL? = nil
    var iconURL: URL? = nil
    var gearKind: GearKind = .atmosphere
    var installIssue: String? = nil
    var isGearPackage: Bool = false
}

enum AgentProfileSourceRecord: String, CaseIterable, Hashable, Identifiable {
    case firstParty = "first_party"
    case userCreated = "user_created"
    case modulePack = "module_pack"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstParty: "First-Party"
        case .userCreated: "User Created"
        case .modulePack: "Module Pack"
        }
    }

    var systemImage: String {
        switch self {
        case .firstParty: "checkmark.seal"
        case .userCreated: "person.crop.circle"
        case .modulePack: "shippingbox"
        }
    }
}

enum AgentProfileAppearanceRecord: Hashable {
    case staticImage(assetPath: String)
    case video(assetPath: String)
    case live2D(bundlePath: String)
    case abstract

    var title: String {
        switch self {
        case .staticImage: "Static Image"
        case .video: "Video"
        case .live2D: "Live2D"
        case .abstract: "Abstract"
        }
    }

    var assetPath: String? {
        switch self {
        case let .staticImage(assetPath), let .video(assetPath):
            assetPath
        case let .live2D(bundlePath):
            bundlePath
        case .abstract:
            nil
        }
    }
}

struct AgentSkillReferenceRecord: Identifiable, Hashable {
    let id: String
    var name: String
    var description: String? = nil
    var path: String? = nil
    var skillFilePath: String? = nil
    var sourceID: String? = nil
    var sourceScope: String? = nil
    var sourcePath: String? = nil
    var profileID: String? = nil
    var status: String? = nil
    var error: String? = nil
}

struct SkillSourceRecord: Identifiable, Hashable {
    let id: String
    var path: String
    var scope: String
    var profileID: String?
    var enabled: Bool
    var addedAt: String
    var lastScannedAt: String?
    var status: String
    var error: String?
    var skills: [AgentSkillReferenceRecord]

    var statusTitle: String {
        switch status {
        case "ready": "Ready"
        case "unavailable": "Unavailable"
        case "invalid": "Invalid"
        default: status.isEmpty ? "Unknown" : status.capitalized
        }
    }

    var skillsSummary: String {
        skills.count == 1 ? "1 skill" : "\(skills.count) skills"
    }
}

struct SkillSourcesRecord: Hashable {
    var systemSources: [SkillSourceRecord]
    var personaSources: [String: [SkillSourceRecord]]

    static let empty = SkillSourcesRecord(systemSources: [], personaSources: [:])

    func personaSources(for profileID: String) -> [SkillSourceRecord] {
        personaSources[profileID] ?? []
    }
}

struct AgentProfileFileEntryRecord: Identifiable, Hashable {
    var id: String { path }
    var title: String
    var path: String
}

struct AgentProfileFileStateRecord: Hashable {
    var workspaceRootPath: String?
    var manifestPath: String?
    var identityPromptPath: String?
    var soulPath: String?
    var playbookPath: String?
    var toolsContextPath: String?
    var memorySeedPath: String?
    var heartbeatPath: String?
    var visualFiles: [AgentProfileFileEntryRecord]
    var supplementalFiles: [AgentProfileFileEntryRecord]
    var canReload: Bool
    var canDelete: Bool

    static let empty = AgentProfileFileStateRecord(
        workspaceRootPath: nil,
        manifestPath: nil,
        identityPromptPath: nil,
        soulPath: nil,
        playbookPath: nil,
        toolsContextPath: nil,
        memorySeedPath: nil,
        heartbeatPath: nil,
        visualFiles: [],
        supplementalFiles: [],
        canReload: false,
        canDelete: false
    )
}

struct AgentProfileRecord: Identifiable, Hashable {
    let id: String
    var name: String
    var tagline: String
    var personalityPrompt: String
    var appearance: AgentProfileAppearanceRecord
    var globalBackground: AgentProfileGlobalBackgroundRecord = .none
    var visualOptions: AgentProfileVisualOptionsRecord = .empty
    var skills: [AgentSkillReferenceRecord]
    var allowedToolIDs: [String]?
    var source: AgentProfileSourceRecord
    var version: String
    var fileState: AgentProfileFileStateRecord = .empty

    var summary: String {
        tagline
    }

    var appearanceTitle: String {
        appearance.title
    }

    var skillsSummary: String {
        if skills.isEmpty {
            return "No skills"
        }

        return skills.count == 1 ? "1 skill" : "\(skills.count) skills"
    }

    var allowedToolsSummary: String {
        guard let allowedToolIDs else {
            return "Workspace defaults"
        }

        if allowedToolIDs.isEmpty {
            return "No tools allowed"
        }

        return allowedToolIDs.count == 1 ? "1 tool allowed" : "\(allowedToolIDs.count) tools allowed"
    }

    var canRevealFiles: Bool {
        fileState.workspaceRootPath != nil
            || fileState.manifestPath != nil
            || fileState.identityPromptPath != nil
            || !fileState.visualFiles.isEmpty
            || !fileState.supplementalFiles.isEmpty
    }
}

struct AgentSkinRecord: Identifiable, Hashable {
    let id: String
    var name: String
    var toneLabel: String
    var activationLabel: String
    var summary: String
}

extension AgentSkinRecord {
    var asAgentProfileRecord: AgentProfileRecord {
        AgentProfileRecord(
            id: id,
            name: name,
            tagline: toneLabel,
            personalityPrompt: summary,
            appearance: .abstract,
            globalBackground: .none,
            visualOptions: .empty,
            skills: [],
            allowedToolIDs: nil,
            source: .modulePack,
            version: "legacy-skin",
            fileState: .empty
        )
    }
}

enum WorkbenchExtensionSelection: Hashable {
    case app(String)
    case skin(String)
}

struct SettingsPaneSummary: Identifiable, Hashable {
    let id: String
    var title: String
    var summary: String
    var items: [SettingValue]
}

struct SettingValue: Identifiable, Hashable {
    let id: String
    var label: String
    var value: String
}
