import Foundation
import SwiftUI

enum GearRegistry {
    static let mediaLibraryWindowID = "media-library"
    static let hyperframesStudioWindowID = "hyperframes-studio"

    private static let manifestFileName = "gear.json"
    private static let bundledGearsDirectoryName = "gears"

    static let nativeGearIDs: Set<String> = [
        MediaLibraryGearDescriptor.gearID,
        HyperframesStudioGearDescriptor.gearID
    ]

    static func gearRecords() -> [InstalledAppRecord] {
        dedupedGearScanResults().map(\.record)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func homeWidgetRecords() -> [InstalledAppRecord] {
        gearRecords()
            .filter { $0.gearKind == .widget && $0.installState == .installed && isEnabled(gearID: $0.id) }
    }

    static func mergedWithGears(_ apps: [InstalledAppRecord]) -> [InstalledAppRecord] {
        let gears = gearRecords()
        let gearIDs = Set(gears.map(\.id))
        let externalApps = apps.filter { !gearIDs.contains($0.id) }
        return gears + externalApps
    }

    static func dedicatedWindowID(gearID: String) -> String? {
        guard isGearInstalled(gearID: gearID) else {
            return nil
        }
        switch gearID {
        case MediaLibraryGearDescriptor.gearID:
            return mediaLibraryWindowID
        case HyperframesStudioGearDescriptor.gearID:
            return hyperframesStudioWindowID
        default:
            return nil
        }
    }

    static func isOptionalAccessory(gearID: String) -> Bool {
        isGearInstalled(gearID: gearID)
    }

    static func isEnabled(gearID: String, defaults: UserDefaults = .standard) -> Bool {
        guard isOptionalAccessory(gearID: gearID) else {
            return true
        }
        let key = enabledPreferenceKey(for: gearID)
        guard defaults.object(forKey: key) != nil else {
            return true
        }
        return defaults.bool(forKey: key)
    }

    static func setEnabled(_ isEnabled: Bool, gearID: String, defaults: UserDefaults = .standard) {
        guard isOptionalAccessory(gearID: gearID) else {
            return
        }
        defaults.set(isEnabled, forKey: enabledPreferenceKey(for: gearID))
    }

    @MainActor
    static func makeNativeGearView(for gear: InstalledAppRecord) -> AnyView? {
        guard isEnabled(gearID: gear.id), isGearInstalled(gearID: gear.id) else {
            return nil
        }
        switch gear.id {
        case MediaLibraryGearDescriptor.gearID:
            return AnyView(MediaLibraryModuleView())
        case HyperframesStudioGearDescriptor.gearID:
            return AnyView(HyperframesStudioModuleView())
        default:
            return nil
        }
    }

    static func manifest(gearID: String) -> GearManifest? {
        gearManifests().first { $0.id == gearID }
    }

    private static func isGearInstalled(gearID: String) -> Bool {
        dedupedGearScanResults().contains { $0.record.id == gearID && $0.record.installState == .installed }
    }

    private static func gearManifests() -> [GearManifest] {
        dedupedGearScanResults().compactMap(\.manifest)
    }

    private static func dedupedGearScanResults() -> [GearScanResult] {
        var resultsByID: [String: GearScanResult] = [:]
        for result in scanGears() {
            // Later roots override earlier roots, so downloaded/user gears can
            // replace bundled development gears without changing host code.
            // Invalid user folders should not hide a valid bundled gear with
            // the same id; they remain visible only when no valid gear exists.
            if result.manifest == nil, resultsByID[result.record.id]?.manifest != nil {
                continue
            }
            resultsByID[result.record.id] = result
        }
        return Array(resultsByID.values)
    }

    private static func scanGears() -> [GearScanResult] {
        gearFolders().map { folder in
            let manifestURL = folder.appendingPathComponent(manifestFileName)
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                return .invalid(folder: folder, reason: "Missing gear.json.")
            }

            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(GearManifest.self, from: data)
                guard manifest.schema == GearManifest.supportedSchema else {
                    return .invalid(folder: folder, reason: "Unsupported manifest schema.")
                }
                guard manifest.entry.isSupported else {
                    return .invalid(folder: folder, reason: "Unsupported gear entry type.")
                }
                let resolvedManifest = manifest.resolvingAssets(relativeTo: folder)
                return .valid(resolvedManifest)
            } catch {
                return .invalid(folder: folder, reason: "Invalid gear.json: \(error.localizedDescription)")
            }
        }
    }

    private static func gearFolders() -> [URL] {
        var folders: [URL] = []
        for root in gearRoots() {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            folders.append(contentsOf: entries.filter { entry in
                (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            })
        }
        return folders
    }

    private static func gearRoots() -> [URL] {
        var roots: [URL] = []
        let runningFromAppBundle = Bundle.main.bundleURL.pathExtension == "app"

        if let appResourceURL = Bundle.main.resourceURL {
            let appBundledRoot = appResourceURL.appendingPathComponent(
                bundledGearsDirectoryName,
                isDirectory: true
            )
            if FileManager.default.fileExists(atPath: appBundledRoot.path) {
                roots.append(appBundledRoot)
            }
        }

        if !runningFromAppBundle,
           let swiftPMBundledRoot = Bundle.module.resourceURL?.appendingPathComponent(
               bundledGearsDirectoryName,
               isDirectory: true
           ),
           FileManager.default.fileExists(atPath: swiftPMBundledRoot.path)
        {
            roots.append(swiftPMBundledRoot)
        }

        if let supportRoot = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("GeeAgent/gears") {
            roots.append(supportRoot)
        }
        return roots
    }

    private static func enabledPreferenceKey(for gearID: String) -> String {
        "geeagent.gear.\(gearID).enabled"
    }
}

private struct GearScanResult {
    var record: InstalledAppRecord
    var manifest: GearManifest?

    static func valid(_ manifest: GearManifest) -> GearScanResult {
        GearScanResult(record: manifest.installedAppRecord(), manifest: manifest)
    }

    static func invalid(folder: URL, reason: String) -> GearScanResult {
        let folderName = folder.lastPathComponent
        let displayName = folderName
            .split(separator: ".")
            .map { $0.capitalized }
            .joined(separator: " ")
        return GearScanResult(
            record: InstalledAppRecord(
                id: folderName,
                name: displayName.isEmpty ? "Invalid Gear" : displayName,
                categoryLabel: "Gear",
                versionLabel: "Unknown",
                healthLabel: "Install issue",
                installState: .installError,
                summary: reason,
                displayMode: .fullCanvas,
                gearKind: .atmosphere,
                installIssue: reason,
                isGearPackage: true
            ),
            manifest: nil
        )
    }
}

struct GearManifest: Decodable, Hashable, Sendable {
    static let supportedSchema = "gee.gear.v1"

    struct Entry: Decodable, Hashable, Sendable {
        var type: String
        var nativeID: String?

        enum CodingKeys: String, CodingKey {
            case type
            case nativeID = "native_id"
        }

        var isSupported: Bool {
            switch type {
            case "native", "widget":
                true
            default:
                false
            }
        }
    }

    struct Agent: Decodable, Hashable, Sendable {
        var enabled: Bool
        var capabilities: [Capability]
    }

    struct Capability: Decodable, Hashable, Sendable {
        var id: String
        var title: String
        var description: String
        var examples: [String]?
    }

    var schema: String
    var id: String
    var name: String
    var description: String
    var developer: String
    var version: String
    var category: String?
    var kind: GearKind?
    var cover: String?
    var icon: String?
    var displayMode: ModuleDisplayMode?
    var entry: Entry
    var agent: Agent?
    var dependencies: GearDependencyPlan?

    private(set) var rootURL: URL = URL(fileURLWithPath: "/")

    enum CodingKeys: String, CodingKey {
        case schema
        case id
        case name
        case description
        case developer
        case version
        case category
        case kind
        case cover
        case icon
        case displayMode = "display_mode"
        case entry
        case agent
        case dependencies
    }

    func resolvingAssets(relativeTo rootURL: URL) -> GearManifest {
        var copy = self
        copy.rootURL = rootURL
        return copy
    }

    func installedAppRecord() -> InstalledAppRecord {
        InstalledAppRecord(
            id: id,
            name: name,
            categoryLabel: category ?? "Gear",
            versionLabel: version,
            healthLabel: "Ready",
            installState: .installed,
            summary: description,
            displayMode: displayMode ?? .fullCanvas,
            developerLabel: developer,
            coverURL: assetURL(cover),
            iconURL: assetURL(icon),
            gearKind: kind ?? .atmosphere,
            isGearPackage: true
        )
    }

    private func assetURL(_ path: String?) -> URL? {
        guard let path else {
            return nil
        }
        return rootURL.appendingPathComponent(path)
    }
}

enum MediaLibraryGearDescriptor {
    static let gearID = "media.library"
}

enum HyperframesStudioGearDescriptor {
    static let gearID = "hyperframes.studio"
}

struct GearWindowRequest: Equatable, Identifiable {
    let id = UUID()
    let gearID: String
    let windowID: String
}
