import AppKit
import Carbon.HIToolbox

/// Registers the quick-input system-wide shortcut using Carbon's public
/// `RegisterEventHotKey` API. `NSEvent.addGlobalMonitorForEvents` only sees
/// global key events after Accessibility permission is granted, which made the
/// shortcut appear to work only while GeeAgent was focused.
final class GlobalShortcutRegistrar: @unchecked Sendable {
    /// Kept as a struct so later plans can swap it per user settings without
    /// rewriting wiring.
    struct Binding: Equatable {
        var keyCode: UInt16
        var modifierFlags: NSEvent.ModifierFlags

        /// `⌘⇧K` conflicts with Finder's Network shortcut, and `⌥Space`
        /// conflicts with Finder Quick Look, so the default global invocation
        /// uses a quieter Gee mnemonic.
        static let quickInputGlobal = Binding(
            keyCode: UInt16(kVK_ANSI_G),
            modifierFlags: [.control, .option]
        )

        /// Keep the old shortcut available while GeeAgent is focused and for
        /// environments where another foreground app does not claim it first.
        static let quickInputLegacy = Binding(
            keyCode: UInt16(kVK_ANSI_K),
            modifierFlags: [.command, .shift]
        )

        static let quickInputBindings: [Binding] = [
            .quickInputGlobal,
            .quickInputLegacy,
        ]

        var carbonModifiers: UInt32 {
            var modifiers: UInt32 = 0
            if modifierFlags.contains(.command) {
                modifiers |= UInt32(cmdKey)
            }
            if modifierFlags.contains(.shift) {
                modifiers |= UInt32(shiftKey)
            }
            if modifierFlags.contains(.option) {
                modifiers |= UInt32(optionKey)
            }
            if modifierFlags.contains(.control) {
                modifiers |= UInt32(controlKey)
            }
            return modifiers
        }
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastFireAt: TimeInterval = 0
    private let bindings: [Binding]
    private let handler: @MainActor () -> Void

    init(bindings: [Binding] = Binding.quickInputBindings, handler: @escaping @MainActor () -> Void) {
        self.bindings = bindings
        self.handler = handler
    }

    func register() {
        unregister()
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let eventTarget = GetApplicationEventTarget()
        let handlerStatus = InstallEventHandler(
            eventTarget,
            { _, _, userData in
                guard let userData else { return noErr }
                let registrar = Unmanaged<GlobalShortcutRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                registrar.scheduleFire()
                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &eventHandlerRef
        )
        if handlerStatus != noErr {
            NSLog("GeeAgent failed to install quick-input hotkey handler: \(handlerStatus)")
        }

        for (index, binding) in bindings.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: OSType(UInt32(ascii: "GAGT")),
                id: UInt32(index + 1)
            )
            let hotKeyStatus = RegisterEventHotKey(
                UInt32(binding.keyCode),
                binding.carbonModifiers,
                hotKeyID,
                eventTarget,
                0,
                &ref
            )
            if hotKeyStatus == noErr, let ref {
                hotKeyRefs.append(ref)
            } else {
                NSLog("GeeAgent failed to register global quick-input hotkey \(index + 1): \(hotKeyStatus)")
            }
        }

        // Fallbacks keep the shortcut usable while GeeAgent is focused even if
        // the global hotkey is unavailable, and can also work system-wide when
        // Accessibility permission allows key-event monitoring.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matches(event) else { return event }
            self.scheduleFire()
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matches(event) else { return }
            self.scheduleFire()
        }
    }

    func unregister() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    deinit { unregister() }

    private func scheduleFire() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let now = Date.timeIntervalSinceReferenceDate
            guard now - lastFireAt > 0.2 else { return }
            lastFireAt = now
            handler()
        }
    }

    private func matches(_ event: NSEvent) -> Bool {
        bindings.contains { binding in
            guard event.keyCode == binding.keyCode else { return false }
            let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            return event.modifierFlags.intersection(relevantFlags) ==
                binding.modifierFlags.intersection(relevantFlags)
        }
    }
}

private extension UInt32 {
    init(ascii string: String) {
        self = string.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }
}
