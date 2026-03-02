# EqualizerApp

SwiftUI-based menu bar equalizer targeting macOS 15+ on Apple Silicon.

## Settings Persistence
- EQ band layout, gains, filter types, and per-band bypass states automatically persist across launches.
- Device selections, bypass toggle, and gain trims continue to restore from the previous session.

## Requirements
- macOS 15 Sequoia or newer
- Apple Silicon Mac
- Xcode 16+ / Swift 6 toolchain

## Running
1. Open the Swift Package (`Package.swift`) directly in Xcode 16+ (File ▸ Open Package…) **or** run it from Terminal:
   ```bash
   cd EqualizerApp
   swift run
   ```
2. Grant microphone/audio permissions when prompted.
3. Look for the slider icon in the menu bar to open the popover.

## BlackHole (Optional)
Install the [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) loopback device if you want to route system audio through the equalizer.

## Roadmap
See `ToDo.md` in the repository root for the incremental plan.
