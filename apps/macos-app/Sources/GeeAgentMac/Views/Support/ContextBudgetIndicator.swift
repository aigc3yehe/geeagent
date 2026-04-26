import SwiftUI

struct ContextBudgetIndicator: View {
    let budget: ContextBudgetRecord
    var compact: Bool = true

    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                ring
                if !compact {
                    Text(budget.percentageLabel)
                        .font(.geeBodyMedium(11))
                        .foregroundStyle(labelTint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Context: \(budget.tokenLabel) · \(budget.summaryState.title)")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            popoverContent
        }
        .accessibilityLabel("Context window")
        .accessibilityValue("\(budget.tokenLabel), \(budget.summaryState.title)")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(ringTint.opacity(0.24), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(budget.usageRatio, 0), 1))
                .stroke(ringTint.opacity(0.86), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(ringTint.opacity(0.66))
                .frame(width: 4, height: 4)
        }
        .frame(width: 18, height: 18)
        .overlay(alignment: .bottomTrailing) {
            if budget.summaryState == .failed {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 9, height: 9)
                    .background(.red, in: Circle())
                    .offset(x: 3, y: 3)
            }
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Context Window")
                    .font(.geeDisplaySemibold(14))
                Spacer()
                Text(budget.percentageLabel)
                    .font(.geeBodyMedium(12))
                    .foregroundStyle(labelTint)
            }

            VStack(alignment: .leading, spacing: 5) {
                metricRow("Used", budget.tokenLabel)
                metricRow("Reserved output", "\(budget.reservedOutputTokens / 1_000)k")
                metricRow("State", budget.summaryState.title)
                if budget.compactedMessagesCount > 0 {
                    metricRow("Compacted", "\(budget.compactedMessagesCount) older messages")
                }
            }

            Text("GeeAgent keeps the full transcript locally. When the 256k window nears capacity, older turns are summarized while recent task context stays verbatim.")
                .font(.geeBody(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 300)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.geeBody(11))
    }

    private var ringTint: Color {
        Color.white.opacity(budget.usageRatio >= 0.95 ? 0.82 : 0.58)
    }

    private var labelTint: Color {
        budget.usageRatio >= 0.95 ? Color.white.opacity(0.86) : Color.secondary
    }
}
