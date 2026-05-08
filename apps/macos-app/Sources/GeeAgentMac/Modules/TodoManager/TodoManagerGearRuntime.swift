import AppKit
import Foundation
import UserNotifications

enum TodoManagerGearDescriptor {
    static let gearID = "todo.manager"
}

enum TodoManagerNotificationCenterFactory {
    static func systemCenterIfAvailable() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
        return .current()
    }
}

enum TodoManagerNotificationState: String, Equatable {
    case unavailable
    case notDetermined
    case authorized
    case denied
    case provisional
    case ephemeral

    init(status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unavailable
        }
    }

    var title: String {
        switch self {
        case .unavailable: "Notification center unavailable"
        case .notDetermined: "Notifications not requested"
        case .authorized: "Notifications authorized"
        case .denied: "Notifications denied"
        case .provisional: "Notifications provisional"
        case .ephemeral: "Notifications temporary"
        }
    }

    var detail: String {
        switch self {
        case .unavailable:
            return "Reminders are stored, but this runtime cannot schedule macOS notifications."
        case .notDetermined:
            return "The first scheduled reminder will ask macOS for permission."
        case .authorized, .provisional, .ephemeral:
            return "Future reminders can be scheduled through macOS notifications."
        case .denied:
            return "Reminders are stored, but macOS notification permission is denied."
        }
    }

    var systemImage: String {
        switch self {
        case .authorized, .provisional, .ephemeral: "bell.badge"
        case .denied: "bell.slash"
        case .notDetermined: "bell.badge.questionmark"
        case .unavailable: "bell"
        }
    }

    var showsSettingsAction: Bool {
        self == .denied || self == .unavailable
    }
}

struct TodoManagerListRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var color: String
    var sortOrder: Int64
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var agentDictionary: [String: Any] {
        [
            "id": id,
            "name": name,
            "color": color,
            "sort_order": sortOrder,
            "created_at": TodoManagerDateCodec.string(from: createdAt),
            "updated_at": TodoManagerDateCodec.string(from: updatedAt)
        ]
    }
}

struct TodoManagerReminderRecord: Codable, Identifiable, Hashable {
    var id: String
    var triggerAt: Date?
    var minutesBeforeDue: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case triggerAt = "trigger_at"
        case minutesBeforeDue = "minutes_before_due"
    }

    func triggerDate(for task: TodoManagerTaskRecord) -> Date? {
        if let triggerAt {
            return triggerAt
        }
        guard let dueAt = task.dueAt, let minutesBeforeDue else {
            return nil
        }
        return Calendar.current.date(byAdding: .minute, value: -minutesBeforeDue, to: dueAt)
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = ["id": id]
        if let triggerAt {
            payload["trigger_at"] = TodoManagerDateCodec.string(from: triggerAt)
        }
        if let minutesBeforeDue {
            payload["minutes_before_due"] = minutesBeforeDue
        }
        return payload
    }
}

struct TodoManagerChecklistItemRecord: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var isCompleted: Bool
    var sortOrder: Int64
    var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isCompleted = "is_completed"
        case sortOrder = "sort_order"
        case completedAt = "completed_at"
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "title": title,
            "is_completed": isCompleted,
            "sort_order": sortOrder
        ]
        if let completedAt {
            payload["completed_at"] = TodoManagerDateCodec.string(from: completedAt)
        }
        return payload
    }
}

struct TodoManagerTaskScheduleSummary: Equatable {
    var dateSource: String
    var dateState: String
    var timeState: String
    var relevantAt: Date?
    var isOverdue: Bool
}

struct TodoManagerTaskRecord: Codable, Identifiable, Hashable {
    var id: String
    var idempotencyKey: String?
    var listID: String
    var title: String
    var content: String
    var status: String
    var priority: Int
    var tags: [String]
    var startAt: Date?
    var dueAt: Date?
    var timezone: String
    var isAllDay: Bool
    var reminders: [TodoManagerReminderRecord]
    var repeatRRULE: String?
    var checklistItems: [TodoManagerChecklistItemRecord]
    var sortOrder: Int64
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case idempotencyKey = "idempotency_key"
        case listID = "list_id"
        case title
        case content
        case status
        case priority
        case tags
        case startAt = "start_at"
        case dueAt = "due_at"
        case timezone
        case isAllDay = "is_all_day"
        case reminders
        case repeatRRULE = "repeat_rrule"
        case checklistItems = "checklist_items"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case deletedAt = "deleted_at"
    }

    var isCompleted: Bool {
        status == "completed"
    }

    var isDeleted: Bool {
        status == "deleted" || deletedAt != nil
    }

    var agentDictionary: [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "list_id": listID,
            "title": title,
            "content": content,
            "status": status,
            "priority": priority,
            "tags": tags,
            "timezone": timezone,
            "is_all_day": isAllDay,
            "reminders": reminders.map(\.agentDictionary),
            "checklist_items": checklistItems.map(\.agentDictionary),
            "sort_order": sortOrder,
            "created_at": TodoManagerDateCodec.string(from: createdAt),
            "updated_at": TodoManagerDateCodec.string(from: updatedAt)
        ]
        if let idempotencyKey {
            payload["idempotency_key"] = idempotencyKey
        }
        if let startAt {
            payload["start_at"] = TodoManagerDateCodec.string(from: startAt)
        }
        if let dueAt {
            payload["due_at"] = TodoManagerDateCodec.string(from: dueAt)
        }
        if let repeatRRULE = repeatRRULE?.nilIfBlank {
            payload["repeat_rrule"] = repeatRRULE
        }
        if let completedAt {
            payload["completed_at"] = TodoManagerDateCodec.string(from: completedAt)
        }
        if let deletedAt {
            payload["deleted_at"] = TodoManagerDateCodec.string(from: deletedAt)
        }
        return payload
    }
}

enum TodoManagerFilter: String, CaseIterable, Identifiable {
    case today
    case upcoming
    case inbox
    case all
    case completed
    case deleted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .inbox: "Inbox"
        case .all: "All"
        case .completed: "Completed"
        case .deleted: "Deleted"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "calendar"
        case .upcoming: "calendar.badge.clock"
        case .inbox: "tray"
        case .all: "checklist"
        case .completed: "checkmark.circle"
        case .deleted: "trash"
        }
    }
}

struct TodoManagerFileDatabase {
    static let defaultListID = "inbox"

    var rootURL: URL?
    var fileManager: FileManager = .default

    func loadLists() -> [TodoManagerListRecord] {
        do {
            let root = try listsRoot()
            let entries = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .compactMap(loadList)
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            return []
        }
    }

    func loadTasks() -> [TodoManagerTaskRecord] {
        do {
            let root = try tasksRoot()
            let entries = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .compactMap(loadTask)
                .sorted { left, right in
                    if left.isCompleted != right.isCompleted {
                        return !left.isCompleted
                    }
                    if left.dueAt != right.dueAt {
                        return (left.dueAt ?? .distantFuture) < (right.dueAt ?? .distantFuture)
                    }
                    return left.createdAt > right.createdAt
                }
        } catch {
            return []
        }
    }

    func ensureDefaultList() throws -> TodoManagerListRecord {
        if let existing = loadLists().first(where: { $0.id == Self.defaultListID }) {
            return existing
        }
        let now = Date()
        let list = TodoManagerListRecord(
            id: Self.defaultListID,
            name: "Inbox",
            color: "#4D8CF5",
            sortOrder: 0,
            createdAt: now,
            updatedAt: now
        )
        try save(list)
        return list
    }

    func save(_ list: TodoManagerListRecord) throws {
        let directory = try listDirectory(list.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(list).write(to: directory.appendingPathComponent("list.json"), options: .atomic)
    }

    func save(_ task: TodoManagerTaskRecord) throws {
        let directory = try taskDirectory(task.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(task).write(to: directory.appendingPathComponent("todo.json"), options: .atomic)
    }

    func removeTask(id: String) throws {
        let directory = try taskDirectory(id)
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        try fileManager.removeItem(at: directory)
    }

    func taskFileURL(_ id: String) throws -> URL {
        try taskDirectory(id).appendingPathComponent("todo.json")
    }

    func appendEvent(action: String, taskID: String, payload: [String: Any]) throws {
        let eventURL = try dataRoot().appendingPathComponent("events.jsonl")
        let event: [String: Any] = [
            "event_id": "todo_event_\(UUID().uuidString.lowercased())",
            "action": action,
            "task_id": taskID,
            "created_at": TodoManagerDateCodec.string(from: Date()),
            "payload": payload
        ]
        let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        if !fileManager.fileExists(atPath: eventURL.path) {
            fileManager.createFile(atPath: eventURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: eventURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
    }

    func dataRoot() throws -> URL {
        if let rootURL {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            return rootURL
        }
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("GeeAgent/gear-data/todo.manager", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func listsRoot() throws -> URL {
        let root = try dataRoot().appendingPathComponent("lists", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func tasksRoot() throws -> URL {
        let root = try dataRoot().appendingPathComponent("tasks", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func listDirectory(_ id: String) throws -> URL {
        try listsRoot().appendingPathComponent(id, isDirectory: true)
    }

    private func taskDirectory(_ id: String) throws -> URL {
        try tasksRoot().appendingPathComponent(id, isDirectory: true)
    }

    private func loadList(_ directory: URL) -> TodoManagerListRecord? {
        decode(TodoManagerListRecord.self, from: directory.appendingPathComponent("list.json"))
    }

    private func loadTask(_ directory: URL) -> TodoManagerTaskRecord? {
        decode(TodoManagerTaskRecord.self, from: directory.appendingPathComponent("todo.json"))
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}

@MainActor
final class TodoManagerGearStore: ObservableObject {
    static let shared = TodoManagerGearStore(
        notificationCenter: TodoManagerNotificationCenterFactory.systemCenterIfAvailable()
    )

    @Published private(set) var lists: [TodoManagerListRecord] = []
    @Published private(set) var tasks: [TodoManagerTaskRecord] = []
    @Published var selectedFilter: TodoManagerFilter = .today
    @Published var selectedTaskID: String?
    @Published var quickAddText = ""
    @Published var searchText = ""
    @Published var isBusy = false
    @Published var statusMessage = "Ready"
    @Published private(set) var notificationState: TodoManagerNotificationState = .unavailable

    private var database: TodoManagerFileDatabase
    private let notificationCenter: UNUserNotificationCenter?

    init(
        database: TodoManagerFileDatabase = TodoManagerFileDatabase(),
        notificationCenter: UNUserNotificationCenter? = nil
    ) {
        self.database = database
        self.notificationCenter = notificationCenter
        loadTodos()
        Task {
            await refreshNotificationStateNow()
        }
    }

    var selectedTask: TodoManagerTaskRecord? {
        tasks.first { $0.id == selectedTaskID }
    }

    var openTaskCount: Int {
        tasks.filter { !$0.isCompleted && !$0.isDeleted }.count
    }

    var visibleTasks: [TodoManagerTaskRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks
            .filter { task in
                filter(task, by: selectedFilter) &&
                (query.isEmpty ||
                 task.title.lowercased().contains(query) ||
                 task.content.lowercased().contains(query) ||
                 task.tags.contains(where: { $0.lowercased().contains(query) }))
            }
            .sorted(by: taskSort)
    }

    func loadTodos() {
        do {
            _ = try database.ensureDefaultList()
            lists = database.loadLists()
            tasks = database.loadTasks()
            if selectedTaskID == nil {
                selectedTaskID = visibleTasks.first?.id
            }
            statusMessage = "\(openTaskCount) open task\(openTaskCount == 1 ? "" : "s")"
        } catch {
            statusMessage = "Todo database failed to load: \(error.localizedDescription)"
        }
    }

    func listName(for listID: String) -> String {
        lists.first { $0.id == listID }?.name ?? "Unknown list"
    }

    func complete(_ task: TodoManagerTaskRecord, isCompleted: Bool) {
        Task {
            _ = await updateAgentTodo(args: [
                "task_id": task.id,
                "completed": isCompleted
            ])
        }
    }

    func delete(_ task: TodoManagerTaskRecord) {
        Task {
            _ = await deleteAgentTodo(args: ["task_id": task.id])
        }
    }

    func refreshNotificationState() {
        Task {
            await refreshNotificationStateNow()
        }
    }

    func refreshNotificationStateNow() async {
        notificationState = await currentNotificationState()
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func addReminder(_ task: TodoManagerTaskRecord, at date: Date) async -> [String: Any] {
        var reminders = reminderPayloads(task.reminders)
        reminders.append([
            "id": Self.newReminderID(),
            "trigger_at": TodoManagerDateCodec.string(from: date)
        ])
        return await applyReminderPayloads(reminders, to: task)
    }

    @discardableResult
    func addRelativeReminder(_ task: TodoManagerTaskRecord, minutesBeforeDue: Int) async -> [String: Any] {
        var reminders = reminderPayloads(task.reminders)
        reminders.append([
            "id": Self.newReminderID(),
            "minutes_before_due": minutesBeforeDue
        ])
        return await applyReminderPayloads(reminders, to: task)
    }

    @discardableResult
    func updateReminder(_ reminderID: String, in task: TodoManagerTaskRecord, at date: Date) async -> [String: Any] {
        let payload = [
            "id": reminderID,
            "trigger_at": TodoManagerDateCodec.string(from: date)
        ]
        return await replaceReminder(reminderID, in: task, with: payload)
    }

    @discardableResult
    func updateRelativeReminder(
        _ reminderID: String,
        in task: TodoManagerTaskRecord,
        minutesBeforeDue: Int
    ) async -> [String: Any] {
        let payload: [String: Any] = [
            "id": reminderID,
            "minutes_before_due": minutesBeforeDue
        ]
        return await replaceReminder(reminderID, in: task, with: payload)
    }

    @discardableResult
    func removeReminder(_ reminderID: String, from task: TodoManagerTaskRecord) async -> [String: Any] {
        guard task.reminders.contains(where: { $0.id == reminderID }) else {
            let payload = failurePayload(
                capabilityID: "todo.update",
                code: "todo.reminder_not_found",
                message: "No reminder matches `\(reminderID)`."
            )
            statusMessage = Self.statusMessage(from: payload)
            return payload
        }
        let reminders = reminderPayloads(task.reminders.filter { $0.id != reminderID })
        return await applyReminderPayloads(reminders, to: task)
    }

    @discardableResult
    func clearReminders(_ task: TodoManagerTaskRecord) async -> [String: Any] {
        await applyReminderPayloads([], to: task)
    }

    private func replaceReminder(
        _ reminderID: String,
        in task: TodoManagerTaskRecord,
        with payload: [String: Any]
    ) async -> [String: Any] {
        guard task.reminders.contains(where: { $0.id == reminderID }) else {
            let payload = failurePayload(
                capabilityID: "todo.update",
                code: "todo.reminder_not_found",
                message: "No reminder matches `\(reminderID)`."
            )
            statusMessage = Self.statusMessage(from: payload)
            return payload
        }
        let reminders = task.reminders.map { reminder in
            reminder.id == reminderID ? payload : reminder.agentDictionary
        }
        return await applyReminderPayloads(reminders, to: task)
    }

    private func applyReminderPayloads(
        _ reminders: [[String: Any]],
        to task: TodoManagerTaskRecord
    ) async -> [String: Any] {
        let payload = await updateAgentTodo(args: [
            "task_id": task.id,
            "reminders": reminders
        ])
        statusMessage = Self.statusMessage(from: payload)
        return payload
    }

    private func reminderPayloads(_ reminders: [TodoManagerReminderRecord]) -> [[String: Any]] {
        reminders.map(\.agentDictionary)
    }

    func revealSelectedTask() {
        guard let selectedTaskID,
              let url = try? database.taskFileURL(selectedTaskID)
        else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func createQuickAddTodo() {
        let text = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        isBusy = true
        Task {
            let parsed = Self.parseQuickAdd(text)
            _ = await createAgentTodo(args: parsed)
            quickAddText = ""
            isBusy = false
        }
    }

    func createAgentTodo(args: [String: Any]) async -> [String: Any] {
        do {
            let title = stringArg(args, "title", "quick_add_text", "quickAddText")
            guard let cleanTitle = title?.nilIfBlank else {
                return failurePayload(
                    capabilityID: "todo.create",
                    code: "gear.args.title",
                    message: "`title` is required."
                )
            }

            let list = try resolveList(args: args)
            let now = Date()
            let idempotencyKey = stringArg(args, "idempotency_key", "idempotencyKey")?.nilIfBlank
            let temporalFields = try normalizedTemporalFields(args: args, title: cleanTitle, now: now)
            let content = stringArg(args, "content") ?? ""
            let priority = try priorityArg(args["priority"])
            let tags = normalizedTags(args["tags"])
            let repeatRRULE = stringArg(args, "repeat_rrule")?.nilIfBlank
            let checklistItems = checklistRecords(args["checklist_items"])
            if let existing = existingTaskForCreate(
                idempotencyKey: idempotencyKey,
                listID: list.id,
                title: cleanTitle,
                content: content,
                priority: priority,
                tags: tags,
                startAt: temporalFields.startAt,
                dueAt: temporalFields.dueAt,
                isAllDay: temporalFields.isAllDay,
                reminders: temporalFields.reminders,
                repeatRRULE: repeatRRULE,
                checklistItems: checklistItems
            ) {
                selectedTaskID = existing.id
                return successPayload(
                    capabilityID: "todo.create",
                    status: "reused",
                    task: existing
                )
            }
            var task = TodoManagerTaskRecord(
                id: "todo_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())",
                idempotencyKey: idempotencyKey,
                listID: list.id,
                title: cleanTitle,
                content: content,
                status: "open",
                priority: priority,
                tags: tags,
                startAt: temporalFields.startAt,
                dueAt: temporalFields.dueAt,
                timezone: temporalFields.timezone,
                isAllDay: temporalFields.isAllDay,
                reminders: temporalFields.reminders,
                repeatRRULE: repeatRRULE,
                checklistItems: checklistItems,
                sortOrder: -Int64((now.timeIntervalSince1970 * 1000).rounded()),
                createdAt: now,
                updatedAt: now,
                completedAt: nil,
                deletedAt: nil
            )
            try database.save(task)
            var warnings = await scheduleNotifications(for: task)
            if task.repeatRRULE != nil {
                warnings.append("repeat_rule_stored_only")
            }
            try database.appendEvent(action: "todo.create", taskID: task.id, payload: task.agentDictionary)
            loadTodos()
            selectedTaskID = task.id
            task = tasks.first { $0.id == task.id } ?? task
            return successPayload(
                capabilityID: "todo.create",
                status: warnings.isEmpty ? "created" : "partial",
                task: task,
                warnings: warnings
            )
        } catch let error as TodoManagerGearError {
            return failurePayload(capabilityID: "todo.create", code: error.code, message: error.message)
        } catch {
            return failurePayload(
                capabilityID: "todo.create",
                code: "todo.create_failed",
                message: error.localizedDescription
            )
        }
    }

    func queryAgentTodos(args: [String: Any]) -> [String: Any] {
        do {
            let records = try queryTasks(args: args)
            let limited = Array(records.prefix(limitArg(args["limit"])))
            return [
                "gear_id": TodoManagerGearDescriptor.gearID,
                "capability_id": "todo.query",
                "status": "succeeded",
                "count": limited.count,
                "total_matching_count": records.count,
                "lists": lists.map(\.agentDictionary),
                "tasks": limited.map(taskPayload)
            ]
        } catch let error as TodoManagerGearError {
            return failurePayload(capabilityID: "todo.query", code: error.code, message: error.message)
        } catch {
            return failurePayload(
                capabilityID: "todo.query",
                code: "todo.query_failed",
                message: error.localizedDescription
            )
        }
    }

    func updateAgentTodo(args: [String: Any]) async -> [String: Any] {
        guard let taskID = stringArg(args, "task_id", "taskId", "id")?.nilIfBlank else {
            return failurePayload(
                capabilityID: "todo.update",
                code: "gear.args.task_id",
                message: "`task_id` is required."
            )
        }

        do {
            guard var task = tasks.first(where: { $0.id == taskID }) ?? database.loadTasks().first(where: { $0.id == taskID }) else {
                return failurePayload(
                    capabilityID: "todo.update",
                    code: "todo.task_not_found",
                    message: "No todo task matches `\(taskID)`."
                )
            }
            let now = Date()
            if let title = stringArg(args, "title") {
                guard let clean = title.nilIfBlank else {
                    return failurePayload(
                        capabilityID: "todo.update",
                        code: "gear.args.title",
                        message: "`title` cannot be blank."
                    )
                }
                task.title = clean
            }
            if let content = stringArg(args, "content") {
                task.content = content
            }
            if args["list_id"] != nil || args["list_name"] != nil {
                task.listID = try resolveList(args: args).id
            }
            if args["tags"] != nil {
                task.tags = normalizedTags(args["tags"])
            }
            if args["priority"] != nil {
                task.priority = try priorityArg(args["priority"])
            }
            if let status = try updateStatusArg(args) {
                applyStatus(status, to: &task, now: now)
            }
            if let completed = boolArg(args, "completed") {
                applyStatus(completed ? "completed" : "open", to: &task, now: now)
            }
            if boolArg(args, "clear_start") == true {
                task.startAt = nil
            } else if args["start_at"] != nil {
                task.startAt = try dateArg(args, "start_at")
            }
            if boolArg(args, "clear_due") == true {
                task.dueAt = nil
            } else if args["due_at"] != nil {
                task.dueAt = try dateArg(args, "due_at")
            }
            if let timezone = stringArg(args, "timezone")?.nilIfBlank {
                task.timezone = timezone
            }
            if let isAllDay = boolArg(args, "is_all_day") {
                task.isAllDay = isAllDay
            }
            if args["reminders"] != nil {
                task.reminders = try reminderRecords(args["reminders"], dueAt: task.dueAt)
            }
            if args["repeat_rrule"] != nil {
                task.repeatRRULE = stringArg(args, "repeat_rrule")?.nilIfBlank
            }
            if args["checklist_items"] != nil {
                task.checklistItems = checklistRecords(args["checklist_items"])
            }
            task.updatedAt = now
            try database.save(task)
            await cancelNotifications(taskID: task.id)
            var warnings = await scheduleNotifications(for: task)
            if task.repeatRRULE != nil {
                warnings.append("repeat_rule_stored_only")
            }
            try database.appendEvent(action: "todo.update", taskID: task.id, payload: task.agentDictionary)
            loadTodos()
            selectedTaskID = task.id
            return successPayload(
                capabilityID: "todo.update",
                status: warnings.isEmpty ? "updated" : "partial",
                task: task,
                warnings: warnings
            )
        } catch let error as TodoManagerGearError {
            return failurePayload(capabilityID: "todo.update", code: error.code, message: error.message)
        } catch {
            return failurePayload(
                capabilityID: "todo.update",
                code: "todo.update_failed",
                message: error.localizedDescription
            )
        }
    }

    func deleteAgentTodo(args: [String: Any]) async -> [String: Any] {
        guard let taskID = stringArg(args, "task_id", "taskId", "id")?.nilIfBlank else {
            return failurePayload(
                capabilityID: "todo.delete",
                code: "gear.args.task_id",
                message: "`task_id` is required."
            )
        }

        do {
            guard var task = tasks.first(where: { $0.id == taskID }) ?? database.loadTasks().first(where: { $0.id == taskID }) else {
                return failurePayload(
                    capabilityID: "todo.delete",
                    code: "todo.task_not_found",
                    message: "No todo task matches `\(taskID)`."
                )
            }
            let now = Date()
            task.status = "deleted"
            task.deletedAt = now
            task.updatedAt = now
            try database.save(task)
            await cancelNotifications(taskID: task.id)
            try database.appendEvent(action: "todo.delete", taskID: task.id, payload: task.agentDictionary)
            loadTodos()
            selectedTaskID = visibleTasks.first?.id
            return successPayload(capabilityID: "todo.delete", status: "deleted", task: task)
        } catch {
            return failurePayload(
                capabilityID: "todo.delete",
                code: "todo.delete_failed",
                message: error.localizedDescription
            )
        }
    }

    private struct TodoManagerTemporalFields {
        var startAt: Date?
        var dueAt: Date?
        var timezone: String
        var isAllDay: Bool
        var reminders: [TodoManagerReminderRecord]
    }

    private struct TodoManagerNaturalTemporalIntent {
        var dueAt: Date?
        var isAllDay: Bool
        var hasClock: Bool
        var hasReminderIntent: Bool
    }

    private func normalizedTemporalFields(
        args: [String: Any],
        title: String,
        now: Date
    ) throws -> TodoManagerTemporalFields {
        let timezone = stringArg(args, "timezone")?.nilIfBlank ?? TimeZone.current.identifier
        var calendar = Calendar.current
        if let parsedTimezone = TimeZone(identifier: timezone) {
            calendar.timeZone = parsedTimezone
        }

        let startAt = try dateArg(args, "start_at")
        var dueAt = try dateArg(args, "due_at")
        var isAllDay = boolArg(args, "is_all_day") ?? false
        let natural = Self.naturalTemporalIntent(in: title, now: now, calendar: calendar)

        if startAt == nil && dueAt == nil, let naturalDueAt = natural.dueAt {
            dueAt = naturalDueAt
            isAllDay = natural.isAllDay
        }

        let reminders: [TodoManagerReminderRecord]
        if args["reminders"] != nil {
            reminders = try reminderRecords(args["reminders"], dueAt: dueAt)
        } else if natural.hasReminderIntent {
            guard let reminderAt = dueAt, natural.hasClock || args["due_at"] != nil else {
                throw TodoManagerGearError(
                    code: "todo.reminder.time_required",
                    message: "Reminder requests require a concrete reminder time."
                )
            }
            reminders = [
                TodoManagerReminderRecord(
                    id: "reminder_0",
                    triggerAt: reminderAt,
                    minutesBeforeDue: nil
                )
            ]
            isAllDay = false
        } else {
            reminders = []
        }

        return TodoManagerTemporalFields(
            startAt: startAt,
            dueAt: dueAt,
            timezone: timezone,
            isAllDay: isAllDay,
            reminders: reminders
        )
    }

    private func existingTaskForCreate(
        idempotencyKey: String?,
        listID: String,
        title: String,
        content: String,
        priority: Int,
        tags: [String],
        startAt: Date?,
        dueAt: Date?,
        isAllDay: Bool,
        reminders: [TodoManagerReminderRecord],
        repeatRRULE: String?,
        checklistItems: [TodoManagerChecklistItemRecord]
    ) -> TodoManagerTaskRecord? {
        let records = database.loadTasks()
        if let idempotencyKey {
            return records.first {
                !$0.isDeleted && $0.idempotencyKey == idempotencyKey
            }
        }

        let recentCutoff = Date().addingTimeInterval(-300)
        return records.first {
            !$0.isDeleted &&
                $0.createdAt >= recentCutoff &&
                $0.listID == listID &&
                $0.title == title &&
                $0.content == content &&
                $0.priority == priority &&
                $0.tags == tags &&
                Self.sameOptionalDate($0.startAt, startAt) &&
                Self.sameOptionalDate($0.dueAt, dueAt) &&
                $0.isAllDay == isAllDay &&
                $0.reminders == reminders &&
                $0.repeatRRULE == repeatRRULE &&
                Self.sameChecklistSignature($0.checklistItems, checklistItems)
        }
    }

    private static func sameOptionalDate(_ left: Date?, _ right: Date?) -> Bool {
        switch (left, right) {
        case (.none, .none):
            return true
        case let (.some(left), .some(right)):
            return abs(left.timeIntervalSince(right)) < 1
        default:
            return false
        }
    }

    private static func sameChecklistSignature(
        _ left: [TodoManagerChecklistItemRecord],
        _ right: [TodoManagerChecklistItemRecord]
    ) -> Bool {
        guard left.count == right.count else {
            return false
        }
        return zip(left, right).allSatisfy { leftItem, rightItem in
            leftItem.title == rightItem.title &&
                leftItem.isCompleted == rightItem.isCompleted &&
                leftItem.sortOrder == rightItem.sortOrder
        }
    }

    private func queryTasks(args: [String: Any]) throws -> [TodoManagerTaskRecord] {
        loadTodos()
        let status = try queryStatusArg(args)
        let listID: String?
        if args["list_id"] != nil || args["list_name"] != nil {
            listID = try resolveList(args: args).id
        } else {
            listID = nil
        }
        let requestedTags = Set(normalizedTags(args["tags"]))
        let priorities = Set(try priorityArrayArg(args["priority"]))
        let dueBucket = try dueBucketArg(args)
        let startDate = try dateArg(args, "start_at")
        let endDate = try dateArg(args, "end_at")
        let search = stringArg(args, "search_text")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return tasks
            .filter { task in
                matchesStatus(task, status: status) &&
                (listID == nil || task.listID == listID) &&
                (requestedTags.isEmpty || requestedTags.isSubset(of: Set(task.tags))) &&
                (priorities.isEmpty || priorities.contains(task.priority)) &&
                matchesDueBucket(task, dueBucket: dueBucket) &&
                matchesRange(task, startDate: startDate, endDate: endDate) &&
                matchesSearch(task, search: search)
            }
            .sorted(by: taskSort)
    }

    private func taskPayload(_ task: TodoManagerTaskRecord) -> [String: Any] {
        var payload = task.agentDictionary
        payload["list_name"] = listName(for: task.listID)
        let schedule = scheduleSummary(for: task)
        payload["date_source"] = schedule.dateSource
        payload["date_state"] = schedule.dateState
        payload["time_state"] = schedule.timeState
        payload["is_overdue"] = schedule.isOverdue
        if let relevantAt = schedule.relevantAt {
            payload["relevant_at"] = TodoManagerDateCodec.string(from: relevantAt)
        }
        if let path = try? database.taskFileURL(task.id).path {
            payload["task_path"] = path
        }
        return payload
    }

    func scheduleSummary(
        for task: TodoManagerTaskRecord,
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> TodoManagerTaskScheduleSummary {
        var calendar = calendar
        if let timezone = TimeZone(identifier: task.timezone) {
            calendar.timeZone = timezone
        }

        let candidate: (source: String, date: Date)?
        if let dueAt = task.dueAt {
            candidate = ("due_at", dueAt)
        } else if let startAt = task.startAt {
            candidate = ("start_at", startAt)
        } else if let reminderAt = reminderDates(for: task).sorted().first {
            candidate = ("reminder", reminderAt)
        } else {
            candidate = nil
        }

        guard let candidate else {
            return TodoManagerTaskScheduleSummary(
                dateSource: "none",
                dateState: "unscheduled",
                timeState: "unscheduled",
                relevantAt: nil,
                isOverdue: false
            )
        }

        let isOverdue = !task.isCompleted && candidate.date < now
        let dateState: String
        if isOverdue {
            dateState = "overdue"
        } else if calendar.isDateInToday(candidate.date) {
            dateState = "today"
        } else {
            dateState = "upcoming"
        }
        let timeState = candidate.source == "due_at" && task.isAllDay ? "all_day" : "timed"

        return TodoManagerTaskScheduleSummary(
            dateSource: candidate.source,
            dateState: dateState,
            timeState: timeState,
            relevantAt: candidate.date,
            isOverdue: isOverdue
        )
    }

    private func successPayload(
        capabilityID: String,
        status: String,
        task: TodoManagerTaskRecord,
        warnings: [String] = []
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "gear_id": TodoManagerGearDescriptor.gearID,
            "capability_id": capabilityID,
            "status": status,
            "task": taskPayload(task)
        ]
        if !warnings.isEmpty {
            payload["warnings"] = warnings
        }
        return payload
    }

    private func failurePayload(capabilityID: String, code: String, message: String) -> [String: Any] {
        [
            "gear_id": TodoManagerGearDescriptor.gearID,
            "capability_id": capabilityID,
            "status": "failed",
            "code": code,
            "error": message
        ]
    }

    private func resolveList(args: [String: Any]) throws -> TodoManagerListRecord {
        _ = try database.ensureDefaultList()
        lists = database.loadLists()
        if let listID = stringArg(args, "list_id")?.nilIfBlank {
            guard let list = lists.first(where: { $0.id == listID }) else {
                throw TodoManagerGearError(
                    code: "todo.list_not_found",
                    message: "No todo list matches id `\(listID)`."
                )
            }
            return list
        }
        if let listName = stringArg(args, "list_name")?.nilIfBlank {
            guard let list = lists.first(where: { $0.name.localizedCaseInsensitiveCompare(listName) == .orderedSame }) else {
                throw TodoManagerGearError(
                    code: "todo.list_not_found",
                    message: "No todo list matches name `\(listName)`."
                )
            }
            return list
        }
        guard let inbox = lists.first(where: { $0.id == TodoManagerFileDatabase.defaultListID }) else {
            return try database.ensureDefaultList()
        }
        return inbox
    }

    private func scheduleNotifications(for task: TodoManagerTaskRecord) async -> [String] {
        let dates = task.reminders.compactMap { $0.triggerDate(for: task) }.filter { $0 > Date() }
        guard !task.reminders.isEmpty, !task.isDeleted, !task.isCompleted else {
            return []
        }
        guard !dates.isEmpty else {
            return ["todo.reminder.no_future_trigger"]
        }
        guard let notificationCenter else {
            notificationState = .unavailable
            return ["todo.reminder.notification_center_unavailable"]
        }

        let status = await notificationAuthorizationStatus()
        notificationState = TodoManagerNotificationState(status: status)
        if status == .notDetermined {
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
                notificationState = granted ? .authorized : .denied
                if !granted {
                    return ["todo.reminder.authorization_required"]
                }
            } catch {
                return ["todo.reminder.authorization_failed:\(error.localizedDescription)"]
            }
        } else if status == .denied {
            return ["todo.reminder.authorization_required"]
        }

        var warnings: [String] = []
        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = task.content.nilIfBlank ?? "Todo reminder"
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(taskID: task.id, index: index),
                content: content,
                trigger: trigger
            )
            do {
                try await notificationCenter.add(request)
            } catch {
                warnings.append("todo.reminder.schedule_failed:\(error.localizedDescription)")
            }
        }
        return warnings
    }

    private func currentNotificationState() async -> TodoManagerNotificationState {
        guard notificationCenter != nil else {
            return .unavailable
        }
        let status = await notificationAuthorizationStatus()
        return TodoManagerNotificationState(status: status)
    }

    private func cancelNotifications(taskID: String) async {
        guard let notificationCenter else {
            return
        }
        let prefix = notificationIdentifierPrefix(taskID: taskID)
        let identifiers = await pendingNotificationRequestIdentifiers()
            .filter { $0.hasPrefix(prefix) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        guard let notificationCenter else {
            return .denied
        }
        return await withCheckedContinuation { continuation in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func pendingNotificationRequestIdentifiers() async -> [String] {
        guard let notificationCenter else {
            return []
        }
        return await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    private func notificationIdentifierPrefix(taskID: String) -> String {
        "todo.manager.\(taskID)."
    }

    private func notificationIdentifier(taskID: String, index: Int) -> String {
        "\(notificationIdentifierPrefix(taskID: taskID))\(index)"
    }

    private static func newReminderID() -> String {
        "reminder_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    private static func parseQuickAdd(_ text: String) -> [String: Any] {
        var titleParts: [String] = []
        var tags: [String] = []
        var priority = 0

        for part in text.split(separator: " ").map(String.init) {
            if part.hasPrefix("#"), let tag = String(part.dropFirst()).nilIfBlank {
                tags.append(tag)
            } else if let parsedPriority = quickAddPriority(part) {
                priority = parsedPriority
            } else {
                titleParts.append(part)
            }
        }

        var payload: [String: Any] = [
            "title": titleParts.joined(separator: " ").nilIfBlank ?? text,
            "priority": priority
        ]
        if !tags.isEmpty {
            payload["tags"] = tags
        }
        return payload
    }

    private static func statusMessage(from payload: [String: Any]) -> String {
        if let warnings = payload["warnings"] as? [String], !warnings.isEmpty {
            return warnings.joined(separator: ", ")
        }
        if let error = payload["error"] as? String {
            return error
        }
        return "Todo updated"
    }

    private static func quickAddPriority(_ token: String) -> Int? {
        switch token.lowercased() {
        case "!1", "p1", "high": 5
        case "!2", "p2", "medium": 3
        case "!3", "p3", "low": 1
        case "!0", "p0": 0
        default: nil
        }
    }

    private static func naturalTemporalIntent(
        in text: String,
        now: Date,
        calendar: Calendar
    ) -> TodoManagerNaturalTemporalIntent {
        let lowercased = text.lowercased()
        let clock = firstClock(in: text)
        let hasReminderIntent = lowercased.contains("remind me") ||
            lowercased.contains("set a reminder") ||
            lowercased.contains("notify me")

        let dayPart = Self.dayPartDefault(in: text, lowercased: lowercased)
        let explicitDateOffset = Self.explicitDateOffset(in: text, now: now, calendar: calendar)
        let weekendOffset = Self.weekendOffset(in: text, now: now, calendar: calendar)
        let nextWeekdayOffset = Self.englishNextWeekdayOffset(in: text, now: now, calendar: calendar)
        let dayOffset: Int?
        if let explicitDateOffset {
            dayOffset = explicitDateOffset
        } else if let dayPartDayOffset = dayPart?.dayOffset {
            dayOffset = dayPartDayOffset
        } else if lowercased.contains("tomorrow") {
            dayOffset = 1
        } else if lowercased.contains("today") ||
                    lowercased.contains("tonight") {
            dayOffset = 0
        } else if let nextWeekdayOffset {
            dayOffset = nextWeekdayOffset
        } else if let weekendOffset {
            dayOffset = weekendOffset
        } else {
            dayOffset = nil
        }

        let inferredClock = hasReminderIntent ? nil : dayPart.map { ($0.hour, $0.minute) }
        let effectiveClock = clock ?? inferredClock

        guard dayOffset != nil || effectiveClock != nil else {
            return TodoManagerNaturalTemporalIntent(
                dueAt: nil,
                isAllDay: false,
                hasClock: false,
                hasReminderIntent: hasReminderIntent
            )
        }

        let resolvedOffset: Int
        if let dayOffset {
            resolvedOffset = dayOffset
        } else if let effectiveClock {
            let today = date(onDayOffset: 0, hour: effectiveClock.hour, minute: effectiveClock.minute, now: now, calendar: calendar)
            resolvedOffset = today <= now ? 1 : 0
        } else {
            resolvedOffset = 0
        }

        let dueAt: Date?
        let isAllDay: Bool
        if let effectiveClock {
            dueAt = date(onDayOffset: resolvedOffset, hour: effectiveClock.hour, minute: effectiveClock.minute, now: now, calendar: calendar)
            isAllDay = false
        } else {
            dueAt = endOfDay(onDayOffset: resolvedOffset, now: now, calendar: calendar)
            isAllDay = true
        }

        return TodoManagerNaturalTemporalIntent(
            dueAt: dueAt,
            isAllDay: isAllDay,
            hasClock: clock != nil,
            hasReminderIntent: hasReminderIntent
        )
    }

    private static func dayPartDefault(
        in text: String,
        lowercased: String
    ) -> (dayOffset: Int?, hour: Int, minute: Int)? {
        let hasMorningMarker = lowercased.contains("morning")
        let hasAfternoonMarker = lowercased.contains("afternoon")
        let hasEveningMarker = lowercased.contains("evening") ||
            lowercased.contains("night") ||
            lowercased.contains("tonight")
        if [hasMorningMarker, hasAfternoonMarker, hasEveningMarker].filter({ $0 }).count > 1 {
            return nil
        }

        if lowercased.contains("tomorrow morning") {
            return (1, 9, 0)
        }
        if lowercased.contains("tomorrow afternoon") {
            return (1, 15, 0)
        }
        if lowercased.contains("tomorrow evening") ||
            lowercased.contains("tomorrow night") {
            return (1, 20, 0)
        }
        if lowercased.contains("today morning") ||
            lowercased.contains("this morning") {
            return (0, 9, 0)
        }
        if lowercased.contains("today afternoon") ||
            lowercased.contains("this afternoon") {
            return (0, 15, 0)
        }
        if lowercased.contains("tonight") ||
            lowercased.contains("today evening") ||
            lowercased.contains("this evening") {
            return (0, 20, 0)
        }
        return nil
    }

    private static func explicitDateOffset(in text: String, now: Date, calendar: Calendar) -> Int? {
        if let match = firstCaptureGroups(
            pattern: "\\b(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})\\b",
            in: text
        ),
            let year = intCapture(match, at: 1),
            let month = intCapture(match, at: 2),
            let day = intCapture(match, at: 3) {
            return dayOffset(year: year, month: month, day: day, now: now, calendar: calendar)
        }

        return nil
    }

    private static func dayOffset(
        year: Int,
        month: Int,
        day: Int,
        now: Date,
        calendar: Calendar
    ) -> Int? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else {
            return nil
        }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else {
            return nil
        }
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTarget = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfTarget).day
    }

    private static func weekendOffset(in text: String, now: Date, calendar: Calendar) -> Int? {
        let lowercased = text.lowercased()
        guard lowercased.contains("this weekend")
        else {
            return nil
        }
        let currentISOWeekday = isoWeekday(for: now, calendar: calendar)
        return currentISOWeekday <= 6 ? 6 - currentISOWeekday : 0
    }

    private static func englishNextWeekdayOffset(in text: String, now: Date, calendar: Calendar) -> Int? {
        guard let match = firstCaptureGroups(
            pattern: "\\bnext\\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b",
            in: text
        ),
            let weekdayText = capture(match, at: 1)?.lowercased(),
            let targetISOWeekday = englishISOWeekday(weekdayText)
        else {
            return nil
        }
        let currentISOWeekday = isoWeekday(for: now, calendar: calendar)
        let offset = (targetISOWeekday - currentISOWeekday + 7) % 7
        return offset == 0 ? 7 : offset
    }

    private static func englishISOWeekday(_ text: String) -> Int? {
        switch text {
        case "monday": 1
        case "tuesday": 2
        case "wednesday": 3
        case "thursday": 4
        case "friday": 5
        case "saturday": 6
        case "sunday": 7
        default: nil
        }
    }

    private static func isoWeekday(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private static func firstClock(in text: String) -> (hour: Int, minute: Int)? {
        if let match = firstCaptureGroups(
            pattern: "\\b(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)\\b",
            in: text
        ) {
            guard var hour = intCapture(match, at: 1) else {
                return nil
            }
            let minute = intCapture(match, at: 2) ?? 0
            let meridiem = capture(match, at: 3)?.lowercased()
            if meridiem == "pm", hour < 12 {
                hour += 12
            } else if meridiem == "am", hour == 12 {
                hour = 0
            }
            guard (0...23).contains(hour), (0...59).contains(minute) else {
                return nil
            }
            return (hour, minute)
        }

        if let match = firstCaptureGroups(pattern: "\\b(\\d{1,2}):(\\d{2})\\b", in: text),
           let hour = intCapture(match, at: 1),
           let minute = intCapture(match, at: 2),
           (0...23).contains(hour),
           (0...59).contains(minute) {
            return (hour, minute)
        }

        return nil
    }

    private static func capture(_ groups: [String?], at index: Int) -> String? {
        guard groups.indices.contains(index) else {
            return nil
        }
        return groups[index]
    }

    private static func intCapture(_ groups: [String?], at index: Int) -> Int? {
        capture(groups, at: index).flatMap(Int.init)
    }

    private static func firstCaptureGroups(pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let matchRange = match.range(at: index)
            guard matchRange.location != NSNotFound,
                  let range = Range(matchRange, in: text)
            else {
                return nil
            }
            return String(text[range])
        }
    }

    private static func date(
        onDayOffset dayOffset: Int,
        hour: Int,
        minute: Int,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static func endOfDay(
        onDayOffset dayOffset: Int,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
    }

    private func filter(_ task: TodoManagerTaskRecord, by filter: TodoManagerFilter) -> Bool {
        switch filter {
        case .today:
            return !task.isDeleted &&
                !task.isCompleted &&
                hasRelevantDateInToday(task)
        case .upcoming:
            return !task.isDeleted && !task.isCompleted && hasUpcomingRelevantDate(task)
        case .inbox:
            return !task.isDeleted && !task.isCompleted && task.listID == TodoManagerFileDatabase.defaultListID
        case .all:
            return !task.isDeleted
        case .completed:
            return !task.isDeleted && task.isCompleted
        case .deleted:
            return task.isDeleted
        }
    }

    private func taskSort(_ left: TodoManagerTaskRecord, _ right: TodoManagerTaskRecord) -> Bool {
        if left.isCompleted != right.isCompleted {
            return !left.isCompleted
        }
        if left.priority != right.priority {
            return left.priority > right.priority
        }
        let leftDate = primaryRelevantDate(for: left)
        let rightDate = primaryRelevantDate(for: right)
        if leftDate != rightDate {
            return (leftDate ?? .distantFuture) < (rightDate ?? .distantFuture)
        }
        return left.createdAt > right.createdAt
    }

    private func matchesStatus(_ task: TodoManagerTaskRecord, status: String) -> Bool {
        switch status {
        case "all":
            return !task.isDeleted
        case "completed":
            return !task.isDeleted && task.isCompleted
        case "deleted":
            return task.isDeleted
        case "open":
            return !task.isDeleted && !task.isCompleted
        default:
            return !task.isDeleted && !task.isCompleted
        }
    }

    private func matchesDueBucket(_ task: TodoManagerTaskRecord, dueBucket: String?) -> Bool {
        guard let dueBucket, dueBucket != "any" else {
            return true
        }
        switch dueBucket {
        case "today":
            return hasRelevantDateInToday(task)
        case "upcoming":
            return hasUpcomingRelevantDate(task)
        case "overdue":
            guard !task.isCompleted, let date = primaryRelevantDate(for: task) else {
                return false
            }
            return date < Date()
        case "none":
            return task.dueAt == nil
        default:
            return true
        }
    }

    private func matchesRange(_ task: TodoManagerTaskRecord, startDate: Date?, endDate: Date?) -> Bool {
        guard startDate != nil || endDate != nil else {
            return true
        }
        guard let candidate = primaryRelevantDate(for: task) else {
            return false
        }
        if let startDate, candidate < startDate {
            return false
        }
        if let endDate, candidate > endDate {
            return false
        }
        return true
    }

    private func matchesSearch(_ task: TodoManagerTaskRecord, search: String?) -> Bool {
        guard let search, !search.isEmpty else {
            return true
        }
        return task.title.lowercased().contains(search) ||
            task.content.lowercased().contains(search) ||
            task.tags.contains { $0.lowercased().contains(search) }
    }

    private func hasRelevantDateInToday(_ task: TodoManagerTaskRecord) -> Bool {
        let calendar = Calendar.current
        return task.dueAt.map(calendar.isDateInToday) == true ||
            task.startAt.map(calendar.isDateInToday) == true ||
            reminderDates(for: task).contains(where: calendar.isDateInToday)
    }

    private func hasUpcomingRelevantDate(_ task: TodoManagerTaskRecord) -> Bool {
        let now = Date()
        return relevantDates(for: task).contains { $0 > now }
    }

    private func primaryRelevantDate(for task: TodoManagerTaskRecord) -> Date? {
        if let dueAt = task.dueAt {
            return dueAt
        }
        if let startAt = task.startAt {
            return startAt
        }
        return reminderDates(for: task).sorted().first
    }

    private func relevantDates(for task: TodoManagerTaskRecord) -> [Date] {
        [task.dueAt, task.startAt].compactMap { $0 } + reminderDates(for: task)
    }

    private func reminderDates(for task: TodoManagerTaskRecord) -> [Date] {
        task.reminders.compactMap { $0.triggerDate(for: task) }
    }

    private func applyStatus(_ status: String, to task: inout TodoManagerTaskRecord, now: Date) {
        switch status {
        case "completed":
            task.status = "completed"
            task.completedAt = task.completedAt ?? now
            task.deletedAt = nil
        case "open":
            task.status = "open"
            task.completedAt = nil
            task.deletedAt = nil
        default:
            break
        }
    }

    private func stringArg(_ args: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = args[key] as? String {
                return value
            }
        }
        return nil
    }

    private func boolArg(_ args: [String: Any], _ key: String) -> Bool? {
        args[key] as? Bool
    }

    private func dateArg(_ args: [String: Any], _ key: String) throws -> Date? {
        guard let value = stringArg(args, key)?.nilIfBlank else {
            return nil
        }
        guard let date = TodoManagerDateCodec.date(from: value) else {
            throw TodoManagerGearError(
                code: "gear.args.\(key)",
                message: "`\(key)` must be an ISO-8601 date string."
            )
        }
        return date
    }

    private func priorityArg(_ value: Any?) throws -> Int {
        guard value != nil else {
            return 0
        }
        let raw = (value as? Int) ?? (value as? NSNumber)?.intValue ?? 0
        guard [0, 1, 3, 5].contains(raw) else {
            throw TodoManagerGearError(
                code: "gear.args.priority",
                message: "`priority` must be one of 0, 1, 3, or 5."
            )
        }
        return raw
    }

    private func normalizedTags(_ value: Any?) -> [String] {
        guard let rawTags = value as? [String] else {
            return []
        }
        return Array(Set(rawTags.compactMap { tag in
            let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            return clean.nilIfBlank?.lowercased()
        })).sorted()
    }

    private func reminderRecords(_ value: Any?, dueAt: Date?) throws -> [TodoManagerReminderRecord] {
        guard value != nil else {
            return []
        }
        guard let values = value as? [Any] else {
            throw TodoManagerGearError(
                code: "gear.args.reminders",
                message: "`reminders` must be an array of reminder strings or objects."
            )
        }
        return try values.enumerated().map { index, value in
            if let trigger = value as? String, let date = TodoManagerDateCodec.date(from: trigger) {
                return TodoManagerReminderRecord(
                    id: "reminder_\(index)",
                    triggerAt: date,
                    minutesBeforeDue: nil
                )
            }
            guard let object = value as? [String: Any] else {
                throw TodoManagerGearError(
                    code: "gear.args.reminders",
                    message: "Each reminder must be an ISO-8601 string or an object with `trigger_at` or `minutes_before_due`."
                )
            }
            let triggerAtString = object["trigger_at"] as? String
            let triggerAt = triggerAtString.flatMap(TodoManagerDateCodec.date)
            if triggerAtString?.nilIfBlank != nil && triggerAt == nil {
                throw TodoManagerGearError(
                    code: "gear.args.reminders",
                    message: "`reminders[].trigger_at` must be an ISO-8601 date string."
                )
            }
            let minutes = (object["minutes_before_due"] as? Int)
                ?? (object["minutes_before_due"] as? NSNumber)?.intValue
            if let minutes, minutes < 0 {
                throw TodoManagerGearError(
                    code: "gear.args.reminders",
                    message: "`reminders[].minutes_before_due` must be zero or greater."
                )
            }
            if minutes != nil && dueAt == nil {
                throw TodoManagerGearError(
                    code: "todo.reminder.due_time_required",
                    message: "`minutes_before_due` reminders require a concrete `due_at` time."
                )
            }
            guard triggerAt != nil || minutes != nil else {
                throw TodoManagerGearError(
                    code: "gear.args.reminders",
                    message: "Each reminder object must include `trigger_at` or `minutes_before_due`."
                )
            }
            return TodoManagerReminderRecord(
                id: (object["id"] as? String)?.nilIfBlank ?? "reminder_\(index)",
                triggerAt: triggerAt,
                minutesBeforeDue: minutes
            )
        }
    }

    private func checklistRecords(_ value: Any?) -> [TodoManagerChecklistItemRecord] {
        guard let values = value as? [Any] else {
            return []
        }
        return values.enumerated().compactMap { index, value in
            let title: String?
            let completed: Bool
            if let string = value as? String {
                title = string
                completed = false
            } else if let object = value as? [String: Any] {
                title = object["title"] as? String
                completed = object["is_completed"] as? Bool ?? object["completed"] as? Bool ?? false
            } else {
                title = nil
                completed = false
            }
            guard let cleanTitle = title?.nilIfBlank else {
                return nil
            }
            return TodoManagerChecklistItemRecord(
                id: "check_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())",
                title: cleanTitle,
                isCompleted: completed,
                sortOrder: Int64(index),
                completedAt: completed ? Date() : nil
            )
        }
    }

    private func priorityArrayArg(_ value: Any?) throws -> [Int] {
        guard value != nil else {
            return []
        }
        if let numbers = value as? [Int] {
            try numbers.forEach(validatePriority)
            return numbers
        }
        if let values = value as? [Any] {
            let numbers = values.compactMap { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue }
            guard numbers.count == values.count else {
                throw TodoManagerGearError(
                    code: "gear.args.priority",
                    message: "`priority` must contain integer values."
                )
            }
            try numbers.forEach(validatePriority)
            return numbers
        }
        throw TodoManagerGearError(
            code: "gear.args.priority",
            message: "`priority` must be an array of 0, 1, 3, or 5."
        )
    }

    private func validatePriority(_ value: Int) throws {
        guard [0, 1, 3, 5].contains(value) else {
            throw TodoManagerGearError(
                code: "gear.args.priority",
                message: "`priority` must be one of 0, 1, 3, or 5."
            )
        }
    }

    private func queryStatusArg(_ args: [String: Any]) throws -> String {
        guard let status = stringArg(args, "status")?.nilIfBlank else {
            return "open"
        }
        guard ["open", "completed", "deleted", "all"].contains(status) else {
            throw TodoManagerGearError(
                code: "gear.args.status",
                message: "`status` must be one of open, completed, deleted, or all."
            )
        }
        return status
    }

    private func updateStatusArg(_ args: [String: Any]) throws -> String? {
        guard let status = stringArg(args, "status")?.nilIfBlank else {
            return nil
        }
        guard ["open", "completed"].contains(status) else {
            throw TodoManagerGearError(
                code: "gear.args.status",
                message: "`status` must be either open or completed."
            )
        }
        return status
    }

    private func dueBucketArg(_ args: [String: Any]) throws -> String? {
        guard let due = stringArg(args, "due")?.nilIfBlank else {
            return nil
        }
        guard ["today", "upcoming", "overdue", "none", "any"].contains(due) else {
            throw TodoManagerGearError(
                code: "gear.args.due",
                message: "`due` must be one of today, upcoming, overdue, none, or any."
            )
        }
        return due
    }

    private func limitArg(_ value: Any?) -> Int {
        let raw = (value as? Int) ?? (value as? NSNumber)?.intValue ?? 50
        return min(max(raw, 1), 200)
    }
}

struct TodoManagerGearError: Error {
    var code: String
    var message: String
}

enum TodoManagerDateCodec {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]

        return fractionalFormatter.date(from: value)
            ?? standardFormatter.date(from: value)
            ?? legacyDateFormatter().date(from: value)
    }

    private static func legacyDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }
}
