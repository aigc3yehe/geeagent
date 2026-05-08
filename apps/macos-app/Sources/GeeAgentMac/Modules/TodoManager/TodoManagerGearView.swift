import SwiftUI

struct TodoManagerGearModuleView: View {
    var body: some View {
        TodoManagerGearWindow()
    }
}

private enum TodoManagerReminderDraftMode: String, CaseIterable, Identifiable {
    case absolute
    case relative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .absolute: "At Time"
        case .relative: "Before Due"
        }
    }
}

struct TodoManagerGearWindow: View {
    @StateObject private var model = TodoManagerGearStore.shared
    @State private var reminderDraft = Date().addingTimeInterval(3600)
    @State private var reminderDraftMode: TodoManagerReminderDraftMode = .absolute
    @State private var relativeReminderMinutes = 30
    @State private var editingReminderID: String?

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                sidebar
                    .frame(width: min(max(proxy.size.width * 0.24, 260), 340))

                Divider()

                taskList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                inspector
                    .frame(width: min(max(proxy.size.width * 0.28, 300), 420))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear { model.loadTodos() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Todo Manager", systemImage: "checklist")
                    .font(.title2.weight(.semibold))
                Text("\(model.openTaskCount) open task\(model.openTaskCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Quick add", text: $model.quickAddText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.createQuickAddTodo() }

                Button {
                    model.createQuickAddTodo()
                } label: {
                    Label("Add Todo", systemImage: model.isBusy ? "arrow.triangle.2.circlepath" : "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.quickAddText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Smart Lists")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(TodoManagerFilter.allCases) { filter in
                    TodoManagerSidebarButton(
                        title: filter.title,
                        systemImage: filter.systemImage,
                        isSelected: model.selectedFilter == filter
                    ) {
                        model.selectedFilter = filter
                        model.selectedTaskID = model.visibleTasks.first?.id
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Lists")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(model.lists) { list in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: list.color) ?? .accentColor)
                            .frame(width: 8, height: 8)
                        Text(list.name)
                            .lineLimit(1)
                        Spacer()
                        Text("\(model.visibleTasks.filter { $0.listID == list.id }.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                }
            }

            Spacer()

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.regularMaterial)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedFilter.title)
                        .font(.title2.weight(.semibold))
                    Text("\(model.visibleTasks.count) visible")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TextField("Search", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                Button {
                    model.loadTodos()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(20)

            Divider()

            if model.visibleTasks.isEmpty {
                ContentUnavailableView(
                    "No Todos",
                    systemImage: "checklist.unchecked",
                    description: Text("Add a task or change the current filter.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visibleTasks) { task in
                            TodoManagerTaskRow(
                                task: task,
                                listName: model.listName(for: task.listID),
                                scheduleSummary: model.scheduleSummary(for: task),
                                isSelected: model.selectedTaskID == task.id,
                                onSelect: {
                                    model.selectedTaskID = task.id
                                },
                                onToggle: {
                                    model.complete(task, isCompleted: !task.isCompleted)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Inspector")
                    .font(.headline)
                Spacer()
                Button {
                    model.revealSelectedTask()
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedTask == nil)
                .help("Reveal record")
            }

            if let task = model.selectedTask {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TodoManagerInspectorHeader(task: task)

                        TodoManagerInspectorSection(title: "Details") {
                            let schedule = model.scheduleSummary(for: task)
                            TodoManagerKeyValue(label: "List", value: model.listName(for: task.listID))
                            TodoManagerKeyValue(label: "Status", value: task.status.capitalized)
                            TodoManagerKeyValue(label: "Schedule", value: scheduleInspectorLabel(schedule))
                            TodoManagerKeyValue(label: "Priority", value: TodoManagerPriority.label(task.priority))
                            if let dueAt = task.dueAt {
                                TodoManagerKeyValue(label: "Due", value: dueAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            if let startAt = task.startAt {
                                TodoManagerKeyValue(label: "Start", value: startAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            if let repeatRRULE = task.repeatRRULE?.nilIfBlank {
                                TodoManagerKeyValue(label: "Repeat", value: repeatRRULE)
                            }
                        }

                        TodoManagerInspectorSection(title: "Reminders") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: model.notificationState.systemImage)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.notificationState.title)
                                            .font(.subheadline.weight(.medium))
                                        Text(model.notificationState.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Button {
                                        model.refreshNotificationState()
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Refresh notification state")
                                    if model.notificationState.showsSettingsAction {
                                        Button {
                                            model.openNotificationSettings()
                                        } label: {
                                            Image(systemName: "gearshape")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Open notification settings")
                                    }
                                }

                                if task.reminders.isEmpty {
                                    TodoManagerKeyValue(label: "Scheduled", value: "None")
                                } else {
                                    ForEach(task.reminders) { reminder in
                                        HStack(spacing: 8) {
                                            Label(reminderLabel(reminder, task: task), systemImage: "bell")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                            Spacer()
                                            Button {
                                                beginEditing(reminder)
                                            } label: {
                                                Image(systemName: "pencil")
                                            }
                                            .buttonStyle(.borderless)
                                            .help("Edit reminder")
                                            Button {
                                                removeReminder(reminder, from: task)
                                            } label: {
                                                Image(systemName: "minus.circle")
                                            }
                                            .buttonStyle(.borderless)
                                            .help("Remove reminder")
                                        }
                                    }
                                }

                                Picker("Reminder kind", selection: $reminderDraftMode) {
                                    ForEach(TodoManagerReminderDraftMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)

                                switch reminderDraftMode {
                                case .absolute:
                                    DatePicker(
                                        "Reminder",
                                        selection: $reminderDraft,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .datePickerStyle(.compact)
                                case .relative:
                                    Stepper(
                                        "\(relativeReminderMinutes)m before due",
                                        value: $relativeReminderMinutes,
                                        in: 0...10_080,
                                        step: 5
                                    )
                                    .disabled(task.dueAt == nil)
                                    if task.dueAt == nil {
                                        Text("Relative reminders require a due date.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                HStack(spacing: 8) {
                                    Button {
                                        applyReminderDraft(to: task)
                                    } label: {
                                        Label(editingReminderID == nil ? "Add" : "Update", systemImage: editingReminderID == nil ? "plus.circle" : "checkmark.circle")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(reminderDraftMode == .relative && task.dueAt == nil)

                                    Button {
                                        resetReminderDraft()
                                    } label: {
                                        Label("Cancel", systemImage: "xmark.circle")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(editingReminderID == nil)

                                    Button {
                                        clearReminders(task)
                                    } label: {
                                        Label("Clear All", systemImage: "bell.slash")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(task.reminders.isEmpty)
                                }
                            }
                        }

                        if !task.tags.isEmpty {
                            TodoManagerInspectorSection(title: "Tags") {
                                HStack(spacing: 6) {
                                    ForEach(task.tags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 8)
                                            .frame(height: 24)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                            }
                        }

                        if !task.content.isEmpty {
                            TodoManagerInspectorSection(title: "Notes") {
                                Text(task.content)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !task.checklistItems.isEmpty {
                            TodoManagerInspectorSection(title: "Checklist") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(task.checklistItems) { item in
                                        Label(item.title, systemImage: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                model.complete(task, isCompleted: !task.isCompleted)
                            } label: {
                                Label(task.isCompleted ? "Reopen" : "Complete", systemImage: task.isCompleted ? "arrow.uturn.left.circle" : "checkmark.circle")
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                model.delete(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .disabled(task.isDeleted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                ContentUnavailableView(
                    "Select a Todo",
                    systemImage: "sidebar.right",
                    description: Text("Task details appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.thinMaterial)
    }

    private func reminderLabel(_ reminder: TodoManagerReminderRecord, task: TodoManagerTaskRecord) -> String {
        if let triggerDate = reminder.triggerDate(for: task) {
            return triggerDate.formatted(date: .abbreviated, time: .shortened)
        }
        if let minutesBeforeDue = reminder.minutesBeforeDue {
            return "\(minutesBeforeDue)m before due"
        }
        return "Unscheduled"
    }

    private func scheduleInspectorLabel(_ summary: TodoManagerTaskScheduleSummary) -> String {
        let source: String
        switch summary.dateSource {
        case "due_at": source = "Due"
        case "start_at": source = "Start"
        case "reminder": source = "Reminder"
        default: source = "No date"
        }
        guard let relevantAt = summary.relevantAt else {
            return source
        }
        let state = summary.dateState == "overdue" ? "Overdue" : source
        let time = summary.timeState == "all_day"
            ? relevantAt.formatted(date: .abbreviated, time: .omitted)
            : relevantAt.formatted(date: .abbreviated, time: .shortened)
        return "\(state) - \(time)"
    }

    private func beginEditing(_ reminder: TodoManagerReminderRecord) {
        editingReminderID = reminder.id
        if let triggerAt = reminder.triggerAt {
            reminderDraftMode = .absolute
            reminderDraft = triggerAt
        } else if let minutesBeforeDue = reminder.minutesBeforeDue {
            reminderDraftMode = .relative
            relativeReminderMinutes = minutesBeforeDue
        }
    }

    private func applyReminderDraft(to task: TodoManagerTaskRecord) {
        Task {
            let payload: [String: Any]
            if let editingReminderID {
                switch reminderDraftMode {
                case .absolute:
                    payload = await model.updateReminder(editingReminderID, in: task, at: reminderDraft)
                case .relative:
                    payload = await model.updateRelativeReminder(
                        editingReminderID,
                        in: task,
                        minutesBeforeDue: relativeReminderMinutes
                    )
                }
            } else {
                switch reminderDraftMode {
                case .absolute:
                    payload = await model.addReminder(task, at: reminderDraft)
                case .relative:
                    payload = await model.addRelativeReminder(task, minutesBeforeDue: relativeReminderMinutes)
                }
            }
            if payload["status"] as? String != "failed" {
                resetReminderDraft()
            }
        }
    }

    private func removeReminder(_ reminder: TodoManagerReminderRecord, from task: TodoManagerTaskRecord) {
        Task {
            let payload = await model.removeReminder(reminder.id, from: task)
            if payload["status"] as? String != "failed", editingReminderID == reminder.id {
                resetReminderDraft()
            }
        }
    }

    private func clearReminders(_ task: TodoManagerTaskRecord) {
        Task {
            let payload = await model.clearReminders(task)
            if payload["status"] as? String != "failed" {
                resetReminderDraft()
            }
        }
    }

    private func resetReminderDraft() {
        editingReminderID = nil
        reminderDraftMode = .absolute
        reminderDraft = Date().addingTimeInterval(3600)
    }
}

private struct TodoManagerSidebarButton: View {
    var title: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer()
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct TodoManagerTaskRow: View {
    var task: TodoManagerTaskRecord
    var listName: String
    var scheduleSummary: TodoManagerTaskScheduleSummary
    var isSelected: Bool
    var onSelect: () -> Void
    var onToggle: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(task.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(task.isCompleted ? .secondary : .primary)
                            .strikethrough(task.isCompleted)
                            .lineLimit(2)
                        if task.priority > 0 {
                            Image(systemName: "flag.fill")
                                .font(.caption)
                                .foregroundStyle(TodoManagerPriority.color(task.priority))
                        }
                    }

                    HStack(spacing: 8) {
                        Text(listName)
                        TodoManagerScheduleChip(summary: scheduleSummary)
                        if !task.reminders.isEmpty {
                            Image(systemName: "bell")
                        }
                        if !task.tags.isEmpty {
                            Text(task.tags.prefix(2).map { "#\($0)" }.joined(separator: " "))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider()
            .padding(.leading, 54)
    }
}

private struct TodoManagerScheduleChip: View {
    var summary: TodoManagerTaskScheduleSummary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(foreground.opacity(0.10), in: Capsule())
            .help(help)
    }

    private var title: String {
        guard let relevantAt = summary.relevantAt else {
            return "No date"
        }
        if summary.dateState == "overdue" {
            return "Overdue"
        }
        if summary.dateState == "today" {
            return summary.timeState == "all_day"
                ? "Today"
                : relevantAt.formatted(date: .omitted, time: .shortened)
        }
        return summary.timeState == "all_day"
            ? relevantAt.formatted(date: .abbreviated, time: .omitted)
            : relevantAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var systemImage: String {
        switch summary.dateSource {
        case "due_at": "calendar"
        case "start_at": "play.circle"
        case "reminder": "bell"
        default: "calendar.badge.exclamationmark"
        }
    }

    private var foreground: Color {
        switch summary.dateState {
        case "overdue": .red
        case "today": .accentColor
        case "upcoming": Color(nsColor: .secondaryLabelColor)
        default: Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var help: String {
        switch summary.dateSource {
        case "due_at": "Due date"
        case "start_at": "Start date"
        case "reminder": "Reminder date"
        default: "Unscheduled"
        }
    }
}

private struct TodoManagerInspectorHeader: View {
    var task: TodoManagerTaskRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(4)
            }
            Text("Created \(task.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TodoManagerInspectorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TodoManagerKeyValue: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

private enum TodoManagerPriority {
    static func label(_ value: Int) -> String {
        switch value {
        case 5: "High"
        case 3: "Medium"
        case 1: "Low"
        default: "None"
        }
    }

    static func color(_ value: Int) -> Color {
        switch value {
        case 5: .red
        case 3: .orange
        case 1: .blue
        default: .secondary
        }
    }
}

private extension Color {
    init?(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard raw.count == 6, let value = Int(raw, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
