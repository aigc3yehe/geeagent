import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct HyperframesProject: Identifiable, Hashable {
    var id: String
    var name: String
    var url: URL
    var createdAt: Date
    var renderURLs: [URL]

    var indexURL: URL {
        url.appendingPathComponent("index.html")
    }

    var assetsURL: URL {
        url.appendingPathComponent("assets", isDirectory: true)
    }

    var rendersURL: URL {
        url.appendingPathComponent("renders", isDirectory: true)
    }
}

@MainActor
final class HyperframesStudioViewModel: ObservableObject {
    @Published private(set) var projects: [HyperframesProject] = []
    @Published var selectedProjectID: HyperframesProject.ID?
    @Published var status: String = "Ready"
    @Published var logText: String = ""
    @Published var isBusy = false
    @Published var timelineURL: URL?

    private let fileManager = FileManager.default
    private var previewProcess: Process?
    private var previewOutputPipe: Pipe?
    private var previewShimDirectory: URL?

    var selectedProject: HyperframesProject? {
        projects.first { $0.id == selectedProjectID }
    }

    init() {
        reloadProjects()
    }

    deinit {
        previewOutputPipe?.fileHandleForReading.readabilityHandler = nil
        previewProcess?.terminate()
    }

    func reloadProjects() {
        do {
            let root = try projectsRoot()
            let entries = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            projects = entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .compactMap(loadProject)
                .sorted { $0.createdAt > $1.createdAt }
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }
        } catch {
            status = "Could not load projects: \(error.localizedDescription)"
        }
    }

    func createProject() async {
        await runBusy("Creating project...") {
            let name = "Hyperframes \(Self.timestamp())"
            let slug = Self.slug(name)
            let projectURL = try projectsRoot().appendingPathComponent(slug, isDirectory: true)
            try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: projectURL.appendingPathComponent("assets", isDirectory: true), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: projectURL.appendingPathComponent("renders", isDirectory: true), withIntermediateDirectories: true)

            let meta = HyperframesProjectMeta(id: slug, name: name, createdAt: Date())
            let data = try JSONEncoder.geePretty.encode(meta)
            try data.write(to: projectURL.appendingPathComponent("meta.json"))
            try Self.blankCompositionHTML(title: name).write(to: projectURL.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

            reloadProjects()
            selectedProjectID = slug
            status = "Created \(name)."
        }
    }

    func importVideo() async {
        guard let project = selectedProject else {
            await createProject()
            return await importVideo()
        }

        guard let sourceURL = pickVideoFile() else {
            return
        }

        await runBusy("Importing video...") {
            let destination = project.assetsURL.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)

            let duration = await probeDuration(videoURL: destination) ?? 10
            let html = Self.videoCompositionHTML(videoFileName: destination.lastPathComponent, duration: duration)
            try html.write(to: project.indexURL, atomically: true, encoding: .utf8)

            reloadProjects()
            selectedProjectID = project.id
            status = "Imported \(sourceURL.lastPathComponent)."
        }
    }

    func openTimeline() async {
        guard let project = selectedProject else {
            status = "Create or select a project first."
            return
        }

        stopPreview()
        let port = 3002
        let projectName = project.url.lastPathComponent
        do {
            let shimDirectory = try makeBrowserOpenShim()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [
                "-lc",
                "hyperframes preview --port \(port) --force-new \(Self.shellQuote(project.url.path))"
            ]
            process.currentDirectoryURL = project.url
            process.environment = Self.processEnvironment(openShimDirectory: shimDirectory)

            let pipe = Pipe()
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.consumePreviewOutput(text, projectName: projectName)
                }
            }
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { [weak self, weak process] _ in
                Task { @MainActor [weak self, weak process] in
                    guard let self, let process, self.previewProcess === process else {
                        return
                    }
                    self.previewOutputPipe?.fileHandleForReading.readabilityHandler = nil
                    self.previewOutputPipe = nil
                    self.previewProcess = nil
                    self.timelineURL = nil
                    self.status = "Timeline server stopped."
                }
            }
            try process.run()
            previewProcess = process
            previewOutputPipe = pipe
            previewShimDirectory = shimDirectory
            status = "Starting timeline in GeeAgent..."

            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if timelineURL == nil, let url = Self.timelineURL(port: port, projectName: projectName) {
                timelineURL = url
                status = "Timeline ready in GeeAgent."
            }
        } catch {
            status = "Could not start timeline: \(error.localizedDescription)"
        }
    }

    func closeTimeline() {
        stopPreview()
        status = "Timeline stopped."
    }

    func render() async {
        guard let project = selectedProject else {
            status = "Create or select a project first."
            return
        }

        await runBusy("Rendering...") {
            let output = project.rendersURL.appendingPathComponent("\(project.id)-\(Self.timestamp()).mp4")
            let result = await Self.runShell(
                "hyperframes render --output \(Self.shellQuote(output.path)) --fps 30 --quality standard",
                cwd: project.url
            )
            logText = result.combinedOutput
            guard result.exitCode == 0 else {
                status = "Render failed."
                return
            }
            reloadProjects()
            selectedProjectID = project.id
            status = "Rendered \(output.lastPathComponent)."
        }
    }

    func revealSelectedProject() {
        guard let project = selectedProject else { return }
        NSWorkspace.shared.activateFileViewerSelecting([project.url])
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func runBusy(_ busyStatus: String, operation: () async throws -> Void) async {
        isBusy = true
        status = busyStatus
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            status = error.localizedDescription
        }
    }

    private func pickVideoFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie, .video]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func loadProject(_ url: URL) -> HyperframesProject? {
        let metaURL = url.appendingPathComponent("meta.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meta = (try? Data(contentsOf: metaURL))
            .flatMap { try? decoder.decode(HyperframesProjectMeta.self, from: $0) }

        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        let renderURLs = ((try? fileManager.contentsOfDirectory(
            at: url.appendingPathComponent("renders", isDirectory: true),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { ["mp4", "mov", "webm"].contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }

        return HyperframesProject(
            id: meta?.id ?? url.lastPathComponent,
            name: meta?.name ?? url.lastPathComponent,
            url: url,
            createdAt: meta?.createdAt ?? values?.creationDate ?? .distantPast,
            renderURLs: renderURLs
        )
    }

    private func projectsRoot() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let geeRoot = support.appendingPathComponent("GeeAgent", isDirectory: true)
        let root = support
            .appendingPathComponent("GeeAgent/gear-data/hyperframes.studio/projects", isDirectory: true)
        try migrateLegacyProjectsIfNeeded(geeRoot: geeRoot, newRoot: root)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func migrateLegacyProjectsIfNeeded(geeRoot: URL, newRoot: URL) throws {
        let legacyPackageRoot = geeRoot.appendingPathComponent("gears/hyperframes.studio", isDirectory: true)
        let legacyProjectsRoot = legacyPackageRoot.appendingPathComponent("projects", isDirectory: true)
        guard fileManager.fileExists(atPath: legacyProjectsRoot.path) else {
            return
        }

        try fileManager.createDirectory(at: newRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: newRoot.path) {
            try fileManager.moveItem(at: legacyProjectsRoot, to: newRoot)
        } else {
            let legacyProjects = try fileManager.contentsOfDirectory(
                at: legacyProjectsRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for projectURL in legacyProjects {
                let destination = uniqueDestination(
                    for: newRoot.appendingPathComponent(projectURL.lastPathComponent, isDirectory: true)
                )
                try fileManager.moveItem(at: projectURL, to: destination)
            }
            try? fileManager.removeItem(at: legacyProjectsRoot)
        }

        let legacyManifest = legacyPackageRoot.appendingPathComponent("gear.json")
        let remaining = (try? fileManager.contentsOfDirectory(
            at: legacyPackageRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        if !fileManager.fileExists(atPath: legacyManifest.path), remaining.isEmpty {
            try? fileManager.removeItem(at: legacyPackageRoot)
        }
    }

    private func uniqueDestination(for proposedURL: URL) -> URL {
        guard fileManager.fileExists(atPath: proposedURL.path) else {
            return proposedURL
        }

        let parent = proposedURL.deletingLastPathComponent()
        let baseName = proposedURL.lastPathComponent
        for index in 1...999 {
            let candidate = parent.appendingPathComponent("\(baseName)-migrated-\(index)", isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return parent.appendingPathComponent("\(baseName)-migrated-\(UUID().uuidString)", isDirectory: true)
    }

    private func probeDuration(videoURL: URL) async -> Double? {
        let result = await Self.runShell(
            "ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 \(Self.shellQuote(videoURL.path))",
            cwd: videoURL.deletingLastPathComponent()
        )
        return Double(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func stopPreview() {
        previewOutputPipe?.fileHandleForReading.readabilityHandler = nil
        previewOutputPipe = nil
        previewProcess?.terminate()
        previewProcess = nil
        timelineURL = nil
        previewShimDirectory = nil
    }

    private static func runShell(_ command: String, cwd: URL) async -> GearCommandResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = cwd
            process.environment = processEnvironment(openShimDirectory: nil)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return GearCommandResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
            }

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return GearCommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
        }.value
    }

    private func consumePreviewOutput(_ text: String, projectName: String) {
        if let url = Self.timelineURL(from: text, projectName: projectName) {
            timelineURL = url
            status = "Timeline ready in GeeAgent."
        }
    }

    private func makeBrowserOpenShim() throws -> URL {
        let root = try gearDataRoot()
            .appendingPathComponent("runtime/browser-open-shim", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let shim = root.appendingPathComponent("open")
        let script = """
        #!/bin/sh
        # GeeAgent embeds Hyperframes Studio in WKWebView, so CLI browser opens are intentionally ignored.
        exit 0
        """
        try script.write(to: shim, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        return root
    }

    private func gearDataRoot() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support.appendingPathComponent("GeeAgent/gear-data/hyperframes.studio", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    nonisolated private static func processEnvironment(openShimDirectory: URL?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HYPERFRAMES_NO_UPDATE_CHECK"] = "1"
        environment["CI"] = environment["CI"] ?? "1"
        environment["BROWSER"] = "/usr/bin/false"
        environment["NO_BROWSER"] = "1"
        environment["OPEN_BROWSER"] = "0"
        environment["npm_config_browser"] = "false"
        let commonPaths: [String?] = [
            openShimDirectory?.path(percentEncoded: false),
            environment["PATH"],
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

    nonisolated private static func timelineURL(from text: String, projectName: String) -> URL? {
        let pattern = #"Studio\s+(http://(?:localhost|127\.0\.0\.1):(\d+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 3,
              let portRange = Range(match.range(at: 2), in: text),
              let port = Int(text[portRange])
        else {
            return nil
        }
        return timelineURL(port: port, projectName: projectName)
    }

    nonisolated private static func timelineURL(port: Int, projectName: String) -> URL? {
        let encodedProject = projectName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectName
        return URL(string: "http://127.0.0.1:\(port)#project/\(encodedProject)")
    }

    private static func blankCompositionHTML(title: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <style>
            html, body { margin: 0; width: 100%; height: 100%; background: #101216; overflow: hidden; }
            [data-composition-id="root"] { position: relative; width: 1920px; height: 1080px; color: white; font-family: Inter, -apple-system, BlinkMacSystemFont, sans-serif; }
            #title { position: absolute; inset: 0; display: grid; place-items: center; font-size: 86px; letter-spacing: 0; }
          </style>
        </head>
        <body>
          <div id="root" data-composition-id="root" data-start="0" data-width="1920" data-height="1080">
            <h1 id="title" class="clip" data-start="0" data-duration="5" data-track-index="0">\(escapeHTML(title))</h1>
            <script src="https://cdn.jsdelivr.net/npm/gsap@3/dist/gsap.min.js"></script>
            <script>
              window.__timelines = window.__timelines || {};
              const tl = gsap.timeline({ paused: true });
              tl.from("#title", { opacity: 0, y: 42, duration: 0.8 }, 0);
              tl.to("#title", { opacity: 0, y: -28, duration: 0.6 }, 4.3);
              tl.set({}, {}, 5);
              window.__timelines["root"] = tl;
            </script>
          </div>
        </body>
        </html>
        """
    }

    private static func videoCompositionHTML(videoFileName: String, duration: Double) -> String {
        let durationText = String(format: "%.3f", duration)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <style>
            html, body { margin: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
            [data-composition-id="root"] { position: relative; width: 1920px; height: 1080px; background: #000; }
            #source-video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain; }
          </style>
        </head>
        <body>
          <div id="root" data-composition-id="root" data-start="0" data-width="1920" data-height="1080">
            <video id="source-video" class="clip" data-start="0" data-duration="\(durationText)" data-track-index="0" data-media-start="0" data-volume="1" data-has-audio="true" src="./assets/\(escapeAttribute(videoFileName))"></video>
            <script src="https://cdn.jsdelivr.net/npm/gsap@3/dist/gsap.min.js"></script>
            <script>
              window.__timelines = window.__timelines || {};
              const tl = gsap.timeline({ paused: true });
              tl.set({}, {}, \(durationText));
              window.__timelines["root"] = tl;
            </script>
          </div>
        </body>
        </html>
        """
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let dashed = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(dashed).split(separator: "-").joined(separator: "-")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeHTML(value).replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private struct HyperframesProjectMeta: Codable {
    var id: String
    var name: String
    var createdAt: Date
}

private extension JSONEncoder {
    static var geePretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
