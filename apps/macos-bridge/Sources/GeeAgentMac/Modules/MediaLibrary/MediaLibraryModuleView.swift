import AppKit
import AVFoundation
import AVKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

struct MediaLibraryModuleView: View {
    private let galleryScrollCoordinateSpace = "media-library-gallery-scroll"

    @Bindable var store: MediaLibraryModuleStore
    @State private var isCreatingFolder = false
    @State private var folderName = ""
    @State private var isDropTargeted = false
    @State private var isSidebarVisible = true
    @State private var isImmersive = false
    @State private var isDynamicShowcaseEnabled = false
    @State private var quickLookController = MediaLibraryQuickLookController()
    @State private var nativePreviewController = MediaLibraryNativePreviewController()
    @State private var isChoosingLibrary = false
    @State private var visibleDynamicItemIDs: Set<MediaLibraryItem.ID> = []

    init(store: MediaLibraryModuleStore = .shared) {
        self.store = store
    }

    var body: some View {
        ZStack {
            MediaLibraryBackdrop()
            VStack(spacing: 0) {
                if let library = store.library {
                    librarySurface(library)
                } else {
                    welcomeSurface
                }
            }
        }
        .task {
            await store.restoreLastLibraryIfNeeded()
        }
        .onDeleteCommand {
            Task { await store.deleteSelectedItems() }
        }
        .onExitCommand {
            store.selectedItemIDs.removeAll()
            store.focusedItemID = nil
        }
        .background {
            MediaLibrarySpaceKeyMonitor {
                showQuickLook()
            }
        }
        .sheet(isPresented: $isCreatingFolder) {
            MediaFolderSheet(
                title: "New Folder",
                name: $folderName,
                confirmTitle: "Create",
                onCancel: {
                    isCreatingFolder = false
                    folderName = ""
                },
                onConfirm: {
                    let name = folderName
                    isCreatingFolder = false
                    folderName = ""
                    Task { await store.createFolder(named: name) }
                }
            )
        }
        .sheet(isPresented: $isChoosingLibrary) {
            MediaLibraryChooserSheet(
                currentLibrary: store.library,
                history: store.libraryHistory,
                onCancel: { isChoosingLibrary = false },
                onOpenHistory: { entry in
                    isChoosingLibrary = false
                    Task { await store.restoreLibraryFromHistory(entry) }
                },
                onOpenOther: {
                    isChoosingLibrary = false
                    Task { await store.chooseLibrary() }
                },
                onCreateLibrary: {
                    isChoosingLibrary = false
                    Task { await store.createLibrary() }
                }
            )
        }
    }

    private var welcomeSurface: some View {
        VStack(spacing: 22) {
            VStack(spacing: 16) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 42, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 7) {
                    Text("Media Library")
                        .font(.geeDisplaySemibold(28))
                    Text("Open an Eagle-compatible library or create a native Gee media library.")
                        .font(.geeBody(13))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await store.chooseLibrary() }
                    } label: {
                        Label("Open Library", systemImage: "folder")
                    }
                    .buttonStyle(EaglePillButtonStyle(variant: .primary))

                    Button {
                        Task { await store.createLibrary() }
                    } label: {
                        Label("Create Library", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(EaglePillButtonStyle())
                }
            }
            .padding(28)
            .frame(width: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )

            if !store.libraryHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.geeBodyMedium(12))
                        .foregroundStyle(.secondary)
                    ForEach(store.libraryHistory.prefix(5)) { entry in
                        Button {
                            Task { await store.restoreLibraryFromHistory(entry) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.name)
                                        .font(.geeBodyMedium(12))
                                    Text(entry.path)
                                        .font(.geeBody(10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(width: 420, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            statusBar
        }
    }

    private func librarySurface(_ library: MediaLibraryInfo) -> some View {
        ZStack {
            if isImmersive {
                immersiveSurface(library)
            } else {
                VStack(spacing: 0) {
                    toolbar(library)
                    Divider().opacity(0.18)
                    HStack(spacing: 0) {
                        if isSidebarVisible {
                            sidebar
                            Divider().opacity(0.16)
                        }
                        gallery(showFilters: true)
                        Divider().opacity(0.16)
                        inspector
                    }
                    statusBar
                }
            }
            if isDropTargeted {
                MediaLibraryDropOverlay()
                    .padding(24)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await store.importMedia(at: urls) }
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .animation(.easeInOut(duration: 0.18), value: isDropTargeted)
    }

    private func clearSelection() {
        store.selectedItemIDs.removeAll()
        store.focusedItemID = nil
    }

    private func showQuickLook() {
        let previewItems = selectedPreviewItems()
        guard !previewItems.isEmpty else { return }
        if previewItems.count == 1, let item = previewItems.first, item.mediaKind == .video {
            nativePreviewController.toggleVideoPreview(item)
            return
        }
        let focusedIndex = previewItems.firstIndex { $0.id == store.focusedItemID } ?? 0
        quickLookController.preview(
            urls: previewItems.map(\.fileURL),
            initialIndex: focusedIndex
        )
    }

    private func selectedPreviewItems() -> [MediaLibraryItem] {
        let selected = store.filteredItems.filter { store.selectedItemIDs.contains($0.id) }
        if !selected.isEmpty {
            return selected
        }
        if let focusedItem = store.focusedItem {
            return [focusedItem]
        }
        return []
    }

    private var dynamicPreviewIDs: Set<MediaLibraryItem.ID> {
        guard isDynamicShowcaseEnabled else { return [] }
        return visibleDynamicItemIDs
    }

    private func immersiveSurface(_ library: MediaLibraryInfo) -> some View {
        ZStack(alignment: .bottom) {
            gallery(showFilters: false)
                .background(Color.black)
            MediaLibraryFloatingToolbar(
                thumbnailSize: $store.thumbnailSize,
                dynamicPlayback: $isDynamicShowcaseEnabled,
                onRefresh: { Task { await store.refresh() } },
                onExit: { isImmersive = false }
            )
            .padding(.bottom, 18)
        }
        .background(Color.black)
    }

    private func toolbar(_ library: MediaLibraryInfo) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                GeeFocusBadge()
                Button {
                    isChoosingLibrary = true
                } label: {
                    Label("Switch library", systemImage: "rectangle.2.swap")
                }
                .buttonStyle(EaglePillButtonStyle())
            }

            Spacer(minLength: 0)

            Button {
                Task { await store.importFilesWithPanel() }
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(EaglePillButtonStyle(variant: .primary))

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(EagleIconButtonStyle())
            .help("Refresh")

            Button {
                isImmersive = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(EagleIconButtonStyle())
            .help("Enter viewer mode")

            Button {
                isDynamicShowcaseEnabled.toggle()
            } label: {
                Image(systemName: isDynamicShowcaseEnabled ? "livephoto" : "livephoto.slash")
            }
            .buttonStyle(EagleIconButtonStyle(isActive: isDynamicShowcaseEnabled))
            .help("Dynamic showcase plays every visible GIF and video; hover any GIF or video to play it immediately.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Folders")
                    .font(.geeDisplaySemibold(12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    folderName = ""
                    isCreatingFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(EagleIconButtonStyle(compact: true))
                .help("New folder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 2) {
                    folderRow(id: nil, name: "All", count: store.items.count, icon: "rectangle.grid.2x2")
                    folderRow(
                        id: MediaLibrarySpecialFolder.uncategorizedID,
                        name: "Uncategorized",
                        count: store.items.filter { $0.folderIDs.isEmpty }.count,
                        icon: "questionmark.folder"
                    )
                    ForEach(store.folders) { folder in
                        folderRow(
                            id: folder.id,
                            name: folder.name,
                            count: store.items.filter { $0.folderIDs.contains(folder.id) }.count,
                            icon: "folder",
                            depth: folder.depth
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }

            if !store.selectedItemIDs.isEmpty {
                Divider().opacity(0.18)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(store.selectedItemIDs.count) selected")
                        .font(.geeBodyMedium(11))
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        Task { await store.deleteSelectedItems() }
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EaglePillButtonStyle(variant: .danger))
                }
                .padding(10)
            }
        }
        .frame(width: 220)
        .background(EaglePalette.sidebar)
    }

    private func folderRow(id: String?, name: String, count: Int, icon: String, depth: Int = 0) -> some View {
        let isSelected = store.selectedFolderID == id
        return Button {
            store.selectFolder(id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                Text(name)
                    .font(.geeBodyMedium(12))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.geeDisplaySemibold(9))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.86) : Color.secondary)
            }
            .padding(.leading, CGFloat(depth) * 12)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(isSelected ? EaglePalette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.1) : Color.clear, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func gallery(showFilters: Bool) -> some View {
        VStack(spacing: 0) {
            if showFilters {
                filterBar
            }
            GeometryReader { scrollProxy in
                ScrollView {
                    ZStack(alignment: .top) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                clearSelection()
                            }

                        if store.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 260)
                        } else if store.filteredItems.isEmpty {
                            emptyGallery
                        } else {
                            let dynamicPreviewIDs = dynamicPreviewIDs
                            JustifiedMediaGridLayout(
                                targetHeight: CGFloat(store.thumbnailSize),
                                spacing: isImmersive ? 2 : 12
                            ) {
                                ForEach(store.filteredItems) { item in
                                    MediaLibraryItemTile(
                                        item: item,
                                        isSelected: store.selectedItemIDs.contains(item.id),
                                        isFocused: store.focusedItemID == item.id,
                                        dynamicPlayback: dynamicPreviewIDs.contains(item.id),
                                        isImmersive: isImmersive,
                                        onSelect: { preserving in
                                            store.toggleSelection(for: item, preservingExisting: preserving)
                                        },
                                        onToggleStar: {
                                            Task { await store.toggleStarred(item) }
                                        },
                                        onMove: { folderID in
                                            if !store.selectedItemIDs.contains(item.id) {
                                                store.selectedItemIDs = [item.id]
                                            }
                                            store.focusedItemID = item.id
                                            Task { await store.moveSelectedItems(to: folderID) }
                                        },
                                        onOpen: {
                                            store.focusedItemID = item.id
                                            store.openFocusedItem()
                                        },
                                        onReveal: {
                                            store.focusedItemID = item.id
                                            store.selectedItemIDs = [item.id]
                                            store.revealFocusedItem()
                                        },
                                        onDelete: {
                                            store.focusedItemID = item.id
                                            store.selectedItemIDs = [item.id]
                                            Task { await store.deleteSelectedItems() }
                                        },
                                        folders: store.folders
                                    )
                                    .background(
                                        MediaLibraryVisibilityReporter(
                                            itemID: item.id,
                                            isEnabled: item.isDynamicPreviewable,
                                            viewportSize: scrollProxy.size,
                                            coordinateSpaceName: galleryScrollCoordinateSpace,
                                            onVisibilityChange: updateDynamicVisibility
                                        )
                                    )
                                    .layoutValue(
                                        key: MediaLibraryAspectRatioKey.self,
                                        value: mediaAspectRatio(for: item)
                                    )
                                }
                            }
                            .padding(isImmersive ? 2 : 14)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .top)
                }
                .coordinateSpace(name: galleryScrollCoordinateSpace)
            }
            .background(isImmersive ? Color.black : Color.black.opacity(0.12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.filteredItems.map(\.id)) { _, ids in
            visibleDynamicItemIDs.formIntersection(Set(ids))
        }
    }

    private func updateDynamicVisibility(itemID: MediaLibraryItem.ID, isVisible: Bool) {
        if isVisible {
            visibleDynamicItemIDs.insert(itemID)
        } else {
            visibleDynamicItemIDs.remove(itemID)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Button {
                isSidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(EagleIconButtonStyle(isActive: isSidebarVisible))
            .help(isSidebarVisible ? "Hide folders" : "Show folders")

            MediaKindSegmentedPicker(selection: $store.filter.mediaKind)

            Button {
                store.filter.starredOnly.toggle()
            } label: {
                Image(systemName: "star.fill")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(EaglePillButtonStyle(isActive: store.filter.starredOnly))
            .help("Starred only")

            TextField("Search name, tags, notes", text: $store.filter.searchText)
                .textFieldStyle(.plain)
                .font(.geeBody(12))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(EaglePalette.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
                .frame(maxWidth: 260)

            Spacer(minLength: 0)

            MediaSizeSlider(value: $store.thumbnailSize)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var emptyGallery: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No media matches the current view.")
                .font(.geeBodyMedium(13))
                .foregroundStyle(.secondary)
            Button {
                Task { await store.importFilesWithPanel() }
            } label: {
                Label("Import Media", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(EaglePillButtonStyle(variant: .primary))
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = store.focusedItem {
                MediaLibraryInspector(item: item, store: store)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inspector")
                        .font(.geeDisplaySemibold(13))
                        .foregroundStyle(.secondary)
                    Text("Select an item to inspect metadata, preview media, or reveal it in Finder.")
                        .font(.geeBody(12))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(EaglePalette.sidebar)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if store.library != nil {
                Text(store.visibleSummary)
                    .foregroundStyle(.secondary)
                if !store.filter.selectedExtensions.isEmpty
                    || store.filter.starredOnly
                    || store.filter.mediaKind != .all
                    || store.filter.minimumDurationSeconds != nil
                    || !store.filter.searchText.isEmpty
                {
                    Text("Filtered")
                        .font(.geeDisplaySemibold(9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            } else {
                Text("Optional gear. Enable and open it when you need media management.")
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .font(.geeBody(11))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(EaglePalette.panel.opacity(0.92))
    }
}

private enum EaglePalette {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let panel = Color(red: 0.14, green: 0.145, blue: 0.155)
    static let toolbar = Color(red: 0.16, green: 0.165, blue: 0.18)
    static let sidebar = Color(red: 0.125, green: 0.13, blue: 0.14)
    static let control = Color(red: 0.18, green: 0.185, blue: 0.2)
    static let hover = Color(red: 0.22, green: 0.225, blue: 0.245)
    static let accent = Color(red: 0.31, green: 0.27, blue: 0.9)
    static let accentHover = Color(red: 0.39, green: 0.35, blue: 0.96)
    static let danger = Color(red: 0.86, green: 0.23, blue: 0.24)
}

private final class MediaLibraryQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var previewURLs: [NSURL] = []

    @MainActor
    func preview(urls: [URL], initialIndex: Int) {
        previewURLs = urls.map { $0 as NSURL }
        guard !previewURLs.isEmpty, let panel = QLPreviewPanel.shared() else {
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = min(max(initialIndex, 0), previewURLs.count - 1)
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewURLs.indices.contains(index) else {
            return nil
        }
        return previewURLs[index]
    }
}

@MainActor
private final class MediaLibraryNativePreviewController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var player: AVPlayer?
    private var previewURL: URL?

    func toggleVideoPreview(_ item: MediaLibraryItem) {
        if previewURL == item.fileURL, window?.isVisible == true {
            tearDownPreview(closeWindow: true)
            return
        }

        tearDownPreview(closeWindow: true)
        previewURL = item.fileURL
        let player = AVPlayer(url: item.fileURL)
        self.player = player

        let playerView = AVPlayerView(frame: NSRect(x: 0, y: 0, width: 960, height: 620))
        playerView.player = player
        playerView.controlsStyle = .floating

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = item.name
        window.contentView = playerView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        player.play()
    }

    func windowWillClose(_ notification: Notification) {
        tearDownPreview(closeWindow: false)
    }

    private func tearDownPreview(closeWindow: Bool) {
        let previewWindow = window
        window = nil
        previewURL = nil
        player?.pause()
        player = nil
        previewWindow?.delegate = nil
        previewWindow?.contentView = nil
        if closeWindow {
            previewWindow?.close()
        }
    }
}

private struct MediaLibrarySpaceKeyMonitor: NSViewRepresentable {
    var onSpace: () -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install(onSpace: onSpace)
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSpace = onSpace
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        var onSpace: (() -> Void)?
        private var monitor: Any?

        func install(onSpace: @escaping () -> Void) {
            self.onSpace = onSpace
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 49, !Self.isTextInputActive else {
                    return event
                }
                self?.onSpace?()
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private static var isTextInputActive: Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else {
                return false
            }
            return responder is NSTextView || responder is NSTextField
        }
    }
}

private struct EaglePillButtonStyle: ButtonStyle {
    enum Variant {
        case normal
        case primary
        case danger
    }

    var variant: Variant = .normal
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.geeBodyMedium(12))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.8)
            )
            .shadow(color: shadowColor, radius: isActive || variant == .primary ? 10 : 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch variant {
        case .normal:
            return isActive ? .white : Color.white.opacity(0.86)
        case .primary, .danger:
            return .white
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        let base: Color
        switch variant {
        case .normal:
            base = isActive ? EaglePalette.accent : EaglePalette.control
        case .primary:
            base = EaglePalette.accent
        case .danger:
            base = EaglePalette.danger
        }
        return isPressed ? base.opacity(0.76) : base
    }

    private var borderColor: Color {
        if isActive || variant == .primary {
            return Color.white.opacity(0.16)
        }
        return Color.white.opacity(0.08)
    }

    private var shadowColor: Color {
        switch variant {
        case .normal:
            return isActive ? EaglePalette.accent.opacity(0.22) : .clear
        case .primary:
            return EaglePalette.accent.opacity(0.24)
        case .danger:
            return EaglePalette.danger.opacity(0.2)
        }
    }
}

private struct EagleIconButtonStyle: ButtonStyle {
    var isActive = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 13, weight: .semibold))
            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.82))
            .frame(width: compact ? 25 : 31, height: compact ? 25 : 31)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .stroke(isActive ? EaglePalette.accentHover.opacity(0.52) : Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .shadow(color: isActive ? EaglePalette.accent.opacity(0.22) : .clear, radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isActive {
            return isPressed ? EaglePalette.accent.opacity(0.76) : EaglePalette.accent
        }
        return isPressed ? EaglePalette.hover : EaglePalette.control
    }
}

private struct EagleDropdownLabel: View {
    let title: String
    let systemImage: String
    var fillWidth = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.geeBodyMedium(12))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.48))
        }
        .foregroundStyle(Color.white.opacity(0.86))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: fillWidth ? .infinity : nil)
        .background(EaglePalette.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }
}

private struct GeeFocusBadge: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(isPulsing ? 0.16 : 0.34))
                    .frame(width: isPulsing ? 19 : 11, height: isPulsing ? 19 : 11)
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.green.opacity(0.62), radius: 7)
            }
            .frame(width: 20, height: 20)

            Text("Gee Focus")
                .font(.geeDisplaySemibold(13))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(EaglePalette.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task {
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct MediaKindSegmentedPicker: View {
    @Binding var selection: MediaLibraryMediaKind

    private let options: [(MediaLibraryMediaKind, String, String)] = [
        (.all, "All", "rectangle.grid.2x2"),
        (.image, "Images", "photo"),
        (.video, "Videos", "film"),
    ]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { option in
                let isSelected = selection == option.0
                Button {
                    selection = option.0
                } label: {
                    Label(option.1, systemImage: option.2)
                        .labelStyle(.titleAndIcon)
                        .font(.geeBodyMedium(11))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.68))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .frame(width: 74)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(isSelected ? EaglePalette.accent : EaglePalette.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 228)
    }
}

private struct MediaSizeSlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.58))
            EagleSmoothSlider(value: $value, range: 110...320)
                .frame(width: 124, height: 16)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(EaglePalette.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct EagleSmoothSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                .clamped(to: 0...1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 4)
                Capsule()
                    .fill(EaglePalette.accent)
                    .frame(width: width * progress, height: 4)
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 11, height: 11)
                    .shadow(color: EaglePalette.accent.opacity(0.34), radius: 6, y: 2)
                    .offset(x: max(0, min(width - 11, width * progress - 5.5)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let ratio = Double((gesture.location.x / width).clamped(to: 0...1))
                        value = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}

private struct MediaLibraryBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    EaglePalette.background,
                    EaglePalette.panel,
                    Color.black.opacity(0.24),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.clear,
                ],
                center: .topTrailing,
                startRadius: 80,
                endRadius: 640
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.clear,
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 540
            )
        }
        .ignoresSafeArea()
    }
}

private struct MediaLibraryDropOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 42, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 4) {
                Text("Drop media to import")
                    .font(.geeDisplaySemibold(19))
                Text("Images and videos are copied into the current Eagle-compatible library.")
                    .font(.geeBody(12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.16))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(0.72),
                    style: StrokeStyle(lineWidth: 2, dash: [10, 8], dashPhase: 2)
                )
        )
        .shadow(color: .black.opacity(0.24), radius: 28, y: 16)
    }
}

private struct MediaLibraryFloatingToolbar: View {
    @Binding var thumbnailSize: Double
    @Binding var dynamicPlayback: Bool
    var onRefresh: () -> Void
    var onExit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onExit) {
                Label("Exit viewer", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(EagleIconButtonStyle())
            .help("Exit viewer mode")

            Divider()
                .frame(height: 26)
                .opacity(0.25)

            Button {
                dynamicPlayback.toggle()
            } label: {
                Image(systemName: dynamicPlayback ? "livephoto" : "livephoto.slash")
            }
            .buttonStyle(EagleIconButtonStyle(isActive: dynamicPlayback))
            .help("Dynamic showcase plays every visible GIF and video; hover any GIF or video to play it immediately.")

            MediaSizeSlider(value: $thumbnailSize)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(EagleIconButtonStyle())
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(EaglePalette.panel.opacity(0.82), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.34), radius: 26, y: 12)
        .padding(.horizontal, 24)
    }
}

private struct MediaLibraryAspectRatioKey: LayoutValueKey {
    static let defaultValue: CGFloat = 4 / 3
}

private struct MediaLibraryVisibilityReporter: View {
    let itemID: MediaLibraryItem.ID
    let isEnabled: Bool
    let viewportSize: CGSize
    let coordinateSpaceName: String
    var onVisibilityChange: (MediaLibraryItem.ID, Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(coordinateSpaceName))
            Color.clear
                .onAppear {
                    report(frame)
                }
                .onChange(of: frame) { _, newFrame in
                    report(newFrame)
                }
                .onChange(of: isEnabled) { _, _ in
                    report(frame)
                }
                .onDisappear {
                    onVisibilityChange(itemID, false)
                }
        }
    }

    private func report(_ frame: CGRect) {
        guard isEnabled else {
            onVisibilityChange(itemID, false)
            return
        }
        let viewport = CGRect(origin: .zero, size: viewportSize)
            .insetBy(dx: -24, dy: -96)
        onVisibilityChange(itemID, frame.intersects(viewport))
    }
}

private struct JustifiedMediaGridLayout: Layout {
    var targetHeight: CGFloat
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else {
            return .zero
        }

        let width = max(proposal.width ?? targetHeight * 4, targetHeight)
        let rows = makeRows(for: subviews, availableWidth: width)
        let totalHeight = rows.reduce(CGFloat.zero) { $0 + $1.height }
            + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = makeRows(for: subviews, availableWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for cell in row.cells {
                subviews[cell.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: cell.width, height: row.height)
                )
                x += cell.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func makeRows(for subviews: Subviews, availableWidth: CGFloat) -> [JustifiedMediaRow] {
        let width = max(availableWidth, targetHeight)
        var rows: [JustifiedMediaRow] = []
        var pending: [Int] = []
        var pendingAspectSum: CGFloat = 0

        for index in subviews.indices {
            let aspect = aspectRatio(for: subviews[index])
            let projectedCount = pending.count + 1
            let projectedAspectSum = pendingAspectSum + aspect
            let projectedWidth = projectedAspectSum * targetHeight + spacing * CGFloat(max(projectedCount - 1, 0))

            if projectedWidth > width, !pending.isEmpty {
                rows.append(makeRow(indices: pending, aspectSum: pendingAspectSum, availableWidth: width, stretchToFill: true, subviews: subviews))
                pending = [index]
                pendingAspectSum = aspect
            } else {
                pending.append(index)
                pendingAspectSum = projectedAspectSum
            }
        }

        if !pending.isEmpty {
            rows.append(makeRow(indices: pending, aspectSum: pendingAspectSum, availableWidth: width, stretchToFill: false, subviews: subviews))
        }

        return rows
    }

    private func makeRow(
        indices: [Int],
        aspectSum: CGFloat,
        availableWidth: CGFloat,
        stretchToFill: Bool,
        subviews: Subviews
    ) -> JustifiedMediaRow {
        let safeAspectSum = max(aspectSum, 0.1)
        let gaps = spacing * CGFloat(max(indices.count - 1, 0))
        let fillHeight = (availableWidth - gaps) / safeAspectSum
        let height = stretchToFill
            ? min(max(fillHeight, targetHeight * 0.72), targetHeight * 1.28)
            : targetHeight

        let cells = indices.map { index in
            let width = min(aspectRatio(for: subviews[index]) * height, availableWidth)
            return JustifiedMediaCell(index: index, width: max(width, 64))
        }

        return JustifiedMediaRow(height: height, cells: cells)
    }

    private func aspectRatio(for subview: LayoutSubview) -> CGFloat {
        max(min(subview[MediaLibraryAspectRatioKey.self], 8), 0.2)
    }
}

private struct JustifiedMediaRow {
    var height: CGFloat
    var cells: [JustifiedMediaCell]
}

private struct JustifiedMediaCell {
    var index: Int
    var width: CGFloat
}

private struct MediaLibraryItemTile: View {
    let item: MediaLibraryItem
    let isSelected: Bool
    let isFocused: Bool
    let dynamicPlayback: Bool
    let isImmersive: Bool
    var onSelect: (Bool) -> Void
    var onToggleStar: () -> Void
    var onMove: (String?) -> Void
    var onOpen: () -> Void
    var onReveal: () -> Void
    var onDelete: () -> Void
    let folders: [MediaLibraryFolder]

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MediaLibraryPreview(item: item, dynamicPlayback: dynamicPlayback || (isHovering && item.isDynamicPreviewable))
                .frame(maxWidth: .infinity)
                .aspectRatio(itemAspectRatio, contentMode: .fit)
                .background(Color.black.opacity(0.3))

            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(isHovering || isSelected || isFocused ? 0.82 : 0.58),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 92)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .opacity(overlayOpacity)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.geeBodyMedium(12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(metadataLine)
                    .font(.geeBody(10))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(10)
            .opacity(overlayOpacity)

            HStack(alignment: .top, spacing: 6) {
                HStack(spacing: 4) {
                    Text(item.ext.uppercased())
                        .font(.geeDisplaySemibold(9))
                    if item.mediaKind == .video {
                        Image(systemName: "film")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.46), in: Capsule())

                Spacer(minLength: 0)

                Button {
                    onToggleStar()
                } label: {
                    Image(systemName: item.isStarred ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.isStarred ? Color.yellow : Color.white.opacity(0.9))
                        .frame(width: 25, height: 25)
                        .background(Color.black.opacity(0.46), in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(isImmersive ? (isHovering ? 1 : 0) : (isHovering || item.isStarred || isSelected ? 1 : 0))
                .help(item.isStarred ? "Remove star" : "Star")
            }
            .padding(7)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(isImmersive ? (isHovering ? 1 : 0) : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: tileRadius, style: .continuous))
        .background(tileBackground, in: RoundedRectangle(cornerRadius: tileRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                .stroke(tileStroke, lineWidth: isFocused ? 1.4 : 0.8)
        )
        .shadow(color: tileShadow, radius: isHovering || isFocused ? 12 : 4, y: isHovering || isFocused ? 8 : 2)
        .scaleEffect(isHovering ? 1.01 : 1)
        .contentShape(RoundedRectangle(cornerRadius: tileRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture {
            let preservingSelection = NSEvent.modifierFlags.contains(.command)
                || NSEvent.modifierFlags.contains(.shift)
                || NSEvent.modifierFlags.contains(.control)
            onSelect(preservingSelection)
        }
        .onTapGesture(count: 2) {
            onOpen()
        }
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }

            Button {
                onReveal()
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button {
                onToggleStar()
            } label: {
                Label(item.isStarred ? "Remove Star" : "Star", systemImage: item.isStarred ? "star.slash" : "star")
            }

            Menu {
                Text("Current: \(currentFolderName)")
                Divider()
                Button {
                    onMove(nil)
                } label: {
                    Label("Uncategorized", systemImage: item.folderIDs.isEmpty ? "checkmark" : "folder")
                }
                ForEach(folders) { folder in
                    Button {
                        onMove(folder.id)
                    } label: {
                        Label(folder.name, systemImage: item.folderIDs.contains(folder.id) ? "checkmark" : "folder")
                    }
                }
            } label: {
                Label("Move to", systemImage: "folder")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityHint("Select the media item. Double click to open it.")
        .animation(.easeInOut(duration: 0.14), value: isHovering)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }

    private var itemAspectRatio: CGFloat {
        mediaAspectRatio(for: item)
    }

    private var metadataLine: String {
        var parts = [mediaSizeString(item.size)]
        if let duration = item.durationSeconds {
            parts.append(durationString(duration))
        }
        return parts.joined(separator: "  /  ")
    }

    private var currentFolderName: String {
        guard let firstFolderID = item.folderIDs.first else {
            return "Uncategorized"
        }
        return folders.first(where: { $0.id == firstFolderID })?.name ?? "Unknown"
    }

    private var overlayOpacity: Double {
        if isImmersive {
            return isHovering ? 1 : 0
        }
        return isHovering || isSelected || isFocused ? 1 : 0.82
    }

    private var tileRadius: CGFloat {
        isImmersive ? 3 : 10
    }

    private var tileBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.3)
        }
        return Color.white.opacity(isHovering ? 0.12 : 0.05)
    }

    private var tileStroke: Color {
        if isFocused {
            return Color.accentColor.opacity(0.85)
        }
        if isSelected {
            return Color.accentColor.opacity(0.55)
        }
        return Color.white.opacity(0.08)
    }

    private var tileShadow: Color {
        if isFocused || isSelected {
            return Color.accentColor.opacity(0.26)
        }
        return Color.black.opacity(isHovering ? 0.28 : 0.16)
    }
}

private struct MediaLibraryPreview: View {
    let item: MediaLibraryItem
    var dynamicPlayback = false

    var body: some View {
        ZStack {
            if dynamicPlayback, item.mediaKind == .video {
                MediaLibraryVideoAutoplayView(url: item.fileURL)
            } else if dynamicPlayback, item.ext.lowercased() == "gif" {
                MediaLibraryAnimatedImageView(url: item.fileURL)
            } else if let thumbnailURL = item.thumbnailURL, let image = NSImage(contentsOf: thumbnailURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: item.mediaKind == .video ? "film" : "photo")
                        .font(.system(size: 26))
                    Text(item.ext.uppercased())
                        .font(.geeDisplaySemibold(10))
                }
                .foregroundStyle(.secondary)
            }

            if item.mediaKind == .video, !dynamicPlayback {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(9)
                    .background(Color.black.opacity(0.42), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .clipped()
    }
}

private struct MediaLibraryAnimatedImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.canDrawSubviewsIntoLayer = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        if imageView.image == nil || context.coordinator.url != url {
            context.coordinator.url = url
            imageView.image = NSImage(contentsOf: url)
            imageView.animates = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var url: URL?
    }
}

private struct MediaLibraryVideoAutoplayView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.masksToBounds = true
        return view
    }

    func updateNSView(_ view: PlayerContainerView, context: Context) {
        guard context.coordinator.url != url else {
            context.coordinator.player?.play()
            return
        }

        context.coordinator.url = url
        context.coordinator.player?.pause()
        if let observer = context.coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
            context.coordinator.observer = nil
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        context.coordinator.player = player
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        view.playerLayer.player = player
        player.play()
    }

    static func dismantleNSView(_ view: PlayerContainerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var url: URL?
        var player: AVPlayer?
        var observer: NSObjectProtocol?
    }

    final class PlayerContainerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }
}

private struct MediaLibraryInspector: View {
    let item: MediaLibraryItem
    @Bindable var store: MediaLibraryModuleStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MediaLibraryPreview(item: item)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.geeDisplaySemibold(15))
                        .lineLimit(2)
                    Text(item.fileURL.lastPathComponent)
                        .font(.geeBody(10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                HStack {
                    Button {
                        store.openFocusedItem()
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(EaglePillButtonStyle(variant: .primary))
                    Button {
                        store.revealFocusedItem()
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .buttonStyle(EaglePillButtonStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    inspectorRow("Type", item.ext.uppercased())
                    inspectorRow("Size", mediaSizeString(item.size))
                    if let width = item.width, let height = item.height {
                        inspectorRow("Dimensions", "\(width) x \(height)")
                    }
                    if let duration = item.durationSeconds {
                        inspectorRow("Duration", durationString(duration))
                    }
                    inspectorRow("Starred", item.isStarred ? "Yes" : "No")
                    inspectorRow("Modified", item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                }

                if !item.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags")
                            .font(.geeBodyMedium(11))
                            .foregroundStyle(.secondary)
                        FlowPills(values: item.tags)
                    }
                }

                if let annotation = item.annotation, !annotation.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Notes")
                            .font(.geeBodyMedium(11))
                            .foregroundStyle(.secondary)
                        Text(annotation)
                            .font(.geeBody(11))
                            .foregroundStyle(.primary.opacity(0.88))
                    }
                }
            }
            .padding(14)
        }
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.geeBody(10))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.geeBodyMedium(11))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

private struct MediaLibraryChooserSheet: View {
    let currentLibrary: MediaLibraryInfo?
    let history: [MediaLibraryHistoryEntry]
    var onCancel: () -> Void
    var onOpenHistory: (MediaLibraryHistoryEntry) -> Void
    var onOpenOther: () -> Void
    var onCreateLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                GeeFocusBadge()
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(EagleIconButtonStyle(compact: true))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Choose Library")
                    .font(.geeDisplaySemibold(22))
                if let currentLibrary {
                    Text(currentLibrary.url.path)
                        .font(.geeBody(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(history.prefix(8)) { entry in
                        Button {
                            onOpenHistory(entry)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: entry.path == currentLibrary?.url.path ? "checkmark.circle.fill" : "folder")
                                    .foregroundStyle(entry.path == currentLibrary?.url.path ? EaglePalette.accentHover : Color.white.opacity(0.58))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(.geeBodyMedium(12))
                                        .lineLimit(1)
                                    Text(entry.path)
                                        .font(.geeBody(10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(EaglePalette.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 220)

            HStack {
                Button(action: onOpenOther) {
                    Label("Open Other", systemImage: "folder")
                }
                .buttonStyle(EaglePillButtonStyle(variant: .primary))

                Button(action: onCreateLibrary) {
                    Label("Create Library", systemImage: "folder.badge.plus")
                }
                .buttonStyle(EaglePillButtonStyle())
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(EaglePalette.panel)
    }
}

private struct FlowPills: View {
    let values: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 5)], alignment: .leading, spacing: 5) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.geeDisplaySemibold(9))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
    }
}

private struct MediaFolderSheet: View {
    let title: String
    @Binding var name: String
    let confirmTitle: String
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.geeDisplaySemibold(16))
            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}

private func mediaSizeString(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

private func durationString(_ seconds: Double) -> String {
    let total = max(Int(seconds.rounded()), 0)
    let minutes = total / 60
    let remaining = total % 60
    return "\(minutes):\(String(format: "%02d", remaining))"
}

private func mediaAspectRatio(for item: MediaLibraryItem) -> CGFloat {
    guard let width = item.width, let height = item.height, width > 0, height > 0 else {
        return item.mediaKind == .video ? 16 / 9 : 4 / 3
    }
    return max(min(CGFloat(width) / CGFloat(height), 8), 0.2)
}

private extension MediaLibraryItem {
    var isDynamicPreviewable: Bool {
        mediaKind == .video || ext.lowercased() == "gif"
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
