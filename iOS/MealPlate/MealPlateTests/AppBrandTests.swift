import XCTest
@testable import MealPlate

@MainActor
final class AppBrandTests: XCTestCase {
    func testDisplayNameUsesCurrentBrand() {
        XCTAssertEqual(AppBrand.displayName, "Mi味")
    }
}
