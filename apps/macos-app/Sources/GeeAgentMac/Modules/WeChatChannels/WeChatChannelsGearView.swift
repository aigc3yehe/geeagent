import SwiftUI
import WebKit

struct WeChatChannelsGearModuleView: View {
    var body: some View {
        WeChatChannelsGearWindow()
    }
}

struct WeChatChannelsGearWindow: View {
    @StateObject private var model = WeChatChannelsGearStore.shared
    @StateObject private var yuanbaoAuthController = WeChatChannelsYuanbaoAuthController()
    @State private var showingYuanbaoAuthorization = false

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                commandPanel
                    .frame(width: min(max(proxy.size.width * 0.33, 380), 500))

                Divider()

                taskPanel
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                detailPanel
                    .frame(width: min(max(proxy.size.width * 0.3, 360), 500))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear {
            model.load()
        }
        .sheet(isPresented: $showingYuanbaoAuthorization) {
            WeChatChannelsYuanbaoSessionSheet(
                model: model,
                controller: yuanbaoAuthController,
                isPresented: $showingYuanbaoAuthorization
            )
        }
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("WeChat Channels")
                        .font(.title2.weight(.semibold))
                    Text(model.sessionConfigured ? "Yuanbao session configured" : "Yuanbao session missing")
                        .font(.caption)
                        .foregroundStyle(model.sessionConfigured ? .green : .secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Source")
                    .font(.headline)
                TextField("https://weixin.qq.com/sph/...", text: $model.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.fetchCurrentMetadata()
                    }

                HStack(spacing: 8) {
                    Button {
                        model.fetchCurrentMetadata()
                    } label: {
                        Label("Metadata", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)

                    Button {
                        model.downloadCurrentVideo()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Session")
                    .font(.headline)

                TextEditor(text: $model.cookieDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 92, maxHeight: 120)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    }

                TextField("User-Agent", text: $model.userAgentDraft)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $model.extraHeadersJSONDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 72, maxHeight: 96)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    }

                HStack {
                    Button {
                        showingYuanbaoAuthorization = true
                    } label: {
                        Label("Authorize", systemImage: "person.badge.key")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.saveSessionFromDrafts()
                    } label: {
                        Label("Save", systemImage: "key")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        model.clearSession()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(model.isBusy ? Color.blue : Color.green)
                    .frame(width: 8, height: 8)
                Text(model.isBusy ? "Working" : "Ready")
                    .font(.caption.weight(.semibold))
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(20)
        .background(.thinMaterial)
    }

    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Downloads")
                        .font(.title3.weight(.semibold))
                    Text("\(model.tasks.count) task\(model.tasks.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh")
            }

            if model.tasks.isEmpty {
                ContentUnavailableView(
                    "No downloads",
                    systemImage: "play.rectangle",
                    description: Text("Resolve or download an explicit WeChat Channels share URL.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.tasks) { task in
                            Button {
                                model.selectedTaskID = task.id
                            } label: {
                                WeChatChannelsTaskRow(
                                    task: task,
                                    selected: model.selectedTaskID == task.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(22)
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Result")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    model.revealSelectedTask()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedTask == nil)
                .help("Reveal in Finder")
            }

            if let selected = model.selectedTask {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Label(selected.status.title, systemImage: statusIcon(selected.status))
                            .foregroundStyle(statusColor(selected.status))
                        Spacer()
                        Text(WeChatChannelsDateCodec.localDisplay(from: selected.updatedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(selected.title)
                            .font(.headline)
                            .lineLimit(3)
                        if let author = selected.author {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let outputPath = selected.outputPath {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("File")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(outputPath)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let errorMessage = selected.errorMessage {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selected.errorCode ?? "Error")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let profile = selected.profile {
                        WeChatChannelsProfileView(profile: profile)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else if let profile = model.profile {
                WeChatChannelsProfileView(profile: profile)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView(
                    "No result selected",
                    systemImage: "sidebar.right",
                    description: Text("Select a task or resolve metadata.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding(20)
        .background(.thinMaterial)
    }

    private func statusIcon(_ status: WeChatChannelsTaskStatus) -> String {
        switch status {
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle"
        case .failed: "xmark.octagon"
        case .degraded: "exclamationmark.triangle"
        }
    }

    private func statusColor(_ status: WeChatChannelsTaskStatus) -> Color {
        switch status {
        case .running: .blue
        case .completed: .green
        case .failed: .red
        case .degraded: .orange
        }
    }
}

private struct WeChatChannelsBrowserSession {
    var cookieHeader: String
    var userAgent: String
}

@MainActor
private final class WeChatChannelsYuanbaoAuthController: NSObject, ObservableObject {
    @Published var statusMessage = "Sign in to Yuanbao, then use the current session."
    @Published var isCapturing = false

    weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func captureSession(completion: @escaping (WeChatChannelsBrowserSession) -> Void) {
        guard let webView else {
            statusMessage = "Yuanbao web view is not ready."
            return
        }

        isCapturing = true
        statusMessage = "Capturing Yuanbao session..."
        webView.evaluateJavaScript("navigator.userAgent") { [weak self, weak webView] value, _ in
            guard let self, let webView else {
                return
            }
            let fallbackUserAgent = WeChatChannelsGearStore.defaultUserAgent
            let userAgent = (value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank ?? fallbackUserAgent

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let yuanbaoCookies = Self.cookiesForHost("yuanbao.tencent.com", from: cookies)
                let cookieHeader = HTTPCookie.requestHeaderFields(with: yuanbaoCookies)["Cookie"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                DispatchQueue.main.async {
                    self.isCapturing = false
                    guard !cookieHeader.isEmpty else {
                        self.statusMessage = "No Yuanbao session cookies were available yet."
                        return
                    }
                    self.statusMessage = "Yuanbao session captured."
                    completion(WeChatChannelsBrowserSession(
                        cookieHeader: cookieHeader,
                        userAgent: userAgent
                    ))
                }
            }
        }
    }

    private static func cookiesForHost(_ host: String, from cookies: [HTTPCookie]) -> [HTTPCookie] {
        cookies
            .filter { cookie in
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                return host == domain || host.hasSuffix(".\(domain)")
            }
            .sorted {
                if $0.domain == $1.domain {
                    return $0.name < $1.name
                }
                return $0.domain.count > $1.domain.count
            }
    }
}

private struct WeChatChannelsYuanbaoSessionSheet: View {
    @ObservedObject var model: WeChatChannelsGearStore
    @ObservedObject var controller: WeChatChannelsYuanbaoAuthController
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yuanbao Authorization")
                        .font(.title3.weight(.semibold))
                    Text(controller.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                Button {
                    controller.captureSession { session in
                        model.saveAuthorizedBrowserSession(
                            cookie: session.cookieHeader,
                            userAgent: session.userAgent
                        )
                        isPresented = false
                    }
                } label: {
                    Label("Use Current Session", systemImage: "key.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isCapturing)
            }
            .padding(14)

            Divider()

            WeChatChannelsYuanbaoWebView(controller: controller)
                .frame(minWidth: 980, minHeight: 680)
        }
        .frame(width: 1080, height: 760)
    }
}

private struct WeChatChannelsYuanbaoWebView: NSViewRepresentable {
    @ObservedObject var controller: WeChatChannelsYuanbaoAuthController

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if #available(macOS 11.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = WeChatChannelsGearStore.defaultUserAgent
        webView.allowsBackForwardNavigationGestures = true
        controller.attach(webView)
        webView.load(URLRequest(url: URL(string: "https://yuanbao.tencent.com/")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        controller.attach(webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var controller: WeChatChannelsYuanbaoAuthController?

        init(controller: WeChatChannelsYuanbaoAuthController) {
            self.controller = controller
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            controller?.attach(webView)
            controller?.statusMessage = "Sign in to Yuanbao, then use the current session."
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

private struct WeChatChannelsTaskRow: View {
    var task: WeChatChannelsTaskRecord
    var selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(task.sourceURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(task.status.title)
                    if let outputByteCount = task.outputByteCount {
                        Text(ByteCountFormatter.string(fromByteCount: outputByteCount, countStyle: .file))
                    }
                    Text(WeChatChannelsDateCodec.localDisplay(from: task.updatedAt))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            selected ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        }
    }

    private var icon: String {
        switch task.status {
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "play.circle"
        case .failed: "xmark.octagon"
        case .degraded: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch task.status {
        case .running: .blue
        case .completed: .green
        case .failed: .red
        case .degraded: .orange
        }
    }
}

private struct WeChatChannelsProfileView: View {
    var profile: WeChatChannelsVideoProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Profile")
                    .font(.headline)
                Spacer()
                if profile.bestVideoURL != nil {
                    Label("Video URL", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("No video URL", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let author = profile.author {
                WeChatChannelsField(label: "Author", value: author)
            }
            if let description = profile.description {
                WeChatChannelsField(label: "Description", value: description)
            }
            if let coverURL = profile.coverURL {
                WeChatChannelsField(label: "Cover", value: coverURL)
            }
            if let bestVideoURL = profile.bestVideoURL {
                WeChatChannelsField(label: "Video", value: bestVideoURL)
            }
        }
    }
}

private struct WeChatChannelsField: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
        }
    }
}
