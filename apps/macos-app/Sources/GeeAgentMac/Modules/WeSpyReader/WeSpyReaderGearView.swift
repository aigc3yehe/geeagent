import SwiftUI

struct WeSpyReaderGearModuleView: View {
    var body: some View {
        WeSpyReaderGearWindow()
    }
}

struct WeSpyReaderGearWindow: View {
    @StateObject private var model = WeSpyReaderGearStore.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                WeSpyReaderBackground()

                HStack(spacing: 0) {
                    commandPanel
                        .frame(width: min(max(proxy.size.width * 0.3, 340), 430))

                    WeSpyReaderDivider()

                    taskSurface
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    WeSpyReaderDivider()

                    detailPanel
                        .frame(width: min(max(proxy.size.width * 0.31, 350), 470))
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
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.mint.opacity(0.95))
                    Text("WeSpy Reader")
                        .font(.geeDisplaySemibold(27))
                        .foregroundStyle(.white.opacity(0.96))
                }

                Text("Convert WeChat public-account articles, albums, and general pages into Markdown-first local files.")
                    .font(.geeBody(12))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            WeSpyReaderModePicker(selection: $model.selectedKind)

            VStack(alignment: .leading, spacing: 9) {
                Text(model.selectedKind.title)
                    .font(.geeDisplaySemibold(11))
                    .foregroundStyle(.white.opacity(0.54))

                TextField(model.selectedKind.placeholder, text: $model.url)
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
                        Text("Article Limit")
                            .font(.geeDisplaySemibold(11))
                            .foregroundStyle(.white.opacity(0.54))
                        Spacer()
                        Text("\(model.maxArticles)")
                            .font(.geeDisplaySemibold(12))
                            .foregroundStyle(.white.opacity(0.82))
                    }

                    HStack(spacing: 8) {
                        WeSpyReaderIconButton(systemImage: "minus") {
                            model.maxArticles = max(1, model.maxArticles - 5)
                        }
                        Slider(value: Binding(
                            get: { Double(model.maxArticles) },
                            set: { model.maxArticles = Int($0.rounded()) }
                        ), in: 1...100, step: 1)
                        .tint(.mint.opacity(0.85))
                        WeSpyReaderIconButton(systemImage: "plus") {
                            model.maxArticles = min(100, model.maxArticles + 5)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Outputs")
                    .font(.geeDisplaySemibold(11))
                    .foregroundStyle(.white.opacity(0.54))

                Toggle("Markdown", isOn: .constant(true))
                    .disabled(true)
                Toggle("HTML", isOn: $model.saveHTML)
                Toggle("JSON", isOn: $model.saveJSON)
            }
            .toggleStyle(.checkbox)
            .font(.geeBodyMedium(12))
            .foregroundStyle(.white.opacity(0.78))

            Button {
                model.runCurrentTask()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.isBusy ? "arrow.triangle.2.circlepath" : model.selectedKind.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.selectedKind.actionTitle)
                            .font(.geeDisplaySemibold(14))
                        Text("Create task and save local files")
                            .font(.geeBody(11))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .frame(height: 58)
                .background(
                    LinearGradient(colors: [.mint.opacity(0.34), .teal.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.mint.opacity(0.28), lineWidth: 0.9)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.isBusy ? Color.teal : Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: (model.isBusy ? Color.teal : Color.green).opacity(0.5), radius: 8)
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
                        Text("Saved under ~/Library/Application Support/GeeAgent/gear-data/wespy.reader/tasks")
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
                }

                if model.tasks.isEmpty {
                    WeSpyReaderPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 27, weight: .semibold))
                                .foregroundStyle(.mint.opacity(0.82))
                            Text("No WeSpy tasks yet")
                                .font(.geeDisplaySemibold(20))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("Paste an article or WeChat album URL. Each run stores a task record and the generated Markdown, with optional HTML and JSON files.")
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
                                WeSpyReaderTaskRow(
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Result")
                    .font(.geeDisplaySemibold(20))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Button {
                    model.revealSelectedTask()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.selectedTask == nil)
            }

            if let task = model.selectedTask {
                WeSpyReaderPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(task.status.title, systemImage: task.status == .completed ? "checkmark.seal" : "exclamationmark.triangle")
                            .font(.geeDisplaySemibold(12))
                            .foregroundStyle(task.status == .failed ? .orange : .mint)

                        Text(task.title)
                            .font(.geeDisplaySemibold(18))
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(task.url)
                            .font(.geeBody(11))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2)
                            .textSelection(.enabled)

                        if let error = task.errorMessage?.nilIfBlank {
                            Text(error)
                                .font(.geeBody(12))
                                .foregroundStyle(.orange.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                WeSpyReaderMetricStrip(task: task)

                if !task.files.isEmpty {
                    detailSection(title: "Files") {
                        ForEach(task.files, id: \.self) { path in
                            Button {
                                model.revealFile(path: path)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: fileIcon(path))
                                        .foregroundStyle(.mint.opacity(0.78))
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                }
                                .font(.geeBodyMedium(11))
                                .foregroundStyle(.white.opacity(0.76))
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !task.articles.isEmpty {
                    detailSection(title: "Articles") {
                        ForEach(task.articles.prefix(8)) { article in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(article.title?.nilIfBlank ?? "Untitled")
                                    .font(.geeBodyMedium(12))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .lineLimit(2)
                                if let url = article.url?.nilIfBlank {
                                    Button(url) {
                                        model.openSourceURL(url)
                                    }
                                    .font(.geeBody(10))
                                    .foregroundStyle(.mint.opacity(0.72))
                                    .buttonStyle(.plain)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                detailSection(title: "Log") {
                    Text(task.log.nilIfBlank ?? "No log.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.52))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                WeSpyReaderPanel {
                    Text("Select a task to inspect outputs.")
                        .font(.geeBody(13))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(.ultraThinMaterial.opacity(0.18))
    }

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.geeDisplaySemibold(11))
                .foregroundStyle(.white.opacity(0.54))
            content()
        }
        .padding(12)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
        }
    }

    private func fileIcon(_ path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "md": "doc.plaintext"
        case "html": "safari"
        case "json": "curlybraces"
        default: "doc"
        }
    }
}

private struct WeSpyReaderModePicker: View {
    @Binding var selection: WeSpyReaderTaskKind

    var body: some View {
        HStack(spacing: 7) {
            ForEach(WeSpyReaderTaskKind.allCases) { kind in
                Button {
                    selection = kind
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                        Text(kind.title)
                            .font(.geeDisplaySemibold(10))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(selection == kind ? .black.opacity(0.86) : .white.opacity(0.64))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        selection == kind ? Color.mint.opacity(0.9) : Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WeSpyReaderTaskRow: View {
    var task: WeSpyReaderTaskRecord
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(task.status == .failed ? .orange.opacity(0.9) : .mint.opacity(0.86))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.geeDisplaySemibold(14))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text(task.status.title)
                        .font(.geeDisplaySemibold(10))
                        .foregroundStyle(task.status == .failed ? .orange.opacity(0.85) : .white.opacity(0.5))
                }

                Text(task.resultSummary)
                    .font(.geeBody(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)

                Text(task.url)
                    .font(.geeBody(10))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            isSelected ? Color.mint.opacity(0.13) : Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.mint.opacity(0.28) : Color.white.opacity(0.07), lineWidth: 0.8)
        }
    }
}

private struct WeSpyReaderMetricStrip: View {
    var task: WeSpyReaderTaskRecord

    var body: some View {
        HStack(spacing: 8) {
            metric("Articles", "\(task.articleCount)")
            metric("Files", "\(task.files.count)")
            metric("Limit", task.kind.supportsLimit ? "\(task.maxArticles)" : "1")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.geeBody(10))
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.geeDisplaySemibold(17))
                .foregroundStyle(.white.opacity(0.86))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct WeSpyReaderPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            }
    }
}

private struct WeSpyReaderIconButton: View {
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct WeSpyReaderDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1)
    }
}

private struct WeSpyReaderBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.08, blue: 0.08),
                Color(red: 0.06, green: 0.12, blue: 0.11),
                Color(red: 0.03, green: 0.04, blue: 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
