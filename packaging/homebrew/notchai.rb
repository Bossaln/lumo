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
  # Afterwards: a pink GT-R drives off – notchai is installed, let's go.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/notchai.app"]

    require "io/console"

    car = [
      "              ___________________",
      "   _ ________/  /_______|_____\\  \\_________",
      "  |_|o  ___                         ___    \\",
      "  |___ /   \\_______________________/   \\___=|>",
      "       \\___/                       \\___/",
    ]
    pink = 205
    gray = 245
    done_text = "notchai ist installiert – los geht's!"

    if $stdout.tty?
      width = ((IO.console&.winsize || [24, 80])[1] || 80).clamp(50, 160)
      rows = car.size + 2 # Auto, Straße, Text
      spokes = ["-", "\\", "|", "/"]
      # Radkästen in der vierten Zeile: Speichen in der Mitte, Rad grau.
      wheels = []
      car[3].scan(/\/   \\/) { wheels << $~.begin(0) }
      hubs = wheels.map { |w| w + 2 }
      rims = wheels.flat_map { |w| (w..w + 4).to_a }
      render = lambda do |x, frame, exhaust, text|
        grid = Array.new(rows) { Array.new(width - 1) { [" ", nil] } }
        car.each_with_index do |line, row|
          line.each_char.with_index do |ch, col|
            # Speichen in den Radkästen drehen sich.
            ch = spokes[frame % 4] if row == 3 && hubs.include?(col)
            next if ch == " "
            c = x + col
            next if c.negative? || c >= width - 1
            color = row == 4 || (row == 3 && rims.include?(col)) ? gray : pink
            grid[row][c] = [ch, color]
          end
        end
        # Auspuffwolken und Fahrtwind hinter dem Wagen.
        exhaust.each do |(ex, ey, ch)|
          grid[ey][ex] = [ch, 240] if ex.between?(0, width - 2) && grid[ey][ex][0] == " "
        end
        # Straße mit Mittelstreifen, die nach links zieht.
        (width - 1).times { |c| grid[car.size][c] = [((c + frame * 2) % 8 < 4 ? "-" : " "), 238] }
        if text
          start = [(width - 1 - text.size) / 2, 0].max
          text.each_char.with_index { |ch, i| grid[car.size + 1][start + i] = [ch, pink] if start + i < width - 1 }
        end
        grid.map do |cells|
          cells.map { |ch, color| color ? "\e[38;5;#{color}m#{ch}\e[0m" : ch }.join + "\e[K"
        end.join("\n")
      end

      print "\e[?25l"
      begin
        puts
        first = true
        draw = lambda do |*args|
          print "\e[#{rows - 1}A\r" unless first
          first = false
          print render.call(*args)
          $stdout.flush
        end
        x = 2.0
        # Motor läuft: Auspuff qualmt.
        10.times do |f|
          puffs = (1..(f % 3 + 1)).map { |i| [2 - i * 2 + 2, 3, i == 1 ? "~" : "."] }
          draw.call(x.round, 0, puffs, nil)
          sleep 0.07
        end
        # Losfahren und beschleunigen, bis der Wagen rechts verschwunden ist.
        speed = 0.6
        frame = 0
        while x < width
          x += speed
          speed = [speed * 1.12, 6.0].min
          frame += 1
          trail = (1..[(speed * 2).round, 10].min).flat_map do |i|
            [[x.round - i * 2, 2, "-"], [x.round - i * 3, 3, "="]]
          end
          draw.call(x.round, frame, trail, nil)
          sleep 0.03
        end
        draw.call(width + 5, frame, [], done_text)
        puts
      ensure
        print "\e[?25h"
      end
    else
      puts car.join("\n")
      puts done_text
    end
  end

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
