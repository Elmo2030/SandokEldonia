import Foundation
import Observation
import IPTVCore

/// Channel zapping: the channel before or after the playing one in the list the user picked it from (a category, favorites, a search).
public enum ChannelZap {
    /// `step` is +1 (next) or -1 (previous); the list wraps around. Nil when there is nothing else to switch to.
    public static func neighbor(of current: Item, in list: [Item], step: Int) -> Item? {
        let channels = list.filter { $0.type == .live }
        guard channels.count > 1, let i = channels.firstIndex(where: { $0.accountId == current.accountId && $0.streamId == current.streamId }) else { return nil }
        return channels[((i + step) % channels.count + channels.count) % channels.count]
    }
}

/// The "up next" countdown after an episode ends: `episode` is set and `secondsLeft` counts down (5, 4, ... 1), then `play` is called
/// with the episode. `cancel()` (Cancel, seeking back, leaving the player) stops it. The pause between seconds is injected for tests.
@MainActor @Observable
public final class UpNext {
    public private(set) var episode: Episode?
    public private(set) var secondsLeft = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let seconds: Int
    @ObservationIgnored private let pause: @Sendable () async -> Void

    public init(seconds: Int = 5, pause: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: .seconds(1)) }) {
        self.seconds = seconds; self.pause = pause
    }

    public var isCounting: Bool { episode != nil }

    public func begin(_ next: Episode, play: @escaping @MainActor (Episode) -> Void) {
        guard episode == nil else { return }
        episode = next
        task = Task { [weak self] in
            guard let self else { return }
            for s in stride(from: self.seconds, through: 1, by: -1) {
                self.secondsLeft = s
                await self.pause()
                if Task.isCancelled { return }
            }
            self.episode = nil; self.secondsLeft = 0; self.task = nil
            play(next)
        }
    }

    public func cancel() { task?.cancel(); task = nil; episode = nil; secondsLeft = 0 }
}
