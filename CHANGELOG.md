# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-01-08

### Added
- ノイズ除去（Voice Isolation）機能を追加
  - AVAudioEngine Voice Processing 使用
  - 環境ノイズを抑制し、人の声をクリアに
  - ON/OFFトグルで切り替え可能

## [1.0.0-beta.1] - 2026-01-06

### Added
- 初回ベータリリース
- リアルタイムオーディオパススルー機能（AVAudioEngine使用）
- マイクゲイン調整（0-200%）
- 入力/出力デバイス選択
- 内蔵スピーカー使用時のハウリング警告と自動保護
- デバッグモード（入力レベルメーター表示）
- メニューバー常駐（LSUIElement）
- App Sandbox対応

### Technical Details
- 低遅延バッファ設定（256フレーム ≈ 5.8ms @ 44.1kHz）
- CoreAudioによるデバイス列挙と切り替え
- macOS 13.0 (Ventura) 以上対応
