# Der letzte Stand des alten Casks „notchai“ im Tap Bossaln/homebrew-tap (Casks/notchai.rb).
# Seit 0.8.0 heißt die App lumo; dieser Cask bleibt veraltet stehen und nennt den Ersatz.
# `brew upgrade` meldet: „notchai has been deprecated because it was renamed to lumo!“ und den Befehl für lumo.
cask "notchai" do
  version "0.7.0"
  sha256 "@SHA256@"

  url "https://github.com/Bossaln/lumo/releases/download/v#{version}/notchai-#{version}.zip"
  name "notchai"
  desc "Turns the MacBook notch into a control center for Claude Code and Codex (renamed to lumo)"
  homepage "https://github.com/Bossaln/lumo"

  deprecate! date: "2026-10-25", because: "was renamed to lumo", replacement_cask: "bossaln/tap/lumo"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "notchai.app"

  uninstall quit: "com.bossaln.notchai"

  zap trash: [
    "~/Library/Application Support/notchai",
    "~/Library/Caches/com.bossaln.notchai",
    "~/Library/HTTPStorages/com.bossaln.notchai",
    "~/Library/HTTPStorages/com.bossaln.notchai.binarycookies",
    "~/Library/Logs/notchai",
    "~/Library/Preferences/com.bossaln.notchai.plist",
    "~/Library/Saved Application State/com.bossaln.notchai.savedState",
  ]
end
