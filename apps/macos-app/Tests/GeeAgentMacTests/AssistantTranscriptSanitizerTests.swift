import XCTest
@testable import GeeAgentMac

final class AssistantTranscriptSanitizerTests: XCTestCase {
    func testDropsBareHostActionDirective() {
        let content = #"<gee-host-actions>{"actions":[{"tool_id":"gee.gear.listCapabilities","arguments":{"detail":"summary"}}]}</gee-host-actions>"#

        XCTAssertEqual(AssistantTranscriptSanitizer.sanitize(content), "")
    }

    func testRemovesEmbeddedHostActionDirectiveWithoutDroppingVisibleReply() {
        let content = """
        Preparing to call a tool.
        <gee-host-actions>{"actions":[{"tool_id":"gee.gear.invoke","arguments":{"gear_id":"bookmark.vault"}}]}</gee-host-actions>
        Continued processing.
        """

        let sanitized = AssistantTranscriptSanitizer.sanitize(content)

        XCTAssertFalse(sanitized.contains("gee-host-actions"))
        XCTAssertFalse(sanitized.contains("gee.gear.invoke"))
        XCTAssertTrue(sanitized.contains("Preparing to call a tool."))
        XCTAssertTrue(sanitized.contains("Continued processing."))
    }

    func testRemovesEmptySourcesFooterAfterControlFrameCleanup() {
        let content = """
        Saved.
        ```gee-host-actions
        {"actions":[{"tool_id":"gee.gear.invoke","arguments":{}}]}
        ```
        Sources:
        """

        XCTAssertEqual(AssistantTranscriptSanitizer.sanitize(content), "Saved.")
    }
}
