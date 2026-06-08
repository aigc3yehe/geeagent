import AppKit
import Combine
import Darwin
import Foundation

enum LocalProjectManagerGearDescriptor {
    static let gearID = "local.project.manager"
}

struct LocalProjectRecord: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var command: String
    var frontendPort: Int?
    var lastManagedPID: Int32?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case command
        case frontendPort = "frontend_port"
        case lastManagedPID = "last_managed_pid"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Untitled Project"
    }

    var frontendURL: URL? {
        guard let frontendPort else {
            return nil
        }
        return URL(string: "http://localhost:\(frontendPort)")
    }
}

struct LocalProjectProcessSnapshot: Equatable, Hashable {
    var pid: Int32
    var command: String
}

enum LocalProjectStatusState: String, Equatable {
    case running
    case stopped
}

enum LocalProjectStatusSource: String, Equatable {
    case frontendPort
    case managedProcess
    case commandMatch
    case none

    var label: String {
        switch self {
        case .frontendPort: "Port"
        case .managedProcess: "Managed PID"
        case .commandMatch: "Command Match"
        case .none: "Stopped"
        }
    }
}

struct LocalProjectStatus: Equatable {
    var projectID: String
    var state: LocalProjectStatusState
    var source: LocalProjectStatusSource
    var pids: [Int32]
    var frontendURL: URL?
    var detail: String

    static func stopped(projectID: String) -> LocalProjectStatus {
        LocalProjectStatus(
            projectID: projectID,
            state: .stopped,
            source: .none,
            pids: [],
            frontendURL: nil,
            detail: "Stopped"
        )
    }
}

struct LocalProjectCommandIdentity: Equatable {
    var command: String
    var workingDirectoryPath: String?
    var launchLine: String?
    var executableName: String?
    var significantArguments: [String]

    init(command: String) {
        self.command = command

        var workingDirectoryPath: String?
        var launchLine: String?
        for rawLine in command.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            let tokens = Self.shellTokens(line)
            if tokens.first == "cd", tokens.count >= 2 {
                workingDirectoryPath = tokens[1]
                continue
            }
            launchLine = line
        }

        self.workingDirectoryPath = workingDirectoryPath
        self.launchLine = launchLine

        let launchTokens = launchLine.map(Self.shellTokens) ?? []
        let executableToken = launchTokens.first
        self.executableName = executableToken.map { URL(fileURLWithPath: $0).lastPathComponent.nilIfBlank ?? $0 }
        self.significantArguments = launchTokens
            .dropFirst()
            .filter { token in
                !token.hasPrefix("-") && token.count >= 2
            }
    }

    func matches(command processCommand: String) -> Bool {
        let normalizedProcessCommand = Self.normalized(processCommand)
        if let launchLine, normalizedProcessCommand.contains(Self.normalized(launchLine)) {
            return true
        }

        guard let executableName else {
            return false
        }

        let normalizedExecutable = Self.normalized(executableName)
        guard normalizedProcessCommand.contains(normalizedExecutable) else {
            return false
        }

        if let workingDirectoryPath,
           normalizedProcessCommand.contains(Self.normalized(workingDirectoryPath)) {
            return true
        }

        guard !significantArguments.isEmpty else {
            return true
        }
        return significantArguments.allSatisfy { token in
            normalizedProcessCommand.contains(Self.normalized(token))
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func shellTokens(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        for character in line {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

struct LocalProjectStatusResolver {
    func resolve(
        project: LocalProjectRecord,
        processSnapshots: [LocalProjectProcessSnapshot],
        portListeners: [Int: [Int32]],
        aliveManagedPIDs: Set<Int32>
    ) -> LocalProjectStatus {
        if let frontendPort = project.frontendPort {
            let pids = sortedUnique(portListeners[frontendPort] ?? [])
            if !pids.isEmpty {
                return LocalProjectStatus(
                    projectID: project.id,
                    state: .running,
                    source: .frontendPort,
                    pids: pids,
                    frontendURL: project.frontendURL,
                    detail: "Listening on :\(frontendPort)"
                )
            }
        }

        let identity = LocalProjectCommandIdentity(command: project.command)
        if let lastManagedPID = project.lastManagedPID,
           aliveManagedPIDs.contains(lastManagedPID),
           managedSnapshotMatches(pid: lastManagedPID, snapshots: processSnapshots, identity: identity) {
            return LocalProjectStatus(
                projectID: project.id,
                state: .running,
                source: .managedProcess,
                pids: [lastManagedPID],
                frontendURL: nil,
                detail: "Managed pid \(lastManagedPID)"
            )
        }

        let commandMatchedPIDs = sortedUnique(
            processSnapshots
                .filter { identity.matches(command: $0.command) }
                .map(\.pid)
        )
        if !commandMatchedPIDs.isEmpty {
            return LocalProjectStatus(
                projectID: project.id,
                state: .running,
                source: .commandMatch,
                pids: commandMatchedPIDs,
                frontendURL: nil,
                detail: "Matched \(commandMatchedPIDs.count) process\(commandMatchedPIDs.count == 1 ? "" : "es")"
            )
        }

        return .stopped(projectID: project.id)
    }

    private func managedSnapshotMatches(
        pid: Int32,
        snapshots: [LocalProjectProcessSnapshot],
        identity: LocalProjectCommandIdentity
    ) -> Bool {
        guard let snapshot = snapshots.first(where: { $0.pid == pid }) else {
            return true
        }
        return identity.matches(command: snapshot.command) || snapshot.command.contains("/bin/zsh")
    }

    private func sortedUnique(_ pids: [Int32]) -> [Int32] {
        Array(Set(pids)).sorted()
    }
}

struct LocalProjectFileDatabase {
    private let rootURL: URL?
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func loadProjects() throws -> [LocalProjectRecord] {
        let url = try projectsURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([LocalProjectRecord].self, from: data)
    }

    func saveProjects(_ projects: [LocalProjectRecord]) throws {
        let url = try projectsURL()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(projects.sorted { $0.createdAt < $1.createdAt })
        try data.write(to: url, options: [.atomic])
    }

    func deleteProject(id: String) throws {
        let projects = try loadProjects().filter { $0.id != id }
        try saveProjects(projects)
    }

    private func projectsURL() throws -> URL {
        let root = try dataRoot()
        return root.appendingPathComponent("projects.json", isDirectory: false)
    }

    private func dataRoot() throws -> URL {
        if let rootURL {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            return rootURL
        }
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("GeeAgent/gear-data/\(LocalProjectManagerGearDescriptor.gearID)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

struct LocalProjectSystemProbe: Sendable {
    func processSnapshots() -> [LocalProjectProcessSnapshot] {
        let output = runOutput(executable: "/bin/ps", arguments: ["-axo", "pid=,command="])
        return output
            .components(separatedBy: .newlines)
            .compactMap(parseProcessSnapshot)
    }

    func portListeners(for ports: [Int]) -> [Int: [Int32]] {
        var listeners: [Int: [Int32]] = [:]
        for port in Set(ports).sorted() {
            let output = runOutput(
                executable: "/usr/sbin/lsof",
                arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"]
            )
            let pids = output
                .components(separatedBy: .newlines)
                .compactMap { line -> Int32? in
                    guard line.hasPrefix("p") else {
                        return nil
                    }
                    return Int32(line.dropFirst())
                }
            if !pids.isEmpty {
                listeners[port] = Array(Set(pids)).sorted()
            }
        }
        return listeners
    }

    func isPIDAlive(_ pid: Int32) -> Bool {
        guard pid > 1 else {
            return false
        }
        return kill(pid, 0) == 0
    }

    @discardableResult
    func terminate(pids: [Int32]) async -> [Int32] {
        let targetPIDs = Array(Set(pids)).filter { $0 > 1 && $0 != getpid() }.sorted()
        for pid in targetPIDs {
            _ = kill(pid, SIGTERM)
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        for pid in targetPIDs where isPIDAlive(pid) {
            _ = kill(pid, SIGKILL)
        }
        return targetPIDs
    }

    private func parseProcessSnapshot(_ line: String) -> LocalProjectProcessSnapshot? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstSpace = trimmed.firstIndex(where: { $0.isWhitespace }) else {
            return nil
        }
        let pidText = String(trimmed[..<firstSpace])
        let command = String(trimmed[firstSpace...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(pidText), !command.isEmpty else {
            return nil
        }
        return LocalProjectProcessSnapshot(pid: pid, command: command)
    }

    private func runOutput(executable: String, arguments: [String]) -> String {
        LocalProjectCommandOutput.run(executable: executable, arguments: arguments)
    }
}

enum LocalProjectCommandOutput {
    static func run(executable: String, arguments: [String]) -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputBuffer = LocalProjectCommandOutputBuffer()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                return
            }
            outputBuffer.append(chunk)
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return ""
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        let remainingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingOutput.isEmpty {
            outputBuffer.append(remainingOutput)
        }

        return String(data: outputBuffer.data(), encoding: .utf8) ?? ""
    }
}

private final class LocalProjectCommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        return snapshot
    }
}

struct LocalProjectDraft: Identifiable, Equatable {
    var id: String
    var existingID: String?
    var name: String
    var command: String
    var frontendPortText: String

    init(
        id: String = UUID().uuidString,
        existingID: String? = nil,
        name: String = "",
        command: String = "",
        frontendPortText: String = ""
    ) {
        self.id = id
        self.existingID = existingID
        self.name = name
        self.command = command
        self.frontendPortText = frontendPortText
    }

    init(record: LocalProjectRecord) {
        self.init(
            existingID: record.id,
            name: record.name,
            command: record.command,
            frontendPortText: record.frontendPort.map(String.init) ?? ""
        )
    }
}

@MainActor
final class LocalProjectManagerGearStore: ObservableObject {
    static let shared = LocalProjectManagerGearStore()

    @Published private(set) var projects: [LocalProjectRecord] = []
    @Published private(set) var statuses: [String: LocalProjectStatus] = [:]
    @Published var isBusy = false
    @Published var statusMessage = "Ready"

    private let database: LocalProjectFileDatabase
    private let probe: LocalProjectSystemProbe
    private let resolver = LocalProjectStatusResolver()
    private var managedProcesses: [String: Process] = [:]

    init(
        database: LocalProjectFileDatabase = LocalProjectFileDatabase(),
        probe: LocalProjectSystemProbe = LocalProjectSystemProbe()
    ) {
        self.database = database
        self.probe = probe
        loadProjects()
    }

    func status(for project: LocalProjectRecord) -> LocalProjectStatus {
        statuses[project.id] ?? .stopped(projectID: project.id)
    }

    func loadProjects() {
        do {
            projects = try database.loadProjects()
            for project in projects where statuses[project.id] == nil {
                statuses[project.id] = .stopped(projectID: project.id)
            }
            statusMessage = projects.isEmpty ? "No projects" : "Ready"
        } catch {
            statusMessage = "Load failed: \(error.localizedDescription)"
        }
    }

    func refreshAll() async {
        guard !isBusy else {
            return
        }
        isBusy = true
        defer { isBusy = false }

        let currentProjects = projects
        let probe = self.probe
        let processSnapshots = await Task.detached(priority: .utility) { probe.processSnapshots() }.value
        let ports = currentProjects.compactMap(\.frontendPort)
        let portListeners = await Task.detached(priority: .utility) { probe.portListeners(for: ports) }.value
        let aliveManagedPIDs = Set(currentProjects.compactMap(\.lastManagedPID).filter { probe.isPIDAlive($0) })

        var nextStatuses: [String: LocalProjectStatus] = [:]
        for project in currentProjects {
            nextStatuses[project.id] = resolver.resolve(
                project: project,
                processSnapshots: processSnapshots,
                portListeners: portListeners,
                aliveManagedPIDs: aliveManagedPIDs
            )
        }
        statuses = nextStatuses
        statusMessage = "Refreshed \(currentProjects.count) project\(currentProjects.count == 1 ? "" : "s")"
    }

    func saveDraft(_ draft: LocalProjectDraft) {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "Name is required"
            return
        }
        guard !trimmedCommand.isEmpty else {
            statusMessage = "Command is required"
            return
        }

        let trimmedPort = draft.frontendPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        let frontendPort: Int?
        if trimmedPort.isEmpty {
            frontendPort = nil
        } else if let parsedPort = Int(trimmedPort), (1...65535).contains(parsedPort) {
            frontendPort = parsedPort
        } else {
            statusMessage = "Port must be 1-65535"
            return
        }

        let now = Date()
        var nextProjects = projects
        if let existingID = draft.existingID,
           let index = nextProjects.firstIndex(where: { $0.id == existingID }) {
            var record = nextProjects[index]
            record.name = trimmedName
            record.command = trimmedCommand
            record.frontendPort = frontendPort
            record.updatedAt = now
            nextProjects[index] = record
        } else {
            nextProjects.append(
                LocalProjectRecord(
                    id: "local_project_\(UUID().uuidString.lowercased())",
                    name: trimmedName,
                    command: trimmedCommand,
                    frontendPort: frontendPort,
                    lastManagedPID: nil,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        persist(nextProjects: nextProjects, message: "Project saved")
    }

    func delete(_ project: LocalProjectRecord) {
        let nextProjects = projects.filter { $0.id != project.id }
        managedProcesses[project.id]?.terminate()
        managedProcesses[project.id] = nil
        statuses[project.id] = nil
        persist(nextProjects: nextProjects, message: "Project removed")
    }

    func start(_ project: LocalProjectRecord) async {
        guard !isBusy else {
            return
        }
        let trimmedCommand = project.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            statusMessage = "Command is required"
            return
        }

        isBusy = true
        defer { isBusy = false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", trimmedCommand]
        if let workingDirectoryPath = LocalProjectCommandIdentity(command: trimmedCommand).workingDirectoryPath {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectoryPath, isDirectory: true)
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.managedProcesses[project.id] = nil
                await self.refreshAllIgnoringBusy()
            }
        }

        do {
            try process.run()
            managedProcesses[project.id] = process
            updateProject(project.id) { record in
                record.lastManagedPID = process.processIdentifier
                record.updatedAt = Date()
            }
            statusMessage = "Started \(project.displayName)"
            await refreshAllIgnoringBusy()
        } catch {
            statusMessage = "Start failed: \(error.localizedDescription)"
        }
    }

    func stop(_ project: LocalProjectRecord) async {
        guard !isBusy else {
            return
        }
        isBusy = true
        defer { isBusy = false }

        await refreshAllIgnoringBusy()
        let status = status(for: project)
        managedProcesses[project.id]?.terminate()
        managedProcesses[project.id] = nil
        _ = await probe.terminate(pids: status.pids)
        updateProject(project.id) { record in
            record.lastManagedPID = nil
            record.updatedAt = Date()
        }
        statusMessage = "Stopped \(project.displayName)"
        await refreshAllIgnoringBusy()
    }

    func openFrontend(for project: LocalProjectRecord) {
        guard let url = status(for: project).frontendURL ?? project.frontendURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func refreshAllIgnoringBusy() async {
        let currentProjects = projects
        let probe = self.probe
        let processSnapshots = await Task.detached(priority: .utility) { probe.processSnapshots() }.value
        let ports = currentProjects.compactMap(\.frontendPort)
        let portListeners = await Task.detached(priority: .utility) { probe.portListeners(for: ports) }.value
        let aliveManagedPIDs = Set(currentProjects.compactMap(\.lastManagedPID).filter { probe.isPIDAlive($0) })
        statuses = Dictionary(uniqueKeysWithValues: currentProjects.map { project in
            (
                project.id,
                resolver.resolve(
                    project: project,
                    processSnapshots: processSnapshots,
                    portListeners: portListeners,
                    aliveManagedPIDs: aliveManagedPIDs
                )
            )
        })
    }

    private func updateProject(_ id: String, mutate: (inout LocalProjectRecord) -> Void) {
        var nextProjects = projects
        guard let index = nextProjects.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&nextProjects[index])
        persist(nextProjects: nextProjects, message: statusMessage)
    }

    private func persist(nextProjects: [LocalProjectRecord], message: String) {
        do {
            try database.saveProjects(nextProjects)
            projects = try database.loadProjects()
            statusMessage = message
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
