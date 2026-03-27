# How It Works

A detailed explanation of how Equaliser processes audio on your Mac.

---

## Overview

Equaliser provides **system-wide audio equalisation** for your Mac. This means every app — Spotify, Safari, Games, FaceTime — has its audio processed through the equaliser before reaching your speakers or headphones.

Achieving system-wide EQ on macOS requires a special approach. Unlike individual apps that only process their own audio, Equaliser needs to intercept **all** audio playing on your system. This is accomplished using a **virtual audio driver**.

---

## The Audio Pipeline

When Equaliser is running, audio flows through this pipeline:

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Your Apps      │     │  Equaliser       │     │  Equaliser      │     │  Output Device  │
│  (Spotify, etc.)│ ──▶ │  Driver          │ ──▶ │  App (EQ)       │ ──▶ │  (Speakers/     │
│                 │     │  (Virtual Device)│     │  (Processing)   │     │   Headphones)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘     └─────────────────┘
```

| Stage | What Happens |
|-------|--------------|
| **Your Apps** | Any app playing audio on your Mac |
| **Equaliser Driver** | A virtual device that captures system audio before it reaches hardware |
| **Equaliser App** | Applies EQ processing, gain adjustments, and effects |
| **Output Device** | Your actual speakers, headphones, or external audio interface |

### How macOS Sees It

macOS treats the Equaliser Driver as a real audio device. When you set it as your system default output:

1. All apps send their audio to the driver
2. The driver passes audio to Equaliser for processing
3. Equaliser sends the processed audio to your chosen output

---

## The Virtual Audio Driver

### What Is It?

The **Equaliser Driver** is a virtual audio device that installs into macOS's audio system. It appears alongside your real audio devices (built-in speakers, headphones, etc.) but has no physical hardware — it exists purely to capture audio for processing.

### Why Is It Needed?

macOS doesn't allow apps to intercept each other's audio. Each app can only access its own audio stream. The virtual driver solves this by becoming the system-wide output device, creating a common point where all audio converges.

### Installation

The driver requires **admin privileges** to install. When you first enable Equaliser:

1. macOS prompts for your password
2. The driver installs to `/Library/Audio/Plug-Ins/HAL/Equaliser.driver`
3. Equaliser appears as an available audio device

**Uninstallation**: The driver can be removed from Settings → Driver → Uninstall Driver. This requires admin privileges again.

### Automatic Updates

Equaliser checks the bundled driver version against the installed version. If a newer version is included with the app, you'll be prompted to update.

---

## Audio Routing Modes

Equaliser offers two modes for handling audio devices.

### Automatic Mode (Recommended)

The simplest way to use Equaliser. Set it once and forget about it.

| Feature | Behaviour |
|---------|-----------|
| **Output Selection** | Follows your macOS Sound settings automatically |
| **Driver Naming** | Shows the output device name (e.g., "Speakers (Equaliser)") |
| **Device Changes** | Instantly follows when you change macOS default output |
| **Headphones** | Auto-switches to headphones when plugged in |

**How it works:**

1. Set the Equaliser Driver as your default output device (Equaliser does this automatically)
2. Change your output device in macOS Sound settings
3. Equaliser detects the change and routes audio accordingly

### Manual Mode

For advanced users who want complete control over device selection.

| Feature | Behaviour |
|---------|-----------|
| **Input Device** | Choose any audio input (virtual or real) |
| **Output Device** | Choose any audio output device |
| **Flexibility** | Works with third-party virtual drivers (BlackHole, etc.) |
| **Permission** | Requires microphone permission |

**Use Manual Mode when:**

- You want to use a different virtual audio driver as input
- You need to route audio from a specific application
- You're doing advanced audio routing with multiple virtual devices

---

## Capture Methods

Equaliser supports two methods for capturing audio from the driver.

### Shared Memory (Default)

The default and recommended capture method.

| Aspect | Details |
|--------|---------|
| **Method** | Lock-free ring buffer via memory mapping |
| **Microphone Permission** | **Not required** |
| **Control Center Indicator** | No orange microphone indicator |
| **Compatibility** | Only works with the Equaliser Driver |

The driver writes audio to shared memory, and Equaliser reads it. No microphone permission needed, no system indicators.

### HAL Input

An alternative capture method for specific use cases.

| Aspect | Details |
|--------|---------|
| **Method** | macOS CoreAudio HAL input stream |
| **Microphone Permission** | **Required** |
| **Control Center Indicator** | Orange microphone indicator shown |
| **Compatibility** | Works with any input device |

**When to use HAL Input:**

- Using Manual Mode with a third-party virtual driver
- Capturing from a real input device
- Advanced audio routing setups

<details>
<summary>🔧 Technical Details: How Shared Memory Capture Works</summary>

The shared memory capture uses a **lock-free ring buffer**:

1. The driver writes audio samples to a memory-mapped ring buffer
2. Equaliser reads from this buffer synchronously during its output callback
3. Atomic operations ensure thread safety without locks
4. No memory allocation happens on the audio thread

**Why this matters:**
- **Real-time safety**: Audio processing must never block or allocate memory
- **Low latency**: Direct memory access without system calls
- **Privacy**: macOS doesn't consider this "microphone access"

The ring buffer also handles **clock drift** between the driver and output device. Since the driver and output device may run at slightly different rates, the buffer absorbs timing differences without artefacts.

</details>

<details>
<summary>🔧 Technical Details: HAL Input Capture</summary>

HAL Input uses macOS's standard audio input mechanism:

1. Equaliser opens an input stream on the selected device
2. macOS calls a callback with audio buffers
3. `AudioUnitRender` pulls audio data from the hardware layer

**Why this requires permission:**
macOS treats any input stream as "microphone access" for privacy. Even virtual drivers trigger this requirement.

**The orange indicator:**
macOS shows an orange microphone icon in Control Center whenever an app has an open input stream. This is system behaviour and cannot be disabled.

</details>

---

## The Equaliser Engine

### Parametric EQ

Equaliser provides **up to 64 bands** of parametric equalisation. Each band gives you precise control over:

| Control | What It Does |
|---------|--------------|
| **Frequency** | The centre frequency to adjust (20 Hz – 20 kHz for standard bands) |
| **Gain** | How much to boost or cut (-36 dB to +36 dB) |
| **Bandwidth** | How wide or narrow the adjustment is |
| **Filter Type** | Parametric, Low Shelf, High Shelf, and more |

### Standard Band Frequencies

The default 10-band configuration uses logarithmically-spaced frequencies:

| Band | Frequency | Range Covers |
|------|-----------|--------------|
| 1 | 32 Hz | Sub-bass |
| 2 | 64 Hz | Deep bass |
| 3 | 128 Hz | Upper bass |
| 4 | 256 Hz | Lower mids |
| 5 | 512 Hz | Mids |
| 6 | 1000 Hz (1 kHz) | Upper mids |
| 7 | 2000 Hz (2 kHz) | Presence |
| 8 | 4000 Hz (4 kHz) | Presence / Brilliance |
| 9 | 8000 Hz (8 kHz) | Highs |
| 10 | 16000 Hz (16 kHz) | Air |

### Gain Controls

In addition to per-band adjustments, Equaliser provides overall gain controls:

| Control | Position | Range | Purpose |
|---------|----------|-------|---------|
| **Input Gain** | Before EQ | -36 dB to +36 dB | Adjust level before processing |
| **Output Gain** | After EQ | -36 dB to +36 dB | Compensate for EQ changes |

### Processing Chain

Audio passes through this sequence:

```
[Input Audio] → [Input Gain] → [EQ Bands] → [Output Gain] → [Output Audio]
```

When **bypassed** (EQ toggle off), the EQ bands and input/output gains are skipped.

### Compare Mode

Compare Mode lets you A/B test your EQ settings against a flat response:

| Mode | What You Hear |
|------|---------------|
| **Normal** | Your EQ curve |
| **Compare** | Flat response with matched volume |

The volume matching ensures fair comparison — EQ boosts naturally sound louder, which can bias perception.

---

## Presets

### Factory Presets

Equaliser includes 11 carefully crafted presets for common use cases:

| Preset | Best For |
|--------|----------|
| Flat | Reference, testing |
| Bass Boost | Hip-hop, EDM, action movies |
| Treble Boost | Classical, acoustic, podcasts |
| Vocal Presence | Podcasts, voice calls, audiobooks |
| Loudness | Low-volume listening |
| Acoustic | Acoustic music, singer-songwriter |
| Rock | Rock, metal, alternative |
| Electronic | EDM, techno, house |
| Jazz | Jazz, blues, soul |
| Podcast | Speech content |
| Classical | Orchestral, chamber music |

See the [EQ Presets Guide](./EQ-Presets-Guide.md) for detailed explanations of each preset.

### Custom Presets

Create your own presets:

1. Adjust your EQ settings
2. Click the preset menu → Save As...
3. Name your preset

Custom presets are saved to:
```
~/Library/Application Support/Equaliser/Presets/
```

### Import and Export

- **Export**: Share presets as `.eqpreset` files
- **Import**: Load presets from `.eqpreset` files
- **EasyEffects**: Import presets from Linux EasyEffects (compatible format)

---

## Device Management

### Headphone Auto-Switch

When headphones are connected, Equaliser automatically switches output:

| Condition | Behaviour |
|-----------|-----------|
| Current output is built-in speakers | Switches to headphones |
| Current output is external device | Keeps current output |

This matches macOS behaviour and prevents audio from unexpectedly playing through speakers.

**How it works:**

| Platform | Detection Method |
|----------|------------------|
| Apple Silicon | Built-in device count change |
| Intel Mac | Jack connection property |

When headphones are unplugged, Equaliser restores the previous output device from history.

### Device History

Equaliser remembers your output device choices:

- When a device becomes unavailable, Equaliser finds a replacement
- When the device returns, Equaliser can restore your preference
- History is limited to prevent stale device references

<details>
<summary>🔧 Technical Details: Device Selection Logic</summary>

Equaliser uses a prioritised selection algorithm:

1. **Preserve current**: If your saved device is still available, keep it
2. **Use macOS default**: If your saved device is gone, use macOS's default
3. **Find fallback**: If no valid devices exist, use built-in speakers

This pure function approach avoids calling CoreAudio with potentially-stale UIDs, which can cause crashes on device disconnection.

</details>

---

## Privacy & Permissions

### What Equaliser Does NOT Do

| Not Done | Meaning |
|----------|---------|
| ❌ Record audio | No audio is ever saved or stored |
| ❌ Transmit audio | No network activity of any kind |
| ❌ Collect analytics | No usage tracking |
| ❌ Phone home | No background network requests |

All audio processing happens **locally on your Mac**. Equaliser has no network capability.

### Microphone Permission

macOS may request microphone permission when Equaliser launches. Here's why:

| Capture Mode | Permission Required? | Why |
|--------------|----------------------|-----|
| **Shared Memory (default)** | No | Audio read from memory, not microphone API |
| **HAL Input** | Yes | Uses macOS audio input APIs |
| **Manual Mode** | Yes | Always requires HAL input |

**The permission prompt appears at launch** because macOS detects the audio-input entitlement in the app, even though the default mode doesn't need it. This is macOS behaviour and cannot be controlled.

If you only use **Automatic Mode with Shared Memory capture**, you can deny the permission — the app will work correctly.

---

## Troubleshooting

### No Sound After Enabling

1. Check that Equaliser Driver is set as default output in macOS Sound settings
2. In Automatic Mode, verify an output device is selected
3. Try toggling EQ off and on

### Orange Microphone Indicator Appears

This happens when using HAL Input capture or Manual Mode. To avoid it:

1. Go to Settings → Driver
2. Select "Shared Memory" as capture mode
3. Ensure you're in Automatic Mode

### Driver Installation Fails

Driver installation requires admin privileges. If installation fails:

1. Ensure you entered your password correctly
2. Check that no other audio apps are blocking the installation
3. Try restarting your Mac and installing again

### Audio Sounds Distorted

Distortion usually indicates:

1. **Input gain too high**: Reduce Input Gain
2. **Output gain too high**: Reduce Output Gain
3. **Excessive band boost**: Reduce individual band gains

Watch the level meters for clipping indicators (red peaks).

