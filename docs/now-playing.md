# „Jetzt läuft“ auf macOS 15.4 bis 27

Stand: 22.10.2026. Woher notchai weiß, was gerade spielt, und wie es die Wiedergabe steuert.

## Ausgangslage

- **Seit macOS 15.4 ist MediaRemote gesperrt.** Liest eine App das private `MediaRemote.framework` direkt, bekommt sie keine Daten mehr. `mediaremoted` prüft den aufrufenden Prozess; nur Prozesse von Apple (Bundle-ID beginnt mit `com.apple.`) dürfen lesen. Das gilt laut aktuellen Berichten auch auf macOS 26 ([cmux PR #21695](https://github.com/manaflow-ai/cmux/pull/21695), [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)).
- Die Sperre hängt am **Prozess**, nicht an der Schnittstelle ([roger #27](https://github.com/MaxBroda/roger/issues/27), gemessen auf macOS 26.6.2). Ein von Apple signiertes Hilfsprogramm darf also weiter lesen.
- Eine öffentliche Schnittstelle für „Jetzt läuft“ anderer Apps gibt es auch auf macOS 27 nicht (keine Apple-Dokumentation gefunden).

## Wege und Entscheidung

### 1. Benachrichtigungen von Spotify und Apple Music (genommen, Grundlage)

- Spotify sendet `com.spotify.client.PlaybackStateChanged`, Apple Music `com.apple.Music.playerInfo`, beide über `DistributedNotificationCenter`, bei jedem Wechsel (Titel, Pause, Weiter).
- Keine Berechtigung nötig, keine Abfrage, kein Strom im Leerlauf.
- Felder (bekannt aus vielen Werkzeugen, auf dem Mac zu bestätigen):
  - **Spotify:** „Player State“ (`Playing`/`Paused`/`Stopped`), „Name“, „Artist“, „Album“, „Duration“ (ms), „Playback Position“ (s), „Track ID“.
  - **Musik:** „Player State“, „Name“, „Artist“, „Album“, „Total Time“ (ms).

### 2. JXA über `/usr/bin/osascript` (genommen, für alle anderen Player)

- `osascript` ist von Apple signiert und darf MediaRemote laden. Ein JXA-Skript liest `MRNowPlayingRequest.localNowPlayingItem.nowPlayingInfo` (Titel, Interpret, Album, Dauer, Rate) und `localNowPlayingPlayerPath.client.displayName` (Name der App) ([Gist von SKaplanOfficial](https://gist.github.com/SKaplanOfficial/f9f5bdd6455436203d0d318c078358de), „Works on macOS 15.4+, including macOS 26 beta 1“).
- Gemessen: 60–70 ms pro Aufruf mit Chrome ([roger #27](https://github.com/MaxBroda/roger/issues/27)).
- Grenzen:
  - Cover über JXA geht nicht (bleibt leer).
  - Keine Echtzeit-Meldungen, nur Abfragen.
  - `console.log` landet auf stderr; das Ergebnis ist der letzte Ausdruck.
  - Ob `client.bundleIdentifier` gelesen werden kann, ist nicht belegt. Deshalb versucht notchai beides und ordnet notfalls über den App-Namen zu.
- Steuern geht ebenfalls: `MRNowPlayingController.localRouteController` mit `sendCommand:options:completion:` (2 = Play/Pause umschalten, 4 = Weiter, 5 = Zurück). Auf 26.2 beta mit Spotify und YouTube bestätigt, auf 26.1 von einem Nutzer nicht reproduziert.
- **Folge:** Fällt dieser Weg auf einer künftigen macOS-Version weg, zeigt notchai nur noch Spotify und Apple Music (über Weg 1).

### 3. `mediaremote-adapter` (Perl + eigenes Framework): bewusst nicht genommen

- Funktioniert laut Projekt auch auf macOS 27.0 (Testabzeichen vom 4.9.2026). Liefert alles inklusive Cover und Live-Meldungen, ist BSD-lizenziert ([GitHub](https://github.com/ungive/mediaremote-adapter)).
- Gründe dagegen:
  - fremder, mitgelieferter Code;
  - hängt an `/usr/bin/perl`, das Apple laut einem Bericht nicht mehr standardmäßig mitliefern will;
  - braucht ein eigenes Objective-C-Framework im Bundle.
- Bleibt die Rückfallebene, falls JXA auf macOS 27 nicht mehr geht.

### 4. Cover

- **Apple Music:** AppleScript `data of artwork 1 of current track`.
- **Spotify:** AppleScript `artwork url of current track`, dann Laden des Bildes von Spotifys Bildserver.
- Beides braucht einmal die Automations-Erlaubnis („notchai möchte Spotify steuern“). Dafür steht `NSAppleEventsUsageDescription` in der `Info.plist`.
- Für Browser und andere Player gibt es kein Cover; notchai zeigt dann ein Symbol der App.

## Musikdienst oder Video?

- MediaRemote meldet nur die **App**, nicht die Webseite.
- Die Faustregel für Browser stützt sich auf das Album: YouTube Music, Spotify Web und Apple Music im Web melden ein Album, YouTube-Videos nicht (Media Session API). Bei „Nur Musikdienste“ zeigt notchai Browser-Inhalte nur mit Album. Das lässt sich abschalten, und jede App lässt sich einzeln auf „immer“ oder „nie“ stellen.

## Umsetzung

- Befehle und Cover für Spotify und Musik laufen ebenfalls über `/usr/bin/osascript` (AppleScript), nicht über `NSAppleScript` im eigenen Prozess: So hat jeder Aufruf eine Frist (2 s) und blockiert nie die Notch.
- Eigene Builds ohne Zertifikat sind ad hoc signiert; ihre Signatur ändert sich mit jedem Build. macOS kann dann nach einem Update erneut fragen, ob notchai Spotify bzw. Musik steuern darf. Release-Builds tragen eine feste Signatur.

## Echte Balken (Visualizer)

Stand: 23.10.2026.

- **Weg:** Core-Audio-Taps (`CATapDescription`, `AudioHardwareCreateProcessTap`, ab macOS 14.2). Der Tap hängt an
  einem privaten Aggregat-Gerät; ein IO-Block bekommt den Ton als Float32 und schreibt ihn gemischt (Mono) in einen
  Ringpuffer (`AudioSampleRing`). Gezeichnet wird mit bis zu 60 Bildern pro Sekunde: FFT über die letzten
  1024 Samples, logarithmische Bänder, je Band selbst eingepegelt (`SpectrumAnalyzer`, `VisualizerBars`, getestet in
  Core). Nichts wird gespeichert oder verschickt.
- **Welcher Ton:** bevorzugt nur die Prozesse des Players, die gerade Ton ausgeben (gleiche Bundle-ID oder ein Helfer
  darunter, etwa `com.google.Chrome.helper`). Findet sich keiner (Safari spielt über `com.apple.WebKit.GPU`), greift
  notchai den ganzen Ton ab, außer seinem eigenen.
- **Freigabe:** `NSAudioCaptureUsageDescription` in der `Info.plist` (deutsch und englisch über
  `InfoPlist.strings`). macOS fragt beim ersten Start des Taps; die Freigabe steht danach unter Datenschutz &
  Sicherheit › Bildschirm- & Systemaudioaufnahme. Ohne Freigabe liefert der Tap nur Nullen. notchai erkennt das
  daran, dass nach 5 s noch nie ein Sample ungleich null kam, zeigt in Einstellungen › Musik einen Hinweis und lässt
  die Balken solange animiert tanzen.
- **Wann:** nur solange Balken zu sehen sind und Musik spielt (eingeklappt, Reiter „Musik“, Titelanzeige). Anlegen
  und Abbauen laufen auf einer eigenen Warteschlange, nie auf dem Hauptthread.
- **Ausgabe gewechselt** (AirPods verbunden …): Bleibt der Zähler des Ringpuffers zwei Sekunden stehen, startet
  notchai den Tap neu.
- Zu prüfen auf dem Mac: Ob macOS während des Abgriffs ein Aufnahme-Symbol in der Menüleiste zeigt, und welche
  Prozesse Spotify, Musik und die Browser tatsächlich melden (`kAudioProcessPropertyBundleID`).

## Offene Punkte

Prüfhilfe: Einstellungen › Entwickler › „Jetzt-läuft-Rohdaten“ kopieren. Das zeigt die letzte JXA-Ausgabe und die letzten Benachrichtigungen samt aller Schlüssel.

- JXA-Abfrage auf macOS 27:
  - Kommt überhaupt etwas?
  - Gibt es `bundleIdentifier`?
  - Wie lange dauert ein Aufruf?
  - Meldet Spotify die Rate wie Chrome (0/1)?
- JXA-Befehle auf macOS 27 (Play/Pause bei YouTube im Browser).
- Schlüssel der Spotify- und Musik-Benachrichtigungen.
- Ob YouTube Music und Spotify Web im Browser tatsächlich ein Album melden und YouTube-Videos nicht.
- Ob `delay(0.2)` im JXA-Befehl reicht, damit der Befehl ankommt, bevor `osascript` endet.
- Spulen bei Browsern: `ObjC.bindFunction('MRMediaRemoteSetElapsedTime', …)` im `osascript`-Prozess (nicht belegt). Spotify und Musik spulen per AppleScript `set player position`.
