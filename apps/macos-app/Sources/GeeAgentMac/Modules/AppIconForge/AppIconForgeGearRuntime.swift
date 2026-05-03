import AppKit
import Foundation
import UniformTypeIdentifiers

struct AppIconForgeExportSettings: Equatable {
    var sourceURL: URL
    var outputDirectory: URL?
    var baseName: String = "AppIcon"
    var contentScale: Double = 0.88
    var cornerRadiusRatio: Double = 0.22
    var includesShadow: Bool = true
}

struct AppIconForgeExportResult: Equatable {
    var sourceURL: URL
    var outputDirectory: URL
    var icnsURL: URL
    var iconsetURL: URL
    var appiconsetURL: URL
    var previewURL: URL
    var generatedFiles: [URL]
}

enum AppIconForgeError: LocalizedError, Equatable {
    case sourceMissing(String)
    case sourceUnreadable(String)
    case imageDecodeFailed(String)
    case invalidBaseName
    case outputCreateFailed(String)
    case pngWriteFailed(String)
    case iconutilFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            return "Source image does not exist: \(path)"
        case .sourceUnreadable(let path):
            return "Source image is not readable: \(path)"
        case .imageDecodeFailed(let path):
            return "Could not decode source image: \(path)"
        case .invalidBaseName:
            return "Output name must contain at least one file-safe character."
        case .outputCreateFailed(let reason):
            return "Could not create output folders: \(reason)"
        case .pngWriteFailed(let path):
            return "Could not write PNG icon file: \(path)"
        case .iconutilFailed(let message):
            return "iconutil failed: \(message)"
        }
    }

    var code: String {
        switch self {
        case .sourceMissing: "gear.app_icon.source_missing"
        case .sourceUnreadable: "gear.app_icon.source_unreadable"
        case .imageDecodeFailed: "gear.app_icon.decode_failed"
        case .invalidBaseName: "gear.app_icon.invalid_name"
        case .outputCreateFailed: "gear.app_icon.output_failed"
        case .pngWriteFailed: "gear.app_icon.png_write_failed"
        case .iconutilFailed: "gear.app_icon.iconutil_failed"
        }
    }
}

enum AppIconForgeRenderer {
    struct IconSlot: Equatable {
        var size: Int
        var scale: Int

        var filename: String {
            let suffix = scale == 1 ? "" : "@\(scale)x"
            return "icon_\(size)x\(size)\(suffix).png"
        }

        var pixelSize: Int { size * scale }
        var contentsSize: String { "\(size)x\(size)" }
        var contentsScale: String { "\(scale)x" }
    }

    static let iconSlots: [IconSlot] = [
        IconSlot(size: 16, scale: 1),
        IconSlot(size: 16, scale: 2),
        IconSlot(size: 32, scale: 1),
        IconSlot(size: 32, scale: 2),
        IconSlot(size: 128, scale: 1),
        IconSlot(size: 128, scale: 2),
        IconSlot(size: 256, scale: 1),
        IconSlot(size: 256, scale: 2),
        IconSlot(size: 512, scale: 1),
        IconSlot(size: 512, scale: 2)
    ]

    static func exportIcons(settings: AppIconForgeExportSettings) throws -> AppIconForgeExportResult {
        let sourceURL = settings.sourceURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw AppIconForgeError.sourceMissing(sourceURL.path)
        }
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw AppIconForgeError.sourceUnreadable(sourceURL.path)
        }
        guard let sourceImage = NSImage(contentsOf: sourceURL),
              let croppedSource = centeredSquareImage(from: sourceImage)
        else {
            throw AppIconForgeError.imageDecodeFailed(sourceURL.path)
        }

        let baseName = sanitizedBaseName(settings.baseName)
        guard !baseName.isEmpty else {
            throw AppIconForgeError.invalidBaseName
        }

        let exportDirectory = try createExportDirectory(baseName: baseName, outputDirectory: settings.outputDirectory)
        let iconsetURL = exportDirectory.appendingPathComponent("\(baseName).iconset", isDirectory: true)
        let appiconsetURL = exportDirectory.appendingPathComponent("\(baseName).appiconset", isDirectory: true)
        let icnsURL = exportDirectory.appendingPathComponent("\(baseName).icns")
        let previewURL = exportDirectory.appendingPathComponent("preview-1024.png")
        let metadataURL = exportDirectory.appendingPathComponent("icon-export.json")

        do {
            try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: appiconsetURL, withIntermediateDirectories: true)
        } catch {
            throw AppIconForgeError.outputCreateFailed(error.localizedDescription)
        }

        var generatedFiles: [URL] = []
        for slot in iconSlots {
            let image = renderIcon(
                sourceImage: croppedSource,
                pixelSize: slot.pixelSize,
                contentScale: clamped(settings.contentScale, min: 0.6, max: 0.95),
                cornerRadiusRatio: clamped(settings.cornerRadiusRatio, min: 0.08, max: 0.28),
                includesShadow: settings.includesShadow
            )
            let iconsetFile = iconsetURL.appendingPathComponent(slot.filename)
            let appiconsetFile = appiconsetURL.appendingPathComponent(slot.filename)
            try writePNG(image, to: iconsetFile)
            try writePNG(image, to: appiconsetFile)
            generatedFiles.append(iconsetFile)
            generatedFiles.append(appiconsetFile)
            if slot.pixelSize == 1024 {
                try writePNG(image, to: previewURL)
                generatedFiles.append(previewURL)
            }
        }

        try writeAppIconContents(slots: iconSlots, to: appiconsetURL.appendingPathComponent("Contents.json"))
        try runIconutil(iconsetURL: iconsetURL, icnsURL: icnsURL)
        generatedFiles.append(icnsURL)

        let metadata: [String: Any] = [
            "gear_id": AppIconForgeGearDescriptor.gearID,
            "source_path": sourceURL.path,
            "icns_path": icnsURL.path,
            "iconset_path": iconsetURL.path,
            "appiconset_path": appiconsetURL.path,
            "preview_path": previewURL.path,
            "canvas_px": 1024,
            "content_scale": clamped(settings.contentScale, min: 0.6, max: 0.95),
            "corner_radius_ratio": clamped(settings.cornerRadiusRatio, min: 0.08, max: 0.28),
            "shadow": settings.includesShadow,
            "slots": iconSlots.map { ["size": $0.contentsSize, "scale": $0.contentsScale, "filename": $0.filename] }
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: metadataURL, options: .atomic)
        generatedFiles.append(metadataURL)

        return AppIconForgeExportResult(
            sourceURL: sourceURL,
            outputDirectory: exportDirectory,
            icnsURL: icnsURL,
            iconsetURL: iconsetURL,
            appiconsetURL: appiconsetURL,
            previewURL: previewURL,
            generatedFiles: generatedFiles.sorted { $0.path < $1.path }
        )
    }

    static func centeredSquareImage(from image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let square = min(cgImage.width, cgImage.height)
        let cropRect = CGRect(
            x: (cgImage.width - square) / 2,
            y: (cgImage.height - square) / 2,
            width: square,
            height: square
        )
        guard let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }
        return NSImage(cgImage: cropped, size: NSSize(width: square, height: square))
    }

    static func renderIcon(
        sourceImage: NSImage,
        pixelSize: Int,
        contentScale: Double,
        cornerRadiusRatio: Double,
        includesShadow: Bool
    ) -> NSImage {
        let canvasSize = NSSize(width: pixelSize, height: pixelSize)
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current else {
            return image
        }
        context.imageInterpolation = .high

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let side = Double(pixelSize) * clamped(contentScale, min: 0.6, max: 0.95)
        let origin = (Double(pixelSize) - side) / 2
        let iconRect = NSRect(x: origin, y: origin, width: side, height: side)
        let radius = side * clamped(cornerRadiusRatio, min: 0.08, max: 0.28)
        let path = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

        if includesShadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
            shadow.shadowBlurRadius = CGFloat(pixelSize) * 0.035
            shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixelSize) * 0.018)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        sourceImage.draw(
            in: iconRect,
            from: NSRect(origin: .zero, size: sourceImage.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.16).setStroke()
        path.lineWidth = max(1, CGFloat(pixelSize) / 512)
        path.stroke()

        return image
    }

    private static func writePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw AppIconForgeError.pngWriteFailed(url.path)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw AppIconForgeError.pngWriteFailed(url.path)
        }
    }

    private static func writeAppIconContents(slots: [IconSlot], to url: URL) throws {
        let images = slots.map { slot in
            [
                "filename": slot.filename,
                "idiom": "mac",
                "scale": slot.contentsScale,
                "size": slot.contentsSize
            ]
        }
        let payload: [String: Any] = [
            "images": images,
            "info": [
                "author": "geeagent",
                "version": 1
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func runIconutil(iconsetURL: URL, icnsURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw AppIconForgeError.iconutilFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppIconForgeError.iconutilFailed(message?.isEmpty == false ? message! : "Exited with status \(process.terminationStatus).")
        }
    }

    private static func createExportDirectory(baseName: String, outputDirectory: URL?) throws -> URL {
        let root = outputDirectory?.standardizedFileURL ?? defaultExportRoot()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = root.appendingPathComponent("\(baseName)-\(formatter.string(from: Date()))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            throw AppIconForgeError.outputCreateFailed(error.localizedDescription)
        }
    }

    private static func defaultExportRoot() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("GeeAgent/gear-data/\(AppIconForgeGearDescriptor.gearID)/exports", isDirectory: true)
    }

    private static func sanitizedBaseName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }

    private static func clamped(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.max(lower, Swift.min(upper, value))
    }
}

@MainActor
final class AppIconForgeGearStore: ObservableObject {
    static let shared = AppIconForgeGearStore()

    @Published var sourceURL: URL?
    @Published var outputDirectory: URL?
    @Published var outputName = "AppIcon"
    @Published var contentScale = 0.88
    @Published var cornerRadiusRatio = 0.22
    @Published var includesShadow = true
    @Published var isExporting = false
    @Published var statusMessage = "Ready"
    @Published var result: AppIconForgeExportResult?
    @Published var previewImage: NSImage?
    @Published var errorMessage: String?

    func chooseSourceImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            setSource(url)
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            outputDirectory = panel.url
        }
    }

    func setSource(_ url: URL) {
        sourceURL = url
        previewImage = NSImage(contentsOf: url)
        errorMessage = nil
        statusMessage = url.lastPathComponent
    }

    func exportCurrent() {
        guard let sourceURL else {
            errorMessage = "Choose an input image first."
            statusMessage = "No source image"
            return
        }
        isExporting = true
        errorMessage = nil
        statusMessage = "Generating icon package..."

        do {
            let export = try AppIconForgeRenderer.exportIcons(settings: AppIconForgeExportSettings(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                baseName: outputName,
                contentScale: contentScale,
                cornerRadiusRatio: cornerRadiusRatio,
                includesShadow: includesShadow
            ))
            result = export
            previewImage = NSImage(contentsOf: export.previewURL)
            statusMessage = "Generated \(export.icnsURL.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Export failed"
        }
        isExporting = false
    }

    func revealResult() {
        guard let result else { return }
        NSWorkspace.shared.activateFileViewerSelecting([result.outputDirectory])
    }

    func runAgentAction(args: [String: Any]) -> [String: Any] {
        guard let sourcePath = args["source_path"] as? String ?? args["path"] as? String else {
            return failurePayload(
                code: "gear.args.source_path",
                error: "`source_path` is required.",
                recovery: "Pass a local image path selected or supplied by the user."
            )
        }

        let outputDir = args["output_dir"] as? String ?? args["output_directory"] as? String
        do {
            let export = try AppIconForgeRenderer.exportIcons(settings: AppIconForgeExportSettings(
                sourceURL: URL(fileURLWithPath: NSString(string: sourcePath).expandingTildeInPath),
                outputDirectory: outputDir.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true) },
                baseName: (args["name"] as? String) ?? "AppIcon",
                contentScale: numberArg(args["content_scale"]) ?? 0.88,
                cornerRadiusRatio: numberArg(args["corner_radius_ratio"]) ?? 0.22,
                includesShadow: (args["shadow"] as? Bool) ?? true
            ))
            result = export
            sourceURL = export.sourceURL
            outputDirectory = outputDir.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true) }
            previewImage = NSImage(contentsOf: export.previewURL)
            statusMessage = "Generated \(export.icnsURL.lastPathComponent)"
            return successPayload(export)
        } catch let error as AppIconForgeError {
            return failurePayload(
                code: error.code,
                error: error.localizedDescription,
                recovery: recovery(for: error)
            )
        } catch {
            return failurePayload(
                code: "gear.app_icon.failed",
                error: error.localizedDescription,
                recovery: "Check the input image and output directory permissions, then retry."
            )
        }
    }

    private func successPayload(_ result: AppIconForgeExportResult) -> [String: Any] {
        [
            "status": "succeeded",
            "gear_id": AppIconForgeGearDescriptor.gearID,
            "capability_id": "app_icon.generate",
            "source_path": result.sourceURL.path,
            "output_dir": result.outputDirectory.path,
            "icns_path": result.icnsURL.path,
            "iconset_path": result.iconsetURL.path,
            "appiconset_path": result.appiconsetURL.path,
            "preview_path": result.previewURL.path,
            "generated_files": result.generatedFiles.map(\.path),
            "spec": [
                "canvas_px": 1024,
                "slots": AppIconForgeRenderer.iconSlots.map {
                    ["size": $0.contentsSize, "scale": $0.contentsScale, "filename": $0.filename]
                }
            ]
        ]
    }

    private func failurePayload(code: String, error: String, recovery: String) -> [String: Any] {
        [
            "status": "failed",
            "gear_id": AppIconForgeGearDescriptor.gearID,
            "capability_id": "app_icon.generate",
            "code": code,
            "error": error,
            "recovery": recovery
        ]
    }

    private func recovery(for error: AppIconForgeError) -> String {
        switch error {
        case .sourceMissing, .sourceUnreadable:
            "Choose an existing local image file that GeeAgent has permission to read."
        case .imageDecodeFailed:
            "Use a PNG, JPEG, HEIC, TIFF, or other image type supported by macOS image decoding."
        case .invalidBaseName:
            "Use a short output name such as AppIcon."
        case .outputCreateFailed, .pngWriteFailed:
            "Choose an output folder that GeeAgent can write to."
        case .iconutilFailed:
            "Confirm /usr/bin/iconutil is available on this macOS installation."
        }
    }

    private func numberArg(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
