import AppKit
import Foundation

enum PowerVideoManagerGearDescriptor {
    static let gearID = "power.video.manager"
}

enum PowerVideoManagerAssetKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case characterLook
    case storyboardGrid
    case firstFrame
    case shotVideo
    case finalVideo
    case editRender
    case diagnostic
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .characterLook: "Character Looks"
        case .storyboardGrid: "Storyboard Grids"
        case .firstFrame: "First Frames"
        case .shotVideo: "Shot Videos"
        case .finalVideo: "Final Outputs"
        case .editRender: "Edit Renders"
        case .diagnostic: "Diagnostics"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .characterLook: "person.crop.rectangle"
        case .storyboardGrid: "rectangle.grid.3x2"
        case .firstFrame: "photo"
        case .shotVideo: "film"
        case .finalVideo: "checkmark.seal"
        case .editRender: "slider.horizontal.3"
        case .diagnostic: "doc.text.magnifyingglass"
        case .other: "doc"
        }
    }
}

struct PowerVideoManagerCostSummary: Decodable, Hashable {
    struct Item: Decodable, Hashable {
        var kind: String?
        var path: String?
        var cost: Double?
    }

    var currency: String
    var total: Double?
    var items: [Item]

    enum CodingKeys: String, CodingKey {
        case currency
        case total
        case totalCost
        case totalRMB
        case total_rmb
        case items
    }

    init(currency: String, total: Double?, items: [Item]) {
        self.currency = currency
        self.total = total
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currency = (try? container.decode(String.self, forKey: .currency)) ?? "RMB"
        total = (try? container.decode(Double.self, forKey: .total))
            ?? (try? container.decode(Double.self, forKey: .totalCost))
            ?? (try? container.decode(Double.self, forKey: .totalRMB))
            ?? (try? container.decode(Double.self, forKey: .total_rmb))
        items = (try? container.decode([Item].self, forKey: .items)) ?? []
    }
}

private struct PowerVideoManagerRunState: Decodable {
    struct Script: Decodable {
        var id: String?
        var slug: String?
        var archivePath: String?
        var productionPromptsPath: String?
    }

    struct Topic: Decodable {
        var titleEn: String?
        var title: String?
    }

    struct VideoCandidate: Decodable {
        var shotNumber: Int?
        var localPath: String?
        var cost: Double?
        var status: String?
    }

    struct VideoCandidates: Decodable {
        var accepted: [VideoCandidate]?
        var completed: [VideoCandidate]?
    }

    struct AcceptedFirstFrame: Decodable {
        var shotNumber: Int?
        var localPath: String?
    }

    var script: Script?
    var topic: Topic?
    var status: String?
    var contentTemplateId: String?
    var productionMode: String?
    var productionRoute: String?
    var editingTemplate: String?
    var cropTemplate: String?
    var aspectRatio: String?
    var finalDeliveryAspect: String?
    var updatedAt: String?
    var acceptedFirstFrames: [AcceptedFirstFrame]?
    var videoCandidates: VideoCandidates?
}

private struct PowerVideoManagerProductionPromptsEnvelope: Decodable {
    struct Payload: Decodable {
        struct PromptShot: Decodable {
            var shotNumber: Int?
            var duration: Double?
            var prompt: String?
            var firstFrameCore: String?
        }

        var contentTemplateId: String?
        var productionMode: String?
        var productionRoute: String?
        var editingTemplate: String?
        var aspectRatio: String?
        var firstFramePrompts: [PromptShot]?
        var videoPrompts: [PromptShot]?
    }

    var resolvedAspectRatio: String?
    var productionPrompts: Payload?
}

struct PowerVideoManagerAsset: Identifiable, Hashable {
    var id: String { relativePath }
    var kind: PowerVideoManagerAssetKind
    var url: URL
    var relativePath: String
    var filename: String
    var fileSize: Int64
    var createdAt: Date?
    var updatedAt: Date
    var shotNumber: Int?
    var isSelected: Bool

    var isImage: Bool {
        ["png", "jpg", "jpeg", "webp", "gif"].contains(url.pathExtension.lowercased())
    }

    var isVideo: Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }
}

struct PowerVideoManagerShot: Identifiable, Hashable {
    var id: Int { shotNumber }
    var shotNumber: Int
    var summary: String?
    var firstFrames: [PowerVideoManagerAsset]
    var videos: [PowerVideoManagerAsset]
    var editRenders: [PowerVideoManagerAsset]
}

struct PowerVideoManagerProject: Identifiable, Hashable {
    var id: String { folderName }
    var folderName: String
    var url: URL
    var title: String
    var createdAt: Date?
    var updatedAt: Date
    var status: String?
    var score: String?
    var duration: String?
    var aspectRatio: String?
    var cost: PowerVideoManagerCostSummary?
    var assets: [PowerVideoManagerAsset]
    var shots: [PowerVideoManagerShot]
    var warnings: [String]

    var progressLabels: [String] {
        var labels: [String] = ["Script"]
        if assets.contains(where: { [.characterLook, .storyboardGrid, .firstFrame, .shotVideo].contains($0.kind) }) {
            labels.append("Production")
        }
        if assets.contains(where: { $0.kind == .editRender }) {
            labels.append("Editing")
        }
        if assets.contains(where: { $0.kind == .finalVideo }) {
            labels.append("Final")
        }
        return labels
    }

    func assets(kind: PowerVideoManagerAssetKind) -> [PowerVideoManagerAsset] {
        assets.filter { $0.kind == kind }
    }

    var primaryCharacterLook: PowerVideoManagerAsset? {
        let characterLooks = assets(kind: .characterLook)
        return characterLooks.first(where: \.isSelected)
            ?? characterLooks.first
    }
}

struct PowerVideoManagerWorkspaceIndex: Hashable {
    var rootURL: URL
    var scannedAt: Date
    var projects: [PowerVideoManagerProject]
}

struct PowerVideoManagerWorkspaceScanner {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan(rootURL: URL) throws -> PowerVideoManagerWorkspaceIndex {
        let entries = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )

        let projects = try entries.compactMap { entry -> PowerVideoManagerProject? in
            guard isDirectory(entry),
                  fileManager.fileExists(atPath: entry.appendingPathComponent("script/script-archive.md").path)
            else {
                return nil
            }
            return try scanProject(entry)
        }
        .sorted { $0.updatedAt > $1.updatedAt }

        return PowerVideoManagerWorkspaceIndex(rootURL: rootURL, scannedAt: Date(), projects: projects)
    }

    private func scanProject(_ projectURL: URL) throws -> PowerVideoManagerProject {
        let scriptURL = projectURL.appendingPathComponent("script/script-archive.md")
        let scriptText = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
        let runState = parseRunState(projectURL: projectURL)
        let productionPrompts = parseProductionPrompts(projectURL: projectURL, runState: runState)
        let selectedPaths = selectedAssetPaths(in: projectURL, runState: runState)
        let assets = try scanAssets(projectURL: projectURL, selectedPaths: selectedPaths)
        let folderValues = try? projectURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let updatedAt = maxDate([folderValues?.contentModificationDate] + assets.map(\.updatedAt)) ?? Date.distantPast
        let createdAt = folderValues?.creationDate ?? parseArchiveDate(scriptText)

        return PowerVideoManagerProject(
            folderName: projectURL.lastPathComponent,
            url: projectURL,
            title: parseTitle(scriptText)
                ?? runState?.topic?.titleEn
                ?? runState?.topic?.title
                ?? runState?.script?.slug
                ?? projectURL.lastPathComponent,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: runState?.status
                ?? parseHeaderValue("Status", from: scriptText)
                ?? runState?.productionMode
                ?? productionPrompts?.productionPrompts?.productionMode,
            score: parseHeaderValue("Score", from: scriptText),
            duration: durationSummary(from: productionPrompts)
                ?? parseHeaderValue("Duration", from: scriptText),
            aspectRatio: runState?.finalDeliveryAspect
                ?? runState?.aspectRatio
                ?? productionPrompts?.resolvedAspectRatio
                ?? productionPrompts?.productionPrompts?.aspectRatio
                ?? parseHeaderValue("Aspect Ratio", from: scriptText),
            cost: parseCostSummary(projectURL: projectURL, runState: runState),
            assets: assets,
            shots: buildShots(from: assets, scriptText: scriptText, productionPrompts: productionPrompts),
            warnings: []
        )
    }

    private func scanAssets(projectURL: URL, selectedPaths: Set<String>) throws -> [PowerVideoManagerAsset] {
        guard let enumerator = fileManager.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var assets: [PowerVideoManagerAsset] = []
        for case let url as URL in enumerator {
            guard isRegularFile(url) else { continue }
            let relativePath = self.relativePath(for: url, root: projectURL)
            let kind = classify(relativePath: relativePath, url: url)
            guard kind != .other else { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
            let updatedAt = values?.contentModificationDate ?? Date.distantPast
            assets.append(
                PowerVideoManagerAsset(
                    kind: kind,
                    url: url,
                    relativePath: relativePath,
                    filename: url.lastPathComponent,
                    fileSize: Int64(values?.fileSize ?? 0),
                    createdAt: values?.creationDate,
                    updatedAt: updatedAt,
                    shotNumber: parseShotNumber(relativePath),
                    isSelected: selectedPaths.contains(relativePath)
                )
            )
        }

        return assets.sorted {
            if $0.kind != $1.kind {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt < $1.updatedAt
            }
            return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private func classify(relativePath: String, url: URL) -> PowerVideoManagerAssetKind {
        let path = relativePath.lowercased()
        let ext = url.pathExtension.lowercased()
        let isImage = ["png", "jpg", "jpeg", "webp", "gif"].contains(ext)
        let isVideo = ["mp4", "mov", "m4v"].contains(ext)
        let isJSONOrMarkdown = ["json", "md"].contains(ext)

        if isImage && (path.contains("production/character-looks/") || path.contains("production/first-frames/character-")) {
            return .characterLook
        }
        if isImage && (
            path.contains("production/storyboard-grid/")
            || path.contains("production/storyboard-grids/")
            || path.contains("production/grid-split/")
            || path.contains("storyboard-grid-")
        ) {
            return .storyboardGrid
        }
        if isImage && (path.contains("production/first-frames/") || path.contains("production/first-frame-candidates")) {
            return .firstFrame
        }
        if isVideo && path.hasPrefix("production/") {
            return .shotVideo
        }
        if (isVideo || isImage) && path.hasPrefix("final/") {
            return .finalVideo
        }
        if (isVideo || isImage) && path.hasPrefix("editing/renders/") {
            return .editRender
        }
        if path.hasPrefix("production/video-review/") {
            return .diagnostic
        }
        if isJSONOrMarkdown && (
            path == "work-notes.md"
            || path == "run-state.json"
            || path.hasPrefix("editing/")
            || path.hasPrefix("production/")
            || path.hasPrefix("script/")
        ) {
            return .diagnostic
        }
        return .other
    }

    private func selectedAssetPaths(in projectURL: URL, runState: PowerVideoManagerRunState?) -> Set<String> {
        var paths = Set<String>()
        let productionSelectionURL = projectURL.appendingPathComponent("production/current-selection.json")
        let editingSelectionURL = projectURL.appendingPathComponent("editing/current-edit.json")

        for item in runState?.acceptedFirstFrames ?? [] {
            if let localPath = item.localPath {
                paths.insert(normalizedRelativePath(localPath, projectURL: projectURL))
            }
        }
        for item in runState?.videoCandidates?.accepted ?? [] {
            if let localPath = item.localPath {
                paths.insert(normalizedRelativePath(localPath, projectURL: projectURL))
            }
        }

        if let data = try? Data(contentsOf: productionSelectionURL),
           let selection = try? JSONDecoder().decode(ProductionSelection.self, from: data) {
            for item in selection.firstFrames + selection.videos {
                paths.insert(normalizedRelativePath(item.path, projectURL: projectURL))
            }
        }

        if let data = try? Data(contentsOf: editingSelectionURL),
           let selection = try? JSONDecoder().decode(EditSelection.self, from: data),
           let currentFinal = selection.currentFinal {
            paths.insert(normalizedRelativePath(currentFinal, projectURL: projectURL))
        }

        return paths
    }

    private func parseCostSummary(projectURL: URL, runState: PowerVideoManagerRunState?) -> PowerVideoManagerCostSummary? {
        let url = projectURL.appendingPathComponent("cost-summary.json")
        if let data = try? Data(contentsOf: url),
           let summary = try? JSONDecoder().decode(PowerVideoManagerCostSummary.self, from: data) {
            return summary
        }

        let accepted = runState?.videoCandidates?.accepted ?? []
        let items = accepted.compactMap { candidate -> PowerVideoManagerCostSummary.Item? in
            guard candidate.cost != nil || candidate.localPath != nil else { return nil }
            return PowerVideoManagerCostSummary.Item(kind: "video", path: candidate.localPath, cost: candidate.cost)
        }
        let total = items.compactMap(\.cost).reduce(0, +)
        guard !items.isEmpty else { return nil }
        return PowerVideoManagerCostSummary(currency: "RMB", total: total, items: items)
    }

    private func buildShots(
        from assets: [PowerVideoManagerAsset],
        scriptText: String,
        productionPrompts: PowerVideoManagerProductionPromptsEnvelope?
    ) -> [PowerVideoManagerShot] {
        let summaries = parseShotSummaries(scriptText)
            .merging(parsePromptShotSummaries(productionPrompts)) { existing, _ in existing }
        let promptShotNumbers = productionPrompts?.productionPrompts?.videoPrompts?.compactMap(\.shotNumber) ?? []
        let shotNumbers = Set(assets.compactMap(\.shotNumber))
            .union(summaries.keys)
            .union(promptShotNumbers)
        return shotNumbers.sorted().map { shotNumber in
            let shotAssets = assets.filter { $0.shotNumber == shotNumber }
            return PowerVideoManagerShot(
                shotNumber: shotNumber,
                summary: summaries[shotNumber],
                firstFrames: shotAssets.filter { $0.kind == .firstFrame },
                videos: shotAssets.filter { $0.kind == .shotVideo },
                editRenders: shotAssets.filter { $0.kind == .editRender }
            )
        }
    }

    private func parseShotSummaries(_ scriptText: String) -> [Int: String] {
        var summaries: [Int: String] = [:]
        let lines = scriptText.components(separatedBy: .newlines)
        var currentShot: Int?
        for line in lines {
            if let shot = firstIntegerMatch(in: line, pattern: #""shotNumber"\s*:\s*(\d+)"#) {
                currentShot = shot
            }
            if let shot = currentShot,
               summaries[shot] == nil,
               let lineText = firstStringMatch(in: line, pattern: #""lines"\s*:\s*"([^"]+)""#) {
                summaries[shot] = lineText
                currentShot = nil
            }
        }
        return summaries
    }

    private func parsePromptShotSummaries(_ envelope: PowerVideoManagerProductionPromptsEnvelope?) -> [Int: String] {
        var summaries: [Int: String] = [:]
        for shot in envelope?.productionPrompts?.videoPrompts ?? [] {
            guard let shotNumber = shot.shotNumber else { continue }
            summaries[shotNumber] = shot.prompt?.nilIfEmpty
                ?? shot.firstFrameCore?.nilIfEmpty
                ?? shot.duration.map { "Duration \(durationLabel($0))" }
        }
        for shot in envelope?.productionPrompts?.firstFramePrompts ?? [] where summaries[shot.shotNumber ?? -1] == nil {
            guard let shotNumber = shot.shotNumber else { continue }
            summaries[shotNumber] = shot.firstFrameCore?.nilIfEmpty ?? shot.prompt?.nilIfEmpty
        }
        return summaries
    }

    private func parseRunState(projectURL: URL) -> PowerVideoManagerRunState? {
        let url = projectURL.appendingPathComponent("run-state.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PowerVideoManagerRunState.self, from: data)
    }

    private func parseProductionPrompts(
        projectURL: URL,
        runState: PowerVideoManagerRunState?
    ) -> PowerVideoManagerProductionPromptsEnvelope? {
        let relativePath = runState?.script?.productionPromptsPath ?? "script/production-prompts.json"
        let url = projectURL.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PowerVideoManagerProductionPromptsEnvelope.self, from: data)
    }

    private func durationSummary(from envelope: PowerVideoManagerProductionPromptsEnvelope?) -> String? {
        let durations = envelope?.productionPrompts?.videoPrompts?.compactMap(\.duration) ?? []
        guard !durations.isEmpty else { return nil }
        return durationLabel(durations.reduce(0, +))
    }

    private func durationLabel(_ seconds: Double) -> String {
        let rounded = seconds.rounded()
        if abs(seconds - rounded) < 0.001 {
            return "\(Int(rounded)) seconds"
        }
        return String(format: "%.1f seconds", seconds)
    }

    private func parseTitle(_ text: String) -> String? {
        text.components(separatedBy: .newlines)
            .first { $0.hasPrefix("# ") }?
            .dropFirst(2)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func parseArchiveDate(_ text: String) -> Date? {
        parseHeaderValue("Generated At", from: text).flatMap(GeeAgentTimeFormatting.parseTimestamp)
    }

    private func parseHeaderValue(_ label: String, from text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let prefix = "> \(label):"
            guard line.hasPrefix(prefix) else { continue }
            return String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
        return nil
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func normalizedRelativePath(_ path: String, projectURL: URL) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectPath = projectURL.standardizedFileURL.path
        if trimmedPath.hasPrefix(projectPath + "/") {
            return String(trimmedPath.dropFirst(projectPath.count + 1))
        }
        return trimmedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
    }

    private func parseShotNumber(_ text: String) -> Int? {
        firstIntegerMatch(in: text, pattern: #"shot[-_](\d{1,4})"#)
    }

    private func firstIntegerMatch(in text: String, pattern: String) -> Int? {
        guard let match = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[range])
    }

    private func firstStringMatch(in text: String, pattern: String) -> String? {
        guard let match = try? NSRegularExpression(pattern: pattern, options: [])
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func maxDate(_ dates: [Date?]) -> Date? {
        dates.compactMap { $0 }.max()
    }
}

private struct SelectionItem: Codable {
    var shotNumber: Int?
    var path: String
}

private struct ProductionSelection: Codable {
    var firstFrames: [SelectionItem]
    var videos: [SelectionItem]

    enum CodingKeys: String, CodingKey {
        case firstFrames
        case videos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstFrames = (try? container.decode([SelectionItem].self, forKey: .firstFrames)) ?? []
        videos = (try? container.decode([SelectionItem].self, forKey: .videos)) ?? []
    }
}

private struct EditSelection: Codable {
    var currentFinal: String?
}

@MainActor
final class PowerVideoManagerGearStore: ObservableObject {
    static let shared = PowerVideoManagerGearStore()

    @Published var workspaceURL: URL?
    @Published var index: PowerVideoManagerWorkspaceIndex?
    @Published var selectedProjectID: PowerVideoManagerProject.ID?
    @Published var selectedTab: PowerVideoManagerDetailTab = .overview
    @Published var selectedAsset: PowerVideoManagerAsset?
    @Published var statusMessage = "Choose a runs workspace."
    @Published var isScanning = false

    private let scanner: PowerVideoManagerWorkspaceScanner

    init(scanner: PowerVideoManagerWorkspaceScanner = PowerVideoManagerWorkspaceScanner()) {
        self.scanner = scanner
    }

    var projects: [PowerVideoManagerProject] {
        index?.projects ?? []
    }

    var selectedProject: PowerVideoManagerProject? {
        guard let selectedProjectID else {
            return projects.first
        }
        return projects.first { $0.id == selectedProjectID } ?? projects.first
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Runs Folder"
        panel.message = "Choose a folder that contains AI video run project folders."
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        scanWorkspace(url)
    }

    func refresh() {
        guard let workspaceURL else {
            statusMessage = "Choose a runs workspace."
            return
        }
        scanWorkspace(workspaceURL)
    }

    func scanWorkspace(_ url: URL) {
        isScanning = true
        statusMessage = "Scanning \(url.lastPathComponent)..."
        do {
            let scanned = try scanner.scan(rootURL: url)
            workspaceURL = url
            index = scanned
            if let current = selectedProjectID, scanned.projects.contains(where: { $0.id == current }) {
                selectedProjectID = current
            } else {
                selectedProjectID = scanned.projects.first?.id
            }
            statusMessage = scanned.projects.isEmpty
                ? "No project folders with script/script-archive.md were found."
                : "Indexed \(scanned.projects.count) project\(scanned.projects.count == 1 ? "" : "s")."
        } catch {
            statusMessage = "Scan failed: \(error.localizedDescription)"
        }
        isScanning = false
    }
}

enum PowerVideoManagerDetailTab: String, CaseIterable, Identifiable {
    case overview
    case script
    case assets
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .script: "Script"
        case .assets: "Assets"
        case .timeline: "Timeline"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
