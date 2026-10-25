import Foundation

/// How far a sync is, 0...1, and never backwards: the three Xtream downloads run at the same time and finish in any order. The sink
/// is told only when the value really grew, in order, from whatever thread moved it. It runs under the lock to keep that order, so it
/// must be quick and must not call back into the meter.
final class SyncMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    private let sink: (@Sendable (Double) -> Void)?

    init(_ sink: (@Sendable (Double) -> Void)?) { self.sink = sink }

    func reach(_ v: Double) { move { max($0, min(v, 1)) } }
    func advance(by d: Double) { move { min($0 + d, 1) } }

    private func move(_ f: (Double) -> Double) {
        lock.withLock { let n = f(value); if n > value { value = n; sink?(n) } }
    }
}
