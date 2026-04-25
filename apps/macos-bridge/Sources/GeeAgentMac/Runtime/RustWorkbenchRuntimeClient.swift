import Foundation

private enum RustWorkbenchRuntimeError: LocalizedError {
    case bridgeUnavailable(String)
    case bridgeInvocation(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case let .bridgeUnavailable(message),
             let .bridgeInvocation(message),
             let .unsupported(message):
            return message
        }
    }
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
    let messages: [RuntimeConversationMessageDTO]
}

private struct RuntimeConversationSummaryDTO: Decodable {
    let conversationId: String
    let title: String
    let status: String
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
}

private struct RuntimeAgentSkillRefDTO: Decodable {
    let id: String
    let path: String?
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

private enum RuntimeTranscriptEventPayloadDTO: Decodable {
    case userMessage(messageId: String, content: String)
    case assistantMessage(messageId: String, content: String)
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
    let createdAt: String
    let payload: RuntimeTranscriptEventPayloadDTO
}

private struct RuntimeSnapshotDTO: Decodable {
    let quickInputHint: String
    let quickReply: String
    let contextBudget: RuntimeContextBudgetDTO?
    let interactionCapabilities: RuntimeInteractionCapabilitiesDTO?
    let lastRequestOutcome: RuntimeRequestOutcomeDTO?
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

private struct RuntimeBridgeServerResponseDTO: Decodable {
    let id: String
    let ok: Bool
    let output: String?
    let error: String?
}

private final class ShellRuntimeBridgeProcess {
    private let fileManager = FileManager.default
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
    private let buildLock = NSLock()
    private let serverLock = NSLock()
    private var serverProcess: Process?
    private var serverStdin: FileHandle?
    private var serverStdout: FileHandle?
    private var serverStderr: FileHandle?
    private var serverExecutableURL: URL?
    private var serverExecutableModificationDate: Date?

    private var repoRootURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private var cargoManifestURL: URL {
        repoRootURL
            .appendingPathComponent("apps")
            .appendingPathComponent("desktop-shell")
            .appendingPathComponent("src-tauri")
            .appendingPathComponent("Cargo.toml")
    }

    private var bridgeBinaryCandidates: [URL] {
        var candidates = [URL]()

        if let overridePath = ProcessInfo.processInfo.environment["GEEAGENT_NATIVE_BRIDGE_BIN"],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(URL(fileURLWithPath: overridePath))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("shell_runtime_bridge"))
        }

        let tauriRoot = repoRootURL
            .appendingPathComponent("apps")
            .appendingPathComponent("desktop-shell")
            .appendingPathComponent("src-tauri")
        candidates.append(tauriRoot.appendingPathComponent("target/debug/shell_runtime_bridge"))
        candidates.append(tauriRoot.appendingPathComponent("target/release/shell_runtime_bridge"))

        return candidates
    }

    deinit {
        stopServer()
    }

    func loadSnapshot() throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["snapshot"])
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

    func submitQuickPrompt(_ prompt: String) throws -> RuntimeSnapshotDTO {
        try decodeSnapshot(arguments: ["submit-quick-prompt", prompt])
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
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "The Rust runtime bridge returned invalid JSON while listing agent profiles: \(raw)"
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
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "The Rust runtime bridge returned invalid JSON while loading chat routing settings: \(raw)"
            )
        }
    }

    func saveChatRoutingSettings(_ settings: ChatRoutingSettings) throws -> RuntimeSnapshotDTO {
        let data = try encoder.encode(settings)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "Could not encode chat routing settings as UTF-8 JSON."
            )
        }
        return try decodeSnapshot(arguments: ["save-chat-routing-settings", raw])
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
    /// the bridge's `invoke-tool` subcommand consumes.
    static func encodeInvocation(_ invocation: ToolInvocation) throws -> String {
        var object: [String: Any] = [
            "tool_id": invocation.toolID,
            "arguments": WorkbenchToolArgumentBridge.encode(invocation.arguments),
        ]
        if let token = invocation.approvalToken, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object["approval_token"] = token
        }
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let json = String(data: payload, encoding: .utf8) else {
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "failed to encode tool invocation payload as UTF-8"
            )
        }
        return json
    }

    /// Exposed for tests — decodes a `WorkbenchToolOutcome` from the tagged
    /// JSON the bridge returns.
    static func decodeOutcome(from data: Data) throws -> WorkbenchToolOutcome {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 output>"
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "tool outcome was not valid JSON: \(raw)"
            )
        }
        guard let dict = object as? [String: Any], let kind = dict["kind"] as? String else {
            throw RustWorkbenchRuntimeError.bridgeInvocation(
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
            return try decoder.decode(RuntimeSnapshotDTO.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 output>"
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "The Rust runtime bridge returned invalid JSON: \(raw)"
            )
        }
    }

    private func run(arguments: [String]) throws -> Data {
        if ProcessInfo.processInfo.environment["GEEAGENT_DISABLE_NATIVE_BRIDGE_SERVER"] != "1" {
            return try runThroughServer(arguments: arguments)
        }

        return try runStandalone(arguments: arguments, timeout: nil)
    }

    private func runStandalone(arguments: [String], timeout: TimeInterval?) throws -> Data {
        let executableURL = try ensureBridgeExecutableURL()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw RustWorkbenchRuntimeError.bridgeUnavailable(
                "Failed to launch the Rust runtime bridge: \(error.localizedDescription)"
            )
        }

        let output = captureOutput(
            from: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            timeout: timeout
        )

        guard !output.timedOut else {
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "The Rust runtime bridge did not finish within \(Int(timeout ?? 0)) seconds. GeeAgent stopped this request so Quick Input would not stay loading forever."
            )
        }

        guard process.terminationStatus == 0 else {
            let stderr = String(data: output.stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                stderr?.isEmpty == false
                    ? stderr!
                    : "The Rust runtime bridge exited with status \(process.terminationStatus)."
            )
        }

        return output.stdout
    }

    private func runThroughServer(arguments: [String]) throws -> Data {
        serverLock.lock()
        defer { serverLock.unlock() }

        return try runThroughServerLocked(arguments: arguments)
    }

    private func runThroughServerLocked(arguments: [String]) throws -> Data {
        guard let command = arguments.first else {
            throw RustWorkbenchRuntimeError.bridgeInvocation("missing bridge command")
        }
        let executableURL = try ensureBridgeExecutableURL()
        try ensureServerLocked(executableURL: executableURL)

        guard let stdin = serverStdin, let stdout = serverStdout else {
            throw RustWorkbenchRuntimeError.bridgeUnavailable(
                "The Rust runtime bridge server is not connected."
            )
        }

        let requestID = UUID().uuidString
        let requestObject: [String: Any] = [
            "id": requestID,
            "command": command,
            "args": Array(arguments.dropFirst()),
        ]
        let requestData = try JSONSerialization.data(
            withJSONObject: requestObject,
            options: [.sortedKeys]
        )
        guard var requestLine = String(data: requestData, encoding: .utf8) else {
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "failed to encode bridge server request"
            )
        }
        requestLine.append("\n")
        try stdin.write(contentsOf: Data(requestLine.utf8))

        let responseData = try readServerLine(
            from: stdout,
            timeout: Self.timeout(for: command)
        )
        let response: RuntimeBridgeServerResponseDTO
        do {
            response = try decoder.decode(RuntimeBridgeServerResponseDTO.self, from: responseData)
        } catch {
            let raw = String(data: responseData, encoding: .utf8) ?? "<non-utf8 output>"
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "The Rust runtime bridge server returned invalid JSON: \(raw)"
            )
        }

        guard response.id == requestID else {
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "The Rust runtime bridge server returned a mismatched response."
            )
        }
        guard response.ok else {
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                response.error ?? "The Rust runtime bridge server failed this request."
            )
        }
        guard let output = response.output else {
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "The Rust runtime bridge server returned no output."
            )
        }
        return Data(output.utf8)
    }

    private func ensureServerLocked(executableURL: URL) throws {
        let modificationDate = Self.modificationDate(for: executableURL)
        if let process = serverProcess,
           process.isRunning,
           serverExecutableURL == executableURL,
           serverExecutableModificationDate == modificationDate {
            return
        }

        stopServerLocked()

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["serve"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw RustWorkbenchRuntimeError.bridgeUnavailable(
                "Failed to launch the Rust runtime bridge server: \(error.localizedDescription)"
            )
        }

        serverProcess = process
        serverStdin = stdinPipe.fileHandleForWriting
        serverStdout = stdoutPipe.fileHandleForReading
        serverStderr = stderrPipe.fileHandleForReading
        serverExecutableURL = executableURL
        serverExecutableModificationDate = modificationDate
    }

    private static func modificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private static func timeout(for command: String) -> TimeInterval {
        switch command {
        case "submit-quick-prompt":
            45
        case "submit-workspace-message", "perform-task-action":
            120
        default:
            60
        }
    }

    private func readServerLine(from stdout: FileHandle, timeout: TimeInterval) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ServerLineReadResult()

        DispatchQueue.global(qos: .userInitiated).async {
            let readResult: Result<Data, RustWorkbenchRuntimeError>
            do {
                readResult = .success(try Self.readServerLineBlocking(from: stdout))
            } catch let error as RustWorkbenchRuntimeError {
                readResult = .failure(error)
            } catch {
                readResult = .failure(.bridgeInvocation(error.localizedDescription))
            }

            resultBox.store(readResult)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            stopServerLocked()
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "The Rust runtime bridge did not reply within \(Int(timeout)) seconds. GeeAgent restarted the bridge so Quick Input would not stay loading forever."
            )
        }

        switch resultBox.snapshot() {
        case let .success(data):
            return data
        case let .failure(error):
            throw error
        case .none:
            throw RustWorkbenchRuntimeError.bridgeInvocation(
                "The Rust runtime bridge finished without a response."
            )
        }
    }

    private static func readServerLineBlocking(from stdout: FileHandle) throws -> Data {
        var buffer = Data()
        while true {
            let chunk = stdout.readData(ofLength: 1)
            if chunk.isEmpty {
                throw RustWorkbenchRuntimeError.bridgeInvocation(
                    "The Rust runtime bridge server exited before replying."
                )
            }
            if chunk == Data([0x0A]) {
                return buffer
            }
            buffer.append(chunk)
        }
    }

    private func stopServer() {
        serverLock.lock()
        defer { serverLock.unlock() }
        stopServerLocked()
    }

    private func stopServerLocked() {
        serverStderr?.readabilityHandler = nil
        serverStdin?.closeFile()
        serverStdout?.closeFile()
        serverStderr?.closeFile()
        if let process = serverProcess, process.isRunning {
            process.terminate()
        }
        serverProcess = nil
        serverStdin = nil
        serverStdout = nil
        serverStderr = nil
        serverExecutableURL = nil
        serverExecutableModificationDate = nil
    }

    private func ensureBridgeExecutableURL() throws -> URL {
        if let executableURL = bridgeBinaryCandidates.first(where: isExecutable) {
            return executableURL
        }

        try buildBridgeBinary()

        if let executableURL = bridgeBinaryCandidates.first(where: isExecutable) {
            return executableURL
        }

        throw RustWorkbenchRuntimeError.bridgeUnavailable(
            "Could not locate the Rust runtime bridge binary after building it."
        )
    }

    private func buildBridgeBinary() throws {
        buildLock.lock()
        defer { buildLock.unlock() }

        if bridgeBinaryCandidates.contains(where: isExecutable) {
            return
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "cargo",
            "build",
            "--manifest-path",
            cargoManifestURL.path,
            "--bin",
            "shell_runtime_bridge",
        ]
        process.currentDirectoryURL = repoRootURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw RustWorkbenchRuntimeError.bridgeUnavailable(
                "Failed to start cargo while building the Rust runtime bridge: \(error.localizedDescription)"
            )
        }

        let output = captureOutput(
            from: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )
        guard process.terminationStatus == 0 else {
            let stderr = String(
                data: output.stderr,
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw RustWorkbenchRuntimeError.bridgeUnavailable(
                stderr.isEmpty
                    ? "cargo build failed for the Rust runtime bridge."
                    : stderr
            )
        }
    }

    private func isExecutable(_ url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
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

final class RustWorkbenchRuntimeClient: WorkbenchRuntimeClient, @unchecked Sendable {
    private let bridge = ShellRuntimeBridgeProcess()
    private let rawSnapshotLock = NSLock()
    private var rawSnapshot: RuntimeSnapshotDTO?

    func loadSnapshot() -> WorkbenchSnapshot {
        do {
            let snapshot = try bridge.loadSnapshot()
            storeRawSnapshot(snapshot)
            return map(snapshot)
        } catch {
            return unavailableSnapshot(detail: error.localizedDescription)
        }
    }

    func createConversation(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.bridge.createConversation()
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
            try self.bridge.activateConversation(conversationID)
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
            try self.bridge.deleteConversation(conversationID)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func sendMessage(
        _ message: String,
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot

        var latestSnapshot = currentRawSnapshot()
        if latestSnapshot?.activeConversation.conversationId != conversationID {
            let activatedSnapshot = try await runOffMainThread {
                try self.bridge.activateConversation(conversationID)
            }
            storeRawSnapshot(activatedSnapshot)
            latestSnapshot = activatedSnapshot
        }

        let routeSnapshot = latestSnapshot
        let nextSnapshot: RuntimeSnapshotDTO = try await runOffMainThread {
            if self.shouldRouteThroughQuickPrompt(
                message: message,
                conversationID: conversationID,
                rawSnapshot: routeSnapshot
            ) {
                return try self.bridge.submitQuickPrompt(message)
            }

            return try self.bridge.submitWorkspaceMessage(message)
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
            throw RustWorkbenchRuntimeError.unsupported(
                "Live task completion is not wired yet. Use chat to continue or retry the task."
            )
        }

        let nextSnapshot = try await runOffMainThread {
            try self.bridge.performTaskAction(taskID: taskID, action: actionName)
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
            try self.bridge.setActiveAgentProfile(profileID)
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
            try self.bridge.submitQuickPrompt(trimmed)
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
            try self.bridge.installAgentPack(at: trimmed)
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
            try self.bridge.reloadAgentProfile(profileID)
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
            try self.bridge.deleteAgentProfile(profileID)
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
            try self.bridge.deleteTerminalAccessRule(ruleID)
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
            try self.bridge.setHighestAuthorizationEnabled(enabled)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func loadChatRoutingSettings() async throws -> ChatRoutingSettings {
        try await runOffMainThread {
            try self.bridge.loadChatRoutingSettings()
        }
    }

    func saveChatRoutingSettings(
        _ settings: ChatRoutingSettings,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        _ = snapshot
        let nextSnapshot = try await runOffMainThread {
            try self.bridge.saveChatRoutingSettings(settings)
        }
        storeRawSnapshot(nextSnapshot)
        return map(nextSnapshot)
    }

    func invokeTool(_ invocation: ToolInvocation) async throws -> WorkbenchToolOutcome {
        try await runOffMainThread {
            try self.bridge.invokeTool(invocation)
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

    private func shouldRouteThroughQuickPrompt(
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
                summary: "\(app.displayName) is available through the Rust runtime registry.",
                displayMode: mode
            )
        } ?? []
        let installedApps = GearRegistry.mergedWithGears(runtimeApps)

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
                isActive: summary.isActive
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
            settings: settings,
            preferredSection: WorkbenchSection(rawValue: snapshot.workspaceRuntime?.activeSection ?? "") ?? .home,
            runtimeStatus: runtimeStatus(from: snapshot.chatRuntime),
            interactionCapabilities: interactionCapabilities(from: snapshot.interactionCapabilities),
            quickInputHint: snapshot.quickInputHint,
            quickReply: snapshot.quickReply,
            contextBudget: contextBudget(from: snapshot.contextBudget),
            lastOutcome: requestOutcome(from: snapshot.lastRequestOutcome)
        )
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
            compactedMessagesCount: dto.compactedMessagesCount
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
        let appearance: AgentProfileAppearanceRecord
        switch dto.appearance.kind {
        case "static_image":
            appearance = .staticImage(assetPath: dto.appearance.assetPath ?? "")
        case "video":
            appearance = .video(assetPath: dto.appearance.assetPath ?? "")
        case "live2d":
            appearance = .live2D(bundlePath: dto.appearance.bundlePath ?? "")
        default:
            appearance = .abstract
        }

        let source = AgentProfileSourceRecord(rawValue: dto.source) ?? .userCreated
        let skills = (dto.skills ?? []).map { ref in
            AgentSkillReferenceRecord(id: ref.id, name: humanize(ref.id), path: ref.path)
        }
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
            skills: skills,
            allowedToolIDs: dto.allowedToolIds,
            source: source,
            version: dto.version,
            fileState: fileState
        )
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
        var projectedMessages = snapshot.activeConversation.messages
            .filter { !transcriptMessageIDs.contains($0.messageId) }
            .map(mapConversationMessage)

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
                projectedMessages.append(
                    ConversationMessage(
                        id: messageId,
                        role: .assistant,
                        kind: .chat,
                        content: content,
                        timestampLabel: formattedConversationTimestamp(event.createdAt)
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

        return projectedMessages
    }

    private func mapConversationMessage(_ message: RuntimeConversationMessageDTO) -> ConversationMessage {
        ConversationMessage(
            id: message.messageId,
            role: conversationRole(message.role),
            kind: .chat,
            content: message.content,
            timestampLabel: formattedConversationTimestamp(message.timestamp)
        )
    }

    private func transcriptMessageID(for event: RuntimeTranscriptEventDTO) -> String? {
        switch event.payload {
        case let .userMessage(messageId, _), let .assistantMessage(messageId, _):
            return messageId
        case .toolInvocation, .toolResult, .sessionStateChanged:
            return nil
        }
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
                    value: artifacts.count == 1 ? "1 ready" : "\(artifacts.count) ready"
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
                summary: capabilities?.readOnlyReason ?? "The native app is using the Rust runtime bridge.",
                items: [
                    SettingValue(id: "cap-send", label: "Send messages", value: yesNo(capabilities?.canSendMessages ?? true)),
                    SettingValue(id: "cap-mutate", label: "Mutate runtime", value: yesNo(capabilities?.canMutateRuntime ?? true)),
                    SettingValue(id: "cap-first-party", label: "First-party actions", value: yesNo(capabilities?.canRunFirstPartyActions ?? true)),
                ]
            ),
            SettingsPaneSummary(
                id: "runtime-last-outcome",
                title: "Last Request",
                summary: lastOutcome?.detail ?? "No request has been submitted from this bridge yet.",
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
                    id: "runtime-bridge-error",
                    title: "Rust runtime bridge unavailable",
                    detail: detail,
                    statusLabel: "Needs attention",
                    actionLabel: "Inspect runtime",
                    kind: .task
                )
            ],
            conversations: [
                ConversationThread(
                    id: "runtime-bridge",
                    title: "Runtime bridge",
                    participantLabel: "System",
                    previewText: detail,
                    statusLabel: "Unavailable",
                    lastActivityLabel: formattedConversationTimestamp("now"),
                    unreadCount: 0,
                    linkedTaskTitle: nil,
                    linkedAppName: nil,
                    messages: [
                        ConversationMessage(
                            id: "runtime-bridge-message",
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
            settings: [
                SettingsPaneSummary(
                    id: "runtime-bridge-error",
                    title: "Runtime Bridge",
                    summary: detail,
                    items: [
                        SettingValue(id: "runtime-bridge-status", label: "Status", value: "Unavailable")
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

private extension RustWorkbenchRuntimeClient {
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

private final class ProcessPipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ nextData: Data) {
        lock.lock()
        data = nextData
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private final class ServerLineReadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, RustWorkbenchRuntimeError>?

    func store(_ nextResult: Result<Data, RustWorkbenchRuntimeError>) {
        lock.lock()
        result = nextResult
        lock.unlock()
    }

    func snapshot() -> Result<Data, RustWorkbenchRuntimeError>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
