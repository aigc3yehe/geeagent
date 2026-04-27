import AppKit
import Foundation
import UniformTypeIdentifiers

enum TwitterCaptureTaskKind: String, Codable, CaseIterable, Identifiable {
    case tweet
    case list
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tweet: "Tweet URL"
        case .list: "List URL"
        case .user: "Username"
        }
    }

    var actionTitle: String {
        switch self {
        case .tweet: "Fetch Tweet"
        case .list: "Fetch List"
        case .user: "Fetch User"
        }
    }

    var placeholder: String {
        switch self {
        case .tweet: "https://x.com/user/status/123..."
        case .list: "https://x.com/i/lists/123..."
        case .user: "@openai or https://x.com/openai"
        }
    }

    var systemImage: String {
        switch self {
        case .tweet: "quote.bubble"
        case .list: "list.bullet.rectangle"
        case .user: "person.crop.circle.badge.plus"
        }
    }

    var supportsLimit: Bool {
        self != .tweet
    }
}

enum TwitterCaptureTaskStatus: String, Codable, Hashable {
    case queued
    case running
    case completed
    case failed

    var title: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

struct TwitterCaptureMediaItem: Codable, Hashable, Identifiable {
    var mediaID: String?
    var type: String
    var url: String?
    var previewURL: String?
    var width: Int?
    var height: Int?

    var id: String {
        mediaID?.nilIfBlank ?? url?.nilIfBlank ?? previewURL?.nilIfBlank ?? "\(type)-media"
    }

    enum CodingKeys: String, CodingKey {
        case mediaID = "id"
        case type
        case url
        case previewURL = "preview_url"
        case width
        case height
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = ["type": type]
        if let mediaID = mediaID?.nilIfBlank { payload["id"] = mediaID }
        if let url = url?.nilIfBlank { payload["url"] = url }
        if let previewURL = previewURL?.nilIfBlank { payload["preview_url"] = previewURL }
        if let width { payload["width"] = width }
        if let height { payload["height"] = height }
        return payload
    }
}

struct TwitterCapturedTweet: Codable, Hashable, Identifiable {
    var tweetID: String
    var tweetURL: String?
    var authorHandle: String?
    var text: String
    var lang: String?
    var likeCount: Int?
    var retweetCount: Int?
    var replyCount: Int?
    var viewCount: Int?
    var createdAt: String?
    var isReply: Bool
    var isRetweet: Bool
    var media: [TwitterCaptureMediaItem]

    var id: String { tweetID }

    enum CodingKeys: String, CodingKey {
        case tweetID = "tweet_id"
        case tweetURL = "tweet_url"
        case authorHandle = "author_handle"
        case text
        case lang
        case likeCount = "like_count"
        case retweetCount = "retweet_count"
        case replyCount = "reply_count"
        case viewCount = "view_count"
        case createdAt = "created_at"
        case isReply = "is_reply"
        case isRetweet = "is_retweet"
        case media
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "tweet_id": tweetID,
            "text": text,
            "is_reply": isReply,
            "is_retweet": isRetweet,
            "media": media.map(\.agentDictionary)
        ]
        if let tweetURL = tweetURL?.nilIfBlank { payload["tweet_url"] = tweetURL }
        if let authorHandle = authorHandle?.nilIfBlank { payload["author_handle"] = authorHandle }
        if let lang = lang?.nilIfBlank { payload["lang"] = lang }
        if let likeCount { payload["like_count"] = likeCount }
        if let retweetCount { payload["retweet_count"] = retweetCount }
        if let replyCount { payload["reply_count"] = replyCount }
        if let viewCount { payload["view_count"] = viewCount }
        if let createdAt = createdAt?.nilIfBlank { payload["created_at"] = createdAt }
        return payload
    }
}

struct TwitterCaptureTaskRecord: Codable, Identifiable, Hashable {
    var id: String
    var kind: TwitterCaptureTaskKind
    var target: String
    var normalizedTarget: String
    var limit: Int
    var status: TwitterCaptureTaskStatus
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var cookieFilePath: String?
    var taskDirectoryPath: String
    var tweets: [TwitterCapturedTweet]
    var nextCursor: String?
    var log: String
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case target
        case normalizedTarget = "normalized_target"
        case limit
        case status
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case cookieFilePath = "cookie_file_path"
        case taskDirectoryPath = "task_directory_path"
        case tweets
        case nextCursor = "next_cursor"
        case log
        case errorMessage = "error_message"
    }

    var taskURL: URL {
        URL(fileURLWithPath: taskDirectoryPath, isDirectory: true).appendingPathComponent("task.json")
    }

    var resultSummary: String {
        switch status {
        case .completed:
            "\(tweets.count) tweet\(tweets.count == 1 ? "" : "s") captured"
        case .failed:
            errorMessage ?? "Task failed"
        case .queued:
            "Waiting to start"
        case .running:
            "Fetching Twitter/X content"
        }
    }
}

enum TwitterCaptureError: LocalizedError {
    case invalidTarget(String)
    case missingCookieFile
    case missingSidecar
    case commandFailed(String)
    case sidecarError(String)
    case invalidSidecarOutput(String)

    var errorDescription: String? {
        switch self {
        case let .invalidTarget(message):
            message
        case .missingCookieFile:
            "Choose a Twitter/X cookie JSON file before running this capture."
        case .missingSidecar:
            "Twitter Capture sidecar script is missing from the gear package."
        case let .commandFailed(detail):
            "Twitter Capture sidecar failed. \(detail)"
        case let .sidecarError(message):
            message
        case let .invalidSidecarOutput(message):
            "Twitter Capture returned invalid data. \(message)"
        }
    }
}

struct TwitterCaptureFileDatabase {
    var rootURL: URL?
    var fileManager: FileManager = .default

    func loadTasks() -> [TwitterCaptureTaskRecord] {
        do {
            let entries = try fileManager.contentsOfDirectory(
                at: try tasksRoot(),
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .compactMap(loadTask)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    func save(_ task: TwitterCaptureTaskRecord) throws {
        let directory = try taskDirectory(task.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(task)
        try data.write(to: directory.appendingPathComponent("task.json"), options: .atomic)
    }

    func taskDirectory(_ id: String) throws -> URL {
        try tasksRoot().appendingPathComponent(id, isDirectory: true)
    }

    func taskFileURL(_ id: String) throws -> URL {
        try taskDirectory(id).appendingPathComponent("task.json")
    }

    func dataRoot() throws -> URL {
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
        .appendingPathComponent("GeeAgent/gear-data/twitter.capture", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func tasksRoot() throws -> URL {
        let root = try dataRoot().appendingPathComponent("tasks", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func loadTask(_ directory: URL) -> TwitterCaptureTaskRecord? {
        let url = directory.appendingPathComponent("task.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TwitterCaptureTaskRecord.self, from: data)
    }
}

enum TwitterCaptureInputParser {
    static func tweetID(from value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in [#"/status(?:es)?/([0-9]+)"#, #"/i/status/([0-9]+)"#] {
            if let match = firstCapture(in: text, pattern: pattern) {
                return match
            }
        }
        return text.range(of: #"^[0-9]{8,}$"#, options: .regularExpression) == nil ? nil : text
    }

    static func listID(from value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = firstCapture(in: text, pattern: #"/lists/([0-9]+)"#) {
            return match
        }
        return text.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) == nil ? nil : text
    }

    static func handle(from value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedAt = text.replacingOccurrences(of: "^@", with: "", options: .regularExpression)
        if strippedAt.range(of: #"^[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil {
            return strippedAt
        }
        guard let url = URL(string: text), let host = url.host?.lowercased(),
              host.contains("twitter.com") || host.contains("x.com")
        else {
            return nil
        }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let first = components.first,
              first != "i",
              first != "home",
              first != "search",
              !components.contains("status"),
              !components.contains("lists"),
              first.range(of: #"^[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil
        else {
            return nil
        }
        return first
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }
}

@MainActor
final class TwitterCaptureGearStore: ObservableObject {
    static let shared = TwitterCaptureGearStore()
    static let cookieFileDefaultsKey = "geeagent.twitter.capture.cookieFile"

    @Published var selectedKind: TwitterCaptureTaskKind = .tweet
    @Published var target = ""
    @Published var limit = 30
    @Published var cookieFilePath = UserDefaults.standard.string(forKey: cookieFileDefaultsKey) ?? ""
    @Published private(set) var tasks: [TwitterCaptureTaskRecord] = []
    @Published var selectedTaskID: TwitterCaptureTaskRecord.ID?
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var isBusy = false

    private let database: TwitterCaptureFileDatabase
    private let sidecar: TwitterCaptureSidecarRunner
    private let fileManager: FileManager
    private let defaults: UserDefaults

    var selectedTask: TwitterCaptureTaskRecord? {
        tasks.first { $0.id == selectedTaskID } ?? tasks.first
    }

    init(
        database: TwitterCaptureFileDatabase = TwitterCaptureFileDatabase(),
        runner: GearCommandRunning = GearShellCommandRunner(),
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        self.database = database
        self.sidecar = TwitterCaptureSidecarRunner(runner: runner, fileManager: fileManager)
        self.fileManager = fileManager
        self.defaults = defaults
        loadTasks()
    }

    func loadTasks() {
        tasks = database.loadTasks()
        selectedTaskID = selectedTaskID ?? tasks.first?.id
    }

    func chooseCookieFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Twitter/X Cookie JSON"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        cookieFilePath = url.path
        defaults.set(url.path, forKey: Self.cookieFileDefaultsKey)
    }

    func runCurrentTask() {
        Task { [weak self, selectedKind, target, limit, cookieFilePath] in
            await self?.runTask(
                kind: selectedKind,
                target: target,
                limit: limit,
                cookieFilePath: cookieFilePath.nilIfBlank,
                capabilityID: nil
            )
        }
    }

    func runAgentAction(capabilityID: String, args: [String: Any]) async -> [String: Any] {
        let request = Self.request(from: capabilityID, args: args)
        guard let request else {
            return [
                "gear_id": TwitterCaptureGearDescriptor.gearID,
                "capability_id": capabilityID,
                "status": "failed",
                "error": "unsupported_or_invalid_arguments"
            ]
        }
        let task = await runTask(
            kind: request.kind,
            target: request.target,
            limit: request.limit,
            cookieFilePath: request.cookieFilePath,
            capabilityID: capabilityID
        )
        return agentPayload(capabilityID: capabilityID, task: task)
    }

    @discardableResult
    private func runTask(
        kind: TwitterCaptureTaskKind,
        target: String,
        limit: Int,
        cookieFilePath: String?,
        capabilityID: String?
    ) async -> TwitterCaptureTaskRecord {
        let now = Date()
        let id = "twitter-\(Self.timestamp())-\(UUID().uuidString.prefix(8))"
        let directory = (try? database.taskDirectory(id))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(id, isDirectory: true)
        let clampedLimit = Self.clampedLimit(kind: kind, limit: limit)
        let task = TwitterCaptureTaskRecord(
            id: id,
            kind: kind,
            target: target,
            normalizedTarget: "",
            limit: clampedLimit,
            status: .queued,
            title: kind.actionTitle,
            createdAt: now,
            updatedAt: now,
            cookieFilePath: cookieFilePath,
            taskDirectoryPath: directory.path,
            tweets: [],
            nextCursor: nil,
            log: "Queued \(kind.rawValue) capture.",
            errorMessage: nil
        )

        tasks.insert(task, at: 0)
        selectedTaskID = task.id
        persist(task)

        isBusy = true
        statusMessage = "Running \(kind.actionTitle.lowercased())..."
        defer {
            isBusy = tasks.contains { $0.status == .running || $0.status == .queued }
        }

        do {
            let request = try validatedSidecarRequest(
                kind: kind,
                target: target,
                limit: clampedLimit,
                cookieFilePath: cookieFilePath
            )
            updateTask(id) { current in
                current.normalizedTarget = request.normalizedTarget
                current.cookieFilePath = request.cookieFilePath
                current.status = .running
                current.updatedAt = Date()
                current.log.append("\nStarted with \(request.action).")
            }

            let result = try await sidecar.run(
                request: request,
                taskDirectory: directory
            )
            updateTask(id) { current in
                current.status = .completed
                current.title = completedTitle(kind: kind, result: result)
                current.tweets = result.items
                current.nextCursor = result.nextCursor
                current.updatedAt = Date()
                current.log.append("\nCaptured \(result.items.count) tweet record(s).")
            }
            statusMessage = "Captured \(result.items.count) tweet record(s)."
        } catch {
            updateTask(id) { current in
                current.status = .failed
                current.errorMessage = error.localizedDescription
                current.updatedAt = Date()
                current.log.append("\nFailed: \(error.localizedDescription)")
            }
            statusMessage = error.localizedDescription
        }

        return tasks.first { $0.id == id } ?? task
    }

    func revealSelectedTask() {
        guard let selectedTask else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([selectedTask.taskURL])
    }

    func openTweet(_ tweet: TwitterCapturedTweet) {
        guard let value = tweet.tweetURL, let url = URL(string: value) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func validatedSidecarRequest(
        kind: TwitterCaptureTaskKind,
        target: String,
        limit: Int,
        cookieFilePath: String?
    ) throws -> TwitterCaptureSidecarRequest {
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTarget.isEmpty else {
            throw TwitterCaptureError.invalidTarget("Enter a Tweet URL, List URL, or username.")
        }

        let cookiePath = expandedCookiePath(cookieFilePath)
        guard let cookiePath, fileManager.fileExists(atPath: cookiePath) else {
            throw TwitterCaptureError.missingCookieFile
        }

        switch kind {
        case .tweet:
            guard let tweetID = TwitterCaptureInputParser.tweetID(from: cleanTarget) else {
                throw TwitterCaptureError.invalidTarget("Enter a valid Twitter/X tweet URL or tweet id.")
            }
            return TwitterCaptureSidecarRequest(
                action: "fetch_tweet",
                normalizedTarget: tweetID,
                cookieFilePath: cookiePath,
                tweetID: tweetID,
                listID: nil,
                handle: nil,
                maxTweets: 1
            )
        case .list:
            guard let listID = TwitterCaptureInputParser.listID(from: cleanTarget) else {
                throw TwitterCaptureError.invalidTarget("Enter a valid Twitter/X list URL or list id.")
            }
            return TwitterCaptureSidecarRequest(
                action: "fetch_list",
                normalizedTarget: listID,
                cookieFilePath: cookiePath,
                tweetID: nil,
                listID: listID,
                handle: nil,
                maxTweets: Self.clampedLimit(kind: kind, limit: limit)
            )
        case .user:
            guard let handle = TwitterCaptureInputParser.handle(from: cleanTarget) else {
                throw TwitterCaptureError.invalidTarget("Enter a valid Twitter/X username or profile URL.")
            }
            return TwitterCaptureSidecarRequest(
                action: "fetch_user",
                normalizedTarget: "@\(handle)",
                cookieFilePath: cookiePath,
                tweetID: nil,
                listID: nil,
                handle: handle,
                maxTweets: Self.clampedLimit(kind: kind, limit: limit)
            )
        }
    }

    private func expandedCookiePath(_ explicitPath: String?) -> String? {
        let candidate = explicitPath?.nilIfBlank ?? cookieFilePath.nilIfBlank ?? defaults.string(forKey: Self.cookieFileDefaultsKey)?.nilIfBlank
        guard let candidate else {
            return nil
        }
        return NSString(string: candidate).expandingTildeInPath
    }

    private func updateTask(_ id: String, mutate: (inout TwitterCaptureTaskRecord) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&tasks[index])
        persist(tasks[index])
    }

    private func persist(_ task: TwitterCaptureTaskRecord) {
        do {
            try database.save(task)
        } catch {
            statusMessage = "Could not save Twitter Capture task: \(error.localizedDescription)"
        }
    }

    private func agentPayload(capabilityID: String, task: TwitterCaptureTaskRecord) -> [String: Any] {
        var payload: [String: Any] = [
            "gear_id": TwitterCaptureGearDescriptor.gearID,
            "capability_id": capabilityID,
            "task_id": task.id,
            "task_path": task.taskURL.path,
            "kind": task.kind.rawValue,
            "target": task.target,
            "normalized_target": task.normalizedTarget,
            "limit": task.limit,
            "status": task.status.rawValue,
            "tweet_count": task.tweets.count,
            "tweets": task.tweets.map(\.agentDictionary)
        ]
        if let errorMessage = task.errorMessage?.nilIfBlank {
            payload["error"] = errorMessage
        }
        if let nextCursor = task.nextCursor?.nilIfBlank {
            payload["next_cursor"] = nextCursor
        }
        return payload
    }

    private static func request(from capabilityID: String, args: [String: Any]) -> AgentRequest? {
        switch capabilityID {
        case "twitter.fetch_tweet":
            guard let url = stringArg(args, "url") ?? stringArg(args, "tweet_url") else {
                return nil
            }
            return AgentRequest(
                kind: .tweet,
                target: url,
                limit: 1,
                cookieFilePath: stringArg(args, "cookie_file")
            )
        case "twitter.fetch_list":
            guard let url = stringArg(args, "url") ?? stringArg(args, "list_url") else {
                return nil
            }
            return AgentRequest(
                kind: .list,
                target: url,
                limit: intArg(args, "limit") ?? intArg(args, "max_tweets") ?? 30,
                cookieFilePath: stringArg(args, "cookie_file")
            )
        case "twitter.fetch_user":
            guard let username = stringArg(args, "username") ?? stringArg(args, "handle") ?? stringArg(args, "url") else {
                return nil
            }
            return AgentRequest(
                kind: .user,
                target: username,
                limit: intArg(args, "limit") ?? intArg(args, "max_tweets") ?? 30,
                cookieFilePath: stringArg(args, "cookie_file")
            )
        default:
            return nil
        }
    }

    private static func stringArg(_ args: [String: Any], _ key: String) -> String? {
        args[key] as? String
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

    private static func clampedLimit(kind: TwitterCaptureTaskKind, limit: Int) -> Int {
        guard kind.supportsLimit else {
            return 1
        }
        return min(max(limit, 1), 200)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func completedTitle(kind: TwitterCaptureTaskKind, result: TwitterCaptureSidecarResult) -> String {
        switch kind {
        case .tweet:
            return result.items.first?.authorHandle ?? "Tweet Capture"
        case .list:
            return "List Capture"
        case .user:
            return result.items.first?.authorHandle ?? "User Capture"
        }
    }
}

private struct AgentRequest {
    var kind: TwitterCaptureTaskKind
    var target: String
    var limit: Int
    var cookieFilePath: String?
}

struct TwitterCaptureSidecarRequest {
    var action: String
    var normalizedTarget: String
    var cookieFilePath: String
    var tweetID: String?
    var listID: String?
    var handle: String?
    var maxTweets: Int
}

struct TwitterCaptureSidecarResult: Decodable, Hashable {
    var items: [TwitterCapturedTweet]
    var nextCursor: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case error
    }
}

struct TwitterCaptureSidecarRunner: @unchecked Sendable {
    var runner: GearCommandRunning
    var fileManager: FileManager = .default

    func run(
        request: TwitterCaptureSidecarRequest,
        taskDirectory: URL
    ) async throws -> TwitterCaptureSidecarResult {
        let scriptURL = try Self.sidecarScriptURL()
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw TwitterCaptureError.missingSidecar
        }
        try fileManager.createDirectory(at: taskDirectory, withIntermediateDirectories: true)

        let requestURL = taskDirectory.appendingPathComponent("request.json")
        let requestData = try JSONEncoder().encode(SidecarCommand(request: request))
        try requestData.write(to: requestURL, options: .atomic)

        let result = await runner.run(
            "python3",
            arguments: [scriptURL.path, requestURL.path],
            timeoutSeconds: request.action == "fetch_tweet" ? 120 : 300
        )
        guard result.exitCode == 0 else {
            if let error = try? Self.decodeError(from: result.stdout) {
                throw TwitterCaptureError.sidecarError(error)
            }
            throw TwitterCaptureError.commandFailed(result.combinedOutput)
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = output.data(using: .utf8) else {
            throw TwitterCaptureError.invalidSidecarOutput("stdout was not UTF-8.")
        }
        let decoded = try JSONDecoder().decode(TwitterCaptureSidecarResult.self, from: data)
        if let error = decoded.error?.nilIfBlank {
            throw TwitterCaptureError.sidecarError(error)
        }
        return decoded
    }

    private static func sidecarScriptURL() throws -> URL {
        guard let manifest = GearHost.manifest(gearID: TwitterCaptureGearDescriptor.gearID) else {
            throw TwitterCaptureError.missingSidecar
        }
        return manifest.rootURL.appendingPathComponent("scripts/twikit_sidecar.py")
    }

    private static func decodeError(from stdout: String) throws -> String? {
        let text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object["error"] as? String
    }

    private struct SidecarCommand: Encodable {
        var action: String
        var params: SidecarParams

        init(request: TwitterCaptureSidecarRequest) {
            action = request.action
            params = SidecarParams(
                cookieFile: request.cookieFilePath,
                tweetID: request.tweetID,
                listID: request.listID,
                handle: request.handle,
                maxTweets: request.maxTweets
            )
        }
    }

    private struct SidecarParams: Encodable {
        var cookieFile: String
        var tweetID: String?
        var listID: String?
        var handle: String?
        var maxTweets: Int

        enum CodingKeys: String, CodingKey {
            case cookieFile = "cookie_file"
            case tweetID = "tweet_id"
            case listID = "list_id"
            case handle
            case maxTweets = "max_tweets"
        }
    }
}
