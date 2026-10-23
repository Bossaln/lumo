#!/usr/bin/env python3
"""Zeichnet docs/images/install.gif für die README: Terminal, getippter brew-Befehl, Homebrew-Ausgabe, dann der echte
GT-R aus `notchai-welcome`.

Der Wagen kommt aus einem Mitschnitt der echten Ausgabe (ANSI-Text), auf dem Mac in einem Terminal mit 72 Spalten:

    LANG=en_US.UTF-8 script -q /tmp/welcome.txt /Applications/notchai.app/Contents/MacOS/notchai-welcome

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
W, H = 960, 540
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

# GT-R-Bilder aus dem Mitschnitt: jedes Bild beginnt nach „Cursor 6 Zeilen hoch“.
raw = open(capture, encoding="utf-8", errors="replace").read()
chunks = raw.split("\x1b[6A")


def parse_frame(chunk):
    """Zeilen aus (Zeichen, Farbe) eines Bildes."""
    rows, row, color = [], [], None
    i = 0
    while i < len(chunk):
        c = chunk[i]
        if c == "\x1b":
            m = re.match(r"\x1b\[([0-9;?]*)([A-Za-z])", chunk[i:])
            if m:
                params, cmd = m.group(1), m.group(2)
                if cmd == "m":
                    color = PALETTE.get(int(params.split(";")[-1])) if params.startswith("38;5") else None
                i += m.end()
                continue
        if c == "\n":
            rows.append(row)
            row = []
        elif c != "\r":
            row.append((c, color))
        i += 1
    rows.append(row)
    return rows[-7:]


frames_gtr = [parse_frame(c) for c in chunks]
frames_gtr[0] = frames_gtr[0][-7:]

prompt = "~ % "
command = "brew install --cask bossaln/tap/notchai"
brew_lines = [
    [("==> ", BLUE), ("Tapping bossaln/tap", TEXT)],
    [("==> ", BLUE), ("Downloading notchai-0.3.0.zip", TEXT)],
    [("######################################################### 100.0%", DIM)],
    [("==> ", BLUE), ("Installing Cask ", TEXT), ("notchai", GREEN)],
    [("==> ", BLUE), ("Moving App 'notchai.app' to '/Applications/notchai.app'", TEXT)],
]


def base():
    image = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((32, 32, W - 32, H - 32), radius=14, fill=WINDOW)
    draw.rounded_rectangle((32, 32, W - 32, 68), radius=14, fill=BAR)
    draw.rectangle((32, 54, W - 32, 68), fill=BAR)
    for x, color in ((54, (255, 95, 87)), (74, (254, 188, 46)), (94, (40, 200, 64))):
        draw.ellipse((x - 6, 44, x + 6, 56), fill=color)
    title = "Install notchai"
    draw.text(((W - draw.textlength(title, font=title_font)) / 2, 41), title, font=title_font, fill=(150, 154, 164))
    return image, draw


def text_line(draw, y, parts, font=mono):
    x = LEFT
    for text, color in parts:
        draw.text((x, y), text, font=font, fill=color)
        x += CHAR_W * len(text)


frames, durations = [], []


def scene(typed, brew_count, gtr=None, caret=True, done=False):
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
    if gtr is not None:
        y += LINE_H // 2
        for row in gtr:
            x = LEFT
            for ch, color in row[:COLS]:
                if ch != " ":
                    draw.text((x, y), ch, font=mono, fill=color or TEXT)
                x += CHAR_W
            y += LINE_H
    if done:
        y += LINE_H // 2
        # Kleiner Bierkrug statt Emoji (die Monospace-Schrift hat keins).
        mx = LEFT + 1
        draw.rectangle((mx, y + 6, mx + 9, y + 17), fill=(240, 176, 60))
        draw.rectangle((mx, y + 3, mx + 9, y + 6), fill=(245, 245, 240))
        draw.rectangle((mx + 10, y + 8, mx + 13, y + 14), outline=(240, 176, 60), width=2)
        text_line(draw, y, [("   ", TEXT), ("notchai was successfully installed!", TEXT)])
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
# Der GT-R: Motor läuft (10 Bilder à 70 ms), dann fährt er los (je 30 ms).
for index, gtr in enumerate(frames_gtr):
    frames.append(scene(command, len(brew_lines), gtr)); durations.append(70 if index < 10 else 30)
frames.append(scene(command, len(brew_lines), frames_gtr[-1], done=True)); durations.append(3500)

frames[0].save(out, save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True, disposal=1)
print(out, len(frames), "Bilder")
