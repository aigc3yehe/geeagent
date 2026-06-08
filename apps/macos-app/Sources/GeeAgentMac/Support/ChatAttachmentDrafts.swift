import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ChatAttachmentDraft: Identifiable {
    enum Kind {
        case image
        case file
        case directory

        var runtimeKind: WorkspaceInputAttachment.Kind {
            switch self {
            case .image: .image
            case .file: .file
            case .directory: .directory
            }
        }

        var systemImage: String {
            switch self {
            case .image: "photo"
            case .file: "doc"
            case .directory: "folder"
            }
        }
    }

    enum Status {
        case ready
        case failed(code: String, message: String)

        var runtimeStatus: WorkspaceInputAttachment.Status {
            switch self {
            case .ready: .ready
            case .failed: .failed
            }
        }
    }

    var id: String
    var kind: Kind
    var displayName: String
    var originalPath: String
    var resolvedPath: String?
    var mimeType: String?
    var sizeBytes: Int?
    var status: Status
    var thumbnail: NSImage?

    var isSendable: Bool {
        if case .failed = status {
            return false
        }
        return true
    }

    var tooltip: String {
        switch status {
        case .ready:
            return resolvedPath ?? originalPath
        case let .failed(_, message):
            return message
        }
    }

    var runtimeAttachment: WorkspaceInputAttachment {
        var attachment = WorkspaceInputAttachment(
            attachmentId: id,
            kind: kind.runtimeKind,
            displayName: displayName,
            originalPath: originalPath,
            resolvedPath: resolvedPath,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            createdAt: Self.isoTimestamp(),
            status: status.runtimeStatus
        )
        if kind == .directory {
            attachment.access.root = resolvedPath ?? originalPath
            attachment.limits = WorkspaceInputAttachment.Limits(
                maxBytes: nil,
                maxEntries: 500,
                maxDepth: 3
            )
        }
        if case let .failed(code, message) = status {
            attachment.error = WorkspaceInputAttachment.Failure(code: code, message: message)
        }
        return attachment
    }

    static func make(fileURL url: URL) -> ChatAttachmentDraft {
        let standardized = url.standardizedFileURL
        let path = standardized.path
        let displayName = standardized.lastPathComponent.isEmpty ? path : standardized.lastPathComponent
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists else {
            return ChatAttachmentDraft(
                id: "att_\(UUID().uuidString)",
                kind: .file,
                displayName: displayName,
                originalPath: path,
                resolvedPath: nil,
                mimeType: nil,
                sizeBytes: nil,
                status: .failed(code: "file.missing", message: "The dropped path does not exist."),
                thumbnail: nil
            )
        }

        let kind: Kind = isDirectory.boolValue ? .directory : (isImageFile(standardized) ? .image : .file)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.intValue
        return ChatAttachmentDraft(
            id: "att_\(UUID().uuidString)",
            kind: kind,
            displayName: displayName,
            originalPath: path,
            resolvedPath: standardized.resolvingSymlinksInPath().path,
            mimeType: isDirectory.boolValue ? nil : mimeType(for: standardized),
            sizeBytes: isDirectory.boolValue ? nil : size,
            status: .ready,
            thumbnail: kind == .image ? thumbnailImage(for: standardized, sizeBytes: size) : nil
        )
    }

    static func make(pastedImage image: NSImage) -> ChatAttachmentDraft {
        let fileName = "pasted-image-\(UUID().uuidString.prefix(8)).png"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("geeagent-chat-attachments", isDirectory: true)
        let fileURL = directory.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try pngData(from: image)
            try data.write(to: fileURL, options: [.atomic])
            return ChatAttachmentDraft(
                id: "att_\(UUID().uuidString)",
                kind: .image,
                displayName: fileName,
                originalPath: fileURL.path,
                resolvedPath: fileURL.standardizedFileURL.resolvingSymlinksInPath().path,
                mimeType: "image/png",
                sizeBytes: data.count,
                status: .ready,
                thumbnail: image
            )
        } catch {
            return ChatAttachmentDraft(
                id: "att_\(UUID().uuidString)",
                kind: .image,
                displayName: fileName,
                originalPath: fileURL.path,
                resolvedPath: nil,
                mimeType: "image/png",
                sizeBytes: nil,
                status: .failed(code: "image.paste_failed", message: error.localizedDescription),
                thumbnail: image
            )
        }
    }

    private static func pngData(from image: NSImage) throws -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "GeeAgentMac.ChatAttachmentDraft",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode pasted image as PNG."]
            )
        }
        return pngData
    }

    private static func thumbnailImage(for url: URL, sizeBytes: Int?) -> NSImage? {
        if let sizeBytes, sizeBytes > 8 * 1024 * 1024 {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    private static func mimeType(for url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

enum ChatAttachmentTransfer {
    static let fileDropTypes = [UTType.fileURL.identifier]
    static let pasteTypes: [UTType] = [.fileURL, .image, .png, .jpeg]

    static func handleFileDrop(
        _ providers: [NSItemProvider],
        appendURLs: @escaping @MainActor ([URL]) -> Void
    ) -> Bool {
        var didAcceptProvider = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            didAcceptProvider = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = fileURL(from: item) else {
                    return
                }
                Task { @MainActor in
                    appendURLs([url])
                }
            }
        }
        return didAcceptProvider
    }

    static func handlePaste(
        _ providers: [NSItemProvider],
        appendURLs: @escaping @MainActor ([URL]) -> Void,
        appendDrafts: @escaping @MainActor ([ChatAttachmentDraft]) -> Void
    ) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let url = fileURL(from: item) else {
                        return
                    }
                    Task { @MainActor in
                        appendURLs([url])
                    }
                }
                continue
            }

            guard provider.canLoadObject(ofClass: NSImage.self) else {
                continue
            }
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else {
                    return
                }
                Task { @MainActor in
                    appendDrafts([ChatAttachmentDraft.make(pastedImage: image)])
                }
            }
        }
    }

    @MainActor
    static func showAttachmentPicker(appendURLs: @escaping @MainActor ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Attach"
        panel.begin { response in
            guard response == .OK else {
                return
            }
            Task { @MainActor in
                appendURLs(panel.urls)
            }
        }
    }

    private static func fileURL(from item: Any?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            if let url = URL(string: string), url.isFileURL {
                return url
            }
            return URL(fileURLWithPath: string)
        }
        return nil
    }
}

struct ChatAttachmentDraftStrip: View {
    @Environment(\.appLanguage) private var appLanguage

    var attachments: [ChatAttachmentDraft]
    var prominentBackground = false
    var onRemove: (ChatAttachmentDraft.ID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 7) {
                        attachmentIcon(attachment)

                        Text(attachment.displayName)
                            .font(.geeDisplaySemibold(11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 180)

                        Button {
                            onRemove(attachment.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help(AppLocalization.string("attachment.removeHelp", defaultValue: "Remove attachment", language: appLanguage))
                    }
                    .padding(.horizontal, 9)
                    .frame(height: attachment.thumbnail == nil ? 28 : 34)
                    .background(
                        Capsule(style: .continuous)
                            .fill(tint(for: attachment).opacity(prominentBackground ? 0.18 : 0.12))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(tint(for: attachment).opacity(prominentBackground ? 0.34 : 0.28), lineWidth: 0.8)
                    }
                    .foregroundStyle(prominentBackground ? .white.opacity(0.9) : .primary)
                    .help(attachment.tooltip)
                }
            }
        }
        .thinScrollIndicator()
    }

    @ViewBuilder
    private func attachmentIcon(_ attachment: ChatAttachmentDraft) -> some View {
        if let thumbnail = attachment.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
                }
        } else {
            Image(systemName: attachment.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint(for: attachment))
        }
    }

    private func tint(for attachment: ChatAttachmentDraft) -> Color {
        if case .failed = attachment.status {
            return .red
        }
        switch attachment.kind {
        case .image:
            return .purple
        case .file:
            return .accentColor
        case .directory:
            return .orange
        }
    }
}

extension Array where Element == ChatAttachmentDraft {
    mutating func appendUniqueAttachmentDrafts(_ drafts: [ChatAttachmentDraft]) {
        var existingPaths = Set(map(\.originalPath))
        for draft in drafts where !existingPaths.contains(draft.originalPath) {
            append(draft)
            existingPaths.insert(draft.originalPath)
        }
    }
}
