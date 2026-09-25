#!/usr/bin/env python3
"""Generate Screen Breaker's sound effects and particle sprites.

Pure Python (no numpy/PIL) so it runs on a stock Omarchy install. The output
is committed to assets/, so this only needs to run when a sound or sprite
changes:

    python3 tools/generate-assets.py
"""

import math
import pathlib
import random
import struct
import wave
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOUNDS = ROOT / "assets" / "sounds"
SPRITES = ROOT / "assets" / "particles"
RATE = 44100

random.seed(7)


# ---------------------------------------------------------------------------
# Audio helpers
# ---------------------------------------------------------------------------

def silence(seconds):
    return [0.0] * int(seconds * RATE)


def noise(seconds):
    return [random.uniform(-1, 1) for _ in range(int(seconds * RATE))]


def lowpass(samples, cutoff, cutoff_end=None):
    out, y = [], 0.0
    n = len(samples)
    for i, x in enumerate(samples):
        c = cutoff if cutoff_end is None else cutoff * (cutoff_end / cutoff) ** (i / n)
        a = 1 - math.exp(-2 * math.pi * c / RATE)
        y += a * (x - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    low = lowpass(samples, cutoff)
    return [x - l for x, l in zip(samples, low)]


def bandpass(samples, low, high):
    return lowpass(highpass(samples, low), high)


def tone(seconds, freq, freq_end=None, shape="sine"):
    out, phase = [], 0.0
    n = int(seconds * RATE)
    for i in range(n):
        f = freq if freq_end is None else freq * (freq_end / freq) ** (i / n)
        phase += 2 * math.pi * f / RATE
        if shape == "sine":
            out.append(math.sin(phase))
        elif shape == "saw":
            out.append(2 * ((phase / (2 * math.pi)) % 1) - 1)
        elif shape == "square":
            out.append(1.0 if math.sin(phase) >= 0 else -1.0)
        else:  # triangle
            out.append(2 * abs(2 * ((phase / (2 * math.pi)) % 1) - 1) - 1)
    return out


def envelope(samples, attack=0.002, decay=None):
    """Fast attack, exponential decay over the whole clip (or `decay` seconds)."""
    n = len(samples)
    decay_n = int((decay or n / RATE) * RATE)
    attack_n = max(1, int(attack * RATE))
    out = []
    for i, x in enumerate(samples):
        if i < attack_n:
            g = i / attack_n
        else:
            g = math.exp(-5 * (i - attack_n) / max(1, decay_n))
        out.append(x * g)
    return out


def gain(samples, g):
    return [x * g for x in samples]


def mix(*tracks, offsets=None):
    offsets = offsets or [0] * len(tracks)
    length = max(int(o * RATE) + len(t) for t, o in zip(tracks, offsets))
    out = [0.0] * length
    for t, o in zip(tracks, offsets):
        start = int(o * RATE)
        for i, x in enumerate(t):
            out[start + i] += x
    return out


def tinkles(count, spread, level):
    parts, offsets = [], []
    for _ in range(count):
        dur = random.uniform(0.06, 0.3)
        parts.append(gain(envelope(tone(dur, random.uniform(2800, 7500))), level * random.uniform(0.5, 1)))
        offsets.append(random.uniform(0, spread))
    return mix(*parts, offsets=offsets)


def crossfade_loop(samples, fade=0.25):
    """Blend the tail into the head so the clip loops without a click."""
    f = int(fade * RATE)
    head, body, tail = samples[:f], samples[f:-f], samples[-f:]
    blended = [t * (1 - i / f) + h * (i / f) for i, (h, t) in enumerate(zip(head, tail))]
    return body + blended


def write_wav(name, samples, level=0.9):
    peak = max(1e-6, max(abs(x) for x in samples))
    scale = level / peak
    SOUNDS.mkdir(parents=True, exist_ok=True)
    with wave.open(str(SOUNDS / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x * scale)) * 32767)) for x in samples))


# ---------------------------------------------------------------------------
# Sounds
# ---------------------------------------------------------------------------

def crack(variant):
    random.seed(100 + variant)
    thud = envelope(tone(0.16, 150, 45), decay=0.08)
    body = envelope(lowpass(noise(0.1), 700), decay=0.04)
    snap = envelope(highpass(noise(0.3), 2500), decay=0.09)
    return mix(gain(thud, 0.8), gain(body, 0.9), gain(snap, 0.6), tinkles(6, 0.3, 0.25))


def shatter():
    fall = envelope(highpass(noise(0.7), 3000), decay=0.3)
    return mix(gain(fall, 0.5), tinkles(18, 0.9, 0.3))


def gunshot(light=False):
    length = 0.16 if light else 0.35
    blast = envelope(lowpass(noise(length), 5000, 300), decay=length * 0.4)
    thump = envelope(tone(0.14, 190, 40, "triangle"), decay=0.06)
    crackle = envelope(highpass(noise(0.18), 3200), decay=0.05)
    return mix(gain(blast, 1.0), gain(thump, 0.8), gain(crackle, 0.3))


def smg_loop():
    shots, offsets = [], []
    t = 0.0
    while t < 3.0:
        random.seed(int(t * 1000))
        shots.append(gunshot(light=True))
        offsets.append(t)
        t += 0.075
    return mix(*shots, offsets=offsets)[: int(3.0 * RATE)]


def casing():
    return mix(gain(envelope(tone(0.06, 4200)), 0.4), gain(envelope(tone(0.05, 3700)), 0.25), offsets=[0, 0.11])


def boom():
    rumble = envelope(lowpass(noise(2.0), 1400, 50), attack=0.005, decay=0.9)
    sub = envelope(tone(1.3, 90, 25), decay=0.6)
    crack_ = envelope(highpass(noise(0.4), 2000), decay=0.1)
    return mix(gain(rumble, 1.2), gain(sub, 1.0), gain(crack_, 0.3), tinkles(20, 1.4, 0.2))


def tick():
    return envelope(tone(0.03, 1800, shape="square"), decay=0.01)


def repair():
    a = envelope(tone(0.25, 520, shape="triangle"), decay=0.12)
    b = envelope(tone(0.35, 780, shape="triangle"), decay=0.18)
    return mix(a, b, offsets=[0, 0.12])


def flame_loop():
    roar = bandpass(noise(4.25), 250, 1100)
    crackles, offsets = [], []
    for _ in range(120):
        crackles.append(gain(envelope(highpass(noise(0.01), 3000)), random.uniform(0.2, 0.6)))
        offsets.append(random.uniform(0, 4.2))
    return crossfade_loop(mix(roar, *crackles, offsets=[0] + offsets)[: int(4.25 * RATE)])


def laser_loop():
    seconds = 3.25
    n = int(seconds * RATE)
    out, p1, p2 = [], 0.0, 0.0
    for i in range(n):
        t = i / RATE
        p1 += 2 * math.pi * 95 / RATE
        p2 += 2 * math.pi * (1700 + 120 * math.sin(2 * math.pi * 23 * t)) / RATE
        saw = 2 * ((p1 / (2 * math.pi)) % 1) - 1
        out.append(0.5 * saw + 0.35 * math.sin(p2))
    return crossfade_loop(lowpass(out, 2400))


def melt_loop():
    seconds = 3.25
    n = int(seconds * RATE)
    out, p = [], 0.0
    rumble = lowpass(noise(seconds), 300)
    for i in range(n):
        t = i / RATE
        p += 2 * math.pi * (70 + 25 * math.sin(2 * math.pi * 5 * t)) / RATE
        out.append(0.6 * math.sin(p) + 1.5 * rumble[i])
    bubbles, offsets = [], []
    for _ in range(18):
        bubbles.append(gain(envelope(tone(0.08, random.uniform(180, 400), random.uniform(600, 900))), 0.35))
        offsets.append(random.uniform(0, seconds - 0.1))
    return crossfade_loop(mix(out, *bubbles, offsets=[0] + offsets)[:n])


def fuse_loop():
    return crossfade_loop(highpass(noise(2.25), 4000))


# ---------------------------------------------------------------------------
# PNG sprites
# ---------------------------------------------------------------------------

def write_png(name, width, height, pixel):
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            r, g, b, a = (max(0, min(255, int(round(c)))) for c in pixel(x, y))
            rows += bytes((r, g, b, a))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    SPRITES.mkdir(parents=True, exist_ok=True)
    (SPRITES / name).write_bytes(png)


def radial(stops):
    """stops: [(t, (r, g, b, a))] from centre (t=0) to edge (t=1)."""
    def color_at(t):
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t <= t1:
                k = (t - t0) / (t1 - t0) if t1 > t0 else 0
                return tuple(a + (b - a) * k for a, b in zip(c0, c1))
        return stops[-1][1]
    def pixel(x, y, size=64):
        d = math.hypot(x + 0.5 - size / 2, y + 0.5 - size / 2) / (size / 2)
        return color_at(min(1.0, d))
    return pixel


def sprites():
    write_png("fire.png", 64, 64, radial([
        (0, (255, 245, 200, 255)), (0.25, (255, 170, 40, 230)), (0.6, (220, 60, 10, 115)), (1, (120, 20, 0, 0))]))
    write_png("glow.png", 64, 64, radial([
        (0, (255, 255, 255, 255)), (0.3, (255, 200, 120, 150)), (1, (255, 120, 0, 0))]))
    write_png("smoke.png", 64, 64, radial([
        (0, (40, 36, 34, 150)), (0.6, (30, 28, 26, 75)), (1, (20, 20, 20, 0))]))

    # Spark: a short horizontal streak; particles auto-rotate along velocity.
    def spark(x, y):
        fx = 1 - abs(x - 15.5) / 16
        fy = max(0, 1 - abs(y - 3.5) / 3)
        a = 255 * fx * fy
        return (255, 225, 150, a)
    write_png("spark.png", 32, 8, spark)

    # Glass: a pale triangle with a bright edge.
    def glass(x, y):
        px, py = x + 0.5, y + 0.5
        inside = py > 2 and py < 14 and abs(px - 8) < (py - 2) * 0.55
        if not inside:
            return (0, 0, 0, 0)
        edge = abs(abs(px - 8) - (py - 2) * 0.55) < 1.2 or py > 12.8
        return (255, 255, 255, 230) if edge else (220, 235, 255, 150)
    write_png("glass.png", 16, 16, glass)

    # Casing: small brass cylinder, side view.
    def casing_px(x, y):
        if 2 <= y <= 6 and 1 <= x <= 14:
            shine = 255 if y == 3 else 0
            return (201 + shine * 0.2, 161 + shine * 0.3, 59 + shine * 0.3, 255)
        return (0, 0, 0, 0)
    write_png("casing.png", 16, 8, casing_px)


def main():
    write_wav("crack-1.wav", crack(1))
    write_wav("crack-2.wav", crack(2))
    write_wav("crack-3.wav", crack(3))
    write_wav("shatter.wav", shatter(), 0.7)
    write_wav("gunshot.wav", gunshot())
    write_wav("smg-loop.wav", smg_loop(), 0.8)
    write_wav("casing.wav", casing(), 0.35)
    write_wav("boom.wav", boom(), 0.95)
    write_wav("tick.wav", tick(), 0.3)
    write_wav("repair.wav", repair(), 0.5)
    write_wav("flame-loop.wav", flame_loop(), 0.7)
    write_wav("laser-loop.wav", laser_loop(), 0.45)
    write_wav("melt-loop.wav", melt_loop(), 0.6)
    write_wav("fuse-loop.wav", fuse_loop(), 0.25)
    sprites()
    print(f"wrote {len(list(SOUNDS.glob('*.wav')))} sounds and {len(list(SPRITES.glob('*.png')))} sprites")


if __name__ == "__main__":
    main()
