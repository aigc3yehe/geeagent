import AVKit
import SwiftUI

struct PowerVideoManagerGearModuleView: View {
    var body: some View {
        PowerVideoManagerGearWindow()
    }
}

struct PowerVideoManagerGearWindow: View {
    @StateObject private var model = PowerVideoManagerGearStore.shared

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                sidebar
                    .frame(width: min(max(proxy.size.width * 0.30, 320), 430))

                Divider()

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(item: $model.selectedAsset) { asset in
            PowerVideoManagerAssetPreview(asset: asset)
                .frame(minWidth: 720, minHeight: 520)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Power Video Manager")
                        .font(.title2.weight(.semibold))
                    Text(model.workspaceURL?.path ?? "No workspace selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.chooseWorkspace()
                } label: {
                    Label("Choose Workspace", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.refresh()
                } label: {
                    Image(systemName: model.isScanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(model.isScanning)
                .help("Refresh")
            }

            if model.projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "film",
                    description: Text("Choose a runs folder containing project folders with script/script-archive.md.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selectedProjectID) {
                    ForEach(model.projects) { project in
                        PowerVideoManagerProjectRow(project: project)
                            .tag(project.id)
                    }
                }
                .listStyle(.sidebar)
            }

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        if let project = model.selectedProject {
            VStack(spacing: 0) {
                PowerVideoManagerProjectHeader(project: project)
                    .padding(18)

                Picker("View", selection: $model.selectedTab) {
                    ForEach(PowerVideoManagerDetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

                Divider()

                switch model.selectedTab {
                case .overview:
                    PowerVideoManagerOverview(project: project, onOpenAsset: { model.selectedAsset = $0 })
                case .script:
                    PowerVideoManagerScriptView(project: project)
                case .assets:
                    PowerVideoManagerAssetsView(project: project, onOpenAsset: { model.selectedAsset = $0 })
                case .timeline:
                    PowerVideoManagerTimelineView(project: project, onOpenAsset: { model.selectedAsset = $0 })
                }
            }
        } else {
            ContentUnavailableView(
                "Choose a Workspace",
                systemImage: "folder.badge.questionmark",
                description: Text("Open a runs folder to inspect AI video projects.")
            )
        }
    }
}

private struct PowerVideoManagerProjectRow: View {
    var project: PowerVideoManagerProject

    var body: some View {
        HStack(spacing: 10) {
            PowerVideoManagerThumbnail(asset: project.primaryCharacterLook, size: CGSize(width: 54, height: 42))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(GeeAgentTimeFormatting.conversationTimestampLabel(project.updatedAt.ISO8601Format()))
                    Text(project.progressLabels.joined(separator: " / "))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text(costLabel(project.cost))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct PowerVideoManagerProjectHeader: View {
    var project: PowerVideoManagerProject

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PowerVideoManagerThumbnail(asset: project.primaryCharacterLook, size: CGSize(width: 92, height: 68))

            VStack(alignment: .leading, spacing: 8) {
                Text(project.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    ForEach(project.progressLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                HStack(spacing: 14) {
                    PowerVideoManagerMetric(label: "Updated", value: GeeAgentTimeFormatting.conversationTimestampLabel(project.updatedAt.ISO8601Format()))
                    PowerVideoManagerMetric(label: "Cost", value: costLabel(project.cost))
                    PowerVideoManagerMetric(label: "Videos", value: "\(project.assets(kind: .shotVideo).count)")
                    PowerVideoManagerMetric(label: "Finals", value: "\(project.assets(kind: .finalVideo).count)")
                }
            }

            Spacer()
        }
    }
}

private struct PowerVideoManagerOverview: View {
    var project: PowerVideoManagerProject
    var onOpenAsset: (PowerVideoManagerAsset) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PowerVideoManagerAssetStrip(title: "Character Looks", assets: project.assets(kind: .characterLook), onOpenAsset: onOpenAsset)
                PowerVideoManagerAssetStrip(title: "Storyboard Grids", assets: project.assets(kind: .storyboardGrid), onOpenAsset: onOpenAsset)
                PowerVideoManagerAssetStrip(title: "Edit Renders", assets: project.assets(kind: .editRender), onOpenAsset: onOpenAsset)
                PowerVideoManagerAssetStrip(title: "Final Outputs", assets: project.assets(kind: .finalVideo), onOpenAsset: onOpenAsset)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Project Evidence")
                        .font(.headline)
                    PowerVideoManagerKeyValue(label: "Folder", value: project.url.path)
                    if let status = project.status {
                        PowerVideoManagerKeyValue(label: "Status", value: status)
                    }
                    if let score = project.score {
                        PowerVideoManagerKeyValue(label: "Score", value: score)
                    }
                    if let duration = project.duration {
                        PowerVideoManagerKeyValue(label: "Duration", value: duration)
                    }
                    if let aspectRatio = project.aspectRatio {
                        PowerVideoManagerKeyValue(label: "Aspect", value: aspectRatio)
                    }
                }
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(18)
        }
    }
}

private struct PowerVideoManagerScriptView: View {
    var project: PowerVideoManagerProject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PowerVideoManagerKeyValue(label: "Script Archive", value: project.url.appendingPathComponent("script/script-archive.md").path)
                PowerVideoManagerKeyValue(label: "Production Prompts", value: project.url.appendingPathComponent("script/production-prompts.json").path)

                if let text = try? String(contentsOf: project.url.appendingPathComponent("script/script-archive.md"), encoding: .utf8) {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(18)
        }
    }
}

private struct PowerVideoManagerAssetsView: View {
    var project: PowerVideoManagerProject
    var onOpenAsset: (PowerVideoManagerAsset) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(PowerVideoManagerAssetKind.allCases.filter { !project.assets(kind: $0).isEmpty }) { kind in
                    PowerVideoManagerAssetSection(kind: kind, assets: project.assets(kind: kind), onOpenAsset: onOpenAsset)
                }
            }
            .padding(18)
        }
    }
}

private struct PowerVideoManagerTimelineView: View {
    var project: PowerVideoManagerProject
    var onOpenAsset: (PowerVideoManagerAsset) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(project.shots) { shot in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Shot \(String(format: "%03d", shot.shotNumber))")
                                .font(.headline)
                            if let summary = shot.summary {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        PowerVideoManagerHorizontalAssetRow(
                            assets: shot.firstFrames + shot.videos + shot.editRenders,
                            onOpenAsset: onOpenAsset
                        )
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(18)
        }
    }
}

private struct PowerVideoManagerAssetSection: View {
    var kind: PowerVideoManagerAssetKind
    var assets: [PowerVideoManagerAsset]
    var onOpenAsset: (PowerVideoManagerAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(kind.title) (\(assets.count))", systemImage: kind.systemImage)
                .font(.headline)

            PowerVideoManagerHorizontalAssetRow(assets: assets, onOpenAsset: onOpenAsset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PowerVideoManagerHorizontalAssetRow: View {
    var assets: [PowerVideoManagerAsset]
    var onOpenAsset: (PowerVideoManagerAsset) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(assets) { asset in
                    PowerVideoManagerAssetMiniCard(asset: asset) {
                        onOpenAsset(asset)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PowerVideoManagerAssetStrip: View {
    var title: String
    var assets: [PowerVideoManagerAsset]
    var onOpenAsset: (PowerVideoManagerAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title) (\(assets.count))")
                .font(.headline)
            if assets.isEmpty {
                ContentUnavailableView("No \(title)", systemImage: "photo")
                    .frame(height: 120)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(assets) { asset in
                            PowerVideoManagerAssetMiniCard(asset: asset) {
                                onOpenAsset(asset)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PowerVideoManagerAssetMiniCard: View {
    var asset: PowerVideoManagerAsset
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 7) {
                PowerVideoManagerThumbnail(asset: asset, size: CGSize(width: 132, height: 82))
                HStack(spacing: 4) {
                    if asset.isSelected {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    Text(asset.filename)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Text(GeeAgentTimeFormatting.conversationTimestampLabel(asset.updatedAt.ISO8601Format()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(asset.relativePath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .padding(9)
            .frame(width: 150, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PowerVideoManagerAssetPreview: View {
    var asset: PowerVideoManagerAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.filename)
                        .font(.headline)
                    Text(asset.relativePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if asset.isImage, let image = NSImage(contentsOf: asset.url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.88))
            } else if asset.isVideo {
                VStack(alignment: .leading, spacing: 8) {
                    VideoPlayer(player: AVPlayer(url: asset.url))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.88))
                    Link("Open File", destination: asset.url)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text((try? String(contentsOf: asset.url, encoding: .utf8)) ?? asset.url.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
    }
}

private struct PowerVideoManagerThumbnail: View {
    var asset: PowerVideoManagerAsset?
    var size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            if let asset {
                if asset.isImage, let image = NSImage(contentsOf: asset.url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if asset.isVideo {
                    PowerVideoManagerVideoThumbnail(asset: asset, size: size)
                } else {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if asset?.isSelected == true {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                .padding(4)
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: asset?.isVideo == true ? "film" : "person.crop.rectangle")
            .font(.system(size: min(size.width, size.height) * 0.34, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct PowerVideoManagerVideoThumbnail: View {
    var asset: PowerVideoManagerAsset
    var size: CGSize

    @State private var isHovered = false
    @State private var posterImage: NSImage?

    var body: some View {
        ZStack {
            if isHovered {
                PowerVideoManagerHoverVideoPlayer(url: asset.url)
                    .transition(.opacity)
            } else if let posterImage {
                Image(nsImage: posterImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.18))
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: min(size.width, size.height) * 0.34, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(isHovered ? 0.20 : 0.34)],
                startPoint: .center,
                endPoint: .bottom
            )

            Image(systemName: isHovered ? "play.fill" : "film.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(5)
                .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(6)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onHover { hovered in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovered
            }
        }
        .task(id: asset.url) {
            posterImage = await PowerVideoManagerVideoPosterLoader.posterImage(for: asset.url, size: size)
        }
    }
}

private enum PowerVideoManagerVideoPosterLoader {
    static func posterImage(for url: URL, size: CGSize) async -> NSImage? {
        let maxPixelSize = max(size.width, size.height) * 3
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let data: Data?
        do {
            let time = CMTime(seconds: 0.2, preferredTimescale: 600)
            let image = try await generator.image(at: time).image
            let representation = NSBitmapImageRep(cgImage: image)
            data = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        } catch {
            data = nil
        }
        guard let data else { return nil }
        return NSImage(data: data)
    }
}

private struct PowerVideoManagerHoverVideoPlayer: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> PowerVideoManagerHoverVideoPlayerView {
        let view = PowerVideoManagerHoverVideoPlayerView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: PowerVideoManagerHoverVideoPlayerView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.configure(url: url)
    }

    static func dismantleNSView(_ nsView: PowerVideoManagerHoverVideoPlayerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private weak var view: PowerVideoManagerHoverVideoPlayerView?
        private var player: AVPlayer?
        private var playerURL: URL?
        private var endObserver: NSObjectProtocol?

        func attach(to view: PowerVideoManagerHoverVideoPlayerView) {
            self.view = view
            view.playerLayer.videoGravity = .resizeAspectFill
        }

        func configure(url: URL) {
            guard playerURL != url else {
                player?.play()
                return
            }
            stop()
            playerURL = url
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.actionAtItemEnd = .none
            view?.playerLayer.player = player
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            self.player = player
            player.play()
        }

        func stop() {
            player?.pause()
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            endObserver = nil
            view?.playerLayer.player = nil
            player = nil
            playerURL = nil
        }
    }
}

private final class PowerVideoManagerHoverVideoPlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private struct PowerVideoManagerMetric: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct PowerVideoManagerKeyValue: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func costLabel(_ cost: PowerVideoManagerCostSummary?) -> String {
    guard let cost else {
        return "Cost Unknown"
    }
    if let total = cost.total {
        return "\(cost.currency) \(String(format: "%.2f", total))"
    }
    return "\(cost.currency) Unknown"
}
