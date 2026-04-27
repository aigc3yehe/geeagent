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

        switch detail {
        case "summary":
            return .completed(
                toolID: toolID,
                payload: summaryPayload(records: records)
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

    private static func summaryPayload(records: [GearCapabilityRecord]) -> [String: Any] {
        let grouped = Dictionary(grouping: records, by: \.gearID)
        let gears = grouped.keys.sorted().compactMap { gearID -> [String: Any]? in
            guard let capabilities = grouped[gearID], let first = capabilities.first else {
                return nil
            }
            return [
                "gear_id": gearID,
                "gear_name": first.gearName,
                "capability_count": capabilities.count,
                "capability_ids": capabilities.map(\.capabilityID).sorted()
            ]
        }
        return [
            "disclosure_level": "summary",
            "tool": "gee.gear.listCapabilities",
            "next_step": "Call with detail=capabilities and one gear_id before invoking a capability.",
            "gears": gears
        ]
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
                "next_step": "Call with detail=schema, this gear_id, and one capability_id before invoking.",
                "capabilities": capabilities.map { capability in
                    [
                        "capability_id": capability.capabilityID,
                        "title": capability.title,
                        "description": capability.description
                    ]
                }
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
        let args = payload["args"] as? [String: Any] ?? [:]

        switch gearID {
        case MediaLibraryGearDescriptor.gearID:
            return invokeMediaLibrary(toolID: toolID, capabilityID: capabilityID, args: args)
        case SmartYTMediaGearDescriptor.gearID:
            return invokeSmartYTMedia(toolID: toolID, capabilityID: capabilityID, args: args)
        case TwitterCaptureGearDescriptor.gearID:
            return await invokeTwitterCapture(toolID: toolID, capabilityID: capabilityID, args: args)
        case BookmarkVaultGearDescriptor.gearID:
            return await invokeBookmarkVault(toolID: toolID, capabilityID: capabilityID, args: args)
        default:
            return .error(
                toolID: toolID,
                code: "gear.invoke.unsupported",
                message: "`\(gearID)` is not connected to the Gee host invocation bridge yet."
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

        let payload = await BookmarkVaultGearStore.shared.saveAgentBookmark(content: content)
        return .completed(toolID: toolID, payload: payload)
    }

    private static func invokeMediaLibrary(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) -> WorkbenchToolOutcome {
        let store = MediaLibraryModuleStore.shared

        switch capabilityID {
        case "media.focus_folder":
            guard store.library != nil else {
                return .error(
                    toolID: toolID,
                    code: "gear.media.library_missing",
                    message: "Open or create a media library before focusing a media folder."
                )
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
    ) -> WorkbenchToolOutcome {
        guard ["smartyt.sniff", "smartyt.download", "smartyt.transcribe"].contains(capabilityID) else {
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
                    message: "`download_kind` must be audio, video, or both."
                )
            }
            downloadKind = parsedKind
        } else {
            downloadKind = nil
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
                    "download_kind": ["type": "string", "enum": ["audio", "video", "both"]],
                    "output_dir": ["type": "string"]
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
        case (BookmarkVaultGearDescriptor.gearID, "bookmark.save"):
            return [
                "type": "object",
                "required": ["content"],
                "additionalProperties": false,
                "properties": [
                    "content": [
                        "type": "string",
                        "description": "Any user-provided content to save. If it contains a URL, Bookmark Vault enriches the bookmark with link metadata when available."
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
}
