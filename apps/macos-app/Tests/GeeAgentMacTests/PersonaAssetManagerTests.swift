import XCTest
@testable import GeeAgentMac

final class PersonaAssetManagerTests: XCTestCase {

    func testClassifyRecognisesExtensions() {
        XCTAssertEqual(PersonaAssetManager.classify(path: "/tmp/banner.png"), .image)
        XCTAssertEqual(PersonaAssetManager.classify(path: "/tmp/intro.mp4"), .video)
        XCTAssertEqual(PersonaAssetManager.classify(path: "/tmp/clip.MOV"), .video)
        XCTAssertEqual(PersonaAssetManager.classify(path: "/tmp/haru.model3.json"), .live2D)
        XCTAssertEqual(PersonaAssetManager.classify(path: "/tmp/bundle.zip"), .live2D)
        XCTAssertNil(PersonaAssetManager.classify(path: "/tmp/notes.txt"))
    }

    func testClassifyDirectoryWithModel3Descriptor() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundleDir = root.appendingPathComponent("haru", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        let descriptor = bundleDir.appendingPathComponent("haru.model3.json")
        try "{}".data(using: .utf8)!.write(to: descriptor)

        XCTAssertEqual(PersonaAssetManager.classify(path: bundleDir.path), .live2D)
    }

    func testImportLive2DBundleFromFolderCopiesDescriptor() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("haru", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let descriptor = source.appendingPathComponent("haru.model3.json")
        try "{}".data(using: .utf8)!.write(to: descriptor)
        let texture = source.appendingPathComponent("texture.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: texture)

        let personaID = "test-persona-\(UUID().uuidString)"
        defer {
            try? removePersonaDirectory(for: personaID)
        }

        let imported = try PersonaAssetManager.importLive2DBundle(from: source, personaID: personaID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.path))
        XCTAssertTrue(imported.path.hasSuffix(".model3.json"))
        XCTAssertTrue(imported.path.contains("Personas/\(personaID)/live2d"))
        let texturePath = imported.deletingLastPathComponent().appendingPathComponent("texture.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: texturePath.path), "bundle siblings should be copied alongside the descriptor")
    }

    func testImportLive2DBundleRejectsDirectoryWithoutDescriptor() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data([0x00]).write(to: source.appendingPathComponent("readme.txt"))

        let personaID = "test-persona-\(UUID().uuidString)"
        defer { try? removePersonaDirectory(for: personaID) }

        XCTAssertThrowsError(
            try PersonaAssetManager.importLive2DBundle(from: source, personaID: personaID)
        ) { error in
            guard case PersonaAssetManager.ImportError.noModel3Json = error else {
                XCTFail("Expected noModel3Json error, got \(error)")
                return
            }
        }
    }

    func testPruneUnusedKeepsCurrentBundleForLive2D() throws {
        let personaID = "test-persona-\(UUID().uuidString)"
        defer { try? removePersonaDirectory(for: personaID) }

        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        // Import two bundles back to back, then prune pinned to the second one.
        let source1 = root.appendingPathComponent("v1", isDirectory: true)
        let source2 = root.appendingPathComponent("v2", isDirectory: true)
        for source in [source1, source2] {
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try "{}".data(using: .utf8)!.write(to: source.appendingPathComponent("model.model3.json"))
        }
        _ = try PersonaAssetManager.importLive2DBundle(from: source1, personaID: personaID)
        let kept = try PersonaAssetManager.importLive2DBundle(from: source2, personaID: personaID)

        PersonaAssetManager.pruneUnused(personaID: personaID, kind: .live2D, currentPath: kept.path)

        let live2DRoot = try live2DDirectory(for: personaID)
        let entries = try FileManager.default.contentsOfDirectory(at: live2DRoot, includingPropertiesForKeys: nil)
        XCTAssertEqual(entries.count, 1, "pruneUnused should keep only the bundle containing the active descriptor")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geeagent-persona-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func live2DDirectory(for personaID: String) throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return appSupport
            .appendingPathComponent("GeeAgent/Personas", isDirectory: true)
            .appendingPathComponent(personaID, isDirectory: true)
            .appendingPathComponent("live2d", isDirectory: true)
    }

    private func removePersonaDirectory(for personaID: String) throws {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let personaRoot = appSupport
            .appendingPathComponent("GeeAgent/Personas", isDirectory: true)
            .appendingPathComponent(personaID, isDirectory: true)
        if FileManager.default.fileExists(atPath: personaRoot.path) {
            try FileManager.default.removeItem(at: personaRoot)
        }
    }
}
