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

    func testDisabledGearDoesNotExposeAgentCapability() {
        let gearID = MediaLibraryGearDescriptor.gearID
        let original = GearHost.isEnabled(gearID: gearID)
        defer { GearHost.setEnabled(original, gearID: gearID) }

        GearHost.setEnabled(false, gearID: gearID)

        XCTAssertNil(
            GearHost.enabledCapabilityRecord(
                gearID: gearID,
                capabilityID: "media.filter"
            )
        )

        GearHost.setEnabled(true, gearID: gearID)

        XCTAssertNotNil(
            GearHost.enabledCapabilityRecord(
                gearID: gearID,
                capabilityID: "media.filter"
            )
        )
    }

    func testPreparationServiceInstallsWeSpyPythonRecipe() async throws {
        let data = Data("""
        {
          "schema": "gee.gear.v1",
          "id": "wespy.reader",
          "name": "WeSpy Reader",
          "description": "Article reader.",
          "developer": "Gee",
          "version": "0.1.0",
          "entry": { "type": "native", "native_id": "wespy.reader" },
          "dependencies": {
            "install_strategy": "on_open",
            "items": [
              {
                "id": "wespy-python",
                "kind": "runtime",
                "scope": "global",
                "required": true,
                "detect": { "command": "python3", "args": ["-c", "import wespy, requests, bs4"] },
                "installer": { "type": "recipe", "id": "python3.install.user.wespy" }
              }
            ]
          }
        }
        """.utf8)
        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)
        let runner = StatefulWeSpyInstallRunner()
        let suiteName = "wespy-prep-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = GearPreparationService(
            runner: runner,
            store: GearPreparationStore(defaults: defaults)
        )

        let snapshot = await service.prepareIfNeeded(
            manifest: manifest.resolvingAssets(relativeTo: URL(fileURLWithPath: "/tmp/wespy.reader"))
        )

        XCTAssertEqual(snapshot.state, .ready)
        let commands = await runner.commandHistory()
        XCTAssertTrue(commands.contains("python3 -m pip install --user wespy"))
        XCTAssertTrue(commands.contains("python3 -m pip install --user --break-system-packages wespy"))
    }
}

private struct FakeGearCommandRunner: GearCommandRunning {
    var responses: [String: GearCommandResult]

    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        let key = ([command] + arguments).joined(separator: " ")
        return responses[key] ?? GearCommandResult(exitCode: 127, stdout: "", stderr: "missing fake response: \(key)")
    }
}

private actor StatefulWeSpyInstallRunner: GearCommandRunning {
    private var detectAttempts = 0
    private var commands: [String] = []

    func run(_ command: String, arguments: [String]) async -> GearCommandResult {
        let key = ([command] + arguments).joined(separator: " ")
        commands.append(key)
        if key == "python3 -c import wespy, requests, bs4" {
            detectAttempts += 1
        }
        let attempt = detectAttempts

        switch key {
        case "command -v python3":
            return GearCommandResult(exitCode: 0, stdout: "/usr/bin/python3\n", stderr: "")
        case "python3 -c import wespy, requests, bs4":
            return attempt == 1
                ? GearCommandResult(exitCode: 1, stdout: "", stderr: "No module named wespy")
                : GearCommandResult(exitCode: 0, stdout: "", stderr: "")
        case "python3 -m pip install --user wespy":
            return GearCommandResult(exitCode: 1, stdout: "", stderr: "error: externally-managed-environment")
        case "python3 -m pip install --user --break-system-packages wespy":
            return GearCommandResult(exitCode: 0, stdout: "installed wespy\n", stderr: "")
        default:
            return GearCommandResult(exitCode: 127, stdout: "", stderr: "unexpected command: \(key)")
        }
    }

    func commandHistory() -> [String] {
        commands
    }
}
