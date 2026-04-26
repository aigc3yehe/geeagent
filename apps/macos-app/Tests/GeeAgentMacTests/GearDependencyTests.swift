import XCTest
@testable import GeeAgentMac

final class GearDependencyTests: XCTestCase {
    func testManifestDecodesGlobalDependencies() throws {
        let data = Data("""
        {
          "schema": "gee.gear.v1",
          "id": "hyperframes.studio",
          "name": "Hyperframes Studio",
          "description": "HTML-to-video production app.",
          "developer": "Gee",
          "version": "0.1.0",
          "category": "Video",
          "kind": "atmosphere",
          "display_mode": "full_canvas",
          "entry": { "type": "native", "native_id": "hyperframes.studio" },
          "dependencies": {
            "install_strategy": "on_open",
            "items": [
              {
                "id": "node",
                "kind": "runtime",
                "scope": "global",
                "required": true,
                "detect": {
                  "command": "node",
                  "args": ["--version"],
                  "min_version": "22.0.0"
                },
                "installer": {
                  "type": "recipe",
                  "id": "brew.install.node"
                }
              }
            ]
          }
        }
        """.utf8)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        let plan = try XCTUnwrap(manifest.dependencies)
        XCTAssertEqual(plan.installStrategy, .onOpen)
        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.items[0].id, "node")
        XCTAssertEqual(plan.items[0].scope, .global)
        XCTAssertEqual(plan.items[0].detect?.minVersion, "22.0.0")
        XCTAssertEqual(plan.items[0].installer?.id, "brew.install.node")
    }

    func testGlobalPreflightAcceptsCompatibleVersion() async throws {
        let item = GearDependencyItem(
            id: "node",
            kind: .runtime,
            scope: .global,
            required: true,
            target: nil,
            detect: GearDependencyDetect(
                command: "node",
                args: ["--version"],
                minVersion: "22.0.0",
                healthCommand: nil,
                healthArgs: nil
            ),
            installer: nil
        )
        let preflight = GearDependencyPreflight(runner: FakeGearCommandRunner(responses: [
            "command -v node": GearCommandResult(exitCode: 0, stdout: "/opt/homebrew/bin/node\n", stderr: ""),
            "node --version": GearCommandResult(exitCode: 0, stdout: "v22.2.0\n", stderr: "")
        ]))

        let result = await preflight.check(item: item, rootURL: URL(fileURLWithPath: "/tmp/gear"))

        XCTAssertTrue(result.isSatisfied)
    }

    func testGlobalPreflightRejectsMissingCommand() async throws {
        let item = GearDependencyItem(
            id: "ffmpeg",
            kind: .binary,
            scope: .global,
            required: true,
            target: nil,
            detect: GearDependencyDetect(
                command: "ffmpeg",
                args: ["-version"],
                minVersion: nil,
                healthCommand: nil,
                healthArgs: nil
            ),
            installer: nil
        )
        let preflight = GearDependencyPreflight(runner: FakeGearCommandRunner(responses: [
            "command -v ffmpeg": GearCommandResult(exitCode: 1, stdout: "", stderr: "")
        ]))

        let result = await preflight.check(item: item, rootURL: URL(fileURLWithPath: "/tmp/gear"))

        XCTAssertFalse(result.isSatisfied)
        XCTAssertTrue(result.summary.contains("not installed"))
    }

    func testVersionComparisonHandlesPartialVersions() {
        XCTAssertEqual(GearDependencyPreflight.compareVersions("22", "22.0.0"), .orderedSame)
        XCTAssertEqual(GearDependencyPreflight.compareVersions("21.9.0", "22.0.0"), .orderedAscending)
        XCTAssertEqual(GearDependencyPreflight.compareVersions("22.1", "22.0.9"), .orderedDescending)
    }
}

private struct FakeGearCommandRunner: GearCommandRunning {
    var responses: [String: GearCommandResult]

    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        let key = ([command] + arguments).joined(separator: " ")
        return responses[key] ?? GearCommandResult(exitCode: 127, stdout: "", stderr: "missing fake response: \(key)")
    }
}
