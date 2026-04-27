import XCTest
@testable import GeeAgentMac

final class BookmarkVaultGearTests: XCTestCase {
    func testBookmarkVaultManifestDeclaresDependencyAndCapability() throws {
        let data = Data("""
        {
          "schema": "gee.gear.v1",
          "id": "bookmark.vault",
          "name": "Bookmark Vault",
          "description": "Universal bookmark gear.",
          "developer": "Gee",
          "version": "0.1.0",
          "category": "Knowledge",
          "kind": "atmosphere",
          "display_mode": "full_canvas",
          "entry": { "type": "native", "native_id": "bookmark.vault" },
          "dependencies": {
            "install_strategy": "on_open",
            "items": [
              {
                "id": "yt-dlp",
                "kind": "binary",
                "scope": "global",
                "required": true,
                "detect": { "command": "yt-dlp", "args": ["--version"] },
                "installer": { "type": "recipe", "id": "brew.install.yt-dlp" }
              }
            ]
          },
          "agent": {
            "enabled": true,
            "capabilities": [
              {
                "id": "bookmark.save",
                "title": "Save bookmark",
                "description": "Save arbitrary content."
              }
            ]
          }
        }
        """.utf8)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, BookmarkVaultGearDescriptor.gearID)
        XCTAssertEqual(manifest.dependencies?.items.first?.id, "yt-dlp")
        XCTAssertEqual(manifest.dependencies?.items.first?.installer?.id, "brew.install.yt-dlp")
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(manifest.agent?.capabilities.first?.id, "bookmark.save")
    }

    func testInputParserFindsFirstURLAndNormalizesWWW() {
        XCTAssertEqual(
            BookmarkVaultInputParser.firstURL(in: "save www.example.com/watch?v=1。"),
            "https://www.example.com/watch?v=1"
        )
        XCTAssertEqual(
            BookmarkVaultInputParser.firstURL(in: "save https://example.com/a/b?x=1,"),
            "https://example.com/a/b?x=1"
        )
    }

    func testYTDLPMetadataParserKeepsSmartYTMetadataFields() throws {
        let stdout = """
        {"title":"Demo Video","extractor_key":"Youtube","uploader":"Gee","duration":187,"webpage_url":"https://example.com/watch?v=1","thumbnail":"https://example.com/t.jpg","ext":"mp4","formats":[{"format_id":"18"},{"format_id":"22"}]}
        """

        let metadata = try BookmarkVaultYTDLPMetadataParser.parse(
            from: stdout,
            fallbackURL: "https://fallback.example/video"
        )

        XCTAssertEqual(metadata.source, "yt-dlp")
        XCTAssertEqual(metadata.pageTitle, "Demo Video")
        XCTAssertEqual(metadata.platform, "Youtube")
        XCTAssertEqual(metadata.uploader, "Gee")
        XCTAssertEqual(metadata.durationSeconds, 187)
        XCTAssertEqual(metadata.url, "https://example.com/watch?v=1")
        XCTAssertEqual(metadata.thumbnailURL, "https://example.com/t.jpg")
        XCTAssertEqual(metadata.extensionHint, "mp4")
        XCTAssertEqual(metadata.formatCount, 2)
    }

    func testBasicHTMLParserPrefersOpenGraphAndCanonicalFields() {
        let html = """
        <html>
          <head>
            <title>Fallback &amp; Title</title>
            <meta property="og:title" content="OG &amp; Title">
            <meta name="description" content="Plain description">
            <meta property="og:description" content="OG description">
            <meta property="og:site_name" content="Example Site">
            <meta property="og:image" content="https://example.com/cover.jpg">
            <link rel="canonical" href="https://example.com/canonical">
          </head>
        </html>
        """

        let metadata = BookmarkVaultHTMLMetadataParser.parse(
            html,
            fallbackURL: "https://example.com/original"
        )

        XCTAssertEqual(metadata.source, "basic_fetch")
        XCTAssertEqual(metadata.pageTitle, "OG & Title")
        XCTAssertEqual(metadata.description, "OG description")
        XCTAssertEqual(metadata.siteName, "Example Site")
        XCTAssertEqual(metadata.thumbnailURL, "https://example.com/cover.jpg")
        XCTAssertEqual(metadata.canonicalURL, "https://example.com/canonical")
    }

    @MainActor
    func testAgentSavePlainContentWritesFileDatabaseRecord() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-vault-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = BookmarkVaultGearStore(
            database: BookmarkVaultFileDatabase(rootURL: root),
            runner: BookmarkVaultMockRunner()
        )

        let payload = await store.saveAgentBookmark(content: "A plain thought worth saving")

        XCTAssertEqual(payload["gear_id"] as? String, BookmarkVaultGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "bookmark.save")
        XCTAssertEqual(payload["status"] as? String, "saved")
        XCTAssertEqual(payload["raw_content"] as? String, "A plain thought worth saving")
        XCTAssertEqual(payload["metadata_source"] as? String, "manual")
        XCTAssertEqual(store.bookmarks.count, 1)
        let path = try XCTUnwrap(payload["bookmark_path"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    @MainActor
    func testAgentSaveCanAttachLocalMediaPaths() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-vault-local-media-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = BookmarkVaultGearStore(
            database: BookmarkVaultFileDatabase(rootURL: root),
            runner: BookmarkVaultMockRunner()
        )

        let payload = await store.saveAgentBookmark(
            content: "Saved media link https://example.com/video",
            localMediaPaths: ["~/Downloads/SmartYT/demo.mp4"]
        )

        let paths = try XCTUnwrap(payload["local_media_paths"] as? [String])
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].hasSuffix("/Downloads/SmartYT/demo.mp4"))
        XCTAssertEqual(store.bookmarks.first?.localMediaPaths, paths)
    }
}

private struct BookmarkVaultMockRunner: GearCommandRunning {
    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        GearCommandResult(exitCode: 127, stdout: "", stderr: "not available")
    }

    func run(_ command: String, arguments: [String], timeoutSeconds: TimeInterval?) async -> GearCommandResult {
        GearCommandResult(exitCode: 127, stdout: "", stderr: "not available")
    }
}
