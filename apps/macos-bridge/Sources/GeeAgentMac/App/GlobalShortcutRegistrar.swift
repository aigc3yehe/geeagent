import AppKit
import Carbon.HIToolbox

/// Registers the `⌘⇧K` system-wide shortcut using Carbon's public
/// `RegisterEventHotKey` API. `NSEvent.addGlobalMonitorForEvents` only sees
/// global key events after Accessibility permission is granted, which made the
/// shortcut appear to work only while GeeAgent was focused.
final class GlobalShortcutRegistrar: @unchecked Sendable {
    /// The sole shortcut registered in this first pass. Kept as a struct so
    /// later plans can swap it per user settings without rewriting wiring.
    struct Binding {
        var keyCode: UInt16
        var modifierFlags: NSEvent.ModifierFlags

        static let quickInput = Binding(
            keyCode: UInt16(kVK_ANSI_K),
            modifierFlags: [.command, .shift]
        )

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

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastFireAt: TimeInterval = 0
    private let binding: Binding
    private let handler: @MainActor () -> Void

    init(binding: Binding = .quickInput, handler: @escaping @MainActor () -> Void) {
        self.binding = binding
        self.handler = handler
    }

    func register() {
        unregister()
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
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

        let hotKeyID = EventHotKeyID(
            signature: OSType(UInt32(ascii: "GAGT")),
            id: 1
        )
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(binding.keyCode),
            binding.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if hotKeyStatus != noErr {
            NSLog("GeeAgent failed to register global quick-input hotkey: \(hotKeyStatus)")
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
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
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
        guard event.keyCode == binding.keyCode else { return false }
        let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        return event.modifierFlags.intersection(relevantFlags) ==
            binding.modifierFlags.intersection(relevantFlags)
    }
}

private extension UInt32 {
    init(ascii string: String) {
        self = string.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }
}
