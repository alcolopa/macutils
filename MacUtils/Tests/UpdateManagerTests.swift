import XCTest
@testable import MacUtils

final class UpdateManagerTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateManager.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(UpdateManager.isNewer("1.10.0", than: "1.9.2"))
        XCTAssertTrue(UpdateManager.isNewer("2.0", than: "1.99.99"))
        XCTAssertFalse(UpdateManager.isNewer("1.1.0", than: "1.1.0"))
        XCTAssertFalse(UpdateManager.isNewer("1.1", than: "1.1.0"))
        XCTAssertFalse(UpdateManager.isNewer("1.0.9", than: "1.1.0"))
    }
}
