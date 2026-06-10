import XCTest
@testable import GeeAgentMac

final class AgentGatewayClientStatusTests: XCTestCase {
    func testAgentGatewayClientStatusProjectionDecodesRuntimeShape() throws {
        let data = Data("""
        {
          "status": "success",
          "standard": "gee.agent_gateway.v0.1",
          "client_count": 3,
          "default_priority": ["codex", "claude_code", "workbuddy"],
          "supported_clients": ["codex", "claude_code", "workbuddy", "gee_internal"],
          "runtime_entrypoint": "/opt/geeagent/dist/native-runtime/index.mjs",
          "config_dir": "/Users/example/Library/Application Support/GeeAgent",
          "clients": [
            {
              "client_id": "claude_code",
              "title": "Claude Code",
              "priority": 2,
              "integration_state": "configuration_available",
              "connection_state": "not_verified",
              "transport": "stdio",
              "install_policy": "manual_user_action_required",
              "fallback_attempted": false,
              "mcp_server": {
                "name": "geeagent",
                "command": "node",
                "args": [
                  "/opt/geeagent/dist/native-runtime/index.mjs",
                  "agent-gateway-mcp",
                  "--client",
                  "claude_code",
                  "--config-dir",
                  "/Users/example/Library/Application Support/GeeAgent"
                ]
              },
              "config_targets": ["Claude Code MCP server entry"],
              "config_snippets": [
                {
                  "label": "MCP server JSON",
                  "format": "json",
                  "body": "{\\"mcpServers\\":{\\"geeagent\\":{}}}"
                }
              ],
              "notes": ["GeeAgentMac must stay running."]
            }
          ]
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let projection = try decoder.decode(AgentGatewayClientStatusProjection.self, from: data)

        XCTAssertEqual(projection.status, "success")
        XCTAssertEqual(projection.defaultPriority, ["codex", "claude_code", "workbuddy"])
        XCTAssertEqual(projection.configDir, "/Users/example/Library/Application Support/GeeAgent")
        let client = try XCTUnwrap(projection.clients.first)
        XCTAssertEqual(client.id, "claude_code")
        XCTAssertEqual(client.integrationStateTitle, "Config ready")
        XCTAssertEqual(client.connectionStateTitle, "Not verified")
        XCTAssertEqual(client.installPolicyTitle, "Manual setup")
        XCTAssertEqual(client.mcpServer.args[3], "claude_code")
        XCTAssertEqual(client.fallbackAttempted, false)
    }
}
