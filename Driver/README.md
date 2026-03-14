# Equaliser Audio Driver

Virtual audio driver based on [BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio Inc.
License: GPL-3.0 (inherited from upstream)

## Custom Properties

One custom CoreAudio property allows the Equaliser app to control the driver:

| Selector | Type | Get/Set | Description |
|----------|------|---------|-------------|
| `'eqnm'` | CFString | Read/Write | Dynamic device name shown in Audio MIDI Setup |

The device name persists to `UserDefaults` via `WriteToStorage` and survives driver reloads.

## Automatic Visibility Management

The driver is **hidden by default** and only appears when the Equaliser app is running:

- On coreaudiod start: device is hidden
- When app connects (`AddDeviceClient`): device becomes visible
- When app disconnects (`RemoveDeviceClient`): device becomes hidden

This works by tracking bundle IDs of connected clients and checking against `net.knage.equaliser`

## Client Tracking

Three helper functions manage client tracking:

```c
static bool Equaliser_IsAppBundleConnected(void);      // Check if our app is connected
static void Equaliser_AddClientBundleID(CFStringRef);  // Track a client
static void Equaliser_RemoveClientBundleID(CFStringRef); // Untrack a client
static void Equaliser_UpdateVisibility(host, deviceID); // Show/hide based on connections
```

## Building

```bash
./driver.sh bundle
```

## Installation

```bash
sudo cp -R .build/Equaliser.driver /Library/Audio/Plug-Ins/HAL/
sudo killall coreaudiod
```

## Updating from Upstream

```bash
cp /path/to/BlackHole.c src/EqualiserDriver.c
patch -p1 < EqualiserDriver.patch
```

If the patch fails (due to line drift), apply changes manually per the sections below.

## Customizations (Manual Reference)

### Header Comment

```c
/*
     File: EqualiserDriver.c
  
     Based on BlackHole.c
     Copyright (C) 2019 Existential Audio Inc.
  
     Modified for Equaliser by logic
  
 */
/*==================================================================================================
	EqualiserDriver.c
==================================================================================================*/
```

### Branding Constants

| Constant | Original | Changed To |
|----------|----------|------------|
| `kDriver_Name` | `"BlackHole"` | `"Equaliser"` |
| `kPlugIn_BundleID` | `"audio.existential.BlackHole2ch"` | `"net.knage.equaliser.driver"` |
| `kPlugIn_Icon` | `"BlackHole.icns"` | `"EqualiserDriver.icns"` |
| `kHas_Driver_Name_Format` | `true` | `false` |
| `kManufacturer_Name` | `"Existential Audio Inc."` | `"logic"` |
| Box name default | `"BlackHole Box"` | `"Equaliser Box"` |

### Property Selectors and State Variables

Insert after `gPitch_Adjust_Enabled`:

```c
// Custom property selectors for Equaliser app communication
#define kEqualiserPropertyName           'eqnm'  // Dynamic device name (CFString)

// Custom property state for Equaliser app communication
static CFStringRef                  gEqualiser_DeviceName               = NULL;

// Client tracking for automatic visibility management
static pthread_mutex_t              gEqualiser_ClientMutex              = PTHREAD_MUTEX_INITIALIZER;
static UInt32                       gEqualiser_AppClientCount           = 0;
static CFStringRef                  gEqualiser_AppBundleID              = NULL;
static bool                         gEqualiser_DeviceShown              = false;  // Hidden until app connects

#define kEqualiserAppBundleID           "net.knage.equaliser"
```

### Client Tracking

The driver uses a simple reference counter to track app connections:

- **`gEqualiser_AppClientCount`**: Counter for our app's connections (0 = no app, 1+ = app connected)
- **`gEqualiser_AppBundleID`**: The bundle ID to match (`net.knage.equaliser`)
- **`gEqualiser_DeviceShown`**: Visibility state (false = hidden, true = visible)

**Visibility Logic:**
- `AddDeviceClient`: Increment counter; if counter becomes 1, show device
- `RemoveDeviceClient`: Deccrement counter; if counter becomes 0, hide device

**Modified Functions:**

| Function | Change |
|----------|--------|
| `BlackHole_Initialize` | Initialize `gEqualiser_AppBundleID`, set `gEqualiser_DeviceShown = false` |
| `BlackHole_AddDeviceClient` | If bundle ID matches our app: increment counter, show device if counter == 1 |
| `BlackHole_RemoveDeviceClient` | If bundle ID matches our app: decrement counter, hide device if counter == 0 |
| `BlackHole_HasDeviceProperty` | Add cases for `kEqualiserPropertyName`, `kAudioObjectPropertyCustomPropertyInfoList` |
| `BlackHole_IsDevicePropertySettable` | Add same cases; name is settable, CustomPropertyInfoList is not |
| `BlackHole_GetDevicePropertyDataSize` | Add same cases with appropriate sizes |
| `BlackHole_GetDevicePropertyData` | Return `gEqualiser_DeviceShown ? 0 : 1` for `kAudioDevicePropertyIsHidden`; return `gEqualiser_DeviceName` if set for `kAudioObjectPropertyName`; add handlers for name prop and CustomPropertyInfoList |
| `BlackHole_SetDevicePropertyData` | Add handler for `kEqualiserPropertyName` that persists via `WriteToStorage` |

### Storage Keys

| Key | Type | Description |
|-----|------|-------------|
| `equaliser device name` | CFString | Last set device name |


