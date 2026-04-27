import Foundation
import SwiftUI

enum GearHost {
    static let mediaLibraryWindowID = "media-library"
    static let hyperframesStudioWindowID = "hyperframes-studio"
    static let smartYTMediaWindowID = "smartyt-media"
    static let twitterCaptureWindowID = "twitter-capture"
    static let bookmarkVaultWindowID = "bookmark-vault"
    static let mediaLibraryWindowDescriptor = GearNativeWindowDescriptor(
        gearID: MediaLibraryGearDescriptor.gearID,
        windowID: mediaLibraryWindowID,
        title: "Media Library",
        defaultWidth: 1180,
        defaultHeight: 780
    )
    static let hyperframesStudioWindowDescriptor = GearNativeWindowDescriptor(
        gearID: HyperframesStudioGearDescriptor.gearID,
        windowID: hyperframesStudioWindowID,
        title: "Hyperframes Studio",
        defaultWidth: 1280,
        defaultHeight: 820
    )
    static let smartYTMediaWindowDescriptor = GearNativeWindowDescriptor(
        gearID: SmartYTMediaGearDescriptor.gearID,
        windowID: smartYTMediaWindowID,
        title: "SmartYT Media",
        defaultWidth: 1180,
        defaultHeight: 760
    )
    static let twitterCaptureWindowDescriptor = GearNativeWindowDescriptor(
        gearID: TwitterCaptureGearDescriptor.gearID,
        windowID: twitterCaptureWindowID,
        title: "Twitter Capture",
        defaultWidth: 1180,
        defaultHeight: 760
    )
    static let bookmarkVaultWindowDescriptor = GearNativeWindowDescriptor(
        gearID: BookmarkVaultGearDescriptor.gearID,
        windowID: bookmarkVaultWindowID,
        title: "Bookmark Vault",
        defaultWidth: 1180,
        defaultHeight: 760
    )
    static let nativeWindowDescriptors: [GearNativeWindowDescriptor] = [
        mediaLibraryWindowDescriptor,
        hyperframesStudioWindowDescriptor,
        smartYTMediaWindowDescriptor,
        twitterCaptureWindowDescriptor,
        bookmarkVaultWindowDescriptor
    ]

    private static let manifestFileName = "gear.json"
    private static let bundledGearsDirectoryNames = ["gears", "Gears"]

    static let nativeGearIDs = Set(nativeWindowDescriptors.map(\.gearID))

    static func gearRecords() -> [InstalledAppRecord] {
        dedupedGearScanResults().map(\.record)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func homeWidgetRecords() -> [InstalledAppRecord] {
        gearRecords()
            .filter { $0.gearKind == .widget && $0.installState == .installed && isEnabled(gearID: $0.id) }
    }

    static func enabledCapabilityRecords(preparationStore: GearPreparationStore = GearPreparationStore()) -> [GearCapabilityRecord] {
        gearManifests()
            .filter { manifest in
                canExposeCapabilities(for: manifest, preparationStore: preparationStore)
            }
            .flatMap { manifest in
                (manifest.agent?.capabilities ?? []).map { capability in
                    GearCapabilityRecord(
                        gearID: manifest.id,
                        gearName: manifest.name,
                        capabilityID: capability.id,
                        title: capability.title,
                        description: capability.description,
                        examples: capability.examples ?? []
                    )
                }
            }
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
        return nativeWindowDescriptors.first { $0.gearID == gearID }?.windowID
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
        case SmartYTMediaGearDescriptor.gearID:
            return AnyView(SmartYTMediaGearModuleView())
        case TwitterCaptureGearDescriptor.gearID:
            return AnyView(TwitterCaptureGearModuleView())
        case BookmarkVaultGearDescriptor.gearID:
            return AnyView(BookmarkVaultGearModuleView())
        default:
            return nil
        }
    }

    @MainActor
    static func makeNativeWindowView(for gearID: String) -> AnyView {
        guard isEnabled(gearID: gearID), isGearInstalled(gearID: gearID) else {
            return AnyView(GearUnavailableWindowView(title: displayTitle(for: gearID)))
        }
        switch gearID {
        case MediaLibraryGearDescriptor.gearID:
            return AnyView(MediaLibraryModuleWindow())
        case HyperframesStudioGearDescriptor.gearID:
            return AnyView(HyperframesStudioModuleWindow())
        case SmartYTMediaGearDescriptor.gearID:
            return AnyView(SmartYTMediaGearWindow())
        case TwitterCaptureGearDescriptor.gearID:
            return AnyView(TwitterCaptureGearWindow())
        case BookmarkVaultGearDescriptor.gearID:
            return AnyView(BookmarkVaultGearWindow())
        default:
            return AnyView(GearUnavailableWindowView(title: displayTitle(for: gearID)))
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

    private static func canExposeCapabilities(
        for manifest: GearManifest,
        preparationStore: GearPreparationStore
    ) -> Bool {
        guard manifest.agent?.enabled == true,
              isEnabled(gearID: manifest.id),
              isGearInstalled(gearID: manifest.id)
        else {
            return false
        }

        let requiredDependencies = manifest.dependencies?.items.filter(\.required) ?? []
        guard !requiredDependencies.isEmpty else {
            return true
        }
        return preparationStore.load(gearID: manifest.id)?.state == .ready
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
                guard manifest.id == folder.lastPathComponent else {
                    return .invalid(folder: folder, reason: "Folder name must match gear id `\(manifest.id)`.")
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
            roots.append(contentsOf: existingBundledRoots(in: appResourceURL))
        }

        if !runningFromAppBundle, let swiftPMResourceURL = Bundle.module.resourceURL {
            roots.append(contentsOf: existingBundledRoots(in: swiftPMResourceURL))
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

    private static func existingBundledRoots(in resourceURL: URL) -> [URL] {
        bundledGearsDirectoryNames.compactMap { directoryName in
            let root = resourceURL.appendingPathComponent(directoryName, isDirectory: true)
            return FileManager.default.fileExists(atPath: root.path) ? root : nil
        }
    }

    private static func enabledPreferenceKey(for gearID: String) -> String {
        "geeagent.gear.\(gearID).enabled"
    }

    private static func displayTitle(for gearID: String) -> String {
        manifest(gearID: gearID)?.name
            ?? nativeWindowDescriptors.first { $0.gearID == gearID }?.title
            ?? "Gear"
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

enum MediaLibraryGearDescriptor {
    static let gearID = "media.library"
}

enum HyperframesStudioGearDescriptor {
    static let gearID = "hyperframes.studio"
}

enum SmartYTMediaGearDescriptor {
    static let gearID = "smartyt.media"
}

enum TwitterCaptureGearDescriptor {
    static let gearID = "twitter.capture"
}

enum BookmarkVaultGearDescriptor {
    static let gearID = "bookmark.vault"
}

struct GearWindowRequest: Equatable, Identifiable {
    let id = UUID()
    let gearID: String
    let windowID: String
}
