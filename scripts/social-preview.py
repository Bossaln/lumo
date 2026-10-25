#!/usr/bin/env python3
"""Zeichnet das Vorschaubild für GitHub (Settings › Social preview): docs/images/social-preview.png, 1280×640.

Oben die Notch mit einem leuchtenden Signal von Claude Code, darunter App-Symbol, Name, Satz und Installationsbefehl.
Braucht Pillow (`pip install pillow`); Schriften: Inter, sonst SF/Helvetica (macOS), sonst DejaVu.
Aufruf aus dem Projektordner: python3 scripts/social-preview.py
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1280, 640
SCALE = 2  # erst doppelt so groß zeichnen, dann verkleinern: weiche Kanten
CLAUDE = (224, 118, 74)
CODEX = (138, 162, 255)
GRAY = (142, 142, 147)


def font(size, bold=False, mono=False):
    names = (["DejaVuSansMono.ttf", "/System/Library/Fonts/Menlo.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"]
             if mono else
             (["/usr/share/fonts/opentype/inter/Inter-Bold.otf", "/System/Library/Fonts/SFNS.ttf",
               "/System/Library/Fonts/Helvetica.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"] if bold else
              ["/usr/share/fonts/opentype/inter/Inter-Medium.otf", "/System/Library/Fonts/SFNS.ttf",
               "/System/Library/Fonts/Helvetica.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]))
    for name in names:
        try:
            return ImageFont.truetype(name, size * SCALE)
        except OSError:
            continue
    return ImageFont.load_default()


def s(*values):
    return [v * SCALE for v in values]


def notch_shape(draw, box, radius, fill):
    """Rechteck oben bündig, unten rund – wie die aufgeklappte Notch."""
    x0, y0, x1, y1 = box
    draw.rounded_rectangle(box, radius=radius, fill=fill)
    draw.rectangle((x0, y0, x1, y0 + radius), fill=fill)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    image = Image.new("RGB", (W * SCALE, H * SCALE), (0, 0, 0))

    # Leuchten in Claude-Orange rund um die Notch.
    glow = Image.new("RGB", image.size, (0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    notch = s(330, 0, 950, 150)
    notch_shape(gdraw, notch, 34 * SCALE, CLAUDE)
    glow = glow.filter(ImageFilter.GaussianBlur(28 * SCALE))
    image = Image.blend(image, glow, 0.55)
    draw = ImageDraw.Draw(image)
    notch_shape(draw, notch, 34 * SCALE, (0, 0, 0))

    # Signal: Punkt, Agent und Projekt, Befehl, Knöpfe.
    draw.ellipse(s(372, 34, 388, 50), fill=CLAUDE)
    draw.text(s(402, 28), "Claude Code", font=font(22, bold=True), fill=(255, 255, 255))
    draw.text(s(552, 31), "· my-app", font=font(19), fill=GRAY)
    draw.text(s(372, 72), "Wants to run:", font=font(18), fill=GRAY)
    draw.rounded_rectangle(s(372, 100, 640, 132), radius=8 * SCALE, fill=(28, 28, 30))
    draw.text(s(386, 104), "npm test", font=font(18, mono=True), fill=(255, 255, 255))
    draw.rounded_rectangle(s(700, 96, 800, 134), radius=19 * SCALE, fill=(44, 44, 46))
    draw.text(s(726, 104), "Deny", font=font(18, bold=True), fill=(255, 255, 255))
    draw.rounded_rectangle(s(812, 96, 912, 134), radius=19 * SCALE, fill=CLAUDE)
    draw.text(s(836, 104), "Allow", font=font(18, bold=True), fill=(255, 255, 255))

    # App-Symbol und Name.
    icon_path = os.path.join(root, "Resources", "AppIcon.png")
    title_font = font(92, bold=True)
    title = "lumo"
    title_w = draw.textlength(title, font=title_font)
    icon_size = 112 * SCALE
    gap = 26 * SCALE
    left = (W * SCALE - (icon_size + gap + title_w)) / 2
    top = 228 * SCALE
    if os.path.exists(icon_path):
        icon = Image.open(icon_path).convert("RGBA").resize((icon_size, icon_size), Image.LANCZOS)
        image.paste(icon, (int(left), int(top)), icon)
    draw.text((left + icon_size + gap, top + 4 * SCALE), title, font=title_font, fill=(255, 255, 255))

    # Satz in zwei Farben: Claude Code und Codex in ihren Agentenfarben.
    line_font = font(34)
    parts = [("Your MacBook notch as a control center for ", (210, 210, 215)), ("Claude Code", CLAUDE),
             (" and ", (210, 210, 215)), ("Codex", CODEX)]
    width = sum(draw.textlength(text, font=line_font) for text, _ in parts)
    x = (W * SCALE - width) / 2
    for text, color in parts:
        draw.text((x, 400 * SCALE), text, font=line_font, fill=color)
        x += draw.textlength(text, font=line_font)

    # Installationsbefehl als Pille.
    command = "brew install --cask bossaln/tap/lumo"
    mono = font(24, mono=True)
    cw = draw.textlength(command, font=mono)
    px = (W * SCALE - cw) / 2
    draw.rounded_rectangle((px - 26 * SCALE, 486 * SCALE, px + cw + 26 * SCALE, 540 * SCALE), radius=27 * SCALE,
                           fill=(22, 22, 24), outline=(58, 58, 62), width=SCALE)
    draw.text((px, 498 * SCALE), command, font=mono, fill=(235, 235, 240))

    out = os.path.join(root, "docs", "images", "social-preview.png")
    image.resize((W, H), Image.LANCZOS).save(out, optimize=True)
    print(out)


if __name__ == "__main__":
    main()
