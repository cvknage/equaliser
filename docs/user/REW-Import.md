# Importing REW Filter Settings

Equaliser can import filter settings exported from [Room EQ Wizard (REW)](https://www.roomeqwizard.com/), allowing you to use REW's measurement and optimisation tools with Equaliser's real-time audio processing.

## Exporting from REW

1. In REW, go to **Equalizer** → **Export filter settings**
2. Save the file as a `.txt` file
3. In Equaliser, use **Presets** → **Import REW Preset...**
4. Select your exported `.txt` file

## Supported File Format

REW exports filter settings as plain text files with the following structure:

```
Filter Settings file
Room EQ V5.31
Dated: 15-Mar-2026 10:30:00
Notes:Your measurement notes
Equaliser: Generic
Filter 1: ON  PK   Fc   1000Hz   Gain   6.0dB  Q  1.41
Filter 2: ON  LS   Fc    200Hz   Gain   3.0dB  Q  0.707
Filter 3: OFF PK   Fc   5000Hz   Gain  -2.0dB  Q  2.0
```

### Format Details

Each filter line follows this pattern:

```
Filter N: ON/OFF TYPE Fc FREQHz Gain VALUEdB [Q VALUE | BW/60 VALUE]
```

| Component | Description |
|-----------|-------------|
| `N` | Filter number (1-20 typically) |
| `ON/OFF` | Whether the filter is active |
| `TYPE` | Filter type code (see below) |
| `Fc` | Frequency marker |
| `FREQ` | Centre frequency in Hz |
| `Gain` | Gain marker |
| `VALUE` | Gain in dB |
| `Q` or `BW/60` | Bandwidth specification |

## Supported Filter Types

Equaliser imports the following REW filter types:

| REW Code | Filter Type | Description |
|----------|-------------|-------------|
| `PK`, `PEQ`, `PA`, `PARAMETRIC` | Parametric | Bell-shaped EQ curve |
| `LS`, `LOWSHELF`, `LOW-SHELF` | Low Shelf | Boosts or cuts frequencies below the centre |
| `HS`, `HIGHSHELF`, `HIGH-SHELF` | High Shelf | Boosts or cuts frequencies above the centre |
| `LP`, `LOWPASS`, `LOW-PASS` | Low Pass | Attenuates frequencies above the cutoff |
| `HP`, `HIGHPASS`, `HIGH-PASS` | High Pass | Attenuates frequencies below the cutoff |
| `BP`, `BANDPASS`, `BAND-PASS` | Band Pass | Passes a band of frequencies |
| `NOTCH`, `BANDSTOP`, `BAND-STOP` | Notch | Narrow band stop filter |

### Unsupported Filters

- `None` filters are skipped during import
- Any unknown filter types default to parametric

## Linked vs Stereo Mode

REW exports one file per channel. How you import depends on your channel mode:

### Linked Mode (Default)

In linked mode, the imported filters apply to **both left and right channels**:

1. Export filter settings from REW
2. Import the file in Equaliser
3. A new preset is created with the same bands for both channels

### Stereo Mode

In stereo mode, you can import **separate L and R files**:

1. Set channel mode to **Stereo** in the EQ window
2. Select **Left** channel focus
3. Import your left channel REW file
4. Select **Right** channel focus
5. Import your right channel REW file
6. Save the combined preset

This allows independent EQ curves for each channel, useful for room correction where left and right speakers need different compensation.

## Limit Ranges

Equaliser applies these limits during import:

| Parameter | Range | Behaviour |
|-----------|-------|-----------|
| Frequency | 20 Hz – 20,000 Hz | Clamped to range |
| Gain | -36 dB to +36 dB | Clamped to range |
| Q | 0.1 to 100.0 | Clamped to range |

If values are clamped, a warning is shown after import.

## Example Files

### Basic Room Correction

```
Filter Settings file
Room EQ V5.31
Dated: 15-Mar-2026 10:30:00
Notes:Living room measurements
Equaliser: Generic
Filter  1: ON  PK   Fc     32Hz   Gain  -4.5dB  Q  1.41
Filter  2: ON  PK   Fc    100Hz   Gain  -2.0dB  Q  2.0
Filter  3: ON  PK   Fc    250Hz   Gain   3.0dB  Q  1.0
Filter  4: ON  PK   Fc   1000Hz   Gain  -1.5dB  Q  1.41
Filter  5: ON  PK   Fc   4000Hz   Gain   2.0dB  Q  2.0
Filter  6: ON  HS   Fc  10000Hz   Gain  -3.0dB  Q  0.707
Filter  7: ON  LS   Fc     80Hz   Gain   4.0dB  Q  0.707
Filter  8: OFF PK   Fc   8000Hz   Gain   0.0dB  Q  1.41
Filter  9: ON  None
Filter 10: ON  HP   Fc     20Hz   Q  0.707
```

### Headphone Correction

```
Filter Settings file
Room EQ V5.31
Dated: 15-Mar-2026 14:22:00
Notes:Sennheiser HD600 correction
Equaliser: Generic
Filter  1: ON  PK   Fc     28Hz   Gain  -5.2dB  Q  2.0
Filter  2: ON  PK   Fc    120Hz   Gain   3.8dB  Q  1.0
Filter  3: ON  PK   Fc    450Hz   Gain  -2.0dB  Q  2.5
Filter  4: ON  PK   Fc   2100Hz   Gain   4.5dB  Q  1.41
Filter  5: ON  PK   Fc   5800Hz   Gain  -3.2dB  Q  3.0
Filter  6: ON  PK   Fc   8500Hz   Gain   2.0dB  Q  2.0
Filter  7: ON  NOTCH Fc  12000Hz   Gain   0.0dB  Q  5.0
```

### Bass Management with BW/60

```
Filter Settings file
Room EQ V5.20
Dated: 20-Jan-2026 09:15:00
Notes:Subwoofer integration
Equaliser: DSP1124P
Filter  1: ON  PK   Fc    25Hz   Gain   6.0dB  BW/60  2.0
Filter  2: ON  PK   Fc    45Hz   Gain  -2.0dB  BW/60  3.0
Filter  3: ON  LS   Fc    80Hz   Gain   0.0dB  Q  0.707
Filter  4: ON  LP   Fc    80Hz   Q  0.707
```

## Troubleshooting

### "No filter settings found in file"

The file doesn't contain any valid filter lines. Ensure you exported **filter settings**, not measurement data.

### Values clamped warning

REW exported values outside Equaliser's supported range. The values have been adjusted automatically. Check the imported bands and adjust if needed.

### Filter type shows as Parametric instead of expected type

REW may use a filter type abbreviation Equaliser doesn't recognise. Unknown types default to parametric. Check that your REW version uses standard abbreviations (PK, LS, HS, LP, HP, etc.).

### Wrong number of bands

Imported filters depend on their state:
- `ON` filters are imported as active bands
- `OFF` filters are imported as bypassed bands
- `None` filters are skipped entirely

### Stereo import affects both channels

You're in linked mode. Switch to stereo mode before importing to apply filters to only the focused channel.
