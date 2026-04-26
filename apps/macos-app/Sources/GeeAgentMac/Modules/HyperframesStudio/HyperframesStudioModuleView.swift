import SwiftUI

struct HyperframesStudioModuleView: View {
    var body: some View {
        HyperframesStudioModuleWindow()
    }
}

struct HyperframesStudioModuleWindow: View {
    @StateObject private var model = HyperframesStudioViewModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                rootBackground

                if let timelineURL = model.timelineURL {
                    timelineScene(url: timelineURL)
                } else {
                    homeScene(proxy: proxy)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var rootBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.075),
                Color(red: 0.035, green: 0.04, blue: 0.055)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func homeScene(proxy: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: min(max(proxy.size.width * 0.24, 248), 320))

            Divider()
                .overlay(Color.white.opacity(0.08))

            VStack(spacing: 0) {
                toolbar
                Divider().overlay(Color.white.opacity(0.08))
                productionSurface
            }
        }
    }

    private func timelineScene(url: URL) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    model.closeTimeline()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.geeDisplaySemibold(12))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
                .help("Return to Hyperframes home")

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedProject?.name ?? "Timeline")
                        .font(.geeDisplaySemibold(13))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                    Text(url.absoluteString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.38))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(.ultraThinMaterial.opacity(0.28))

            Divider()
                .overlay(Color.white.opacity(0.08))

            HyperframesTimelineWebView(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hyperframes")
                    .font(.geeDisplaySemibold(26))
                    .foregroundStyle(.white.opacity(0.96))
                Text("HTML-to-video production loop")
                    .font(.geeBody(12))
                    .foregroundStyle(.white.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Projects", systemImage: "folder")
                    .font(.geeDisplaySemibold(12))
                    .foregroundStyle(.white.opacity(0.68))

                if model.projects.isEmpty {
                    Text("No projects yet")
                        .font(.geeBody(13))
                        .foregroundStyle(.white.opacity(0.46))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.projects) { project in
                            Button {
                                model.selectedProjectID = project.id
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.richtext")
                                        .font(.system(size: 12, weight: .semibold))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(project.name)
                                            .font(.geeDisplaySemibold(12))
                                            .lineLimit(1)
                                        Text("\(project.renderURLs.count) result\(project.renderURLs.count == 1 ? "" : "s")")
                                            .font(.geeBody(10))
                                            .foregroundStyle(.white.opacity(0.42))
                                    }
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(model.selectedProjectID == project.id ? .white.opacity(0.92) : .white.opacity(0.62))
                                .padding(.horizontal, 10)
                                .frame(height: 44)
                                .background(
                                    Color.white.opacity(model.selectedProjectID == project.id ? 0.105 : 0.045),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label(model.isBusy ? "Working" : "Ready", systemImage: model.isBusy ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                    .font(.geeDisplaySemibold(12))
                    .foregroundStyle(model.isBusy ? .blue.opacity(0.9) : .green.opacity(0.9))
                Text(model.status)
                    .font(.geeBody(11))
                    .foregroundStyle(.white.opacity(0.46))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .background(.ultraThinMaterial.opacity(0.22))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            ForEach(HyperframesStudioAction.allCases) { action in
                Button {
                    perform(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.geeDisplaySemibold(12))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy || action.requiresProject && model.selectedProject == nil)
                .opacity(model.isBusy || action.requiresProject && model.selectedProject == nil ? 0.46 : 1)
                .help(action.subtitle)
            }

            Spacer()

            Button {
                model.reloadProjects()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Refresh projects")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.18))
    }

    private var productionSurface: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.selectedProject?.name ?? "Production")
                    .font(.geeDisplaySemibold(20))
                    .foregroundStyle(.white.opacity(0.92))

                Text(model.selectedProject?.url.path ?? "Create a project, import footage, open the Hyperframes timeline, render, then inspect outputs.")
                    .font(.geeBody(13))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(2)

                actionGrid

                if !model.logText.isEmpty {
                    Text(model.logText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
                .overlay(Color.white.opacity(0.08))

            resultsPanel
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            ForEach(HyperframesStudioAction.allCases) { action in
                Button {
                    perform(action)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                        Text(action.title)
                            .font(.geeDisplaySemibold(14))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(action.subtitle)
                            .font(.geeBody(12))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy || action.requiresProject && model.selectedProject == nil)
            }
        }
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Results")
                .font(.geeDisplaySemibold(16))
                .foregroundStyle(.white.opacity(0.88))

            if let project = model.selectedProject, !project.renderURLs.isEmpty {
                ForEach(project.renderURLs, id: \.path) { url in
                    Button {
                        model.reveal(url)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "play.rectangle")
                                .font(.system(size: 13, weight: .semibold))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(url.lastPathComponent)
                                    .font(.geeDisplaySemibold(11))
                                    .lineLimit(1)
                                Text("Reveal in Finder")
                                    .font(.geeBody(10))
                                    .foregroundStyle(.white.opacity(0.42))
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(10)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Rendered outputs will appear here with Finder handoff.")
                    .font(.geeBody(12))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 280, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial.opacity(0.16))
    }

    private func perform(_ action: HyperframesStudioAction) {
        Task {
            switch action {
            case .new:
                await model.createProject()
            case .importVideo:
                await model.importVideo()
            case .timeline:
                await model.openTimeline()
            case .render:
                await model.render()
            case .results:
                model.revealSelectedProject()
            }
        }
    }
}

private enum HyperframesStudioAction: String, CaseIterable, Identifiable {
    case new
    case importVideo
    case timeline
    case render
    case results

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: "New"
        case .importVideo: "Import"
        case .timeline: "Timeline"
        case .render: "Render"
        case .results: "Results"
        }
    }

    var systemImage: String {
        switch self {
        case .new: "plus"
        case .importVideo: "film.stack"
        case .timeline: "timeline.selection"
        case .render: "play.rectangle"
        case .results: "rectangle.stack"
        }
    }

    var subtitle: String {
        switch self {
        case .new: "Create a Hyperframes project"
        case .importVideo: "Copy video into project assets"
        case .timeline: "Run timeline inside this gear"
        case .render: "Queue an MP4 render"
        case .results: "Reveal project and renders"
        }
    }

    var requiresProject: Bool {
        self != .new
    }
}
