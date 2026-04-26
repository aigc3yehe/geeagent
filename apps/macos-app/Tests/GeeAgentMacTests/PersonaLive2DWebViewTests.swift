import XCTest
@testable import GeeAgentMac

final class PersonaLive2DWebViewTests: XCTestCase {
    typealias Coordinator = PersonaLive2DWebView.Coordinator

    func testConfigurationScriptSerializesBundlePath() throws {
        let raw = "/Users/me/Library/Application Support/GeeAgent/Personas/gee/live2d/haru/haru.model3.json"
        let js = Coordinator.configurationScript(for: raw)

        XCTAssertTrue(js.contains("window.geeLive2DConfig ="))
        XCTAssertTrue(js.contains("\"modelUrl\""), "script should expose the model URL to the host")
        XCTAssertTrue(js.contains("haru.model3.json"), "serialized path should survive JSON encoding")

        let dict = try decodeConfigPayload(from: js)
        let modelUrl = try XCTUnwrap(dict["modelUrl"] as? String)
        XCTAssertTrue(modelUrl.contains("haru.model3.json"), "modelUrl should keep the target file reachable, got: \(modelUrl)")
        XCTAssertTrue(modelUrl.hasPrefix("geeagent-live2d://") || modelUrl.hasPrefix("file://"))
        XCTAssertEqual(dict["modelPath"] as? String, raw, "raw POSIX path should remain on modelPath")
        XCTAssertNil(dict["previewImageUrl"] as? String)
    }

    func testConfigurationScriptEscapesProblematicCharacters() throws {
        let tricky = "/tmp/\"quotes\"/path with spaces/back\\slash/model.model3.json"
        let js = Coordinator.configurationScript(for: tricky)

        // Round-tripping the JSON payload back yields the same raw path on modelPath; modelUrl
        // is the percent-encoded file URL form of the same path.
        let dict = try decodeConfigPayload(from: js)
        XCTAssertEqual(dict["modelPath"] as? String, tricky)
        let modelURL = try XCTUnwrap(dict["modelUrl"] as? String)
        XCTAssertTrue(modelURL.contains("model.model3.json"))
    }

    func testReadAccessRootFallsBackToHostDirWhenBundlePathEmpty() {
        let host = URL(fileURLWithPath: "/Applications/GeeAgentMac.app/Contents/Resources/Live2DHost")
        let root = Coordinator.readAccessRoot(hostDir: host, bundleDir: nil)
        XCTAssertEqual(root, host)
    }

    func testReadAccessRootPicksDeepestSharedAncestor() {
        let host = URL(fileURLWithPath: "/Users/me/Documents/geeagent/apps/macos-app/dist/GeeAgentMac.app/Contents/Resources/Live2DHost")
        let bundle = URL(fileURLWithPath: "/Users/me/Library/Application Support/GeeAgent/Personas/gee/live2d/abc123")

        let root = Coordinator.readAccessRoot(hostDir: host, bundleDir: bundle)
        XCTAssertEqual(root.path, "/Users/me", "should widen just enough to cover both the app bundle and the persona dir")
    }

    func testReadAccessRootHandlesDisjointTreesByFallingBackToHostParent() {
        let host = URL(fileURLWithPath: "/Applications/GeeAgentMac.app/Contents/Resources/Live2DHost")
        let bundle = URL(fileURLWithPath: "/Volumes/External/Personas/manga/live2d/xyz")

        let root = Coordinator.readAccessRoot(hostDir: host, bundleDir: bundle)
        XCTAssertEqual(root.path, "/Applications/GeeAgentMac.app/Contents/Resources", "disjoint trees should stay anchored near the host dir")
    }

    func testCommonAncestorOfIdenticalPathsIsThatPath() {
        let shared = URL(fileURLWithPath: "/Users/me/Library")
        XCTAssertEqual(Coordinator.commonAncestorDirectory(shared, shared).path, shared.path)
    }

    func testPreviewImageDataURLPrefersBundleIcon() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let modelURL = temp.appendingPathComponent("avatar.model3.json")
        try "{}".data(using: .utf8)?.write(to: modelURL)

        let iconURL = temp.appendingPathComponent("icon.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: iconURL)

        let dataURL = try XCTUnwrap(Coordinator.previewImageDataURL(for: modelURL.path))
        XCTAssertTrue(dataURL.hasPrefix("data:image/jpeg;base64,"))
    }

    func testModelResourceURLUsesCustomSchemeForPersonaBundles() {
        let raw = "/Users/me/Library/Application Support/GeeAgent/Personas/gee/live2d/haru/haru.model3.json"
        let value = Coordinator.modelResourceURLString(for: raw)
        XCTAssertTrue(value.hasPrefix("geeagent-live2d://app/persona/"))
        XCTAssertTrue(value.contains("haru.model3.json"))
    }

    // MARK: - Helpers

    private func decodeConfigPayload(from js: String) throws -> [String: Any] {
        let payload = js.replacingOccurrences(of: "window.geeLive2DConfig = ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let data = try XCTUnwrap(payload.data(using: .utf8))
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any])
    }
}
