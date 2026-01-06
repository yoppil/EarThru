# EarThru for Mac

外音取り込み（パススルー）専用の macOS メニューバーアプリ。

マイクで拾った音をリアルタイムでイヤホンに流し、周囲の音を聞きながら作業できます。

## 機能

- 🎧 **リアルタイムパススルー**: AVAudioEngine による低遅延オーディオ転送
- 🎚️ **ゲイン調整**: 0% 〜 200% のマイク音量調整
- 🔊 **デバイス選択**: 入力/出力デバイスを自由に選択
- ⚠️ **安全対策**: 内蔵スピーカー選択時のハウリング警告

## 動作環境

- macOS 13.0 (Ventura) 以上
- Xcode 15 以上

## セットアップ

### 1. Xcodeプロジェクトの作成

```
Xcode → File → New → Project → macOS → App
```

設定:
- **Product Name**: `EarThru`
- **Team**: あなたのチーム
- **Organization Identifier**: 任意（例: `com.yourname`）
- **Interface**: SwiftUI
- **Language**: Swift
- **Include Tests**: チェックなし

### 2. ソースファイルの追加

プロジェクト作成後、以下のファイルを追加:

1. 既存の `ContentView.swift` を削除
2. `OpenEar/` フォルダ内のファイルをXcodeプロジェクトにドラッグ＆ドロップ
3. グループ構造を維持してコピー

### 3. Signing & Capabilities の設定

Xcodeで：

1. プロジェクトナビゲータで「EarThru」を選択
2. ターゲット「EarThru」を選択
3. 「Signing & Capabilities」タブを開く
4. 「+ Capability」をクリック
5. **App Sandbox** を追加（既にある場合はスキップ）
6. App Sandbox の設定で **Hardware → Audio Input** にチェック

### 4. Info.plist の確認

`Info.plist` に以下が含まれていることを確認:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>EarThruは外音取り込みのためにマイクを使用します。</string>

<key>LSUIElement</key>
<true/>
```

### 5. ビルドと実行

1. ビルドターゲットを **My Mac** に設定
2. `Cmd + R` で実行
3. メニューバーに耳のアイコンが表示される
4. 初回起動時にマイク許可ダイアログが表示されるので「OK」をクリック

## 使い方

1. **ヘッドホン/イヤホンを接続**（必須：スピーカーではハウリングの恐れ）
2. メニューバーのアイコンをクリック
3. 出力デバイスでイヤホン/ヘッドホンを選択
4. 「パススルー」をONに切り替え
5. マイクが拾った音がイヤホンから聞こえる

## ファイル構成

```
OpenEar/
├── EarThruApp.swift          # エントリーポイント（MenuBarExtra）
├── Models/
│   ├── AudioModel.swift      # AVAudioEngineパススルーロジック
│   └── AudioDeviceManager.swift  # CoreAudioデバイス列挙
├── Views/
│   └── ContentView.swift     # メニューバーUI
├── Info.plist                # 権限設定
└── EarThru.entitlements      # サンドボックス設定
```

## 技術詳細

### 低遅延化

- バッファサイズ: 256フレーム（@ 44.1kHz ≈ 5.8ms）
- AVAudioEngineの直接接続による最小限の処理遅延

### 安全対策

- 内蔵スピーカー検出時に自動警告
- 内蔵スピーカー選択時はパススルー無効化
- TransportType + デバイス名でスピーカーを判定

## ライセンス

MIT License
