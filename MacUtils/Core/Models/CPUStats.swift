import Darwin

public struct CoreLoad: Sendable {
    public let coreIndex: Int
    public let userPercentage: Double
    public let systemPercentage: Double
    public let idlePercentage: Double
    
    public init(coreIndex: Int, userPercentage: Double, systemPercentage: Double, idlePercentage: Double) {
        self.coreIndex = coreIndex
        self.userPercentage = userPercentage
        self.systemPercentage = systemPercentage
        self.idlePercentage = idlePercentage
    }
    
    public var totalUsagePercentage: Double {
        return min(max(userPercentage + systemPercentage, 0.0), 100.0)
    }
}

public struct CPUStats: Sendable {
    public let totalUsage: Double          // 0.0 to 100.0
    public let perCoreLoads: [CoreLoad]
    public let loadAverages: [Double]      // 1m, 5m, 15m
    public let cpuModel: String            // e.g. "Apple M1 Pro"
    public let uptimeSeconds: Double       // Boot uptime in seconds
    public let topProcesses: [ProcessItem]
    public let timestamp: UInt64           // mach_absolute_time
    
    public init(
        totalUsage: Double,
        perCoreLoads: [CoreLoad],
        loadAverages: [Double] = [0.0, 0.0, 0.0],
        cpuModel: String = "Apple Silicon",
        uptimeSeconds: Double = 0.0,
        topProcesses: [ProcessItem] = [],
        timestamp: UInt64
    ) {
        self.totalUsage = totalUsage
        self.perCoreLoads = perCoreLoads
        self.loadAverages = loadAverages
        self.cpuModel = cpuModel
        self.uptimeSeconds = uptimeSeconds
        self.topProcesses = topProcesses
        self.timestamp = timestamp
    }
    
    public var formattedUptime: String {
        let total = Int(uptimeSeconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }
}
