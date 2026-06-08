import XCTest
@testable import GeeAgentMac

final class AppLocalizationTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "GeeAgentMacTests.AppLocalizationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testSupportedLocalizationResourcesHaveMatchingKeys() throws {
        let keySets = try AppLanguage.translatedCases.map { language in
            try AppLocalization.localizationKeys(for: language)
        }

        guard let first = keySets.first else {
            XCTFail("Expected at least one translated language.")
            return
        }

        for keys in keySets.dropFirst() {
            XCTAssertEqual(keys, first)
        }
    }

    func testMainNavigationLabelsResolveForSupportedLanguages() {
        XCTAssertEqual(
            AppLocalization.string("nav.chat", defaultValue: "Chat", language: .en),
            "Chat"
        )
        let zhHansLabel = AppLocalization.string("nav.chat", defaultValue: "Chat", language: .zhHans)
        let japaneseLabel = AppLocalization.string("nav.chat", defaultValue: "Chat", language: .ja)

        XCTAssertFalse(zhHansLabel.isEmpty)
        XCTAssertFalse(japaneseLabel.isEmpty)
        XCTAssertNotEqual(zhHansLabel, "Chat")
        XCTAssertNotEqual(japaneseLabel, "Chat")
    }

    func testL10nFacadeResolvesLocaleIdentifiers() {
        let zhHansLabel = L10n.string(
            key: "nav.settings",
            defaultValue: "Settings",
            locale: Locale(identifier: "zh-Hans")
        )
        let japaneseLabel = L10n.string(
            key: "nav.settings",
            defaultValue: "Settings",
            locale: Locale(identifier: "ja")
        )

        XCTAssertFalse(zhHansLabel.isEmpty)
        XCTAssertFalse(japaneseLabel.isEmpty)
        XCTAssertNotEqual(zhHansLabel, "Settings")
        XCTAssertNotEqual(japaneseLabel, "Settings")
    }

    func testLanguagePreferencePersistsAndClearsSystemDefault() {
        XCTAssertEqual(AppLanguage.savedPreference(defaults: defaults), .system)

        AppLanguage.save(.ja, defaults: defaults)
        XCTAssertEqual(AppLanguage.savedPreference(defaults: defaults), .ja)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "ja")

        AppLanguage.save(.system, defaults: defaults)
        XCTAssertEqual(AppLanguage.savedPreference(defaults: defaults), .system)
        XCTAssertNil(defaults.string(forKey: AppLanguage.defaultsKey))
    }
}
