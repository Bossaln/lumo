import Foundation

/// Systemweites „Jetzt läuft“ über JXA: `/usr/bin/osascript -l JavaScript -e <script>`. `osascript` ist
/// von Apple signiert und darf MediaRemote lesen; notchai selbst lädt MediaRemote nie (`docs/now-playing.md`).
public enum NowPlayingProbe {
    /// Gibt als letzten Ausdruck JSON oder `null` aus (`console.log` ginge auf stderr).
    public static let script = #"""
    ObjC.import('Foundation');
    function run() {
      try {
        var bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
        if (!bundle.load) { return 'null'; }
        var Request = $.NSClassFromString('MRNowPlayingRequest');
        var item = Request.localNowPlayingItem;
        if (!item || !item.js) { return 'null'; }
        var info = item.nowPlayingInfo;
        var get = function (key) {
          try { var v = ObjC.unwrap(info.valueForKey(key)); return (v === undefined || v === null) ? null : v; }
          catch (e) { return null; }
        };
        var app = null, bundleId = null;
        try {
          var client = Request.localNowPlayingPlayerPath.client;
          app = ObjC.unwrap(client.displayName) || null;
          bundleId = ObjC.unwrap(client.bundleIdentifier) || null;
        } catch (e) {}
        var position = null;
        try { position = ObjC.unwrap(item.metadata.calculatedPlaybackPosition); } catch (e) {}
        if (typeof position !== 'number') { position = get('kMRMediaRemoteNowPlayingInfoElapsedTime'); }
        return JSON.stringify({
          title: get('kMRMediaRemoteNowPlayingInfoTitle'),
          artist: get('kMRMediaRemoteNowPlayingInfoArtist'),
          album: get('kMRMediaRemoteNowPlayingInfoAlbum'),
          duration: get('kMRMediaRemoteNowPlayingInfoDuration'),
          position: position,
          rate: get('kMRMediaRemoteNowPlayingInfoPlaybackRate'),
          app: app,
          bundleId: bundleId
        });
      } catch (e) {
        return 'null';
      }
    }
    """#

    /// Ausgabe der Abfrage auswerten. Alles außer einem Objekt mit Titel heißt „nichts läuft“.
    public static func parse(_ output: Data, now: Date) -> NowPlaying? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: output), let row = value.objectValue,
              let title = row["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        func text(_ key: String) -> String? {
            row[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        }
        let bundleId = text("bundleId")
        let source = PlayerSource(bundleId: bundleId, name: text("app") ?? bundleId ?? L("Unbekannt"))
        let duration = row["duration"]?.numberValue.flatMap { $0 > 0 ? $0 : nil }
        return NowPlaying(source: source, title: title, artist: text("artist"), album: text("album"),
                          duration: duration, elapsed: row["position"]?.numberValue, timestamp: now,
                          isPlaying: (row["rate"]?.numberValue ?? 0) > 0, reportedAt: now)
    }
}

/// Benachrichtigungen, die Spotify und Apple Music bei jedem Wechsel über `DistributedNotificationCenter`
/// senden. Brauchen keine Berechtigung und sind die sichere Grundlage für beide Apps.
public enum PlayerNotification {
    public static let spotify = "com.spotify.client.PlaybackStateChanged"
    public static let music = "com.apple.Music.playerInfo"
    public static let names = [spotify, music]

    /// „Stopped“ ergibt ein `NowPlaying` ohne Titel; der `NowPlayingStore` versteht das als „weg“.
    public static func parse(name: String, userInfo: [String: Any], now: Date) -> NowPlaying? {
        let source: PlayerSource
        let durationKey: String
        switch name {
        case spotify:
            source = PlayerSource(bundleId: "com.spotify.client", name: "Spotify")
            durationKey = "Duration"
        case music:
            source = PlayerSource(bundleId: "com.apple.Music", name: "Musik")
            durationKey = "Total Time"
        default:
            return nil
        }
        let state = userInfo["Player State"] as? String ?? ""
        let title = state == "Stopped" ? "" : (userInfo["Name"] as? String ?? "")
        func text(_ key: String) -> String? {
            (userInfo[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        return NowPlaying(source: source, title: title, artist: text("Artist"), album: text("Album"),
                          duration: number(userInfo[durationKey]).flatMap { $0 > 0 ? $0 / 1000 : nil },
                          elapsed: number(userInfo["Playback Position"]), timestamp: now,
                          isPlaying: state == "Playing", reportedAt: now)
    }

    /// Zahlen kommen je nach App als Int, Double oder NSNumber.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: d
        case let i as Int: Double(i)
        case let n as NSNumber: n.doubleValue
        default: nil
        }
    }
}
