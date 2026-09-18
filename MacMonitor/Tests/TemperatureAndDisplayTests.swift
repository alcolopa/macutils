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
    
    func testMachDisplayReaderExecution() {
        let reader = MachDisplayReader()
        let stats = reader.readDisplays()
        
        XCTAssertGreaterThanOrEqual(stats.activeDisplayCount, 1, "There should be at least 1 active display")
        guard let first = stats.displays.first else {
            XCTFail("No displays returned")
            return
        }
        XCTAssertGreaterThan(first.resolution.width, 0.0)
        XCTAssertGreaterThan(first.resolution.height, 0.0)
        XCTAssertGreaterThan(first.refreshRate, 0.0)
    }
    
    func testPreferencesMetricOrderPersistence() {
        let prefs = AppPreferences.shared
        let originalOrder = prefs.metricOrder
        
        let newOrder: [MetricType] = [.temperatures, .displays, .cpu, .memory, .disk, .network, .battery, .weather]
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
