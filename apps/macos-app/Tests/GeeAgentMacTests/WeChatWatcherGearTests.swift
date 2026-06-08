import XCTest
@testable import GeeAgentMac

final class WeChatWatcherGearTests: XCTestCase {
    func testWeChatWatcherManifestDeclaresCapabilities() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/wechat.watcher/gear.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let agent = try XCTUnwrap(raw["agent"] as? [String: Any])
        let rawCapabilities = try XCTUnwrap(agent["capabilities"] as? [[String: Any]])

        XCTAssertEqual(manifest.id, WeChatWatcherGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.type, "native")
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(
            manifest.agent?.capabilities.map(\.id),
            [
                "wechat.auth_status",
                "wechat.search_accounts",
                "wechat.watch_account",
                "wechat.list_watched_accounts",
                "wechat.check_updates",
                "wechat.latest_articles"
            ]
        )
        let exportedIDs = rawCapabilities.compactMap { capability -> String? in
            guard let exports = capability["exports"] as? [String: Any],
                  let codex = exports["codex"] as? [String: Any],
                  codex["enabled"] as? Bool == true
            else {
                return nil
            }
            return capability["id"] as? String
        }
        XCTAssertEqual(exportedIDs, [
            "wechat.auth_status",
            "wechat.search_accounts",
            "wechat.watch_account",
            "wechat.list_watched_accounts",
            "wechat.check_updates",
            "wechat.latest_articles"
        ])
        XCTAssertTrue(GearHost.nativeWindowDescriptors.contains(GearHost.weChatWatcherWindowDescriptor))
        XCTAssertTrue(GearHost.nativeGearIDs.contains(WeChatWatcherGearDescriptor.gearID))
    }

    func testWeChatBackendSearchParserUsesFakeIDInsteadOfURL() {
        let object: [String: Any] = [
            "list": [
                [
                    "fakeid": "MzA4NzMyNzU5Mg==",
                    "nickname": "Demo Account",
                    "alias": "demo",
                    "round_head_img": "https://example.com/avatar.png",
                    "signature": "Demo intro"
                ]
            ]
        ]

        let results = WeChatWatcherURLSessionAPIClient.parseSearchResults(object)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.fakeID, "MzA4NzMyNzU5Mg==")
        XCTAssertEqual(results.first?.name, "Demo Account")
        XCTAssertEqual(results.first?.avatarURL, "https://example.com/avatar.png")
    }

    func testWeChatBackendArticleParserReadsPublishInfo() throws {
        let publishInfo = """
        {
          "appmsgex": [
            {
              "aid": "2247480001_1",
              "title": "New Article",
              "link": "https://mp.weixin.qq.com/s/demo",
              "cover": "https://example.com/cover.jpg",
              "digest": "Summary",
              "update_time": 1780000000,
              "create_time": 1779990000
            }
          ]
        }
        """
        let publishPage = [
            "publish_list": [
                ["publish_info": publishInfo]
            ]
        ] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: publishPage)
        let object: [String: Any] = [
            "publish_page": String(data: data, encoding: .utf8) ?? "{}"
        ]

        let articles = WeChatWatcherURLSessionAPIClient.parseArticleSummaries(
            object,
            accountID: "wechat-demo",
            accountName: "Demo Account"
        )

        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles.first?.articleID, "2247480001_1")
        XCTAssertEqual(articles.first?.accountName, "Demo Account")
        XCTAssertEqual(articles.first?.url, "https://mp.weixin.qq.com/s/demo")
    }

    @MainActor
    func testAgentSearchFailsStructurallyWithoutSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wechat-watcher-auth-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WeChatWatcherGearStore(
            database: WeChatWatcherFileDatabase(rootURL: root),
            credentialStore: WeChatWatcherMemoryCredentialStore(),
            client: WeChatWatcherMockClient()
        )

        let payload = await store.runAgentAction(
            capabilityID: "wechat.search_accounts",
            args: ["query": "Demo"]
        )

        XCTAssertEqual(payload["gear_id"] as? String, WeChatWatcherGearDescriptor.gearID)
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertEqual(payload["code"] as? String, "auth_missing")
        XCTAssertEqual(payload["fallback_attempted"] as? Bool, false)
    }

    @MainActor
    func testWatchAndCheckUpdatesPersistsStructuredRun() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wechat-watcher-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let credentialStore = WeChatWatcherMemoryCredentialStore()
        let store = WeChatWatcherGearStore(
            database: WeChatWatcherFileDatabase(rootURL: root),
            credentialStore: credentialStore,
            client: WeChatWatcherMockClient(
                articles: [
                    WeChatWatcherArticleSummary(
                        articleID: "article-2",
                        accountID: "wechat-fake",
                        accountName: "Demo Account",
                        title: "Second",
                        url: "https://mp.weixin.qq.com/s/second",
                        coverURL: nil,
                        digest: nil,
                        publishTime: 200,
                        createTime: nil
                    ),
                    WeChatWatcherArticleSummary(
                        articleID: "article-1",
                        accountID: "wechat-fake",
                        accountName: "Demo Account",
                        title: "First",
                        url: "https://mp.weixin.qq.com/s/first",
                        coverURL: nil,
                        digest: nil,
                        publishTime: 100,
                        createTime: nil
                    )
                ]
            )
        )

        try store.saveSession(token: "token", cookie: "cookie", userAgent: "ua")

        let watchPayload = await store.runAgentAction(
            capabilityID: "wechat.watch_account",
            args: [
                "fake_id": "fake",
                "name": "Demo Account"
            ]
        )
        XCTAssertEqual(watchPayload["status"] as? String, "success")

        let checkPayload = await store.runAgentAction(
            capabilityID: "wechat.check_updates",
            args: ["limit": 10]
        )

        XCTAssertEqual(checkPayload["status"] as? String, "completed")
        XCTAssertEqual(checkPayload["article_count"] as? Int, 2)
        XCTAssertEqual(store.runs.count, 1)
        XCTAssertEqual(store.accounts.first?.lastSeenArticleID, "article-2")

        let reloaded = WeChatWatcherFileDatabase(rootURL: root).loadState()
        XCTAssertEqual(reloaded.accounts.count, 1)
        XCTAssertEqual(reloaded.runs.first?.articles.count, 2)
    }

    @MainActor
    func testLatestArticlesSearchesByNameAndUpdatesWatchlist() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wechat-watcher-latest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let credentialStore = WeChatWatcherMemoryCredentialStore()
        let store = WeChatWatcherGearStore(
            database: WeChatWatcherFileDatabase(rootURL: root),
            credentialStore: credentialStore,
            client: WeChatWatcherMockClient(
                searchResults: [
                    WeChatWatcherSearchResult(
                        fakeID: "other",
                        name: "Other Account",
                        alias: nil,
                        avatarURL: nil,
                        intro: nil
                    ),
                    WeChatWatcherSearchResult(
                        fakeID: "hku",
                        name: "HKU ICB",
                        alias: "hkuicb",
                        avatarURL: "https://example.com/hku.png",
                        intro: "HKU ICB updates"
                    )
                ],
                articles: [
                    WeChatWatcherArticleSummary(
                        articleID: "article-2",
                        accountID: "unused",
                        accountName: "unused",
                        title: "Second HKU ICB Article",
                        url: "https://mp.weixin.qq.com/s/hku-second",
                        coverURL: nil,
                        digest: "Second digest",
                        publishTime: 200,
                        createTime: nil
                    ),
                    WeChatWatcherArticleSummary(
                        articleID: "article-1",
                        accountID: "unused",
                        accountName: "unused",
                        title: "First HKU ICB Article",
                        url: "https://mp.weixin.qq.com/s/hku-first",
                        coverURL: nil,
                        digest: "First digest",
                        publishTime: 100,
                        createTime: nil
                    )
                ]
            )
        )

        try store.saveSession(token: "token", cookie: "cookie", userAgent: "ua")

        let payload = await store.runAgentAction(
            capabilityID: "wechat.latest_articles",
            args: [
                "query": "HKU ICB",
                "limit": 2
            ]
        )

        XCTAssertEqual(payload["gear_id"] as? String, WeChatWatcherGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "wechat.latest_articles")
        XCTAssertEqual(payload["status"] as? String, "success")
        XCTAssertEqual(payload["fallback_attempted"] as? Bool, false)
        XCTAssertEqual(payload["query"] as? String, "HKU ICB")
        XCTAssertEqual(payload["search_result_count"] as? Int, 2)
        XCTAssertEqual(payload["watchlist_updated"] as? Bool, true)
        XCTAssertEqual(payload["latest_article_count"] as? Int, 2)

        let selected = try XCTUnwrap(payload["selected_account"] as? [String: Any])
        XCTAssertEqual(selected["fake_id"] as? String, "hku")
        XCTAssertEqual(selected["name"] as? String, "HKU ICB")

        let articles = try XCTUnwrap(payload["articles"] as? [[String: Any]])
        XCTAssertEqual(articles.compactMap { $0["article_id"] as? String }, ["article-2", "article-1"])
        XCTAssertEqual(articles.compactMap { $0["account_name"] as? String }, ["HKU ICB", "HKU ICB"])

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.accounts.first?.fakeID, "hku")
        XCTAssertEqual(store.accounts.first?.lastSeenArticleID, "article-2")
        XCTAssertEqual(store.accounts.first?.lastPublishTime, 200)

        let reloaded = WeChatWatcherFileDatabase(rootURL: root).loadState()
        XCTAssertEqual(reloaded.accounts.first?.fakeID, "hku")
        XCTAssertEqual(reloaded.accounts.first?.lastSeenArticleID, "article-2")
    }
}

private struct WeChatWatcherMockClient: WeChatWatcherAPIClient {
    var searchResults: [WeChatWatcherSearchResult] = [
        WeChatWatcherSearchResult(
            fakeID: "fake",
            name: "Demo Account",
            alias: nil,
            avatarURL: nil,
            intro: nil
        )
    ]
    var articles: [WeChatWatcherArticleSummary] = []

    func searchAccounts(
        query: String,
        limit: Int,
        offset: Int,
        credential: WeChatWatcherSessionCredential
    ) async throws -> [WeChatWatcherSearchResult] {
        searchResults
    }

    func fetchArticles(
        fakeID: String,
        accountID: String,
        accountName: String,
        limit: Int,
        credential: WeChatWatcherSessionCredential
    ) async throws -> [WeChatWatcherArticleSummary] {
        articles.map { article in
            WeChatWatcherArticleSummary(
                articleID: article.articleID,
                accountID: accountID,
                accountName: accountName,
                title: article.title,
                url: article.url,
                coverURL: article.coverURL,
                digest: article.digest,
                publishTime: article.publishTime,
                createTime: article.createTime
            )
        }
    }
}
