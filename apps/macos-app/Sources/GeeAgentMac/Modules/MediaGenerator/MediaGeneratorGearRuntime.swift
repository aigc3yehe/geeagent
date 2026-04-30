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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nanoBananaPro: "Nano Banana Pro"
        case .gptImage2: "GPT Image-2"
        }
    }

    var subtitle: String {
        switch self {
        case .nanoBananaPro: "Xenodia image model with aspect ratio, resolution, output format, and up to 8 references."
        case .gptImage2: "Xenodia GPT Image-2 with prompt/reference routing, resolution controls, and up to 16 references."
        }
    }
}

enum MediaGeneratorAspectRatio: String, Codable, CaseIterable, Identifiable {
    case auto
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

    var id: String { rawValue }
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
    var url: String
    var timestamp: Date

    init(id: String = UUID().uuidString, url: String, timestamp: Date = Date()) {
        self.id = id
        self.url = url
        self.timestamp = timestamp
    }
}

struct MediaGeneratorTask: Codable, Identifiable, Hashable, Sendable {
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
        return parameters["output_format"] == "jpg" ? "jpg" : "png"
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "gear_id": MediaGeneratorGearDescriptor.gearID,
            "category": category.rawValue,
            "model": modelID.rawValue,
            "prompt": prompt,
            "status": status.rawValue,
            "created_at": ISO8601DateFormatter().string(from: createdAt),
            "updated_at": ISO8601DateFormatter().string(from: updatedAt),
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
            "\(category.title) generation is reserved for future Xenodia media endpoints."
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
        let root = try gearRoot().appendingPathComponent("tasks", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func taskDirectory(_ id: String) throws -> URL {
        try tasksRoot().appendingPathComponent(id, isDirectory: true)
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
    var backend: XenodiaMediaBackend

    func createImageTask(
        modelID: MediaGeneratorModelID,
        prompt: String,
        imageCount: Int,
        useAsync: Bool,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        outputFormat: MediaGeneratorOutputFormat,
        references: [MediaGeneratorReference]
    ) async throws -> (providerTaskID: String?, resultURL: String?) {
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
            useAsync: useAsync,
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
        return try parseCreationResponse(responseData)
    }

    func pollTask(taskID: String) async throws -> XenodiaTaskPollResult {
        let taskBase = backend.taskRetrievalURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(taskBase)/\(taskID)") else {
            throw MediaGeneratorError.invalidResponse("Invalid Xenodia task retrieval URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(backend.requestTimeoutSeconds)
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

    private func imageRequestFields(
        modelID: MediaGeneratorModelID,
        prompt: String,
        imageCount: Int,
        useAsync: Bool,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        outputFormat: MediaGeneratorOutputFormat
    ) -> [String: Any] {
        var fields: [String: Any] = [
            "model": modelID.rawValue,
            "prompt": prompt,
            "n": imageCount,
            "async": useAsync,
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
        }
        return fields
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
        request.timeoutInterval = TimeInterval(backend.requestTimeoutSeconds)
        request.setValue("Bearer \(backend.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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
        request.timeoutInterval = TimeInterval(backend.requestTimeoutSeconds)
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

    private func parseCreationResponse(_ data: Data) throws -> (providerTaskID: String?, resultURL: String?) {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaGeneratorError.invalidResponse("Xenodia creation response was not a JSON object.")
        }
        let providerTaskID = object["task_id"] as? String
            ?? object["taskId"] as? String
            ?? ((object["data"] as? [String: Any])?["task_id"] as? String)
            ?? ((object["data"] as? [String: Any])?["taskId"] as? String)
        let resultURL = Self.firstResultURL(in: object)
        return (providerTaskID, resultURL)
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
    @Published var useAsync = true
    @Published var references: [MediaGeneratorReference] = []
    @Published var taskFilter: MediaGeneratorTaskFilter = .all
    @Published var modelFilter: MediaGeneratorModelID?
    @Published var searchQuery = ""
    @Published var quickPrompts: [MediaGeneratorQuickPrompt] = MediaGeneratorQuickPrompt.defaults
    @Published private(set) var imageHistory: [MediaGeneratorImageHistoryItem] = []
    @Published private(set) var tasks: [MediaGeneratorTask] = []
    @Published var selectedTaskID: MediaGeneratorTask.ID?
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var isBusy = false

    private let database: MediaGeneratorFileDatabase
    private let channel: XenodiaMediaChannel
    private var pollingTaskIDs: Set<MediaGeneratorTask.ID> = []

    var selectedTask: MediaGeneratorTask? {
        tasks.first { $0.id == selectedTaskID } ?? tasks.first
    }

    var selectedModelReferenceLimit: Int {
        Self.maxReferenceCount(for: selectedModel)
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
        selectedTaskID = selectedTaskID ?? tasks.first?.id
        resumePollingForRunningTasks()
    }

    func selectModel(_ model: MediaGeneratorModelID) {
        selectedModel = model
        normalizeSelectionForCurrentModel()
    }

    func addReferenceFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.supportedReferenceContentTypes
        if panel.runModal() == .OK {
            for url in panel.urls {
                guard references.count < selectedModelReferenceLimit else {
                    break
                }
                do {
                    try Self.validateLocalReferenceFile(url)
                    references.append(
                        MediaGeneratorReference(
                            id: UUID().uuidString,
                            url: nil,
                            localPath: url.path,
                            displayName: url.lastPathComponent
                        )
                    )
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func addReferenceURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard references.count < selectedModelReferenceLimit,
              let parsed = URL(string: trimmed),
              parsed.scheme?.hasPrefix("http") == true
        else {
            statusMessage = "Paste a valid image URL. \(selectedModel.title) references are limited to \(selectedModelReferenceLimit)."
            return
        }
        references.append(
            MediaGeneratorReference(
                id: UUID().uuidString,
                url: trimmed,
                localPath: nil,
                displayName: parsed.lastPathComponent.isEmpty ? parsed.host ?? "Reference URL" : parsed.lastPathComponent
            )
        )
        addImageHistoryURL(trimmed)
    }

    func removeReference(_ reference: MediaGeneratorReference) {
        references.removeAll { $0.id == reference.id }
    }

    func applyImageHistory(_ item: MediaGeneratorImageHistoryItem) {
        addReferenceURL(item.url)
    }

    func removeImageHistory(_ item: MediaGeneratorImageHistoryItem) {
        imageHistory.removeAll { $0.url == item.url }
        persistImageHistory()
    }

    func useResultAsReference(_ task: MediaGeneratorTask) {
        guard let resultURL = task.resultURL else {
            statusMessage = "No result URL to use as a reference."
            return
        }
        addReferenceURL(resultURL)
        statusMessage = "Added generated image as a reference."
    }

    func applyTaskParameters(_ task: MediaGeneratorTask) {
        category = task.category
        selectedModel = task.modelID
        prompt = task.prompt
        references = Array(task.references.prefix(Self.maxReferenceCount(for: task.modelID)))
        aspectRatio = task.parameters["aspect_ratio"].flatMap(MediaGeneratorAspectRatio.init(rawValue:))
            ?? Self.defaultAspectRatio(for: task.modelID)
        resolution = task.parameters["resolution"].flatMap(MediaGeneratorResolution.init(rawValue:)) ?? .oneK
        outputFormat = task.parameters["output_format"].flatMap(MediaGeneratorOutputFormat.init(rawValue:)) ?? .png
        imageCount = Int(task.parameters["n"] ?? "1") ?? 1
        useAsync = Bool(task.parameters["async"] ?? "true") ?? true
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

    func confirmAndDelete(_ task: MediaGeneratorTask) {
        let alert = NSAlert()
        alert.messageText = "Delete this generation task?"
        alert.informativeText = "This removes the task record from Media Generator history. Downloaded files you saved elsewhere are not removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        delete(task)
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
            await self?.createTask(
                category: self?.category ?? .image,
                modelID: self?.selectedModel ?? .nanoBananaPro,
                prompt: prompt,
                imageCount: self?.imageCount ?? 1,
                useAsync: self?.useAsync ?? true,
                aspectRatio: self?.aspectRatio ?? .square,
                resolution: self?.resolution ?? .oneK,
                outputFormat: self?.outputFormat ?? .png,
                references: self?.references ?? []
            )
        }
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
            statusMessage = "Downloaded image to \(destinationURL.lastPathComponent)."
        } catch {
            statusMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    func createAgentTask(args: [String: Any]) async -> [String: Any] {
        let prompt = (args["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = (args["model"] as? String).flatMap(MediaGeneratorModelID.init(rawValue:)) ?? .nanoBananaPro
        let category = (args["category"] as? String).flatMap(MediaGeneratorCategory.init(rawValue:)) ?? .image
        let aspectRatio = (args["aspect_ratio"] as? String).flatMap(MediaGeneratorAspectRatio.init(rawValue:))
            ?? Self.defaultAspectRatio(for: model)
        let resolution = (args["resolution"] as? String).flatMap(MediaGeneratorResolution.init(rawValue:)) ?? .oneK
        let outputFormat = (args["output_format"] as? String).flatMap(MediaGeneratorOutputFormat.init(rawValue:)) ?? .png
        let useAsync = Self.boolArg(args["async"], defaultValue: true)
        let imageCount: Int
        do {
            try Self.validateUnsupportedModelArgs(modelID: model, args: args)
            try Self.validateResponseFormat(args["response_format"])
            imageCount = try Self.imageCountArg(args["n"])
        } catch {
            statusMessage = error.localizedDescription
            return [
                "gear_id": MediaGeneratorGearDescriptor.gearID,
                "capability_id": "media_generator.create_task",
                "status": "failed",
                "error": statusMessage
            ]
        }
        let urls = (args["reference_urls"] as? [String]) ?? []
        let paths = (args["reference_paths"] as? [String]) ?? []
        let maxReferenceCount = Self.maxReferenceCount(for: model)
        let refs = urls.prefix(maxReferenceCount).map {
            MediaGeneratorReference(id: UUID().uuidString, url: $0, localPath: nil, displayName: URL(string: $0)?.lastPathComponent ?? "Reference URL")
        } + paths.prefix(max(0, maxReferenceCount - urls.count)).map {
            MediaGeneratorReference(id: UUID().uuidString, url: nil, localPath: $0, displayName: URL(fileURLWithPath: $0).lastPathComponent)
        }
        guard let task = await createTask(
            category: category,
            modelID: model,
            prompt: prompt,
            imageCount: imageCount,
            useAsync: useAsync,
            aspectRatio: aspectRatio,
            resolution: resolution,
            outputFormat: outputFormat,
            references: refs
        ) else {
            return [
                "gear_id": MediaGeneratorGearDescriptor.gearID,
                "capability_id": "media_generator.create_task",
                "status": "failed",
                "error": statusMessage
            ]
        }
        var payload = task.agentDictionary
        payload["capability_id"] = "media_generator.create_task"
        if let path = try? database.taskFileURL(task.id).path {
            payload["task_path"] = path
        }
        return payload
    }

    func taskPayload(taskID: String?) -> [String: Any] {
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
                    "category": "image",
                    "description": model.subtitle,
                    "default_parameters": Self.defaultParameterPayload(for: model),
                    "supported_fields": Self.supportedFields(for: model),
                    "supported_values": Self.supportedValuesPayload(for: model),
                    "max_total_references": Self.maxReferenceCount(for: model)
                ]
            },
            "constraints": [
                "n": ["minimum": 1, "maximum": 1, "default": 1],
                "response_format": ["enum": ["url"], "default": "url"],
                "max_total_references_by_model": [
                    MediaGeneratorModelID.nanoBananaPro.rawValue: Self.maxReferenceCount(for: .nanoBananaPro),
                    MediaGeneratorModelID.gptImage2.rawValue: Self.maxReferenceCount(for: .gptImage2)
                ],
                "max_reference_file_bytes": MediaGeneratorError.maxReferenceFileBytes,
                "accepted_mime_types": ["image/jpeg", "image/png", "image/webp"]
            ],
            "placeholders": [
                "video": "Reserved for future Xenodia video generation endpoints.",
                "audio": "Reserved for future Xenodia audio generation endpoints."
            ]
        ]
    }

    @discardableResult
    private func createTask(
        category: MediaGeneratorCategory,
        modelID: MediaGeneratorModelID,
        prompt: String,
        imageCount: Int,
        useAsync: Bool,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        outputFormat: MediaGeneratorOutputFormat,
        references: [MediaGeneratorReference]
    ) async -> MediaGeneratorTask? {
        guard !prompt.isEmpty else {
            statusMessage = MediaGeneratorError.emptyPrompt.localizedDescription
            return nil
        }
        guard category == .image else {
            statusMessage = MediaGeneratorError.unsupportedCategory(category).localizedDescription
            return nil
        }
        do {
            try Self.validateImageCount(imageCount)
            try Self.validateModelParameters(modelID: modelID, aspectRatio: aspectRatio, resolution: resolution)
            try Self.validateReferences(modelID: modelID, references)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }

        let now = Date()
        var task = MediaGeneratorTask(
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
                imageCount: imageCount,
                useAsync: useAsync,
                aspectRatio: aspectRatio,
                resolution: resolution,
                outputFormat: outputFormat
            ),
            references: Array(references.prefix(Self.maxReferenceCount(for: modelID)))
        )
        tasks.insert(task, at: 0)
        selectedTaskID = task.id
        persist(task)

        isBusy = true
        statusMessage = "Creating Xenodia generation task..."
        defer { isBusy = false }

        do {
            let backend = try await channel.loadBackend()
            let client = XenodiaImageGenerationClient(backend: backend)
            let created = try await client.createImageTask(
                modelID: modelID,
                prompt: prompt,
                imageCount: imageCount,
                useAsync: useAsync,
                aspectRatio: aspectRatio,
                resolution: resolution,
                outputFormat: outputFormat,
                references: task.references
            )
            task.providerTaskID = created.providerTaskID
            task.resultURL = created.resultURL
            task.status = created.resultURL == nil ? .running : .completed
            task.updatedAt = Date()
            if task.status == .completed {
                task = await cacheGeneratedResultIfPossible(task)
                if let resultURL = task.resultURL {
                    addImageHistoryURL(resultURL)
                }
            }
            update(task)
            statusMessage = task.status == .completed
                ? (task.isLocallyCached ? "Generated and cached image." : "Generated image.")
                : "Task created. Polling Xenodia..."
            if let providerTaskID = task.providerTaskID, task.resultURL == nil {
                Task { [weak self] in
                    await self?.poll(taskID: task.id, providerTaskID: providerTaskID)
                }
            }
            return task
        } catch {
            task.status = .failed
            task.errorMessage = error.localizedDescription
            task.updatedAt = Date()
            update(task)
            statusMessage = error.localizedDescription
            return task
        }
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
                let status = try await client.pollTask(taskID: providerTaskID)
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
                    addImageHistoryURL(resultURL)
                    update(task)
                    statusMessage = task.isLocallyCached ? "Generated and cached image." : "Generated image."
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
                if let progress = status.progress {
                    statusMessage = "Xenodia task \(progress)%..."
                }
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
            statusMessage = "Generated image. Local cache failed: \(error.localizedDescription)"
            return task
        }
    }

    private func currentParameterSnapshot(
        modelID: MediaGeneratorModelID,
        imageCount: Int,
        useAsync: Bool,
        aspectRatio: MediaGeneratorAspectRatio,
        resolution: MediaGeneratorResolution,
        outputFormat: MediaGeneratorOutputFormat
    ) -> [String: String] {
        var parameters = [
            "response_format": "url",
            "n": "\(imageCount)",
            "async": "\(useAsync)"
        ]
        switch modelID {
        case .nanoBananaPro:
            parameters["aspect_ratio"] = aspectRatio.rawValue
            parameters["resolution"] = resolution.rawValue
            parameters["output_format"] = outputFormat.rawValue
        case .gptImage2:
            parameters["aspect_ratio"] = aspectRatio.rawValue
            parameters["resolution"] = resolution.rawValue
        }
        return parameters
    }

    private func update(_ task: MediaGeneratorTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        persist(task)
    }

    private func addImageHistoryURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              parsed.scheme?.hasPrefix("http") == true
        else {
            return
        }
        imageHistory.removeAll { $0.url == trimmed }
        imageHistory.insert(MediaGeneratorImageHistoryItem(url: trimmed), at: 0)
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

    private static var supportedReferenceContentTypes: [UTType] {
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
        default:
            return [.png]
        }
    }

    private static func defaultAspectRatio(for modelID: MediaGeneratorModelID) -> MediaGeneratorAspectRatio {
        modelID == .gptImage2 ? .auto : .square
    }

    nonisolated static func supportedAspectRatios(for modelID: MediaGeneratorModelID) -> [MediaGeneratorAspectRatio] {
        switch modelID {
        case .nanoBananaPro:
            return [.square, .tall, .wide, .classicPortrait, .classicLandscape, .portrait, .vertical, .story, .landscape, .cinema, .auto]
        case .gptImage2:
            return [.auto, .square, .story, .landscape, .classicLandscape, .classicPortrait]
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
        }
    }

    nonisolated static func maxReferenceCount(for modelID: MediaGeneratorModelID) -> Int {
        switch modelID {
        case .nanoBananaPro:
            return 8
        case .gptImage2:
            return 16
        }
    }

    private static func supportedFields(for modelID: MediaGeneratorModelID) -> [String] {
        switch modelID {
        case .nanoBananaPro:
            ["model", "prompt", "n", "async", "response_format", "aspect_ratio", "resolution", "output_format", "image_input"]
        case .gptImage2:
            ["model", "prompt", "n", "async", "response_format", "aspect_ratio", "resolution", "image_input"]
        }
    }

    private static func supportedValuesPayload(for modelID: MediaGeneratorModelID) -> [String: Any] {
        var payload: [String: Any] = [
            "aspect_ratio": supportedAspectRatios(for: modelID).map(\.rawValue),
            "resolution": MediaGeneratorResolution.allCases.map(\.rawValue)
        ]
        if modelID == .nanoBananaPro {
            payload["output_format"] = MediaGeneratorOutputFormat.allCases.map(\.rawValue)
        }
        return payload
    }

    private static func defaultParameterPayload(for modelID: MediaGeneratorModelID) -> [String: Any] {
        var payload: [String: Any] = [
            "n": 1,
            "async": true,
            "response_format": "url",
            "aspect_ratio": defaultAspectRatio(for: modelID).rawValue
        ]
        switch modelID {
        case .nanoBananaPro:
            payload["resolution"] = MediaGeneratorResolution.oneK.rawValue
            payload["output_format"] = MediaGeneratorOutputFormat.png.rawValue
        case .gptImage2:
            payload["resolution"] = MediaGeneratorResolution.oneK.rawValue
        }
        return payload
    }

    func normalizeSelectionForCurrentModel() {
        let supportedRatios = Self.supportedAspectRatios(for: selectedModel)
        if !supportedRatios.contains(aspectRatio) {
            aspectRatio = Self.defaultAspectRatio(for: selectedModel)
        }
        let supportedResolutions = Self.supportedResolutions(for: selectedModel, aspectRatio: aspectRatio)
        if !supportedResolutions.contains(resolution) {
            resolution = supportedResolutions.first ?? .oneK
        }
        if references.count > Self.maxReferenceCount(for: selectedModel) {
            references = Array(references.prefix(Self.maxReferenceCount(for: selectedModel)))
            statusMessage = "\(selectedModel.title) accepts at most \(Self.maxReferenceCount(for: selectedModel)) references."
        }
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

    private static func validateImageCount(_ imageCount: Int) throws {
        guard imageCount == 1 else {
            throw MediaGeneratorError.invalidOption("Xenodia image generation currently supports only n=1.")
        }
    }

    private static func validateResponseFormat(_ value: Any?) throws {
        guard let value else {
            return
        }
        if let string = value as? String, string == "url" {
            return
        }
        throw MediaGeneratorError.invalidOption("Xenodia image generation currently supports only response_format=url.")
    }

    private static func validateUnsupportedModelArgs(modelID: MediaGeneratorModelID, args: [String: Any]) throws {
        guard modelID == .gptImage2 else {
            return
        }
        if args["output_format"] != nil {
            throw MediaGeneratorError.invalidOption("GPT Image-2 does not support output_format in the current Xenodia API.")
        }
        if args["nsfw_checker"] != nil {
            throw MediaGeneratorError.invalidOption("GPT Image-2 does not support nsfw_checker in the current Xenodia API.")
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

    private static func validateReferences(modelID: MediaGeneratorModelID, _ references: [MediaGeneratorReference]) throws {
        let maxCount = maxReferenceCount(for: modelID)
        guard references.count <= maxCount else {
            throw MediaGeneratorError.invalidReference("\(modelID.title) image_input accepts at most \(maxCount) total references.")
        }
        for reference in references {
            if let localPath = reference.localPath {
                try validateLocalReferenceFile(URL(fileURLWithPath: localPath))
            }
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
