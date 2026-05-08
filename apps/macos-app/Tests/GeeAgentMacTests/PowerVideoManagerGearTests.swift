import XCTest
@testable import GeeAgentMac

final class PowerVideoManagerGearTests: XCTestCase {
    func testScannerFindsOnlyScriptArchiveProjectsAndSortsByUpdatedTime() throws {
        let root = try makeTemporaryRunsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let older = root.appendingPathComponent("001-old-run", isDirectory: true)
        let newer = root.appendingPathComponent("002-new-run", isDirectory: true)
        let telegram = root.appendingPathComponent("telegram-preview-test", isDirectory: true)
        try writeScriptArchive(in: older, title: "001 - Old Run")
        try writeScriptArchive(in: newer, title: "002 - New Run")
        try FileManager.default.createDirectory(at: telegram.appendingPathComponent("production"), withIntermediateDirectories: true)

        try setModificationDate(Date(timeIntervalSince1970: 100), for: older)
        try setModificationDate(Date(timeIntervalSince1970: 200), for: newer)

        let index = try PowerVideoManagerWorkspaceScanner().scan(rootURL: root)

        XCTAssertEqual(index.projects.map(\.folderName), ["002-new-run", "001-old-run"])
        XCTAssertEqual(index.projects.first?.title, "002 - New Run")
    }

    func testScannerGroupsAssetsAndMarksOnlyExplicitSelection() throws {
        let root = try makeTemporaryRunsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("007-leng", isDirectory: true)
        try writeScriptArchive(in: project, title: "007 - Leng")
        try writeText("png", to: project.appendingPathComponent("production/character-looks/accepted-character.png"))
        try writeText("png", to: project.appendingPathComponent("production/storyboard-grid/storyboard-grid-001.png"))
        try writeText("png", to: project.appendingPathComponent("production/first-frames/shot-001-first-frame.png"))
        try writeText("mp4", to: project.appendingPathComponent("production/videos/shot-001-veo.mp4"))
        try writeText("mp4", to: project.appendingPathComponent("production/video-candidates-rerun/shot-001-veo-rerun.mp4"))
        try writeText("mp4", to: project.appendingPathComponent("final/final.mp4"))
        try writeText("jpg", to: project.appendingPathComponent("final/contact-sheet.jpg"))
        try writeText("mp4", to: project.appendingPathComponent("editing/renders/final-cut-v2.mp4"))
        try writeText("png", to: project.appendingPathComponent("editing/renders/final-cut-v2-contact-sheet.png"))
        try writeText("""
        {
          "schemaVersion": 1,
          "videos": [
            { "shotNumber": 1, "path": "\(project.path)/production/videos/shot-001-veo.mp4" }
          ],
          "firstFrames": [
            { "shotNumber": 1, "path": "production/first-frames/shot-001-first-frame.png" }
          ]
        }
        """, to: project.appendingPathComponent("production/current-selection.json"))

        let scanned = try XCTUnwrap(PowerVideoManagerWorkspaceScanner().scan(rootURL: root).projects.first)

        XCTAssertEqual(scanned.assets.filter { $0.kind == .characterLook }.count, 1)
        XCTAssertEqual(scanned.assets.filter { $0.kind == .storyboardGrid }.count, 1)
        XCTAssertEqual(scanned.assets.filter { $0.kind == .firstFrame }.count, 1)
        XCTAssertEqual(scanned.assets.filter { $0.kind == .shotVideo }.count, 2)
        XCTAssertEqual(scanned.assets.filter { $0.kind == .finalVideo }.count, 2)
        XCTAssertEqual(scanned.assets.filter { $0.kind == .editRender }.count, 2)

        let selectedVideo = try XCTUnwrap(scanned.assets.first { $0.relativePath == "production/videos/shot-001-veo.mp4" })
        let rerunVideo = try XCTUnwrap(scanned.assets.first { $0.relativePath == "production/video-candidates-rerun/shot-001-veo-rerun.mp4" })
        XCTAssertTrue(selectedVideo.isSelected)
        XCTAssertFalse(rerunVideo.isSelected)
        XCTAssertEqual(scanned.shots.map(\.shotNumber), [1])
        XCTAssertEqual(scanned.shots.first?.videos.count, 2)
    }

    func testScannerParsesCostSummaryWhenAvailable() throws {
        let root = try makeTemporaryRunsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("005-cost", isDirectory: true)
        try writeScriptArchive(in: project, title: "005 - Cost")
        try writeText("""
        {
          "schemaVersion": 1,
          "currency": "RMB",
          "total": 2.7,
          "items": [
            { "kind": "image", "path": "production/character-looks/accepted-character.png", "cost": 0.35 },
            { "kind": "video", "path": "production/videos/shot-001.mp4", "cost": 1.0 }
          ]
        }
        """, to: project.appendingPathComponent("cost-summary.json"))

        let scanned = try XCTUnwrap(PowerVideoManagerWorkspaceScanner().scan(rootURL: root).projects.first)

        XCTAssertEqual(scanned.cost?.currency, "RMB")
        XCTAssertEqual(scanned.cost?.total, 2.7)
        XCTAssertEqual(scanned.cost?.items.count, 2)
    }

    func testScannerParsesFlexibleCostSummary() throws {
        let root = try makeTemporaryRunsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("006-flexible-cost", isDirectory: true)
        try writeScriptArchive(in: project, title: "006 - Flexible Cost")
        try writeText("""
        {
          "schemaVersion": 1,
          "totalRMB": 4.2
        }
        """, to: project.appendingPathComponent("cost-summary.json"))

        let scanned = try XCTUnwrap(PowerVideoManagerWorkspaceScanner().scan(rootURL: root).projects.first)

        XCTAssertEqual(scanned.cost?.currency, "RMB")
        XCTAssertEqual(scanned.cost?.total, 4.2)
        XCTAssertEqual(scanned.cost?.items.count, 0)
    }

    func testManifestDeclaresReadOnlyNativeGearWithoutAgentCapabilities() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/power.video.manager/gear.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, PowerVideoManagerGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.nativeID, PowerVideoManagerGearDescriptor.gearID)
        XCTAssertEqual(manifest.kind, .atmosphere)
        XCTAssertEqual(manifest.agent?.enabled, false)
        XCTAssertEqual(manifest.agent?.capabilities.isEmpty, true)
    }

    func testGearHostRegistersPowerVideoManagerNativeWindow() {
        XCTAssertEqual(GearHost.powerVideoManagerWindowDescriptor.gearID, PowerVideoManagerGearDescriptor.gearID)
        XCTAssertEqual(GearHost.powerVideoManagerWindowDescriptor.windowID, GearHost.powerVideoManagerWindowID)
        XCTAssertTrue(GearHost.nativeWindowDescriptors.contains(GearHost.powerVideoManagerWindowDescriptor))
        XCTAssertTrue(GearHost.nativeGearIDs.contains(PowerVideoManagerGearDescriptor.gearID))
    }

    private func makeTemporaryRunsRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("power-video-manager-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeScriptArchive(in project: URL, title: String) throws {
        try writeText("""
        # \(title)

        > Generated At: 2026-05-07T12:22:43+08:00
        > Status: Completed
        > Score: S tier (24/25)
        > Duration: 34 seconds
        > Aspect Ratio: Landscape 16:9

        ## Final Output
        """, to: project.appendingPathComponent("script/script-archive.md"))
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.data(using: .utf8)?.write(to: url)
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
