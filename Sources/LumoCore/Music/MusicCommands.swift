import Foundation

public enum MusicCommand: String, Sendable, CaseIterable {
    case playPause, next, previous

    /// Nummer des Befehls in MediaRemote (`MRMediaRemoteCommand`).
    public var mediaRemoteNumber: Int {
        switch self {
        case .playPause: 2
        case .next: 4
        case .previous: 5
        }
    }

    /// Befehl in den Wörterbüchern von Spotify und Musik.
    var appleScriptVerb: String {
        switch self {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
    }
}

/// Skripte zum Steuern und für das Cover. Spotify und Musik werden per AppleScript angesprochen (zuverlässig,
/// mit Cover), alle anderen Player über JXA im `osascript`-Prozess (`docs/now-playing.md`).
public enum MusicCommands {
    /// AppleScript-Name der App, wenn sie per AppleScript steuerbar ist.
    public static func appleScriptApp(for source: PlayerSource) -> String? {
        switch PlayerCatalog.canonical(source).bundleId {
        case "com.spotify.client": "Spotify"
        case "com.apple.Music": "Music"
        default: nil
        }
    }

    /// Spricht die App nur an, wenn sie schon läuft; `tell` würde sie sonst starten.
    public static func appleScript(_ command: MusicCommand, app: String) -> String {
        """
        if application "\(app)" is running then
          tell application "\(app)" to \(command.appleScriptVerb)
        end if
        """
    }

    /// JXA für `/usr/bin/osascript -l JavaScript`: schickt den Befehl an den Player, der gerade
    /// „Jetzt läuft“ hält. Gibt `true` oder `false` aus.
    public static func jxa(_ command: MusicCommand) -> String {
        """
        ObjC.import('Foundation');
        function run() {
          try {
            var bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
            if (!bundle.load) { return 'false'; }
            var controller = $.NSClassFromString('MRNowPlayingController').localRouteController;
            controller.sendCommandOptionsCompletion(\(command.mediaRemoteNumber), $.NSDictionary.alloc.init, null);
            delay(0.2);
            return 'true';
          } catch (e) {
            return 'false';
          }
        }
        """
    }

    /// Spulen bei Spotify und Musik: `player position` in Sekunden.
    public static func seekAppleScript(app: String, position: TimeInterval) -> String {
        """
        if application "\(app)" is running then
          tell application "\(app)" to set player position to \(seconds(position))
        end if
        """
    }

    /// Spulen bei allen anderen Playern über MediaRemote im `osascript`-Prozess (auf dem Mac zu prüfen).
    public static func seekJxa(position: TimeInterval) -> String {
        """
        ObjC.import('Foundation');
        function run() {
          try {
            var bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
            if (!bundle.load) { return 'false'; }
            ObjC.bindFunction('MRMediaRemoteSetElapsedTime', ['void', ['double']]);
            $.MRMediaRemoteSetElapsedTime(\(seconds(position)));
            delay(0.2);
            return 'true';
          } catch (e) {
            return 'false';
          }
        }
        """
    }

    /// Immer mit Punkt und zwei Nachkommastellen, unabhängig von der Sprache des Macs.
    private static func seconds(_ position: TimeInterval) -> String {
        String(format: "%.2f", max(0, position))
    }

    /// Cover des aktuellen Titels: Spotify liefert eine Bild-URL, Musik die Bilddaten. Andere Apps: `nil`.
    public static func artworkScript(app: String) -> String? {
        let expression: String
        switch app {
        case "Spotify": expression = "artwork url of current track"
        case "Music": expression = "data of artwork 1 of current track"
        default: return nil
        }
        return """
        if application "\(app)" is running then
          tell application "\(app)"
            try
              return \(expression)
            end try
          end tell
        end if
        return ""
        """
    }
}

/// Rohdaten, wie `osascript` sie ausgibt: `«data PNGf89504E47…»` (vier Zeichen Typ, dann Hex).
public enum AppleScriptData {
    public static func parse(_ output: String) -> Data? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("«data "), text.hasSuffix("»") else { return nil }
        let hex = Array(text.dropFirst(6).dropLast().utf8.dropFirst(4))
        guard !hex.isEmpty, hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        for i in stride(from: 0, to: hex.count, by: 2) {
            guard let high = nibble(hex[i]), let low = nibble(hex[i + 1]) else { return nil }
            data.append(high << 4 | low)
        }
        return data
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: c - 48
        case 65...70: c - 55
        case 97...102: c - 87
        default: nil
        }
    }
}
