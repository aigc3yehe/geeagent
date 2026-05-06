import AppKit
import XCTest
@testable import GeeAgentMac

final class MediaGeneratorGearTests: XCTestCase {
    func testXenodiaMediaBackendDecodesSnakeCaseRuntimePayload() throws {
        let data = Data("""
        {
          "api_key": "secret-test-key",
          "image_generations_url": "https://api.xenodia.xyz/v1/images/generations",
          "video_generations_url": "https://api.xenodia.xyz/v1/videos/generations",
          "task_retrieval_url": "https://api.xenodia.xyz/v1/tasks",
          "request_timeout_seconds": 45
        }
        """.utf8)

        let backend = try JSONDecoder().decode(XenodiaMediaBackend.self, from: data)

        XCTAssertEqual(backend.apiKey, "secret-test-key")
        XCTAssertEqual(backend.imageGenerationsURL, "https://api.xenodia.xyz/v1/images/generations")
        XCTAssertEqual(backend.videoGenerationsURL, "https://api.xenodia.xyz/v1/videos/generations")
        XCTAssertEqual(backend.taskRetrievalURL, "https://api.xenodia.xyz/v1/tasks")
        XCTAssertEqual(backend.requestTimeoutSeconds, 45)
    }

    func testXenodiaMediaBackendRuntimePayloadDecoderIgnoresGlobalSnakeCaseStrategy() throws {
        let data = Data("""
        {
          "api_key": "secret-test-key",
          "image_generations_url": "https://api.xenodia.xyz/v1/images/generations",
          "video_generations_url": "https://api.xenodia.xyz/v1/videos/generations",
          "task_retrieval_url": "https://api.xenodia.xyz/v1/tasks",
          "request_timeout_seconds": 45
        }
        """.utf8)
        let runtimeWideDecoder = JSONDecoder()
        runtimeWideDecoder.keyDecodingStrategy = .convertFromSnakeCase

        XCTAssertThrowsError(try runtimeWideDecoder.decode(XenodiaMediaBackend.self, from: data))

        let backend = try XenodiaMediaBackend.decodeRuntimePayload(data)

        XCTAssertEqual(backend.apiKey, "secret-test-key")
        XCTAssertEqual(backend.imageGenerationsURL, "https://api.xenodia.xyz/v1/images/generations")
        XCTAssertEqual(backend.videoGenerationsURL, "https://api.xenodia.xyz/v1/videos/generations")
        XCTAssertEqual(backend.taskRetrievalURL, "https://api.xenodia.xyz/v1/tasks")
        XCTAssertEqual(backend.requestTimeoutSeconds, 45)
    }

    func testXenodiaImageGenerationClientEnforcesLongRunningRequestTimeoutFloor() {
        let backend = XenodiaMediaBackend(
            apiKey: "secret-test-key",
            imageGenerationsURL: "https://api.xenodia.xyz/v1/images/generations",
            videoGenerationsURL: "https://api.xenodia.xyz/v1/videos/generations",
            taskRetrievalURL: "https://api.xenodia.xyz/v1/tasks",
            storageUploadURL: nil,
            requestTimeoutSeconds: 45
        )

        XCTAssertGreaterThanOrEqual(
            XenodiaImageGenerationClient.requestTimeoutInterval(for: backend),
            1_800
        )
    }

    func testXenodiaTimedOutStatusRequestsRemainRetryable() {
        XCTAssertTrue(XenodiaImageGenerationClient.isRetryableStatusPollError(URLError(.timedOut)))
        XCTAssertFalse(XenodiaImageGenerationClient.isRetryableStatusPollError(URLError(.notConnectedToInternet)))
    }

    func testXenodiaTaskResponseParsesOfficialSuccessPayload() throws {
        let data = Data("""
        {
          "task_id": "0f6b9f2f-4d2a-4e1a-ae49-3e5d4f88dc2f",
          "object": "task",
          "model": "nano-banana-pro",
          "type": "image",
          "state": "success",
          "request": {
            "prompt": "A cinematic banana pilot standing on a wet neon runway.",
            "aspect_ratio": "16:9",
            "resolution": "4K",
            "output_format": "png"
          },
          "result": {
            "created": 1760002248,
            "data": [
              { "url": "https://cdn.xenodia.xyz/generated/a.png" }
            ]
          },
          "error": {},
          "progress": 100,
          "created_at": 1760002222,
          "updated_at": 1760002248,
          "completed_at": 1760002248
        }
        """.utf8)

        let result = try XenodiaImageGenerationClient.parseTaskResponse(data)

        XCTAssertTrue(result.isSuccessful)
        XCTAssertFalse(result.isFailed)
        XCTAssertEqual(result.resultURL, "https://cdn.xenodia.xyz/generated/a.png")
        XCTAssertEqual(result.progress, 100)
    }

    func testXenodiaTaskResponseParsesOfficialVideoSuccessPayload() throws {
        let data = Data("""
        {
          "task_id": "task_123",
          "state": "success",
          "result": {
            "created": 1760000100,
            "data": [
              { "url": "https://cdn.example.com/video.mp4" }
            ],
            "resolution": "720p"
          },
          "progress": 100,
          "poll_url": "/v1/tasks/task_123"
        }
        """.utf8)

        let result = try XenodiaImageGenerationClient.parseTaskResponse(data)

        XCTAssertTrue(result.isSuccessful)
        XCTAssertEqual(result.resultURL, "https://cdn.example.com/video.mp4")
        XCTAssertEqual(result.progress, 100)
    }

    func testXenodiaAssetUploadResponseNormalizesAssetIDs() throws {
        let assetIDData = Data("""
        {
          "data": {
            "asset_id": "asset_123"
          }
        }
        """.utf8)
        let urlData = Data("""
        {
          "asset_url": "https://cdn.example.com/reference.png"
        }
        """.utf8)

        XCTAssertEqual(try XenodiaImageGenerationClient.parseAssetUploadReference(assetIDData), "asset://asset_123")
        XCTAssertEqual(try XenodiaImageGenerationClient.parseAssetUploadReference(urlData), "https://cdn.example.com/reference.png")
    }

    func testXenodiaTaskResponseAcceptsCompletedAliasAndAlternateURLKeys() throws {
        let data = Data("""
        {
          "state": "completed",
          "result": {
            "outputs": ["https://cdn.xenodia.xyz/generated/alias.webp"]
          },
          "progress": 100,
          "error": {}
        }
        """.utf8)

        let result = try XenodiaImageGenerationClient.parseTaskResponse(data)

        XCTAssertTrue(result.isSuccessful)
        XCTAssertEqual(result.resultURL, "https://cdn.xenodia.xyz/generated/alias.webp")
    }

    func testMediaGeneratorManifestDeclaresXenodiaCapabilities() throws {
        let data = Data("""
        {
          "schema": "gee.gear.v1",
          "id": "media.generator",
          "name": "Media Generator",
          "description": "Native media generation workspace.",
          "developer": "Gee",
          "version": "0.1.0",
          "category": "Creative",
          "kind": "atmosphere",
          "display_mode": "full_canvas",
          "entry": { "type": "native", "native_id": "media.generator" },
          "agent": {
            "enabled": true,
            "capabilities": [
              {
                "id": "media_generator.list_models",
                "title": "List media generation models",
                "description": "List models."
              },
              {
                "id": "media_generator.create_task",
                "title": "Create media generation task",
                "description": "Create a generation task."
              },
              {
                "id": "media_generator.get_task",
                "title": "Get generation task",
                "description": "Read task state."
              }
            ]
          }
        }
        """.utf8)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.nativeID, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(
            manifest.agent?.capabilities.map(\.id),
            [
                "media_generator.list_models",
                "media_generator.create_task",
                "media_generator.get_task"
            ]
        )
    }

    func testMediaGeneratorFileDatabaseRoundTripsTaskRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = MediaGeneratorFileDatabase(rootURL: root)
        let task = MediaGeneratorTask(
            id: "media-generator-test",
            category: .image,
            modelID: .nanoBananaPro,
            prompt: "A compact rainy neon workspace",
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_774_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_774_000_030),
            providerTaskID: "xenodia-task-1",
            resultURL: "https://cdn.example/image.png",
            localOutputPath: nil,
            errorMessage: nil,
            parameters: ["aspect_ratio": "16:9"],
            references: [
                MediaGeneratorReference(
                    id: "ref-1",
                    url: "https://example.com/ref.png",
                    localPath: nil,
                    displayName: "ref.png"
                )
            ]
        )

        try database.save(task)

        let tasks = database.loadTasks()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.id, task.id)
        XCTAssertEqual(tasks.first?.providerTaskID, "xenodia-task-1")
        XCTAssertEqual(tasks.first?.resultURL, "https://cdn.example/image.png")
        XCTAssertEqual(tasks.first?.references.first?.url, "https://example.com/ref.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try database.taskFileURL(task.id).path))
    }

    func testMediaGeneratorReferencePreviewURLSupportsDisplayableImageReferencesOnly() {
        let remote = MediaGeneratorReference(
            id: "remote",
            url: "https://cdn.example/reference.png",
            localPath: nil,
            displayName: "reference.png"
        )
        let asset = MediaGeneratorReference(
            id: "asset",
            url: "asset://reference-1",
            localPath: nil,
            displayName: "reference-1"
        )
        let local = MediaGeneratorReference(
            id: "local",
            url: nil,
            localPath: "/tmp/reference.webp",
            displayName: "reference.webp"
        )

        XCTAssertEqual(remote.previewURL?.absoluteString, "https://cdn.example/reference.png")
        XCTAssertNil(asset.previewURL)
        XCTAssertEqual(local.previewURL, URL(fileURLWithPath: "/tmp/reference.webp"))
    }

    func testMediaGeneratorFileDatabaseClearsPreBatchTaskHistory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-legacy-task-clear-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tasksRoot = root.appendingPathComponent("tasks", isDirectory: true)
        let legacyDirectory = tasksRoot.appendingPathComponent("legacy-task", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try Data("""
        {
          "id": "legacy-task",
          "category": "image",
          "modelID": "nano-banana-pro",
          "prompt": "old task",
          "status": "completed",
          "createdAt": "2026-05-01T00:00:00Z",
          "updatedAt": "2026-05-01T00:00:00Z",
          "parameters": { "n": "1" },
          "references": []
        }
        """.utf8).write(to: legacyDirectory.appendingPathComponent("task.json"))

        let database = MediaGeneratorFileDatabase(rootURL: root)

        XCTAssertTrue(database.loadTasks().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    func testMediaGeneratorFileDatabaseRoundTripsQuickPrompts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-quick-prompt-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = MediaGeneratorFileDatabase(rootURL: root)
        let prompts = [
            MediaGeneratorQuickPrompt(
                id: "custom-1",
                name: "Editorial",
                content: "editorial lighting, clean background"
            )
        ]

        try database.saveQuickPrompts(prompts)

        XCTAssertEqual(database.loadQuickPrompts(), prompts)
    }

    func testMediaGeneratorFileDatabaseRoundTripsImageHistory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-image-history-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = MediaGeneratorFileDatabase(rootURL: root)
        let history = [
            MediaGeneratorImageHistoryItem(
                id: "history-1",
                url: "https://cdn.example/history.png",
                timestamp: Date(timeIntervalSince1970: 1_774_000_111)
            )
        ]

        try database.saveImageHistory(history)

        XCTAssertEqual(database.loadImageHistory(), history)
    }

    func testMediaGeneratorFileDatabaseReadsLegacyURLOnlyImageHistory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-legacy-image-history-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacyHistoryURL = root.appendingPathComponent("image-history.json")
        try Data("""
        [
          {
            "id": "legacy-history",
            "url": "https://cdn.example/references/legacy.png",
            "timestamp": "2026-04-30T00:00:00Z"
          }
        ]
        """.utf8).write(to: legacyHistoryURL)
        let database = MediaGeneratorFileDatabase(rootURL: root)

        let history = database.loadImageHistory()

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, "legacy-history")
        XCTAssertEqual(history.first?.url, "https://cdn.example/references/legacy.png")
        XCTAssertEqual(history.first?.localPath, nil)
        XCTAssertEqual(history.first?.displayName, "legacy.png")
    }

    @MainActor
    func testReferenceURLAddsReusableHistoryItem() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-reference-url-history-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        store.addReferenceURL("https://cdn.example/references/pose.png")

        XCTAssertEqual(store.references.map(\.url), ["https://cdn.example/references/pose.png"])
        XCTAssertEqual(store.imageHistory.map(\.url), ["https://cdn.example/references/pose.png"])
        XCTAssertEqual(store.imageHistory.first?.localPath, nil)
        XCTAssertEqual(store.imageHistory.first?.displayName, "pose.png")
    }

    @MainActor
    func testLocalReferenceFileAddsReusableHistoryItem() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-local-reference-history-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let referenceURL = root.appendingPathComponent("moodboard.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: referenceURL)
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root.appendingPathComponent("gear-data", isDirectory: true)))

        store.addReferenceFileURL(referenceURL)

        XCTAssertEqual(store.references.map(\.localPath), [referenceURL.path])
        XCTAssertEqual(store.imageHistory.map(\.localPath), [referenceURL.path])
        XCTAssertEqual(store.imageHistory.first?.url, nil)
        XCTAssertEqual(store.imageHistory.first?.displayName, "moodboard.png")
    }

    @MainActor
    func testVideoLocalReferenceFileAddsReusableHistoryItem() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-video-local-reference-history-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let referenceURL = root.appendingPathComponent("video-frame.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: referenceURL)
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root.appendingPathComponent("gear-data", isDirectory: true)))

        store.selectCategory(.video)
        store.addReferenceFileURL(referenceURL)

        XCTAssertEqual(store.references.map(\.localPath), [referenceURL.path])
        XCTAssertEqual(store.imageHistory.map(\.localPath), [referenceURL.path])
        XCTAssertEqual(store.imageHistory.first?.displayName, "video-frame.png")
    }

    @MainActor
    func testClipboardImageAddsReusableReferenceFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-clipboard-reference-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("media-generator-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)

        store.addClipboardReferenceImage(from: pasteboard)

        XCTAssertEqual(store.references.count, 1)
        let localPath = try XCTUnwrap(store.references.first?.localPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localPath))
        XCTAssertEqual(store.imageHistory.map(\.localPath), [localPath])
        XCTAssertTrue(MediaGeneratorGearStore.pasteboardHasReferenceImage(pasteboard))
    }

    @MainActor
    func testGeneratedResultReusedAsReferenceDoesNotEnterReferenceHistory() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-generated-result-history-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))
        let task = MediaGeneratorTask(
            id: "generated-result",
            category: .image,
            modelID: .nanoBananaPro,
            prompt: "Generated output",
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_774_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_774_000_030),
            providerTaskID: "xenodia-task-1",
            resultURL: "https://cdn.example/generated/output.png",
            localOutputPath: nil,
            errorMessage: nil,
            parameters: ["aspect_ratio": "1:1"],
            references: []
        )

        store.useResultAsReference(task)

        XCTAssertEqual(store.references.map(\.url), ["https://cdn.example/generated/output.png"])
        XCTAssertTrue(store.imageHistory.isEmpty)
    }

    func testMediaGeneratorTaskRejectsPreBatchLegacyRecords() throws {
        let data = Data("""
        {
          "id": "legacy-task",
          "category": "image",
          "modelID": "nano-banana-pro",
          "prompt": "Legacy prompt",
          "status": "completed",
          "createdAt": "2026-04-29T00:00:00Z",
          "updatedAt": "2026-04-29T00:00:01Z",
          "providerTaskID": "provider-1",
          "resultURL": "https://example.com/result.png",
          "parameters": {
            "aspect_ratio": "1:1"
          },
          "references": []
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertThrowsError(try decoder.decode(MediaGeneratorTask.self, from: data))
    }

    func testMediaGeneratorFileDatabaseDeletesTaskDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-delete-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = MediaGeneratorFileDatabase(rootURL: root)
        let task = MediaGeneratorTask(
            id: "media-generator-delete-test",
            category: .image,
            modelID: .nanoBananaPro,
            prompt: "Delete me",
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_774_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_774_000_030),
            providerTaskID: "xenodia-task-1",
            resultURL: "https://cdn.example/image.png",
            localOutputPath: nil,
            errorMessage: nil,
            parameters: ["aspect_ratio": "1:1"],
            references: [],
            isStarred: true
        )

        try database.save(task)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try database.taskFileURL(task.id).path))

        try database.deleteTask(id: task.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: try database.taskFileURL(task.id).path))
        XCTAssertTrue(database.loadTasks().isEmpty)
    }

    func testMediaGeneratorFileDatabaseWritesResultCacheInsideTaskDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = MediaGeneratorFileDatabase(rootURL: root)
        let task = MediaGeneratorTask(
            id: "media-generator-cache-test",
            category: .image,
            modelID: .nanoBananaPro,
            prompt: "Cache me",
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_774_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_774_000_030),
            providerTaskID: "xenodia-task-1",
            resultURL: "https://cdn.example/image.png",
            localOutputPath: nil,
            errorMessage: nil,
            parameters: ["output_format": "png"],
            references: []
        )

        try database.save(task)
        let cachedURL = try database.saveResultData(Data("cached-image".utf8), for: task, suggestedExtension: ".PNG")

        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedURL.path))
        XCTAssertTrue(cachedURL.path.hasPrefix(root.path))
        XCTAssertTrue(cachedURL.path.contains("/tasks/\(task.id)/outputs/result.png"))
        XCTAssertEqual(try String(contentsOf: cachedURL, encoding: .utf8), "cached-image")
    }

    func testMediaGeneratorTaskPrefersLocalCachedResultWhenFileExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-local-result-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cachedURL = root.appendingPathComponent("result.webp")
        try Data("image".utf8).write(to: cachedURL)
        let task = MediaGeneratorTask(
            id: "media-generator-local-result-test",
            category: .image,
            modelID: .nanoBananaPro,
            prompt: "Prefer local",
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_774_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_774_000_030),
            providerTaskID: "xenodia-task-1",
            resultURL: "https://cdn.example/image.png",
            localOutputPath: cachedURL.path,
            errorMessage: nil,
            parameters: ["output_format": "png"],
            references: []
        )

        XCTAssertTrue(task.isLocallyCached)
        XCTAssertEqual(task.resultDisplayURL, cachedURL)
        XCTAssertEqual(task.resultFileExtension, "webp")
        XCTAssertEqual(task.agentDictionary["id"] as? String, "media-generator-local-result-test")
        XCTAssertEqual(task.agentDictionary["task_id"] as? String, "media-generator-local-result-test")
        XCTAssertEqual(task.agentDictionary["is_locally_cached"] as? Bool, true)
    }

    func testMediaGeneratorTaskGroupReportsCompletedBatchStatusToAgents() {
        let batchID = "media-generator-batch-test"
        let first = MediaGeneratorTask(
            id: "media-generator-batch-test-1",
            category: .image,
            modelID: .nanoBananaPro,
            prompt: "Batch prompt",
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_774_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_774_000_030),
            providerTaskID: "xenodia-task-1",
            resultURL: "https://cdn.example/image-1.png",
            localOutputPath: nil,
            errorMessage: nil,
            parameters: ["n": "1", "batch_count": "2"],
            references: [],
            batchID: batchID,
            batchIndex: 1,
            batchCount: 2
        )
        let second = MediaGeneratorTask(
            id: "media-generator-batch-test-2",
            category: .image,
            modelID: .nanoBananaPro,
            prompt: "Batch prompt",
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_774_000_001),
            updatedAt: Date(timeIntervalSince1970: 1_774_000_031),
            providerTaskID: "xenodia-task-2",
            resultURL: "https://cdn.example/image-2.png",
            localOutputPath: nil,
            errorMessage: nil,
            parameters: ["n": "1", "batch_count": "2"],
            references: [],
            batchID: batchID,
            batchIndex: 2,
            batchCount: 2
        )

        let group = MediaGeneratorTaskGroup(id: batchID, batchID: batchID, tasks: [first, second])

        XCTAssertEqual(group.statusTitle, MediaGeneratorTaskStatus.completed.title)
        XCTAssertEqual(group.agentStatus, MediaGeneratorTaskStatus.completed.rawValue)
    }

    @MainActor
    func testVisibleTasksApplySearchStatusModelAndStarredFilters() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-filter-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = MediaGeneratorFileDatabase(rootURL: root)
        let completedStarred = MediaGeneratorTask(
            id: "completed-starred",
            category: .image,
            modelID: .gptImage2,
            prompt: "Silver compass icon",
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_774_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_774_000_030),
            providerTaskID: nil,
            resultURL: "https://cdn.example/compass.png",
            localOutputPath: nil,
            errorMessage: nil,
            parameters: ["aspect_ratio": "1:1"],
            references: [],
            isStarred: true
        )
        let failed = MediaGeneratorTask(
            id: "failed-task",
            category: .image,
            modelID: .nanoBananaPro,
            prompt: "Emerald leaf icon",
            status: .failed,
            createdAt: Date(timeIntervalSince1970: 1_774_000_100),
            updatedAt: Date(timeIntervalSince1970: 1_774_000_130),
            providerTaskID: nil,
            resultURL: nil,
            localOutputPath: nil,
            errorMessage: "Network failed",
            parameters: ["aspect_ratio": "1:1"],
            references: []
        )
        try? database.save(completedStarred)
        try? database.save(failed)
        let store = MediaGeneratorGearStore(database: database)

        store.taskFilter = .starred
        XCTAssertEqual(store.visibleTasks.map(\.id), ["completed-starred"])

        store.taskFilter = .all
        store.modelFilter = .nanoBananaPro
        XCTAssertEqual(store.visibleTasks.map(\.id), ["failed-task"])

        store.modelFilter = nil
        store.searchQuery = "compass"
        XCTAssertEqual(store.visibleTasks.map(\.id), ["completed-starred"])
    }

    @MainActor
    func testApplyTaskParametersRestoresPromptModelParametersAndReferences() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-apply-task-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))
        let task = MediaGeneratorTask(
            id: "apply-task",
            category: .image,
            modelID: .gptImage2,
            prompt: "Restored prompt",
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_774_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_774_000_030),
            providerTaskID: nil,
            resultURL: "https://cdn.example/result.png",
            localOutputPath: nil,
            errorMessage: nil,
            parameters: [
                "aspect_ratio": "16:9",
                "resolution": "2K",
                "n": "1",
                "async": "false"
            ],
            references: [
                MediaGeneratorReference(
                    id: "ref-1",
                    url: "https://cdn.example/ref.png",
                    localPath: nil,
                    displayName: "ref.png"
                )
            ]
        )

        store.applyTaskParameters(task)

        XCTAssertEqual(store.category, .image)
        XCTAssertEqual(store.selectedModel, .gptImage2)
        XCTAssertEqual(store.prompt, "Restored prompt")
        XCTAssertEqual(store.aspectRatio, .landscape)
        XCTAssertEqual(store.resolution, .twoK)
        XCTAssertEqual(store.imageCount, 1)
        XCTAssertFalse(store.useAsync)
        XCTAssertEqual(store.references.map(\.url), ["https://cdn.example/ref.png"])
        XCTAssertEqual(store.selectedTaskID, "apply-task")
    }

    @MainActor
    func testModelPayloadUsesGlobalXenodiaChannelAndPlaceholders() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-model-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = store.modelPayload()

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.list_models")
        XCTAssertEqual(payload["channel"] as? String, "xenodia")
        let models = payload["models"] as? [[String: Any]]
        XCTAssertEqual(
            models?.map { $0["model"] as? String },
            [
                "nano-banana-pro",
                "gpt-image-2",
                "veo3.1",
                "veo3.1_fast",
                "veo3.1_lite",
                "seedance-2",
                "seedance-2-fast"
            ]
        )
        let nanoFields = models?.first?["supported_fields"] as? [String]
        XCTAssertTrue(nanoFields?.contains("resolution") == true)
        XCTAssertTrue(nanoFields?.contains("output_format") == true)
        let gptFields = models?.first { $0["model"] as? String == "gpt-image-2" }?["supported_fields"] as? [String]
        XCTAssertTrue(gptFields?.contains("aspect_ratio") == true)
        XCTAssertTrue(gptFields?.contains("resolution") == true)
        XCTAssertFalse(gptFields?.contains("nsfw_checker") == true)
        XCTAssertFalse(gptFields?.contains("output_format") == true)
        let veoFields = models?.first { $0["model"] as? String == "veo3.1_fast" }?["supported_fields"] as? [String]
        XCTAssertTrue(veoFields?.contains("batch_count") == true)
        XCTAssertTrue(veoFields?.contains("generation_type") == true)
        XCTAssertTrue(veoFields?.contains("image_urls") == true)
        let seedanceFields = models?.first { $0["model"] as? String == "seedance-2" }?["supported_fields"] as? [String]
        XCTAssertTrue(seedanceFields?.contains("batch_count") == true)
        XCTAssertTrue(seedanceFields?.contains("duration") == true)
        XCTAssertTrue(seedanceFields?.contains("reference_video_urls") == true)
        let constraints = payload["constraints"] as? [String: Any]
        let referenceLimits = constraints?["max_total_references_by_model"] as? [String: Int]
        XCTAssertEqual(referenceLimits?["nano-banana-pro"], 8)
        XCTAssertEqual(referenceLimits?["gpt-image-2"], 16)
        XCTAssertEqual(referenceLimits?["veo3.1_fast"], 3)
        XCTAssertEqual(referenceLimits?["seedance-2"], 9)
        let batchConstraint = constraints?["batch_count"] as? [String: Int]
        XCTAssertEqual(batchConstraint?["maximum"], 4)
        XCTAssertEqual(constraints?["max_reference_file_bytes"] as? Int64, 31_457_280)
        let placeholders = payload["placeholders"] as? [String: String]
        XCTAssertTrue(placeholders?["audio"]?.contains("Xenodia audio") == true)
    }

    @MainActor
    func testInvalidImageCountFailsBeforeProviderCall() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-count-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = await store.createAgentTask(args: [
            "category": "image",
            "prompt": "Make a compact icon",
            "n": 2
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertTrue((payload["error"] as? String)?.contains("n=1") == true)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    @MainActor
    func testAgentBatchCountCreatesGroupedChildTasksWithSingleProviderImageRequests() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-batch-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = await store.createAgentTask(args: [
            "category": "image",
            "prompt": "Make four compact icon variations",
            "batch_count": 4
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["batch_count"] as? Int, 4)
        XCTAssertNotNil(payload["batch_id"] as? String)
        XCTAssertEqual(store.tasks.count, 4)
        XCTAssertEqual(store.visibleTaskGroups.count, 1)
        XCTAssertEqual(store.visibleTaskGroups.first?.tasks.count, 4)
        XCTAssertEqual(Set(store.tasks.compactMap(\.batchID)).count, 1)
        XCTAssertEqual(Set(store.tasks.map(\.batchCount)), [4])
        XCTAssertEqual(Set(store.tasks.compactMap { $0.parameters["n"] }), ["1"])
        let payloadTasks = payload["tasks"] as? [[String: Any]]
        XCTAssertEqual(payloadTasks?.count, 4)
    }

    @MainActor
    func testUnsupportedGptImage2ResolutionCombinationFailsBeforeProviderCall() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-gpt-resolution-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = await store.createAgentTask(args: [
            "category": "image",
            "model": "gpt-image-2",
            "prompt": "Make a compact icon",
            "aspect_ratio": "1:1",
            "resolution": "4K"
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertTrue((payload["error"] as? String)?.contains("resolution=4K") == true)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    @MainActor
    func testImage2AliasAndLowercaseResolutionNormalizeForAgentTasks() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-image2-alias-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = await store.createAgentTask(args: [
            "category": "image",
            "model": "image-2",
            "prompt": "Make a compact icon",
            "aspect_ratio": "auto",
            "resolution": "2k"
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertTrue((payload["error"] as? String)?.contains("GPT Image-2") == true)
        XCTAssertTrue((payload["error"] as? String)?.contains("resolution=2K") == true)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    @MainActor
    func testUnsupportedGptImage2OutputFormatFailsBeforeProviderCall() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-gpt-output-format-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = await store.createAgentTask(args: [
            "category": "image",
            "model": "gpt-image-2",
            "prompt": "Make a compact icon",
            "output_format": "png"
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertTrue((payload["error"] as? String)?.contains("output_format") == true)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    @MainActor
    func testAgentVideoBatchCountCreatesGroupedChildTasks() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-video-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = await store.createAgentTask(args: [
            "category": "video",
            "model": "veo3.1_fast",
            "prompt": "Make a five second product teaser",
            "batch_count": 2
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["batch_count"] as? Int, 2)
        XCTAssertNotNil(payload["batch_id"] as? String)
        XCTAssertEqual(store.tasks.count, 2)
        XCTAssertEqual(store.visibleTaskGroups.count, 1)
        XCTAssertEqual(store.visibleTaskGroups.first?.tasks.count, 2)
        XCTAssertEqual(Set(store.tasks.map(\.category)), [.video])
        XCTAssertEqual(Set(store.tasks.map(\.modelID)), [.veo31Fast])
        XCTAssertEqual(Set(store.tasks.map(\.batchCount)), [2])
        XCTAssertEqual(Set(store.tasks.compactMap { $0.parameters["batch_count"] }), ["2"])
        XCTAssertTrue(store.tasks.allSatisfy { $0.parameters["n"] == nil })
        XCTAssertTrue(store.tasks.allSatisfy { $0.parameters["async"] == nil })
        XCTAssertTrue(store.tasks.allSatisfy { $0.parameters["response_format"] == nil })
        let payloadTasks = payload["tasks"] as? [[String: Any]]
        XCTAssertEqual(payloadTasks?.count, 2)
    }

    @MainActor
    func testVeoReferenceModeRequiresFastModelBeforeProviderCall() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-veo-reference-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = await store.createAgentTask(args: [
            "category": "video",
            "model": "veo3.1",
            "prompt": "Animate this product frame",
            "generation_type": "REFERENCE_2_VIDEO",
            "reference_urls": ["https://cdn.example/frame.png"]
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertTrue((payload["error"] as? String)?.contains("only supports veo3.1_fast") == true)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    @MainActor
    func testVeoFastReferenceURLsInferReferenceGenerationType() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-veo-fast-reference-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        _ = await store.createAgentTask(args: [
            "category": "video",
            "model": "veo3.1_fast",
            "prompt": "Animate this product frame",
            "reference_urls": ["https://cdn.example/frame.png"]
        ])

        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.parameters["generation_type"], "REFERENCE_2_VIDEO")
        XCTAssertEqual(store.tasks.first?.references.map(\.url), ["https://cdn.example/frame.png"])
    }

    @MainActor
    func testAgentReferenceLimitFailsBeforeProviderCall() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-reference-limit-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))
        let referenceURLs = (1...17).map { "https://cdn.example/reference-\($0).png" }

        let payload = await store.createAgentTask(args: [
            "category": "image",
            "model": "gpt-image-2",
            "prompt": "Make a product board from these references",
            "reference_urls": referenceURLs
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertTrue((payload["error"] as? String)?.contains("at most 16 total references") == true)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    @MainActor
    func testSeedanceFirstFrameRejectsReferenceImageArrayBeforeProviderCall() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-seedance-image-reference-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = await store.createAgentTask(args: [
            "category": "video",
            "model": "seedance-2",
            "prompt": "Animate a product reveal",
            "first_frame_url": "asset://first-frame",
            "reference_image_urls": ["https://cdn.example/style.png"]
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertTrue((payload["error"] as? String)?.contains("cannot be combined") == true)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    @MainActor
    func testSeedanceFirstFrameRejectsReferenceVideoArrayBeforeProviderCall() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-seedance-reference-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = await store.createAgentTask(args: [
            "category": "video",
            "model": "seedance-2",
            "prompt": "Animate a product reveal",
            "first_frame_url": "asset://first-frame",
            "reference_video_urls": ["https://cdn.example/motion.mp4"]
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertTrue((payload["error"] as? String)?.contains("cannot be combined") == true)
        XCTAssertTrue(store.tasks.isEmpty)
    }
}
