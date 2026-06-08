import AppKit
import Foundation
import Security

enum WeChatWatcherGearDescriptor {
    static let gearID = "wechat.watcher"
}

struct WeChatWatcherSessionCredential: Codable, Hashable {
    var token: String
    var cookie: String
    var userAgent: String
    var savedAt: Date

    var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct WeChatWatcherAccountRecord: Codable, Identifiable, Hashable {
    var id: String
    var fakeID: String
    var name: String
    var avatarURL: String?
    var intro: String?
    var enabled: Bool
    var lastSeenArticleID: String?
    var lastPublishTime: Int?
    var lastCheckedAt: Date?
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case fakeID = "fake_id"
        case name
        case avatarURL = "avatar_url"
        case intro
        case enabled
        case lastSeenArticleID = "last_seen_article_id"
        case lastPublishTime = "last_publish_time"
        case lastCheckedAt = "last_checked_at"
        case lastError = "last_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "fake_id": fakeID,
            "name": name,
            "enabled": enabled,
            "created_at": WeChatWatcherDateCodec.string(from: createdAt),
            "updated_at": WeChatWatcherDateCodec.string(from: updatedAt)
        ]
        if let avatarURL = avatarURL?.nilIfBlank { payload["avatar_url"] = avatarURL }
        if let intro = intro?.nilIfBlank { payload["intro"] = intro }
        if let lastSeenArticleID = lastSeenArticleID?.nilIfBlank { payload["last_seen_article_id"] = lastSeenArticleID }
        if let lastPublishTime { payload["last_publish_time"] = lastPublishTime }
        if let lastCheckedAt { payload["last_checked_at"] = WeChatWatcherDateCodec.string(from: lastCheckedAt) }
        if let lastError = lastError?.nilIfBlank { payload["last_error"] = lastError }
        return payload
    }
}

struct WeChatWatcherSearchResult: Codable, Identifiable, Hashable {
    var fakeID: String
    var name: String
    var alias: String?
    var avatarURL: String?
    var intro: String?

    var id: String { fakeID }

    enum CodingKeys: String, CodingKey {
        case fakeID = "fake_id"
        case name
        case alias
        case avatarURL = "avatar_url"
        case intro
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "fake_id": fakeID,
            "name": name
        ]
        if let alias = alias?.nilIfBlank { payload["alias"] = alias }
        if let avatarURL = avatarURL?.nilIfBlank { payload["avatar_url"] = avatarURL }
        if let intro = intro?.nilIfBlank { payload["intro"] = intro }
        return payload
    }
}

struct WeChatWatcherArticleSummary: Codable, Identifiable, Hashable {
    var articleID: String
    var accountID: String
    var accountName: String
    var title: String
    var url: String
    var coverURL: String?
    var digest: String?
    var publishTime: Int?
    var createTime: Int?

    var id: String { "\(accountID):\(articleID)" }

    enum CodingKeys: String, CodingKey {
        case articleID = "article_id"
        case accountID = "account_id"
        case accountName = "account_name"
        case title
        case url
        case coverURL = "cover_url"
        case digest
        case publishTime = "publish_time"
        case createTime = "create_time"
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "article_id": articleID,
            "account_id": accountID,
            "account_name": accountName,
            "title": title,
            "url": url
        ]
        if let coverURL = coverURL?.nilIfBlank { payload["cover_url"] = coverURL }
        if let digest = digest?.nilIfBlank { payload["digest"] = digest }
        if let publishTime { payload["publish_time"] = publishTime }
        if let createTime { payload["create_time"] = createTime }
        return payload
    }
}

enum WeChatWatcherRunStatus: String, Codable, Hashable {
    case completed
    case failed
    case degraded
}

struct WeChatWatcherCheckRunRecord: Codable, Identifiable, Hashable {
    var id: String
    var status: WeChatWatcherRunStatus
    var accountIDs: [String]
    var articles: [WeChatWatcherArticleSummary]
    var errors: [String]
    var createdAt: Date
    var completedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case accountIDs = "account_ids"
        case articles
        case errors
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    var agentDictionary: [String: Any] {
        [
            "id": id,
            "status": status.rawValue,
            "account_ids": accountIDs,
            "article_count": articles.count,
            "articles": articles.map(\.agentDictionary),
            "errors": errors,
            "created_at": WeChatWatcherDateCodec.string(from: createdAt),
            "completed_at": WeChatWatcherDateCodec.string(from: completedAt)
        ]
    }
}

enum WeChatWatcherDateCodec {
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

enum WeChatWatcherError: LocalizedError {
    case authMissing
    case invalidArguments(String)
    case networkFailed(String)
    case apiRejected(String)
    case storageFailed(String)

    var errorDescription: String? {
        switch self {
        case .authMissing:
            "WeChat Watcher needs a WeChat Official Account backend session before it can search or check accounts."
        case let .invalidArguments(message):
            message
        case let .networkFailed(message):
            message
        case let .apiRejected(message):
            message
        case let .storageFailed(message):
            message
        }
    }

    var code: String {
        switch self {
        case .authMissing: "auth_missing"
        case .invalidArguments: "invalid_arguments"
        case .networkFailed: "network_failed"
        case .apiRejected: "wechat_api_rejected"
        case .storageFailed: "storage_failed"
        }
    }
}

protocol WeChatWatcherCredentialStoring {
    func loadCredential() throws -> WeChatWatcherSessionCredential?
    func saveCredential(_ credential: WeChatWatcherSessionCredential) throws
    func deleteCredential() throws
}

struct WeChatWatcherKeychainCredentialStore: WeChatWatcherCredentialStoring {
    var service = "com.geeagent.gear.wechat.watcher"
    var account = "official-account-session"

    func loadCredential() throws -> WeChatWatcherSessionCredential? {
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
            throw WeChatWatcherError.storageFailed("Could not read WeChat Watcher session from Keychain.")
        }
        return try JSONDecoder().decode(WeChatWatcherSessionCredential.self, from: data)
    }

    func saveCredential(_ credential: WeChatWatcherSessionCredential) throws {
        let data = try JSONEncoder().encode(credential)
        var query = baseQuery()
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw WeChatWatcherError.storageFailed("Could not save WeChat Watcher session to Keychain.")
            }
            return
        }
        guard status == errSecSuccess else {
            throw WeChatWatcherError.storageFailed("Could not inspect WeChat Watcher Keychain session.")
        }
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw WeChatWatcherError.storageFailed("Could not update WeChat Watcher session in Keychain.")
        }
    }

    func deleteCredential() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WeChatWatcherError.storageFailed("Could not delete WeChat Watcher Keychain session.")
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

struct WeChatWatcherMemoryCredentialStore: WeChatWatcherCredentialStoring {
    final class Box {
        var credential: WeChatWatcherSessionCredential?
    }

    var box = Box()

    func loadCredential() throws -> WeChatWatcherSessionCredential? {
        box.credential
    }

    func saveCredential(_ credential: WeChatWatcherSessionCredential) throws {
        box.credential = credential
    }

    func deleteCredential() throws {
        box.credential = nil
    }
}

struct WeChatWatcherStateFile: Codable, Hashable {
    static let currentVersion = 1

    var version: Int
    var accounts: [WeChatWatcherAccountRecord]
    var runs: [WeChatWatcherCheckRunRecord]

    init(
        version: Int = Self.currentVersion,
        accounts: [WeChatWatcherAccountRecord] = [],
        runs: [WeChatWatcherCheckRunRecord] = []
    ) {
        self.version = version
        self.accounts = accounts
        self.runs = runs
    }
}

struct WeChatWatcherFileDatabase {
    var rootURL: URL?
    var fileManager: FileManager = .default

    var stateURL: URL {
        (try? dataRoot())?.appendingPathComponent("watcher.json")
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("wechat-watcher.json")
    }

    func loadState() -> WeChatWatcherStateFile {
        do {
            let url = try dataRoot().appendingPathComponent("watcher.json")
            guard fileManager.fileExists(atPath: url.path) else {
                return WeChatWatcherStateFile()
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WeChatWatcherStateFile.self, from: Data(contentsOf: url))
        } catch {
            return WeChatWatcherStateFile()
        }
    }

    func saveState(_ state: WeChatWatcherStateFile) throws {
        let url = try dataRoot().appendingPathComponent("watcher.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
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
        .appendingPathComponent("GeeAgent/gear-data/wechat.watcher", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

protocol WeChatWatcherAPIClient {
    @MainActor
    func searchAccounts(
        query: String,
        limit: Int,
        offset: Int,
        credential: WeChatWatcherSessionCredential
    ) async throws -> [WeChatWatcherSearchResult]

    @MainActor
    func fetchArticles(
        fakeID: String,
        accountID: String,
        accountName: String,
        limit: Int,
        credential: WeChatWatcherSessionCredential
    ) async throws -> [WeChatWatcherArticleSummary]
}

struct WeChatWatcherURLSessionAPIClient: WeChatWatcherAPIClient {
    var session: URLSession = .shared

    func searchAccounts(
        query: String,
        limit: Int,
        offset: Int,
        credential: WeChatWatcherSessionCredential
    ) async throws -> [WeChatWatcherSearchResult] {
        var components = URLComponents(string: "https://mp.weixin.qq.com/cgi-bin/searchbiz")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "search_biz"),
            URLQueryItem(name: "begin", value: "\(offset)"),
            URLQueryItem(name: "count", value: "\(limit)"),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "token", value: credential.token),
            URLQueryItem(name: "lang", value: "zh_CN"),
            URLQueryItem(name: "f", value: "json"),
            URLQueryItem(name: "ajax", value: "1")
        ]
        guard let url = components?.url else {
            throw WeChatWatcherError.invalidArguments("Could not construct WeChat account search URL.")
        }
        let object = try await requestJSON(url: url, credential: credential)
        try Self.throwIfRejected(object)
        return Self.parseSearchResults(object)
    }

    func fetchArticles(
        fakeID: String,
        accountID: String,
        accountName: String,
        limit: Int,
        credential: WeChatWatcherSessionCredential
    ) async throws -> [WeChatWatcherArticleSummary] {
        var components = URLComponents(string: "https://mp.weixin.qq.com/cgi-bin/appmsgpublish")
        components?.queryItems = [
            URLQueryItem(name: "sub", value: "list"),
            URLQueryItem(name: "sub_action", value: "list_ex"),
            URLQueryItem(name: "begin", value: "0"),
            URLQueryItem(name: "count", value: "\(limit)"),
            URLQueryItem(name: "fakeid", value: fakeID),
            URLQueryItem(name: "token", value: credential.token),
            URLQueryItem(name: "lang", value: "zh_CN"),
            URLQueryItem(name: "f", value: "json"),
            URLQueryItem(name: "ajax", value: "1")
        ]
        guard let url = components?.url else {
            throw WeChatWatcherError.invalidArguments("Could not construct WeChat article list URL.")
        }
        let object = try await requestJSON(url: url, credential: credential)
        try Self.throwIfRejected(object)
        return Self.parseArticleSummaries(object, accountID: accountID, accountName: accountName)
    }

    private func requestJSON(
        url: URL,
        credential: WeChatWatcherSessionCredential
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credential.cookie, forHTTPHeaderField: "Cookie")
        request.setValue(credential.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://mp.weixin.qq.com/", forHTTPHeaderField: "Referer")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                throw WeChatWatcherError.networkFailed("WeChat backend returned HTTP \(http.statusCode).")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WeChatWatcherError.networkFailed("WeChat backend did not return a JSON object.")
            }
            return object
        } catch let error as WeChatWatcherError {
            throw error
        } catch {
            throw WeChatWatcherError.networkFailed(error.localizedDescription)
        }
    }

    static func throwIfRejected(_ object: [String: Any]) throws {
        if let baseResp = object["base_resp"] as? [String: Any] {
            let ret = intValue(baseResp["ret"]) ?? 0
            if ret != 0 {
                let message = stringValue(baseResp["err_msg"]) ?? "WeChat backend rejected the request with code \(ret)."
                throw WeChatWatcherError.apiRejected(message)
            }
        }
        if let ret = intValue(object["ret"]), ret != 0 {
            let message = stringValue(object["errmsg"]) ?? stringValue(object["err_msg"]) ?? "WeChat backend rejected the request with code \(ret)."
            throw WeChatWatcherError.apiRejected(message)
        }
    }

    static func parseSearchResults(_ object: [String: Any]) -> [WeChatWatcherSearchResult] {
        let list = object["list"] as? [[String: Any]] ?? []
        return list.compactMap { item in
            let fakeID = stringValue(item["fakeid"])
                ?? stringValue(item["fake_id"])
                ?? stringValue(item["id"])
            let name = stringValue(item["nickname"])
                ?? stringValue(item["name"])
                ?? stringValue(item["alias"])
            guard let fakeID = fakeID?.nilIfBlank,
                  let name = name?.nilIfBlank
            else {
                return nil
            }
            return WeChatWatcherSearchResult(
                fakeID: fakeID,
                name: name,
                alias: stringValue(item["alias"]),
                avatarURL: stringValue(item["round_head_img"]) ?? stringValue(item["avatar_url"]),
                intro: stringValue(item["signature"]) ?? stringValue(item["intro"])
            )
        }
    }

    static func parseArticleSummaries(
        _ object: [String: Any],
        accountID: String,
        accountName: String
    ) -> [WeChatWatcherArticleSummary] {
        let publishPage = objectValue(object["publish_page"])
        let publishList = publishPage?["publish_list"] as? [[String: Any]] ?? []
        return publishList.flatMap { publishItem -> [WeChatWatcherArticleSummary] in
            let publishInfo = objectValue(publishItem["publish_info"]) ?? publishItem
            let messages = publishInfo["appmsgex"] as? [[String: Any]]
                ?? objectValue(publishInfo["appmsg_info"])?.compactMessageList
                ?? []
            return messages.compactMap { message in
                guard let url = stringValue(message["link"])?.nilIfBlank,
                      let title = stringValue(message["title"])?.nilIfBlank
                else {
                    return nil
                }
                let articleID = stringValue(message["aid"])
                    ?? stringValue(message["appmsgid"])
                    ?? articleIDFromURL(url)
                    ?? url
                return WeChatWatcherArticleSummary(
                    articleID: articleID,
                    accountID: accountID,
                    accountName: accountName,
                    title: title,
                    url: url,
                    coverURL: stringValue(message["cover"]) ?? stringValue(message["cover_url"]),
                    digest: stringValue(message["digest"]),
                    publishTime: intValue(message["update_time"]) ?? intValue(message["publish_time"]),
                    createTime: intValue(message["create_time"])
                )
            }
        }
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

    private static func articleIDFromURL(_ value: String) -> String? {
        guard let url = URL(string: value) else {
            return nil
        }
        if let mid = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "mid" })?
            .value,
            let idx = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "idx" })?
            .value
        {
            return "\(mid)-\(idx)"
        }
        return url.lastPathComponent.nilIfBlank
    }
}

private extension Dictionary where Key == String, Value == Any {
    var compactMessageList: [[String: Any]] {
        if let list = self["appmsgex"] as? [[String: Any]] {
            return list
        }
        return [self]
    }
}

@MainActor
final class WeChatWatcherGearStore: ObservableObject {
    static let shared = WeChatWatcherGearStore()

    @Published private(set) var accounts: [WeChatWatcherAccountRecord] = []
    @Published private(set) var runs: [WeChatWatcherCheckRunRecord] = []
    @Published private(set) var searchResults: [WeChatWatcherSearchResult] = []
    @Published private(set) var sessionConfigured = false
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage = "Ready"

    @Published var tokenDraft = ""
    @Published var cookieDraft = ""
    @Published var userAgentDraft = "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
    @Published var searchQuery = ""
    @Published var selectedAccountID: String?

    private let database: WeChatWatcherFileDatabase
    private let credentialStore: any WeChatWatcherCredentialStoring
    private let client: any WeChatWatcherAPIClient

    init(
        database: WeChatWatcherFileDatabase = WeChatWatcherFileDatabase(),
        credentialStore: any WeChatWatcherCredentialStoring = WeChatWatcherKeychainCredentialStore(),
        client: any WeChatWatcherAPIClient = WeChatWatcherURLSessionAPIClient()
    ) {
        self.database = database
        self.credentialStore = credentialStore
        self.client = client
        load()
    }

    func load() {
        let state = database.loadState()
        accounts = state.accounts.sorted { $0.updatedAt > $1.updatedAt }
        runs = state.runs.sorted { $0.completedAt > $1.completedAt }
        selectedAccountID = selectedAccountID ?? accounts.first?.id
        do {
            sessionConfigured = try credentialStore.loadCredential()?.isConfigured == true
        } catch {
            sessionConfigured = false
        }
    }

    func saveSessionFromDrafts() {
        do {
            try saveSession(token: tokenDraft, cookie: cookieDraft, userAgent: userAgentDraft)
            tokenDraft = ""
            cookieDraft = ""
            statusMessage = "WeChat backend session saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearSession() {
        do {
            try credentialStore.deleteCredential()
            sessionConfigured = false
            statusMessage = "WeChat backend session cleared."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveSession(token: String, cookie: String, userAgent: String) throws {
        let credential = WeChatWatcherSessionCredential(
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            cookie: cookie.trimmingCharacters(in: .whitespacesAndNewlines),
            userAgent: userAgent.trimmingCharacters(in: .whitespacesAndNewlines),
            savedAt: Date()
        )
        guard credential.isConfigured else {
            throw WeChatWatcherError.invalidArguments("Token, cookie, and user-agent are required.")
        }
        try credentialStore.saveCredential(credential)
        sessionConfigured = true
    }

    func searchCurrentQuery() {
        Task {
            await searchAccounts(query: searchQuery)
        }
    }

    func searchAccounts(query: String, limit: Int = 10, offset: Int = 0) async {
        isBusy = true
        statusMessage = "Searching WeChat accounts..."
        defer { isBusy = false }
        do {
            let credential = try configuredCredential()
            let results = try await client.searchAccounts(
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                limit: Self.clamp(limit, min: 1, max: 50),
                offset: max(0, offset),
                credential: credential
            )
            searchResults = results
            statusMessage = "Found \(results.count) account candidate(s)."
        } catch {
            searchResults = []
            statusMessage = error.localizedDescription
        }
    }

    func watch(_ result: WeChatWatcherSearchResult) {
        do {
            let account = try upsertAccount(
                fakeID: result.fakeID,
                name: result.name,
                avatarURL: result.avatarURL,
                intro: result.intro,
                enabled: true
            )
            selectedAccountID = account.id
            statusMessage = "Watching \(account.name)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func checkSelectedAccount() {
        Task {
            await checkUpdates(accountID: selectedAccountID)
        }
    }

    func checkAllAccounts() {
        Task {
            await checkUpdates(accountID: nil)
        }
    }

    @discardableResult
    func checkUpdates(accountID: String?, limit: Int = 20) async -> WeChatWatcherCheckRunRecord {
        isBusy = true
        statusMessage = "Checking WeChat account updates..."
        defer { isBusy = false }

        let startedAt = Date()
        var targetAccounts = accounts.filter(\.enabled)
        if let accountID = accountID?.nilIfBlank {
            targetAccounts = targetAccounts.filter { $0.id == accountID || $0.fakeID == accountID }
        }

        var newArticles: [WeChatWatcherArticleSummary] = []
        var errors: [String] = []

        do {
            let credential = try configuredCredential()
            guard !targetAccounts.isEmpty else {
                throw WeChatWatcherError.invalidArguments("No enabled watched accounts matched this check.")
            }

            for account in targetAccounts {
                do {
                    let fetched = try await client.fetchArticles(
                        fakeID: account.fakeID,
                        accountID: account.id,
                        accountName: account.name,
                        limit: Self.clamp(limit, min: 1, max: 100),
                        credential: credential
                    )
                    let discovered = Self.newArticles(from: fetched, previous: account)
                    newArticles.append(contentsOf: discovered)
                    updateAccountAfterCheck(accountID: account.id, fetched: fetched, error: nil)
                } catch {
                    let message = "\(account.name): \(error.localizedDescription)"
                    errors.append(message)
                    updateAccountAfterCheck(accountID: account.id, fetched: [], error: error.localizedDescription)
                }
            }
        } catch {
            errors.append(error.localizedDescription)
        }

        let status: WeChatWatcherRunStatus = errors.isEmpty ? .completed : (newArticles.isEmpty ? .failed : .degraded)
        let run = WeChatWatcherCheckRunRecord(
            id: "wechat-check-\(Self.timestamp())-\(UUID().uuidString.prefix(8))",
            status: status,
            accountIDs: targetAccounts.map(\.id),
            articles: newArticles,
            errors: errors,
            createdAt: startedAt,
            completedAt: Date()
        )
        runs.insert(run, at: 0)
        persist()
        statusMessage = errors.isEmpty
            ? "Discovered \(newArticles.count) new article(s)."
            : "Check \(status.rawValue): \(errors.joined(separator: "; "))"
        return run
    }

    func runAgentAction(capabilityID: String, args: [String: Any]) async -> [String: Any] {
        do {
            switch capabilityID {
            case "wechat.auth_status":
                return authStatusPayload()
            case "wechat.search_accounts":
                return try await searchAccountsPayload(args: args)
            case "wechat.watch_account":
                return try watchAccountPayload(args: args)
            case "wechat.list_watched_accounts":
                return listAccountsPayload()
            case "wechat.check_updates":
                return await checkUpdatesPayload(args: args)
            case "wechat.latest_articles":
                return try await latestArticlesByNamePayload(args: args)
            default:
                throw WeChatWatcherError.invalidArguments("wechat.watcher does not support `\(capabilityID)`.")
            }
        } catch {
            return failurePayload(capabilityID: capabilityID, error: error)
        }
    }

    private func authStatusPayload() -> [String: Any] {
        load()
        return [
            "gear_id": WeChatWatcherGearDescriptor.gearID,
            "capability_id": "wechat.auth_status",
            "status": "success",
            "fallback_attempted": false,
            "session_configured": sessionConfigured,
            "credential_store": "keychain",
            "watch_count": accounts.count,
            "data_path": database.stateURL.path
        ]
    }

    private func searchAccountsPayload(args: [String: Any]) async throws -> [String: Any] {
        let query = try requiredString(args, "query", aliases: ["account_name", "name"])
        let credential = try configuredCredential()
        let results = try await client.searchAccounts(
            query: query,
            limit: Self.clamp(intArg(args, "limit") ?? 10, min: 1, max: 50),
            offset: max(0, intArg(args, "offset") ?? 0),
            credential: credential
        )
        searchResults = results
        return [
            "gear_id": WeChatWatcherGearDescriptor.gearID,
            "capability_id": "wechat.search_accounts",
            "status": "success",
            "fallback_attempted": false,
            "query": query,
            "result_count": results.count,
            "accounts": results.map(\.agentDictionary)
        ]
    }

    private func watchAccountPayload(args: [String: Any]) throws -> [String: Any] {
        let fakeID = try requiredString(args, "fake_id", aliases: ["fakeid", "mp_id"])
        let name = try requiredString(args, "name", aliases: ["mp_name", "account_name"])
        let account = try upsertAccount(
            fakeID: fakeID,
            name: name,
            avatarURL: stringArg(args, "avatar_url", "avatar", "mp_cover"),
            intro: stringArg(args, "intro", "signature", "mp_intro"),
            enabled: boolArg(args, "enabled") ?? true
        )
        return [
            "gear_id": WeChatWatcherGearDescriptor.gearID,
            "capability_id": "wechat.watch_account",
            "status": "success",
            "fallback_attempted": false,
            "account": account.agentDictionary,
            "watch_count": accounts.count
        ]
    }

    private func listAccountsPayload() -> [String: Any] {
        load()
        return [
            "gear_id": WeChatWatcherGearDescriptor.gearID,
            "capability_id": "wechat.list_watched_accounts",
            "status": "success",
            "fallback_attempted": false,
            "account_count": accounts.count,
            "accounts": accounts.map(\.agentDictionary)
        ]
    }

    private func checkUpdatesPayload(args: [String: Any]) async -> [String: Any] {
        let run = await checkUpdates(
            accountID: stringArg(args, "account_id", "id", "fake_id"),
            limit: intArg(args, "limit") ?? intArg(args, "max_articles") ?? 20
        )
        var payload = run.agentDictionary
        payload["gear_id"] = WeChatWatcherGearDescriptor.gearID
        payload["capability_id"] = "wechat.check_updates"
        payload["fallback_attempted"] = false
        payload["data_path"] = database.stateURL.path
        return payload
    }

    private func latestArticlesByNamePayload(args: [String: Any]) async throws -> [String: Any] {
        let query = try requiredString(args, "query", aliases: ["account_name", "name"])
        let limit = Self.clamp(intArg(args, "limit") ?? intArg(args, "max_articles") ?? 2, min: 1, max: 20)
        let searchLimit = Self.clamp(intArg(args, "search_limit") ?? 5, min: 1, max: 20)
        let shouldWatch = boolArg(args, "auto_watch") ?? boolArg(args, "watch") ?? true
        let credential = try configuredCredential()

        let results = try await client.searchAccounts(
            query: query,
            limit: searchLimit,
            offset: max(0, intArg(args, "offset") ?? 0),
            credential: credential
        )
        searchResults = results
        guard let selected = Self.bestAccountMatch(in: results, query: query) else {
            throw WeChatWatcherError.invalidArguments("No WeChat public account matched `\(query)`.")
        }

        let account: WeChatWatcherAccountRecord
        if shouldWatch {
            account = try upsertAccount(
                fakeID: selected.fakeID,
                name: selected.name,
                avatarURL: selected.avatarURL,
                intro: selected.intro,
                enabled: true
            )
        } else {
            account = WeChatWatcherAccountRecord(
                id: Self.accountID(fakeID: selected.fakeID),
                fakeID: selected.fakeID,
                name: selected.name,
                avatarURL: selected.avatarURL,
                intro: selected.intro,
                enabled: true,
                lastSeenArticleID: nil,
                lastPublishTime: nil,
                lastCheckedAt: nil,
                lastError: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        let articles = try await client.fetchArticles(
            fakeID: account.fakeID,
            accountID: account.id,
            accountName: account.name,
            limit: limit,
            credential: credential
        )
        if shouldWatch {
            updateAccountAfterCheck(accountID: account.id, fetched: articles, error: nil)
            persist()
        }

        let latestArticles = Array(articles.prefix(limit))
        statusMessage = "Fetched \(latestArticles.count) latest article(s) for \(account.name)."
        return [
            "gear_id": WeChatWatcherGearDescriptor.gearID,
            "capability_id": "wechat.latest_articles",
            "status": "success",
            "fallback_attempted": false,
            "query": query,
            "search_result_count": results.count,
            "watchlist_updated": shouldWatch,
            "selected_account": account.agentDictionary,
            "latest_article_count": latestArticles.count,
            "articles": latestArticles.map(\.agentDictionary),
            "candidate_accounts": results.map(\.agentDictionary),
            "data_path": database.stateURL.path
        ]
    }

    private func upsertAccount(
        fakeID: String,
        name: String,
        avatarURL: String?,
        intro: String?,
        enabled: Bool
    ) throws -> WeChatWatcherAccountRecord {
        let trimmedFakeID = fakeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFakeID.isEmpty, !trimmedName.isEmpty else {
            throw WeChatWatcherError.invalidArguments("`fake_id` and `name` are required to watch a WeChat account.")
        }

        let now = Date()
        var nextAccounts = accounts
        if let index = nextAccounts.firstIndex(where: { $0.fakeID == trimmedFakeID }) {
            nextAccounts[index].name = trimmedName
            nextAccounts[index].avatarURL = avatarURL
            nextAccounts[index].intro = intro
            nextAccounts[index].enabled = enabled
            nextAccounts[index].updatedAt = now
        } else {
            nextAccounts.insert(
                WeChatWatcherAccountRecord(
                    id: Self.accountID(fakeID: trimmedFakeID),
                    fakeID: trimmedFakeID,
                    name: trimmedName,
                    avatarURL: avatarURL,
                    intro: intro,
                    enabled: enabled,
                    lastSeenArticleID: nil,
                    lastPublishTime: nil,
                    lastCheckedAt: nil,
                    lastError: nil,
                    createdAt: now,
                    updatedAt: now
                ),
                at: 0
            )
        }
        accounts = nextAccounts.sorted { $0.updatedAt > $1.updatedAt }
        persist()
        return accounts.first { $0.fakeID == trimmedFakeID } ?? nextAccounts[0]
    }

    private func updateAccountAfterCheck(
        accountID: String,
        fetched: [WeChatWatcherArticleSummary],
        error: String?
    ) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            return
        }
        accounts[index].lastCheckedAt = Date()
        accounts[index].lastError = error
        accounts[index].updatedAt = Date()
        if let latest = fetched.first {
            accounts[index].lastSeenArticleID = latest.articleID
            accounts[index].lastPublishTime = latest.publishTime ?? accounts[index].lastPublishTime
        }
    }

    private func configuredCredential() throws -> WeChatWatcherSessionCredential {
        guard let credential = try credentialStore.loadCredential(), credential.isConfigured else {
            sessionConfigured = false
            throw WeChatWatcherError.authMissing
        }
        sessionConfigured = true
        return credential
    }

    private func persist() {
        do {
            try database.saveState(WeChatWatcherStateFile(accounts: accounts, runs: Array(runs.prefix(100))))
        } catch {
            statusMessage = "Could not save WeChat Watcher state: \(error.localizedDescription)"
        }
    }

    private func failurePayload(capabilityID: String, error: Error) -> [String: Any] {
        let watcherError = error as? WeChatWatcherError
        return [
            "gear_id": WeChatWatcherGearDescriptor.gearID,
            "capability_id": capabilityID,
            "status": "failed",
            "fallback_attempted": false,
            "code": watcherError?.code ?? "action_failed",
            "error": error.localizedDescription
        ]
    }

    private static func newArticles(
        from fetched: [WeChatWatcherArticleSummary],
        previous account: WeChatWatcherAccountRecord
    ) -> [WeChatWatcherArticleSummary] {
        guard let lastSeen = account.lastSeenArticleID?.nilIfBlank else {
            return fetched
        }
        var result: [WeChatWatcherArticleSummary] = []
        for article in fetched {
            if article.articleID == lastSeen {
                break
            }
            if let lastPublishTime = account.lastPublishTime,
               let publishTime = article.publishTime,
               publishTime <= lastPublishTime,
               !result.isEmpty {
                continue
            }
            result.append(article)
        }
        return result
    }

    private static func bestAccountMatch(
        in results: [WeChatWatcherSearchResult],
        query: String
    ) -> WeChatWatcherSearchResult? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = results.first(where: {
            $0.name.lowercased() == normalizedQuery || $0.alias?.lowercased() == normalizedQuery
        }) {
            return exact
        }
        if let contains = results.first(where: {
            $0.name.lowercased().contains(normalizedQuery) || ($0.alias?.lowercased().contains(normalizedQuery) == true)
        }) {
            return contains
        }
        return results.first
    }

    private static func accountID(fakeID: String) -> String {
        let clean = fakeID
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return "wechat-\(clean.prefix(48))"
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

    private func requiredString(
        _ args: [String: Any],
        _ key: String,
        aliases: [String] = []
    ) throws -> String {
        let value = stringArg(args, ([key] + aliases))
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            throw WeChatWatcherError.invalidArguments("`\(key)` is required.")
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

    private func boolArg(_ args: [String: Any], _ key: String) -> Bool? {
        if let value = args[key] as? Bool {
            return value
        }
        if let value = args[key] as? NSNumber {
            return value.boolValue
        }
        if let value = args[key] as? String {
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }
}
