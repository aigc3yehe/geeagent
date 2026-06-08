import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case system
    case en
    case zhHans = "zh-Hans"
    case ja

    static let defaultsKey = "geeagent.app.language"

    static var translatedCases: [AppLanguage] {
        [.en, .zhHans, .ja]
    }

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .system:
            return Locale.preferredLanguages.first ?? Locale.current.identifier
        case .en:
            return "en"
        case .zhHans:
            return "zh-Hans"
        case .ja:
            return "ja"
        }
    }

    var resolvedLanguage: AppLanguage {
        switch self {
        case .system:
            return Self.systemPreferredLanguage()
        default:
            return self
        }
    }

    var resolvedLocale: Locale {
        Locale(identifier: resolvedLanguage.localeIdentifier)
    }

    var displayTitle: String {
        switch self {
        case .system:
            return AppLocalization.string("settings.language.system", defaultValue: "System", language: self)
        case .en:
            return Locale(identifier: localeIdentifier).localizedString(forIdentifier: localeIdentifier) ?? "English"
        case .zhHans, .ja:
            return Locale(identifier: localeIdentifier).localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier
        }
    }

    var localizedDisplayTitle: String {
        switch self {
        case .system:
            return AppLocalization.string("settings.language.system", defaultValue: "System", language: self)
        case .en:
            return AppLocalization.string("settings.language.english", defaultValue: "English", language: self)
        case .zhHans:
            return AppLocalization.string("settings.language.simplifiedChinese", defaultValue: "Simplified Chinese", language: self)
        case .ja:
            return AppLocalization.string("settings.language.japanese", defaultValue: "Japanese", language: self)
        }
    }

    static func savedPreference(defaults: UserDefaults = .standard) -> AppLanguage {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let language = AppLanguage(rawValue: rawValue)
        else {
            return .system
        }
        return language
    }

    static func save(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        if language == .system {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(language.rawValue, forKey: defaultsKey)
        }
    }

    static func systemPreferredLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        for identifier in preferredLanguages {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized == "ja" || normalized.hasPrefix("ja-") {
                return .ja
            }
            if normalized == "zh-hans" ||
                normalized.hasPrefix("zh-hans-") ||
                normalized == "zh-cn" ||
                normalized.hasPrefix("zh-cn-") ||
                normalized == "zh-sg" ||
                normalized.hasPrefix("zh-sg-") {
                return .zhHans
            }
            if normalized == "en" || normalized.hasPrefix("en-") {
                return .en
            }
        }
        return .en
    }
}

enum AppLocalization {
    private static let tableName = "Localizable"
    private static let tableCache = AppLocalizationTableCache()

    static func string(
        _ key: String,
        defaultValue: String,
        language: AppLanguage = AppLanguage.savedPreference()
    ) -> String {
        let resolvedLanguage = language.resolvedLanguage
        if let value = localizationTable(for: resolvedLanguage)?[key],
           !value.isEmpty {
            return value
        }
        return defaultValue
    }

    static func format(
        _ key: String,
        defaultValue: String,
        language: AppLanguage = AppLanguage.savedPreference(),
        _ arguments: CVarArg...
    ) -> String {
        format(key, defaultValue: defaultValue, language: language, arguments: arguments)
    }

    static func format(
        _ key: String,
        defaultValue: String,
        language: AppLanguage = AppLanguage.savedPreference(),
        arguments: [CVarArg]
    ) -> String {
        String(
            format: string(key, defaultValue: defaultValue, language: language),
            locale: language.resolvedLocale,
            arguments: arguments
        )
    }

    static func localizationKeys(for language: AppLanguage) throws -> Set<String> {
        let resolvedLanguage = language.resolvedLanguage
        guard let url = localizationFileURL(for: resolvedLanguage) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let pattern = #"^\s*"((?:\\"|[^"])*)"\s*="#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let nsRange = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        let matches = regex.matches(in: contents, range: nsRange)
        return Set(matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: contents) else { return nil }
            return String(contents[range]).replacingOccurrences(of: "\\\"", with: "\"")
        })
    }

    private static func localizationFileURL(for language: AppLanguage) -> URL? {
        for bundle in resourceBundleCandidates() {
            if let url = bundle.url(
                forResource: tableName,
                withExtension: "strings",
                subdirectory: "\(language.resourceName).lproj"
            ) {
                return url
            }
        }
        return nil
    }

    private static func localizationTable(for language: AppLanguage) -> [String: String]? {
        if let cachedTable = tableCache.table(for: language) {
            return cachedTable
        }
        guard let url = localizationFileURL(for: language),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              )
        else {
            return nil
        }
        guard let table = plist as? [String: String] else {
            return nil
        }
        tableCache.insert(table, for: language)
        return table
    }

    private static func resourceBundleCandidates() -> [Bundle] {
        [Bundle.module, Bundle.main]
    }
}

enum L10n {
    static func string(
        key: String,
        defaultValue: String,
        locale: Locale? = nil
    ) -> String {
        AppLocalization.string(
            key,
            defaultValue: defaultValue,
            language: language(for: locale)
        )
    }

    static func format(
        key: String,
        defaultValue: String,
        locale: Locale? = nil,
        _ arguments: CVarArg...
    ) -> String {
        AppLocalization.format(
            key,
            defaultValue: defaultValue,
            language: language(for: locale),
            arguments: arguments
        )
    }

    private static func language(for locale: Locale?) -> AppLanguage {
        guard let identifier = locale?.identifier, !identifier.isEmpty else {
            return AppLanguage.savedPreference()
        }
        return AppLanguage.systemPreferredLanguage(preferredLanguages: [identifier])
    }
}

private final class AppLocalizationTableCache: @unchecked Sendable {
    private let lock = NSLock()
    private var tables: [String: [String: String]] = [:]

    func table(for language: AppLanguage) -> [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return tables[language.resourceName]
    }

    func insert(_ table: [String: String], for language: AppLanguage) {
        lock.lock()
        tables[language.resourceName] = table
        lock.unlock()
    }
}

private extension AppLanguage {
    var resourceName: String {
        switch self {
        case .system:
            return resolvedLanguage.resourceName
        case .en:
            return "en"
        case .zhHans:
            return "zh-Hans"
        case .ja:
            return "ja"
        }
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppLanguage = AppLanguage.savedPreference()
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

extension View {
    func appLanguage(_ language: AppLanguage) -> some View {
        environment(\.appLanguage, language)
            .environment(\.locale, language.resolvedLocale)
    }
}

extension WorkbenchStore {
    func localizedString(_ key: String, defaultValue: String) -> String {
        AppLocalization.string(key, defaultValue: defaultValue, language: appLanguage)
    }

    func localizedFormat(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        AppLocalization.format(key, defaultValue: defaultValue, language: appLanguage, arguments: arguments)
    }
}
