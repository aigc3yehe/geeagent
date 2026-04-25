import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class MediaLibraryModuleStore {
    static let shared = MediaLibraryModuleStore()

    private enum PreferenceKey {
        static let lastLibraryPath = "geeagent.mediaLibrary.lastLibraryPath"
        static let libraryHistory = "geeagent.mediaLibrary.libraryHistory"
    }

    private let service = MediaLibraryService()
    private let defaults: UserDefaults

    var library: MediaLibraryInfo?
    var items: [MediaLibraryItem] = []
    var folders: [MediaLibraryFolder] = []
    var selectedFolderID: String?
    var filter = MediaLibraryFilterState()
    var selectedItemIDs: Set<MediaLibraryItem.ID> = []
    var focusedItemID: MediaLibraryItem.ID?
    var thumbnailSize: Double = 190
    var isLoading = false
    var errorMessage: String?
    var libraryHistory: [MediaLibraryHistoryEntry] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.libraryHistory = Self.loadHistory(from: defaults)
    }

    var focusedItem: MediaLibraryItem? {
        guard let focusedItemID else { return nil }
        return items.first(where: { $0.id == focusedItemID })
    }

    var availableExtensions: [String] {
        Array(Set(items.map { $0.ext.lowercased() })).sorted()
    }

    var filteredItems: [MediaLibraryItem] {
        items.filter { item in
            if let selectedFolderID {
                if selectedFolderID == MediaLibrarySpecialFolder.uncategorizedID {
                    if !item.folderIDs.isEmpty { return false }
                } else if !item.folderIDs.contains(selectedFolderID) {
                    return false
                }
            }

            switch filter.mediaKind {
            case .all:
                break
            case .image where item.mediaKind != .image:
                return false
            case .video where item.mediaKind != .video:
                return false
            default:
                break
            }

            if !filter.selectedExtensions.isEmpty && !filter.selectedExtensions.contains(item.ext.lowercased()) {
                return false
            }

            if filter.starredOnly && !item.isStarred {
                return false
            }

            if let minimumDuration = filter.minimumDurationSeconds,
               (item.durationSeconds ?? 0) < minimumDuration
            {
                return false
            }

            let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let haystack = ([item.name, item.ext, item.annotation ?? ""] + item.tags).joined(separator: " ").lowercased()
                if !haystack.contains(query.lowercased()) {
                    return false
                }
            }

            return true
        }
    }

    var visibleSummary: String {
        "\(filteredItems.count) of \(items.count)"
    }

    func restoreLastLibraryIfNeeded() async {
        guard library == nil, let path = defaults.string(forKey: PreferenceKey.lastLibraryPath) else {
            return
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        await openLibrary(at: url)
    }

    func chooseLibrary() async {
        let panel = NSOpenPanel()
        panel.title = "Open Eagle or Viewer Library"
        panel.message = "Choose a library folder that contains metadata.json or library.json."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        await openLibrary(at: url)
    }

    func restoreLibraryFromHistory(_ entry: MediaLibraryHistoryEntry) async {
        let url = URL(fileURLWithPath: entry.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "That library is no longer available."
            libraryHistory.removeAll { $0.path == entry.path }
            persistHistory()
            return
        }
        await openLibrary(at: url)
    }

    func createLibrary() async {
        let panel = NSOpenPanel()
        panel.title = "Choose Parent Folder"
        panel.message = "Gee will create an Eagle-compatible media library inside this folder."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parentURL = panel.url else {
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "GeeMedia-\(formatter.string(from: Date())).library"

        await runLoading {
            let info = try service.createLibrary(parentURL: parentURL, name: name)
            applyOpenedLibrary(info)
            try reloadLibraryContents()
        }
    }

    func importFilesWithPanel() async {
        let panel = NSOpenPanel()
        panel.title = "Import Media"
        panel.message = "Choose images or videos to import into the current library."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .movie]
        guard panel.runModal() == .OK else {
            return
        }
        await importMedia(at: panel.urls)
    }

    func importMedia(at urls: [URL]) async {
        guard let library else {
            errorMessage = "Open or create a library before importing media."
            return
        }

        await runLoading {
            let imported = try service.importFiles(urls, into: library.url)
            try reloadLibraryContents()
            if imported.isEmpty {
                errorMessage = "No new supported media files were imported."
            }
        }
    }

    func refresh() async {
        guard library != nil else { return }
        await runLoading {
            try reloadLibraryContents()
        }
    }

    func selectFolder(_ folderID: String?) {
        selectedFolderID = folderID
        selectedItemIDs.removeAll()
        focusedItemID = nil
    }

    func selectFolder(named name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "all" {
            selectFolder(nil)
            return true
        }
        if normalized == "uncategorized" {
            selectFolder(MediaLibrarySpecialFolder.uncategorizedID)
            return true
        }
        guard let folder = folders.first(where: { $0.name.lowercased() == normalized }) else {
            return false
        }
        selectFolder(folder.id)
        return true
    }

    func applyAgentFilter(
        extensions: [String]? = nil,
        starredOnly: Bool? = nil,
        mediaKind: MediaLibraryMediaKind? = nil,
        minimumDurationSeconds: Double? = nil
    ) {
        if let extensions {
            filter.selectedExtensions = Set(extensions.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }
        if let starredOnly {
            filter.starredOnly = starredOnly
        }
        if let mediaKind {
            filter.mediaKind = mediaKind
        }
        if let minimumDurationSeconds {
            filter.minimumDurationSeconds = minimumDurationSeconds
        }
    }

    func clearFilters() {
        filter = MediaLibraryFilterState()
    }

    func toggleExtension(_ ext: String) {
        let normalized = ext.lowercased()
        if filter.selectedExtensions.contains(normalized) {
            filter.selectedExtensions.remove(normalized)
        } else {
            filter.selectedExtensions.insert(normalized)
        }
    }

    func toggleSelection(for item: MediaLibraryItem, preservingExisting: Bool) {
        if preservingExisting {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
            }
        } else {
            selectedItemIDs = [item.id]
        }
        focusedItemID = item.id
    }

    func toggleStarred(_ item: MediaLibraryItem) async {
        guard let library else { return }
        await runLoading {
            try service.setStarred(!item.isStarred, itemID: item.id, in: library.url)
            try reloadLibraryContents()
            focusedItemID = item.id
        }
    }

    func deleteSelectedItems() async {
        guard let library, !selectedItemIDs.isEmpty else { return }
        let ids = selectedItemIDs
        await runLoading {
            for id in ids {
                try service.deleteItem(id: id, from: library.url)
            }
            selectedItemIDs.removeAll()
            focusedItemID = nil
            try reloadLibraryContents()
        }
    }

    func moveSelectedItems(to folderID: String?) async {
        guard let library, !selectedItemIDs.isEmpty else { return }
        let ids = selectedItemIDs
        await runLoading {
            try service.moveItems(ids, to: folderID, in: library.url)
            selectedItemIDs.removeAll()
            try reloadLibraryContents()
        }
    }

    func createFolder(named name: String) async {
        guard let library else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await runLoading {
            _ = try service.createFolder(named: trimmed, in: library.url)
            try reloadLibraryContents()
        }
    }

    func revealFocusedItem() {
        guard let focusedItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([focusedItem.fileURL])
    }

    func openFocusedItem() {
        guard let focusedItem else { return }
        NSWorkspace.shared.open(focusedItem.fileURL)
    }

    private func openLibrary(at url: URL) async {
        await runLoading {
            let info = try service.openLibrary(at: url)
            applyOpenedLibrary(info)
            try reloadLibraryContents()
        }
    }

    private func applyOpenedLibrary(_ info: MediaLibraryInfo) {
        library = info
        folders = info.folders
        selectedFolderID = nil
        selectedItemIDs.removeAll()
        focusedItemID = nil
        defaults.set(info.url.path, forKey: PreferenceKey.lastLibraryPath)
        updateHistory(with: info)
    }

    private func reloadLibraryContents() throws {
        guard let library else { return }
        items = try service.loadItems(from: library.url)
        folders = try service.loadFolders(from: library.url, kind: library.kind)
        self.library = MediaLibraryInfo(name: library.name, url: library.url, kind: library.kind, folders: folders)
        selectedItemIDs = selectedItemIDs.intersection(Set(items.map(\.id)))
        if let focusedItemID, !items.contains(where: { $0.id == focusedItemID }) {
            self.focusedItemID = nil
        }
    }

    private func runLoading(_ work: () throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func updateHistory(with info: MediaLibraryInfo) {
        let entry = MediaLibraryHistoryEntry(name: info.name, path: info.url.path)
        libraryHistory.removeAll { $0.path == entry.path }
        libraryHistory.insert(entry, at: 0)
        libraryHistory = Array(libraryHistory.prefix(20))
        persistHistory()
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(libraryHistory) {
            defaults.set(data, forKey: PreferenceKey.libraryHistory)
        }
    }

    private static func loadHistory(from defaults: UserDefaults) -> [MediaLibraryHistoryEntry] {
        guard let data = defaults.data(forKey: PreferenceKey.libraryHistory),
              let history = try? JSONDecoder().decode([MediaLibraryHistoryEntry].self, from: data)
        else {
            return []
        }
        return history
    }
}

struct MediaLibraryHistoryEntry: Codable, Hashable, Identifiable {
    var name: String
    var path: String

    var id: String { path }
}

enum MediaLibrarySpecialFolder {
    static let uncategorizedID = "__uncategorized"
}
