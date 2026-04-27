import SwiftUI

struct BookmarkVaultGearModuleView: View {
    var body: some View {
        BookmarkVaultGearWindow()
    }
}

struct BookmarkVaultGearWindow: View {
    @StateObject private var model = BookmarkVaultGearStore.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BookmarkVaultRootBackground()

                HStack(spacing: 0) {
                    commandPanel
                        .frame(width: min(max(proxy.size.width * 0.30, 340), 430))

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    bookmarkList
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    inspector
                        .frame(width: min(max(proxy.size.width * 0.30, 340), 430))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            model.loadBookmarks()
        }
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Image(systemName: "bookmark.square")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.mint.opacity(0.9))
                    Text("Bookmark Vault")
                        .font(.geeDisplaySemibold(27))
                        .foregroundStyle(.white.opacity(0.96))
                }

                Text("Save any note or URL. Media links get SmartYT-grade metadata first.")
                    .font(.geeBody(12))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Content")
                    .font(.geeDisplaySemibold(11))
                    .foregroundStyle(.white.opacity(0.52))

                TextEditor(text: $model.inputText)
                    .font(.geeBodyMedium(13))
                    .foregroundStyle(.white.opacity(0.92))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 150)
                    .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.11), lineWidth: 0.8)
                    }
            }

            BookmarkVaultCommandButton(
                title: "Save bookmark",
                subtitle: "Detect URL, fetch metadata, write file database",
                systemImage: model.isBusy ? "arrow.triangle.2.circlepath" : "plus.circle",
                accent: .mint
            ) {
                model.saveCurrentBookmark()
            }
            .disabled(model.isBusy)

            VStack(alignment: .leading, spacing: 9) {
                BookmarkVaultHintRow(icon: "play.rectangle", title: "Media sites", text: "yt-dlp metadata: title, platform, duration, thumbnail, formats.")
                BookmarkVaultHintRow(icon: "quote.bubble", title: "Twitter/X", text: "Tweet URLs use oEmbed first, then fall back to media/web fetch.")
                BookmarkVaultHintRow(icon: "globe", title: "General web", text: "OpenGraph, Twitter Card, canonical URL, title, description.")
            }

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

    private var bookmarkList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Saved Items")
                            .font(.geeDisplaySemibold(21))
                            .foregroundStyle(.white.opacity(0.92))
                        Text("\(model.bookmarks.count) bookmark\(model.bookmarks.count == 1 ? "" : "s") in the local file database")
                            .font(.geeBody(12))
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    Spacer()

                    Button {
                        model.loadBookmarks()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(width: 31, height: 31)
                            .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if model.bookmarks.isEmpty {
                    BookmarkVaultGlassPanel {
                        VStack(alignment: .leading, spacing: 11) {
                            Image(systemName: "bookmark.badge.plus")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.mint.opacity(0.82))
                            Text("Drop an idea, link, or media URL here")
                                .font(.geeDisplaySemibold(20))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("Bookmark Vault keeps the original content and enriches URLs when metadata is available.")
                                .font(.geeBody(13))
                                .foregroundStyle(.white.opacity(0.52))
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(model.bookmarks) { bookmark in
                            Button {
                                model.selectedBookmarkID = bookmark.id
                            } label: {
                                BookmarkVaultRow(
                                    bookmark: bookmark,
                                    isSelected: model.selectedBookmarkID == bookmark.id
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

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Inspector")
                    .font(.geeDisplaySemibold(18))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Button {
                    model.revealSelectedBookmark()
                } label: {
                    Label("Finder", systemImage: "folder")
                        .font(.geeDisplaySemibold(11))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.selectedBookmark == nil)
            }

            if let bookmark = model.selectedBookmark {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        BookmarkVaultPreviewCard(bookmark: bookmark)

                        HStack(spacing: 8) {
                            if bookmark.url != nil {
                                BookmarkVaultSmallButton(title: "Open", systemImage: "arrow.up.right") {
                                    model.openSelectedBookmarkURL()
                                }
                            }
                            BookmarkVaultSmallButton(title: "Reveal", systemImage: "doc.text.magnifyingglass") {
                                model.revealSelectedBookmark()
                            }
                            BookmarkVaultSmallButton(title: "Delete", systemImage: "trash", accent: .orange) {
                                model.deleteSelectedBookmark()
                            }
                        }

                        BookmarkVaultDetailSection(title: "Original Content", text: bookmark.rawContent)

                        if let description = bookmark.description?.nilIfBlank {
                            BookmarkVaultDetailSection(title: "Description", text: description)
                        }

                        if let localMediaPaths = bookmark.localMediaPaths, !localMediaPaths.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Local Media")
                                    .font(.geeDisplaySemibold(12))
                                    .foregroundStyle(.white.opacity(0.62))
                                ForEach(localMediaPaths, id: \.self) { path in
                                    Text(path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.66))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .frame(minHeight: 30, alignment: .center)
                                        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }

                        if !bookmark.extras.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Extra Fields")
                                    .font(.geeDisplaySemibold(12))
                                    .foregroundStyle(.white.opacity(0.62))
                                ForEach(bookmark.extras.keys.sorted(), id: \.self) { key in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(key)
                                            .font(.geeDisplaySemibold(10))
                                            .foregroundStyle(.white.opacity(0.44))
                                            .frame(width: 94, alignment: .leading)
                                        Text(bookmark.extras[key] ?? "")
                                            .font(.geeBody(11))
                                            .foregroundStyle(.white.opacity(0.68))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(12)
                                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
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
                    Text("Select a bookmark")
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
}

private struct BookmarkVaultRootBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.032, green: 0.046, blue: 0.054),
                    Color(red: 0.018, green: 0.021, blue: 0.030)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.mint.opacity(0.13))
                .blur(radius: 92)
                .frame(width: 360, height: 360)
                .offset(x: -270, y: -180)

            Circle()
                .fill(Color.cyan.opacity(0.10))
                .blur(radius: 110)
                .frame(width: 430, height: 430)
                .offset(x: 310, y: 230)
        }
        .ignoresSafeArea()
    }
}

private struct BookmarkVaultCommandButton: View {
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

private struct BookmarkVaultHintRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.geeDisplaySemibold(11))
                    .foregroundStyle(.white.opacity(0.72))
                Text(text)
                    .font(.geeBody(10))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BookmarkVaultGlassPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial.opacity(0.34), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            }
    }
}

private struct BookmarkVaultRow: View {
    let bookmark: BookmarkVaultRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 72, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    BookmarkVaultTag(bookmark.sourceLabel, accent: sourceColor)
                    if let platform = bookmark.platform?.nilIfBlank {
                        BookmarkVaultTag(platform)
                    }
                    if let ext = bookmark.extensionHint?.nilIfBlank {
                        BookmarkVaultTag(ext.uppercased())
                    }
                }

                Text(bookmark.displayTitle)
                    .font(.geeDisplaySemibold(13))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)

                Text(bookmark.subtitle)
                    .font(.geeBody(10))
                    .foregroundStyle(.white.opacity(0.40))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.geeBody(10))
                .foregroundStyle(.white.opacity(0.32))
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 11)
        .frame(height: 76)
        .background(
            isSelected ? Color.white.opacity(0.11) : Color.white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.mint.opacity(0.34) : Color.white.opacity(0.075), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            if let thumbnailURL = bookmark.thumbnailURL,
               let url = URL(string: thumbnailURL)
            {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [sourceColor.opacity(0.35), Color.black.opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var icon: String {
        switch bookmark.metadataSource {
        case "yt-dlp": "play.rectangle"
        case "twitter_oembed": "quote.bubble"
        case "basic_fetch": "globe"
        default: "text.badge.plus"
        }
    }

    private var sourceColor: Color {
        switch bookmark.metadataSource {
        case "yt-dlp": .cyan
        case "twitter_oembed": .blue
        case "basic_fetch": .mint
        default: .white
        }
    }
}

private struct BookmarkVaultPreviewCard: View {
    let bookmark: BookmarkVaultRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                BookmarkVaultTag(bookmark.sourceLabel, accent: .mint)
                if let siteName = bookmark.siteName?.nilIfBlank {
                    BookmarkVaultTag(siteName)
                }
                if let duration = bookmark.durationSeconds {
                    BookmarkVaultTag(durationText(duration))
                }
            }

            Text(bookmark.displayTitle)
                .font(.geeDisplaySemibold(20))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)

            if let url = bookmark.url?.nilIfBlank {
                Text(url)
                    .font(.geeBody(11))
                    .foregroundStyle(.white.opacity(0.44))
                    .textSelection(.enabled)
            }

            if let uploader = bookmark.uploader?.nilIfBlank {
                Text("by \(uploader)")
                    .font(.geeBodyMedium(11))
                    .foregroundStyle(.white.opacity(0.48))
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

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct BookmarkVaultSmallButton: View {
    let title: String
    let systemImage: String
    var accent: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.geeDisplaySemibold(11))
                .foregroundStyle(accent.opacity(0.78))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct BookmarkVaultDetailSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.geeDisplaySemibold(12))
                .foregroundStyle(.white.opacity(0.62))
            Text(text)
                .font(.geeBody(12))
                .foregroundStyle(.white.opacity(0.72))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

private struct BookmarkVaultTag: View {
    let text: String
    var accent: Color = .white

    init(_ text: String, accent: Color = .white) {
        self.text = text
        self.accent = accent
    }

    var body: some View {
        Text(text)
            .font(.geeDisplaySemibold(10))
            .foregroundStyle(accent.opacity(0.78))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
