#!/usr/bin/env python3
"""Zeichnet docs/images/install.gif für die README: Terminal, getippter brew-Befehl, Homebrew-Ausgabe, dann die echte
Begrüßungsszene aus `lumo-welcome` (MacBook, Leuchten, Signal, Musik).

Die Szene kommt aus einem Mitschnitt der echten Ausgabe (ANSI-Text) in einem Pseudo-Terminal mit 72 Spalten und
15 Zeilen (so zeichnet das Programm an Ort und Stelle statt im Vollbild), zum Beispiel mit Pythons `pty`:

    LANG=en_US.UTF-8 python3 capture.py /tmp/welcome.txt 72 15 /Applications/lumo.app/Contents/MacOS/lumo-welcome

Braucht Pillow (`pip install pillow`); Schriften: DejaVu Sans Mono und Inter, sonst Menlo und SF (macOS).
Aufruf aus dem Projektordner: python3 scripts/install-gif.py /tmp/welcome.txt
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
capture = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "docs", "images", "install.gif")
W, H = 960, 640
COLS = 72
BG = (11, 12, 16)
WINDOW = (22, 24, 29)
BAR = (30, 33, 39)
TEXT = (220, 222, 228)
DIM = (128, 132, 142)
GREEN = (112, 214, 140)
BLUE = (120, 170, 255)
PALETTE = {205: (255, 95, 175), 245: (138, 138, 138), 240: (88, 88, 88), 238: (68, 68, 68)}



def font(names, size):
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


mono = font(["/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", "DejaVuSansMono.ttf", "/System/Library/Fonts/Menlo.ttc"], 15)
title_font = font(["/usr/share/fonts/opentype/inter/Inter-SemiBold.otf", "/System/Library/Fonts/SFNS.ttf",
                   "/System/Library/Fonts/Helvetica.ttc"], 14)
CHAR_W = mono.getlength("M")
LINE_H = 21
LEFT, TOP = 56, 92

# Die Szene aus dem Mitschnitt: ein kleines virtuelles Terminal liest die Steuerzeichen (Farben, Cursor hoch,
# Zeile löschen) und merkt sich vor jedem Cursorsprung ein Bild.
def xterm(i):
    base = [(0,0,0),(205,0,0),(0,205,0),(205,205,0),(0,0,238),(205,0,205),(0,205,205),(229,229,229),
            (127,127,127),(255,0,0),(0,255,0),(255,255,0),(92,92,255),(255,0,255),(0,255,255),(255,255,255)]
    if i < 16: return base[i]
    if i < 232:
        i -= 16; r, g, b = i // 36, (i // 6) % 6, i % 6
        return tuple(0 if v == 0 else 55 + v * 40 for v in (r, g, b))
    v = 8 + (i - 232) * 10
    return (v, v, v)

class Term:
    def __init__(self, cols=120, rows=60):
        self.cols, self.rows = cols, rows
        self.grid = [[(" ", None, None, False) for _ in range(cols)] for _ in range(rows)]
        self.x = self.y = 0
        self.fg = self.bg = None; self.bold = False
        self.frames = []
    def snapshot(self):
        self.frames.append([row[:] for row in self.grid])
    def feed(self, s):
        i = 0
        while i < len(s):
            c = s[i]
            if c == "\x1b":
                m = re.match(r"\x1b\[([0-9;?]*)([A-Za-z])", s[i:])
                if m:
                    p, cmd = m.group(1), m.group(2); i += m.end()
                    if cmd == "m":
                        parts = [int(v) for v in p.split(";") if v != ""] or [0]
                        j = 0
                        while j < len(parts):
                            v = parts[j]
                            if v == 0: self.fg = self.bg = None; self.bold = False
                            elif v == 1: self.bold = True
                            elif v == 38 and parts[j+1] == 5: self.fg = parts[j+2]; j += 2
                            elif v == 48 and parts[j+1] == 5: self.bg = parts[j+2]; j += 2
                            j += 1
                    elif cmd == "A": self.snapshot(); self.y = max(self.y - int(p or 1), 0)
                    elif cmd == "H":
                        if self.frames or any(ch != " " for row in self.grid for ch, *_ in row): self.snapshot()
                        r, _, col = (p or "1;1").partition(";"); self.y, self.x = int(r or 1) - 1, int(col or 1) - 1
                    elif cmd == "J": self.grid = [[(" ", None, None, False) for _ in range(self.cols)] for _ in range(self.rows)]
                    elif cmd == "K":
                        for k in range(self.x, self.cols): self.grid[self.y][k] = (" ", None, None, False)
                    continue
            if c == "\n": self.y += 1; self.x = 0
            elif c == "\r": self.x = 0
            elif c >= " ":
                if self.y < self.rows and self.x < self.cols:
                    self.grid[self.y][self.x] = (c, self.fg, self.bg, self.bold)
                self.x += 1
            i += 1
        self.snapshot()


SCENE_COLS = 72
raw = open(capture, encoding="utf-8", errors="replace", newline="").read()
term = Term(cols=SCENE_COLS, rows=40)
term.feed(raw)
# Jedes Bild: die 15 Zeilen der Szene; sie beginnt nach dem ersten Zeilenumbruch in Zeile 1.
SCENE_ROWS = 15
frames_scene = [frame[1:1 + SCENE_ROWS] for frame in term.frames]
frames_scene = [frame for frame in frames_scene if any(ch != " " for row in frame for ch, *_ in row)]

prompt = "~ % "
command = "brew install --cask bossaln/tap/lumo"
brew_lines = [
    [("==> ", BLUE), ("Tapping bossaln/tap", TEXT)],
    [("==> ", BLUE), ("Downloading lumo-0.9.1.zip", TEXT)],
    [("######################################################### 100.0%", DIM)],
    [("==> ", BLUE), ("Installing Cask ", TEXT), ("lumo", GREEN)],
    [("==> ", BLUE), ("Moving App 'lumo.app' to '/Applications/lumo.app'", TEXT)],
]


def base():
    image = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((32, 32, W - 32, H - 32), radius=14, fill=WINDOW)
    draw.rounded_rectangle((32, 32, W - 32, 68), radius=14, fill=BAR)
    draw.rectangle((32, 54, W - 32, 68), fill=BAR)
    for x, color in ((54, (255, 95, 87)), (74, (254, 188, 46)), (94, (40, 200, 64))):
        draw.ellipse((x - 6, 44, x + 6, 56), fill=color)
    title = "Install lumo"
    draw.text(((W - draw.textlength(title, font=title_font)) / 2, 41), title, font=title_font, fill=(150, 154, 164))
    return image, draw


def mug(draw, mx, y):
    draw.rectangle((mx, y + 6, mx + 9, y + 17), fill=(240, 176, 60))
    draw.rectangle((mx, y + 3, mx + 9, y + 6), fill=(245, 245, 240))
    draw.rectangle((mx + 10, y + 8, mx + 13, y + 14), outline=(240, 176, 60), width=2)


def text_line(draw, y, parts, font=mono):
    x = LEFT
    for text, color in parts:
        draw.text((x, y), text, font=font, fill=color)
        x += CHAR_W * len(text)


frames, durations = [], []


def scene(typed, brew_count, picture=None, caret=True, done=False):
    image, draw = base()
    y = TOP
    text_line(draw, y, [(prompt, GREEN), (typed, TEXT)])
    if caret and brew_count == 0:
        x = LEFT + CHAR_W * (len(prompt) + len(typed))
        draw.rectangle((x, y + 2, x + CHAR_W - 1, y + 18), fill=(200, 200, 205))
    y += LINE_H
    for line in brew_lines[:brew_count]:
        text_line(draw, y, line)
        y += LINE_H
    if picture is not None:
        y += LINE_H // 2
        for row in picture:
            x = LEFT
            for ch, fg, bg, bold in row[:COLS]:
                if bg is not None:
                    draw.rectangle((x, y, x + CHAR_W - 1, y + LINE_H - 1), fill=xterm(bg))
                if ch == "\U0001F37A":
                    # Das Emoji belegt zwei Spalten; die Monospace-Schrift hat keins, also ein kleiner Bierkrug.
                    mug(draw, x, y)
                    x += CHAR_W
                elif ch != " ":
                    draw.text((x, y), ch, font=mono, fill=xterm(fg) if fg is not None else TEXT)
                x += CHAR_W
            y += LINE_H
    if done:
        y += LINE_H // 2
        # Kleiner Bierkrug statt Emoji (die Monospace-Schrift hat keins).
        mug(draw, LEFT + 1, y)
        text_line(draw, y, [("   ", TEXT), ("lumo was successfully installed!", TEXT)])
        y += LINE_H
        text_line(draw, y, [(prompt, GREEN)])
        x = LEFT + CHAR_W * len(prompt)
        draw.rectangle((x, y + 2, x + CHAR_W - 1, y + 18), fill=(200, 200, 205))
    return image


# Leeres Fenster, dann Tippen.
frames.append(scene("", 0)); durations.append(700)
for n in range(1, len(command) + 1):
    frames.append(scene(command[:n], 0)); durations.append(45 if command[n - 1] != " " else 90)
frames.append(scene(command, 0, caret=False)); durations.append(450)
for n in range(1, len(brew_lines) + 1):
    frames.append(scene(command, n)); durations.append(380 if n != 3 else 650)
# Die Szene: MacBook, Leuchten, Signal, Musik. Die Standzeiten entsprechen grob denen im Programm.
for index, picture in enumerate(frames_scene):
    frames.append(scene(command, len(brew_lines), picture)); durations.append(60)
frames.append(scene(command, len(brew_lines), frames_scene[-1], done=True)); durations.append(4000)

frames[0].save(out, save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True, disposal=1)
print(out, len(frames), "Bilder")
