import AppKit
import Foundation
import UniformTypeIdentifiers

enum MediaGeneratorCategory: String, Codable, CaseIterable, Identifiable {
    case image
    case video
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        }
    }

    var systemImage: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        }
    }
}

enum MediaGeneratorTaskStatus: String, Codable, Hashable {
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

enum MediaGeneratorTaskFilter: String, CaseIterable, Identifiable {
    case all
    case completed
    case running
    case failed
    case starred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .completed: "Done"
        case .running: "Running"
        case .failed: "Failed"
        case .starred: "Starred"
        }
    }
}

enum MediaGeneratorModelID: String, Codable, CaseIterable, Identifiable {
    case nanoBananaPro = "nano-banana-pro"
    case gptImage2 = "gpt-image-2"
    case veo31 = "veo3.1"
    case veo31Fast = "veo3.1_fast"
    case veo31Lite = "veo3.1_lite"
    case seedance2 = "seedance-2"
    case seedance2Fast = "seedance-2-fast"

    var id: String { rawValue }

    var category: MediaGeneratorCategory {
        switch self {
        case .nanoBananaPro, .gptImage2:
            .image
        case .veo31, .veo31Fast, .veo31Lite, .seedance2, .seedance2Fast:
            .video
        }
    }

    var title: String {
        switch self {
        case .nanoBananaPro: "Nano Banana Pro"
        case .gptImage2: "GPT Image-2"
        case .veo31: "Veo3.1"
        case .veo31Fast: "Veo3.1 Fast"
        case .veo31Lite: "Veo3.1 Lite"
        case .seedance2: "Seedance 2.0"
        case .seedance2Fast: "Seedance 2.0 Fast"
        }
    }

    var subtitle: String {
        switch self {
        case .nanoBananaPro: "Xenodia image model with aspect ratio, resolution, output format, and up to 8 references."
        case .gptImage2: "Xenodia GPT Image-2 with prompt/reference routing, resolution controls, and up to 16 references."
        case .veo31: "Xenodia Veo3.1 quality video model with task-only polling."
        case .veo31Fast: "Xenodia Veo3.1 fast video model and default for reference-to-video."
        case .veo31Lite: "Xenodia Veo3.1 lite video model for lower-cost drafts."
        case .seedance2: "Xenodia Seedance 2.0 video model with 480p, 720p, and 1080p output."
        case .seedance2Fast: "Xenodia Seedance 2.0 fast video model with multimodal reference support."
        }
    }

    var isVeo: Bool {
        switch self {
        case .veo31, .veo31Fast, .veo31Lite:
            true
        default:
            false
        }
    }

    var isSeedance: Bool {
        switch self {
        case .seedance2, .seedance2Fast:
            true
        default:
            false
        }
    }
}

enum MediaGeneratorAspectRatio: String, Codable, CaseIterable, Identifiable {
    case auto
    case adaptive
    case square = "1:1"
    case tall = "2:3"
    case wide = "3:2"
    case classicPortrait = "3:4"
    case classicLandscape = "4:3"
    case portrait = "4:5"
    case vertical = "5:4"
    case story = "9:16"
    case landscape = "16:9"
    case cinema = "21:9"

    var id: String { rawValue }
}

enum MediaGeneratorResolution: String, Codable, CaseIterable, Identifiable {
    case oneK = "1K"
    case twoK = "2K"
    case fourK = "4K"
    case p480 = "480p"
    case p720 = "720p"
    case p1080 = "1080p"
    case video4K = "4k"

    var id: String { rawValue }
}

enum MediaGeneratorVideoGenerationType: String, Codable, CaseIterable, Identifiable {
    case textToVideo = "TEXT_2_VIDEO"
    case firstAndLastFrames = "FIRST_AND_LAST_FRAMES_2_VIDEO"
    case referenceToVideo = "REFERENCE_2_VIDEO"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .textToVideo: "Text"
        case .firstAndLastFrames: "First/Last"
        case .referenceToVideo: "Reference"
        }
    }
}

enum MediaGeneratorOutputFormat: String, Codable, CaseIterable, Identifiable {
    case png
    case jpg

    var id: String { rawValue }
}

struct MediaGeneratorReference: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var url: String?
    var localPath: String?
    var displayName: String

    var isRemote: Bool {
        url != nil
    }

    var previewURL: URL? {
        if let localPath {
            return URL(fileURLWithPath: localPath)
        }
        guard let url,
              let parsed = URL(string: url),
              parsed.scheme?.hasPrefix("http") == true
        else {
            return nil
        }
        return parsed
    }
}

struct MediaGeneratorVideoOptions: Hashable, Sendable {
    var generationType: MediaGeneratorVideoGenerationType = .textToVideo
    var duration: Int = 5
    var generateAudio: Bool = false
    var webSearch: Bool = false
    var nsfwChecker: Bool = false
    var seed: Int?
    var enableTranslation: Bool = true
    var watermark: String?
    var firstFrameURL: String?
    var lastFrameURL: String?
    var referenceVideoURLs: [String] = []
    var referenceAudioURLs: [String] = []
    var callbackURL: String?

    static let `default` = MediaGeneratorVideoOptions()
}

struct MediaGeneratorQuickPrompt: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var content: String

    static let defaults: [MediaGeneratorQuickPrompt] = [
        MediaGeneratorQuickPrompt(
            id: "cinematic",
            name: "Cinematic",
            content: "cinematic lighting, refined composition"
        ),
        MediaGeneratorQuickPrompt(
            id: "product",
            name: "Product",
            content: "premium product photography, soft reflections"
        ),
        MediaGeneratorQuickPrompt(
            id: "storyboard",
            name: "Storyboard",
            content: "clear subject silhouette, production-ready frame"
        )
    ]
}

struct MediaGeneratorImageHistoryItem: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var url: String?
    var localPath: String?
    var displayName: String
    var timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case localPath
        case displayName
        case timestamp
    }

    init(
        id: String = UUID().uuidString,
        url: String? = nil,
        localPath: String? = nil,
        displayName: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.localPath = localPath
        self.displayName = displayName ?? Self.defaultDisplayName(url: url, localPath: localPath)
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let url = try container.decodeIfPresent(String.self, forKey: .url)
        let localPath = try container.decodeIfPresent(String.self, forKey: .localPath)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.url = url
        self.localPath = localPath
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? Self.defaultDisplayName(url: url, localPath: localPath)
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }

    var historyKey: String {
        url ?? localPath ?? id
    }

    var previewURL: URL? {
        if let url {
            return URL(string: url)
        }
        if let localPath {
            return URL(fileURLWithPath: localPath)
        }
        return nil
    }

    private static func defaultDisplayName(url: String?, localPath: String?) -> String {
        if let url,
           let parsed = URL(string: url) {
            return parsed.lastPathComponent.isEmpty ? parsed.host ?? "Reference URL" : parsed.lastPathComponent
        }
        if let localPath {
            return URL(fileURLWithPath: localPath).lastPathComponent
        }
        return "Reference Image"
    }
}

struct MediaGeneratorTask: Codable, Identifiable, Hashable, Sendable {
    static let currentSchemaVersion = 2

    var id: String
    var category: MediaGeneratorCategory
    var modelID: MediaGeneratorModelID
    var prompt: String
    var status: MediaGeneratorTaskStatus
    var createdAt: Date
    var updatedAt: Date
    var providerTaskID: String?
    var resultURL: String?
    var localOutputPath: String?
    var errorMessage: String?
    var parameters: [String: String]
    var references: [MediaGeneratorReference]
    var isStarred: Bool = false
    var schemaVersion: Int = Self.currentSchemaVersion
    var batchID: String?
    var batchIndex: Int = 1
    var batchCount: Int = 1

    var displayTitle: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? modelID.title : prompt
    }

    var resultDisplayURL: URL? {
        if let localOutputPath, FileManager.default.fileExists(atPath: localOutputPath) {
            return URL(fileURLWithPath: localOutputPath)
        }
        guard let resultURL else {
            return nil
        }
        return URL(string: resultURL)
    }

    var isLocallyCached: Bool {
        guard let localOutputPath else {
            return false
        }
        return FileManager.default.fileExists(atPath: localOutputPath)
    }

    var resultFileExtension: String {
        if let localOutputPath {
            let ext = URL(fileURLWithPath: localOutputPath).pathExtension
            if !ext.isEmpty {
                return ext
            }
        }
        if let resultURL, let url = URL(string: resultURL) {
            let ext = url.pathExtension
            if !ext.isEmpty {
                return ext
            }
        }
        if category == .video {
            return "mp4"
        }
        return parameters["output_format"] == "jpg" ? "jpg" : "png"
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "task_id": id,
            "gear_id": MediaGeneratorGearDescriptor.gearID,
            "category": category.rawValue,
            "model": modelID.rawValue,
            "prompt": prompt,
            "status": status.rawValue,
            "schema_version": schemaVersion,
            "created_at": ISO8601DateFormatter().string(from: createdAt),
            "updated_at": ISO8601DateFormatter().string(from: updatedAt),
            "batch_index": batchIndex,
            "batch_count": batchCount,
            "parameters": parameters,
            "references": references.map { reference in
                [
                    "id": reference.id,
                    "url": reference.url ?? "",
                    "local_path": reference.localPath ?? "",
                    "display_name": reference.displayName
                ]
            }
        ]
        if let providerTaskID { payload["provider_task_id"] = providerTaskID }
        if let resultURL { payload["result_url"] = resultURL }
        if let localOutputPath { payload["local_output_path"] = localOutputPath }
        if let errorMessage { payload["error"] = errorMessage }
        if let batchID { payload["batch_id"] = batchID }
        payload["is_starred"] = isStarred
        payload["is_locally_cached"] = isLocallyCached
        return payload
    }
}

extension MediaGeneratorTask {
    enum CodingKeys: String, CodingKey {
        case id
        case category
        case modelID
        case prompt
        case status
        case createdAt
        case updatedAt
        case providerTaskID
        case resultURL
        case localOutputPath
        case errorMessage
        case parameters
        case references
        case isStarred
        case schemaVersion
        case batchID
        case batchIndex
        case batchCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == MediaGeneratorTask.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported media generator task schema \(schemaVersion)."
            )
        }
        self.id = try container.decode(String.self, forKey: .id)
        self.category = try container.decode(MediaGeneratorCategory.self, forKey: .category)
        self.modelID = try container.decode(MediaGeneratorModelID.self, forKey: .modelID)
        self.prompt = try container.decode(String.self, forKey: .prompt)
        self.status = try container.decode(MediaGeneratorTaskStatus.self, forKey: .status)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.providerTaskID = try container.decodeIfPresent(String.self, forKey: .providerTaskID)
        self.resultURL = try container.decodeIfPresent(String.self, forKey: .resultURL)
        self.localOutputPath = try container.decodeIfPresent(String.self, forKey: .localOutputPath)
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        self.parameters = try container.decode([String: String].self, forKey: .parameters)
        self.references = try container.decode([MediaGeneratorReference].self, forKey: .references)
        self.isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        self.schemaVersion = schemaVersion
        self.batchID = try container.decodeIfPresent(String.self, forKey: .batchID)
        self.batchIndex = try container.decode(Int.self, forKey: .batchIndex)
        self.batchCount = try container.decode(Int.self, forKey: .batchCount)
    }
}

struct MediaGeneratorTaskGroup: Identifiable, Hashable, Sendable {
    var id: String
    var batchID: String?
    var tasks: [MediaGeneratorTask]

    var representative: MediaGeneratorTask {
        tasks.sorted(by: Self.sortTasks).first!
    }

    var isBatch: Bool {
        batchID != nil || tasks.count > 1 || representative.batchCount > 1
    }

    var batchCount: Int {
        max(representative.batchCount, tasks.count)
    }

    var completedCount: Int {
        tasks.filter { $0.status == .completed }.count
    }

    var failedCount: Int {
        tasks.filter { $0.status == .failed }.count
    }

    var runningCount: Int {
        tasks.filter { $0.status == .running || $0.status == .queued }.count
    }

    var statusTitle: String {
        if completedCount == tasks.count {
            return MediaGeneratorTaskStatus.completed.title
        }
        if failedCount == tasks.count {
            return MediaGeneratorTaskStatus.failed.title
        }
        if failedCount > 0, runningCount == 0 {
            return "Partial"
        }
        if runningCount > 0 {
            return MediaGeneratorTaskStatus.running.title
        }
        return representative.status.title
    }

    var agentStatus: String {
        if completedCount == tasks.count {
            return MediaGeneratorTaskStatus.completed.rawValue
        }
        if failedCount == tasks.count {
            return MediaGeneratorTaskStatus.failed.rawValue
        }
        if failedCount > 0, runningCount == 0 {
            return "partial"
        }
        if runningCount > 0 {
            return MediaGeneratorTaskStatus.running.rawValue
        }
        return representative.status.rawValue
    }

    var isStarred: Bool {
        tasks.contains { $0.isStarred }
    }

    var isLocallyCached: Bool {
        tasks.contains { $0.isLocallyCached }
    }

    static func sortTasks(_ lhs: MediaGeneratorTask, _ rhs: MediaGeneratorTask) -> Bool {
        if let lhsBatchID = lhs.batchID,
           lhsBatchID == rhs.batchID {
            return lhs.batchIndex < rhs.batchIndex
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.batchIndex < rhs.batchIndex
    }
}

enum MediaGeneratorError: LocalizedError {
    static let maxReferenceCount = 8
    static let maxReferenceFileBytes: Int64 = 31_457_280

    case emptyPrompt
    case unsupportedCategory(MediaGeneratorCategory)
    case missingXenodiaChannel(String)
    case invalidOption(String)
    case invalidReference(String)
    case invalidResponse(String)
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            "Enter a prompt before generating media."
        case let .unsupportedCategory(category):
            "\(category.title) generation is not available through the current Xenodia media channel."
        case let .missingXenodiaChannel(message):
            message
        case let .invalidOption(message):
            message
        case let .invalidReference(message):
            message
        case let .invalidResponse(message):
            message
        case let .requestFailed(status, body):
            "Xenodia request failed (\(status)): \(body)"
        }
    }
}

struct MediaGeneratorFileDatabase {
    private static let taskHistorySchemaVersion = MediaGeneratorTask.currentSchemaVersion

    var rootURL: URL?
    var fileManager: FileManager = .default

    func loadTasks() -> [MediaGeneratorTask] {
        do {
            let entries = try fileManager.contentsOfDirectory(
                at: try tasksRoot(),
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
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

    func loadQuickPrompts() -> [MediaGeneratorQuickPrompt] {
        do {
            let url = try gearRoot().appendingPathComponent("quick-prompts.json")
            guard fileManager.fileExists(atPath: url.path) else {
                return MediaGeneratorQuickPrompt.defaults
            }
            let decoder = JSONDecoder()
            let prompts = try decoder.decode([MediaGeneratorQuickPrompt].self, from: Data(contentsOf: url))
            return prompts.isEmpty ? MediaGeneratorQuickPrompt.defaults : prompts
        } catch {
            return MediaGeneratorQuickPrompt.defaults
        }
    }

    func saveQuickPrompts(_ prompts: [MediaGeneratorQuickPrompt]) throws {
        let url = try gearRoot().appendingPathComponent("quick-prompts.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(prompts)
        try data.write(to: url, options: .atomic)
    }

    func loadImageHistory() -> [MediaGeneratorImageHistoryItem] {
        do {
            let url = try gearRoot().appendingPathComponent("image-history.json")
            guard fileManager.fileExists(atPath: url.path) else {
                return []
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([MediaGeneratorImageHistoryItem].self, from: Data(contentsOf: url))
        } catch {
            return []
        }
    }

    func saveImageHistory(_ history: [MediaGeneratorImageHistoryItem]) throws {
        let url = try gearRoot().appendingPathComponent("image-history.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(history)
        try data.write(to: url, options: .atomic)
    }

    func saveReferenceImageData(_ data: Data, suggestedExtension: String) throws -> URL {
        let directory = try gearRoot().appendingPathComponent("reference-uploads", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent(
            "reference-\(UUID().uuidString).\(sanitizedFileExtension(suggestedExtension))"
        )
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    func save(_ task: MediaGeneratorTask) throws {
        let directory = try taskDirectory(task.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(task)
        try data.write(to: directory.appendingPathComponent("task.json"), options: .atomic)
    }

    func taskFileURL(_ id: String) throws -> URL {
        try taskDirectory(id).appendingPathComponent("task.json")
    }

    func deleteTask(id: String) throws {
        let directory = try taskDirectory(id)
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        try fileManager.removeItem(at: directory)
    }

    func saveResultData(_ data: Data, for task: MediaGeneratorTask, suggestedExtension: String) throws -> URL {
        let outputDirectory = try taskDirectory(task.id).appendingPathComponent("outputs", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("result.\(sanitizedFileExtension(suggestedExtension))")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private func loadTask(from directory: URL) -> MediaGeneratorTask? {
        let url = directory.appendingPathComponent("task.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MediaGeneratorTask.self, from: data)
    }

    private func tasksRoot() throws -> URL {
        try ensureCurrentTaskHistorySchema()
        let root = try taskRootURL()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func taskDirectory(_ id: String) throws -> URL {
        try tasksRoot().appendingPathComponent(id, isDirectory: true)
    }

    private func taskRootURL() throws -> URL {
        try gearRoot().appendingPathComponent("tasks", isDirectory: true)
    }

    private func ensureCurrentTaskHistorySchema() throws {
        let root = try gearRoot()
        let markerURL = root.appendingPathComponent("task-history-schema-version")
        let expected = "\(Self.taskHistorySchemaVersion)"
        let current = (try? String(contentsOf: markerURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tasksURL = root.appendingPathComponent("tasks", isDirectory: true)
        guard current == expected else {
            if fileManager.fileExists(atPath: tasksURL.path) {
                try fileManager.removeItem(at: tasksURL)
            }
            try fileManager.createDirectory(at: tasksURL, withIntermediateDirectories: true)
            try expected.write(to: markerURL, atomically: true, encoding: .utf8)
            return
        }
        try fileManager.createDirectory(at: tasksURL, withIntermediateDirectories: true)
    }

    private func sanitizedFileExtension(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let sanitized = value
            .lowercased()
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
        return sanitized.isEmpty ? "png" : sanitized
    }

    private func gearRoot() throws -> URL {
        if let rootURL {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            return rootURL
        }
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support.appendingPathComponent("GeeAgent/gear-data/media.generator", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

struct XenodiaMediaChannel {
    func loadBackend() async throws -> XenodiaMediaBackend {
        do {
            return try await Task.detached {
                try NativeWorkbenchRuntimeClient().loadXenodiaMediaBackend()
            }.value
        } catch {
            throw MediaGeneratorError.missingXenodiaChannel(error.localizedDescription)
        }
    }
}

struct XenodiaTaskPollResult: Sendable {
    var state: String
    var progress: Int?
    var resultURL: String?
    var error: String?

    var normalizedState: String {
        state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isSuccessful: Bool {
        ["success", "succeeded", "completed", "complete"].contains(normalizedState)
    }

    var isFailed: Bool {
        ["fail", "failed", "error", "errored"].contains(normalizedState)
    }
}

struct XenodiaImageGenerationClient {
    static let minimumLongRunningRequestTimeoutSeconds = 30 * 60

    var backend: XenodiaMediaBackend

    static func requestTimeoutInterval(for backend: XenodiaMediaBackend) -> TimeInterval {
        TimeInterval(max(backend.requestTimeoutSeconds, minimumLongRunningRequestTimeoutSeconds))
    }

    static func isRetryableStatusPollError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        return urlError.code == .timedOut
    }

    func createImageTask(
        modelID: MediaGeneratorModelID,
        prompt: String,
        imageCount: Int,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        outputFormat: MediaGeneratorOutputFormat,
        references: [MediaGeneratorReference]
    ) async throws -> String {
        let maxReferenceCount = MediaGeneratorGearStore.maxReferenceCount(for: modelID)
        let remoteURLs = references.compactMap(\.url)
        let localURLs = references.compactMap { reference -> URL? in
            guard let localPath = reference.localPath else {
                return nil
            }
            return URL(fileURLWithPath: localPath)
        }
        let body = imageRequestFields(
            modelID: modelID,
            prompt: prompt,
            imageCount: imageCount,
            aspectRatio: aspectRatio,
            resolution: resolution,
            outputFormat: outputFormat
        )

        let responseData: Data
        if localURLs.isEmpty {
            responseData = try await postJSON(fields: body, imageInputURLs: remoteURLs, maxReferenceCount: maxReferenceCount)
        } else {
            responseData = try await postMultipart(
                fields: body,
                imageInputURLs: remoteURLs,
                files: localURLs,
                maxReferenceCount: maxReferenceCount
            )
        }
        return try Self.parseCreationTaskID(responseData)
    }

    func createVideoTask(
        modelID: MediaGeneratorModelID,
        prompt: String,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        references: [MediaGeneratorReference],
        parameters: [String: String]
    ) async throws -> String {
        let fields = try videoRequestFields(
            modelID: modelID,
            prompt: prompt,
            aspectRatio: aspectRatio,
            resolution: resolution,
            references: references,
            parameters: parameters
        )
        let responseData = try await postVideoJSON(fields: fields)
        return try Self.parseCreationTaskID(responseData)
    }

    func uploadReferenceAsset(fileURL: URL) async throws -> String {
        guard let uploadURLString = backend.storageUploadURL,
              let url = URL(string: uploadURLString)
        else {
            throw MediaGeneratorError.missingXenodiaChannel(
                "Xenodia storage upload URL is not configured. Video local reference images must be uploaded before they can be used as asset:// references."
            )
        }
        let boundary = "GeeMediaAssetUpload-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeoutInterval(for: backend)
        request.setValue("Bearer \(backend.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try assetUploadBody(boundary: boundary, fileURL: fileURL)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        return try Self.parseAssetUploadReference(data)
    }

    func pollTask(taskID: String) async throws -> XenodiaTaskPollResult {
        let taskBase = backend.taskRetrievalURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(taskBase)/\(taskID)") else {
            throw MediaGeneratorError.invalidResponse("Invalid Xenodia task retrieval URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeoutInterval(for: backend)
        request.setValue("Bearer \(backend.apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        return try Self.parseTaskResponse(data)
    }

    static func parseTaskResponse(_ data: Data) throws -> XenodiaTaskPollResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaGeneratorError.invalidResponse("Xenodia task response was not a JSON object.")
        }
        let state = (object["state"] as? String) ?? "unknown"
        let progress = object["progress"] as? Int
        let resultURL = Self.firstResultURL(in: object)
        let error = (object["error"] as? [String: Any])?["message"] as? String
            ?? object["message"] as? String
        return XenodiaTaskPollResult(state: state, progress: progress, resultURL: resultURL, error: error)
    }

    static func parseAssetUploadReference(_ data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reference = firstAssetReference(in: object)
        else {
            throw MediaGeneratorError.invalidResponse("Xenodia asset upload response did not include an asset URL or ID.")
        }
        return reference
    }

    private func imageRequestFields(
        modelID: MediaGeneratorModelID,
        prompt: String,
        imageCount: Int,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        outputFormat: MediaGeneratorOutputFormat
    ) -> [String: Any] {
        var fields: [String: Any] = [
            "model": modelID.rawValue,
            "prompt": prompt,
            "n": imageCount,
            "response_format": "url"
        ]
        switch modelID {
        case .nanoBananaPro:
            fields["aspect_ratio"] = aspectRatio.rawValue
            fields["resolution"] = resolution.rawValue
            fields["output_format"] = outputFormat.rawValue
        case .gptImage2:
            fields["aspect_ratio"] = aspectRatio.rawValue
            fields["resolution"] = resolution.rawValue
        case .veo31, .veo31Fast, .veo31Lite, .seedance2, .seedance2Fast:
            break
        }
        return fields
    }

    private func videoRequestFields(
        modelID: MediaGeneratorModelID,
        prompt: String,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        references: [MediaGeneratorReference],
        parameters: [String: String]
    ) throws -> [String: Any] {
        let imageURLs = references.compactMap(\.url)
        var fields: [String: Any] = [
            "model": modelID.rawValue,
            "prompt": prompt,
            "resolution": resolution.rawValue
        ]

        if modelID.isVeo {
            let generationType = parameters["generation_type"]
                .flatMap(MediaGeneratorVideoGenerationType.init(rawValue:))
                ?? (imageURLs.isEmpty ? .textToVideo : .referenceToVideo)
            fields["generationType"] = generationType.rawValue
            fields["aspect_ratio"] = aspectRatio == .auto ? "Auto" : aspectRatio.rawValue
            if !imageURLs.isEmpty {
                fields["imageUrls"] = imageURLs
            }
            if let seed = intParameter(parameters["seed"]) {
                fields["seeds"] = seed
            }
            if let enableTranslation = boolParameter(parameters["enable_translation"]) {
                fields["enableTranslation"] = enableTranslation
            }
            if let watermark = nonEmptyParameter(parameters["watermark"]) {
                fields["watermark"] = watermark
            }
            if let callbackURL = nonEmptyParameter(parameters["callback_url"]) {
                fields["callBackUrl"] = callbackURL
            }
            return fields
        }

        if modelID.isSeedance {
            fields["aspect_ratio"] = aspectRatio.rawValue
            fields["duration"] = intParameter(parameters["duration"]) ?? 5
            if let generateAudio = boolParameter(parameters["generate_audio"]) {
                fields["generate_audio"] = generateAudio
            }
            let hasFrameMode = nonEmptyParameter(parameters["first_frame_url"]) != nil
                || nonEmptyParameter(parameters["last_frame_url"]) != nil
            if let firstFrameURL = nonEmptyParameter(parameters["first_frame_url"]) {
                fields["first_frame_url"] = firstFrameURL
            }
            if let lastFrameURL = nonEmptyParameter(parameters["last_frame_url"]) {
                fields["last_frame_url"] = lastFrameURL
            }
            let referenceImageURLs = stringArrayParameter(parameters["reference_image_urls"])
            if !hasFrameMode, !referenceImageURLs.isEmpty {
                fields["reference_image_urls"] = referenceImageURLs
            } else if !hasFrameMode, !imageURLs.isEmpty {
                fields["reference_image_urls"] = imageURLs
            }
            let referenceVideoURLs = stringArrayParameter(parameters["reference_video_urls"])
            if !referenceVideoURLs.isEmpty {
                fields["reference_video_urls"] = referenceVideoURLs
            }
            let referenceAudioURLs = stringArrayParameter(parameters["reference_audio_urls"])
            if !referenceAudioURLs.isEmpty {
                fields["reference_audio_urls"] = referenceAudioURLs
            }
            if let webSearch = boolParameter(parameters["web_search"]) {
                fields["web_search"] = webSearch
            }
            if let nsfwChecker = boolParameter(parameters["nsfw_checker"]) {
                fields["nsfw_checker"] = nsfwChecker
            }
            if let callbackURL = nonEmptyParameter(parameters["callback_url"]) {
                fields["callBackUrl"] = callbackURL
            }
            return fields
        }

        throw MediaGeneratorError.unsupportedCategory(.video)
    }

    private func postJSON(fields: [String: Any], imageInputURLs: [String], maxReferenceCount: Int) async throws -> Data {
        guard let url = URL(string: backend.imageGenerationsURL) else {
            throw MediaGeneratorError.invalidResponse("Invalid Xenodia image generation URL.")
        }
        var body: [String: Any] = fields
        let cappedImageInputURLs = Array(imageInputURLs.prefix(maxReferenceCount))
        if !cappedImageInputURLs.isEmpty {
            body["image_input"] = cappedImageInputURLs
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeoutInterval(for: backend)
        request.setValue("Bearer \(backend.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        return data
    }

    private func postVideoJSON(fields: [String: Any]) async throws -> Data {
        guard let url = URL(string: backend.videoGenerationsURL) else {
            throw MediaGeneratorError.invalidResponse("Invalid Xenodia video generation URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeoutInterval(for: backend)
        request.setValue("Bearer \(backend.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        return data
    }

    private func postMultipart(
        fields: [String: Any],
        imageInputURLs: [String],
        files: [URL],
        maxReferenceCount: Int
    ) async throws -> Data {
        guard let url = URL(string: backend.imageGenerationsURL) else {
            throw MediaGeneratorError.invalidResponse("Invalid Xenodia image generation URL.")
        }
        let boundary = "GeeMediaGenerator-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeoutInterval(for: backend)
        request.setValue("Bearer \(backend.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let cappedImageInputURLs = Array(imageInputURLs.prefix(maxReferenceCount))
        request.httpBody = try multipartBody(
            boundary: boundary,
            fields: fields,
            imageInputURLs: cappedImageInputURLs,
            files: files,
            maxReferenceCount: maxReferenceCount
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        return data
    }

    private func multipartBody(
        boundary: String,
        fields: [String: Any],
        imageInputURLs: [String],
        files: [URL],
        maxReferenceCount: Int
    ) throws -> Data {
        var data = Data()
        for (key, value) in fields {
            data.appendString("--\(boundary)\r\n")
            data.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            data.appendString("\(value)\r\n")
        }
        for url in imageInputURLs {
            data.appendString("--\(boundary)\r\n")
            data.appendString("Content-Disposition: form-data; name=\"image_input[]\"\r\n\r\n")
            data.appendString("\(url)\r\n")
        }
        for fileURL in files.prefix(max(0, maxReferenceCount - imageInputURLs.count)) {
            let fileData = try Data(contentsOf: fileURL)
            data.appendString("--\(boundary)\r\n")
            data.appendString(
                "Content-Disposition: form-data; name=\"image[]\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
            )
            data.appendString("Content-Type: \(mimeType(for: fileURL))\r\n\r\n")
            data.append(fileData)
            data.appendString("\r\n")
        }
        data.appendString("--\(boundary)--\r\n")
        return data
    }

    private func assetUploadBody(boundary: String, fileURL: URL) throws -> Data {
        var data = Data()
        let fileData = try Data(contentsOf: fileURL)
        data.appendString("--\(boundary)\r\n")
        data.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        data.appendString("Content-Type: \(mimeType(for: fileURL))\r\n\r\n")
        data.append(fileData)
        data.appendString("\r\n")
        data.appendString("--\(boundary)--\r\n")
        return data
    }

    static func parseCreationTaskID(_ data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaGeneratorError.invalidResponse("Xenodia creation response was not a JSON object.")
        }
        let providerTaskID = object["task_id"] as? String
            ?? object["taskId"] as? String
            ?? ((object["data"] as? [String: Any])?["task_id"] as? String)
            ?? ((object["data"] as? [String: Any])?["taskId"] as? String)
        guard let providerTaskID,
              !providerTaskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw MediaGeneratorError.invalidResponse("Xenodia creation response did not include a task_id.")
        }
        return providerTaskID
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
            throw MediaGeneratorError.requestFailed(http.statusCode, body)
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        default: "image/png"
        }
    }

    private func nonEmptyParameter(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func boolParameter(_ value: String?) -> Bool? {
        guard let value else {
            return nil
        }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private func intParameter(_ value: String?) -> Int? {
        guard let value else {
            return nil
        }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func stringArrayParameter(_ value: String?) -> [String] {
        guard let value,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private static func firstResultURL(in object: [String: Any]) -> String? {
        if let url = object["url"] as? String {
            return url
        }
        if let imageURL = object["image_url"] as? String {
            return imageURL
        }
        if let output = object["output"] as? String {
            return output
        }
        if let outputs = object["outputs"] as? [String] {
            return outputs.first
        }
        if let data = object["data"] as? [[String: Any]] {
            return data.compactMap { Self.firstResultURL(in: $0) }.first
        }
        if let result = object["result"] as? [String: Any],
           let resultURL = Self.firstResultURL(in: result) {
            return resultURL
        }
        if let nested = object["data"] as? [String: Any],
           let resultURL = Self.firstResultURL(in: nested) {
            return resultURL
        }
        return nil
    }

    private static func firstAssetReference(in object: [String: Any]) -> String? {
        for key in ["asset_url", "assetUrl", "asset_uri", "assetUri", "url", "uri"] {
            if let reference = normalizeAssetReference(object[key]) {
                return reference
            }
        }
        for key in ["asset_id", "assetId", "id", "file_id", "fileId"] {
            if let reference = normalizeAssetReference(object[key], defaultAssetScheme: true) {
                return reference
            }
        }
        for key in ["data", "result", "asset", "file"] {
            if let nested = object[key] as? [String: Any],
               let reference = firstAssetReference(in: nested) {
                return reference
            }
            if let array = object[key] as? [[String: Any]] {
                return array.compactMap(firstAssetReference).first
            }
        }
        return nil
    }

    private static func normalizeAssetReference(_ value: Any?, defaultAssetScheme: Bool = false) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let url = URL(string: trimmed), url.scheme != nil {
            return trimmed
        }
        return defaultAssetScheme ? "asset://\(trimmed)" : nil
    }
}

@MainActor
final class MediaGeneratorGearStore: ObservableObject {
    static let shared = MediaGeneratorGearStore()

    @Published var category: MediaGeneratorCategory = .image
    @Published var selectedModel: MediaGeneratorModelID = .nanoBananaPro
    @Published var prompt = ""
    @Published var aspectRatio: MediaGeneratorAspectRatio = .square
    @Published var resolution: MediaGeneratorResolution = .oneK
    @Published var outputFormat: MediaGeneratorOutputFormat = .png
    @Published var imageCount = 1
    @Published var videoGenerationType: MediaGeneratorVideoGenerationType = .textToVideo
    @Published var videoDuration = 5
    @Published var generateAudio = false
    @Published var webSearch = false
    @Published var nsfwChecker = false
    @Published var references: [MediaGeneratorReference] = []
    @Published var taskFilter: MediaGeneratorTaskFilter = .all
    @Published var modelFilter: MediaGeneratorModelID?
    @Published var searchQuery = ""
    @Published var quickPrompts: [MediaGeneratorQuickPrompt] = MediaGeneratorQuickPrompt.defaults
    @Published private(set) var imageHistory: [MediaGeneratorImageHistoryItem] = []
    @Published private(set) var tasks: [MediaGeneratorTask] = []
    @Published var selectedTaskID: MediaGeneratorTask.ID?
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var activeCreationCount = 0

    private let database: MediaGeneratorFileDatabase
    private let channel: XenodiaMediaChannel
    private var pollingTaskIDs: Set<MediaGeneratorTask.ID> = []

    var isBusy: Bool {
        activeCreationCount > 0
    }

    var selectedTask: MediaGeneratorTask? {
        tasks.first { $0.id == selectedTaskID } ?? tasks.first
    }

    var selectedModelReferenceLimit: Int {
        Self.maxReferenceCount(for: selectedModel)
    }

    var taskGroups: [MediaGeneratorTaskGroup] {
        Self.groupedTasks(tasks)
    }

    var visibleTasks: [MediaGeneratorTask] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks.filter { task in
            if let modelFilter, task.modelID != modelFilter {
                return false
            }
            switch taskFilter {
            case .all:
                break
            case .completed:
                guard task.status == .completed else { return false }
            case .running:
                guard task.status == .running || task.status == .queued else { return false }
            case .failed:
                guard task.status == .failed else { return false }
            case .starred:
                guard task.isStarred else { return false }
            }
            guard !query.isEmpty else {
                return true
            }
            let haystack = [
                task.prompt,
                task.modelID.title,
                task.status.title,
                task.resultURL ?? "",
                task.errorMessage ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            return haystack.contains(query)
        }
    }

    var visibleTaskGroups: [MediaGeneratorTaskGroup] {
        Self.groupedTasks(visibleTasks)
    }

    init(
        database: MediaGeneratorFileDatabase = MediaGeneratorFileDatabase(),
        channel: XenodiaMediaChannel = XenodiaMediaChannel()
    ) {
        self.database = database
        self.channel = channel
        quickPrompts = database.loadQuickPrompts()
        imageHistory = database.loadImageHistory()
        loadTasks()
    }

    func loadTasks() {
        tasks = database.loadTasks()
        selectedTaskID = selectedTaskID ?? taskGroups.first?.representative.id
        resumePollingForRunningTasks()
    }

    func selectCategory(_ category: MediaGeneratorCategory) {
        self.category = category
        if category != .audio, selectedModel.category != category {
            selectedModel = Self.defaultModel(for: category)
        }
        normalizeSelectionForCurrentModel()
    }

    func selectModel(_ model: MediaGeneratorModelID) {
        selectedModel = model
        category = model.category
        normalizeSelectionForCurrentModel()
    }

    func addReferenceFiles() {
        guard category == .image || category == .video else {
            statusMessage = "\(category.title) references are not available."
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.supportedReferenceContentTypes
        if panel.runModal() == .OK {
            for url in panel.urls {
                guard references.count < selectedModelReferenceLimit else {
                    break
                }
                addReferenceFileURL(url)
            }
        }
    }

    func addClipboardReferenceImage(from pasteboard: NSPasteboard = .general) {
        guard category == .image || category == .video else {
            statusMessage = "\(category.title) references are not available."
            return
        }
        if let urls = Self.pasteboardReferenceFileURLs(pasteboard), !urls.isEmpty {
            for url in urls {
                guard references.count < selectedModelReferenceLimit else {
                    statusMessage = "\(selectedModel.title) references are limited to \(selectedModelReferenceLimit)."
                    return
                }
                addReferenceFileURL(url)
            }
            return
        }
        guard let imageData = Self.referenceImageData(from: pasteboard) else {
            statusMessage = "Clipboard does not contain a reusable image."
            return
        }
        addReferenceImageData(imageData.data, suggestedExtension: imageData.fileExtension)
    }

    func addReferenceImageData(_ data: Data, suggestedExtension: String = "png") {
        guard references.count < selectedModelReferenceLimit else {
            statusMessage = "\(selectedModel.title) references are limited to \(selectedModelReferenceLimit)."
            return
        }
        do {
            let fileURL = try database.saveReferenceImageData(data, suggestedExtension: suggestedExtension)
            addReferenceFileURL(fileURL)
            statusMessage = "Added clipboard image as a reference."
        } catch {
            statusMessage = "Clipboard image import failed: \(error.localizedDescription)"
        }
    }

    nonisolated static func pasteboardHasReferenceImage(_ pasteboard: NSPasteboard = .general) -> Bool {
        if let urls = Self.pasteboardReferenceFileURLs(pasteboard), !urls.isEmpty {
            return true
        }
        return referenceImageData(from: pasteboard) != nil
    }

    nonisolated private static func pasteboardReferenceFileURLs(_ pasteboard: NSPasteboard) -> [URL]? {
        guard let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) else {
            return nil
        }
        let urls = objects.compactMap { object -> URL? in
            if let url = object as? URL {
                return url
            }
            if let nsURL = object as? NSURL {
                return nsURL as URL
            }
            return nil
        }
        .filter { url in
            guard url.isFileURL else {
                return false
            }
            let values = try? url.resourceValues(forKeys: [.contentTypeKey])
            guard let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) else {
                return false
            }
            return supportedReferenceContentTypes.contains { type.conforms(to: $0) }
        }
        return urls.isEmpty ? nil : urls
    }

    nonisolated private static func referenceImageData(from pasteboard: NSPasteboard) -> (data: Data, fileExtension: String)? {
        if let png = pasteboard.data(forType: .png) {
            return (png, "png")
        }
        if let image = NSImage(pasteboard: pasteboard),
           let png = pngData(from: image) {
            return (png, "png")
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        return nil
    }

    nonisolated private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    func addReferenceFileURL(_ url: URL) {
        guard references.count < selectedModelReferenceLimit else {
            statusMessage = "\(selectedModel.title) references are limited to \(selectedModelReferenceLimit)."
            return
        }
        do {
            try Self.validateLocalReferenceFile(url)
            let reference = MediaGeneratorReference(
                id: UUID().uuidString,
                url: nil,
                localPath: url.path,
                displayName: url.lastPathComponent
            )
            references.append(reference)
            addImageHistoryReference(reference)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addReferenceURL(_ url: String, recordHistory: Bool = true) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard references.count < selectedModelReferenceLimit else {
            statusMessage = "\(selectedModel.title) references are limited to \(selectedModelReferenceLimit)."
            return
        }
        guard let parsed = URL(string: trimmed),
              (category == .video
                  ? (parsed.scheme?.hasPrefix("http") == true || parsed.scheme == "asset")
                  : parsed.scheme?.hasPrefix("http") == true)
        else {
            statusMessage = category == .video
                ? "Paste a valid public media URL or Xenodia asset:// reference."
                : "Paste a valid image URL. \(selectedModel.title) references are limited to \(selectedModelReferenceLimit)."
            return
        }
        let reference = MediaGeneratorReference(
            id: UUID().uuidString,
            url: trimmed,
            localPath: nil,
            displayName: parsed.lastPathComponent.isEmpty ? parsed.host ?? "Reference URL" : parsed.lastPathComponent
        )
        references.append(reference)
        if recordHistory, category != .audio {
            addImageHistoryReference(reference)
        }
    }

    func removeReference(_ reference: MediaGeneratorReference) {
        references.removeAll { $0.id == reference.id }
    }

    func applyImageHistory(_ item: MediaGeneratorImageHistoryItem) {
        if let url = item.url {
            addReferenceURL(url)
            return
        }
        if let localPath = item.localPath {
            addReferenceFileURL(URL(fileURLWithPath: localPath))
            return
        }
        statusMessage = "History item is missing a reusable reference."
    }

    func removeImageHistory(_ item: MediaGeneratorImageHistoryItem) {
        imageHistory.removeAll { $0.historyKey == item.historyKey }
        persistImageHistory()
    }

    func useResultAsReference(_ task: MediaGeneratorTask) {
        guard task.category == .image else {
            statusMessage = "Only generated images can be reused as image references."
            return
        }
        guard let resultURL = task.resultURL else {
            statusMessage = "No result URL to use as a reference."
            return
        }
        addReferenceURL(resultURL, recordHistory: false)
        statusMessage = "Added generated image as a reference."
    }

    func applyTaskParameters(_ task: MediaGeneratorTask) {
        category = task.category
        selectedModel = task.modelID
        prompt = task.prompt
        references = Array(task.references.prefix(Self.maxReferenceCount(for: task.modelID)))
        aspectRatio = task.parameters["aspect_ratio"].flatMap(MediaGeneratorAspectRatio.init(rawValue:))
            ?? Self.defaultAspectRatio(for: task.modelID)
        resolution = task.parameters["resolution"].flatMap(MediaGeneratorResolution.init(rawValue:))
            ?? Self.defaultResolution(for: task.modelID, aspectRatio: aspectRatio)
        outputFormat = task.parameters["output_format"].flatMap(MediaGeneratorOutputFormat.init(rawValue:)) ?? .png
        imageCount = task.batchCount
        videoGenerationType = task.parameters["generation_type"].flatMap(MediaGeneratorVideoGenerationType.init(rawValue:)) ?? .textToVideo
        videoDuration = task.parameters["duration"].flatMap(Int.init) ?? 5
        generateAudio = Bool(task.parameters["generate_audio"] ?? "false") ?? false
        webSearch = Bool(task.parameters["web_search"] ?? "false") ?? false
        nsfwChecker = Bool(task.parameters["nsfw_checker"] ?? "false") ?? false
        normalizeSelectionForCurrentModel()
        selectedTaskID = task.id
        statusMessage = "Applied task prompt and parameters."
    }

    func addQuickPrompt(name: String, content: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !normalizedContent.isEmpty else {
            statusMessage = "Quick prompt name and content are required."
            return
        }
        quickPrompts.append(
            MediaGeneratorQuickPrompt(
                id: "quick-prompt-\(UUID().uuidString)",
                name: normalizedName,
                content: normalizedContent
            )
        )
        persistQuickPrompts()
        statusMessage = "Saved quick prompt."
    }

    func updateQuickPrompt(_ prompt: MediaGeneratorQuickPrompt, name: String, content: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = quickPrompts.firstIndex(where: { $0.id == prompt.id }),
              !normalizedName.isEmpty,
              !normalizedContent.isEmpty
        else {
            statusMessage = "Quick prompt name and content are required."
            return
        }
        quickPrompts[index].name = normalizedName
        quickPrompts[index].content = normalizedContent
        persistQuickPrompts()
        statusMessage = "Updated quick prompt."
    }

    func deleteQuickPrompt(_ prompt: MediaGeneratorQuickPrompt) {
        quickPrompts.removeAll { $0.id == prompt.id }
        if quickPrompts.isEmpty {
            quickPrompts = MediaGeneratorQuickPrompt.defaults
        }
        persistQuickPrompts()
        statusMessage = "Deleted quick prompt."
    }

    func resetQuickPrompts() {
        quickPrompts = MediaGeneratorQuickPrompt.defaults
        persistQuickPrompts()
        statusMessage = "Reset quick prompts."
    }

    func toggleStar(_ task: MediaGeneratorTask) {
        guard var updated = tasks.first(where: { $0.id == task.id }) else {
            return
        }
        updated.isStarred.toggle()
        updated.updatedAt = Date()
        update(updated)
        statusMessage = updated.isStarred ? "Added to starred results." : "Removed from starred results."
    }

    func toggleStar(_ group: MediaGeneratorTaskGroup) {
        let shouldStar = !group.tasks.allSatisfy(\.isStarred)
        for task in group.tasks {
            guard var updated = tasks.first(where: { $0.id == task.id }) else {
                continue
            }
            updated.isStarred = shouldStar
            updated.updatedAt = Date()
            update(updated)
        }
        statusMessage = shouldStar ? "Added batch to starred results." : "Removed batch from starred results."
    }

    func delete(_ task: MediaGeneratorTask) {
        do {
            try database.deleteTask(id: task.id)
            tasks.removeAll { $0.id == task.id }
            if selectedTaskID == task.id {
                selectedTaskID = tasks.first?.id
            }
            statusMessage = "Deleted generation task."
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func delete(_ group: MediaGeneratorTaskGroup) {
        do {
            for task in group.tasks {
                try database.deleteTask(id: task.id)
            }
            let ids = Set(group.tasks.map(\.id))
            tasks.removeAll { ids.contains($0.id) }
            if let currentSelection = selectedTaskID, ids.contains(currentSelection) {
                selectedTaskID = taskGroups.first?.representative.id
            }
            statusMessage = group.isBatch ? "Deleted generation batch." : "Deleted generation task."
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func copyResultURL(_ task: MediaGeneratorTask) {
        guard let resultURL = task.resultURL else {
            statusMessage = "No result URL to copy."
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resultURL, forType: .string)
        statusMessage = "Copied result URL."
    }

    func revealResultInFinder(_ task: MediaGeneratorTask) {
        guard let resultURL = task.resultDisplayURL, resultURL.isFileURL else {
            statusMessage = "No local cached result to reveal yet."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([resultURL])
        statusMessage = "Revealed local result in Finder."
    }

    func downloadResult(_ task: MediaGeneratorTask) {
        guard task.resultDisplayURL != nil else {
            statusMessage = "No generated result to download."
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(task.id).\(task.resultFileExtension)"
        panel.allowedContentTypes = Self.downloadContentTypes(for: task)
        if panel.runModal() != .OK {
            return
        }
        guard let destinationURL = panel.url else {
            return
        }
        Task { [weak self] in
            await self?.download(task: task, to: destinationURL)
        }
    }

    func generateCurrentPrompt() {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { [weak self] in
            await self?.createTasks(
                category: self?.category ?? .image,
                modelID: self?.selectedModel ?? .nanoBananaPro,
                prompt: prompt,
                batchCount: self?.imageCount ?? 1,
                aspectRatio: self?.aspectRatio ?? .square,
                resolution: self?.resolution ?? .oneK,
                outputFormat: self?.outputFormat ?? .png,
                references: self?.references ?? [],
                videoOptions: self?.currentVideoOptions() ?? .default
            )
        }
    }

    private func currentVideoOptions() -> MediaGeneratorVideoOptions {
        MediaGeneratorVideoOptions(
            generationType: videoGenerationType,
            duration: min(max(videoDuration, 4), 15),
            generateAudio: generateAudio,
            webSearch: webSearch,
            nsfwChecker: nsfwChecker,
            seed: nil,
            enableTranslation: true,
            watermark: nil,
            firstFrameURL: videoGenerationType == .firstAndLastFrames ? references.first?.url : nil,
            lastFrameURL: videoGenerationType == .firstAndLastFrames ? references.dropFirst().first?.url : nil,
            referenceVideoURLs: [],
            referenceAudioURLs: [],
            callbackURL: nil
        )
    }

    private func download(task: MediaGeneratorTask, to destinationURL: URL) async {
        guard let sourceURL = task.resultDisplayURL else {
            statusMessage = "No generated result to download."
            return
        }
        do {
            if sourceURL.isFileURL {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            } else {
                let (data, response) = try await URLSession.shared.data(from: sourceURL)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    throw MediaGeneratorError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "<non-utf8 response>")
                }
                try data.write(to: destinationURL, options: .atomic)
            }
            statusMessage = "Downloaded \(task.category.rawValue) to \(destinationURL.lastPathComponent)."
        } catch {
            statusMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    func createAgentTask(args: [String: Any]) async -> [String: Any] {
        let prompt = (args["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requestedModel = Self.modelIDArg(args["model"])
        let category = Self.categoryArg(args["category"])
            ?? requestedModel?.category
            ?? .image
        guard category != .audio else {
            statusMessage = MediaGeneratorError.unsupportedCategory(category).localizedDescription
            return [
                "gear_id": MediaGeneratorGearDescriptor.gearID,
                "capability_id": "media_generator.create_task",
                "status": "failed",
                "error": statusMessage
            ]
        }
        let model = requestedModel ?? Self.defaultModel(for: category)
        let aspectRatio = Self.aspectRatioArg(args["aspect_ratio"])
            ?? Self.defaultAspectRatio(for: model)
        let resolution = Self.normalizedResolution(
            Self.resolutionArg(args["resolution"]),
            for: model
        ) ?? Self.defaultResolution(for: model, aspectRatio: aspectRatio)
        let outputFormat = Self.outputFormatArg(args["output_format"]) ?? .png
        let videoOptions = Self.videoOptionsArg(args)
        let providerImageCount: Int
        let batchCount: Int
        do {
            try Self.validateUnsupportedModelArgs(modelID: model, args: args)
            try Self.validateResponseFormat(args["response_format"])
            providerImageCount = try Self.imageCountArg(args["n"])
            batchCount = try Self.batchCountArg(args["batch_count"])
            try Self.validateBatchCount(batchCount, category: category)
        } catch {
            statusMessage = error.localizedDescription
            return [
                "gear_id": MediaGeneratorGearDescriptor.gearID,
                "capability_id": "media_generator.create_task",
                "status": "failed",
                "error": statusMessage
            ]
        }
        let urls = Self.videoFrameURLs(from: videoOptions)
            + Self.stringArrayArg(args["reference_urls"])
            + Self.stringArrayArg(args["image_urls"])
            + Self.stringArrayArg(args["imageUrls"])
            + Self.stringArrayArg(args["reference_image_urls"])
        let paths = Self.stringArrayArg(args["reference_paths"])
        let refs = urls.map {
            MediaGeneratorReference(id: UUID().uuidString, url: $0, localPath: nil, displayName: URL(string: $0)?.lastPathComponent ?? "Reference URL")
        } + paths.map {
            MediaGeneratorReference(id: UUID().uuidString, url: nil, localPath: $0, displayName: URL(fileURLWithPath: $0).lastPathComponent)
        }
        guard providerImageCount == 1 else {
            statusMessage = "Xenodia image generation currently supports only n=1."
            return [
                "gear_id": MediaGeneratorGearDescriptor.gearID,
                "capability_id": "media_generator.create_task",
                "status": "failed",
                "error": statusMessage
            ]
        }
        guard let group = await createTasks(
            category: category,
            modelID: model,
            prompt: prompt,
            batchCount: batchCount,
            aspectRatio: aspectRatio,
            resolution: resolution,
            outputFormat: outputFormat,
            references: refs,
            videoOptions: videoOptions
        ) else {
            return [
                "gear_id": MediaGeneratorGearDescriptor.gearID,
                "capability_id": "media_generator.create_task",
                "status": "failed",
                "error": statusMessage
            ]
        }
        return groupPayload(group, capabilityID: "media_generator.create_task")
    }

    func taskPayload(taskID: String?, batchID: String? = nil) -> [String: Any] {
        if let batchID,
           let group = taskGroups.first(where: { $0.id == batchID || $0.batchID == batchID }) {
            return groupPayload(group, capabilityID: "media_generator.get_task")
        }
        if let taskID,
           let group = taskGroups.first(where: { $0.id == taskID || $0.batchID == taskID }),
           group.isBatch {
            return groupPayload(group, capabilityID: "media_generator.get_task")
        }
        let task = taskID.flatMap { id in tasks.first { $0.id == id } } ?? selectedTask
        guard let task else {
            return [
                "gear_id": MediaGeneratorGearDescriptor.gearID,
                "capability_id": "media_generator.get_task",
                "status": "not_found"
            ]
        }
        var payload = task.agentDictionary
        payload["capability_id"] = "media_generator.get_task"
        if let path = try? database.taskFileURL(task.id).path {
            payload["task_path"] = path
        }
        return payload
    }

    func modelPayload() -> [String: Any] {
        [
            "gear_id": MediaGeneratorGearDescriptor.gearID,
            "capability_id": "media_generator.list_models",
            "status": "ok",
            "channel": "xenodia",
            "models": MediaGeneratorModelID.allCases.map { model in
                [
                    "model": model.rawValue,
                    "title": model.title,
                    "category": model.category.rawValue,
                    "description": model.subtitle,
                    "default_parameters": Self.defaultParameterPayload(for: model),
                    "supported_fields": Self.supportedFields(for: model),
                    "supported_values": Self.supportedValuesPayload(for: model),
                    "max_total_references": Self.maxReferenceCount(for: model)
                ]
            },
            "constraints": [
                "n": ["minimum": 1, "maximum": 1, "default": 1],
                "batch_count": ["minimum": 1, "maximum": 4, "default": 1],
                "response_format": ["enum": ["url"], "default": "url"],
                "max_total_references_by_model": [
                    MediaGeneratorModelID.nanoBananaPro.rawValue: Self.maxReferenceCount(for: .nanoBananaPro),
                    MediaGeneratorModelID.gptImage2.rawValue: Self.maxReferenceCount(for: .gptImage2),
                    MediaGeneratorModelID.veo31.rawValue: Self.maxReferenceCount(for: .veo31),
                    MediaGeneratorModelID.veo31Fast.rawValue: Self.maxReferenceCount(for: .veo31Fast),
                    MediaGeneratorModelID.veo31Lite.rawValue: Self.maxReferenceCount(for: .veo31Lite),
                    MediaGeneratorModelID.seedance2.rawValue: Self.maxReferenceCount(for: .seedance2),
                    MediaGeneratorModelID.seedance2Fast.rawValue: Self.maxReferenceCount(for: .seedance2Fast)
                ],
                "max_reference_file_bytes": MediaGeneratorError.maxReferenceFileBytes,
                "accepted_mime_types": ["image/jpeg", "image/png", "image/webp"],
                "video_reference_url_schemes": ["http", "https", "asset"],
                "video_local_reference_upload": "requires configured Xenodia storage_upload_url"
            ],
            "placeholders": [
                "audio": "Reserved for future Xenodia audio generation endpoints."
            ]
        ]
    }

    private func groupPayload(_ group: MediaGeneratorTaskGroup, capabilityID: String) -> [String: Any] {
        if !group.isBatch {
            var payload = group.representative.agentDictionary
            payload["capability_id"] = capabilityID
            if let path = try? database.taskFileURL(group.representative.id).path {
                payload["task_path"] = path
            }
            return payload
        }

        let taskPayloads = group.tasks.sorted(by: MediaGeneratorTaskGroup.sortTasks).map { task in
            var payload = task.agentDictionary
            if let path = try? database.taskFileURL(task.id).path {
                payload["task_path"] = path
            }
            return payload
        }
        return [
            "gear_id": MediaGeneratorGearDescriptor.gearID,
            "capability_id": capabilityID,
            "status": group.agentStatus,
            "category": group.representative.category.rawValue,
            "model": group.representative.modelID.rawValue,
            "prompt": group.representative.prompt,
            "batch_id": group.id,
            "batch_count": group.batchCount,
            "completed_count": group.completedCount,
            "failed_count": group.failedCount,
            "running_count": group.runningCount,
            "tasks": taskPayloads
        ]
    }

    @discardableResult
    private func createTasks(
        category: MediaGeneratorCategory,
        modelID: MediaGeneratorModelID,
        prompt: String,
        batchCount: Int,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        outputFormat: MediaGeneratorOutputFormat,
        references: [MediaGeneratorReference],
        videoOptions: MediaGeneratorVideoOptions = .default
    ) async -> MediaGeneratorTaskGroup? {
        do {
            try Self.validateBatchCount(batchCount, category: category)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
        let normalizedBatchCount = max(1, min(batchCount, 4))
        let batchID = normalizedBatchCount > 1
            ? "media-generator-batch-\(Self.timestamp())-\(UUID().uuidString.prefix(8))"
            : nil
        var enqueuedTasks: [MediaGeneratorTask] = []
        for index in 1...normalizedBatchCount {
            guard let task = enqueueTask(
                category: category,
                modelID: modelID,
                prompt: prompt,
                providerImageCount: 1,
                aspectRatio: aspectRatio,
                resolution: resolution,
                outputFormat: outputFormat,
                references: references,
                videoOptions: videoOptions,
                batchID: batchID,
                batchIndex: index,
                batchCount: normalizedBatchCount
            ) else {
                if enqueuedTasks.isEmpty {
                    return nil
                }
                break
            }
            enqueuedTasks.append(task)
        }
        guard !enqueuedTasks.isEmpty else {
            return nil
        }
        let id = batchID ?? enqueuedTasks[0].id
        statusMessage = normalizedBatchCount > 1
            ? "Queued \(normalizedBatchCount) Xenodia generation tasks."
            : "Queued Xenodia generation task."

        let creationTasks = enqueuedTasks.map { task in
            Task { [weak self] in
                await self?.startProviderCreation(taskID: task.id)
            }
        }
        for creationTask in creationTasks {
            _ = await creationTask.value
        }

        let refreshedTasks = enqueuedTasks.compactMap { enqueuedTask in
            tasks.first { $0.id == enqueuedTask.id }
        }
        return MediaGeneratorTaskGroup(
            id: id,
            batchID: batchID,
            tasks: refreshedTasks.isEmpty ? enqueuedTasks : refreshedTasks
        )
    }

    @discardableResult
    private func enqueueTask(
        category: MediaGeneratorCategory,
        modelID: MediaGeneratorModelID,
        prompt: String,
        providerImageCount: Int,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        outputFormat: MediaGeneratorOutputFormat,
        references: [MediaGeneratorReference],
        videoOptions: MediaGeneratorVideoOptions = .default,
        batchID: String? = nil,
        batchIndex: Int = 1,
        batchCount: Int = 1
    ) -> MediaGeneratorTask? {
        guard !prompt.isEmpty else {
            statusMessage = MediaGeneratorError.emptyPrompt.localizedDescription
            return nil
        }
        guard category == modelID.category else {
            statusMessage = "\(modelID.title) is a \(modelID.category.rawValue) model, not \(category.rawValue)."
            return nil
        }
        guard category == .image || category == .video else {
            statusMessage = MediaGeneratorError.unsupportedCategory(category).localizedDescription
            return nil
        }
        do {
            try Self.validateImageCount(providerImageCount)
            try Self.validateModelParameters(modelID: modelID, aspectRatio: aspectRatio, resolution: resolution)
            try Self.validateReferences(modelID: modelID, references, videoOptions: videoOptions)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }

        let now = Date()
        let task = MediaGeneratorTask(
            id: "media-generator-\(Self.timestamp())-\(UUID().uuidString.prefix(8))",
            category: category,
            modelID: modelID,
            prompt: prompt,
            status: .running,
            createdAt: now,
            updatedAt: now,
            providerTaskID: nil,
            resultURL: nil,
            localOutputPath: nil,
            errorMessage: nil,
            parameters: currentParameterSnapshot(
                modelID: modelID,
                imageCount: providerImageCount,
                batchCount: batchCount,
                aspectRatio: aspectRatio,
                resolution: resolution,
                outputFormat: outputFormat,
                videoOptions: videoOptions
            ),
            references: Array(references.prefix(Self.maxReferenceCount(for: modelID))),
            batchID: batchID,
            batchIndex: batchIndex,
            batchCount: batchCount
        )
        tasks.insert(task, at: 0)
        selectedTaskID = task.id
        persist(task)
        return task
    }

    @discardableResult
    private func startProviderCreation(taskID: MediaGeneratorTask.ID) async -> MediaGeneratorTask? {
        guard let enqueuedTask = tasks.first(where: { $0.id == taskID }) else {
            return nil
        }
        activeCreationCount += 1
        statusMessage = enqueuedTask.batchCount > 1
            ? "Creating Xenodia generation task \(enqueuedTask.batchIndex) of \(enqueuedTask.batchCount)..."
            : "Creating Xenodia generation task..."
        defer { activeCreationCount = max(0, activeCreationCount - 1) }

        do {
            let backend = try await channel.loadBackend()
            let client = XenodiaImageGenerationClient(backend: backend)
            var providerTask = enqueuedTask
            if providerTask.category == .video {
                providerTask = try await resolveVideoLocalReferences(for: providerTask, client: client)
            }
            let aspectRatio = providerTask.parameters["aspect_ratio"].flatMap(MediaGeneratorAspectRatio.init(rawValue:))
                ?? Self.defaultAspectRatio(for: providerTask.modelID)
            let resolution = providerTask.parameters["resolution"].flatMap(MediaGeneratorResolution.init(rawValue:))
                ?? Self.defaultResolution(for: providerTask.modelID, aspectRatio: aspectRatio)
            let providerTaskID: String
            switch providerTask.category {
            case .image:
                providerTaskID = try await client.createImageTask(
                    modelID: providerTask.modelID,
                    prompt: providerTask.prompt,
                    imageCount: Int(providerTask.parameters["n"] ?? "1") ?? 1,
                    aspectRatio: aspectRatio,
                    resolution: resolution,
                    outputFormat: providerTask.parameters["output_format"].flatMap(MediaGeneratorOutputFormat.init(rawValue:)) ?? .png,
                    references: providerTask.references
                )
            case .video:
                providerTaskID = try await client.createVideoTask(
                    modelID: providerTask.modelID,
                    prompt: providerTask.prompt,
                    aspectRatio: aspectRatio,
                    resolution: resolution,
                    references: providerTask.references,
                    parameters: providerTask.parameters
                )
            case .audio:
                throw MediaGeneratorError.unsupportedCategory(.audio)
            }
            guard var task = tasks.first(where: { $0.id == taskID }) else {
                return nil
            }
            task.providerTaskID = providerTaskID
            task.resultURL = nil
            task.status = .running
            task.updatedAt = Date()
            guard tasks.contains(where: { $0.id == taskID }) else {
                return nil
            }
            update(task)
            statusMessage = "Task created. Polling Xenodia..."
            Task { [weak self] in
                await self?.poll(taskID: task.id, providerTaskID: providerTaskID)
            }
            return task
        } catch {
            guard var task = tasks.first(where: { $0.id == taskID }) else {
                return nil
            }
            task.status = .failed
            task.errorMessage = error.localizedDescription
            task.updatedAt = Date()
            update(task)
            statusMessage = error.localizedDescription
            return task
        }
    }

    private func resolveVideoLocalReferences(
        for task: MediaGeneratorTask,
        client: XenodiaImageGenerationClient
    ) async throws -> MediaGeneratorTask {
        guard task.category == .video,
              task.references.contains(where: { $0.localPath != nil })
        else {
            return task
        }

        var resolvedReferences: [MediaGeneratorReference] = []
        for reference in task.references {
            guard let localPath = reference.localPath else {
                resolvedReferences.append(reference)
                continue
            }
            let fileURL = URL(fileURLWithPath: localPath)
            try Self.validateLocalReferenceFile(fileURL)
            statusMessage = "Uploading reference image for video..."
            let assetReference = try await client.uploadReferenceAsset(fileURL: fileURL)
            var resolved = reference
            resolved.url = assetReference
            resolved.localPath = nil
            resolvedReferences.append(resolved)
            addImageHistoryReference(resolved)
        }

        var updated = task
        updated.references = resolvedReferences
        updated.parameters = Self.videoParametersAfterResolvingReferences(
            updated.parameters,
            references: resolvedReferences
        )
        updated.updatedAt = Date()
        update(updated)
        return updated
    }

    private func poll(taskID: String, providerTaskID: String) async {
        guard !pollingTaskIDs.contains(taskID) else {
            return
        }
        pollingTaskIDs.insert(taskID)
        defer { pollingTaskIDs.remove(taskID) }

        do {
            let backend = try await channel.loadBackend()
            let client = XenodiaImageGenerationClient(backend: backend)
            for attempt in 0..<240 {
                if attempt > 0 {
                    let seconds = min(15, 3 + attempt / 20)
                    try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                }
                let status: XenodiaTaskPollResult
                do {
                    status = try await client.pollTask(taskID: providerTaskID)
                } catch {
                    guard XenodiaImageGenerationClient.isRetryableStatusPollError(error) else {
                        throw error
                    }
                    guard var task = tasks.first(where: { $0.id == taskID }) else {
                        return
                    }
                    task.status = .running
                    task.updatedAt = Date()
                    update(task)
                    statusMessage = "Xenodia status check timed out. Still polling..."
                    continue
                }
                guard var task = tasks.first(where: { $0.id == taskID }) else {
                    return
                }
                if status.isSuccessful {
                    guard let resultURL = status.resultURL else {
                        task.status = .failed
                        task.errorMessage = "Xenodia task succeeded but did not include a result URL."
                        task.updatedAt = Date()
                        update(task)
                        statusMessage = task.errorMessage ?? "Generation completed without a result URL."
                        return
                    }
                    task.status = .completed
                    task.resultURL = resultURL
                    task.updatedAt = Date()
                    task = await cacheGeneratedResultIfPossible(task)
                    update(task)
                    statusMessage = task.isLocallyCached
                        ? "Generated and cached \(task.category.rawValue)."
                        : "Generated \(task.category.rawValue)."
                    return
                }
                if status.isFailed {
                    task.status = .failed
                    task.errorMessage = status.error ?? "Xenodia media task failed."
                    task.updatedAt = Date()
                    update(task)
                    statusMessage = task.errorMessage ?? "Generation failed."
                    return
                }
                task.status = .running
                task.updatedAt = Date()
                update(task)
                statusMessage = "Xenodia task is still running..."
            }
            guard var task = tasks.first(where: { $0.id == taskID }) else {
                return
            }
            task.updatedAt = Date()
            update(task)
            statusMessage = "Xenodia task is still running. Refresh will continue polling."
        } catch {
            guard var task = tasks.first(where: { $0.id == taskID }) else {
                return
            }
            task.status = .failed
            task.errorMessage = error.localizedDescription
            task.updatedAt = Date()
            update(task)
            statusMessage = error.localizedDescription
        }
    }

    private func resumePollingForRunningTasks() {
        for task in tasks where task.status == .running || task.status == .queued {
            guard let providerTaskID = task.providerTaskID, task.resultURL == nil else {
                continue
            }
            Task { [weak self] in
                await self?.poll(taskID: task.id, providerTaskID: providerTaskID)
            }
        }
    }

    private func cacheGeneratedResultIfPossible(_ task: MediaGeneratorTask) async -> MediaGeneratorTask {
        guard !task.isLocallyCached,
              let resultURL = task.resultURL,
              let url = URL(string: resultURL),
              !url.isFileURL
        else {
            return task
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw MediaGeneratorError.requestFailed(
                    http.statusCode,
                    String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
                )
            }
            let cachedURL = try database.saveResultData(data, for: task, suggestedExtension: task.resultFileExtension)
            var updated = task
            updated.localOutputPath = cachedURL.path
            updated.updatedAt = Date()
            return updated
        } catch {
            statusMessage = "Generated \(task.category.rawValue). Local cache failed: \(error.localizedDescription)"
            return task
        }
    }

    private func currentParameterSnapshot(
        modelID: MediaGeneratorModelID,
        imageCount: Int,
        batchCount: Int,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        outputFormat: MediaGeneratorOutputFormat,
        videoOptions: MediaGeneratorVideoOptions = .default
    ) -> [String: String] {
        var parameters = [
            "batch_count": "\(batchCount)"
        ]
        switch modelID {
        case .nanoBananaPro:
            parameters["response_format"] = "url"
            parameters["n"] = "\(imageCount)"
            parameters["aspect_ratio"] = aspectRatio.rawValue
            parameters["resolution"] = resolution.rawValue
            parameters["output_format"] = outputFormat.rawValue
        case .gptImage2:
            parameters["response_format"] = "url"
            parameters["n"] = "\(imageCount)"
            parameters["aspect_ratio"] = aspectRatio.rawValue
            parameters["resolution"] = resolution.rawValue
        case .veo31, .veo31Fast, .veo31Lite:
            parameters["aspect_ratio"] = aspectRatio.rawValue
            parameters["resolution"] = resolution.rawValue
            parameters["generation_type"] = videoOptions.generationType.rawValue
            parameters["enable_translation"] = "\(videoOptions.enableTranslation)"
            if let seed = videoOptions.seed {
                parameters["seed"] = "\(seed)"
            }
            if let watermark = videoOptions.watermark {
                parameters["watermark"] = watermark
            }
            if let callbackURL = videoOptions.callbackURL {
                parameters["callback_url"] = callbackURL
            }
        case .seedance2, .seedance2Fast:
            parameters["aspect_ratio"] = aspectRatio.rawValue
            parameters["resolution"] = resolution.rawValue
            parameters["generation_type"] = videoOptions.generationType.rawValue
            parameters["duration"] = "\(videoOptions.duration)"
            parameters["generate_audio"] = "\(videoOptions.generateAudio)"
            parameters["web_search"] = "\(videoOptions.webSearch)"
            parameters["nsfw_checker"] = "\(videoOptions.nsfwChecker)"
            if let firstFrameURL = videoOptions.firstFrameURL {
                parameters["first_frame_url"] = firstFrameURL
            }
            if let lastFrameURL = videoOptions.lastFrameURL {
                parameters["last_frame_url"] = lastFrameURL
            }
            if !videoOptions.referenceVideoURLs.isEmpty {
                parameters["reference_video_urls"] = Self.jsonStringArray(videoOptions.referenceVideoURLs)
            }
            if !videoOptions.referenceAudioURLs.isEmpty {
                parameters["reference_audio_urls"] = Self.jsonStringArray(videoOptions.referenceAudioURLs)
            }
            if let callbackURL = videoOptions.callbackURL {
                parameters["callback_url"] = callbackURL
            }
        }
        return parameters
    }

    private static func videoParametersAfterResolvingReferences(
        _ parameters: [String: String],
        references: [MediaGeneratorReference]
    ) -> [String: String] {
        guard parameters["generation_type"] == MediaGeneratorVideoGenerationType.firstAndLastFrames.rawValue else {
            return parameters
        }
        var updated = parameters
        let urls = references.compactMap(\.url)
        if let firstURL = urls.first {
            updated["first_frame_url"] = firstURL
        }
        if urls.count > 1 {
            updated["last_frame_url"] = urls[1]
        } else {
            updated.removeValue(forKey: "last_frame_url")
        }
        return updated
    }

    private func update(_ task: MediaGeneratorTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        persist(task)
    }

    private func addImageHistoryReference(_ reference: MediaGeneratorReference) {
        let item: MediaGeneratorImageHistoryItem
        if let url = reference.url?.trimmingCharacters(in: .whitespacesAndNewlines),
           let parsed = URL(string: url),
           parsed.scheme?.hasPrefix("http") == true || parsed.scheme == "asset" {
            item = MediaGeneratorImageHistoryItem(url: url, displayName: reference.displayName)
        } else if let localPath = reference.localPath, !localPath.isEmpty {
            item = MediaGeneratorImageHistoryItem(localPath: localPath, displayName: reference.displayName)
        } else {
            return
        }
        imageHistory.removeAll { $0.historyKey == item.historyKey }
        imageHistory.insert(item, at: 0)
        if imageHistory.count > 2_000 {
            imageHistory = Array(imageHistory.prefix(2_000))
        }
        persistImageHistory()
    }

    private func persistImageHistory() {
        do {
            try database.saveImageHistory(imageHistory)
        } catch {
            statusMessage = "Could not save image history: \(error.localizedDescription)"
        }
    }

    private func persistQuickPrompts() {
        do {
            try database.saveQuickPrompts(quickPrompts)
        } catch {
            statusMessage = "Could not save quick prompts: \(error.localizedDescription)"
        }
    }

    private func persist(_ task: MediaGeneratorTask) {
        do {
            try database.save(task)
        } catch {
            statusMessage = "Could not save task: \(error.localizedDescription)"
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    nonisolated private static var supportedReferenceContentTypes: [UTType] {
        var types: [UTType] = [.jpeg, .png]
        if let webP = UTType(filenameExtension: "webp") {
            types.append(webP)
        }
        return types
    }

    private static func downloadContentTypes(for task: MediaGeneratorTask) -> [UTType] {
        switch task.resultFileExtension.lowercased() {
        case "jpg", "jpeg":
            return [.jpeg]
        case "webp":
            return UTType(filenameExtension: "webp").map { [$0] } ?? []
        case "mp4":
            return UTType(filenameExtension: "mp4").map { [$0] } ?? [.movie]
        case "mov":
            return [.quickTimeMovie]
        case "webm":
            return UTType(filenameExtension: "webm").map { [$0] } ?? [.movie]
        default:
            return task.category == .video ? [.movie] : [.png]
        }
    }

    private static func defaultModel(for category: MediaGeneratorCategory) -> MediaGeneratorModelID {
        switch category {
        case .image:
            return .nanoBananaPro
        case .video:
            return .veo31Fast
        case .audio:
            return .nanoBananaPro
        }
    }

    private static func defaultAspectRatio(for modelID: MediaGeneratorModelID) -> MediaGeneratorAspectRatio {
        switch modelID {
        case .gptImage2:
            return .auto
        case .veo31, .veo31Fast, .veo31Lite, .seedance2, .seedance2Fast:
            return .landscape
        case .nanoBananaPro:
            return .square
        }
    }

    private static func defaultResolution(
        for modelID: MediaGeneratorModelID,
        aspectRatio: MediaGeneratorAspectRatio
    ) -> MediaGeneratorResolution {
        supportedResolutions(for: modelID, aspectRatio: aspectRatio).first
            ?? (modelID.category == .video ? .p720 : .oneK)
    }

    nonisolated static func availableModels(for category: MediaGeneratorCategory) -> [MediaGeneratorModelID] {
        MediaGeneratorModelID.allCases.filter { $0.category == category }
    }

    nonisolated static func supportedVideoGenerationTypes(
        for modelID: MediaGeneratorModelID
    ) -> [MediaGeneratorVideoGenerationType] {
        switch modelID {
        case .veo31, .veo31Lite:
            return [.textToVideo, .firstAndLastFrames]
        case .veo31Fast:
            return MediaGeneratorVideoGenerationType.allCases
        case .seedance2, .seedance2Fast:
            return [.textToVideo, .firstAndLastFrames, .referenceToVideo]
        case .nanoBananaPro, .gptImage2:
            return []
        }
    }

    private static func categoryArg(_ value: Any?) -> MediaGeneratorCategory? {
        guard let string = value as? String else {
            return nil
        }
        return MediaGeneratorCategory(
            rawValue: string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    private static func modelIDArg(_ value: Any?) -> MediaGeneratorModelID? {
        guard let string = value as? String else {
            return nil
        }
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "nano-banana-pro", "nanobananapro":
            return .nanoBananaPro
        case "gpt-image-2", "gptimage2", "image-2", "image2":
            return .gptImage2
        case "veo3.1", "veo-3.1", "veo31":
            return .veo31
        case "veo3.1-fast", "veo-3.1-fast", "veo31-fast":
            return .veo31Fast
        case "veo3.1-lite", "veo-3.1-lite", "veo31-lite":
            return .veo31Lite
        case "seedance-2", "seedance2", "seedance-2.0", "seedance2.0":
            return .seedance2
        case "seedance-2-fast", "seedance2-fast", "seedance-2.0-fast", "seedance2.0-fast":
            return .seedance2Fast
        default:
            return MediaGeneratorModelID(rawValue: string.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? MediaGeneratorModelID(rawValue: normalized)
        }
    }

    private static func aspectRatioArg(_ value: Any?) -> MediaGeneratorAspectRatio? {
        guard let string = value as? String else {
            return nil
        }
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")
        switch normalized.lowercased() {
        case "auto":
            return .auto
        case "adaptive":
            return .adaptive
        default:
            return MediaGeneratorAspectRatio(rawValue: normalized)
        }
    }

    private static func resolutionArg(_ value: Any?) -> MediaGeneratorResolution? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "480p":
            return .p480
        case "720p":
            return .p720
        case "1080p":
            return .p1080
        case "4k":
            if trimmed == "4K" {
                return .fourK
            }
            return .video4K
        default:
            return MediaGeneratorResolution(rawValue: trimmed.uppercased())
        }
    }

    private static func normalizedResolution(
        _ resolution: MediaGeneratorResolution?,
        for modelID: MediaGeneratorModelID
    ) -> MediaGeneratorResolution? {
        guard let resolution else {
            return nil
        }
        if modelID.category == .video, resolution == .fourK {
            return .video4K
        }
        if modelID.category == .image, resolution == .video4K {
            return .fourK
        }
        return resolution
    }

    private static func outputFormatArg(_ value: Any?) -> MediaGeneratorOutputFormat? {
        guard let string = value as? String else {
            return nil
        }
        return MediaGeneratorOutputFormat(
            rawValue: string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        )
    }

    nonisolated static func supportedAspectRatios(for modelID: MediaGeneratorModelID) -> [MediaGeneratorAspectRatio] {
        switch modelID {
        case .nanoBananaPro:
            return [.square, .tall, .wide, .classicPortrait, .classicLandscape, .portrait, .vertical, .story, .landscape, .cinema, .auto]
        case .gptImage2:
            return [.auto, .square, .story, .landscape, .classicLandscape, .classicPortrait]
        case .veo31, .veo31Fast, .veo31Lite:
            return [.landscape, .story, .auto]
        case .seedance2, .seedance2Fast:
            return [.square, .classicLandscape, .classicPortrait, .landscape, .story, .cinema, .adaptive]
        }
    }

    nonisolated static func supportedResolutions(for modelID: MediaGeneratorModelID, aspectRatio: MediaGeneratorAspectRatio) -> [MediaGeneratorResolution] {
        switch modelID {
        case .nanoBananaPro:
            return [.oneK, .twoK, .fourK]
        case .gptImage2:
            if aspectRatio == .auto {
                return [.oneK]
            }
            if aspectRatio == .square {
                return [.oneK, .twoK]
            }
            return [.oneK, .twoK, .fourK]
        case .veo31, .veo31Fast:
            return [.p720, .p1080, .video4K]
        case .veo31Lite:
            return [.p720, .p1080]
        case .seedance2:
            return [.p720, .p480, .p1080]
        case .seedance2Fast:
            return [.p720, .p480]
        }
    }

    private static func supportedModelResolutions(for modelID: MediaGeneratorModelID) -> [MediaGeneratorResolution] {
        var seen = Set<MediaGeneratorResolution>()
        var output: [MediaGeneratorResolution] = []
        for aspectRatio in supportedAspectRatios(for: modelID) {
            for resolution in supportedResolutions(for: modelID, aspectRatio: aspectRatio) where !seen.contains(resolution) {
                seen.insert(resolution)
                output.append(resolution)
            }
        }
        return output
    }

    private static func supportedResolutionsByAspectRatioPayload(for modelID: MediaGeneratorModelID) -> [String: [String]] {
        Dictionary(
            uniqueKeysWithValues: supportedAspectRatios(for: modelID).map { aspectRatio in
                (
                    aspectRatio.rawValue,
                    supportedResolutions(for: modelID, aspectRatio: aspectRatio).map(\.rawValue)
                )
            }
        )
    }

    nonisolated static func maxReferenceCount(for modelID: MediaGeneratorModelID) -> Int {
        switch modelID {
        case .nanoBananaPro:
            return 8
        case .gptImage2:
            return 16
        case .veo31, .veo31Fast, .veo31Lite:
            return 3
        case .seedance2, .seedance2Fast:
            return 9
        }
    }

    private static func supportedFields(for modelID: MediaGeneratorModelID) -> [String] {
        switch modelID {
        case .nanoBananaPro:
            ["model", "prompt", "n", "batch_count", "response_format", "aspect_ratio", "resolution", "output_format", "image_input"]
        case .gptImage2:
            ["model", "prompt", "n", "batch_count", "response_format", "aspect_ratio", "resolution", "image_input"]
        case .veo31, .veo31Fast, .veo31Lite:
            [
                "model", "prompt", "batch_count", "generation_type", "aspect_ratio", "resolution",
                "image_urls", "seed", "enable_translation", "watermark", "callback_url"
            ]
        case .seedance2, .seedance2Fast:
            [
                "model", "prompt", "batch_count", "aspect_ratio", "resolution", "duration",
                "first_frame_url", "last_frame_url", "reference_image_urls",
                "reference_video_urls", "reference_audio_urls", "generate_audio",
                "web_search", "nsfw_checker", "callback_url"
            ]
        }
    }

    nonisolated static func groupedTasks(_ tasks: [MediaGeneratorTask]) -> [MediaGeneratorTaskGroup] {
        let orderedTasks = tasks.sorted(by: MediaGeneratorTaskGroup.sortTasks)
        var grouped: [String: [MediaGeneratorTask]] = [:]
        var order: [String] = []
        for task in orderedTasks {
            let key = task.batchID ?? task.id
            if grouped[key] == nil {
                grouped[key] = []
                order.append(key)
            }
            grouped[key, default: []].append(task)
        }
        return order.compactMap { key in
            guard let tasks = grouped[key]?.sorted(by: MediaGeneratorTaskGroup.sortTasks),
                  !tasks.isEmpty
            else {
                return nil
            }
            return MediaGeneratorTaskGroup(
                id: key,
                batchID: tasks.first?.batchID,
                tasks: tasks
            )
        }
    }

    private static func supportedValuesPayload(for modelID: MediaGeneratorModelID) -> [String: Any] {
        var payload: [String: Any] = [
            "aspect_ratio": supportedAspectRatios(for: modelID).map(\.rawValue),
            "resolution": supportedModelResolutions(for: modelID).map(\.rawValue),
            "resolution_by_aspect_ratio": supportedResolutionsByAspectRatioPayload(for: modelID)
        ]
        if modelID == .nanoBananaPro {
            payload["output_format"] = MediaGeneratorOutputFormat.allCases.map(\.rawValue)
        }
        if modelID.category == .video {
            payload["generation_type"] = supportedVideoGenerationTypes(for: modelID).map(\.rawValue)
            payload["reference_url_schemes"] = ["http", "https", "asset"]
        }
        if modelID.isSeedance {
            payload["duration"] = ["minimum": 4, "maximum": 15, "default": 5]
            payload["generate_audio"] = [true, false]
            payload["web_search"] = [true, false]
            payload["nsfw_checker"] = [true, false]
        }
        return payload
    }

    private static func defaultParameterPayload(for modelID: MediaGeneratorModelID) -> [String: Any] {
        var payload: [String: Any] = ["aspect_ratio": defaultAspectRatio(for: modelID).rawValue]
        switch modelID {
        case .nanoBananaPro:
            payload["n"] = 1
            payload["batch_count"] = 1
            payload["response_format"] = "url"
            payload["resolution"] = MediaGeneratorResolution.oneK.rawValue
            payload["output_format"] = MediaGeneratorOutputFormat.png.rawValue
        case .gptImage2:
            payload["n"] = 1
            payload["batch_count"] = 1
            payload["response_format"] = "url"
            payload["resolution"] = MediaGeneratorResolution.oneK.rawValue
        case .veo31, .veo31Fast, .veo31Lite:
            payload["batch_count"] = 1
            payload["resolution"] = MediaGeneratorResolution.p720.rawValue
            payload["generation_type"] = MediaGeneratorVideoGenerationType.textToVideo.rawValue
            payload["enable_translation"] = true
        case .seedance2, .seedance2Fast:
            payload["batch_count"] = 1
            payload["resolution"] = MediaGeneratorResolution.p720.rawValue
            payload["duration"] = 5
            payload["generate_audio"] = false
            payload["web_search"] = false
            payload["nsfw_checker"] = false
        }
        return payload
    }

    func normalizeSelectionForCurrentModel() {
        if category != .audio, selectedModel.category != category {
            selectedModel = Self.defaultModel(for: category)
        }
        let supportedRatios = Self.supportedAspectRatios(for: selectedModel)
        if !supportedRatios.contains(aspectRatio) {
            aspectRatio = Self.defaultAspectRatio(for: selectedModel)
        }
        let supportedResolutions = Self.supportedResolutions(for: selectedModel, aspectRatio: aspectRatio)
        if !supportedResolutions.contains(resolution) {
            resolution = Self.defaultResolution(for: selectedModel, aspectRatio: aspectRatio)
        }
        if !Self.supportedVideoGenerationTypes(for: selectedModel).contains(videoGenerationType) {
            videoGenerationType = .textToVideo
        }
        if references.count > Self.maxReferenceCount(for: selectedModel) {
            references = Array(references.prefix(Self.maxReferenceCount(for: selectedModel)))
            statusMessage = "\(selectedModel.title) accepts at most \(Self.maxReferenceCount(for: selectedModel)) references."
        }
        if selectedModel.category == .video {
            videoDuration = min(max(videoDuration, 4), 15)
        }
        imageCount = min(max(imageCount, 1), 4)
    }

    private static func boolArg(_ value: Any?, defaultValue: Bool) -> Bool {
        if let bool = value as? Bool {
            return bool
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return defaultValue
            }
        }
        return defaultValue
    }

    private static func intArg(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double, double.rounded() == double {
            return Int(double)
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func stringArg(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringArrayArg(_ value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let anyValues = value as? [Any] {
            return anyValues.compactMap(stringArg)
        }
        if let string = stringArg(value) {
            return [string]
        }
        return []
    }

    private static func videoFrameURLs(from options: MediaGeneratorVideoOptions) -> [String] {
        [options.firstFrameURL, options.lastFrameURL].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    private static func videoOptionsArg(_ args: [String: Any]) -> MediaGeneratorVideoOptions {
        let firstFrameURL = stringArg(args["first_frame_url"])
            ?? stringArg(args["firstFrameUrl"])
            ?? stringArg(args["firstFrameURL"])
        let lastFrameURL = stringArg(args["last_frame_url"])
            ?? stringArg(args["lastFrameUrl"])
            ?? stringArg(args["lastFrameURL"])
        let referenceVideoURLs = stringArrayArg(args["reference_video_urls"])
            + stringArrayArg(args["referenceVideoUrls"])
            + stringArrayArg(args["referenceVideoURLs"])
        let referenceAudioURLs = stringArrayArg(args["reference_audio_urls"])
            + stringArrayArg(args["referenceAudioUrls"])
            + stringArrayArg(args["referenceAudioURLs"])
        let explicitGenerationType = videoGenerationTypeArg(
            args["generation_type"] ?? args["generationType"]
        )
        let inferredGenerationType: MediaGeneratorVideoGenerationType
        if let explicitGenerationType {
            inferredGenerationType = explicitGenerationType
        } else if firstFrameURL != nil || lastFrameURL != nil {
            inferredGenerationType = .firstAndLastFrames
        } else if !referenceVideoURLs.isEmpty
            || !referenceAudioURLs.isEmpty
            || !stringArrayArg(args["reference_image_urls"]).isEmpty
            || !stringArrayArg(args["reference_urls"]).isEmpty
            || !stringArrayArg(args["image_urls"]).isEmpty
            || !stringArrayArg(args["imageUrls"]).isEmpty {
            inferredGenerationType = .referenceToVideo
        } else {
            inferredGenerationType = .textToVideo
        }
        return MediaGeneratorVideoOptions(
            generationType: inferredGenerationType,
            duration: intArg(args["duration"]).map { min(max($0, 4), 15) } ?? 5,
            generateAudio: boolArg(args["generate_audio"], defaultValue: false),
            webSearch: boolArg(args["web_search"], defaultValue: false),
            nsfwChecker: boolArg(args["nsfw_checker"], defaultValue: false),
            seed: intArg(args["seed"] ?? args["seeds"]),
            enableTranslation: boolArg(
                args["enable_translation"] ?? args["enableTranslation"],
                defaultValue: true
            ),
            watermark: stringArg(args["watermark"]),
            firstFrameURL: firstFrameURL,
            lastFrameURL: lastFrameURL,
            referenceVideoURLs: referenceVideoURLs,
            referenceAudioURLs: referenceAudioURLs,
            callbackURL: stringArg(args["callback_url"] ?? args["callBackUrl"] ?? args["callbackUrl"])
        )
    }

    private static func videoGenerationTypeArg(_ value: Any?) -> MediaGeneratorVideoGenerationType? {
        guard let string = value as? String else {
            return nil
        }
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "text", "text_to_video", "text_2_video":
            return .textToVideo
        case "first_last", "first_and_last", "first_and_last_frames", "first_and_last_frames_2_video":
            return .firstAndLastFrames
        case "reference", "reference_to_video", "reference_2_video":
            return .referenceToVideo
        default:
            return MediaGeneratorVideoGenerationType(rawValue: string)
        }
    }

    private static func jsonStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    private static func imageCountArg(_ value: Any?) throws -> Int {
        if value == nil {
            return 1
        }
        if let int = value as? Int {
            try validateImageCount(int)
            return int
        }
        if let string = value as? String, let int = Int(string) {
            try validateImageCount(int)
            return int
        }
        throw MediaGeneratorError.invalidOption("Xenodia image generation currently supports only n=1.")
    }

    private static func batchCountArg(_ value: Any?) throws -> Int {
        if value == nil {
            return 1
        }
        if let int = value as? Int {
            try validateBatchCount(int)
            return int
        }
        if let double = value as? Double, double.rounded() == double {
            let int = Int(double)
            try validateBatchCount(int)
            return int
        }
        if let string = value as? String, let int = Int(string) {
            try validateBatchCount(int)
            return int
        }
        throw MediaGeneratorError.invalidOption("Media Generator batch_count must be between 1 and 4.")
    }

    private static func validateImageCount(_ imageCount: Int) throws {
        guard imageCount == 1 else {
            throw MediaGeneratorError.invalidOption("Xenodia image generation currently supports only n=1.")
        }
    }

    private static func validateBatchCount(_ batchCount: Int) throws {
        guard (1...4).contains(batchCount) else {
            throw MediaGeneratorError.invalidOption("Media Generator batch_count must be between 1 and 4.")
        }
    }

    private static func validateBatchCount(_ batchCount: Int, category _: MediaGeneratorCategory) throws {
        try validateBatchCount(batchCount)
    }

    private static func validateResponseFormat(_ value: Any?) throws {
        guard let value else {
            return
        }
        if let string = value as? String, string == "url" {
            return
        }
        throw MediaGeneratorError.invalidOption("Xenodia media generation currently supports only response_format=url.")
    }

    private static func validateUnsupportedModelArgs(modelID: MediaGeneratorModelID, args: [String: Any]) throws {
        if modelID.category == .video, args["output_format"] != nil {
            throw MediaGeneratorError.invalidOption("\(modelID.title) does not support output_format.")
        }
        if modelID == .gptImage2 {
            if args["output_format"] != nil {
                throw MediaGeneratorError.invalidOption("GPT Image-2 does not support output_format in the current Xenodia API.")
            }
            if args["nsfw_checker"] != nil {
                throw MediaGeneratorError.invalidOption("GPT Image-2 does not support nsfw_checker in the current Xenodia API.")
            }
        }
        if modelID.isVeo {
            for key in ["duration", "generate_audio", "web_search", "nsfw_checker", "reference_video_urls", "reference_audio_urls"] where args[key] != nil {
                throw MediaGeneratorError.invalidOption("\(modelID.title) does not support \(key).")
            }
        }
        if modelID.isSeedance {
            for key in ["seed", "seeds", "enable_translation", "enableTranslation", "watermark"] where args[key] != nil {
                throw MediaGeneratorError.invalidOption("\(modelID.title) does not support \(key).")
            }
        }
    }

    private static func validateModelParameters(
        modelID: MediaGeneratorModelID,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution
    ) throws {
        guard supportedAspectRatios(for: modelID).contains(aspectRatio) else {
            throw MediaGeneratorError.invalidOption("\(modelID.title) does not support aspect_ratio=\(aspectRatio.rawValue).")
        }
        guard supportedResolutions(for: modelID, aspectRatio: aspectRatio).contains(resolution) else {
            throw MediaGeneratorError.invalidOption("\(modelID.title) does not support resolution=\(resolution.rawValue) with aspect_ratio=\(aspectRatio.rawValue).")
        }
    }

    private static func validateReferences(
        modelID: MediaGeneratorModelID,
        _ references: [MediaGeneratorReference],
        videoOptions: MediaGeneratorVideoOptions
    ) throws {
        let maxCount = maxReferenceCount(for: modelID)
        guard references.count <= maxCount else {
            throw MediaGeneratorError.invalidReference("\(modelID.title) accepts at most \(maxCount) total references.")
        }
        guard modelID.category == .video else {
            for reference in references {
                if let url = reference.url {
                    try validateReferenceURL(url, allowedSchemes: ["http", "https"], label: "Reference image")
                }
                if let localPath = reference.localPath {
                    try validateLocalReferenceFile(URL(fileURLWithPath: localPath))
                }
            }
            return
        }

        for reference in references {
            if let localPath = reference.localPath {
                try validateLocalReferenceFile(URL(fileURLWithPath: localPath))
            }
            if let url = reference.url {
                try validateReferenceURL(url, allowedSchemes: ["http", "https", "asset"], label: "Video reference")
            }
        }

        if modelID.isVeo {
            if let seed = videoOptions.seed, !(10_000...99_999).contains(seed) {
                throw MediaGeneratorError.invalidOption("Veo3.1 seeds must be between 10000 and 99999.")
            }
            switch videoOptions.generationType {
            case .textToVideo:
                guard references.isEmpty else {
                    throw MediaGeneratorError.invalidReference("Veo3.1 TEXT_2_VIDEO does not accept imageUrls.")
                }
            case .firstAndLastFrames:
                guard (1...2).contains(references.count) else {
                    throw MediaGeneratorError.invalidReference("Veo3.1 FIRST_AND_LAST_FRAMES_2_VIDEO requires 1-2 imageUrls.")
                }
            case .referenceToVideo:
                guard modelID == .veo31Fast else {
                    throw MediaGeneratorError.invalidOption("Veo3.1 REFERENCE_2_VIDEO only supports veo3.1_fast.")
                }
                guard (1...3).contains(references.count) else {
                    throw MediaGeneratorError.invalidReference("Veo3.1 REFERENCE_2_VIDEO requires 1-3 imageUrls.")
                }
            }
            return
        }

        if modelID.isSeedance {
            guard (4...15).contains(videoOptions.duration) else {
                throw MediaGeneratorError.invalidOption("Seedance 2.0 duration must be an integer from 4 to 15 seconds.")
            }
            try validateURLList(videoOptions.referenceVideoURLs, maxCount: 3, label: "reference_video_urls")
            try validateURLList(videoOptions.referenceAudioURLs, maxCount: 3, label: "reference_audio_urls")
            if videoOptions.lastFrameURL != nil, videoOptions.firstFrameURL == nil {
                throw MediaGeneratorError.invalidReference("Seedance 2.0 last_frame_url requires first_frame_url.")
            }
            if videoOptions.generationType == .firstAndLastFrames
                || videoOptions.firstFrameURL != nil
                || videoOptions.lastFrameURL != nil {
                let frameURLCount = videoFrameURLs(from: videoOptions).count
                guard (1...2).contains(references.count) else {
                    throw MediaGeneratorError.invalidReference("Seedance 2.0 first/last frame mode accepts at most 2 frame URLs.")
                }
                guard frameURLCount == 0 || references.count == frameURLCount else {
                    throw MediaGeneratorError.invalidReference("Seedance 2.0 first/last frame URLs cannot be combined with multimodal reference arrays.")
                }
                guard videoOptions.referenceVideoURLs.isEmpty, videoOptions.referenceAudioURLs.isEmpty else {
                    throw MediaGeneratorError.invalidReference("Seedance 2.0 first/last frame URLs cannot be combined with multimodal reference arrays.")
                }
            }
        }
    }

    private static func validateURLList(_ urls: [String], maxCount: Int, label: String) throws {
        guard urls.count <= maxCount else {
            throw MediaGeneratorError.invalidReference("\(label) accepts at most \(maxCount) URLs.")
        }
        for url in urls {
            try validateReferenceURL(url, allowedSchemes: ["http", "https", "asset"], label: label)
        }
    }

    private static func validateReferenceURL(
        _ value: String,
        allowedSchemes: Set<String>,
        label: String
    ) throws {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme)
        else {
            throw MediaGeneratorError.invalidReference("\(label) must use \(allowedSchemes.sorted().joined(separator: ", ")) URL schemes.")
        }
    }

    private static func validateLocalReferenceFile(_ fileURL: URL) throws {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        if let fileSize = values.fileSize,
           Int64(fileSize) > MediaGeneratorError.maxReferenceFileBytes {
            throw MediaGeneratorError.invalidReference("Reference image must be 30MB or smaller.")
        }
        let type = values.contentType ?? UTType(filenameExtension: fileURL.pathExtension)
        guard let type,
              supportedReferenceContentTypes.contains(where: { type.conforms(to: $0) })
        else {
            throw MediaGeneratorError.invalidReference("Reference images must be JPEG, PNG, or WebP.")
        }
    }
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}
