#!/usr/bin/env python3
"""Procedural art pipeline for Sudan Runner (Gadaman).

Everything the game needs art-wise is generated here so the repository stays
free of binary blobs that nobody can edit. Run with:

    python3 tools/generate_assets.py

Dependencies: Pillow (pip install pillow).

The Sudan flag geometry follows the official construction (1:2 ratio,
three equal horizontal bands, green hoist triangle reaching 1/3 of the fly).
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art")
TEX = os.path.join(ROOT, "assets", "textures")
FONTS = os.path.join(ROOT, "assets", "fonts")

# Official Sudan flag palette.
RED = (210, 16, 52)
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
GREEN = (0, 154, 0)
GOLD = (242, 183, 5)
INK = (8, 10, 11)


def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(os.path.join(FONTS, f"Cairo-{weight}.ttf"), size)


# ---------------------------------------------------------------------------
# Flag primitives
# ---------------------------------------------------------------------------
def flag_image(width: int, height: int) -> Image.Image:
    """Draw the Sudanese flag at an arbitrary aspect ratio."""
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    band = height / 3.0
    d.rectangle([0, 0, width, band], fill=RED + (255,))
    d.rectangle([0, band, width, band * 2], fill=WHITE + (255,))
    d.rectangle([0, band * 2, width, height], fill=BLACK + (255,))
    # Green triangle: full height at the hoist, apex at 1/3 of the fly.
    d.polygon([(0, 0), (width, height / 2.0), (0, height)], fill=GREEN + (255,))
    return img


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return mask


def add_grain(img: Image.Image, amount: int = 12, seed: int = 7) -> Image.Image:
    rnd = random.Random(seed)
    noise = Image.effect_noise(img.size, amount).convert("L")
    grain = Image.merge("RGBA", (noise, noise, noise, Image.new("L", img.size, 26)))
    return Image.alpha_composite(img.convert("RGBA"), grain)


def vignette(img: Image.Image, strength: float = 0.75) -> Image.Image:
    w, h = img.size
    small = Image.new("L", (64, 64), 0)
    d = ImageDraw.Draw(small)
    d.ellipse([-12, -12, 76, 76], fill=255)
    small = small.filter(ImageFilter.GaussianBlur(10)).resize((w, h), Image.BICUBIC)
    dark = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    dark.putalpha(small.point(lambda v: int((255 - v) * strength)))
    return Image.alpha_composite(img.convert("RGBA"), dark)


# ---------------------------------------------------------------------------
# App icon / splash
# ---------------------------------------------------------------------------
def build_icon() -> None:
    size = 512
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = size - 40
    flag = flag_image(inner, inner).resize((inner, inner))
    flag.putalpha(rounded_mask((inner, inner), 96))
    # Soft drop shadow so the icon reads on dark and light launchers.
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [24, 34, size - 16, size - 10], 100, fill=(0, 0, 0, 140)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    icon = Image.alpha_composite(icon, shadow)
    icon.alpha_composite(flag, (20, 16))

    d = ImageDraw.Draw(icon)
    d.rounded_rectangle([20, 16, size - 21, size - 21], 96, outline=(255, 255, 255, 60), width=3)
    d.rounded_rectangle([30, 26, size - 31, size - 31], 88, outline=GOLD + (110,), width=3)

    # Glossy diagonal highlight.
    gloss = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).polygon(
        [(20, 16), (size * 0.72, 16), (size * 0.30, size - 21), (20, size - 21)],
        fill=(255, 255, 255, 22),
    )
    gloss.putalpha(Image.composite(gloss.getchannel("A"), Image.new("L", (size, size), 0),
                                  rounded_mask((size, size), 96)))
    icon.alpha_composite(gloss)
    icon.save(os.path.join(ART, "icon.png"))
    # Android launcher icon option expects exactly 192x192.
    icon.resize((192, 192), Image.LANCZOS).save(os.path.join(ART, "icon_192.png"))

    # Android adaptive icon: transparent canvas, artwork inside the 66% safe zone.
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    emblem_size = 260
    emblem = flag_image(emblem_size, emblem_size).resize((emblem_size, emblem_size))
    emblem.putalpha(rounded_mask((emblem_size, emblem_size), 46))
    fg.alpha_composite(emblem, ((432 - emblem_size) // 2, (432 - emblem_size) // 2))
    fg.save(os.path.join(ART, "icon_foreground.png"))

    bg = Image.new("RGBA", (432, 432), GREEN + (255,))
    bd = ImageDraw.Draw(bg)
    for y in range(432):
        shade = int(18 * math.sin(y / 432.0 * math.pi))
        bd.line([(0, y), (432, y)], fill=(0, max(0, 70 - shade), 0, 255))
    bg.save(os.path.join(ART, "icon_background.png"))


def build_splash() -> None:
    """1280x720 boot splash. Same layout Godot's boot splash expects."""
    w, h = 1280, 720
    img = Image.new("RGBA", (w, h), INK + (255,))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(7 + 12 * t), int(10 + 16 * t), int(11 + 13 * t), 255))

    emblem = 300
    x0 = (w - emblem) // 2
    y0 = 64
    flag = flag_image(emblem, emblem).resize((emblem, emblem))
    flag.putalpha(rounded_mask((emblem, emblem), 26))
    img.alpha_composite(flag, (x0, y0))

    d.text((w // 2, y0 + emblem + 44), "SUDAN RUNNER", font=font("Black", 74),
           fill=(255, 255, 255, 255), anchor="mt")
    d.text((w // 2, y0 + emblem + 146), "K H A R T O U M   S T R E E T S", font=font("Bold", 26),
           fill=GOLD + (235,), anchor="mt")
    d.text((w // 2, h - 62), "GODOT 4  ·  G A D A M A N", font=font("Medium", 20),
           fill=(255, 255, 255, 105), anchor="mt")
    img.convert("RGB").save(os.path.join(ART, "splash.png"))


def build_menu_background() -> None:
    """Full-screen menu backdrop: dusk over the Nile, Khartoum skyline, acacias."""
    w, h = 1920, 1080
    img = Image.new("RGBA", (w, h), INK + (255,))
    d = ImageDraw.Draw(img)
    horizon = int(h * 0.66)

    # Dusk gradient: warm sand haze near the horizon fading into deep indigo.
    top = (10, 12, 24)
    mid = (86, 26, 44)
    low = (196, 104, 46)
    for y in range(horizon + 1):
        t = y / horizon
        if t < 0.55:
            k = t / 0.55
            col = tuple(int(top[i] + (mid[i] - top[i]) * k) for i in range(3))
        else:
            k = (t - 0.55) / 0.45
            col = tuple(int(mid[i] + (low[i] - mid[i]) * k) for i in range(3))
        d.line([(0, y), (w, y)], fill=col + (255,))

    # Low sun. Additive blending keeps the glow from turning muddy over the sky.
    sx, sy = int(w * 0.70), int(horizon * 0.72)
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for r in range(300, 0, -3):
        a = int(58 * (1 - r / 300) ** 2.4)
        gd.ellipse([sx - r, sy - r, sx + r, sy + r], fill=(a, int(a * 0.72), int(a * 0.36)))
    glow = glow.filter(ImageFilter.GaussianBlur(6))
    base_rgb = ImageChops.add(img.convert("RGB"), glow)
    img = base_rgb.convert("RGBA")
    disc = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(disc).ellipse([sx - 66, sy - 66, sx + 66, sy + 66], fill=(255, 232, 186, 238))
    img.alpha_composite(disc.filter(ImageFilter.GaussianBlur(3)))

    # The Nile, with a flag-coloured reflection band.
    shore = int(h * 0.80)
    river = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rd = ImageDraw.Draw(river)
    rd.rectangle([0, horizon, w, shore], fill=(16, 30, 40, 255))
    for i in range(0, 90):
        y = horizon + i * 3
        a = int(120 * (1 - i / 90.0))
        rd.line([(0, y), (w, y)], fill=(70, 120, 130, max(0, a // 4)))
    for i in range(26):
        x = int(w * 0.70) + random.Random(i).randint(-260, 260)
        ln = random.Random(i + 90).randint(40, 220)
        rd.line([(x - ln // 2, horizon + 20 + i * 6), (x + ln // 2, horizon + 20 + i * 6)],
                fill=(255, 214, 150, max(0, 120 - i * 4)), width=3)
    img.alpha_composite(river.filter(ImageFilter.GaussianBlur(1)))

    # Corniche / road in the foreground.
    road = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rdd = ImageDraw.Draw(road)
    rdd.rectangle([0, shore - 6, w, h], fill=(24, 25, 27, 255))
    rdd.rectangle([0, shore - 6, w, shore + 2], fill=(58, 58, 60, 255))
    for i in range(-2, 12):
        x = i * 220 + 40
        rdd.polygon([(x, h - 26), (x + 130, h - 26), (x + 152, h), (x + 14, h)],
                    fill=(226, 214, 180, 60))
    road = road.filter(ImageFilter.GaussianBlur(0.6))
    img.alpha_composite(road)

    # Skyline silhouette on the far bank.
    city = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(city)
    rnd = random.Random(11)

    def building(x: int, bw: int, bh: int, shade: int) -> None:
        cd.rectangle([x, horizon - bh, x + bw, horizon + 6], fill=(shade, shade + 1, shade + 3, 245))
        for wy in range(horizon - bh + 22, horizon - 30, 40):
            for wx in range(x + 14, x + bw - 18, 30):
                if rnd.random() < 0.30:
                    cd.rectangle([wx, wy, wx + 10, wy + 14], fill=(255, 205, 120, 135))

    x = -40
    while x < w + 60:
        bw = rnd.randint(80, 190)
        bh = rnd.randint(90, 250)
        building(x, bw, bh, rnd.randint(8, 18))
        x += bw + rnd.randint(8, 30)

    # Minaret with dome, the Khartoum skyline signature.
    mx, my = int(w * 0.78), horizon - 260
    cd.rectangle([mx - 15, my, mx + 15, horizon], fill=(11, 12, 14, 250))
    cd.ellipse([mx - 28, my - 40, mx + 28, my + 24], fill=(11, 12, 14, 250))
    cd.polygon([(mx, my - 100), (mx + 12, my - 46), (mx - 12, my - 46)], fill=(11, 12, 14, 250))
    cd.rectangle([mx - 40, my - 6, mx + 40, my + 4], fill=(11, 12, 14, 250))

    # Acacia trees with the classic flat canopy.
    for tx, scale in ((int(w * 0.06), 1.0), (int(w * 0.19), 0.8), (int(w * 0.47), 0.9),
                      (int(w * 0.94), 1.1)):
        top = horizon - int(rnd.randint(140, 200) * scale)
        cd.rectangle([tx - 6, top, tx + 6, horizon + 6], fill=(10, 11, 10, 250))
        cd.ellipse([tx - int(86 * scale), top - int(40 * scale),
                    tx + int(86 * scale), top + int(18 * scale)], fill=(10, 11, 10, 250))
    img.alpha_composite(city)

    # Foreground: a passing "amjad" minibus on the corniche.
    fg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fg)
    bx, by = int(w * 0.09), int(h * 0.80)
    fd.ellipse([bx - 20, by + 108, bx + 380, by + 152], fill=(0, 0, 0, 140))
    fd.rounded_rectangle([bx, by, bx + 360, by + 120], 16, fill=(14, 16, 18, 250))
    fd.rectangle([bx + 14, by + 14, bx + 346, by + 34], fill=RED + (255,))
    fd.rectangle([bx + 14, by + 34, bx + 346, by + 44], fill=WHITE + (255,))
    fd.rectangle([bx + 14, by + 44, bx + 346, by + 54], fill=BLACK + (255,))
    fd.polygon([(bx + 14, by + 14), (bx + 84, by + 34), (bx + 14, by + 54)], fill=GREEN + (255,))
    for wx in range(bx + 24, bx + 330, 56):
        fd.rounded_rectangle([wx, by + 64, wx + 42, by + 98], 6, fill=(24, 36, 42, 250))
    for wx in (bx + 60, bx + 300):
        fd.ellipse([wx - 26, by + 100, wx + 26, by + 152], fill=(9, 9, 10, 255))
        fd.ellipse([wx - 11, by + 115, wx + 11, by + 137], fill=(70, 70, 70, 255))
    img.alpha_composite(fg)

    img = add_grain(img, 5, seed=4)
    img = vignette(img, 0.66)
    d = ImageDraw.Draw(img)
    d.rectangle([18, 18, w - 19, h - 19], outline=GOLD + (40,), width=2)
    img.convert("RGB").save(os.path.join(ART, "menu_bg.png"), optimize=True)


def build_logo() -> None:
    w, h = 1200, 420
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text((w // 2, 40), "SUDAN", font=font("Black", 150), fill=(255, 255, 255, 255), anchor="ma")
    d.text((w // 2, 190), "RUNNER", font=font("Black", 150), fill=GOLD + (255,), anchor="ma")
    d.line([(w // 2 - 250, 360), (w // 2 + 250, 360)], fill=(255, 255, 255, 90), width=4)
    d.text((w // 2, 372), "G A D A M A N", font=font("Medium", 34),
           fill=(255, 255, 255, 170), anchor="ma")
    img.save(os.path.join(ART, "logo.png"))


# ---------------------------------------------------------------------------
# Collectible / HUD icons
# ---------------------------------------------------------------------------
def build_cup_icons() -> None:
    """Traditional Sudanese drink glasses used as the in-game collectibles."""
    drinks = {
        "aradaib": (122, 58, 18),   # tamarind, dark amber
        "karkadeh": (142, 22, 46),  # hibiscus, deep red
        "gongolez": (226, 208, 168),  # baobab, creamy
    }
    for name, liquid in drinks.items():
        s = 192
        img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        body = [(46, 44), (146, 44), (132, 158), (60, 158)]
        d.polygon(body, fill=(236, 244, 246, 90))
        d.polygon([(56, 96), (136, 96), (128, 154), (64, 154)], fill=liquid + (240,))
        d.line([(46, 44), (60, 158)], fill=(255, 255, 255, 190), width=6)
        d.line([(146, 44), (132, 158)], fill=(255, 255, 255, 110), width=4)
        d.ellipse([44, 34, 148, 56], fill=(255, 255, 255, 60), outline=(255, 255, 255, 200), width=4)
        d.line([(74, 60), (70, 120)], fill=(255, 255, 255, 90), width=5)
        img.save(os.path.join(ART, f"cup_{name}.png"))

    # Small monochrome-ish HUD glyph.
    hud = Image.open(os.path.join(ART, "cup_karkadeh.png")).resize((96, 96), Image.LANCZOS)
    hud.save(os.path.join(ART, "hud_cup.png"))


# ---------------------------------------------------------------------------
# Tileable textures
# ---------------------------------------------------------------------------
def noise_layer(size: int, base: tuple[int, int, int], amount: int, seed: int,
                contrast: float = 1.0) -> Image.Image:
    rnd = random.Random(seed)
    img = Image.new("RGB", (size, size), base)
    px = img.load()
    for y in range(size):
        for x in range(size):
            n = int(rnd.gauss(0, amount) * contrast)
            px[x, y] = tuple(min(255, max(0, c + n)) for c in base)
    return img


def build_textures() -> None:
    size = 256
    asphalt = noise_layer(size, (43, 45, 48), 9, 21)
    d = ImageDraw.Draw(asphalt)
    rnd = random.Random(5)
    for _ in range(260):
        x, y = rnd.randrange(size), rnd.randrange(size)
        r = rnd.choice([1, 1, 2])
        d.ellipse([x, y, x + r, y + r], fill=(70, 72, 74))
    for _ in range(14):
        x, y = rnd.randrange(size), rnd.randrange(size)
        d.line([(x, y), (x + rnd.randint(6, 26), y + rnd.randint(-4, 4))],
               fill=(30, 31, 33), width=1)
    asphalt.save(os.path.join(TEX, "asphalt.png"))

    sand = noise_layer(size, (205, 173, 124), 12, 22)
    sd = ImageDraw.Draw(sand)
    rnd = random.Random(9)
    for _ in range(160):
        x, y = rnd.randrange(size), rnd.randrange(size)
        sd.ellipse([x, y, x + 1, y + 1], fill=(232, 206, 160))
    sand.save(os.path.join(TEX, "sand.png"))

    # Soft round shadow used as a cheap blob shadow under characters/props.
    s = 128
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    for r in range(s // 2, 0, -1):
        a = int(190 * (r / (s / 2)) ** 2.2)
        shadow_draw.ellipse([s / 2 - r, s / 2 - r * 0.62, s / 2 + r, s / 2 + r * 0.62],
                            fill=(0, 0, 0, a))
    shadow = shadow.filter(ImageFilter.GaussianBlur(5))
    shadow.save(os.path.join(TEX, "blob_shadow.png"))

    # Soft white puff: dust, sparkles and landing puffs (tinted per effect).
    puff = Image.new("RGBA", (128, 128), (255, 255, 255, 0))
    pd = ImageDraw.Draw(puff)
    for r in range(60, 0, -1):
        a = int(230 * (1.0 - (r / 60.0)) ** 1.7)
        pd.ellipse([64 - r, 64 - r, 64 + r, 64 + r], fill=(255, 255, 255, a))
    puff = puff.filter(ImageFilter.GaussianBlur(3))
    puff.save(os.path.join(TEX, "puff.png"))

    # Exact flag texture for suits, decals and bus liveries.
    flag = flag_image(512, 256)
    flag.convert("RGB").save(os.path.join(TEX, "flag.png"))


def main() -> None:
    for path in (ART, TEX):
        os.makedirs(path, exist_ok=True)
    build_icon()
    build_splash()
    build_menu_background()
    build_logo()
    build_cup_icons()
    build_textures()
    print("assets generated in", ART, "and", TEX)


if __name__ == "__main__":
    main()
