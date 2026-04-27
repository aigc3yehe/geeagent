import XCTest
@testable import GeeAgentMac

final class TwitterCaptureGearTests: XCTestCase {
    func testTwitterCaptureManifestDeclaresDependenciesAndCapabilities() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/twitter.capture/gear.json")
        let data = try Data(contentsOf: manifestURL)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, TwitterCaptureGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.type, "native")
        XCTAssertEqual(manifest.dependencies?.items.map(\.id), ["python3", "twikit-httpx"])
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(
            manifest.agent?.capabilities.map(\.id),
            ["twitter.fetch_tweet", "twitter.fetch_list", "twitter.fetch_user"]
        )
    }

    func testTwitterCaptureInputParserHandlesCommonTargets() {
        XCTAssertEqual(
            TwitterCaptureInputParser.tweetID(from: "https://x.com/openai/status/1780000000000000000"),
            "1780000000000000000"
        )
        XCTAssertEqual(
            TwitterCaptureInputParser.tweetID(from: "https://twitter.com/i/status/1780000000000000001"),
            "1780000000000000001"
        )
        XCTAssertEqual(
            TwitterCaptureInputParser.listID(from: "https://x.com/i/lists/123456789"),
            "123456789"
        )
        XCTAssertEqual(TwitterCaptureInputParser.handle(from: "@openai"), "openai")
        XCTAssertEqual(TwitterCaptureInputParser.handle(from: "https://x.com/openai"), "openai")
        XCTAssertNil(TwitterCaptureInputParser.handle(from: "https://x.com/openai/status/178"))
    }

    func testTwikitSidecarDefaultsKnownRequiredUserLegacyFields() throws {
        let sidecarURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/twitter.capture/scripts/twikit_sidecar.py")
        let source = try String(contentsOf: sidecarURL, encoding: .utf8)

        for field in [
            "possibly_sensitive",
            "can_dm",
            "can_media_tag",
            "want_retweets",
            "default_profile",
            "default_profile_image",
            "has_custom_timelines",
            "fast_followers_count",
            "normal_followers_count",
            "is_translator",
            "translator_type",
            "withheld_in_countries"
        ] {
            XCTAssertTrue(
                source.contains("\"\(field)\""),
                "twikit_sidecar.py should default legacy user field \(field)"
            )
        }
    }

    func testTwitterCaptureFileDatabaseRoundTripsTaskRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("twitter-capture-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = TwitterCaptureFileDatabase(rootURL: root)
        let now = Date()
        let task = TwitterCaptureTaskRecord(
            id: "twitter-test",
            kind: .tweet,
            target: "https://x.com/openai/status/178",
            normalizedTarget: "178",
            limit: 1,
            status: .completed,
            title: "Tweet Capture",
            createdAt: now,
            updatedAt: now,
            cookieFilePath: "/tmp/cookies.json",
            taskDirectoryPath: try database.taskDirectory("twitter-test").path,
            tweets: [
                TwitterCapturedTweet(
                    tweetID: "178",
                    tweetURL: "https://x.com/openai/status/178",
                    authorHandle: "@openai",
                    text: "Hello from a test tweet.",
                    lang: "en",
                    likeCount: 10,
                    retweetCount: 2,
                    replyCount: 1,
                    viewCount: 100,
                    createdAt: "2026-04-27T00:00:00Z",
                    isReply: false,
                    isRetweet: false,
                    media: []
                )
            ],
            nextCursor: nil,
            log: "Completed",
            errorMessage: nil
        )

        try database.save(task)

        let loaded = try XCTUnwrap(database.loadTasks().first)
        XCTAssertEqual(loaded.id, task.id)
        XCTAssertEqual(loaded.tweets.first?.text, "Hello from a test tweet.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try database.taskFileURL(task.id).path))
    }
}
