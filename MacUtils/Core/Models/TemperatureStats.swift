import Foundation

public enum SensorCategory: String, Sendable, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case battery = "Battery"
    case system = "System"
}

public struct SensorReading: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let temperature: Double // in Celsius
    public let category: SensorCategory
    
    public init(name: String, temperature: Double, category: SensorCategory) {
        self.name = name
        self.temperature = temperature
        self.category = category
    }
}

public struct TemperatureStats: Sendable {
    public let sensors: [SensorReading]
    public let cpuTemperature: Double      // Primary CPU package / die temp
    public let gpuTemperature: Double?     // Primary GPU temp if available
    public let batteryTemperature: Double? // Battery temp
    public let thermalPressure: ProcessInfo.ThermalState
    public let timestamp: UInt64
    
    public init(
        sensors: [SensorReading] = [],
        cpuTemperature: Double = 45.0,
        gpuTemperature: Double? = nil,
        batteryTemperature: Double? = nil,
        thermalPressure: ProcessInfo.ThermalState = .nominal,
        timestamp: UInt64 = mach_absolute_time()
    ) {
        self.sensors = sensors
        self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature
        self.batteryTemperature = batteryTemperature
        self.thermalPressure = thermalPressure
        self.timestamp = timestamp
    }
    
    public var thermalStateString: String {
        switch thermalPressure {
        case .nominal:  return "Nominal (Cool)"
        case .fair:     return "Fair (Warm)"
        case .serious:  return "Serious (Throttling)"
        case .critical: return "Critical (High Heat)"
        @unknown default: return "Normal"
        }
    }
}
