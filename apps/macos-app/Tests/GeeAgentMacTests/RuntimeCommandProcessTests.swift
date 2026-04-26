import XCTest
@testable import GeeAgentMac

final class RuntimeCommandProcessTests: XCTestCase {
    func testNativeRuntimeUsesBundledMjsEntry() {
        XCTAssertEqual(NativeRuntimeBundle.entryFileName, "index.mjs")
        XCTAssertEqual(NativeRuntimeBundle.resourceDirectory, "agent-runtime/native-runtime")
        XCTAssertEqual(NativeRuntimeBundle.sdkCliResourceDirectory, "agent-runtime/claude-sdk")
        XCTAssertEqual(NativeRuntimeBundle.sdkCliFileName, "claude")
        XCTAssertEqual(NativeRuntimeBundle.configResourceDirectory, "agent-runtime/config")
        XCTAssertEqual(NativeRuntimeBundle.modelRoutingConfigFileName, "model-routing.toml")
        XCTAssertEqual(NativeRuntimeBundle.chatRuntimeConfigFileName, "chat-runtime.toml")
    }

    func testLongLivedServerReturnsLineWithoutClosingStdout() throws {
        let server = RuntimeCommandServer(label: "test runtime")
        defer { server.stop() }

        let script = """
        import json
        import sys

        for line in sys.stdin:
            request = json.loads(line)
            print(json.dumps({
                "id": request["id"],
                "ok": True,
                "output": "pong"
            }), flush=True)
        """
        let launch = RuntimeCommandLaunch(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-u", "-c", script],
            currentDirectoryURL: nil,
            fingerprintURL: URL(fileURLWithPath: "/usr/bin/env"),
            environment: ProcessInfo.processInfo.environment
        )

        let output = try server.run(
            command: "snapshot",
            args: [],
            launch: launch,
            timeout: 2
        )

        XCTAssertEqual(String(data: output, encoding: .utf8), "pong")
    }

    func testServerExitBeforeReplyFailsWithoutWaitingForTimeout() throws {
        let server = RuntimeCommandServer(label: "test runtime")
        defer { server.stop() }

        let script = "import sys; sys.exit(0)"
        let launch = RuntimeCommandLaunch(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-u", "-c", script],
            currentDirectoryURL: nil,
            fingerprintURL: URL(fileURLWithPath: "/usr/bin/env"),
            environment: ProcessInfo.processInfo.environment
        )

        let startedAt = Date()
        XCTAssertThrowsError(
            try server.run(
                command: "snapshot",
                args: [],
                launch: launch,
                timeout: 2
            )
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("exited before replying"),
                "Unexpected error: \(error.localizedDescription)"
            )
        }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
    }
}
