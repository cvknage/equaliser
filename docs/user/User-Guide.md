# Equaliser User Guide

A practical guide to using Equaliser — the system-wide audio equaliser for macOS.

---

## Quick Start

Equaliser works in the background, processing all audio from your Mac through a customisable EQ curve. To get started:

1. Launch Equaliser — the main window opens and the menu bar icon appears
2. If prompted, install the audio driver — this requires your password
3. EQ is now active for all audio playing on your Mac

---

## The Menu Bar

The Equaliser icon lives in your menu bar and is the quickest way to control the app without interrupting what you're doing. From there you can toggle EQ on and off, switch presets, open the main window, or quit entirely.

---

## The Main Window

Open the main window from the menu bar for full control over your EQ.

### The Band Sliders

The main area displays a horizontal row of vertical sliders — one for each frequency band. Drag a slider up to boost that frequency, or down to cut it. Double-click a slider to reset it to 0 dB. Each band column shows the frequency at the top (tap to edit directly), the gain slider in the centre, and the gain value in dB at the bottom.

Click the gear icon on any band to open a popover with full controls: **gain** (how much to boost or cut, from -36 dB to +36 dB), **frequency** (where in the spectrum the band is centred, from 20 Hz to 20 kHz), **bandwidth** (Q), and **filter type** (parametric, shelf, etc.).

Bandwidth is expressed as a Q factor from 0.1 to 100 — think of it as zoom. A high Q zooms in tight on a single frequency for a precise, surgical adjustment; a low Q affects a wider range for a broad, gentle curve.

### Channel Mode

Above the sliders, you can switch between **Linked** (both channels share the same EQ) and **Stereo** (left and right channels have independent EQ curves). In Stereo mode, use the L/R toggle to choose which channel you're editing.

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Tab / Shift+Tab** | Move between bands |
| **↑ / ↓** | Adjust value |
| **Enter / Escape** | Accept and exit edit |
| **Cmd+B** | Toggle bypass |
| **Cmd+S** | Save preset |

### Level Meters

The level meters show your input and output levels in real time. Keep an eye on them when making large boosts — if the meters clip (red peaks), reduce your Input Gain to create more headroom, or try cutting other bands rather than boosting.

---

## Presets

Presets let you save and recall EQ settings instantly.

### Factory Presets

Equaliser ships with eleven presets covering common listening scenarios — **Flat** for reference, **Bass Boost** and **Treble Boost** for emphasis, **Vocal Presence** and **Podcast** for speech, and genre-specific curves for Rock, Electronic, Jazz, Classical, and more. See the [EQ Presets Guide](./EQ-Presets-Guide.md) for a detailed explanation of each one.

### Saving Your Own Presets

Once you've dialled in a sound you like, click **Save As...** in the preset menu and give it a name. It's worth keeping separate presets for headphones and speakers — the same EQ rarely sounds right on both.

### Importing Presets

Equaliser can import `.eqpreset` files, EasyEffects presets from Linux, and filter files from Room EQ Wizard (REW). See [REW Import](./REW-Import.md) for details on the REW workflow.

---

## Bypass & Compare

**Bypass** (the power toggle) turns off all EQ processing so audio passes through completely unchanged. Use it to disable the EQ without quitting the app.

**Compare mode** is more useful for critical listening. It A/B tests your EQ against a flat, volume-matched response — so you're hearing a real difference, not just a loudness difference. Toggle between EQ and Flat to check whether your curve is actually improving the sound. A timer switches back to EQ automatically after 5 minutes.

---

## Settings

Click the gear icon in the top right to access settings.

**Driver** lets you install or uninstall the Equaliser virtual audio driver, and switch between capture modes. Most users should leave this on **Shared Memory** (the default) — it works without microphone permission and doesn't trigger the orange menu bar indicator.

**Devices** controls how Equaliser selects your output. **Automatic** mode (recommended) handles this for you; **Manual** mode lets you pick a specific output device.

**Preferences** lets you display bandwidth as Q factor or octaves depending on what you're used to.

---

## Tips

**Start subtle.** Small adjustments — a dB or two — usually sound more natural than dramatic boosts or cuts. It's easy to overcook an EQ.

**Cut more than you boost.** If something sounds harsh or muddy, try cutting the problem frequency rather than boosting elsewhere. It tends to sound cleaner and avoids gain buildup.

**Use Compare mode honestly.** Louder almost always sounds "better" — Compare mode removes that variable, so you can judge the EQ on its actual merits.

**Create presets per output.** Headphones and speakers need different EQ. Save separate presets for each so switching is just a click away.

---

For deeper reading: [How It Works](./How-It-Works.md) covers the audio pipeline, and [The EQ Engine](./The-EQ-Engine.md) goes into the DSP details.
