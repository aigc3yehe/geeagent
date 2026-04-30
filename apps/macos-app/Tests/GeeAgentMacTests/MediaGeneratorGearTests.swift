import XCTest
@testable import GeeAgentMac

final class MediaGeneratorGearTests: XCTestCase {
    func testXenodiaMediaBackendDecodesSnakeCaseRuntimePayload() throws {
        let data = Data("""
        {
          "api_key": "secret-test-key",
          "image_generations_url": "https://api.xenodia.xyz/v1/images/generations",
          "task_retrieval_url": "https://api.xenodia.xyz/v1/tasks",
          "request_timeout_seconds": 45
        }
        """.utf8)

        let backend = try JSONDecoder().decode(XenodiaMediaBackend.self, from: data)

        XCTAssertEqual(backend.apiKey, "secret-test-key")
        XCTAssertEqual(backend.imageGenerationsURL, "https://api.xenodia.xyz/v1/images/generations")
        XCTAssertEqual(backend.taskRetrievalURL, "https://api.xenodia.xyz/v1/tasks")
        XCTAssertEqual(backend.requestTimeoutSeconds, 45)
    }

    func testXenodiaMediaBackendRuntimePayloadDecoderIgnoresGlobalSnakeCaseStrategy() throws {
        let data = Data("""
        {
          "api_key": "secret-test-key",
          "image_generations_url": "https://api.xenodia.xyz/v1/images/generations",
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
        XCTAssertEqual(backend.taskRetrievalURL, "https://api.xenodia.xyz/v1/tasks")
        XCTAssertEqual(backend.requestTimeoutSeconds, 45)
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

    func testMediaGeneratorTaskDecodesLegacyRecordsWithoutStarredFlag() throws {
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

        let task = try decoder.decode(MediaGeneratorTask.self, from: data)

        XCTAssertEqual(task.id, "legacy-task")
        XCTAssertFalse(task.isStarred)
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
        XCTAssertEqual(task.agentDictionary["is_locally_cached"] as? Bool, true)
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
        XCTAssertEqual(models?.map { $0["model"] as? String }, ["nano-banana-pro", "gpt-image-2"])
        let nanoFields = models?.first?["supported_fields"] as? [String]
        XCTAssertTrue(nanoFields?.contains("resolution") == true)
        XCTAssertTrue(nanoFields?.contains("output_format") == true)
        let gptFields = models?.last?["supported_fields"] as? [String]
        XCTAssertTrue(gptFields?.contains("aspect_ratio") == true)
        XCTAssertTrue(gptFields?.contains("resolution") == true)
        XCTAssertFalse(gptFields?.contains("nsfw_checker") == true)
        XCTAssertFalse(gptFields?.contains("output_format") == true)
        let constraints = payload["constraints"] as? [String: Any]
        let referenceLimits = constraints?["max_total_references_by_model"] as? [String: Int]
        XCTAssertEqual(referenceLimits?["nano-banana-pro"], 8)
        XCTAssertEqual(referenceLimits?["gpt-image-2"], 16)
        XCTAssertEqual(constraints?["max_reference_file_bytes"] as? Int64, 31_457_280)
        let placeholders = payload["placeholders"] as? [String: String]
        XCTAssertTrue(placeholders?["video"]?.contains("Xenodia video") == true)
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
    func testUnsupportedVideoTaskFailsBeforeProviderCall() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-generator-video-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaGeneratorGearStore(database: MediaGeneratorFileDatabase(rootURL: root))

        let payload = await store.createAgentTask(args: [
            "category": "video",
            "prompt": "Make a five second product teaser"
        ])

        XCTAssertEqual(payload["gear_id"] as? String, MediaGeneratorGearDescriptor.gearID)
        XCTAssertEqual(payload["capability_id"] as? String, "media_generator.create_task")
        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertTrue((payload["error"] as? String)?.contains("future Xenodia media endpoints") == true)
        XCTAssertTrue(store.tasks.isEmpty)
    }
}
