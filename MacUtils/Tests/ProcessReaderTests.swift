import XCTest
@testable import MacUtils

final class ProcessReaderTests: XCTestCase {
    func testTopProcessesReader() {
        let reader = DarwinProcessReader()
        let (byMem, byCPU) = reader.readTopProcesses(limit: 5)
        
        XCTAssertFalse(byMem.isEmpty, "Top processes by memory must not be empty")
        XCTAssertFalse(byCPU.isEmpty, "Top processes by CPU must not be empty")
        XCTAssertLessThanOrEqual(byMem.count, 5)
        XCTAssertLessThanOrEqual(byCPU.count, 5)
        
        for item in byMem {
            XCTAssertFalse(item.name.isEmpty)
            XCTAssertGreaterThanOrEqual(item.residentBytes, 0)
        }
    }
}
