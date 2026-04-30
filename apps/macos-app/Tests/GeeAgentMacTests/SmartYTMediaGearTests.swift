import XCTest
@testable import GeeAgentMac

final class SmartYTMediaGearTests: XCTestCase {
    func testSmartYTManifestDeclaresDependenciesAndCapabilities() throws {
        let data = Data("""
        {
          "schema": "gee.gear.v1",
          "id": "smartyt.media",
          "name": "SmartYT Media",
          "description": "URL media sniffer.",
          "developer": "Gee",
          "version": "0.1.0",
          "category": "Media",
          "kind": "atmosphere",
          "display_mode": "full_canvas",
          "entry": { "type": "native", "native_id": "smartyt.media" },
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
                "id": "smartyt.download",
                "title": "Download URL media",
                "description": "Queue a media download."
              }
            ]
          }
        }
        """.utf8)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, SmartYTMediaGearDescriptor.gearID)
        XCTAssertEqual(manifest.dependencies?.items.first?.id, "yt-dlp")
        XCTAssertEqual(manifest.dependencies?.items.first?.installer?.id, "brew.install.yt-dlp")
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(manifest.agent?.capabilities.first?.id, "smartyt.download")
    }

    func testYTDLPMetadataParsingKeepsSmartYTFields() throws {
        let stdout = """
        {"title":"Demo Video","extractor_key":"Youtube","uploader":"Gee","duration":187,"webpage_url":"https://example.com/watch?v=1","thumbnail":"https://example.com/t.jpg","ext":"mp4","formats":[{"format_id":"18"},{"format_id":"22"}]}
        """

        let info = try SmartYTMediaInfo.parse(from: stdout, fallbackURL: "https://fallback.example/video")

        XCTAssertEqual(info.title, "Demo Video")
        XCTAssertEqual(info.platform, "Youtube")
        XCTAssertEqual(info.uploader, "Gee")
        XCTAssertEqual(info.durationText, "3:07")
        XCTAssertEqual(info.extensionHint, "mp4")
        XCTAssertEqual(info.formatCount, 2)
        XCTAssertEqual(info.webpageURL?.absoluteString, "https://example.com/watch?v=1")
    }

    @MainActor
    func testDirectImageURLsDefaultToImageDownloads() throws {
        let extensionURL = "https://pbs.twimg.com/media/HHFx7HsbsAEQHuH.jpg?name=large"
        let formatURL = "https://pbs.twimg.com/media/HHFx7HsbsAEQHuH?format=jpg&name=large"
        let videoURL = "https://video.twimg.com/amplify_video/demo/vid/avc1/demo.mp4"

        XCTAssertTrue(SmartYTMediaGearStore.isDirectImageURL(extensionURL))
        XCTAssertTrue(SmartYTMediaGearStore.isDirectImageURL(formatURL))
        XCTAssertFalse(SmartYTMediaGearStore.isDirectImageURL(videoURL))
        XCTAssertEqual(SmartYTMediaGearStore.defaultDownloadKind(for: extensionURL), .image)
        XCTAssertEqual(SmartYTMediaGearStore.defaultDownloadKind(for: formatURL), .image)
        XCTAssertEqual(SmartYTMediaGearStore.defaultDownloadKind(for: videoURL), .video)
    }

    func testSmartYTDownloadKindIncludesImage() throws {
        XCTAssertEqual(SmartYTDownloadKind(rawValue: "image"), .image)
        XCTAssertTrue(SmartYTDownloadKind.allCases.contains(.image))
        XCTAssertEqual(SmartYTDownloadKind.image.title, "Image")
    }

    @MainActor
    func testDefaultSmartYTArtifactRootUsesDownloadsFolder() throws {
        let root = try SmartYTMediaGearStore.defaultArtifactRoot()

        XCTAssertEqual(root.lastPathComponent, "SmartYT")
        XCTAssertTrue(root.deletingLastPathComponent().path.hasSuffix("/Downloads"))
    }
}
