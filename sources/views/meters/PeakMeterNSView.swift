import SwiftUI

/// SwiftUI wrapper for the GPU-accelerated peak meter.
struct PeakMeterNSView: NSViewRepresentable {
    let meterStore: MeterStore
    let meterType: MeterType
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> PeakMeterLayer {
        let view = PeakMeterLayer()
        meterStore.addObserver(view, for: meterType)
        context.coordinator.meterStore = meterStore
        context.coordinator.meterType = meterType
        return view
    }
    
    func updateNSView(_ nsView: PeakMeterLayer, context: Context) {
        // Updates come via observer callback, not through SwiftUI
    }
    
    func dismantleNSView(_ nsView: PeakMeterLayer, coordinator: Coordinator) {
        coordinator.meterStore?.removeObserver(nsView, for: coordinator.meterType)
    }
    
    class Coordinator {
        weak var meterStore: MeterStore?
        var meterType: MeterType = .inputPeakLeft
    }
}
