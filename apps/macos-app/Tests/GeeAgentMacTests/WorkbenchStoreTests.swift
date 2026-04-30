import XCTest
@testable import GeeAgentMac

private let activeAgentProfilePreferenceKey = "geeagent.activeAgentProfileId"
private let profileAppearancePreferencesKey = "geeagent.profileAppearancePreferences"
private let legacyHomeVisualModeKey = "geeagent.home.visualMode"
private let legacyHomeBannerImagePathKey = "geeagent.home.bannerImagePath"

@MainActor
final class WorkbenchStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: activeAgentProfilePreferenceKey)
        defaults.removeObject(forKey: profileAppearancePreferencesKey)
        defaults.removeObject(forKey: legacyHomeVisualModeKey)
        defaults.removeObject(forKey: legacyHomeBannerImagePathKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: activeAgentProfilePreferenceKey)
        defaults.removeObject(forKey: profileAppearancePreferencesKey)
        defaults.removeObject(forKey: legacyHomeVisualModeKey)
        defaults.removeObject(forKey: legacyHomeBannerImagePathKey)
        super.tearDown()
    }

    func testHomeChatFocusReturnsToHomeAndUsesChatMode() {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.openSection(.tasks)
        store.openHomeChatFocus()

        XCTAssertEqual(store.selectedSection, .home)
        XCTAssertEqual(store.homeSurfaceMode, .chatFocus)
    }

    func testLeavingHomeCollapsesFocusedHomeMode() {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.openHomeTaskFocus()
        store.openSection(.chat)

        XCTAssertEqual(store.selectedSection, .chat)
        XCTAssertEqual(store.homeSurfaceMode, .companion)
    }

    func testPreviewHomeTaskFocusStartsWithApproveActionForApprovalTask() {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.openHomeTaskFocus()

        XCTAssertEqual(store.selectedTask?.status, .needsApproval)
        XCTAssertEqual(store.selectedTaskActions, [.allowOnce, .alwaysAllow, .deny])
    }

    func testPreviewTaskSelectionExposesRetryActionsForRecoverableTasks() throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        let blockedTask = try XCTUnwrap(store.tasks.first(where: { $0.status == .blocked }))
        store.selectedTaskID = blockedTask.id
        XCTAssertEqual(store.selectedTaskActions, [.retry])

        let failedTask = try XCTUnwrap(store.tasks.first(where: { $0.status == .failed }))
        store.selectedTaskID = failedTask.id
        XCTAssertEqual(store.selectedTaskActions, [.retry])
    }

    func testPreviewActiveAgentProfileDefaultsToBundledGee() throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        let activeProfile = try XCTUnwrap(store.activeAgentProfile)
        XCTAssertEqual(activeProfile.id, "gee")
        XCTAssertEqual(activeProfile.source, .firstParty)
        XCTAssertTrue(
            store.availableAgentProfiles.contains(where: { $0.id == "gee" }),
            "Bundled gee profile should always be listed"
        )
    }

    func testSnapshotActiveAgentProfileBeatsStaleUserDefaults() throws {
        UserDefaults.standard.set("companion", forKey: activeAgentProfilePreferenceKey)

        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        XCTAssertEqual(
            store.activeAgentProfileID,
            store.snapshot.activeAgentProfileID,
            "Runtime snapshot should be the source of truth for the active persona on init"
        )
        XCTAssertEqual(store.activeAgentProfile?.id, "gee")
    }

    func testUserDefaultsFillsInWhenSnapshotHasNoActiveAgentProfile() throws {
        UserDefaults.standard.set("companion", forKey: activeAgentProfilePreferenceKey)

        let preview = PreviewWorkbenchRuntimeClient()
        var snapshot = preview.loadSnapshot()
        snapshot.activeAgentProfileID = nil
        let client = FixedSnapshotRuntimeClient(snapshot: snapshot)

        let store = WorkbenchStore(runtimeClient: client)

        XCTAssertEqual(store.activeAgentProfileID, "companion")
    }

    // MARK: - Plan 2: persona-driven appearance

    func testFreshInstallEffectiveAppearanceFollowsActivePersona() throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        XCTAssertEqual(store.effectiveActiveAppearance, store.activeAgentProfile?.appearance)
        XCTAssertEqual(store.activeProfileAppearancePreference.kind, store.activeAgentProfile?.appearance.kind)
    }

    func testSettingAppearanceKindUpdatesEffectiveAppearance() throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.setActiveAppearanceKind(.abstract)

        XCTAssertEqual(store.effectiveHomeVisualMode, .abstract)
        XCTAssertEqual(store.effectiveActiveAppearance, .abstract)
    }

    func testSettingAssetPathRemembersPerKindSelectionWithoutOverridingLoadedAppearance() throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.setActiveAppearanceKind(.staticImage)
        store.setActiveAppearanceAssetPath("/tmp/one.png", for: .staticImage)
        store.setActiveAppearanceAssetPath("/tmp/two.mp4", for: .video)

        XCTAssertEqual(store.activeProfileAppearancePreference.staticImagePath, "/tmp/one.png")
        XCTAssertEqual(store.activeProfileAppearancePreference.videoPath, "/tmp/two.mp4")

        store.setActiveAppearanceKind(.video)
        XCTAssertEqual(store.activeProfileAppearancePreference.kind, .video)

        store.setActiveAppearanceKind(.staticImage)
        XCTAssertEqual(store.activeProfileAppearancePreference.kind, .staticImage)
        XCTAssertNil(
            store.effectiveBannerAssetPath,
            "Remembered local asset paths must not override the loaded profile appearance"
        )
    }

    func testAppearancePreferencePersistsAcrossStoreReloads() throws {
        do {
            let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
            store.setActiveAppearanceKind(.staticImage)
            store.setActiveAppearanceAssetPath("/tmp/persisted.png", for: .staticImage)
        }

        let nextStore = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        XCTAssertEqual(nextStore.activeProfileAppearancePreference.kind, .staticImage)
        XCTAssertEqual(nextStore.activeProfileAppearancePreference.staticImagePath, "/tmp/persisted.png")
    }

    func testLive2DPersonaCanSwitchToAbstractBackgroundMode() throws {
        let preview = PreviewWorkbenchRuntimeClient()
        var snapshot = preview.loadSnapshot()
        let live2DProfile = AgentProfileRecord(
            id: "manga",
            name: "Manga",
            tagline: "Live2D-first companion",
            personalityPrompt: "",
            appearance: .live2D(bundlePath: "/tmp/manga/model3.json"),
            skills: [],
            allowedToolIDs: nil,
            source: .userCreated,
            version: "1.0.0"
        )
        snapshot.availableAgentProfiles.append(live2DProfile)
        snapshot.activeAgentProfileID = live2DProfile.id
        let client = FixedSnapshotRuntimeClient(snapshot: snapshot)

        let store = WorkbenchStore(runtimeClient: client)

        store.setActiveAppearanceKind(.abstract)
        XCTAssertEqual(store.activeProfileAppearancePreference.kind, .abstract)
        XCTAssertEqual(
            store.effectiveActiveAppearance,
            .abstract,
            "The mountain appearance switch should hide persona media and leave the global background or abstract field visible"
        )
        XCTAssertEqual(store.effectiveHomeVisualMode, .abstract)
    }

    func testNonLive2DPersonaKeepsLive2DDisabledUntilBundleExists() throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        XCTAssertFalse(
            store.isAppearanceKindSelectable(.live2D),
            "Personas without a live2D baseline or remembered bundle cannot select live2D"
        )

        store.setActiveAppearanceAssetPath("/tmp/some/model3.json", for: .live2D)
        XCTAssertTrue(
            store.isAppearanceKindSelectable(.live2D),
            "A remembered live2D bundle path should unlock the chip"
        )
    }

    func testClearActiveProfileAppearanceOverrideRevertsToBaseline() throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        let baselineAppearance = try XCTUnwrap(store.activeAgentProfile?.appearance)

        store.setActiveAppearanceKind(.staticImage)
        store.setActiveAppearanceAssetPath("/tmp/banner.png", for: .staticImage)
        XCTAssertTrue(store.activeProfileHasAppearanceOverride)

        store.clearActiveProfileAppearanceOverride()

        XCTAssertFalse(store.activeProfileHasAppearanceOverride)
        XCTAssertEqual(store.effectiveActiveAppearance, baselineAppearance)
    }

    func testNonLive2DAppearanceClearsMotionCatalog() throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.setActiveAppearanceAssetPath("/tmp/model/model3.json", for: .live2D)
        store.setActiveAppearanceKind(.live2D)
        XCTAssertTrue(store.availableLive2DPoses.isEmpty)
        XCTAssertTrue(store.availableLive2DActionMotions.isEmpty)

        store.setActiveAppearanceKind(.abstract)

        XCTAssertTrue(store.availableLive2DPoses.isEmpty)
        XCTAssertNil(store.live2DMotionPlaybackRequest)
    }

    func testPlayLive2DMotionCreatesFreshPlaybackRequest() throws {
        let motion = Live2DMotionRecord(
            id: "idle.motion3.json",
            title: "idle",
            relativePath: "idle.motion3.json",
            source: .scanned,
            category: .pose,
            isLoop: true
        )
        let preview = PreviewWorkbenchRuntimeClient()
        var snapshot = preview.loadSnapshot()
        snapshot.availableAgentProfiles = [
            AgentProfileRecord(
                id: "gee",
                name: "Gee",
                tagline: "Test",
                personalityPrompt: "",
                appearance: .live2D(bundlePath: "/tmp/model3.json"),
                skills: [],
                allowedToolIDs: nil,
                source: .firstParty,
                version: "1.0.0"
            )
        ]
        snapshot.activeAgentProfileID = "gee"
        let store = WorkbenchStore(runtimeClient: FixedSnapshotRuntimeClient(snapshot: snapshot))

        store.playLive2DMotion(motion)
        let firstRequest = try XCTUnwrap(store.live2DMotionPlaybackRequest)
        store.playLive2DMotion(motion)
        let secondRequest = try XCTUnwrap(store.live2DMotionPlaybackRequest)

        XCTAssertEqual(firstRequest.motion.relativePath, motion.relativePath)
        XCTAssertNotEqual(firstRequest.requestID, secondRequest.requestID)
    }

    func testTriggerLive2DActionRestoresActivePose() async throws {
        let pose = Live2DMotionRecord(
            id: "idle.motion3.json",
            title: "Default Pose",
            relativePath: "idle.motion3.json",
            source: .scanned,
            category: .pose,
            isLoop: true,
            durationSeconds: 4
        )
        let action = Live2DMotionRecord(
            id: "wave.motion3.json",
            title: "Wave",
            relativePath: "wave.motion3.json",
            source: .scanned,
            category: .action,
            isLoop: false,
            durationSeconds: 0.05
        )
        let preview = PreviewWorkbenchRuntimeClient()
        var snapshot = preview.loadSnapshot()
        snapshot.availableAgentProfiles = [
            AgentProfileRecord(
                id: "gee",
                name: "Gee",
                tagline: "Test",
                personalityPrompt: "",
                appearance: .live2D(bundlePath: "/tmp/model3.json"),
                skills: [],
                allowedToolIDs: nil,
                source: .firstParty,
                version: "1.0.0"
            )
        ]
        snapshot.activeAgentProfileID = "gee"
        let store = WorkbenchStore(runtimeClient: FixedSnapshotRuntimeClient(snapshot: snapshot))
        store.live2DActionCatalog = Live2DActionCatalog(
            defaultPose: pose,
            fallbackPose: nil,
            poses: [pose],
            actions: [action],
            expressions: []
        )

        store.triggerLive2DAction(action)
        XCTAssertEqual(store.live2DMotionPlaybackRequest?.motion.relativePath, "wave.motion3.json")

        try await waitUntil(timeout: 2.0) {
            store.live2DMotionPlaybackRequest?.motion.relativePath == "idle.motion3.json"
        }
    }

    func testLegacyHomeVisualPrefsMigrateIntoActivePersonaOnce() throws {
        let defaults = UserDefaults.standard
        defaults.set("banner", forKey: legacyHomeVisualModeKey)
        defaults.set("/tmp/legacy.png", forKey: legacyHomeBannerImagePathKey)

        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        XCTAssertEqual(store.activeProfileAppearancePreference.kind, .staticImage)
        XCTAssertEqual(store.activeProfileAppearancePreference.staticImagePath, "/tmp/legacy.png")
        XCTAssertNil(defaults.string(forKey: legacyHomeVisualModeKey),
                     "Legacy visual-mode key should be removed after a successful migration")
        XCTAssertNil(defaults.string(forKey: legacyHomeBannerImagePathKey),
                     "Legacy banner-path key should be removed after a successful migration")
    }

    func testSettingActiveAgentProfileUpdatesStoreSelection() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        let alternateProfile = try XCTUnwrap(
            store.availableAgentProfiles.first(where: { $0.id != store.activeAgentProfile?.id })
        )

        store.setActiveAgentProfile(alternateProfile)
        try await waitUntil(timeout: 2.0) { store.activeAgentProfileID == alternateProfile.id }

        XCTAssertEqual(store.activeAgentProfileID, alternateProfile.id)
        XCTAssertEqual(store.selectedAgentProfileID, alternateProfile.id)
        XCTAssertEqual(store.activeAgentProfile?.id, alternateProfile.id)
    }

    func testFailedActiveAgentProfileSwitchDoesNotEnterFalseActiveState() async throws {
        let store = WorkbenchStore(runtimeClient: FailingSetActiveRuntimeClient(snapshot: PreviewWorkbenchRuntimeClient().loadSnapshot()))
        let originalActiveID = store.activeAgentProfileID
        let alternateProfile = try XCTUnwrap(
            store.availableAgentProfiles.first(where: { $0.id != originalActiveID })
        )

        store.setActiveAgentProfile(alternateProfile)

        try await waitUntil(timeout: 2.0) { store.lastErrorMessage != nil }

        XCTAssertEqual(store.activeAgentProfileID, originalActiveID)
        XCTAssertEqual(store.selectedAgentProfileID, alternateProfile.id)
    }

    // MARK: Plan 4 — tool dispatch

    func testInvokeNavigateOpenSectionSwitchesSelectedSection() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        store.openSection(.home)

        store.invokeTool(
            ToolInvocation(
                toolID: "navigate.openSection",
                arguments: ["section": .string("tasks")]
            )
        )

        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        XCTAssertEqual(store.selectedSection, .tasks)
        XCTAssertNil(store.pendingToolApproval)
        if case .completed = store.lastToolOutcome {
            // ok
        } else {
            XCTFail("Expected completed outcome, got \(String(describing: store.lastToolOutcome))")
        }
    }

    // MARK: Plan 6 — standalone modules + navigate.openModule

    func testInvokeNavigateOpenModuleRequestsDedicatedWindowForNativeStandaloneGear() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        store.openSection(.tasks)

        store.invokeTool(
            ToolInvocation(
                toolID: "navigate.openModule",
                arguments: ["module_id": .string("media.library")]
            )
        )

        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        XCTAssertNil(store.presentedStandaloneModuleID)
        XCTAssertEqual(store.pendingGearWindowRequest?.gearID, "media.library")
        XCTAssertEqual(store.pendingGearWindowRequest?.windowID, GearHost.mediaLibraryWindowID)
        XCTAssertEqual(store.selectedSection, .tasks)
    }

    func testInvokeNavigateOpenModuleInNavSelectsAppsExtension() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        store.openSection(.home)

        store.invokeTool(
            ToolInvocation(
                toolID: "navigate.openModule",
                arguments: ["module_id": .string("app-release-board")]
            )
        )

        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        XCTAssertNil(store.presentedStandaloneModuleID)
        XCTAssertEqual(store.selectedSection, .apps)
        XCTAssertEqual(store.selectedExtension, .app("app-release-board"))
    }

    func testInvokeGeeAppOpenSurfaceRequestsDedicatedGearWindow() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.invokeTool(
            ToolInvocation(
                toolID: "gee.app.openSurface",
                arguments: ["gear_id": .string("media.library")]
            )
        )

        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        XCTAssertNil(store.presentedStandaloneModuleID)
        XCTAssertEqual(store.pendingGearWindowRequest?.gearID, "media.library")
        XCTAssertEqual(store.pendingGearWindowRequest?.windowID, GearHost.mediaLibraryWindowID)
    }

    func testInvokeGeeGearListCapabilitiesUsesProgressiveDisclosure() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.invokeTool(
            ToolInvocation(
                toolID: "gee.gear.listCapabilities",
                arguments: ["detail": .string("summary")]
            )
        )
        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        guard case let .completed(_, summaryPayload)? = store.lastToolOutcome else {
            return XCTFail("Expected summary capability payload, got \(String(describing: store.lastToolOutcome))")
        }
        XCTAssertEqual(summaryPayload["disclosure_level"] as? String, "summary")
        let gears = try XCTUnwrap(summaryPayload["gears"] as? [[String: Any]])
        let mediaGear = try XCTUnwrap(gears.first { $0["gear_id"] as? String == "media.library" })
        XCTAssertEqual(mediaGear["capability_count"] as? Int, 3)
        XCTAssertTrue((mediaGear["capability_ids"] as? [String])?.contains("media.import_files") == true)
        XCTAssertNil(mediaGear["description"], "Summary disclosure should not include full capability copy.")

        store.invokeTool(
            ToolInvocation(
                toolID: "gee.gear.listCapabilities",
                arguments: [
                    "detail": .string("summary"),
                    "run_plan_id": .string("run_plan_demo"),
                    "stage_id": .string("stage_fetch_tweet"),
                    "focus_gear_ids": .stringArray(["media.library", "media.generator"]),
                    "focus_capability_ids": .stringArray(["media.import_files", "media_generator.create_task"])
                ]
            )
        )
        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        guard case let .completed(_, focusedPayload)? = store.lastToolOutcome else {
            return XCTFail("Expected focused capability payload, got \(String(describing: store.lastToolOutcome))")
        }
        XCTAssertEqual(focusedPayload["disclosure_level"] as? String, "summary")
        XCTAssertEqual(focusedPayload["focus_applied"] as? Bool, true)
        XCTAssertEqual(focusedPayload["focus_complete"] as? Bool, true)
        XCTAssertEqual(focusedPayload["run_plan_id"] as? String, "run_plan_demo")
        XCTAssertEqual(focusedPayload["missing_focus_gear_ids"] as? [String], [])
        XCTAssertEqual(focusedPayload["missing_focus_capability_ids"] as? [String], [])
        let focusedGears = try XCTUnwrap(focusedPayload["gears"] as? [[String: Any]])
        XCTAssertEqual(Set(focusedGears.compactMap { $0["gear_id"] as? String }), Set(["media.library", "media.generator"]))
        let focusedCapabilityIDs = Set(
            focusedGears.flatMap { ($0["capability_ids"] as? [String]) ?? [] }
        )
        XCTAssertEqual(focusedCapabilityIDs, Set(["media.import_files", "media_generator.create_task"]))

        store.invokeTool(
            ToolInvocation(
                toolID: "gee.gear.listCapabilities",
                arguments: [
                    "detail": .string("summary"),
                    "run_plan_id": .string("run_plan_missing"),
                    "stage_id": .string("stage_missing"),
                    "focus_gear_ids": .stringArray(["missing.gear"]),
                    "focus_capability_ids": .stringArray(["missing.capability"])
                ]
            )
        )
        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        guard case let .error(_, code, message)? = store.lastToolOutcome else {
            return XCTFail("Expected focused capability failure, got \(String(describing: store.lastToolOutcome))")
        }
        XCTAssertEqual(code, "gear.focus_unavailable")
        XCTAssertTrue(message.contains("focused runtime plan"))

        store.invokeTool(
            ToolInvocation(
                toolID: "gee.gear.listCapabilities",
                arguments: [
                    "detail": .string("schema"),
                    "gear_id": .string("media.library"),
                    "capability_id": .string("media.filter")
                ]
            )
        )
        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        guard case let .completed(_, schemaPayload)? = store.lastToolOutcome else {
            return XCTFail("Expected schema capability payload, got \(String(describing: store.lastToolOutcome))")
        }
        XCTAssertEqual(schemaPayload["disclosure_level"] as? String, "schema")
        XCTAssertEqual(schemaPayload["gear_id"] as? String, "media.library")
        XCTAssertEqual(schemaPayload["capability_id"] as? String, "media.filter")
        XCTAssertNotNil(schemaPayload["args_schema"])
    }

    func testInvokeGeeGearMediaFilterAppliesToMediaLibraryStore() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        let mediaStore = MediaLibraryModuleStore.shared
        let originalLibrary = mediaStore.library
        let originalItems = mediaStore.items
        let originalFolders = mediaStore.folders
        let originalSelectedFolderID = mediaStore.selectedFolderID
        let originalFilter = mediaStore.filter
        let originalSelectedItemIDs = mediaStore.selectedItemIDs
        let originalFocusedItemID = mediaStore.focusedItemID
        defer {
            mediaStore.library = originalLibrary
            mediaStore.items = originalItems
            mediaStore.folders = originalFolders
            mediaStore.selectedFolderID = originalSelectedFolderID
            mediaStore.filter = originalFilter
            mediaStore.selectedItemIDs = originalSelectedItemIDs
            mediaStore.focusedItemID = originalFocusedItemID
        }

        let folder = MediaLibraryFolder(id: "folder-clips", name: "Clips", createdAt: Date(), depth: 0)
        mediaStore.library = MediaLibraryInfo(
            name: "Test Library",
            url: URL(fileURLWithPath: "/tmp/Test.library"),
            kind: .eagle,
            folders: [folder]
        )
        mediaStore.folders = [folder]
        mediaStore.items = [
            mediaItem(id: "long-starred", ext: "mp4", duration: 240, folderIDs: [folder.id], isStarred: true),
            mediaItem(id: "short-starred", ext: "mp4", duration: 60, folderIDs: [folder.id], isStarred: true),
            mediaItem(id: "image", ext: "png", duration: nil, folderIDs: [folder.id], isStarred: true)
        ]
        mediaStore.clearFilters()
        mediaStore.selectFolder(nil)

        store.invokeTool(
            ToolInvocation(
                toolID: "gee.gear.invoke",
                arguments: [
                    "gear_id": .string("media.library"),
                    "capability_id": .string("media.filter"),
                    "args": .object([
                        "kind": .string("video"),
                        "extensions": .stringArray(["mp4"]),
                        "starred_only": .bool(true),
                        "minimum_duration_seconds": .int(180),
                        "search_text": .string("long"),
                        "folder_name": .string("Clips")
                    ])
                ]
            )
        )
        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        XCTAssertEqual(mediaStore.selectedFolderID, folder.id)
        XCTAssertEqual(mediaStore.filter.mediaKind, .video)
        XCTAssertEqual(mediaStore.filter.selectedExtensions, ["mp4"])
        XCTAssertEqual(mediaStore.filter.starredOnly, true)
        XCTAssertEqual(mediaStore.filter.minimumDurationSeconds, 180)
        XCTAssertEqual(mediaStore.filter.searchText, "long")
        XCTAssertEqual(mediaStore.filteredItems.map(\.id), ["long-starred"])

        guard case let .completed(_, payload)? = store.lastToolOutcome else {
            return XCTFail("Expected completed gear invocation, got \(String(describing: store.lastToolOutcome))")
        }
        XCTAssertEqual(payload["gear_id"] as? String, "media.library")
        XCTAssertEqual(payload["capability_id"] as? String, "media.filter")
        XCTAssertEqual(payload["filtered_count"] as? Int, 1)
        XCTAssertEqual(payload["total_count"] as? Int, 3)
    }

    func testMediaLibraryUIKindSelectionClearsHiddenAgentFilters() {
        let defaults = UserDefaults(suiteName: "GeeAgentMacTests.MediaLibraryFilters.\(UUID().uuidString)")!
        let mediaStore = MediaLibraryModuleStore(defaults: defaults)

        mediaStore.applyAgentFilter(
            extensions: ["png"],
            starredOnly: true,
            mediaKind: .image,
            minimumDurationSeconds: 180,
            searchText: "night"
        )
        XCTAssertTrue(mediaStore.hasActiveFilters)

        mediaStore.selectMediaKindFromUI(.video)

        XCTAssertEqual(mediaStore.filter.mediaKind, .video)
        XCTAssertEqual(mediaStore.filter.selectedExtensions, [])
        XCTAssertNil(mediaStore.filter.minimumDurationSeconds)
        XCTAssertTrue(mediaStore.filter.starredOnly)
        XCTAssertEqual(mediaStore.filter.searchText, "night")

        mediaStore.selectMediaKindFromUI(.all)

        XCTAssertFalse(mediaStore.hasActiveFilters)
        XCTAssertEqual(mediaStore.filter.mediaKind, .all)
        XCTAssertEqual(mediaStore.filter.selectedExtensions, [])
        XCTAssertFalse(mediaStore.filter.starredOnly)
        XCTAssertNil(mediaStore.filter.minimumDurationSeconds)
        XCTAssertEqual(mediaStore.filter.searchText, "")
    }

    func testCloseStandaloneModuleRestoresPriorSection() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        store.openSection(.automations)

        store.invokeTool(
            ToolInvocation(
                toolID: "navigate.openModule",
                arguments: ["module_id": .string("media.library")]
            )
        )
        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        store.closeStandaloneModule()

        XCTAssertNil(store.presentedStandaloneModuleID)
        XCTAssertEqual(store.selectedSection, .automations)
    }

    func testInvokeShellRunWithoutTokenSurfacesPendingApproval() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.invokeTool(
            ToolInvocation(
                toolID: "shell.run",
                arguments: ["command": .string("ls")]
            )
        )

        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        let pending = try XCTUnwrap(store.pendingToolApproval)
        XCTAssertEqual(pending.invocation.toolID, "shell.run")
        XCTAssertEqual(pending.blastRadius, .external)
        XCTAssertFalse(pending.generatedToken.isEmpty)
    }

    func testApprovingPendingToolReDispatchesWithToken() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.invokeTool(
            ToolInvocation(
                toolID: "shell.run",
                arguments: ["command": .string("ls")]
            )
        )
        try await waitUntil(timeout: 2.0) { store.pendingToolApproval != nil }

        store.resolvePendingApproval(accept: true)
        try await waitUntil(timeout: 2.0) { !store.isInvokingTool }

        XCTAssertNil(store.pendingToolApproval)
        guard case .completed = try XCTUnwrap(store.lastToolOutcome) else {
            return XCTFail("Expected completed outcome after approval")
        }
    }

    func testCancellingPendingToolRecordsDenial() {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.pendingToolApproval = PendingToolApproval(
            invocation: ToolInvocation(toolID: "shell.run", arguments: [:]),
            blastRadius: .external,
            prompt: "test",
            generatedToken: "tok"
        )

        store.resolvePendingApproval(accept: false)

        XCTAssertNil(store.pendingToolApproval)
        if case .denied(_, let reason) = store.lastToolOutcome {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("Expected denied outcome after cancel, got \(String(describing: store.lastToolOutcome))")
        }
    }

    // MARK: Plan 5 — menu-bar quick input

    func testMenuBarStateReflectsPendingApprovalTask() {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        // The preview snapshot ships with a .needsApproval task at the head
        // of the queue, so the menu-bar ring should show `waitingReview`.
        XCTAssertEqual(store.menuBarState, .waitingReview)
    }

    func testMenuBarStateFallsBackToIdleWhenNoActionableTasks() {
        var snapshot = PreviewWorkbenchRuntimeClient().loadSnapshot()
        snapshot.tasks = snapshot.tasks.map { original in
            var copy = original
            copy.status = .completed
            return copy
        }
        snapshot.runtimeStatus.state = .live

        let store = WorkbenchStore(runtimeClient: FixedSnapshotRuntimeClient(snapshot: snapshot))
        XCTAssertEqual(store.menuBarState, .idle)
    }

    func testMenuBarStateDegradesWhenChatRuntimeIsNotLive() {
        var snapshot = PreviewWorkbenchRuntimeClient().loadSnapshot()
        snapshot.tasks = snapshot.tasks.map { original in
            var copy = original
            copy.status = .completed
            return copy
        }
        snapshot.runtimeStatus.state = .needsSetup

        let store = WorkbenchStore(runtimeClient: FixedSnapshotRuntimeClient(snapshot: snapshot))
        XCTAssertEqual(store.menuBarState, .degraded)
    }

    func testSubmitQuickInputRoutesDraftAndRecordsLatestResult() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        let originalConversationID = store.selectedConversationID
        let originalConversationCount = store.conversations.count

        store.quickInputDraft = "Remind me what's in the review queue"
        store.submitQuickInput()

        try await waitUntil(timeout: 2.0) { !store.isSubmittingQuickInput }

        XCTAssertEqual(store.quickInputDraft, "")
        XCTAssertEqual(store.quickInputLatestResult?.kind, .chatReply)
        XCTAssertEqual(store.conversations.count, originalConversationCount + 1)
        XCTAssertNotEqual(store.selectedConversationID, originalConversationID)
        XCTAssertEqual(store.selectedConversation?.tags, ["quick-input"])
    }

    func testSubmitQuickInputImmediatelyOpensChatAndShowsSendingState() {
        let store = WorkbenchStore(runtimeClient: DelayedQuickInputRuntimeClient(snapshot: PreviewWorkbenchRuntimeClient().loadSnapshot()))
        store.selectedSection = .home
        store.quickInputDraft = "Save this link and fetch metadata"

        store.submitQuickInput()

        XCTAssertEqual(store.selectedSection, .chat)
        XCTAssertTrue(store.isSubmittingQuickInput)
        XCTAssertTrue(store.isSendingMessage)
    }

    func testSendMessageClearsLocalThinkingStateAfterRuntimeSnapshot() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())

        store.sendMessage("Please answer from the chat runtime.", openSection: false)

        try await waitUntil(timeout: 2.0) { !store.isSendingMessage }

        XCTAssertEqual(store.lastOutcome?.kind, .chatReply)
        XCTAssertFalse(store.isSendingMessage)
    }

    func testPendingChatTurnIgnoresOlderDuplicateUserMessages() throws {
        let repeatedMessage = "Please repeat the same request."
        var snapshot = PreviewWorkbenchRuntimeClient().loadSnapshot()
        var conversation = try XCTUnwrap(snapshot.conversations.first)
        conversation.messages.append(
            ConversationMessage(
                id: "existing-duplicate-user-message",
                role: .user,
                content: repeatedMessage,
                timestampLabel: "Earlier"
            )
        )
        conversation.isActive = true
        snapshot.conversations = [conversation]
        snapshot.preferredSection = .chat
        let store = WorkbenchStore(runtimeClient: DelayedSendMessageRuntimeClient(snapshot: snapshot))

        store.sendMessage(repeatedMessage, openSection: false)

        let displayConversation = try XCTUnwrap(store.selectedDisplayConversation)
        XCTAssertTrue(
            displayConversation.messages.contains {
                $0.id.hasPrefix("pending-user-") && $0.content == repeatedMessage
            },
            "An older equal-content user message must not hide the newly submitted local message."
        )
        XCTAssertTrue(
            displayConversation.messages.contains {
                $0.id.hasPrefix("pending-thinking-") && $0.statusLabel == "waiting for first event"
            },
            "The first-event waiting state should stay visible until this specific runtime turn arrives."
        )
    }

    func testSendMessageAppliesRuntimeHostActionIntentsToGear() async throws {
        let mediaStore = MediaLibraryModuleStore.shared
        let originalLibrary = mediaStore.library
        let originalItems = mediaStore.items
        let originalFolders = mediaStore.folders
        let originalSelectedFolderID = mediaStore.selectedFolderID
        let originalFilter = mediaStore.filter
        let originalSelectedItemIDs = mediaStore.selectedItemIDs
        let originalFocusedItemID = mediaStore.focusedItemID
        defer {
            mediaStore.library = originalLibrary
            mediaStore.items = originalItems
            mediaStore.folders = originalFolders
            mediaStore.selectedFolderID = originalSelectedFolderID
            mediaStore.filter = originalFilter
            mediaStore.selectedItemIDs = originalSelectedItemIDs
            mediaStore.focusedItemID = originalFocusedItemID
        }

        mediaStore.library = MediaLibraryInfo(
            name: "Test Library",
            url: URL(fileURLWithPath: "/tmp/Test.library"),
            kind: .eagle,
            folders: []
        )
        mediaStore.folders = []
        mediaStore.items = [
            mediaItem(id: "clip", ext: "mp4", duration: 240, folderIDs: [], isStarred: false),
            mediaItem(id: "image", ext: "png", duration: nil, folderIDs: [], isStarred: false)
        ]
        mediaStore.clearFilters()

        var responseSnapshot = PreviewWorkbenchRuntimeClient().loadSnapshot()
        responseSnapshot.hostActionIntents = [
            WorkbenchHostActionIntent(
                id: "host-action-open-media",
                toolID: "gee.app.openSurface",
                arguments: ["gear_id": .string("media.library")]
            ),
            WorkbenchHostActionIntent(
                id: "host-action-filter-video",
                toolID: "gee.gear.invoke",
                arguments: [
                    "gear_id": .string("media.library"),
                    "capability_id": .string("media.filter"),
                    "args": .object(["kind": .string("video")])
                ]
            )
        ]
        let store = WorkbenchStore(runtimeClient: HostActionRuntimeClient(snapshot: responseSnapshot))

        store.sendMessage("Show video files in the media library.")

        try await waitUntil(timeout: 2.0) {
            mediaStore.filter.mediaKind == .video && store.pendingGearWindowRequest?.gearID == "media.library"
        }
        XCTAssertEqual(mediaStore.filteredItems.map(\.id), ["clip"])

        mediaStore.clearFilters()
        XCTAssertEqual(mediaStore.filter.mediaKind, .all)

        store.sendMessage("Show video files in the media library.")

        try await waitUntil(timeout: 2.0) {
            mediaStore.filter.mediaKind == .video
        }
        XCTAssertEqual(mediaStore.filteredItems.map(\.id), ["clip"])
    }

    func testSubmitQuickInputIgnoresEmptyDrafts() {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        store.quickInputDraft = "   "
        store.submitQuickInput()
        XCTAssertFalse(store.isSubmittingQuickInput)
        XCTAssertNil(store.quickInputLatestResult)
    }

    func testSubmitQuickInputRespectsCanUseQuickInputGate() {
        var snapshot = PreviewWorkbenchRuntimeClient().loadSnapshot()
        snapshot.interactionCapabilities.canUseQuickInput = false

        let store = WorkbenchStore(runtimeClient: FixedSnapshotRuntimeClient(snapshot: snapshot))
        store.quickInputDraft = "anything"
        store.submitQuickInput()

        XCTAssertFalse(store.isSubmittingQuickInput)
        XCTAssertNil(store.quickInputLatestResult)
    }

    func testResetQuickInputClearsDraftAndLatestResult() {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        store.quickInputDraft = "draft"
        store.quickInputLatestResult = WorkbenchRequestOutcome(
            kind: .chatReply,
            detail: "prior",
            taskID: nil
        )

        store.resetQuickInput()

        XCTAssertEqual(store.quickInputDraft, "")
        XCTAssertNil(store.quickInputLatestResult)
        XCTAssertFalse(store.isSubmittingQuickInput)
    }

    func testImportAgentPackSelectsNewlyImportedProfile() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let importedID = try await store.importAgentPack(from: tempDir)

        XCTAssertEqual(importedID, tempDir.lastPathComponent.lowercased())
        XCTAssertEqual(store.selectedAgentProfileID, importedID)
        XCTAssertTrue(store.availableAgentProfiles.contains(where: { $0.id == importedID }))
    }

    func testReloadAgentProfileKeepsSelectionAndUpdatesOutcome() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        let imported = AgentProfileRecord(
            id: "local-pack",
            name: "Local Pack",
            tagline: "Reloadable",
            personalityPrompt: "prompt",
            appearance: .staticImage(assetPath: "/tmp/local-pack/appearance/hero.png"),
            skills: [],
            allowedToolIDs: nil,
            source: .modulePack,
            version: "1.0.0",
            fileState: AgentProfileFileStateRecord(
                workspaceRootPath: "/tmp/local-pack",
                manifestPath: "/tmp/local-pack/agent.json",
                identityPromptPath: "/tmp/local-pack/identity-prompt.md",
                visualFiles: [],
                supplementalFiles: [],
                canReload: true,
                canDelete: true
            )
        )
        store.snapshot.availableAgentProfiles.insert(imported, at: 0)
        store.selectedAgentProfileID = imported.id

        try await store.reloadAgentProfile(imported)

        XCTAssertEqual(store.selectedAgentProfileID, imported.id)
        XCTAssertEqual(store.lastOutcome?.detail, "Preview reloaded agent definition local-pack.")
    }

    func testDeleteAgentProfileRemovesImportedProfile() async throws {
        let store = WorkbenchStore(runtimeClient: PreviewWorkbenchRuntimeClient())
        let imported = AgentProfileRecord(
            id: "throwaway-pack",
            name: "Throwaway",
            tagline: "Delete me",
            personalityPrompt: "prompt",
            appearance: .staticImage(assetPath: "/tmp/throwaway/appearance/hero.png"),
            skills: [],
            allowedToolIDs: nil,
            source: .modulePack,
            version: "1.0.0",
            fileState: AgentProfileFileStateRecord(
                workspaceRootPath: "/tmp/throwaway",
                manifestPath: "/tmp/throwaway/agent.json",
                identityPromptPath: "/tmp/throwaway/identity-prompt.md",
                visualFiles: [],
                supplementalFiles: [],
                canReload: true,
                canDelete: true
            )
        )
        store.snapshot.availableAgentProfiles.insert(imported, at: 0)
        store.snapshot.activeAgentProfileID = imported.id
        store.selectedAgentProfileID = imported.id

        try await store.deleteAgentProfile(imported)

        XCTAssertFalse(store.availableAgentProfiles.contains(where: { $0.id == imported.id }))
        XCTAssertEqual(store.activeAgentProfileID, "gee")
    }

    /// Polls the main-actor condition until it becomes true or the deadline
    /// is reached. Mirrors the small utility used by other async tests so we
    /// don't need to spin a `XCTestExpectation` per case.
    private func waitUntil(
        timeout: TimeInterval,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await MainActor.run(body: condition) { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Condition did not become true within \(timeout)s")
    }

    private func mediaItem(
        id: String,
        ext: String,
        duration: Double?,
        folderIDs: [String],
        isStarred: Bool
    ) -> MediaLibraryItem {
        MediaLibraryItem(
            id: id,
            name: id,
            ext: ext,
            width: 1920,
            height: 1080,
            durationSeconds: duration,
            size: 1024,
            modifiedAt: Date(),
            tags: [],
            annotation: nil,
            sourceURL: nil,
            fileURL: URL(fileURLWithPath: "/tmp/\(id).\(ext)"),
            thumbnailURL: nil,
            folderIDs: folderIDs,
            isStarred: isStarred
        )
    }
}

private struct FixedSnapshotRuntimeClient: WorkbenchRuntimeClient {
    var snapshot: WorkbenchSnapshot

    func loadSnapshot() -> WorkbenchSnapshot { snapshot }
    func createConversation(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot { snapshot }
    func activateConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func sendMessage(
        _ message: String,
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        allowAutoRouting: Bool
    ) async throws -> WorkbenchSnapshot { snapshot }
    func performTaskAction(
        _ action: WorkbenchTaskAction,
        in snapshot: WorkbenchSnapshot,
        taskID: WorkbenchTaskRecord.ID
    ) async throws -> WorkbenchSnapshot { snapshot }
    func setActiveAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var next = snapshot
        next.activeAgentProfileID = profileID
        return next
    }

    func installAgentPack(
        at packPath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }

    func reloadAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }

    func deleteAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var next = snapshot
        next.availableAgentProfiles.removeAll { $0.id == profileID }
        if next.activeAgentProfileID == profileID {
            next.activeAgentProfileID = "gee"
        }
        return next
    }

    func deleteTerminalPermissionRule(
        _ ruleID: TerminalPermissionRuleRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }

    func setHighestAuthorizationEnabled(
        _ enabled: Bool,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }

    func loadChatRoutingSettings() async throws -> ChatRoutingSettings {
        try await PreviewWorkbenchRuntimeClient().loadChatRoutingSettings()
    }

    func saveChatRoutingSettings(
        _ settings: ChatRoutingSettings,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }

    func submitQuickPrompt(
        _ prompt: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }

    func completeHostActionTurn(
        _ completions: [WorkbenchHostActionCompletion],
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }

    func invokeTool(_ invocation: ToolInvocation) async throws -> WorkbenchToolOutcome {
        .completed(toolID: invocation.toolID, payload: [:])
    }
}

private struct DelayedQuickInputRuntimeClient: WorkbenchRuntimeClient {
    var snapshot: WorkbenchSnapshot

    func loadSnapshot() -> WorkbenchSnapshot { snapshot }
    func createConversation(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot { snapshot }
    func activateConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func sendMessage(
        _ message: String,
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        allowAutoRouting: Bool
    ) async throws -> WorkbenchSnapshot { snapshot }
    func performTaskAction(
        _ action: WorkbenchTaskAction,
        in snapshot: WorkbenchSnapshot,
        taskID: WorkbenchTaskRecord.ID
    ) async throws -> WorkbenchSnapshot { snapshot }
    func setActiveAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func installAgentPack(
        at packPath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func reloadAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteTerminalPermissionRule(
        _ ruleID: TerminalPermissionRuleRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func setHighestAuthorizationEnabled(
        _ enabled: Bool,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func loadChatRoutingSettings() async throws -> ChatRoutingSettings {
        try await PreviewWorkbenchRuntimeClient().loadChatRoutingSettings()
    }
    func saveChatRoutingSettings(
        _ settings: ChatRoutingSettings,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func submitQuickPrompt(
        _ prompt: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        try await Task.sleep(nanoseconds: 500_000_000)
        return snapshot
    }
    func completeHostActionTurn(
        _ completions: [WorkbenchHostActionCompletion],
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func invokeTool(_ invocation: ToolInvocation) async throws -> WorkbenchToolOutcome {
        .completed(toolID: invocation.toolID, payload: [:])
    }
}

private struct DelayedSendMessageRuntimeClient: WorkbenchRuntimeClient {
    var snapshot: WorkbenchSnapshot

    func loadSnapshot() -> WorkbenchSnapshot { snapshot }
    func createConversation(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot { snapshot }
    func activateConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func sendMessage(
        _ message: String,
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        allowAutoRouting: Bool
    ) async throws -> WorkbenchSnapshot {
        try await Task.sleep(nanoseconds: 500_000_000)
        return snapshot
    }
    func performTaskAction(
        _ action: WorkbenchTaskAction,
        in snapshot: WorkbenchSnapshot,
        taskID: WorkbenchTaskRecord.ID
    ) async throws -> WorkbenchSnapshot { snapshot }
    func setActiveAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func installAgentPack(
        at packPath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func reloadAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteTerminalPermissionRule(
        _ ruleID: TerminalPermissionRuleRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func setHighestAuthorizationEnabled(
        _ enabled: Bool,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func loadChatRoutingSettings() async throws -> ChatRoutingSettings {
        try await PreviewWorkbenchRuntimeClient().loadChatRoutingSettings()
    }
    func saveChatRoutingSettings(
        _ settings: ChatRoutingSettings,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func submitQuickPrompt(
        _ prompt: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func completeHostActionTurn(
        _ completions: [WorkbenchHostActionCompletion],
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func invokeTool(_ invocation: ToolInvocation) async throws -> WorkbenchToolOutcome {
        .completed(toolID: invocation.toolID, payload: [:])
    }
}

private struct HostActionRuntimeClient: WorkbenchRuntimeClient {
    var snapshot: WorkbenchSnapshot

    func loadSnapshot() -> WorkbenchSnapshot {
        var loadedSnapshot = snapshot
        loadedSnapshot.hostActionIntents = []
        return loadedSnapshot
    }
    func createConversation(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot { snapshot }
    func activateConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func sendMessage(
        _ message: String,
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        allowAutoRouting: Bool
    ) async throws -> WorkbenchSnapshot { self.snapshot }
    func performTaskAction(
        _ action: WorkbenchTaskAction,
        in snapshot: WorkbenchSnapshot,
        taskID: WorkbenchTaskRecord.ID
    ) async throws -> WorkbenchSnapshot { snapshot }
    func setActiveAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func installAgentPack(
        at packPath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func reloadAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteTerminalPermissionRule(
        _ ruleID: TerminalPermissionRuleRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func setHighestAuthorizationEnabled(
        _ enabled: Bool,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func loadChatRoutingSettings() async throws -> ChatRoutingSettings {
        try await PreviewWorkbenchRuntimeClient().loadChatRoutingSettings()
    }
    func saveChatRoutingSettings(
        _ settings: ChatRoutingSettings,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func submitQuickPrompt(
        _ prompt: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { self.snapshot }

    func completeHostActionTurn(
        _ completions: [WorkbenchHostActionCompletion],
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        var nextSnapshot = self.snapshot
        nextSnapshot.hostActionIntents = []
        return nextSnapshot
    }

    func invokeTool(_ invocation: ToolInvocation) async throws -> WorkbenchToolOutcome {
        try await PreviewWorkbenchRuntimeClient().invokeTool(invocation)
    }
}

private struct FailingSetActiveRuntimeClient: WorkbenchRuntimeClient {
    var snapshot: WorkbenchSnapshot

    func loadSnapshot() -> WorkbenchSnapshot { snapshot }
    func createConversation(in snapshot: WorkbenchSnapshot) async throws -> WorkbenchSnapshot { snapshot }
    func activateConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteConversation(
        _ conversationID: ConversationThread.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func sendMessage(
        _ message: String,
        in snapshot: WorkbenchSnapshot,
        conversationID: ConversationThread.ID,
        allowAutoRouting: Bool
    ) async throws -> WorkbenchSnapshot { snapshot }
    func performTaskAction(
        _ action: WorkbenchTaskAction,
        in snapshot: WorkbenchSnapshot,
        taskID: WorkbenchTaskRecord.ID
    ) async throws -> WorkbenchSnapshot { snapshot }
    func setActiveAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot {
        throw NSError(domain: "GeeAgentMacTests", code: 99, userInfo: [
            NSLocalizedDescriptionKey: "Synthetic failure while switching active profile."
        ])
    }
    func installAgentPack(
        at packPath: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func reloadAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteAgentProfile(
        _ profileID: AgentProfileRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func deleteTerminalPermissionRule(
        _ ruleID: TerminalPermissionRuleRecord.ID,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func setHighestAuthorizationEnabled(
        _ enabled: Bool,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func loadChatRoutingSettings() async throws -> ChatRoutingSettings {
        try await PreviewWorkbenchRuntimeClient().loadChatRoutingSettings()
    }
    func saveChatRoutingSettings(
        _ settings: ChatRoutingSettings,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }
    func submitQuickPrompt(
        _ prompt: String,
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }

    func completeHostActionTurn(
        _ completions: [WorkbenchHostActionCompletion],
        in snapshot: WorkbenchSnapshot
    ) async throws -> WorkbenchSnapshot { snapshot }

    func invokeTool(_ invocation: ToolInvocation) async throws -> WorkbenchToolOutcome {
        .completed(toolID: invocation.toolID, payload: [:])
    }
}
