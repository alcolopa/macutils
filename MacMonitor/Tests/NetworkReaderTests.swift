import XCTest
import Darwin
@testable import MacMonitor

final class NetworkReaderTests: XCTestCase {

    func testNetworkReaderExecution() {
        let reader = MachNetworkReader()
        let initial = reader.readNetworkUsage()
        XCTAssertGreaterThanOrEqual(initial.totalBytesIn, 0)
        XCTAssertGreaterThanOrEqual(initial.totalBytesOut, 0)
        
        // Wait briefly and read again
        usleep(100_000) // 100ms
        let second = reader.readNetworkUsage()
        
        XCTAssertGreaterThanOrEqual(second.bytesInPerSec, 0)
        XCTAssertGreaterThanOrEqual(second.bytesOutPerSec, 0)
        XCTAssertFalse(second.primaryInterface.isEmpty)
    }

    func testSpeedFormatting() {
        XCTAssertEqual(NetworkStats.formatSpeed(500), "500 B/s")
        XCTAssertEqual(NetworkStats.formatSpeed(1500), "1 KB/s")
        XCTAssertEqual(NetworkStats.formatSpeed(1024 * 1024 * 5), "5.0 MB/s")
        XCTAssertEqual(NetworkStats.formatSpeed(1024 * 1024 * 1024 * 2.5), "2.50 GB/s")
    }

    func testTopNetworkProcesses() {
        let reader = MachNetworkReader()
        let procs = reader.readTopNetworkProcesses(limit: 5)
        XCTAssertLessThanOrEqual(procs.count, 5)
        for p in procs {
            XCTAssertGreaterThan(p.pid, 0)
            XCTAssertFalse(p.name.isEmpty)
            XCTAssertFalse(p.formattedSpeed.isEmpty)
            XCTAssertFalse(p.formattedTotal.isEmpty)
        }
    }
}
