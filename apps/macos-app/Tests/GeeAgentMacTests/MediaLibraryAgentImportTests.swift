import AppKit
import XCTest
@testable import GeeAgentMac

final class MediaLibraryAgentImportTests: XCTestCase {
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
}
