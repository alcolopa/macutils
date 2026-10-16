import XCTest
import Darwin
@testable import MacUtils

final class MachReaderTests: XCTestCase {

    func testCPULatencyUnderFiveMilliseconds() {
        let reader = MachCPUReader()
        _ = reader.readSystemUsage()
        
        let start = DispatchTime.now().uptimeNanoseconds
        _ = reader.readSystemUsage()
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
        
        XCTAssertLessThan(elapsedMs, 5.0, "Mach CPU read latency exceeded budget: \(elapsedMs)ms")
    }

    func testMachPortNeutralityOverOneThousandReads() {
        func getPortCount() -> mach_msg_type_number_t {
            var portNames: mach_port_name_array_t?
            var namesCount: mach_msg_type_number_t = 0
            var portTypes: mach_port_type_array_t?
            var typesCount: mach_msg_type_number_t = 0
            
            let kr = mach_port_names(mach_task_self_, &portNames, &namesCount, &portTypes, &typesCount)
            XCTAssertEqual(kr, KERN_SUCCESS)
            
            if let portNames = portNames {
                vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: portNames)), vm_size_t(namesCount) * vm_size_t(MemoryLayout<mach_port_name_t>.stride))
            }
            if let portTypes = portTypes {
                vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: portTypes)), vm_size_t(typesCount) * vm_size_t(MemoryLayout<mach_port_type_t>.stride))
            }
            return namesCount
        }
        
        let reader = MachCPUReader()
        _ = reader.readSystemUsage()
        
        let startCount = getPortCount()
        for _ in 0..<1000 {
            _ = reader.readSystemUsage()
        }
        let endCount = getPortCount()
        
        XCTAssertEqual(startCount, endCount, "Mach port leak detected! Net port delta: \(Int(endCount) - Int(startCount))")
    }

    func testMachMemoryReaderIntegrity() {
        let reader = MachMemoryReader()
        let mem = reader.readMemoryUsage()
        
        XCTAssertGreaterThan(mem.totalBytes, 0, "Total memory must be greater than 0")
        XCTAssertGreaterThan(mem.usedBytes, 0, "Used memory must be greater than 0")
        XCTAssertLessThanOrEqual(mem.usedPercentage, 100.0, "Used percentage must not exceed 100%")
        XCTAssertGreaterThanOrEqual(mem.usedPercentage, 0.0, "Used percentage must be non-negative")
    }

    func testMemoryPressureReading() {
        let reader = MachMemoryReader()
        let mem = reader.readMemoryUsage()
        XCTAssertGreaterThan(mem.pressurePercentage, 0.0)
        XCTAssertLessThanOrEqual(mem.pressurePercentage, 100.0)
    }

    func testSwapMemoryReading() {
        let reader = MachMemoryReader()
        let mem = reader.readMemoryUsage()
        XCTAssertGreaterThanOrEqual(mem.swap.totalBytes, 0)
        XCTAssertGreaterThanOrEqual(mem.swap.usedBytes, 0)
        XCTAssertGreaterThanOrEqual(mem.swap.freeBytes, 0)
    }

    func testCPUGraphRendererRingBufferBoundaries() {
        let renderer = CPUGraphRenderer()
        for i in 0..<300 {
            renderer.push(value: Double(i % 100))
        }
        let snapshot = renderer.snapshotValues()
        XCTAssertEqual(snapshot.count, CPUGraphRenderer.capacity)
        for val in snapshot {
            XCTAssertGreaterThanOrEqual(val, 0.0)
            XCTAssertLessThanOrEqual(val, 100.0)
        }
    }
}
