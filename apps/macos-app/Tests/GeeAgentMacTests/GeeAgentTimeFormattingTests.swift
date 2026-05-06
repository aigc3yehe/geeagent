import XCTest
@testable import GeeAgentMac

final class GeeAgentTimeFormattingTests: XCTestCase {
    func testAbsoluteTimestampUsesCurrentLocalTimeZone() {
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(secondsFromGMT: 8 * 3_600)!
        defer { NSTimeZone.default = previousTimeZone }

        XCTAssertEqual(
            GeeAgentTimeFormatting.absoluteTimestampLabel("2026-05-04T01:55:27Z"),
            "2026-05-04 09:55"
        )
    }
}
