import AppKit
import CoreText
import Foundation
import SwiftUI

enum GeeFontFamily {
    static let displayBold = "SpaceGrotesk-Bold"
    static let displaySemibold = "SpaceGrotesk-SemiBold"
    static let bodyRegular = "WorkSans-Regular"
    static let bodyMedium = "WorkSans-Medium"
}

enum GeeTypography {
    static func registerBundledFonts() {
        guard let resourcesURL = Bundle.main.resourceURL else {
            return
        }

        let fontURLs = [
            resourcesURL.appendingPathComponent("Fonts/\(GeeFontFamily.displayBold).ttf"),
            resourcesURL.appendingPathComponent("Fonts/\(GeeFontFamily.displaySemibold).ttf"),
            resourcesURL.appendingPathComponent("Fonts/\(GeeFontFamily.bodyRegular).ttf"),
            resourcesURL.appendingPathComponent("Fonts/\(GeeFontFamily.bodyMedium).ttf")
        ]

        for fontURL in fontURLs where FileManager.default.fileExists(atPath: fontURL.path) {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }
}

extension Font {
    static func geeDisplay(_ size: CGFloat) -> Font {
        .custom(GeeFontFamily.displayBold, size: size)
    }

    static func geeDisplaySemibold(_ size: CGFloat) -> Font {
        .custom(GeeFontFamily.displaySemibold, size: size)
    }

    static func geeBody(_ size: CGFloat) -> Font {
        .custom(GeeFontFamily.bodyRegular, size: size)
    }

    static func geeBodyMedium(_ size: CGFloat) -> Font {
        .custom(GeeFontFamily.bodyMedium, size: size)
    }
}

extension NSFont {
    /// AppKit mirror of `Font.geeBody(_:)` — used by the NSTextField-backed
    /// quick-input field so its metrics match surrounding SwiftUI text.
    static func geeBody(_ size: CGFloat) -> NSFont {
        NSFont(name: GeeFontFamily.bodyRegular, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .regular)
    }

    static func geeBodyMedium(_ size: CGFloat) -> NSFont {
        NSFont(name: GeeFontFamily.bodyMedium, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .medium)
    }
}
