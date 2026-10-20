import XCTest
@testable import MacUtils

final class ProcessReaderTests: XCTestCase {
    @MainActor
    func testAppListsPreloadWithoutOpeningPanels() async {
        let loaded = expectation(description: "CPU and memory app lists preload in passive mode")
        let poller = AdaptivePoller()
        var fulfilled = false
        poller.onMetricsUpdated = { cpu, memory, _, _, state in
            guard !fulfilled, !cpu.topProcesses.isEmpty, !memory.topProcesses.isEmpty else { return }
            fulfilled = true
            XCTAssertEqual(state, .passive)
            loaded.fulfill()
        }
        poller.start()
        defer { poller.stop() }
        await fulfillment(of: [loaded], timeout: 15)
    }

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
