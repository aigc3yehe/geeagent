import SwiftUI

struct TwitterCaptureGearModuleView: View {
    var body: some View {
        TwitterCaptureGearWindow()
    }
}

struct TwitterCaptureGearWindow: View {
    @StateObject private var model = TwitterCaptureGearStore.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TwitterCaptureBackground()

                HStack(spacing: 0) {
                    commandPanel
                        .frame(width: min(max(proxy.size.width * 0.29, 330), 410))

                    TwitterCaptureDivider()

                    taskSurface
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    TwitterCaptureDivider()

                    detailPanel
                        .frame(width: min(max(proxy.size.width * 0.31, 350), 460))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            model.loadTasks()
        }
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Image(systemName: "bird")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.cyan.opacity(0.92))
                    Text("Twitter Capture")
                        .font(.geeDisplaySemibold(27))
                        .foregroundStyle(.white.opacity(0.96))
                }

                Text("Capture Tweet, List, and user timeline records into a local task database.")
                    .font(.geeBody(12))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }

            TwitterCaptureModePicker(selection: $model.selectedKind)

            VStack(alignment: .leading, spacing: 9) {
                Text(model.selectedKind.title)
                    .font(.geeDisplaySemibold(11))
                    .foregroundStyle(.white.opacity(0.54))

                TextField(model.selectedKind.placeholder, text: $model.target)
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
                        model.runCurrentTask()
                    }
            }

            if model.selectedKind.supportsLimit {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Tweet Limit")
                            .font(.geeDisplaySemibold(11))
                            .foregroundStyle(.white.opacity(0.54))
                        Spacer()
                        Text("\(model.limit)")
                            .font(.geeDisplaySemibold(12))
                            .foregroundStyle(.white.opacity(0.82))
                    }

                    HStack(spacing: 8) {
                        TwitterCaptureIconButton(systemImage: "minus") {
                            model.limit = max(1, model.limit - 5)
                        }
                        Slider(value: Binding(
                            get: { Double(model.limit) },
                            set: { model.limit = Int($0.rounded()) }
                        ), in: 1...200, step: 1)
                        .tint(.cyan.opacity(0.85))
                        TwitterCaptureIconButton(systemImage: "plus") {
                            model.limit = min(200, model.limit + 5)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Cookie Session")
                    .font(.geeDisplaySemibold(11))
                    .foregroundStyle(.white.opacity(0.54))

                HStack(spacing: 8) {
                    Text(model.cookieFilePath.nilIfBlank ?? "Choose cookie JSON")
                        .font(.geeBodyMedium(11))
                        .foregroundStyle(model.cookieFilePath.nilIfBlank == nil ? .white.opacity(0.42) : .white.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
                        }

                    Button {
                        model.chooseCookieFile()
                    } label: {
                        Text("Choose")
                            .font(.geeDisplaySemibold(11))
                            .foregroundStyle(.black.opacity(0.82))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Text("Export cookies from an authenticated X/Twitter browser session as JSON.")
                    .font(.geeBody(11))
                    .foregroundStyle(.white.opacity(0.38))
            }

            Button {
                model.runCurrentTask()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.isBusy ? "arrow.triangle.2.circlepath" : model.selectedKind.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.selectedKind.actionTitle)
                            .font(.geeDisplaySemibold(14))
                        Text("Create task and save result data")
                            .font(.geeBody(11))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .frame(height: 58)
                .background(
                    LinearGradient(colors: [.cyan.opacity(0.34), .blue.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.cyan.opacity(0.28), lineWidth: 0.9)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.isBusy ? Color.blue : Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: (model.isBusy ? Color.blue : Color.green).opacity(0.5), radius: 8)
                    Text(model.isBusy ? "Working" : "Ready")
                        .font(.geeDisplaySemibold(12))
                        .foregroundStyle(.white.opacity(0.74))
                }
                Text(model.statusMessage)
                    .font(.geeBody(11))
                    .foregroundStyle(.white.opacity(0.46))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .background(.ultraThinMaterial.opacity(0.24))
    }

    private var taskSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Task Database")
                            .font(.geeDisplaySemibold(21))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("Saved under ~/Library/Application Support/GeeAgent/gear-data/twitter.capture/tasks")
                            .font(.geeBody(12))
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    Spacer()

                    Button {
                        model.loadTasks()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.confirmAndDeleteAllTasks()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red.opacity((model.tasks.isEmpty || model.isBusy) ? 0.32 : 0.78))
                            .frame(width: 32, height: 32)
                            .background(Color.red.opacity((model.tasks.isEmpty || model.isBusy) ? 0.035 : 0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.tasks.isEmpty || model.isBusy)
                }

                if model.tasks.isEmpty {
                    TwitterCapturePanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 27, weight: .semibold))
                                .foregroundStyle(.cyan.opacity(0.82))
                            Text("No capture tasks yet")
                                .font(.geeDisplaySemibold(20))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("Run a Tweet URL, List URL, or username capture. Each run creates a file-database task record with result tweets and media metadata.")
                                .font(.geeBody(13))
                                .foregroundStyle(.white.opacity(0.52))
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(model.tasks) { task in
                            Button {
                                model.selectedTaskID = task.id
                            } label: {
                                TwitterCaptureTaskRow(
                                    task: task,
                                    isSelected: model.selectedTaskID == task.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Result")
                    .font(.geeDisplaySemibold(18))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Button {
                    model.revealSelectedTask()
                } label: {
                    Label("Task JSON", systemImage: "doc.text.magnifyingglass")
                        .font(.geeDisplaySemibold(11))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.selectedTask == nil)
            }

            if let task = model.selectedTask {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TwitterCaptureTaskSummary(task: task)

                        if task.tweets.isEmpty {
                            Text(task.errorMessage ?? "No tweet records saved yet.")
                                .font(.geeBody(13))
                                .foregroundStyle(task.status == .failed ? .red.opacity(0.86) : .white.opacity(0.48))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(task.tweets) { tweet in
                                    TwitterCapturedTweetCard(tweet: tweet) {
                                        model.openTweet(tweet)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer()
                Text("Select a task to inspect captured tweets.")
                    .font(.geeBody(13))
                    .foregroundStyle(.white.opacity(0.46))
                Spacer()
            }
        }
        .padding(22)
        .background(.ultraThinMaterial.opacity(0.18))
    }
}

private struct TwitterCaptureModePicker: View {
    @Binding var selection: TwitterCaptureTaskKind

    var body: some View {
        HStack(spacing: 7) {
            ForEach(TwitterCaptureTaskKind.allCases) { kind in
                Button {
                    selection = kind
                } label: {
                    Label(kind.title, systemImage: kind.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.geeDisplaySemibold(11))
                        .foregroundStyle(selection == kind ? .black.opacity(0.82) : .white.opacity(0.66))
                        .frame(maxWidth: .infinity)
                        .frame(height: 31)
                        .background(
                            selection == kind ? Color.white.opacity(0.88) : Color.white.opacity(0.075),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct TwitterCaptureTaskRow: View {
    var task: TwitterCaptureTaskRecord
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [.cyan.opacity(0.34), .blue.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: task.kind.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.84))
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(task.title)
                        .font(.geeDisplaySemibold(15))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    TwitterCaptureStatusPill(status: task.status)
                }
                Text(task.target)
                    .font(.geeBodyMedium(12))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(task.kind.title) / \(task.resultSummary)")
                    .font(.geeBody(11))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                Label("Task created \(task.createdAtLocalDisplay)", systemImage: "clock")
                    .font(.geeBodyMedium(10))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }

            Spacer()

            Text("\(task.tweets.count)")
                .font(.geeDisplaySemibold(18))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(12)
        .background(isSelected ? Color.white.opacity(0.11) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(isSelected ? Color.cyan.opacity(0.42) : Color.white.opacity(0.09), lineWidth: 0.9)
        }
    }
}

private struct TwitterCaptureTaskSummary: View {
    var task: TwitterCaptureTaskRecord

    var body: some View {
        TwitterCapturePanel {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title)
                            .font(.geeDisplaySemibold(19))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(task.target)
                            .font(.geeBodyMedium(12))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    TwitterCaptureStatusPill(status: task.status)
                }

                HStack(spacing: 8) {
                    TwitterCaptureTag(task.kind.title)
                    TwitterCaptureTag("\(task.tweets.count) tweets")
                    TwitterCaptureTag("limit \(task.limit)")
                    TwitterCaptureTag("created \(task.createdAtLocalDisplay)")
                }

                Text(task.taskURL.path)
                    .font(.geeBody(10))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct TwitterCapturedTweetCard: View {
    var tweet: TwitterCapturedTweet
    var open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tweet.authorHandle ?? "@unknown")
                    .font(.geeDisplaySemibold(13))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Button(action: open) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Text(tweet.text.nilIfBlank ?? "No text captured.")
                .font(.geeBody(12))
                .foregroundStyle(.white.opacity(0.76))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !tweet.media.isEmpty {
                HStack(spacing: 8) {
                    ForEach(tweet.media.prefix(3)) { item in
                        TwitterMediaPreview(item: item)
                    }
                    if tweet.media.count > 3 {
                        Text("+\(tweet.media.count - 3)")
                            .font(.geeDisplaySemibold(11))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                }
            }

            HStack(spacing: 8) {
                TwitterCaptureMetric(systemImage: "heart", value: tweet.likeCount)
                TwitterCaptureMetric(systemImage: "arrow.2.squarepath", value: tweet.retweetCount)
                TwitterCaptureMetric(systemImage: "bubble.left", value: tweet.replyCount)
                TwitterCaptureMetric(systemImage: "eye", value: tweet.viewCount)
            }
        }
        .padding(13)
        .background(Color.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }
}

private struct TwitterMediaPreview: View {
    var item: TwitterCaptureMediaItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let preview = item.previewURL ?? item.url, let url = URL(string: preview) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }

            Text(item.type.uppercased())
                .font(.geeDisplaySemibold(8))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(Color.black.opacity(0.42), in: Capsule())
                .padding(5)
        }
        .frame(width: 82, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            Color.white.opacity(0.06)
            Image(systemName: item.type == "video" ? "play.rectangle" : "photo")
                .foregroundStyle(.white.opacity(0.46))
        }
    }
}

private struct TwitterCaptureMetric: View {
    var systemImage: String
    var value: Int?

    var body: some View {
        if let value {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text("\(value)")
            }
            .font(.geeBodyMedium(10))
            .foregroundStyle(.white.opacity(0.42))
        }
    }
}

private struct TwitterCaptureStatusPill: View {
    var status: TwitterCaptureTaskStatus

    var body: some View {
        Text(status.title)
            .font(.geeDisplaySemibold(9))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var foreground: Color {
        switch status {
        case .completed: .green.opacity(0.88)
        case .failed: .red.opacity(0.88)
        case .running: .blue.opacity(0.88)
        case .queued: .white.opacity(0.62)
        }
    }

    private var background: Color {
        switch status {
        case .completed: .green.opacity(0.13)
        case .failed: .red.opacity(0.13)
        case .running: .blue.opacity(0.13)
        case .queued: .white.opacity(0.07)
        }
    }
}

private struct TwitterCaptureTag: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.geeDisplaySemibold(10))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct TwitterCaptureIconButton: View {
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TwitterCapturePanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
            }
    }
}

private struct TwitterCaptureDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
    }
}

private struct TwitterCaptureBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.10)
            RadialGradient(colors: [.cyan.opacity(0.20), .clear], center: .topLeading, startRadius: 40, endRadius: 680)
            RadialGradient(colors: [.blue.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 80, endRadius: 760)
            LinearGradient(colors: [.black.opacity(0.22), .clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}
