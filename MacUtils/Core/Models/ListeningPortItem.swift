import Foundation

public struct ListeningPortItem: Sendable, Identifiable {
    public var id: String { "\(port)-\(pid)" }
    public let port: Int
    public let pid: Int32
    public let processName: String
    public let address: String
    public let iconPath: String?
    
    public init(port: Int, pid: Int32, processName: String, address: String = "*", iconPath: String? = nil) {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.address = address
        self.iconPath = iconPath
    }
    
    public var formattedPort: String {
        return ":\(port)"
    }
}
