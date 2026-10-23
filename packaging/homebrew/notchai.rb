# Vorlage für den Cask im Tap Bossaln/homebrew-tap (Casks/notchai.rb).
# Der Release-Workflow ersetzt @VERSION@ und @SHA256@ und schiebt die Datei in den Tap.
cask "notchai" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/Bossaln/notchai/releases/download/v#{version}/notchai-#{version}.zip"
  name "notchai"
  desc "Turns the MacBook notch into a control center for Claude Code and Codex"
  homepage "https://github.com/Bossaln/notchai"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "notchai.app"

  # notchai is signed with its own certificate, not notarized by Apple. Without this step Gatekeeper
  # would refuse to open it ("Apple could not verify …").
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/notchai.app"]
  end

  uninstall quit: "com.bossaln.notchai"

  zap trash: [
    "~/Library/Application Support/notchai",
    "~/Library/Logs/notchai",
  ]

  caveats <<~EOS
    ┌─────────────────────────────────────────────────────────────┐
    │  notchai is installed. Your notch is about to get busy.     │
    └─────────────────────────────────────────────────────────────┘

    Start it:
      open -a notchai

    On first launch a setup assistant connects Claude Code and Codex.
    It backs up your settings first and can undo everything later.

    Codex: run `codex` once in a terminal and choose
      "Trust all and continue" so notchai's hooks may run.

    Optional permissions (System Settings › Privacy & Security):
      Accessibility  double-tap right ⌘ for the office, typing replies
      Automation     cover art and controls for Spotify and Music

    The interface is in German. Updates: `brew upgrade --cask notchai`
    or the update button in notchai's settings.

    Before uninstalling, remove the hooks in notchai:
      Settings › Agenten › "Alles entfernen"
  EOS
end
