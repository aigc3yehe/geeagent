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

    func testRelativeTimestampLabelsUseSelectedLanguage() {
        let date = Date(timeIntervalSinceNow: -3 * 60)

        XCTAssertEqual(
            GeeAgentTimeFormatting.conversationTimestampLabel(date.ISO8601Format(), language: .en),
            "3m ago"
        )
        let zhHansLabel = GeeAgentTimeFormatting.conversationTimestampLabel(
            date.ISO8601Format(),
            language: .zhHans
        )
        let japaneseLabel = GeeAgentTimeFormatting.conversationTimestampLabel(
            date.ISO8601Format(),
            language: .ja
        )

        XCTAssertTrue(zhHansLabel.contains("3"))
        XCTAssertTrue(japaneseLabel.contains("3"))
        XCTAssertNotEqual(zhHansLabel, "3m ago")
        XCTAssertNotEqual(japaneseLabel, "3m ago")
    }
}
