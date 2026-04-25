import SwiftUI

/// Compact 380×420 panel anchored under the status item. Port of the React
/// `MenuBarPanel.tsx` (see `apps/desktop-shell/src/surfaces/MenuBarPanel.tsx`)
/// using native SwiftUI primitives and the design-v2 token set.
struct MenuBarPanelView: View {
    let store: WorkbenchStore
    var onOpenQuickInput: () -> Void
    var onOpenMainWindow: (_ section: WorkbenchSection) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            primaryCopyBlock
            actionCluster
            Divider().opacity(0.15)
            runtimeBlock
            Divider().opacity(0.15)
            recentTasks
        }
        .padding(16)
        .frame(width: 380, height: 420, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            statePill
            Spacer()
            Button(action: primaryActionHandler) {
                Text(primaryActionLabel)
                    .font(.geeBodyMedium(12))
                    .frame(minWidth: 84)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(statePillColor)
            .controlSize(.small)
        }
    }

    private var statePill: some View {
        Text(store.menuBarState.pillLabel)
            .font(.geeBodyMedium(10))
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(statePillColor.opacity(0.18))
            )
            .foregroundStyle(statePillColor)
    }

    private var primaryCopyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(copy.title)
                .font(.geeDisplaySemibold(15))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(copy.detail)
                .font(.geeBody(12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: action cluster

    private var actionCluster: some View {
        HStack(spacing: 6) {
            menuChip("Quick Input", symbol: "bolt.fill", action: onOpenQuickInput)
            menuChip("Chat", symbol: "bubble.left", action: {
                onOpenMainWindow(.chat)
            })
            menuChip("Logs", symbol: "doc.text.magnifyingglass", action: {
                onOpenMainWindow(.logs)
            })
            if reviewCount > 0 {
                menuChip("Review", symbol: "checkmark.shield", action: {
                    onOpenMainWindow(.logs)
                })
            }
            if needsSetup {
                menuChip("Setup", symbol: "wrench.and.screwdriver", action: {
                    onOpenMainWindow(.settings)
                })
            }
        }
    }

    private func menuChip(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title).font(.geeBodyMedium(11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: runtime

    private var runtimeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(runtimeLabel)
                .font(.geeBodyMedium(12))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(store.runtimeStatus.detail)
                .font(.geeBody(11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: {
                onOpenMainWindow(.settings)
            }) {
                Text(store.runtimeStatus.state == .live ? "Manage Runtime" : "Open Workspace Setup")
                    .font(.geeBodyMedium(11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: recent tasks

    private var recentTasks: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent Logs")
                    .font(.geeBodyMedium(11))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Logs") {
                    onOpenMainWindow(.logs)
                }
                .font(.geeBodyMedium(10))
                .buttonStyle(.link)
            }
            ForEach(store.tasks.prefix(3)) { task in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title)
                            .font(.geeBodyMedium(12))
                            .lineLimit(1)
                        Text(task.summary)
                            .font(.geeBody(10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(statusLabel(for: task.status))
                        .font(.geeBodyMedium(10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(statusTint(for: task.status).opacity(0.18))
                        )
                        .foregroundStyle(statusTint(for: task.status))
                }
            }
        }
    }

    // MARK: derived values

    private var copy: (title: String, detail: String) {
        switch store.menuBarState {
        case .waitingReview:
            let task = store.tasks.first { $0.status == .needsApproval }
            return (
                task?.title ?? "Approval waiting",
                task?.summary ?? "A sensitive action is paused for your review."
            )
        case .waitingInput:
            let task = store.tasks.first { $0.status == .blocked }
            return (
                task?.title ?? "Input needed",
                task?.summary ?? "Something is ready, but it needs your next decision."
            )
        case .degraded:
            if needsSetup && store.tasks.first(where: { $0.status == .failed }) == nil {
                return (
                    "Setup needed",
                    "Live chat is not ready yet. Open setup to finish provider configuration."
                )
            }
            let task = store.tasks.first { $0.status == .failed }
            return (
                task?.title ?? "Needs attention",
                task?.summary ?? "Open the task queue to recover the blocked work."
            )
        case .working:
            let task = store.tasks.first { $0.status == .running || $0.status == .queued }
            return (
                task?.title ?? "Work is active",
                task?.summary ?? "GeeAgent is still moving through the current queue."
            )
        case .idle:
            return ("Ready for the next request", store.quickReply)
        }
    }

    private var primaryActionLabel: String {
        switch store.menuBarState {
        case .waitingReview: return "Open Review"
        case _ where needsSetup: return "Open Setup"
        case .idle: return "Open Chat"
        default: return "Open Logs"
        }
    }

    private func primaryActionHandler() {
        switch store.menuBarState {
        case .waitingReview:
            onOpenMainWindow(.logs)
        case _ where needsSetup:
            onOpenMainWindow(.settings)
        case .idle:
            onOpenMainWindow(.chat)
        default:
            onOpenMainWindow(.logs)
        }
    }

    private var runtimeLabel: String {
        switch store.runtimeStatus.state {
        case .live:
            let provider = store.runtimeStatus.providerName ?? "provider"
            return "Live chat via \(provider)"
        case .needsSetup: return "Chat setup needed"
        case .degraded: return "Chat degraded"
        case .unavailable: return "Chat unavailable"
        }
    }

    private var needsSetup: Bool { store.runtimeStatus.state != .live }
    private var reviewCount: Int { store.tasks.filter { $0.status == .needsApproval }.count }

    private var statePillColor: Color {
        switch store.menuBarState {
        case .idle: return .green
        case .working: return .blue
        case .waitingReview: return .orange
        case .waitingInput: return .orange
        case .degraded: return .red
        }
    }

    private func statusLabel(for status: WorkbenchTaskStatus) -> String {
        switch status {
        case .needsApproval: return "review"
        case .running: return "running"
        case .blocked: return "blocked"
        case .queued: return "queued"
        case .completed: return "done"
        case .failed: return "failed"
        }
    }

    private func statusTint(for status: WorkbenchTaskStatus) -> Color {
        switch status {
        case .needsApproval, .blocked: return .orange
        case .running, .queued: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}
