protocol WorkbenchRuntimeClient: Sendable {
    func loadSnapshot() -> WorkbenchSnapshot
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
        conversationID: ConversationThread.ID
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

    /// Submits a single-shot prompt through the menu-bar / quick-input surface
    /// and returns the next full snapshot.
    func submitQuickPrompt(
        _ prompt: String,
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
}

extension WorkbenchRuntimeClient {
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
