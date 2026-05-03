import Foundation

enum NativeRuntimeBundle {
    static let entryFileName = "index.mjs"
    static let resourceDirectory = "agent-runtime/native-runtime"
    static let sdkCliResourceDirectory = "agent-runtime/claude-sdk"
    static let sdkCliFileName = "claude"
    static let configResourceDirectory = "agent-runtime/config"
    static let modelRoutingConfigFileName = "model-routing.toml"
    static let chatRuntimeConfigFileName = "chat-runtime.toml"
}

private struct RuntimeInteractionCapabilitiesDTO: Decodable {
    let surface: String
    let canSendMessages: Bool
    let canUseQuickInput: Bool
    let canMutateRuntime: Bool
    let canRunFirstPartyActions: Bool
    let readOnlyReason: String?
}

private struct RuntimeRequestOutcomeDTO: Decodable {
    let source: String
    let kind: String
    let detail: String
    let taskId: String?
    let moduleRunId: String?
}

private struct RuntimeChatRuntimeDTO: Decodable {
    let status: String
    let activeProvider: String?
    let detail: String
}

private struct RuntimeLastRunStateDTO: Decodable {
    let conversationId: String?
    let status: String
    let stopReason: String?
    let detail: String?
    let resumable: Bool?
    let taskId: String?
    let moduleRunId: String?
}

struct XenodiaMediaBackend: Codable, Hashable, Sendable {
    let apiKey: String
    let imageGenerationsURL: String
    let taskRetrievalURL: String
    let storageUploadURL: String?
    let requestTimeoutSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case imageGenerationsURL = "image_generations_url"
        case taskRetrievalURL = "task_retrieval_url"
        case storageUploadURL = "storage_upload_url"
        case requestTimeoutSeconds = "request_timeout_seconds"
    }

    static func decodeRuntimePayload(_ data: Data) throws -> XenodiaMediaBackend {
        // This DTO already declares explicit snake_case CodingKeys. Do not reuse
        // the runtime-wide .convertFromSnakeCase decoder or the keys are converted
        // twice and valid Xenodia channel JSON fails before any API request is made.
        try JSONDecoder().decode(XenodiaMediaBackend.self, from: data)
    }
}

private struct RuntimeContextBudgetDTO: Decodable {
    let maxTokens: Int
    let usedTokens: Int
    let reservedOutputTokens: Int
    let usageRatio: Double
    let estimateSource: String
    let summaryState: String
    let lastSummarizedAt: String?
    let nextSummaryAtRatio: Double
    let compactedMessagesCount: Int
    let projectionMode: String?
    let rawHistoryTokens: Int?
    let projectedHistoryTokens: Int?
    let recentTokens: Int?
    let summaryTokens: Int?
    let latestRequestTokens: Int?
}

private struct RuntimeConversationMessageDTO: Decodable {
    let messageId: String
    let role: String
    let content: String
    let timestamp: String
}

private struct RuntimeConversationDTO: Decodable {
    let conversationId: String
    let title: String
    let status: String
    let tags: [String]?
    let messages: [RuntimeConversationMessageDTO]
}

private struct RuntimeConversationSummaryDTO: Decodable {
    let conversationId: String
    let title: String
    let status: String
    let tags: [String]?
    let lastMessagePreview: String
    let lastTimestamp: String
    let isActive: Bool
}

private struct RuntimeTaskDTO: Decodable {
    let taskId: String
    let title: String
    let summary: String
    let currentStage: String
    let status: String
    let importanceLevel: String
    let progressPercent: Int
    let artifactCount: Int
    let approvalRequestId: String?
}

private struct RuntimeApprovalParameterDTO: Decodable {
    let label: String
    let value: String
}

private struct RuntimeApprovalDTO: Decodable {
    let approvalRequestId: String
    let taskId: String
    let actionTitle: String
    let reason: String
    let riskTags: [String]
    let reviewRequired: Bool
    let status: String
    let parameters: [RuntimeApprovalParameterDTO]
}

private struct RuntimeAutomationDTO: Decodable {
    let automationId: String
    let name: String
    let status: String
    let triggerKind: String
    let cadence: String
    let timeOfDay: String
    let scheduleHint: String?
    let goalPrompt: String
}

private struct RuntimeModuleRecoverabilityDTO: Decodable {
    let retrySafe: Bool
    let resumeSupported: Bool
    let hint: String?
}

private struct RuntimeModuleRunCoreDTO: Decodable {
    let moduleRunId: String
    let taskId: String
    let moduleId: String
    let status: String
    let updatedAt: String
}

private struct RuntimeModuleRunDTO: Decodable {
    let moduleRun: RuntimeModuleRunCoreDTO
    let recoverability: RuntimeModuleRecoverabilityDTO?
}

private struct RuntimeWorkspaceFocusDTO: Decodable {
    let mode: String
    let taskId: String?
}

private struct RuntimeWorkspaceAppDTO: Decodable {
    let appId: String
    let displayName: String
    let installState: String
    let displayMode: String?
}

private struct RuntimeWorkspaceSkinDTO: Decodable {
    let skinId: String
    let displayName: String
}

private struct RuntimeWorkspaceRuntimeDTO: Decodable {
    let activeSection: String
    let sections: [String]
    let apps: [RuntimeWorkspaceAppDTO]
    let agentSkins: [RuntimeWorkspaceSkinDTO]
}

private struct RuntimeAgentProfileAppearanceDTO: Decodable {
    let kind: String
    let assetPath: String?
    let bundlePath: String?
    let live2dBundlePath: String?
    let videoAssetPath: String?
    let imageAssetPath: String?
    let globalBackground: RuntimeAgentProfileGlobalBackgroundDTO?
}

private struct RuntimeAgentProfileGlobalBackgroundDTO: Decodable {
    let kind: String?
    let assetPath: String?
    let videoAssetPath: String?
    let imageAssetPath: String?
}

private struct RuntimeAgentSkillRefDTO: Decodable {
    let id: String
    let name: String?
    let description: String?
    let path: String?
    let skillFilePath: String?
    let sourceId: String?
    let sourceScope: String?
    let sourcePath: String?
    let profileId: String?
    let status: String?
    let error: String?
}

private struct RuntimeSkillSourceDTO: Decodable {
    let id: String
    let path: String
    let scope: String
    let profileId: String?
    let enabled: Bool
    let addedAt: String
    let lastScannedAt: String?
    let status: String
    let error: String?
    let skills: [RuntimeAgentSkillRefDTO]?
}

private struct RuntimeSkillSourcesDTO: Decodable {
    let systemSources: [RuntimeSkillSourceDTO]?
    let personaSources: [String: [RuntimeSkillSourceDTO]]?
}

private struct RuntimeAgentProfileFileEntryDTO: Decodable {
    let title: String
    let path: String
}

private struct RuntimeAgentProfileFileStateDTO: Decodable {
    let workspaceRootPath: String?
    let manifestPath: String?
    let identityPromptPath: String?
    let soulPath: String?
    let playbookPath: String?
    let toolsContextPath: String?
    let memorySeedPath: String?
    let heartbeatPath: String?
    let visualFiles: [RuntimeAgentProfileFileEntryDTO]?
    let supplementalFiles: [RuntimeAgentProfileFileEntryDTO]?
    let canReload: Bool?
    let canDelete: Bool?
}

private struct RuntimeAgentProfileDTO: Decodable {
    let id: String
    let name: String
    let tagline: String
    let personalityPrompt: String
    let appearance: RuntimeAgentProfileAppearanceDTO
    let skills: [RuntimeAgentSkillRefDTO]?
    let allowedToolIds: [String]?
    let source: String
    let version: String
    let fileState: RuntimeAgentProfileFileStateDTO?
}

private struct RuntimeExecutionSessionDTO: Decodable {
    let sessionId: String
    let conversationId: String?
}

private struct RuntimeArtifactRefDTO: Decodable {
    let artifactId: String
    let artifactType: String
    let title: String
    let payloadRef: String
    let inlinePreviewSummary: String?

    private enum CodingKeys: String, CodingKey {
        case artifactId
        case artifactType = "type"
        case title
        case payloadRef
        case inlinePreviewSummary
    }
}

private struct RuntimeRunProjectionDTO: Decodable {
    let runId: String
    let rowCount: Int
    let artifactIds: [String]
    let artifactRefs: [RuntimeRunArtifactRefDTO]
    let diagnostics: RuntimeRunDiagnosticsDTO
    let rows: [RuntimeRunProjectionRowDTO]
}

private struct RuntimeRunProjectionRowDTO: Decodable {
    let rowId: String
    let runId: String
    let sequence: Int
    let eventId: String?
    let eventKind: String
    let projectionKind: String
    let label: String
    let status: String?
    let summary: String
    let stageId: String?
    let toolName: String?
    let projectionScope: String
    let expandable: Bool
    let artifactIds: [String]
}

private struct RuntimeRunArtifactRefDTO: Decodable {
    let artifactId: String
    let kind: String?
    let title: String?
    let path: String?
    let summary: String?
    let sha256: String?
    let byteCount: Int?
    let tokenEstimate: Int?
    let mimeType: String?
    let sourceEventId: String?
    let sourceEventSequence: Int?
    let sourceInvocationId: String?
    let sourceToolName: String?
    let sourceHostActionId: String?
}

private struct RuntimeRunDiagnosticsDTO: Decodable {
    let duplicateEventIds: [String]
    let missingParentEventIds: [String]
    let missingSequenceNumbers: [Int]
    let outOfOrderEventIds: [String]
}

private struct RuntimeRunWaitClassificationDTO: Decodable {
    let runId: String
    let waitKind: String
    let status: String
    let detail: String
    let evidence: RuntimeRunWaitEvidenceDTO
}

private struct RuntimeRunWaitEvidenceDTO: Decodable {
    let runId: String
    let lastEventKind: String?
    let lastEventSequence: Int?
    let lastToolUseId: String?
    let pendingToolUseId: String?
    let pendingHostActionIds: [String]
    let pendingApprovalId: String?
    let sdkSessionId: String?
    let gatewayRequestId: String?
    let diagnostics: RuntimeRunDiagnosticsDTO
}

private struct RuntimeToolInvocationDTO: Decodable {
    let invocationId: String
    let sessionId: String
    let originatingMessageId: String
    let toolName: String
    let inputSummary: String?
    let status: String
    let approvalRequestId: String?
    let createdAt: String
    let updatedAt: String
}

private struct RuntimeRunPlanStageDTO: Decodable {
    let stageId: String?
    let title: String?
    let objective: String?
    let requiredCapabilities: [String]?
    let inputContract: [String]?
    let completionSignal: String?
    let blockedSignal: String?
}

private struct RuntimeRunPlanDTO: Decodable {
    let planId: String?
    let userGoal: String?
    let successCriteria: [String]?
    let stages: [RuntimeRunPlanStageDTO]?
    let currentStageId: String?
    let reopenCapabilityDiscoveryWhen: [String]?
}

private enum RuntimeTranscriptEventPayloadDTO: Decodable {
    case userMessage(messageId: String, content: String)
    case assistantMessage(messageId: String, content: String)
    case assistantMessageDelta(messageId: String, delta: String)
    case runPlanCreated(runPlan: RuntimeRunPlanDTO?, summary: String?)
    case runPlanUpdated(
        runPlan: RuntimeRunPlanDTO?,
        runPlanId: String?,
        currentStageId: String?,
        summary: String?
    )
    case capabilityFocusLocked(
        runPlanId: String?,
        stageId: String?,
        focusGearIds: [String],
        focusCapabilityIds: [String],
        summary: String?
    )
    case stageStarted(
        runPlanId: String?,
        stageId: String?,
        title: String?,
        objective: String?,
        requiredCapabilities: [String],
        summary: String?
    )
    case stageConcluded(
        runPlanId: String?,
        stageId: String?,
        title: String?,
        status: String,
        summary: String?
    )
    case toolInvocation(invocation: RuntimeToolInvocationDTO)
    case toolResult(
        invocationId: String,
        status: String,
        summary: String?,
        error: String?,
        artifacts: [RuntimeArtifactRefDTO]
    )
    case sessionStateChanged(summary: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case messageId
        case content
        case delta
        case runPlan
        case runPlanId
        case currentStageId
        case stageId
        case title
        case objective
        case requiredCapabilities
        case focusGearIds
        case focusCapabilityIds
        case invocation
        case invocationId
        case status
        case summary
        case error
        case artifacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "user_message":
            self = .userMessage(
                messageId: try container.decode(String.self, forKey: .messageId),
                content: try container.decode(String.self, forKey: .content)
            )
        case "assistant_message":
            self = .assistantMessage(
                messageId: try container.decode(String.self, forKey: .messageId),
                content: try container.decode(String.self, forKey: .content)
            )
        case "assistant_message_delta":
            self = .assistantMessageDelta(
                messageId: try container.decode(String.self, forKey: .messageId),
                delta: try container.decode(String.self, forKey: .delta)
            )
        case "run_plan_created":
            self = .runPlanCreated(
                runPlan: try container.decodeIfPresent(RuntimeRunPlanDTO.self, forKey: .runPlan),
                summary: try container.decodeIfPresent(String.self, forKey: .summary)
            )
        case "run_plan_updated":
            self = .runPlanUpdated(
                runPlan: try container.decodeIfPresent(RuntimeRunPlanDTO.self, forKey: .runPlan),
                runPlanId: try container.decodeIfPresent(String.self, forKey: .runPlanId),
                currentStageId: try container.decodeIfPresent(String.self, forKey: .currentStageId),
                summary: try container.decodeIfPresent(String.self, forKey: .summary)
            )
        case "capability_focus_locked":
            self = .capabilityFocusLocked(
                runPlanId: try container.decodeIfPresent(String.self, forKey: .runPlanId),
                stageId: try container.decodeIfPresent(String.self, forKey: .stageId),
                focusGearIds: try container.decodeIfPresent([String].self, forKey: .focusGearIds) ?? [],
                focusCapabilityIds: try container.decodeIfPresent([String].self, forKey: .focusCapabilityIds) ?? [],
                summary: try container.decodeIfPresent(String.self, forKey: .summary)
            )
        case "stage_started":
            self = .stageStarted(
                runPlanId: try container.decodeIfPresent(String.self, forKey: .runPlanId),
                stageId: try container.decodeIfPresent(String.self, forKey: .stageId),
                title: try container.decodeIfPresent(String.self, forKey: .title),
                objective: try container.decodeIfPresent(String.self, forKey: .objective),
                requiredCapabilities: try container.decodeIfPresent([String].self, forKey: .requiredCapabilities) ?? [],
                summary: try container.decodeIfPresent(String.self, forKey: .summary)
            )
        case "stage_concluded":
            self = .stageConcluded(
                runPlanId: try container.decodeIfPresent(String.self, forKey: .runPlanId),
                stageId: try container.decodeIfPresent(String.self, forKey: .stageId),
                title: try container.decodeIfPresent(String.self, forKey: .title),
                status: try container.decodeIfPresent(String.self, forKey: .status) ?? "completed",
                summary: try container.decodeIfPresent(String.self, forKey: .summary)
            )
        case "tool_invocation":
            self = .toolInvocation(
                invocation: try container.decode(RuntimeToolInvocationDTO.self, forKey: .invocation)
            )
        case "tool_result":
            self = .toolResult(
                invocationId: try container.decode(String.self, forKey: .invocationId),
                status: try container.decode(String.self, forKey: .status),
                summary: try container.decodeIfPresent(String.self, forKey: .summary),
                error: try container.decodeIfPresent(String.self, forKey: .error),
                artifacts: try container.decodeIfPresent([RuntimeArtifactRefDTO].self, forKey: .artifacts) ?? []
            )
        case "session_state_changed":
            self = .sessionStateChanged(
                summary: try container.decode(String.self, forKey: .summary)
            )
        default:
            self = .sessionStateChanged(summary: "Session state updated.")
        }
    }
}

private struct RuntimeTranscriptEventDTO: Decodable {
    let eventId: String
    let sessionId: String
    let parentEventId: String?
    let runId: String?
    let sequence: Int?
    let createdAt: String
    let payload: RuntimeTranscriptEventPayloadDTO
}

private struct RuntimeSnapshotDTO: Decodable {
    let quickInputHint: String
    let quickReply: String
    let contextBudget: RuntimeContextBudgetDTO?
    let interactionCapabilities: RuntimeInteractionCapabilitiesDTO?
    let lastRequestOutcome: RuntimeRequestOutcomeDTO?
    let lastRunState: RuntimeLastRunStateDTO?
    let chatRuntime: RuntimeChatRuntimeDTO
    let conversations: [RuntimeConversationSummaryDTO]
    let activeConversation: RuntimeConversationDTO
    let automations: [RuntimeAutomationDTO]?
    let moduleRuns: [RuntimeModuleRunDTO]
    let executionSessions: [RuntimeExecutionSessionDTO]?
    let transcriptEvents: [RuntimeTranscriptEventDTO]?
    let tasks: [RuntimeTaskDTO]
    let approvalRequests: [RuntimeApprovalDTO]
    let terminalAccessRules: [RuntimeTerminalAccessRuleDTO]?
    let securityPreferences: RuntimeSecurityPreferencesDTO?
    let workspaceFocus: RuntimeWorkspaceFocusDTO
    let workspaceRuntime: RuntimeWorkspaceRuntimeDTO?
    let activeAgentProfile: RuntimeAgentProfileDTO?
    let agentProfiles: [RuntimeAgentProfileDTO]?
    let hostActionIntents: [RuntimeHostActionIntentDTO]?
    let externalInvocations: [RuntimeExternalInvocationDTO]?
    let skillSources: RuntimeSkillSourcesDTO?
}

private struct RuntimeHostActionIntentDTO: Decodable {
    let hostActionId: String
    let toolId: String
    let arguments: RuntimeJSONValue?
}

private struct RuntimeExternalInvocationDTO: Decodable {
    let externalInvocationId: String
    let tool: String
    let status: String
    let gearId: String?
    let capabilityId: String?
    let surfaceId: String?
    let args: RuntimeJSONValue?
}

private enum RuntimeJSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([RuntimeJSONValue])
    case object([String: RuntimeJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RuntimeJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: RuntimeJSONValue].self))
        }
    }
}

private struct RuntimeTerminalAccessRuleDTO: Decodable {
    let ruleId: String
    let decision: String
    let kind: String
    let label: String
    let command: String?
    let cwd: String?
    let updatedAt: String
}

private struct RuntimeSecurityPreferencesDTO: Decodable {
    let highestAuthorizationEnabled: Bool?
}

enum AssistantTranscriptSanitizer {
    static func sanitize(_ content: String) -> String {
        let cleanedContent = removingStageProgressText(
            from: removingControlFrames(from: content)
        )
        var lines = cleanedContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        while let last = lines.last,
              last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeLast()
        }

        guard let lastLine = lines.last else {
            return ""
        }

        let normalizedLastLine = lastLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            .lowercased()

        guard normalizedLastLine == "sources:"
            || normalizedLastLine == "sources："
            || normalizedLastLine == "sources"
        else {
            return cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        lines.removeLast()
        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingControlFrames(from content: String) -> String {
        var output = content
        for pattern in [
            #"(?is)<gee-host-actions>\s*.*?\s*</gee-host-actions>"#,
            #"(?is)```gee-host-actions\s*.*?```"#
        ] {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = expression.stringByReplacingMatches(
                in: output,
                options: [],
                range: range,
                withTemplate: ""
            )
        }
        return output
    }

    private static func removingStageProgressText(from content: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?im)(^|[\n.])\s*(Stage complete|Stage completed)\s*:\s*[^.\n]*(?:\.\s*)?"#
        ) else {
            return content
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return expression
            .stringByReplacingMatches(
                in: content,
                options: [],
                range: range,
                withTemplate: "$1"
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class AgentRuntimeProcess {
    private static let applicationSupportFolderName = "GeeAgent"
    private static let legacyApplicationSupportFolderName = "io.geeagent.desktop"

    private let fileManager = FileManager.default
    private let nativeRuntimeServer = RuntimeCommandServer(label: "TypeScript native runtime")
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static func redactSensitiveJSON(_ raw: String) -> String {
        raw.replacing(
            /"api_key"\s*:\s*"[^"]*"/,
            with: #""api_key":"<redacted>""#
        )
    }

    private var repoRootURL: URL {
        let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        if let discovered = discoverRepoRoot(startingAt: sourceURL) {
            return discovered
        }
        if let resourceURL = Bundle.main.resourceURL,
           let discovered = discoverRepoRoot(startingAt: resourceURL) {
            return discovered
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }

    private var agentRuntimeRootURL: URL {
        repoRootURL
            .appendingPathComponent("apps")
            .appendingPathComponent("agent-runtime")
    }

    private var developmentNativeRuntimeEntryURL: URL {
        agentRuntimeRootURL
            .appendingPathComponent("dist")
            .appendingPathComponent("native-runtime")
            .appendingPathComponent(NativeRuntimeBundle.entryFileName)
    }

    private var bundledNativeRuntimeEntryURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent(NativeRuntimeBundle.resourceDirectory)
            .appendingPathComponent(NativeRuntimeBundle.entryFileName)
    }

    private var bundledRuntimeConfigDirectoryURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent(NativeRuntimeBundle.configResourceDirectory)
    }

    private var bundledClaudeSdkCliURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent(NativeRuntimeBundle.sdkCliResourceDirectory)
            .appendingPathComponent(NativeRuntimeBundle.sdkCliFileName)
    }

    private var developmentClaudeSdkCliURL: URL {
        agentRuntimeRootURL
            .appendingPathComponent("node_modules")
            .appendingPathComponent("@anthropic-ai")
            .appendingPathComponent("claude-agent-sdk-darwin-arm64")
            .appendingPathComponent(NativeRuntimeBundle.sdkCliFileName)
    }

    private var stagedNativeRuntimeEntryURL: URL {
        applicationSupportRootURL
            .appendingPathComponent("runtime")
            .appendingPathComponent("native-runtime")
            .appendingPathComponent(NativeRuntimeBundle.entryFileName)
    }

    private var stagedClaudeSdkCliURL: URL {
        applicationSupportRootURL
            .appendingPathComponent("runtime")
            .appendingPathComponent("claude-sdk")
            .appendingPathComponent(NativeRuntimeBundle.sdkCliFileName)
    }

    private var applicationSupportRootURL: URL {
        applicationSupportBaseURL()
            .appendingPathComponent(Self.applicationSupportFolderName, isDirectory: true)
    }

    private var legacyApplicationSupportRootURL: URL {
        applicationSupportBaseURL()
            .appendingPathComponent(Self.legacyApplicationSupportFolderName, isDirectory: true)
    }

    private var safeRuntimeWorkingDirectoryURL: URL {
        applicationSupportRootURL
    }

    private var envExecutableURL: URL {
        URL(fileURLWithPath: "/usr/bin/env")
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        nativeRuntimeServer.stop()
    }

    func loadSnapshot() throws -> RuntimeSnapshotDTO {
        try decodeSnapshotStandalone(arguments: ["snapshot"])
    }

    func loadLiveSnapshot() throws -> RuntimeSnapshotDTO {
        try decodeSnapshotStandalone(arguments: ["snapshot"])
    }

    func createConversation() throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["create-conversation"])
    }

    func activateConversation(_ conversationID: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["set-active-conversation", conversationID])
    }

    func deleteConversation(_ conversationID: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["delete-conversation", conversationID])
    }

    func submitWorkspaceMessage(_ message: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["submit-workspace-message", message])
    }

    func submitRoutedWorkspaceMessage(_ message: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["submit-routed-workspace-message", message])
    }

    func submitQuickPrompt(_ prompt: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["submit-quick-prompt", prompt])
    }

    func completeHostActionTurn(_ completions: [WorkbenchHostActionCompletion]) throws -> RuntimeSnapshotDTO {
        let data = try encoder.encode(completions)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw RuntimeProcessError.runtimeInvocation(
                "Could not encode host action completions as UTF-8 JSON."
            )
        }
        return try decodeSnapshot(arguments: ["complete-host-action-turn", raw])
    }

    func completeExternalInvocation(_ completion: WorkbenchExternalInvocationCompletion) throws -> RuntimeSnapshotDTO {
        let raw = try Self.encodeExternalInvocationCompletion(completion)
        return try decodeSnapshot(arguments: ["codex-external-invocation-complete", raw])
    }

    func performTaskAction(taskID: String, action: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["perform-task-action", taskID, action])
    }

    func listAgentProfiles() throws -> [RuntimeAgentProfileDTO] {
        let data = try run(arguments: ["list-agent-profiles"])
        do {
            return try decoder.decode([RuntimeAgentProfileDTO].self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 output>"
            throw RuntimeProcessError.runtimeInvocation(
                "The agent runtime returned invalid JSON while listing agent profiles: \(raw)"
            )
        }
    }

    func setActiveAgentProfile(_ profileID: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["set-active-agent-profile", profileID])
    }

    func installAgentPack(at packPath: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["install-agent-pack", packPath])
    }

    func reloadAgentProfile(_ profileID: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["reload-agent-profile", profileID])
    }

    func deleteAgentProfile(_ profileID: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["delete-agent-profile", profileID])
    }

    func addSystemSkillSource(at sourcePath: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["add-system-skill-source", sourcePath])
    }

    func removeSystemSkillSource(_ sourceID: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["remove-system-skill-source", sourceID])
    }

    func addPersonaSkillSource(profileID: String, sourcePath: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["add-persona-skill-source", profileID, sourcePath])
    }

    func removePersonaSkillSource(profileID: String, sourceID: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["remove-persona-skill-source", profileID, sourceID])
    }

    func deleteTerminalAccessRule(_ ruleID: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["delete-terminal-access-rule", ruleID])
    }

    func setHighestAuthorizationEnabled(_ enabled: Bool) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["set-highest-authorization", enabled ? "true" : "false"])
    }

    func loadChatRoutingSettings() throws -> ChatRoutingSettings {
        let data = try run(arguments: ["get-chat-routing-settings"])
        do {
            return try decoder.decode(ChatRoutingSettings.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw RuntimeProcessError.runtimeInvocation(
                "The agent runtime returned invalid JSON while loading chat routing settings: \(raw)"
            )
        }
    }

    func loadXenodiaMediaBackend() throws -> XenodiaMediaBackend {
        let data = try run(arguments: ["get-xenodia-media-backend"])
        do {
            return try XenodiaMediaBackend.decodeRuntimePayload(data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw RuntimeProcessError.runtimeInvocation(
                "The agent runtime returned invalid JSON while loading the Xenodia media channel: \(Self.redactSensitiveJSON(raw))"
            )
        }
    }

    func saveChatRoutingSettings(_ settings: ChatRoutingSettings) throws -> RuntimeSnapshotDTO {
        let data = try encoder.encode(settings)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw RuntimeProcessError.runtimeInvocation(
                "Could not encode chat routing settings as UTF-8 JSON."
            )
        }
        return try decodeSnapshot(arguments: ["save-chat-routing-settings", raw])
    }

    func projectRuntimeRun(_ runID: String) throws -> RuntimeRunProjectionDTO {
        let data = try run(arguments: ["project-runtime-run", runID])
        do {
            return try decoder.decode(RuntimeRunProjectionDTO.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw RuntimeProcessError.runtimeInvocation(
                "The agent runtime returned invalid JSON while projecting run \(runID): \(raw)"
            )
        }
    }

    func classifyRuntimeRunWait(_ runID: String) throws -> RuntimeRunWaitClassificationDTO {
        let data = try run(arguments: ["classify-runtime-run-wait", runID])
        do {
            return try decoder.decode(RuntimeRunWaitClassificationDTO.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw RuntimeProcessError.runtimeInvocation(
                "The agent runtime returned invalid JSON while classifying run \(runID): \(raw)"
            )
        }
    }

    /// Serialises `invocation` into the tagged JSON the backend expects and
    /// returns the decoded `WorkbenchToolOutcome`. This is synchronous here;
    /// callers on the Swift side should hop via `runOffMainThread`.
    func invokeTool(_ invocation: ToolInvocation) throws -> WorkbenchToolOutcome {
        let requestJSON = try Self.encodeInvocation(invocation)
        let data = try run(arguments: ["invoke-tool", requestJSON])
        return try Self.decodeOutcome(from: data)
    }

    /// Exposed for tests — turns a Swift `ToolInvocation` into the JSON string
    /// the runtime's `invoke-tool` subcommand consumes.
    static func encodeInvocation(_ invocation: ToolInvocation) throws -> String {
        var object: [String: Any] = [
            "tool_id": invocation.toolID,
            "arguments": WorkbenchToolArgumentCodec.encode(invocation.arguments),
        ]
        if let token = invocation.approvalToken, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object["approval_token"] = token
        }
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let json = String(data: payload, encoding: .utf8) else {
            throw RuntimeProcessError.runtimeInvocation(
                "failed to encode tool invocation payload as UTF-8"
            )
        }
        return json
    }

    static func encodeExternalInvocationCompletion(
        _ completion: WorkbenchExternalInvocationCompletion
    ) throws -> String {
        var object: [String: Any] = [
            "external_invocation_id": completion.externalInvocationID,
            "status": completion.status.rawValue,
        ]
        if let resultJSON = completion.resultJSON,
           let data = resultJSON.data(using: .utf8),
           let result = try? JSONSerialization.jsonObject(with: data) {
            object["result"] = result
        }
        if let code = completion.code {
            object["code"] = code
        }
        if let message = completion.message {
            object["message"] = message
        }
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let json = String(data: payload, encoding: .utf8) else {
            throw RuntimeProcessError.runtimeInvocation(
                "failed to encode external invocation completion payload as UTF-8"
            )
        }
        return json
    }

    /// Exposed for tests — decodes a `WorkbenchToolOutcome` from the tagged
    /// JSON the runtime returns.
    static func decodeOutcome(from data: Data) throws -> WorkbenchToolOutcome {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 output>"
            throw RuntimeProcessError.runtimeInvocation(
                "tool outcome was not valid JSON: \(raw)"
            )
        }
        guard let dict = object as? [String: Any], let kind = dict["kind"] as? String else {
            throw RuntimeProcessError.runtimeInvocation(
                "tool outcome missing `kind` field"
            )
        }
        let toolID = (dict["tool_id"] as? String) ?? ""
        switch kind {
        case "completed":
            let payload = dict["payload"] as? [String: Any] ?? [:]
            return .completed(toolID: toolID, payload: payload)
        case "needs_approval":
            let blastRadiusRaw = (dict["blast_radius"] as? String) ?? "external"
            let blastRadius = WorkbenchToolBlastRadius(rawValue: blastRadiusRaw) ?? .external
            let prompt = (dict["prompt"] as? String) ?? "This tool requires your approval."
            return .needsApproval(toolID: toolID, blastRadius: blastRadius, prompt: prompt)
        case "denied":
            let reason = (dict["reason"] as? String) ?? "Denied by the active persona."
            return .denied(toolID: toolID, reason: reason)
        case "error":
            let code = (dict["code"] as? String) ?? "tool.error"
            let message = (dict["message"] as? String) ?? "Unknown tool error."
            return .error(toolID: toolID, code: code, message: message)
        default:
            return .error(
                toolID: toolID,
                code: "tool.outcome_unknown",
                message: "Unrecognised tool outcome kind: \(kind)"
            )
        }
    }

    private func decodeSnapshot(arguments: [String]) throws -> RuntimeSnapshotDTO {
        let data = try run(arguments: arguments)
        do {
            let snapshot = try decoder.decode(RuntimeSnapshotDTO.self, from: data)
            recycleStatefulServerIfTurnClosed(arguments: arguments, snapshot: snapshot)
            return snapshot
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 output>"
            throw RuntimeProcessError.runtimeInvocation(
                "The agent runtime returned invalid JSON: \(raw)"
            )
        }
    }

    private func decodeSnapshotStandalone(arguments: [String]) throws -> RuntimeSnapshotDTO {
        let data = try runStandalone(arguments: arguments, timeout: Self.timeout(for: arguments.first))
        do {
            return try decoder.decode(RuntimeSnapshotDTO.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 output>"
            throw RuntimeProcessError.runtimeInvocation(
                "The agent runtime returned invalid JSON: \(raw)"
            )
        }
    }

    private func recycleStatefulServerIfTurnClosed(
        arguments: [String],
        snapshot: RuntimeSnapshotDTO
    ) {
        guard let command = arguments.first,
              Self.statefulRuntimeCommands.contains(command),
              command != "invoke-tool" else {
            return
        }
        guard snapshot.lastRunState?.resumable == false,
              snapshot.hostActionIntents?.isEmpty != false else {
            return
        }
        nativeRuntimeServer.stop()
    }

    private func run(arguments: [String]) throws -> Data {
        if ProcessInfo.processInfo.environment["GEEAGENT_DISABLE_NATIVE_BRIDGE_SERVER"] != "1",
           let command = arguments.first,
           Self.statefulRuntimeCommands.contains(command) {
            return try runThroughServer(arguments: arguments)
        }

        return try runStandalone(arguments: arguments, timeout: Self.timeout(for: arguments.first))
    }

    private func runStandalone(arguments: [String], timeout: TimeInterval?) throws -> Data {
        let launch = try nativeRuntimeLaunch(arguments: arguments)
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.currentDirectoryURL
        process.environment = launch.environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw RuntimeProcessError.runtimeUnavailable(
                "Failed to launch the runtime command process: \(error.localizedDescription)"
            )
        }

        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        let output = captureOutput(
            from: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            timeout: timeout
        )

        guard !output.timedOut else {
            throw RuntimeProcessError.runtimeInvocation(
                "The agent runtime did not finish within \(Int(timeout ?? 0)) seconds. GeeAgent stopped this request so Quick Input would not stay loading forever."
            )
        }

        guard process.terminationStatus == 0 else {
            let stderr = String(data: output.stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RuntimeProcessError.runtimeInvocation(
                stderr?.isEmpty == false
                    ? stderr!
                    : "The agent runtime exited with status \(process.terminationStatus)."
            )
        }

        return output.stdout
    }

    private func runThroughServer(arguments: [String]) throws -> Data {
        guard let command = arguments.first else {
            throw RuntimeProcessError.runtimeInvocation("missing runtime command")
        }
        return try nativeRuntimeServer.run(
            command: command,
            args: Array(arguments.dropFirst()),
            launch: try nativeRuntimeLaunch(arguments: ["serve"]),
            timeout: Self.timeout(for: command)
        )
    }

    private static func timeout(for command: String?) -> TimeInterval {
        switch command ?? "" {
        case "submit-quick-prompt":
            75
        case "complete-host-action-turn":
            150
        case "submit-workspace-message", "submit-routed-workspace-message", "perform-task-action":
            150
        default:
            60
        }
    }

    private static let statefulRuntimeCommands: Set<String> = [
        "submit-workspace-message",
        "submit-routed-workspace-message",
        "submit-quick-prompt",
        "perform-task-action",
        "complete-host-action-turn",
        "invoke-tool",
    ]

    private func nativeRuntimeLaunch(arguments: [String]) throws -> RuntimeCommandLaunch {
        guard !arguments.isEmpty else {
            throw RuntimeProcessError.runtimeInvocation("missing runtime command")
        }
        try migrateLegacyRuntimeSupportIfNeeded()
        try verifyNativeRuntimeLauncher()
        let entryURL = try prepareNativeRuntimeEntry()
        let claudeSdkCliURL = try prepareClaudeSdkCli()
        return RuntimeCommandLaunch(
            executableURL: envExecutableURL,
            arguments: ["node", entryURL.path] + arguments + ["--config-dir", applicationSupportRootURL.path],
            currentDirectoryURL: safeRuntimeWorkingDirectoryURL,
            fingerprintURL: entryURL,
            environment: nativeRuntimeEnvironment(claudeSdkCliURL: claudeSdkCliURL)
        )
    }

    private func discoverRepoRoot(startingAt startURL: URL) -> URL? {
        var candidate = startURL.standardizedFileURL
        for _ in 0..<14 {
            let runtimeRoot = candidate
                .appendingPathComponent("apps", isDirectory: true)
                .appendingPathComponent("agent-runtime", isDirectory: true)
            let configRoot = candidate.appendingPathComponent("config", isDirectory: true)
            var isRuntimeDirectory: ObjCBool = false
            var isConfigDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: runtimeRoot.path, isDirectory: &isRuntimeDirectory),
               isRuntimeDirectory.boolValue,
               fileManager.fileExists(atPath: configRoot.path, isDirectory: &isConfigDirectory),
               isConfigDirectory.boolValue {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                break
            }
            candidate = parent
        }
        return nil
    }

    private func applicationSupportBaseURL() -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
    }

    private func migrateLegacyRuntimeSupportIfNeeded() throws {
        guard fileManager.fileExists(atPath: legacyApplicationSupportRootURL.path) else {
            try fileManager.createDirectory(
                at: applicationSupportRootURL,
                withIntermediateDirectories: true
            )
            try ensureDefaultRuntimeConfigFilesIfNeeded()
            return
        }

        try fileManager.createDirectory(
            at: applicationSupportRootURL,
            withIntermediateDirectories: true
        )

        for relativePath in legacyRuntimeSupportMigrationPaths {
            let sourceURL = legacyApplicationSupportRootURL.appendingPathComponent(relativePath)
            let targetURL = applicationSupportRootURL.appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: sourceURL.path),
                  !fileManager.fileExists(atPath: targetURL.path) else {
                continue
            }
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }
        try migrateLegacyRuntimeStoreIfNeeded()
        try ensureDefaultRuntimeConfigFilesIfNeeded()
    }

    private var legacyRuntimeSupportMigrationPaths: [String] {
        [
            "chat-runtime-secrets.toml",
            "model-routing.toml",
            "runtime-security.json",
            "runtime-skill-sources.json",
            "terminal-access.json",
            "agents",
        ]
    }

    private var defaultRuntimeConfigMigrationPaths: [String] {
        [
            NativeRuntimeBundle.chatRuntimeConfigFileName,
            NativeRuntimeBundle.modelRoutingConfigFileName,
        ]
    }

    private func ensureDefaultRuntimeConfigFilesIfNeeded() throws {
        for fileName in defaultRuntimeConfigMigrationPaths {
            let targetURL = applicationSupportRootURL.appendingPathComponent(fileName)
            guard !fileManager.fileExists(atPath: targetURL.path),
                  let text = defaultRuntimeConfigText(fileName: fileName) else {
                continue
            }
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: targetURL, atomically: true, encoding: .utf8)
        }
    }

    private func migrateLegacyRuntimeStoreIfNeeded() throws {
        let relativePath = "runtime-store.json"
        let sourceURL = legacyApplicationSupportRootURL.appendingPathComponent(relativePath)
        let targetURL = applicationSupportRootURL.appendingPathComponent(relativePath)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }
        if !fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.copyItem(at: sourceURL, to: targetURL)
            return
        }
        guard shouldReplaceBrokenRuntimeStore(targetURL) else {
            return
        }

        let backupURL = applicationSupportRootURL
            .appendingPathComponent("runtime-store.json.pre-geeagent-migration", isDirectory: false)
        if !fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.copyItem(at: targetURL, to: backupURL)
        }
        let legacyData = try Data(contentsOf: sourceURL)
        try legacyData.write(to: targetURL, options: [.atomic])
    }

    private func shouldReplaceBrokenRuntimeStore(_ storeURL: URL) -> Bool {
        guard let text = try? String(contentsOf: storeURL, encoding: .utf8) else {
            return false
        }
        return text.contains("/apps/config/chat-runtime.toml")
            || text.contains("Application Support/config/chat-runtime.toml")
    }

    private func verifyNativeRuntimeLauncher() throws {
        guard fileManager.isExecutableFile(atPath: envExecutableURL.path) else {
            throw RuntimeProcessError.runtimeUnavailable(
                "Could not find the system environment launcher at \(envExecutableURL.path)."
            )
        }
    }

    private func prepareNativeRuntimeEntry() throws -> URL {
        try stageRuntimeFile(
            sourceURL: nativeRuntimeSourceEntryURL(),
            targetURL: stagedNativeRuntimeEntryURL,
            description: "TypeScript native runtime",
            makeExecutable: false
        )
    }

    private func prepareClaudeSdkCli() throws -> URL {
        try stageRuntimeFile(
            sourceURL: claudeSdkCliSourceURL(),
            targetURL: stagedClaudeSdkCliURL,
            description: "SDK CLI",
            makeExecutable: true
        )
    }

    private func stageRuntimeFile(
        sourceURL: URL,
        targetURL: URL,
        description: String,
        makeExecutable: Bool
    ) throws -> URL {
        let targetDirectoryURL = targetURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: targetDirectoryURL,
                withIntermediateDirectories: true
            )
            if try nativeRuntimeStageNeedsUpdate(sourceURL: sourceURL, targetURL: targetURL) {
                let data = try Data(contentsOf: sourceURL)
                try data.write(to: targetURL, options: [.atomic])
            }
            if makeExecutable {
                try fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: Int16(0o755))],
                    ofItemAtPath: targetURL.path
                )
            }
            return targetURL
        } catch {
            throw RuntimeProcessError.runtimeUnavailable(
                "Could not stage the \(description) at \(targetURL.path): \(error.localizedDescription)"
            )
        }
    }

    private func nativeRuntimeSourceEntryURL() throws -> URL {
        if let bundledNativeRuntimeEntryURL,
           fileManager.fileExists(atPath: bundledNativeRuntimeEntryURL.path) {
            return bundledNativeRuntimeEntryURL
        }
        if fileManager.fileExists(atPath: developmentNativeRuntimeEntryURL.path) {
            return developmentNativeRuntimeEntryURL
        }
        throw RuntimeProcessError.runtimeUnavailable(
            "Could not find the built TypeScript native runtime entry at \(developmentNativeRuntimeEntryURL.path). Run `npm run build --prefix apps/agent-runtime` before starting GeeAgent."
        )
    }

    private func claudeSdkCliSourceURL() throws -> URL {
        if let bundledClaudeSdkCliURL,
           fileManager.fileExists(atPath: bundledClaudeSdkCliURL.path) {
            return bundledClaudeSdkCliURL
        }
        if fileManager.fileExists(atPath: developmentClaudeSdkCliURL.path) {
            return developmentClaudeSdkCliURL
        }
        throw RuntimeProcessError.runtimeUnavailable(
            "Could not find the SDK CLI at \(developmentClaudeSdkCliURL.path). Run `npm install --prefix apps/agent-runtime` before starting GeeAgent."
        )
    }

    private func nativeRuntimeStageNeedsUpdate(sourceURL: URL, targetURL: URL) throws -> Bool {
        guard fileManager.fileExists(atPath: targetURL.path) else {
            return true
        }
        let sourceAttributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        let targetAttributes = try fileManager.attributesOfItem(atPath: targetURL.path)
        let sourceSize = sourceAttributes[.size] as? UInt64
        let targetSize = targetAttributes[.size] as? UInt64
        if sourceSize != targetSize {
            return true
        }
        guard let sourceDate = sourceAttributes[.modificationDate] as? Date,
              let targetDate = targetAttributes[.modificationDate] as? Date else {
            return false
        }
        return sourceDate > targetDate
    }

    private func nativeRuntimeEnvironment(claudeSdkCliURL: URL) -> [String: String] {
        let hostEnvironment = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]
        environment["HOME"] = hostEnvironment["HOME"] ?? NSHomeDirectory()
        environment["USER"] = hostEnvironment["USER"] ?? NSUserName()
        environment["LOGNAME"] = hostEnvironment["LOGNAME"] ?? NSUserName()
        environment["SHELL"] = hostEnvironment["SHELL"] ?? "/bin/zsh"
        environment["TMPDIR"] = hostEnvironment["TMPDIR"] ?? NSTemporaryDirectory()
        environment["LANG"] = hostEnvironment["LANG"] ?? "en_US.UTF-8"
        environment["PWD"] = safeRuntimeWorkingDirectoryURL.path
        environment["GEEAGENT_CONFIG_DIR"] = hostEnvironment["GEEAGENT_CONFIG_DIR"] ?? applicationSupportRootURL.path
        environment["GEEAGENT_RUNTIME_PROJECT_PATH"] = hostEnvironment["GEEAGENT_RUNTIME_PROJECT_PATH"] ?? applicationSupportRootURL.path
        environment["GEEAGENT_CLAUDE_CODE_EXECUTABLE"] = hostEnvironment["GEEAGENT_CLAUDE_CODE_EXECUTABLE"] ?? claudeSdkCliURL.path
        environment["GEEAGENT_REPO_ROOT"] = hostEnvironment["GEEAGENT_REPO_ROOT"] ?? repoRootURL.path
        environment["GEEAGENT_GATEWAY_TRACE_PATH"] =
            hostEnvironment["GEEAGENT_GATEWAY_TRACE_PATH"] ??
            applicationSupportRootURL.appendingPathComponent("runtime-gateway-trace.jsonl").path
        environment["GEEAGENT_DEFAULT_MODEL_ROUTING_TOML"] =
            hostEnvironment["GEEAGENT_DEFAULT_MODEL_ROUTING_TOML"] ??
            defaultRuntimeConfigText(fileName: NativeRuntimeBundle.modelRoutingConfigFileName)
        environment["GEEAGENT_DEFAULT_CHAT_RUNTIME_TOML"] =
            hostEnvironment["GEEAGENT_DEFAULT_CHAT_RUNTIME_TOML"] ??
            defaultRuntimeConfigText(fileName: NativeRuntimeBundle.chatRuntimeConfigFileName)
        if let idleTimeout = hostEnvironment["GEEAGENT_SDK_EVENT_IDLE_TIMEOUT_MS"] {
            environment["GEEAGENT_SDK_EVENT_IDLE_TIMEOUT_MS"] = idleTimeout
        }
        let commonPaths = [
            hostEnvironment["PATH"],
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        environment["PATH"] = commonPaths.compactMap(\.self).joined(separator: ":")
        return environment
    }

    private func defaultRuntimeConfigText(fileName: String) -> String? {
        let bundledURL = bundledRuntimeConfigDirectoryURL?.appendingPathComponent(fileName)
        let developmentURL = repoRootURL.appendingPathComponent("config").appendingPathComponent(fileName)
        for url in [bundledURL, developmentURL].compactMap(\.self) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    private func captureOutput(
        from process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        timeout: TimeInterval? = nil
    ) -> (stdout: Data, stderr: Data, timedOut: Bool) {
        let group = DispatchGroup()
        let processGroup = DispatchGroup()
        let stdoutCollector = ProcessPipeCollector()
        let stderrCollector = ProcessPipeCollector()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            stdoutCollector.store(data)
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            stderrCollector.store(data)
            group.leave()
        }

        processGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            processGroup.leave()
        }

        var timedOut = false
        if let timeout {
            let deadline = DispatchTime.now() + timeout
            if processGroup.wait(timeout: deadline) == .timedOut {
                timedOut = true
                process.terminate()
                if processGroup.wait(timeout: .now() + 2) == .timedOut {
                    stdoutPipe.fileHandleForReading.closeFile()
                    stderrPipe.fileHandleForReading.closeFile()
                }
            }
        } else {
            processGroup.wait()
        }
        group.wait()

        return (stdoutCollector.snapshot(), stderrCollector.snapshot(), timedOut)
    }
}

final class NativeWorkbenchRuntimeClient: WorkbenchRuntimeClient, @unchecked Sendable {
    private let runtime = AgentRuntimeProcess()
    private let rawSnapshotLock = NSLock()
    private var rawSnapshot: RuntimeSnapshotDTO?

    static func projectSnapshotForTesting(from data: Data) throws -> WorkbenchSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snapshot = try decoder.decode(RuntimeSnapshotDTO.self, from: data)
        return NativeWorkbenchRuntimeClient().map(snapshot)
    }

    func shutdown() {
        runtime.shutdown()
    }

    func loadSnapshot() -> WorkbenchSnapshot {
        do {
            let snapshot = try runtime.loadSnapshot()
            storeRawSnapshot(snapshot)
            return map(snapshot)
        } catch {
            return unavailableSnapshot(detail: error.localizedDescription)
        }
    }

    func loadLiveSnapshot() -> WorkbenchSnapshot {
        do {
            let snapshot = try runtime.loadLiveSnapshot()
            storeRawSnapshot(snapshot)
            return map(snapshot)
        } catch {
            if let rawSnapshot = currentRawSnapshot() {
                return map(rawSnapshot)
            }
            return unavailableSnapshot(detail: error.localizedDescription)
        }
    }

    func createConversation(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.createConversation()
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func activateConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let snapshot = try await runOffMainThread {
            try self.runtime.activateConversation(conversationID)
        }
        storeRawSnapshot(snapshot)
        return map(snapshot)
    }

    func deleteConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.deleteConversation(conversationID)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func sendMessage(
        _ message: String,
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        allowAutoRouting: Bool
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot

        var latestSnapshot = currentRawSnapshot()
        if latestSnapshot?.activeConversation.conversationId != conversationID {
            let activatedSnapshot = try await runOffMainThread {
                try self.runtime.activateConversation(conversationID)
            }
            storeRawSnapshot(activatedSnapshot)
            latestSnapshot = activatedSnapshot
        }

        let routeSnapshot = latestSnapshot
        let nextSnapshot: RuntimeSnapshotDTO = try await runOffMainThread {
            if allowAutoRouting,
               self.shouldUseWorkspaceAutoRouting(
                message: message,
                conversationID: conversationID,
                rawSnapshot: routeSnapshot
            ) {
                return try self.runtime.submitRoutedWorkspaceMessage(message)
            }

            return try self.runtime.submitWorkspaceMessage(message)
        }

        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func performTaskAction(
        _ action: WorkbenchTaskAction,
        in snapshot: WorkbenchSnapshot,
        taskID: WorkbenchTaskRecord.ID
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let actionName: String
        switch action {
        case .allowOnce:
            actionName = "allow_once"
        case .alwaysAllow:
            actionName = "always_allow"
        case .deny:
            actionName = "deny"
        case .retry:
            actionName = "retry"
        case .complete:
            throw RuntimeProcessError.unsupported(
                "Live task completion is not wired yet. Use chat to continue or retry the task."
            )
        }

        let nextSnapshot = try await runOffMainThread {
            try self.runtime.performTaskAction(taskID: taskID, action: actionName)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func setActiveAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.setActiveAgentProfile(profileID)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func submitQuickPrompt(
        _ prompt: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snapshot }
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.submitQuickPrompt(trimmed)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func completeHostActionTurn(
        _ completions: [WorkbenchHostActionCompletion],
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        guard !completions.isEmpty else { return snapshot }
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.completeHostActionTurn(completions)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func completeExternalInvocation(
        _ completion: WorkbenchExternalInvocationCompletion,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.completeExternalInvocation(completion)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func installAgentPack(
        at packPath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let trimmed = packPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snapshot }
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.installAgentPack(at: trimmed)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func reloadAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.reloadAgentProfile(profileID)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func deleteAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.deleteAgentProfile(profileID)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func addSystemSkillSource(
        at sourcePath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let trimmed = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snapshot }
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.addSystemSkillSource(at: trimmed)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func removeSystemSkillSource(
        _ sourceID: SkillSourceRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.removeSystemSkillSource(sourceID)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func addPersonaSkillSource(
        profileID: AgentProfileRecord.ID,
        sourcePath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let trimmed = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snapshot }
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.addPersonaSkillSource(profileID: profileID, sourcePath: trimmed)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func removePersonaSkillSource(
        profileID: AgentProfileRecord.ID,
        sourceID: SkillSourceRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.removePersonaSkillSource(profileID: profileID, sourceID: sourceID)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func deleteTerminalPermissionRule(
        _ ruleID: TerminalPermissionRuleRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.deleteTerminalAccessRule(ruleID)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func setHighestAuthorizationEnabled(
        _ enabled: Bool,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.setHighestAuthorizationEnabled(enabled)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func loadChatRoutingSettings() async throws -> ChatRoutingSettings {
        try await runOffMainThread {
            try self.runtime.loadChatRoutingSettings()
        }
    }

    func loadXenodiaMediaBackend() throws -> XenodiaMediaBackend {
        try runtime.loadXenodiaMediaBackend()
    }

    func saveChatRoutingSettings(
        _ settings: ChatRoutingSettings,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.runtime.saveChatRoutingSettings(settings)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func projectRuntimeRun(_ runID: String) async throws -> WorkbenchRuntimeRunProjection {
        let projection = try await runOffMainThread {
            try self.runtime.projectRuntimeRun(runID)
        }
        return mapRuntimeRunProjection(projection)
    }

    func classifyRuntimeRunWait(_ runID: String) async throws -> WorkbenchRuntimeRunWaitClassification {
        let classification = try await runOffMainThread {
            try self.runtime.classifyRuntimeRunWait(runID)
        }
        return mapRuntimeRunWaitClassification(classification)
    }

    func invokeTool(_ invocation: ToolInvocation) async throws -> WorkbenchToolOutcome {
        try await runOffMainThread {
            try self.runtime.invokeTool(invocation)
        }
    }

    private func currentRawSnapshot() -> RuntimeSnapshotDTO? {
        rawSnapshotLock.lock()
        defer { rawSnapshotLock.unlock() }
        return rawSnapshot
    }

    private func storeRawSnapshot(_ snapshot: RuntimeSnapshotDTO) {
        rawSnapshotLock.lock()
        rawSnapshot = snapshot
        rawSnapshotLock.unlock()
    }

    private func runOffMainThread<T>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func shouldUseWorkspaceAutoRouting(
        message: String,
        conversationID: String,
        rawSnapshot: RuntimeSnapshotDTO?
    ) -> Bool {
        guard let rawSnapshot else {
            return false
        }

        guard conversationID == rawSnapshot.activeConversation.conversationId else {
            return false
        }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return false
        }

        let userMessageCount = rawSnapshot.activeConversation.messages.filter { $0.role == "user" }.count
        let hasBootstrapShape =
            rawSnapshot.activeConversation.title == "New Conversation" &&
            userMessageCount == 0 &&
            rawSnapshot.activeConversation.messages.count <= 1

        return hasBootstrapShape
    }

    private func map(_ snapshot: RuntimeSnapshotDTO) -> WorkbenchSnapshot {
        let tasks = snapshot.tasks.map { task in
            let moduleRun = snapshot.moduleRuns.first(where: { $0.moduleRun.taskId == task.taskId })
            return WorkbenchTaskRecord(
                id: task.taskId,
                title: task.title,
                ownerLabel: "GeeAgent",
                appName: moduleName(for: task.taskId, moduleRuns: snapshot.moduleRuns),
                status: workbenchTaskStatus(task.status),
                priorityLabel: importanceLabel(task.importanceLevel),
                dueLabel: dueLabel(task.status),
                updatedLabel: updatedLabel(for: task.taskId, moduleRuns: snapshot.moduleRuns),
                summary: task.summary,
                artifactCount: task.artifactCount,
                approvalRequestID: task.approvalRequestId,
                moduleRunID: moduleRun?.moduleRun.moduleRunId,
                canRetry: moduleRun?.recoverability?.retrySafe ?? false
            )
        }

        let openApprovals = snapshot.approvalRequests.filter { $0.status == "open" }
        let automations = (snapshot.automations ?? []).map { automation in
            let schedule = automationScheduleLabel(automation)
            return AutomationRecord(
                id: automation.automationId,
                name: automation.name,
                scopeLabel: humanize(automation.triggerKind),
                scheduleLabel: schedule,
                nextRunLabel: schedule,
                lastRunLabel: "Latest runtime snapshot",
                status: automationStatus(automation.status),
                summary: summarize(automation.goalPrompt, limit: 120)
            )
        }

        let runtimeApps: [InstalledAppRecord] = snapshot.workspaceRuntime?.apps.map { app in
            let mode = ModuleDisplayMode(rawValue: app.displayMode ?? ModuleDisplayMode.inNav.rawValue) ?? .inNav
            return InstalledAppRecord(
                id: app.appId,
                name: app.displayName,
                categoryLabel: "Workspace app",
                versionLabel: "Registry",
                healthLabel: app.installState == "installed" ? "Ready" : humanize(app.installState),
                installState: .installed,
                summary: "\(app.displayName) is available through the runtime registry.",
                displayMode: mode
            )
        } ?? []
        let installedApps = GearHost.mergedWithGears(runtimeApps)

        let agentSkins = snapshot.workspaceRuntime?.agentSkins.map { skin in
            AgentSkinRecord(
                id: skin.skinId,
                name: skin.displayName,
                toneLabel: "Default",
                activationLabel: "Available",
                summary: "\(skin.displayName) is exposed from the runtime skin catalog."
            )
        } ?? []

        let summaries = snapshot.conversations.isEmpty
            ? [
                RuntimeConversationSummaryDTO(
                    conversationId: snapshot.activeConversation.conversationId,
                    title: snapshot.activeConversation.title,
                    status: snapshot.activeConversation.status,
                    tags: snapshot.activeConversation.tags,
                    lastMessagePreview: snapshot.activeConversation.messages.last?.content ?? "Fresh conversation.",
                    lastTimestamp: snapshot.activeConversation.messages.last?.timestamp ?? "Now",
                    isActive: true
                )
            ]
            : snapshot.conversations

        let linkedTaskTitle = snapshot.workspaceFocus.taskId.flatMap { taskID in
            tasks.first(where: { $0.id == taskID })?.title
        }
        let activeConversationID = snapshot.activeConversation.conversationId
        let activeConversationMessages = projectConversationMessages(from: snapshot)
        let activeRuntimeRunSummary = runtimeRunSummary(
            conversationID: activeConversationID,
            executionSessions: snapshot.executionSessions ?? [],
            transcriptEvents: snapshot.transcriptEvents ?? []
        )
        let conversations = summaries.map { summary in
            ConversationThread(
                id: summary.conversationId,
                title: summary.title,
                participantLabel: summary.isActive
                    ? activeParticipantLabel(chatRuntime: snapshot.chatRuntime)
                    : "GeeAgent",
                previewText: summary.lastMessagePreview,
                statusLabel: humanize(summary.status),
                lastActivityLabel: formattedConversationTimestamp(summary.lastTimestamp),
                unreadCount: 0,
                linkedTaskTitle: summary.conversationId == activeConversationID ? linkedTaskTitle : nil,
                linkedAppName: summary.conversationId == activeConversationID
                    ? moduleName(for: snapshot.workspaceFocus.taskId, moduleRuns: snapshot.moduleRuns)
                    : nil,
                messages: summary.conversationId == activeConversationID
                    ? activeConversationMessages
                    : [],
                tags: summary.tags ?? [],
                isActive: summary.isActive,
                runtimeRunSummary: summary.conversationId == activeConversationID
                    ? activeRuntimeRunSummary
                    : nil
            )
        }

        let settings = settingsPanes(from: snapshot)
        let homeItems = homeItems(
            openApprovals: openApprovals,
            tasks: tasks,
            automations: automations,
            installedApps: installedApps
        )

        let availableAgentProfiles = (snapshot.agentProfiles ?? []).map(mapAgentProfile)
        let activeAgentProfileID = snapshot.activeAgentProfile?.id ?? availableAgentProfiles.first?.id
        let terminalPermissionRules = (snapshot.terminalAccessRules ?? []).map(mapTerminalPermissionRule)

        return WorkbenchSnapshot(
            homeSummary: WorkbenchHomeSummary(
                openTasksCount: tasks.filter { $0.status != .completed }.count,
                approvalsCount: openApprovals.count,
                nextAutomationLabel: automations.first.map { "\($0.name) - \($0.scheduleLabel)" } ?? "No schedules",
                installedAppsCount: installedApps.count
            ),
            homeItems: homeItems,
            conversations: conversations,
            tasks: tasks,
            automations: automations,
            installedApps: installedApps,
            agentSkins: agentSkins,
            availableAgentProfiles: availableAgentProfiles,
            activeAgentProfileID: activeAgentProfileID,
            terminalPermissionRules: terminalPermissionRules,
            securityPreferences: WorkbenchSecurityPreferences(
                highestAuthorizationEnabled: snapshot.securityPreferences?.highestAuthorizationEnabled ?? false
            ),
            skillSources: mapSkillSources(snapshot.skillSources),
            settings: settings,
            preferredSection: WorkbenchSection(rawValue: snapshot.workspaceRuntime?.activeSection ?? "") ?? .home,
            runtimeStatus: runtimeStatus(from: snapshot.chatRuntime),
            interactionCapabilities: interactionCapabilities(from: snapshot.interactionCapabilities),
            quickInputHint: snapshot.quickInputHint,
            quickReply: snapshot.quickReply,
            contextBudget: contextBudget(from: snapshot.contextBudget),
            lastOutcome: requestOutcome(from: snapshot.lastRequestOutcome),
            hostActionIntents: hostActionIntents(from: snapshot.hostActionIntents),
            externalInvocations: externalInvocations(from: snapshot.externalInvocations)
        )
    }

    private func hostActionIntents(from dtos: [RuntimeHostActionIntentDTO]?) -> [WorkbenchHostActionIntent] {
        (dtos ?? []).map { dto in
            WorkbenchHostActionIntent(
                id: dto.hostActionId,
                toolID: dto.toolId,
                arguments: workbenchArguments(from: dto.arguments)
            )
        }
    }

    private func mapRuntimeRunProjection(_ dto: RuntimeRunProjectionDTO) -> WorkbenchRuntimeRunProjection {
        WorkbenchRuntimeRunProjection(
            runID: dto.runId,
            rowCount: dto.rowCount,
            artifactIDs: dto.artifactIds,
            artifactRefs: dto.artifactRefs.map(mapRuntimeRunArtifactRef),
            diagnostics: mapRuntimeRunDiagnostics(dto.diagnostics),
            rows: dto.rows.map(mapRuntimeRunProjectionRow)
        )
    }

    private func mapRuntimeRunProjectionRow(_ dto: RuntimeRunProjectionRowDTO) -> WorkbenchRuntimeRunProjectionRow {
        WorkbenchRuntimeRunProjectionRow(
            rowID: dto.rowId,
            runID: dto.runId,
            sequence: dto.sequence,
            eventID: dto.eventId,
            eventKind: dto.eventKind,
            projectionKind: dto.projectionKind,
            label: dto.label,
            status: dto.status,
            summary: dto.summary,
            stageID: dto.stageId,
            toolName: dto.toolName,
            projectionScope: dto.projectionScope,
            expandable: dto.expandable,
            artifactIDs: dto.artifactIds
        )
    }

    private func mapRuntimeRunArtifactRef(_ dto: RuntimeRunArtifactRefDTO) -> WorkbenchRuntimeRunArtifactRef {
        WorkbenchRuntimeRunArtifactRef(
            artifactID: dto.artifactId,
            kind: dto.kind,
            title: dto.title,
            path: dto.path,
            summary: dto.summary,
            sha256: dto.sha256,
            byteCount: dto.byteCount,
            tokenEstimate: dto.tokenEstimate,
            mimeType: dto.mimeType,
            sourceEventID: dto.sourceEventId,
            sourceEventSequence: dto.sourceEventSequence,
            sourceInvocationID: dto.sourceInvocationId,
            sourceToolName: dto.sourceToolName,
            sourceHostActionID: dto.sourceHostActionId
        )
    }

    private func mapRuntimeRunWaitClassification(
        _ dto: RuntimeRunWaitClassificationDTO
    ) -> WorkbenchRuntimeRunWaitClassification {
        WorkbenchRuntimeRunWaitClassification(
            runID: dto.runId,
            waitKind: dto.waitKind,
            status: dto.status,
            detail: dto.detail,
            evidence: WorkbenchRuntimeRunWaitEvidence(
                runID: dto.evidence.runId,
                lastEventKind: dto.evidence.lastEventKind,
                lastEventSequence: dto.evidence.lastEventSequence,
                lastToolUseID: dto.evidence.lastToolUseId,
                pendingToolUseID: dto.evidence.pendingToolUseId,
                pendingHostActionIDs: dto.evidence.pendingHostActionIds,
                pendingApprovalID: dto.evidence.pendingApprovalId,
                sdkSessionID: dto.evidence.sdkSessionId,
                gatewayRequestID: dto.evidence.gatewayRequestId,
                diagnostics: mapRuntimeRunDiagnostics(dto.evidence.diagnostics)
            )
        )
    }

    private func mapRuntimeRunDiagnostics(_ dto: RuntimeRunDiagnosticsDTO) -> WorkbenchRuntimeRunDiagnostics {
        WorkbenchRuntimeRunDiagnostics(
            duplicateEventIDs: dto.duplicateEventIds,
            missingParentEventIDs: dto.missingParentEventIds,
            missingSequenceNumbers: dto.missingSequenceNumbers,
            outOfOrderEventIDs: dto.outOfOrderEventIds
        )
    }

    private func externalInvocations(from dtos: [RuntimeExternalInvocationDTO]?) -> [WorkbenchExternalInvocation] {
        (dtos ?? []).compactMap { dto in
            guard let tool = WorkbenchExternalInvocationTool(rawValue: dto.tool),
                  let status = WorkbenchExternalInvocationStatus(rawValue: dto.status)
            else {
                return nil
            }
            return WorkbenchExternalInvocation(
                id: dto.externalInvocationId,
                tool: tool,
                status: status,
                gearID: dto.gearId,
                capabilityID: dto.capabilityId,
                surfaceID: dto.surfaceId,
                args: workbenchArguments(from: dto.args)
            )
        }
    }

    private func workbenchArguments(from value: RuntimeJSONValue?) -> [String: WorkbenchToolArgumentValue] {
        guard case let .object(object)? = value else {
            return [:]
        }
        return object.mapValues(workbenchArgumentValue)
    }

    private func workbenchArgumentValue(from value: RuntimeJSONValue) -> WorkbenchToolArgumentValue {
        switch value {
        case let .string(string):
            return .string(string)
        case let .int(int):
            return .int(int)
        case let .double(double):
            return .double(double)
        case let .bool(bool):
            return .bool(bool)
        case let .array(array):
            return .stringArray(array.compactMap { item in
                guard case let .string(string) = item else { return nil }
                return string
            })
        case let .object(object):
            return .object(object.mapValues(workbenchArgumentValue))
        case .null:
            return .null
        }
    }

    private func contextBudget(from dto: RuntimeContextBudgetDTO?) -> ContextBudgetRecord {
        guard let dto else {
            return .empty
        }

        return ContextBudgetRecord(
            maxTokens: dto.maxTokens,
            usedTokens: dto.usedTokens,
            reservedOutputTokens: dto.reservedOutputTokens,
            usageRatio: dto.usageRatio,
            estimateSource: dto.estimateSource,
            summaryState: ContextBudgetRecord.SummaryState(rawValue: dto.summaryState) ?? .watching,
            lastSummarizedAt: dto.lastSummarizedAt,
            nextSummaryAtRatio: dto.nextSummaryAtRatio,
            compactedMessagesCount: dto.compactedMessagesCount,
            projectionMode: dto.projectionMode ?? "unknown",
            rawHistoryTokens: dto.rawHistoryTokens ?? 0,
            projectedHistoryTokens: dto.rawHistoryTokens == nil ? 0 : dto.projectedHistoryTokens ?? dto.usedTokens,
            recentTokens: dto.recentTokens ?? 0,
            summaryTokens: dto.summaryTokens ?? 0,
            latestRequestTokens: dto.latestRequestTokens ?? 0
        )
    }

    private func mapTerminalPermissionRule(_ dto: RuntimeTerminalAccessRuleDTO) -> TerminalPermissionRuleRecord {
        TerminalPermissionRuleRecord(
            id: dto.ruleId,
            decision: TerminalPermissionRuleRecord.Decision(rawValue: dto.decision) ?? .deny,
            kind: humanize(dto.kind),
            label: dto.label,
            command: dto.command,
            cwd: dto.cwd,
            updatedAt: dto.updatedAt
        )
    }

    private func mapAgentProfile(_ dto: RuntimeAgentProfileDTO) -> AgentProfileRecord {
        let live2DPath = firstNonEmpty(dto.appearance.live2dBundlePath, dto.appearance.bundlePath)
        let videoPath = firstNonEmpty(dto.appearance.videoAssetPath, dto.appearance.kind == "video" ? dto.appearance.assetPath : nil)
        let imagePath = firstNonEmpty(dto.appearance.imageAssetPath, dto.appearance.kind == "static_image" ? dto.appearance.assetPath : nil)
        let appearance: AgentProfileAppearanceRecord
        if let live2DPath {
            appearance = .live2D(bundlePath: live2DPath)
        } else if let videoPath {
            appearance = .video(assetPath: videoPath)
        } else if let imagePath {
            appearance = .staticImage(assetPath: imagePath)
        } else {
            appearance = .abstract
        }
        let globalBackground = mapGlobalBackground(dto.appearance.globalBackground)
        let visualOptions = AgentProfileVisualOptionsRecord(
            live2DBundlePath: live2DPath,
            videoAssetPath: videoPath,
            imageAssetPath: imagePath
        )

        let source = AgentProfileSourceRecord(rawValue: dto.source) ?? .userCreated
        let skills = (dto.skills ?? []).map(mapSkillReference)
        let fileState = AgentProfileFileStateRecord(
            workspaceRootPath: dto.fileState?.workspaceRootPath,
            manifestPath: dto.fileState?.manifestPath,
            identityPromptPath: dto.fileState?.identityPromptPath,
            soulPath: dto.fileState?.soulPath,
            playbookPath: dto.fileState?.playbookPath,
            toolsContextPath: dto.fileState?.toolsContextPath,
            memorySeedPath: dto.fileState?.memorySeedPath,
            heartbeatPath: dto.fileState?.heartbeatPath,
            visualFiles: (dto.fileState?.visualFiles ?? []).map { AgentProfileFileEntryRecord(title: $0.title, path: $0.path) },
            supplementalFiles: (dto.fileState?.supplementalFiles ?? []).map { AgentProfileFileEntryRecord(title: $0.title, path: $0.path) },
            canReload: dto.fileState?.canReload ?? false,
            canDelete: dto.fileState?.canDelete ?? false
        )

        return AgentProfileRecord(
            id: dto.id,
            name: dto.name,
            tagline: dto.tagline,
            personalityPrompt: dto.personalityPrompt,
            appearance: appearance,
            globalBackground: globalBackground,
            visualOptions: visualOptions,
            skills: skills,
            allowedToolIDs: dto.allowedToolIds,
            source: source,
            version: dto.version,
            fileState: fileState
        )
    }

    private func mapSkillSources(_ dto: RuntimeSkillSourcesDTO?) -> SkillSourcesRecord {
        guard let dto else { return .empty }
        var personaSources: [String: [SkillSourceRecord]] = [:]
        for (profileID, sources) in dto.personaSources ?? [:] {
            personaSources[profileID] = sources.map(mapSkillSource)
        }
        return SkillSourcesRecord(
            systemSources: (dto.systemSources ?? []).map(mapSkillSource),
            personaSources: personaSources
        )
    }

    private func mapSkillSource(_ dto: RuntimeSkillSourceDTO) -> SkillSourceRecord {
        SkillSourceRecord(
            id: dto.id,
            path: dto.path,
            scope: dto.scope,
            profileID: dto.profileId,
            enabled: dto.enabled,
            addedAt: dto.addedAt,
            lastScannedAt: dto.lastScannedAt,
            status: dto.status,
            error: dto.error,
            skills: (dto.skills ?? []).map(mapSkillReference)
        )
    }

    private func mapSkillReference(_ ref: RuntimeAgentSkillRefDTO) -> AgentSkillReferenceRecord {
        AgentSkillReferenceRecord(
            id: ref.id,
            name: ref.name ?? humanize(ref.id),
            description: ref.description,
            path: ref.path,
            skillFilePath: ref.skillFilePath,
            sourceID: ref.sourceId,
            sourceScope: ref.sourceScope,
            sourcePath: ref.sourcePath,
            profileID: ref.profileId,
            status: ref.status,
            error: ref.error
        )
    }

    private func mapGlobalBackground(_ dto: RuntimeAgentProfileGlobalBackgroundDTO?) -> AgentProfileGlobalBackgroundRecord {
        guard let dto else { return .none }
        if let videoPath = firstNonEmpty(dto.videoAssetPath, dto.kind == "video" ? dto.assetPath : nil) {
            return .video(assetPath: videoPath)
        }
        if let imagePath = firstNonEmpty(dto.imageAssetPath, (dto.kind == "static_image" || dto.kind == "image") ? dto.assetPath : nil) {
            return .staticImage(assetPath: imagePath)
        }
        return .none
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func runtimeRunSummary(
        conversationID: String,
        executionSessions: [RuntimeExecutionSessionDTO],
        transcriptEvents: [RuntimeTranscriptEventDTO]
    ) -> ConversationRuntimeRunSummary? {
        let sessionIDs = Set(
            executionSessions
                .filter { $0.conversationId == conversationID }
                .map(\.sessionId)
        )
        guard !sessionIDs.isEmpty else {
            return nil
        }
        let runEvents = transcriptEvents
            .filter { event in
                guard sessionIDs.contains(event.sessionId),
                      let runID = event.runId?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !runID.isEmpty
                else {
                    return false
                }
                return true
            }
        guard let latestRunID = runEvents.last?.runId else {
            return nil
        }
        let latestRunEvents = runEvents.filter { $0.runId == latestRunID }
        let sequences = latestRunEvents.compactMap(\.sequence)
        return ConversationRuntimeRunSummary(
            runID: latestRunID,
            eventCount: latestRunEvents.count,
            firstSequence: sequences.min(),
            lastSequence: sequences.max(),
            lastEventKind: latestRunEvents.last.map(transcriptEventKind)
        )
    }

    private func transcriptEventKind(_ event: RuntimeTranscriptEventDTO) -> String {
        switch event.payload {
        case .userMessage:
            return "user_message"
        case .assistantMessage:
            return "assistant_message"
        case .assistantMessageDelta:
            return "assistant_message_delta"
        case .runPlanCreated:
            return "run_plan_created"
        case .runPlanUpdated:
            return "run_plan_updated"
        case .capabilityFocusLocked:
            return "capability_focus_locked"
        case .stageStarted:
            return "stage_started"
        case .stageConcluded:
            return "stage_concluded"
        case .toolInvocation:
            return "tool_invocation"
        case .toolResult:
            return "tool_result"
        case .sessionStateChanged:
            return "session_state_changed"
        }
    }

    private func projectConversationMessages(from snapshot: RuntimeSnapshotDTO) -> [ConversationMessage] {
        let rawTranscriptEvents = snapshot.transcriptEvents ?? []
        let rawExecutionSessions = snapshot.executionSessions ?? []
        guard
            let activeSessionID = rawExecutionSessions
                .first(where: { $0.conversationId == snapshot.activeConversation.conversationId })?
                .sessionId
        else {
            return snapshot.activeConversation.messages.map(mapConversationMessage)
        }

        let transcriptEvents = rawTranscriptEvents.filter { $0.sessionId == activeSessionID }
        guard !transcriptEvents.isEmpty else {
            return snapshot.activeConversation.messages.map(mapConversationMessage)
        }

        let transcriptMessageIDs = Set(transcriptEvents.compactMap(transcriptMessageID(for:)))
        var projectedMessages: [ConversationMessage] = []

        let approvalsByID = Dictionary(
            uniqueKeysWithValues: snapshot.approvalRequests.map { ($0.approvalRequestId, $0) }
        )

        for event in transcriptEvents {
            switch event.payload {
            case let .userMessage(messageId, content):
                projectedMessages.append(
                    ConversationMessage(
                        id: messageId,
                        role: .user,
                        kind: .chat,
                        content: content,
                        timestampLabel: formattedConversationTimestamp(event.createdAt)
                    )
                )
            case let .assistantMessage(messageId, content):
                upsertAssistantMessage(
                    messageId: messageId,
                    content: sanitizedAssistantContent(content),
                    timestampLabel: formattedConversationTimestamp(event.createdAt),
                    messages: &projectedMessages
                )
            case let .assistantMessageDelta(messageId, delta):
                appendAssistantDelta(
                    messageId: messageId,
                    delta: delta,
                    timestampLabel: formattedConversationTimestamp(event.createdAt),
                    messages: &projectedMessages
                )
            case let .runPlanCreated(runPlan, summary):
                projectedMessages.append(
                    mapRunPlanCreatedMessage(
                        event: event,
                        runPlan: runPlan,
                        summary: summary
                    )
                )
            case let .runPlanUpdated(runPlan, runPlanId, currentStageId, summary):
                projectedMessages.append(
                    mapRunPlanUpdatedMessage(
                        event: event,
                        runPlan: runPlan,
                        runPlanId: runPlanId,
                        currentStageId: currentStageId,
                        summary: summary
                    )
                )
            case let .capabilityFocusLocked(runPlanId, stageId, focusGearIds, focusCapabilityIds, summary):
                projectedMessages.append(
                    mapCapabilityFocusMessage(
                        event: event,
                        runPlanId: runPlanId,
                        stageId: stageId,
                        focusGearIds: focusGearIds,
                        focusCapabilityIds: focusCapabilityIds,
                        summary: summary
                    )
                )
            case let .stageStarted(runPlanId, stageId, title, objective, requiredCapabilities, summary):
                projectedMessages.append(
                    mapStageStartedMessage(
                        event: event,
                        runPlanId: runPlanId,
                        stageId: stageId,
                        title: title,
                        objective: objective,
                        requiredCapabilities: requiredCapabilities,
                        summary: summary
                    )
                )
            case let .stageConcluded(runPlanId, stageId, title, status, summary):
                projectedMessages.append(
                    mapStageConcludedMessage(
                        event: event,
                        runPlanId: runPlanId,
                        stageId: stageId,
                        title: title,
                        status: status,
                        summary: summary
                    )
                )
            case let .toolInvocation(invocation):
                projectedMessages.append(mapActionInvocationMessage(invocation, createdAt: event.createdAt))
                if
                    let approvalRequestID = invocation.approvalRequestId,
                    let approval = approvalsByID[approvalRequestID],
                    approval.status == "open"
                {
                    projectedMessages.append(mapApprovalMessage(approval, createdAt: event.createdAt))
                }
            case let .toolResult(invocationId, status, summary, error, artifacts):
                projectedMessages.append(
                    mapActionResultMessage(
                        invocationId: invocationId,
                        status: status,
                        summary: summary,
                        error: error,
                        artifacts: artifacts,
                        createdAt: event.createdAt
                    )
                )
            case let .sessionStateChanged(summary):
                if shouldProjectSessionStateSummary(summary) {
                    projectedMessages.append(
                        ConversationMessage(
                            id: event.eventId,
                            role: .assistant,
                            kind: .thinking,
                            headerTitle: "Thinking",
                            content: summary,
                            timestampLabel: formattedConversationTimestamp(event.createdAt),
                            tone: .neutral
                        )
                    )
                }
            }
        }

        let legacyMessages = snapshot.activeConversation.messages
            .filter { !transcriptMessageIDs.contains($0.messageId) }
            .map(mapConversationMessage)
        return projectedMessages + legacyMessages
    }

    private func shouldProjectSessionStateSummary(_ summary: String) -> Bool {
        let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return false
        }

        let lowSignalFragments = [
            "Turn setup complete.",
            "delegating this turn into the SDK loop",
            "the agent inspected the Gear result and requested another native Gear host action inside the same SDK run",
            "the agent requested native Gear host action(s)",
            "GeeAgent paused the same SDK run until the macOS host returns structured results",
            "the SDK runtime is waiting on native Gear host action results",
            "native Gear actions completed; returning structured host results to the SDK runtime",
            "the SDK runtime continued after Gear host results and completed the active user turn",
            "Turn finalized after",
            "the SDK runtime completed",
            "completed the active turn",
            "completed the active user turn",
            "committed the resulting tool trace",
            "committed that failed turn",
        ]

        return !lowSignalFragments.contains { fragment in
            normalized.localizedCaseInsensitiveContains(fragment)
        }
    }

    private func upsertAssistantMessage(
        messageId: String,
        content: String,
        timestampLabel: String,
        messages: inout [ConversationMessage]
    ) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            messages.removeAll { $0.id == messageId }
            return
        }
        let message = ConversationMessage(
            id: messageId,
            role: .assistant,
            kind: .chat,
            content: content,
            timestampLabel: timestampLabel
        )
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages.remove(at: index)
            messages.append(message)
        } else {
            messages.append(message)
        }
    }

    private func appendAssistantDelta(
        messageId: String,
        delta: String,
        timestampLabel: String,
        messages: inout [ConversationMessage]
    ) {
        guard !delta.isEmpty else {
            return
        }
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            let sanitizedContent = sanitizedAssistantContent(messages[index].content + delta)
            if sanitizedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.remove(at: index)
            } else {
                messages[index].content = sanitizedContent
            }
        } else {
            let sanitizedContent = sanitizedAssistantContent(delta)
            guard !sanitizedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            messages.append(
                ConversationMessage(
                    id: messageId,
                    role: .assistant,
                    kind: .chat,
                    content: sanitizedContent,
                    timestampLabel: timestampLabel
                )
            )
        }
    }

    private func mapConversationMessage(_ message: RuntimeConversationMessageDTO) -> ConversationMessage {
        let role = conversationRole(message.role)
        return ConversationMessage(
            id: message.messageId,
            role: role,
            kind: .chat,
            content: role == .assistant ? sanitizedAssistantContent(message.content) : message.content,
            timestampLabel: formattedConversationTimestamp(message.timestamp)
        )
    }

    private func sanitizedAssistantContent(_ content: String) -> String {
        AssistantTranscriptSanitizer.sanitize(content)
    }

    private func transcriptMessageID(for event: RuntimeTranscriptEventDTO) -> String? {
        switch event.payload {
        case let .userMessage(messageId, _),
             let .assistantMessage(messageId, _),
             let .assistantMessageDelta(messageId, _):
            return messageId
        case .runPlanCreated,
             .runPlanUpdated,
             .capabilityFocusLocked,
             .stageStarted,
             .stageConcluded,
             .toolInvocation,
             .toolResult,
             .sessionStateChanged:
            return nil
        }
    }

    private func mapRunPlanCreatedMessage(
        event: RuntimeTranscriptEventDTO,
        runPlan: RuntimeRunPlanDTO?,
        summary: String?
    ) -> ConversationMessage {
        var detailItems = [ConversationMessageDetailItem]()
        appendDetail("Plan", value: runPlan?.planId, to: &detailItems)
        appendDetail("Current stage", value: runPlan?.currentStageId.map(humanize), to: &detailItems)
        appendDetail("Success criteria", value: compactList(runPlan?.successCriteria ?? []), to: &detailItems)

        let stageCount = runPlan?.stages?.count ?? 0
        return ConversationMessage(
            id: "phase3-\(event.eventId)",
            role: .system,
            kind: .action,
            headerTitle: "Plan created",
            content: firstNonEmpty(runPlan?.userGoal, summary, "Run plan created.") ?? "Run plan created.",
            timestampLabel: formattedConversationTimestamp(event.createdAt),
            statusLabel: stageCount > 0 ? pluralizedStageCount(stageCount) : "Plan ready",
            systemImage: "list.bullet",
            detailItems: detailItems,
            sourceReferenceID: event.eventId,
            tone: .info
        )
    }

    private func mapRunPlanUpdatedMessage(
        event: RuntimeTranscriptEventDTO,
        runPlan: RuntimeRunPlanDTO?,
        runPlanId: String?,
        currentStageId: String?,
        summary: String?
    ) -> ConversationMessage {
        var detailItems = [ConversationMessageDetailItem]()
        appendDetail("Plan", value: firstNonEmpty(runPlanId, runPlan?.planId), to: &detailItems)
        appendDetail("Current stage", value: firstNonEmpty(currentStageId, runPlan?.currentStageId).map(humanize), to: &detailItems)
        appendDetail("Success criteria", value: compactList(runPlan?.successCriteria ?? []), to: &detailItems)

        return ConversationMessage(
            id: "phase3-\(event.eventId)",
            role: .system,
            kind: .action,
            headerTitle: "Plan updated",
            content: firstNonEmpty(summary, runPlan?.userGoal, "Run plan updated.") ?? "Run plan updated.",
            timestampLabel: formattedConversationTimestamp(event.createdAt),
            statusLabel: "Updated",
            systemImage: "arrow.triangle.2.circlepath",
            detailItems: detailItems,
            sourceReferenceID: event.eventId,
            tone: .info
        )
    }

    private func mapCapabilityFocusMessage(
        event: RuntimeTranscriptEventDTO,
        runPlanId: String?,
        stageId: String?,
        focusGearIds: [String],
        focusCapabilityIds: [String],
        summary: String?
    ) -> ConversationMessage {
        var detailItems = [ConversationMessageDetailItem]()
        appendDetail("Plan", value: runPlanId, to: &detailItems)
        appendDetail("Stage", value: stageId.map(humanize), to: &detailItems)
        appendDetail("Capabilities", value: compactList(focusCapabilityIds), to: &detailItems)
        appendDetail("Gears", value: compactList(focusGearIds), to: &detailItems)

        return ConversationMessage(
            id: "phase3-\(event.eventId)",
            role: .system,
            kind: .action,
            headerTitle: "Focus locked",
            content: firstNonEmpty(summary, focusSummary(capabilityIds: focusCapabilityIds, gearIds: focusGearIds))
                ?? "Capability focus locked.",
            timestampLabel: formattedConversationTimestamp(event.createdAt),
            statusLabel: focusStatusLabel(capabilityIds: focusCapabilityIds, gearIds: focusGearIds),
            systemImage: "lock.circle",
            detailItems: detailItems,
            sourceReferenceID: event.eventId,
            tone: .info
        )
    }

    private func mapStageStartedMessage(
        event: RuntimeTranscriptEventDTO,
        runPlanId: String?,
        stageId: String?,
        title: String?,
        objective: String?,
        requiredCapabilities: [String],
        summary: String?
    ) -> ConversationMessage {
        var detailItems = [ConversationMessageDetailItem]()
        appendDetail("Plan", value: runPlanId, to: &detailItems)
        appendDetail("Stage", value: stageId.map(humanize), to: &detailItems)
        appendDetail("Required capabilities", value: compactList(requiredCapabilities), to: &detailItems)

        return ConversationMessage(
            id: "phase3-\(event.eventId)",
            role: .system,
            kind: .action,
            headerTitle: "Stage started",
            content: firstNonEmpty(objective, summary, title, "Stage started.") ?? "Stage started.",
            timestampLabel: formattedConversationTimestamp(event.createdAt),
            statusLabel: firstNonEmpty(title, "Running"),
            systemImage: "play.circle",
            detailItems: detailItems,
            sourceReferenceID: event.eventId,
            tone: .info
        )
    }

    private func mapStageConcludedMessage(
        event: RuntimeTranscriptEventDTO,
        runPlanId: String?,
        stageId: String?,
        title: String?,
        status: String,
        summary: String?
    ) -> ConversationMessage {
        var detailItems = [ConversationMessageDetailItem]()
        appendDetail("Plan", value: runPlanId, to: &detailItems)
        appendDetail("Stage", value: stageId.map(humanize), to: &detailItems)

        return ConversationMessage(
            id: "phase3-\(event.eventId)",
            role: .system,
            kind: .action,
            headerTitle: stageConclusionTitle(for: status),
            content: firstNonEmpty(summary, title, "Stage concluded.") ?? "Stage concluded.",
            timestampLabel: formattedConversationTimestamp(event.createdAt),
            statusLabel: humanize(status),
            systemImage: stageConclusionSystemImage(for: status),
            detailItems: detailItems,
            sourceReferenceID: event.eventId,
            tone: stageConclusionTone(for: status)
        )
    }

    private func mapActionInvocationMessage(
        _ invocation: RuntimeToolInvocationDTO,
        createdAt: String
    ) -> ConversationMessage {
        ConversationMessage(
            id: "action-\(invocation.invocationId)",
            role: .system,
            kind: .action,
            headerTitle: "Agent Activity",
            content: invocation.inputSummary ?? actionSummary(from: invocation.toolName),
            timestampLabel: formattedConversationTimestamp(createdAt),
            statusLabel: actionStatusLabel(for: invocation.status, isResult: false),
            systemImage: actionSystemImage(for: invocation.status, isResult: false),
            secondaryContent: actionSourceLabel(for: invocation.toolName),
            sourceReferenceID: invocation.invocationId,
            tone: actionTone(for: invocation.status)
        )
    }

    private func mapActionResultMessage(
        invocationId: String,
        status: String,
        summary: String?,
        error: String?,
        artifacts: [RuntimeArtifactRefDTO],
        createdAt: String
    ) -> ConversationMessage {
        var detailItems = [ConversationMessageDetailItem]()
        if !artifacts.isEmpty {
            detailItems.append(
                ConversationMessageDetailItem(
                    label: "Artifacts",
                    value: artifactSummary(artifacts)
                )
            )
        }

        return ConversationMessage(
            id: "result-\(invocationId)",
            role: .system,
            kind: .action,
            headerTitle: "Action Result",
            content: error ?? summary ?? fallbackResultSummary(for: status),
            timestampLabel: formattedConversationTimestamp(createdAt),
            statusLabel: actionStatusLabel(for: status, isResult: true),
            systemImage: actionSystemImage(for: status, isResult: true),
            secondaryContent: nil,
            detailItems: detailItems,
            sourceReferenceID: invocationId,
            tone: actionTone(for: status)
        )
    }

    private func artifactSummary(_ artifacts: [RuntimeArtifactRefDTO]) -> String {
        let visible = artifacts.prefix(2).map { artifact in
            compactArtifactLabel(artifact)
        }
        let prefix = artifacts.count == 1 ? "1 artifact" : "\(artifacts.count) artifacts"
        let details = visible.isEmpty ? "" : ": \(visible.joined(separator: " · "))"
        let suffix = artifacts.count > visible.count ? " · +\(artifacts.count - visible.count) more" : ""
        return "\(prefix)\(details)\(suffix)"
    }

    private func compactArtifactLabel(_ artifact: RuntimeArtifactRefDTO) -> String {
        let title = artifact.title.nilIfBlank ?? "Artifact"
        guard let preview = artifact.inlinePreviewSummary?.nilIfBlank else {
            return clampDetailText(title, limit: 80)
        }
        return "\(clampDetailText(title, limit: 56)): \(clampDetailText(preview, limit: 96))"
    }

    private func clampDetailText(_ text: String, limit: Int) -> String {
        let normalized = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }
        return "\(normalized.prefix(max(0, limit - 1)))…"
    }

    private func mapApprovalMessage(
        _ approval: RuntimeApprovalDTO,
        createdAt: String
    ) -> ConversationMessage {
        var detailItems = approval.parameters.map {
            ConversationMessageDetailItem(label: $0.label, value: $0.value)
        }
        if !approval.riskTags.isEmpty {
            detailItems.append(
                ConversationMessageDetailItem(
                    label: "Impact",
                    value: approval.riskTags.map(humanize).joined(separator: ", ")
                )
            )
        }

        return ConversationMessage(
            id: "approval-\(approval.approvalRequestId)",
            role: .system,
            kind: .approval,
            headerTitle: "Authorization Needed",
            content: approval.actionTitle,
            timestampLabel: formattedConversationTimestamp(createdAt),
            statusLabel: approval.reviewRequired ? "Waiting for your approval" : "Review requested",
            systemImage: "hand.raised.fill",
            secondaryContent: approval.reason,
            detailItems: detailItems,
            primaryActionLabel: "Review in Tasks",
            primaryActionTaskID: approval.taskId,
            sourceReferenceID: approval.approvalRequestId,
            tone: .warning
        )
    }

    private func actionStatusLabel(for rawStatus: String, isResult: Bool) -> String {
        switch rawStatus {
        case "queued":
            return isResult ? "Queued" : "Preparing"
        case "running":
            return isResult ? "Updated" : "Running"
        case "succeeded":
            return isResult ? "" : "Completed"
        case "failed":
            return "Failed"
        case "cancelled":
            return "Cancelled"
        default:
            return isResult ? "Updated" : "Working"
        }
    }

    private func actionSystemImage(for rawStatus: String, isResult: Bool) -> String {
        switch rawStatus {
        case "queued":
            return "clock"
        case "running":
            return isResult ? "text.badge.checkmark" : "ellipsis.circle"
        case "succeeded":
            return isResult ? "terminal" : "checkmark.circle.fill"
        case "failed":
            return "exclamationmark.triangle.fill"
        case "cancelled":
            return "xmark.circle.fill"
        default:
            return "ellipsis.circle"
        }
    }

    private func actionTone(for rawStatus: String) -> ConversationMessage.Tone {
        switch rawStatus {
        case "succeeded":
            return .success
        case "failed", "cancelled":
            return .critical
        case "queued":
            return .neutral
        default:
            return .info
        }
    }

    private func actionSourceLabel(for toolName: String) -> String {
        let parts = toolName
            .split(separator: ".")
            .map { humanize(String($0)) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return "Local action"
        }
        if parts.count == 1 {
            return parts[0]
        }
        return "\(parts.dropLast().joined(separator: " · ")) · \(parts.last ?? "")"
    }

    private func actionSummary(from toolName: String) -> String {
        "Running \(actionSourceLabel(for: toolName).lowercased())."
    }

    private func appendDetail(
        _ label: String,
        value: String?,
        to detailItems: inout [ConversationMessageDetailItem]
    ) {
        guard let value = value?.nilIfBlank else {
            return
        }
        detailItems.append(ConversationMessageDetailItem(label: label, value: value))
    }

    private func compactList(_ values: [String], limit: Int = 3) -> String? {
        let cleaned = values.compactMap(\.nilIfBlank)
        guard !cleaned.isEmpty else {
            return nil
        }

        let visible = cleaned.prefix(limit).joined(separator: ", ")
        let overflowCount = cleaned.count - min(cleaned.count, limit)
        return overflowCount > 0 ? "\(visible), +\(overflowCount) more" : visible
    }

    private func pluralizedStageCount(_ count: Int) -> String {
        count == 1 ? "1 stage" : "\(count) stages"
    }

    private func focusStatusLabel(capabilityIds: [String], gearIds: [String]) -> String {
        if !capabilityIds.isEmpty {
            return capabilityIds.count == 1 ? "1 capability" : "\(capabilityIds.count) capabilities"
        }
        if !gearIds.isEmpty {
            return gearIds.count == 1 ? "1 gear" : "\(gearIds.count) gears"
        }
        return "Scoped"
    }

    private func focusSummary(capabilityIds: [String], gearIds: [String]) -> String {
        if let capabilities = compactList(capabilityIds, limit: 2) {
            return "Capability focus locked to \(capabilities)."
        }
        if let gears = compactList(gearIds, limit: 2) {
            return "Gear focus locked to \(gears)."
        }
        return "Capability focus remains scoped by the active plan."
    }

    private func stageConclusionTitle(for rawStatus: String) -> String {
        switch rawStatus {
        case "completed":
            return "Stage completed"
        case "partial":
            return "Stage partially complete"
        case "blocked":
            return "Stage blocked"
        case "plan_changed":
            return "Stage changed plan"
        case "needs_user_input":
            return "Stage needs input"
        default:
            return "Stage concluded"
        }
    }

    private func stageConclusionSystemImage(for rawStatus: String) -> String {
        switch rawStatus {
        case "completed":
            return "checkmark.circle.fill"
        case "blocked":
            return "exclamationmark.triangle.fill"
        case "needs_user_input":
            return "hand.raised.fill"
        case "plan_changed":
            return "arrow.triangle.2.circlepath"
        case "partial":
            return "circle.lefthalf.filled"
        default:
            return "checkmark.circle"
        }
    }

    private func stageConclusionTone(for rawStatus: String) -> ConversationMessage.Tone {
        switch rawStatus {
        case "completed":
            return .success
        case "blocked":
            return .critical
        case "partial", "plan_changed", "needs_user_input":
            return .warning
        default:
            return .info
        }
    }

    private func fallbackResultSummary(for rawStatus: String) -> String {
        switch rawStatus {
        case "failed":
            return "The action did not complete."
        case "cancelled":
            return "The action was cancelled."
        case "succeeded":
            return "The action completed."
        default:
            return "The action was updated."
        }
    }

    private func settingsPanes(from snapshot: RuntimeSnapshotDTO) -> [SettingsPaneSummary] {
        let capabilities = snapshot.interactionCapabilities
        let lastOutcome = snapshot.lastRequestOutcome

        return [
            SettingsPaneSummary(
                id: "runtime-status",
                title: "Runtime",
                summary: snapshot.chatRuntime.detail,
                items: [
                    SettingValue(id: "runtime-surface", label: "Surface", value: humanize(capabilities?.surface ?? "desktop_live")),
                    SettingValue(id: "runtime-chat", label: "Chat", value: humanize(snapshot.chatRuntime.status)),
                    SettingValue(id: "runtime-provider", label: "Provider", value: snapshot.chatRuntime.activeProvider ?? "Not configured"),
                ]
            ),
            SettingsPaneSummary(
                id: "runtime-capabilities",
                title: "Capabilities",
                summary: capabilities?.readOnlyReason ?? "The native app is using the agent runtime.",
                items: [
                    SettingValue(id: "cap-send", label: "Send messages", value: yesNo(capabilities?.canSendMessages ?? true)),
                    SettingValue(id: "cap-mutate", label: "Mutate runtime", value: yesNo(capabilities?.canMutateRuntime ?? true)),
                    SettingValue(id: "cap-first-party", label: "First-party actions", value: yesNo(capabilities?.canRunFirstPartyActions ?? true)),
                ]
            ),
            SettingsPaneSummary(
                id: "runtime-last-outcome",
                title: "Last Request",
                summary: lastOutcome?.detail ?? "No request has been submitted from this runtime yet.",
                items: [
                    SettingValue(id: "outcome-kind", label: "Kind", value: humanize(lastOutcome?.kind ?? "none")),
                    SettingValue(id: "outcome-source", label: "Source", value: humanize(lastOutcome?.source ?? "none")),
                    SettingValue(id: "outcome-task", label: "Task", value: lastOutcome?.taskId ?? "None"),
                ]
            ),
        ]
    }

    private func runtimeStatus(from chatRuntime: RuntimeChatRuntimeDTO) -> WorkbenchRuntimeStatus {
        let state: WorkbenchRuntimeState
        switch chatRuntime.status {
        case "live":
            state = .live
        case "needs_setup":
            state = .needsSetup
        case "degraded":
            state = .degraded
        default:
            state = .unavailable
        }

        return WorkbenchRuntimeStatus(
            state: state,
            detail: chatRuntime.detail,
            providerName: chatRuntime.activeProvider
        )
    }

    private func interactionCapabilities(
        from capabilities: RuntimeInteractionCapabilitiesDTO?
    ) -> WorkbenchInteractionCapabilities {
        WorkbenchInteractionCapabilities(
            canSendMessages: capabilities?.canSendMessages ?? false,
            canMutateRuntime: capabilities?.canMutateRuntime ?? false,
            readOnlyReason: capabilities?.readOnlyReason,
            canUseQuickInput: capabilities?.canUseQuickInput ?? true
        )
    }

    private func requestOutcome(from outcome: RuntimeRequestOutcomeDTO?) -> WorkbenchRequestOutcome? {
        guard let outcome else {
            return nil
        }

        let kind: WorkbenchRequestOutcomeKind
        switch outcome.kind {
        case "chat_reply":
            kind = .chatReply
        case "task_handoff":
            kind = .taskHandoff
        case "first_party_action":
            kind = .firstPartyAction
        case "host_action_pending", "host_action_completed":
            kind = .firstPartyAction
        case "clarify_needed":
            kind = .clarifyNeeded
        case "needs_setup":
            kind = .needsSetup
        default:
            kind = .error
        }

        return WorkbenchRequestOutcome(kind: kind, detail: outcome.detail, taskID: outcome.taskId)
    }

    private func homeItems(
        openApprovals: [RuntimeApprovalDTO],
        tasks: [WorkbenchTaskRecord],
        automations: [AutomationRecord],
        installedApps: [InstalledAppRecord]
    ) -> [WorkbenchHomeItem] {
        var items = [WorkbenchHomeItem]()

        for approval in openApprovals.prefix(2) {
            items.append(
                WorkbenchHomeItem(
                    id: "approval-\(approval.approvalRequestId)",
                    title: approval.actionTitle,
                    detail: approval.reason,
                    statusLabel: "Needs review",
                    actionLabel: "Review approval",
                    kind: .approval
                )
            )
        }

        for task in tasks.filter({ $0.status != .completed }).prefix(3) {
            items.append(
                WorkbenchHomeItem(
                    id: "task-\(task.id)",
                    title: task.title,
                    detail: task.summary,
                    statusLabel: task.status.title,
                    actionLabel: "Open task",
                    kind: .task
                )
            )
        }

        if let automation = automations.first {
            items.append(
                WorkbenchHomeItem(
                    id: "automation-\(automation.id)",
                    title: automation.name,
                    detail: automation.summary,
                    statusLabel: automation.scheduleLabel,
                    actionLabel: "Inspect automation",
                    kind: .automation
                )
            )
        }

        if let app = installedApps.first {
            items.append(
                WorkbenchHomeItem(
                    id: "app-\(app.id)",
                    title: app.name,
                    detail: app.summary,
                    statusLabel: app.healthLabel,
                    actionLabel: "Inspect app",
                    kind: .app
                )
            )
        }

        return items
    }

    private func unavailableSnapshot(detail: String) -> WorkbenchSnapshot {
        WorkbenchSnapshot(
            homeSummary: WorkbenchHomeSummary(
                openTasksCount: 0,
                approvalsCount: 0,
                nextAutomationLabel: "No schedules",
                installedAppsCount: 0
            ),
            homeItems: [
                WorkbenchHomeItem(
                    id: "runtime-error",
                    title: "Agent runtime unavailable",
                    detail: detail,
                    statusLabel: "Needs attention",
                    actionLabel: "Inspect runtime",
                    kind: .task
                )
            ],
            conversations: [
                ConversationThread(
                    id: "runtime",
                    title: "Agent runtime",
                    participantLabel: "System",
                    previewText: detail,
                    statusLabel: "Unavailable",
                    lastActivityLabel: formattedConversationTimestamp("now"),
                    unreadCount: 0,
                    linkedTaskTitle: nil,
                    linkedAppName: nil,
                    messages: [
                        ConversationMessage(
                            id: "runtime-message",
                            role: .system,
                            content: detail,
                            timestampLabel: formattedConversationTimestamp("now")
                        )
                    ]
                )
            ],
            tasks: [],
            automations: [],
            installedApps: [],
            agentSkins: [],
            skillSources: .empty,
            settings: [
                SettingsPaneSummary(
                    id: "runtime-error",
                    title: "Agent Runtime",
                    summary: detail,
                    items: [
                        SettingValue(id: "runtime-status", label: "Status", value: "Unavailable")
                    ]
                )
            ],
            preferredSection: .chat,
            runtimeStatus: WorkbenchRuntimeStatus(
                state: .unavailable,
                detail: detail,
                providerName: nil
            ),
            interactionCapabilities: WorkbenchInteractionCapabilities(
                canSendMessages: false,
                canMutateRuntime: false,
                readOnlyReason: detail
            ),
            lastOutcome: WorkbenchRequestOutcome(kind: .error, detail: detail, taskID: nil)
        )
    }

    private func conversationRole(_ role: String) -> ConversationMessage.Role {
        switch role {
        case "user":
            return .user
        case "assistant":
            return .assistant
        default:
            return .system
        }
    }

    private func workbenchTaskStatus(_ rawStatus: String) -> WorkbenchTaskStatus {
        switch rawStatus {
        case "waiting_review":
            return .needsApproval
        case "waiting_input":
            return .blocked
        case "running":
            return .running
        case "queued":
            return .queued
        case "completed":
            return .completed
        case "failed":
            return .failed
        default:
            return .blocked
        }
    }

    private func automationStatus(_ rawStatus: String) -> AutomationStatus {
        switch rawStatus {
        case "paused":
            return .paused
        case "attention":
            return .attention
        default:
            return .active
        }
    }

    private func dueLabel(_ rawStatus: String) -> String {
        switch rawStatus {
        case "waiting_review":
            return "Needs review"
        case "waiting_input":
            return "Needs input"
        case "running":
            return "In progress"
        case "completed":
            return "Completed"
        case "failed":
            return "Retry needed"
        default:
            return "Queued"
        }
    }

    private func updatedLabel(for taskID: String, moduleRuns: [RuntimeModuleRunDTO]) -> String {
        moduleRuns.first(where: { $0.moduleRun.taskId == taskID })?.moduleRun.updatedAt ?? "Latest runtime snapshot"
    }

    private func moduleName(for taskID: String?, moduleRuns: [RuntimeModuleRunDTO]) -> String? {
        guard let taskID else {
            return nil
        }

        guard let moduleID = moduleRuns.first(where: { $0.moduleRun.taskId == taskID })?.moduleRun.moduleId else {
            return nil
        }

        return humanize(moduleID.split(separator: ".").suffix(2).joined(separator: " "))
    }

    private func moduleName(for taskID: String, moduleRuns: [RuntimeModuleRunDTO]) -> String {
        moduleName(for: Optional(taskID), moduleRuns: moduleRuns) ?? "Workspace"
    }

    private func importanceLabel(_ rawImportance: String) -> String {
        humanize(rawImportance)
    }

    private func automationScheduleLabel(_ automation: RuntimeAutomationDTO) -> String {
        if automation.cadence == "once", let scheduleHint = automation.scheduleHint, !scheduleHint.isEmpty {
            return "\(scheduleHint) at \(automation.timeOfDay)"
        }

        switch automation.cadence {
        case "weekdays":
            return "Weekdays at \(automation.timeOfDay)"
        case "weekly":
            return "Every week at \(automation.timeOfDay)"
        case "once":
            return "One time at \(automation.timeOfDay)"
        default:
            return "Every day at \(automation.timeOfDay)"
        }
    }

    private func activeParticipantLabel(chatRuntime: RuntimeChatRuntimeDTO) -> String {
        if let provider = chatRuntime.activeProvider {
            return "Live via \(provider)"
        }

        return "GeeAgent"
    }

    private func formattedConversationTimestamp(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "--"
        }

        let lowered = trimmed.lowercased()
        if lowered == "now" || lowered == "just now" {
            return "Just now"
        }

        guard let date = Self.parseConversationTimestamp(trimmed) else {
            return trimmed
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < -60 {
            return date.formatted(Self.absoluteConversationTimestampFormat)
        }

        if interval < 60 {
            return "Just now"
        }

        if interval < 3_600 {
            return "\(max(Int(interval / 60), 1))m ago"
        }

        if interval < 86_400 {
            return "\(max(Int(interval / 3_600), 1))h ago"
        }

        if interval < 604_800 {
            let days = max(Int(interval / 86_400), 1)
            let hours = Int(interval.truncatingRemainder(dividingBy: 86_400) / 3_600)
            return hours > 0 ? "\(days)d \(hours)h ago" : "\(days)d ago"
        }

        return date.formatted(Self.absoluteConversationTimestampFormat)
    }

    private func humanize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func summarize(_ raw: String, limit: Int) -> String {
        let normalized = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }

        let endIndex = normalized.index(normalized.startIndex, offsetBy: limit - 1)
        return "\(normalized[..<endIndex])…"
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}

private extension NativeWorkbenchRuntimeClient {
    static let absoluteConversationTimestampFormat: Date.FormatStyle = .dateTime
        .year()
        .month(.twoDigits)
        .day(.twoDigits)
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)

    static func parseConversationTimestamp(_ raw: String) -> Date? {
        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: raw) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
