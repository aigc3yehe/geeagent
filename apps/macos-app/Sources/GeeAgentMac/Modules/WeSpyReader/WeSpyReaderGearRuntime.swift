import AppKit
import Foundation

enum WeSpyReaderTaskKind: String, Codable, CaseIterable, Identifiable {
    case article
    case albumList
    case albumDownload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .article: "Article URL"
        case .albumList: "Album List"
        case .albumDownload: "Album Download"
        }
    }

    var actionTitle: String {
        switch self {
        case .article: "Fetch Article"
        case .albumList: "List Album"
        case .albumDownload: "Fetch Album"
        }
    }

    var placeholder: String {
        switch self {
        case .article: "https://mp.weixin.qq.com/s/..."
        case .albumList, .albumDownload: "https://mp.weixin.qq.com/mp/appmsgalbum?..."
        }
    }

    var sidecarAction: String {
        switch self {
        case .article: "fetch_article"
        case .albumList: "list_album"
        case .albumDownload: "fetch_album"
        }
    }

    var capabilityID: String {
        switch self {
        case .article: "wespy.fetch_article"
        case .albumList: "wespy.list_album"
        case .albumDownload: "wespy.fetch_album"
        }
    }

    var systemImage: String {
        switch self {
        case .article: "doc.text.magnifyingglass"
        case .albumList: "list.bullet.rectangle"
        case .albumDownload: "tray.and.arrow.down"
        }
    }

    var supportsLimit: Bool {
        self != .article
    }
}

enum WeSpyReaderTaskStatus: String, Codable, Hashable {
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

struct WeSpyReaderArticleSummary: Codable, Hashable, Identifiable {
    var title: String?
    var author: String?
    var publishTime: String?
    var url: String?
    var msgid: String?
    var createTime: String?

    var id: String {
        [url, msgid, title, createTime]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: "|")
            .nilIfBlank ?? "article-summary"
    }

    enum CodingKeys: String, CodingKey {
        case title
        case author
        case publishTime = "publish_time"
        case url
        case msgid
        case createTime = "create_time"
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [:]
        if let title = title?.nilIfBlank { payload["title"] = title }
        if let author = author?.nilIfBlank { payload["author"] = author }
        if let publishTime = publishTime?.nilIfBlank { payload["publish_time"] = publishTime }
        if let url = url?.nilIfBlank { payload["url"] = url }
        if let msgid = msgid?.nilIfBlank { payload["msgid"] = msgid }
        if let createTime = createTime?.nilIfBlank { payload["create_time"] = createTime }
        return payload
    }
}

struct WeSpyReaderTaskRecord: Codable, Identifiable, Hashable {
    var id: String
    var kind: WeSpyReaderTaskKind
    var url: String
    var maxArticles: Int
    var saveHTML: Bool
    var saveJSON: Bool
    var saveMarkdown: Bool
    var status: WeSpyReaderTaskStatus
    var title: String
    var author: String?
    var publishTime: String?
    var articleCount: Int
    var outputDirectoryPath: String
    var taskDirectoryPath: String
    var files: [String]
    var articles: [WeSpyReaderArticleSummary]
    var log: String
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case url
        case maxArticles = "max_articles"
        case saveHTML = "save_html"
        case saveJSON = "save_json"
        case saveMarkdown = "save_markdown"
        case status
        case title
        case author
        case publishTime = "publish_time"
        case articleCount = "article_count"
        case outputDirectoryPath = "output_directory_path"
        case taskDirectoryPath = "task_directory_path"
        case files
        case articles
        case log
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var taskURL: URL {
        URL(fileURLWithPath: taskDirectoryPath, isDirectory: true).appendingPathComponent("task.json")
    }

    var resultSummary: String {
        switch status {
        case .completed:
            if kind == .albumList {
                return "\(articleCount) article URL\(articleCount == 1 ? "" : "s") listed"
            }
            return "\(articleCount) article\(articleCount == 1 ? "" : "s") captured, \(files.count) file\(files.count == 1 ? "" : "s")"
        case .failed:
            return errorMessage ?? "Task failed"
        case .queued:
            return "Waiting to start"
        case .running:
            return "Running WeSpy"
        }
    }
}

enum WeSpyReaderError: LocalizedError {
    case invalidURL
    case missingSidecar
    case commandFailed(String)
    case invalidSidecarOutput(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid article or WeChat album URL."
        case .missingSidecar:
            "WeSpy Reader sidecar script is missing from the gear package."
        case let .commandFailed(detail):
            "WeSpy sidecar failed. \(detail)"
        case let .invalidSidecarOutput(message):
            "WeSpy returned invalid data. \(message)"
        }
    }
}

struct WeSpyReaderFileDatabase {
    var rootURL: URL?
    var fileManager: FileManager = .default

    func loadTasks() -> [WeSpyReaderTaskRecord] {
        do {
            let entries = try fileManager.contentsOfDirectory(
                at: try tasksRoot(),
                includingPropertiesForKeys: [.isDirectoryKey],
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

    func save(_ task: WeSpyReaderTaskRecord) throws {
        let directory = try taskDirectory(task.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(task).write(to: directory.appendingPathComponent("task.json"), options: .atomic)
    }

    func taskDirectory(_ id: String) throws -> URL {
        try tasksRoot().appendingPathComponent(id, isDirectory: true)
    }

    func outputDirectory(_ id: String) throws -> URL {
        try taskDirectory(id).appendingPathComponent("output", isDirectory: true)
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
        .appendingPathComponent("GeeAgent/gear-data/wespy.reader", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func tasksRoot() throws -> URL {
        let root = try dataRoot().appendingPathComponent("tasks", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func loadTask(_ directory: URL) -> WeSpyReaderTaskRecord? {
        let url = directory.appendingPathComponent("task.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WeSpyReaderTaskRecord.self, from: data)
    }
}

enum WeSpyReaderInputParser {
    static func isHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    static func isWeChatAlbumURL(_ value: String) -> Bool {
        value.lowercased().contains("mp.weixin.qq.com/mp/appmsgalbum")
    }
}

@MainActor
final class WeSpyReaderGearStore: ObservableObject {
    static let shared = WeSpyReaderGearStore()

    @Published var selectedKind: WeSpyReaderTaskKind = .article
    @Published var url = ""
    @Published var maxArticles = 10
    @Published var saveHTML = false
    @Published var saveJSON = false
    @Published private(set) var tasks: [WeSpyReaderTaskRecord] = []
    @Published var selectedTaskID: WeSpyReaderTaskRecord.ID?
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var isBusy = false

    private let database: WeSpyReaderFileDatabase
    private let sidecar: WeSpyReaderSidecarRunner

    var selectedTask: WeSpyReaderTaskRecord? {
        tasks.first { $0.id == selectedTaskID } ?? tasks.first
    }

    init(
        database: WeSpyReaderFileDatabase = WeSpyReaderFileDatabase(),
        runner: GearCommandRunning = GearShellCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.database = database
        self.sidecar = WeSpyReaderSidecarRunner(runner: runner, fileManager: fileManager)
        loadTasks()
    }

    func loadTasks() {
        tasks = database.loadTasks()
        selectedTaskID = selectedTaskID ?? tasks.first?.id
    }

    func runCurrentTask() {
        Task { [weak self, selectedKind, url, maxArticles, saveHTML, saveJSON] in
            await self?.runTask(
                kind: selectedKind,
                url: url,
                maxArticles: maxArticles,
                saveHTML: saveHTML,
                saveJSON: saveJSON,
                capabilityID: nil
            )
        }
    }

    func runAgentAction(capabilityID: String, args: [String: Any]) async -> [String: Any] {
        guard let request = Self.request(from: capabilityID, args: args) else {
            return [
                "gear_id": WeSpyReaderGearDescriptor.gearID,
                "capability_id": capabilityID,
                "status": "failed",
                "error": "unsupported_or_invalid_arguments"
            ]
        }
        let task = await runTask(
            kind: request.kind,
            url: request.url,
            maxArticles: request.maxArticles,
            saveHTML: request.saveHTML,
            saveJSON: request.saveJSON,
            capabilityID: capabilityID
        )
        let exportedMarkdownPath = exportCombinedMarkdownIfRequested(request.exportMarkdown, task: task)
        return agentPayload(
            capabilityID: capabilityID,
            task: task,
            exportedMarkdownPath: exportedMarkdownPath
        )
    }

    @discardableResult
    private func runTask(
        kind: WeSpyReaderTaskKind,
        url: String,
        maxArticles: Int,
        saveHTML: Bool,
        saveJSON: Bool,
        capabilityID: String?
    ) async -> WeSpyReaderTaskRecord {
        let now = Date()
        let id = "wespy-\(Self.timestamp())-\(UUID().uuidString.prefix(8))"
        let directory = (try? database.taskDirectory(id))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(id, isDirectory: true)
        let outputDirectory = (try? database.outputDirectory(id))
            ?? directory.appendingPathComponent("output", isDirectory: true)
        let task = WeSpyReaderTaskRecord(
            id: id,
            kind: kind,
            url: url,
            maxArticles: Self.clampedMaxArticles(maxArticles),
            saveHTML: saveHTML,
            saveJSON: saveJSON,
            saveMarkdown: true,
            status: .queued,
            title: kind.actionTitle,
            author: nil,
            publishTime: nil,
            articleCount: 0,
            outputDirectoryPath: outputDirectory.path,
            taskDirectoryPath: directory.path,
            files: [],
            articles: [],
            log: "Queued \(kind.rawValue) task.",
            errorMessage: nil,
            createdAt: now,
            updatedAt: now
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
            guard WeSpyReaderInputParser.isHTTPURL(url) else {
                throw WeSpyReaderError.invalidURL
            }
            updateTask(id) { current in
                current.status = .running
                current.updatedAt = Date()
                current.log.append("\nStarted WeSpy \(kind.sidecarAction).")
            }

            let result = try await sidecar.run(
                request: WeSpyReaderSidecarRequest(
                    action: kind.sidecarAction,
                    url: url,
                    outputDirectoryPath: outputDirectory.path,
                    maxArticles: Self.clampedMaxArticles(maxArticles),
                    saveHTML: saveHTML,
                    saveJSON: saveJSON,
                    saveMarkdown: true
                ),
                taskDirectory: directory
            )
            updateTask(id) { current in
                current.status = result.status == "failed" ? .failed : .completed
                current.title = result.title?.nilIfBlank ?? kind.actionTitle
                current.author = result.author
                current.publishTime = result.publishTime
                current.articleCount = result.articleCount ?? result.articles.count
                current.files = result.files
                current.articles = result.articles
                current.errorMessage = result.error
                current.updatedAt = Date()
                current.log.append("\n\(result.log?.nilIfBlank ?? "WeSpy finished.")")
            }
            statusMessage = result.status == "failed"
                ? (result.error ?? "WeSpy failed.")
                : "Captured \(result.articleCount ?? result.articles.count) article record(s)."
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
        guard let selectedTask else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedTask.taskURL])
    }

    func revealFile(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openSourceURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateTask(_ id: String, mutate: (inout WeSpyReaderTaskRecord) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&tasks[index])
        persist(tasks[index])
    }

    private func persist(_ task: WeSpyReaderTaskRecord) {
        do {
            try database.save(task)
        } catch {
            statusMessage = "Could not save WeSpy task: \(error.localizedDescription)"
        }
    }

    private func agentPayload(
        capabilityID: String,
        task: WeSpyReaderTaskRecord,
        exportedMarkdownPath: String? = nil
    ) -> [String: Any] {
        let files = exportedMarkdownPath.map { task.files + [$0] } ?? task.files
        var payload: [String: Any] = [
            "gear_id": WeSpyReaderGearDescriptor.gearID,
            "capability_id": capabilityID,
            "task_id": task.id,
            "task_path": task.taskURL.path,
            "kind": task.kind.rawValue,
            "url": task.url,
            "status": task.status.rawValue,
            "article_count": task.articleCount,
            "output_dir": task.outputDirectoryPath,
            "files": files,
            "articles": task.articles.map(\.agentDictionary)
        ]
        if let exportedMarkdownPath { payload["exported_markdown_path"] = exportedMarkdownPath }
        if let title = task.title.nilIfBlank { payload["title"] = title }
        if let author = task.author?.nilIfBlank { payload["author"] = author }
        if let publishTime = task.publishTime?.nilIfBlank { payload["publish_time"] = publishTime }
        if let errorMessage = task.errorMessage?.nilIfBlank { payload["error"] = errorMessage }
        return payload
    }

    private static func request(from capabilityID: String, args: [String: Any]) -> AgentRequest? {
        guard let url = stringArg(args, "url") ?? stringArg(args, "article_url") ?? stringArg(args, "album_url") else {
            return nil
        }
        let kind: WeSpyReaderTaskKind
        switch capabilityID {
        case "wespy.fetch_article":
            kind = .article
        case "wespy.list_album":
            kind = .albumList
        case "wespy.fetch_album":
            kind = .albumDownload
        default:
            return nil
        }
        return AgentRequest(
            kind: kind,
            url: url,
            maxArticles: intArg(args, "max_articles") ?? intArg(args, "limit") ?? 10,
            saveHTML: boolArg(args, "save_html") ?? boolArg(args, "html") ?? false,
            saveJSON: boolArg(args, "save_json") ?? boolArg(args, "json") ?? false,
            exportMarkdown: boolArg(args, "export_markdown") ?? false
        )
    }

    private func exportCombinedMarkdownIfRequested(
        _ requested: Bool,
        task: WeSpyReaderTaskRecord
    ) -> String? {
        guard requested, task.status == .completed, let exportURL = safeMarkdownExportURL(task: task) else {
            return nil
        }

        let sections = safeMarkdownSourceURLs(task: task)
            .compactMap { filePath -> String? in
                guard let text = try? String(contentsOf: filePath, encoding: .utf8) else {
                    return nil
                }
                return text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfBlank
            }

        guard !sections.isEmpty else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: exportURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try sections
                .joined(separator: "\n\n---\n\n")
                .write(to: exportURL, atomically: true, encoding: .utf8)
            return exportURL.path
        } catch {
            statusMessage = "Could not export markdown: \(error.localizedDescription)"
            return nil
        }
    }

    private func safeMarkdownExportURL(task: WeSpyReaderTaskRecord) -> URL? {
        let taskRoot = URL(fileURLWithPath: task.taskDirectoryPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let exportURL = taskRoot
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent("combined.md")
            .standardizedFileURL
        guard path(exportURL.deletingLastPathComponent().path, isInside: taskRoot.path) else {
            return nil
        }
        return exportURL
    }

    private func safeMarkdownSourceURLs(task: WeSpyReaderTaskRecord) -> [URL] {
        let outputRoot = URL(fileURLWithPath: task.outputDirectoryPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return task.files.compactMap { filePath in
            let url = URL(fileURLWithPath: filePath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let ext = url.pathExtension.lowercased()
            guard (ext == "md" || ext == "markdown"),
                  path(url.path, isInside: outputRoot.path)
            else {
                return nil
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                return nil
            }
            return url
        }
    }

    private func path(_ candidate: String, isInside root: String) -> Bool {
        let normalizedRoot = root.hasSuffix("/") ? root : "\(root)/"
        return candidate == root || candidate.hasPrefix(normalizedRoot)
    }

    private static func stringArg(_ args: [String: Any], _ key: String) -> String? {
        args[key] as? String
    }

    private static func intArg(_ args: [String: Any], _ key: String) -> Int? {
        if let int = args[key] as? Int { return int }
        if let double = args[key] as? Double { return Int(double) }
        if let string = args[key] as? String { return Int(string) }
        return nil
    }

    private static func boolArg(_ args: [String: Any], _ key: String) -> Bool? {
        if let bool = args[key] as? Bool { return bool }
        if let string = args[key] as? String {
            switch string.lowercased() {
            case "true", "1", "yes", "on": return true
            case "false", "0", "no", "off": return false
            default: return nil
            }
        }
        return nil
    }

    private static func clampedMaxArticles(_ value: Int) -> Int {
        min(max(value, 1), 200)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private struct AgentRequest {
    var kind: WeSpyReaderTaskKind
    var url: String
    var maxArticles: Int
    var saveHTML: Bool
    var saveJSON: Bool
    var exportMarkdown: Bool
}

struct WeSpyReaderSidecarRequest {
    var action: String
    var url: String
    var outputDirectoryPath: String
    var maxArticles: Int
    var saveHTML: Bool
    var saveJSON: Bool
    var saveMarkdown: Bool
}

struct WeSpyReaderSidecarResult: Decodable, Hashable {
    var status: String
    var action: String?
    var url: String?
    var outputDir: String?
    var files: [String]
    var title: String?
    var author: String?
    var publishTime: String?
    var articleCount: Int?
    var articles: [WeSpyReaderArticleSummary]
    var log: String?
    var error: String?
    var code: String?

    enum CodingKeys: String, CodingKey {
        case status
        case action
        case url
        case outputDir = "output_dir"
        case files
        case title
        case author
        case publishTime = "publish_time"
        case articleCount = "article_count"
        case articles
        case log
        case error
        case code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        outputDir = try container.decodeIfPresent(String.self, forKey: .outputDir)
        files = try container.decodeIfPresent([String].self, forKey: .files) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        publishTime = try container.decodeIfPresent(String.self, forKey: .publishTime)
        articleCount = try container.decodeIfPresent(Int.self, forKey: .articleCount)
        articles = try container.decodeIfPresent([WeSpyReaderArticleSummary].self, forKey: .articles) ?? []
        log = try container.decodeIfPresent(String.self, forKey: .log)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        code = try container.decodeIfPresent(String.self, forKey: .code)

        if articles.isEmpty,
           articleCount ?? 0 > 0 || title?.nilIfBlank != nil || url?.nilIfBlank != nil
        {
            articles = [
                WeSpyReaderArticleSummary(
                    title: title?.nilIfBlank,
                    author: author?.nilIfBlank,
                    publishTime: publishTime?.nilIfBlank,
                    url: url?.nilIfBlank,
                    msgid: nil,
                    createTime: nil
                )
            ]
        }
    }
}

struct WeSpyReaderSidecarRunner: @unchecked Sendable {
    var runner: GearCommandRunning
    var fileManager: FileManager = .default

    func run(
        request: WeSpyReaderSidecarRequest,
        taskDirectory: URL
    ) async throws -> WeSpyReaderSidecarResult {
        let scriptURL = try Self.sidecarScriptURL()
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw WeSpyReaderError.missingSidecar
        }
        try fileManager.createDirectory(at: taskDirectory, withIntermediateDirectories: true)

        let requestURL = taskDirectory.appendingPathComponent("request.json")
        let data = try JSONEncoder().encode(SidecarCommand(request: request))
        try data.write(to: requestURL, options: .atomic)

        let result = await runner.run(
            "python3",
            arguments: [scriptURL.path, requestURL.path],
            timeoutSeconds: request.action == "fetch_album" ? 600 : 180
        )
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let outputData = output.data(using: .utf8), !outputData.isEmpty else {
            throw WeSpyReaderError.commandFailed(result.combinedOutput)
        }
        let decoded = try JSONDecoder().decode(WeSpyReaderSidecarResult.self, from: outputData)
        if result.exitCode != 0, decoded.status != "failed" {
            throw WeSpyReaderError.commandFailed(result.combinedOutput)
        }
        return decoded
    }

    private static func sidecarScriptURL() throws -> URL {
        guard let manifest = GearHost.manifest(gearID: WeSpyReaderGearDescriptor.gearID) else {
            throw WeSpyReaderError.missingSidecar
        }
        return manifest.rootURL.appendingPathComponent("scripts/wespy_sidecar.py")
    }

    private struct SidecarCommand: Encodable {
        var action: String
        var params: SidecarParams

        init(request: WeSpyReaderSidecarRequest) {
            action = request.action
            params = SidecarParams(
                url: request.url,
                outputDir: request.outputDirectoryPath,
                maxArticles: request.maxArticles,
                saveHTML: request.saveHTML,
                saveJSON: request.saveJSON,
                saveMarkdown: request.saveMarkdown
            )
        }
    }

    private struct SidecarParams: Encodable {
        var url: String
        var outputDir: String
        var maxArticles: Int
        var saveHTML: Bool
        var saveJSON: Bool
        var saveMarkdown: Bool

        enum CodingKeys: String, CodingKey {
            case url
            case outputDir = "output_dir"
            case maxArticles = "max_articles"
            case saveHTML = "save_html"
            case saveJSON = "save_json"
            case saveMarkdown = "save_markdown"
        }
    }
}
