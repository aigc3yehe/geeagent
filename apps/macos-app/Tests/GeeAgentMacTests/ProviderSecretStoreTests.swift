import Foundation
import XCTest
@testable import GeeAgentMac

final class ProviderSecretStoreTests: XCTestCase {
    func testParsesProviderSecretsWithoutExposingKeyStatus() throws {
        let raw = """
        version = 1

        [providers.xenodia]
        api_key = "xenodia-secret"
        model_override = "xenodia-model"

        [providers.elevenlabs]
        api_key = "elevenlabs-secret"
        """

        let parsed = ProviderSecretStore.parseSecrets(raw)

        XCTAssertEqual(parsed["xenodia"]?.apiKey, "xenodia-secret")
        XCTAssertEqual(parsed["xenodia"]?.modelOverride, "xenodia-model")
        XCTAssertEqual(parsed["elevenlabs"]?.apiKey, "elevenlabs-secret")
    }

    func testSaveAndClearProviderKeyPreservesModelOverride() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("geeagent-provider-secret-tests-\(UUID().uuidString)", isDirectory: true)
        let secretsURL = directory.appendingPathComponent("chat-runtime-secrets.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        version = 1

        [providers.xenodia]
        model_override = "xenodia-model"
        """.write(to: secretsURL, atomically: true, encoding: .utf8)

        let store = ProviderSecretStore(secretsURL: secretsURL)
        let saved = try store.saveAPIKey("xenodia-secret", providerID: "xenodia")
        XCTAssertEqual(saved.status(for: "xenodia")?.source, "saved")
        XCTAssertEqual(saved.status(for: "xenodia")?.savedAPIKeyConfigured, true)

        let attributes = try FileManager.default.attributesOfItem(atPath: secretsURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)

        _ = try store.clearAPIKey(providerID: "xenodia")
        let parsed = ProviderSecretStore.parseSecrets(
            try String(contentsOf: secretsURL, encoding: .utf8)
        )
        XCTAssertNil(parsed["xenodia"]?.apiKey)
        XCTAssertEqual(parsed["xenodia"]?.modelOverride, "xenodia-model")
    }

    func testRejectsProviderIDThatWouldBreakTomlShape() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("geeagent-provider-secret-tests-\(UUID().uuidString)", isDirectory: true)
        let secretsURL = directory.appendingPathComponent("chat-runtime-secrets.toml")
        let store = ProviderSecretStore(secretsURL: secretsURL)

        XCTAssertThrowsError(try store.saveAPIKey("secret", providerID: "bad]\napi_key = \"oops\""))
    }
}
