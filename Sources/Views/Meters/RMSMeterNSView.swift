import SwiftUI

/// SwiftUI wrapper for the GPU-accelerated RMS meter.
struct RMSMeterNSView: NSViewRepresentable {
    let meterStore: MeterStore
    let meterType: MeterType
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> RMSMeterLayer {
        let view = RMSMeterLayer()
        meterStore.addObserver(view, for: meterType)
        context.coordinator.meterStore = meterStore
        context.coordinator.meterType = meterType
        return view
    }
    
    func updateNSView(_ nsView: RMSMeterLayer, context: Context) {
        // Updates come via observer callback, not through SwiftUI
    }
    
    func dismantleNSView(_ nsView: RMSMeterLayer, coordinator: Coordinator) {
        coordinator.meterStore?.removeObserver(nsView, for: coordinator.meterType)
    }
    
    class Coordinator {
        weak var meterStore: MeterStore?
        var meterType: MeterType = .inputRMSLeft
    }
}
