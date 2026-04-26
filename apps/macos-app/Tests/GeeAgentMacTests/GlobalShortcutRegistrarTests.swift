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
}
