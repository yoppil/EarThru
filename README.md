# EarThru

**Real-time Audio Passthrough for macOS**

Low-latency audio passthrough app that routes microphone input directly to your headphones.

## Features

- **Real-time Passthrough** - Ultra-low latency (~6ms)
- **Voice Isolation** - Reduces background noise for clearer voice
- **Gain Control** - Adjustable microphone gain (0-200%)
- **Device Selection** - Choose input/output audio devices
- **Feedback Protection** - Auto-protection when using built-in speakers

## Requirements

| Item | Requirement |
|------|-------------|
| OS | macOS 13.0 (Ventura) or later |
| Build | Xcode 15+ |
| Architecture | Apple Silicon / Intel |

## Installation

### Download from Releases

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the DMG and drag `EarThru.app` to `/Applications`
3. Grant microphone access on first launch

### Build from Source

```bash
git clone https://github.com/yourname/earthru.git
cd earthru
open EarThru.xcodeproj
```

Build and run in Xcode (Cmd+R)

## Usage

1. Click the menu bar icon
2. Select input device (microphone) and output device (headphones)
3. Toggle **Passthrough** ON to start audio routing
4. Adjust gain as needed
5. Enable **Voice Isolation** to reduce background noise

> **Warning**: Always use headphones. Built-in speaker usage is automatically blocked to prevent feedback.

## License

[MIT License](LICENSE)
