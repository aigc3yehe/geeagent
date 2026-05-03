import AppKit
import XCTest
@testable import GeeAgentMac

final class AppIconForgeGearTests: XCTestCase {
    func testRendererCreatesMacIconPackage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-icon-forge-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceURL = root.appendingPathComponent("source.png")
        try makeSourceImage(at: sourceURL)

        let result = try AppIconForgeRenderer.exportIcons(settings: AppIconForgeExportSettings(
            sourceURL: sourceURL,
            outputDirectory: root,
            baseName: "TestIcon",
            contentScale: 0.82,
            cornerRadiusRatio: 0.225,
            includesShadow: true
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.icnsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.previewURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.iconsetURL.appendingPathComponent("icon_16x16.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.iconsetURL.appendingPathComponent("icon_512x512@2x.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appiconsetURL.appendingPathComponent("Contents.json").path))
        XCTAssertEqual(AppIconForgeRenderer.iconSlots.count, 10)
    }

    func testManifestDeclaresNativeCapability() throws {
        let data = Data("""
        {
          "schema": "gee.gear.v1",
          "id": "app.icon.forge",
          "name": "App Icon Forge",
          "description": "Native macOS icon generator.",
          "developer": "Gee",
          "version": "0.1.0",
          "category": "Developer",
          "kind": "atmosphere",
          "display_mode": "full_canvas",
          "entry": { "type": "native", "native_id": "app.icon.forge" },
          "agent": {
            "enabled": true,
            "capabilities": [
              {
                "id": "app_icon.generate",
                "title": "Generate macOS app icons",
                "description": "Generate a rounded macOS icon package."
              }
            ]
          }
        }
        """.utf8)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, AppIconForgeGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.nativeID, AppIconForgeGearDescriptor.gearID)
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(manifest.agent?.capabilities.map(\.id), ["app_icon.generate"])
    }

    private func makeSourceImage(at url: URL) throws {
        let size = NSSize(width: 300, height: 240)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemIndigo.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.systemTeal.setFill()
        NSBezierPath(ovalIn: NSRect(x: 42, y: 28, width: 210, height: 180)).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Could not create test PNG")
            return
        }
        try png.write(to: url)
    }
}
