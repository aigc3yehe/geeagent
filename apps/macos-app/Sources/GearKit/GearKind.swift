enum GearKind: String, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case atmosphere
    case widget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atmosphere: "Atmosphere App"
        case .widget: "Widget"
        }
    }

    var subtitle: String {
        switch self {
        case .atmosphere: "An immersive app that can open on its own or plug into Gee Focus."
        case .widget: "A compact home-screen component for ongoing monitoring and lightweight reminders."
        }
    }

    var systemImage: String {
        switch self {
        case .atmosphere: "sparkles.rectangle.stack"
        case .widget: "rectangle.on.rectangle.angled"
        }
    }
}
