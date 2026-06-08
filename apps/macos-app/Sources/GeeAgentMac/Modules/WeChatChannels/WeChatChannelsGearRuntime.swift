import AppKit
import Foundation
import Security

enum WeChatChannelsGearDescriptor {
    static let gearID = "wechat.channels"
}

struct WeChatChannelsCredential: Codable, Hashable {
    var cookie: String
    var userAgent: String
    var extraHeaders: [String: String]
    var savedAt: Date

    var isConfigured: Bool {
        !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum WeChatChannelsTaskStatus: String, Codable, Hashable {
    case running
    case completed
    case failed
    case degraded

    var title: String {
        switch self {
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .degraded: "Degraded"
        }
    }
}

struct WeChatChannelsParseData: Codable, Hashable {
    var exportID: String?
    var playableURL: String?
    var coverURL: String?
    var author: String?
    var authorIconURL: String?
    var description: String?

    enum CodingKeys: String, CodingKey {
        case exportID = "export_id"
        case playableURL = "playable_url"
        case coverURL = "cover_url"
        case author
        case authorIconURL = "author_icon_url"
        case description
    }
}

struct WeChatChannelsVideoProfile: Codable, Hashable {
    var sourceURL: String
    var shortID: String?
    var exportID: String?
    var generalToken: String?
    var resolutionPath: String? = nil
    var author: String?
    var authorAvatarURL: String?
    var description: String?
    var coverURL: String?
    var createdAt: Int?
    var videoURL: String?
    var h264VideoURL: String?
    var h265VideoURL: String?
    var originVideoURL: String?
    var likeCountText: String?
    var forwardCountText: String?
    var commentCountText: String?

    enum CodingKeys: String, CodingKey {
        case sourceURL = "source_url"
        case shortID = "short_id"
        case exportID = "export_id"
        case generalToken = "general_token"
        case resolutionPath = "resolution_path"
        case author
        case authorAvatarURL = "author_avatar_url"
        case description
        case coverURL = "cover_url"
        case createdAt = "created_at"
        case videoURL = "video_url"
        case h264VideoURL = "h264_video_url"
        case h265VideoURL = "h265_video_url"
        case originVideoURL = "origin_video_url"
        case likeCountText = "like_count_text"
        case forwardCountText = "forward_count_text"
        case commentCountText = "comment_count_text"
    }

    var bestVideoURL: String? {
        h265VideoURL?.nilIfBlank
            ?? h264VideoURL?.nilIfBlank
            ?? videoURL?.nilIfBlank
            ?? originVideoURL?.nilIfBlank
    }

    var title: String {
        let cleanDescription = description?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanDescription, !cleanDescription.isEmpty {
            return String(cleanDescription.prefix(80))
        }
        if let author = author?.nilIfBlank {
            return "\(author) WeChat Channels video"
        }
        return "WeChat Channels video"
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "source_url": sourceURL,
            "title": title,
            "has_video_url": bestVideoURL != nil
        ]
        if let shortID = shortID?.nilIfBlank { payload["short_id"] = shortID }
        if let exportID = exportID?.nilIfBlank { payload["export_id"] = exportID }
        if let author = author?.nilIfBlank { payload["author"] = author }
        if let resolutionPath = resolutionPath?.nilIfBlank { payload["resolution_path"] = resolutionPath }
        if let authorAvatarURL = authorAvatarURL?.nilIfBlank { payload["author_avatar_url"] = authorAvatarURL }
        if let description = description?.nilIfBlank { payload["description"] = description }
        if let coverURL = coverURL?.nilIfBlank { payload["cover_url"] = coverURL }
        if let createdAt { payload["created_at"] = createdAt }
        if let videoURL = videoURL?.nilIfBlank { payload["video_url"] = videoURL }
        if let h264VideoURL = h264VideoURL?.nilIfBlank { payload["h264_video_url"] = h264VideoURL }
        if let h265VideoURL = h265VideoURL?.nilIfBlank { payload["h265_video_url"] = h265VideoURL }
        if let originVideoURL = originVideoURL?.nilIfBlank { payload["origin_video_url"] = originVideoURL }
        if let bestVideoURL { payload["best_video_url"] = bestVideoURL }
        if let likeCountText = likeCountText?.nilIfBlank { payload["like_count_text"] = likeCountText }
        if let forwardCountText = forwardCountText?.nilIfBlank { payload["forward_count_text"] = forwardCountText }
        if let commentCountText = commentCountText?.nilIfBlank { payload["comment_count_text"] = commentCountText }
        return payload
    }
}

struct WeChatChannelsDownloadedFile: Codable, Hashable {
    var path: String
    var byteCount: Int64
    var mimeType: String?

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "path": path,
            "byte_count": byteCount
        ]
        if let mimeType = mimeType?.nilIfBlank { payload["mime_type"] = mimeType }
        return payload
    }
}

struct WeChatChannelsTaskRecord: Codable, Identifiable, Hashable {
    var id: String
    var sourceURL: String
    var status: WeChatChannelsTaskStatus
    var title: String
    var author: String?
    var profile: WeChatChannelsVideoProfile?
    var outputDirectoryPath: String
    var outputPath: String?
    var outputByteCount: Int64?
    var errorCode: String?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sourceURL = "source_url"
        case status
        case title
        case author
        case profile
        case outputDirectoryPath = "output_directory_path"
        case outputPath = "output_path"
        case outputByteCount = "output_byte_count"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "source_url": sourceURL,
            "status": status.rawValue,
            "title": title,
            "output_directory_path": outputDirectoryPath,
            "created_at": WeChatChannelsDateCodec.string(from: createdAt),
            "updated_at": WeChatChannelsDateCodec.string(from: updatedAt)
        ]
        if let author = author?.nilIfBlank { payload["author"] = author }
        if let profile { payload["profile"] = profile.agentDictionary }
        if let outputPath = outputPath?.nilIfBlank { payload["output_path"] = outputPath }
        if let outputByteCount { payload["output_byte_count"] = outputByteCount }
        if let errorCode = errorCode?.nilIfBlank { payload["error_code"] = errorCode }
        if let errorMessage = errorMessage?.nilIfBlank { payload["error"] = errorMessage }
        return payload
    }
}

enum WeChatChannelsDateCodec {
    static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func localDisplay(from date: Date?) -> String {
        guard let date else {
            return "Never"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

enum WeChatChannelsError: LocalizedError {
    case invalidURL(String)
    case authMissing
    case invalidArguments(String)
    case networkFailed(String)
    case apiRejected(String)
    case noVideoURL
    case downloadFailed(String)
    case storageFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(message):
            message
        case .authMissing:
            "WeChat Channels needs a configured Tencent Yuanbao web session before it can resolve this URL into a downloadable video feed."
        case let .invalidArguments(message):
            message
        case let .networkFailed(message):
            message
        case let .apiRejected(message):
            message
        case .noVideoURL:
            "The WeChat Channels profile was resolved, but Tencent did not return a downloadable video URL."
        case let .downloadFailed(message):
            message
        case let .storageFailed(message):
            message
        }
    }

    var code: String {
        switch self {
        case .invalidURL: "invalid_url"
        case .authMissing: "auth_missing"
        case .invalidArguments: "invalid_arguments"
        case .networkFailed: "network_failed"
        case .apiRejected: "wechat_channels_api_rejected"
        case .noVideoURL: "no_video_url"
        case .downloadFailed: "download_failed"
        case .storageFailed: "storage_failed"
        }
    }

    var recovery: String {
        switch self {
        case .authMissing:
            "Open WeChat Channels Downloader in GeeAgent, save a current yuanbao.tencent.com web Cookie and User-Agent, then retry the same URL."
        case .noVideoURL:
            "The official shortUri feed returned metadata but no downloadable video URL. Save a current Yuanbao web session in the Gear if you need GeeAgent to resolve the downloadable feed URL. Do not use third-party parser sites as a fallback."
        case .apiRejected:
            "Refresh the Yuanbao web session in the Gear settings. If Yuanbao changed request headers, paste the current browser headers into the Gear and retry."
        default:
            "Inspect the structured error and retry the same Gear capability after correcting the reported input, session, or network issue."
        }
    }
}

protocol WeChatChannelsCredentialStoring {
    func loadCredential() throws -> WeChatChannelsCredential?
    func saveCredential(_ credential: WeChatChannelsCredential) throws
    func deleteCredential() throws
}

struct WeChatChannelsKeychainCredentialStore: WeChatChannelsCredentialStoring {
    var service = "com.geeagent.gear.wechat.channels"
    var account = "yuanbao-web-session"

    func loadCredential() throws -> WeChatChannelsCredential? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data
        else {
            throw WeChatChannelsError.storageFailed("Could not read the WeChat Channels session from Keychain.")
        }
        return try JSONDecoder().decode(WeChatChannelsCredential.self, from: data)
    }

    func saveCredential(_ credential: WeChatChannelsCredential) throws {
        let data = try JSONEncoder().encode(credential)
        var query = baseQuery()
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw WeChatChannelsError.storageFailed("Could not save the WeChat Channels session to Keychain.")
            }
            return
        }
        guard status == errSecSuccess else {
            throw WeChatChannelsError.storageFailed("Could not inspect the WeChat Channels Keychain session.")
        }
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw WeChatChannelsError.storageFailed("Could not update the WeChat Channels session in Keychain.")
        }
    }

    func deleteCredential() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WeChatChannelsError.storageFailed("Could not delete the WeChat Channels Keychain session.")
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct WeChatChannelsMemoryCredentialStore: WeChatChannelsCredentialStoring {
    final class Box {
        var credential: WeChatChannelsCredential?
    }

    var box = Box()

    func loadCredential() throws -> WeChatChannelsCredential? {
        box.credential
    }

    func saveCredential(_ credential: WeChatChannelsCredential) throws {
        box.credential = credential
    }

    func deleteCredential() throws {
        box.credential = nil
    }
}

struct WeChatChannelsFileDatabase {
    var rootURL: URL?
    var fileManager: FileManager = .default

    var stateURL: URL {
        (try? dataRoot())?.appendingPathComponent("tasks")
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("wechat-channels")
    }

    func loadTasks() -> [WeChatChannelsTaskRecord] {
        do {
            let entries = try fileManager.contentsOfDirectory(
                at: try tasksRoot(),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .compactMap { directory in
                    let url = directory.appendingPathComponent("task.json")
                    guard let data = try? Data(contentsOf: url) else {
                        return nil
                    }
                    return try? decoder.decode(WeChatChannelsTaskRecord.self, from: data)
                }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    func save(_ task: WeChatChannelsTaskRecord) throws {
        let directory = try taskDirectory(task.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(task).write(to: directory.appendingPathComponent("task.json"), options: .atomic)
    }

    func taskDirectory(_ id: String) throws -> URL {
        try tasksRoot().appendingPathComponent(id, isDirectory: true)
    }

    func outputDirectory(_ id: String) throws -> URL {
        let directory = try taskDirectory(id).appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
        .appendingPathComponent("GeeAgent/gear-data/wechat.channels", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func tasksRoot() throws -> URL {
        let root = try dataRoot().appendingPathComponent("tasks", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

@MainActor
protocol WeChatChannelsAPIClient {
    func fetchProfile(
        sourceURL: String,
        credential: WeChatChannelsCredential?
    ) async throws -> WeChatChannelsVideoProfile
}

struct WeChatChannelsURLSessionAPIClient: WeChatChannelsAPIClient {
    var session: URLSession = .shared

    func fetchProfile(
        sourceURL: String,
        credential: WeChatChannelsCredential?
    ) async throws -> WeChatChannelsVideoProfile {
        let normalized = try WeChatChannelsURLNormalizer.normalizedSourceURL(sourceURL)
        if let tokenAndExportID = WeChatChannelsURLNormalizer.feedTokenAndExportID(from: normalized.sourceURL) {
            return try await fetchFeedProfile(
                sourceURL: normalized.sourceURL,
                shortID: normalized.shortID,
                exportID: tokenAndExportID.exportID,
                generalToken: tokenAndExportID.generalToken,
                resolutionPath: "feed_export_id"
            )
        }

        if let shortID = normalized.shortID {
            let shortURIProfile = try await fetchShortURIProfile(
                sourceURL: normalized.sourceURL,
                shortID: shortID
            )
            if shortURIProfile.bestVideoURL != nil {
                return shortURIProfile
            }
            guard let credential, credential.isConfigured else {
                return shortURIProfile
            }
        }

        guard let credential, credential.isConfigured else {
            throw WeChatChannelsError.authMissing
        }
        let parseData = try await parseShareURL(normalized.sourceURL, credential: credential)
        let tokenAndExportID = try Self.tokenAndExportID(from: parseData)
        var profile = try await fetchFeedProfile(
            sourceURL: normalized.sourceURL,
            shortID: normalized.shortID,
            exportID: tokenAndExportID.exportID,
            generalToken: tokenAndExportID.generalToken,
            resolutionPath: "yuanbao_feed"
        )
        if profile.author == nil {
            profile.author = parseData.author
        }
        if profile.description == nil {
            profile.description = parseData.description
        }
        if profile.coverURL == nil {
            profile.coverURL = parseData.coverURL
        }
        if profile.authorAvatarURL == nil {
            profile.authorAvatarURL = parseData.authorIconURL
        }
        return profile
    }

    private func parseShareURL(
        _ shareURL: String,
        credential: WeChatChannelsCredential
    ) async throws -> WeChatChannelsParseData {
        guard let url = URL(string: "https://yuanbao.tencent.com/api/weixin/get_parse_result") else {
            throw WeChatChannelsError.invalidURL("Could not construct the Yuanbao parse URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "video_channel_url",
            "url": shareURL,
            "scene": 1
        ])
        applyYuanbaoHeaders(to: &request, credential: credential)

        let object = try await requestJSON(request)
        try Self.throwIfYuanbaoRejected(object)
        guard let data = object["data"] as? [String: Any] else {
            throw WeChatChannelsError.apiRejected("Yuanbao did not return parse data for the WeChat Channels URL.")
        }
        return WeChatChannelsParseData(
            exportID: Self.stringValue(data["wx_export_id"]) ?? Self.stringValue(data["export_id"]),
            playableURL: Self.stringValue(data["playable_url"]) ?? Self.stringValue(data["playableUrl"]),
            coverURL: Self.stringValue(data["cover_url"]) ?? Self.stringValue(data["coverUrl"]),
            author: Self.stringValue(data["author"]),
            authorIconURL: Self.stringValue(data["author_icon"]) ?? Self.stringValue(data["author_icon_url"]),
            description: Self.stringValue(data["desc"]) ?? Self.stringValue(data["description"])
        )
    }

    private func fetchFeedProfile(
        sourceURL: String,
        shortID: String?,
        exportID: String,
        generalToken: String?,
        resolutionPath: String
    ) async throws -> WeChatChannelsVideoProfile {
        let body: [String: Any] = [
            "baseReq": ["generalToken": generalToken ?? ""],
            "exportId": exportID
        ]
        let referer = "https://channels.weixin.qq.com/finder-preview/pages/feed?entry_card_type=48&comment_scene=39&appid=0&token=\(Self.percentEncode(generalToken ?? ""))&entry_scene=0&eid=\(Self.percentEncode(exportID))"
        let object = try await fetchFeedInfoObject(body: body, referer: referer)
        try Self.throwIfChannelsRejected(object)
        return try Self.parseFeedProfile(
            object,
            sourceURL: sourceURL,
            shortID: shortID,
            exportID: exportID,
            generalToken: generalToken,
            resolutionPath: resolutionPath
        )
    }

    private func fetchShortURIProfile(
        sourceURL: String,
        shortID: String
    ) async throws -> WeChatChannelsVideoProfile {
        let body: [String: Any] = [
            "baseReq": ["generalToken": ""],
            "shortUri": shortID
        ]
        let referer = "https://channels.weixin.qq.com/finder-preview/pages/sph?id=\(Self.percentEncode(shortID))"
        let object = try await fetchFeedInfoObject(body: body, referer: referer)
        try Self.throwIfChannelsRejected(object)
        return try Self.parseFeedProfile(
            object,
            sourceURL: sourceURL,
            shortID: shortID,
            exportID: nil,
            generalToken: nil,
            resolutionPath: "short_uri"
        )
    }

    private func fetchFeedInfoObject(
        body: [String: Any],
        referer: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: "https://channels.weixin.qq.com/finder-preview/api/feed/get_feed_info?_rid=\(Self.requestID())&_pageUrl=https:%2F%2Fchannels.weixin.qq.com%2Ffinder-preview%2Fpages%2Ffeed") else {
            throw WeChatChannelsError.invalidURL("Could not construct the WeChat Channels feed URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://channels.weixin.qq.com", forHTTPHeaderField: "Origin")
        request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        return try await requestJSON(request)
    }

    private func requestJSON(_ request: URLRequest) async throws -> [String: Any] {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                throw WeChatChannelsError.networkFailed("Tencent returned HTTP \(http.statusCode).")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WeChatChannelsError.networkFailed("Tencent did not return a JSON object.")
            }
            return object
        } catch let error as WeChatChannelsError {
            throw error
        } catch {
            throw WeChatChannelsError.networkFailed(error.localizedDescription)
        }
    }

    private func applyYuanbaoHeaders(
        to request: inout URLRequest,
        credential: WeChatChannelsCredential
    ) {
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://yuanbao.tencent.com", forHTTPHeaderField: "Origin")
        request.setValue("https://yuanbao.tencent.com/", forHTTPHeaderField: "Referer")
        request.setValue(credential.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("web", forHTTPHeaderField: "x-source")
        request.setValue("mac", forHTTPHeaderField: "x-platform")
        request.setValue("zh-CN", forHTTPHeaderField: "x-language")
        request.setValue(credential.cookie, forHTTPHeaderField: "Cookie")
        for (key, value) in credential.extraHeaders where !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    static func parseFeedProfile(
        _ object: [String: Any],
        sourceURL: String,
        shortID: String?,
        exportID: String?,
        generalToken: String?,
        resolutionPath: String? = nil
    ) throws -> WeChatChannelsVideoProfile {
        let data = objectValue(object["data"]) ?? object
        let authorInfo = objectValue(data["authorInfo"]) ?? objectValue(data["author_info"]) ?? [:]
        let feedInfo = objectValue(data["feedInfo"]) ?? objectValue(data["feed_info"]) ?? data
        let h264 = objectValue(feedInfo["h264VideoInfo"]) ?? objectValue(feedInfo["h264_video_info"]) ?? [:]
        let h265 = objectValue(feedInfo["h265VideoInfo"]) ?? objectValue(feedInfo["h265_video_info"]) ?? [:]
        let sceneInfo = objectValue(data["sceneInfo"]) ?? objectValue(data["scene_info"]) ?? [:]

        return WeChatChannelsVideoProfile(
            sourceURL: sourceURL,
            shortID: shortID,
            exportID: exportID
                ?? stringValue(sceneInfo["dynamicExportId"])
                ?? stringValue(sceneInfo["dynamic_export_id"])
                ?? stringValue(sceneInfo["exportId"])
                ?? stringValue(sceneInfo["export_id"]),
            generalToken: generalToken,
            resolutionPath: resolutionPath,
            author: stringValue(authorInfo["nickname"]) ?? stringValue(authorInfo["author"]),
            authorAvatarURL: stringValue(authorInfo["headImgUrl"]) ?? stringValue(authorInfo["head_img_url"]),
            description: stringValue(feedInfo["description"]) ?? stringValue(feedInfo["desc"]),
            coverURL: stringValue(feedInfo["coverUrl"]) ?? stringValue(feedInfo["cover_url"]),
            createdAt: intValue(feedInfo["createtime"]) ?? intValue(feedInfo["createTime"]),
            videoURL: stringValue(feedInfo["videoUrl"]) ?? stringValue(feedInfo["video_url"]),
            h264VideoURL: stringValue(h264["videoUrl"]) ?? stringValue(h264["video_url"]),
            h265VideoURL: stringValue(h265["videoUrl"]) ?? stringValue(h265["video_url"]),
            originVideoURL: stringValue(feedInfo["originVideoUrl"]) ?? stringValue(feedInfo["origin_video_url"]),
            likeCountText: stringValue(feedInfo["likeCountFmt"]) ?? stringValue(feedInfo["like_count_fmt"]),
            forwardCountText: stringValue(feedInfo["forwardCountFmt"]) ?? stringValue(feedInfo["forward_count_fmt"]),
            commentCountText: stringValue(feedInfo["commentCountFmt"]) ?? stringValue(feedInfo["comment_count_fmt"])
        )
    }

    static func throwIfYuanbaoRejected(_ object: [String: Any]) throws {
        if let code = intValue(object["code"]), code != 0 {
            let message = stringValue(object["msg"]) ?? stringValue(object["message"]) ?? "Yuanbao rejected the parse request with code \(code)."
            throw WeChatChannelsError.apiRejected(message)
        }
        if let error = stringValue(object["error"])?.nilIfBlank {
            throw WeChatChannelsError.apiRejected(error)
        }
    }

    static func throwIfChannelsRejected(_ object: [String: Any]) throws {
        let code = intValue(object["errCode"]) ?? intValue(object["errcode"]) ?? 0
        if code != 0 {
            let message = stringValue(object["errMsg"]) ?? stringValue(object["errmsg"]) ?? "WeChat Channels rejected the feed request with code \(code)."
            throw WeChatChannelsError.apiRejected(message)
        }
    }

    static func tokenAndExportID(from parseData: WeChatChannelsParseData) throws -> (generalToken: String?, exportID: String) {
        let playableURL = parseData.playableURL ?? ""
        if let parsed = URL(string: playableURL),
           let components = URLComponents(url: parsed, resolvingAgainstBaseURL: false) {
            let token = components.queryItems?.first(where: { $0.name == "token" })?.value
            let eid = components.queryItems?.first(where: { $0.name == "eid" })?.value
            if let eid = eid?.nilIfBlank {
                return (token, eid)
            }
        }
        if let exportID = parseData.exportID?.nilIfBlank {
            throw WeChatChannelsError.apiRejected("Yuanbao returned export id `\(exportID)` but no feed token.")
        }
        throw WeChatChannelsError.apiRejected("Yuanbao did not return a playable feed URL.")
    }

    private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"

    private static func requestID() -> String {
        let timestampHex = String(Int(Date().timeIntervalSince1970), radix: 16)
        let random = (0..<8).map { _ in String("0123456789abcdef".randomElement() ?? "0") }.joined()
        return "\(timestampHex)-\(random)"
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static func objectValue(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] {
            return object
        }
        if let text = value as? String,
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }
}

enum WeChatChannelsURLNormalizer {
    static func normalizedSourceURL(_ raw: String) throws -> (sourceURL: String, shortID: String?) {
        let trimmed = trimURL(raw)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased()
        else {
            throw WeChatChannelsError.invalidURL("Enter a valid WeChat Channels share URL.")
        }

        if host == "weixin.qq.com" || host.hasSuffix(".weixin.qq.com") {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2, parts[0] == "sph" {
                let id = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else {
                    throw WeChatChannelsError.invalidURL("The WeChat Channels share URL is missing its short id.")
                }
                return ("https://weixin.qq.com/sph/\(id)", id)
            }
        }

        if host == "channels.weixin.qq.com" || host.hasSuffix(".channels.weixin.qq.com") {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if url.path.contains("/finder-preview/pages/sph"),
               let id = components?.queryItems?.first(where: { $0.name == "id" })?.value?.nilIfBlank {
                return ("https://weixin.qq.com/sph/\(id)", id)
            }
            if feedTokenAndExportID(from: trimmed) != nil {
                return (trimmed, nil)
            }
        }

        throw WeChatChannelsError.invalidURL("Only weixin.qq.com/sph and channels.weixin.qq.com finder-preview URLs are supported.")
    }

    static func feedTokenAndExportID(from raw: String) -> (generalToken: String?, exportID: String)? {
        guard let url = URL(string: raw),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        let token = components.queryItems?.first(where: { $0.name == "token" })?.value?.nilIfBlank
        let exportID = components.queryItems?.first(where: { $0.name == "eid" || $0.name == "export_id" })?.value?.nilIfBlank
        guard let exportID else {
            return nil
        }
        return (token, exportID)
    }

    private static func trimURL(_ raw: String) -> String {
        let trailing = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\u{3002}\u{3002}\u{FF0C}\u{FF0C}\u{3001}\u{FF1B};\u{FF1A}:\u{FF01}!\u{FF1F}?)\u{FF09}]\u{3011}>\"'"))
        return raw.trimmingCharacters(in: trailing)
    }
}

@MainActor
protocol WeChatChannelsMediaDownloading {
    func download(
        from url: URL,
        outputDirectory: URL,
        suggestedTitle: String,
        userAgent: String
    ) async throws -> WeChatChannelsDownloadedFile
}

struct WeChatChannelsURLSessionDownloader: WeChatChannelsMediaDownloading {
    var session: URLSession = .shared
    var fileManager: FileManager = .default

    func download(
        from url: URL,
        outputDirectory: URL,
        suggestedTitle: String,
        userAgent: String
    ) async throws -> WeChatChannelsDownloadedFile {
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://channels.weixin.qq.com/", forHTTPHeaderField: "Referer")

        do {
            let (temporaryURL, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode)
            else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw WeChatChannelsError.downloadFailed("Video download returned HTTP \(status).")
            }
            let extensionHint = Self.extensionHint(response: response, url: url)
            let filename = "\(Self.safeFilename(suggestedTitle)).\(extensionHint)"
            let destination = outputDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            let byteCount = (try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
            return WeChatChannelsDownloadedFile(
                path: destination.path,
                byteCount: byteCount,
                mimeType: response.mimeType
            )
        } catch let error as WeChatChannelsError {
            throw error
        } catch {
            throw WeChatChannelsError.downloadFailed(error.localizedDescription)
        }
    }

    private static func extensionHint(response: URLResponse, url: URL) -> String {
        if let pathExtension = url.pathExtension.nilIfBlank {
            return pathExtension
        }
        switch response.mimeType {
        case "video/mp4":
            return "mp4"
        case "video/quicktime":
            return "mov"
        default:
            return "mp4"
        }
    }

    static func safeFilename(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "[\\\\/:*?\"<>|\\n\\r\\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.nilIfBlank ?? "wechat-channels-video").prefix(80))
    }
}

@MainActor
final class WeChatChannelsGearStore: ObservableObject {
    static let shared = WeChatChannelsGearStore()

    @Published var urlString = ""
    @Published var cookieDraft = ""
    @Published var userAgentDraft = WeChatChannelsGearStore.defaultUserAgent
    @Published var extraHeadersJSONDraft = "{}"
    @Published private(set) var sessionConfigured = false
    @Published private(set) var tasks: [WeChatChannelsTaskRecord] = []
    @Published private(set) var profile: WeChatChannelsVideoProfile?
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage = "Ready"
    @Published var selectedTaskID: String?

    private let database: WeChatChannelsFileDatabase
    private let credentialStore: any WeChatChannelsCredentialStoring
    private let client: any WeChatChannelsAPIClient
    private let downloader: any WeChatChannelsMediaDownloading

    init(
        database: WeChatChannelsFileDatabase = WeChatChannelsFileDatabase(),
        credentialStore: any WeChatChannelsCredentialStoring = WeChatChannelsKeychainCredentialStore(),
        client: any WeChatChannelsAPIClient = WeChatChannelsURLSessionAPIClient(),
        downloader: any WeChatChannelsMediaDownloading = WeChatChannelsURLSessionDownloader()
    ) {
        self.database = database
        self.credentialStore = credentialStore
        self.client = client
        self.downloader = downloader
        load()
    }

    var selectedTask: WeChatChannelsTaskRecord? {
        tasks.first { $0.id == selectedTaskID } ?? tasks.first
    }

    func load() {
        tasks = database.loadTasks()
        selectedTaskID = selectedTaskID ?? tasks.first?.id
        do {
            sessionConfigured = try credentialStore.loadCredential()?.isConfigured == true
        } catch {
            sessionConfigured = false
        }
    }

    func saveSessionFromDrafts() {
        do {
            let headers = try Self.parseExtraHeaders(extraHeadersJSONDraft)
            try saveSession(cookie: cookieDraft, userAgent: userAgentDraft, extraHeaders: headers)
            cookieDraft = ""
            statusMessage = "Yuanbao session saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearSession() {
        do {
            try credentialStore.deleteCredential()
            sessionConfigured = false
            statusMessage = "Yuanbao session cleared."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveSession(cookie: String, userAgent: String, extraHeaders: [String: String] = [:]) throws {
        let credential = WeChatChannelsCredential(
            cookie: cookie.trimmingCharacters(in: .whitespacesAndNewlines),
            userAgent: userAgent.trimmingCharacters(in: .whitespacesAndNewlines),
            extraHeaders: extraHeaders,
            savedAt: Date()
        )
        guard credential.isConfigured else {
            throw WeChatChannelsError.invalidArguments("Cookie and User-Agent are required.")
        }
        try credentialStore.saveCredential(credential)
        sessionConfigured = true
    }

    func saveAuthorizedBrowserSession(cookie: String, userAgent: String) {
        do {
            try saveSession(cookie: cookie, userAgent: userAgent, extraHeaders: [:])
            cookieDraft = ""
            extraHeadersJSONDraft = "{}"
            statusMessage = "Yuanbao browser session saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func fetchCurrentMetadata() {
        Task {
            _ = await metadataPayload(args: ["url": urlString])
        }
    }

    func downloadCurrentVideo() {
        Task {
            _ = await downloadPayload(args: ["url": urlString])
        }
    }

    func revealSelectedTask() {
        guard let selectedTask else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: selectedTask.outputPath ?? selectedTask.outputDirectoryPath)
        ])
    }

    func runAgentAction(capabilityID: String, args: [String: Any]) async -> [String: Any] {
        switch capabilityID {
        case "wechat_channels.auth_status":
            return authStatusPayload()
        case "wechat_channels.metadata":
            return await metadataPayload(args: args)
        case "wechat_channels.download":
            return await downloadPayload(args: args)
        case "wechat_channels.get_task":
            return getTaskPayload(taskID: stringArg(args, "task_id", "id"))
        case "wechat_channels.list_tasks":
            return listTasksPayload(limit: intArg(args, "limit") ?? 50)
        default:
            return failurePayload(
                capabilityID: capabilityID,
                error: WeChatChannelsError.invalidArguments("wechat.channels does not support `\(capabilityID)`.")
            )
        }
    }

    private func authStatusPayload() -> [String: Any] {
        load()
        return [
            "gear_id": WeChatChannelsGearDescriptor.gearID,
            "capability_id": "wechat_channels.auth_status",
            "status": "success",
            "fallback_attempted": false,
            "session_configured": sessionConfigured,
            "credential_store": "keychain",
            "task_count": tasks.count,
            "data_path": database.stateURL.path
        ]
    }

    private func metadataPayload(args: [String: Any]) async -> [String: Any] {
        isBusy = true
        statusMessage = "Resolving WeChat Channels metadata..."
        defer { isBusy = false }

        do {
            let sourceURL = try requiredString(args, "url", aliases: ["share_url", "sph_url"])
            let fetched = try await client.fetchProfile(
                sourceURL: sourceURL,
                credential: try credentialStore.loadCredential()
            )
            profile = fetched
            statusMessage = fetched.bestVideoURL == nil
                ? "Resolved metadata without a downloadable video URL."
                : "Resolved metadata and video URL."
            var payload: [String: Any] = [
                "gear_id": WeChatChannelsGearDescriptor.gearID,
                "capability_id": "wechat_channels.metadata",
                "status": fetched.bestVideoURL == nil ? "degraded" : "success",
                "fallback_attempted": false,
                "profile": fetched.agentDictionary
            ]
            if fetched.bestVideoURL == nil {
                payload["code"] = WeChatChannelsError.noVideoURL.code
                payload["recovery"] = WeChatChannelsError.noVideoURL.recovery
            }
            return payload
        } catch {
            statusMessage = error.localizedDescription
            return failurePayload(capabilityID: "wechat_channels.metadata", error: error)
        }
    }

    private func downloadPayload(args: [String: Any]) async -> [String: Any] {
        isBusy = true
        statusMessage = "Downloading WeChat Channels video..."
        defer { isBusy = false }

        do {
            let sourceURL = try requiredString(args, "url", aliases: ["share_url", "sph_url"])
            let outputDirectoryOverride = stringArg(args, "output_dir", "output_directory")
            let startedAt = Date()
            let taskID = "wechat-channels-\(Self.timestamp())-\(UUID().uuidString.prefix(8))"
            let outputDirectory = try resolvedOutputDirectory(taskID: taskID, override: outputDirectoryOverride)
            var task = WeChatChannelsTaskRecord(
                id: taskID,
                sourceURL: sourceURL,
                status: .running,
                title: "WeChat Channels video",
                author: nil,
                profile: nil,
                outputDirectoryPath: outputDirectory.path,
                outputPath: nil,
                outputByteCount: nil,
                errorCode: nil,
                errorMessage: nil,
                createdAt: startedAt,
                updatedAt: startedAt
            )
            tasks.insert(task, at: 0)
            selectedTaskID = task.id
            try persist(task)

            do {
                let fetched = try await client.fetchProfile(
                    sourceURL: sourceURL,
                    credential: try credentialStore.loadCredential()
                )
                profile = fetched
                task.title = fetched.title
                task.author = fetched.author
                task.profile = fetched
                guard let videoURLString = fetched.bestVideoURL,
                      let videoURL = URL(string: videoURLString)
                else {
                    throw WeChatChannelsError.noVideoURL
                }

                let credential = try credentialStore.loadCredential()
                let downloaded = try await downloader.download(
                    from: videoURL,
                    outputDirectory: outputDirectory,
                    suggestedTitle: fetched.title,
                    userAgent: credential?.userAgent ?? Self.defaultUserAgent
                )
                task.status = .completed
                task.outputPath = downloaded.path
                task.outputByteCount = downloaded.byteCount
                task.updatedAt = Date()
                updateTask(task)
                try persist(task)
                statusMessage = "Downloaded WeChat Channels video."
                return [
                    "gear_id": WeChatChannelsGearDescriptor.gearID,
                    "capability_id": "wechat_channels.download",
                    "status": "completed",
                    "fallback_attempted": false,
                    "task": task.agentDictionary,
                    "profile": fetched.agentDictionary,
                    "output_paths": [downloaded.path],
                    "download": downloaded.agentDictionary
                ]
            } catch {
                let channelsError = error as? WeChatChannelsError
                task.status = channelsError?.code == WeChatChannelsError.noVideoURL.code ? .degraded : .failed
                task.errorCode = channelsError?.code ?? "action_failed"
                task.errorMessage = error.localizedDescription
                task.updatedAt = Date()
                updateTask(task)
                try persist(task)
                statusMessage = error.localizedDescription
                return failurePayload(
                    capabilityID: "wechat_channels.download",
                    error: error,
                    task: task,
                    status: task.status == .degraded ? "degraded" : "failed"
                )
            }
        } catch {
            statusMessage = error.localizedDescription
            return failurePayload(capabilityID: "wechat_channels.download", error: error)
        }
    }

    private func getTaskPayload(taskID: String?) -> [String: Any] {
        load()
        guard let taskID = taskID?.nilIfBlank else {
            return failurePayload(
                capabilityID: "wechat_channels.get_task",
                error: WeChatChannelsError.invalidArguments("`task_id` is required.")
            )
        }
        guard let task = tasks.first(where: { $0.id == taskID }) else {
            return failurePayload(
                capabilityID: "wechat_channels.get_task",
                error: WeChatChannelsError.invalidArguments("No WeChat Channels task matched `\(taskID)`.")
            )
        }
        return [
            "gear_id": WeChatChannelsGearDescriptor.gearID,
            "capability_id": "wechat_channels.get_task",
            "status": "success",
            "fallback_attempted": false,
            "task": task.agentDictionary
        ]
    }

    private func listTasksPayload(limit: Int) -> [String: Any] {
        load()
        let clamped = Self.clamp(limit, min: 1, max: 200)
        let listed = Array(tasks.prefix(clamped))
        return [
            "gear_id": WeChatChannelsGearDescriptor.gearID,
            "capability_id": "wechat_channels.list_tasks",
            "status": "success",
            "fallback_attempted": false,
            "task_count": listed.count,
            "tasks": listed.map(\.agentDictionary),
            "data_path": database.stateURL.path
        ]
    }

    private func failurePayload(
        capabilityID: String,
        error: Error,
        task: WeChatChannelsTaskRecord? = nil,
        status: String = "failed"
    ) -> [String: Any] {
        let channelsError = error as? WeChatChannelsError
        var payload: [String: Any] = [
            "gear_id": WeChatChannelsGearDescriptor.gearID,
            "capability_id": capabilityID,
            "status": status,
            "fallback_attempted": false,
            "code": channelsError?.code ?? "action_failed",
            "error": error.localizedDescription,
            "recovery": channelsError?.recovery ?? "Inspect the structured error and retry the same Gear capability after correcting the issue."
        ]
        if let task {
            payload["task"] = task.agentDictionary
            if let profile = task.profile {
                payload["profile"] = profile.agentDictionary
            }
        }
        return payload
    }

    private func resolvedOutputDirectory(taskID: String, override: String?) throws -> URL {
        if let override = override?.nilIfBlank {
            let expanded = (override as NSString).expandingTildeInPath
            let directory = URL(fileURLWithPath: expanded, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
        if database.rootURL != nil {
            return try database.outputDirectory(taskID)
        }
        let downloads = try Self.defaultArtifactRoot()
        let directory = downloads.appendingPathComponent(taskID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func updateTask(_ task: WeChatChannelsTaskRecord) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        tasks.sort { $0.createdAt > $1.createdAt }
        selectedTaskID = task.id
    }

    private func persist(_ task: WeChatChannelsTaskRecord) throws {
        do {
            try database.save(task)
        } catch {
            throw WeChatChannelsError.storageFailed("Could not save WeChat Channels task: \(error.localizedDescription)")
        }
    }

    static func defaultArtifactRoot() throws -> URL {
        let downloads = try FileManager.default.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("WeChat Channels", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        return downloads
    }

    static func parseExtraHeaders(_ raw: String) throws -> [String: String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "{}" else {
            return [:]
        }
        guard let data = trimmed.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw WeChatChannelsError.invalidArguments("Extra headers must be a JSON object.")
        }
        var headers: [String: String] = [:]
        for (key, value) in object {
            if let string = value as? String {
                headers[key] = string
            } else if let number = value as? NSNumber {
                headers[key] = number.stringValue
            } else {
                throw WeChatChannelsError.invalidArguments("Extra header `\(key)` must be a string or number.")
            }
        }
        return headers
    }

    private func requiredString(
        _ args: [String: Any],
        _ key: String,
        aliases: [String] = []
    ) throws -> String {
        let value = stringArg(args, ([key] + aliases))
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            throw WeChatChannelsError.invalidArguments("`\(key)` is required.")
        }
        return trimmed
    }

    private func stringArg(_ args: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = args[key] as? String {
                return value
            }
            if let value = args[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private func stringArg(_ args: [String: Any], _ keys: String...) -> String? {
        stringArg(args, keys)
    }

    private func intArg(_ args: [String: Any], _ key: String) -> Int? {
        if let value = args[key] as? Int {
            return value
        }
        if let value = args[key] as? NSNumber {
            return value.intValue
        }
        if let value = args[key] as? String {
            return Int(value)
        }
        return nil
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }

    static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"
}
