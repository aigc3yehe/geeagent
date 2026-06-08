import XCTest
@testable import GeeAgentMac

final class MediaLibraryDynamicPreviewPolicyTests: XCTestCase {
    func testDynamicPreviewKeepsAllVisibleAutoplayItems() {
        let items = (0..<6).map { index in
            makeMediaItem(id: "video-\(index)", ext: "mp4")
        }
        let visibleIDs = Set(items.map(\.id))

        let previewIDs = MediaLibraryDynamicPreviewPolicy.previewItemIDs(
            visibleItemIDs: visibleIDs,
            items: items
        )

        XCTAssertEqual(previewIDs, visibleIDs)
    }

    func testDynamicPreviewKeepsVisibleDynamicItemsAndSkipsHiddenOrStaticItems() {
        let items = [
            makeMediaItem(id: "image", ext: "png"),
            makeMediaItem(id: "video-0", ext: "mp4"),
            makeMediaItem(id: "gif-0", ext: "gif"),
            makeMediaItem(id: "video-1", ext: "mov"),
            makeMediaItem(id: "video-2", ext: "mp4"),
        ]

        let previewIDs = MediaLibraryDynamicPreviewPolicy.previewItemIDs(
            visibleItemIDs: ["image", "gif-0", "video-1", "video-2"],
            items: items
        )

        XCTAssertEqual(previewIDs, ["gif-0", "video-1", "video-2"])
    }

    func testStartupDelayIsStableAndBounded() {
        let first = MediaLibraryDynamicPreviewPolicy.startupDelayNanoseconds(for: "video-0")
        let second = MediaLibraryDynamicPreviewPolicy.startupDelayNanoseconds(for: "video-0")

        XCTAssertEqual(first, second)
        XCTAssertLessThanOrEqual(first, 490_000_000)
    }

    func testExpandedViewportMarksPreviouslyOutsideTileVisible() {
        let frame = CGRect(x: 0, y: 520, width: 320, height: 180)

        XCTAssertFalse(
            MediaLibraryDynamicPreviewPolicy.isVisibleForDynamicPreview(
                frame: frame,
                viewportSize: CGSize(width: 800, height: 360),
                isEnabled: true
            )
        )
        XCTAssertTrue(
            MediaLibraryDynamicPreviewPolicy.isVisibleForDynamicPreview(
                frame: frame,
                viewportSize: CGSize(width: 1200, height: 680),
                isEnabled: true
            )
        )
    }

    func testVideoLeadInSkipsDelayedFirstVideoFrame() {
        XCTAssertTrue(MediaLibraryDynamicPreviewPolicy.shouldSkipVideoLeadIn(startSeconds: 1.382))
    }

    func testVideoLeadInKeepsTinyMuxingOffsets() {
        XCTAssertFalse(MediaLibraryDynamicPreviewPolicy.shouldSkipVideoLeadIn(startSeconds: 0))
        XCTAssertFalse(MediaLibraryDynamicPreviewPolicy.shouldSkipVideoLeadIn(startSeconds: 0.066))
        XCTAssertFalse(MediaLibraryDynamicPreviewPolicy.shouldSkipVideoLeadIn(startSeconds: .nan))
    }

    private func makeMediaItem(id: String, ext: String) -> MediaLibraryItem {
        MediaLibraryItem(
            id: id,
            name: id,
            ext: ext,
            width: 1920,
            height: 1080,
            durationSeconds: ext == "gif" || ext == "png" ? nil : 12,
            size: 1024,
            modifiedAt: Date(timeIntervalSince1970: 0),
            tags: [],
            annotation: nil,
            sourceURL: nil,
            fileURL: URL(fileURLWithPath: "/tmp/\(id).\(ext)"),
            thumbnailURL: nil,
            folderIDs: [],
            isStarred: false
        )
    }
}
