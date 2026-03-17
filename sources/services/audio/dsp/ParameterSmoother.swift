import Foundation
import Combine

actor ParameterSmoother {
    private let smoothingInterval: TimeInterval
    private var task: Task<Void, Never>?

    init(interval: TimeInterval = 0.02) {
        self.smoothingInterval = interval
    }

    func ramp(
        from startValue: Float,
        to endValue: Float,
        duration: TimeInterval,
        step: @escaping @MainActor (Float) -> Void
    ) {
        task?.cancel()
        let steps = max(1, Int(duration / smoothingInterval))
        let delta = (endValue - startValue) / Float(steps)

        task = Task { [smoothingInterval] in
            var currentValue = startValue
            for iteration in 0..<steps {
                try? await Task.sleep(nanoseconds: UInt64(smoothingInterval * 1_000_000_000))
                currentValue += delta
                await step(currentValue)
                if Task.isCancelled { return }
                if iteration == steps - 1 {
                    await step(endValue)
                }
            }
        }
    }
}
