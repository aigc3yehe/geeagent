import ApplicationServices
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

        /// Primary launcher shortcut. Keep this Spotlight-like so quick input
        /// feels like a lightweight command surface instead of an app-specific
        /// hidden chord.
        static let quickInputPrimary = Binding(
            keyCode: UInt16(kVK_Space),
            modifierFlags: [.option]
        )

        /// `⌘⇧K` conflicts with Finder's Network shortcut in Finder, so keep
        /// a quieter Gee mnemonic as a second global option.
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
            .quickInputPrimary,
            .quickInputGlobal,
            .quickInputLegacy,
        ]

        /// Dedicated launcher for audio capture. This intentionally does not
        /// share Quick Input's bindings or panel lifecycle.
        static let audioCapture = Binding(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.control, .option]
        )

        /// A second chord gives audio capture a path around keyboards or
        /// system features that reserve Control-Option combinations.
        static let audioCaptureAlternate = Binding(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.command, .shift]
        )

        static let audioCaptureBindings: [Binding] = [
            .audioCapture,
            .audioCaptureAlternate,
        ]

        func matches(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
            guard keyCode == self.keyCode else { return false }
            let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            return modifierFlags.intersection(relevantFlags) ==
                self.modifierFlags.intersection(relevantFlags)
        }

        static func modifierFlags(from cgFlags: CGEventFlags) -> NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if cgFlags.contains(.maskCommand) {
                flags.insert(.command)
            }
            if cgFlags.contains(.maskShift) {
                flags.insert(.shift)
            }
            if cgFlags.contains(.maskAlternate) {
                flags.insert(.option)
            }
            if cgFlags.contains(.maskControl) {
                flags.insert(.control)
            }
            return flags
        }

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
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastFireAt: TimeInterval = 0
    private let bindings: [Binding]
    private let handler: @MainActor () -> Void
    private let hotKeySignature: OSType
    private let hotKeyIDBase: UInt32
    private let logLabel: String

    init(
        bindings: [Binding] = Binding.quickInputBindings,
        hotKeySignature: OSType = OSType(UInt32(ascii: "GAGT")),
        hotKeyIDBase: UInt32 = 1,
        logLabel: String = "quick-input",
        handler: @escaping @MainActor () -> Void
    ) {
        self.bindings = bindings
        self.hotKeySignature = hotKeySignature
        self.hotKeyIDBase = hotKeyIDBase
        self.logLabel = logLabel
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
            { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let registrar = Unmanaged<GlobalShortcutRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                guard registrar.owns(event: event) else { return OSStatus(eventNotHandledErr) }
                registrar.scheduleFire()
                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &eventHandlerRef
        )
        if handlerStatus != noErr {
            NSLog("GeeAgent failed to install \(logLabel) hotkey handler: \(handlerStatus)")
        }

        for (index, binding) in bindings.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: hotKeySignature,
                id: hotKeyIDBase + UInt32(index)
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
                NSLog("GeeAgent failed to register global \(logLabel) hotkey \(index + 1): \(hotKeyStatus)")
            }
        }

        if hotKeyRefs.isEmpty {
            NSLog("GeeAgent could not register any global \(logLabel) hotkeys. Local focused shortcuts will still be monitored.")
        } else {
            NSLog("GeeAgent registered \(hotKeyRefs.count) global \(logLabel) Carbon hotkey(s).")
        }

        installEventTapFallback()

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
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
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

    private func owns(event: EventRef?) -> Bool {
        guard let event else { return false }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return false }
        let ids = Set((0..<bindings.count).map { hotKeyIDBase + UInt32($0) })
        return hotKeyID.signature == hotKeySignature && ids.contains(hotKeyID.id)
    }

    private func matches(_ event: NSEvent) -> Bool {
        matches(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }

    private func matches(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        bindings.contains { binding in
            binding.matches(keyCode: keyCode, modifierFlags: modifierFlags)
        }
    }

    private func installEventTapFallback() {
        let promptOptions = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        guard AXIsProcessTrustedWithOptions(promptOptions) else {
            NSLog("GeeAgent \(logLabel) global event-tap fallback needs Accessibility permission.")
            return
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let registrar = Unmanaged<GlobalShortcutRegistrar>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    registrar.enableEventTap()
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown else {
                    return Unmanaged.passUnretained(event)
                }
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let modifierFlags = Binding.modifierFlags(from: event.flags)
                guard registrar.matches(keyCode: keyCode, modifierFlags: modifierFlags) else {
                    return Unmanaged.passUnretained(event)
                }
                registrar.scheduleFire()
                return nil
            },
            userInfo: selfPointer
        ) else {
            NSLog("GeeAgent failed to install \(logLabel) global event-tap fallback.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapRunLoopSource = source
        NSLog("GeeAgent installed \(logLabel) global event-tap fallback.")
    }

    private func enableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
}

extension UInt32 {
    init(ascii string: String) {
        self = string.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }
}
