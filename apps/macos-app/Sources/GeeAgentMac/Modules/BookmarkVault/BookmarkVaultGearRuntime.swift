import AppKit
import Foundation

struct BookmarkVaultRecord: Codable, Identifiable, Hashable {
    var id: String
    var rawContent: String
    var pageTitle: String?
    var url: String?
    var createdAt: Date
    var updatedAt: Date
    var metadataSource: String
    var description: String?
    var siteName: String?
    var thumbnailURL: String?
    var canonicalURL: String?
    var mediaTitle: String?
    var platform: String?
    var uploader: String?
    var durationSeconds: Double?
    var extensionHint: String?
    var formatCount: Int?
    var extras: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case rawContent = "raw_content"
        case pageTitle = "page_title"
        case url
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case metadataSource = "metadata_source"
        case description
        case siteName = "site_name"
        case thumbnailURL = "thumbnail_url"
        case canonicalURL = "canonical_url"
        case mediaTitle = "media_title"
        case platform
        case uploader
        case durationSeconds = "duration_seconds"
        case extensionHint = "extension_hint"
        case formatCount = "format_count"
        case extras
    }

    var displayTitle: String {
        pageTitle?.nilIfBlank
            ?? mediaTitle?.nilIfBlank
            ?? url?.nilIfBlank
            ?? rawContent.nilIfBlank
            ?? "Untitled bookmark"
    }

    var subtitle: String {
        url?.nilIfBlank
            ?? description?.nilIfBlank
            ?? "Plain saved content"
    }

    var sourceLabel: String {
        switch metadataSource {
        case "yt-dlp": "Media"
        case "twitter_oembed": "Twitter/X"
        case "basic_fetch": "Web"
        case "manual": "Text"
        default: metadataSource
        }
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "raw_content": rawContent,
            "metadata_source": metadataSource,
            "created_at": ISO8601DateFormatter().string(from: createdAt),
            "updated_at": ISO8601DateFormatter().string(from: updatedAt),
            "extras": extras
        ]
        if let pageTitle = pageTitle?.nilIfBlank { payload["page_title"] = pageTitle }
        if let url = url?.nilIfBlank { payload["url"] = url }
        if let description = description?.nilIfBlank { payload["description"] = description }
        if let siteName = siteName?.nilIfBlank { payload["site_name"] = siteName }
        if let thumbnailURL = thumbnailURL?.nilIfBlank { payload["thumbnail_url"] = thumbnailURL }
        if let canonicalURL = canonicalURL?.nilIfBlank { payload["canonical_url"] = canonicalURL }
        if let mediaTitle = mediaTitle?.nilIfBlank { payload["media_title"] = mediaTitle }
        if let platform = platform?.nilIfBlank { payload["platform"] = platform }
        if let uploader = uploader?.nilIfBlank { payload["uploader"] = uploader }
        if let durationSeconds { payload["duration_seconds"] = durationSeconds }
        if let extensionHint = extensionHint?.nilIfBlank { payload["extension_hint"] = extensionHint }
        if let formatCount { payload["format_count"] = formatCount }
        return payload
    }
}

struct BookmarkVaultMetadata: Hashable {
    var pageTitle: String?
    var url: String?
    var description: String?
    var siteName: String?
    var thumbnailURL: String?
    var canonicalURL: String?
    var mediaTitle: String?
    var platform: String?
    var uploader: String?
    var durationSeconds: Double?
    var extensionHint: String?
    var formatCount: Int?
    var source: String
    var extras: [String: String] = [:]
}

enum BookmarkVaultInputParser {
    static func firstURL(in value: String) -> String? {
        let pattern = #"(?i)\b((?:https?://|www\.)[^\s<>"'，。！？、]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: value)
        else {
            return nil
        }

        var url = String(value[matchRange])
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,，。;；!！?？)]}）】"))
        if url.lowercased().hasPrefix("www.") {
            url = "https://\(url)"
        }
        guard let parsed = URL(string: url), parsed.scheme != nil, parsed.host != nil else {
            return nil
        }
        return url
    }
}

struct BookmarkVaultFileDatabase {
    var rootURL: URL?
    var fileManager: FileManager = .default

    func loadBookmarks() -> [BookmarkVaultRecord] {
        do {
            let entries = try fileManager.contentsOfDirectory(
                at: try bookmarksRoot(),
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            return entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .compactMap(loadBookmark)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    func save(_ record: BookmarkVaultRecord) throws {
        let directory = try bookmarkDirectory(record.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: directory.appendingPathComponent("bookmark.json"), options: .atomic)
    }

    func delete(id: String) throws {
        let directory = try bookmarkDirectory(id)
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        try fileManager.removeItem(at: directory)
    }

    func bookmarkFileURL(_ id: String) throws -> URL {
        try bookmarkDirectory(id).appendingPathComponent("bookmark.json")
    }

    func bookmarkDirectory(_ id: String) throws -> URL {
        try bookmarksRoot().appendingPathComponent(id, isDirectory: true)
    }

    func dataRoot() throws -> URL {
        if let rootURL {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            return rootURL
        }
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("GeeAgent/gear-data/bookmark.vault", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func bookmarksRoot() throws -> URL {
        let root = try dataRoot().appendingPathComponent("bookmarks", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func loadBookmark(_ directory: URL) -> BookmarkVaultRecord? {
        let url = directory.appendingPathComponent("bookmark.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BookmarkVaultRecord.self, from: data)
    }
}

struct BookmarkVaultMetadataFetcher: Sendable {
    var runner: GearCommandRunning

    func metadata(for urlString: String) async -> BookmarkVaultMetadata {
        if Self.isTwitterStatusURL(urlString),
           let metadata = await fetchTwitterOEmbed(urlString: urlString)
        {
            return metadata
        }
        if let metadata = await sniffWithYTDLP(urlString: urlString) {
            return metadata
        }
        if let metadata = await fetchBasicMetadata(urlString: urlString) {
            return metadata
        }
        return BookmarkVaultMetadata(url: urlString, source: "empty")
    }

    private func sniffWithYTDLP(urlString: String) async -> BookmarkVaultMetadata? {
        let result = await runner.run(
            "yt-dlp",
            arguments: [
                "--dump-single-json",
                "--no-warnings",
                "--skip-download",
                urlString
            ],
            timeoutSeconds: 45
        )
        guard result.exitCode == 0,
              let metadata = try? BookmarkVaultYTDLPMetadataParser.parse(from: result.stdout, fallbackURL: urlString)
        else {
            return nil
        }
        return metadata
    }

    private func fetchTwitterOEmbed(urlString: String) async -> BookmarkVaultMetadata? {
        guard var components = URLComponents(string: "https://publish.twitter.com/oembed") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: urlString),
            URLQueryItem(name: "omit_script", value: "true"),
            URLQueryItem(name: "dnt", value: "true")
        ]
        guard let url = components.url else {
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 14)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }
            let html = object["html"] as? String
            let authorName = (object["author_name"] as? String)?.nilIfBlank
            let stripped = html.map(BookmarkVaultHTMLMetadataParser.stripHTML)?.nilIfBlank
            let description = stripped ?? authorName
            let title = [authorName, stripped].compactMap { $0?.nilIfBlank }.joined(separator: ": ").nilIfBlank
                ?? "Twitter/X bookmark"
            var extras: [String: String] = [:]
            for key in ["author_url", "provider_name", "provider_url", "type", "cache_age"] {
                if let value = object[key] as? String, let clean = value.nilIfBlank {
                    extras[key] = clean
                }
            }
            return BookmarkVaultMetadata(
                pageTitle: title,
                url: (object["url"] as? String)?.nilIfBlank ?? urlString,
                description: description,
                siteName: "Twitter/X",
                canonicalURL: urlString,
                mediaTitle: stripped,
                platform: "Twitter/X",
                uploader: authorName,
                source: "twitter_oembed",
                extras: extras
            )
        } catch {
            return nil
        }
    }

    private func fetchBasicMetadata(urlString: String) async -> BookmarkVaultMetadata? {
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 14)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.3", forHTTPHeaderField: "Accept")
        request.setValue("bytes=0-262143", forHTTPHeaderField: "Range")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                return nil
            }
            let mimeType = response.mimeType?.lowercased() ?? ""
            guard mimeType.isEmpty || mimeType.contains("html") || mimeType.contains("xml") || mimeType.contains("text") else {
                return BookmarkVaultMetadata(url: urlString, source: "basic_fetch")
            }
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            guard !html.isEmpty else {
                return BookmarkVaultMetadata(url: urlString, source: "basic_fetch")
            }
            return BookmarkVaultHTMLMetadataParser.parse(html, fallbackURL: urlString)
        } catch {
            return nil
        }
    }

    private static var userAgent: String {
        "GeeAgentBookmarkVault/0.1 (+https://gee.local)"
    }

    private static func isTwitterStatusURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let host = url.host?.lowercased() else {
            return false
        }
        guard host == "x.com" || host.hasSuffix(".x.com") || host == "twitter.com" || host.hasSuffix(".twitter.com") else {
            return false
        }
        return url.path.range(of: #"/status(?:es)?/[0-9]+"#, options: [.regularExpression, .caseInsensitive]) != nil
            || url.path.range(of: #"/i/status/[0-9]+"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

enum BookmarkVaultYTDLPMetadataParser {
    static func parse(from stdout: String, fallbackURL: String) throws -> BookmarkVaultMetadata {
        let jsonText = try extractJSONObjectText(from: stdout)
        let data = Data(jsonText.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BookmarkVaultMetadataError.invalidMetadata("yt-dlp did not return a JSON object.")
        }

        let title = (object["title"] as? String)?.nilIfBlank
            ?? (object["fulltitle"] as? String)?.nilIfBlank
            ?? URL(string: fallbackURL)?.lastPathComponent.nilIfBlank
        let platform = (object["extractor_key"] as? String)?.nilIfBlank
            ?? (object["extractor"] as? String)?.nilIfBlank
        let uploader = (object["uploader"] as? String)?.nilIfBlank
            ?? (object["channel"] as? String)?.nilIfBlank
            ?? (object["creator"] as? String)?.nilIfBlank
        let webpageURL = (object["webpage_url"] as? String)?.nilIfBlank ?? fallbackURL
        let thumbnailURL = (object["thumbnail"] as? String)?.nilIfBlank
        let description = (object["description"] as? String)?.nilIfBlank
        let duration = doubleValue(object["duration"])
        let ext = (object["ext"] as? String)?.nilIfBlank
        let formats = object["formats"] as? [[String: Any]]
        var extras: [String: String] = [:]
        for key in ["id", "display_id", "upload_date", "availability", "webpage_url_domain"] {
            if let value = object[key] as? String, let clean = value.nilIfBlank {
                extras[key] = clean
            }
        }

        return BookmarkVaultMetadata(
            pageTitle: title,
            url: webpageURL,
            description: description,
            siteName: platform,
            thumbnailURL: thumbnailURL,
            canonicalURL: webpageURL,
            mediaTitle: title,
            platform: platform,
            uploader: uploader,
            durationSeconds: duration,
            extensionHint: ext,
            formatCount: formats?.count,
            source: "yt-dlp",
            extras: extras
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func extractJSONObjectText(from stdout: String) throws -> String {
        guard let start = stdout.firstIndex(of: "{"),
              let end = stdout.lastIndex(of: "}")
        else {
            throw BookmarkVaultMetadataError.invalidMetadata("No JSON payload was found in yt-dlp output.")
        }
        return String(stdout[start...end])
    }
}

enum BookmarkVaultHTMLMetadataParser {
    static func parse(_ html: String, fallbackURL: String) -> BookmarkVaultMetadata {
        let metaTags = tags(named: "meta", in: html).map(attributes)
        let linkTags = tags(named: "link", in: html).map(attributes)

        func meta(_ keys: [String]) -> String? {
            for key in keys.map({ $0.lowercased() }) {
                for tag in metaTags {
                    let name = tag["name"]?.lowercased()
                    let property = tag["property"]?.lowercased()
                    if name == key || property == key {
                        return tag["content"]?.nilIfBlank.map(decodeEntities)
                    }
                }
            }
            return nil
        }

        let canonical = linkTags.first { tag in
            tag["rel"]?.lowercased().split(separator: " ").contains("canonical") == true
        }?["href"]?.nilIfBlank

        let title = meta(["og:title", "twitter:title"])
            ?? titleTag(in: html)
        let description = meta(["og:description", "twitter:description", "description"])
        let siteName = meta(["og:site_name", "application-name"])
        let image = meta(["og:image", "twitter:image"])

        return BookmarkVaultMetadata(
            pageTitle: title,
            url: fallbackURL,
            description: description,
            siteName: siteName,
            thumbnailURL: image,
            canonicalURL: canonical ?? fallbackURL,
            source: "basic_fetch"
        )
    }

    static func stripHTML(_ html: String) -> String {
        let withoutScripts = html
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
        let text = withoutScripts
            .replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</p\s*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decodeEntities(text)
    }

    private static func tags(named name: String, in html: String) -> [String] {
        let pattern = #"(?is)<\#(name)\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: html) else {
                return nil
            }
            return String(html[matchRange])
        }
    }

    private static func attributes(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:.-]+)\s*=\s*(['"])(.*?)\2"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: range) {
            guard match.numberOfRanges > 3,
                  let keyRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 3), in: tag)
            else {
                continue
            }
            result[String(tag[keyRange]).lowercased()] = decodeEntities(String(tag[valueRange]))
        }
        return result
    }

    private static func titleTag(in html: String) -> String? {
        firstCapture(in: html, pattern: #"(?is)<title[^>]*>(.*?)</title>"#)
            .map(stripHTML)?
            .nilIfBlank
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func decodeEntities(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return result
        }
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        for match in regex.matches(in: result, range: range).reversed() {
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result)
            else {
                continue
            }
            let codeText = String(result[valueRange])
            let scalarValue: UInt32?
            if codeText.lowercased().hasPrefix("x") {
                scalarValue = UInt32(String(codeText.dropFirst()), radix: 16)
            } else {
                scalarValue = UInt32(codeText)
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                result.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }
        return result
    }
}

enum BookmarkVaultMetadataError: LocalizedError {
    case invalidMetadata(String)

    var errorDescription: String? {
        switch self {
        case let .invalidMetadata(message):
            message
        }
    }
}

@MainActor
final class BookmarkVaultGearStore: ObservableObject {
    static let shared = BookmarkVaultGearStore()

    @Published var inputText = ""
    @Published private(set) var bookmarks: [BookmarkVaultRecord] = []
    @Published var selectedBookmarkID: BookmarkVaultRecord.ID?
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var isBusy = false

    private let database: BookmarkVaultFileDatabase
    private let fetcher: BookmarkVaultMetadataFetcher

    var selectedBookmark: BookmarkVaultRecord? {
        bookmarks.first { $0.id == selectedBookmarkID } ?? bookmarks.first
    }

    init(
        database: BookmarkVaultFileDatabase = BookmarkVaultFileDatabase(),
        runner: GearCommandRunning = GearShellCommandRunner()
    ) {
        self.database = database
        self.fetcher = BookmarkVaultMetadataFetcher(runner: runner)
        loadBookmarks()
    }

    func loadBookmarks() {
        bookmarks = database.loadBookmarks()
        selectedBookmarkID = selectedBookmarkID ?? bookmarks.first?.id
    }

    func saveCurrentBookmark() {
        let content = inputText
        Task { [weak self] in
            await self?.saveBookmark(content: content)
        }
    }

    func saveAgentBookmark(content: String) async -> [String: Any] {
        guard let record = await saveBookmark(content: content, capabilityID: "bookmark.save") else {
            return [
                "gear_id": BookmarkVaultGearDescriptor.gearID,
                "capability_id": "bookmark.save",
                "status": "failed",
                "error": "empty_content"
            ]
        }
        var payload = record.agentDictionary
        payload["gear_id"] = BookmarkVaultGearDescriptor.gearID
        payload["capability_id"] = "bookmark.save"
        payload["status"] = "saved"
        payload["bookmark_id"] = record.id
        if let path = try? database.bookmarkFileURL(record.id).path {
            payload["bookmark_path"] = path
        }
        return payload
    }

    @discardableResult
    func saveBookmark(content: String, capabilityID: String? = nil) async -> BookmarkVaultRecord? {
        let raw = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            statusMessage = "Enter content to save."
            return nil
        }

        isBusy = true
        statusMessage = "Saving bookmark..."
        defer { isBusy = false }

        let url = BookmarkVaultInputParser.firstURL(in: raw)
        let metadata: BookmarkVaultMetadata?
        if let url {
            metadata = await fetcher.metadata(for: url)
        } else {
            metadata = nil
        }
        let now = Date()
        let record = BookmarkVaultRecord(
            id: "bookmark-\(Self.timestamp())-\(UUID().uuidString.prefix(8))",
            rawContent: raw,
            pageTitle: metadata?.pageTitle,
            url: metadata?.url ?? url,
            createdAt: now,
            updatedAt: now,
            metadataSource: metadata?.source ?? "manual",
            description: metadata?.description,
            siteName: metadata?.siteName,
            thumbnailURL: metadata?.thumbnailURL,
            canonicalURL: metadata?.canonicalURL,
            mediaTitle: metadata?.mediaTitle,
            platform: metadata?.platform,
            uploader: metadata?.uploader,
            durationSeconds: metadata?.durationSeconds,
            extensionHint: metadata?.extensionHint,
            formatCount: metadata?.formatCount,
            extras: metadata?.extras ?? [:]
        )

        do {
            try database.save(record)
            bookmarks.insert(record, at: 0)
            selectedBookmarkID = record.id
            inputText = capabilityID == nil ? "" : inputText
            statusMessage = "Saved \(record.displayTitle)."
            return record
        } catch {
            statusMessage = "Could not save bookmark: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteSelectedBookmark() {
        guard let selectedBookmarkID else {
            return
        }
        do {
            try database.delete(id: selectedBookmarkID)
            bookmarks.removeAll { $0.id == selectedBookmarkID }
            self.selectedBookmarkID = bookmarks.first?.id
            statusMessage = "Bookmark deleted."
        } catch {
            statusMessage = "Could not delete bookmark: \(error.localizedDescription)"
        }
    }

    func revealSelectedBookmark() {
        guard let record = selectedBookmark,
              let url = try? database.bookmarkFileURL(record.id)
        else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openSelectedBookmarkURL() {
        guard let urlString = selectedBookmark?.url,
              let url = URL(string: urlString)
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
