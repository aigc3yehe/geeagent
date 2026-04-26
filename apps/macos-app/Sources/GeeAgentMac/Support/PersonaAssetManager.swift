import Foundation
import AppKit

/// Manages on-disk persona assets (image banners, looping videos, Live2D bundles).
///
/// All assets live under `~/Library/Application Support/GeeAgent/Personas/<personaID>/<kind>/`
/// where `<kind>` is one of `image`, `video`, or `live2d`. Each operation is idempotent and safe
/// to call repeatedly; callers are responsible for calling `pruneUnused(personaID:kind:currentPath:)`
/// after a successful copy when they want to drop older revisions from disk.
///
/// `PersonaAssetManager` replaces the legacy `BannerAssetManager`. The old single-bucket
/// `~/Library/Application Support/GeeAgent/Banners/` directory is migrated into the active
/// persona's `image/` (or `video/`) folder the first time the store boots after upgrade —
/// see `WorkbenchStore.migrateLegacyHomeAppearancePreferences` for the wiring.
enum PersonaAssetManager {

    // MARK: - Kinds

    enum AssetKind: String, CaseIterable {
        case image
        case video
        case live2D = "live2d"

        fileprivate var directoryName: String { rawValue }
    }

    // MARK: - Extension probes

    static var imageExtensions: Set<String> { ["png", "jpg", "jpeg", "heic", "tif", "tiff", "webp", "bmp", "gif"] }
    static var videoExtensions: Set<String> { ["mp4", "mov", "m4v"] }
    static var live2DBundleFileSuffix: String { ".model3.json" }

    static func isVideoPath(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return videoExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    static func isImagePath(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return imageExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    /// Classifies a path into an `AssetKind` based on extension and, for Live2D, on the target
    /// being a `.zip` or a directory/file matching the Cubism model layout.
    static func classify(path: String) -> AssetKind? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if imageExtensions.contains(ext) { return .image }
        if ext == "zip" { return .live2D }
        if path.lowercased().hasSuffix(live2DBundleFileSuffix) { return .live2D }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            // A bare directory is only classified as live2d when it carries a *.model3.json.
            if findModel3Json(in: URL(fileURLWithPath: path)) != nil { return .live2D }
        }
        return nil
    }

    // MARK: - Image / video copy

    /// Copies an image or video file under `Personas/<personaID>/<kind>/` with a fresh UUID name
    /// so the asset survives the original file being moved or deleted.
    @discardableResult
    static func copyMediaAsset(
        from source: URL,
        kind: AssetKind,
        personaID: String
    ) throws -> URL {
        precondition(kind == .image || kind == .video, "copyMediaAsset only handles image/video")
        let destDir = try directory(for: kind, personaID: personaID)
        let ext = source.pathExtension.lowercased()
        let filename = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let dest = destDir.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    // MARK: - Live2D bundles

    /// Imports a Live2D asset into `Personas/<personaID>/live2d/<bundle-id>/` and returns the
    /// URL of the `*.model3.json` file inside the imported bundle.
    ///
    /// The source may be:
    /// - a directory containing a `*.model3.json` file at its root (the whole directory is copied),
    /// - a `*.model3.json` file (the parent directory is copied if it exists, otherwise just the file),
    /// - a `.zip` archive (extracted via `/usr/bin/ditto`).
    ///
    /// Throws if nothing resembling a Cubism model3 descriptor is found after import.
    @discardableResult
    static func importLive2DBundle(
        from source: URL,
        personaID: String
    ) throws -> URL {
        let fm = FileManager.default
        let destRoot = try directory(for: .live2D, personaID: personaID)
        let importedDir = destRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: importedDir, withIntermediateDirectories: true)

        let ext = source.pathExtension.lowercased()
        if ext == "zip" {
            try runDitto(source: source, destinationDir: importedDir)
        } else {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: source.path, isDirectory: &isDir)
            if isDir.boolValue {
                try copyDirectoryContents(from: source, into: importedDir)
            } else if source.lastPathComponent.lowercased().hasSuffix(live2DBundleFileSuffix) {
                // Stand-alone model3 file: copy its parent directory if it looks like a bundle,
                // otherwise just the file.
                if let parent = URL(fileURLWithPath: source.deletingLastPathComponent().path) as URL?,
                   fm.fileExists(atPath: parent.path) {
                    try copyDirectoryContents(from: parent, into: importedDir)
                } else {
                    try fm.copyItem(at: source, to: importedDir.appendingPathComponent(source.lastPathComponent))
                }
            } else {
                throw ImportError.unsupportedInput(path: source.path)
            }
        }

        guard let model3 = findModel3Json(in: importedDir) else {
            try? fm.removeItem(at: importedDir)
            throw ImportError.noModel3Json(path: source.path)
        }
        return model3
    }

    enum ImportError: LocalizedError {
        case unsupportedInput(path: String)
        case noModel3Json(path: String)
        case dittoFailed(status: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case .unsupportedInput(let path):
                return "Can't import Live2D bundle from \(path) — expected a folder, .zip, or *.model3.json file."
            case .noModel3Json(let path):
                return "Imported bundle at \(path) has no *.model3.json descriptor."
            case .dittoFailed(let status, let stderr):
                return "ditto failed (\(status)): \(stderr)"
            }
        }
    }

    // MARK: - Pruning

    /// Deletes every file / bundle inside the persona's directory for `kind` other than the
    /// currently-referenced one. Passing `nil` for `currentPath` clears the whole folder.
    static func pruneUnused(
        personaID: String,
        kind: AssetKind,
        currentPath: String?
    ) {
        guard let dir = try? directory(for: kind, personaID: personaID) else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        // For Live2D we keep the whole ancestor bundle directory if `currentPath` lives inside it.
        let currentContainerPath: String? = currentPath.flatMap { path in
            if kind == .live2D {
                return liveBundleContainer(forModel3Path: path, underRoot: dir)?.path
            }
            return path
        }

        for url in entries {
            if let keep = currentContainerPath, url.path == keep { continue }
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Live2D helpers

    /// Walks `root` and returns the first file whose name ends in `.model3.json`. Searches
    /// top-level first, then one layer deep, to avoid pathological directory crawls.
    static func findModel3Json(in root: URL) -> URL? {
        let fm = FileManager.default
        guard let shallow = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        if let direct = shallow.first(where: { isModel3Json($0) }) {
            return direct
        }
        for entry in shallow {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if let nested = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil),
               let descriptor = nested.first(where: { isModel3Json($0) }) {
                return descriptor
            }
        }
        return nil
    }

    private static func isModel3Json(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased().hasSuffix(live2DBundleFileSuffix)
    }

    private static func liveBundleContainer(forModel3Path model3Path: String, underRoot root: URL) -> URL? {
        let model3URL = URL(fileURLWithPath: model3Path)
        guard model3URL.path.hasPrefix(root.path) else { return nil }
        // Return the first directory under `root` that contains the model3 descriptor.
        var current = model3URL.deletingLastPathComponent()
        while current.path != root.path {
            let parent = current.deletingLastPathComponent()
            if parent.path == root.path { return current }
            if parent.path.isEmpty { return nil }
            current = parent
        }
        return nil
    }

    // MARK: - Directory management

    private static func directory(for kind: AssetKind, personaID: String) throws -> URL {
        let base = try personasRoot().appendingPathComponent(personaID, isDirectory: true)
        let dir = base.appendingPathComponent(kind.directoryName, isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func personasRoot() throws -> URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let root = appSupport.appendingPathComponent("GeeAgent/Personas", isDirectory: true)
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    // MARK: - Legacy migration

    /// Moves pre-persona banner assets (previously stored under `GeeAgent/Banners/`) into the
    /// given persona's `image/` or `video/` folder, returning the new canonical path. Used once
    /// on boot by `WorkbenchStore.migrateLegacyHomeAppearancePreferences`. Missing source paths
    /// yield `nil` without an error; callers should fall back to the bundled hero.
    static func migrateLegacyBanner(path: String, forPersona personaID: String) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }
        let kind: AssetKind = isVideoPath(path) ? .video : .image
        let sourceURL = URL(fileURLWithPath: path)
        do {
            let copied = try copyMediaAsset(from: sourceURL, kind: kind, personaID: personaID)
            return copied.path
        } catch {
            return nil
        }
    }

    /// Removes the legacy `GeeAgent/Banners/` directory if present. Safe to call even if the
    /// directory was already cleaned up.
    static func cleanupLegacyBannersDirectory() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacy = appSupport.appendingPathComponent("GeeAgent/Banners", isDirectory: true)
        if fm.fileExists(atPath: legacy.path) {
            try? fm.removeItem(at: legacy)
        }
    }

    // MARK: - Private file ops

    private static func copyDirectoryContents(from source: URL, into destination: URL) throws {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for entry in entries {
            let target = destination.appendingPathComponent(entry.lastPathComponent)
            try fm.copyItem(at: entry, to: target)
        }
    }

    private static func runDitto(source: URL, destinationDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", source.path, destinationDir.path]

        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            throw ImportError.dittoFailed(status: process.terminationStatus, stderr: stderrText)
        }
    }
}
