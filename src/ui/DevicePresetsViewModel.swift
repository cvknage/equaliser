import SwiftUI

struct PresetDevice: Identifiable {
    /// Output preset key, which matches the CoreAudio UID for most devices.
    let uid: String
    let name: String
    let isAvailable: Bool
    let isSelected: Bool

    var id: String { uid }
}

@MainActor
@Observable
final class DevicePresetsViewModel {
    private unowned let store: EqualiserStore

    init(store: EqualiserStore) {
        self.store = store
    }

    var devices: [PresetDevice] {
        var names = store.presetManager.outputDeviceNames
        for uid in store.presetManager.outputPresets.keys where names[uid] == nil {
            names[uid] = uid
        }
        let available = Set(store.outputDevices.filter(\.isValidForSelection).map { OutputPresetKey.make(for: $0.uid) })
        let selected = selectedKey
        return names.map { uid, name in
            PresetDevice(
                uid: uid,
                name: name,
                isAvailable: available.contains(uid),
                isSelected: uid == selected
            )
        }.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.uid < $1.uid : order == .orderedAscending
        }
    }

    var presets: [Preset] { store.presetManager.presets }

    private var selectedKey: String? {
        store.selectedOutputDeviceID.map(OutputPresetKey.make)
    }

    func presetName(for uid: String) -> String? {
        store.presetManager.preset(forOutputDevice: uid)?.metadata.name
    }

    func updatePreset(named name: String?, for uid: String) {
        store.presetManager.updateOutputPreset(named: name, for: uid)
        if OutputPresetKey.make(for: uid) == selectedKey, let name {
            store.loadPreset(named: name)
        }
    }
}
