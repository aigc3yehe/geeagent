import Foundation

@MainActor
enum GeeHostToolRouter {
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
        default:
            return nil
        }
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
                payload: MediaGeneratorGearStore.shared.taskPayload(taskID: stringArg(args, "task_id"))
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
            do {
                let report = try await store.importMediaForAgentReport(paths: paths)
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
        guard ["smartyt.sniff", "smartyt.download", "smartyt.download_now", "smartyt.transcribe"].contains(capabilityID) else {
            return .error(
                toolID: toolID,
                code: "gear.smartyt.capability_unsupported",
                message: "smartyt.media does not support `\(capabilityID)` yet."
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
                outputDirectory: stringArg(args, "output_dir") ?? stringArg(args, "output_directory")
            )
            return .completed(toolID: toolID, payload: payload)
        }

        let payload = SmartYTMediaGearStore.shared.enqueueAgentAction(
            capabilityID: capabilityID,
            url: url,
            downloadKind: downloadKind,
            language: stringArg(args, "language"),
            outputDirectory: stringArg(args, "output_dir") ?? stringArg(args, "output_directory")
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
        [
            "id": item.id,
            "name": item.name,
            "ext": item.ext,
            "file_path": item.fileURL.path,
            "media_kind": item.mediaKind.rawValue,
            "duration_seconds": item.durationSeconds ?? NSNull()
        ]
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
                    "url": ["type": "string", "format": "uri"]
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
                    "output_dir": ["type": "string"]
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
                    ]
                ]
            ]
        case (SmartYTMediaGearDescriptor.gearID, "smartyt.transcribe"):
            return [
                "type": "object",
                "required": ["url"],
                "additionalProperties": false,
                "properties": [
                    "url": ["type": "string", "format": "uri"],
                    "language": ["type": "string"],
                    "output_dir": ["type": "string"]
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
                    "category": ["type": "string", "enum": ["image", "video", "audio"]],
                    "model": ["type": "string", "enum": ["nano-banana-pro", "gpt-image-2"]],
                    "n": [
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 1,
                        "description": "Xenodia image generation currently supports only 1 image per request."
                    ],
                    "async": [
                        "type": "boolean",
                        "description": "When true, create an async Xenodia task and poll the task endpoint. Gee defaults this to true."
                    ],
                    "response_format": [
                        "type": "string",
                        "enum": ["url"],
                        "description": "Only URL responses are currently supported."
                    ],
                    "aspect_ratio": [
                        "type": "string",
                        "enum": ["auto", "1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"],
                        "description": "Supported by both Nano Banana Pro and GPT Image-2. Defaults to 1:1 for Nano and auto for GPT Image-2."
                    ],
                    "resolution": [
                        "type": "string",
                        "enum": ["1K", "2K", "4K"],
                        "description": "Nano Banana Pro only."
                    ],
                    "output_format": [
                        "type": "string",
                        "enum": ["png", "jpg"],
                        "description": "Nano Banana Pro only."
                    ],
                    "nsfw_checker": [
                        "type": "boolean",
                        "description": "GPT Image-2 only."
                    ],
                    "reference_urls": [
                        "type": "array",
                        "maxItems": 8,
                        "items": ["type": "string"],
                        "description": "Remote reference image URLs passed as Xenodia image_input."
                    ],
                    "reference_paths": [
                        "type": "array",
                        "maxItems": 8,
                        "items": ["type": "string"],
                        "description": "Optional local JPEG, PNG, or WebP image paths, up to 30MB each. The Gear sends them through the global Xenodia channel instead of Qiniu."
                    ]
                ]
            ]
        case (MediaGeneratorGearDescriptor.gearID, "media_generator.get_task"):
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "task_id": ["type": "string"]
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
                    ]
                ]
            ]
        default:
            return nil
        }
    }

    private static func stringArg(_ args: [String: Any], _ key: String) -> String? {
        args[key] as? String
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

    private static func stringArrayArg(_ args: [String: Any], _ key: String) -> [String]? {
        args[key] as? [String]
    }

    private static func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }
}
