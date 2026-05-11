import AppKit
import ApplicationServices
import Foundation

struct GeeNativeAppControlRequest: Hashable, Sendable {
    var appID: String
    var action: String
    var prompt: String?
    var instruction: String?
}

struct GeeNativeAppControlResult: Hashable, Sendable {
    enum State: String, Hashable, Sendable {
        case succeeded
        case blocked
        case failed
    }

    var state: State
    var code: String
    var message: String
    var appID: String
    var action: String
    var appName: String?

    var status: String {
        state == .succeeded ? "succeeded" : "failed"
    }

    func payload(toolID: String = "gee.nativeApp.control") -> [String: Any] {
        var payload: [String: Any] = [
            "intent": "native_app.control",
            "tool": toolID,
            "status": status,
            "state": state.rawValue,
            "code": code,
            "message": message,
            "app_id": appID,
            "action": action
        ]
        if let appName {
            payload["app_name"] = appName
        }
        if state != .succeeded {
            payload["error"] = message
        }
        return payload
    }
}

@MainActor
protocol GeeNativeAppControlling: AnyObject {
    func control(_ request: GeeNativeAppControlRequest) async -> GeeNativeAppControlResult
}

@MainActor
final class GeeNativeAppController: GeeNativeAppControlling {
    static let shared = GeeNativeAppController()

    private let codexAppURL: URL
    private let pasteboard: NSPasteboard
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(
        codexAppURL: URL = URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true),
        pasteboard: NSPasteboard = .general,
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) {
        self.codexAppURL = codexAppURL
        self.pasteboard = pasteboard
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func control(_ request: GeeNativeAppControlRequest) async -> GeeNativeAppControlResult {
        let appID = Self.normalizedAppID(request.appID)
        let action = Self.normalizedAction(request.action)
        switch (appID, action) {
        case ("codex", "new_chat_and_send"):
            let rawPrompt = request.prompt ?? request.instruction
            return await sendPromptToCodexDesktop(
                rawPrompt,
                appID: appID,
                action: action
            )
        default:
            return .init(
                state: .failed,
                code: "native_app.unsupported_action",
                message: "Native app control failed: `\(request.appID)` does not support action `\(request.action)`.",
                appID: appID.isEmpty ? request.appID : appID,
                action: action.isEmpty ? request.action : action,
                appName: nil
            )
        }
    }

    private func sendPromptToCodexDesktop(
        _ prompt: String?,
        appID: String,
        action: String
    ) async -> GeeNativeAppControlResult {
        let trimmedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedPrompt.isEmpty else {
            return .init(
                state: .blocked,
                code: "native_app.prompt_empty",
                message: "Native app control blocked: Codex Desktop requires a prompt.",
                appID: appID,
                action: action,
                appName: "Codex Desktop"
            )
        }
        let finalPrompt = Self.codexPromptBody(from: trimmedPrompt)
        guard AXIsProcessTrusted() else {
            return .init(
                state: .blocked,
                code: "native_app.accessibility_permission_required",
                message: "Native app control blocked: GeeAgentMac needs macOS Accessibility permission to control Codex Desktop.",
                appID: appID,
                action: action,
                appName: "Codex Desktop"
            )
        }
        guard fileManager.fileExists(atPath: codexAppURL.path) else {
            return .init(
                state: .failed,
                code: "native_app.codex_app_missing",
                message: "Native app control failed: Codex.app was not found at \(codexAppURL.path).",
                appID: appID,
                action: action,
                appName: "Codex Desktop"
            )
        }

        let runningApp: NSRunningApplication
        do {
            runningApp = try await openCodexApp()
        } catch {
            return .init(
                state: .failed,
                code: "native_app.codex_open_failed",
                message: "Native app control failed: \(error.localizedDescription)",
                appID: appID,
                action: action,
                appName: "Codex Desktop"
            )
        }
        runningApp.activate(options: [.activateAllWindows])
        try? await Task.sleep(nanoseconds: 700_000_000)

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        if let failure = await pressNewCodexChat(in: appElement, appID: appID, action: action) {
            return failure
        }
        try? await Task.sleep(nanoseconds: 900_000_000)

        let usedFocusedPaste = await pastePromptIntoCodexComposer(finalPrompt, appElement: appElement)
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        guard await submitCodexPrompt(appElement: appElement, expectedPrompt: finalPrompt) else {
            return .init(
                state: .failed,
                code: usedFocusedPaste ? "native_app.submit_failed_after_focused_paste" : "native_app.submit_failed",
                message: "Native app control failed: the prompt was inserted, but Codex Desktop did not submit after Return and did not expose a usable submit button.",
                appID: appID,
                action: action,
                appName: "Codex Desktop"
            )
        }

        return .init(
            state: .succeeded,
            code: usedFocusedPaste ? "native_app.sent_via_focused_composer" : "native_app.sent",
            message: "Sent the prompt to Codex Desktop. Open Codex Desktop on this Mac to watch progress.",
            appID: appID,
            action: action,
            appName: "Codex Desktop"
        )
    }

    private static func normalizedAppID(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "codex", "codex.desktop", "codex_desktop", "codex desktop":
            return "codex"
        default:
            return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func normalizedAction(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "new_chat_and_send", "new-chat-and-send", "new_chat", "send_prompt", "send":
            return "new_chat_and_send"
        default:
            return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private func openCodexApp() async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return try await withCheckedThrowingContinuation { continuation in
            workspace.openApplication(at: codexAppURL, configuration: configuration) { app, error in
                if let app {
                    continuation.resume(returning: app)
                    return
                }
                continuation.resume(throwing: error ?? CocoaError(.fileNoSuchFile))
            }
        }
    }

    private func findPromptInput(in root: AXUIElement) -> AXUIElement? {
        findElement(in: root, maxDepth: 24) { element in
            let role = attributeString(element, kAXRoleAttribute as CFString)
            guard role == kAXTextAreaRole as String || role == kAXTextFieldRole as String else {
                return false
            }
            let haystack = searchableText(for: element).lowercased()
            if haystack.isEmpty {
                return true
            }
            return ["message", "ask", "prompt", "codex"].contains { haystack.contains($0) }
        }
    }

    private func waitForPromptInput(in root: AXUIElement) async -> AXUIElement? {
        for _ in 0..<30 {
            if let input = findPromptInput(in: root) {
                return input
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return nil
    }

    private func pastePromptIntoCodexComposer(_ prompt: String, appElement: AXUIElement) async -> Bool {
        var usedFocusedPaste = false
        if let input = await waitForPromptInput(in: appElement) {
            _ = AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            try? await Task.sleep(nanoseconds: 150_000_000)
        } else {
            usedFocusedPaste = true
        }
        postKey(0, flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 120_000_000)
        postKey(51)
        try? await Task.sleep(nanoseconds: 120_000_000)
        await pasteTemporaryString(prompt)
        return usedFocusedPaste
    }

    private func submitCodexPrompt(appElement: AXUIElement, expectedPrompt: String) async -> Bool {
        postKey(36)
        try? await Task.sleep(nanoseconds: 900_000_000)
        if promptAppearsSubmitted(appElement: appElement, expectedPrompt: expectedPrompt) {
            return true
        }

        for _ in 0..<20 {
            if let sendButton = bestSubmitButton(in: appElement) {
                if clickCenter(of: sendButton) {
                    return true
                }
                if AXUIElementPerformAction(sendButton, kAXPressAction as CFString) == .success {
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return false
    }

    private func promptAppearsSubmitted(appElement: AXUIElement, expectedPrompt: String) -> Bool {
        guard let input = findPromptInput(in: appElement),
              let value = attributeString(input, kAXValueAttribute as CFString)
        else {
            return !visibleTextContains(appElement, expectedPrompt)
        }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = expectedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty || normalizedValue != normalizedPrompt
    }

    private func visibleTextContains(_ root: AXUIElement, _ text: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return false
        }
        var found = false
        walkElements(in: root, maxDepth: 28) { element in
            if found {
                return
            }
            found = searchableText(for: element).contains(needle)
        }
        return found
    }

    private func pressNewCodexChat(
        in appElement: AXUIElement,
        appID: String,
        action: String
    ) async -> GeeNativeAppControlResult? {
        if let menuBar = attributeElement(appElement, kAXMenuBarAttribute as CFString) {
            let menuOutcome = await waitForEnabledElement(
                in: menuBar,
                maxDepth: 8,
                matching: isNewChatMenuItem
            )
            if let menuItem = menuOutcome.element {
                guard AXUIElementPerformAction(menuItem, kAXPressAction as CFString) == .success else {
                    return .init(
                        state: .failed,
                        code: "native_app.new_chat_menu_press_failed",
                        message: "Native app control failed: File > New Chat could not be selected in Codex Desktop.",
                        appID: appID,
                        action: action,
                        appName: "Codex Desktop"
                    )
                }
                return nil
            }
            if menuOutcome.disabledSeen {
                return .init(
                    state: .failed,
                    code: "native_app.new_chat_menu_disabled",
                    message: "Native app control failed: File > New Chat is visible but disabled in Codex Desktop.",
                    appID: appID,
                    action: action,
                    appName: "Codex Desktop"
                )
            }
        }

        let buttonOutcome = await waitForEnabledElement(in: appElement, maxDepth: 9, matching: isNewChatButton)
        guard let button = buttonOutcome.element else {
            if buttonOutcome.disabledSeen {
                return .init(
                    state: .failed,
                    code: "native_app.new_chat_button_disabled",
                    message: "Native app control failed: New Chat is visible but disabled in Codex Desktop.",
                    appID: appID,
                    action: action,
                    appName: "Codex Desktop"
                )
            }
            return .init(
                state: .failed,
                code: "native_app.new_chat_control_not_found",
                message: "Native app control failed: neither File > New Chat nor a New Chat button was reachable in Codex Desktop.",
                appID: appID,
                action: action,
                appName: "Codex Desktop"
            )
        }
        guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
            return .init(
                state: .failed,
                code: "native_app.new_chat_button_press_failed",
                message: "Native app control failed: New Chat could not be pressed in Codex Desktop.",
                appID: appID,
                action: action,
                appName: "Codex Desktop"
            )
        }
        return nil
    }

    private func isNewChatMenuItem(_ element: AXUIElement) -> Bool {
        guard attributeString(element, kAXRoleAttribute as CFString) == kAXMenuItemRole as String else {
            return false
        }
        return attributeString(element, kAXTitleAttribute as CFString) == "New Chat"
    }

    private func isNewChatButton(_ element: AXUIElement) -> Bool {
        guard attributeString(element, kAXRoleAttribute as CFString) == kAXButtonRole as String else {
            return false
        }
        let haystack = searchableText(for: element).lowercased()
        return ["new chat", "new conversation", "new task"].contains { haystack.contains($0) }
    }

    private func isSendButton(_ element: AXUIElement) -> Bool {
        guard attributeString(element, kAXRoleAttribute as CFString) == kAXButtonRole as String else {
            return false
        }
        let haystack = searchableText(for: element).lowercased()
        return ["send", "submit"].contains { haystack.contains($0) }
    }

    private func bestSubmitButton(in root: AXUIElement) -> AXUIElement? {
        let windowFrame = focusedWindowFrame(in: root)
        var bestElement: AXUIElement?
        var bestScore = -Double.infinity
        walkElements(in: root, maxDepth: 28) { element in
            guard attributeString(element, kAXRoleAttribute as CFString) == kAXButtonRole as String,
                  attributeBool(element, kAXEnabledAttribute as CFString) != false
            else {
                return
            }

            let haystack = searchableText(for: element).lowercased()
            if ["send", "submit"].contains(where: { haystack.contains($0) }) {
                bestElement = element
                bestScore = 10_000
                return
            }

            guard let position = attributeCGPoint(element, kAXPositionAttribute as CFString),
                  let size = attributeCGSize(element, kAXSizeAttribute as CFString),
                  size.width >= 28,
                  size.width <= 96,
                  size.height >= 28,
                  size.height <= 96,
                  abs(size.width - size.height) <= 18
            else {
                return
            }
            let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
            if let windowFrame {
                guard center.x > windowFrame.midX,
                      center.y > windowFrame.minY + windowFrame.height * 0.45,
                      center.x < windowFrame.maxX - 12,
                      center.y < windowFrame.maxY - 12
                else {
                    return
                }
                let normalizedX = (center.x - windowFrame.minX) / max(windowFrame.width, 1)
                let normalizedY = (center.y - windowFrame.minY) / max(windowFrame.height, 1)
                let score = normalizedX * 2 + normalizedY - abs(size.width - size.height) / 100
                if score > bestScore {
                    bestScore = score
                    bestElement = element
                }
            } else if center.x + center.y > bestScore {
                bestScore = center.x + center.y
                bestElement = element
            }
        }
        return bestElement
    }

    private func findElement(
        in root: AXUIElement,
        maxDepth: Int,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            visited += 1
            guard visited < 3_000 else {
                return nil
            }
            if predicate(element) {
                return element
            }
            guard depth > 0 else {
                return nil
            }
            for child in children(of: element) {
                if let found = walk(child, depth: depth - 1) {
                    return found
                }
            }
            return nil
        }
        return walk(root, depth: maxDepth)
    }

    private func walkElements(
        in root: AXUIElement,
        maxDepth: Int,
        visit: (AXUIElement) -> Void
    ) {
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) {
            visited += 1
            guard visited < 5_000 else {
                return
            }
            visit(element)
            guard depth > 0 else {
                return
            }
            for child in children(of: element) {
                walk(child, depth: depth - 1)
            }
        }
        walk(root, depth: maxDepth)
    }

    private func waitForElement(
        in root: AXUIElement,
        maxDepth: Int,
        matching predicate: (AXUIElement) -> Bool
    ) async -> AXUIElement? {
        for _ in 0..<20 {
            if let element = findElement(in: root, maxDepth: maxDepth, matching: predicate) {
                return element
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return nil
    }

    private func findEnabledElement(
        in root: AXUIElement,
        maxDepth: Int,
        matching predicate: (AXUIElement) -> Bool
    ) -> (element: AXUIElement?, disabledSeen: Bool) {
        var visited = 0
        var disabledSeen = false
        func walk(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            visited += 1
            guard visited < 3_000 else {
                return nil
            }
            if predicate(element) {
                if attributeBool(element, kAXEnabledAttribute as CFString) != false {
                    return element
                }
                disabledSeen = true
            }
            guard depth > 0 else {
                return nil
            }
            for child in children(of: element) {
                if let found = walk(child, depth: depth - 1) {
                    return found
                }
            }
            return nil
        }
        return (walk(root, depth: maxDepth), disabledSeen)
    }

    private func waitForEnabledElement(
        in root: AXUIElement,
        maxDepth: Int,
        matching predicate: (AXUIElement) -> Bool
    ) async -> (element: AXUIElement?, disabledSeen: Bool) {
        var disabledSeen = false
        for _ in 0..<20 {
            let outcome = findEnabledElement(in: root, maxDepth: maxDepth, matching: predicate)
            if let element = outcome.element {
                return (element, disabledSeen || outcome.disabledSeen)
            }
            disabledSeen = disabledSeen || outcome.disabledSeen
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return (nil, disabledSeen)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success else {
            return []
        }
        return raw as? [AXUIElement] ?? []
    }

    private func searchableText(for element: AXUIElement) -> String {
        [
            attributeString(element, kAXTitleAttribute as CFString),
            attributeString(element, kAXDescriptionAttribute as CFString),
            attributeString(element, kAXHelpAttribute as CFString),
            attributeString(element, "AXPlaceholderValue" as CFString),
            attributeString(element, kAXValueAttribute as CFString)
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func attributeString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &raw) == .success else {
            return nil
        }
        return raw as? String
    }

    private func attributeElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &raw) == .success,
              let raw,
              CFGetTypeID(raw) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (raw as! AXUIElement)
    }

    private func focusedWindowFrame(in appElement: AXUIElement) -> CGRect? {
        guard let window = attributeElement(appElement, kAXFocusedWindowAttribute as CFString),
              let position = attributeCGPoint(window, kAXPositionAttribute as CFString),
              let size = attributeCGSize(window, kAXSizeAttribute as CFString)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func attributeBool(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &raw) == .success,
              let raw
        else {
            return nil
        }
        if CFGetTypeID(raw) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((raw as! CFBoolean))
        }
        return raw as? Bool
    }

    private func attributeCGPoint(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &raw) == .success,
              let raw,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else {
            return nil
        }
        let value = raw as! AXValue
        guard AXValueGetType(value) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func attributeCGSize(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &raw) == .success,
              let raw,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else {
            return nil
        }
        let value = raw as! AXValue
        guard AXValueGetType(value) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func pasteTemporaryString(_ value: String) async {
        let oldItems = pasteboard.pasteboardItems ?? []
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        postKey(9, flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 350_000_000)
        pasteboard.clearContents()
        if !oldItems.isEmpty {
            pasteboard.writeObjects(oldItems)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    private func clickCenter(of element: AXUIElement) -> Bool {
        guard let position = attributeCGPoint(element, kAXPositionAttribute as CFString),
              let size = attributeCGSize(element, kAXSizeAttribute as CFString)
        else {
            return false
        }
        let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return down != nil && up != nil
    }

    private static func codexPromptBody(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeCodexDelegationWrapper(trimmed),
              let taskRange = trimmed.range(of: "\nTask:", options: [.caseInsensitive])
        else {
            return trimmed
        }

        let afterTaskLabel = trimmed[taskRange.upperBound...]
        let taskBody: String
        if let newline = afterTaskLabel.firstIndex(where: { $0.isNewline }) {
            taskBody = String(afterTaskLabel[afterTaskLabel.index(after: newline)...])
        } else {
            taskBody = String(afterTaskLabel)
        }
        let normalized = taskBody.trimmingCharacters(in: .whitespacesAndNewlines)
        return collapseExactTandemDuplicate(normalized)
    }

    private static func looksLikeCodexDelegationWrapper(_ value: String) -> Bool {
        value.contains("The user delegated the following task")
            || value.contains("Use the browser/Chrome plugin")
            || value.contains("Do not pretend completion")
    }

    private static func collapseExactTandemDuplicate(_ value: String) -> String {
        let characters = Array(value)
        guard characters.count >= 16, characters.count.isMultiple(of: 2) else {
            return value
        }
        let midpoint = characters.count / 2
        let first = String(characters[..<midpoint]).trimmingCharacters(in: .whitespacesAndNewlines)
        let second = String(characters[midpoint...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, first == second else {
            return value
        }
        return first
    }
}
