import Foundation

struct GearDependencyPlan: Decodable, Hashable, Sendable {
    enum InstallStrategy: String, Decodable, Hashable, Sendable {
        case onOpen = "on_open"
        case onFirstRun = "on_first_run"
    }

    var installStrategy: InstallStrategy
    var items: [GearDependencyItem]

    enum CodingKeys: String, CodingKey {
        case installStrategy = "install_strategy"
        case items
    }
}

struct GearDependencyItem: Decodable, Hashable, Identifiable, Sendable {
    enum Kind: String, Decodable, Hashable, Sendable {
        case binary
        case framework
        case model
        case data
        case runtime
    }

    enum Scope: String, Decodable, Hashable, Sendable {
        case global
        case gearLocal = "gear_local"
    }

    var id: String
    var kind: Kind
    var scope: Scope
    var required: Bool
    var target: String?
    var detect: GearDependencyDetect?
    var installer: GearDependencyInstallerSpec?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case scope
        case required
        case target
        case detect
        case installer
    }
}

struct GearDependencyDetect: Decodable, Hashable, Sendable {
    var command: String?
    var args: [String]?
    var minVersion: String?
    var healthCommand: String?
    var healthArgs: [String]?

    enum CodingKeys: String, CodingKey {
        case command
        case args
        case minVersion = "min_version"
        case healthCommand = "health_command"
        case healthArgs = "health_args"
    }
}

struct GearDependencyInstallerSpec: Decodable, Hashable, Sendable {
    enum InstallerType: String, Decodable, Hashable, Sendable {
        case recipe
        case script
        case archive
        case none
    }

    var type: InstallerType
    var id: String?
    var path: String?
    var package: String?
    var version: String?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case path
        case package
        case version
    }
}

enum GearPreparationState: String, Codable, Hashable, Sendable {
    case unknown
    case checking
    case needsSetup = "needs_setup"
    case installing
    case ready
    case installFailed = "install_failed"
    case unsupported

    var title: String {
        switch self {
        case .unknown: "Unknown"
        case .checking: "Checking"
        case .needsSetup: "Needs Setup"
        case .installing: "Installing"
        case .ready: "Ready"
        case .installFailed: "Setup Failed"
        case .unsupported: "Unsupported"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .checking: "magnifyingglass"
        case .needsSetup: "arrow.down.circle"
        case .installing: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.seal"
        case .installFailed: "exclamationmark.triangle"
        case .unsupported: "nosign"
        }
    }

    var isBusy: Bool {
        self == .checking || self == .installing
    }
}

struct GearPreparationSnapshot: Codable, Hashable, Sendable {
    var gearID: String
    var state: GearPreparationState
    var summary: String
    var detail: String?
    var missingDependencyIDs: [String]
    var updatedAt: Date

    static func ready(gearID: String, summary: String = "Ready") -> GearPreparationSnapshot {
        GearPreparationSnapshot(
            gearID: gearID,
            state: .ready,
            summary: summary,
            detail: nil,
            missingDependencyIDs: [],
            updatedAt: Date()
        )
    }
}

struct GearDependencyCheckResult: Hashable, Sendable {
    var item: GearDependencyItem
    var isSatisfied: Bool
    var summary: String
    var detail: String?
}
