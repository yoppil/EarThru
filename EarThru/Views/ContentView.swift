import SwiftUI

/// メニューバーポップアップのメインビュー
struct ContentView: View {
    @ObservedObject var audioModel: AudioModel
    
    /// 入力レベルに応じた色
    private var levelColor: Color {
        let level = audioModel.inputLevel
        if level < 0.3 {
            return .green
        } else if level < 0.7 {
            return .yellow
        } else {
            return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Image(systemName: "ear.fill")
                    .foregroundColor(.accentColor)
                Text("EarThru")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // 内蔵スピーカー警告
            if audioModel.showBuiltInSpeakerWarning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("内蔵スピーカーではハウリングの恐れがあります")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            // パススルー ON/OFF トグル
            Toggle(isOn: $audioModel.isPassthroughEnabled) {
                HStack {
                    Image(systemName: audioModel.isPassthroughEnabled ? "mic.fill" : "mic.slash")
                        .foregroundColor(audioModel.isPassthroughEnabled ? .green : .secondary)
                    Text("パススルー")
                }
            }
            .toggleStyle(.switch)
            .disabled(audioModel.showBuiltInSpeakerWarning)
            
            Divider()
            
            // 音量スライダー
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("ゲイン: \(Int(audioModel.volume * 100))%")
                        .font(.caption)
                }
                
                Slider(value: $audioModel.volume, in: 0...2, step: 0.1)
            }
            
            Divider()
            
            // 入力デバイス選択
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "mic")
                    Text("入力デバイス")
                        .font(.caption)
                }
                
                Picker("", selection: $audioModel.selectedInputDevice) {
                    ForEach(audioModel.inputDevices) { device in
                        Text(device.name).tag(device as AudioDevice?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            
            // 出力デバイス選択
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "headphones")
                    Text("出力デバイス")
                        .font(.caption)
                }
                
                Picker("", selection: $audioModel.selectedOutputDevice) {
                    ForEach(audioModel.outputDevices) { device in
                        HStack {
                            Text(device.name)
                            if device.isBuiltInSpeaker {
                                Image(systemName: "exclamationmark.triangle")
                            }
                        }
                        .tag(device as AudioDevice?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            
            Divider()
            
            // デバッグモード
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $audioModel.isDebugMode) {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(audioModel.isDebugMode ? .blue : .secondary)
                        Text("デバッグモード")
                            .font(.caption)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: audioModel.isDebugMode) { _, newValue in
                    // デバッグモード切り替え時にパススルーを再起動
                    if audioModel.isPassthroughEnabled {
                        audioModel.isPassthroughEnabled = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            audioModel.isPassthroughEnabled = true
                        }
                    }
                }
                
                // 入力レベルメーター
                if audioModel.isDebugMode {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "mic.fill")
                                .foregroundColor(levelColor)
                            Text("入力レベル")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", audioModel.inputLevel * 100))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        
                        // レベルバー
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.2))
                                
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(levelColor)
                                    .frame(width: geometry.size.width * CGFloat(audioModel.inputLevel))
                                    .animation(.linear(duration: 0.05), value: audioModel.inputLevel)
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            
            Divider()
            
            // Quit ボタン
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text("終了")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .padding()
        .frame(width: 280)
    }
}

#Preview {
    ContentView(audioModel: AudioModel())
}
