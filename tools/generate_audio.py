#!/usr/bin/env python3
"""Procedural audio pipeline for Sudan Runner.

Generates an upbeat Sudanese percussion loop (doum / tek / clap / shaker with a
pentatonic bass and pluck hook) plus every sound effect the game uses.
Nothing here is sampled from copyrighted material - it is all synthesised.

    python3 tools/generate_audio.py          # needs numpy (recommended)
    python3 tools/generate_audio.py --no-numpy

Ogg Vorbis encoding is done with ffmpeg when it is available (the CI workflow
installs a static build); otherwise the WAV files are kept.
"""
from __future__ import annotations

import math
import os
import random
import shutil
import struct
import subprocess
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
SR = 32000

try:
    import numpy as np
except ImportError:  # pragma: no cover - fallback path
    np = None

random.seed(2024)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def t_axis(seconds: float) -> "np.ndarray":
    return np.arange(int(SR * seconds)) / SR


def env(n: int, attack: float = 0.002, decay: float = 0.2, curve: float = 3.0) -> "np.ndarray":
    """Simple attack / exponential-decay envelope of n samples."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    d = np.exp(-np.maximum(t - attack, 0.0) / max(decay, 1e-4) * curve)
    return a * d


def add(buf: "np.ndarray", sig: "np.ndarray", at: float, gain: float = 1.0) -> None:
    i = int(at * SR)
    if i >= len(buf):
        return
    n = min(len(sig), len(buf) - i)
    buf[i:i + n] += sig[:n] * gain


def tone(freq: float, dur: float, kind: str = "sine", detune: float = 0.0) -> "np.ndarray":
    t = t_axis(dur)
    if kind == "sine":
        s = np.sin(2 * np.pi * freq * t)
    elif kind == "tri":
        s = 2 * np.abs(2 * ((freq * t) % 1) - 1) - 1
    elif kind == "square":
        s = np.sign(np.sin(2 * np.pi * freq * t))
    elif kind == "saw":
        s = 2 * ((freq * t) % 1) - 1
    else:
        raise ValueError(kind)
    if detune:
        s = 0.5 * s + 0.5 * np.sin(2 * np.pi * (freq * (1 + detune)) * t)
    return s


def noise(dur: float) -> "np.ndarray":
    return np.random.default_rng(7).normal(0, 1, int(SR * dur))


def onepole_lp(x: "np.ndarray", cutoff: float) -> "np.ndarray":
    a = math.exp(-2 * math.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def svf_band(x: "np.ndarray", center: float, q: float = 1.2) -> "np.ndarray":
    """Chamberlin state-variable band-pass, good enough for percussion."""
    f = 2 * math.sin(math.pi * min(center, SR / 6) / SR)
    damp = 1.0 / q
    low = band = 0.0
    out = np.empty_like(x)
    for i, v in enumerate(x):
        high = v - low - damp * band
        band += f * high
        low += f * band
        out[i] = band
    return out


def soft_clip(x: "np.ndarray", drive: float = 1.4) -> "np.ndarray":
    return np.tanh(x * drive) / math.tanh(drive)


def normalize(x: "np.ndarray", peak: float = 0.92) -> "np.ndarray":
    m = float(np.max(np.abs(x))) or 1.0
    return x * (peak / m)


def save_wav(path: str, stereo: "np.ndarray") -> None:
    data = np.clip(stereo, -1, 1)
    interleaved = (data * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(interleaved)


def save_mono_wav(path: str, mono: "np.ndarray") -> None:
    data = np.clip(mono, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype("<i2").tobytes())


# ---------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------
def doum(gain: float = 1.0) -> "np.ndarray":
    d = 0.30
    t = t_axis(d)
    f = 92 * np.exp(-t * 9) + 52
    phase = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t * 11)
    skin = svf_band(noise(d), 1800, 1.0) * np.exp(-t * 60) * 0.25
    click = svf_band(noise(d), 4200, 1.0) * np.exp(-t * 220) * 0.12
    return normalize(body + skin + click, gain)


def tek(gain: float = 0.7) -> "np.ndarray":
    d = 0.09
    t = t_axis(d)
    body = np.sin(2 * np.pi * (320 + 90 * np.exp(-t * 90)) * t) * np.exp(-t * 55)
    slap = svf_band(noise(d), 3100, 1.6) * np.exp(-t * 95)
    return normalize(body * 0.5 + slap, gain)


def clap(gain: float = 0.55) -> "np.ndarray":
    d = 0.20
    out = np.zeros(int(SR * d))
    for i, dt in enumerate((0.0, 0.008, 0.016, 0.027)):
        n = svf_band(noise(0.12), 1500, 1.1) * env(int(SR * 0.12), 0.001, 0.028, 2.5)
        add(out, n, dt, 0.9 - i * 0.1)
    out += svf_band(noise(d), 2400, 1.4) * np.exp(-np.arange(len(out)) / SR * 22) * 0.25
    return normalize(out, gain)


def shaker(gain: float = 0.22) -> "np.ndarray":
    d = 0.055
    n = svf_band(noise(d), 6500, 2.2) * env(int(SR * d), 0.004, 0.03, 3.0)
    return normalize(n, gain)


def cowbell(gain: float = 0.18) -> "np.ndarray":
    d = 0.22
    t = t_axis(d)
    s = (tone(540, d, "square") * 0.5 + tone(812, d, "square") * 0.5) * np.exp(-t * 18)
    return normalize(svf_band(s, 2200, 0.9) + s * 0.3, gain)


def bass(freq: float, dur: float, gain: float = 1.0) -> "np.ndarray":
    t = t_axis(dur)
    s = tone(freq, dur, "saw", detune=0.004) * 0.45 + tone(freq / 2, dur, "sine") * 0.55
    s = onepole_lp(s, 420)
    s *= env(len(s), 0.006, dur * 0.65, 2.2)
    return normalize(s, gain)


def pluck(freq: float, dur: float, gain: float = 1.0) -> "np.ndarray":
    """Karplus-Strong style pluck, the 'tanbur-ish' hook of the track."""
    n = int(SR * dur)
    period = max(2, int(SR / freq))
    rng = np.random.default_rng(int(freq))
    buf = rng.uniform(-1, 1, period)
    out = np.empty(n)
    idx = 0
    for i in range(n):
        v = buf[idx]
        nxt = buf[(idx + 1) % period]
        out[i] = v
        buf[idx] = (v + nxt) * 0.5 * 0.996
        idx = (idx + 1) % period
    out *= env(n, 0.001, dur * 0.55, 2.6)
    out = onepole_lp(out, 2600)
    return normalize(out, gain)


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------
NOTES = {
    "D2": 73.42, "F2": 87.31, "G2": 98.00, "A2": 110.00, "C3": 130.81,
    "D3": 146.83, "F3": 174.61, "G3": 196.00, "A3": 220.00, "C4": 261.63,
    "D4": 293.66, "F4": 349.23, "G4": 392.00, "A4": 440.00, "D5": 587.33,
}


def build_music(bars: int = 8, bpm: int = 96) -> "np.ndarray":
    beat = 60.0 / bpm
    step = beat / 4.0              # 16th note
    bar_len = beat * 4
    total = bar_len * bars
    length = int(SR * total)
    music = np.zeros(length)
    tail = int(SR * 2.0)           # render tails past the end, wrap for seamless loop

    def put(sig: "np.ndarray", at: float, gain: float) -> None:
        i = int(at * SR)
        for k in range(len(sig)):
            j = (i + k) % length
            music[j] += sig[k] * gain

    # --- percussion -------------------------------------------------------
    doum_pat = {0: 1.0, 6: 0.85, 10: 0.9, 14: 0.55}
    tek_pat = {3: 0.8, 5: 0.55, 7: 0.9, 11: 0.6, 12: 0.85, 15: 0.7}
    clap_pat = {4: 0.7, 12: 0.8}
    for bar in range(bars):
        base = bar * bar_len
        for s16 in range(16):
            at = base + s16 * step
            if s16 in doum_pat:
                put(doum(), at, doum_pat[s16] * 0.95)
            if s16 in tek_pat:
                put(tek(), at, tek_pat[s16] * 0.6)
            if s16 in clap_pat:
                put(clap(), at, clap_pat[s16] * 0.5)
            # Shaker on every 8th, accented on the off-beat.
            if s16 % 2 == 0:
                put(shaker(), at, 0.55 if s16 % 4 == 0 else 0.9)
        for s16 in (2, 7, 14):
            put(cowbell(), base + s16 * step, 0.5)
        # Fill at the end of every 4th bar.
        if bar % 4 == 3:
            for k, s16 in enumerate((13, 14, 15)):
                put(tek(), base + s16 * step, 0.45 + k * 0.15)

    # --- bass -------------------------------------------------------------
    riffs = [
        [(0, "D2", 2), (3, "D2", 1), (6, "F2", 2), (8, "G2", 2), (11, "A2", 1), (14, "C3", 2)],
        [(0, "D2", 2), (3, "D2", 1), (6, "G2", 3), (10, "F2", 2), (12, "D2", 2), (14, "A2", 2)],
    ]
    for bar in range(bars):
        base = bar * bar_len
        for s16, note, dur16 in riffs[bar % len(riffs)]:
            put(bass(NOTES[note], dur16 * step * 0.95), base + s16 * step, 0.75)

    # --- hook -------------------------------------------------------------
    melody = [
        [(0, "D4", 2), (2, "F4", 2), (4, "G4", 2), (7, "A4", 3), (11, "G4", 2), (13, "F4", 3)],
        [(0, "D4", 3), (4, "C4", 2), (6, "D4", 2), (9, "F4", 3), (12, "G4", 2), (14, "A4", 2)],
        [(0, "A4", 2), (2, "G4", 2), (4, "F4", 3), (8, "D4", 2), (10, "F4", 2), (12, "G4", 4)],
        [(0, "D5", 4), (6, "A4", 2), (8, "G4", 2), (10, "F4", 4)],
    ]
    for bar in range(bars):
        base = bar * bar_len
        for s16, note, dur16 in melody[bar % len(melody)]:
            at = base + s16 * step
            put(pluck(NOTES[note], dur16 * step * 1.4), at, 0.34)
            # Dubby dotted-eighth echo.
            put(pluck(NOTES[note], dur16 * step * 1.1), at + step * 3, 0.13)
            put(pluck(NOTES[note], dur16 * step * 0.9), at + step * 6, 0.06)

    # --- pad --------------------------------------------------------------
    for bar in range(bars):
        base = bar * bar_len
        chord = ("D3", "F3", "A3") if bar % 2 == 0 else ("G3", "A3", "D3")
        for note in chord:
            t = t_axis(bar_len)
            s = tone(NOTES[note], bar_len, "saw", detune=0.006)
            s = onepole_lp(s, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.22 * t)) * 0.09
            put(s * env(len(s), 0.15, bar_len * 0.5, 1.4), base, 0.6)

    # Stereo width: the echo of the hook sits on the right, percussion centre.
    music = soft_clip(music, 1.15)
    music = normalize(music, 0.80)
    left = music
    right = np.roll(music, int(SR * 0.011)) * 0.92
    stereo = np.stack([left, right], axis=1)

    # Fade the very first few milliseconds so a loop restart does not click.
    fade = int(SR * 0.004)
    stereo[:fade] *= np.linspace(0, 1, fade)[:, None]
    return stereo


# ---------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------
def sfx_pickup() -> "np.ndarray":
    d = 0.22
    out = np.zeros(int(SR * d))
    add(out, tone(880, 0.12) * env(int(SR * 0.12), 0.002, 0.05, 3), 0.0, 0.5)
    add(out, tone(1320, 0.16) * env(int(SR * 0.16), 0.002, 0.07, 3), 0.05, 0.45)
    add(out, tone(1760, 0.14) * env(int(SR * 0.14), 0.002, 0.05, 3), 0.09, 0.25)
    return normalize(out, 0.75)


def sfx_combo() -> "np.ndarray":
    d = 0.5
    out = np.zeros(int(SR * d))
    for i, f in enumerate((1046, 1318, 1568, 2093)):
        add(out, tone(f, 0.3) * env(int(SR * 0.3), 0.002, 0.09, 3), i * 0.055, 0.4)
    add(out, sfx_pickup(), 0.2, 0.3)
    return normalize(out, 0.8)


def sfx_jump() -> "np.ndarray":
    d = 0.28
    t = t_axis(d)
    f = 260 + 700 * (t / d) ** 0.6
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.004, 0.09, 2.4)
    air = svf_band(noise(d), 1800, 1.2) * env(len(t), 0.01, 0.06, 2.0) * 0.35
    return normalize(s + air, 0.6)


def sfx_slide() -> "np.ndarray":
    d = 0.35
    n = noise(d)
    s = svf_band(n, 900, 0.8) * env(int(SR * d), 0.02, 0.12, 1.6)
    s += svf_band(n, 2600, 1.4) * env(int(SR * d), 0.01, 0.05, 2.0) * 0.4
    return normalize(s, 0.5)


def sfx_hit() -> "np.ndarray":
    d = 0.55
    t = t_axis(d)
    thud = np.sin(2 * np.pi * (70 * np.exp(-t * 6) + 38) * t) * np.exp(-t * 7)
    crash = svf_band(noise(d), 700, 0.9) * np.exp(-t * 9) * 0.8
    metal = svf_band(noise(d), 3200, 3.0) * np.exp(-t * 16) * 0.25
    return normalize(soft_clip(thud + crash + metal, 1.6), 0.9)


def sfx_gameover() -> "np.ndarray":
    d = 1.6
    out = np.zeros(int(SR * d))
    for i, note in enumerate(("A3", "G3", "F3", "D3")):
        f = NOTES[note]
        seg = (tone(f, 0.5, "tri") * 0.6 + tone(f * 2, 0.5, "sine") * 0.2)
        add(out, seg * env(int(SR * 0.5), 0.01, 0.22, 2.2), i * 0.22, 0.55)
    add(out, doum(0.6), 0.0, 0.7)
    return normalize(out, 0.8)


def sfx_click() -> "np.ndarray":
    d = 0.08
    n = svf_band(noise(d), 2400, 1.8) * env(int(SR * d), 0.001, 0.018, 3)
    return normalize(n, 0.4)


def sfx_milestone() -> "np.ndarray":
    d = 0.9
    out = np.zeros(int(SR * d))
    for i, note in enumerate(("D4", "F4", "A4", "D5")):
        add(out, pluck(NOTES[note], 0.6, 0.7), i * 0.08, 0.6)
    return normalize(out, 0.75)


def sfx_cheer() -> "np.ndarray":
    """Crowd cheer: filtered noise swells with random formant-ish bumps."""
    d = 2.2
    t = t_axis(d)
    out = np.zeros(len(t))
    rng = np.random.default_rng(31)
    for _ in range(14):
        c = rng.uniform(500, 2600)
        start = rng.uniform(0.0, 1.2)
        seg = svf_band(noise(1.0), c, 2.5) * env(int(SR * 1.0), 0.15, 0.35, 1.5)
        add(out, seg, start, rng.uniform(0.15, 0.4))
    out *= np.clip(np.sin(np.pi * np.clip(t / d, 0, 1)) * 1.6, 0, 1)
    return normalize(out, 0.5)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    if np is None:
        print("numpy is required for audio generation; install it with pip install numpy")
        sys.exit(1)

    save_wav(os.path.join(OUT, "music_khartoum.wav"), build_music())
    save_mono_wav(os.path.join(OUT, "sfx_pickup.wav"), sfx_pickup())
    save_mono_wav(os.path.join(OUT, "sfx_combo.wav"), sfx_combo())
    save_mono_wav(os.path.join(OUT, "sfx_jump.wav"), sfx_jump())
    save_mono_wav(os.path.join(OUT, "sfx_slide.wav"), sfx_slide())
    save_mono_wav(os.path.join(OUT, "sfx_hit.wav"), sfx_hit())
    save_mono_wav(os.path.join(OUT, "sfx_gameover.wav"), sfx_gameover())
    save_mono_wav(os.path.join(OUT, "sfx_click.wav"), sfx_click())
    save_mono_wav(os.path.join(OUT, "sfx_milestone.wav"), sfx_milestone())
    save_mono_wav(os.path.join(OUT, "sfx_cheer.wav"), sfx_cheer())

    ffmpeg = shutil.which("ffmpeg") or os.environ.get("FFMPEG_BIN")
    if ffmpeg:
        for name in sorted(os.listdir(OUT)):
            if not name.endswith(".wav"):
                continue
            src = os.path.join(OUT, name)
            dst = os.path.join(OUT, name[:-4] + ".ogg")
            subprocess.run(
                [ffmpeg, "-y", "-loglevel", "error", "-i", src,
                 "-c:a", "libvorbis", "-q:a", "4", dst],
                check=True,
            )
            os.remove(src)
        print("encoded ogg files with", ffmpeg)
    else:
        print("ffmpeg not found - WAV files kept (Godot imports them fine)")


if __name__ == "__main__":
    main()
