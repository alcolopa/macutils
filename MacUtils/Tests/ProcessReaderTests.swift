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
    
    func testProcessCPUUsageCalculationAccuracy() {
        let reader = DarwinProcessReader()
        _ = reader.readTopProcesses(limit: 5)
        
        let isRunning = ManagedAtomicBool(true)
        let thread = Thread {
            var counter: UInt64 = 0
            while isRunning.value {
                counter &+= 1
            }
            _ = counter
        }
        thread.start()
        
        Thread.sleep(forTimeInterval: 0.5)
        let (_, byCPU) = reader.readTopProcesses(limit: 10)
        isRunning.value = false
        
        let myPid = ProcessInfo.processInfo.processIdentifier
        let myProcess = byCPU.first { $0.pid == myPid }
        
        // With a busy thread running for 500ms, the process should register substantial CPU%
        // (historically crippled to ~1-2% on Apple Silicon due to mach timebase scaling bug)
        if let proc = myProcess {
            XCTAssertGreaterThan(proc.cpuPercentage, 20.0, "Busy process CPU% should be realistic, got \(proc.cpuPercentage)%")
        }
    }
}

private final class ManagedAtomicBool: @unchecked Sendable {
    private var _val: Bool
    private let lock = NSLock()
    init(_ val: Bool) { self._val = val }
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _val }
        set { lock.lock(); defer { lock.unlock() }; _val = newValue }
    }
}
