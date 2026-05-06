protocol WorkbenchRuntimeClient: Sendable {
    func loadSnapshot() -> WorkbenchSnapshot
    func loadLiveSnapshot() -> WorkbenchSnapshot
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

struct TelegramChannelMessagePayload: Codable, Hashable, Sendable {
    struct Message: Codable, Hashable, Sendable {
        var idempotencyKey: String
        var telegramUpdateId: Int?
        var chatId: String
        var messageId: String
        var fromUserId: String?
        var text: String
        var attachments: [String]
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
}
