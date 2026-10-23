<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="notchai icon">
</p>

<h1 align="center">notchai</h1>

<p align="center">
  Your MacBook notch as a control center for <b>Claude Code</b> and <b>Codex</b>.<br>
  See who is working, who is waiting for you and who is done – and answer right from the notch.
</p>

<p align="center">
  <a href="https://github.com/Bossaln/notchai/releases/latest"><img src="https://img.shields.io/github/v/release/Bossaln/notchai?label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20silicon-required-black" alt="Apple silicon">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="GPL-3.0"></a>
</p>

```sh
brew install --cask bossaln/tap/notchai
```

> [!NOTE]
> The interface is currently in **German**. An English translation is welcome – see [Contributing](#contributing).

## What it does

**Signals in the notch.** When an agent asks for permission, asks a question, finishes or fails, the notch opens
and glows in that agent's color. Allow, deny, pick an answer or type a reply without leaving what you are doing.
Choose between three styles: a flat island next to the camera, a wide banner, or a taller panel.

**Every session at a glance.** Hover over the notch to see all running Claude Code and Codex sessions: title,
project, last step, how full the context is, and what you got done today. Click a session to bring its window to the
front, or reply to it directly. Works with the Claude desktop app, the terminal, VS Code and cmux.

**Now playing.** Spotify, Apple Music and most other players: cover art, title, a progress bar you can scrub,
playback controls, a backdrop in the colors of the cover and a soft glow. While music plays, a compact view with
dancing bars sits right next to the camera.

**A pixel warehouse for your agents.** Every session becomes a little character in a warehouse with two tuned cars,
a couch, a fridge full of energy drinks, a projector and a bed. Characters sit at their desks while working, wait
beside them when they need you, grab a drink when they are done and go to bed after a while. The light follows the
real sun. Double-tap the right <kbd>⌘</kbd> key to open the warehouse in a big window.

<p align="center">
  <img src="docs/images/warehouse.png" width="704" alt="The pixel warehouse at night (preview rendering)">
</p>

**Almost everything is a setting.** True black background so the notch blends into the camera cutout, agent colors,
signal style, animations, glow, sounds, which tab opens on hover, music sources, warehouse size and lighting, and more.

## Never in the way

- **notchai never blocks your agents.** If the app is not running or does not answer, its hook gives up immediately
  and Claude Code and Codex behave exactly as without notchai.
- **Your settings stay yours.** The setup assistant writes its hooks to `~/.claude/settings.json` and
  `~/.codex/hooks.json` only after making a backup, shows what it changes and removes everything with one click.
  It never writes `~/.codex/config.toml`.
- **Nothing leaves your Mac.** No account, no analytics. The only network request is the optional update check
  against this repository's releases.

## Requirements

- A MacBook with a notch (Apple silicon) running macOS 14 Sonoma or later
- [Claude Code](https://code.claude.com/docs) and/or [Codex](https://github.com/openai/codex)

## Install

### Homebrew (recommended)

```sh
brew install --cask bossaln/tap/notchai
```

This adds the tap [`Bossaln/homebrew-tap`](https://github.com/Bossaln/homebrew-tap) and installs notchai to
`/Applications`. Afterwards, `brew upgrade --cask notchai` keeps it up to date – or use the update button in
notchai's settings, which does the same.

<details>
<summary>Why a tap, and why does the cask remove the quarantine flag?</summary>

notchai is signed with its own certificate but not notarized by Apple (that needs a paid Apple Developer account).
Homebrew's main repository only accepts notarized apps, so notchai lives in its own tap. Without notarization,
macOS Gatekeeper would refuse to open the app, so the cask removes the quarantine flag after installing. Because
every release is signed with the same certificate, macOS keeps the permissions you grant across updates.

</details>

### Manual download

Download `notchai-<version>.zip` from the [latest release](https://github.com/Bossaln/notchai/releases/latest),
unzip it and move `notchai.app` to `/Applications`. On first launch macOS will block it; allow it under
**System Settings › Privacy & Security › Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/notchai.app
```

## First launch

1. Your screen edges light up and the glow pulls into the notch, which keeps glowing until setup is done. A setup assistant connects **Claude Code** and **Codex** and lets you try the notch styles, colors and session views right away.
2. **Codex** only runs hooks you trusted: start `codex` once in a terminal and choose **"Trust all and continue"**.
3. Optional permissions, only needed for these features
   (System Settings › Privacy & Security):
   - **Accessibility** – double-tap right <kbd>⌘</kbd> for the warehouse, typing replies into a session's window
   - **Automation** – cover art and playback controls for Spotify and Music

Everything else is in **Settings** (menu bar icon › Einstellungen). Turn on **Allgemein › Entwickleroptionen** for a developer page with test signals, raw diagnostics and a full reset to a fresh install.

## Uninstall

1. In notchai: **Einstellungen › Agenten › „Alles entfernen“** removes the hooks from Claude Code and Codex.
2. Then:

   ```sh
   brew uninstall --cask notchai          # add --zap to also delete settings and logs
   ```

## Build from source

You need the Xcode Command Line Tools with Swift 6 (no full Xcode required).

```sh
git clone https://github.com/Bossaln/notchai.git
cd notchai
swift test              # run the tests
scripts/run.sh          # build the app bundle and launch it
scripts/install.sh      # pull, test, build and install to /Applications
```

A build made from a source folder updates itself from that folder: the update button pulls with Git
(fast-forward only), rebuilds and relaunches.

### Project layout

| Path | What lives there |
| --- | --- |
| `Sources/NotchaiCore` | Logic without UI: hooks, session book, transcript readers, now playing, the warehouse renderer and simulation. Fully unit tested. |
| `Sources/Notchai` | The app: AppKit panel at the notch, SwiftUI views, settings, setup assistant |
| `Sources/notchai-hook` | The small program Claude Code and Codex call as a hook. Always exits 0, never blocks. |
| `Tests/NotchaiCoreTests` | Tests (Swift Testing) with synthetic fixtures |
| `docs/` | Notes on how the agents' hooks and macOS "now playing" behave (German) |
| `scripts/`, `packaging/` | Building, installing, releasing and the Homebrew cask |

## Contributing

Issues and pull requests are welcome. Please add tests for new logic in `NotchaiCore` (Swift Testing:
`import Testing`, `@Test`, `#expect`). Code comments and the interface are German for now; an English
localization of the interface would be a great contribution. How releases are made is described in
[`docs/releasing.md`](docs/releasing.md).

## License

notchai is free software under the [GNU General Public License v3.0](LICENSE). © 2026 Bossaln

notchai is an independent project and not affiliated with Anthropic or OpenAI. Claude and Claude Code are
trademarks of Anthropic; Codex is a trademark of OpenAI.
