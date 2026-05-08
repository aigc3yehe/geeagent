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

    @MainActor
    func testCreateTodoReusesExistingTaskForIdempotencyKey() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-idempotency-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))
        let args: [String: Any] = [
            "title": "Run Power Video Manager workflow test",
            "idempotency_key": "conversation-1-message-1-todo-create"
        ]

        let first = await store.createAgentTodo(args: args)
        let second = await store.createAgentTodo(args: args)

        XCTAssertEqual(first["status"] as? String, "created")
        XCTAssertEqual(second["status"] as? String, "reused")
        let firstTask = try XCTUnwrap(first["task"] as? [String: Any])
        let secondTask = try XCTUnwrap(second["task"] as? [String: Any])
        XCTAssertEqual(firstTask["id"] as? String, secondTask["id"] as? String)
        XCTAssertEqual(store.queryAgentTodos(args: ["status": "open"])["count"] as? Int, 1)
    }

    @MainActor
    func testCreateTodoReusesRecentExactPlainDuplicateWithoutIdempotencyKey() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-plain-dedupe-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))
        let args: [String: Any] = [
            "title": "Improve automated video Telegram notifications",
            "content": "Keep the task plain; no due date from the model retry."
        ]

        let first = await store.createAgentTodo(args: args)
        let second = await store.createAgentTodo(args: args)

        XCTAssertEqual(first["status"] as? String, "created")
        XCTAssertEqual(second["status"] as? String, "reused")
        let firstTask = try XCTUnwrap(first["task"] as? [String: Any])
        let secondTask = try XCTUnwrap(second["task"] as? [String: Any])
        XCTAssertEqual(firstTask["id"] as? String, secondTask["id"] as? String)
        XCTAssertEqual(store.queryAgentTodos(args: ["status": "open"])["count"] as? Int, 1)
    }

    @MainActor
    func testCreateTodoReusesRecentChecklistDuplicateWithoutIdempotencyKey() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-checklist-dedupe-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))
        let args: [String: Any] = [
            "title": "Prepare launch checklist",
            "checklist_items": ["Open settings", "Send test reminder"]
        ]

        let first = await store.createAgentTodo(args: args)
        let second = await store.createAgentTodo(args: args)

        XCTAssertEqual(first["status"] as? String, "created")
        XCTAssertEqual(second["status"] as? String, "reused")
        let firstTask = try XCTUnwrap(first["task"] as? [String: Any])
        let secondTask = try XCTUnwrap(second["task"] as? [String: Any])
        XCTAssertEqual(firstTask["id"] as? String, secondTask["id"] as? String)
        XCTAssertEqual(store.queryAgentTodos(args: ["status": "open"])["count"] as? Int, 1)
    }

    @MainActor
    func testCreateTodoDoesNotReuseRecentDuplicateWhenBodyDiffers() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-dedupe-signature-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let first = await store.createAgentTodo(args: [
            "title": "Review generated video notifications",
            "content": "Telegram delivery path"
        ])
        let second = await store.createAgentTodo(args: [
            "title": "Review generated video notifications",
            "content": "Desktop notification path"
        ])

        XCTAssertEqual(first["status"] as? String, "created")
        XCTAssertEqual(second["status"] as? String, "created")
        XCTAssertEqual(store.queryAgentTodos(args: ["status": "open"])["count"] as? Int, 2)
    }

    @MainActor
    func testCreateTodoNormalizesTodayTextIntoTodayBucket() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-today-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let created = await store.createAgentTodo(args: [
            "title": "Finish power video production flow testing today."
        ])

        XCTAssertEqual(created["status"] as? String, "created")
        let task = try XCTUnwrap(created["task"] as? [String: Any])
        let dueAt = try XCTUnwrap(task["due_at"] as? String)
        XCTAssertEqual(task["is_all_day"] as? Bool, true)
        XCTAssertNotNil(TodoManagerDateCodec.date(from: dueAt).flatMap { Calendar.current.isDateInToday($0) ? $0 : nil })

        let today = store.queryAgentTodos(args: ["due": "today"])
        XCTAssertEqual(today["count"] as? Int, 1)
    }

    @MainActor
    func testCreateTodoNormalizesReminderTextIntoDueAndReminder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-reminder-text-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let created = await store.createAgentTodo(args: [
            "title": "Remind me to take medicine tomorrow at 3 pm"
        ])

        XCTAssertEqual(created["status"] as? String, "partial")
        XCTAssertEqual(created["warnings"] as? [String], ["todo.reminder.notification_center_unavailable"])
        let task = try XCTUnwrap(created["task"] as? [String: Any])
        XCTAssertEqual(task["is_all_day"] as? Bool, false)
        let dueAt = try XCTUnwrap(TodoManagerDateCodec.date(from: try XCTUnwrap(task["due_at"] as? String)))
        let components = Calendar.current.dateComponents([.hour, .minute], from: dueAt)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 0)
        let reminders = try XCTUnwrap(task["reminders"] as? [[String: Any]])
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders[0]["trigger_at"] as? String, TodoManagerDateCodec.string(from: dueAt))
    }

    @MainActor
    func testCreateTodoNormalizesNextWeekdayReminderText() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-weekday-reminder-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let created = await store.createAgentTodo(args: [
            "title": "Remind me to review next friday at 3 pm"
        ])

        XCTAssertEqual(created["status"] as? String, "partial")
        let task = try XCTUnwrap(created["task"] as? [String: Any])
        let dueAt = try XCTUnwrap(TodoManagerDateCodec.date(from: try XCTUnwrap(task["due_at"] as? String)))
        let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: dueAt)
        XCTAssertEqual(components.weekday, 6)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 0)
        XCTAssertGreaterThan(dueAt.timeIntervalSinceNow, 0)
        let reminders = try XCTUnwrap(task["reminders"] as? [[String: Any]])
        XCTAssertEqual(reminders[0]["trigger_at"] as? String, TodoManagerDateCodec.string(from: dueAt))
    }

    @MainActor
    func testCreateTodoNormalizesEnglishNextWeekdayReminderText() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-english-weekday-reminder-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let calendar = Calendar.current
        let expectedDay = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: 2,
            to: calendar.startOfDay(for: Date())
        ))
        let weekdayName = englishWeekdayName(for: expectedDay, calendar: calendar)
        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let created = await store.createAgentTodo(args: [
            "title": "next \(weekdayName) 3pm remind me to review"
        ])

        XCTAssertEqual(created["status"] as? String, "partial")
        let task = try XCTUnwrap(created["task"] as? [String: Any])
        let dueAt = try XCTUnwrap(TodoManagerDateCodec.date(from: try XCTUnwrap(task["due_at"] as? String)))
        let components = calendar.dateComponents([.hour, .minute], from: dueAt)
        XCTAssertTrue(calendar.isDate(dueAt, inSameDayAs: expectedDay))
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 0)
    }

    @MainActor
    func testCreateTodoNormalizesExplicitDateReminderText() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-explicit-date-reminder-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let calendar = Calendar.current
        let expectedDay = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: 9,
            to: calendar.startOfDay(for: Date())
        ))
        let dateText = yyyyMMddString(for: expectedDay, calendar: calendar)
        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let created = await store.createAgentTodo(args: [
            "title": "\(dateText) 14:30 remind me to archive receipts"
        ])

        XCTAssertEqual(created["status"] as? String, "partial")
        let task = try XCTUnwrap(created["task"] as? [String: Any])
        let dueAt = try XCTUnwrap(TodoManagerDateCodec.date(from: try XCTUnwrap(task["due_at"] as? String)))
        let components = calendar.dateComponents([.hour, .minute], from: dueAt)
        XCTAssertTrue(calendar.isDate(dueAt, inSameDayAs: expectedDay))
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 30)
        let reminders = try XCTUnwrap(task["reminders"] as? [[String: Any]])
        XCTAssertEqual(reminders[0]["trigger_at"] as? String, TodoManagerDateCodec.string(from: dueAt))
    }

    @MainActor
    func testCreateTodoNormalizesWeekendTextIntoAllDayDueDate() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-weekend-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let calendar = Calendar.current
        let expectedDay = upcomingWeekendDay(calendar: calendar)
        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let created = await store.createAgentTodo(args: [
            "title": "Organize the task list this weekend"
        ])

        XCTAssertEqual(created["status"] as? String, "created")
        let task = try XCTUnwrap(created["task"] as? [String: Any])
        let dueAt = try XCTUnwrap(TodoManagerDateCodec.date(from: try XCTUnwrap(task["due_at"] as? String)))
        let components = calendar.dateComponents([.hour, .minute], from: dueAt)
        XCTAssertTrue(calendar.isDate(dueAt, inSameDayAs: expectedDay))
        XCTAssertEqual(task["is_all_day"] as? Bool, true)
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 59)
    }

    @MainActor
    func testCreateTodoNormalizesMorningDayPartWithoutReminderIntent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-morning-day-part-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let calendar = Calendar.current
        let expectedDay = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        ))
        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let created = await store.createAgentTodo(args: [
            "title": "tomorrow morning organize the task list"
        ])

        XCTAssertEqual(created["status"] as? String, "created")
        let task = try XCTUnwrap(created["task"] as? [String: Any])
        let dueAt = try XCTUnwrap(TodoManagerDateCodec.date(from: try XCTUnwrap(task["due_at"] as? String)))
        let components = calendar.dateComponents([.hour, .minute], from: dueAt)
        XCTAssertTrue(calendar.isDate(dueAt, inSameDayAs: expectedDay))
        XCTAssertEqual(task["is_all_day"] as? Bool, false)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    @MainActor
    func testCreateTodoNormalizesEnglishDayPartWithoutReminderIntent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-english-day-part-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let calendar = Calendar.current
        let expectedDay = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        ))
        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let created = await store.createAgentTodo(args: [
            "title": "tomorrow afternoon review launch plan"
        ])

        XCTAssertEqual(created["status"] as? String, "created")
        let task = try XCTUnwrap(created["task"] as? [String: Any])
        let dueAt = try XCTUnwrap(TodoManagerDateCodec.date(from: try XCTUnwrap(task["due_at"] as? String)))
        let components = calendar.dateComponents([.hour, .minute], from: dueAt)
        XCTAssertTrue(calendar.isDate(dueAt, inSameDayAs: expectedDay))
        XCTAssertEqual(task["is_all_day"] as? Bool, false)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 0)
    }

    @MainActor
    func testReminderArgumentsRequireAResolvableReminderTime() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-reminder-validation-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        let missingTime = await store.createAgentTodo(args: [
            "title": "Remind me to take medicine"
        ])
        XCTAssertEqual(missingTime["status"] as? String, "failed")
        XCTAssertEqual(missingTime["code"] as? String, "todo.reminder.time_required")

        let missingConcreteDayPartTime = await store.createAgentTodo(args: [
            "title": "Remind me to organize the task list tomorrow morning"
        ])
        XCTAssertEqual(missingConcreteDayPartTime["status"] as? String, "failed")
        XCTAssertEqual(missingConcreteDayPartTime["code"] as? String, "todo.reminder.time_required")

        let missingDue = await store.createAgentTodo(args: [
            "title": "Prepare review",
            "reminders": [
                ["minutes_before_due": 30]
            ]
        ])
        XCTAssertEqual(missingDue["status"] as? String, "failed")
        XCTAssertEqual(missingDue["code"] as? String, "todo.reminder.due_time_required")
    }

    @MainActor
    func testReminderEditingSupportsAddUpdateAndRemove() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-reminder-editing-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))
        let dueAt = Date().addingTimeInterval(86_400)
        let created = await store.createAgentTodo(args: [
            "title": "Review reminder editor",
            "due_at": TodoManagerDateCodec.string(from: dueAt)
        ])
        var task = try taskRecord(from: created)

        let firstReminderAt = dueAt.addingTimeInterval(-3_600)
        let addedAbsolute = await store.addReminder(task, at: firstReminderAt)
        task = try taskRecord(from: addedAbsolute)
        XCTAssertEqual(task.reminders.count, 1)
        assertDate(task.reminders[0].triggerAt, equals: firstReminderAt)

        let addedRelative = await store.addRelativeReminder(task, minutesBeforeDue: 30)
        task = try taskRecord(from: addedRelative)
        XCTAssertEqual(task.reminders.count, 2)
        XCTAssertEqual(task.reminders[1].minutesBeforeDue, 30)

        let updatedReminderAt = dueAt.addingTimeInterval(-1_800)
        let updated = await store.updateReminder(task.reminders[0].id, in: task, at: updatedReminderAt)
        task = try taskRecord(from: updated)
        XCTAssertEqual(task.reminders.count, 2)
        assertDate(task.reminders[0].triggerAt, equals: updatedReminderAt)

        let removed = await store.removeReminder(task.reminders[1].id, from: task)
        task = try taskRecord(from: removed)
        XCTAssertEqual(task.reminders.count, 1)
        assertDate(task.reminders[0].triggerAt, equals: updatedReminderAt)
    }

    @MainActor
    func testTodayBucketIncludesReminderOnlyTasks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-reminder-today-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))
        let created = await store.createAgentTodo(args: [
            "title": "Reminder-only Today task"
        ])
        let task = try taskRecord(from: created)
        _ = await store.updateAgentTodo(args: [
            "task_id": task.id,
            "reminders": [
                ["trigger_at": TodoManagerDateCodec.string(from: Date())]
            ]
        ])

        let today = store.queryAgentTodos(args: ["due": "today"])
        XCTAssertEqual(today["count"] as? Int, 1)
    }

    @MainActor
    func testQueryPayloadReportsScheduleSummaryForDailyReview() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-manager-schedule-summary-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let calendar = Calendar.current
        let now = Date()
        let todayEnd = try XCTUnwrap(calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now))
        let store = TodoManagerGearStore(database: TodoManagerFileDatabase(rootURL: root))

        _ = await store.createAgentTodo(args: [
            "title": "Overdue timed due",
            "due_at": TodoManagerDateCodec.string(from: now.addingTimeInterval(-3_600))
        ])
        _ = await store.createAgentTodo(args: [
            "title": "All-day today",
            "due_at": TodoManagerDateCodec.string(from: todayEnd),
            "is_all_day": true
        ])
        _ = await store.createAgentTodo(args: [
            "title": "Start tomorrow",
            "start_at": TodoManagerDateCodec.string(from: now.addingTimeInterval(86_400))
        ])
        _ = await store.createAgentTodo(args: [
            "title": "Reminder-only upcoming",
            "reminders": [
                ["trigger_at": TodoManagerDateCodec.string(from: now.addingTimeInterval(86_400))]
            ]
        ])
        _ = await store.createAgentTodo(args: [
            "title": "No schedule"
        ])

        let queried = store.queryAgentTodos(args: ["status": "open", "limit": 10])
        let tasks = try taskPayloads(from: queried)
        let byTitle = Dictionary(uniqueKeysWithValues: tasks.compactMap { task in
            (task["title"] as? String).map { ($0, task) }
        })

        XCTAssertEqual(byTitle["Overdue timed due"]?["date_source"] as? String, "due_at")
        XCTAssertEqual(byTitle["Overdue timed due"]?["date_state"] as? String, "overdue")
        XCTAssertEqual(byTitle["Overdue timed due"]?["time_state"] as? String, "timed")
        XCTAssertEqual(byTitle["Overdue timed due"]?["is_overdue"] as? Bool, true)
        XCTAssertNotNil(byTitle["Overdue timed due"]?["relevant_at"] as? String)

        XCTAssertEqual(byTitle["All-day today"]?["date_source"] as? String, "due_at")
        XCTAssertEqual(byTitle["All-day today"]?["date_state"] as? String, "today")
        XCTAssertEqual(byTitle["All-day today"]?["time_state"] as? String, "all_day")

        XCTAssertEqual(byTitle["Start tomorrow"]?["date_source"] as? String, "start_at")
        XCTAssertEqual(byTitle["Start tomorrow"]?["date_state"] as? String, "upcoming")
        XCTAssertEqual(byTitle["Start tomorrow"]?["time_state"] as? String, "timed")

        XCTAssertEqual(byTitle["Reminder-only upcoming"]?["date_source"] as? String, "reminder")
        XCTAssertEqual(byTitle["Reminder-only upcoming"]?["date_state"] as? String, "upcoming")
        XCTAssertEqual(byTitle["Reminder-only upcoming"]?["time_state"] as? String, "timed")

        XCTAssertEqual(byTitle["No schedule"]?["date_source"] as? String, "none")
        XCTAssertEqual(byTitle["No schedule"]?["date_state"] as? String, "unscheduled")
        XCTAssertEqual(byTitle["No schedule"]?["time_state"] as? String, "unscheduled")
        XCTAssertEqual(byTitle["No schedule"]?["is_overdue"] as? Bool, false)
        XCTAssertNil(byTitle["No schedule"]?["relevant_at"])
    }

    private func taskRecord(from payload: [String: Any]) throws -> TodoManagerTaskRecord {
        let taskPayload = try XCTUnwrap(payload["task"] as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: taskPayload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TodoManagerTaskRecord.self, from: data)
    }

    private func taskPayloads(from payload: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(payload["tasks"] as? [[String: Any]])
    }

    private func assertDate(
        _ actual: Date?,
        equals expected: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected a date", file: file, line: line)
            return
        }
        XCTAssertLessThan(abs(actual.timeIntervalSince(expected)), 1, file: file, line: line)
    }

    private func englishWeekdayName(for date: Date, calendar: Calendar) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: "Sunday"
        case 2: "Monday"
        case 3: "Tuesday"
        case 4: "Wednesday"
        case 5: "Thursday"
        case 6: "Friday"
        case 7: "Saturday"
        default: "Monday"
        }
    }

    private func yyyyMMddString(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            try! XCTUnwrap(components.year),
            try! XCTUnwrap(components.month),
            try! XCTUnwrap(components.day)
        )
    }

    private func upcomingWeekendDay(calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        let dayOffset = isoWeekday <= 6 ? 6 - isoWeekday : 0
        return calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
    }
}
