import Foundation

/// Spulen mit der Maus im Fortschrittsbalken.
public enum MusicScrub {
    public static func position(fraction: Double, duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return min(max(fraction, 0), 1) * duration
    }

    /// Nach dem Loslassen zeigt der Balken die neue Stelle, bis der Player sie meldet; sonst spränge er
    /// kurz zurück auf die alte.
    public struct Override: Equatable, Sendable {
        public static let lifetime: TimeInterval = 3
        public static let tolerance: TimeInterval = 1.5

        public var position: TimeInterval
        public var track: String
        public var playing: Bool
        public var at: Date

        public init(position: TimeInterval, track: String, playing: Bool, at: Date) {
            self.position = position
            self.track = track
            self.playing = playing
            self.at = at
        }

        public func position(at now: Date) -> TimeInterval {
            position + (playing ? max(0, now.timeIntervalSince(at)) : 0)
        }

        /// Erledigt, wenn der Player die neue Stelle meldet, der Titel wechselt oder die Frist um ist.
        public func isSettled(by item: NowPlaying?, trackKey: String?, now: Date) -> Bool {
            if now.timeIntervalSince(at) > Self.lifetime || trackKey != track { return true }
            guard let reported = item?.position(at: now) else { return false }
            return abs(reported - position(at: now)) < Self.tolerance
        }
    }
}
