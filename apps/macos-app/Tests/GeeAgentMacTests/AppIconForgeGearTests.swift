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

    func testRendererCreatesGearCatalogIconPackage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gear-icon-forge-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceURL = root.appendingPathComponent("source.png")
        try makeSourceImage(at: sourceURL)

        let result = try AppIconForgeRenderer.exportGearIcon(settings: AppIconForgeGearIconSettings(
            sourceURL: sourceURL,
            outputDirectory: root,
            baseName: "TestGear",
            contentScale: 0.84,
            cornerRadiusRatio: 0.18,
            includesShadow: true
        ))

        XCTAssertEqual(result.manifestIconPath, "assets/icon.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.iconURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.previewURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.metadataURL.path))
        XCTAssertEqual(result.iconURL.lastPathComponent, "icon.png")
        XCTAssertEqual(result.iconURL.deletingLastPathComponent().lastPathComponent, "assets")
        XCTAssertEqual(try pngPixelSize(at: result.iconURL), CGSize(width: 780, height: 580))
        XCTAssertEqual(result.previewURL.lastPathComponent, "preview-780x580.png")

        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: result.metadataURL)) as? [String: Any])
        XCTAssertEqual(metadata["spec_id"] as? String, AppIconForgeGearIconSpec.id)
        XCTAssertEqual(metadata["manifest_icon"] as? String, "assets/icon.png")
        XCTAssertEqual(metadata["canvas_width_px"] as? Int, 780)
        XCTAssertEqual(metadata["canvas_height_px"] as? Int, 580)
        XCTAssertEqual(metadata["aspect_ratio"] as? String, "39:29")
        XCTAssertEqual(metadata["intended_surface"] as? String, "gears_list")
    }

    func testManifestDeclaresNativeCapabilities() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/app.icon.forge/gear.json")
        let data = try Data(contentsOf: manifestURL)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, AppIconForgeGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.nativeID, AppIconForgeGearDescriptor.gearID)
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(manifest.agent?.capabilities.map(\.id), [
            "app_icon.generate",
            "gear_icon.generate"
        ])
    }

    func testGearsCatalogPrefersExistingManifestIconOverCover() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gear-catalog-icon-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let iconURL = root.appendingPathComponent("icon.png")
        let coverURL = root.appendingPathComponent("cover.png")
        try makeSourceImage(at: iconURL)

        var app = InstalledAppRecord(
            id: "demo.gear",
            name: "Demo Gear",
            categoryLabel: "Developer",
            versionLabel: "0.1.0",
            healthLabel: "Ready",
            installState: .installed,
            summary: "Demo",
            displayMode: .fullCanvas,
            coverURL: coverURL,
            iconURL: iconURL,
            isGearPackage: true
        )

        XCTAssertEqual(GearCatalogVisual.primary(for: app).kind, .icon)
        XCTAssertEqual(GearCatalogVisual.primary(for: app).url, iconURL)
        XCTAssertEqual(GearCatalogVisual.primary(for: app).frameSize, CGSize(width: 78, height: 58))

        app.iconURL = root.appendingPathComponent("missing.png")
        XCTAssertEqual(GearCatalogVisual.primary(for: app).kind, .cover)
        XCTAssertEqual(GearCatalogVisual.primary(for: app).url, coverURL)
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

    private func pngPixelSize(at url: URL) throws -> CGSize {
        let data = try Data(contentsOf: url)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    }
}
