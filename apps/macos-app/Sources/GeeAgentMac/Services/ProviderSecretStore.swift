import Foundation

struct ProviderSecretStore: @unchecked Sendable {
    struct ProviderEntry: Hashable, Sendable {
        var apiKey: String?
        var modelOverride: String?
    }

    private static let secretsFileName = "chat-runtime-secrets.toml"
    private static let appSupportFolderName = "GeeAgent"

    // Provider keys saved from Settings stay in GeeAgent's local application
    // data. Do not move this path to Keychain, launchd, shell profiles, or
    // another system-level credential store without an explicit product change.
    var secretsURL: URL
    var fileManager: FileManager = .default

    init(
        secretsURL: URL = ProviderSecretStore.defaultSecretsURL(),
        fileManager: FileManager = .default
    ) {
        self.secretsURL = secretsURL
        self.fileManager = fileManager
    }

    static func defaultSecretsURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        return base
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
            .appendingPathComponent(secretsFileName)
    }

    func loadSettings() throws -> ProviderSecretSettings {
        let secrets = try loadSecrets()
        let providers = ProviderSecretSettings.defaultSettings.providers.map { status in
            let savedKey = secrets[status.providerID]?.apiKey?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let savedKeyConfigured = savedKey?.isEmpty == false
            let envKey = status.envVar.flatMap { ProcessInfo.processInfo.environment[$0] }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if envKey?.isEmpty == false {
                return ProviderSecretStatus(
                    providerID: status.providerID,
                    title: status.title,
                    apiKeyConfigured: true,
                    savedAPIKeyConfigured: savedKeyConfigured,
                    source: "environment",
                    envVar: status.envVar
                )
            }

            return ProviderSecretStatus(
                providerID: status.providerID,
                title: status.title,
                apiKeyConfigured: savedKeyConfigured,
                savedAPIKeyConfigured: savedKeyConfigured,
                source: savedKeyConfigured ? "saved" : "missing",
                envVar: status.envVar
            )
        }
        return ProviderSecretSettings(providers: providers)
    }

    func apiKey(providerID: String, envVar: String?) throws -> String? {
        let providerID = try Self.validatedProviderID(providerID)
        if let envVar {
            let envKey = ProcessInfo.processInfo.environment[envVar]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if envKey?.isEmpty == false {
                return envKey
            }
        }
        return try loadSecrets()[providerID]?.apiKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveAPIKey(_ apiKey: String, providerID: String) throws -> ProviderSecretSettings {
        let providerID = try Self.validatedProviderID(providerID)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw RuntimeProcessError.runtimeInvocation("API key cannot be empty.")
        }
        var secrets = try loadSecrets()
        var entry = secrets[providerID] ?? ProviderEntry()
        entry.apiKey = trimmedKey
        secrets[providerID] = entry
        try writeSecrets(secrets)
        return try loadSettings()
    }

    func clearAPIKey(providerID: String) throws -> ProviderSecretSettings {
        let providerID = try Self.validatedProviderID(providerID)
        var secrets = try loadSecrets()
        if var entry = secrets[providerID] {
            entry.apiKey = nil
            if entry.modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                secrets[providerID] = entry
            } else {
                secrets.removeValue(forKey: providerID)
            }
        }
        try writeSecrets(secrets)
        return try loadSettings()
    }

    private func loadSecrets() throws -> [String: ProviderEntry] {
        guard fileManager.fileExists(atPath: secretsURL.path) else {
            return [:]
        }
        let raw = try String(contentsOf: secretsURL, encoding: .utf8)
        return Self.parseSecrets(raw)
    }

    private func writeSecrets(_ secrets: [String: ProviderEntry]) throws {
        try fileManager.createDirectory(
            at: secretsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: secretsURL.deletingLastPathComponent().path
        )
        try Self.renderSecrets(secrets).write(to: secretsURL, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
    }

    static func parseSecrets(_ raw: String) -> [String: ProviderEntry] {
        var providers: [String: ProviderEntry] = [:]
        var currentProviderID: String?

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let section = String(trimmed.dropFirst().dropLast())
                if section.hasPrefix("providers.") {
                    currentProviderID = String(section.dropFirst("providers.".count))
                    providers[currentProviderID ?? ""] = providers[currentProviderID ?? ""] ?? ProviderEntry()
                } else {
                    currentProviderID = nil
                }
                continue
            }

            guard let currentProviderID,
                  let equalsIndex = trimmed.firstIndex(of: "=")
            else { continue }

            let key = trimmed[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: equalsIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let decoded = decodeTomlString(value)
            var entry = providers[currentProviderID] ?? ProviderEntry()
            switch key {
            case "api_key":
                entry.apiKey = decoded
            case "model_override":
                entry.modelOverride = decoded
            default:
                break
            }
            providers[currentProviderID] = entry
        }

        return providers.filter { !$0.key.isEmpty }
    }

    static func renderSecrets(_ secrets: [String: ProviderEntry]) -> String {
        var lines = ["version = 1", ""]
        for providerID in secrets.keys.sorted() {
            guard let entry = secrets[providerID] else { continue }
            let apiKey = entry.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelOverride = entry.modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard apiKey?.isEmpty == false || modelOverride?.isEmpty == false else { continue }
            lines.append("[providers.\(providerID)]")
            if let apiKey, !apiKey.isEmpty {
                lines.append("api_key = \(encodeTomlString(apiKey))")
            }
            if let modelOverride, !modelOverride.isEmpty {
                lines.append("model_override = \(encodeTomlString(modelOverride))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func validatedProviderID(_ providerID: String) throws -> String {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            throw RuntimeProcessError.runtimeInvocation("Provider id is invalid.")
        }
        return trimmed
    }

    private static func decodeTomlString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return trimmed
        }
        let inner = String(trimmed.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func encodeTomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
