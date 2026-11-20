import Foundation
import AppKit
import CoreAudio

public struct AppAudioItem: Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let iconPath: String?
    public let leadPid: pid_t
    public let objectIDs: [AudioObjectID]
    public let isPlaying: Bool
    public let volume: Float   // 0.0 ... 1.0
    public let isMuted: Bool
    
    public var effectiveGain: Float {
        isMuted ? 0.0 : min(max(volume, 0.0), 1.0)
    }
    
    public var formattedVolume: String {
        isMuted ? "Muted" : "\(Int((volume * 100.0).rounded()))%"
    }
}

/// Manages per-application audio volume & mute using macOS 14.2+ Core Audio Process Taps.
/// Apps left at 100% unmuted incur zero tap overhead; taps are created on demand when an app
/// is attenuated or muted and automatically re-routed if the default output device changes.
public final class PerAppAudioManager: @unchecked Sendable {
    public static let shared = PerAppAudioManager()
    public static let didChange = Notification.Name("MacUtilsPerAppAudioDidChange")
    
    public static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }
    
    private struct AppAudioState {
        var volume: Float = 1.0
        var isMuted: Bool = false
        var effectiveGain: Float { isMuted ? 0.0 : min(max(volume, 0.0), 1.0) }
    }
    
    private let lock = NSLock()
    private var appStates: [String: AppAudioState] = [:]
    private var activeSessions: [String: AnyObject] = [:] // AppAudioTapSession on macOS 14.2+
    private var lastKnownObjectIDs: [String: [AudioObjectID]] = [:]
    
    public init() {
        NotificationCenter.default.addObserver(
            forName: AudioHardwareManager.didChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleOutputDeviceChanged()
        }
    }
    
    deinit {
        stopAll()
    }
    
    // MARK: - Enumeration
    
    public func listAudioApps() -> [AppAudioItem] {
        guard #available(macOS 14.2, *) else { return [] }
        
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else {
            return []
        }
        
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &objectIDs) == noErr else {
            return []
        }
        
        let myPid = ProcessInfo.processInfo.processIdentifier
        
        struct GroupBuilder {
            var name: String
            var iconPath: String?
            var leadPid: pid_t
            var objectIDs: [AudioObjectID]
            var isPlaying: Bool
            var isGUIApp: Bool
        }
        
        var groups: [String: GroupBuilder] = [:]
        var nameBuf = [CChar](repeating: 0, count: 128)
        
        for objID in objectIDs {
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(objID, &pidAddr, 0, nil, &pidSize, &pid) == noErr,
                  pid > 0, pid != myPid else { continue }
            
            var running: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectGetPropertyData(objID, &runAddr, 0, nil, &runSize, &running)
            let isPlaying = running != 0
            
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let fallbackName: String
            if let loc = runningApp?.localizedName, !loc.isEmpty {
                fallbackName = loc
            } else {
                let len = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
                if len > 0 {
                    fallbackName = String(decoding: nameBuf.prefix(Int(len)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                } else {
                    fallbackName = "Process \(pid)"
                }
            }
            
            let identity = ProcessIdentity.resolve(pid: pid, fallbackName: fallbackName)
            let isGUI = (runningApp?.activationPolicy == .regular) || (identity.iconPath?.hasSuffix(".app") == true)
            
            if var existing = groups[identity.key] {
                existing.objectIDs.append(objID)
                existing.isPlaying = existing.isPlaying || isPlaying
                existing.isGUIApp = existing.isGUIApp || isGUI
                if existing.iconPath == nil { existing.iconPath = identity.iconPath }
                groups[identity.key] = existing
            } else {
                groups[identity.key] = GroupBuilder(
                    name: identity.name,
                    iconPath: identity.iconPath,
                    leadPid: pid,
                    objectIDs: [objID],
                    isPlaying: isPlaying,
                    isGUIApp: isGUI
                )
            }
        }
        
        lock.lock()
        var items: [AppAudioItem] = []
        for (key, g) in groups {
            let state = appStates[key] ?? AppAudioState()
            let hasCustomState = state.isMuted || state.volume < 0.999
            // Show GUI apps, anything actively playing audio, or anything the user adjusted
            guard g.isGUIApp || g.isPlaying || hasCustomState else { continue }
            
            lastKnownObjectIDs[key] = g.objectIDs
            items.append(AppAudioItem(
                key: key,
                name: g.name,
                iconPath: g.iconPath,
                leadPid: g.leadPid,
                objectIDs: g.objectIDs,
                isPlaying: g.isPlaying,
                volume: state.volume,
                isMuted: state.isMuted
            ))
        }
        lock.unlock()
        
        // Sort: actively playing first, then adjusted apps, then alphabetical
        items.sort { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
            let lhsCustom = lhs.isMuted || lhs.volume < 0.999
            let rhsCustom = rhs.isMuted || rhs.volume < 0.999
            if lhsCustom != rhsCustom { return lhsCustom }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        
        return items
    }
    
    // MARK: - Volume & Mute Control
    
    public func setVolume(_ volume: Float, for appKey: String, objectIDs: [AudioObjectID]? = nil) {
        let clamped = min(max(volume, 0.0), 1.0)
        lock.lock()
        var state = appStates[appKey] ?? AppAudioState()
        state.volume = clamped
        if clamped > 0.001 && state.isMuted {
            state.isMuted = false
        }
        appStates[appKey] = state
        if let ids = objectIDs { lastKnownObjectIDs[appKey] = ids }
        let ids = lastKnownObjectIDs[appKey] ?? []
        lock.unlock()
        
        applyTapState(for: appKey, state: state, objectIDs: ids)
        notifyChanged()
    }
    
    public func setMuted(_ muted: Bool, for appKey: String, objectIDs: [AudioObjectID]? = nil) {
        lock.lock()
        var state = appStates[appKey] ?? AppAudioState()
        state.isMuted = muted
        appStates[appKey] = state
        if let ids = objectIDs { lastKnownObjectIDs[appKey] = ids }
        let ids = lastKnownObjectIDs[appKey] ?? []
        lock.unlock()
        
        applyTapState(for: appKey, state: state, objectIDs: ids)
        notifyChanged()
    }
    
    public func toggleMute(for appKey: String, objectIDs: [AudioObjectID]? = nil) {
        lock.lock()
        let currentlyMuted = appStates[appKey]?.isMuted ?? false
        lock.unlock()
        setMuted(!currentlyMuted, for: appKey, objectIDs: objectIDs)
    }
    
    public func resetAll() {
        lock.lock()
        let keys = Array(appStates.keys)
        appStates.removeAll()
        let sessions = activeSessions
        activeSessions.removeAll()
        lock.unlock()
        
        if #available(macOS 14.2, *) {
            for (_, obj) in sessions {
                (obj as? AppAudioTapSession)?.stop()
            }
        }
        if !keys.isEmpty {
            notifyChanged()
        }
    }
    
    public func stopAll() {
        lock.lock()
        let sessions = activeSessions
        activeSessions.removeAll()
        lock.unlock()
        
        if #available(macOS 14.2, *) {
            for (_, obj) in sessions {
                (obj as? AppAudioTapSession)?.stop()
            }
        }
    }
    
    // MARK: - Internal Tap Lifecycle
    
    private func applyTapState(for appKey: String, state: AppAudioState, objectIDs: [AudioObjectID]) {
        guard #available(macOS 14.2, *) else { return }
        let gain = state.effectiveGain
        
        // At 100% unmuted, tear down the tap completely so there is zero overhead
        if gain >= 0.999 {
            lock.lock()
            let existing = activeSessions.removeValue(forKey: appKey) as? AppAudioTapSession
            lock.unlock()
            existing?.stop()
            return
        }
        
        guard !objectIDs.isEmpty else { return }
        
        lock.lock()
        if let existing = activeSessions[appKey] as? AppAudioTapSession,
           existing.objectIDs == objectIDs {
            existing.setGain(gain)
            lock.unlock()
            return
        }
        let oldSession = activeSessions.removeValue(forKey: appKey) as? AppAudioTapSession
        lock.unlock()
        
        oldSession?.stop()
        
        guard let outputUID = defaultOutputDeviceUID() else { return }
        if let session = AppAudioTapSession(appKey: appKey, objectIDs: objectIDs, outputDeviceUID: outputUID, initialGain: gain) {
            lock.lock()
            activeSessions[appKey] = session
            lock.unlock()
        }
    }
    
    private func handleOutputDeviceChanged() {
        guard #available(macOS 14.2, *) else { return }
        lock.lock()
        let statesSnapshot = appStates
        let idsSnapshot = lastKnownObjectIDs
        let oldSessions = activeSessions
        activeSessions.removeAll()
        lock.unlock()
        
        for (_, obj) in oldSessions {
            (obj as? AppAudioTapSession)?.stop()
        }
        
        guard let outputUID = defaultOutputDeviceUID() else { return }
        for (key, state) in statesSnapshot {
            let gain = state.effectiveGain
            guard gain < 0.999, let ids = idsSnapshot[key], !ids.isEmpty else { continue }
            if let session = AppAudioTapSession(appKey: key, objectIDs: ids, outputDeviceUID: outputUID, initialGain: gain) {
                lock.lock()
                activeSessions[key] = session
                lock.unlock()
            }
        }
    }
    
    private func defaultOutputDeviceUID() -> String? {
        let devID = AudioHardwareManager.shared.defaultOutputDeviceID()
        guard devID != 0 else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, &cfUID) == noErr,
              let uid = cfUID?.takeRetainedValue() as String? else {
            return nil
        }
        return uid
    }
    
    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
}

// MARK: - Real-Time Audio Tap Session (macOS 14.2+)

@available(macOS 14.2, *)
private final class GainState: @unchecked Sendable {
    var targetGain: Float
    var currentGain: Float
    init(_ gain: Float) {
        self.targetGain = gain
        self.currentGain = gain
    }
}

@available(macOS 14.2, *)
private final class AppAudioTapSession: @unchecked Sendable {
    let appKey: String
    let objectIDs: [AudioObjectID]
    private let gainState: GainState
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    
    init?(appKey: String, objectIDs: [AudioObjectID], outputDeviceUID: String, initialGain: Float) {
        self.appKey = appKey
        self.objectIDs = objectIDs
        self.gainState = GainState(initialGain)
        
        let desc = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true
        desc.isExclusive = false
        
        var createdTapID: AudioObjectID = kAudioObjectUnknown
        guard AudioHardwareCreateProcessTap(desc, &createdTapID) == noErr,
              createdTapID != kAudioObjectUnknown else {
            return nil
        }
        self.tapID = createdTapID
        
        let aggDict: [String: Any] = [
            kAudioAggregateDeviceUIDKey: "com.macutils.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceNameKey: "MacUtils Tap (\(appKey))",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: desc.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]
        
        var createdAggID: AudioDeviceID = kAudioObjectUnknown
        guard AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &createdAggID) == noErr,
              createdAggID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(createdTapID)
            self.tapID = kAudioObjectUnknown
            return nil
        }
        self.aggregateDeviceID = createdAggID
        
        let gainBox = self.gainState
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, createdAggID, nil) { _, inInputData, _, outOutputData, _ in
            let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let outList = UnsafeMutableAudioBufferListPointer(outOutputData)
            
            let target = gainBox.targetGain
            let startGain = gainBox.currentGain
            
            // Zero output buffers first
            for outBuf in outList {
                if let ptr = outBuf.mData {
                    memset(ptr, 0, Int(outBuf.mDataByteSize))
                }
            }
            
            guard !inList.isEmpty, !outList.isEmpty else {
                gainBox.currentGain = target
                return
            }
            
            if inList.count == outList.count {
                // Matching buffer layout (both interleaved or both non-interleaved)
                for b in 0..<outList.count {
                    guard let inPtr = inList[b].mData?.assumingMemoryBound(to: Float32.self),
                          let outPtr = outList[b].mData?.assumingMemoryBound(to: Float32.self) else { continue }
                    let sampleCount = min(Int(inList[b].mDataByteSize), Int(outList[b].mDataByteSize)) / MemoryLayout<Float32>.size
                    guard sampleCount > 0 else { continue }
                    let step = (target - startGain) / Float(sampleCount)
                    var g = startGain
                    for i in 0..<sampleCount {
                        g += step
                        outPtr[i] = inPtr[i] * g
                    }
                }
            } else if inList.count == 1 && outList.count >= 2 {
                // Input interleaved stereo -> Output non-interleaved
                if let inPtr = inList[0].mData?.assumingMemoryBound(to: Float32.self) {
                    let inChannels = max(1, Int(inList[0].mNumberChannels))
                    let inFrames = (Int(inList[0].mDataByteSize) / MemoryLayout<Float32>.size) / inChannels
                    for c in 0..<min(inChannels, outList.count) {
                        guard let outPtr = outList[c].mData?.assumingMemoryBound(to: Float32.self) else { continue }
                        let outFrames = Int(outList[c].mDataByteSize) / MemoryLayout<Float32>.size
                        let frames = min(inFrames, outFrames)
                        guard frames > 0 else { continue }
                        let step = (target - startGain) / Float(frames)
                        var g = startGain
                        for f in 0..<frames {
                            g += step
                            outPtr[f] = inPtr[f * inChannels + c] * g
                        }
                    }
                }
            } else if inList.count >= 2 && outList.count == 1 {
                // Input non-interleaved -> Output interleaved
                if let outPtr = outList[0].mData?.assumingMemoryBound(to: Float32.self) {
                    let outChannels = max(1, Int(outList[0].mNumberChannels))
                    let outFrames = (Int(outList[0].mDataByteSize) / MemoryLayout<Float32>.size) / outChannels
                    for c in 0..<min(inList.count, outChannels) {
                        guard let inPtr = inList[c].mData?.assumingMemoryBound(to: Float32.self) else { continue }
                        let inFrames = Int(inList[c].mDataByteSize) / MemoryLayout<Float32>.size
                        let frames = min(inFrames, outFrames)
                        guard frames > 0 else { continue }
                        let step = (target - startGain) / Float(frames)
                        var g = startGain
                        for f in 0..<frames {
                            g += step
                            outPtr[f * outChannels + c] = inPtr[f] * g
                        }
                    }
                }
            }
            
            gainBox.currentGain = target
        }
        
        guard status == noErr, let validProcID = procID else {
            stop()
            return nil
        }
        self.ioProcID = validProcID
        
        if AudioDeviceStart(createdAggID, validProcID) != noErr {
            stop()
            return nil
        }
    }
    
    deinit {
        stop()
    }
    
    func setGain(_ gain: Float) {
        gainState.targetGain = min(max(gain, 0.0), 1.0)
    }
    
    func stop() {
        if let procID = ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            ioProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }
}
