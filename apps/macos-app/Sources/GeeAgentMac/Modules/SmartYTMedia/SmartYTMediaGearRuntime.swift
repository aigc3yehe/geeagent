import AppKit
import Foundation

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

    private static func orientation(width: Int?, height: Int?) -> String? {
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
    var log: String
    var errorMessage: String?

    var outputURLs: [URL] {
        outputPaths.map { URL(fileURLWithPath: $0) }
    }

    var transcriptURL: URL? {
        transcriptPath.map { URL(fileURLWithPath: $0) }
    }
}

enum SmartYTMediaError: LocalizedError {
    case invalidURL
    case invalidMetadata(String)
    case commandFailed(command: String, detail: String)
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
        case let .missingArtifact(message):
            message
        case let .transcriptionUnavailable(message):
            message
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

    private let runner: GearCommandRunning
    private let fileManager: FileManager

    var selectedJob: SmartYTMediaJob? {
        jobs.first { $0.id == selectedJobID } ?? jobs.first
    }

    init(
        runner: GearCommandRunning = GearShellCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.fileManager = fileManager
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
                        startingIndex: candidates.count
                    )
                    candidates.append(contentsOf: results)
                } catch {
                    warnings.append("youtube search failed: \(error.localizedDescription)")
                }
            case "bilibili", "douyin", "xiaohongshu":
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
            let info = try await sniff(url: cleanURL)
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

    func enqueueAgentAction(
        capabilityID: String,
        url: String,
        downloadKind: SmartYTDownloadKind?,
        language: String?,
        outputDirectory: String?
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
            outputDirectory: outputDirectory
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
        outputDirectory: String?
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
            let info = try? await sniff(url: cleanURL)
            let outputs = try await download(url: cleanURL, kind: kind, into: jobRoot)
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
                error: error.localizedDescription
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
        outputDirectory: String?
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
            log: "Queued \(action.rawValue) for \(url)",
            errorMessage: nil
        )
        jobs.insert(job, at: 0)
        selectedJobID = job.id
        statusMessage = "\(action.title) queued."
        persist(job)

        Task { [weak self] in
            await self?.run(jobID: job.id, language: language)
        }
        return job
    }

    private func agentPayload(
        capabilityID: String,
        job: SmartYTMediaJob,
        status: String,
        outputPaths: [String],
        error: String? = nil,
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

    private func run(jobID: String, language: String?) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else {
            return
        }

        updateJob(jobID) { current in
            current.status = .running
            current.updatedAt = Date()
            current.log.append("\nStarted at \(Date().formatted()).")
        }
        isBusy = true
        defer { isBusy = jobs.contains { $0.status == .running || $0.status == .queued } }

        do {
            let jobRoot = try ensureArtifactDirectory(for: job)
            switch job.action {
            case .sniff:
                let info = try await sniff(url: job.url)
                mediaInfo = info
                updateJob(jobID) { current in
                    current.mediaInfo = info
                    current.title = info.title
                    current.status = .completed
                    current.updatedAt = Date()
                    current.log.append("\nMetadata extracted.")
                }
                statusMessage = "Sniffed \(info.title)."
            case .download:
                let outputs = try await download(url: job.url, kind: job.downloadKind, into: jobRoot)
                updateJob(jobID) { current in
                    current.outputPaths = outputs.map(\.path)
                    current.status = .completed
                    current.updatedAt = Date()
                    current.log.append("\nDownloaded \(outputs.count) artifact(s).")
                }
                statusMessage = "Download completed."
            case .transcribe:
                let result = try await transcribe(url: job.url, language: language, into: jobRoot)
                updateJob(jobID) { current in
                    current.outputPaths = result.artifacts.map(\.path)
                    current.transcriptPath = result.transcriptURL.path
                    current.transcriptPreview = Self.preview(result.text)
                    current.status = .completed
                    current.updatedAt = Date()
                    current.log.append("\nTranscript created via \(result.source).")
                }
                statusMessage = "Transcript completed."
            }
        } catch {
            updateJob(jobID) { current in
                current.status = .failed
                current.errorMessage = error.localizedDescription
                current.updatedAt = Date()
                current.log.append("\nFailed: \(error.localizedDescription)")
            }
            statusMessage = error.localizedDescription
        }

        if let updated = jobs.first(where: { $0.id == jobID }) {
            persist(updated)
        }
    }

    private func sniff(url: String) async throws -> SmartYTMediaInfo {
        let result = await runner.run(
            "yt-dlp",
            arguments: [
                "--dump-single-json",
                "--no-warnings",
                "--skip-download",
                url
            ],
            timeoutSeconds: 90
        )
        guard result.exitCode == 0 else {
            throw SmartYTMediaError.commandFailed(command: "yt-dlp --dump-single-json", detail: result.combinedOutput)
        }
        return try SmartYTMediaInfo.parse(from: result.stdout, fallbackURL: url)
    }

    private func searchYouTubeCandidates(
        query: String,
        limit: Int,
        taskID: String,
        startingIndex: Int
    ) async throws -> [SmartYTSearchCandidate] {
        let result = await runner.run(
            "yt-dlp",
            arguments: [
                "--dump-json",
                "--no-warnings",
                "--skip-download",
                "ytsearch\(limit):\(query)"
            ],
            timeoutSeconds: 120
        )
        guard result.exitCode == 0 else {
            throw SmartYTMediaError.commandFailed(command: "yt-dlp ytsearch", detail: result.combinedOutput)
        }
        return SmartYTSearchCandidate.parseYTDLPJSONLines(
            result.stdout,
            platform: "youtube",
            taskID: taskID,
            startingIndex: startingIndex
        )
    }

    private func download(url: String, kind: SmartYTDownloadKind, into directory: URL) async throws -> [URL] {
        if Self.isDirectImageURL(url) {
            switch kind {
            case .audio:
                throw SmartYTMediaError.missingArtifact("Image URL cannot be downloaded as audio.")
            case .image, .video, .both:
                return [try await downloadImage(url: url, into: directory)]
            }
        }
        var outputs: [URL] = []
        switch kind {
        case .audio:
            outputs.append(try await downloadAudio(url: url, into: directory))
        case .image:
            outputs.append(try await downloadImage(url: url, into: directory))
        case .video:
            outputs.append(try await downloadVideo(url: url, into: directory))
        case .both:
            outputs.append(try await downloadVideo(url: url, into: directory))
            outputs.append(try await downloadAudio(url: url, into: directory))
        }
        return outputs
    }

    private func transcribe(url: String, language: String?, into directory: URL) async throws -> SmartYTTranscriptionResult {
        if let subtitle = try await extractSubtitle(url: url, language: language, into: directory) {
            return subtitle
        }

        let audioURL = try await downloadAudio(url: url, into: directory)
        guard let whisperCommand = await findWhisperCommand() else {
            throw SmartYTMediaError.transcriptionUnavailable(
                "No platform subtitles were found, and no local Whisper CLI was detected. Install `whisper` or provide a future STT provider to convert downloaded audio to text."
            )
        }

        let transcriptURL = directory.appendingPathComponent("transcript.txt")
        let result: GearCommandResult
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
            result = await runner.run("whisper", arguments: args, timeoutSeconds: nil)
            if !fileManager.fileExists(atPath: transcriptURL.path),
               let generated = firstFile(in: directory, extensions: ["txt"])
            {
                try? fileManager.copyItem(at: generated, to: transcriptURL)
            }
        default:
            result = await runner.run(
                whisperCommand,
                arguments: [
                    "-f", audioURL.path,
                    "-otxt",
                    "-of", directory.appendingPathComponent("transcript").path
                ],
                timeoutSeconds: nil
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

    private func extractSubtitle(url: String, language: String?, into directory: URL) async throws -> SmartYTTranscriptionResult? {
        let template = directory.appendingPathComponent("subtitle.%(ext)s").path
        let languageList = subtitleLanguageList(preferred: language)
        let result = await runner.run(
            "yt-dlp",
            arguments: [
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

    private func downloadAudio(url: String, into directory: URL) async throws -> URL {
        let template = directory.appendingPathComponent("audio.%(ext)s").path
        let result = await runner.run(
            "yt-dlp",
            arguments: [
                "-x",
                "--audio-format", "mp3",
                "--audio-quality", "0",
                "--no-playlist",
                "-o", template,
                url
            ],
            timeoutSeconds: nil
        )
        guard result.exitCode == 0 else {
            throw SmartYTMediaError.commandFailed(command: "yt-dlp audio download", detail: result.combinedOutput)
        }
        guard let output = firstFile(in: directory, extensions: ["mp3", "m4a", "wav", "aac", "opus"]) else {
            throw SmartYTMediaError.missingArtifact("Audio download finished but no audio artifact was found.")
        }
        return output
    }

    private func downloadVideo(url: String, into directory: URL) async throws -> URL {
        let template = directory.appendingPathComponent("video.%(ext)s").path
        let result = await runner.run(
            "yt-dlp",
            arguments: [
                "-f", "bv*+ba/best",
                "--merge-output-format", "mp4",
                "--no-playlist",
                "-o", template,
                url
            ],
            timeoutSeconds: nil
        )
        guard result.exitCode == 0 else {
            throw SmartYTMediaError.commandFailed(command: "yt-dlp video download", detail: result.combinedOutput)
        }
        guard let output = firstFile(in: directory, extensions: ["mp4", "mov", "mkv", "webm"]) else {
            throw SmartYTMediaError.missingArtifact("Video download finished but no video artifact was found.")
        }
        return output
    }

    private func downloadImage(url: String, into directory: URL) async throws -> URL {
        guard let sourceURL = URL(string: url) else {
            throw SmartYTMediaError.invalidURL
        }
        var request = URLRequest(url: sourceURL)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
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

    private func updateJob(_ id: String, mutate: (inout SmartYTMediaJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&jobs[index])
        persist(jobs[index])
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
        [
            "gear_id": SmartYTMediaGearDescriptor.gearID,
            "capability_id": "smartyt.search_candidates",
            "status": task.status,
            "search_task_id": task.id,
            "task_id": task.id,
            "candidates": task.candidates.map(candidatePayload),
            "warnings": task.warnings,
            "error": task.error ?? NSNull()
        ]
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
        [
            "task_id": job.id,
            "job_id": job.id,
            "kind": job.action.rawValue,
            "state": job.status.rawValue,
            "source_url": job.url,
            "download_kind": job.downloadKind.rawValue,
            "output_files": job.outputPaths.map { ["path": $0] },
            "artifact_root": artifactDirectory(for: job).path,
            "created_at": Self.iso8601(job.createdAt),
            "updated_at": Self.iso8601(job.updatedAt),
            "error": job.errorMessage ?? NSNull()
        ]
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

    private static func normalizedPlatform(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "youtube.com", with: "youtube")
    }

    private static func stringArg(_ args: [String: Any], _ key: String) -> String? {
        args[key] as? String
    }

    private static func stringArrayArg(_ args: [String: Any], _ key: String) -> [String]? {
        args[key] as? [String]
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
}

private struct SmartYTTranscriptionResult {
    var text: String
    var transcriptURL: URL
    var artifacts: [URL]
    var source: String
}
