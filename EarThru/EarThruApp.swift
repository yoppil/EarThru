import SwiftUI

/// EarThru for Mac - メニューバー常駐型オーディオパススルーアプリ
@main
struct EarThruApp: App {
    @StateObject private var audioModel = AudioModel()
    
    var body: some Scene {
        // MenuBarExtraを使用してメニューバーに常駐
        MenuBarExtra {
            ContentView(audioModel: audioModel)
        } label: {
            // メニューバーアイコン
            Image(systemName: audioModel.isPassthroughEnabled ? "ear.fill" : "ear")
        }
        .menuBarExtraStyle(.window)
    }
}
