import Foundation

enum Live2DAssetSource: String, Hashable {
    case model3
    case vtube
    case scanned
}

enum Live2DMotionCategory: String, Hashable {
    case pose
    case action
}

struct Live2DMotionRecord: Identifiable, Hashable {
    let id: String
    var title: String
    var relativePath: String
    var source: Live2DAssetSource
    var category: Live2DMotionCategory
    var isLoop: Bool
    var durationSeconds: Double?
}

struct Live2DExpressionRecord: Identifiable, Hashable {
    let id: String
    var title: String
    var relativePath: String
    var source: Live2DAssetSource
}

struct Live2DActionCatalog: Hashable {
    var defaultPose: Live2DMotionRecord?
    var fallbackPose: Live2DMotionRecord?
    var poses: [Live2DMotionRecord]
    var actions: [Live2DMotionRecord]
    var expressions: [Live2DExpressionRecord]

    static let empty = Live2DActionCatalog(
        defaultPose: nil,
        fallbackPose: nil,
        poses: [],
        actions: [],
        expressions: []
    )
}

struct Live2DMotionPlaybackRequest: Hashable {
    let requestID: String
    let bundlePath: String
    let motion: Live2DMotionRecord

    init(bundlePath: String, motion: Live2DMotionRecord) {
        self.requestID = UUID().uuidString
        self.bundlePath = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        self.motion = motion
    }
}

struct Live2DViewportState: Codable, Hashable {
    var offsetX: Double
    var offsetY: Double
    var scale: Double

    static let `default` = Live2DViewportState(offsetX: 0, offsetY: 0, scale: 1)

    func clamped() -> Live2DViewportState {
        Live2DViewportState(
            offsetX: min(max(offsetX, -420), 420),
            offsetY: min(max(offsetY, -260), 260),
            scale: min(max(scale, 0.65), 1.8)
        )
    }
}

enum Live2DMotionCatalog {
    static func discoverCatalog(bundlePath: String) -> Live2DActionCatalog {
        let descriptorURL = URL(fileURLWithPath: bundlePath).standardizedFileURL
        guard descriptorURL.pathExtension.lowercased() == "json" else { return .empty }

        let bundleDirectory = descriptorURL.deletingLastPathComponent()
        var posesByPath: [String: Live2DMotionRecord] = [:]
        var actionsByPath: [String: Live2DMotionRecord] = [:]
        var expressionsByPath: [String: Live2DExpressionRecord] = [:]
        var defaultPosePath: String?
        var fallbackPosePath: String?

        addModel3Motions(
            from: descriptorURL,
            bundleDirectory: bundleDirectory,
            posesByPath: &posesByPath,
            actionsByPath: &actionsByPath
        )
        addVTubeEntries(
            in: bundleDirectory,
            posesByPath: &posesByPath,
            actionsByPath: &actionsByPath,
            expressionsByPath: &expressionsByPath,
            defaultPosePath: &defaultPosePath,
            fallbackPosePath: &fallbackPosePath
        )
        addScannedAssets(
            in: bundleDirectory,
            posesByPath: &posesByPath,
            actionsByPath: &actionsByPath,
            expressionsByPath: &expressionsByPath
        )

        let poses = sortMotions(
            posesByPath.values,
            defaultPath: defaultPosePath,
            fallbackPath: fallbackPosePath
        )
        let actions = sortMotions(actionsByPath.values)
        let expressions = expressionsByPath.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        return Live2DActionCatalog(
            defaultPose: defaultPosePath.flatMap { posesByPath[$0] } ?? poses.first,
            fallbackPose: fallbackPosePath.flatMap { posesByPath[$0] },
            poses: poses,
            actions: actions,
            expressions: expressions
        )
    }

    static func discoverMotions(bundlePath: String) -> [Live2DMotionRecord] {
        let catalog = discoverCatalog(bundlePath: bundlePath)
        return catalog.poses + catalog.actions
    }

    private static func addModel3Motions(
        from descriptorURL: URL,
        bundleDirectory: URL,
        posesByPath: inout [String: Live2DMotionRecord],
        actionsByPath: inout [String: Live2DMotionRecord]
    ) {
        guard
            let data = try? Data(contentsOf: descriptorURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let fileReferences = json["FileReferences"] as? [String: Any],
            let motions = fileReferences["Motions"] as? [String: Any]
        else {
            return
        }

        for (groupName, value) in motions {
            guard let entries = value as? [[String: Any]] else { continue }
            let isPoseGroup = groupName.localizedCaseInsensitiveCompare("idle") == .orderedSame
            for (index, entry) in entries.enumerated() {
                guard let file = entry["File"] as? String, file.lowercased().hasSuffix(".motion3.json") else {
                    continue
                }

                let metadata = motionMetadata(for: file, in: bundleDirectory)
                let title = prettyAssetTitle(
                    preferred: entry["Name"] as? String,
                    fallbackPath: file,
                    fallbackGroup: groupName,
                    fallbackIndex: index
                )
                let category: Live2DMotionCategory = isPoseGroup ? .pose : .action
                upsertMotion(
                    relativePath: file,
                    title: title,
                    source: .model3,
                    category: category,
                    isLoop: metadata.isLoop,
                    durationSeconds: metadata.durationSeconds,
                    posesByPath: &posesByPath,
                    actionsByPath: &actionsByPath
                )
            }
        }
    }

    private static func addVTubeEntries(
        in bundleDirectory: URL,
        posesByPath: inout [String: Live2DMotionRecord],
        actionsByPath: inout [String: Live2DMotionRecord],
        expressionsByPath: inout [String: Live2DExpressionRecord],
        defaultPosePath: inout String?,
        fallbackPosePath: inout String?
    ) {
        guard
            let vtubeURL = try? FileManager.default.contentsOfDirectory(
                at: bundleDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).first(where: { $0.pathExtension.lowercased() == "json" && $0.lastPathComponent.lowercased().hasSuffix(".vtube.json") }),
            let data = try? Data(contentsOf: vtubeURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        let fileRefs = json["FileReferences"] as? [String: Any]
        if let idleAnimation = fileRefs?["IdleAnimation"] as? String,
           idleAnimation.lowercased().hasSuffix(".motion3.json") {
            let metadata = motionMetadata(for: idleAnimation, in: bundleDirectory)
            upsertMotion(
                relativePath: idleAnimation,
                title: prettyAssetTitle(preferred: "Default Pose", fallbackPath: idleAnimation),
                source: .vtube,
                category: .pose,
                isLoop: metadata.isLoop,
                durationSeconds: metadata.durationSeconds,
                posesByPath: &posesByPath,
                actionsByPath: &actionsByPath
            )
            defaultPosePath = normalizePath(idleAnimation)
        }

        if let trackingLost = fileRefs?["IdleAnimationWhenTrackingLost"] as? String,
           trackingLost.lowercased().hasSuffix(".motion3.json") {
            let metadata = motionMetadata(for: trackingLost, in: bundleDirectory)
            upsertMotion(
                relativePath: trackingLost,
                title: prettyAssetTitle(preferred: "Sleep Idle", fallbackPath: trackingLost),
                source: .vtube,
                category: .pose,
                isLoop: metadata.isLoop,
                durationSeconds: metadata.durationSeconds,
                posesByPath: &posesByPath,
                actionsByPath: &actionsByPath
            )
            fallbackPosePath = normalizePath(trackingLost)
        }

        guard let hotkeys = json["Hotkeys"] as? [[String: Any]] else { return }
        for hotkey in hotkeys {
            let action = (hotkey["Action"] as? String) ?? ""
            let preferredName = (hotkey["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let file = hotkey["File"] as? String else { continue }
            let normalizedFile = normalizePath(file)

            if normalizedFile.lowercased().hasSuffix(".motion3.json") {
                let metadata = motionMetadata(for: file, in: bundleDirectory)
                let category: Live2DMotionCategory
                if action == "ChangeIdleAnimation" ||
                    metadata.isLoop ||
                    normalizedFile == defaultPosePath ||
                    normalizedFile == fallbackPosePath {
                    category = .pose
                } else {
                    category = .action
                }
                upsertMotion(
                    relativePath: file,
                    title: prettyAssetTitle(
                        preferred: preferredName?.isEmpty == false ? preferredName : nil,
                        fallbackPath: file,
                        fallbackGroup: action
                    ),
                    source: .vtube,
                    category: category,
                    isLoop: metadata.isLoop,
                    durationSeconds: metadata.durationSeconds,
                    posesByPath: &posesByPath,
                    actionsByPath: &actionsByPath
                )
                continue
            }

            guard normalizedFile.lowercased().hasSuffix(".exp3.json") else { continue }
            upsertExpression(
                relativePath: file,
                title: prettyAssetTitle(
                    preferred: preferredName?.isEmpty == false ? preferredName : nil,
                    fallbackPath: file
                ),
                source: .vtube,
                into: &expressionsByPath
            )
        }
    }

    private static func addScannedAssets(
        in bundleDirectory: URL,
        posesByPath: inout [String: Live2DMotionRecord],
        actionsByPath: inout [String: Live2DMotionRecord],
        expressionsByPath: inout [String: Live2DExpressionRecord]
    ) {
        guard let enumerator = FileManager.default.enumerator(at: bundleDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for case let fileURL as URL in enumerator {
            guard let relativePath = relativePath(for: fileURL, within: bundleDirectory) else { continue }
            let lowercasedPath = relativePath.lowercased()

            if lowercasedPath.hasSuffix(".motion3.json") {
                let metadata = motionMetadata(for: relativePath, in: bundleDirectory)
                upsertMotion(
                    relativePath: relativePath,
                    title: prettyAssetTitle(preferred: nil, fallbackPath: relativePath),
                    source: .scanned,
                    category: .action,
                    isLoop: metadata.isLoop,
                    durationSeconds: metadata.durationSeconds,
                    posesByPath: &posesByPath,
                    actionsByPath: &actionsByPath
                )
            } else if lowercasedPath.hasSuffix(".exp3.json") {
                upsertExpression(
                    relativePath: relativePath,
                    title: prettyAssetTitle(preferred: nil, fallbackPath: relativePath),
                    source: .scanned,
                    into: &expressionsByPath
                )
            }
        }
    }

    private static func upsertMotion(
        relativePath: String,
        title: String,
        source: Live2DAssetSource,
        category: Live2DMotionCategory,
        isLoop: Bool,
        durationSeconds: Double?,
        posesByPath: inout [String: Live2DMotionRecord],
        actionsByPath: inout [String: Live2DMotionRecord]
    ) {
        let normalizedPath = normalizePath(relativePath)
        let target = category == .pose ? posesByPath : actionsByPath
        let existing = target[normalizedPath] ?? (category == .pose ? actionsByPath[normalizedPath] : posesByPath[normalizedPath])

        let candidate = Live2DMotionRecord(
            id: normalizedPath,
            title: title,
            relativePath: normalizedPath,
            source: source,
            category: category,
            isLoop: isLoop,
            durationSeconds: durationSeconds
        )

        if let existing {
            if shouldReplaceMotion(existing: existing, candidate: candidate) {
                if category == .pose {
                    posesByPath[normalizedPath] = candidate
                    actionsByPath.removeValue(forKey: normalizedPath)
                } else if posesByPath[normalizedPath] == nil {
                    actionsByPath[normalizedPath] = candidate
                }
            }
            return
        }

        if category == .pose {
            posesByPath[normalizedPath] = candidate
            actionsByPath.removeValue(forKey: normalizedPath)
        } else {
            actionsByPath[normalizedPath] = candidate
        }
    }

    private static func shouldReplaceMotion(existing: Live2DMotionRecord, candidate: Live2DMotionRecord) -> Bool {
        if candidate.category == .pose && existing.category != .pose {
            return true
        }
        if candidate.category != .pose && existing.category == .pose {
            return false
        }

        let existingFallbackTitle = prettyAssetTitle(preferred: nil, fallbackPath: existing.relativePath)
        let candidateSourceRank = sourceRank(candidate.source)
        let existingSourceRank = sourceRank(existing.source)
        return candidateSourceRank < existingSourceRank ||
            (candidateSourceRank == existingSourceRank &&
             existing.title == existingFallbackTitle &&
             candidate.title != existingFallbackTitle)
    }

    private static func upsertExpression(
        relativePath: String,
        title: String,
        source: Live2DAssetSource,
        into expressionsByPath: inout [String: Live2DExpressionRecord]
    ) {
        let normalizedPath = normalizePath(relativePath)
        let candidate = Live2DExpressionRecord(
            id: normalizedPath,
            title: title,
            relativePath: normalizedPath,
            source: source
        )

        if let existing = expressionsByPath[normalizedPath] {
            let existingFallbackTitle = prettyAssetTitle(preferred: nil, fallbackPath: existing.relativePath)
            let candidateSourceRank = sourceRank(candidate.source)
            let existingSourceRank = sourceRank(existing.source)
            let shouldReplace = candidateSourceRank < existingSourceRank ||
                (candidateSourceRank == existingSourceRank &&
                 existing.title == existingFallbackTitle &&
                 candidate.title != existingFallbackTitle)
            if shouldReplace {
                expressionsByPath[normalizedPath] = candidate
            }
            return
        }

        expressionsByPath[normalizedPath] = candidate
    }

    private static func relativePath(for fileURL: URL, within bundleDirectory: URL) -> String? {
        let resolvedFileURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedBundleDirectory = bundleDirectory.resolvingSymlinksInPath().standardizedFileURL

        let fileComponents = resolvedFileURL.pathComponents
        let directoryComponents = resolvedBundleDirectory.pathComponents

        guard fileComponents.count > directoryComponents.count else { return nil }
        guard Array(fileComponents.prefix(directoryComponents.count)) == directoryComponents else { return nil }

        return fileComponents
            .dropFirst(directoryComponents.count)
            .joined(separator: "/")
    }

    private static func motionMetadata(for relativePath: String, in bundleDirectory: URL) -> (isLoop: Bool, durationSeconds: Double?) {
        let motionURL = bundleDirectory.appendingPathComponent(relativePath)
        guard
            let data = try? Data(contentsOf: motionURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let meta = json["Meta"] as? [String: Any]
        else {
            return (false, nil)
        }

        return (
            meta["Loop"] as? Bool ?? false,
            meta["Duration"] as? Double
        )
    }

    private static func sortMotions<S: Sequence>(
        _ motions: S,
        defaultPath: String? = nil,
        fallbackPath: String? = nil
    ) -> [Live2DMotionRecord] where S.Element == Live2DMotionRecord {
        motions.sorted { lhs, rhs in
            let lhsRank = motionSortRank(lhs, defaultPath: defaultPath, fallbackPath: fallbackPath)
            let rhsRank = motionSortRank(rhs, defaultPath: defaultPath, fallbackPath: fallbackPath)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func motionSortRank(
        _ motion: Live2DMotionRecord,
        defaultPath: String?,
        fallbackPath: String?
    ) -> Int {
        if motion.relativePath == defaultPath {
            return 0
        }
        if motion.relativePath == fallbackPath {
            return 1
        }
        return 2
    }

    private static func sourceRank(_ source: Live2DAssetSource) -> Int {
        switch source {
        case .model3: return 0
        case .vtube: return 1
        case .scanned: return 2
        }
    }

    private static func normalizePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    private static func prettyAssetTitle(
        preferred: String?,
        fallbackPath: String,
        fallbackGroup: String? = nil,
        fallbackIndex: Int? = nil
    ) -> String {
        if let preferred,
           !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let translated = translatedAssetTitle(for: preferred)
            if !translated.isEmpty {
                return translated
            }
        }

        let stem = URL(fileURLWithPath: fallbackPath).deletingPathExtension().deletingPathExtension().lastPathComponent
        if !stem.isEmpty {
            let translatedStem = translatedAssetTitle(for: stem)
            if !translatedStem.isEmpty {
                return translatedStem
            }
        }

        if let fallbackGroup {
            if let fallbackIndex {
                return "\(fallbackGroup) \(fallbackIndex + 1)"
            }
            return fallbackGroup
        }

        return fallbackPath
    }

    private static func translatedAssetTitle(for rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let englishMap: [String: String] = [
            "书本": "Book",
            "书本-写字": "Book Writing",
            "书本-点击": "Book Tap",
            "冰淇淋": "Ice Cream",
            "变小": "Shrink",
            "只有头": "Head Only",
            "待机动画": "Idle Animation",
            "戳脸": "Poke Cheek",
            "打瞌睡": "Sleepy",
            "打瞌睡动画": "Sleepy Animation",
            "星星眼": "Star Eyes",
            "流泪": "Tears",
            "熊猫抱枕": "Panda Pillow",
            "爱心眼": "Heart Eyes",
            "眼镜": "Glasses",
            "脸红": "Blush",
            "脸黑": "Dark Face",
            "舌头": "Tongue",
            "蚊香眼": "Dizzy Eyes",
            "走路动画": "Walking Animation"
        ]

        if let mapped = englishMap[trimmed] {
            return mapped
        }

        let containsCJK = trimmed.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0x3040 ... 0x30FF, 0xAC00 ... 0xD7AF:
                return true
            default:
                return false
            }
        }

        if containsCJK {
            return ""
        }

        return trimmed.replacingOccurrences(of: "_", with: " ")
    }
}
