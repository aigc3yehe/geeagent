import AppKit
import XCTest
@testable import GeeAgentMac

final class MediaLibraryAgentImportTests: XCTestCase {
    private let lastLibraryPathKey = "geeagent.mediaLibrary.lastLibraryPath"
    private let lastLibraryBookmarkKey = "geeagent.mediaLibrary.lastLibraryBookmark"

    @MainActor
    func testAgentImportCopiesLocalMediaIntoCurrentLibrary() async throws {
        let store = MediaLibraryModuleStore.shared
        let originalLibrary = store.library
        let originalItems = store.items
        let originalFolders = store.folders
        let originalSelectedFolderID = store.selectedFolderID
        let originalFilter = store.filter
        let originalSelectedItemIDs = store.selectedItemIDs
        let originalFocusedItemID = store.focusedItemID
        defer {
            store.library = originalLibrary
            store.items = originalItems
            store.folders = originalFolders
            store.selectedFolderID = originalSelectedFolderID
            store.filter = originalFilter
            store.selectedItemIDs = originalSelectedItemIDs
            store.focusedItemID = originalFocusedItemID
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-agent-import-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let source = root.appendingPathComponent("sample.png")
        try makePNGData().write(to: source)

        let library = try MediaLibraryService().createLibrary(parentURL: root, name: "AgentImport.library")
        store.library = library
        store.folders = library.folders
        store.items = []
        store.selectedFolderID = nil
        store.selectedItemIDs = []
        store.focusedItemID = nil

        let imported = try await store.importMediaForAgent(paths: [source.path])

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.ext, "png")
        XCTAssertTrue(imported.first?.fileURL.path.contains("AgentImport.library/images") == true)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.focusedItemID, imported.first?.id)
    }

    @MainActor
    func testAgentImportRestoresLastLibraryBeforeImporting() async throws {
        let suiteName = "media-agent-restore-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-agent-restore-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let source = root.appendingPathComponent("sample.png")
        try makePNGData().write(to: source)

        let library = try MediaLibraryService().createLibrary(parentURL: root, name: "AgentRestore.library")
        defaults.set(library.url.path, forKey: lastLibraryPathKey)

        let store = MediaLibraryModuleStore(defaults: defaults)
        let imported = try await store.importMediaForAgent(paths: [source.path])

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(store.library?.url.path, library.url.path)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.focusedItemID, imported.first?.id)
    }

    @MainActor
    func testAgentImportRouterReportsMissingSourcePaths() async throws {
        let store = MediaLibraryModuleStore.shared
        let originalLibrary = store.library
        let originalItems = store.items
        let originalFolders = store.folders
        let originalSelectedFolderID = store.selectedFolderID
        let originalFilter = store.filter
        let originalSelectedItemIDs = store.selectedItemIDs
        let originalFocusedItemID = store.focusedItemID
        defer {
            store.library = originalLibrary
            store.items = originalItems
            store.folders = originalFolders
            store.selectedFolderID = originalSelectedFolderID
            store.filter = originalFilter
            store.selectedItemIDs = originalSelectedItemIDs
            store.focusedItemID = originalFocusedItemID
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-agent-router-import-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let source = root.appendingPathComponent("sample.png")
        let missing = root.appendingPathComponent("missing.mp4")
        try makePNGData().write(to: source)

        let library = try MediaLibraryService().createLibrary(parentURL: root, name: "AgentRouterImport.library")
        store.library = library
        store.folders = library.folders
        store.items = []
        store.selectedFolderID = nil
        store.selectedItemIDs = []
        store.focusedItemID = nil

        let outcome = WorkbenchToolOutcome.completed(
            toolID: "gee.gear.invoke",
            payload: [
                "intent": "gear.invoke",
                "gear_id": "media.library",
                "capability_id": "media.import_files",
                "args": [
                    "paths": [source.path, missing.path]
                ]
            ]
        )

        guard case let .completed(_, payload)? = await GeeHostToolRouter.resolveCompletedIntent(outcome) else {
            return XCTFail("Expected completed media import outcome.")
        }

        XCTAssertEqual(payload["imported_count"] as? Int, 1)
        XCTAssertEqual(payload["missing_paths"] as? [String], [missing.path])
    }

    @MainActor
    func testAgentImportRouterRequestsAuthorizationWhenLibraryCannotBeRestored() async throws {
        let store = MediaLibraryModuleStore.shared
        let originalLibrary = store.library
        let originalItems = store.items
        let originalFolders = store.folders
        let originalSelectedFolderID = store.selectedFolderID
        let originalFilter = store.filter
        let originalSelectedItemIDs = store.selectedItemIDs
        let originalFocusedItemID = store.focusedItemID
        let defaults = UserDefaults.standard
        let originalLastPath = defaults.object(forKey: lastLibraryPathKey)
        let originalLastBookmark = defaults.object(forKey: lastLibraryBookmarkKey)
        defer {
            store.library = originalLibrary
            store.items = originalItems
            store.folders = originalFolders
            store.selectedFolderID = originalSelectedFolderID
            store.filter = originalFilter
            store.selectedItemIDs = originalSelectedItemIDs
            store.focusedItemID = originalFocusedItemID
            restore(originalLastPath, forKey: lastLibraryPathKey, defaults: defaults)
            restore(originalLastBookmark, forKey: lastLibraryBookmarkKey, defaults: defaults)
        }

        defaults.removeObject(forKey: lastLibraryPathKey)
        defaults.removeObject(forKey: lastLibraryBookmarkKey)
        store.library = nil
        store.items = []
        store.folders = []
        store.selectedFolderID = nil
        store.selectedItemIDs = []
        store.focusedItemID = nil

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-agent-auth-required-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let source = root.appendingPathComponent("downloaded.mp4")
        try Data([0, 1, 2, 3]).write(to: source)

        let outcome = WorkbenchToolOutcome.completed(
            toolID: "gee.gear.invoke",
            payload: [
                "intent": "gear.invoke",
                "gear_id": "media.library",
                "capability_id": "media.import_files",
                "args": [
                    "paths": [source.path]
                ]
            ]
        )

        guard case let .completed(_, payload)? = await GeeHostToolRouter.resolveCompletedIntent(outcome) else {
            return XCTFail("Expected completed structured authorization result.")
        }

        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertEqual(payload["code"] as? String, "gear.media.authorization_required")
        XCTAssertEqual(payload["intent"] as? String, "navigate.module")
        XCTAssertEqual(payload["module_id"] as? String, "media.library")
        XCTAssertEqual(payload["pending_paths"] as? [String], [source.path])
    }

    private func makePNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private func restore(_ value: Any?, forKey key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
