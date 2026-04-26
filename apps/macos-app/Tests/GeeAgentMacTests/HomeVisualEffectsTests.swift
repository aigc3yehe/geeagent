import XCTest
@testable import GeeAgentMac

final class HomeVisualEffectsTests: XCTestCase {
    func testRainGlassFieldUsesSparseDropletCounts() {
        let field = makeHomeRainGlassField()

        XCTAssertEqual(field.staticDroplets.count, 9)
        XCTAssertEqual(field.slidingDroplets.count, 3)
        XCTAssertEqual(field.impactRipples.count, 4)
    }

    func testRainGlassFieldDropletsStayOnCanvasAndTrailDownward() {
        let field = makeHomeRainGlassField()

        XCTAssertTrue(field.staticDroplets.allSatisfy { droplet in
            (0.0...1.0).contains(droplet.normalizedX) &&
            (0.0...1.0).contains(droplet.normalizedY)
        })
        XCTAssertTrue(field.slidingDroplets.allSatisfy { droplet in
            droplet.endY > droplet.startY && droplet.trailLength > 0
        })
        XCTAssertTrue(field.impactRipples.allSatisfy { ripple in
            ripple.peakRadius > 0 && ripple.duration > 0
        })
    }
}
