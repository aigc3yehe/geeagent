import SwiftUI

struct TasksView: View {
    @Bindable var store: WorkbenchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusRow
                .padding(.horizontal)
                .padding(.top)

            if let task = store.selectedTask {
                taskFocusCard(task: task)
                    .padding(.horizontal)
            }

            List(selection: $store.selectedTaskID) {
                ForEach(WorkbenchTaskStatus.allCases, id: \.self) { status in
                    let tasks = store.tasks(for: status)
                    if !tasks.isEmpty {
                        Section(status.title) {
                            ForEach(tasks) { task in
                                TaskRow(task: task)
                                    .tag(task.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Tasks")
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            ForEach(WorkbenchTaskStatus.allCases, id: \.self) { status in
                WorkbenchMetricTile(
                    title: status.shortTitle,
                    value: "\(store.tasks(for: status).count)",
                    systemImage: status.systemImage
                )
            }
        }
    }

    @ViewBuilder
    private func taskFocusCard(task: WorkbenchTaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.geeDisplaySemibold(22))
                    Text(task.summary)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                WorkbenchStatusBadge(title: task.status.title, systemImage: task.status.systemImage)
            }

            HStack(spacing: 12) {
                Label(task.appName, systemImage: "square.grid.2x2")
                Label(task.ownerLabel, systemImage: "person")
                Text(task.updatedLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            if !store.selectedTaskActions.isEmpty {
                taskActionRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var taskActionRow: some View {
        HStack(spacing: 10) {
            ForEach(store.selectedTaskActions, id: \.self) { action in
                if action == .deny {
                    Button {
                        store.performSelectedTaskAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.isPerformingTaskAction)
                } else {
                    Button {
                        store.performSelectedTaskAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isPerformingTaskAction)
                }
            }
        }
    }
}

private struct TaskRow: View {
    var task: WorkbenchTaskRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.status.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                    Text(task.priorityLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(task.summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label(task.appName, systemImage: "square.grid.2x2")
                    Label(task.ownerLabel, systemImage: "person")
                    Text(task.updatedLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                WorkbenchStatusBadge(title: task.status.title, systemImage: task.status.systemImage)
                Text(task.dueLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
