import XCTest
@testable import GeeAgentMac

final class TelegramBridgeGearTests: XCTestCase {
    func testManifestDeclaresPushOnlyCapabilities() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/telegram.bridge/gear.json")
        let data = try Data(contentsOf: manifestURL)

        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rawAgent = try XCTUnwrap(raw["agent"] as? [String: Any])
        let rawCapabilities = try XCTUnwrap(rawAgent["capabilities"] as? [[String: Any]])

        XCTAssertEqual(manifest.id, TelegramBridgeGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.nativeID, TelegramBridgeGearDescriptor.gearID)
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(manifest.agent?.capabilities.map(\.id), [
            "telegram_bridge.status",
            "telegram_push.list_channels",
            "telegram_push.upsert_channel",
            "telegram_push.send_message"
        ])
        XCTAssertEqual(rawAgent["enabled"] as? Bool, true)
        let exportsByID = Dictionary(
            uniqueKeysWithValues: rawCapabilities.compactMap { capability -> (String, Bool)? in
                guard let id = capability["id"] as? String,
                      let exports = capability["exports"] as? [String: Any],
                      let codex = exports["codex"] as? [String: Any],
                      let enabled = codex["enabled"] as? Bool
                else {
                    return nil
                }
                return (id, enabled)
            }
        )
        XCTAssertEqual(exportsByID["telegram_bridge.status"], true)
        XCTAssertEqual(exportsByID["telegram_push.list_channels"], true)
        XCTAssertEqual(exportsByID["telegram_push.upsert_channel"], false)
        XCTAssertEqual(exportsByID["telegram_push.send_message"], true)
    }

    func testNativeWindowDescriptorIsRegistered() {
        XCTAssertTrue(
            GearHost.nativeWindowDescriptors.contains { descriptor in
                descriptor.gearID == TelegramBridgeGearDescriptor.gearID &&
                descriptor.windowID == GearHost.telegramBridgeWindowID
            }
        )
    }
}
