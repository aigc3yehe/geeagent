import SwiftUI

/// Sheet shown when a tool invocation returns `NeedsApproval`. The user can
/// either approve (which re-dispatches the invocation with an approval token)
/// or cancel. Keeps the visual language consistent with the rest of the
/// workbench: small radii, WorkSans body, SpaceGrotesk display.
struct ToolApprovalSheet: View {
    let pending: PendingToolApproval
    var onCancel: () -> Void
    var onApprove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider().opacity(0.15)
            detailSummary
            argumentsSection
            Spacer(minLength: 12)
            footerButtons
        }
        .padding(20)
        .frame(minWidth: 420, maxWidth: 520, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .onExitCommand(perform: onCancel)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: blastRadiusSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(blastRadiusColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(blastRadiusColor.opacity(0.16))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Approve local action")
                    .font(.geeDisplaySemibold(15))
                Text(pending.invocation.toolID)
                    .font(.geeBody(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(blastRadiusLabel)
                .font(.geeBodyMedium(11))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(blastRadiusColor.opacity(0.16))
                )
                .foregroundStyle(blastRadiusColor)
        }
    }

    private var detailSummary: some View {
        Text(pending.prompt)
            .font(.geeBody(13))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var argumentsSection: some View {
        if pending.invocation.arguments.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Arguments")
                    .font(.geeBodyMedium(11))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(sortedArgumentKeys, id: \.self) { key in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(key)
                            .font(.geeBodyMedium(12))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 96, alignment: .leading)
                        Text(formattedArgument(pending.invocation.arguments[key]))
                            .font(.geeBody(12))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Spacer()
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.geeBodyMedium(13))
                    .frame(minWidth: 72)
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.bordered)

            Button(action: onApprove) {
                Text("Approve")
                    .font(.geeBodyMedium(13))
                    .frame(minWidth: 72)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(blastRadiusColor)
        }
    }

    private var sortedArgumentKeys: [String] {
        pending.invocation.arguments.keys.sorted()
    }

    private func formattedArgument(_ value: WorkbenchToolArgumentValue?) -> String {
        switch value {
        case .string(let string):
            return string
        case .int(let int):
            return String(int)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .stringArray(let array):
            return array.joined(separator: ", ")
        case .null, .none:
            return "—"
        }
    }

    private var blastRadiusLabel: String {
        switch pending.blastRadius {
        case .safe: return "Safe"
        case .local: return "Local"
        case .external: return "External"
        }
    }

    private var blastRadiusSymbol: String {
        switch pending.blastRadius {
        case .safe: return "checkmark.seal"
        case .local: return "folder.badge.gearshape"
        case .external: return "exclamationmark.triangle"
        }
    }

    private var blastRadiusColor: Color {
        switch pending.blastRadius {
        case .safe: return .green
        case .local: return .blue
        case .external: return .orange
        }
    }
}
