import XCTest
@testable import GeeAgentMac

final class TodoManagerGearTests: XCTestCase {
    func testTodoManagerManifestDeclaresCodexExportedCapabilities() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Gears/todo.manager/gear.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(GearManifest.self, from: data)

        XCTAssertEqual(manifest.id, TodoManagerGearDescriptor.gearID)
        XCTAssertEqual(manifest.entry.nativeID, TodoManagerGearDescriptor.gearID)
        XCTAssertEqual(manifest.agent?.enabled, true)
        XCTAssertEqual(
            manifest.agent?.capabilities.map(\.id),
            ["todo.create", "todo.query", "todo.update", "todo.delete"]
        )
    }

    @MainActor
    func testAgentTodoLifecycleWritesGearOwnedData() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let created = await store.createAgentTodo(args: [
            "title": "Ship Todo Manager",
            "content": "Build the local-first task gear.",
            "tags": ["work", "#release"],
            "priority": 5,
            "checklist_items": ["Create gear package", "Wire Codex export"]
        ])

        XCTAssertEqual(created["gear_id"] as? String, TodoManagerGearDescriptor.gearID)
        XCTAssertEqual(created["capability_id"] as? String, "todo.create")
        XCTAssertEqual(created["status"] as? String, "created")
        let createdTask = try XCTUnwrap(created["task"] as? [String: Any])
        let taskID = try XCTUnwrap(createdTask["id"] as? String)
        XCTAssertEqual(createdTask["title"] as? String, "Ship Todo Manager")
        XCTAssertEqual(createdTask["priority"] as? Int, 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(createdTask["task_path"] as? String)))

        let queriedOpen = store.queryAgentTodos(args: [
            "status": "open",
            "tags": ["work"],
            "priority": [5]
        ])
        XCTAssertEqual(queriedOpen["status"] as? String, "succeeded")
        XCTAssertEqual(queriedOpen["count"] as? Int, 1)

        let updated = await store.updateAgentTodo(args: [
            "task_id": taskID,
            "completed": true
        ])
        XCTAssertEqual(updated["status"] as? String, "updated")
        let updatedTask = try XCTUnwrap(updated["task"] as? [String: Any])
        XCTAssertEqual(updatedTask["status"] as? String, "completed")
        XCTAssertNotNil(updatedTask["completed_at"])

        let queriedCompleted = store.queryAgentTodos(args: ["status": "completed"])
        XCTAssertEqual(queriedCompleted["count"] as? Int, 1)

        let deleted = await store.deleteAgentTodo(args: ["task_id": taskID])
        XCTAssertEqual(deleted["status"] as? String, "deleted")
        let deletedTask = try XCTUnwrap(deleted["task"] as? [String: Any])
        XCTAssertEqual(deletedTask["status"] as? String, "deleted")

        let queriedDeleted = store.queryAgentTodos(args: ["status": "deleted"])
        XCTAssertEqual(queriedDeleted["count"] as? Int, 1)
    }

    @MainActor
    func testCreateRejectsUnknownListInsteadOfCreatingFallbackList() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-list-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))
        let payload = await store.createAgentTodo(args: [
            "title": "Needs an existing list",
            "list_name": "Missing List"
        ])

        XCTAssertEqual(payload["status"] as? String, "failed")
        XCTAssertEqual(payload["code"] as? String, "todo.list_not_found")
    }

    @MainActor
    func testInvalidAgentArgumentsReturnStructuredFailures() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-args-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let invalidPriority = await store.createAgentTodo(args: [
            "title": "Bad priority",
            "priority": 2
        ])
        XCTAssertEqual(invalidPriority["status"] as? String, "failed")
        XCTAssertEqual(invalidPriority["code"] as? String, "gear.args.priority")

        let invalidDate = await store.createAgentTodo(args: [
            "title": "Bad due date",
            "due_at": "next friday"
        ])
        XCTAssertEqual(invalidDate["status"] as? String, "failed")
        XCTAssertEqual(invalidDate["code"] as? String, "gear.args.due_at")

        let invalidQuery = store.queryAgentTodos(args: ["status": "waiting"])
        XCTAssertEqual(invalidQuery["status"] as? String, "failed")
        XCTAssertEqual(invalidQuery["code"] as? String, "gear.args.status")
    }

    @MainActor
    func testCodexFriendlyArgumentAliasesReachNativeStore() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-alias-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))
        let created = await store.createAgentTodo(args: [
            "quickAddText": "Review bridge aliases"
        ])
        let createdTask = try XCTUnwrap(created["task"] as? [String: Any])
        let taskID = try XCTUnwrap(createdTask["id"] as? String)
        XCTAssertEqual(created["status"] as? String, "created")
        XCTAssertEqual(createdTask["title"] as? String, "Review bridge aliases")

        let updated = await store.updateAgentTodo(args: [
            "taskId": taskID,
            "completed": true
        ])
        XCTAssertEqual(updated["status"] as? String, "updated")
        let updatedTask = try XCTUnwrap(updated["task"] as? [String: Any])
        XCTAssertEqual(updatedTask["status"] as? String, "completed")

        let deleted = await store.deleteAgentTodo(args: ["id": taskID])
        XCTAssertEqual(deleted["status"] as? String, "deleted")
    }
}
