import XCTest
import Darwin
@testable import MacUtils

final class DiskReaderTests: XCTestCase {

    func testDiskReaderExecution() {
        let reader = MachDiskReader()
        let stats = reader.readDiskUsage()
        
        XCTAssertGreaterThan(stats.rootVolume.totalBytes, 0, "Root disk capacity must be > 0")
        XCTAssertGreaterThan(stats.rootVolume.usedBytes, 0, "Root disk used bytes must be > 0")
        XCTAssertGreaterThan(stats.rootVolume.freeBytes, 0, "Root disk free bytes must be > 0")
        XCTAssertLessThanOrEqual(stats.rootVolume.usedPercentage, 100.0)
        XCTAssertGreaterThanOrEqual(stats.rootVolume.usedPercentage, 0.0)
        XCTAssertFalse(stats.allVolumes.isEmpty)
    }

    func testDiskFormatting() {
        let oneGB: UInt64 = 1024 * 1024 * 1024
        XCTAssertEqual(DiskStats.formatBytes(oneGB * 250), "250 GB")
        XCTAssertEqual(DiskStats.formatBytes(oneGB * 1024 * 2), "2.0 TB")
    }
}
