import XCTest
@testable import MealPlate

@MainActor
final class CollageEditorHistoryTests: XCTestCase {
    func testUndoAndWithdrawRestoreOneCommittedGesture() {
        let model = CollageEditorModel(period: .today)
        let layer = makeLayer(zIndex: 3)
        model.layers = [layer]

        model.beginHistoryTransaction()
        layer.center = CGPoint(x: 0.8, y: 0.7)
        model.commitHistoryTransaction()

        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(model.layers[0].center.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(model.layers[0].center.y, 0.35, accuracy: 0.0001)

        XCTAssertTrue(model.canWithdrawUndo)
        model.withdrawUndo()
        XCTAssertEqual(model.layers[0].center.x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(model.layers[0].center.y, 0.7, accuracy: 0.0001)
    }

    func testHistoryKeepsOnlyTwentyCommittedSteps() {
        let model = CollageEditorModel(period: .today)
        let layer = makeLayer(zIndex: 1)
        model.layers = [layer]

        for index in 1...25 {
            model.beginHistoryTransaction()
            layer.center.x = CGFloat(index) / 100
            model.commitHistoryTransaction()
        }

        for _ in 0..<20 { model.undo() }
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(model.layers[0].center.x, 0.05, accuracy: 0.0001)
    }

    func testDraggingDoesNotChangeLayerOrder() {
        let model = CollageEditorModel(period: .today)
        let lower = makeLayer(zIndex: 2)
        let upper = makeLayer(zIndex: 8)
        model.layers = [lower, upper]
        let canvas = CGSize(width: 402, height: 536)

        model.beginLayerDrag(lower.id, location: CGPoint(x: 100, y: 120))
        model.updateLayerDrag(lower.id, location: CGPoint(x: 240, y: 260), canvasSize: canvas)
        model.endLayerDrag(lower.id)

        XCTAssertEqual(lower.zIndex, 2)
        XCTAssertEqual(upper.zIndex, 8)
    }

    func testMoveLayerOneStepSwapsOnlyAdjacentLayer() {
        let model = CollageEditorModel(period: .today)
        let first = makeLayer(zIndex: 1)
        let second = makeLayer(zIndex: 4)
        let third = makeLayer(zIndex: 9)
        model.layers = [first, second, third]

        model.moveLayerOneStep(first.id, direction: .up)

        XCTAssertEqual(first.zIndex, 4)
        XCTAssertEqual(second.zIndex, 1)
        XCTAssertEqual(third.zIndex, 9)
    }

    func testRepeatedTapAtSamePointCyclesOverlappingLayersWithoutReordering() {
        let model = CollageEditorModel(period: .today)
        let lower = makeLayer(zIndex: 2)
        let upper = makeLayer(zIndex: 8)
        lower.center = CGPoint(x: 0.5, y: 0.5)
        upper.center = CGPoint(x: 0.5, y: 0.5)
        model.layers = [lower, upper]
        let canvas = CGSize(width: 402, height: 536)
        let point = CGPoint(x: 201, y: 268)

        model.selectLayer(at: point, canvasSize: canvas)
        XCTAssertEqual(model.selectedLayerID, upper.id)
        model.selectLayer(at: point, canvasSize: canvas)
        XCTAssertEqual(model.selectedLayerID, lower.id)
        XCTAssertEqual(lower.zIndex, 2)
        XCTAssertEqual(upper.zIndex, 8)
    }

    func testBackgroundOpacityIsSavedInScene() throws {
        let model = CollageEditorModel(period: .today)
        model.inputFingerprint = "opacity-test"
        model.backgroundSlots = [CollageBackgroundSlot(opacity: 0.42)]

        let scene = try XCTUnwrap(model.storedSceneSnapshot())
        let data = try JSONEncoder().encode(scene)
        let decoded = try JSONDecoder().decode(StoredCollageScene.self, from: data)

        XCTAssertEqual(try XCTUnwrap(decoded.backgrounds.first?.opacity), 0.42, accuracy: 0.0001)
    }

    private func makeLayer(zIndex: Int) -> CollageLayer {
        CollageLayer(
            kind: .sticker,
            center: CGPoint(x: 0.25, y: 0.35),
            normalizedWidth: 0.25,
            zIndex: zIndex
        )
    }
}
