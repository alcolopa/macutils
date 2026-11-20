import Foundation
import CoreAudio
import CoreMediaIO

public final class AudioHardwareManager: @unchecked Sendable {
    public static let shared = AudioHardwareManager()
    public static let didChange = Notification.Name("MacUtilsAudioDidChange")
    
    private let lock = NSLock()
    
    public init() {
        registerListeners()
    }
    
    deinit {
        // CoreAudio listeners
    }
    
    private func registerListeners() {
        var defInAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defInAddr, DispatchQueue.main) { _, _ in
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
        
        var defOutAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defOutAddr, DispatchQueue.main) { _, _ in
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
    
    // MARK: - Default Device IDs
    
    public func defaultInputDeviceID() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }
    
    public func defaultOutputDeviceID() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }
    
    // MARK: - Mute Control
    
    public func isInputMuted() -> Bool {
        let devID = defaultInputDeviceID()
        guard devID != 0 else { return false }
        
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(devID, &muteAddr) {
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(devID, &muteAddr, 0, nil, &size, &muted) == noErr {
                return muted != 0
            }
        }
        
        // Fallback: check if volume is 0
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(devID, &volAddr) {
            var vol: Float32 = 1.0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(devID, &volAddr, 0, nil, &size, &vol) == noErr {
                return vol <= 0.001
            }
        }
        
        return false
    }
    
    public func setInputMuted(_ muted: Bool) {
        let devID = defaultInputDeviceID()
        guard devID != 0 else { return }
        
        var muteVal: UInt32 = muted ? 1 : 0
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(devID, &muteAddr) {
            let size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectSetPropertyData(devID, &muteAddr, 0, nil, size, &muteVal)
        }
        
        // Also ensure volume is muted or restored
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(devID, &volAddr) {
            var targetVol: Float32 = muted ? 0.0 : 0.75
            let size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectSetPropertyData(devID, &volAddr, 0, nil, size, &targetVol)
        }
        
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    
    public func toggleInputMute() {
        setInputMuted(!isInputMuted())
    }
    
    // MARK: - Device Enumeration & Selection
    
    public func getDevices() -> (inputs: [AudioDeviceItem], outputs: [AudioDeviceItem]) {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return ([], [])
        }
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return ([], [])
        }
        
        let defIn = defaultInputDeviceID()
        let defOut = defaultOutputDeviceID()
        
        var inputs: [AudioDeviceItem] = []
        var outputs: [AudioDeviceItem] = []
        
        for devID in ids {
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let nameErr = AudioObjectGetPropertyData(devID, &nameAddr, 0, nil, &nameSize, &cfName)
            let name = (nameErr == noErr ? cfName?.takeRetainedValue() as String? : nil) ?? "Audio Device \(devID)"
            
            // Check output streams
            var outStreamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var outStreamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(devID, &outStreamAddr, 0, nil, &outStreamSize)
            let isOutput = outStreamSize > 0
            
            // Check input streams
            var inStreamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inStreamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(devID, &inStreamAddr, 0, nil, &inStreamSize)
            let isInput = inStreamSize > 0
            
            if isInput {
                inputs.append(AudioDeviceItem(
                    deviceID: devID,
                    name: name,
                    isInput: true,
                    isOutput: isOutput,
                    isDefaultInput: devID == defIn,
                    isDefaultOutput: devID == defOut
                ))
            }
            if isOutput {
                outputs.append(AudioDeviceItem(
                    deviceID: devID,
                    name: name,
                    isInput: isInput,
                    isOutput: true,
                    isDefaultInput: devID == defIn,
                    isDefaultOutput: devID == defOut
                ))
            }
        }
        
        return (inputs, outputs)
    }
    
    public func setDefaultOutputDevice(_ id: AudioDeviceID) {
        var devID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &devID)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    
    public func setDefaultInputDevice(_ id: AudioDeviceID) {
        var devID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &devID)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    
    // MARK: - Live Privacy Detection (Camera & Microphone in use)
    
    public func isAnyMicrophoneInUse() -> Bool {
        let (inputs, _) = getDevices()
        for dev in inputs {
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(dev.deviceID, &addr),
               AudioObjectGetPropertyData(dev.deviceID, &addr, 0, nil, &size, &isRunning) == noErr,
               isRunning != 0 {
                return true
            }
        }
        return false
    }
    
    public func isAnyCameraInUse() -> Bool {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return false
        }
        let count = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, dataSize, &dataUsed, &devices) == noErr else {
            return false
        }
        
        var runningProp = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        for deviceID in devices {
            if CMIOObjectHasProperty(deviceID, &runningProp) {
                var isRunning: UInt32 = 0
                var used: UInt32 = 0
                let size = UInt32(MemoryLayout<UInt32>.size)
                if CMIOObjectGetPropertyData(deviceID, &runningProp, 0, nil, size, &used, &isRunning) == noErr,
                   isRunning != 0 {
                    return true
                }
            }
        }
        return false
    }
}
