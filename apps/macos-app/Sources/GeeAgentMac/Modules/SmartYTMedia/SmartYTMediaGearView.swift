import SwiftUI

struct SmartYTMediaGearModuleView: View {
    var body: some View {
        SmartYTMediaGearWindow()
    }
}

struct SmartYTMediaGearWindow: View {
    @StateObject private var model = SmartYTMediaGearStore.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SmartYTRootBackground()

                HStack(spacing: 0) {
                    commandPanel
                        .frame(width: min(max(proxy.size.width * 0.30, 330), 430))

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    resultsSurface
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    jobInspector
                        .frame(width: min(max(proxy.size.width * 0.30, 340), 430))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            model.loadJobs()
        }
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.cyan.opacity(0.88))
                    Text("SmartYT Media")
                        .font(.geeDisplaySemibold(27))
                        .foregroundStyle(.white.opacity(0.96))
                }

                Text("Sniff, download, and turn URL media into text.")
                    .font(.geeBody(12))
                    .foregroundStyle(.white.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("URL")
                    .font(.geeDisplaySemibold(11))
                    .foregroundStyle(.white.opacity(0.52))

                TextField("https://...", text: $model.urlString)
                    .textFieldStyle(.plain)
                    .font(.geeBodyMedium(13))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    }
                    .onSubmit {
                        Task { await model.sniffCurrentURL() }
                    }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Download Type")
                    .font(.geeDisplaySemibold(11))
                    .foregroundStyle(.white.opacity(0.52))

                HStack(spacing: 7) {
                    ForEach(SmartYTDownloadKind.allCases) { kind in
                        Button {
                            model.selectedDownloadKind = kind
                        } label: {
                            Text(kind.title)
                                .font(.geeDisplaySemibold(11))
                                .foregroundStyle(model.selectedDownloadKind == kind ? .black.opacity(0.82) : .white.opacity(0.66))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(
                                    model.selectedDownloadKind == kind ? Color.white.opacity(0.88) : Color.white.opacity(0.075),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Language Hint")
                    .font(.geeDisplaySemibold(11))
                    .foregroundStyle(.white.opacity(0.52))

                TextField("zh, en, ja ...", text: $model.languagePreference)
                    .textFieldStyle(.plain)
                    .font(.geeBodyMedium(12))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
                    }
            }

            VStack(spacing: 9) {
                SmartYTCommandButton(
                    title: "Sniff media",
                    subtitle: "Inspect title, duration, platform, formats",
                    systemImage: "waveform.and.magnifyingglass",
                    accent: .cyan
                ) {
                    Task { await model.sniffCurrentURL() }
                }

                SmartYTCommandButton(
                    title: "Download",
                    subtitle: "\(model.selectedDownloadKind.title) artifact via yt-dlp",
                    systemImage: "arrow.down.circle",
                    accent: .blue
                ) {
                    model.downloadCurrentURL(kind: model.selectedDownloadKind)
                }

                SmartYTCommandButton(
                    title: "Convert to text",
                    subtitle: "Subtitles first, local Whisper if available",
                    systemImage: "text.quote",
                    accent: .green
                ) {
                    model.transcribeCurrentURL()
                }
            }

            Text("Default output: ~/Downloads/SmartYT")
                .font(.geeBody(11))
                .foregroundStyle(.white.opacity(0.42))

            Spacer()

            statusFooter
        }
        .padding(22)
        .background(.ultraThinMaterial.opacity(0.22))
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.isBusy ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.isBusy ? .blue.opacity(0.92) : .green.opacity(0.92))
                Text(model.isBusy ? "Working" : "Ready")
                    .font(.geeDisplaySemibold(12))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Text(model.statusMessage)
                .font(.geeBody(11))
                .foregroundStyle(.white.opacity(0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resultsSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mediaInfoCard
                jobsList
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var mediaInfoCard: some View {
        if let info = model.mediaInfo {
            SmartYTGlassPanel {
                HStack(alignment: .top, spacing: 16) {
                    thumbnail(url: info.thumbnailURL)
                        .frame(width: 168, height: 104)

                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            SmartYTTag(info.platform)
                            if let ext = info.extensionHint {
                                SmartYTTag(ext.uppercased())
                            }
                            SmartYTTag("\(info.formatCount) formats")
                        }

                        Text(info.title)
                            .font(.geeDisplaySemibold(22))
                            .foregroundStyle(.white.opacity(0.94))
                            .lineLimit(2)

                        Text([info.uploader, info.durationText].compactMap(\.self).joined(separator: " / "))
                            .font(.geeBodyMedium(12))
                            .foregroundStyle(.white.opacity(0.52))
                    }

                    Spacer()
                }
            }
        } else {
            SmartYTGlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.cyan.opacity(0.82))
                    Text("Paste a URL and sniff media")
                        .font(.geeDisplaySemibold(20))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("This Gear follows SmartYT's URL acquisition loop: metadata first, then download or transcript extraction.")
                        .font(.geeBody(13))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
        }
    }

    private var jobsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Jobs")
                    .font(.geeDisplaySemibold(16))
                    .foregroundStyle(.white.opacity(0.86))

                Spacer()

                Button {
                    model.loadJobs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.66))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if model.jobs.isEmpty {
                Text("No jobs yet. Sniff, download, or convert a URL to create one.")
                    .font(.geeBody(13))
                    .foregroundStyle(.white.opacity(0.46))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                LazyVStack(spacing: 9) {
                    ForEach(model.jobs) { job in
                        Button {
                            model.selectedJobID = job.id
                        } label: {
                            SmartYTJobRow(job: job, isSelected: model.selectedJobID == job.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var jobInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Inspector")
                    .font(.geeDisplaySemibold(18))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Button {
                    model.revealSelectedJob()
                } label: {
                    Label("Finder", systemImage: "folder")
                        .font(.geeDisplaySemibold(11))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.selectedJob == nil)
            }

            if let job = model.selectedJob {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SmartYTJobSummary(job: job)

                        if let preview = job.transcriptPreview {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Transcript Preview")
                                    .font(.geeDisplaySemibold(12))
                                    .foregroundStyle(.white.opacity(0.62))
                                Text(preview)
                                    .font(.geeBody(12))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }

                        if !job.outputURLs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Artifacts")
                                    .font(.geeDisplaySemibold(12))
                                    .foregroundStyle(.white.opacity(0.62))
                                ForEach(job.outputURLs, id: \.path) { url in
                                    Button {
                                        model.reveal(url)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "doc")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text(url.lastPathComponent)
                                                .font(.geeBodyMedium(11))
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        .foregroundStyle(.white.opacity(0.7))
                                        .padding(.horizontal, 10)
                                        .frame(height: 30)
                                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Log")
                                .font(.geeDisplaySemibold(12))
                                .foregroundStyle(.white.opacity(0.62))
                            Text(job.log)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.48))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer()
                VStack(spacing: 9) {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                    Text("Select a job")
                        .font(.geeDisplaySemibold(15))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.18))
    }

    private func thumbnail(url: URL?) -> some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        SmartYTThumbnailPlaceholder()
                    }
                }
            } else {
                SmartYTThumbnailPlaceholder()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        }
    }
}

private struct SmartYTRootBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.045, blue: 0.065),
                    Color(red: 0.018, green: 0.022, blue: 0.032)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(0.15))
                .blur(radius: 90)
                .frame(width: 360, height: 360)
                .offset(x: -260, y: -180)

            Circle()
                .fill(Color.blue.opacity(0.11))
                .blur(radius: 110)
                .frame(width: 420, height: 420)
                .offset(x: 300, y: 240)
        }
        .ignoresSafeArea()
    }
}

private struct SmartYTCommandButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.92))
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.geeDisplaySemibold(13))
                        .foregroundStyle(.white.opacity(0.88))
                    Text(subtitle)
                        .font(.geeBody(11))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SmartYTGlassPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial.opacity(0.36), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            }
    }
}

private struct SmartYTTag: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.geeDisplaySemibold(10))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct SmartYTThumbnailPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.cyan.opacity(0.33),
                    Color.blue.opacity(0.25),
                    Color.black.opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

private struct SmartYTJobRow: View {
    let job: SmartYTMediaJob
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: job.action.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor.opacity(0.95))
                .frame(width: 30, height: 30)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(job.title)
                    .font(.geeDisplaySemibold(12))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(job.url)
                    .font(.geeBody(10))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(job.status.title)
                .font(.geeDisplaySemibold(10))
                .foregroundStyle(statusColor.opacity(0.9))
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 11)
        .frame(height: 54)
        .background(
            isSelected ? Color.white.opacity(0.11) : Color.white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.cyan.opacity(0.35) : Color.white.opacity(0.075), lineWidth: 0.8)
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .queued: .white.opacity(0.68)
        case .running: .blue
        case .completed: .green
        case .failed: .orange
        }
    }
}

private struct SmartYTJobSummary: View {
    let job: SmartYTMediaJob

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SmartYTTag(job.action.title)
                SmartYTTag(job.downloadKind.title)
                SmartYTTag(job.status.title)
            }

            Text(job.title)
                .font(.geeDisplaySemibold(19))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)

            Text(job.url)
                .font(.geeBody(11))
                .foregroundStyle(.white.opacity(0.44))
                .textSelection(.enabled)

            if let error = job.errorMessage {
                Text(error)
                    .font(.geeBody(12))
                    .foregroundStyle(.orange.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
        }
    }
}
