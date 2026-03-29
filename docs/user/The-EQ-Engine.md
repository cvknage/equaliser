# The Equaliser Engine

A detailed look at the custom biquad DSP engine that powers Equaliser's audio processing.

---

## Overview

Equaliser processes audio using a **custom biquad DSP engine** built specifically for real-time, low-latency equalisation on macOS. This engine is written in Swift and leverages Apple's vDSP framework for native performance on Apple Silicon.

Why custom? Most EQ apps use Apple's `AVAudioUnitEQ`, which limits control and doesn't support independent left/right channel processing. Equaliser's custom engine provides:

- **64 bands per channel** (128 total in stereo mode)
- **Independent L/R channels** for stereo mastering
- **Real-time safety** — no allocations or locks on the audio thread
- **Native performance** through Apple's Accelerate framework

---

## What Is a Biquad Filter?

A **biquad** (bi-quadratic) filter is a digital filter that can implement any second-order IIR (infinite impulse response) filter. The term comes from the transfer function being a ratio of two quadratic polynomials.

Every parametric EQ band you adjust — whether it's a bell curve, low shelf, or high-pass — is implemented as a single biquad filter. When you have 10 bands of EQ, you're chaining 10 biquads in series:

```
[Audio In] → [Biquad 1] → [Biquad 2] → ... → [Biquad N] → [Audio Out]
```

Each biquad has five coefficients (a1, a2, b0, b1, b2) that define its frequency response. When you adjust a band's frequency, Q, or gain, Equaliser recalculates these coefficients and sends them to the audio thread.

<details>
<summary>⚙️ Technical Details: The Transfer Function</summary>

A biquad filter is defined by its transfer function in the z-domain:

```
        b0 + b1·z⁻¹ + b2·z⁻²
H(z) = ─────────────────────
        1 + a1·z⁻¹ + a2·z⁻²
```

The five coefficients (b0, b1, b2, a1, a2) determine the filter's behaviour:
- **b0, b1, b2**: Feedforward coefficients (numerator)
- **a1, a2**: Feedback coefficients (denominator)

Each sample y[n] is computed from the input x[n] and previous samples:

```
y[n] = b0·x[n] + b1·x[n-1] + b2·x[n-2] - a1·y[n-1] - a2·y[n-2]
```

The "delay elements" (x[n-1], y[n-1], etc.) give the filter its memory — this is why IIR filters can achieve steep slopes with few coefficients.

</details>

---

## The RBJ Audio EQ Cookbook

Equaliser's coefficient calculations follow the **RBJ Audio EQ Cookbook**, an industry-standard reference by Robert Bristow-Johnson. Originally published on the music-dsp mailing list in the 1990s, the Cookbook provides closed-form equations for every common audio filter type.

**Why the Cookbook?**

- **Proven correctness** — Used by countless audio applications, DAWs, and plugins
- **Numerical stability** — Formulas designed to work across the audible spectrum
- **Complete coverage** — All 11 filter types Equaliser supports

**The Cookbook reference:**

- [Original Music-DSP post (archived)](https://webaudio.github.io/Audio-EQ-Cookbook/Audio-EQ-Cookbook.txt)
- [W3C Web Audio API version](https://webaudio.github.io/Audio-EQ-Cookbook/Audio-EQ-Cookbook.html)

Equaliser implements all Cookbook filter types:

| Filter Type | Cookbook Formula | Use Case |
|-------------|-----------------|----------|
| Parametric (Peaking) | `peakingEQ` | Boost/cut at a specific frequency |
| Low-Pass | `LPF` | Remove high frequencies |
| High-Pass | `HPF` | Remove low frequencies |
| Low Shelf | `lowShelf` | Boost/cut bass frequencies |
| High Shelf | `highShelf` | Boost/cut treble frequencies |
| Band-Pass | `BPF` (constant 0 dB peak) | Isolate a frequency band |
| Notch | `notch` | Remove a specific frequency |
| Resonant Low-Pass | `LPF` with Q | Low-pass with resonant peak |
| Resonant High-Pass | `HPF` with Q | High-pass with resonant peak |
| Resonant Low Shelf | `lowShelf` with Q | Bass shelf with adjustable slope |
| Resonant High Shelf | `highShelf` with Q | Treble shelf with adjustable slope |

---

## Why Swift + vDSP?

Equaliser's engine is written in **Swift** and uses **Apple's vDSP** (part of the Accelerate framework) for the actual filtering operations. This combination delivers native performance with clean, maintainable code.

### What Is vDSP?

vDSP is Apple's vectorised Digital Signal Processing library, optimised for Apple Silicon:

- **SIMD operations** — Process 4-8 samples per instruction
- **NEON acceleration** — Native ARM64 vector instructions
- **Zero allocation** — All operations work on pre-allocated buffers

### Why Not AVAudioUnitEQ?

Apple's `AVAudioUnitEQ` is convenient but limiting:

| Aspect | AVAudioUnitEQ | Custom biquad (Equaliser) |
|--------|---------------|---------------------------|
| Per-channel config | No | Yes (independent L/R) |
| Coefficient access | Limited | Full control |
| Real-time updates | Apple-controlled | Atomic, lock-free |
| Debugging | Black box | Transparent |

<details>
<summary>⚙️ Technical Details: Double-Precision Coefficients</summary>

Equaliser calculates filter coefficients using **Double** (64-bit) precision, then converts to **Float** (32-bit) for the vDSP operations.

Why Double for calculation?

- **Narrow filters** — A Q of 20 at low frequencies produces very small alpha values. Float precision can introduce audible errors.
- **Low frequencies** — Near DC, sin(ω) values become tiny. Double maintains precision.
- **Accurate shelf slopes** — Shelf filters involve sqrt(A) terms that benefit from extra precision.

The vDSP biquad function (`vDSP_biquad`) operates on Float arrays, which is fine for runtime — the audio samples are Float anyway. Only the coefficient calculation benefits from Double.

</details>

---

## Real-Time Safety

Audio processing must happen in **real-time** — the next buffer of samples must be ready before the speaker needs them. If processing takes too long, you get **dropouts**: clicks, pops, or gaps in the audio.

Equaliser's engine is designed from the ground up for real-time safety:

| Operation | Thread | Real-Time Safe? | How |
|-----------|--------|-----------------|-----|
| Calculate coefficients | Main | No | Pure maths, may allocate |
| Apply slider change | Main | No | Writes to pending buffer |
| Process audio | Audio | **Yes** | Pre-allocated buffers, atomics only |
| Update filter state | Audio | **Yes** | Only if dirty, bounded copy |

### Lock-Free Coefficient Updates

When you drag a slider, the main thread calculates new coefficients. But the audio thread is already running — how do we update without blocking?

Equaliser uses a **lock-free double-buffer** pattern:

```
[Main Thread]                              [Audio Thread]
     │                                          │
     ▼                                          │
BiquadMath.calculateCoefficients()              │
     │                                          │
     ▼                                          │
pendingCoefficients[index] = newCoeffs          │
     │                                          │
hasPendingUpdate.store(true, .releasing)        │
     │                                          │
     └─────── atomic flag ─────────────────────►│
                                                │
                                                ▼
                                       flag.exchange(false)
                                                │
                                                ▼
                                for each band where pending != active:
                                    filter.setCoefficients(pending)
                                    // vDSP setup recreated here
                                                │
                                                ▼
                                    process audio with new coefficients
```

Key points:

1. **No locks** — Atomic flag synchronises threads without blocking
2. **Dirty tracking** — Only changed bands trigger rebuild (`Equatable` comparison). A single-band slider drag rebuilds exactly 1 filter.
3. **Bounded setup recreation** — `vDSP_biquad_CreateSetup` is called on the audio thread, but only for dirty bands. The setup object doesn't allocate memory; it's a pre-sized data structure.
4. **State preserved** — Slider drags don't reset filter delay elements (no clicks). Only preset loads and sample rate changes reset state.

### Why This Matters

Without real-time safety:

- **Locks cause priority inversion** — Audio thread waits for UI thread
- **Allocations cause VM faults** — First access to new memory can take 100s of milliseconds
- **Unbounded work causes underruns** — Processing might not finish in time

Equaliser's engine guarantees: every filter operation completes in bounded time, every time.

<details>
<summary>⚙️ Technical Details: vDSP Biquad Setup</summary>

Each biquad filter requires a **setup object** (`vDSP_biquad_Setup`) that holds internal state. Creating and destroying these objects is expensive.

Equaliser's `BiquadFilter` manages this carefully:

```swift
// Init: create setup once
let setup = vDSP_biquad_CreateSetup(&coefficients, 1, .intersect)

// Runtime: reuse setup, only update coefficients
vDSP_biquad(setup, &input, &output, 1, frameCount)

// Coefficients change: destroy old setup, create new one
vDSP_biquad_DestroySetup(setup)
let newSetup = vDSP_biquad_CreateSetup(&newCoefficients, 1, .intersect)
```

The setup is only recreated when coefficients actually change, and the old setup is kept valid until the new one is ready. This prevents any gap in processing.

</details>

---

## Independent Stereo Processing

Equaliser supports **independent EQ for left and right channels** — each channel can have completely different curves.

### Architecture

Each EQ layer has two separate filter chains:

```
┌──────────────────────────────────────────────────────┐
│                       EQ Layer                       │
│                                                      │
│  ┌─────────────────┐           ┌─────────────────┐   │
│  │  Left Channel   │           │  Right Channel  │   │
│  │  EQChain        │           │  EQChain        │   │
│  │  (64 bands)     │           │  (64 bands)     │   │
│  └─────────────────┘           └─────────────────┘   │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### Linked vs Stereo Mode

| Mode | Behaviour |
|------|-----------|
| **Linked** (default) | Both channels share the same EQ curve. Editing any band updates both left and right. |
| **Stereo** | Left and right channels have independent curves. Edit each channel separately. |

Use cases for stereo mode:

- **Driver variation compensation** — Headphone drivers can have minor frequency response differences between left and right
- **Room correction** — Room acoustics affect left and right speakers differently
- **Hearing compensation** — Compensate for asymmetric hearing between left and right ears

---

## Further Reading

- **[How It Works](./How-It-Works.md)** — Overview of the complete audio pipeline
- **[EQ Presets Guide](./EQ-Presets-Guide.md)** — Understanding factory presets
- **[RBJ Audio EQ Cookbook](https://webaudio.github.io/Audio-EQ-Cookbook/Audio-EQ-Cookbook.txt)** — The original reference
- **[Apple vDSP Documentation](https://developer.apple.com/documentation/accelerate/vdsp)** — Apple's DSP framework
