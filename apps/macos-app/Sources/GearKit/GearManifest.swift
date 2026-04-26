import Foundation

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

    func assetURL(_ path: String?) -> URL? {
        guard let path else {
            return nil
        }
        return rootURL.appendingPathComponent(path)
    }
}
