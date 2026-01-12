import SwiftUI
import AVFoundation
import Combine

/// オーディオデバイス情報を表す構造体
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let isInput: Bool
    let isBuiltInSpeaker: Bool
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// オーディオパススルーのコアロジックを管理するモデル
/// AVAudioEngineを使用してマイク入力をリアルタイムで出力に転送
@MainActor
class AudioModel: ObservableObject {
    // MARK: - Published Properties
    
    /// パススルーが有効かどうか
    @Published var isPassthroughEnabled: Bool = false {
        didSet {
            if isPassthroughEnabled {
                startPassthrough()
            } else {
                stopPassthrough()
            }
        }
    }
    
    /// マイクゲイン（0.0 〜 2.0）
    @Published var volume: Float = 1.0 {
        didSet {
            mixerNode.outputVolume = volume
        }
    }
    
    /// 内蔵スピーカー警告フラグ
    @Published var showBuiltInSpeakerWarning: Bool = false
    
    /// 利用可能な入力デバイス
    @Published var inputDevices: [AudioDevice] = []
    
    /// 利用可能な出力デバイス
    @Published var outputDevices: [AudioDevice] = []
    
    /// 選択中の入力デバイス
    @Published var selectedInputDevice: AudioDevice? {
        didSet {
            if isPassthroughEnabled {
                restartPassthrough()
            }
        }
    }
    
    /// 選択中の出力デバイス
    @Published var selectedOutputDevice: AudioDevice? {
        didSet {
            checkBuiltInSpeakerWarning()
            if isPassthroughEnabled {
                restartPassthrough()
            }
        }
    }
    
    /// 入力レベル（0.0 〜 1.0）- デバッグ用
    @Published var inputLevel: Float = 0.0
    
    /// デバッグモード（レベルメーター表示）
    @Published var isDebugMode: Bool = false {
        didSet {
            if isDebugMode && isPassthroughEnabled {
                updateLatencyMeasurement()
            }
        }
    }
    
    /// 推定レイテンシー（ミリ秒）
    @Published var latencyMs: Double = 0.0
    
    /// ノイズゲートが有効か
    @Published var isNoiseGateEnabled: Bool = false {
        didSet {
            if isPassthroughEnabled {
                restartPassthrough()
            }
        }
    }
    
    /// ノイズゲートの閾値（0.0〜0.1）- これ以下の音量をミュート
    @Published var noiseGateThreshold: Float = 0.02
    
    // MARK: - Private Properties
    
    private var audioEngine: AVAudioEngine
    private var mixerNode: AVAudioMixerNode
    private var deviceManager: AudioDeviceManager
    private var cancellables = Set<AnyCancellable>()
    
    /// 低レイテンシー用のバッファサイズ（128フレーム ≈ 2.9ms @ 44.1kHz）
    private let preferredBufferSize: UInt32 = 128
    
    /// High-Pass Filter（80Hz以下をカット）
    private var highPassFilter: AVAudioUnitEQ!
    
    /// ノイズゲート用のスムージング係数
    private var gateSmoothing: Float = 1.0
    
    // MARK: - Initialization
    
    init() {
        self.audioEngine = AVAudioEngine()
        self.mixerNode = AVAudioMixerNode()
        self.deviceManager = AudioDeviceManager()
        
        setupAudioEngine()
        loadDevices()
        setupNotifications()
        requestMicrophonePermission()
    }
    
    /// マイク権限をリクエスト
    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            print("マイク権限: 未決定 - リクエスト中...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted {
                        print("マイク権限: 承認されました")
                    } else {
                        print("マイク権限: 拒否されました")
                    }
                }
            }
        case .restricted:
            print("マイク権限: 制限されています")
        case .denied:
            print("マイク権限: 拒否されています - システム環境設定で許可してください")
        case .authorized:
            print("マイク権限: 承認済み")
        @unknown default:
            print("マイク権限: 不明な状態")
        }
    }
    
    deinit {
        // deinitはnonisolated contextなので、直接audioEngineを停止
        audioEngine.stop()
    }
    
    // MARK: - Setup
    
    private func setupAudioEngine() {
        // ミキサーノードをエンジンに接続
        audioEngine.attach(mixerNode)
        
        // High-Pass Filterを作成（80Hz以下をカット）
        highPassFilter = AVAudioUnitEQ(numberOfBands: 1)
        highPassFilter.bands[0].filterType = .highPass
        highPassFilter.bands[0].frequency = 80.0
        highPassFilter.bands[0].bypass = false
        audioEngine.attach(highPassFilter)
    }
    
    /// オーディオエンジンのノード接続を構築
    private func connectNodes() {
        // 既存の接続をリセット
        audioEngine.disconnectNodeInput(mixerNode)
        audioEngine.disconnectNodeInput(highPassFilter)
        audioEngine.disconnectNodeInput(audioEngine.mainMixerNode)
        
        // 入力ノードのフォーマットを取得
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        
        // フォーマットが有効かチェック
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("無効な入力フォーマット: sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount)")
            return
        }
        
        print("入力フォーマット: \(inputFormat)")
        
        if isNoiseGateEnabled {
            // ノイズゲート有効: 入力 → HPF → ミキサー → 出力
            audioEngine.connect(audioEngine.inputNode, to: highPassFilter, format: inputFormat)
            audioEngine.connect(highPassFilter, to: mixerNode, format: inputFormat)
            audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: inputFormat)
            
            // ノイズゲート処理用のtapをインストール
            installNoiseGateTap(format: inputFormat)
            print("ノイズゲート: 有効 (閾値: \(noiseGateThreshold))")
        } else {
            // ノイズゲート無効: 入力 → ミキサー → 出力
            audioEngine.connect(audioEngine.inputNode, to: mixerNode, format: inputFormat)
            audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: inputFormat)
            print("ノイズゲート: 無効")
        }
        
        // デバッグモードが有効ならレベルメーターをインストール
        if isDebugMode {
            installLevelMeter()
        }
    }
    
    /// ノイズゲート処理用のtapをインストール
    private func installNoiseGateTap(format: AVAudioFormat) {
        let bufferSize: AVAudioFrameCount = 256
        
        highPassFilter.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.applyNoiseGate(to: buffer)
        }
    }
    
    /// ノイズゲートを適用（閾値以下の音をフェードアウト）
    private func applyNoiseGate(to buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let threshold = noiseGateThreshold
        
        // RMSを計算
        var totalPower: Float = 0.0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                totalPower += samples[frame] * samples[frame]
            }
        }
        let rms = sqrt(totalPower / Float(frameLength * channelCount))
        
        // ゲートの開閉をスムーズに
        let targetGain: Float = rms > threshold ? 1.0 : 0.0
        let smoothingFactor: Float = 0.1
        gateSmoothing = gateSmoothing + smoothingFactor * (targetGain - gateSmoothing)
        
        // ゲインを適用
        if gateSmoothing < 0.99 {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameLength {
                    samples[frame] *= gateSmoothing
                }
            }
        }
    }
    
    /// ノイズゲートのtapを削除
    private func removeNoiseGateTap() {
        highPassFilter.removeTap(onBus: 0)
    }
    
    /// オーディオレベルメーターをインストール
    private func installLevelMeter() {
        // 既存のtapを削除
        removeLevelMeter()
        
        // mixerNodeの出力フォーマットを取得
        let format = mixerNode.outputFormat(forBus: 0)
        print("レベルメーターインストール: format=\(format)")
        
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            print("レベルメーター: 無効なフォーマット")
            return
        }
        
        let bufferSize: AVAudioFrameCount = 256
        
        // mixerNodeにタップをインストール
        mixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData else {
                print("レベルメーター: channelDataがnull")
                return
            }
            
            let channelCount = Int(buffer.format.channelCount)
            let frameLength = Int(buffer.frameLength)
            
            guard frameLength > 0 && channelCount > 0 else { return }
            
            var totalPower: Float = 0.0
            
            // 全チャンネルのRMSを計算
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                var channelPower: Float = 0.0
                
                for frame in 0..<frameLength {
                    let sample = samples[frame]
                    channelPower += sample * sample
                }
                
                totalPower += channelPower
            }
            
            let rms = sqrt(totalPower / Float(frameLength * channelCount))
            // RMSをリニアスケール（0-1）に変換（ゲインを調整）
            let level = min(1.0, max(0.0, rms * 10.0))
            
            Task { @MainActor [weak self] in
                self?.inputLevel = level
            }
        }
        
        print("レベルメーターインストール完了")
    }
    
    /// オーディオレベルメーターを削除
    private func removeLevelMeter() {
        mixerNode.removeTap(onBus: 0)
    }
    
    private func loadDevices() {
        inputDevices = deviceManager.getInputDevices()
        outputDevices = deviceManager.getOutputDevices()
        
        // デフォルトデバイスを選択
        if selectedInputDevice == nil {
            selectedInputDevice = deviceManager.getDefaultInputDevice()
        }
        if selectedOutputDevice == nil {
            selectedOutputDevice = deviceManager.getDefaultOutputDevice()
        }
        
        checkBuiltInSpeakerWarning()
    }
    
    private func setupNotifications() {
        // オーディオ設定変更の通知を監視
        NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleConfigurationChange()
                }
            }
            .store(in: &cancellables)
        
        // デバイス変更の監視
        deviceManager.startDeviceChangeListener { [weak self] in
            Task { @MainActor in
                self?.loadDevices()
            }
        }
    }
    
    // MARK: - Passthrough Control
    
    private func startPassthrough() {
        print("=== startPassthrough 開始 ===")
        print("selectedOutputDevice: \(selectedOutputDevice?.name ?? "nil")")
        print("isBuiltInSpeaker: \(selectedOutputDevice?.isBuiltInSpeaker ?? false)")
        print("showBuiltInSpeakerWarning: \(showBuiltInSpeakerWarning)")
        
        // マイク権限チェック
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("マイク権限状態: \(authStatus.rawValue)")
        if authStatus != .authorized {
            print("マイク権限がありません")
            requestMicrophonePermission()
            isPassthroughEnabled = false
            return
        }
        
        // 内蔵スピーカーの場合は起動しない
        if selectedOutputDevice?.isBuiltInSpeaker == true {
            print("内蔵スピーカーのため起動をキャンセル")
            showBuiltInSpeakerWarning = true
            isPassthroughEnabled = false
            return
        }
        
        do {
            // エンジンを再構成
            reconfigureEngine()
            
            // エンジン開始
            try audioEngine.start()
            print("パススルー開始成功")
            
            // レイテンシー計測
            if isDebugMode {
                updateLatencyMeasurement()
            }
        } catch {
            print("オーディオエンジン起動エラー: \(error)")
            isPassthroughEnabled = false
        }
    }
    
    private func stopPassthrough() {
        // tapを削除
        removeLevelMeter()
        if isNoiseGateEnabled {
            removeNoiseGateTap()
        }
        audioEngine.stop()
        // 接続をリセット
        audioEngine.disconnectNodeInput(mixerNode)
        audioEngine.disconnectNodeInput(highPassFilter)
        audioEngine.disconnectNodeInput(audioEngine.mainMixerNode)
        // レベルをリセット
        inputLevel = 0.0
        latencyMs = 0.0
        gateSmoothing = 1.0
        print("パススルー停止")
    }
    
    private func restartPassthrough() {
        stopPassthrough()
        
        // 最小限の待機で再起動
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.startPassthrough()
        }
    }
    
    private func reconfigureEngine() {
        print("エンジン再構成開始...")
        
        // 既存のエンジンを停止
        audioEngine.stop()
        
        // システムのデフォルトデバイスを変更
        if let inputDevice = selectedInputDevice {
            print("システムデフォルト入力設定: \(inputDevice.name) (ID: \(inputDevice.id))")
            setSystemDefaultInputDevice(inputDevice.id)
            setDeviceBufferSize(inputDevice.id, frameSize: preferredBufferSize)
        }
        
        if let outputDevice = selectedOutputDevice {
            print("システムデフォルト出力設定: \(outputDevice.name) (ID: \(outputDevice.id))")
            setSystemDefaultOutputDevice(outputDevice.id)
            setDeviceBufferSize(outputDevice.id, frameSize: preferredBufferSize)
        }
        
        // 新しいエンジンを作成
        audioEngine = AVAudioEngine()
        mixerNode = AVAudioMixerNode()
        
        // ミキサーノードをアタッチ
        audioEngine.attach(mixerNode)
        
        // High-Pass Filterを再作成
        highPassFilter = AVAudioUnitEQ(numberOfBands: 1)
        highPassFilter.bands[0].filterType = .highPass
        highPassFilter.bands[0].frequency = 80.0
        highPassFilter.bands[0].bypass = false
        audioEngine.attach(highPassFilter)
        
        // inputNode/outputNodeにアクセスしてAudioUnitを初期化
        _ = audioEngine.inputNode
        _ = audioEngine.outputNode
        
        // ノード接続を構築
        connectNodes()
        
        // ミキサーのボリュームを設定
        mixerNode.outputVolume = volume
        
        print("エンジン再構成完了")
    }
    
    /// デバイスのバッファサイズを設定（低レイテンシー化）
    private func setDeviceBufferSize(_ deviceID: AudioDeviceID, frameSize: UInt32) {
        var frameSize = frameSize
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &frameSize
        )
        
        if status == noErr {
            print("バッファサイズ設定成功: \(frameSize)フレーム")
        } else {
            print("バッファサイズ設定エラー: \(status)")
        }
    }
    
    /// システムのデフォルト入力デバイスを設定
    private func setSystemDefaultInputDevice(_ deviceID: AudioDeviceID) {
        var deviceID = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        
        if status != noErr {
            print("システム入力デバイス設定エラー: \(status)")
        } else {
            print("システム入力デバイス設定成功")
        }
    }
    
    /// システムのデフォルト出力デバイスを設定
    private func setSystemDefaultOutputDevice(_ deviceID: AudioDeviceID) {
        var deviceID = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        
        if status != noErr {
            print("システム出力デバイス設定エラー: \(status)")
        } else {
            print("システム出力デバイス設定成功")
        }
    }
    
    private func handleConfigurationChange() {
        if isPassthroughEnabled {
            restartPassthrough()
        }
        loadDevices()
    }
    
    // MARK: - Safety Check
    
    /// レイテンシーを計測・更新
    private func updateLatencyMeasurement() {
        let inputNode = audioEngine.inputNode
        
        // サンプルレートを取得
        let format = inputNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        
        guard sampleRate > 0 else {
            print("レイテンシー計測: 無効なサンプルレート")
            return
        }
        
        // CoreAudioからバッファサイズを取得
        var bufferFrameSize: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        // 入力デバイスのバッファサイズを取得
        if let inputDeviceID = selectedInputDevice?.id {
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyBufferFrameSize,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            AudioObjectGetPropertyData(
                inputDeviceID,
                &propertyAddress,
                0,
                nil,
                &propertySize,
                &bufferFrameSize
            )
        }
        
        // デフォルト値（256フレーム）
        if bufferFrameSize == 0 {
            bufferFrameSize = 256
        }
        
        // レイテンシー計算: 入力バッファ + 出力バッファ（往復）
        // 実際のレイテンシー = バッファサイズ * 2 / サンプルレート * 1000 (ms)
        let bufferLatency = Double(bufferFrameSize) * 2.0 / sampleRate * 1000.0
        
        // 追加のシステム遅延（約1-2ms）を加算
        latencyMs = bufferLatency + 1.5
        
        print("レイテンシー計測: bufferSize=\(bufferFrameSize), sampleRate=\(sampleRate), latency=\(String(format: "%.1f", latencyMs))ms")
    }
    
    private func checkBuiltInSpeakerWarning() {
        if selectedOutputDevice?.isBuiltInSpeaker == true {
            showBuiltInSpeakerWarning = true
            if isPassthroughEnabled {
                isPassthroughEnabled = false
            }
        } else {
            showBuiltInSpeakerWarning = false
        }
    }
    
}
