import Foundation

/// When a failed or dropped stream is loaded again, and from where.
public enum PlaybackRetry {
    public enum Decision: Equatable { case retry(after: TimeInterval, start: Double), giveUp }

    public static let maxRetries = 3

    /// `attempt` is the number of retries already made in a row; `position` the last position the player reported (0 = it never started).
    /// A live channel restarts at the live edge; a movie or episode resumes a moment before where it broke. A title that never
    /// started gets one more try only: the link is most likely wrong or refused, and waiting 14 s to say so would be unkind.
    public static func decide(isLive: Bool, attempt: Int, position: Double, requestedStart: Double) -> Decision {
        let limit = isLive || position > 0 ? maxRetries : 1
        guard attempt >= 0, attempt < limit else { return .giveUp }
        let delay = min(2 * pow(2, Double(attempt)), 8)             // 2 s, 4 s, 8 s
        let start = isLive ? 0 : (position > 0 ? max(position - 2, 0) : requestedStart)
        return .retry(after: delay, start: start)
    }
}

/// The text of "Copy diagnostics": enough to tell a refused link from a dropped connection, and nothing that could log someone in.
/// Stream addresses carry the account (`/movie/<user>/<password>/<id>.mkv`, tokens in the query), so only the host and the file type
/// are kept, and any address inside mpv's own message is replaced.
public enum PlaybackDiagnostics {
    public static func report(kind: String, url: URL, position: Double, duration: Double, retries: Int,
                              error: String?, appVersion: String, system: String) -> String {
        [
            "SandokEldonia \(appVersion) · \(system)",
            "Type: \(kind)",
            "Server: \(url.scheme ?? "?")://\(url.host ?? "?")\(url.port.map { ":\($0)" } ?? "")",
            "File type: \(url.pathExtension.isEmpty ? "-" : url.pathExtension.lowercased())",
            "Position: \(clock(position)) / \(clock(duration))",
            "Retries: \(retries)",
            "Error: \(redacted(error) ?? "-")",
        ].joined(separator: "\n")
    }

    static func redacted(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text.replacingOccurrences(of: #"[A-Za-z][A-Za-z0-9+.\-]*://\S+"#, with: "<address>", options: .regularExpression)
    }

    private static func clock(_ s: Double) -> String {
        let t = Int(max(s.isFinite ? s : 0, 0)); return String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60)
    }
}

/// The player's own volume (mpv `volume`), moved by the arrow keys in steps of 5.
public enum PlayerVolume {
    public static let range: ClosedRange<Double> = 0...100
    public static let step = 5.0

    public static func stepped(from v: Double, up: Bool) -> Double {
        guard v.isFinite else { return range.upperBound }
        let snapped = (v / step).rounded() * step
        return min(max(snapped + (up ? step : -step), range.lowerBound), range.upperBound)
    }
}
