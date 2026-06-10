protocol WorkbenchRuntimeClient: Sendable {
    func loadSnapshot() -> WorkbenchSnapshot
    func loadLiveSnapshot() -> WorkbenchSnapshot
    func loadExternalInvocationSnapshot(from currentSnapshot: WorkbenchSnapshot) -> WorkbenchSnapshot
    func createConversation(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot
    func activateConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func deleteConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func sendMessage(
        _ message: String,
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        allowAutoRouting: Bool
    ) async throws -> WorkbenchSnapshot
    func cancelActiveRun(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot
    func performTaskAction(
        _ action: WorkbenchTaskAction,
        in snapshot: WorkbenchSnapshot,
        taskID: WorkbenchTaskRecord.ID
    ) async throws -> WorkbenchSnapshot
    func setActiveAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot

    /// Installs an agent definition from a user-selected directory and returns the
    /// refreshed snapshot containing the newly-available persona.
    func installAgentPack(
        at packPath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func reloadAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func deleteAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func addSystemSkillSource(
        at sourcePath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func removeSystemSkillSource(
        _ sourceID: SkillSourceRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func addPersonaSkillSource(
        profileID: AgentProfileRecord.ID,
        sourcePath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func removePersonaSkillSource(
        profileID: AgentProfileRecord.ID,
        sourceID: SkillSourceRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func deleteTerminalPermissionRule(
        _ ruleID: TerminalPermissionRuleRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func setHighestAuthorizationEnabled(
        _ enabled: Bool,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func loadChatRoutingSettings() async throws -> ChatRoutingSettings
    func saveChatRoutingSettings(
        _ settings: ChatRoutingSettings,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func loadProviderSecretSettings() async throws -> ProviderSecretSettings
    func saveProviderAPIKey(
        providerID: String,
        apiKey: String
    ) async throws -> ProviderSecretSettings
    func clearProviderAPIKey(providerID: String) async throws -> ProviderSecretSettings
    func loadAgentGatewayStatus() async throws -> AgentGatewayStatusRecord
    func loadAgentGatewayClientStatus() async throws -> AgentGatewayClientStatusProjection
    func projectRuntimeRun(_ runID: String) async throws -> WorkbenchRuntimeRunProjection
    func classifyRuntimeRunWait(_ runID: String) async throws -> WorkbenchRuntimeRunWaitClassification

    /// Submits a single-shot prompt through the menu-bar / quick-input surface
    /// and returns the next full snapshot.
    func submitQuickPrompt(
        _ prompt: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
    func submitChannelMessage(
        _ payload: TelegramChannelMessagePayload,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot

    /// Completes a runtime-routed Gear turn after the native host has executed
    /// the requested actions. The backend uses these structured results to ask
    /// the agent/LLM for the final user-facing reply.
    func completeHostActionTurn(
        _ completions: [WorkbenchHostActionCompletion],
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot

    /// Invokes a tool through the backend dispatcher. Returns the raw outcome;
    /// the store decides how to apply it (navigate, pop approval sheet, etc.).
    func invokeTool(_ invocation: ToolInvocation) async throws -> WorkbenchToolOutcome

    /// Completes a Codex-originated external invocation after GeeAgentMac has
    /// executed it through GearHost.
    func completeExternalInvocation(
        _ completion: WorkbenchExternalInvocationCompletion,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot
}

protocol WorkbenchAttachmentRuntimeClient: WorkbenchRuntimeClient {
    func sendMessage(
        _ message: String,
        attachments: [WorkspaceInputAttachment],
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        allowAutoRouting: Bool
    ) async throws -> WorkbenchSnapshot
}

struct WorkspaceInputAttachment: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case image
        case file
        case directory
    }

    enum Source: String, Codable, Sendable {
        case workspaceChat = "workspace_chat"
        case channelIngress = "channel_ingress"
        case codexBridge = "codex_bridge"
    }

    enum Status: String, Codable, Sendable {
        case ready
        case degraded
        case failed
    }

    struct Access: Codable, Hashable, Sendable {
        var scope: String = "run"
        var mode: String = "read"
        var root: String?
        var expiresAt: String?
    }

    struct ImageInfo: Codable, Hashable, Sendable {
        var width: Int?
        var height: Int?
        var storedBase64Ref: String?
        var resized: Bool?
    }

    struct Limits: Codable, Hashable, Sendable {
        var maxBytes: Int?
        var maxEntries: Int?
        var maxDepth: Int?
    }

    struct Failure: Codable, Hashable, Sendable {
        var code: String
        var message: String
    }

    var id: String { attachmentId }

    var attachmentId: String
    var kind: Kind
    var source: Source = .workspaceChat
    var displayName: String
    var originalPath: String?
    var resolvedPath: String?
    var mimeType: String?
    var sizeBytes: Int?
    var createdAt: String
    var status: Status = .ready
    var access: Access = Access()
    var image: ImageInfo?
    var limits: Limits?
    var error: Failure?
    var fallbackAttempted: Bool = false
}

struct WorkspaceMessageInputPayload: Codable, Hashable, Sendable {
    var inputType = "workspace_message"
    var text: String
    var attachments: [WorkspaceInputAttachment]
}

struct TelegramChannelMessageAttachmentRef: Codable, Hashable, Sendable {
    var artifactId: String
    var kind: String
    var type: String
    var title: String
    var uri: String
    var summary: String
    var mimeType: String?
    var telegramFileId: String
    var telegramFileUniqueId: String?
    var telegramMediaKind: String
    var width: Int?
    var height: Int?
}

struct TelegramChannelMessagePayload: Codable, Hashable, Sendable {
    struct Message: Codable, Hashable, Sendable {
        var idempotencyKey: String
        var telegramUpdateId: Int?
        var chatId: String
        var messageId: String
        var fromUserId: String?
        var text: String
        var attachments: [TelegramChannelMessageAttachmentRef]
    }

    struct Security: Codable, Hashable, Sendable {
        var decision: String
        var policyId: String
    }

    struct Projection: Codable, Hashable, Sendable {
        struct ReplyTarget: Codable, Hashable, Sendable {
            var chatId: String
            var messageId: String
        }

        var surface: String
        var replyTarget: ReplyTarget
    }

    var source: String = "telegram.bridge"
    var role: String = "gee_direct"
    var channelIdentity: String
    var message: Message
    var security: Security
    var projection: Projection
}

extension WorkbenchRuntimeClient {
    func loadLiveSnapshot() -> WorkbenchSnapshot {
        loadSnapshot()
    }

    func loadExternalInvocationSnapshot(from currentSnapshot: WorkbenchSnapshot) -> WorkbenchSnapshot {
        loadLiveSnapshot()
    }

    func cancelActiveRun(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot {
        snapshot
    }

    func sendMessage(
        _ message: String,
        attachments: [WorkspaceInputAttachment],
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        allowAutoRouting: Bool
    ) async throws -> WorkbenchSnapshot {
        if attachments.isEmpty {
            return try await sendMessage(
                message,
                in: snapshot,
                conversationID: conversationID,
                allowAutoRouting: allowAutoRouting
            )
        }
        guard let attachmentClient = self as? any WorkbenchAttachmentRuntimeClient else {
            throw RuntimeProcessError.unsupported(
                "This runtime client does not support workspace input attachments."
            )
        }
        return try await attachmentClient.sendMessage(
            message,
            attachments: attachments,
            in: snapshot,
            conversationID: conversationID,
            allowAutoRouting: allowAutoRouting
        )
    }

    func completeExternalInvocation(
        _ completion: WorkbenchExternalInvocationCompletion,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = completion
        _ = snapshot
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support external Codex invocation completion."
        )
    }

    func submitChannelMessage(
        _ payload: TelegramChannelMessagePayload,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = payload
        _ = snapshot
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support Telegram channel ingress."
        )
    }

    func projectRuntimeRun(_ runID: String) async throws -> WorkbenchRuntimeRunProjection {
        _ = runID
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support runtime run projection."
        )
    }

    func classifyRuntimeRunWait(_ runID: String) async throws -> WorkbenchRuntimeRunWaitClassification {
        _ = runID
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support runtime run wait classification."
        )
    }

    func loadAgentGatewayStatus() async throws -> AgentGatewayStatusRecord {
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support Agent Gateway status."
        )
    }

    func loadAgentGatewayClientStatus() async throws -> AgentGatewayClientStatusProjection {
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support Agent Gateway client status."
        )
    }

    func addSystemSkillSource(
        at sourcePath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = sourcePath
        _ = snapshot
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support global skill sources."
        )
    }

    func removeSystemSkillSource(
        _ sourceID: SkillSourceRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = sourceID
        _ = snapshot
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support global skill sources."
        )
    }

    func addPersonaSkillSource(
        profileID: AgentProfileRecord.ID,
        sourcePath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = profileID
        _ = sourcePath
        _ = snapshot
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support persona skill sources."
        )
    }

    func removePersonaSkillSource(
        profileID: AgentProfileRecord.ID,
        sourceID: SkillSourceRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = profileID
        _ = sourceID
        _ = snapshot
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support persona skill sources."
        )
    }

    func loadProviderSecretSettings() async throws -> ProviderSecretSettings {
        ProviderSecretSettings.defaultSettings
    }

    func saveProviderAPIKey(
        providerID: String,
        apiKey: String
    ) async throws -> ProviderSecretSettings {
        _ = providerID
        _ = apiKey
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support provider key storage."
        )
    }

    func clearProviderAPIKey(providerID: String) async throws -> ProviderSecretSettings {
        _ = providerID
        throw RuntimeProcessError.unsupported(
            "This runtime client does not support provider key storage."
        )
    }
}
