import Foundation

@MainActor
enum GeeHostToolRouter {
    static func resolveCompletedIntent(_ outcome: WorkbenchToolOutcome) -> WorkbenchToolOutcome? {
        guard case let .completed(toolID, payload) = outcome,
              let intent = payload["intent"] as? String
        else {
            return nil
        }

        switch intent {
        case "gear.list_capabilities":
            return listCapabilities(toolID: toolID, payload: payload)
        case "gear.invoke":
            return invokeGear(toolID: toolID, payload: payload)
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
    ) -> WorkbenchToolOutcome {
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
        default:
            return .error(
                toolID: toolID,
                code: "gear.invoke.unsupported",
                message: "`\(gearID)` is not connected to the Gee host invocation bridge yet."
            )
        }
    }

    private static func invokeMediaLibrary(
        toolID: String,
        capabilityID: String,
        args: [String: Any]
    ) -> WorkbenchToolOutcome {
        let store = MediaLibraryModuleStore.shared
        guard store.library != nil else {
            return .error(
                toolID: toolID,
                code: "gear.media.library_missing",
                message: "Open or create a media library before invoking media.library."
            )
        }

        switch capabilityID {
        case "media.focus_folder":
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
