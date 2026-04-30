import XCTest
@testable import GeeAgentMac

final class WeSpyReaderGearTests: XCTestCase {
    func testWeSpyReaderManifestDeclaresDependenciesAndCapabilities() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/wespy.reader/gear.json")
        let data = try Data(contentsOf: manifestURL)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, WeSpyReaderGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.type, "native")
        XCTAssertEqual(manifest.dependencies?.items.map(\.id), ["python3", "wespy-python"])
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(
            manifest.agent?.capabilities.map(\.id),
            ["wespy.fetch_article", "wespy.list_album", "wespy.fetch_album"]
        )
    }

    func testWeSpyReaderInputParserRecognizesHTTPAndAlbumURLs() {
        XCTAssertTrue(WeSpyReaderInputParser.isHTTPURL("https://mp.weixin.qq.com/s/demo"))
        XCTAssertTrue(WeSpyReaderInputParser.isHTTPURL("http://example.com/article"))
        XCTAssertFalse(WeSpyReaderInputParser.isHTTPURL("file:///tmp/article.html"))
        XCTAssertTrue(
            WeSpyReaderInputParser.isWeChatAlbumURL(
                "https://mp.weixin.qq.com/mp/appmsgalbum?__biz=abc&album_id=123"
            )
        )
    }

    @MainActor
    func testGearInvokeAcceptsTopLevelArgumentsFromHostDirectives() {
        let args = GeeHostToolRouter.normalizedGearInvokeArgs(from: [
            "intent": "gear.invoke",
            "gear_id": "wespy.reader",
            "capability_id": "wespy.fetch_album",
            "url": "https://mp.weixin.qq.com/mp/appmsgalbum?album_id=123",
            "input": [
                "url": "https://mp.weixin.qq.com/mp/appmsgalbum?album_id=456",
                "max_articles": 5
            ],
            "max_articles": 10,
            "export_markdown": true,
            "args": [
                "save_html": false
            ]
        ])

        XCTAssertEqual(args["url"] as? String, "https://mp.weixin.qq.com/mp/appmsgalbum?album_id=456")
        XCTAssertEqual(args["max_articles"] as? Int, 5)
        XCTAssertEqual(args["save_html"] as? Bool, false)
        XCTAssertEqual(args["export_markdown"] as? Bool, true)
        XCTAssertNil(args["gear_id"])
        XCTAssertNil(args["capability_id"])
    }

    func testWeSpyReaderFileDatabaseRoundTripsTaskRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wespy-reader-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = WeSpyReaderFileDatabase(rootURL: root)
        let now = Date()
        let task = WeSpyReaderTaskRecord(
            id: "wespy-test",
            kind: .article,
            url: "https://mp.weixin.qq.com/s/demo",
            maxArticles: 1,
            saveHTML: true,
            saveJSON: true,
            saveMarkdown: true,
            status: .completed,
            title: "Demo Article",
            author: "Gee",
            publishTime: "2026-04-27",
            articleCount: 1,
            outputDirectoryPath: try database.outputDirectory("wespy-test").path,
            taskDirectoryPath: try database.taskDirectory("wespy-test").path,
            files: ["/tmp/demo.md"],
            articles: [
                WeSpyReaderArticleSummary(
                    title: "Demo Article",
                    author: "Gee",
                    publishTime: "2026-04-27",
                    url: "https://mp.weixin.qq.com/s/demo",
                    msgid: nil,
                    createTime: nil
                )
            ],
            log: "Completed",
            errorMessage: nil,
            createdAt: now,
            updatedAt: now
        )

        try database.save(task)

        let loaded = try XCTUnwrap(database.loadTasks().first)
        XCTAssertEqual(loaded.id, task.id)
        XCTAssertEqual(loaded.title, "Demo Article")
        XCTAssertEqual(loaded.articles.first?.url, "https://mp.weixin.qq.com/s/demo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: loaded.taskURL.path))
    }

    @MainActor
    func testAgentActionRejectsInvalidURLBeforeRunningSidecar() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wespy-reader-invalid-url-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WeSpyReaderGearStore(
            database: WeSpyReaderFileDatabase(rootURL: root),
            runner: WeSpyReaderMockRunner()
        )

        let payload = await store.runAgentAction(
            capabilityID: "wespy.fetch_article",
            args: ["url": "not a url"]
        )

        XCTAssertEqual(payload["gear_id"] as? String, WeSpyReaderGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "wespy.fetch_article")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertNotNil(payload["error"] as? String)
        XCTAssertEqual(store.tasks.count, 1)
    }

    @MainActor
    func testMarkdownExportStaysInsideGearStorageAndIgnoresExternalFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wespy-reader-export-\(UUID().uuidString)", isDirectory: true)
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("wespy-reader-external-\(UUID().uuidString).md")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        let store = WeSpyReaderGearStore(
            database: WeSpyReaderFileDatabase(rootURL: root),
            runner: WeSpyReaderExportMockRunner(externalMarkdownURL: external)
        )

        let payload = await store.runAgentAction(
            capabilityID: "wespy.fetch_album",
            args: [
                "url": "https://mp.weixin.qq.com/mp/appmsgalbum?album_id=123",
                "max_articles": 1,
                "export_markdown": true
            ]
        )

        let exportedPath = try XCTUnwrap(payload["exported_markdown_path"] as? String)
        XCTAssertTrue(exportedPath.hasPrefix(root.path))
        XCTAssertFalse(exportedPath.contains("/Desktop/"))
        let exportedText = try String(contentsOfFile: exportedPath, encoding: .utf8)
        XCTAssertTrue(exportedText.contains("safe gear markdown"))
        XCTAssertFalse(exportedText.contains("external secret"))
    }

    @MainActor
    func testSingleArticlePayloadWithoutArticlesArrayStillCompletes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wespy-reader-single-article-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WeSpyReaderGearStore(
            database: WeSpyReaderFileDatabase(rootURL: root),
            runner: WeSpyReaderSingleArticleMockRunner()
        )

        let payload = await store.runAgentAction(
            capabilityID: "wespy.fetch_article",
            args: ["url": "https://mp.weixin.qq.com/s/demo"]
        )

        XCTAssertEqual(payload["status"] as? String, "completed")
        XCTAssertEqual(payload["article_count"] as? Int, 1)
        let articles = try XCTUnwrap(payload["articles"] as? [[String: Any]])
        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles.first?["title"] as? String, "Recovered Article")
        XCTAssertEqual(store.tasks.first?.status, .completed)
    }
}

private struct WeSpyReaderMockRunner: GearCommandRunning {
    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        GearCommandResult(exitCode: 127, stdout: "", stderr: "mock runner should not execute")
    }

    func run(_ command: String, arguments: [String], timeoutSeconds: TimeInterval?) async -> GearCommandResult {
        GearCommandResult(exitCode: 127, stdout: "", stderr: "mock runner should not execute")
    }
}

private struct WeSpyReaderExportMockRunner: GearCommandRunning {
    var externalMarkdownURL: URL

    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        await run(command, arguments: arguments, timeoutSeconds: nil)
    }

    func run(_ command: String, arguments: [String], timeoutSeconds: TimeInterval?) async -> GearCommandResult {
        guard let requestPath = arguments.last,
              let data = try? Data(contentsOf: URL(fileURLWithPath: requestPath)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let params = object["params"] as? [String: Any],
              let outputDirectoryPath = params["output_dir"] as? String
        else {
            return GearCommandResult(exitCode: 1, stdout: "", stderr: "bad mock request")
        }

        let outputDirectory = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        let safeMarkdownURL = outputDirectory.appendingPathComponent("article.md")
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try "safe gear markdown".write(to: safeMarkdownURL, atomically: true, encoding: .utf8)
            try "external secret".write(to: externalMarkdownURL, atomically: true, encoding: .utf8)
            let payload: [String: Any] = [
                "status": "completed",
                "action": "fetch_album",
                "url": params["url"] as? String ?? "",
                "output_dir": outputDirectoryPath,
                "files": [safeMarkdownURL.path, externalMarkdownURL.path],
                "title": "Mock Album",
                "article_count": 1,
                "articles": [
                    [
                        "title": "Mock Article",
                        "url": params["url"] as? String ?? ""
                    ]
                ],
                "log": "mock complete"
            ]
            let response = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            return GearCommandResult(
                exitCode: 0,
                stdout: String(data: response, encoding: .utf8) ?? "{}",
                stderr: ""
            )
        } catch {
            return GearCommandResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
        }
    }
}

private struct WeSpyReaderSingleArticleMockRunner: GearCommandRunning {
    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        await run(command, arguments: arguments, timeoutSeconds: nil)
    }

    func run(_ command: String, arguments: [String], timeoutSeconds: TimeInterval?) async -> GearCommandResult {
        guard let requestPath = arguments.last,
              let data = try? Data(contentsOf: URL(fileURLWithPath: requestPath)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let params = object["params"] as? [String: Any],
              let outputDirectoryPath = params["output_dir"] as? String
        else {
            return GearCommandResult(exitCode: 1, stdout: "", stderr: "bad mock request")
        }

        let outputDirectory = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        let markdownURL = outputDirectory.appendingPathComponent("article.md")
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try "single article body".write(to: markdownURL, atomically: true, encoding: .utf8)
            let payload: [String: Any] = [
                "status": "completed",
                "action": "fetch_article",
                "url": params["url"] as? String ?? "",
                "output_dir": outputDirectoryPath,
                "files": [markdownURL.path],
                "title": "Recovered Article",
                "author": "Gee",
                "article_count": 1,
                "log": "mock single article complete"
            ]
            let response = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            return GearCommandResult(
                exitCode: 0,
                stdout: String(data: response, encoding: .utf8) ?? "{}",
                stderr: ""
            )
        } catch {
            return GearCommandResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
        }
    }
}
