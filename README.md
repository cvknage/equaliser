# Equaliser

A system-wide audio equalizer for macOS. Apply EQ to everything playing on your Mac—Spotify, YouTube, games, anything.

Lives in your menu bar. No dock icon, no clutter.

## What It Does

Equaliser sits between your system audio and your speakers or headphones, letting you shape the sound of everything on your Mac with up to 64-bands of parametric EQ.

**Use cases:**
- Boost bass on laptop speakers that lack low end
- Tame harsh treble on bright headphones
- Add presence to dialogue in movies
- Match the sound signature of your favorite headphones

## How It Works

Equaliser uses [BlackHole](https://existential.audio/blackhole/), a free virtual audio driver, to capture system audio. Your Mac sends audio to BlackHole, Equaliser processes it through the EQ, and outputs to your speakers or headphones.

```
Apps → BlackHole → Equaliser → Speakers/Headphones
```

## Getting Started

### 1. Install BlackHole

Download the free 2-channel version from [existential.audio/blackhole](https://existential.audio/blackhole/)

Or with Homebrew:
```
brew install blackhole-2ch
```

### 2. Get Equaliser

Download from [Releases](#), or build from source:
```
swift build -c release && ./bundle.sh
```

### 3. Set Up Audio Routing

1. Set your Mac's sound output to **BlackHole 2ch** (System Settings → Sound)
2. Open Equaliser from the menu bar
3. Choose **BlackHole 2ch** as input, your speakers as output
4. Click **Start**

That's it. Adjust the EQ to taste.

## Features

- **Up to 64-bands of parametric EQ** with adjustable frequency, gain, and bandwidth per band
- **Compare Mode** — A/B comparison between your EQ curve and flat response at matched volume
- **Real-time level meters** — monitor input/output signals
- **Presets** — includes Bass Boost, Vocal Presence, and more; save your own
- **EasyEffects import/export** for sharing presets with Linux users
- **System EQ toggle** — master on/off for all processing = disable EQ
- **Remembers your settings** — devices, routing, EQ state, and preferences persist across launches

## Requirements

- macOS 15 (Sequoia) or later
- Apple Silicon Mac
- BlackHole 2ch (free)
