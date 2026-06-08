import SwiftUI

enum LocalProjectTilePrimaryAction: Equatable {
    case start
    case stop

    init(status: LocalProjectStatus) {
        self = status.state == .running ? .stop : .start
    }

    var label: String {
        switch self {
        case .start: "Start"
        case .stop: "Stop"
        }
    }

    var systemImageName: String {
        switch self {
        case .start: "play.fill"
        case .stop: "stop.fill"
        }
    }
}

struct LocalProjectTileOpenPageAction: Equatable {
    var isVisible: Bool
    var url: URL?

    init(project: LocalProjectRecord, status: LocalProjectStatus) {
        guard status.state == .running, let frontendURL = status.frontendURL ?? project.frontendURL else {
            self.isVisible = false
            self.url = nil
            return
        }
        self.isVisible = true
        self.url = frontendURL
    }
}

struct LocalProjectManagerGearModuleView: View {
    var body: some View {
        LocalProjectManagerGearWindow()
    }
}

struct LocalProjectManagerGearWindow: View {
    @StateObject private var store = LocalProjectManagerGearStore.shared
    @State private var draft = LocalProjectDraft()
    @State private var isEditorPresented = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            if store.projects.isEmpty {
                ContentUnavailableView("No Projects", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(store.projects) { project in
                            LocalProjectTile(
                                project: project,
                                status: store.status(for: project),
                                isBusy: store.isBusy,
                                onStart: {
                                    Task { await store.start(project) }
                                },
                                onStop: {
                                    Task { await store.stop(project) }
                                },
                                onOpenPage: {
                                    store.openFrontend(for: project)
                                },
                                onEdit: {
                                    draft = LocalProjectDraft(record: project)
                                    isEditorPresented = true
                                },
                                onDelete: {
                                    store.delete(project)
                                }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isEditorPresented) {
            LocalProjectEditorSheet(
                draft: $draft,
                onCancel: { isEditorPresented = false },
                onSave: {
                    store.saveDraft(draft)
                    isEditorPresented = false
                    Task { await store.refreshAll() }
                }
            )
        }
        .task {
            await store.refreshAll()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Local Project Manager")
                    .font(.title2.weight(.semibold))
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: store.isBusy ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(store.isBusy)
            .help("Refresh")

            Button {
                draft = LocalProjectDraft()
                isEditorPresented = true
            } label: {
                Label("Add Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct LocalProjectTile: View {
    var project: LocalProjectRecord
    var status: LocalProjectStatus
    var isBusy: Bool
    var onStart: () -> Void
    var onStop: () -> Void
    var onOpenPage: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var isRunning: Bool {
        status.state == .running
    }

    private var primaryAction: LocalProjectTilePrimaryAction {
        LocalProjectTilePrimaryAction(status: status)
    }

    private var openPageAction: LocalProjectTileOpenPageAction {
        LocalProjectTileOpenPageAction(project: project, status: status)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: performPrimaryAction) {
                tileContent
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .help("\(primaryAction.label) \(project.displayName)")
            .accessibilityLabel("\(primaryAction.label) \(project.displayName)")

            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Edit")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Remove")
            }
            .padding(.top, 14)
            .padding(.trailing, 14)

            if openPageAction.isVisible {
                Button(action: onOpenPage) {
                    Image(systemName: "safari")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .help("Open Page")
                .padding(.trailing, 14)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isRunning ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                    Image(systemName: primaryAction.systemImageName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isRunning ? Color.red : Color.accentColor)
                }
                .frame(width: 46, height: 46)

                Spacer()
            }
            .padding(.trailing, 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.displayName)
                    .font(.headline)
                    .lineLimit(2)
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(isRunning ? .green : .secondary)
                    .lineLimit(1)
                Text(status.source.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(project.command.components(separatedBy: .newlines).last?.nilIfBlank ?? project.command)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Label(primaryAction.label, systemImage: primaryAction.systemImageName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isRunning ? Color.red : Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRunning ? Color.red.opacity(0.10) : Color.accentColor.opacity(0.12))
                    )
                    .padding(.trailing, openPageAction.isVisible ? 44 : 0)
            }
        }
        .padding(14)
        .frame(minHeight: 210)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private func performPrimaryAction() {
        switch primaryAction {
        case .start:
            onStart()
        case .stop:
            onStop()
        }
    }
}

private struct LocalProjectEditorSheet: View {
    @Binding var draft: LocalProjectDraft
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.existingID == nil ? "Add Project" : "Edit Project")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Project name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Terminal Command")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.command)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.12))
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Frontend Port")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Optional", text: $draft.frontendPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}
