import XCTest
@testable import GeeAgentMac

final class WeChatChannelsGearTests: XCTestCase {
    func testWeChatChannelsManifestDeclaresExportedCapabilities() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/wechat.channels/gear.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let agent = try XCTUnwrap(raw["agent"] as? [String: Any])
        let rawCapabilities = try XCTUnwrap(agent["capabilities"] as? [[String: Any]])

        XCTAssertEqual(manifest.id, WeChatChannelsGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.type, "native")
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(
            manifest.agent?.capabilities.map(\.id),
            [
                "wechat_channels.auth_status",
                "wechat_channels.metadata",
                "wechat_channels.download",
                "wechat_channels.get_task",
                "wechat_channels.list_tasks"
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
            "wechat_channels.auth_status",
            "wechat_channels.metadata",
            "wechat_channels.download",
            "wechat_channels.get_task",
            "wechat_channels.list_tasks"
        ])
        XCTAssertTrue(GearHost.nativeWindowDescriptors.contains(GearHost.weChatChannelsWindowDescriptor))
        XCTAssertTrue(GearHost.nativeGearIDs.contains(WeChatChannelsGearDescriptor.gearID))
    }

    func testURLNormalizerAcceptsShareAndFinderPreviewLinks() throws {
        let share = try WeChatChannelsURLNormalizer.normalizedSourceURL("https://weixin.qq.com/sph/AZJc5LQAbb")
        XCTAssertEqual(share.sourceURL, "https://weixin.qq.com/sph/AZJc5LQAbb")
        XCTAssertEqual(share.shortID, "AZJc5LQAbb")

        let preview = try WeChatChannelsURLNormalizer.normalizedSourceURL("https://channels.weixin.qq.com/finder-preview/pages/sph?id=AZJc5LQAbb")
        XCTAssertEqual(preview.sourceURL, "https://weixin.qq.com/sph/AZJc5LQAbb")
        XCTAssertEqual(preview.shortID, "AZJc5LQAbb")

        let feed = "https://channels.weixin.qq.com/finder-preview/pages/feed?token=general-token&eid=export-id"
        let token = try XCTUnwrap(WeChatChannelsURLNormalizer.feedTokenAndExportID(from: feed))
        XCTAssertEqual(token.generalToken, "general-token")
        XCTAssertEqual(token.exportID, "export-id")

        let feedWithoutToken = "https://channels.weixin.qq.com/finder-preview/pages/feed?eid=export-only"
        let exportOnly = try XCTUnwrap(WeChatChannelsURLNormalizer.feedTokenAndExportID(from: feedWithoutToken))
        XCTAssertNil(exportOnly.generalToken)
        XCTAssertEqual(exportOnly.exportID, "export-only")
    }

    @MainActor
    func testFeedParserKeepsTencentVideoURLFields() throws {
        let object: [String: Any] = [
            "errCode": 0,
            "data": [
                "authorInfo": [
                    "nickname": "Demo Author",
                    "headImgUrl": "https://example.com/avatar.jpg"
                ],
                "feedInfo": [
                    "description": "Demo Channels video",
                    "coverUrl": "https://example.com/cover.jpg",
                    "createtime": 1780000000,
                    "videoUrl": "https://finder.video.qq.com/default.mp4",
                    "h264VideoInfo": [
                        "videoUrl": "https://finder.video.qq.com/h264.mp4"
                    ],
                    "h265VideoInfo": [
                        "videoUrl": "https://finder.video.qq.com/h265.mp4"
                    ],
                    "likeCountFmt": "952"
                ]
            ]
        ]

        let profile = try WeChatChannelsURLSessionAPIClient.parseFeedProfile(
            object,
            sourceURL: "https://weixin.qq.com/sph/demo",
            shortID: "demo",
            exportID: "export-id",
            generalToken: "token"
        )

        XCTAssertEqual(profile.author, "Demo Author")
        XCTAssertEqual(profile.description, "Demo Channels video")
        XCTAssertEqual(profile.bestVideoURL, "https://finder.video.qq.com/h265.mp4")
        XCTAssertEqual(profile.likeCountText, "952")
        XCTAssertEqual(profile.agentDictionary["has_video_url"] as? Bool, true)
    }

    @MainActor
    func testShortShareMetadataUsesOfficialShortURIWithoutYuanbaoSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeChatChannelsMockURLProtocol.self]
        let requestBox = WeChatChannelsRequestBox()
        WeChatChannelsMockURLProtocol.handler = { request in
            requestBox.requests.append(request)
            let body = try XCTUnwrap(WeChatChannelsMockURLProtocol.jsonBody(from: request))
            XCTAssertEqual(body["shortUri"] as? String, "AZJc5LQAbb")
            let baseReq = body["baseReq"] as? [String: Any]
            XCTAssertEqual(baseReq?["generalToken"] as? String, "")
            return try WeChatChannelsMockURLProtocol.jsonResponse([
                "errCode": 0,
                "data": [
                    "authorInfo": [
                        "nickname": "Short URI Author"
                    ],
                    "feedInfo": [
                        "description": "Short URI metadata",
                        "coverUrl": "https://finder.video.qq.com/cover.jpg",
                        "likeCountFmt": "963"
                    ],
                    "sceneInfo": [
                        "dynamicExportId": "export/dynamic-id"
                    ]
                ]
            ])
        }
        defer {
            WeChatChannelsMockURLProtocol.handler = nil
        }

        let client = WeChatChannelsURLSessionAPIClient(
            session: URLSession(configuration: configuration)
        )
        let profile = try await client.fetchProfile(
            sourceURL: "https://weixin.qq.com/sph/AZJc5LQAbb",
            credential: nil
        )

        XCTAssertEqual(requestBox.requests.count, 1)
        XCTAssertEqual(profile.shortID, "AZJc5LQAbb")
        XCTAssertEqual(profile.exportID, "export/dynamic-id")
        XCTAssertEqual(profile.resolutionPath, "short_uri")
        XCTAssertEqual(profile.author, "Short URI Author")
        XCTAssertEqual(profile.description, "Short URI metadata")
        XCTAssertEqual(profile.likeCountText, "963")
        XCTAssertNil(profile.bestVideoURL)
    }

    @MainActor
    func testShortShareUsesYuanbaoSessionToRecoverDownloadableFeedURL() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeChatChannelsMockURLProtocol.self]
        let requestBox = WeChatChannelsRequestBox()
        WeChatChannelsMockURLProtocol.handler = { request in
            requestBox.requests.append(request)
            let host = try XCTUnwrap(request.url?.host)
            let body = try XCTUnwrap(WeChatChannelsMockURLProtocol.jsonBody(from: request))

            if host == "channels.weixin.qq.com", body["shortUri"] as? String == "AZJc5LQAbb" {
                return try WeChatChannelsMockURLProtocol.jsonResponse([
                    "errCode": 0,
                    "data": [
                        "authorInfo": [
                            "nickname": "Short URI Author"
                        ],
                        "feedInfo": [
                            "description": "Short URI metadata"
                        ],
                        "sceneInfo": [
                            "dynamicExportId": "export/dynamic-id"
                        ]
                    ]
                ])
            }

            if host == "yuanbao.tencent.com" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session-cookie")
                XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "session-ua")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test-Header"), "extra")
                XCTAssertEqual(body["type"] as? String, "video_channel_url")
                XCTAssertEqual(body["url"] as? String, "https://weixin.qq.com/sph/AZJc5LQAbb")
                return try WeChatChannelsMockURLProtocol.jsonResponse(
                    [
                        "code": 0,
                        "data": [
                            "playable_url": "https://channels.weixin.qq.com/finder-preview/pages/feed?token=general-token&eid=export-id",
                            "author": "Parsed Author",
                            "author_icon_url": "https://example.com/parsed-avatar.jpg",
                            "desc": "Parsed description",
                            "cover_url": "https://example.com/parsed-cover.jpg"
                        ]
                    ],
                    url: request.url!
                )
            }

            if host == "channels.weixin.qq.com", body["exportId"] as? String == "export-id" {
                let baseReq = body["baseReq"] as? [String: Any]
                XCTAssertEqual(baseReq?["generalToken"] as? String, "general-token")
                return try WeChatChannelsMockURLProtocol.jsonResponse([
                    "errCode": 0,
                    "data": [
                        "feedInfo": [
                            "h264VideoInfo": [
                                "videoUrl": "https://finder.video.qq.com/recovered.mp4"
                            ]
                        ]
                    ]
                ])
            }

            XCTFail("Unexpected request: \(request)")
            return try WeChatChannelsMockURLProtocol.jsonResponse([:])
        }
        defer {
            WeChatChannelsMockURLProtocol.handler = nil
        }

        let client = WeChatChannelsURLSessionAPIClient(
            session: URLSession(configuration: configuration)
        )
        let profile = try await client.fetchProfile(
            sourceURL: "https://weixin.qq.com/sph/AZJc5LQAbb",
            credential: WeChatChannelsCredential(
                cookie: "session-cookie",
                userAgent: "session-ua",
                extraHeaders: ["X-Test-Header": "extra"],
                savedAt: Date()
            )
        )

        XCTAssertEqual(requestBox.requests.count, 3)
        XCTAssertEqual(profile.resolutionPath, "yuanbao_feed")
        XCTAssertEqual(profile.exportID, "export-id")
        XCTAssertEqual(profile.generalToken, "general-token")
        XCTAssertEqual(profile.bestVideoURL, "https://finder.video.qq.com/recovered.mp4")
        XCTAssertEqual(profile.author, "Parsed Author")
        XCTAssertEqual(profile.description, "Parsed description")
        XCTAssertEqual(profile.coverURL, "https://example.com/parsed-cover.jpg")
        XCTAssertEqual(profile.authorAvatarURL, "https://example.com/parsed-avatar.jpg")
    }

    @MainActor
    func testDownloadShortShareDegradesWithoutYuanbaoSessionWhenShortURIHasNoVideoURL() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wechat-channels-short-uri-no-video-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WeChatChannelsGearStore(
            database: WeChatChannelsFileDatabase(rootURL: root),
            credentialStore: WeChatChannelsMemoryCredentialStore(),
            client: WeChatChannelsMockClient(
                profile: WeChatChannelsVideoProfile(
                    sourceURL: "https://weixin.qq.com/sph/AZJc5LQAbb",
                    shortID: "AZJc5LQAbb",
                    exportID: "export/dynamic-id",
                    generalToken: nil,
                    resolutionPath: "short_uri",
                    author: "Short URI Author",
                    authorAvatarURL: nil,
                    description: "Short URI metadata",
                    coverURL: nil,
                    createdAt: nil,
                    videoURL: nil,
                    h264VideoURL: nil,
                    h265VideoURL: nil,
                    originVideoURL: nil,
                    likeCountText: nil,
                    forwardCountText: nil,
                    commentCountText: nil
                )
            ),
            downloader: WeChatChannelsMockDownloader()
        )

        let payload = await store.runAgentAction(
            capabilityID: "wechat_channels.download",
            args: ["url": "https://weixin.qq.com/sph/AZJc5LQAbb"]
        )

        XCTAssertEqual(payload["status"] as? String, "degraded")
        XCTAssertEqual(payload["code"] as? String, "no_video_url")
        XCTAssertEqual(payload["fallback_attempted"] as? Bool, false)
        let profile = try XCTUnwrap(payload["profile"] as? [String: Any])
        XCTAssertEqual(profile["resolution_path"] as? String, "short_uri")
        XCTAssertEqual(store.tasks.first?.status, .degraded)
        XCTAssertEqual(store.tasks.first?.errorCode, "no_video_url")
    }

    @MainActor
    func testMetadataFailsStructurallyWithoutSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wechat-channels-auth-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WeChatChannelsGearStore(
            database: WeChatChannelsFileDatabase(rootURL: root),
            credentialStore: WeChatChannelsMemoryCredentialStore(),
            client: WeChatChannelsMockClient(requiresCredential: true),
            downloader: WeChatChannelsMockDownloader()
        )

        let payload = await store.runAgentAction(
            capabilityID: "wechat_channels.metadata",
            args: ["url": "https://weixin.qq.com/sph/AZJc5LQAbb"]
        )

        XCTAssertEqual(payload["gear_id"] as? String, WeChatChannelsGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "wechat_channels.metadata")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertEqual(payload["code"] as? String, "auth_missing")
        XCTAssertEqual(payload["fallback_attempted"] as? Bool, false)
    }

    @MainActor
    func testDownloadDegradesWhenTencentReturnsNoVideoURL() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wechat-channels-no-video-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let credentialStore = WeChatChannelsMemoryCredentialStore()
        let store = WeChatChannelsGearStore(
            database: WeChatChannelsFileDatabase(rootURL: root),
            credentialStore: credentialStore,
            client: WeChatChannelsMockClient(
                profile: WeChatChannelsVideoProfile(
                    sourceURL: "https://weixin.qq.com/sph/demo",
                    shortID: "demo",
                    exportID: "export",
                    generalToken: "token",
                    author: "Demo",
                    authorAvatarURL: nil,
                    description: "No URL profile",
                    coverURL: nil,
                    createdAt: nil,
                    videoURL: nil,
                    h264VideoURL: nil,
                    h265VideoURL: nil,
                    originVideoURL: nil,
                    likeCountText: nil,
                    forwardCountText: nil,
                    commentCountText: nil
                )
            ),
            downloader: WeChatChannelsMockDownloader()
        )
        try store.saveSession(cookie: "cookie", userAgent: "ua")

        let payload = await store.runAgentAction(
            capabilityID: "wechat_channels.download",
            args: ["url": "https://weixin.qq.com/sph/demo"]
        )

        XCTAssertEqual(payload["status"] as? String, "degraded")
        XCTAssertEqual(payload["code"] as? String, "no_video_url")
        XCTAssertEqual(payload["fallback_attempted"] as? Bool, false)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.status, .degraded)
        XCTAssertEqual(store.tasks.first?.errorCode, "no_video_url")
    }

    @MainActor
    func testDownloadWritesArtifactAndPersistsTask() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wechat-channels-download-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let credentialStore = WeChatChannelsMemoryCredentialStore()
        let store = WeChatChannelsGearStore(
            database: WeChatChannelsFileDatabase(rootURL: root),
            credentialStore: credentialStore,
            client: WeChatChannelsMockClient(
                profile: WeChatChannelsVideoProfile(
                    sourceURL: "https://weixin.qq.com/sph/demo",
                    shortID: "demo",
                    exportID: "export",
                    generalToken: "token",
                    author: "Demo Author",
                    authorAvatarURL: nil,
                    description: "Successful download",
                    coverURL: nil,
                    createdAt: nil,
                    videoURL: nil,
                    h264VideoURL: "https://finder.video.qq.com/demo.mp4",
                    h265VideoURL: nil,
                    originVideoURL: nil,
                    likeCountText: nil,
                    forwardCountText: nil,
                    commentCountText: nil
                )
            ),
            downloader: WeChatChannelsMockDownloader()
        )
        try store.saveSession(cookie: "cookie", userAgent: "ua")

        let payload = await store.runAgentAction(
            capabilityID: "wechat_channels.download",
            args: [
                "url": "https://weixin.qq.com/sph/demo",
                "output_dir": output.path
            ]
        )

        XCTAssertEqual(payload["status"] as? String, "completed")
        XCTAssertEqual(payload["fallback_attempted"] as? Bool, false)
        let outputPaths = try XCTUnwrap(payload["output_paths"] as? [String])
        XCTAssertEqual(outputPaths.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPaths[0]))
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.status, .completed)
        XCTAssertEqual(store.tasks.first?.author, "Demo Author")

        let reloaded = WeChatChannelsFileDatabase(rootURL: root).loadTasks()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.status, .completed)
        XCTAssertEqual(reloaded.first?.outputPath, outputPaths[0])
    }
}

private struct WeChatChannelsMockClient: WeChatChannelsAPIClient {
    var requiresCredential = false
    var profile = WeChatChannelsVideoProfile(
        sourceURL: "https://weixin.qq.com/sph/demo",
        shortID: "demo",
        exportID: "export",
        generalToken: "token",
        author: "Demo",
        authorAvatarURL: nil,
        description: "Demo profile",
        coverURL: nil,
        createdAt: nil,
        videoURL: nil,
        h264VideoURL: "https://finder.video.qq.com/demo.mp4",
        h265VideoURL: nil,
        originVideoURL: nil,
        likeCountText: nil,
        forwardCountText: nil,
        commentCountText: nil
    )

    func fetchProfile(
        sourceURL: String,
        credential: WeChatChannelsCredential?
    ) async throws -> WeChatChannelsVideoProfile {
        if requiresCredential, credential?.isConfigured != true {
            throw WeChatChannelsError.authMissing
        }
        var copy = profile
        copy.sourceURL = sourceURL
        return copy
    }
}

private struct WeChatChannelsMockDownloader: WeChatChannelsMediaDownloading {
    func download(
        from url: URL,
        outputDirectory: URL,
        suggestedTitle: String,
        userAgent: String
    ) async throws -> WeChatChannelsDownloadedFile {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let path = outputDirectory.appendingPathComponent("mock-video.mp4")
        try Data("mock-video".utf8).write(to: path)
        return WeChatChannelsDownloadedFile(
            path: path.path,
            byteCount: 10,
            mimeType: "video/mp4"
        )
    }
}

private final class WeChatChannelsRequestBox {
    var requests: [URLRequest] = []
}

private final class WeChatChannelsMockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "channels.weixin.qq.com"
            || request.url?.host == "yuanbao.tencent.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: WeChatChannelsError.networkFailed("No mock handler configured."))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func jsonResponse(
        _ object: [String: Any],
        statusCode: Int = 200,
        url: URL = URL(string: "https://channels.weixin.qq.com/finder-preview/api/feed/get_feed_info")!
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }

    static func jsonBody(from request: URLRequest) -> [String: Any]? {
        let data = request.httpBody ?? request.httpBodyStream.flatMap { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: bufferSize)
                if count <= 0 {
                    break
                }
                data.append(buffer, count: count)
            }
            return data
        }
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }
}
