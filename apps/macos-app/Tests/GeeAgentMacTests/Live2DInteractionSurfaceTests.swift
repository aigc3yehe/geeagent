import CoreGraphics
import XCTest
@testable import GeeAgentMac

final class Live2DInteractionSurfaceTests: XCTestCase {
    func testViewportClampPullsEdgePositionBackWhenScaleShrinks() {
        let enlarged = Live2DViewportState(offsetX: 420, offsetY: 260, scale: 1.8).clamped()
        XCTAssertEqual(enlarged.offsetX, 420, accuracy: 0.001)
        XCTAssertEqual(enlarged.offsetY, 260, accuracy: 0.001)

        let shrunken = Live2DViewportState(
            offsetX: enlarged.offsetX,
            offsetY: enlarged.offsetY,
            scale: 0.65
        ).clamped()

        XCTAssertEqual(shrunken.offsetX, 0, accuracy: 0.001)
        XCTAssertEqual(shrunken.offsetY, 0, accuracy: 0.001)
        XCTAssertEqual(shrunken.scale, 0.65, accuracy: 0.001)
    }

    func testInteractionRectCoversVisibleHeroCenterWithExtremeViewportOffsets() {
        let bounds = CGRect(x: 0, y: 0, width: 1093, height: 768)
        let viewport = Live2DViewportState(offsetX: -420, offsetY: -259.5, scale: 0.65)

        let rect = InteractionView.interactionRect(in: bounds, viewportState: viewport)

        XCTAssertTrue(
            rect.contains(CGPoint(x: bounds.midX, y: bounds.midY + 40)),
            "interaction rect should still cover the visible character body after viewport calibration, got \(rect)"
        )
        XCTAssertGreaterThan(rect.minY, bounds.height * 0.17)
    }

    func testInteractionRectProvidesCentralTargetAtDefaultViewport() {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)

        let rect = InteractionView.interactionRect(in: bounds, viewportState: .default)

        XCTAssertTrue(rect.contains(CGPoint(x: bounds.midX, y: bounds.midY + 40)))
        XCTAssertLessThan(rect.width, bounds.width * 0.5)
        XCTAssertLessThan(rect.minY, bounds.height * 0.35)
    }

    func testLive2DHostKeepsRuntimePointerEventsEnabled() throws {
        let index = try String(contentsOf: live2DHostResource("index.html"), encoding: .utf8)
        XCTAssertFalse(
            index.contains("html, body {\n        margin: 0;") && index.contains("pointer-events: none;\n        user-select"),
            "the document root must allow pointer events so the character can receive clicks"
        )

        let app = try String(contentsOf: live2DHostResource("app.js"), encoding: .utf8)
        XCTAssertTrue(app.contains("runtimeCanvas.style.pointerEvents = \"auto\""))
        XCTAssertTrue(
            app.contains("runtimeCanvas.style.touchAction = \"none\""),
            "runtime canvases should be able to receive pointer interactions without browser gesture side effects"
        )
    }

    func testLive2DHostCentersModelsWithoutDescriptorLayout() throws {
        let bootstrap = try String(contentsOf: live2DHostResource("live2d-bootstrap.js"), encoding: .utf8)

        XCTAssertTrue(
            bootstrap.contains("this._usesFallbackLayout = layout.size === 0;"),
            "models that omit Cubism Layout metadata should use the host fallback layout path"
        )
        XCTAssertTrue(bootstrap.contains("this._fallbackLayoutBounds = this.measureVisibleDrawableBounds();"))
        XCTAssertTrue(bootstrap.contains("this.applyFallbackLayoutToViewport("))
        XCTAssertTrue(bootstrap.contains("if (model._usesFallbackLayout) {"))
        XCTAssertTrue(bootstrap.contains("model.applyFallbackLayoutToViewport(width, height);"))
        XCTAssertTrue(bootstrap.contains("projection.scale(height / width, 1);"))
    }

    @MainActor
    func testExcludedRectYieldsHitTestingToHomeWidgets() {
        let view = InteractionView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        let widgetRect = CGRect(x: 485, y: 360, width: 230, height: 118)

        view.configure(
            viewportState: .default,
            catalog: .empty,
            activePosePath: nil,
            activeExpressionPath: nil,
            excludedRects: [widgetRect],
            onPrimaryClick: {},
            onSelectPose: { _ in },
            onSelectExpression: { _ in },
            onPlayAction: { _ in },
            onResetExpression: {},
            onDrag: { _ in },
            onScale: { _ in },
            onResetViewport: {}
        )

        XCTAssertNil(
            view.hitTest(CGPoint(x: 600, y: 419)),
            "home widgets that overlap the Live2D body should receive the drag start instead of the Live2D overlay"
        )
        XCTAssertTrue(view.hitTest(CGPoint(x: 600, y: 590)) === view)
    }

    func testHomeWidgetStoredPositionMatchesWidgetLayerPlacement() {
        let canvasSize = CGSize(width: 1000, height: 700)
        let stored = #"{"btc.price":{"x":530.41078125,"y":396.2890625}}"#

        let point = HomeWidgetPlacement.storedPosition(
            for: "btc.price",
            canvasSize: canvasSize,
            storedPositions: stored
        )

        XCTAssertEqual(point.x, 530.41078125, accuracy: 0.0001)
        XCTAssertEqual(point.y, 396.2890625, accuracy: 0.0001)
    }

    private func live2DHostResource(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Live2DHost/\(name)")
    }
}
