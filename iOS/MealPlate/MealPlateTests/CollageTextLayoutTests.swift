import XCTest
@testable import MealPlate

@MainActor
final class CollageTextLayoutTests: XCTestCase {
    private let canvasSize = CGSize(width: 402, height: 536)

    func testScaleDownTemplateTextExpandsBeforeShrinking() {
        let layer = makeTemplateText(
            text: "This Week",
            width: 0.08,
            height: 0.06,
            overflow: .scaleDown,
            maximumLines: 1
        )

        let baseWidth = layer.normalizedWidth * canvasSize.width
        let resolved = layer.displaySize(in: canvasSize)

        XCTAssertGreaterThan(resolved.width, baseWidth)
        XCTAssertLessThanOrEqual(resolved.width, canvasSize.width)
    }

    func testWrappedTemplateTextGrowsVerticallyToFitLines() {
        let layer = makeTemplateText(
            text: "好吃好吃好吃\n今日份惊喜\n认真记录中",
            width: 0.24,
            height: 0.025,
            overflow: .wrap,
            maximumLines: 3
        )

        let baseHeight = 0.025 * canvasSize.height
        let resolved = layer.displaySize(in: canvasSize)

        XCTAssertGreaterThan(resolved.height, baseHeight)
    }

    func testLeadingTextExpansionPreservesLeadingAnchor() {
        let layer = makeTemplateText(
            text: "one step at a time",
            width: 0.08,
            height: 0.05,
            overflow: .clip,
            maximumLines: 1,
            alignment: .leading
        )
        let baseWidth = layer.normalizedWidth * canvasSize.width
        let originalLeading = layer.center.x * canvasSize.width - baseWidth / 2

        let resolvedSize = layer.displaySize(in: canvasSize)
        let resolvedCenter = layer.displayCenter(in: canvasSize)
        let resolvedLeading = resolvedCenter.x * canvasSize.width - resolvedSize.width / 2

        XCTAssertEqual(resolvedLeading, originalLeading, accuracy: 0.5)
    }

    private func makeTemplateText(
        text: String,
        width: CGFloat,
        height: CGFloat,
        overflow: CollageTextOverflow,
        maximumLines: Int,
        alignment: CollageTextAlignment = .leading
    ) -> CollageLayer {
        CollageLayer(
            kind: .text,
            text: text,
            center: CGPoint(x: 0.5, y: 0.5),
            normalizedWidth: width,
            zIndex: 1,
            textFont: .heiti,
            textAlignment: alignment,
            textFrameHeight: height,
            textFontSizeRatio: 0.045,
            textLineHeightMultiple: 1.2,
            textMaximumLines: maximumLines,
            textOverflow: overflow
        )
    }
}
