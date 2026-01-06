import Foundation
import CoreAudio

/// オーディオデバイスの列挙と管理を行うマネージャークラス
class AudioDeviceManager {
    
    // MARK: - Device Enumeration
    
    /// 利用可能な入力デバイス（マイク）を取得
    func getInputDevices() -> [AudioDevice] {
        return getDevices(isInput: true)
    }
    
    /// 利用可能な出力デバイス（スピーカー/ヘッドホン）を取得
    func getOutputDevices() -> [AudioDevice] {
        return getDevices(isInput: false)
    }
    
    /// デフォルトの入力デバイスを取得
    func getDefaultInputDevice() -> AudioDevice? {
        let deviceID = getDefaultDeviceID(isInput: true)
        guard deviceID != kAudioObjectUnknown else { return nil }
        
        let name = getDeviceName(deviceID)
        let isBuiltIn = isBuiltInDevice(deviceID)
        return AudioDevice(id: deviceID, name: name, isInput: true, isBuiltInSpeaker: false)
    }
    
    /// デフォルトの出力デバイスを取得
    func getDefaultOutputDevice() -> AudioDevice? {
        let deviceID = getDefaultDeviceID(isInput: false)
        guard deviceID != kAudioObjectUnknown else { return nil }
        
        let name = getDeviceName(deviceID)
        let isBuiltIn = isBuiltInSpeaker(deviceID)
        return AudioDevice(id: deviceID, name: name, isInput: false, isBuiltInSpeaker: isBuiltIn)
    }
    
    // MARK: - Device Change Listener
    
    private var deviceChangeCallback: (() -> Void)?
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    
    /// デバイス変更リスナーを開始
    func startDeviceChangeListener(callback: @escaping () -> Void) {
        deviceChangeCallback = callback
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        listenerBlock = { [weak self] _, _ in
            self?.deviceChangeCallback?()
        }
        
        if let block = listenerBlock {
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                DispatchQueue.main,
                block
            )
        }
    }
    
    /// デバイス変更リスナーを停止
    func stopDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if let block = listenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                DispatchQueue.main,
                block
            )
        }
        
        listenerBlock = nil
        deviceChangeCallback = nil
    }
    
    // MARK: - Private Methods
    
    private func getDevices(isInput: Bool) -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else { return [] }
        
        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            // 入力/出力のストリーム数をチェック
            let streamCount = getStreamCount(deviceID, isInput: isInput)
            guard streamCount > 0 else { return nil }
            
            let name = getDeviceName(deviceID)
            let isBuiltIn = isInput ? false : isBuiltInSpeaker(deviceID)
            
            return AudioDevice(
                id: deviceID,
                name: name,
                isInput: isInput,
                isBuiltInSpeaker: isBuiltIn
            )
        }
    }
    
    private func getDefaultDeviceID(isInput: Bool) -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        return status == noErr ? deviceID : kAudioObjectUnknown
    }
    
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )
        
        return status == noErr ? name as String : "Unknown Device"
    }
    
    private func getStreamCount(_ deviceID: AudioDeviceID, isInput: Bool) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: isInput ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return 0 }
        
        return Int(dataSize) / MemoryLayout<AudioStreamID>.size
    }
    
    private func isBuiltInDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &transportType
        )
        
        return status == noErr && transportType == kAudioDeviceTransportTypeBuiltIn
    }
    
    /// 内蔵スピーカーかどうかを判定（ハウリング防止用）
    private func isBuiltInSpeaker(_ deviceID: AudioDeviceID) -> Bool {
        // トランスポートタイプで内蔵デバイスを判定
        guard isBuiltInDevice(deviceID) else { return false }
        
        // デバイス名でスピーカーを判定
        let name = getDeviceName(deviceID).lowercased()
        return name.contains("speaker") || 
               name.contains("スピーカー") || 
               name.contains("内蔵") ||
               name.contains("built-in")
    }
}
