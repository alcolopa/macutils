import XCTest
@testable import MacMonitor

final class TemperatureAndDisplayTests: XCTestCase {
    func testMachTemperatureReaderExecution() {
        let reader = MachTemperatureReader()
        let stats = reader.readTemperatures()
        
        // Sanity checks on temperatures
        XCTAssertGreaterThan(stats.cpuTemperature, 0.0, "CPU temperature should be positive")
        XCTAssertLessThan(stats.cpuTemperature, 125.0, "CPU temperature should be reasonable (<125C)")
        
        if let bat = stats.batteryTemperature {
            XCTAssertGreaterThan(bat, 0.0)
            XCTAssertLessThan(bat, 65.0)
        }
    }
    
    func testMachTemperatureReaderPortNeutralityOverReads() {
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
        
        let reader = MachTemperatureReader()
        _ = reader.readTemperatures()
        
        let startCount = getPortCount()
        for _ in 0..<50 {
            _ = reader.readTemperatures()
        }
        let endCount = getPortCount()
        
        XCTAssertEqual(startCount, endCount, "Temperature reader leaked Mach ports! Delta: \(Int(endCount) - Int(startCount))")
    }
    
    func testPreferencesMetricOrderPersistence() {
        let prefs = AppPreferences.shared
        let originalOrder = prefs.metricOrder
        
        let newOrder: [MetricType] = [.temperatures, .cpu, .memory, .disk, .network, .weather]
        prefs.metricOrder = newOrder
        
        XCTAssertEqual(prefs.metricOrder, newOrder)
        
        // Restore
        prefs.metricOrder = originalOrder
    }
    
    func testMetricMoveAndStyleCustomization() {
        let prefs = AppPreferences.shared
        let originalOrder = prefs.metricOrder
        let originalCpuStyle = prefs.displayStyle(for: .cpu)
        
        // Test moveMetric
        prefs.moveMetric(from: 0, to: 2)
        XCTAssertEqual(prefs.metricOrder[2], originalOrder[0])
        
        // Test style change
        prefs.setDisplayStyle(.circularGauge, for: .cpu)
        XCTAssertEqual(prefs.displayStyle(for: .cpu), .circularGauge)
        
        // Restore
        prefs.metricOrder = originalOrder
        prefs.setDisplayStyle(originalCpuStyle, for: .cpu)
    }
}
