/// How the host presents an installed capability module in the workbench.
/// Mirrors the runtime `ModuleDisplayMode` / `display_mode` on
/// `InstalledAppSummary` in the workspace snapshot.
enum ModuleDisplayMode: String, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case inNav = "in_nav"
    case fullCanvas = "full_canvas"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .inNav: "In nav"
        case .fullCanvas: "Full window"
        }
    }
}
