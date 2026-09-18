import XCTest
@testable import MacMonitor

final class BatteryReaderTests: XCTestCase {
    func testBatteryReader() {
        let reader = MachBatteryReader()
        let stats = reader.readBatteryUsage()
        
        XCTAssertGreaterThanOrEqual(stats.currentCapacity, 0)
        XCTAssertLessThanOrEqual(stats.currentCapacity, 100)
        XCTAssertFalse(stats.powerSourceState.isEmpty)
        XCTAssertFalse(stats.formattedTimeRemaining.isEmpty)
    }
}
