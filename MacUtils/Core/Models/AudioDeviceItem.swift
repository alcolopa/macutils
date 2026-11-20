import Foundation
import CoreAudio

public struct AudioDeviceItem: Sendable, Identifiable {
    public var id: AudioDeviceID { deviceID }
    public let deviceID: AudioDeviceID
    public let name: String
    public let isInput: Bool
    public let isOutput: Bool
    public let isDefaultInput: Bool
    public let isDefaultOutput: Bool
    
    public init(
        deviceID: AudioDeviceID,
        name: String,
        isInput: Bool,
        isOutput: Bool,
        isDefaultInput: Bool = false,
        isDefaultOutput: Bool = false
    ) {
        self.deviceID = deviceID
        self.name = name
        self.isInput = isInput
        self.isOutput = isOutput
        self.isDefaultInput = isDefaultInput
        self.isDefaultOutput = isDefaultOutput
    }
}
