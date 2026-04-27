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
        static let lastLibraryBookmark = "geeagent.mediaLibrary.lastLibraryBookmark"
        static let libraryHistory = "geeagent.mediaLibrary.libraryHistory"
    }

    private let service = MediaLibraryService()
    private let defaults: UserDefaults
    private var activeLibraryAccess: MediaLibrarySecurityScope?

    private struct LoadedLibrarySnapshot: Sendable {
        var info: MediaLibraryInfo
        var items: [MediaLibraryItem]
        var folders: [MediaLibraryFolder]
    }

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
    var pendingAgentImportPaths: [String] = []
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

    var hasActiveFilters: Bool {
        !filter.selectedExtensions.isEmpty
            || filter.starredOnly
            || filter.mediaKind != .all
            || filter.minimumDurationSeconds != nil
            || !filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func restoreLastLibraryIfNeeded() async {
        guard library == nil else {
            return
        }
        await runLoading {
            _ = try await restoreLastLibraryFromPreferences()
        }
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
            activeLibraryAccess = MediaLibrarySecurityScope(url: info.url)
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
            let importService = MediaLibraryService()
            let imported = try await importService.importFiles(urls, into: library.url)
            try reloadLibraryContents()
            if imported.isEmpty {
                errorMessage = "No new supported media files were imported."
            }
        }
    }

    func importMediaForAgent(paths: [String]) async throws -> [MediaLibraryItem] {
        let urls = paths
            .map { NSString(string: $0).expandingTildeInPath }
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else {
            throw MediaLibraryAgentImportError.noReadableFiles
        }

        let library = try await ensureLibraryForAgent(pendingPaths: urls.map(\.path))

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let importService = MediaLibraryService()
            let imported = try await importService.importFiles(urls, into: library.url)
            try reloadLibraryContents()
            if let firstImported = imported.first {
                focusedItemID = firstImported.id
                selectedItemIDs = [firstImported.id]
            }
            if imported.isEmpty {
                errorMessage = "No new supported media files were imported."
            }
            pendingAgentImportPaths = []
            return imported
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func ensureLibraryForAgent(pendingPaths: [String] = []) async throws -> MediaLibraryInfo {
        if let library {
            return library
        }
        if isLoading {
            throw MediaLibraryAgentImportError.libraryLoading
        }

        do {
            if try await restoreLastLibraryFromPreferences(), let library {
                return library
            }
        } catch {
            pendingAgentImportPaths = pendingPaths
            throw MediaLibraryAgentImportError.authorizationRequired(pendingPaths: pendingPaths)
        }

        pendingAgentImportPaths = pendingPaths
        throw MediaLibraryAgentImportError.authorizationRequired(pendingPaths: pendingPaths)
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
        minimumDurationSeconds: Double? = nil,
        searchText: String? = nil
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
        if let searchText {
            filter.searchText = searchText
        }
    }

    func clearFilters() {
        filter = MediaLibraryFilterState()
    }

    func selectMediaKindFromUI(_ mediaKind: MediaLibraryMediaKind) {
        if mediaKind == .all {
            clearFilters()
            return
        }

        filter.mediaKind = mediaKind
        filter.selectedExtensions.removeAll()
        filter.minimumDurationSeconds = nil
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
            try await openLibraryThrowing(at: url, shouldPersistBookmark: true)
        }
    }

    private func openLibraryThrowing(at url: URL, shouldPersistBookmark: Bool) async throws {
        let access = MediaLibrarySecurityScope(url: url)
        let loaded = try await loadLibrarySnapshot(at: url)
        activeLibraryAccess = access
        applyLoadedLibrary(loaded, shouldPersistBookmark: shouldPersistBookmark)
    }

    private func applyOpenedLibrary(_ info: MediaLibraryInfo, shouldPersistBookmark: Bool = true) {
        library = info
        folders = info.folders
        selectedFolderID = nil
        selectedItemIDs.removeAll()
        focusedItemID = nil
        defaults.set(info.url.path, forKey: PreferenceKey.lastLibraryPath)
        if shouldPersistBookmark {
            persistBookmark(for: info.url)
        }
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

    private func loadLibrarySnapshot(at url: URL) async throws -> LoadedLibrarySnapshot {
        try await Task.detached(priority: .userInitiated) {
            let service = MediaLibraryService()
            let info = try service.openLibrary(at: url)
            let items = try service.loadItems(from: info.url)
            let folders = try service.loadFolders(from: info.url, kind: info.kind)
            let refreshedInfo = MediaLibraryInfo(
                name: info.name,
                url: info.url,
                kind: info.kind,
                folders: folders
            )
            return LoadedLibrarySnapshot(info: refreshedInfo, items: items, folders: folders)
        }.value
    }

    private func applyLoadedLibrary(_ loaded: LoadedLibrarySnapshot, shouldPersistBookmark: Bool = true) {
        applyOpenedLibrary(loaded.info, shouldPersistBookmark: shouldPersistBookmark)
        items = loaded.items
        folders = loaded.folders
        library = loaded.info
        pendingAgentImportPaths = []
        selectedItemIDs = selectedItemIDs.intersection(Set(items.map(\.id)))
        if let focusedItemID, !items.contains(where: { $0.id == focusedItemID }) {
            self.focusedItemID = nil
        }
    }

    private func restoreLastLibraryFromPreferences() async throws -> Bool {
        guard let url = try restoredLibraryURLFromPreferences() else {
            return false
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            clearStoredLibraryAccess()
            return false
        }
        try await openLibraryThrowing(at: url, shouldPersistBookmark: true)
        return true
    }

    private func restoredLibraryURLFromPreferences() throws -> URL? {
        if let bookmarkData = defaults.data(forKey: PreferenceKey.lastLibraryBookmark) {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                persistBookmark(for: url)
            }
            return url
        }

        guard let path = defaults.string(forKey: PreferenceKey.lastLibraryPath), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func persistBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: PreferenceKey.lastLibraryBookmark)
        } catch {
            defaults.removeObject(forKey: PreferenceKey.lastLibraryBookmark)
        }
    }

    private func clearStoredLibraryAccess() {
        defaults.removeObject(forKey: PreferenceKey.lastLibraryPath)
        defaults.removeObject(forKey: PreferenceKey.lastLibraryBookmark)
        libraryHistory.removeAll()
        persistHistory()
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

    private func runLoading(_ work: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await work()
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

enum MediaLibraryAgentImportError: LocalizedError {
    case libraryLoading
    case libraryMissing
    case authorizationRequired(pendingPaths: [String])
    case noReadableFiles

    var errorDescription: String? {
        switch self {
        case .libraryLoading:
            return "The media library is still loading. Retry after the library finishes loading."
        case .libraryMissing:
            return "Open or create a media library before importing downloaded media."
        case .authorizationRequired:
            return "Media Library needs access to a library before importing downloaded media."
        case .noReadableFiles:
            return "No readable local media files were provided."
        }
    }
}

private final class MediaLibrarySecurityScope {
    private let url: URL
    private let didStartAccessing: Bool

    init(url: URL) {
        self.url = url
        didStartAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
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
