import AppKit
import Carbon.HIToolbox
import XCTest
@testable import GeeAgentMac

final class GlobalShortcutRegistrarTests: XCTestCase {
    func testDefaultQuickInputGlobalShortcutAvoidsFinderCommandShiftK() {
        XCTAssertEqual(
            GlobalShortcutRegistrar.Binding.quickInputGlobal,
            GlobalShortcutRegistrar.Binding(
                keyCode: UInt16(kVK_ANSI_G),
                modifierFlags: [.control, .option]
            )
        )
    }

    func testLegacyCommandShiftKRemainsACompatibilityBinding() {
        XCTAssertTrue(
            GlobalShortcutRegistrar.Binding.quickInputBindings.contains(
                GlobalShortcutRegistrar.Binding(
                    keyCode: UInt16(kVK_ANSI_K),
                    modifierFlags: [.command, .shift]
                )
            )
        )
    }

    func testAudioCaptureShortcutIsDedicatedChord() {
        XCTAssertEqual(
            GlobalShortcutRegistrar.Binding.audioCapture,
            GlobalShortcutRegistrar.Binding(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.control, .option]
            )
        )
        XCTAssertFalse(GlobalShortcutRegistrar.Binding.quickInputBindings.contains(.audioCapture))
    }

    func testAudioCaptureRegistersFallbackChord() {
        XCTAssertEqual(
            GlobalShortcutRegistrar.Binding.audioCaptureAlternate,
            GlobalShortcutRegistrar.Binding(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.command, .shift]
            )
        )
        XCTAssertEqual(
            GlobalShortcutRegistrar.Binding.audioCaptureBindings,
            [.audioCapture, .audioCaptureAlternate]
        )
        XCTAssertTrue(
            GlobalShortcutRegistrar.Binding.audioCaptureBindings.allSatisfy {
                !GlobalShortcutRegistrar.Binding.quickInputBindings.contains($0)
            }
        )
    }

    func testCGEventFlagsMapToShortcutModifierFlags() {
        let flags = GlobalShortcutRegistrar.Binding.modifierFlags(
            from: [.maskControl, .maskAlternate]
        )

        XCTAssertEqual(flags, [.control, .option])
        XCTAssertTrue(
            GlobalShortcutRegistrar.Binding.audioCapture.matches(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: flags
            )
        )
    }
}
