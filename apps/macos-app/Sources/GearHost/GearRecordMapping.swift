import Foundation

extension GearManifest {
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
}
