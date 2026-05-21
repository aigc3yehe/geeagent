import XCTest
@testable import GeeAgentMac

final class SmartYTMediaGearTests: XCTestCase {
    func testSmartYTManifestDeclaresDependenciesAndCapabilities() throws {
        let data = Data("""
        {
          "schema": "gee.gear.v1",
          "id": "smartyt.media",
          "name": "SmartYT Media",
          "description": "URL media sniffer.",
          "developer": "Gee",
          "version": "0.1.0",
          "category": "Media",
          "kind": "atmosphere",
          "display_mode": "full_canvas",
          "entry": { "type": "native", "native_id": "smartyt.media" },
          "dependencies": {
            "install_strategy": "on_open",
            "items": [
              {
                "id": "yt-dlp",
                "kind": "binary",
                "scope": "global",
                "required": true,
                "detect": { "command": "yt-dlp", "args": ["--version"] },
                "installer": { "type": "recipe", "id": "brew.install.yt-dlp" }
              }
            ]
          },
          "agent": {
            "enabled": true,
            "capabilities": [
              {
                "id": "smartyt.download",
                "title": "Download URL media",
                "description": "Queue a media download."
              }
            ]
          }
        }
        """.utf8)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, SmartYTMediaGearDescriptor.gearID)
        XCTAssertEqual(manifest.dependencies?.items.first?.id, "yt-dlp")
        XCTAssertEqual(manifest.dependencies?.items.first?.installer?.id, "brew.install.yt-dlp")
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(manifest.agent?.capabilities.first?.id, "smartyt.download")
    }

    func testYTDLPMetadataParsingKeepsSmartYTFields() throws {
        let stdout = """
        {"title":"Demo Video","extractor_key":"Youtube","uploader":"Gee","duration":187,"webpage_url":"https://example.com/watch?v=1","thumbnail":"https://example.com/t.jpg","ext":"mp4","formats":[{"format_id":"18"},{"format_id":"22"}]}
        """

        let info = try SmartYTMediaInfo.parse(from: stdout, fallbackURL: "https://fallback.example/video")

        XCTAssertEqual(info.title, "Demo Video")
        XCTAssertEqual(info.platform, "Youtube")
        XCTAssertEqual(info.uploader, "Gee")
        XCTAssertEqual(info.durationText, "3:07")
        XCTAssertEqual(info.extensionHint, "mp4")
        XCTAssertEqual(info.formatCount, 2)
        XCTAssertEqual(info.webpageURL?.absoluteString, "https://example.com/watch?v=1")
    }

    func testYTDLPSearchCandidateParsingKeepsStableCandidateShape() throws {
        let stdout = """
        {"id":"abc123","title":"Evening walk","extractor_key":"Youtube","uploader":"Gee","duration":38.2,"webpage_url":"https://youtube.com/watch?v=abc123","thumbnail":"https://example.com/t.jpg","width":1920,"height":1080,"upload_date":"20260501"}
        """

        let candidates = SmartYTSearchCandidate.parseYTDLPJSONLines(
            stdout,
            platform: "youtube",
            taskID: "smartyt-search-test",
            startingIndex: 0
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.id, "cand-001")
        XCTAssertEqual(candidates.first?.platform, "youtube")
        XCTAssertEqual(candidates.first?.title, "Evening walk")
        XCTAssertEqual(candidates.first?.sourceURL, "https://youtube.com/watch?v=abc123")
        XCTAssertEqual(candidates.first?.orientation, "horizontal")
        XCTAssertEqual(candidates.first?.publishedAt, "2026-05-01T00:00:00Z")
    }

    @MainActor
    func testDirectImageURLsDefaultToImageDownloads() throws {
        let extensionURL = "https://pbs.twimg.com/media/HHFx7HsbsAEQHuH.jpg?name=large"
        let formatURL = "https://pbs.twimg.com/media/HHFx7HsbsAEQHuH?format=jpg&name=large"
        let videoURL = "https://video.twimg.com/amplify_video/demo/vid/avc1/demo.mp4"

        XCTAssertTrue(SmartYTMediaGearStore.isDirectImageURL(extensionURL))
        XCTAssertTrue(SmartYTMediaGearStore.isDirectImageURL(formatURL))
        XCTAssertFalse(SmartYTMediaGearStore.isDirectImageURL(videoURL))
        XCTAssertEqual(SmartYTMediaGearStore.defaultDownloadKind(for: extensionURL), .image)
        XCTAssertEqual(SmartYTMediaGearStore.defaultDownloadKind(for: formatURL), .image)
        XCTAssertEqual(SmartYTMediaGearStore.defaultDownloadKind(for: videoURL), .video)
    }

    func testSmartYTDownloadKindIncludesImage() throws {
        XCTAssertEqual(SmartYTDownloadKind(rawValue: "image"), .image)
        XCTAssertTrue(SmartYTDownloadKind.allCases.contains(.image))
        XCTAssertEqual(SmartYTDownloadKind.image.title, "Image")
    }

    func testJSONCookieExportConvertsToNetscapeFormat() throws {
        let json = Data("""
        [
          {
            "domain": ".youtube.com",
            "expirationDate": 1790000000.4,
            "hostOnly": false,
            "httpOnly": true,
            "name": "SID",
            "path": "/",
            "secure": true,
            "session": false,
            "value": "abc123"
          }
        ]
        """.utf8)

        let converted = try SmartYTYTDLPCookieFile.normalizedNetscapeData(from: json)
        let text = try XCTUnwrap(String(data: converted, encoding: .utf8))

        XCTAssertTrue(text.hasPrefix("# Netscape HTTP Cookie File"))
        XCTAssertTrue(text.contains("#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t1790000000\tSID\tabc123"))
    }

    @MainActor
    func testDefaultSmartYTArtifactRootUsesDownloadsFolder() throws {
        let root = try SmartYTMediaGearStore.defaultArtifactRoot()

        XCTAssertEqual(root.lastPathComponent, "SmartYT")
        XCTAssertTrue(root.deletingLastPathComponent().path.hasSuffix("/Downloads"))
    }

    @MainActor
    func testYTDLPMaintenanceRunsBrewUpgradeAtMostOncePerDay() async throws {
        let runner = RecordingSmartYTRunner(responses: [
            "yt-dlp --version": [
                GearCommandResult(exitCode: 0, stdout: "2026.03.17\n", stderr: ""),
                GearCommandResult(exitCode: 0, stdout: "2026.03.17\n", stderr: "")
            ],
            "command -v brew": [
                GearCommandResult(exitCode: 0, stdout: "/opt/homebrew/bin/brew\n", stderr: "")
            ],
            "brew upgrade yt-dlp": [
                GearCommandResult(exitCode: 0, stdout: "Warning: yt-dlp 2026.03.17 already installed\n", stderr: "")
            ],
            "yt-dlp --dump-single-json --no-warnings --skip-download https://youtube.com/watch?v=smartyt-maintenance-test": [
                GearCommandResult(
                    exitCode: 0,
                    stdout: #"{"title":"Maintenance","extractor_key":"Youtube","webpage_url":"https://youtube.com/watch?v=smartyt-maintenance-test","duration":12}"#,
                    stderr: ""
                ),
                GearCommandResult(
                    exitCode: 0,
                    stdout: #"{"title":"Maintenance","extractor_key":"Youtube","webpage_url":"https://youtube.com/watch?v=smartyt-maintenance-test","duration":12}"#,
                    stderr: ""
                )
            ]
        ])
        let suiteName = "smartyt-maintenance-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: try isolatedSmartYTDataRoot())
        store.urlString = "https://youtube.com/watch?v=smartyt-maintenance-test"

        await store.sniffCurrentURL()
        await store.sniffCurrentURL()

        let commands = await runner.commandHistory()
        XCTAssertEqual(commands.filter { $0 == "brew upgrade yt-dlp" }.count, 1)
    }

    @MainActor
    func testConcurrentYTDLPMaintenanceUsesSingleBrewUpgrade() async throws {
        let runner = RecordingSmartYTRunner(
            responses: [
                "yt-dlp --version": [
                    GearCommandResult(exitCode: 0, stdout: "2026.03.17\n", stderr: ""),
                    GearCommandResult(exitCode: 0, stdout: "2026.03.17_2\n", stderr: "")
                ],
                "command -v brew": [
                    GearCommandResult(exitCode: 0, stdout: "/opt/homebrew/bin/brew\n", stderr: ""),
                    GearCommandResult(exitCode: 0, stdout: "/opt/homebrew/bin/brew\n", stderr: "")
                ],
                "brew upgrade yt-dlp": [
                    GearCommandResult(exitCode: 0, stdout: "Upgraded yt-dlp\n", stderr: "")
                ],
                "yt-dlp --dump-single-json --no-warnings --skip-download https://youtube.com/watch?v=smartyt-concurrent-maintenance-test": [
                    GearCommandResult(
                        exitCode: 0,
                        stdout: #"{"title":"Concurrent Maintenance","extractor_key":"Youtube","webpage_url":"https://youtube.com/watch?v=smartyt-concurrent-maintenance-test","duration":12}"#,
                        stderr: ""
                    ),
                    GearCommandResult(
                        exitCode: 0,
                        stdout: #"{"title":"Concurrent Maintenance","extractor_key":"Youtube","webpage_url":"https://youtube.com/watch?v=smartyt-concurrent-maintenance-test","duration":12}"#,
                        stderr: ""
                    )
                ]
            ],
            delays: [
                "brew upgrade yt-dlp": 250_000_000
            ]
        )
        let suiteName = "smartyt-concurrent-maintenance-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: try isolatedSmartYTDataRoot())
        store.urlString = "https://youtube.com/watch?v=smartyt-concurrent-maintenance-test"

        async let first: Void = store.sniffCurrentURL()
        try await Task.sleep(nanoseconds: 50_000_000)
        async let second: Void = store.sniffCurrentURL()
        _ = await (first, second)

        let commands = await runner.commandHistory()
        XCTAssertEqual(commands.filter { $0 == "brew upgrade yt-dlp" }.count, 1)
        XCTAssertEqual(commands.filter { $0.hasPrefix("yt-dlp --dump-single-json") }.count, 2)
    }

    @MainActor
    func testYTDLPMaintenanceContinuesAfterHomebrewLinkWarningWhenYTDLPExists() async throws {
        let brewOutput = """
        Error: The `brew link` step did not complete successfully
        Could not symlink bin/yt-dlp
        Target /opt/homebrew/bin/yt-dlp
        already exists.
        """
        let runner = RecordingSmartYTRunner(responses: [
            "yt-dlp --version": [
                GearCommandResult(exitCode: 0, stdout: "2026.03.17\n", stderr: ""),
                GearCommandResult(exitCode: 0, stdout: "2026.03.17\n", stderr: ""),
                GearCommandResult(exitCode: 0, stdout: "2026.03.17\n", stderr: "")
            ],
            "command -v brew": [
                GearCommandResult(exitCode: 0, stdout: "/opt/homebrew/bin/brew\n", stderr: "")
            ],
            "brew upgrade yt-dlp": [
                GearCommandResult(exitCode: 1, stdout: brewOutput, stderr: "")
            ],
            "yt-dlp --dump-single-json --no-warnings --skip-download https://youtube.com/watch?v=smartyt-link-warning-test": [
                GearCommandResult(
                    exitCode: 0,
                    stdout: #"{"title":"Link Warning","extractor_key":"Youtube","webpage_url":"https://youtube.com/watch?v=smartyt-link-warning-test","duration":12}"#,
                    stderr: ""
                )
            ]
        ])
        let suiteName = "smartyt-maintenance-link-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: try isolatedSmartYTDataRoot())
        store.urlString = "https://youtube.com/watch?v=smartyt-link-warning-test"

        await store.sniffCurrentURL()

        let commands = await runner.commandHistory()
        XCTAssertTrue(commands.contains("yt-dlp --dump-single-json --no-warnings --skip-download https://youtube.com/watch?v=smartyt-link-warning-test"))
        XCTAssertNotNil(defaults.object(forKey: "geeagent.smartyt.ytdlp.lastMaintenanceAt"))
    }

    @MainActor
    func testYouTubeBotVerificationReturnsStructuredRecovery() async throws {
        let botOutput = """
        [youtube] Extracting URL: https://www.youtube.com/watch?v=smartyt-bot-test
        ERROR: [youtube] smartyt-bot-test: Sign in to confirm you’re not a bot. Use --cookies-from-browser or --cookies for the authentication.
        """
        let runner = RecordingSmartYTRunner(responses: [
            "yt-dlp --dump-single-json --no-warnings --skip-download https://www.youtube.com/watch?v=smartyt-bot-test": [
                GearCommandResult(exitCode: 1, stdout: "", stderr: botOutput)
            ],
            "yt-dlp -f bv*+ba/best --newline --merge-output-format mp4 --no-playlist -o /tmp/smartyt-bot-test/video.%(ext)s https://www.youtube.com/watch?v=smartyt-bot-test": [
                GearCommandResult(exitCode: 1, stdout: "", stderr: botOutput)
            ]
        ])
        let suiteName = "smartyt-bot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Date(), forKey: "geeagent.smartyt.ytdlp.lastMaintenanceAt")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: try isolatedSmartYTDataRoot())

        let payload = await store.runImmediateAgentDownload(
            url: "https://www.youtube.com/watch?v=smartyt-bot-test",
            downloadKind: .video,
            outputDirectory: "/tmp/smartyt-bot-test"
        )

        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertEqual(payload["error_code"] as? String, "gear.smartyt.youtube_auth_required")
        XCTAssertTrue((payload["recovery"] as? String)?.contains("cookies") == true)
    }

    @MainActor
    func testSavedCookieFileIsCopiedToTemporaryCookieJarForYTDLP() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartyt-cookie-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cookieFile = tempRoot.appendingPathComponent("cookies.txt")
        let originalCookies = "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t1790000000\tSID\tabc123\n"
        try originalCookies.write(to: cookieFile, atomically: true, encoding: .utf8)

        let runner = RecordingSmartYTRunner(responses: [
            "yt-dlp --cookies * --dump-single-json --no-warnings --skip-download https://youtube.com/watch?v=smartyt-cookie-test": [
                GearCommandResult(
                    exitCode: 0,
                    stdout: #"{"title":"Cookie Video","extractor_key":"Youtube","webpage_url":"https://youtube.com/watch?v=smartyt-cookie-test","duration":18}"#,
                    stderr: ""
                )
            ]
        ])
        let suiteName = "smartyt-cookie-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Date(), forKey: "geeagent.smartyt.ytdlp.lastMaintenanceAt")
        defaults.set(cookieFile.path, forKey: SmartYTMediaGearStore.cookieFileDefaultsKey)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: try isolatedSmartYTDataRoot())
        store.urlString = "https://youtube.com/watch?v=smartyt-cookie-test"

        await store.sniffCurrentURL()

        let commands = await runner.commandHistory()
        let ytdlpCommand = try XCTUnwrap(commands.first { $0.hasPrefix("yt-dlp --cookies ") })
        let parts = ytdlpCommand.split(separator: " ").map(String.init)
        let cookieArgumentIndex = try XCTUnwrap(parts.firstIndex(of: "--cookies").map { parts.index(after: $0) })
        let temporaryCookiePath = parts[cookieArgumentIndex]
        XCTAssertNotEqual(temporaryCookiePath, cookieFile.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryCookiePath))
        XCTAssertEqual(try String(contentsOf: cookieFile, encoding: .utf8), originalCookies)
    }

    @MainActor
    func testExpiredSavedCookieRefreshesFromChromeAndRetriesYTDLP() async throws {
        let botOutput = """
        [youtube] Extracting URL: https://youtube.com/watch?v=smartyt-refresh-test
        WARNING: [youtube] The provided YouTube account cookies are no longer valid.
        ERROR: [youtube] smartyt-refresh-test: Sign in to confirm you’re not a bot. Use --cookies-from-browser or --cookies for the authentication.
        """
        let runner = RecordingSmartYTRunner(responses: [
            "yt-dlp --cookies * --dump-single-json --no-warnings --skip-download https://youtube.com/watch?v=smartyt-refresh-test": [
                GearCommandResult(exitCode: 1, stdout: "", stderr: botOutput),
                GearCommandResult(
                    exitCode: 0,
                    stdout: #"{"title":"Refreshed Cookie Video","extractor_key":"Youtube","webpage_url":"https://youtube.com/watch?v=smartyt-refresh-test","duration":24}"#,
                    stderr: ""
                )
            ],
            "yt-dlp --cookies-from-browser chrome --cookies * --no-warnings --skip-download --simulate https://youtube.com/watch?v=smartyt-refresh-test": [
                GearCommandResult(exitCode: 0, stdout: "refreshed\n", stderr: "")
            ]
        ])
        let suiteName = "smartyt-refresh-cookie-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Date(), forKey: "geeagent.smartyt.ytdlp.lastMaintenanceAt")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let dataRoot = try isolatedSmartYTDataRoot()
        let cookieFile = dataRoot
            .appendingPathComponent("cookies", isDirectory: true)
            .appendingPathComponent("yt-dlp-cookies.txt")
        try FileManager.default.createDirectory(at: cookieFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t1790000000\tSID\told\n".write(
            to: cookieFile,
            atomically: true,
            encoding: .utf8
        )
        defaults.set(cookieFile.path, forKey: SmartYTMediaGearStore.cookieFileDefaultsKey)
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: dataRoot)
        store.urlString = "https://youtube.com/watch?v=smartyt-refresh-test"

        await store.sniffCurrentURL()

        XCTAssertEqual(store.mediaInfo?.title, "Refreshed Cookie Video")
        XCTAssertEqual(defaults.string(forKey: SmartYTMediaGearStore.cookieFileDefaultsKey), cookieFile.path)
        let commands = await runner.commandHistory()
        XCTAssertEqual(commands.filter { $0.hasPrefix("yt-dlp --cookies ") }.count, 2)
        XCTAssertTrue(commands.contains { $0.hasPrefix("yt-dlp --cookies-from-browser chrome --cookies ") })
    }

    @MainActor
    func testExplicitCookiePathDoesNotAutoRefreshFromChrome() async throws {
        let botOutput = """
        ERROR: [youtube] explicit-cookie-test: Sign in to confirm you’re not a bot. Use --cookies-from-browser or --cookies for the authentication.
        """
        let runner = RecordingSmartYTRunner(responses: [
            "yt-dlp --cookies * --dump-single-json --no-warnings --skip-download https://youtube.com/watch?v=explicit-cookie-test": [
                GearCommandResult(exitCode: 1, stdout: "", stderr: botOutput)
            ],
            "yt-dlp --cookies * -f bv*+ba/best --newline --merge-output-format mp4 --no-playlist -o /tmp/smartyt-explicit-cookie-output/video.%(ext)s https://youtube.com/watch?v=explicit-cookie-test": [
                GearCommandResult(exitCode: 1, stdout: "", stderr: botOutput)
            ]
        ])
        let suiteName = "smartyt-explicit-cookie-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Date(), forKey: "geeagent.smartyt.ytdlp.lastMaintenanceAt")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let dataRoot = try isolatedSmartYTDataRoot()
        let explicitCookieFile = dataRoot.appendingPathComponent("external-cookies.txt")
        try "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t1790000000\tSID\texplicit\n".write(
            to: explicitCookieFile,
            atomically: true,
            encoding: .utf8
        )
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: dataRoot)

        let payload = await store.runImmediateAgentDownload(
            url: "https://youtube.com/watch?v=explicit-cookie-test",
            downloadKind: .video,
            outputDirectory: "/tmp/smartyt-explicit-cookie-output",
            cookieFilePath: explicitCookieFile.path
        )

        XCTAssertEqual(payload["status"] as? String, "failed")
        let commands = await runner.commandHistory()
        XCTAssertFalse(commands.contains { $0.contains("--cookies-from-browser chrome") })
    }

    @MainActor
    func testMissingSavedCookieFileReturnsStructuredFailure() async throws {
        let missingPath = "/tmp/smartyt-missing-\(UUID().uuidString)-cookies.txt"
        let runner = RecordingSmartYTRunner(responses: [:])
        let suiteName = "smartyt-missing-cookie-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Date(), forKey: "geeagent.smartyt.ytdlp.lastMaintenanceAt")
        defaults.set(missingPath, forKey: SmartYTMediaGearStore.cookieFileDefaultsKey)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: try isolatedSmartYTDataRoot())

        let payload = await store.runImmediateAgentDownload(
            url: "https://www.youtube.com/watch?v=smartyt-missing-cookie-test",
            downloadKind: .video,
            outputDirectory: "/tmp/smartyt-missing-cookie-output"
        )

        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertEqual(payload["error_code"] as? String, "gear.smartyt.cookie_file_missing")
        XCTAssertTrue((payload["recovery"] as? String)?.contains("Choose and save") == true)
        let commands = await runner.commandHistory()
        XCTAssertFalse(commands.contains { $0.hasPrefix("yt-dlp ") })
    }

    @MainActor
    func testExternalJSONCookieFileReturnsStructuredFailure() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartyt-json-cookie-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cookieFile = tempRoot.appendingPathComponent("cookies.json")
        try #"[{"domain":".youtube.com","name":"SID","value":"abc123"}]"#.write(
            to: cookieFile,
            atomically: true,
            encoding: .utf8
        )

        let runner = RecordingSmartYTRunner(responses: [:])
        let suiteName = "smartyt-json-cookie-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Date(), forKey: "geeagent.smartyt.ytdlp.lastMaintenanceAt")
        defaults.set(cookieFile.path, forKey: SmartYTMediaGearStore.cookieFileDefaultsKey)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: try isolatedSmartYTDataRoot())

        let payload = await store.runImmediateAgentDownload(
            url: "https://www.youtube.com/watch?v=smartyt-json-cookie-test",
            downloadKind: .video,
            outputDirectory: "/tmp/smartyt-json-cookie-output"
        )

        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertEqual(payload["error_code"] as? String, "gear.smartyt.cookie_file_invalid")
        let commands = await runner.commandHistory()
        XCTAssertFalse(commands.contains { $0.hasPrefix("yt-dlp ") })
    }

    @MainActor
    func testClearingExternalCookiePreferenceDoesNotDeleteOriginalFile() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartyt-clear-cookie-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let externalCookieFile = tempRoot.appendingPathComponent("original-cookies.txt")
        try "# Netscape HTTP Cookie File\n".write(to: externalCookieFile, atomically: true, encoding: .utf8)

        let suiteName = "smartyt-clear-cookie-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(externalCookieFile.path, forKey: SmartYTMediaGearStore.cookieFileDefaultsKey)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartYTMediaGearStore(defaults: defaults, dataRoot: try isolatedSmartYTDataRoot())

        store.clearCookieFile()

        XCTAssertTrue(FileManager.default.fileExists(atPath: externalCookieFile.path))
        XCTAssertNil(defaults.string(forKey: SmartYTMediaGearStore.cookieFileDefaultsKey))
    }

    @MainActor
    func testDownloadJobReportsStreamingProgress() async throws {
        let runner = StreamingSmartYTRunner(
            lines: [
                "Downloading webpage",
                "[download] Destination: /tmp/video.mp4",
                "[download] 25.0% of 10.00MiB at 1.00MiB/s ETA 00:07",
                "[Merger] Merging formats into \"/tmp/video.mp4\""
            ],
            finalResult: GearCommandResult(exitCode: 0, stdout: "", stderr: ""),
            lineDelayNanoseconds: 250_000_000
        )
        let suiteName = "smartyt-progress-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Date(), forKey: "geeagent.smartyt.ytdlp.lastMaintenanceAt")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: try isolatedSmartYTDataRoot())
        store.urlString = "https://youtube.com/watch?v=smartyt-progress-test"

        store.downloadCurrentURL(kind: .video)
        let jobID = try XCTUnwrap(store.selectedJobID)

        try await Task.sleep(nanoseconds: 650_000_000)

        let runningJob = try XCTUnwrap(store.jobs.first { $0.id == jobID })
        XCTAssertEqual(runningJob.status, .running)
        XCTAssertEqual(runningJob.progressLabel, "25.0% of 10.00MiB at 1.00MiB/s ETA 00:07")
        XCTAssertGreaterThanOrEqual(runningJob.normalizedProgressFraction ?? 0, 0.25)

        let runningTaskPayload = try XCTUnwrap(store.taskPayload(taskID: jobID)["task"] as? [String: Any])
        XCTAssertEqual(runningTaskPayload["can_cancel"] as? Bool, true)
        XCTAssertEqual(runningTaskPayload["progress_label"] as? String, "25.0% of 10.00MiB at 1.00MiB/s ETA 00:07")

        let completedJob = try await waitForJob(store, id: jobID) { $0.status == .completed }
        XCTAssertEqual(completedJob.progressLabel, "Download completed.")
        XCTAssertEqual(completedJob.normalizedProgressFraction, 1)
        XCTAssertEqual(completedJob.outputPaths.count, 1)
    }

    @MainActor
    func testCancellingRunningDownloadMarksJobCancelled() async throws {
        let runner = StreamingSmartYTRunner(
            lines: [
                "Downloading webpage",
                "[download] Destination: /tmp/video.mp4",
                "[download] 5.0% of 10.00MiB at 1.00MiB/s ETA 00:09",
                "[download] 10.0% of 10.00MiB at 1.00MiB/s ETA 00:08"
            ],
            finalResult: GearCommandResult(exitCode: 0, stdout: "", stderr: ""),
            lineDelayNanoseconds: 300_000_000
        )
        let suiteName = "smartyt-cancel-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Date(), forKey: "geeagent.smartyt.ytdlp.lastMaintenanceAt")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SmartYTMediaGearStore(runner: runner, defaults: defaults, dataRoot: try isolatedSmartYTDataRoot())
        store.urlString = "https://youtube.com/watch?v=smartyt-cancel-test"

        store.downloadCurrentURL(kind: .video)
        let jobID = try XCTUnwrap(store.selectedJobID)

        let startedJob = try await waitForJob(store, id: jobID) { $0.status == .running }
        XCTAssertTrue(startedJob.canCancel)

        try await Task.sleep(nanoseconds: 350_000_000)
        store.cancel(jobID: jobID)

        let cancelledJob = try await waitForJob(store, id: jobID) { $0.status == .cancelled }
        XCTAssertEqual(cancelledJob.progressLabel, "Cancelled")
        XCTAssertFalse(cancelledJob.canCancel)
        XCTAssertNil(cancelledJob.errorMessage)

        let taskPayload = try XCTUnwrap(store.taskPayload(taskID: jobID)["task"] as? [String: Any])
        XCTAssertEqual(taskPayload["state"] as? String, "cancelled")
        XCTAssertEqual(taskPayload["can_cancel"] as? Bool, false)
    }

    @MainActor
    func testDeletingJobRemovesPersistedRecordButKeepsRunningJobs() throws {
        let dataRoot = try isolatedSmartYTDataRoot()
        let artifactRoot = try isolatedSmartYTDataRoot()
        let completedArtifact = artifactRoot.appendingPathComponent("smartyt-delete-completed", isDirectory: true)
        try FileManager.default.createDirectory(at: completedArtifact, withIntermediateDirectories: true)
        let downloadedFile = completedArtifact.appendingPathComponent("video.mp4")
        try Data("video".utf8).write(to: downloadedFile)
        let completed = makeSmartYTJob(
            id: "smartyt-delete-completed",
            status: .completed,
            artifactDirectoryPath: completedArtifact.path,
            outputPaths: [downloadedFile.path]
        )
        let running = makeSmartYTJob(id: "smartyt-delete-running", status: .running)
        try writePersistedJob(completed, dataRoot: dataRoot)
        try writePersistedJob(running, dataRoot: dataRoot)

        let store = SmartYTMediaGearStore(
            runner: RecordingSmartYTRunner(responses: [:]),
            defaults: try XCTUnwrap(UserDefaults(suiteName: "smartyt-delete-\(UUID().uuidString)")),
            dataRoot: dataRoot
        )

        XCTAssertTrue(store.deleteJob(id: completed.id))
        XCTAssertFalse(store.jobs.contains { $0.id == completed.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("jobs/\(completed.id)").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadedFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: completedArtifact.path))

        XCTAssertFalse(store.deleteJob(id: running.id))
        XCTAssertTrue(store.jobs.contains { $0.id == running.id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("jobs/\(running.id)").path))
    }

    @MainActor
    func testDeletingCompletedAndFailedJobsKeepsActiveAndCancelledJobs() throws {
        let dataRoot = try isolatedSmartYTDataRoot()
        let artifactRoot = try isolatedSmartYTDataRoot()
        let completedArtifact = artifactRoot.appendingPathComponent("smartyt-bulk-completed", isDirectory: true)
        let failedArtifact = artifactRoot.appendingPathComponent("smartyt-bulk-failed", isDirectory: true)
        try FileManager.default.createDirectory(at: completedArtifact, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: failedArtifact, withIntermediateDirectories: true)
        let completedFile = completedArtifact.appendingPathComponent("video.mp4")
        let failedPartial = failedArtifact.appendingPathComponent("video.mp4.part")
        try Data("video".utf8).write(to: completedFile)
        try Data("partial".utf8).write(to: failedPartial)
        let completed = makeSmartYTJob(
            id: "smartyt-bulk-completed",
            status: .completed,
            artifactDirectoryPath: completedArtifact.path,
            outputPaths: [completedFile.path]
        )
        let failed = makeSmartYTJob(
            id: "smartyt-bulk-failed",
            status: .failed,
            artifactDirectoryPath: failedArtifact.path
        )
        let running = makeSmartYTJob(id: "smartyt-bulk-running", status: .running)
        let queued = makeSmartYTJob(id: "smartyt-bulk-queued", status: .queued)
        let cancelled = makeSmartYTJob(id: "smartyt-bulk-cancelled", status: .cancelled)
        for job in [completed, failed, running, queued, cancelled] {
            try writePersistedJob(job, dataRoot: dataRoot)
        }

        let store = SmartYTMediaGearStore(
            runner: RecordingSmartYTRunner(responses: [:]),
            defaults: try XCTUnwrap(UserDefaults(suiteName: "smartyt-bulk-delete-\(UUID().uuidString)")),
            dataRoot: dataRoot
        )

        XCTAssertEqual(store.deleteCompletedAndFailedJobs(), 2)

        let remainingIDs = Set(store.jobs.map(\.id))
        XCTAssertFalse(remainingIDs.contains(completed.id))
        XCTAssertFalse(remainingIDs.contains(failed.id))
        XCTAssertTrue(remainingIDs.contains(running.id))
        XCTAssertTrue(remainingIDs.contains(queued.id))
        XCTAssertTrue(remainingIDs.contains(cancelled.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("jobs/\(completed.id)").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("jobs/\(failed.id)").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: completedFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: completedArtifact.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedPartial.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedArtifact.path))
    }

    private func isolatedSmartYTDataRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartyt-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    @MainActor
    private func waitForJob(
        _ store: SmartYTMediaGearStore,
        id: String,
        until predicate: (SmartYTMediaJob) -> Bool
    ) async throws -> SmartYTMediaJob {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let job = store.jobs.first(where: { $0.id == id }), predicate(job) {
                return job
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for SmartYT job \(id)")
        return try XCTUnwrap(store.jobs.first(where: { $0.id == id }))
    }

    private func makeSmartYTJob(
        id: String,
        status: SmartYTJobStatus,
        artifactDirectoryPath: String? = nil,
        outputPaths: [String] = []
    ) -> SmartYTMediaJob {
        let now = Date()
        return SmartYTMediaJob(
            id: id,
            url: "https://youtube.com/watch?v=\(id)",
            action: .download,
            downloadKind: .video,
            status: status,
            title: id,
            createdAt: now,
            updatedAt: now,
            mediaInfo: nil,
            outputPaths: outputPaths,
            transcriptPath: nil,
            transcriptPreview: nil,
            artifactDirectoryPath: artifactDirectoryPath,
            progressFraction: nil,
            progressLabel: nil,
            log: "Fixture \(id)",
            errorMessage: status == .failed ? "fixture failure" : nil
        )
    }

    private func writePersistedJob(_ job: SmartYTMediaJob, dataRoot: URL) throws {
        let directory = dataRoot.appendingPathComponent("jobs/\(job.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(job)
        try data.write(to: directory.appendingPathComponent("job.json"), options: .atomic)
    }

}

private actor RecordingSmartYTRunner: GearCommandRunning {
    private var responses: [String: [GearCommandResult]]
    private var delays: [String: UInt64]
    private var commands: [String] = []

    init(responses: [String: [GearCommandResult]], delays: [String: UInt64] = [:]) {
        self.responses = responses
        self.delays = delays
    }

    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        let key = ([command] + arguments).joined(separator: " ")
        commands.append(key)
        let responseKey = responses[key] != nil ? key : responses.keys.first { Self.matchesWildcardPattern($0, value: key) }
        guard let responseKey, var queue = responses[responseKey], !queue.isEmpty else {
            return GearCommandResult(exitCode: 127, stdout: "", stderr: "missing fake response: \(key)")
        }
        if let delay = delays[responseKey] {
            try? await Task.sleep(nanoseconds: delay)
        }
        let result = queue.removeFirst()
        responses[responseKey] = queue
        return result
    }

    func commandHistory() -> [String] {
        commands
    }

    private static func matchesWildcardPattern(_ pattern: String, value: String) -> Bool {
        guard pattern.contains("*") else {
            return false
        }
        var remainder = value[...]
        for part in pattern.split(separator: "*", omittingEmptySubsequences: false) {
            guard !part.isEmpty else {
                continue
            }
            guard let range = remainder.range(of: part) else {
                return false
            }
            remainder = remainder[range.upperBound...]
        }
        return true
    }
}

private final class TestSmartYTCommandHandle: @unchecked Sendable, SmartYTCommandCancellable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }
}

private actor StreamingSmartYTRunner: SmartYTStreamingCommandRunning {
    private let lines: [String]
    private let finalResult: GearCommandResult
    private let lineDelayNanoseconds: UInt64
    private var commands: [String] = []

    init(
        lines: [String],
        finalResult: GearCommandResult,
        lineDelayNanoseconds: UInt64
    ) {
        self.lines = lines
        self.finalResult = finalResult
        self.lineDelayNanoseconds = lineDelayNanoseconds
    }

    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        let key = ([command] + arguments).joined(separator: " ")
        commands.append(key)
        return GearCommandResult(exitCode: 127, stdout: "", stderr: "unexpected non-streaming command: \(key)")
    }

    func runStreaming(
        _ command: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        onStart: @escaping @Sendable (any SmartYTCommandCancellable) -> Void,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> GearCommandResult {
        let key = ([command] + arguments).joined(separator: " ")
        commands.append(key)

        let handle = TestSmartYTCommandHandle()
        onStart(handle)

        for line in lines {
            if handle.isCancelled || Task.isCancelled {
                return GearCommandResult(exitCode: 130, stdout: "", stderr: "cancelled")
            }
            onLine(line)
            do {
                try await Task.sleep(nanoseconds: lineDelayNanoseconds)
            } catch {
                return GearCommandResult(exitCode: 130, stdout: "", stderr: "cancelled")
            }
        }

        if handle.isCancelled || Task.isCancelled {
            return GearCommandResult(exitCode: 130, stdout: "", stderr: "cancelled")
        }

        if finalResult.exitCode == 0 {
            createMockArtifact(arguments: arguments)
        }
        return finalResult
    }

    func commandHistory() -> [String] {
        commands
    }

    private func createMockArtifact(arguments: [String]) {
        guard let outputIndex = arguments.firstIndex(of: "-o") else {
            return
        }
        let templateIndex = arguments.index(after: outputIndex)
        guard arguments.indices.contains(templateIndex) else {
            return
        }
        let template = arguments[templateIndex]
        let ext = arguments.contains("--audio-format") ? "mp3" : "mp4"
        let outputPath = template.replacingOccurrences(of: "%(ext)s", with: ext)
        let outputURL = URL(fileURLWithPath: outputPath)
        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("demo".utf8).write(to: outputURL, options: .atomic)
    }
}
