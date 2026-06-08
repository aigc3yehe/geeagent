import AppKit
import Foundation
import UniformTypeIdentifiers

enum SmartYTMediaAction: String, Codable, CaseIterable, Identifiable {
    case sniff
    case download
    case transcribe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sniff: "Sniff"
        case .download: "Download"
        case .transcribe: "To Text"
        }
    }

    var systemImage: String {
        switch self {
        case .sniff: "waveform.and.magnifyingglass"
        case .download: "arrow.down.circle"
        case .transcribe: "text.quote"
        }
    }
}

enum SmartYTDownloadKind: String, Codable, CaseIterable, Identifiable {
    case audio
    case image
    case video
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audio: "Audio"
        case .image: "Image"
        case .video: "Video"
        case .both: "Both"
        }
    }
}

enum SmartYTJobStatus: String, Codable, Hashable {
    case queued
    case running
    case completed
    case cancelled
    case failed

    var title: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }
}

struct SmartYTSearchCandidate: Codable, Identifiable, Hashable {
    var id: String
    var platform: String
    var title: String
    var url: String
    var sourceURL: String
    var thumbnailURL: String?
    var previewURL: String?
    var durationSeconds: Double?
    var width: Int?
    var height: Int?
    var orientation: String?
    var author: String?
    var publishedAt: String?
    var rawMetadata: [String: String]

    var candidateID: String { id }

    static func parseYTDLPJSONLines(
        _ stdout: String,
        platform: String,
        taskID: String,
        startingIndex: Int
    ) -> [SmartYTSearchCandidate] {
        var candidates: [SmartYTSearchCandidate] = []
        for rawLine in stdout.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }
            guard let candidate = parseYTDLPObject(
                object,
                platform: platform,
                taskID: taskID,
                index: startingIndex + candidates.count + 1
            ) else {
                continue
            }
            candidates.append(candidate)
        }
        if candidates.isEmpty,
           let data = stdout.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidate = parseYTDLPObject(
                object,
                platform: platform,
                taskID: taskID,
                index: startingIndex + 1
           )
        {
            candidates.append(candidate)
        }
        return candidates
    }

    private static func parseYTDLPObject(
        _ object: [String: Any],
        platform: String,
        taskID: String,
        index: Int
    ) -> SmartYTSearchCandidate? {
        let title = string(object["title"]) ?? string(object["fulltitle"]) ?? "Untitled media"
        let sourceURL = string(object["webpage_url"])
            ?? string(object["original_url"])
            ?? string(object["url"])
            ?? ""
        guard !sourceURL.isEmpty else {
            return nil
        }
        let width = int(object["width"])
        let height = int(object["height"])
        let uploadDate = string(object["upload_date"])
        return SmartYTSearchCandidate(
            id: String(format: "cand-%03d", index),
            platform: platform,
            title: title,
            url: sourceURL,
            sourceURL: sourceURL,
            thumbnailURL: string(object["thumbnail"]),
            previewURL: string(object["webpage_url"]) ?? sourceURL,
            durationSeconds: double(object["duration"]),
            width: width,
            height: height,
            orientation: orientation(width: width, height: height),
            author: string(object["uploader"]) ?? string(object["channel"]) ?? string(object["creator"]),
            publishedAt: isoDate(fromUploadDate: uploadDate),
            rawMetadata: [
                "extractor": string(object["extractor"]) ?? "",
                "extractor_key": string(object["extractor_key"]) ?? "",
                "id": string(object["id"]) ?? ""
            ].filter { !$0.value.isEmpty }
        )
    }

    fileprivate static func orientation(width: Int?, height: Int?) -> String? {
        guard let width, let height, width > 0, height > 0 else {
            return nil
        }
        if width == height { return "square" }
        return width > height ? "horizontal" : "vertical"
    }

    private static func isoDate(fromUploadDate value: String?) -> String? {
        guard let value, value.count == 8 else {
            return nil
        }
        let year = value.prefix(4)
        let month = value.dropFirst(4).prefix(2)
        let day = value.suffix(2)
        return "\(year)-\(month)-\(day)T00:00:00Z"
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}

struct SmartYTSearchTask: Codable, Identifiable, Hashable {
    var id: String
    var projectID: String?
    var runID: String?
    var taskLabel: String?
    var query: String
    var platforms: [String]
    var filters: [String: String]
    var limit: Int
    var status: String
    var candidates: [SmartYTSearchCandidate]
    var warnings: [String]
    var error: String?
    var createdAt: Date
    var updatedAt: Date
}

struct SmartYTMediaInfo: Codable, Hashable {
    var title: String
    var platform: String
    var uploader: String?
    var durationSeconds: Double?
    var webpageURL: URL?
    var thumbnailURL: URL?
    var extensionHint: String?
    var formatCount: Int

    var durationText: String {
        guard let durationSeconds else {
            return "Unknown duration"
        }
        let total = Int(durationSeconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func parse(from stdout: String, fallbackURL: String) throws -> SmartYTMediaInfo {
        let jsonText = try Self.extractJSONObjectText(from: stdout)
        let data = Data(jsonText.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SmartYTMediaError.invalidMetadata("yt-dlp did not return a JSON object.")
        }

        let title = (object["title"] as? String)?.nilIfBlank
            ?? (object["fulltitle"] as? String)?.nilIfBlank
            ?? URL(string: fallbackURL)?.lastPathComponent.nilIfBlank
            ?? "Untitled media"
        let platform = (object["extractor_key"] as? String)?.nilIfBlank
            ?? (object["extractor"] as? String)?.nilIfBlank
            ?? "Generic"
        let uploader = (object["uploader"] as? String)?.nilIfBlank
            ?? (object["channel"] as? String)?.nilIfBlank
            ?? (object["creator"] as? String)?.nilIfBlank
        let webpageURL = URL(string: (object["webpage_url"] as? String) ?? fallbackURL)
        let thumbnailURL = (object["thumbnail"] as? String).flatMap(URL.init(string:))
        let duration = Self.doubleValue(object["duration"])
        let ext = (object["ext"] as? String)?.nilIfBlank
        let formats = object["formats"] as? [[String: Any]]

        return SmartYTMediaInfo(
            title: title,
            platform: platform,
            uploader: uploader,
            durationSeconds: duration,
            webpageURL: webpageURL,
            thumbnailURL: thumbnailURL,
            extensionHint: ext,
            formatCount: formats?.count ?? 0
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func extractJSONObjectText(from stdout: String) throws -> String {
        guard let start = stdout.firstIndex(of: "{"),
              let end = stdout.lastIndex(of: "}")
        else {
            throw SmartYTMediaError.invalidMetadata("No JSON payload was found in yt-dlp output.")
        }
        return String(stdout[start...end])
    }
}

struct SmartYTMediaJob: Codable, Identifiable, Hashable {
    var id: String
    var url: String
    var action: SmartYTMediaAction
    var downloadKind: SmartYTDownloadKind
    var status: SmartYTJobStatus
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var mediaInfo: SmartYTMediaInfo?
    var outputPaths: [String]
    var transcriptPath: String?
    var transcriptPreview: String?
    var artifactDirectoryPath: String?
    var progressFraction: Double?
    var progressLabel: String?
    var log: String
    var errorMessage: String?

    var outputURLs: [URL] {
        outputPaths.map { URL(fileURLWithPath: $0) }
    }

    var transcriptURL: URL? {
        transcriptPath.map { URL(fileURLWithPath: $0) }
    }

    var canCancel: Bool {
        status == .queued || status == .running
    }

    var normalizedProgressFraction: Double? {
        guard let progressFraction else {
            return nil
        }
        return min(max(progressFraction, 0), 1)
    }
}

enum SmartYTMediaError: LocalizedError {
    case invalidURL
    case invalidMetadata(String)
    case commandFailed(command: String, detail: String)
    case youtubeAuthenticationRequired(command: String, detail: String)
    case dependencyMaintenanceFailed(String)
    case missingCookieFile(String)
    case invalidCookieFile(String)
    case browserCookieRefreshFailed(String)
    case missingArtifact(String)
    case transcriptionUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid URL."
        case let .invalidMetadata(message):
            message
        case let .commandFailed(command, detail):
            "`\(command)` failed. \(detail)"
        case let .youtubeAuthenticationRequired(command, detail):
            "`\(command)` needs authenticated YouTube cookies. \(detail)"
        case let .dependencyMaintenanceFailed(message):
            message
        case let .missingCookieFile(path):
            "Configured yt-dlp cookie file is missing: \(path)"
        case let .invalidCookieFile(message):
            message
        case let .browserCookieRefreshFailed(message):
            message
        case let .missingArtifact(message):
            message
        case let .transcriptionUnavailable(message):
            message
        }
    }

    var code: String {
        switch self {
        case .invalidURL:
            "gear.smartyt.invalid_url"
        case .invalidMetadata:
            "gear.smartyt.invalid_metadata"
        case .commandFailed:
            "gear.smartyt.command_failed"
        case .youtubeAuthenticationRequired:
            "gear.smartyt.youtube_auth_required"
        case .dependencyMaintenanceFailed:
            "gear.smartyt.dependency_maintenance_failed"
        case .missingCookieFile:
            "gear.smartyt.cookie_file_missing"
        case .invalidCookieFile:
            "gear.smartyt.cookie_file_invalid"
        case .browserCookieRefreshFailed:
            "gear.smartyt.browser_cookie_refresh_failed"
        case .missingArtifact:
            "gear.smartyt.missing_artifact"
        case .transcriptionUnavailable:
            "gear.smartyt.transcription_unavailable"
        }
    }

    var recovery: String? {
        switch self {
        case .youtubeAuthenticationRequired:
            "Choose and save an authenticated YouTube cookies.txt file in SmartYT, or pass `cookie_file` explicitly, then retry the same URL. Updating yt-dlp alone does not fix this bot-verification response."
        case .dependencyMaintenanceFailed:
            "Check that Homebrew and yt-dlp are available, then retry SmartYT after dependency maintenance succeeds."
        case .missingCookieFile:
            "Choose and save a fresh cookies.txt file in SmartYT, or clear the saved cookie configuration before retrying public media."
        case .invalidCookieFile:
            "Choose a browser-exported Netscape cookies.txt file or a supported JSON cookie export from SmartYT, then retry the same URL."
        case .browserCookieRefreshFailed:
            "Open Chrome with an authenticated YouTube session, allow local cookie access if macOS prompts, then refresh cookies from SmartYT or retry the download."
        case .commandFailed:
            "Inspect the command output for the provider-specific reason, then retry after correcting that dependency or provider state."
        default:
            nil
        }
    }
}

struct SmartYTYTDLPMaintenanceReport: Hashable {
    var checkedAt: Date
    var versionBefore: String?
    var versionAfter: String?
    var output: String
    var warning: String?

    var summary: String {
        if let warning {
            return warning
        }
        let before = versionBefore ?? "unknown"
        let after = versionAfter ?? "unknown"
        if before == after {
            return "yt-dlp is current at \(after)."
        }
        return "yt-dlp refreshed from \(before) to \(after)."
    }
}

enum SmartYTYTDLPCookieFile {
    private struct BrowserCookie: Decodable {
        var domain: String?
        var expirationDate: Double?
        var hostOnly: Bool?
        var httpOnly: Bool?
        var name: String?
        var path: String?
        var secure: Bool?
        var session: Bool?
        var value: String?
    }

    static func normalizedNetscapeData(from data: Data) throws -> Data {
        if let text = String(data: data, encoding: .utf8),
           isLikelyNetscape(text)
        {
            return data
        }

        guard let cookies = try? JSONDecoder().decode([BrowserCookie].self, from: data) else {
            throw SmartYTMediaError.invalidCookieFile(
                "Cookie file must be a Netscape cookies.txt file or a browser JSON cookie export."
            )
        }

        let lines = try cookies.compactMap(netscapeLine)
        guard !lines.isEmpty else {
            throw SmartYTMediaError.invalidCookieFile("Cookie export did not contain any usable cookies.")
        }

        let text = (["# Netscape HTTP Cookie File"] + lines).joined(separator: "\n") + "\n"
        return Data(text.utf8)
    }

    static func isLikelyNetscape(_ text: String) -> Bool {
        if text.hasPrefix("# Netscape HTTP Cookie File") {
            return true
        }
        return text
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                    return false
                }
                return trimmed.split(separator: "\t", omittingEmptySubsequences: false).count == 7
            }
    }

    private static func netscapeLine(_ cookie: BrowserCookie) throws -> String? {
        guard let rawDomain = cookie.domain?.nilIfBlank,
              let name = cookie.name,
              let value = cookie.value
        else {
            return nil
        }

        let domain = (cookie.httpOnly == true ? "#HttpOnly_" : "") + rawDomain
        let includeSubdomains = cookie.hostOnly == true ? "FALSE" : "TRUE"
        let path = cookie.path?.nilIfBlank ?? "/"
        let secure = cookie.secure == true ? "TRUE" : "FALSE"
        let expiration = cookie.session == true ? 0 : Int64(cookie.expirationDate ?? 0)
        return try [
            domain,
            includeSubdomains,
            path,
            secure,
            String(expiration),
            name,
            value
        ]
        .map(sanitizeField)
        .joined(separator: "\t")
    }

    private static func sanitizeField(_ field: String) throws -> String {
        if field.rangeOfCharacter(from: CharacterSet(charactersIn: "\t\r\n")) != nil {
            throw SmartYTMediaError.invalidCookieFile("Cookie export contains unsupported tab or newline characters.")
        }
        return field
    }
}

protocol SmartYTCommandCancellable: Sendable {
    func cancel()
}

protocol SmartYTStreamingCommandRunning: GearCommandRunning {
    func runStreaming(
        _ command: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        onStart: @escaping @Sendable (any SmartYTCommandCancellable) -> Void,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> GearCommandResult
}

extension GearShellCommandRunner: SmartYTStreamingCommandRunning {
    func runStreaming(
        _ command: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        onStart: @escaping @Sendable (any SmartYTCommandCancellable) -> Void,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> GearCommandResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", Self.smartYTShellCommand(command, arguments: arguments)]
            process.environment = Self.smartYTProcessEnvironment()

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBuffer = SmartYTCommandOutputBuffer()
            let stderrBuffer = SmartYTCommandOutputBuffer()
            let stdoutLines = SmartYTCommandLineBuffer()
            let stderrLines = SmartYTCommandLineBuffer()
            let processHandle = SmartYTProcessHandle(process: process)
            onStart(processHandle)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                stdoutBuffer.append(data)
                stdoutLines.append(data, onLine: onLine)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                stderrBuffer.append(data)
                stderrLines.append(data, onLine: onLine)
            }

            let timeoutTask = timeoutSeconds.map { timeoutSeconds in
                Task.detached(priority: .utility) {
                    let nanoseconds = UInt64(max(timeoutSeconds, 0.1) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else {
                        return
                    }
                    processHandle.terminateForTimeout()
                }
            }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                timeoutTask?.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                return GearCommandResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
            }

            timeoutTask?.cancel()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let stdoutTail = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            stdoutBuffer.append(stdoutTail)
            stdoutLines.append(stdoutTail, onLine: onLine)
            stdoutLines.flush(onLine: onLine)

            let stderrTail = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            stderrBuffer.append(stderrTail)
            stderrLines.append(stderrTail, onLine: onLine)
            stderrLines.flush(onLine: onLine)

            var stderr = stderrBuffer.string()
            if processHandle.didTimeOut {
                let timeoutMessage = "Command timed out after \(Int(timeoutSeconds ?? 0))s: \(command)"
                stderr = [stderr, timeoutMessage].filter { !$0.isEmpty }.joined(separator: "\n")
                return GearCommandResult(exitCode: 124, stdout: stdoutBuffer.string(), stderr: stderr)
            }

            return GearCommandResult(
                exitCode: process.terminationStatus,
                stdout: stdoutBuffer.string(),
                stderr: stderr
            )
        }.value
    }

    private static func smartYTShellCommand(_ command: String, arguments: [String]) -> String {
        ([command] + arguments)
            .map(smartYTShellQuote)
            .joined(separator: " ")
    }

    private static func smartYTShellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func smartYTProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HYPERFRAMES_NO_UPDATE_CHECK"] = "1"
        environment["CI"] = environment["CI"] ?? "1"

        let commonPaths = [
            environment["PATH"],
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        environment["PATH"] = commonPaths.compactMap(\.self).joined(separator: ":")
        return environment
    }
}

private final class SmartYTProcessHandle: @unchecked Sendable, SmartYTCommandCancellable {
    let process: Process
    private let lock = NSLock()
    private var timedOut = false

    init(process: Process) {
        self.process = process
    }

    var didTimeOut: Bool {
        lock.lock()
        let value = timedOut
        lock.unlock()
        return value
    }

    func cancel() {
        terminate(markTimedOut: false)
    }

    func terminateForTimeout() {
        terminate(markTimedOut: true)
    }

    private func terminate(markTimedOut: Bool) {
        lock.lock()
        if markTimedOut {
            timedOut = true
        }
        lock.unlock()
        guard process.isRunning else {
            return
        }
        process.interrupt()
        Task.detached(priority: .utility) { [process] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard process.isRunning else {
                return
            }
            process.terminate()
        }
    }
}

private final class SmartYTCommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

private final class SmartYTCommandLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ data: Data, onLine: @escaping @Sendable (String) -> Void) {
        guard !data.isEmpty,
              let chunk = String(data: data, encoding: .utf8),
              !chunk.isEmpty
        else {
            return
        }

        let lines: [String]
        lock.lock()
        buffer.append(chunk)
        lines = extractLinesLocked()
        lock.unlock()

        for line in lines where !line.isEmpty {
            onLine(line)
        }
    }

    func flush(onLine: @escaping @Sendable (String) -> Void) {
        let trailing: String?
        lock.lock()
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        trailing = value.isEmpty ? nil : buffer
        buffer = ""
        lock.unlock()

        if let trailing {
            onLine(trailing)
        }
    }

    private func extractLinesLocked() -> [String] {
        var lines: [String] = []
        while let boundary = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            lines.append(String(buffer[..<boundary]))
            var next = buffer.index(after: boundary)
            while next < buffer.endIndex, buffer[next] == "\n" || buffer[next] == "\r" {
                next = buffer.index(after: next)
            }
            buffer = String(buffer[next...])
        }
        return lines
    }
}

private final class SmartYTProgressLineSink: @unchecked Sendable {
    weak var store: SmartYTMediaGearStore?
    let jobID: String

    init(store: SmartYTMediaGearStore, jobID: String) {
        self.store = store
        self.jobID = jobID
    }

    func handle(_ line: String) {
        Task { @MainActor [weak store] in
            store?.handleYTDLPOutputLine(line, for: jobID)
        }
    }
}

@MainActor
final class SmartYTMediaGearStore: ObservableObject {
    static let shared = SmartYTMediaGearStore()

    @Published var urlString = ""
    @Published var selectedDownloadKind: SmartYTDownloadKind = .audio
    @Published var languagePreference = ""
    @Published private(set) var mediaInfo: SmartYTMediaInfo?
    @Published private(set) var jobs: [SmartYTMediaJob] = []
    @Published private(set) var searchTasks: [SmartYTSearchTask] = []
    @Published var selectedJobID: SmartYTMediaJob.ID?
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var isBusy = false
    @Published private(set) var cookieFilePath = ""

    private let runner: GearCommandRunning
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let dataRootOverride: URL?
    private var jobTasks: [String: Task<Void, Never>] = [:]
    private var activeCommandHandles: [String: any SmartYTCommandCancellable] = [:]
    private var ytdlpMaintenanceTask: Task<SmartYTYTDLPMaintenanceReport, Error>?
    private var lastPersistedProgressStep: [String: Int] = [:]
    private var lastProgressLabelByJobID: [String: String] = [:]
    static let cookieFileDefaultsKey = "geeagent.smartyt.cookies.file"
    private static let ytdlpMaintenanceDefaultsKey = "geeagent.smartyt.ytdlp.lastMaintenanceAt"
    private static let ytdlpMaintenanceInterval: TimeInterval = 24 * 60 * 60
    private static let savedCookieFileName = "yt-dlp-cookies.txt"
    private static let browserCookieRefreshProbeURL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

    var selectedJob: SmartYTMediaJob? {
        jobs.first { $0.id == selectedJobID } ?? jobs.first
    }

    var cookieStatusTitle: String {
        guard let path = cookieFilePath.nilIfBlank else {
            return "No cookies saved"
        }
        return fileManager.fileExists(atPath: path) ? "Cookies saved" : "Cookie file missing"
    }

    var cookieStatusDetail: String {
        guard let path = cookieFilePath.nilIfBlank else {
            return "Optional for YouTube bot checks"
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return fileManager.fileExists(atPath: path) ? name : "Choose cookies.txt again"
    }

    init(
        runner: GearCommandRunning = GearShellCommandRunner(),
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        dataRoot: URL? = nil
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.defaults = defaults
        self.dataRootOverride = dataRoot
        self.cookieFilePath = defaults.string(forKey: Self.cookieFileDefaultsKey) ?? ""
        loadJobs()
        loadSearchTasks()
    }

    func loadJobs() {
        do {
            let root = try jobsRoot()
            let entries = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            jobs = entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .compactMap(loadJob)
                .sorted { $0.createdAt > $1.createdAt }
            selectedJobID = selectedJobID ?? jobs.first?.id
        } catch {
            statusMessage = "Could not load SmartYT jobs: \(error.localizedDescription)"
        }
    }

    func chooseCookieFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose yt-dlp Cookies File"
        panel.message = "Choose a browser-exported cookies.txt or JSON cookie file for YouTube and other yt-dlp sites."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.text, .json, .data]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let savedURL = try saveCookieFile(from: url)
            cookieFilePath = savedURL.path
            defaults.set(savedURL.path, forKey: Self.cookieFileDefaultsKey)
            statusMessage = "Saved yt-dlp cookies."
        } catch {
            statusMessage = "Could not save cookies: \(error.localizedDescription)"
        }
    }

    func clearCookieFile() {
        if let path = cookieFilePath.nilIfBlank {
            let savedPath = try? savedCookieFileURL().path
            if path == savedPath {
                try? fileManager.removeItem(atPath: path)
            }
        }
        cookieFilePath = ""
        defaults.removeObject(forKey: Self.cookieFileDefaultsKey)
        statusMessage = "Cleared saved yt-dlp cookies."
    }

    func refreshCookieFileFromBrowser() {
        let probeURL = normalizedURL(urlString) ?? Self.browserCookieRefreshProbeURL
        Task {
            await runBusy("Refreshing YouTube cookies from Chrome...") {
                let savedURL = try await refreshSavedCookieFileFromBrowser(for: probeURL)
                cookieFilePath = savedURL.path
                defaults.set(savedURL.path, forKey: Self.cookieFileDefaultsKey)
                statusMessage = "Refreshed YouTube cookies from Chrome."
            }
        }
    }

    func searchCandidatesForAgent(args: [String: Any]) async -> [String: Any] {
        guard let query = Self.stringArg(args, "query")?.nilIfBlank else {
            return [
                "gear_id": SmartYTMediaGearDescriptor.gearID,
                "capability_id": "smartyt.search_candidates",
                "status": "failed",
                "error": "`query` is required.",
                "recovery": "Call smartyt.search_candidates with an explicit search query."
            ]
        }

        let platforms = (Self.stringArrayArg(args, "platforms") ?? ["youtube"])
            .map { Self.normalizedPlatform($0) }
            .filter { !$0.isEmpty }
        guard !platforms.isEmpty else {
            return [
                "gear_id": SmartYTMediaGearDescriptor.gearID,
                "capability_id": "smartyt.search_candidates",
                "status": "failed",
                "code": "gear.smartyt.platforms_required",
                "error": "`platforms` must include at least one platform when provided.",
                "recovery": "Retry with `platforms: [\"youtube\"]` or omit platforms to use the default."
            ]
        }
        let limit = max(1, min(Self.intArg(args, "limit") ?? 30, 50))
        let taskID = "smartyt-search-\(Self.timestamp())-\(UUID().uuidString.prefix(8))"
        let filters = Self.stringDictionaryArg(args, "filters")
        var candidates: [SmartYTSearchCandidate] = []
        var warnings: [String] = []

        for platform in platforms {
            switch platform {
            case "youtube":
                do {
                    let remaining = max(limit - candidates.count, 0)
                    guard remaining > 0 else { continue }
                    let results = try await searchYouTubeCandidates(
                        query: query,
                        limit: remaining,
                        taskID: taskID,
                        startingIndex: candidates.count,
                        cookieFilePath: Self.stringArg(args, "cookie_file") ?? Self.stringArg(args, "cookies_file")
                    )
                    candidates.append(contentsOf: results)
                } catch {
                    warnings.append("youtube search failed: \(error.localizedDescription)")
                }
            case "douyin", "xiaohongshu":
                do {
                    let remaining = max(limit - candidates.count, 0)
                    guard remaining > 0 else { continue }
                    let results = try await searchChinaShortVideoCandidates(
                        query: query,
                        platform: platform,
                        limit: remaining,
                        startingIndex: candidates.count
                    )
                    candidates.append(contentsOf: results)
                    if results.isEmpty {
                        warnings.append("\(platform) search returned no video candidates.")
                    }
                } catch {
                    warnings.append("\(platform) search failed: \(error.localizedDescription)")
                }
            case "bilibili":
                warnings.append("\(platform) search is not implemented yet; no fallback search was attempted.")
            default:
                warnings.append("\(platform) search is not supported.")
            }
        }

        let status: String
        let error: String?
        if candidates.isEmpty {
            status = "failed"
            error = warnings.isEmpty ? "No candidates were found." : warnings.joined(separator: " ")
        } else if warnings.isEmpty {
            status = "succeeded"
            error = nil
        } else {
            status = "partial"
            error = warnings.joined(separator: " ")
        }

        let now = Date()
        let task = SmartYTSearchTask(
            id: taskID,
            projectID: Self.stringArg(args, "project_id"),
            runID: Self.stringArg(args, "run_id"),
            taskLabel: Self.stringArg(args, "task_label"),
            query: query,
            platforms: platforms,
            filters: filters,
            limit: limit,
            status: status,
            candidates: candidates,
            warnings: warnings,
            error: error,
            createdAt: now,
            updatedAt: now
        )
        do {
            try persist(task)
        } catch {
            statusMessage = "Could not save search task: \(error.localizedDescription)"
            return [
                "gear_id": SmartYTMediaGearDescriptor.gearID,
                "capability_id": "smartyt.search_candidates",
                "status": "failed",
                "code": "gear.smartyt.search_persist_failed",
                "search_task_id": task.id,
                "task_id": task.id,
                "candidates": candidates.map(candidatePayload),
                "warnings": warnings,
                "error": "Could not save SmartYT search task: \(error.localizedDescription)",
                "recovery": "Check GeeAgent application data directory permissions and retry."
            ]
        }
        searchTasks.insert(task, at: 0)
        statusMessage = candidates.isEmpty ? "Search returned no candidates." : "Found \(candidates.count) candidate(s)."

        return searchTaskPayload(task)
    }

    func sniffCurrentURL() async {
        guard let cleanURL = normalizedURL(urlString) else {
            statusMessage = SmartYTMediaError.invalidURL.localizedDescription
            return
        }
        await runBusy("Sniffing media...") {
            let info = try await sniff(url: cleanURL, cookieFilePath: nil)
            mediaInfo = info
            statusMessage = "Sniffed \(info.title)."
        }
    }

    func downloadCurrentURL(kind: SmartYTDownloadKind) {
        guard let cleanURL = normalizedURL(urlString) else {
            statusMessage = SmartYTMediaError.invalidURL.localizedDescription
            return
        }
        _ = enqueue(action: .download, url: cleanURL, downloadKind: kind, language: languagePreference.nilIfBlank, outputDirectory: nil)
    }

    func transcribeCurrentURL() {
        guard let cleanURL = normalizedURL(urlString) else {
            statusMessage = SmartYTMediaError.invalidURL.localizedDescription
            return
        }
        _ = enqueue(action: .transcribe, url: cleanURL, downloadKind: .audio, language: languagePreference.nilIfBlank, outputDirectory: nil)
    }

    func cancelSelectedJob() {
        guard let selectedJob else {
            return
        }
        cancel(jobID: selectedJob.id)
    }

    func cancel(jobID: String) {
        guard let job = jobs.first(where: { $0.id == jobID }), job.canCancel else {
            return
        }
        activeCommandHandles[jobID]?.cancel()
        jobTasks[jobID]?.cancel()
        cleanupActiveExecution(for: jobID)
        updateJob(jobID) { current in
            current.status = .cancelled
            current.updatedAt = Date()
            current.progressLabel = "Cancelled"
            current.errorMessage = nil
            current.log.append("\nCancelled at \(Date().formatted()).")
        }
        statusMessage = "Cancelled \(job.title)."
    }

    @discardableResult
    func deleteSelectedJob() -> Bool {
        guard let selectedJob else {
            return false
        }
        return deleteJob(id: selectedJob.id)
    }

    @discardableResult
    func deleteJob(id: String) -> Bool {
        guard let job = jobs.first(where: { $0.id == id }) else {
            return false
        }
        guard !job.canCancel else {
            statusMessage = "Cancel or finish the active SmartYT job before deleting it."
            return false
        }

        do {
            try deleteAssociatedJobData(for: job)
            try deletePersistedJobRecord(id)
            jobs.removeAll { $0.id == id }
            cleanupActiveExecution(for: id)
            if selectedJobID == id {
                selectedJobID = jobs.first?.id
            }
            isBusy = jobs.contains { $0.status == .running || $0.status == .queued }
            statusMessage = "Deleted SmartYT job record."
            return true
        } catch {
            statusMessage = "Could not delete SmartYT job: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func deleteCompletedAndFailedJobs() -> Int {
        let removableIDs = jobs
            .filter { $0.status == .completed || $0.status == .failed }
            .map(\.id)
        var deletedCount = 0
        for id in removableIDs where deleteJob(id: id) {
            deletedCount += 1
        }
        statusMessage = deletedCount == 0
            ? "No completed or failed SmartYT jobs to delete."
            : "Deleted \(deletedCount) completed or failed SmartYT job record\(deletedCount == 1 ? "" : "s")."
        return deletedCount
    }

    func enqueueAgentAction(
        capabilityID: String,
        url: String,
        downloadKind: SmartYTDownloadKind?,
        language: String?,
        outputDirectory: String?,
        cookieFilePath: String? = nil
    ) -> [String: Any] {
        guard let cleanURL = normalizedURL(url) else {
            return [
                "gear_id": SmartYTMediaGearDescriptor.gearID,
                "capability_id": capabilityID,
                "status": "failed",
                "error": "invalid_url"
            ]
        }

        let action: SmartYTMediaAction
        switch capabilityID {
        case "smartyt.sniff":
            action = .sniff
        case "smartyt.download":
            action = .download
        case "smartyt.transcribe":
            action = .transcribe
        default:
            return [
                "gear_id": SmartYTMediaGearDescriptor.gearID,
                "capability_id": capabilityID,
                "status": "failed",
                "error": "unsupported_capability"
            ]
        }

        let actionDefaultKind = action == .transcribe
            ? SmartYTDownloadKind.audio
            : Self.defaultDownloadKind(for: cleanURL)
        let job = enqueue(
            action: action,
            url: cleanURL,
            downloadKind: downloadKind ?? actionDefaultKind,
            language: language?.nilIfBlank,
            outputDirectory: outputDirectory,
            cookieFilePath: cookieFilePath
        )

        return [
            "gear_id": SmartYTMediaGearDescriptor.gearID,
            "capability_id": capabilityID,
            "action": action.rawValue,
            "job_id": job.id,
            "status": job.status.rawValue,
            "url": cleanURL,
            "download_kind": job.downloadKind.rawValue,
            "artifact_root": artifactDirectory(for: job).path,
            "next_step": "Open SmartYT Media to monitor progress; future Gear status capabilities can poll this job_id."
        ]
    }

    func runImmediateAgentDownload(
        url: String,
        downloadKind: SmartYTDownloadKind?,
        outputDirectory: String?,
        cookieFilePath: String? = nil
    ) async -> [String: Any] {
        guard let cleanURL = normalizedURL(url) else {
            return [
                "gear_id": SmartYTMediaGearDescriptor.gearID,
                "capability_id": "smartyt.download_now",
                "status": "failed",
                "error": "invalid_url"
            ]
        }

        let kind = downloadKind ?? Self.defaultDownloadKind(for: cleanURL)
        if outputDirectory == nil,
           let existing = reusableCompletedDownload(for: cleanURL, kind: kind)
        {
            selectedJobID = existing.id
            let outputPaths = reusableOutputPaths(for: existing, kind: kind)
            statusMessage = "Using existing download."
            return agentPayload(
                capabilityID: "smartyt.download_now",
                job: existing,
                status: "completed",
                outputPaths: outputPaths,
                reused: true
            )
        }

        let now = Date()
        let id = "smartyt-\(Self.timestamp())-\(UUID().uuidString.prefix(8))"
        let artifactDirectory = resolvedArtifactDirectory(jobID: id, requestedPath: outputDirectory)
        let job = SmartYTMediaJob(
            id: id,
            url: cleanURL,
            action: .download,
            downloadKind: kind,
            status: .running,
            title: "Download",
            createdAt: now,
            updatedAt: now,
            mediaInfo: nil,
            outputPaths: [],
            transcriptPath: nil,
            transcriptPreview: nil,
            artifactDirectoryPath: artifactDirectory.path,
            progressFraction: 0,
            progressLabel: "Preparing download...",
            log: "Started immediate workflow download for \(cleanURL)",
            errorMessage: nil
        )
        jobs.insert(job, at: 0)
        selectedJobID = job.id
        persist(job)
        isBusy = true
        statusMessage = "Downloading media..."
        defer { isBusy = jobs.contains { $0.status == .running || $0.status == .queued } }

        do {
            let jobRoot = try ensureArtifactDirectory(for: job)
            let info = Self.isDirectImageURL(cleanURL) ? nil : try? await sniff(url: cleanURL, cookieFilePath: cookieFilePath)
            let outputs = try await download(url: cleanURL, kind: kind, into: jobRoot, cookieFilePath: cookieFilePath, trackedJobID: nil)
            updateJob(id) { current in
                current.mediaInfo = info
                current.title = info?.title ?? "Downloaded Media"
                current.outputPaths = outputs.map(\.path)
                current.status = .completed
                current.updatedAt = Date()
                current.log.append("\nImmediate download completed with \(outputs.count) artifact(s).")
            }
            statusMessage = "Download completed."
            let completed = jobs.first { $0.id == id } ?? job
            return agentPayload(
                capabilityID: "smartyt.download_now",
                job: completed,
                status: "completed",
                outputPaths: outputs.map(\.path)
            )
        } catch {
            updateJob(id) { current in
                current.status = .failed
                current.errorMessage = error.localizedDescription
                current.updatedAt = Date()
                current.log.append("\nFailed: \(error.localizedDescription)")
            }
            statusMessage = error.localizedDescription
            let failed = jobs.first { $0.id == id } ?? job
            return agentPayload(
                capabilityID: "smartyt.download_now",
                job: failed,
                status: "failed",
                outputPaths: [],
                error: error.localizedDescription,
                smartYTError: error as? SmartYTMediaError
            )
        }
    }

    func revealSelectedJob() {
        guard let selectedJob else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([artifactDirectory(for: selectedJob)])
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func enqueue(
        action: SmartYTMediaAction,
        url: String,
        downloadKind: SmartYTDownloadKind,
        language: String?,
        outputDirectory: String?,
        cookieFilePath: String? = nil
    ) -> SmartYTMediaJob {
        let now = Date()
        let id = "smartyt-\(Self.timestamp())-\(UUID().uuidString.prefix(8))"
        let artifactDirectory = resolvedArtifactDirectory(jobID: id, requestedPath: outputDirectory)
        let job = SmartYTMediaJob(
            id: id,
            url: url,
            action: action,
            downloadKind: downloadKind,
            status: .queued,
            title: action.title,
            createdAt: now,
            updatedAt: now,
            mediaInfo: nil,
            outputPaths: [],
            transcriptPath: nil,
            transcriptPreview: nil,
            artifactDirectoryPath: artifactDirectory.path,
            progressFraction: action == .download || action == .transcribe ? 0 : nil,
            progressLabel: action == .download ? "Queued for download." : action == .transcribe ? "Queued for transcript." : nil,
            log: "Queued \(action.rawValue) for \(url)",
            errorMessage: nil
        )
        jobs.insert(job, at: 0)
        selectedJobID = job.id
        statusMessage = "\(action.title) queued."
        persist(job)

        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else {
                return
            }
            await self.run(jobID: job.id, language: language, cookieFilePath: cookieFilePath)
        }
        jobTasks[job.id] = task
        return job
    }

    private func agentPayload(
        capabilityID: String,
        job: SmartYTMediaJob,
        status: String,
        outputPaths: [String],
        error: String? = nil,
        smartYTError: SmartYTMediaError? = nil,
        reused: Bool = false
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "gear_id": SmartYTMediaGearDescriptor.gearID,
            "capability_id": capabilityID,
            "action": job.action.rawValue,
            "job_id": job.id,
            "status": status,
            "url": job.url,
            "download_kind": job.downloadKind.rawValue,
            "artifact_root": artifactDirectory(for: job).path,
            "output_paths": outputPaths
        ]
        if reused {
            payload["reused_existing_download"] = true
        }
        if let mediaInfo = job.mediaInfo {
            payload["media_info"] = [
                "title": mediaInfo.title,
                "platform": mediaInfo.platform,
                "uploader": (mediaInfo.uploader as Any?) ?? NSNull(),
                "duration_seconds": (mediaInfo.durationSeconds as Any?) ?? NSNull(),
                "webpage_url": (mediaInfo.webpageURL?.absoluteString as Any?) ?? NSNull(),
                "thumbnail_url": (mediaInfo.thumbnailURL?.absoluteString as Any?) ?? NSNull(),
                "extension_hint": (mediaInfo.extensionHint as Any?) ?? NSNull(),
                "format_count": mediaInfo.formatCount
            ]
        }
        if let error {
            payload["error"] = error
            if let smartYTError = smartYTError
                ?? Self.smartYTErrorFromMessage(error)
                ?? job.errorMessage.flatMap(Self.smartYTErrorFromMessage)
            {
                payload["error_code"] = smartYTError.code
                if let recovery = smartYTError.recovery {
                    payload["recovery"] = recovery
                }
            }
        }
        return payload
    }

    func taskPayload(taskID: String) -> [String: Any] {
        if let job = jobs.first(where: { $0.id == taskID }) {
            return [
                "gear_id": SmartYTMediaGearDescriptor.gearID,
                "capability_id": "smartyt.get_task",
                "status": "succeeded",
                "task": jobPayload(job),
                "error": NSNull()
            ]
        }
        if let task = searchTasks.first(where: { $0.id == taskID }) {
            return [
                "gear_id": SmartYTMediaGearDescriptor.gearID,
                "capability_id": "smartyt.get_task",
                "status": "succeeded",
                "task": searchTaskSummaryPayload(task),
                "candidates": task.candidates.map(candidatePayload),
                "error": NSNull()
            ]
        }
        return [
            "gear_id": SmartYTMediaGearDescriptor.gearID,
            "capability_id": "smartyt.get_task",
            "status": "failed",
            "error": "Task `\(taskID)` was not found.",
            "recovery": "Call smartyt.list_tasks to inspect available SmartYT tasks."
        ]
    }

    func listTasksPayload(limit: Int) -> [String: Any] {
        let jobPayloads = jobs.map(jobPayload)
        let searchPayloads = searchTasks.map(searchTaskSummaryPayload)
        let tasks = Array((jobPayloads + searchPayloads).prefix(min(max(limit, 1), 200)))
        return [
            "gear_id": SmartYTMediaGearDescriptor.gearID,
            "capability_id": "smartyt.list_tasks",
            "status": "succeeded",
            "tasks": tasks,
            "count": tasks.count,
            "error": NSNull()
        ]
    }

    private func reusableCompletedDownload(
        for url: String,
        kind: SmartYTDownloadKind
    ) -> SmartYTMediaJob? {
        jobs.first { job in
            job.action == .download &&
                job.status == .completed &&
                job.url == url &&
                !reusableOutputPaths(for: job, kind: kind).isEmpty
        }
    }

    private func reusableOutputPaths(
        for job: SmartYTMediaJob,
        kind: SmartYTDownloadKind
    ) -> [String] {
        let existingPaths = job.outputPaths.filter { fileManager.fileExists(atPath: $0) }
        switch kind {
        case .audio:
            return existingPaths.filter { Self.isAudioPath($0) }
        case .image:
            return existingPaths.filter { Self.isImagePath($0) }
        case .video:
            return existingPaths.filter { Self.isVideoPath($0) }
        case .both:
            return existingPaths
        }
    }

    private static func isAudioPath(_ path: String) -> Bool {
        ["mp3", "m4a", "wav", "aac", "opus"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    static func isDirectImageURL(_ raw: String) -> Bool {
        imageExtension(for: raw) != nil
    }

    static func defaultDownloadKind(for raw: String) -> SmartYTDownloadKind {
        isDirectImageURL(raw) ? .image : .video
    }

    private static func isImagePath(_ path: String) -> Bool {
        imageExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private static func isVideoPath(_ path: String) -> Bool {
        ["mp4", "mov", "mkv", "webm"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private func run(jobID: String, language: String?, cookieFilePath: String?) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else {
            cleanupActiveExecution(for: jobID)
            return
        }
        guard job.status != .cancelled else {
            cleanupActiveExecution(for: jobID)
            return
        }

        updateJob(jobID) { current in
            current.status = .running
            current.updatedAt = Date()
            current.progressFraction = current.action == .sniff || current.action == .download || current.action == .transcribe ? 0 : current.progressFraction
            current.progressLabel = current.action == .sniff
                ? "Fetching metadata..."
                : current.action == .download
                    ? "Preparing download..."
                    : current.action == .transcribe
                        ? "Checking subtitles..."
                        : current.progressLabel
            current.log.append("\nStarted at \(Date().formatted()).")
        }
        isBusy = true
        defer {
            cleanupActiveExecution(for: jobID)
            isBusy = jobs.contains { $0.status == .running || $0.status == .queued }
        }

        do {
            let jobRoot = try ensureArtifactDirectory(for: job)
            try Task.checkCancellation()
            switch job.action {
            case .sniff:
                let info = try await sniff(url: job.url, cookieFilePath: cookieFilePath, trackedJobID: jobID)
                mediaInfo = info
                updateJob(jobID) { current in
                    current.mediaInfo = info
                    current.title = info.title
                    current.status = .completed
                    current.updatedAt = Date()
                    current.progressFraction = 1
                    current.progressLabel = "Metadata extracted."
                    current.log.append("\nMetadata extracted.")
                }
                statusMessage = "Sniffed \(info.title)."
            case .download:
                let outputs = try await download(url: job.url, kind: job.downloadKind, into: jobRoot, cookieFilePath: cookieFilePath, trackedJobID: jobID)
                updateJob(jobID) { current in
                    current.outputPaths = outputs.map(\.path)
                    current.status = .completed
                    current.updatedAt = Date()
                    current.progressFraction = 1
                    current.progressLabel = "Download completed."
                    current.log.append("\nDownloaded \(outputs.count) artifact(s).")
                }
                statusMessage = "Download completed."
            case .transcribe:
                let result = try await transcribe(url: job.url, language: language, into: jobRoot, cookieFilePath: cookieFilePath, trackedJobID: jobID)
                updateJob(jobID) { current in
                    current.outputPaths = result.artifacts.map(\.path)
                    current.transcriptPath = result.transcriptURL.path
                    current.transcriptPreview = Self.preview(result.text)
                    current.status = .completed
                    current.updatedAt = Date()
                    current.progressFraction = 1
                    current.progressLabel = "Transcript completed."
                    current.log.append("\nTranscript created via \(result.source).")
                }
                statusMessage = "Transcript completed."
            }
        } catch {
            if Task.isCancelled || jobs.first(where: { $0.id == jobID })?.status == .cancelled {
                updateJob(jobID) { current in
                    current.status = .cancelled
                    current.updatedAt = Date()
                    current.progressLabel = "Cancelled"
                    current.errorMessage = nil
                    if !current.log.contains("Cancelled at") {
                        current.log.append("\nCancelled at \(Date().formatted()).")
                    }
                }
                statusMessage = "Cancelled job."
            } else {
                updateJob(jobID) { current in
                    current.status = .failed
                    current.errorMessage = error.localizedDescription
                    current.updatedAt = Date()
                    current.log.append("\nFailed: \(error.localizedDescription)")
                }
                statusMessage = error.localizedDescription
            }
        }

        if let updated = jobs.first(where: { $0.id == jobID }) {
            persist(updated)
        }
    }

    private func sniff(
        url: String,
        cookieFilePath: String?,
        trackedJobID: String? = nil
    ) async throws -> SmartYTMediaInfo {
        _ = try await refreshYTDLPIfNeeded(reason: "sniff")
        let result = try await runYTDLP(
            [
                "--dump-single-json",
                "--no-warnings",
                "--skip-download",
                url
            ],
            cookieFilePath: cookieFilePath,
            trackedJobID: trackedJobID,
            timeoutSeconds: 90
        )
        guard result.exitCode == 0 else {
            throw Self.ytdlpFailure(command: "yt-dlp --dump-single-json", result: result)
        }
        return try SmartYTMediaInfo.parse(from: result.stdout, fallbackURL: url)
    }

    private func searchYouTubeCandidates(
        query: String,
        limit: Int,
        taskID: String,
        startingIndex: Int,
        cookieFilePath: String?
    ) async throws -> [SmartYTSearchCandidate] {
        _ = try await refreshYTDLPIfNeeded(reason: "search")
        let result = try await runYTDLP(
            [
                "--dump-json",
                "--no-warnings",
                "--skip-download",
                "ytsearch\(limit):\(query)"
            ],
            cookieFilePath: cookieFilePath,
            timeoutSeconds: 120
        )
        guard result.exitCode == 0 else {
            throw Self.ytdlpFailure(command: "yt-dlp ytsearch", result: result)
        }
        return SmartYTSearchCandidate.parseYTDLPJSONLines(
            result.stdout,
            platform: "youtube",
            taskID: taskID,
            startingIndex: startingIndex
        )
    }

    private func searchChinaShortVideoCandidates(
        query: String,
        platform: String,
        limit: Int,
        startingIndex: Int
    ) async throws -> [SmartYTSearchCandidate] {
        switch platform {
        case "xiaohongshu":
            return try await searchXiaohongshuCandidates(
                query: query,
                limit: limit,
                startingIndex: startingIndex
            )
        case "douyin":
            return try await searchDouyinCandidates(
                query: query,
                limit: limit,
                startingIndex: startingIndex
            )
        default:
            throw SmartYTMediaError.commandFailed(
                command: "smartyt.search_candidates",
                detail: Self.platformSearchUnavailableMessage(platform: platform)
            )
        }
    }

    private func searchXiaohongshuCandidates(
        query: String,
        limit: Int,
        startingIndex: Int
    ) async throws -> [SmartYTSearchCandidate] {
        let result = try await runCommand(
            "python3",
            arguments: [
                "-m", "xhs_cli.cli",
                "search", query,
                "--type", "video",
                "--json"
            ],
            timeoutSeconds: 120,
            trackedJobID: nil
        )
        guard result.exitCode == 0 else {
            throw Self.cliFailure(command: "python3 -m xhs_cli.cli search", result: result)
        }
        return try Self.parseXiaohongshuSearchCandidates(
            result.stdout,
            limit: limit,
            startingIndex: startingIndex
        )
    }

    private func searchDouyinCandidates(
        query: String,
        limit: Int,
        startingIndex: Int
    ) async throws -> [SmartYTSearchCandidate] {
        let result = try await runCommand(
            "python3",
            arguments: [
                "-m", "dy_cli.main",
                "search", query,
                "--type", "video",
                "--count", "\(limit)",
                "--json-output"
            ],
            timeoutSeconds: 120,
            trackedJobID: nil
        )
        guard result.exitCode == 0 else {
            throw Self.cliFailure(command: "python3 -m dy_cli.main search", result: result)
        }
        return try Self.parseDouyinSearchCandidates(
            result.stdout,
            limit: limit,
            startingIndex: startingIndex
        )
    }

    private func download(
        url: String,
        kind: SmartYTDownloadKind,
        into directory: URL,
        cookieFilePath: String?,
        trackedJobID: String? = nil
    ) async throws -> [URL] {
        if Self.isDirectImageURL(url) {
            switch kind {
            case .audio:
                throw SmartYTMediaError.missingArtifact("Image URL cannot be downloaded as audio.")
            case .image, .video, .both:
                return [try await downloadImage(url: url, into: directory)]
            }
        }
        if Self.platformForURL(url) == "douyin" {
            return try await downloadDouyinMedia(
                url: url,
                kind: kind,
                into: directory,
                trackedJobID: trackedJobID
            )
        }
        var outputs: [URL] = []
        switch kind {
        case .audio:
            outputs.append(try await downloadAudio(url: url, into: directory, cookieFilePath: cookieFilePath, trackedJobID: trackedJobID))
        case .image:
            outputs.append(try await downloadImage(url: url, into: directory))
        case .video:
            outputs.append(try await downloadVideo(url: url, into: directory, cookieFilePath: cookieFilePath, trackedJobID: trackedJobID))
        case .both:
            outputs.append(try await downloadVideo(url: url, into: directory, cookieFilePath: cookieFilePath, trackedJobID: trackedJobID))
            outputs.append(try await downloadAudio(url: url, into: directory, cookieFilePath: cookieFilePath, trackedJobID: trackedJobID))
        }
        return outputs
    }

    private func downloadDouyinMedia(
        url: String,
        kind: SmartYTDownloadKind,
        into directory: URL,
        trackedJobID: String?
    ) async throws -> [URL] {
        switch kind {
        case .image:
            throw SmartYTMediaError.missingArtifact("Douyin video URLs cannot be downloaded as direct images.")
        case .video, .audio, .both:
            break
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let trackedJobID {
            updateJobProgress(
                trackedJobID,
                fraction: 0.08,
                label: kind == .audio ? "Downloading Douyin audio with dy-cli..." : "Downloading Douyin video with dy-cli...",
                persistence: .phase,
                logLine: "Using dy-cli for Douyin media download."
            )
        }

        var arguments = [
            "-m", "dy_cli.main",
            "download",
            "--output-dir", directory.path
        ]
        if kind == .audio || kind == .both {
            arguments.append("--music")
        }
        arguments.append(url)

        let result = try await runCommand(
            "python3",
            arguments: arguments,
            timeoutSeconds: nil,
            trackedJobID: trackedJobID
        )
        guard result.exitCode == 0 else {
            throw Self.cliFailure(command: "python3 -m dy_cli.main download", result: result)
        }

        let videos = mediaFiles(in: directory, extensions: Self.videoExtensions)
        let audio = mediaFiles(in: directory, extensions: Self.audioExtensions)
        switch kind {
        case .video:
            guard !videos.isEmpty else {
                throw SmartYTMediaError.missingArtifact("dy-cli finished but no Douyin video artifact was found.")
            }
            return videos
        case .audio:
            guard !audio.isEmpty else {
                throw SmartYTMediaError.missingArtifact("dy-cli finished but no Douyin audio artifact was found.")
            }
            return audio
        case .both:
            guard !videos.isEmpty else {
                throw SmartYTMediaError.missingArtifact("dy-cli finished but no Douyin video artifact was found.")
            }
            guard !audio.isEmpty else {
                throw SmartYTMediaError.missingArtifact("dy-cli finished but no Douyin music artifact was found.")
            }
            return videos + audio
        case .image:
            throw SmartYTMediaError.missingArtifact("Douyin video URLs cannot be downloaded as direct images.")
        }
    }

    private func transcribe(
        url: String,
        language: String?,
        into directory: URL,
        cookieFilePath: String?,
        trackedJobID: String? = nil
    ) async throws -> SmartYTTranscriptionResult {
        if let subtitle = try await extractSubtitle(url: url, language: language, into: directory, cookieFilePath: cookieFilePath, trackedJobID: trackedJobID) {
            return subtitle
        }

        let audioURL = try await downloadAudio(url: url, into: directory, cookieFilePath: cookieFilePath, trackedJobID: trackedJobID)
        guard let whisperCommand = await findWhisperCommand() else {
            throw SmartYTMediaError.transcriptionUnavailable(
                "No platform subtitles were found, and no local Whisper CLI was detected. Install `whisper` or provide a future STT provider to convert downloaded audio to text."
            )
        }

        let transcriptURL = directory.appendingPathComponent("transcript.txt")
        let result: GearCommandResult
        if let trackedJobID {
            updateJobProgress(
                trackedJobID,
                fraction: 0.95,
                label: "Transcribing audio...",
                persistence: .phase
            )
        }
        switch whisperCommand {
        case "whisper":
            var args = [
                audioURL.path,
                "--model", "base",
                "--output_format", "txt",
                "--output_dir", directory.path
            ]
            if let language {
                args.append(contentsOf: ["--language", language])
            }
            result = try await runCommand(
                "whisper",
                arguments: args,
                timeoutSeconds: nil,
                trackedJobID: trackedJobID
            )
            if !fileManager.fileExists(atPath: transcriptURL.path),
               let generated = firstFile(in: directory, extensions: ["txt"])
            {
                try? fileManager.copyItem(at: generated, to: transcriptURL)
            }
        default:
            result = try await runCommand(
                whisperCommand,
                arguments: [
                    "-f", audioURL.path,
                    "-otxt",
                    "-of", directory.appendingPathComponent("transcript").path
                ],
                timeoutSeconds: nil,
                trackedJobID: trackedJobID
            )
        }

        guard result.exitCode == 0 else {
            throw SmartYTMediaError.commandFailed(command: whisperCommand, detail: result.combinedOutput)
        }

        let effectiveTranscriptURL = fileManager.fileExists(atPath: transcriptURL.path)
            ? transcriptURL
            : directory.appendingPathComponent("transcript.txt")
        guard let text = try? String(contentsOf: effectiveTranscriptURL, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SmartYTMediaError.missingArtifact("Whisper finished but no transcript text file was found.")
        }
        return SmartYTTranscriptionResult(
            text: text,
            transcriptURL: effectiveTranscriptURL,
            artifacts: [audioURL, effectiveTranscriptURL],
            source: whisperCommand
        )
    }

    private func extractSubtitle(
        url: String,
        language: String?,
        into directory: URL,
        cookieFilePath: String?,
        trackedJobID: String? = nil
    ) async throws -> SmartYTTranscriptionResult? {
        _ = try await refreshYTDLPIfNeeded(reason: "subtitle")
        let template = directory.appendingPathComponent("subtitle.%(ext)s").path
        let languageList = subtitleLanguageList(preferred: language)
        let result = try await runYTDLP(
            [
                "--write-sub",
                "--write-auto-sub",
                "--sub-langs", languageList,
                "--sub-format", "srt/vtt/json3",
                "--convert-subs", "srt",
                "--skip-download",
                "--ignore-no-formats-error",
                "--no-warnings",
                "-o", template,
                url
            ],
            cookieFilePath: cookieFilePath,
            trackedJobID: trackedJobID,
            timeoutSeconds: 90
        )
        if result.exitCode != 0,
           firstFile(in: directory, extensions: ["srt", "vtt", "json3"]) == nil
        {
            return nil
        }

        guard let subtitleURL = firstFile(in: directory, extensions: ["srt", "vtt", "json3"]) else {
            return nil
        }

        let text = try parseSubtitleFile(subtitleURL)
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > 10 else {
            return nil
        }

        let transcriptURL = directory.appendingPathComponent("transcript.txt")
        try text.write(to: transcriptURL, atomically: true, encoding: .utf8)
        return SmartYTTranscriptionResult(
            text: text,
            transcriptURL: transcriptURL,
            artifacts: [subtitleURL, transcriptURL],
            source: "subtitle"
        )
    }

    private func downloadAudio(
        url: String,
        into directory: URL,
        cookieFilePath: String?,
        trackedJobID: String? = nil
    ) async throws -> URL {
        _ = try await refreshYTDLPIfNeeded(reason: "audio")
        let template = directory.appendingPathComponent("audio.%(ext)s").path
        let result = try await runYTDLP(
            [
                "-x",
                "--audio-format", "mp3",
                "--audio-quality", "0",
                "--newline",
                "--no-playlist",
                "-o", template,
                url
            ],
            cookieFilePath: cookieFilePath,
            trackedJobID: trackedJobID,
            timeoutSeconds: nil
        )
        guard result.exitCode == 0 else {
            throw Self.ytdlpFailure(command: "yt-dlp audio download", result: result)
        }
        guard let output = firstFile(in: directory, extensions: ["mp3", "m4a", "wav", "aac", "opus"]) else {
            throw SmartYTMediaError.missingArtifact("Audio download finished but no audio artifact was found.")
        }
        return output
    }

    private func downloadVideo(
        url: String,
        into directory: URL,
        cookieFilePath: String?,
        trackedJobID: String? = nil
    ) async throws -> URL {
        _ = try await refreshYTDLPIfNeeded(reason: "video")
        let template = directory.appendingPathComponent("video.%(ext)s").path
        let result = try await runYTDLP(
            [
                "-f", "bv*+ba/best",
                "--newline",
                "--merge-output-format", "mp4",
                "--no-playlist",
                "-o", template,
                url
            ],
            cookieFilePath: cookieFilePath,
            trackedJobID: trackedJobID,
            timeoutSeconds: nil
        )
        guard result.exitCode == 0 else {
            throw Self.ytdlpFailure(command: "yt-dlp video download", result: result)
        }
        guard let output = firstFile(in: directory, extensions: ["mp4", "mov", "mkv", "webm"]) else {
            throw SmartYTMediaError.missingArtifact("Video download finished but no video artifact was found.")
        }
        return output
    }

    private func downloadImage(url: String, into directory: URL) async throws -> URL {
        try Task.checkCancellation()
        guard let sourceURL = URL(string: url) else {
            throw SmartYTMediaError.invalidURL
        }
        var request = URLRequest(url: sourceURL)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SmartYTMediaError.commandFailed(
                command: "image download",
                detail: "HTTP \(http.statusCode)"
            )
        }
        let ext = Self.imageExtension(for: url) ?? "jpg"
        let output = directory.appendingPathComponent("image.\(ext)")
        try data.write(to: output, options: .atomic)
        return output
    }

    private func findWhisperCommand() async -> String? {
        for command in ["whisper", "whisper-cli"] {
            let result = await runner.run("command", arguments: ["-v", command], timeoutSeconds: 8)
            if result.exitCode == 0 {
                return command
            }
        }
        return nil
    }

    private func saveCookieFile(from sourceURL: URL) throws -> URL {
        let targetURL = try savedCookieFileURL()
        let sourcePath = NSString(string: sourceURL.path).expandingTildeInPath
        let sourceData = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
        let normalizedData = try SmartYTYTDLPCookieFile.normalizedNetscapeData(from: sourceData)
        if sourcePath != targetURL.path {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
        }
        try normalizedData.write(to: targetURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetURL.path)
        return targetURL
    }

    private func runYTDLP(
        _ baseArguments: [String],
        cookieFilePath explicitPath: String?,
        trackedJobID: String? = nil,
        timeoutSeconds: TimeInterval?
    ) async throws -> GearCommandResult {
        let firstResult = try await runYTDLPOnce(
            baseArguments,
            cookieFilePath: explicitPath,
            trackedJobID: trackedJobID,
            timeoutSeconds: timeoutSeconds
        )
        guard shouldRefreshBrowserCookies(after: firstResult, explicitCookiePath: explicitPath),
              let probeURL = ytdlpCookieRefreshProbeURL(from: baseArguments)
        else {
            return firstResult
        }

        if let trackedJobID {
            updateJobProgress(
                trackedJobID,
                fraction: nil,
                label: "Refreshing YouTube cookies from Chrome...",
                persistence: .phase
            )
        }
        do {
            _ = try await refreshSavedCookieFileFromBrowser(for: probeURL)
        } catch {
            let detail = [
                firstResult.combinedOutput,
                "Automatic Chrome cookie refresh failed: \(error.localizedDescription)"
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            return GearCommandResult(exitCode: firstResult.exitCode, stdout: firstResult.stdout, stderr: detail)
        }

        return try await runYTDLPOnce(
            baseArguments,
            cookieFilePath: explicitPath,
            trackedJobID: trackedJobID,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func runYTDLPOnce(
        _ baseArguments: [String],
        cookieFilePath explicitPath: String?,
        trackedJobID: String? = nil,
        timeoutSeconds: TimeInterval?
    ) async throws -> GearCommandResult {
        let invocation = try ytdlpArguments(baseArguments, cookieFilePath: explicitPath)
        let lineSink = trackedJobID.map { SmartYTProgressLineSink(store: self, jobID: $0) }
        let onLineHandler: (@Sendable (String) -> Void)?
        if let lineSink {
            onLineHandler = { line in
                lineSink.handle(line)
            }
        } else {
            onLineHandler = nil
        }
        defer {
            if let temporaryCookieURL = invocation.temporaryCookieURL {
                try? fileManager.removeItem(at: temporaryCookieURL)
            }
        }
        return try await runCommand(
            "yt-dlp",
            arguments: invocation.arguments,
            timeoutSeconds: timeoutSeconds,
            trackedJobID: trackedJobID,
            onLine: onLineHandler
        )
    }

    private func shouldRefreshBrowserCookies(after result: GearCommandResult, explicitCookiePath: String?) -> Bool {
        guard explicitCookiePath?.nilIfBlank == nil else {
            return false
        }
        guard case .youtubeAuthenticationRequired = Self.ytdlpFailure(command: "yt-dlp", result: result) else {
            return false
        }
        return true
    }

    private func ytdlpCookieRefreshProbeURL(from arguments: [String]) -> String? {
        arguments.reversed().first { value in
            value.hasPrefix("http://")
                || value.hasPrefix("https://")
                || value.hasPrefix("ytsearch")
        }
    }

    private func runCommand(
        _ command: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        trackedJobID: String?,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> GearCommandResult {
        try Task.checkCancellation()
        guard let trackedJobID else {
            let result = await runner.run(command, arguments: arguments, timeoutSeconds: timeoutSeconds)
            try Task.checkCancellation()
            return result
        }
        if let streamingRunner = runner as? SmartYTStreamingCommandRunning {
            let result = await streamingRunner.runStreaming(
                command,
                arguments: arguments,
                timeoutSeconds: timeoutSeconds,
                onStart: { handle in
                    Task { @MainActor [weak self] in
                        self?.activeCommandHandles[trackedJobID] = handle
                    }
                },
                onLine: { line in
                    Task { @MainActor in
                        onLine?(line)
                    }
                }
            )
            if activeCommandHandles[trackedJobID] != nil {
                activeCommandHandles.removeValue(forKey: trackedJobID)
            }
            try Task.checkCancellation()
            return result
        }
        let result = await runner.run(command, arguments: arguments, timeoutSeconds: timeoutSeconds)
        try Task.checkCancellation()
        return result
    }

    private func ytdlpArguments(_ baseArguments: [String], cookieFilePath explicitPath: String?) throws -> (arguments: [String], temporaryCookieURL: URL?) {
        guard let cookiePath = try resolvedCookieFilePath(explicitPath) else {
            return (baseArguments, nil)
        }
        let temporaryCookieURL = try temporaryYTDLPCookieFile(copying: cookiePath)
        return (["--cookies", temporaryCookieURL.path] + baseArguments, temporaryCookieURL)
    }

    private func temporaryYTDLPCookieFile(copying sourcePath: String) throws -> URL {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let data = try Data(contentsOf: sourceURL)
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("geeagent-smartyt-ytdlp-cookies-\(UUID().uuidString).txt", isDirectory: false)
        try data.write(to: temporaryURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
        return temporaryURL
    }

    private func refreshSavedCookieFileFromBrowser(for url: String) async throws -> URL {
        let targetURL = try savedCookieFileURL()
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("geeagent-smartyt-browser-cookies-\(UUID().uuidString).txt", isDirectory: false)
        try Data("# Netscape HTTP Cookie File\n".utf8).write(to: temporaryURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }

        let result = await runner.run(
            "yt-dlp",
            arguments: [
                "--cookies-from-browser", "chrome",
                "--cookies", temporaryURL.path,
                "--no-warnings",
                "--skip-download",
                "--simulate",
                url
            ],
            timeoutSeconds: 180
        )
        guard result.exitCode == 0 else {
            throw SmartYTMediaError.browserCookieRefreshFailed(
                "Could not refresh YouTube cookies from Chrome. \(result.combinedOutput)"
            )
        }

        let data = try Data(contentsOf: temporaryURL)
        _ = try SmartYTYTDLPCookieFile.normalizedNetscapeData(from: data)
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try data.write(to: targetURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetURL.path)
        cookieFilePath = targetURL.path
        defaults.set(targetURL.path, forKey: Self.cookieFileDefaultsKey)
        return targetURL
    }

    private func resolvedCookieFilePath(_ explicitPath: String?) throws -> String? {
        let candidate = explicitPath?.nilIfBlank
            ?? cookieFilePath.nilIfBlank
            ?? defaults.string(forKey: Self.cookieFileDefaultsKey)?.nilIfBlank
        guard let candidate else {
            return nil
        }
        let expanded = NSString(string: candidate).expandingTildeInPath
        guard fileManager.fileExists(atPath: expanded) else {
            throw SmartYTMediaError.missingCookieFile(expanded)
        }
        try normalizeSavedCookieFileIfNeeded(atPath: expanded)
        return expanded
    }

    private func normalizeSavedCookieFileIfNeeded(atPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8),
           SmartYTYTDLPCookieFile.isLikelyNetscape(text)
        {
            return
        }

        let savedPath = try savedCookieFileURL().path
        guard path == savedPath else {
            throw SmartYTMediaError.invalidCookieFile(
                "Configured yt-dlp cookie file is not Netscape formatted. Re-import it in SmartYT so JSON exports can be converted."
            )
        }

        let normalizedData = try SmartYTYTDLPCookieFile.normalizedNetscapeData(from: data)
        try normalizedData.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func refreshYTDLPIfNeeded(reason: String) async throws -> SmartYTYTDLPMaintenanceReport? {
        let now = Date()
        if let last = defaults.object(forKey: Self.ytdlpMaintenanceDefaultsKey) as? Date,
           now.timeIntervalSince(last) < Self.ytdlpMaintenanceInterval
        {
            return nil
        }

        if let task = ytdlpMaintenanceTask {
            return try await task.value
        }

        let task = Task { @MainActor [self] in
            defer {
                ytdlpMaintenanceTask = nil
            }
            return try await performYTDLPMaintenance(reason: reason, checkedAt: now)
        }
        ytdlpMaintenanceTask = task
        return try await task.value
    }

    private func performYTDLPMaintenance(reason: String, checkedAt now: Date) async throws -> SmartYTYTDLPMaintenanceReport {
        let versionBefore = await ytdlpVersion()
        let brewCheck = await runner.run("command", arguments: ["-v", "brew"], timeoutSeconds: 20)
        guard brewCheck.exitCode == 0 else {
            throw SmartYTMediaError.dependencyMaintenanceFailed(
                "Could not refresh yt-dlp before \(reason): Homebrew is not available. \(brewCheck.combinedOutput)"
            )
        }

        let upgrade = await runner.run("brew", arguments: ["upgrade", "yt-dlp"], timeoutSeconds: 600)
        let maintenanceWarning: String?
        if upgrade.exitCode == 0 {
            maintenanceWarning = nil
        } else if await canContinueAfterBrewYTDLPLinkWarning(upgrade) {
            maintenanceWarning = "yt-dlp maintenance completed with a Homebrew link warning; continuing with the available yt-dlp binary."
        } else {
            throw SmartYTMediaError.dependencyMaintenanceFailed(
                "Could not refresh yt-dlp before \(reason): \(upgrade.combinedOutput)"
            )
        }

        defaults.set(now, forKey: Self.ytdlpMaintenanceDefaultsKey)
        let versionAfter = await ytdlpVersion()
        let report = SmartYTYTDLPMaintenanceReport(
            checkedAt: now,
            versionBefore: versionBefore,
            versionAfter: versionAfter,
            output: upgrade.combinedOutput,
            warning: maintenanceWarning
        )
        statusMessage = report.summary
        return report
    }

    private func canContinueAfterBrewYTDLPLinkWarning(_ result: GearCommandResult) async -> Bool {
        let normalized = result.combinedOutput.lowercased()
        guard normalized.contains("brew link")
            && normalized.contains("yt-dlp")
            && normalized.contains("already exists")
        else {
            return false
        }
        return await ytdlpVersion() != nil
    }

    private func ytdlpVersion() async -> String? {
        let result = await runner.run("yt-dlp", arguments: ["--version"], timeoutSeconds: 20)
        guard result.exitCode == 0 else {
            return nil
        }
        return result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private static func ytdlpFailure(command: String, result: GearCommandResult) -> SmartYTMediaError {
        let detail = result.combinedOutput
        let normalized = detail.lowercased()
        if normalized.contains("sign in to confirm")
            && normalized.contains("not a bot")
            && normalized.contains("cookies")
        {
            return .youtubeAuthenticationRequired(command: command, detail: detail)
        }
        return .commandFailed(command: command, detail: detail)
    }

    private static func cliFailure(command: String, result: GearCommandResult) -> SmartYTMediaError {
        let detail = result.combinedOutput.nilIfBlank ?? "Command exited with \(result.exitCode)."
        let normalized = detail.lowercased()
        if normalized.contains("no module named xhs_cli") || normalized.contains("no module named dy_cli") {
            return .commandFailed(
                command: command,
                detail: "\(detail)\nInstall SmartYT's Xiaohongshu/Douyin Python CLI dependencies from the Gear dependency setup."
            )
        }
        if normalized.contains("please log in") || normalized.contains("not logged in") || normalized.contains("login") {
            return .commandFailed(
                command: command,
                detail: "\(detail)\nLog in with the platform CLI account flow, then retry the same SmartYT search."
            )
        }
        if normalized.contains("mainland ip") || normalized.contains("domestic ip") || normalized.contains("proxy") {
            return .commandFailed(
                command: command,
                detail: "\(detail)\nConfigure the platform CLI proxy/network route, then retry the same SmartYT action."
            )
        }
        return .commandFailed(command: command, detail: detail)
    }

    private static func smartYTErrorFromMessage(_ message: String) -> SmartYTMediaError? {
        let normalized = message.lowercased()
        if normalized.contains("needs authenticated youtube cookies") || (
            normalized.contains("sign in to confirm")
                && normalized.contains("not a bot")
                && normalized.contains("cookies")
        ) {
            return .youtubeAuthenticationRequired(command: "yt-dlp", detail: message)
        }
        if normalized.contains("could not refresh yt-dlp") {
            return .dependencyMaintenanceFailed(message)
        }
        if normalized.contains("configured yt-dlp cookie file is missing") {
            return .missingCookieFile(message)
        }
        if normalized.contains("cookie file must be")
            || normalized.contains("cookie file is not netscape")
            || normalized.contains("cookie export")
        {
            return .invalidCookieFile(message)
        }
        if normalized.contains("could not refresh youtube cookies from chrome")
            || normalized.contains("automatic chrome cookie refresh failed")
        {
            return .browserCookieRefreshFailed(message)
        }
        return nil
    }

    private func parseSubtitleFile(_ url: URL) throws -> String {
        let content = try String(contentsOf: url, encoding: .utf8)
        switch url.pathExtension.lowercased() {
        case "vtt":
            return parseTimedText(content, timePattern: "-->")
        case "srt":
            return parseTimedText(content, timePattern: "-->")
        case "json3":
            return parseJSON3(content)
        default:
            return content
        }
    }

    private func parseTimedText(_ content: String, timePattern: String) -> String {
        let blocks = content.components(separatedBy: .newlines)
        var lines: [String] = []
        var acceptText = false

        for rawLine in blocks {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                acceptText = false
                continue
            }
            if trimmed == "WEBVTT" || trimmed.hasPrefix("NOTE") || trimmed.hasPrefix("STYLE") {
                acceptText = false
                continue
            }
            if trimmed.contains(timePattern) {
                acceptText = true
                continue
            }
            if Int(trimmed) != nil {
                continue
            }
            guard acceptText else {
                continue
            }
            let clean = trimmed
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\\[A-Za-z]+\d*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                lines.append(clean)
            }
        }

        return dedupeProgressiveLines(lines).joined(separator: "\n")
    }

    private func parseJSON3(_ content: String) -> String {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = object["body"] as? [[String: Any]]
        else {
            return content
        }
        let lines = body.compactMap { ($0["content"] as? String)?.nilIfBlank }
        return dedupeProgressiveLines(lines).joined(separator: "\n")
    }

    private func dedupeProgressiveLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for (index, line) in lines.enumerated() {
            if index + 1 < lines.count, lines[index + 1].hasPrefix(line), lines[index + 1].count > line.count {
                continue
            }
            guard seen.insert(line).inserted else {
                continue
            }
            result.append(line)
        }
        return result
    }

    private func subtitleLanguageList(preferred: String?) -> String {
        if let preferred = preferred?.nilIfBlank {
            return [preferred, "zh-Hans", "zh-CN", "zh", "en", "en-US"].joined(separator: ",")
        }
        return "zh-Hans,zh-CN,zh,chi,zho,en,en-US,en-GB,eng"
    }

    private func firstFile(in directory: URL, extensions: Set<String>) -> URL? {
        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .first
    }

    private func firstFile(in directory: URL, extensions: [String]) -> URL? {
        firstFile(in: directory, extensions: Set(extensions.map { $0.lowercased() }))
    }

    private func runBusy(_ status: String, operation: () async throws -> Void) async {
        isBusy = true
        statusMessage = status
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func normalizedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^@", with: "", options: .regularExpression)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            return nil
        }
        return trimmed
    }

    private static func imageExtension(for raw: String) -> String? {
        if let url = URL(string: raw) {
            let pathExtension = url.pathExtension.lowercased()
            if imageExtensions.contains(pathExtension) {
                return pathExtension
            }
        }
        guard let components = URLComponents(string: raw) else {
            return nil
        }
        let format = components.queryItems?
            .first { $0.name.lowercased() == "format" }?
            .value?
            .lowercased()
        guard let format, imageExtensions.contains(format) else {
            return nil
        }
        return format
    }

    private static let imageExtensions = ["jpg", "jpeg", "png", "webp", "gif"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "mkv", "webm"]
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "opus"]

    private func mediaFiles(in directory: URL, extensions allowedExtensions: Set<String>) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                guard allowedExtensions.contains(url.pathExtension.lowercased()) else {
                    return false
                }
                return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .sorted { $0.path < $1.path }
    }

    private enum SmartYTProgressPersistenceKind {
        case none
        case phase
        case step
    }

    private struct SmartYTProgressEvent {
        var fraction: Double?
        var label: String
        var persistence: SmartYTProgressPersistenceKind
        var logLine: String?
    }

    private func cleanupActiveExecution(for jobID: String) {
        activeCommandHandles.removeValue(forKey: jobID)
        jobTasks.removeValue(forKey: jobID)
        lastPersistedProgressStep.removeValue(forKey: jobID)
        lastProgressLabelByJobID.removeValue(forKey: jobID)
    }

    private func updateJobProgress(
        _ jobID: String,
        fraction: Double?,
        label: String,
        persistence: SmartYTProgressPersistenceKind,
        logLine: String? = nil
    ) {
        let shouldPersist = shouldPersistProgress(
            jobID: jobID,
            fraction: fraction,
            label: label,
            persistence: persistence
        )
        updateJob(jobID, persist: shouldPersist) { current in
            if let fraction {
                current.progressFraction = max(current.normalizedProgressFraction ?? 0, min(max(fraction, 0), 1))
            }
            current.progressLabel = label
            current.updatedAt = Date()
            if let logLine, !current.log.contains(logLine) {
                current.log.append("\n\(logLine)")
            }
        }
    }

    private func shouldPersistProgress(
        jobID: String,
        fraction: Double?,
        label: String,
        persistence: SmartYTProgressPersistenceKind
    ) -> Bool {
        switch persistence {
        case .none:
            return false
        case .phase:
            if lastProgressLabelByJobID[jobID] != label {
                lastProgressLabelByJobID[jobID] = label
                return true
            }
            return false
        case .step:
            let step = Int(floor((fraction ?? 0) * 20))
            if step > (lastPersistedProgressStep[jobID] ?? -1) {
                lastPersistedProgressStep[jobID] = step
                return true
            }
            return false
        }
    }

    fileprivate func handleYTDLPOutputLine(_ line: String, for jobID: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let currentFraction = jobs.first(where: { $0.id == jobID })?.normalizedProgressFraction
        guard let event = Self.progressEvent(fromYTDLPLine: trimmed, currentFraction: currentFraction) else {
            return
        }
        updateJobProgress(
            jobID,
            fraction: event.fraction,
            label: event.label,
            persistence: event.persistence,
            logLine: event.logLine
        )
    }

    private static func progressEvent(
        fromYTDLPLine line: String,
        currentFraction: Double?
    ) -> SmartYTProgressEvent? {
        if line.hasPrefix("[download]"),
           let percentRange = line.range(of: #"[0-9]+(?:\.[0-9]+)?%"#, options: .regularExpression)
        {
            let percentString = String(line[percentRange].dropLast())
            if let percentValue = Double(percentString) {
                let fraction = max(currentFraction ?? 0, percentValue / 100)
                let label = line
                    .replacingOccurrences(of: "[download]", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return SmartYTProgressEvent(
                    fraction: fraction,
                    label: label,
                    persistence: .step,
                    logLine: nil
                )
            }
        }
        if line.hasPrefix("[download] Destination:") {
            return SmartYTProgressEvent(
                fraction: max(currentFraction ?? 0, 0.01),
                label: "Preparing download...",
                persistence: .phase,
                logLine: line
            )
        }
        if line.hasPrefix("[download] Got error:") {
            return SmartYTProgressEvent(
                fraction: currentFraction,
                label: "Retrying download...",
                persistence: .phase,
                logLine: line
            )
        }
        if line.hasPrefix("[Merger]") {
            return SmartYTProgressEvent(
                fraction: max(currentFraction ?? 0, 0.98),
                label: "Merging video and audio...",
                persistence: .phase,
                logLine: line
            )
        }
        if line.hasPrefix("[ExtractAudio]") {
            return SmartYTProgressEvent(
                fraction: max(currentFraction ?? 0, 0.96),
                label: "Extracting audio...",
                persistence: .phase,
                logLine: line
            )
        }
        if line.contains("Downloading webpage") {
            return SmartYTProgressEvent(
                fraction: currentFraction,
                label: "Fetching video page...",
                persistence: .phase,
                logLine: line
            )
        }
        if line.contains("Downloading player")
            || line.contains("Downloading android")
            || line.contains("Downloading tv")
            || line.contains("Downloading m3u8")
        {
            return SmartYTProgressEvent(
                fraction: max(currentFraction ?? 0, 0.02),
                label: "Preparing media stream...",
                persistence: .phase,
                logLine: line
            )
        }
        if line.hasPrefix("[info]"), line.contains("format(s):") {
            return SmartYTProgressEvent(
                fraction: max(currentFraction ?? 0, 0.03),
                label: "Starting media transfer...",
                persistence: .phase,
                logLine: line
            )
        }
        return nil
    }

    private func updateJob(_ id: String, persist shouldPersist: Bool = true, mutate: (inout SmartYTMediaJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&jobs[index])
        if shouldPersist {
            persist(jobs[index])
        }
    }

    private func persist(_ job: SmartYTMediaJob) {
        do {
            let directory = try ensureStateJobDirectory(job.id)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(job)
            try data.write(to: directory.appendingPathComponent("job.json"), options: .atomic)
        } catch {
            statusMessage = "Could not save job: \(error.localizedDescription)"
        }
    }

    private func loadJob(_ directory: URL) -> SmartYTMediaJob? {
        let url = directory.appendingPathComponent("job.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SmartYTMediaJob.self, from: data)
    }

    private func deletePersistedJobRecord(_ id: String) throws {
        let directory = try stateJobDirectory(id)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    private func deleteAssociatedJobData(for job: SmartYTMediaJob) throws {
        let artifactURL = artifactDirectory(for: job).standardizedFileURL
        let filePaths = Set((job.outputPaths + [job.transcriptPath].compactMap(\.self))
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        for path in filePaths where fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }

        if shouldDeleteWholeArtifactDirectory(artifactURL, for: job) {
            if fileManager.fileExists(atPath: artifactURL.path) {
                try fileManager.removeItem(at: artifactURL)
            }
            return
        }

        try removeDirectoryIfEmpty(artifactURL)
    }

    private func shouldDeleteWholeArtifactDirectory(_ directory: URL, for job: SmartYTMediaJob) -> Bool {
        let defaultDirectory = defaultArtifactDirectory(jobID: job.id).standardizedFileURL
        return directory.path == defaultDirectory.path || directory.lastPathComponent == job.id
    }

    private func removeDirectoryIfEmpty(_ directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
        if contents.isEmpty {
            try fileManager.removeItem(at: directory)
        }
    }

    private func persist(_ task: SmartYTSearchTask) throws {
        let directory = try ensureStateSearchDirectory(task.id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(task)
        try data.write(to: directory.appendingPathComponent("search.json"), options: .atomic)
    }

    private func loadSearchTasks() {
        do {
            let root = try searchesRoot()
            let entries = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            searchTasks = entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .compactMap(loadSearchTask)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            statusMessage = "Could not load SmartYT search tasks: \(error.localizedDescription)"
        }
    }

    private func loadSearchTask(_ directory: URL) -> SmartYTSearchTask? {
        let url = directory.appendingPathComponent("search.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SmartYTSearchTask.self, from: data)
    }

    private func dataRoot() throws -> URL {
        if let dataRootOverride {
            try fileManager.createDirectory(at: dataRootOverride, withIntermediateDirectories: true)
            return dataRootOverride
        }
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("GeeAgent/gear-data/smartyt.media", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func jobsRoot() throws -> URL {
        let root = try dataRoot().appendingPathComponent("jobs", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func searchesRoot() throws -> URL {
        let root = try dataRoot().appendingPathComponent("searches", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func cookiesRoot() throws -> URL {
        let root = try dataRoot().appendingPathComponent("cookies", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func savedCookieFileURL() throws -> URL {
        try cookiesRoot().appendingPathComponent(Self.savedCookieFileName, isDirectory: false)
    }

    static func defaultArtifactRoot(fileManager: FileManager = .default) throws -> URL {
        let downloads = try fileManager.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return downloads.appendingPathComponent("SmartYT", isDirectory: true)
    }

    private func stateJobDirectory(_ id: String) throws -> URL {
        try jobsRoot().appendingPathComponent(id, isDirectory: true)
    }

    private func ensureStateJobDirectory(_ id: String) throws -> URL {
        let directory = try stateJobDirectory(id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func ensureStateSearchDirectory(_ id: String) throws -> URL {
        let directory = try searchesRoot().appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func defaultArtifactDirectory(jobID: String) -> URL {
        let root = (try? Self.defaultArtifactRoot(fileManager: fileManager))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SmartYT", isDirectory: true)
        return root.appendingPathComponent(jobID, isDirectory: true)
    }

    private func artifactDirectory(for job: SmartYTMediaJob) -> URL {
        if let path = job.artifactDirectoryPath?.nilIfBlank {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let existingOutput = job.outputPaths.first?.nilIfBlank {
            return URL(fileURLWithPath: existingOutput).deletingLastPathComponent()
        }
        return defaultArtifactDirectory(jobID: job.id)
    }

    private func ensureArtifactDirectory(for job: SmartYTMediaJob) throws -> URL {
        let directory = artifactDirectory(for: job)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func resolvedArtifactDirectory(jobID: String, requestedPath: String?) -> URL {
        guard let requestedPath = requestedPath?.nilIfBlank else {
            return defaultArtifactDirectory(jobID: jobID)
        }
        let expanded = NSString(string: requestedPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func preview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1_200 else {
            return trimmed
        }
        return String(trimmed.prefix(1_200)) + "\n..."
    }

    private func searchTaskPayload(_ task: SmartYTSearchTask) -> [String: Any] {
        var payload: [String: Any] = [
            "gear_id": SmartYTMediaGearDescriptor.gearID,
            "capability_id": "smartyt.search_candidates",
            "status": task.status,
            "search_task_id": task.id,
            "task_id": task.id,
            "query": task.query,
            "platforms": task.platforms,
            "limit": task.limit,
            "candidates": task.candidates.map(candidatePayload),
            "warnings": task.warnings,
            "error": task.error ?? NSNull()
        ]
        if let error = task.error,
           let smartYTError = Self.smartYTErrorFromMessage(error)
        {
            payload["error_code"] = smartYTError.code
            if let recovery = smartYTError.recovery {
                payload["recovery"] = recovery
            }
        }
        return payload
    }

    private func searchTaskSummaryPayload(_ task: SmartYTSearchTask) -> [String: Any] {
        [
            "task_id": task.id,
            "kind": "search",
            "state": task.status,
            "query": task.query,
            "platforms": task.platforms,
            "candidate_count": task.candidates.count,
            "created_at": Self.iso8601(task.createdAt),
            "updated_at": Self.iso8601(task.updatedAt),
            "error": task.error ?? NSNull()
        ]
    }

    private func jobPayload(_ job: SmartYTMediaJob) -> [String: Any] {
        var payload: [String: Any] = [
            "task_id": job.id,
            "job_id": job.id,
            "kind": job.action.rawValue,
            "state": job.status.rawValue,
            "source_url": job.url,
            "download_kind": job.downloadKind.rawValue,
            "output_files": job.outputPaths.map { ["path": $0] },
            "artifact_root": artifactDirectory(for: job).path,
            "progress_fraction": job.normalizedProgressFraction ?? NSNull(),
            "progress_label": job.progressLabel ?? NSNull(),
            "can_cancel": job.canCancel,
            "created_at": Self.iso8601(job.createdAt),
            "updated_at": Self.iso8601(job.updatedAt),
            "error": job.errorMessage ?? NSNull()
        ]
        if let error = job.errorMessage,
           let smartYTError = Self.smartYTErrorFromMessage(error)
        {
            payload["error_code"] = smartYTError.code
            if let recovery = smartYTError.recovery {
                payload["recovery"] = recovery
            }
        }
        return payload
    }

    private func candidatePayload(_ candidate: SmartYTSearchCandidate) -> [String: Any] {
        [
            "candidate_id": candidate.id,
            "platform": candidate.platform,
            "title": candidate.title,
            "url": candidate.url,
            "source_url": candidate.sourceURL,
            "thumbnail_url": candidate.thumbnailURL ?? NSNull(),
            "preview_url": candidate.previewURL ?? NSNull(),
            "duration": candidate.durationSeconds ?? NSNull(),
            "duration_seconds": candidate.durationSeconds ?? NSNull(),
            "width": candidate.width ?? NSNull(),
            "height": candidate.height ?? NSNull(),
            "orientation": candidate.orientation ?? NSNull(),
            "author": candidate.author ?? NSNull(),
            "published_at": candidate.publishedAt ?? NSNull(),
            "raw_metadata": candidate.rawMetadata
        ]
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseXiaohongshuSearchCandidates(
        _ stdout: String,
        limit: Int,
        startingIndex: Int
    ) throws -> [SmartYTSearchCandidate] {
        guard let object = try parseJSONObject(stdout),
              let data = object["data"] as? [String: Any],
              let items = data["items"] as? [[String: Any]]
        else {
            throw SmartYTMediaError.invalidMetadata("xhs search did not return the expected JSON envelope.")
        }

        var candidates: [SmartYTSearchCandidate] = []
        for item in items {
            guard candidates.count < limit,
                  let noteID = stringValue(item["id"])?.nilIfBlank,
                  let noteCard = item["note_card"] as? [String: Any],
                  stringValue(noteCard["type"]) == "video"
            else {
                continue
            }
            let token = stringValue(item["xsec_token"])
                ?? stringValue(noteCard["xsec_token"])
            let sourceURL = xiaohongshuNoteURL(noteID: noteID, xsecToken: token)
            let cover = noteCard["cover"] as? [String: Any]
            let user = noteCard["user"] as? [String: Any]
            let title = stringValue(noteCard["display_title"])
                ?? stringValue(noteCard["title"])
                ?? "Xiaohongshu video"
            let width = intValue(cover?["width"])
            let height = intValue(cover?["height"])
            var rawMetadata = [
                "provider": "xiaohongshu-cli",
                "note_id": noteID
            ]
            if let token, !token.isEmpty {
                rawMetadata["xsec_token"] = token
            }
            if let likedCount = stringValue((noteCard["interact_info"] as? [String: Any])?["liked_count"]) {
                rawMetadata["liked_count"] = likedCount
            }

            candidates.append(SmartYTSearchCandidate(
                id: String(format: "cand-%03d", startingIndex + candidates.count + 1),
                platform: "xiaohongshu",
                title: title,
                url: sourceURL,
                sourceURL: sourceURL,
                thumbnailURL: stringValue(cover?["url_default"]) ?? stringValue(cover?["url_pre"]),
                previewURL: sourceURL,
                durationSeconds: nil,
                width: width,
                height: height,
                orientation: SmartYTSearchCandidate.orientation(width: width, height: height),
                author: stringValue(user?["nickname"]) ?? stringValue(user?["nick_name"]),
                publishedAt: nil,
                rawMetadata: rawMetadata
            ))
        }
        return candidates
    }

    private static func parseDouyinSearchCandidates(
        _ stdout: String,
        limit: Int,
        startingIndex: Int
    ) throws -> [SmartYTSearchCandidate] {
        guard let object = try parseJSONObject(stdout) else {
            throw SmartYTMediaError.invalidMetadata("dy search did not return JSON.")
        }
        let payload = (object["data"] as? [String: Any]) ?? object
        let entries = (payload["data"] as? [[String: Any]]) ?? []
        var candidates: [SmartYTSearchCandidate] = []

        for entry in entries {
            guard candidates.count < limit,
                  let aweme = entry["aweme_info"] as? [String: Any],
                  let awemeID = stringValue(aweme["aweme_id"])?.nilIfBlank
            else {
                continue
            }
            let video = aweme["video"] as? [String: Any]
            let cover = video?["cover"] as? [String: Any]
            let author = aweme["author"] as? [String: Any]
            let statistics = aweme["statistics"] as? [String: Any]
            let sourceURL = "https://www.douyin.com/video/\(awemeID)"
            let width = intValue(video?["width"])
            let height = intValue(video?["height"])
            var rawMetadata = [
                "provider": "dy-cli",
                "aweme_id": awemeID
            ]
            if let diggCount = stringValue(statistics?["digg_count"]) {
                rawMetadata["digg_count"] = diggCount
            }
            if let shareURL = stringValue(aweme["share_url"]) {
                rawMetadata["share_url"] = shareURL
            }

            candidates.append(SmartYTSearchCandidate(
                id: String(format: "cand-%03d", startingIndex + candidates.count + 1),
                platform: "douyin",
                title: stringValue(aweme["desc"]) ?? "Douyin video",
                url: sourceURL,
                sourceURL: sourceURL,
                thumbnailURL: firstString(in: cover?["url_list"]),
                previewURL: sourceURL,
                durationSeconds: doubleValue(video?["duration"]).map { $0 / 1000 },
                width: width,
                height: height,
                orientation: SmartYTSearchCandidate.orientation(width: width, height: height),
                author: stringValue(author?["nickname"]),
                publishedAt: timestampISO8601(aweme["create_time"]),
                rawMetadata: rawMetadata
            ))
        }
        return candidates
    }

    private static func parseJSONObject(_ stdout: String) throws -> [String: Any]? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if trimmed.hasPrefix("{") {
            jsonText = trimmed
        } else if let start = trimmed.firstIndex(of: "{"),
                  let end = trimmed.lastIndex(of: "}"),
                  start <= end
        {
            jsonText = String(trimmed[start...end])
        } else {
            jsonText = trimmed
        }
        guard let data = jsonText.data(using: .utf8) else {
            return nil
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func xiaohongshuNoteURL(noteID: String, xsecToken: String?) -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.xiaohongshu.com"
        components.path = "/explore/\(noteID)"
        if let xsecToken, !xsecToken.isEmpty {
            components.queryItems = [URLQueryItem(name: "xsec_token", value: xsecToken)]
        }
        return components.url?.absoluteString ?? "https://www.xiaohongshu.com/explore/\(noteID)"
    }

    private static func firstString(in value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let values = value as? [String] {
            return values.first
        }
        if let values = value as? [Any] {
            return values.compactMap(stringValue).first
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let int = value as? Int {
            return String(int)
        }
        if let double = value as? Double {
            return String(double)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func timestampISO8601(_ value: Any?) -> String? {
        guard let timestamp = doubleValue(value), timestamp > 0 else {
            return nil
        }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static func normalizedPlatform(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "youtube.com", with: "youtube")
            .replacingOccurrences(of: "red note", with: "rednote")
        switch normalized {
        case "douyin.com", "www.douyin.com", "v.douyin.com", "iesdouyin.com":
            return "douyin"
        case "xiaohongshu.com", "www.xiaohongshu.com", "xhs", "xhslink", "xhslink.com", "red", "rednote":
            return "xiaohongshu"
        default:
            return normalized
        }
    }

    private static func platformForURL(_ rawURL: String) -> String? {
        guard let url = URL(string: rawURL),
              let host = url.host?.lowercased()
        else {
            return nil
        }
        if host == "douyin.com"
            || host.hasSuffix(".douyin.com")
            || host == "iesdouyin.com"
            || host.hasSuffix(".iesdouyin.com")
        {
            return "douyin"
        }
        if host == "xiaohongshu.com"
            || host.hasSuffix(".xiaohongshu.com")
            || host == "xhslink.com"
            || host.hasSuffix(".xhslink.com")
        {
            return "xiaohongshu"
        }
        return nil
    }

    private static func stringArg(_ args: [String: Any], _ key: String) -> String? {
        args[key] as? String
    }

    private static func stringArrayArg(_ args: [String: Any], _ key: String) -> [String]? {
        if let values = args[key] as? [String] {
            return values
        }
        if let values = args[key] as? [Any] {
            return values.compactMap { $0 as? String }
        }
        if let value = args[key] as? String {
            let separators = CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: ",，;；"))
            let values = value
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return values.isEmpty ? nil : values
        }
        return nil
    }

    private static func intArg(_ args: [String: Any], _ key: String) -> Int? {
        if let int = args[key] as? Int {
            return int
        }
        if let double = args[key] as? Double {
            return Int(double)
        }
        if let string = args[key] as? String {
            return Int(string)
        }
        return nil
    }

    private static func stringDictionaryArg(_ args: [String: Any], _ key: String) -> [String: String] {
        guard let dictionary = args[key] as? [String: Any] else {
            return [:]
        }
        return dictionary.reduce(into: [String: String]()) { output, entry in
            if let string = entry.value as? String {
                output[entry.key] = string
            } else if let number = entry.value as? NSNumber {
                output[entry.key] = number.stringValue
            } else if let bool = entry.value as? Bool {
                output[entry.key] = bool ? "true" : "false"
            }
        }
    }

    private static func platformSearchUnavailableMessage(platform: String) -> String {
        switch platform {
        case "douyin":
            return "douyin keyword search requires the Gear-declared dy-cli dependency and a logged-in Douyin CLI account."
        case "xiaohongshu":
            return "xiaohongshu keyword search requires the Gear-declared xiaohongshu-cli dependency and browser cookies."
        default:
            return "\(platform) keyword search has no configured stable provider."
        }
    }
}

private struct SmartYTTranscriptionResult {
    var text: String
    var transcriptURL: URL
    var artifacts: [URL]
    var source: String
}
