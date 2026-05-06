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

struct AppIconForgeGearIconSettings: Equatable {
    var sourceURL: URL
    var outputDirectory: URL?
    var baseName: String = "GearIcon"
    var contentScale: Double = 0.84
    var cornerRadiusRatio: Double = 0.18
    var includesShadow: Bool = true
}

struct AppIconForgeGearIconResult: Equatable {
    var sourceURL: URL
    var outputDirectory: URL
    var assetsDirectoryURL: URL
    var iconURL: URL
    var previewURL: URL
    var metadataURL: URL
    var manifestIconPath: String
    var generatedFiles: [URL]
}

enum AppIconForgeGearIconSpec {
    static let id = "gee.gear.icon.v1"
    static let canvasWidthPixels = 780
    static let canvasHeightPixels = 580
    static let aspectRatio = "39:29"
    static let manifestIconPath = "assets/icon.png"
    static let intendedSurface = "gears_list"
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

enum AppIconForgeOutputKind: String, CaseIterable, Identifiable {
    case appIcon
    case gearIcon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appIcon:
            "macOS App"
        case .gearIcon:
            "Gear List"
        }
    }

    var subtitle: String {
        switch self {
        case .appIcon:
            "Build .icns, .iconset, and Xcode appiconset outputs."
        case .gearIcon:
            "Build a simple list tile at assets/icon.png for the Gears catalog."
        }
    }

    var actionTitle: String {
        switch self {
        case .appIcon:
            "Export App Icons"
        case .gearIcon:
            "Export Gear Icon"
        }
    }

    var previewSubtitle: String {
        switch self {
        case .appIcon:
            "1024 canvas, transparent padding, rounded icon body"
        case .gearIcon:
            "780x580 PNG for manifest icon: assets/icon.png"
        }
    }

    var exportingStatus: String {
        switch self {
        case .appIcon:
            "Generating app icon package..."
        case .gearIcon:
            "Generating gear icon..."
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
        let (sourceURL, croppedSource) = try loadCroppedSourceImage(from: settings.sourceURL, targetAspectRatio: 1)

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

    static func exportGearIcon(settings: AppIconForgeGearIconSettings) throws -> AppIconForgeGearIconResult {
        let (sourceURL, croppedSource) = try loadCroppedSourceImage(
            from: settings.sourceURL,
            targetAspectRatio: Double(AppIconForgeGearIconSpec.canvasWidthPixels) / Double(AppIconForgeGearIconSpec.canvasHeightPixels)
        )

        let baseName = sanitizedBaseName(settings.baseName)
        guard !baseName.isEmpty else {
            throw AppIconForgeError.invalidBaseName
        }

        let exportDirectory = try createExportDirectory(baseName: baseName, outputDirectory: settings.outputDirectory)
        let assetsDirectory = exportDirectory.appendingPathComponent("assets", isDirectory: true)
        let iconURL = assetsDirectory.appendingPathComponent("icon.png")
        let previewURL = exportDirectory.appendingPathComponent("preview-780x580.png")
        let metadataURL = exportDirectory.appendingPathComponent("gear-icon.json")

        do {
            try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        } catch {
            throw AppIconForgeError.outputCreateFailed(error.localizedDescription)
        }

        let icon = renderIcon(
            sourceImage: croppedSource,
            canvasSize: NSSize(
                width: AppIconForgeGearIconSpec.canvasWidthPixels,
                height: AppIconForgeGearIconSpec.canvasHeightPixels
            ),
            contentScale: clamped(settings.contentScale, min: 0.6, max: 0.95),
            cornerRadiusRatio: clamped(settings.cornerRadiusRatio, min: 0.08, max: 0.28),
            includesShadow: settings.includesShadow
        )
        try writePNG(icon, to: iconURL)
        try writePNG(icon, to: previewURL)

        let metadata: [String: Any] = [
            "spec_id": AppIconForgeGearIconSpec.id,
            "gear_id": AppIconForgeGearDescriptor.gearID,
            "source_path": sourceURL.path,
            "icon_path": iconURL.path,
            "manifest_icon": AppIconForgeGearIconSpec.manifestIconPath,
            "preview_path": previewURL.path,
            "canvas_width_px": AppIconForgeGearIconSpec.canvasWidthPixels,
            "canvas_height_px": AppIconForgeGearIconSpec.canvasHeightPixels,
            "aspect_ratio": AppIconForgeGearIconSpec.aspectRatio,
            "content_scale": clamped(settings.contentScale, min: 0.6, max: 0.95),
            "corner_radius_ratio": clamped(settings.cornerRadiusRatio, min: 0.08, max: 0.28),
            "shadow": settings.includesShadow,
            "intended_surface": AppIconForgeGearIconSpec.intendedSurface
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: metadataURL, options: .atomic)

        return AppIconForgeGearIconResult(
            sourceURL: sourceURL,
            outputDirectory: exportDirectory,
            assetsDirectoryURL: assetsDirectory,
            iconURL: iconURL,
            previewURL: previewURL,
            metadataURL: metadataURL,
            manifestIconPath: AppIconForgeGearIconSpec.manifestIconPath,
            generatedFiles: [iconURL, metadataURL, previewURL].sorted { $0.path < $1.path }
        )
    }

    static func centeredSquareImage(from image: NSImage) -> NSImage? {
        centeredCroppedImage(from: image, targetAspectRatio: 1)
    }

    static func centeredCroppedImage(from image: NSImage, targetAspectRatio: Double) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let targetAspectRatio = Swift.max(0.1, targetAspectRatio)
        let sourceAspectRatio = Double(cgImage.width) / Double(cgImage.height)
        let cropWidth: Int
        let cropHeight: Int
        if sourceAspectRatio > targetAspectRatio {
            cropHeight = cgImage.height
            cropWidth = Int(Double(cropHeight) * targetAspectRatio)
        } else {
            cropWidth = cgImage.width
            cropHeight = Int(Double(cropWidth) / targetAspectRatio)
        }
        let cropRect = CGRect(
            x: (cgImage.width - cropWidth) / 2,
            y: (cgImage.height - cropHeight) / 2,
            width: cropWidth,
            height: cropHeight
        )
        guard let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }
        return NSImage(cgImage: cropped, size: NSSize(width: cropWidth, height: cropHeight))
    }

    static func renderIcon(
        sourceImage: NSImage,
        pixelSize: Int,
        contentScale: Double,
        cornerRadiusRatio: Double,
        includesShadow: Bool
    ) -> NSImage {
        renderIcon(
            sourceImage: sourceImage,
            canvasSize: NSSize(width: pixelSize, height: pixelSize),
            contentScale: contentScale,
            cornerRadiusRatio: cornerRadiusRatio,
            includesShadow: includesShadow
        )
    }

    static func renderIcon(
        sourceImage: NSImage,
        canvasSize: NSSize,
        contentScale: Double,
        cornerRadiusRatio: Double,
        includesShadow: Bool
    ) -> NSImage {
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        let image = NSImage(size: canvasSize)
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return image
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer {
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }

        context.imageInterpolation = .high
        context.shouldAntialias = true

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let contentScale = clamped(contentScale, min: 0.6, max: 0.95)
        let iconWidth = Double(width) * contentScale
        let iconHeight = Double(height) * contentScale
        let iconRect = NSRect(
            x: (Double(width) - iconWidth) / 2,
            y: (Double(height) - iconHeight) / 2,
            width: iconWidth,
            height: iconHeight
        )
        let radius = min(iconWidth, iconHeight) * clamped(cornerRadiusRatio, min: 0.08, max: 0.28)
        let path = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)
        let shortSide = CGFloat(min(width, height))

        if includesShadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
            shadow.shadowBlurRadius = shortSide * 0.035
            shadow.shadowOffset = NSSize(width: 0, height: -shortSide * 0.018)
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
        path.lineWidth = max(1, shortSide / 512)
        path.stroke()

        return image
    }

    private static func loadCroppedSourceImage(from url: URL, targetAspectRatio: Double) throws -> (URL, NSImage) {
        let sourceURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw AppIconForgeError.sourceMissing(sourceURL.path)
        }
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw AppIconForgeError.sourceUnreadable(sourceURL.path)
        }
        guard let sourceImage = NSImage(contentsOf: sourceURL),
              let croppedSource = centeredCroppedImage(from: sourceImage, targetAspectRatio: targetAspectRatio)
        else {
            throw AppIconForgeError.imageDecodeFailed(sourceURL.path)
        }
        return (sourceURL, croppedSource)
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
    @Published var outputKind: AppIconForgeOutputKind = .appIcon
    @Published var isExporting = false
    @Published var statusMessage = "Ready"
    @Published var result: AppIconForgeExportResult?
    @Published var gearIconResult: AppIconForgeGearIconResult?
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
        statusMessage = outputKind.exportingStatus

        do {
            switch outputKind {
            case .appIcon:
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
            case .gearIcon:
                let export = try AppIconForgeRenderer.exportGearIcon(settings: AppIconForgeGearIconSettings(
                    sourceURL: sourceURL,
                    outputDirectory: outputDirectory,
                    baseName: outputName.isEmpty ? "GearIcon" : outputName,
                    contentScale: contentScale,
                    cornerRadiusRatio: cornerRadiusRatio,
                    includesShadow: includesShadow
                ))
                gearIconResult = export
                previewImage = NSImage(contentsOf: export.previewURL)
                statusMessage = "Generated \(export.manifestIconPath)"
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Export failed"
        }
        isExporting = false
    }

    func revealResult() {
        guard let outputDirectory = activeOutputDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputDirectory])
    }

    var activeOutputDirectory: URL? {
        switch outputKind {
        case .appIcon:
            result?.outputDirectory
        case .gearIcon:
            gearIconResult?.outputDirectory
        }
    }

    func runAgentAction(capabilityID: String = "app_icon.generate", args: [String: Any]) -> [String: Any] {
        guard let sourcePath = args["source_path"] as? String ?? args["path"] as? String else {
            return failurePayload(
                capabilityID: capabilityID,
                code: "gear.args.source_path",
                error: "`source_path` is required.",
                recovery: "Pass a local image path selected or supplied by the user."
            )
        }

        let outputDir = args["output_dir"] as? String ?? args["output_directory"] as? String
        do {
            let expandedSourceURL = URL(fileURLWithPath: NSString(string: sourcePath).expandingTildeInPath)
            let expandedOutputURL = outputDir.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true) }
            switch capabilityID {
            case "app_icon.generate":
                let export = try AppIconForgeRenderer.exportIcons(settings: AppIconForgeExportSettings(
                    sourceURL: expandedSourceURL,
                    outputDirectory: expandedOutputURL,
                    baseName: (args["name"] as? String) ?? "AppIcon",
                    contentScale: numberArg(args["content_scale"]) ?? 0.88,
                    cornerRadiusRatio: numberArg(args["corner_radius_ratio"]) ?? 0.22,
                    includesShadow: (args["shadow"] as? Bool) ?? true
                ))
                result = export
                outputKind = .appIcon
                sourceURL = export.sourceURL
                outputDirectory = expandedOutputURL
                previewImage = NSImage(contentsOf: export.previewURL)
                statusMessage = "Generated \(export.icnsURL.lastPathComponent)"
                return successPayload(export)
            case "gear_icon.generate":
                let export = try AppIconForgeRenderer.exportGearIcon(settings: AppIconForgeGearIconSettings(
                    sourceURL: expandedSourceURL,
                    outputDirectory: expandedOutputURL,
                    baseName: (args["name"] as? String) ?? "GearIcon",
                    contentScale: numberArg(args["content_scale"]) ?? 0.84,
                    cornerRadiusRatio: numberArg(args["corner_radius_ratio"]) ?? 0.18,
                    includesShadow: (args["shadow"] as? Bool) ?? true
                ))
                gearIconResult = export
                outputKind = .gearIcon
                sourceURL = export.sourceURL
                outputDirectory = expandedOutputURL
                previewImage = NSImage(contentsOf: export.previewURL)
                statusMessage = "Generated \(export.manifestIconPath)"
                return successPayload(export)
            default:
                return failurePayload(
                    capabilityID: capabilityID,
                    code: "gear.app_icon.capability_unsupported",
                    error: "app.icon.forge does not support `\(capabilityID)` yet.",
                    recovery: "Invoke app_icon.generate or gear_icon.generate."
                )
            }
        } catch let error as AppIconForgeError {
            return failurePayload(
                capabilityID: capabilityID,
                code: error.code,
                error: error.localizedDescription,
                recovery: recovery(for: error)
            )
        } catch {
            return failurePayload(
                capabilityID: capabilityID,
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

    private func successPayload(_ result: AppIconForgeGearIconResult) -> [String: Any] {
        [
            "status": "succeeded",
            "gear_id": AppIconForgeGearDescriptor.gearID,
            "capability_id": "gear_icon.generate",
            "source_path": result.sourceURL.path,
            "output_dir": result.outputDirectory.path,
            "assets_path": result.assetsDirectoryURL.path,
            "icon_path": result.iconURL.path,
            "manifest_icon": result.manifestIconPath,
            "preview_path": result.previewURL.path,
            "metadata_path": result.metadataURL.path,
            "generated_files": result.generatedFiles.map(\.path),
            "spec": [
                "id": AppIconForgeGearIconSpec.id,
                "canvas_width_px": AppIconForgeGearIconSpec.canvasWidthPixels,
                "canvas_height_px": AppIconForgeGearIconSpec.canvasHeightPixels,
                "aspect_ratio": AppIconForgeGearIconSpec.aspectRatio,
                "manifest_icon": AppIconForgeGearIconSpec.manifestIconPath,
                "intended_surface": AppIconForgeGearIconSpec.intendedSurface
            ]
        ]
    }

    private func failurePayload(capabilityID: String, code: String, error: String, recovery: String) -> [String: Any] {
        [
            "status": "failed",
            "gear_id": AppIconForgeGearDescriptor.gearID,
            "capability_id": capabilityID,
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
