import Foundation

@MainActor
enum GeeHostToolRouter {
    static func invokeExternalCapability(
        gearID: String,
        capabilityID: String,
        args: [String: Any]
    ) async -> WorkbenchToolOutcome {
        await invokeGear(
            toolID: "gee.gear.invoke",
            payload: [
                "gear_id": gearID,
                "capability_id": capabilityID,
                "args": args
            ]
        )
    }

    static func resolveCompletedIntent(_ outcome: WorkbenchToolOutcome) async -> WorkbenchToolOutcome? {
        guard case let .completed(toolID, payload) = outcome,
              let intent = payload["intent"] as? String
        else {
            return nil
        }

        switch intent {
        case "gear.list_capabilities":
            return listCapabilities(toolID: toolID, payload: payload)
        case "gear.invoke":
            return await invokeGear(toolID: toolID, payload: payload)
        case "native_app.control":
            return await controlNativeApp(toolID: toolID, payload: payload)
        default:
            return nil
        }
    }

    private static func controlNativeApp(
        toolID: String,
        payload: [String: Any]
    ) async -> WorkbenchToolOutcome {
        guard let appID = stringArg(payload, "app_id", "app"),
              !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .error(
                toolID: toolID,
                code: "native_app.args.app_id",
                message: "`app_id` is required for native app control."
            )
        }
        guard let action = stringArg(payload, "action"),
              !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .error(
                toolID: toolID,
                code: "native_app.args.action",
                message: "`action` is required for native app control."
            )
        }
        let result = await GeeNativeAppController.shared.control(
            GeeNativeAppControlRequest(
                appID: appID,
                action: action,
                prompt: stringArg(payload, "prompt"),
                instruction: stringArg(payload, "instruction")
            )
        )
        return .completed(toolID: toolID, payload: result.payload(toolID: toolID))
    }

    private static func listCapabilities(
        toolID: String,
        payload: [String: Any]
    ) -> WorkbenchToolOutcome {
        let records = GearHost.enabledCapabilityRecords()
        let detail = (payload["detail"] as? String) ?? "summary"
        let gearID = payload["gear_id"] as? String
        let capabilityID = payload["capability_id"] as? String
        let focusGearIDs = stringArray(payload["focus_gear_ids"])
        let focusCapabilityIDs = stringArray(payload["focus_capability_ids"])
        let runPlanID = payload["run_plan_id"] as? String
        let stageID = payload["stage_id"] as? String

        switch detail {
        case "summary":
            let summary = summaryPayload(
                records: records,
                focusGearIDs: focusGearIDs,
                focusCapabilityIDs: focusCapabilityIDs,
                runPlanID: runPlanID,
                stageID: stageID
            )
            if isFocusedSummaryUnavailable(summary, focusGearIDs: focusGearIDs, focusCapabilityIDs: focusCapabilityIDs) {
                return .error(
                    toolID: toolID,
                    code: "gear.focus_unavailable",
                    message: "No enabled Gear capabilities matched the focused runtime plan."
                )
            }
            return .completed(
                toolID: toolID,
                payload: summary
            )
        case "capabilities":
            guard let gearID else {
                return .error(
                    toolID: toolID,
                    code: "gear.args.gear_id",
                    message: "`gear_id` is required when requesting Gear capability details."
                )
            }
            return capabilitiesPayload(toolID: toolID, gearID: gearID, records: records)
        case "schema":
            guard let gearID else {
                return .error(
                    toolID: toolID,
                    code: "gear.args.gear_id",
                    message: "`gear_id` is required when requesting a Gear capability schema."
                )
            }
            guard let capabilityID else {
                return .error(
                    toolID: toolID,
                    code: "gear.args.capability_id",
                    message: "`capability_id` is required when requesting a Gear capability schema."
                )
            }
            return schemaPayload(toolID: toolID, gearID: gearID, capabilityID: capabilityID, records: records)
        default:
            return .error(
                toolID: toolID,
                code: "gear.args.detail",
                message: "`detail` must be summary, capabilities, or schema."
            )
        }
    }

    private static func summaryPayload(
        records: [GearCapabilityRecord],
        focusGearIDs: [String],
        focusCapabilityIDs: [String],
        runPlanID: String?,
        stageID: String?
    ) -> [String: Any] {
        let focusedRecords = focusedCapabilityRecords(
            records,
            focusGearIDs: focusGearIDs,
            focusCapabilityIDs: focusCapabilityIDs
        )
        let diagnostics = focusDiagnostics(
            records: records,
            focusGearIDs: focusGearIDs,
            focusCapabilityIDs: focusCapabilityIDs
        )
        let grouped = Dictionary(grouping: focusedRecords, by: \.gearID)
        let gears = grouped.keys.sorted().compactMap { gearID -> [String: Any]? in
            guard let capabilities = grouped[gearID], let first = capabilities.first else {
                return nil
            }
            let sortedCapabilities = capabilities.sorted { $0.capabilityID < $1.capabilityID }
            return [
                "gear_id": gearID,
                "gear_name": first.gearName,
                "capability_count": capabilities.count,
                "capability_ids": sortedCapabilities.map(\.capabilityID),
                "capabilities": sortedCapabilities.map(compactCapabilitySummary)
            ]
        }
        var payload: [String: Any] = [
            "disclosure_level": "summary",
            "tool": "gee.gear.listCapabilities",
            "focus_applied": !focusGearIDs.isEmpty || !focusCapabilityIDs.isEmpty,
            "next_step": "If the compact focused capability summary includes the needed capability and required_args are satisfied, call gee.gear.invoke directly. Request detail=schema only when optional argument types are unclear or when the active plan reopens discovery.",
            "gears": gears
        ]
        if !focusGearIDs.isEmpty {
            payload["focus_gear_ids"] = focusGearIDs
        }
        if !focusCapabilityIDs.isEmpty {
            payload["focus_capability_ids"] = focusCapabilityIDs
        }
        if !focusGearIDs.isEmpty || !focusCapabilityIDs.isEmpty {
            payload["focus_complete"] = diagnostics.missingGearIDs.isEmpty && diagnostics.missingCapabilityIDs.isEmpty
            payload["missing_focus_gear_ids"] = diagnostics.missingGearIDs
            payload["missing_focus_capability_ids"] = diagnostics.missingCapabilityIDs
        }
        if let runPlanID, !runPlanID.isEmpty {
            payload["run_plan_id"] = runPlanID
        }
        if let stageID, !stageID.isEmpty {
            payload["stage_id"] = stageID
        }
        return payload
    }

    private static func isFocusedSummaryUnavailable(
        _ payload: [String: Any],
        focusGearIDs: [String],
        focusCapabilityIDs: [String]
    ) -> Bool {
        guard !focusGearIDs.isEmpty || !focusCapabilityIDs.isEmpty else {
            return false
        }
        let gears = payload["gears"] as? [[String: Any]] ?? []
        return gears.isEmpty
    }

    private static func focusDiagnostics(
        records: [GearCapabilityRecord],
        focusGearIDs: [String],
        focusCapabilityIDs: [String]
    ) -> (missingGearIDs: [String], missingCapabilityIDs: [String]) {
        let availableGearIDs = Set(records.map(\.gearID))
        let availableCapabilityIDs = Set(records.map(\.capabilityID))
        return (
            missingGearIDs: focusGearIDs.filter { !availableGearIDs.contains($0) },
            missingCapabilityIDs: focusCapabilityIDs.filter { !availableCapabilityIDs.contains($0) }
        )
    }

    private static func focusedCapabilityRecords(
        _ records: [GearCapabilityRecord],
        focusGearIDs: [String],
        focusCapabilityIDs: [String]
    ) -> [GearCapabilityRecord] {
        guard !focusGearIDs.isEmpty || !focusCapabilityIDs.isEmpty else {
            return records
        }
        let gearIDSet = Set(focusGearIDs)
        let capabilityIDSet = Set(focusCapabilityIDs)
        return records.filter { record in
            (gearIDSet.isEmpty || gearIDSet.contains(record.gearID)) &&
            (capabilityIDSet.isEmpty || capabilityIDSet.contains(record.capabilityID))
        }
    }

    private static func compactCapabilitySummary(_ capability: GearCapabilityRecord) -> [String: Any] {
        var payload: [String: Any] = [
            "capability_id": capability.capabilityID,
            "title": capability.title,
            "description": capability.description
        ]
        if !capability.examples.isEmpty {
            payload["examples"] = capability.examples
        }
        if let schema = argsSchema(gearID: capability.gearID, capabilityID: capability.capabilityID) {
            let requiredArgs = schema["required"] as? [String] ?? []
            payload["required_args"] = requiredArgs
            if let properties = schema["properties"] as? [String: Any] {
                payload["optional_args"] = properties.keys
                    .filter { !requiredArgs.contains($0) }
                    .sorted()
            }
        }
        return payload
    }

    private static func capabilitiesPayload(
        toolID: String,
        gearID: String,
        records: [GearCapabilityRecord]
    ) -> WorkbenchToolOutcome {
        let capabilities = records.filter { $0.gearID == gearID }
        guard let first = capabilities.first else {
            return .error(
                toolID: toolID,
                code: "gear.unknown_or_unavailable",
                message: "No enabled Gear capabilities are available for `\(gearID)`."
            )
        }
        return .completed(
            toolID: toolID,
            payload: [
                "disclosure_level": "capabilities",
                "gear_id": gearID,
                "gear_name": first.gearName,
                "next_step": "Invoke directly when required_args are available; request detail=schema only when exact optional argument types are needed.",
                "capabilities": capabilities
                    .sorted { $0.capabilityID < $1.capabilityID }
                    .map(compactCapabilitySummary)
            ]
        )
    }

    private static func schemaPayload(
        toolID: String,
        gearID: String,
        capabilityID: String,
        records: [GearCapabilityRecord]
    ) -> WorkbenchToolOutcome {
        guard let capability = records.first(where: { $0.gearID == gearID && $0.capabilityID == capabilityID }) else {
            return .error(
                toolID: toolID,
                code: "gear.capability_unavailable",
                message: "`\(gearID)` does not expose enabled capability `\(capabilityID)`."
            )
        }
        guard let schema = argsSchema(gearID: gearID, capabilityID: capabilityID) else {
            return .error(
                toolID: toolID,
                code: "gear.schema_unavailable",
                message: "`\(gearID)` capability `\(capabilityID)` has no host invocation schema yet."
            )
        }
        return .completed(
            toolID: toolID,
            payload: [
                "disclosure_level": "schema",
                "gear_id": gearID,
                "gear_name": capability.gearName,
                "capability_id": capabilityID,
                "title": capability.title,
                "description": capability.description,
                "examples": capability.examples,
                "args_schema": schema
            ]
        )
    }

    private static func invokeGear(
        toolID: String,
        payload: [String: Any]
    ) async -> WorkbenchToolOutcome {
        guard let gearID = payload["gear_id"] as? String, !gearID.isEmpty else {
            return .error(toolID: toolID, code: "gear.args.gear_id", message: "`gear_id` is required.")
        }
        guard let capabilityID = payload["capability_id"] as? String, !capabilityID.isEmpty else {
            return .error(toolID: toolID, code: "gear.args.capability_id", message: "`capability_id` is required.")
        }
        let args = normalizedGearInvokeArgs(from: payload)
        guard GearHost.enabledCapabilityRecord(gearID: gearID, capabilityID: capabilityID) != nil else {
            return .error(
                toolID: toolID,
                code: "gear.capability_unavailable",
                message: "`\(gearID)` does not expose enabled and prepared capability `\(capabilityID)`."
            )
        }

        switch gearID {
        case MediaLibraryGearDescriptor.gearID:
            return await invokeMediaLibrary(toolID: toolID, capabilityID: capabilityID, args: args)
        case SmartYTMediaGearDescriptor.gearID:
            return await invokeSmartYTMedia(toolID: toolID, capabilityID: capabilityID, args: args)
        case TwitterCaptureGearDescriptor.gearID:
            return await invokeTwitterCapture(toolID: toolID, capabilityID: capabilityID, args: args)
        case BookmarkVaultGearDescriptor.gearID:
            return await invokeBookmarkVault(toolID: toolID, capabilityID: capabilityID, args: args)
        case WeSpyReaderGearDescriptor.gearID:
            return await invokeWeSpyReader(toolID: toolID, capabilityID: capabilityID, args: args)
        case MediaGeneratorGearDescriptor.gearID:
            return await invokeMediaGenerator(toolID: toolID, capabilityID: capabilityID, args: args)
        case AppIconForgeGearDescriptor.gearID:
            return invokeAppIconForge(toolID: toolID, capabilityID: capabilityID, args: args)
        case TelegramBridgeGearDescriptor.gearID:
            return await invokeTelegramBridge(toolID: toolID, capabilityID: capabilityID, args: args)
        case TodoManagerGearDescriptor.gearID:
            return await invokeTodoManager(toolID: toolID, capabilityID: capabilityID, args: args)
        default:
            return .error(
                toolID: toolID,
                code: "gear.invoke.unsupported",
                message: "`\(gearID)` is not connected to the Gee host invocation bridge yet."
            )
        }
    }

    static func normalizedGearInvokeArgs(from payload: [String: Any]) -> [String: Any] {
        var args = payload["args"] as? [String: Any] ?? [:]
        if let input = payload["input"] as? [String: Any] {
            for (key, value) in input where args[key] == nil {
                args[key] = value
            }
        }
        let envelopeKeys = Set(["intent", "gear_id", "capability_id", "args", "input"])
        for (key, value) in payload where !envelopeKeys.contains(key) && args[key] == nil {
            args[key] = value
        }
        return args
    }

    private static func invokeAppIconForge(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) -> WorkbenchToolOutcome {
        guard ["app_icon.generate", "gear_icon.generate"].contains(capabilityID) else {
            return .error(
                toolID: toolID,
                code: "gear.app_icon.capability_unsupported",
                message: "app.icon.forge does not support `\(capabilityID)` yet."
            )
        }
        return .completed(
            toolID: toolID,
            payload: AppIconForgeGearStore.shared.runAgentAction(capabilityID: capabilityID, args: args)
        )
    }

    private static func invokeTelegramBridge(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) async -> WorkbenchToolOutcome {
        guard [
            "telegram_bridge.status",
            "telegram_push.list_channels",
            "telegram_push.upsert_channel",
            "telegram_push.send_message",
            "telegram_push.send_file",
            "telegram_direct.send_file"
        ].contains(capabilityID) else {
            return .error(
                toolID: toolID,
                code: "gear.telegram_bridge.capability_unsupported",
                message: "telegram.bridge does not support `\(capabilityID)` yet."
            )
        }
        return .completed(
            toolID: toolID,
            payload: await TelegramBridgeGearStore.shared.runAgentAction(
                capabilityID: capabilityID,
                args: args
            )
        )
    }

    private static func invokeTodoManager(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) async -> WorkbenchToolOutcome {
        switch capabilityID {
        case "todo.create":
            guard let title = stringArg(args, "title", "quick_add_text", "quickAddText"),
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return .error(toolID: toolID, code: "gear.args.title", message: "`title` is required.")
            }
            return .completed(
                toolID: toolID,
                payload: await TodoManagerGearStore.shared.createAgentTodo(args: args)
            )
        case "todo.query":
            return .completed(
                toolID: toolID,
                payload: TodoManagerGearStore.shared.queryAgentTodos(args: args)
            )
        case "todo.update":
            guard let taskID = stringArg(args, "task_id", "taskId", "id"), !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error(toolID: toolID, code: "gear.args.task_id", message: "`task_id` is required.")
            }
            return .completed(
                toolID: toolID,
                payload: await TodoManagerGearStore.shared.updateAgentTodo(args: args)
            )
        case "todo.delete":
            guard let taskID = stringArg(args, "task_id", "taskId", "id"), !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error(toolID: toolID, code: "gear.args.task_id", message: "`task_id` is required.")
            }
            return .completed(
                toolID: toolID,
                payload: await TodoManagerGearStore.shared.deleteAgentTodo(args: args)
            )
        default:
            return .error(
                toolID: toolID,
                code: "gear.todo.capability_unsupported",
                message: "todo.manager does not support `\(capabilityID)` yet."
            )
        }
    }

    private static func invokeMediaGenerator(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) async -> WorkbenchToolOutcome {
        switch capabilityID {
        case "media_generator.list_models":
            return .completed(toolID: toolID, payload: MediaGeneratorGearStore.shared.modelPayload())
        case "media_generator.create_task":
            guard let prompt = stringArg(args, "prompt"), !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error(toolID: toolID, code: "gear.args.prompt", message: "`prompt` is required.")
            }
            var normalizedArgs = args
            normalizedArgs["prompt"] = prompt
            let payload = await MediaGeneratorGearStore.shared.createAgentTask(args: normalizedArgs)
            return .completed(toolID: toolID, payload: payload)
        case "media_generator.get_task":
            return .completed(
                toolID: toolID,
                payload: MediaGeneratorGearStore.shared.taskPayload(
                    taskID: stringArg(args, "task_id"),
                    batchID: stringArg(args, "batch_id")
                )
            )
        default:
            return .error(
                toolID: toolID,
                code: "gear.media_generator.capability_unsupported",
                message: "media.generator does not support `\(capabilityID)` yet."
            )
        }
    }

    private static func invokeBookmarkVault(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) async -> WorkbenchToolOutcome {
        guard capabilityID == "bookmark.save" else {
            return .error(
                toolID: toolID,
                code: "gear.bookmark.capability_unsupported",
                message: "bookmark.vault does not support `\(capabilityID)` yet."
            )
        }
        guard let content = stringArg(args, "content") ?? stringArg(args, "raw_content"),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .error(toolID: toolID, code: "gear.args.content", message: "`content` is required.")
        }

        let payload = await BookmarkVaultGearStore.shared.saveAgentBookmark(
            content: content,
            localMediaPaths: stringArrayArg(args, "local_media_paths")
        )
        return .completed(toolID: toolID, payload: payload)
    }

    private static func invokeWeSpyReader(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) async -> WorkbenchToolOutcome {
        guard ["wespy.fetch_article", "wespy.list_album", "wespy.fetch_album"].contains(capabilityID) else {
            return .error(
                toolID: toolID,
                code: "gear.wespy.capability_unsupported",
                message: "wespy.reader does not support `\(capabilityID)` yet."
            )
        }
        guard stringArg(args, "url") ?? stringArg(args, "article_url") ?? stringArg(args, "album_url") != nil else {
            return .error(toolID: toolID, code: "gear.args.url", message: "`url` is required.")
        }
        let payload = await WeSpyReaderGearStore.shared.runAgentAction(
            capabilityID: capabilityID,
            args: args
        )
        return .completed(toolID: toolID, payload: payload)
    }

    private static func invokeMediaLibrary(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) async -> WorkbenchToolOutcome {
        let store = MediaLibraryModuleStore.shared

        switch capabilityID {
        case "media.focus_folder":
            if let unavailable = await mediaLibraryUnavailableOutcome(
                toolID: toolID,
                capabilityID: capabilityID,
                pendingPaths: []
            ) {
                return unavailable
            }
            guard let folderName = stringArg(args, "folder_name"), !folderName.isEmpty else {
                return .error(toolID: toolID, code: "gear.args.folder_name", message: "`folder_name` is required.")
            }
            guard store.selectFolder(named: folderName) else {
                return .error(
                    toolID: toolID,
                    code: "gear.media.folder_not_found",
                    message: "No media folder matches `\(folderName)`."
                )
            }
            return mediaLibraryCompletionPayload(
                toolID: toolID,
                capabilityID: capabilityID,
                action: "focused_folder"
            )
        case "media.filter":
            if let unavailable = await mediaLibraryUnavailableOutcome(
                toolID: toolID,
                capabilityID: capabilityID,
                pendingPaths: []
            ) {
                return unavailable
            }

            if let folderName = stringArg(args, "folder_name"), !folderName.isEmpty,
               !store.selectFolder(named: folderName)
            {
                return .error(
                    toolID: toolID,
                    code: "gear.media.folder_not_found",
                    message: "No media folder matches `\(folderName)`."
                )
            }

            let mediaKind: MediaLibraryMediaKind?
            if let kind = stringArg(args, "kind") {
                guard let parsed = MediaLibraryMediaKind(rawValue: kind) else {
                    return .error(
                        toolID: toolID,
                        code: "gear.args.kind",
                        message: "`kind` must be all, image, or video."
                    )
                }
                mediaKind = parsed
            } else {
                mediaKind = nil
            }

            store.applyAgentFilter(
                extensions: stringArrayArg(args, "extensions"),
                starredOnly: boolArg(args, "starred_only"),
                mediaKind: mediaKind,
                minimumDurationSeconds: doubleArg(args, "minimum_duration_seconds"),
                searchText: stringArg(args, "search_text") ?? stringArg(args, "query")
            )
            return mediaLibraryCompletionPayload(
                toolID: toolID,
                capabilityID: capabilityID,
                action: "applied_filter"
            )
        case "media.import_files":
            let paths = stringArrayArg(args, "paths") ?? stringArrayArg(args, "file_paths") ?? []
            guard !paths.isEmpty else {
                return .error(
                    toolID: toolID,
                    code: "gear.args.paths",
                    message: "`paths` is required and must include at least one local file path."
                )
            }
            let expandedPaths = paths.map { NSString(string: $0).expandingTildeInPath }
            let missingPaths = expandedPaths.filter { !FileManager.default.fileExists(atPath: $0) }
            let importMetadata = mediaLibraryImportMetadata(from: args)
            if let reviewStatus = importMetadata?.reviewStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reviewStatus.isEmpty,
               !MediaLibraryService.allowedReviewStatuses.contains(reviewStatus)
            {
                return .error(
                    toolID: toolID,
                    code: "gear.media.invalid_review_status",
                    message: "`\(reviewStatus)` is not an allowed media review status."
                )
            }
            do {
                let report = try await store.importMediaForAgentReport(paths: paths, metadata: importMetadata)
                if report.availableItems.isEmpty {
                    return .completed(
                        toolID: toolID,
                        payload: [
                            "gear_id": MediaLibraryGearDescriptor.gearID,
                            "capability_id": capabilityID,
                            "action": "import_skipped",
                            "status": "failed",
                            "code": "gear.media.no_supported_files",
                            "error": "No supported media files were imported or found in the library.",
                            "requested_paths": paths,
                            "missing_paths": missingPaths,
                            "unsupported_paths": report.unsupportedPaths,
                            "duplicate_paths": report.duplicatePaths,
                            "supported_extensions": Array(MediaLibraryService.imageExtensions.union(MediaLibraryService.videoExtensions)).sorted(),
                            "imported_count": 0,
                            "existing_count": 0,
                            "available_count": 0,
                            "library_path": store.library?.url.path ?? NSNull()
                        ]
                    )
                }
                let importAction = report.importedItems.isEmpty ? "import_noop" : "imported_files"
                let importReason = report.importedItems.isEmpty ? "all_duplicates" : "imported_or_reused"
                return .completed(
                    toolID: toolID,
                    payload: [
                        "gear_id": MediaLibraryGearDescriptor.gearID,
                        "capability_id": capabilityID,
                        "action": importAction,
                        "status": "succeeded",
                        "reason": importReason,
                        "requested_paths": paths,
                        "missing_paths": missingPaths,
                        "unsupported_paths": report.unsupportedPaths,
                        "duplicate_paths": report.duplicatePaths,
                        "imported_count": report.importedItems.count,
                        "existing_count": report.existingItems.count,
                        "available_count": report.availableItems.count,
                        "library_path": store.library?.url.path ?? NSNull(),
                        "imported_items": report.importedItems.map { mediaLibraryItemPayload($0) },
                        "existing_items": report.existingItems.map { mediaLibraryItemPayload($0) },
                        "available_items": report.availableItems.map { mediaLibraryItemPayload($0) }
                    ]
                )
            } catch let error as MediaLibraryAgentImportError {
                switch error {
                case .authorizationRequired(let pendingPaths):
                    return mediaLibraryAuthorizationRequiredPayload(
                        toolID: toolID,
                        capabilityID: capabilityID,
                        requestedPaths: paths,
                        pendingPaths: pendingPaths,
                        missingPaths: missingPaths
                    )
                case .libraryLoading:
                    return .error(
                        toolID: toolID,
                        code: "gear.media.library_loading",
                        message: error.localizedDescription
                    )
                case .libraryMissing:
                    return mediaLibraryAuthorizationRequiredPayload(
                        toolID: toolID,
                        capabilityID: capabilityID,
                        requestedPaths: paths,
                        pendingPaths: expandedPaths.filter { FileManager.default.fileExists(atPath: $0) },
                        missingPaths: missingPaths
                    )
                case .noReadableFiles:
                    return .error(
                        toolID: toolID,
                        code: "gear.media.no_readable_files",
                        message: error.localizedDescription
                    )
                }
            } catch {
                return .error(
                    toolID: toolID,
                    code: "gear.media.import_failed",
                    message: error.localizedDescription
                )
            }
        case "media.inspect_assets":
            let itemIDs = stringArrayArg(args, "item_ids") ?? stringArrayArg(args, "ids") ?? []
            let paths = stringArrayArg(args, "paths") ?? stringArrayArg(args, "file_paths") ?? []
            guard !itemIDs.isEmpty || !paths.isEmpty else {
                return .error(
                    toolID: toolID,
                    code: "gear.args.assets",
                    message: "`item_ids` or `paths` is required."
                )
            }
            do {
                let inspections = try await store.inspectAssetsForAgent(itemIDs: itemIDs, paths: paths)
                return .completed(
                    toolID: toolID,
                    payload: [
                        "gear_id": MediaLibraryGearDescriptor.gearID,
                        "capability_id": capabilityID,
                        "status": "succeeded",
                        "assets": inspections.map { mediaLibraryInspectionPayload($0) },
                        "error": NSNull()
                    ]
                )
            } catch let error as MediaLibraryAgentImportError {
                return mediaLibraryErrorOutcome(
                    toolID: toolID,
                    capabilityID: capabilityID,
                    error: error
                )
            } catch {
                return .error(
                    toolID: toolID,
                    code: "gear.media.inspect_failed",
                    message: error.localizedDescription
                )
            }
        case "media.update_review_state":
            let itemIDs = stringArrayArg(args, "item_ids") ?? stringArrayArg(args, "ids") ?? []
            guard !itemIDs.isEmpty else {
                return .error(toolID: toolID, code: "gear.args.item_ids", message: "`item_ids` is required.")
            }
            guard let reviewStatus = stringArg(args, "review_status"), !reviewStatus.isEmpty else {
                return .error(toolID: toolID, code: "gear.args.review_status", message: "`review_status` is required.")
            }
            let manualFlags = stringDictionaryArg(args, "manual_flags")
            do {
                let updated = try await store.updateReviewStateForAgent(
                    itemIDs: itemIDs,
                    reviewStatus: reviewStatus,
                    manualFlags: manualFlags,
                    notes: stringArg(args, "notes")
                )
                let updatedIDs = Set(updated.map(\.id))
                let missingItemIDs = itemIDs.filter { !updatedIDs.contains($0) }
                let status = updated.isEmpty ? "failed" : (missingItemIDs.isEmpty ? "succeeded" : "partial")
                return .completed(
                    toolID: toolID,
                    payload: [
                        "gear_id": MediaLibraryGearDescriptor.gearID,
                        "capability_id": capabilityID,
                        "status": status,
                        "code": updated.isEmpty ? "gear.media.items_not_found" : NSNull(),
                        "updated_items": updated.map(\.id),
                        "missing_item_ids": missingItemIDs,
                        "updated_count": updated.count,
                        "items": updated.map { mediaLibraryItemPayload($0) },
                        "error": updated.isEmpty ? "No requested Media Library items were found." : NSNull()
                    ]
                )
            } catch let error as MediaLibraryAgentImportError {
                return mediaLibraryErrorOutcome(
                    toolID: toolID,
                    capabilityID: capabilityID,
                    error: error
                )
            } catch {
                return .error(
                    toolID: toolID,
                    code: "gear.media.review_update_failed",
                    message: error.localizedDescription
                )
            }
        case "media.search_assets":
            if let unavailable = await mediaLibraryUnavailableOutcome(
                toolID: toolID,
                capabilityID: capabilityID,
                pendingPaths: []
            ) {
                return unavailable
            }
            let filters = dictionaryArg(args, "filters")
            let items = mediaLibrarySearchItems(
                store.items,
                projectID: stringArg(args, "project_id") ?? stringArg(filters, "project_id"),
                runID: stringArg(args, "run_id") ?? stringArg(filters, "run_id"),
                filters: filters,
                limit: intArg(args, "limit") ?? intArg(filters, "limit") ?? 50
            )
            return .completed(
                toolID: toolID,
                payload: [
                    "gear_id": MediaLibraryGearDescriptor.gearID,
                    "capability_id": capabilityID,
                    "status": "succeeded",
                    "items": items.map { mediaLibraryItemPayload($0) },
                    "count": items.count,
                    "error": NSNull()
                ]
            )
        default:
            return .error(
                toolID: toolID,
                code: "gear.media.capability_unsupported",
                message: "media.library does not support `\(capabilityID)` yet."
            )
        }
    }

    private static func invokeSmartYTMedia(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) async -> WorkbenchToolOutcome {
        guard [
            "smartyt.search_candidates",
            "smartyt.sniff",
            "smartyt.download",
            "smartyt.download_now",
            "smartyt.get_task",
            "smartyt.list_tasks"
        ].contains(capabilityID) else {
            return .error(
                toolID: toolID,
                code: "gear.smartyt.capability_unsupported",
                message: "smartyt.media does not support `\(capabilityID)` yet."
            )
        }
        if capabilityID == "smartyt.search_candidates" {
            let payload = await SmartYTMediaGearStore.shared.searchCandidatesForAgent(args: args)
            return .completed(toolID: toolID, payload: payload)
        }
        if capabilityID == "smartyt.get_task" {
            guard let taskID = stringArg(args, "task_id") ?? stringArg(args, "job_id") ?? stringArg(args, "search_task_id") else {
                return .error(toolID: toolID, code: "gear.args.task_id", message: "`task_id` is required.")
            }
            return .completed(
                toolID: toolID,
                payload: SmartYTMediaGearStore.shared.taskPayload(taskID: taskID)
            )
        }
        if capabilityID == "smartyt.list_tasks" {
            return .completed(
                toolID: toolID,
                payload: SmartYTMediaGearStore.shared.listTasksPayload(limit: intArg(args, "limit") ?? 50)
            )
        }
        guard let url = stringArg(args, "url"), !url.isEmpty else {
            return .error(toolID: toolID, code: "gear.args.url", message: "`url` is required.")
        }

        let requestedKind = stringArg(args, "download_kind")
            ?? stringArg(args, "media_type")
            ?? stringArg(args, "download_type")
        let downloadKind: SmartYTDownloadKind?
        if let requestedKind, !requestedKind.isEmpty {
            guard let parsedKind = SmartYTDownloadKind(rawValue: requestedKind) else {
                return .error(
                    toolID: toolID,
                    code: "gear.args.download_kind",
                    message: "`download_kind` must be audio, image, video, or both."
                )
            }
            downloadKind = parsedKind
        } else {
            downloadKind = nil
        }

        if capabilityID == "smartyt.download_now" {
            let payload = await SmartYTMediaGearStore.shared.runImmediateAgentDownload(
                url: url,
                downloadKind: downloadKind,
                outputDirectory: stringArg(args, "output_dir") ?? stringArg(args, "output_directory"),
                cookieFilePath: stringArg(args, "cookie_file") ?? stringArg(args, "cookies_file")
            )
            return .completed(toolID: toolID, payload: payload)
        }

        let payload = SmartYTMediaGearStore.shared.enqueueAgentAction(
            capabilityID: capabilityID,
            url: url,
            downloadKind: downloadKind,
            language: stringArg(args, "language"),
            outputDirectory: stringArg(args, "output_dir") ?? stringArg(args, "output_directory"),
            cookieFilePath: stringArg(args, "cookie_file") ?? stringArg(args, "cookies_file")
        )
        return .completed(toolID: toolID, payload: payload)
    }

    private static func invokeTwitterCapture(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) async -> WorkbenchToolOutcome {
        guard ["twitter.fetch_tweet", "twitter.fetch_list", "twitter.fetch_user"].contains(capabilityID) else {
            return .error(
                toolID: toolID,
                code: "gear.twitter.capability_unsupported",
                message: "twitter.capture does not support `\(capabilityID)` yet."
            )
        }

        switch capabilityID {
        case "twitter.fetch_tweet":
            guard stringArg(args, "url") ?? stringArg(args, "tweet_url") != nil else {
                return .error(toolID: toolID, code: "gear.args.url", message: "`url` is required.")
            }
        case "twitter.fetch_list":
            guard stringArg(args, "url") ?? stringArg(args, "list_url") != nil else {
                return .error(toolID: toolID, code: "gear.args.url", message: "`url` is required.")
            }
        case "twitter.fetch_user":
            guard stringArg(args, "username") ?? stringArg(args, "handle") ?? stringArg(args, "url") != nil else {
                return .error(toolID: toolID, code: "gear.args.username", message: "`username` is required.")
            }
        default:
            break
        }

        let payload = await TwitterCaptureGearStore.shared.runAgentAction(
            capabilityID: capabilityID,
            args: args
        )
        return .completed(toolID: toolID, payload: payload)
    }

    private static func mediaLibraryCompletionPayload(
        toolID: String,
        capabilityID: String,
        action: String
    ) -> WorkbenchToolOutcome {
        let store = MediaLibraryModuleStore.shared
        return .completed(
            toolID: toolID,
            payload: [
                "gear_id": MediaLibraryGearDescriptor.gearID,
                "capability_id": capabilityID,
                "action": action,
                "filtered_count": store.filteredItems.count,
                "total_count": store.items.count,
                "visible_summary": store.visibleSummary,
                "selected_folder_id": store.selectedFolderID ?? NSNull(),
                "filter": [
                    "kind": store.filter.mediaKind.rawValue,
                    "extensions": Array(store.filter.selectedExtensions).sorted(),
                    "starred_only": store.filter.starredOnly,
                    "minimum_duration_seconds": store.filter.minimumDurationSeconds ?? NSNull()
                ]
            ]
        )
    }

    private static func mediaLibraryItemPayload(_ item: MediaLibraryItem) -> [String: Any] {
        let metadata: [String: Any] = [
            "source_url": item.sourceURL ?? NSNull(),
            "project_id": item.projectID ?? NSNull(),
            "run_id": item.runID ?? NSNull(),
            "platform": item.platform ?? NSNull(),
            "source_task_id": item.sourceTaskID ?? NSNull(),
            "beat_id": item.beatID ?? NSNull(),
            "intended_use": item.intendedUse ?? NSNull(),
            "review_status": item.reviewStatus ?? NSNull(),
            "manual_flags": item.manualFlags,
            "notes": item.reviewNotes ?? NSNull()
        ]
        return [
            "item_id": item.id,
            "id": item.id,
            "name": item.name,
            "ext": item.ext,
            "file_path": item.fileURL.path,
            "thumbnail_path": item.thumbnailURL?.path ?? NSNull(),
            "media_type": item.mediaKind.rawValue,
            "media_kind": item.mediaKind.rawValue,
            "duration_seconds": item.durationSeconds ?? NSNull(),
            "duration": item.durationSeconds ?? NSNull(),
            "width": item.width ?? NSNull(),
            "height": item.height ?? NSNull(),
            "orientation": mediaLibraryOrientation(width: item.width, height: item.height) ?? NSNull(),
            "source_url": item.sourceURL ?? NSNull(),
            "tags": item.tags,
            "review_status": item.reviewStatus ?? NSNull(),
            "metadata": metadata
        ]
    }

    private static func mediaLibraryInspectionPayload(_ inspection: MediaLibraryAssetInspection) -> [String: Any] {
        [
            "item_id": inspection.itemID ?? NSNull(),
            "file_path": inspection.filePath,
            "exists": inspection.exists,
            "playable": inspection.playable,
            "duration": inspection.durationSeconds ?? NSNull(),
            "duration_seconds": inspection.durationSeconds ?? NSNull(),
            "width": inspection.width ?? NSNull(),
            "height": inspection.height ?? NSNull(),
            "orientation": inspection.orientation ?? NSNull(),
            "video_codec": inspection.videoCodec ?? NSNull(),
            "audio_codec": inspection.audioCodec ?? NSNull(),
            "errors": inspection.errors
        ]
    }

    private static func mediaLibraryImportMetadata(from args: [String: Any]) -> MediaLibraryImportMetadata? {
        let metadata = dictionaryArg(args, "metadata")
        let manualFlags = stringDictionaryArg(args, "manual_flags").merging(stringDictionaryArg(metadata, "manual_flags")) { _, new in new }
        let tags = (stringArrayArg(args, "tags") ?? []) + (stringArrayArg(metadata, "tags") ?? [])
        let value = MediaLibraryImportMetadata(
            projectID: stringArg(args, "project_id") ?? stringArg(metadata, "project_id"),
            runID: stringArg(args, "run_id") ?? stringArg(metadata, "run_id"),
            sourceURL: stringArg(args, "source_url") ?? stringArg(metadata, "source_url") ?? stringArg(metadata, "url"),
            platform: stringArg(args, "platform") ?? stringArg(metadata, "platform"),
            sourceTaskID: stringArg(args, "source_task_id") ?? stringArg(metadata, "source_task_id"),
            beatID: stringArg(args, "beat_id") ?? stringArg(metadata, "beat_id"),
            intendedUse: stringArg(args, "intended_use") ?? stringArg(metadata, "intended_use"),
            reviewStatus: stringArg(args, "review_status") ?? stringArg(metadata, "review_status"),
            tags: tags,
            manualFlags: manualFlags,
            notes: stringArg(args, "notes") ?? stringArg(metadata, "notes")
        )
        let hasValue = [
            value.projectID,
            value.runID,
            value.sourceURL,
            value.platform,
            value.sourceTaskID,
            value.beatID,
            value.intendedUse,
            value.reviewStatus,
            value.notes
        ].contains { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false } || !value.tags.isEmpty || !value.manualFlags.isEmpty
        return hasValue ? value : nil
    }

    private static func mediaLibrarySearchItems(
        _ items: [MediaLibraryItem],
        projectID: String?,
        runID: String?,
        filters: [String: Any],
        limit: Int
    ) -> [MediaLibraryItem] {
        let reviewStatuses = Set(stringArrayArg(filters, "review_status") ?? stringArg(filters, "review_status").map { [$0] } ?? [])
        let beatID = stringArg(filters, "beat_id")
        let mediaType = stringArg(filters, "media_type") ?? stringArg(filters, "kind")
        let orientation = stringArg(filters, "orientation")
        let requiredTags = Set((stringArrayArg(filters, "tags") ?? []).map { $0.lowercased() })
        let clampedLimit = min(max(limit, 1), 200)
        return Array(items.filter { item in
            if let projectID, !projectID.isEmpty, item.projectID != projectID { return false }
            if let runID, !runID.isEmpty, item.runID != runID { return false }
            if let beatID, !beatID.isEmpty, item.beatID != beatID { return false }
            if !reviewStatuses.isEmpty, !reviewStatuses.contains(item.reviewStatus ?? "") { return false }
            if let mediaType, !mediaType.isEmpty, mediaType != "all", item.mediaKind.rawValue != mediaType { return false }
            if let orientation, !orientation.isEmpty, orientation != "any",
               mediaLibraryOrientation(width: item.width, height: item.height) != orientation
            {
                return false
            }
            if !requiredTags.isEmpty {
                let itemTags = Set(item.tags.map { $0.lowercased() })
                if !requiredTags.isSubset(of: itemTags) { return false }
            }
            return true
        }.prefix(clampedLimit))
    }

    private static func mediaLibraryOrientation(width: Int?, height: Int?) -> String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        if width == height { return "square" }
        return width > height ? "horizontal" : "vertical"
    }

    private static func mediaLibraryErrorOutcome(
        toolID: String,
        capabilityID: String,
        error: MediaLibraryAgentImportError
    ) -> WorkbenchToolOutcome {
        switch error {
        case .authorizationRequired(let pendingPaths):
            return mediaLibraryAuthorizationRequiredPayload(
                toolID: toolID,
                capabilityID: capabilityID,
                requestedPaths: pendingPaths,
                pendingPaths: pendingPaths,
                missingPaths: []
            )
        case .libraryLoading:
            return .error(toolID: toolID, code: "gear.media.library_loading", message: error.localizedDescription)
        case .libraryMissing:
            return mediaLibraryAuthorizationRequiredPayload(
                toolID: toolID,
                capabilityID: capabilityID,
                requestedPaths: [],
                pendingPaths: [],
                missingPaths: []
            )
        case .noReadableFiles:
            return .error(toolID: toolID, code: "gear.media.no_readable_files", message: error.localizedDescription)
        }
    }

    private static func mediaLibraryUnavailableOutcome(
        toolID: String,
        capabilityID: String,
        pendingPaths: [String]
    ) async -> WorkbenchToolOutcome? {
        let store = MediaLibraryModuleStore.shared
        do {
            _ = try await store.ensureLibraryForAgent(pendingPaths: pendingPaths)
            return nil
        } catch let error as MediaLibraryAgentImportError {
            switch error {
            case .libraryLoading:
                return .error(
                    toolID: toolID,
                    code: "gear.media.library_loading",
                    message: error.localizedDescription
                )
            case .authorizationRequired(let paths):
                return mediaLibraryAuthorizationRequiredPayload(
                    toolID: toolID,
                    capabilityID: capabilityID,
                    requestedPaths: pendingPaths,
                    pendingPaths: paths,
                    missingPaths: []
                )
            case .libraryMissing:
                return mediaLibraryAuthorizationRequiredPayload(
                    toolID: toolID,
                    capabilityID: capabilityID,
                    requestedPaths: pendingPaths,
                    pendingPaths: pendingPaths,
                    missingPaths: []
                )
            case .noReadableFiles:
                return .error(
                    toolID: toolID,
                    code: "gear.media.no_readable_files",
                    message: error.localizedDescription
                )
            }
        } catch {
            return mediaLibraryAuthorizationRequiredPayload(
                toolID: toolID,
                capabilityID: capabilityID,
                requestedPaths: pendingPaths,
                pendingPaths: pendingPaths,
                missingPaths: []
            )
        }
    }

    private static func mediaLibraryAuthorizationRequiredPayload(
        toolID: String,
        capabilityID: String,
        requestedPaths: [String],
        pendingPaths: [String],
        missingPaths: [String]
    ) -> WorkbenchToolOutcome {
        .completed(
            toolID: toolID,
            payload: [
                "gear_id": MediaLibraryGearDescriptor.gearID,
                "capability_id": capabilityID,
                "action": "authorization_required",
                "status": "failed",
                "code": "gear.media.authorization_required",
                "error": "Media Library needs macOS access to a library before this action can continue.",
                "recovery": "Open Media Library and choose or create a library. GeeAgent will keep the pending local media paths so the agent can retry after authorization.",
                "requested_paths": requestedPaths,
                "pending_paths": pendingPaths,
                "missing_paths": missingPaths,
                "intent": "navigate.module",
                "module_id": MediaLibraryGearDescriptor.gearID
            ]
        )
    }

    private static func argsSchema(gearID: String, capabilityID: String) -> [String: Any]? {
        switch (gearID, capabilityID) {
        case (TelegramBridgeGearDescriptor.gearID, "telegram_bridge.status"):
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [:]
            ]
        case (TelegramBridgeGearDescriptor.gearID, "telegram_push.list_channels"):
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "enabled_only": ["type": "boolean"]
                ]
            ]
        case (TelegramBridgeGearDescriptor.gearID, "telegram_push.upsert_channel"):
            return [
                "type": "object",
                "required": ["channel_id", "account_id", "target_kind", "target_value"],
                "additionalProperties": false,
                "properties": [
                    "channel_id": ["type": "string"],
                    "account_id": ["type": "string"],
                    "title": ["type": "string"],
                    "bot_username": ["type": "string"],
                    "target_kind": [
                        "type": "string",
                        "enum": ["chat_id", "group_id", "channel_id", "channel_username"]
                    ],
                    "target_value": ["type": "string"],
                    "enabled": ["type": "boolean"],
                    "parse_mode": [
                        "type": "string",
                        "enum": ["Markdown", "MarkdownV2", "HTML", "plain"]
                    ],
                    "disable_web_preview": ["type": "boolean"]
                ]
            ]
        case (TelegramBridgeGearDescriptor.gearID, "telegram_push.send_message"):
            return [
                "type": "object",
                "required": ["channel_id", "message", "idempotency_key"],
                "additionalProperties": false,
                "properties": [
                    "channel_id": ["type": "string"],
                    "message": ["type": "string"],
                    "idempotency_key": ["type": "string"],
                    "parse_mode": [
                        "type": "string",
                        "enum": ["Markdown", "MarkdownV2", "HTML", "plain"]
                    ],
                    "disable_web_preview": ["type": "boolean"]
                ]
            ]
        case (TelegramBridgeGearDescriptor.gearID, "telegram_push.send_file"):
            return [
                "type": "object",
                "required": ["channel_id", "file_path", "idempotency_key"],
                "additionalProperties": false,
                "properties": [
                    "channel_id": ["type": "string"],
                    "file_path": ["type": "string"],
                    "caption": ["type": "string"],
                    "idempotency_key": ["type": "string"]
                ]
            ]
        case (TelegramBridgeGearDescriptor.gearID, "telegram_direct.send_file"):
            return [
                "type": "object",
                "required": ["file_path", "idempotency_key"],
                "additionalProperties": false,
                "properties": [
                    "file_path": ["type": "string"],
                    "caption": ["type": "string"],
                    "idempotency_key": ["type": "string"],
                    "account_id": ["type": "string"],
                    "chat_id": ["type": "string"]
                ]
            ]
        case (TodoManagerGearDescriptor.gearID, "todo.create"):
            return [
                "type": "object",
                "required": ["title"],
                "additionalProperties": false,
                "properties": [
                    "title": ["type": "string"],
                    "content": ["type": "string"],
                    "list_id": ["type": "string"],
                    "list_name": ["type": "string"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "priority": ["type": "integer", "enum": [0, 1, 3, 5]],
                    "start_at": ["type": "string"],
                    "due_at": ["type": "string"],
                    "timezone": ["type": "string"],
                    "is_all_day": ["type": "boolean"],
                    "reminders": ["type": "array", "items": ["type": "object"]],
                    "repeat_rrule": ["type": "string"],
                    "checklist_items": ["type": "array", "items": ["type": "string"]]
                ]
            ]
        case (TodoManagerGearDescriptor.gearID, "todo.query"):
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "status": ["type": "string", "enum": ["open", "completed", "deleted", "all"]],
                    "list_id": ["type": "string"],
                    "list_name": ["type": "string"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "priority": ["type": "array", "items": ["type": "integer", "enum": [0, 1, 3, 5]]],
                    "due": ["type": "string", "enum": ["today", "upcoming", "overdue", "none", "any"]],
                    "start_at": ["type": "string"],
                    "end_at": ["type": "string"],
                    "search_text": ["type": "string"],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 200]
                ]
            ]
        case (TodoManagerGearDescriptor.gearID, "todo.update"):
            return [
                "type": "object",
                "required": ["task_id"],
                "additionalProperties": false,
                "properties": [
                    "task_id": ["type": "string"],
                    "title": ["type": "string"],
                    "content": ["type": "string"],
                    "list_id": ["type": "string"],
                    "list_name": ["type": "string"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "priority": ["type": "integer", "enum": [0, 1, 3, 5]],
                    "status": ["type": "string", "enum": ["open", "completed"]],
                    "completed": ["type": "boolean"],
                    "start_at": ["type": "string"],
                    "due_at": ["type": "string"],
                    "clear_start": ["type": "boolean"],
                    "clear_due": ["type": "boolean"],
                    "timezone": ["type": "string"],
                    "is_all_day": ["type": "boolean"],
                    "reminders": ["type": "array", "items": ["type": "object"]],
                    "repeat_rrule": ["type": "string"],
                    "checklist_items": ["type": "array", "items": ["type": "string"]]
                ]
            ]
        case (TodoManagerGearDescriptor.gearID, "todo.delete"):
            return [
                "type": "object",
                "required": ["task_id"],
                "additionalProperties": false,
                "properties": [
                    "task_id": ["type": "string"]
                ]
            ]
        case (MediaLibraryGearDescriptor.gearID, "media.filter"):
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "kind": ["type": "string", "enum": ["all", "image", "video"]],
                    "extensions": ["type": "array", "items": ["type": "string"]],
                    "starred_only": ["type": "boolean"],
                    "minimum_duration_seconds": ["type": "number"],
                    "search_text": ["type": "string"],
                    "folder_name": ["type": "string"]
                ]
            ]
        case (MediaLibraryGearDescriptor.gearID, "media.focus_folder"):
            return [
                "type": "object",
                "required": ["folder_name"],
                "additionalProperties": false,
                "properties": [
                    "folder_name": ["type": "string"]
                ]
            ]
        case (SmartYTMediaGearDescriptor.gearID, "smartyt.sniff"):
            return [
                "type": "object",
                "required": ["url"],
                "additionalProperties": false,
                "properties": [
                    "url": ["type": "string", "format": "uri"],
                    "cookie_file": [
                        "type": "string",
                        "description": "Optional local yt-dlp cookies.txt path. Defaults to the SmartYT saved cookie file when configured."
                    ]
                ]
            ]
        case (SmartYTMediaGearDescriptor.gearID, "smartyt.search_candidates"):
            return [
                "type": "object",
                "required": ["query"],
                "additionalProperties": false,
                "properties": [
                    "project_id": ["type": "string"],
                    "run_id": ["type": "string"],
                    "task_label": ["type": "string"],
                    "query": ["type": "string"],
                    "platforms": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Search platforms. Current host execution supports youtube search and returns explicit warnings for unsupported platforms."
                    ],
                    "filters": [
                        "type": "object",
                        "additionalProperties": ["type": ["string", "number", "boolean"]]
                    ],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 50],
                    "cookie_file": [
                        "type": "string",
                        "description": "Optional local yt-dlp cookies.txt path. Defaults to the SmartYT saved cookie file when configured."
                    ]
                ]
            ]
        case (SmartYTMediaGearDescriptor.gearID, "smartyt.get_task"):
            return [
                "type": "object",
                "required": ["task_id"],
                "additionalProperties": false,
                "properties": [
                    "task_id": ["type": "string"]
                ]
            ]
        case (SmartYTMediaGearDescriptor.gearID, "smartyt.list_tasks"):
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "limit": ["type": "integer", "minimum": 1, "maximum": 200]
                ]
            ]
        case (SmartYTMediaGearDescriptor.gearID, "smartyt.download"):
            return [
                "type": "object",
                "required": ["url"],
                "additionalProperties": false,
                "properties": [
                    "url": ["type": "string", "format": "uri"],
                    "download_kind": ["type": "string", "enum": ["audio", "image", "video", "both"]],
                    "output_dir": ["type": "string"],
                    "cookie_file": [
                        "type": "string",
                        "description": "Optional local yt-dlp cookies.txt path. Defaults to the SmartYT saved cookie file when configured."
                    ]
                ]
            ]
        case (SmartYTMediaGearDescriptor.gearID, "smartyt.download_now"):
            return [
                "type": "object",
                "required": ["url"],
                "additionalProperties": false,
                "properties": [
                    "url": ["type": "string", "format": "uri"],
                    "download_kind": ["type": "string", "enum": ["audio", "image", "video", "both"]],
                    "output_dir": [
                        "type": "string",
                        "description": "Optional local directory for completed artifacts. Defaults to ~/Downloads/SmartYT/<job-id>."
                    ],
                    "cookie_file": [
                        "type": "string",
                        "description": "Optional local yt-dlp cookies.txt path. Defaults to the SmartYT saved cookie file when configured."
                    ]
                ]
            ]
        case (TwitterCaptureGearDescriptor.gearID, "twitter.fetch_tweet"):
            return [
                "type": "object",
                "required": ["url"],
                "additionalProperties": false,
                "properties": [
                    "url": ["type": "string", "format": "uri"],
                    "cookie_file": ["type": "string"]
                ]
            ]
        case (TwitterCaptureGearDescriptor.gearID, "twitter.fetch_list"):
            return [
                "type": "object",
                "required": ["url"],
                "additionalProperties": false,
                "properties": [
                    "url": ["type": "string", "format": "uri"],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 200],
                    "cookie_file": ["type": "string"]
                ]
            ]
        case (TwitterCaptureGearDescriptor.gearID, "twitter.fetch_user"):
            return [
                "type": "object",
                "required": ["username"],
                "additionalProperties": false,
                "properties": [
                    "username": ["type": "string"],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 200],
                    "cookie_file": ["type": "string"]
                ]
            ]
        case (WeSpyReaderGearDescriptor.gearID, "wespy.fetch_article"):
            return [
                "type": "object",
                "required": ["url"],
                "additionalProperties": false,
                "properties": [
                    "url": ["type": "string", "format": "uri"],
                    "save_html": ["type": "boolean"],
                    "save_json": ["type": "boolean"]
                ]
            ]
        case (WeSpyReaderGearDescriptor.gearID, "wespy.list_album"):
            return [
                "type": "object",
                "required": ["url"],
                "additionalProperties": false,
                "properties": [
                    "url": ["type": "string", "format": "uri"],
                    "max_articles": ["type": "integer", "minimum": 1, "maximum": 200]
                ]
            ]
        case (WeSpyReaderGearDescriptor.gearID, "wespy.fetch_album"):
            return [
                "type": "object",
                "required": ["url"],
                "additionalProperties": false,
                "properties": [
                    "url": ["type": "string", "format": "uri"],
                    "max_articles": ["type": "integer", "minimum": 1, "maximum": 200],
                    "save_html": ["type": "boolean"],
                    "save_json": ["type": "boolean"],
                    "export_markdown": ["type": "boolean"]
                ]
            ]
        case (BookmarkVaultGearDescriptor.gearID, "bookmark.save"):
            return [
                "type": "object",
                "required": ["content"],
                "additionalProperties": false,
                "properties": [
                    "content": [
                        "type": "string",
                        "description": "Any user-provided content to save. If it contains a URL, Bookmark Vault enriches the bookmark with link metadata when available."
                    ],
                    "local_media_paths": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Optional local media paths associated with this bookmark, usually imported Media Library item paths."
                    ]
                ]
            ]
        case (MediaGeneratorGearDescriptor.gearID, "media_generator.list_models"):
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [:]
            ]
        case (MediaGeneratorGearDescriptor.gearID, "media_generator.create_task"):
            return [
                "type": "object",
                "required": ["prompt"],
                "additionalProperties": false,
                "properties": [
                    "prompt": ["type": "string"],
                    "category": ["type": "string", "enum": ["image", "video"]],
                    "model": [
                        "type": "string",
                        "enum": [
                            "nano-banana-pro",
                            "gpt-image-2",
                            "image-2",
                            "veo3.1",
                            "veo3.1_fast",
                            "veo3.1_lite",
                            "seedance-2",
                            "seedance-2-fast",
                            "seedance2.0",
                            "seedance2.0-fast"
                        ],
                        "description": "Use gpt-image-2 for GPT Image-2. image-2 is accepted as an alias. Video models use Xenodia Veo3.1 or Seedance 2.0 IDs."
                    ],
                    "n": [
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 1,
                        "description": "Image-only provider count. Xenodia image generation currently supports only 1 image per request."
                    ],
                    "batch_count": [
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 4,
                        "description": "Gear-level fan-out for image and video. Gee creates one Xenodia task per requested result and returns one grouped batch result."
                    ],
                    "async": [
                        "type": "boolean",
                        "description": "Image task switch. Video generation is task-only and always polls Xenodia task retrieval."
                    ],
                    "response_format": [
                        "type": "string",
                        "enum": ["url"],
                        "description": "Only URL responses are currently supported."
                    ],
                    "aspect_ratio": [
                        "type": "string",
                        "enum": ["auto", "adaptive", "1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"],
                        "description": "Supported values vary by selected image or video model. Veo accepts 16:9, 9:16, or auto. Seedance accepts adaptive, 1:1, 4:3, 3:4, 16:9, 9:16, or 21:9."
                    ],
                    "resolution": [
                        "type": "string",
                        "enum": ["1K", "2K", "4K", "480p", "720p", "1080p", "4k"],
                        "description": "Supported values vary by model. Image models use K resolutions; video models use 480p, 720p, 1080p, or Veo 4k where supported."
                    ],
                    "output_format": [
                        "type": "string",
                        "enum": ["png", "jpg"],
                        "description": "Nano Banana Pro only."
                    ],
                    "generation_type": [
                        "type": "string",
                        "enum": ["TEXT_2_VIDEO", "FIRST_AND_LAST_FRAMES_2_VIDEO", "REFERENCE_2_VIDEO"],
                        "description": "Veo mode. REFERENCE_2_VIDEO requires veo3.1_fast. Seedance uses this as Gee UI intent for text, first/last frame, or reference modes."
                    ],
                    "duration": [
                        "type": "integer",
                        "minimum": 4,
                        "maximum": 15,
                        "description": "Seedance 2.0 duration in seconds."
                    ],
                    "first_frame_url": [
                        "type": "string",
                        "description": "Seedance first frame image URL or asset:// ID. Also accepted by Gee as a frame URL for Veo FIRST_AND_LAST_FRAMES_2_VIDEO."
                    ],
                    "last_frame_url": [
                        "type": "string",
                        "description": "Seedance last frame image URL or asset:// ID. Requires first_frame_url."
                    ],
                    "reference_urls": [
                        "type": "array",
                        "maxItems": 16,
                        "items": ["type": "string"],
                        "description": "Remote reference image URLs. Image models pass them as Xenodia image_input. Veo passes them as imageUrls. Seedance passes them as reference_image_urls unless first/last frame URLs are used."
                    ],
                    "image_urls": [
                        "type": "array",
                        "maxItems": 9,
                        "items": ["type": "string"],
                        "description": "Alias for video/image reference URLs."
                    ],
                    "reference_image_urls": [
                        "type": "array",
                        "maxItems": 9,
                        "items": ["type": "string"],
                        "description": "Seedance multimodal reference image URLs or asset:// IDs. Gear validation enforces model limits."
                    ],
                    "reference_video_urls": [
                        "type": "array",
                        "maxItems": 3,
                        "items": ["type": "string"],
                        "description": "Seedance multimodal reference video URLs or asset:// IDs."
                    ],
                    "reference_audio_urls": [
                        "type": "array",
                        "maxItems": 3,
                        "items": ["type": "string"],
                        "description": "Seedance multimodal reference audio URLs or asset:// IDs."
                    ],
                    "reference_paths": [
                        "type": "array",
                        "maxItems": 16,
                        "items": ["type": "string"],
                        "description": "Local JPEG, PNG, or WebP reference image paths, up to 30MB each. Image tasks send them as multipart references; video tasks upload them through the configured Xenodia storage upload URL before generation."
                    ],
                    "generate_audio": [
                        "type": "boolean",
                        "description": "Seedance 2.0 only."
                    ],
                    "web_search": [
                        "type": "boolean",
                        "description": "Seedance 2.0 only."
                    ],
                    "nsfw_checker": [
                        "type": "boolean",
                        "description": "Seedance 2.0 only."
                    ],
                    "seed": [
                        "type": "integer",
                        "minimum": 10000,
                        "maximum": 99999,
                        "description": "Veo3.1 seeds parameter."
                    ],
                    "enable_translation": [
                        "type": "boolean",
                        "description": "Veo3.1 enableTranslation parameter."
                    ],
                    "watermark": [
                        "type": "string",
                        "description": "Veo3.1 watermark text."
                    ],
                    "callback_url": [
                        "type": "string",
                        "description": "Optional Xenodia callBackUrl."
                    ]
                ]
            ]
        case (MediaGeneratorGearDescriptor.gearID, "media_generator.get_task"):
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "task_id": ["type": "string"],
                    "batch_id": ["type": "string"]
                ]
            ]
        case (MediaLibraryGearDescriptor.gearID, "media.import_files"):
            return [
                "type": "object",
                "required": ["paths"],
                "additionalProperties": false,
                "properties": [
                    "paths": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Local media file paths to import into the currently open media library."
                    ],
                    "project_id": ["type": "string"],
                    "run_id": ["type": "string"],
                    "metadata": [
                        "type": "object",
                        "additionalProperties": true,
                        "description": "Optional explicit source/review metadata to store on imported or duplicate media items."
                    ]
                ]
            ]
        case (MediaLibraryGearDescriptor.gearID, "media.inspect_assets"):
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "item_ids": ["type": "array", "items": ["type": "string"]],
                    "paths": ["type": "array", "items": ["type": "string"]]
                ]
            ]
        case (MediaLibraryGearDescriptor.gearID, "media.update_review_state"):
            return [
                "type": "object",
                "required": ["item_ids", "review_status"],
                "additionalProperties": false,
                "properties": [
                    "item_ids": ["type": "array", "items": ["type": "string"]],
                    "review_status": [
                        "type": "string",
                        "enum": ["pending_review", "draft_usable", "final_usable", "not_suitable", "needs_replacement"]
                    ],
                    "manual_flags": ["type": "object", "additionalProperties": ["type": "string"]],
                    "notes": ["type": "string"]
                ]
            ]
        case (MediaLibraryGearDescriptor.gearID, "media.search_assets"):
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "project_id": ["type": "string"],
                    "run_id": ["type": "string"],
                    "filters": ["type": "object", "additionalProperties": true],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 200]
                ]
            ]
        case (AppIconForgeGearDescriptor.gearID, "app_icon.generate"):
            return [
                "type": "object",
                "required": ["source_path"],
                "additionalProperties": false,
                "properties": [
                    "source_path": [
                        "type": "string",
                        "description": "Local image path selected or supplied by the user."
                    ],
                    "output_dir": [
                        "type": "string",
                        "description": "Optional local directory for generated .icns, .iconset, and .appiconset artifacts."
                    ],
                    "name": [
                        "type": "string",
                        "description": "Output base name. Defaults to AppIcon."
                    ],
                    "content_scale": [
                        "type": "number",
                        "minimum": 0.6,
                        "maximum": 0.95
                    ],
                    "corner_radius_ratio": [
                        "type": "number",
                        "minimum": 0.08,
                        "maximum": 0.28
                    ],
                    "shadow": [
                        "type": "boolean"
                    ]
                ]
            ]
        case (AppIconForgeGearDescriptor.gearID, "gear_icon.generate"):
            return [
                "type": "object",
                "required": ["source_path"],
                "additionalProperties": false,
                "properties": [
                    "source_path": [
                        "type": "string",
                        "description": "Local image path selected or supplied by the user."
                    ],
                    "output_dir": [
                        "type": "string",
                        "description": "Optional local directory for the generated assets/icon.png gear catalog icon."
                    ],
                    "name": [
                        "type": "string",
                        "description": "Output folder base name. Defaults to GearIcon."
                    ],
                    "content_scale": [
                        "type": "number",
                        "minimum": 0.6,
                        "maximum": 0.95
                    ],
                    "corner_radius_ratio": [
                        "type": "number",
                        "minimum": 0.08,
                        "maximum": 0.28
                    ],
                    "shadow": [
                        "type": "boolean"
                    ]
                ]
            ]
        default:
            return nil
        }
    }

    private static func stringArg(_ args: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = args[key] as? String {
                return value
            }
        }
        return nil
    }

    private static func boolArg(_ args: [String: Any], _ key: String) -> Bool? {
        args[key] as? Bool
    }

    private static func doubleArg(_ args: [String: Any], _ key: String) -> Double? {
        if let double = args[key] as? Double {
            return double
        }
        if let int = args[key] as? Int {
            return Double(int)
        }
        return nil
    }

    private static func intArg(_ args: [String: Any], _ key: String) -> Int? {
        if let int = args[key] as? Int {
            return int
        }
        if let double = args[key] as? Double {
            return Int(double)
        }
        if let string = args[key] as? String {
            return Int(string)
        }
        return nil
    }

    private static func stringArrayArg(_ args: [String: Any], _ key: String) -> [String]? {
        args[key] as? [String]
    }

    private static func dictionaryArg(_ args: [String: Any], _ key: String) -> [String: Any] {
        args[key] as? [String: Any] ?? [:]
    }

    private static func stringDictionaryArg(_ args: [String: Any], _ key: String) -> [String: String] {
        guard let dictionary = args[key] as? [String: Any] else {
            return [:]
        }
        return dictionary.reduce(into: [String: String]()) { output, entry in
            if let string = entry.value as? String {
                output[entry.key] = string
            }
        }
    }

    private static func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }
}
