import XCTest
@testable import GeeAgentMac

final class Live2DMotionCatalogTests: XCTestCase {
    func testDiscoverCatalogSeparatesPosesActionsAndExpressions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = root.appendingPathComponent("Sample.model3.json")
        try """
        {
          "Version": 3,
          "FileReferences": {
            "Moc": "Sample.moc3",
            "Textures": [],
            "Physics": "Sample.physics3.json"
          }
        }
        """.write(to: descriptor, atomically: true, encoding: .utf8)

        let vtube = root.appendingPathComponent("Sample.vtube.json")
        try """
        {
          "Version": 1,
          "FileReferences": {
            "Model": "Sample.model3.json",
            "IdleAnimation": "idle.motion3.json",
            "IdleAnimationWhenTrackingLost": "sleep.motion3.json"
          },
          "Hotkeys": [
            {
              "Name": "Wave",
              "Action": "TriggerAnimation",
              "File": "motions/wave.motion3.json"
            },
            {
              "Name": "Blush",
              "Action": "ToggleExpression",
              "File": "blush.exp3.json"
            }
          ]
        }
        """.write(to: vtube, atomically: true, encoding: .utf8)

        try """
        { "Meta": { "Loop": true, "Duration": 3.2 } }
        """.write(to: root.appendingPathComponent("idle.motion3.json"), atomically: true, encoding: .utf8)
        try """
        { "Meta": { "Loop": true, "Duration": 4.8 } }
        """.write(to: root.appendingPathComponent("sleep.motion3.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("motions", isDirectory: true), withIntermediateDirectories: true)
        try """
        { "Meta": { "Loop": false, "Duration": 1.6 } }
        """.write(to: root.appendingPathComponent("motions/wave.motion3.json"), atomically: true, encoding: .utf8)
        try Data("{}".utf8).write(to: root.appendingPathComponent("blush.exp3.json"))

        let catalog = Live2DMotionCatalog.discoverCatalog(bundlePath: descriptor.path)

        XCTAssertEqual(catalog.defaultPose?.relativePath, "idle.motion3.json")
        XCTAssertEqual(catalog.fallbackPose?.relativePath, "sleep.motion3.json")
        XCTAssertEqual(catalog.poses.map(\.relativePath), [
            "idle.motion3.json",
            "sleep.motion3.json",
        ])
        XCTAssertEqual(catalog.actions.map(\.relativePath), [
            "motions/wave.motion3.json",
        ])
        XCTAssertEqual(catalog.actions.first?.isLoop, false)
        XCTAssertEqual(catalog.expressions.map(\.relativePath), [
            "blush.exp3.json",
        ])
    }

    func testDiscoverCatalogUsesModel3IdleAsPoseAndTapAsAction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = root.appendingPathComponent("Sample.model3.json")
        try """
        {
          "Version": 3,
          "FileReferences": {
            "Moc": "Sample.moc3",
            "Textures": [],
            "Motions": {
              "Idle": [
                { "File": "motions/idle.motion3.json" }
              ],
              "TapBody": [
                { "File": "motions/tap.motion3.json", "Name": "Tap Dance" }
              ]
            }
          }
        }
        """.write(to: descriptor, atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: root.appendingPathComponent("motions", isDirectory: true), withIntermediateDirectories: true)
        try """
        { "Meta": { "Loop": true, "Duration": 5.0 } }
        """.write(to: root.appendingPathComponent("motions/idle.motion3.json"), atomically: true, encoding: .utf8)
        try """
        { "Meta": { "Loop": false, "Duration": 1.2 } }
        """.write(to: root.appendingPathComponent("motions/tap.motion3.json"), atomically: true, encoding: .utf8)

        let catalog = Live2DMotionCatalog.discoverCatalog(bundlePath: descriptor.path)

        XCTAssertEqual(catalog.poses.first(where: { $0.relativePath == "motions/idle.motion3.json" })?.source, .model3)
        XCTAssertEqual(catalog.poses.first(where: { $0.relativePath == "motions/idle.motion3.json" })?.category, .pose)
        XCTAssertEqual(catalog.actions.first(where: { $0.relativePath == "motions/tap.motion3.json" })?.title, "Tap Dance")
        XCTAssertEqual(catalog.actions.first(where: { $0.relativePath == "motions/tap.motion3.json" })?.category, .action)
    }

    func testLoopingTriggerAnimationHotkeyIsPromotedToPose() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = root.appendingPathComponent("Sample.model3.json")
        try """
        {
          "Version": 3,
          "FileReferences": {
            "Moc": "Sample.moc3",
            "Textures": []
          }
        }
        """.write(to: descriptor, atomically: true, encoding: .utf8)

        let vtube = root.appendingPathComponent("Sample.vtube.json")
        try """
        {
          "Version": 1,
          "FileReferences": {
            "Model": "Sample.model3.json",
            "IdleAnimation": "idle.motion3.json"
          },
          "Hotkeys": [
            {
              "Name": "Sleep",
              "Action": "TriggerAnimation",
              "File": "sleep.motion3.json"
            },
            {
              "Name": "Wave",
              "Action": "TriggerAnimation",
              "File": "wave.motion3.json"
            }
          ]
        }
        """.write(to: vtube, atomically: true, encoding: .utf8)

        try """
        { "Meta": { "Loop": true, "Duration": 4.0 } }
        """.write(to: root.appendingPathComponent("idle.motion3.json"), atomically: true, encoding: .utf8)
        try """
        { "Meta": { "Loop": true, "Duration": 4.0 } }
        """.write(to: root.appendingPathComponent("sleep.motion3.json"), atomically: true, encoding: .utf8)
        try """
        { "Meta": { "Loop": false, "Duration": 1.2 } }
        """.write(to: root.appendingPathComponent("wave.motion3.json"), atomically: true, encoding: .utf8)

        let catalog = Live2DMotionCatalog.discoverCatalog(bundlePath: descriptor.path)

        XCTAssertTrue(catalog.poses.contains(where: { $0.relativePath == "sleep.motion3.json" }))
        XCTAssertFalse(catalog.actions.contains(where: { $0.relativePath == "sleep.motion3.json" }))
        XCTAssertTrue(catalog.actions.contains(where: { $0.relativePath == "wave.motion3.json" }))
    }
}
