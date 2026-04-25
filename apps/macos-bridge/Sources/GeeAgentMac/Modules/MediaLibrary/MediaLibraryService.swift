import AppKit
import AVFoundation
import Foundation

enum MediaLibraryKind: String, Codable, Hashable {
    case eagle
    case viewer
}

struct MediaLibraryInfo: Hashable {
    var name: String
    var url: URL
    var kind: MediaLibraryKind
    var folders: [MediaLibraryFolder]
}

struct MediaLibraryFolder: Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Date
    var depth: Int
}

struct MediaLibraryItem: Identifiable, Hashable {
    var id: String
    var name: String
    var ext: String
    var width: Int?
    var height: Int?
    var durationSeconds: Double?
    var size: Int64
    var modifiedAt: Date
    var tags: [String]
    var annotation: String?
    var sourceURL: String?
    var fileURL: URL
    var thumbnailURL: URL?
    var folderIDs: [String]
    var isStarred: Bool

    var primaryFolderID: String? {
        folderIDs.first
    }

    var mediaKind: MediaLibraryMediaKind {
        MediaLibraryService.videoExtensions.contains(ext.lowercased()) ? .video : .image
    }
}

enum MediaLibraryMediaKind: String, CaseIterable, Identifiable, Hashable {
    case all
    case image
    case video

    var id: String { rawValue }
}

struct MediaLibraryFilterState: Hashable {
    var mediaKind: MediaLibraryMediaKind = .all
    var selectedExtensions: Set<String> = []
    var starredOnly = false
    var minimumDurationSeconds: Double?
    var searchText = ""
}

final class MediaLibraryService {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "heic"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "avi", "webm", "mkv", "m4v"]

    private let fileManager = FileManager.default

    func openLibrary(at url: URL) throws -> MediaLibraryInfo {
        let kind = try libraryKind(for: url)
        let folders = try loadFolders(from: url, kind: kind)
        return MediaLibraryInfo(
            name: url.deletingPathExtension().lastPathComponent,
            url: url,
            kind: kind,
            folders: folders
        )
    }

    func createLibrary(parentURL: URL, name: String) throws -> MediaLibraryInfo {
        let libraryURL = parentURL.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: libraryURL.appendingPathComponent("images", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: libraryURL.appendingPathComponent("thumbnails", isDirectory: true), withIntermediateDirectories: true)

        let now = currentMilliseconds()
        try writeJSONObject(
            [
                "folders": [],
                "smartFolders": [],
                "quickAccess": [],
                "tagsGroups": [],
                "modificationTime": now,
                "applicationVersion": "4.0.0"
            ],
            to: libraryURL.appendingPathComponent("metadata.json")
        )
        try writeJSONObject(["historyTags": [], "starredTags": []], to: libraryURL.appendingPathComponent("tags.json"))
        try writeJSONObject([:], to: libraryURL.appendingPathComponent("mtime.json"))

        return MediaLibraryInfo(name: name, url: libraryURL, kind: .eagle, folders: [])
    }

    func loadFolders(from libraryURL: URL, kind: MediaLibraryKind) throws -> [MediaLibraryFolder] {
        switch kind {
        case .eagle:
            let rootURL = libraryURL.appendingPathComponent("metadata.json")
            let root = try readJSONObject(from: rootURL)
            let folders = root["folders"] as? [[String: Any]] ?? []
            return flattenEagleFolders(folders)
        case .viewer:
            let rootURL = libraryURL.appendingPathComponent("library.json")
            let root = try readJSONObject(from: rootURL)
            let folders = root["folders"] as? [[String: Any]] ?? []
            return folders.compactMap { folder in
                guard let id = folder["id"] as? String, let name = folder["name"] as? String else {
                    return nil
                }
                return MediaLibraryFolder(
                    id: id,
                    name: name,
                    createdAt: dateFromMilliseconds(folder["created"] as? Double),
                    depth: 0
                )
            }
        }
    }

    func loadItems(from libraryURL: URL) throws -> [MediaLibraryItem] {
        let imagesURL = libraryURL.appendingPathComponent("images", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(at: imagesURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        let itemURLs = entries.filter { $0.pathExtension == "info" }
        var items: [MediaLibraryItem] = []

        for itemURL in itemURLs {
            let metadataURL = itemURL.appendingPathComponent("metadata.json")
            guard let metadata = try? readJSONObject(from: metadataURL) else {
                continue
            }
            if metadata["isDeleted"] as? Bool == true {
                continue
            }

            guard let item = try loadItem(itemURL: itemURL, metadata: metadata) else {
                continue
            }
            items.append(item)
        }

        return items.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func importFiles(_ fileURLs: [URL], into libraryURL: URL) throws -> [MediaLibraryItem] {
        let supportedExtensions = Self.imageExtensions.union(Self.videoExtensions)
        var existingSignatures = Set(
            (try? loadItems(from: libraryURL)).map { items in
                items.map { Self.itemSignature(fileName: $0.fileURL.lastPathComponent, size: $0.size) }
            } ?? []
        )
        var imported: [MediaLibraryItem] = []

        for fileURL in fileURLs {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else {
                continue
            }

            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let size = int64(attributes[.size]) ?? 0
            let signature = Self.itemSignature(fileName: fileURL.lastPathComponent, size: size)
            guard !existingSignatures.contains(signature) else {
                continue
            }

            let id = Self.generateEagleID()
            let itemURL = libraryURL
                .appendingPathComponent("images", isDirectory: true)
                .appendingPathComponent("\(id).info", isDirectory: true)
            try fileManager.createDirectory(at: itemURL, withIntermediateDirectories: true)

            let destinationURL = itemURL.appendingPathComponent(fileURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: fileURL, to: destinationURL)

            let mediaInfo = try makeThumbnailIfPossible(for: destinationURL, in: itemURL)

            var metadata: [String: Any] = [
                "id": id,
                "name": destinationURL.deletingPathExtension().lastPathComponent,
                "size": size,
                "ext": ext,
                "tags": [],
                "folders": [],
                "isDeleted": false,
                "url": "",
                "annotation": "",
                "modificationTime": currentMilliseconds(),
                "starred": false,
                "lastModified": currentMilliseconds()
            ]
            if let width = mediaInfo.width {
                metadata["width"] = width
            }
            if let height = mediaInfo.height {
                metadata["height"] = height
            }
            if let duration = mediaInfo.durationSeconds {
                metadata["duration"] = duration
            }
            try writeJSONObject(metadata, to: itemURL.appendingPathComponent("metadata.json"))

            if let item = try loadItem(itemURL: itemURL, metadata: metadata) {
                imported.append(item)
                existingSignatures.insert(signature)
            }
        }

        return imported
    }

    func deleteItem(id: String, from libraryURL: URL) throws {
        let itemURL = libraryURL
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent("\(id).info", isDirectory: true)
        if fileManager.fileExists(atPath: itemURL.path) {
            try fileManager.removeItem(at: itemURL)
        }
    }

    func setStarred(_ isStarred: Bool, itemID: String, in libraryURL: URL) throws {
        let metadataURL = metadataURL(for: itemID, in: libraryURL)
        var metadata = try readJSONObject(from: metadataURL)
        metadata["starred"] = isStarred
        metadata["lastModified"] = currentMilliseconds()
        try writeJSONObject(metadata, to: metadataURL)
    }

    func moveItems(_ itemIDs: Set<String>, to folderID: String?, in libraryURL: URL) throws {
        for itemID in itemIDs {
            let metadataURL = metadataURL(for: itemID, in: libraryURL)
            var metadata = try readJSONObject(from: metadataURL)
            metadata["folders"] = folderID.map { [$0] } ?? []
            metadata["lastModified"] = currentMilliseconds()
            try writeJSONObject(metadata, to: metadataURL)
        }
    }

    func createFolder(named name: String, in libraryURL: URL) throws -> MediaLibraryFolder {
        var root = try readJSONObject(from: libraryURL.appendingPathComponent("metadata.json"))
        var folders = root["folders"] as? [[String: Any]] ?? []
        let id = Self.generateEagleID()
        let created = currentMilliseconds()
        let folder: [String: Any] = [
            "id": id,
            "name": name,
            "description": "",
            "children": [],
            "modificationTime": created,
            "tags": []
        ]
        folders.append(folder)
        root["folders"] = folders
        root["modificationTime"] = created
        try writeJSONObject(root, to: libraryURL.appendingPathComponent("metadata.json"))
        return MediaLibraryFolder(id: id, name: name, createdAt: dateFromMilliseconds(Double(created)), depth: 0)
    }

    private func libraryKind(for libraryURL: URL) throws -> MediaLibraryKind {
        if fileManager.fileExists(atPath: libraryURL.appendingPathComponent("metadata.json").path) {
            return .eagle
        }
        if fileManager.fileExists(atPath: libraryURL.appendingPathComponent("library.json").path) {
            return .viewer
        }
        throw MediaLibraryError.invalidLibrary
    }

    private func loadItem(itemURL: URL, metadata: [String: Any]) throws -> MediaLibraryItem? {
        let files = try fileManager.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let fileURL = files.first(where: { url in
            let name = url.lastPathComponent
            return name != "metadata.json" && !name.hasPrefix(".") && !name.hasPrefix("_thumbnail")
        }) else {
            return nil
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let ext = string(metadata["ext"]) ?? fileURL.pathExtension.lowercased()
        let thumbnailURL = files.first(where: { $0.lastPathComponent.hasPrefix("_thumbnail") })
            ?? (Self.imageExtensions.contains(ext.lowercased()) ? fileURL : nil)

        let folderIDs = metadata["folders"] as? [String] ?? []
        return MediaLibraryItem(
            id: string(metadata["id"]) ?? itemURL.deletingPathExtension().lastPathComponent,
            name: string(metadata["name"]) ?? fileURL.deletingPathExtension().lastPathComponent,
            ext: ext,
            width: int(metadata["width"]),
            height: int(metadata["height"]),
            durationSeconds: double(metadata["duration"]),
            size: int64(metadata["size"]) ?? attributes[.size] as? Int64 ?? 0,
            modifiedAt: dateFromMilliseconds(double(metadata["modificationTime"]) ?? double(metadata["lastModified"])),
            tags: metadata["tags"] as? [String] ?? [],
            annotation: string(metadata["annotation"]),
            sourceURL: string(metadata["url"]),
            fileURL: fileURL,
            thumbnailURL: thumbnailURL,
            folderIDs: folderIDs,
            isStarred: starredValue(from: metadata)
        )
    }

    private func flattenEagleFolders(_ folders: [[String: Any]], depth: Int = 0) -> [MediaLibraryFolder] {
        var output: [MediaLibraryFolder] = []
        for folder in folders {
            if let id = folder["id"] as? String, let name = folder["name"] as? String {
                output.append(
                    MediaLibraryFolder(
                        id: id,
                        name: name,
                        createdAt: dateFromMilliseconds(double(folder["modificationTime"])),
                        depth: depth
                    )
                )
            }
            if let children = folder["children"] as? [[String: Any]], !children.isEmpty {
                output.append(contentsOf: flattenEagleFolders(children, depth: depth + 1))
            }
        }
        return output
    }

    private func makeThumbnailIfPossible(for mediaURL: URL, in itemURL: URL) throws -> (width: Int?, height: Int?, durationSeconds: Double?) {
        let ext = mediaURL.pathExtension.lowercased()
        let thumbnailURL = itemURL.appendingPathComponent("_thumbnail.png")

        if Self.imageExtensions.contains(ext), let image = NSImage(contentsOf: mediaURL) {
            let size = image.size
            try writeThumbnail(from: image, to: thumbnailURL)
            return (Int(size.width), Int(size.height), nil)
        }

        if Self.videoExtensions.contains(ext) {
            let asset = AVURLAsset(url: mediaURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let imageTime = CMTime(seconds: 0.2, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: imageTime, actualTime: nil) {
                try writeThumbnail(from: NSImage(cgImage: cgImage, size: .zero), to: thumbnailURL)
            }
            let duration = CMTimeGetSeconds(asset.duration)
            if let track = asset.tracks(withMediaType: .video).first {
                let naturalSize = track.naturalSize.applying(track.preferredTransform)
                return (Int(abs(naturalSize.width)), Int(abs(naturalSize.height)), duration.isFinite ? duration : nil)
            }
            return (nil, nil, duration.isFinite ? duration : nil)
        }

        return (nil, nil, nil)
    }

    private func writeThumbnail(from image: NSImage, to url: URL) throws {
        let maxDimension: CGFloat = 420
        let ratio = min(maxDimension / max(image.size.width, 1), maxDimension / max(image.size.height, 1), 1)
        let targetSize = NSSize(width: max(image.size.width * ratio, 1), height: max(image.size.height * ratio, 1))
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        resized.unlockFocus()

        guard
            let tiff = resized.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw MediaLibraryError.thumbnailFailed
        }
        try png.write(to: url)
    }

    private func metadataURL(for itemID: String, in libraryURL: URL) -> URL {
        libraryURL
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent("\(itemID).info", isDirectory: true)
            .appendingPathComponent("metadata.json")
    }

    private func readJSONObject(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let value = try JSONSerialization.jsonObject(with: data)
        return value as? [String: Any] ?? [:]
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func currentMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func dateFromMilliseconds(_ value: Double?) -> Date {
        guard let value else {
            return Date(timeIntervalSince1970: 0)
        }
        return Date(timeIntervalSince1970: value / 1000)
    }

    private func string(_ value: Any?) -> String? {
        value as? String
    }

    private func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        return nil
    }

    private func int64(_ value: Any?) -> Int64? {
        if let int = value as? Int { return Int64(int) }
        if let int64 = value as? Int64 { return int64 }
        if let number = value as? NSNumber { return number.int64Value }
        if let double = value as? Double { return Int64(double) }
        return nil
    }

    private func double(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let int64 = value as? Int64 { return Double(int64) }
        return nil
    }

    private func starredValue(from metadata: [String: Any]) -> Bool {
        if let starred = metadata["starred"] as? Bool {
            return starred
        }
        if let isStarred = metadata["isStarred"] as? Bool {
            return isStarred
        }
        if let rating = int(metadata["rating"]) {
            return rating > 0
        }
        if let star = int(metadata["star"]) {
            return star > 0
        }
        return false
    }

    static func generateEagleID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(13)).uppercased()
    }

    private static func itemSignature(fileName: String, size: Int64) -> String {
        "\(fileName.lowercased())#\(size)"
    }
}

enum MediaLibraryError: LocalizedError {
    case invalidLibrary
    case thumbnailFailed

    var errorDescription: String? {
        switch self {
        case .invalidLibrary:
            return "Choose a valid Eagle or Viewer library folder."
        case .thumbnailFailed:
            return "The thumbnail could not be written."
        }
    }
}
