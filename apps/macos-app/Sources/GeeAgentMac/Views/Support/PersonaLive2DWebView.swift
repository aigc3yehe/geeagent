import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// WKWebView that renders the active persona's Live2D bundle on the home hero.
///
/// Design contract:
/// - **Interactive canvas.** Native Home controls sit above it, while open hero-space clicks can
///   still reach the Live2D host and the companion interaction surface.
/// - **Pauses on home-invisibility.** When `isActive` flips to `false` (the user navigated away
///   from the home surface), we message the host page to stop its RAF loop. Reactivating the
///   home surface resumes the loop.
/// - **Per-bundle reload.** Changing `bundlePath` reloads the host with a new `geeLive2DConfig`
///   so switching personas doesn't leak animation frames from the previous one.
struct PersonaLive2DWebView: NSViewRepresentable {
    var bundlePath: String
    var isActive: Bool
    var playbackRequest: Live2DMotionPlaybackRequest?
    var viewportState: Live2DViewportState
    var idlePosePath: String?
    var expressionPath: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: Coordinator.modelScheme)

        // Inject the model URL + debug flags before any page script runs.
        let script = WKUserScript(
            source: Coordinator.configurationScript(for: bundlePath),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(script)
        configuration.userContentController = contentController
        configuration.suppressesIncrementalRendering = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.isHidden = false
        webView.wantsLayer = true
        webView.layer?.backgroundColor = .clear

        context.coordinator.webView = webView
        context.coordinator.configure(
            bundlePath: bundlePath,
            isActive: isActive,
            playbackRequest: playbackRequest,
            viewportState: viewportState,
            idlePosePath: idlePosePath,
            expressionPath: expressionPath
        )
        context.coordinator.registerAppLifecycleObservers()
        context.coordinator.loadHostPage()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            bundlePath: bundlePath,
            isActive: isActive,
            playbackRequest: playbackRequest,
            viewportState: viewportState,
            idlePosePath: idlePosePath,
            expressionPath: expressionPath
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKURLSchemeHandler {
        nonisolated static let modelScheme = "geeagent-live2d"
        nonisolated static let appHost = "app"
        nonisolated static let hostRootComponent = "host"
        nonisolated static let personaRootComponent = "persona"

        weak var webView: WKWebView?
        private(set) var currentBundlePath: String = ""
        private(set) var isActive: Bool = false
        private var didLoadHost: Bool = false
        private var pendingPlaybackRequest: Live2DMotionPlaybackRequest?
        private var lastAppliedPlaybackRequestID: String?
        private var pendingViewportState: Live2DViewportState = .default
        private var lastAppliedViewportState: Live2DViewportState?
        private var pendingIdlePosePath: String?
        private var lastAppliedIdlePosePath: String?
        private var pendingExpressionPath: String?
        private var lastAppliedExpressionPath: String?

        func configure(
            bundlePath: String,
            isActive: Bool,
            playbackRequest: Live2DMotionPlaybackRequest?,
            viewportState: Live2DViewportState,
            idlePosePath: String?,
            expressionPath: String?
        ) {
            self.currentBundlePath = bundlePath
            self.isActive = isActive
            self.pendingPlaybackRequest = playbackRequest
            self.pendingViewportState = viewportState
            self.pendingIdlePosePath = idlePosePath
            self.pendingExpressionPath = expressionPath
        }

        func loadHostPage() {
            guard let webView else { return }
            guard Self.stagedHostIndex() != nil,
                  let hostURL = Self.hostPageURL()
            else {
                // Nothing to load — the fallback silhouette is drawn by app.js only when
                // resources are shipped. The abstract scene sits behind us as a safety net.
                return
            }
            webView.load(URLRequest(url: hostURL))
            didLoadHost = true
        }

        func update(
            bundlePath: String,
            isActive: Bool,
            playbackRequest: Live2DMotionPlaybackRequest?,
            viewportState: Live2DViewportState,
            idlePosePath: String?,
            expressionPath: String?
        ) {
            let bundleChanged = bundlePath != currentBundlePath
            currentBundlePath = bundlePath
            self.isActive = isActive
            self.pendingPlaybackRequest = playbackRequest
            self.pendingViewportState = viewportState
            self.pendingIdlePosePath = idlePosePath
            self.pendingExpressionPath = expressionPath

            if bundleChanged {
                reloadWithNewBundle()
            } else {
                applyPlaybackState()
                applyViewportIfNeeded()
                applyIdlePoseIfNeeded()
                applyExpressionIfNeeded()
                applyPlaybackRequestIfNeeded()
            }
        }

        func registerAppLifecycleObservers() {
            // Intentionally no-op. GeeAgent keeps decorative Live2D motion running even when the
            // app loses focus so the home surface feels alive during multitasking.
        }

        func tearDown() {
            webView?.evaluateJavaScript("window.geeLive2D?.stop?.()", completionHandler: nil)
        }

        // MARK: Playback

        private func applyPlaybackState() {
            let shouldPlay = isActive
            let js = shouldPlay ? "window.geeLive2D?.resume?.()" : "window.geeLive2D?.pause?.()"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        private func applyViewportIfNeeded() {
            guard let webView else { return }
            guard pendingViewportState != lastAppliedViewportState else { return }
            guard
                let data = try? JSONEncoder().encode(pendingViewportState),
                let json = String(data: data, encoding: .utf8)
            else {
                return
            }

            lastAppliedViewportState = pendingViewportState
            let js = """
            (async function() {
              const viewport = \(json);
              return await window.geeLive2D?.setViewport?.(viewport);
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func applyIdlePoseIfNeeded() {
            guard let webView else { return }
            guard pendingIdlePosePath != lastAppliedIdlePosePath else { return }

            let idlePoseValue = pendingIdlePosePath.map(Self.javascriptStringLiteral) ?? "null"
            lastAppliedIdlePosePath = pendingIdlePosePath
            let js = """
            (async function() {
              return await window.geeLive2D?.setPose?.(\(idlePoseValue));
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func applyExpressionIfNeeded() {
            guard let webView else { return }
            guard pendingExpressionPath != lastAppliedExpressionPath else { return }

            let expressionValue = pendingExpressionPath.map(Self.javascriptStringLiteral) ?? "null"
            lastAppliedExpressionPath = pendingExpressionPath
            let js = """
            (async function() {
              return await window.geeLive2D?.setExpression?.(\(expressionValue));
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func applyPlaybackRequestIfNeeded() {
            guard let webView, let request = pendingPlaybackRequest else { return }
            guard request.requestID != lastAppliedPlaybackRequestID else { return }
            guard request.bundlePath == URL(fileURLWithPath: currentBundlePath).standardizedFileURL.path else { return }

            let payload: [String: Any] = [
                "path": request.motion.relativePath,
                "title": request.motion.title,
            ]
            guard
                let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                let json = String(data: data, encoding: .utf8)
            else {
                return
            }

            lastAppliedPlaybackRequestID = request.requestID
            let js = """
            (async function() {
              const motion = \(json);
              return await window.geeLive2D?.playMotion?.(motion.path, motion.title);
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func reloadWithNewBundle() {
            guard let webView else { return }
            let script = WKUserScript(
                source: Self.configurationScript(for: currentBundlePath),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            let controller = webView.configuration.userContentController
            controller.removeAllUserScripts()
            controller.addUserScript(script)
            loadHostPage()
            // Playback state is re-applied once the page finishes loading.
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyPlaybackState()
            applyViewportIfNeeded()
            applyIdlePoseIfNeeded()
            applyExpressionIfNeeded()
            applyPlaybackRequestIfNeeded()
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard let requestURL = urlSchemeTask.request.url,
                  let fileURL = Self.resolveServedFileURL(from: requestURL),
                  let data = try? Data(contentsOf: fileURL)
            else {
                urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
                return
            }

            let mimeType = Self.mimeType(for: fileURL)
            let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mimeType,
                    "Access-Control-Allow-Origin": "*",
                    "Cache-Control": "no-store",
                ]
            ) ?? URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

        // MARK: - Helpers

        nonisolated static func configurationScript(for bundlePath: String) -> String {
            // We serialize the bundlePath through JSONEncoder-equivalent escaping by round-tripping
            // through JSONSerialization to be safe against backslashes/quotes in filesystem paths.
            // `modelUrl` is expressed relative to the staged `Live2DHost/` directory whenever
            // possible so WKWebView treats the model bundle as same-tree local content.
            // `modelPath` stays as the raw POSIX path for code that wants it.
            let modelURLString = modelResourceURLString(for: bundlePath)
            let payload: [String: Any] = [
                "modelUrl": modelURLString,
                "modelPath": bundlePath,
                "debug": false,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  let json = String(data: data, encoding: .utf8)
            else {
                return "window.geeLive2DConfig = { modelUrl: \"\", modelPath: \"\", debug: false };"
            }
            return "window.geeLive2DConfig = \(json);"
        }

        nonisolated static func javascriptStringLiteral(_ value: String) -> String {
            guard
                let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
                var json = String(data: data, encoding: .utf8)
            else {
                return "\"\""
            }
            json.removeFirst()
            json.removeLast()
            return json
        }

        nonisolated static func modelResourceURLString(for bundlePath: String) -> String {
            guard !bundlePath.isEmpty else { return "" }
            let modelURL = URL(fileURLWithPath: bundlePath).standardizedFileURL
            if let relativeComponents = personaRelativePathComponents(for: modelURL) {
                let encodedPath = relativeComponents
                    .map { segment in
                        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? segment
                    }
                    .joined(separator: "/")
                return "\(modelScheme)://\(appHost)/\(personaRootComponent)/\(encodedPath)"
            }
            return modelURL.absoluteString
        }

        nonisolated private static func hostPageURL() -> URL? {
            URL(string: "\(modelScheme)://\(appHost)/\(hostRootComponent)/index.html")
        }

        nonisolated static func previewImageDataURL(for bundlePath: String) -> String? {
            guard !bundlePath.isEmpty else { return nil }
            let modelURL = URL(fileURLWithPath: bundlePath)
            let bundleDir = modelURL.deletingLastPathComponent()

            let candidates = iconImageCandidates(in: bundleDir)
            for candidate in candidates {
                if let dataURL = dataURLForImage(at: candidate) {
                    return dataURL
                }
            }
            return nil
        }

        nonisolated private static func iconImageCandidates(in directory: URL) -> [URL] {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            let preferred = ["icon.jpg", "icon.jpeg", "icon.png", "icon.webp"]
            var lookup: [String: URL] = [:]
            for entry in entries {
                lookup[entry.lastPathComponent.lowercased()] = entry
            }

            var ordered: [URL] = preferred.compactMap { lookup[$0] }
            ordered.append(contentsOf: entries.filter { entry in
                let name = entry.lastPathComponent.lowercased()
                return name.hasPrefix("icon.") && !preferred.contains(name)
            })
            return ordered
        }

        nonisolated private static func dataURLForImage(at url: URL) -> String? {
            let ext = url.pathExtension.lowercased()
            let mimeType: String
            switch ext {
            case "jpg", "jpeg":
                mimeType = "image/jpeg"
            case "png":
                mimeType = "image/png"
            case "webp":
                mimeType = "image/webp"
            case "gif":
                mimeType = "image/gif"
            default:
                return nil
            }

            guard let data = try? Data(contentsOf: url) else { return nil }
            return "data:\(mimeType);base64,\(data.base64EncodedString())"
        }

        /// Computes a single directory tree that WebKit can read, containing both the staged host
        /// page and the persona's Live2D bundle. When no bundle path is present yet, we simply
        /// return the host directory.
        nonisolated static func readAccessRoot(hostDir: URL, bundleDir: URL?) -> URL {
            guard let bundleDir else { return hostDir }
            return commonAncestorDirectory(hostDir, bundleDir)
        }

        /// Returns the deepest directory that is an ancestor of both `a` and `b`, resolved
        /// through symlinks. Falls back to the host directory's parent if the inputs live on
        /// disjoint trees; the staging logic should keep them co-located in practice.
        nonisolated static func commonAncestorDirectory(_ a: URL, _ b: URL) -> URL {
            let aResolved = a.resolvingSymlinksInPath().standardizedFileURL
            let bResolved = b.resolvingSymlinksInPath().standardizedFileURL
            let aComponents = aResolved.pathComponents
            let bComponents = bResolved.pathComponents

            var shared: [String] = []
            for (x, y) in zip(aComponents, bComponents) {
                if x == y {
                    shared.append(x)
                } else {
                    break
                }
            }

            if shared.isEmpty || shared == ["/"] {
                return aResolved.deletingLastPathComponent()
            }

            var result = URL(fileURLWithPath: "/")
            for (index, component) in shared.enumerated() where index > 0 {
                result = result.appendingPathComponent(component)
            }
            return result
        }

        nonisolated static func stagedHostIndex() -> URL? {
            guard let bundledIndex = locateBundledHostIndex() else { return nil }
            let bundledHostDir = bundledIndex.deletingLastPathComponent()
            let stagedHostDir = stagedHostDirectory()
            let stagedIndex = stagedHostDir.appendingPathComponent("index.html")
            let fm = FileManager.default

            do {
                if fm.fileExists(atPath: stagedHostDir.path) {
                    try fm.removeItem(at: stagedHostDir)
                }
                try fm.createDirectory(at: stagedHostDir, withIntermediateDirectories: true)
                try copyDirectoryContents(from: bundledHostDir, to: stagedHostDir)
                return stagedIndex
            } catch {
                return bundledIndex
            }
        }

        nonisolated private static func stagedHostDirectory() -> URL {
            let fm = FileManager.default
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            return appSupport.appendingPathComponent("GeeAgent/Live2DHost", isDirectory: true)
        }

        nonisolated private static func personasRootURL() -> URL? {
            let fm = FileManager.default
            guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            return appSupport.appendingPathComponent("GeeAgent/Personas", isDirectory: true).standardizedFileURL
        }

        nonisolated private static func personaRelativePathComponents(for modelURL: URL) -> [String]? {
            let components = modelURL.standardizedFileURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            guard components.count >= 3 else { return nil }

            for index in 0..<(components.count - 1) {
                guard components[index] == "GeeAgent", components[index + 1] == "Personas" else {
                    continue
                }

                let relative = Array(components.dropFirst(index + 2))
                return relative.isEmpty ? nil : relative
            }

            return nil
        }

        nonisolated private static func resolveServedFileURL(from url: URL) -> URL? {
            guard url.scheme == modelScheme, url.host == appHost else { return nil }

            let segments = url.pathComponents
                .filter { $0 != "/" && !$0.isEmpty }
                .compactMap { $0.removingPercentEncoding }

            guard let root = segments.first, !segments.contains("..") else { return nil }

            switch root {
            case hostRootComponent:
                let hostRoot = stagedHostDirectory().standardizedFileURL
                let relative = Array(segments.dropFirst())
                var resolved = hostRoot
                for segment in relative {
                    resolved.appendPathComponent(segment, isDirectory: false)
                }
                let standardized = resolved.standardizedFileURL
                guard standardized.path.hasPrefix(hostRoot.path) else { return nil }
                return standardized

            case personaRootComponent:
                guard let personasRoot = personasRootURL() else { return nil }
                let relative = Array(segments.dropFirst())
                var resolved = personasRoot
                for segment in relative {
                    resolved.appendPathComponent(segment, isDirectory: false)
                }
                let standardized = resolved.standardizedFileURL
                guard standardized.path.hasPrefix(personasRoot.path) else { return nil }
                return standardized

            default:
                return nil
            }
        }

        nonisolated private static func mimeType(for fileURL: URL) -> String {
            if let type = UTType(filenameExtension: fileURL.pathExtension.lowercased()),
               let mime = type.preferredMIMEType {
                return mime
            }
            switch fileURL.pathExtension.lowercased() {
            case "moc3":
                return "application/octet-stream"
            case "motion3", "exp3", "physics3", "pose3", "userdata3":
                return "application/json"
            default:
                return "application/octet-stream"
            }
        }

        nonisolated private static func copyDirectoryContents(from source: URL, to destination: URL) throws {
            let fm = FileManager.default
            let entries = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for entry in entries {
                let target = destination.appendingPathComponent(entry.lastPathComponent, isDirectory: true)
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
                try fm.copyItem(at: entry, to: target)
            }
        }

        nonisolated private static func locateBundledHostIndex() -> URL? {
            let bundle = Bundle.main
            if let url = bundle.url(forResource: "index", withExtension: "html", subdirectory: "Live2DHost") {
                return url
            }
            // Fallback for `swift run` / SPM test contexts: look alongside the executable.
            let exec = bundle.bundleURL.deletingLastPathComponent()
            let candidate = exec.appendingPathComponent("Live2DHost/index.html")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            return nil
        }
    }
}
