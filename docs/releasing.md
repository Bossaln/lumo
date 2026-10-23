# Veröffentlichen

notchai wird über GitHub Releases und den eigenen Homebrew-Tap [`Bossaln/homebrew-tap`](https://github.com/Bossaln/homebrew-tap)
verteilt. Nutzer installieren mit:

```sh
brew install --cask bossaln/tap/notchai
```

## Wie es zusammenhängt

1. Der Workflow `.github/workflows/release.yml` startet bei einem Tag `v*` (oder per Hand unter
   **Actions › Release › Run workflow**).
2. Er testet, baut die App mit `scripts/package-release.sh` und signiert sie mit dem eigenen Zertifikat
   „notchai Signing“ (Secrets `NOTCHAI_CERT_P12`, `NOTCHAI_CERT_PASSWORD`).
3. Er legt das GitHub Release `vX.Y.Z` mit `notchai-X.Y.Z.zip` an (Versionshinweise erzeugt GitHub).
4. Er schreibt den Cask aus `packaging/homebrew/notchai.rb` mit Version und Prüfsumme nach
   `Bossaln/homebrew-tap/Casks/notchai.rb` (Secret `TAP_GITHUB_TOKEN`).
5. Installierte Apps finden die neue Version beim nächsten Update-Check und aktualisieren sich per `brew upgrade`.

## Eine neue Version veröffentlichen

```sh
git switch main && git pull
git tag v0.2.0
git push origin v0.2.0
```

Oder ohne Terminal: GitHub › **Actions › Release › Run workflow**, Version `0.2.0` eintragen.
Die Versionsnummer steht danach in der App (Einstellungen › Allgemein) und auf der Release-Seite.

## Einmalige Einrichtung

1. **Öffentliche Repositorys:** `Bossaln/notchai` (der Code) und `Bossaln/homebrew-tap` (leer anlegen,
   der Release-Workflow füllt es).
2. **Workflows aktivieren:** Die Workflow-Dateien liegen in `packaging/github-workflows/`, weil Werkzeuge ohne das
   GitHub-Recht „workflow“ sie nicht pushen dürfen. Einmal im notchai-Ordner:

   ```sh
   mkdir -p .github/workflows && git mv packaging/github-workflows/*.yml .github/workflows/
   git commit -m "Workflows aktivieren" && git push
   ```

3. **Zertifikat** (kostenlos, ohne Apple-Konto), auf dem Mac im notchai-Ordner:

   ```sh
   scripts/create-signing-certificate.sh
   ```

   Es erzeugt „notchai Signing“, legt es in den Schlüsselbund (dann signieren auch eigene Builds damit) und setzt
   die Secrets `NOTCHAI_CERT_P12` und `NOTCHAI_CERT_PASSWORD` (mit der GitHub-Kommandozeile `gh`, sonst steht am
   Ende, was von Hand einzutragen ist). **`signing/notchai-signing.p12` und `signing/password.txt` sicher
   aufbewahren.** Ein neues Zertifikat würde bei allen Nutzern die Freigaben (Bedienungshilfen) einmal zurücksetzen.
4. **Token für den Tap:** GitHub › Settings › Developer settings › Personal access tokens › **Fine-grained tokens** ›
   *Generate new token*:
   - Repository access: *Only select repositories* › `Bossaln/homebrew-tap`
   - Permissions: *Contents* › **Read and write**
   - Ablaufdatum nach Wunsch (läuft es ab, aktualisiert der Workflow den Tap nicht mehr und warnt)

   Den Token in `Bossaln/notchai` › Settings › Secrets and variables › Actions als `TAP_GITHUB_TOKEN` speichern.

Fehlt das Zertifikat, signiert der Workflow nur ad hoc und warnt; fehlt der Token, bleibt der Tap unverändert und der
Workflow warnt ebenfalls.

## Signatur und Gatekeeper

- notchai ist mit dem eigenen Zertifikat signiert, aber nicht von Apple notarisiert. Der Cask entfernt deshalb nach
  der Installation die Quarantäne-Markierung, sonst würde Gatekeeper die App sperren. Homebrew erlaubt das in eigenen
  Taps; im offiziellen Verzeichnis (`brew install notchai` ohne Tap) sind seit dem 1. 9. 2026 nur noch Apps erlaubt,
  die Gatekeeper bestehen.
- **Homebrew 7** (September 2026) warnt bei jedem Cask mit `postflight do … end`: „Calling `postflight` is deprecated!
  Use `postflight_steps` instead.“ `postflight_steps` erlaubt nur feste Schritte ohne eigenen Ruby-Code und läuft in
  einer Sandbox mit eigenem Pseudo-Terminal. Der Cask ruft darin `xattr` und das Programm `notchai-welcome` aus dem
  App-Bundle auf; das schreibt den fahrenden GT-R direkt nach `/dev/tty` (die Sandbox erlaubt das, Homebrew reicht die
  Zeichen sofort weiter). Beide Schritte dürfen scheitern (`must_succeed: false`), die Installation bricht dann nicht
  ab. Ältere Homebrew-Versionen ohne `postflight_steps` bekommen weiter den alten `postflight`-Block.
- Weil jede Version dieselbe Signatur trägt, behält macOS die Freigaben (Bedienungshilfen, Automation) über Updates.
- **Später ins offizielle Homebrew:** Dafür braucht es eine Apple Developer ID (99 $ pro Jahr), Notarisierung im
  Release-Workflow und genug Bekanntheit (bei eigener Einreichung mindestens 225 Sterne, 90 Forks oder 90 Beobachter;
  reicht jemand anderes ein, 75 Sterne bzw. 30 Forks oder Beobachter; das Repository muss mindestens 30 Tage alt sein).

## Ohne GitHub Actions (Notfall)

Auf dem Mac mit Zertifikat im Schlüsselbund:

```sh
scripts/package-release.sh 0.2.0
gh release create v0.2.0 build/notchai-0.2.0.zip --title "notchai 0.2.0" --generate-notes
```

Danach in `Bossaln/homebrew-tap/Casks/notchai.rb` `version` und `sha256` (steht in `build/notchai-0.2.0.zip.sha256`)
von Hand anpassen.
