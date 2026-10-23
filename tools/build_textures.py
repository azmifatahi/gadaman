#!/usr/bin/env python3
"""Turn the reference artwork in ``art_src/`` into game-ready, tileable textures.

Why a build step
----------------
The reference photos are 1250-1670 px stills. The game needs:

* **seamless** albedo maps (the road and the facade strips repeat every 40 m),
* mobile-sized files (1-2 MB is fine, 3 MB per texture is not),
* matching normal + roughness maps so the surfaces respond to the sun,

...and none of that can be produced by a shader at runtime. Everything here is
deterministic (fixed seeds), so re-running the script reproduces byte-identical
output.

Usage::

    python3 tools/build_textures.py            # writes assets/textures/*
    python3 tools/build_textures.py --check    # verify the outputs exist

Requires Pillow (``pip install pillow``); it is a build-time dependency only and
is *not* shipped with the game.
"""
from __future__ import annotations

import math
from PIL import ImageDraw
import os
import sys

from PIL import Image, ImageFilter, ImageChops, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_src")
OUT = os.path.join(ROOT, "assets", "textures")

# Mobile budget: albedo 1024, detail maps 512.
ALBEDO = 1024
DETAIL = 512
SKY_W = 2048
SKY_H = 1024


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def load(name: str) -> Image.Image:
    path = os.path.join(SRC, name)
    if not os.path.exists(path):
        raise SystemExit(f"missing source image: {path}")
    return Image.open(path).convert("RGB")


def save(img: Image.Image, name: str, quality: int = 88) -> None:
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    if name.endswith(".jpg"):
        img.convert("RGB").save(path, "JPEG", quality=quality, optimize=True,
                                progressive=False, subsampling=0)
    else:
        img.save(path, "PNG", optimize=True)
    kb = os.path.getsize(path) / 1024.0
    print(f"  {name:<34} {img.size[0]}x{img.size[1]}  {kb:7.1f} KB")


def cover_crop(img: Image.Image, size: tuple[int, int],
               focus: tuple[float, float] = (0.5, 0.5)) -> Image.Image:
    """Scale + crop so the image fills ``size`` without distortion."""
    tw, th = size
    sw, sh = img.size
    scale = max(tw / sw, th / sh)
    nw, nh = max(1, round(sw * scale)), max(1, round(sh * scale))
    img = img.resize((nw, nh), Image.LANCZOS)
    x = int((nw - tw) * focus[0])
    y = int((nh - th) * focus[1])
    return img.crop((x, y, x + tw, y + th))


def mirror_tile(img: Image.Image) -> Image.Image:
    """Make an image tile perfectly by mirroring it into the right half.

    The blended-feather trick leaves visible ghosting on structured textures
    (asphalt grain, clouds). Mirroring is mathematically seamless: the column at
    the seam is identical on both sides, and the outer edges are the original
    left/right edges, which now face each other. On organic surfaces (road,
    water, sky) the resulting symmetry is invisible in motion.
    """
    w, h = img.size
    half = img.crop((0, 0, w // 2, h))
    flipped = half.transpose(Image.FLIP_LEFT_RIGHT)
    out = Image.new("RGB", (w, h))
    out.paste(half, (0, 0))
    out.paste(flipped, (w // 2, 0))
    return out


def mirror_tile_v(img: Image.Image) -> Image.Image:
    """Same trick vertically."""
    w, h = img.size
    half = img.crop((0, 0, w, h // 2))
    flipped = half.transpose(Image.FLIP_TOP_BOTTOM)
    out = Image.new("RGB", (w, h))
    out.paste(half, (0, 0))
    out.paste(flipped, (0, h // 2))
    return out


def make_seamless(img: Image.Image, overlap: float = 0.22) -> Image.Image:
    """Legacy feather blend, kept for facades where mirroring would look wrong."""
    w, h = img.size
    shifted = ImageChops.offset(img, w // 2, h // 2)
    mask = Image.new("L", (w, h), 0)
    px = mask.load()
    band_x = int(w * overlap)
    band_y = int(h * overlap)
    for y in range(h):
        for x in range(w):
            dx = min(x, w - 1 - x) / max(1, band_x)
            dy = min(y, h - 1 - y) / max(1, band_y)
            v = max(0.0, 1.0 - min(dx, dy))
            px[x, y] = int(255 * (v ** 0.75))
    mask = mask.filter(ImageFilter.GaussianBlur(max(2, w // 128)))
    return Image.composite(shifted, img, mask)


def luminance_normal(img: Image.Image, strength: float = 2.4) -> Image.Image:
    """Cheap height->normal conversion from luminance (Sobel)."""
    g = img.convert("L").filter(ImageFilter.GaussianBlur(1.0))
    w, h = g.size
    src = g.load()
    out = Image.new("RGB", (w, h))
    dst = out.load()
    for y in range(h):
        ym = (y - 1) % h
        yp = (y + 1) % h
        for x in range(w):
            xm = (x - 1) % w
            xp = (x + 1) % w
            gx = (src[xp, ym] + 2 * src[xp, y] + src[xp, yp]) - \
                 (src[xm, ym] + 2 * src[xm, y] + src[xm, yp])
            gy = (src[xm, yp] + 2 * src[x, yp] + src[xp, yp]) - \
                 (src[xm, ym] + 2 * src[x, ym] + src[xp, ym])
            nx = -gx / 255.0 * strength
            ny = -gy / 255.0 * strength
            nz = 1.0
            inv = 1.0 / math.sqrt(nx * nx + ny * ny + nz * nz)
            dst[x, y] = (
                int(127.5 + 127.5 * nx * inv),
                int(127.5 + 127.5 * ny * inv),
                int(127.5 + 127.5 * nz * inv),
            )
    return out.filter(ImageFilter.GaussianBlur(0.4))


def roughness_from(img: Image.Image, lo: float = 0.62, hi: float = 0.95) -> Image.Image:
    """Roughness = inverse of local contrast (polished specks read as smoother)."""
    g = img.convert("L")
    blur = g.filter(ImageFilter.GaussianBlur(2.0))
    detail = ImageChops.difference(g, blur)
    stat = ImageStat.Stat(detail)
    mean = max(1.0, stat.mean[0])
    px = detail.load()
    w, h = detail.size
    out = Image.new("L", (w, h))
    dst = out.load()
    for y in range(h):
        for x in range(w):
            d = min(1.0, px[x, y] / (mean * 6.0))
            dst[x, y] = int(255 * (hi - (hi - lo) * d))
    return out


def equirect_sky(img: Image.Image) -> Image.Image:
    """Build a 2:1 equirectangular sky from the photo's *sky only*.

    The Khartoum skyline is NOT baked into the dome: a mirrored skyline would
    show the same minarets twice per turn. It ships separately (``build_skyline``)
    as a cylindrical backdrop, so it appears exactly once around the player and
    the dome stays a clean, seamless cloud field.

    Layout, in equirect space (v = 0 at the zenith, v = 1 at the nadir):
      v 0.00 - 0.50  photo sky, deepened towards the zenith with a colour ramp
      v 0.50 - 0.55  horizon haze
      v 0.55 - 1.00  ground haze (never seen: the track covers it)
    """
    sw, sh = img.size
    w, h = SKY_W, SKY_H
    # Pure sky only: the Khartoum skyline starts around 35 % of the photo, and
    # even its faintest antennas must not end up mirrored on the dome.
    horizon_row = int(sh * 0.20)

    upper_h = h // 2
    # Trim the sun flare at the right edge: mirroring would duplicate it.
    sky = img.crop((0, 0, int(sw * 0.88), horizon_row)).resize((w, upper_h), Image.LANCZOS)
    sky = sky.filter(ImageFilter.GaussianBlur(1.5))   # hide the 2x vertical stretch
    sky = mirror_tile(sky)                 # perfectly seamless in U

    # Deepen the zenith the way a real sky does when you tilt the camera up.
    # A multiplicative ramp (rather than a fresh gradient) keeps the photo's
    # clouds, so the pole is neither flat nor smeared.
    ramp = Image.new("RGB", (w, upper_h))
    rp = ramp.load()
    for y in range(upper_h):
        t = y / max(1, upper_h - 1)        # 0 = zenith, 1 = horizon
        k = 1.0 - 0.46 * (1.0 - t) ** 1.7
        v = int(255 * k)
        for x in range(w):
            rp[x, y] = (v, v, int(255 * min(1.0, k * 1.03)))
    sky = ImageChops.multiply(sky, ramp)
    # Soften the extreme top rows, which the resize stretched the most.
    sky.paste(sky.crop((0, 0, w, 12)).filter(ImageFilter.GaussianBlur(7)), (0, 0))

    out = Image.new("RGB", (w, h))
    out.paste(sky, (0, 0))

    # Horizon haze + ground: sample the photo's own haze colour so the seam
    # between the dome and the fog is invisible.
    haze = sky.crop((0, upper_h - 30, w, upper_h)).resize((1, 1), Image.BOX).getpixel((0, 0))
    ground = (52, 45, 40)
    lower = Image.new("RGB", (w, upper_h))
    lp = lower.load()
    for y in range(upper_h):
        t = y / max(1, upper_h - 1)
        k = 0.0 if t < 0.06 else ((t - 0.06) / 0.94) ** 0.75
        c = tuple(int(haze[i] * (1 - k) + ground[i] * k) for i in range(3))
        for x in range(w):
            lp[x, y] = c
    out.paste(lower, (0, upper_h))
    return out


def erase_sun(img: Image.Image) -> Image.Image:
    """Remove the sun disc from the source photo.

    The dome is built by crossfading the photo with itself rolled half a turn,
    so any bright unique feature is printed twice - a second sun on the opposite
    horizon. Copy-pasting a neighbouring patch left visible streaks (the haze
    has a horizontal gradient), so the disc is instead replaced by a heavily
    blurred copy of its own surroundings, which is exactly what a flat dust
    horizon looks like.
    """
    img = img.convert("RGB")
    sw, sh = img.size
    px = img.load()
    # The sun is the brightest thing in the lower half of the frame.
    best_x, best_y, best_score = sw // 2, int(sh * 0.8), 0.0
    for y in range(int(sh * 0.55), int(sh * 0.98), 2):
        for x in range(0, sw, 2):
            r, g, b = px[x, y]
            score = r + g + b
            if score > best_score:
                best_x, best_y, best_score = x, y, score

    rx = int(sh * 0.16)
    ry = int(sh * 0.085)
    # Blur radius must exceed the glow, otherwise the halo survives.
    blurred = img.filter(ImageFilter.GaussianBlur(rx * 0.55))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).ellipse(
        (best_x - rx, best_y - ry, best_x + rx, best_y + ry), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(min(rx, ry) * 0.45))
    return Image.composite(blurred, img, mask)


def flatten_azimuth(band: Image.Image) -> Image.Image:
    """Remove the photo's left-to-right brightness ramp from a sky band.

    A sunset photo is much brighter on the sun side. Mirroring such a band turns
    that ramp into two fake "sun glows" 180 deg apart, and the seam ends up as
    the brightest column on the whole dome. Removing only the low-frequency
    column profile leaves every cloud intact while making the sky uniform in
    azimuth, so the single painted sun below is the only bright feature.
    """
    band = band.convert("RGB")
    w, h = band.size
    px = band.load()
    # Smoothed per-column brightness over the sky part only (the haze below the
    # horizon is already flat and would only add noise).
    rows = range(0, max(2, int(h * 0.62)))
    prof = []
    for x in range(w):
        prof.append(sum(sum(px[x, y]) for y in rows) / max(1, len(rows)))
    k = max(8, w // 24)
    smooth = []
    for x in range(w):
        acc = 0.0
        for d in range(-k, k + 1):
            # Clamp, never wrap: the band is *not* periodic at this stage, and a
            # circular average would fold the bright left edge onto the dark
            # right edge and print a hard stripe down the middle of the sky.
            acc += prof[min(w - 1, max(0, x + d))]
        smooth.append(acc / (2 * k + 1))
    mean = sum(smooth) / w
    if mean <= 1.0:
        return band
    out = Image.new("RGB", (w, h))
    op = out.load()
    for x in range(w):
        gain = mean / max(1.0, smooth[x])
        for y in range(h):
            r, g, b = px[x, y]
            op[x, y] = (min(255, int(r * gain)), min(255, int(g * gain)),
                        min(255, int(b * gain)))
    return out


def paint_sun(dome: Image.Image, u: float = 0.535, v: float = 0.465) -> Image.Image:
    """Paint one soft sun + glow at (u, v) of the equirect dome.

    Computed per pixel instead of by stacking ellipses: stacked shapes band
    visibly on a smooth horizon and read as a square blob. The falloff is
    exponential (like real scattering) with a small bright core.

    Godot's panorama sky maps -Z to u = 0, and world.gd rotates the dome by 180
    deg to hide the texture wrap behind the player. u = 0.5 + 0.035 therefore puts
    the sun just right of the runner, low over the horizon: the Khartoum dusk the
    whole art direction is built on.
    """
    w, h = dome.size
    cx = int(w * u) % w
    cy = int(h * v)

    reach = int(h * 0.40)
    x0, x1 = max(0, cx - reach), min(w, cx + reach)
    y0, y1 = max(0, cy - reach), min(h, cy + reach)
    patch = dome.crop((x0, y0, x1, y1)).convert("RGB")
    pp = patch.load()
    pw, ph = patch.size
    lx, ly = cx - x0, cy - y0

    core = max(2.0, h * 0.011)          # radius of the bright disc
    halo = h * 0.075                    # radius of the tight glow
    for y in range(ph):
        for x in range(pw):
            dx = float(x - lx)
            dy = float(y - ly) * 1.35   # squash: the haze is wider than tall
            d = math.hypot(dx, dy)
            if d > reach:
                continue
            # Tight halo + a very wide, very faint wash, plus a tiny core.
            glow = 0.55 * math.exp(-d / halo) + 0.22 * math.exp(-d / (halo * 3.2))
            disc = math.exp(-(d / core) ** 2)
            # Cosine window -> exactly 0 at the patch edge, otherwise the crop
            # leaves a visible circle on the haze.
            glow *= 0.5 + 0.5 * math.cos(math.pi * min(1.0, d / reach))
            glow = min(1.6, glow + 1.1 * disc)
            r, g, b = pp[x, y]
            # Warm the light instead of whitening everything: 1.0 / 0.78 / 0.52.
            nr = r + (255 - r) * min(1.0, glow)
            ng = g + (232 - g) * min(1.0, glow * 0.82)
            nb = b + (176 - b) * min(1.0, glow * 0.62)
            pp[x, y] = (int(nr), int(ng), int(nb))

    out = dome.copy()
    out.paste(patch, (x0, y0))
    return out


def equirect_panorama(img: Image.Image) -> Image.Image:
    """Turn a sky-only photo into a 2:1 equirectangular dome texture.

    Three problems have to be solved, and each one has exactly one clean answer:

    1. **The photo does not wrap.** A 360 deg dome needs the left edge to match
       the right. Mirroring is seamless but doubles the cloud symmetry into a
       visible hard line down the middle of the sky, so we crossfade the band
       with itself rolled by half a turn and a cosine mask instead.
    2. **The sun is unique.** Any wrap or crossfade prints it twice. The band we
       use (from 55 % of the frame rightwards) contains no sun at all; the sun
       in the game is painted once, in paint_sun(), at the azimuth the camera
       looks at.
    3. **The photo has a left-to-right brightness ramp.** Crossfading a ramp
       leaves two bright patches 180 deg apart - fake suns made of pure ramp.
       flatten_azimuth() removes only that low-frequency ramp and leaves every
       cloud untouched.
    """
    w, h = SKY_W, SKY_H
    upper = h // 2

    src = img.convert("RGB")
    sw, sh = src.size
    band = src.crop((int(sw * 0.55), 0, sw, int(sh * 0.97)))
    band = flatten_azimuth(band)

    # Seamless wrap: crossfade with the same band rolled half a turn. The mask
    # is 1 across the middle and cosine-ramps to 0 over `overlap` at both edges;
    # because the roll is exactly half the width, the two ramps cover the same
    # cloud field and the loop closes with no step at u = 0 or u = 0.5.
    bw, bh = band.size
    shifted = ImageChops.offset(band, bw // 2, 0)
    mask = Image.new("L", (bw, bh), 0)
    mp = mask.load()
    overlap = max(4, int(bw * 0.28))
    for x in range(bw):
        if x < overlap:
            t = x / max(1, overlap - 1)
            a = 0.5 - 0.5 * math.cos(math.pi * t)
        elif x > bw - 1 - overlap:
            t = (bw - 1 - x) / max(1, overlap - 1)
            a = 0.5 - 0.5 * math.cos(math.pi * t)
        else:
            a = 1.0
        v = int(255 * a)
        for y in range(bh):
            mp[x, y] = v
    wrapped = Image.composite(band, shifted, mask)
    out = wrapped.resize((w, upper), Image.LANCZOS)

    # Deepen the zenith: the top ~15 % of an equirect dome is the pole, which a
    # single-row photo does not actually contain.
    ramp = Image.new("RGB", (w, upper))
    rp = ramp.load()
    for y in range(upper):
        t = y / max(1, upper - 1)
        k = 1.0 - 0.30 * (1.0 - t) ** 2.0
        v = int(255 * k)
        for x in range(w):
            rp[x, y] = (v, int(v * 0.98), int(255 * min(1.0, k * 1.02)))
    out.paste(ImageChops.multiply(out, ramp), (0, 0))

    # Lower hemisphere: horizon haze fading into ground. Fog and the street hide
    # almost all of it, so a two-colour ramp is enough and costs nothing.
    # Continue from the last sky row *per column*, so the hemisphere boundary is
    # invisible: averaging a band would leave a step wherever the haze differs
    # between the top and the bottom of that band.
    ground = (46, 40, 36)
    edge = out.crop((0, upper - 1, w, upper)).load()
    lower = Image.new("RGB", (w, upper))
    lp = lower.load()
    for y in range(upper):
        t = y / max(1, upper - 1)
        k = (t / 0.30) ** 1.4 if t < 0.30 else 1.0
        k = min(1.0, k)
        for x in range(w):
            e = edge[x, 0]
            lp[x, y] = (int(e[0] * (1 - k) + ground[0] * k),
                        int(e[1] * (1 - k) + ground[1] * k),
                        int(e[2] * (1 - k) + ground[2] * k))
    dome = Image.new("RGB", (w, h))
    dome.paste(out, (0, 0))
    dome.paste(lower, (0, upper))
    return paint_sun(dome)


def build_skyline(img: Image.Image) -> Image.Image:
    """Extract the Khartoum skyline as an alpha band for a cylindrical backdrop.

    The top edge is feathered so the band melts into the sky dome; the bottom
    edge is feathered into the haze that sits on the horizon plane.
    """
    sw, sh = img.size
    y0 = int(sh * 0.455)
    y1 = int(sh * 0.625)
    band = img.crop((0, y0, sw, y1))
    target = (4096, 320)
    band = cover_crop(band, target, (0.5, 0.5))

    # Alpha: transparent at the very top (sky), solid by 45 % of the band,
    # transparent again at the very bottom (blends into ground haze).
    alpha = Image.new("L", target, 255)
    ap = alpha.load()
    tw, th = target
    for y in range(th):
        t = y / max(1, th - 1)
        if t < 0.45:
            a = int(255 * (t / 0.45) ** 1.5)
        elif t > 0.88:
            a = int(255 * max(0.0, (1.0 - t) / 0.12) ** 1.2)
        else:
            a = 255
        for x in range(tw):
            ap[x, y] = a

    # Mirror the band so the cylinder has no seam where it closes.
    half = band.crop((0, 0, tw // 2, th))
    flipped = half.transpose(Image.FLIP_LEFT_RIGHT)
    mirrored = Image.new("RGB", target)
    mirrored.paste(half, (0, 0))
    mirrored.paste(flipped, (tw // 2, 0))
    a_half = alpha.crop((0, 0, tw // 2, th))
    a_mir = Image.new("L", target)
    a_mir.paste(a_half, (0, 0))
    a_mir.paste(a_half.transpose(Image.FLIP_LEFT_RIGHT), (tw // 2, 0))

    out = mirrored.convert("RGBA")
    out.putalpha(a_mir)
    return out


def facade_strip(img: Image.Image, size: tuple[int, int],
                 skip: float = 0.0) -> Image.Image:
    """Crop a shopfront band and make it tile horizontally only."""
    w, h = img.size
    band = img.crop((int(w * skip), int(h * 0.18), w, int(h * 0.86)))
    band = cover_crop(band, size)
    return make_seamless(band, overlap=0.18)


# ---------------------------------------------------------------------------
# recipes
# ---------------------------------------------------------------------------
def build_sky() -> None:
    print("sky")
    # The sky dome comes from the dedicated, sky-only panorama. The old source
    # (`khartoum_skyline.jpg`) is a cityscape: cropping its top 20 % yields a
    # flat, low-contrast band that washes out behind the fog, which is why the
    # gameplay shots looked hazy rather than like a sunset.
    save(equirect_panorama(load("sky_panorama.jpg")), "sky_khartoum.jpg", quality=90)
    # The skyline band still comes from the real Khartoum photo.
    photo = load("khartoum_skyline.jpg")
    save(build_skyline(photo), "skyline_khartoum.png")
    # A dedicated menu backdrop: the photo itself, slightly darkened for text.
    menu = cover_crop(photo, (1280, 720), (0.5, 0.42))
    menu = Image.blend(menu, Image.new("RGB", menu.size, (8, 10, 14)), 0.30)
    save(menu, "menu_bg.jpg", quality=88)


def build_road() -> None:
    print("road")
    road = mirror_tile(cover_crop(load("asphalt.jpg"), (ALBEDO, ALBEDO)))
    save(road, "asphalt_photo.jpg", quality=90)
    narrow = road.resize((DETAIL, DETAIL), Image.LANCZOS)
    save(luminance_normal(narrow, 1.6), "asphalt_photo_normal.png")
    save(roughness_from(narrow), "asphalt_photo_rough.png")


def build_pavement() -> None:
    print("pavement")
    pav = mirror_tile(cover_crop(load("pavement.jpg"), (ALBEDO, ALBEDO)))
    save(pav, "pavement_photo.jpg", quality=90)
    save(luminance_normal(pav.resize((DETAIL, DETAIL), Image.LANCZOS), 2.0),
         "pavement_photo_normal.png")


def build_water() -> None:
    print("water")
    water = mirror_tile(cover_crop(load("nile_water.jpg"), (ALBEDO, ALBEDO)))
    save(water, "water_photo.jpg", quality=90)


def build_facades() -> None:
    print("facades")
    bahri = load("bahri_street.jpg")
    # Turquoise shopfronts: the lower band on the right third of the photo.
    shops = facade_strip(bahri.crop((int(bahri.width * 0.30), 0, bahri.width, bahri.height)),
                         (1024, 512), skip=0.02)
    save(shops, "facade_shops.jpg", quality=88)
    # Ochre upper storeys with shutters: the left third.
    upper = facade_strip(bahri.crop((0, 0, int(bahri.width * 0.42), bahri.height)),
                         (1024, 512), skip=0.0)
    save(upper, "facade_ochre.jpg", quality=88)
    # Lighter plaster band for the far side of the road.
    light = cover_crop(bahri.crop((int(bahri.width * 0.55), int(bahri.height * 0.05),
                                   bahri.width, int(bahri.height * 0.55))),
                       (1024, 512), (0.25, 0.5))
    save(Image.blend(light, Image.new("RGB", light.size, (200, 186, 160)), 0.22),
         "facade_plaster.jpg", quality=88)


def build_facade_atlas() -> None:
    """Pack the three facade strips side by side for a single-texture material.

    The segment builder addresses them as u = [0..1/3), [1/3..2/3), [2/3..1],
    so a whole street can mix three photographic wall styles in one draw call.
    """
    print("facade atlas")
    tile_w, tile_h = 512, 512
    names = ["facade_shops.jpg", "facade_ochre.jpg", "facade_plaster.jpg"]
    atlas = Image.new("RGB", (tile_w * 3, tile_h))
    for i, name in enumerate(names):
        img = Image.open(os.path.join(OUT, name)).convert("RGB")
        atlas.paste(cover_crop(img, (tile_w, tile_h)), (i * tile_w, 0))
    save(atlas, "facade_atlas.jpg", quality=90)


def build_bridge() -> None:
    print("bridge")
    truss = load("bridge_mac_nimir.jpg")
    # Steel lattice: the diagonals in the middle of the truss photograph.
    band = truss.crop((int(truss.width * 0.30), int(truss.height * 0.10),
                       int(truss.width * 0.95), int(truss.height * 0.62)))
    band = cover_crop(band, (1024, 512))
    save(band, "truss_steel.jpg", quality=86)
    save(luminance_normal(band.resize((DETAIL, DETAIL), Image.LANCZOS), 3.0),
         "truss_steel_normal.png")

    # Concrete pier / abutment.
    shambat = load("bridge_shambat.jpg")
    concrete = shambat.crop((int(shambat.width * 0.05), int(shambat.height * 0.55),
                             int(shambat.width * 0.55), shambat.height))
    concrete = make_seamless(cover_crop(concrete, (512, 512)), 0.2)
    save(concrete, "concrete_photo.jpg", quality=88)


def main(argv: list[str]) -> int:
    if "--check" in argv:
        required = [
            "sky_khartoum.jpg", "skyline_khartoum.png", "menu_bg.jpg",
            "asphalt_photo.jpg",
            "asphalt_photo_normal.png", "asphalt_photo_rough.png",
            "pavement_photo.jpg", "pavement_photo_normal.png", "water_photo.jpg",
            "facade_shops.jpg", "facade_ochre.jpg", "facade_plaster.jpg",
            "facade_atlas.jpg",
            "truss_steel.jpg", "truss_steel_normal.png", "concrete_photo.jpg",
        ]
        missing = [n for n in required if not os.path.exists(os.path.join(OUT, n))]
        if missing:
            print("missing textures:", ", ".join(missing))
            return 1
        print(f"all {len(required)} textures present")
        return 0

    build_sky()
    build_road()
    build_pavement()
    build_water()
    build_facades()
    build_facade_atlas()
    build_bridge()
    print("\ndone ->", OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
