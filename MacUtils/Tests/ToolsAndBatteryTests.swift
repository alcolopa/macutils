import XCTest
@testable import MacUtils

final class ToolsAndBatteryTests: XCTestCase {
    @MainActor
    func testColorPickerFormatting() {
        // Pure red
        XCTAssertEqual(ScreenColorPicker.formatColor(r: 1.0, g: 0.0, b: 0.0, as: .hex), "#FF0000")
        XCTAssertEqual(ScreenColorPicker.formatColor(r: 1.0, g: 0.0, b: 0.0, as: .rgb), "rgb(255, 0, 0)")
        XCTAssertEqual(ScreenColorPicker.formatColor(r: 1.0, g: 0.0, b: 0.0, as: .hsl), "hsl(0, 100%, 50%)")
        
        // Tailwind blue #3B82F6 (59, 130, 246)
        let r = CGFloat(59) / 255.0
        let g = CGFloat(130) / 255.0
        let b = CGFloat(246) / 255.0
        XCTAssertEqual(ScreenColorPicker.formatColor(r: r, g: g, b: b, as: .hex), "#3B82F6")
        XCTAssertEqual(ScreenColorPicker.formatColor(r: r, g: g, b: b, as: .rgb), "rgb(59, 130, 246)")
        XCTAssertEqual(ScreenColorPicker.formatColor(r: r, g: g, b: b, as: .hsl), "hsl(217, 91%, 60%)")
        
        // Black & White
        XCTAssertEqual(ScreenColorPicker.formatColor(r: 0.0, g: 0.0, b: 0.0, as: .hsl), "hsl(0, 0%, 0%)")
        XCTAssertEqual(ScreenColorPicker.formatColor(r: 1.0, g: 1.0, b: 1.0, as: .hsl), "hsl(0, 0%, 100%)")
    }
    
    func testBatteryReader() {
        let reader = MachBatteryReader()
        let stats = reader.readBatteryUsage()
        XCTAssertGreaterThanOrEqual(stats.percentage, 0.0)
        XCTAssertLessThanOrEqual(stats.percentage, 100.0)
        XCTAssertFalse(stats.powerSourceState.isEmpty)
    }
    
    func testPortReaderSafety() {
        let reader = DarwinPortReader()
        let ports = reader.readListeningPorts(forceRefresh: true)
        for item in ports {
            XCTAssertGreaterThan(item.port, 0)
            XCTAssertGreaterThan(item.pid, 0)
            XCTAssertFalse(item.processName.isEmpty)
        }
        // Must never allow killing PID 0 or 1
        XCTAssertFalse(reader.killProcess(pid: 0))
        XCTAssertFalse(reader.killProcess(pid: 1))
    }
    
    func testAudioHardwareEnumerationAndPrivacyQueries() {
        let manager = AudioHardwareManager.shared
        let (inputs, outputs) = manager.getDevices()
        // Querying privacy indicators should complete safely
        _ = manager.isAnyMicrophoneInUse()
        _ = manager.isAnyCameraInUse()
        for dev in inputs { XCTAssertTrue(dev.isInput); XCTAssertFalse(dev.name.isEmpty) }
        for dev in outputs { XCTAssertTrue(dev.isOutput); XCTAssertFalse(dev.name.isEmpty) }
    }
    
    @MainActor
    func testDisplayControlEnumeration() {
        let displays = DisplayControlManager.shared.connectedDisplays()
        for disp in displays {
            XCTAssertFalse(disp.name.isEmpty)
            XCTAssertGreaterThanOrEqual(disp.brightness, 0)
            XCTAssertLessThanOrEqual(disp.brightness, 100)
        }
    }
    
    func testToolsPreferencesPersistence() {
        let prefs = AppPreferences.shared
        let origFormat = prefs.colorPickerFormat
        let origHotkeys = prefs.toolsHotkeysEnabled
        defer {
            prefs.colorPickerFormat = origFormat
            prefs.toolsHotkeysEnabled = origHotkeys
        }
        
        prefs.colorPickerFormat = .hsl
        XCTAssertEqual(prefs.colorPickerFormat, .hsl)
        
        prefs.toolsHotkeysEnabled = false
        XCTAssertFalse(prefs.toolsHotkeysEnabled)
    }
    
    func testPerAppAudioEnumeration() {
        let manager = PerAppAudioManager()
        let apps = manager.listAudioApps()
        for app in apps {
            XCTAssertFalse(app.key.isEmpty)
            XCTAssertFalse(app.name.isEmpty)
            XCTAssertFalse(app.objectIDs.isEmpty)
            XCTAssertEqual(app.volume, 1.0, accuracy: 0.001)
            XCTAssertFalse(app.isMuted)
        }
        manager.resetAll()
    }
}
