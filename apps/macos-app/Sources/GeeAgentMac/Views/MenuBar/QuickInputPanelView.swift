import AppKit
import SwiftUI

/// Centered 720-wide floating quick-input. Visual language is intentionally
/// solid rather than glassy: a dark command panel with one strong input row.
///
/// The input itself is an NSTextField wrapper (`FocusAwareTextField`) rather
/// than SwiftUI's `TextField(.plain)` — the SwiftUI variant installs a field
/// editor on focus whose baseline subtly shifts the glyph vertical position,
/// clipping the top pixel row against a fixed-height container. The AppKit
/// field gives exact metric control (bezel-off, focus-ring-off, caret color).
struct QuickInputPanelView: View {
    let store: WorkbenchStore
    var onOpenChat: () -> Void
    var onDismiss: () -> Void

    @State private var isFocused: Bool = false
    @State private var focusRequestToken: Int = 0

    private let outerCornerRadius: CGFloat = 14
    private let fieldRowHeight: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputRow
            routingModeHint
            if let latest = store.quickInputLatestResult {
                latestResultCard(latest)
            } else if !store.canUseQuickInput {
                readOnlyNotice
            }
        }
        .padding(14)
        .frame(width: 720, alignment: .topLeading)
        .background(commandPanelBackground)
        .onAppear {
            focusRequestToken &+= 1
        }
        .onExitCommand(perform: onDismiss)
    }

    // MARK: input row

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    // Soft white so the icon reads as a cue rather than a
                    // solid accent button.
                    Color.white.opacity(store.canUseQuickInput ? 0.78 : 0.34)
                )
                .frame(width: 22, height: 22)

            FocusAwareTextField(
                text: Binding(
                    get: { store.quickInputDraft },
                    set: { next in
                        store.quickInputDraft = next
                        if store.quickInputLatestResult != nil {
                            store.quickInputLatestResult = nil
                        }
                    }
                ),
                placeholder: placeholderText,
                isEnabled: store.canUseQuickInput && !store.isSubmittingQuickInput,
                focusRequestToken: focusRequestToken,
                onFocusChange: { focused in
                    isFocused = focused
                },
                onSubmit: submit
            )
            .frame(height: fieldRowHeight)
            .accessibilityLabel("Quick input prompt")

            if store.isSubmittingQuickInput {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.8))
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(submitEnabled ? 0.92 : 0.32))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!submitEnabled)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: fieldRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isFocused ? QuickInputPalette.fieldFocused : QuickInputPalette.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isFocused ? QuickInputPalette.focusStroke : QuickInputPalette.stroke, lineWidth: 0.9)
                )
                // The background shape must not intercept mouse events, or
                // AppKit will consider the surrounding panel a hit target
                // and prevent the window from being dragged by grabbing it.
                .allowsHitTesting(false)
        )
    }

    private var routingModeHint: some View {
        HStack(spacing: 6) {
            Image(systemName: store.autoConversationRoutingEnabled ? "arrow.triangle.branch" : "text.bubble")
                .font(.system(size: 10, weight: .semibold))
            Text(routingModeText)
                .lineLimit(1)
        }
        .font(.geeBody(11))
        .foregroundStyle(.white.opacity(0.54))
        .padding(.horizontal, 4)
        .accessibilityLabel("Quick input routing")
        .accessibilityValue(routingModeText)
    }

    private var routingModeText: String {
        if store.autoConversationRoutingEnabled {
            return "Auto-route is on. GeeAgent will choose the conversation."
        }

        if let title = store.selectedConversation?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return "Auto-route is off. Sending to \(title)."
        }

        return "Auto-route is off. Sending to the selected conversation."
    }

    private var submitEnabled: Bool {
        store.canUseQuickInput &&
        !store.quickInputDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var placeholderText: String {
        store.canUseQuickInput ? store.quickInputHint : "Preview only."
    }

    private var readOnlyNotice: some View {
        Text(
            store.snapshot.interactionCapabilities.readOnlyReason
                ?? "Open the desktop app to use quick input."
        )
        .font(.geeBody(11))
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 4)
    }

    // MARK: latest-result card

    private func latestResultCard(_ outcome: WorkbenchRequestOutcome) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: outcome.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(outcome.kind.tint)
                .frame(width: 22, height: 22)
                .background(QuickInputPalette.badge, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.kind.title)
                    .font(.geeBodyMedium(10))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(outcome.kind.tint)
                Text(outcome.detail)
                    .font(.geeBody(12))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                if outcome.kind.needsChatContinuation {
                    Button(action: onOpenChat) {
                        Label("Open Chat", systemImage: "arrow.up.right.square")
                            .font(.geeBodyMedium(11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(QuickInputPalette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(QuickInputPalette.stroke, lineWidth: 0.8)
                )
                .allowsHitTesting(false)
        )
    }

    // MARK: solid command panel

    private var commandPanelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                .fill(QuickInputPalette.panel)

            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            QuickInputPalette.panelTop,
                            QuickInputPalette.panel,
                            QuickInputPalette.panelBottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                .stroke(QuickInputPalette.outerStroke, lineWidth: 0.9)

            RoundedRectangle(cornerRadius: max(outerCornerRadius - 1, 0), style: .continuous)
                .inset(by: 1)
                .stroke(QuickInputPalette.innerStroke, lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }

    private func submit() {
        store.submitQuickInput()
    }
}

private enum QuickInputPalette {
    static let panel = Color(red: 0.045, green: 0.05, blue: 0.064)
    static let panelTop = Color(red: 0.062, green: 0.07, blue: 0.088)
    static let panelBottom = Color(red: 0.028, green: 0.031, blue: 0.04)
    static let field = Color(red: 0.072, green: 0.079, blue: 0.098)
    static let fieldFocused = Color(red: 0.085, green: 0.094, blue: 0.116)
    static let card = Color(red: 0.066, green: 0.073, blue: 0.09)
    static let badge = Color(red: 0.105, green: 0.118, blue: 0.145)
    static let stroke = Color(red: 0.20, green: 0.22, blue: 0.26)
    static let focusStroke = Color(red: 0.44, green: 0.55, blue: 0.72)
    static let outerStroke = Color(red: 0.24, green: 0.26, blue: 0.31)
    static let innerStroke = Color(red: 0.10, green: 0.115, blue: 0.14)
}

// MARK: - FocusAwareTextField

/// Thin `NSTextField` wrapper that exists for one reason: SwiftUI's
/// `TextField(.plain)` silently re-lays its baseline when focus installs
/// the field editor (`NSTextView`), and the few-pixel baseline shift clips
/// the glyph top edge against a fixed-height row. The AppKit field gives
/// us a clean bezel-less / focus-ring-less surface with full pixel control
/// and doesn't move on focus. Also customizes the insertion-point color to
/// match the milky-white aesthetic.
private struct FocusAwareTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool
    /// Incremented by the parent to request programmatic focus (e.g. when
    /// the panel appears). The coordinator observes changes, not the raw
    /// value, so repeated focus requests always take effect.
    let focusRequestToken: Int
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }

    func makeNSView(context: Context) -> GeeQuickTextField {
        let field = GeeQuickTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.font = NSFont.geeBody(16)
        field.textColor = NSColor.white.withAlphaComponent(0.92)
        field.insertionPointColor = NSColor.white.withAlphaComponent(0.82)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitAction)
        field.stringValue = text
        field.applyPlaceholder(placeholder)
        field.onFocusChange = { focused in
            context.coordinator.owner.onFocusChange(focused)
        }
        return field
    }

    func updateNSView(_ nsView: GeeQuickTextField, context: Context) {
        context.coordinator.owner = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderAttributedString?.string != placeholder {
            nsView.applyPlaceholder(placeholder)
        }
        nsView.isEditable = isEnabled
        nsView.isSelectable = isEnabled
        nsView.textColor = NSColor.white.withAlphaComponent(isEnabled ? 0.92 : 0.4)

        // Programmatic focus: only act when the token changes, and only
        // once the field is actually in a window (pre-attachment calls are
        // silently ignored by AppKit).
        if context.coordinator.lastFocusToken != focusRequestToken {
            context.coordinator.lastFocusToken = focusRequestToken
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }
                window.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: FocusAwareTextField
        var lastFocusToken: Int = .min

        init(owner: FocusAwareTextField) {
            self.owner = owner
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            owner.text = field.stringValue
        }

        @MainActor @objc func submitAction() {
            owner.onSubmit()
        }

        @MainActor
        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                owner.onSubmit()
                return true
            }
            return false
        }
    }
}

/// `NSTextField` subclass that (1) forwards first-responder transitions so
/// the SwiftUI command row can recolor its stroke, and (2) reapplies the custom
/// insertion-point color on the field editor (which is re-attached per
/// focus cycle, so setting it once in `makeNSView` is not sufficient).
private final class GeeQuickTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    var insertionPointColor: NSColor = .white

    func applyPlaceholder(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.geeBody(16),
            .foregroundColor: NSColor.white.withAlphaComponent(0.42)
        ]
        placeholderAttributedString = NSAttributedString(string: text, attributes: attrs)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            if let editor = currentEditor() as? NSTextView {
                editor.insertionPointColor = insertionPointColor
                editor.drawsBackground = false
                editor.backgroundColor = .clear
            }
            onFocusChange?(true)
        }
        return ok
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}

private extension WorkbenchRequestOutcomeKind {
    var title: String {
        switch self {
        case .chatReply: return "Chat reply"
        case .taskHandoff: return "Task handoff"
        case .firstPartyAction: return "First-party action"
        case .clarifyNeeded: return "Clarify"
        case .needsSetup: return "Needs setup"
        case .error: return "Error"
        }
    }

    var symbol: String {
        switch self {
        case .chatReply: return "text.bubble"
        case .taskHandoff: return "arrow.turn.up.right"
        case .firstPartyAction: return "bolt.fill"
        case .clarifyNeeded: return "questionmark.circle"
        case .needsSetup: return "wrench.and.screwdriver"
        case .error: return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .chatReply: return .green
        case .taskHandoff, .firstPartyAction: return .blue
        case .clarifyNeeded, .needsSetup: return .orange
        case .error: return .red
        }
    }

    var needsChatContinuation: Bool {
        switch self {
        case .taskHandoff, .clarifyNeeded, .needsSetup:
            return true
        case .chatReply, .firstPartyAction, .error:
            return false
        }
    }
}
