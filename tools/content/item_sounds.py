"""Звуки предметов (синтез): ключи, зажигалка, рация, затяжка/выдох/кашель, печатная машинка зон,
шелест денег, выстрел-«хвост» эхо не нужен — только то, чего нет в HL2.
python3 tools/content/item_sounds.py  ->  content/sound/nyrp/fx/*.wav
"""
import os
import struct

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "sound", "nyrp", "fx")
SR = 44100
rng = np.random.default_rng(7)


def t(d):
    return np.arange(int(d * SR)) / SR


def save(name, x, peak=0.8):
    x = x / (np.abs(x).max() + 1e-9) * peak
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    chunks = b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16) + b"data" + struct.pack("<I", len(pcm)) + pcm
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


def bandpass(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, len(x))


def lowpass(x, hi):
    return bandpass(x, 0, hi)


def place(out, x, at):
    o = int(at * SR)
    n = min(len(x), len(out) - o)
    if n > 0:
        out[o:o + n] += x[:n]


def ping(f, d, decay, amp=1.0):
    tt = t(d)
    partials = (1.0, 2.76, 5.4, 8.93)
    return amp * sum(np.sin(2 * np.pi * f * p * tt + rng.uniform(0, 6)) * np.exp(-tt * decay * (1 + i * 0.7)) / (1 + i)
                     for i, p in enumerate(partials))


def keys():
    """Связка ключей: серия коротких металлических касаний."""
    out = np.zeros(int(0.9 * SR))
    for k in range(9):
        at = rng.uniform(0, 0.6)
        place(out, ping(rng.uniform(2200, 4800), 0.25, rng.uniform(25, 45), rng.uniform(0.3, 1.0)), at)
        place(out, bandpass(rng.normal(0, 1, int(0.01 * SR)), 3000, 9000) * 0.3, at)
    return out


def lock_turn():
    """Поворот ключа в замке: трение + щелчок ригеля."""
    out = np.zeros(int(0.7 * SR))
    fr = bandpass(rng.normal(0, 1, int(0.35 * SR)), 900, 4000) * np.linspace(0.2, 0.6, int(0.35 * SR))
    place(out, fr, 0.05)
    click = bandpass(rng.normal(0, 1, int(0.03 * SR)), 1500, 7000) * np.exp(-t(0.03) * 120)
    place(out, click * 2.2, 0.42)
    place(out, ping(1800, 0.2, 40, 0.6), 0.42)
    return out


def lighter():
    """Зажигалка: чирк колёсиком (щелчок + искры) и мягкий «вух» пламени."""
    out = np.zeros(int(1.0 * SR))
    wheel = bandpass(rng.normal(0, 1, int(0.08 * SR)), 2000, 9000) * np.exp(-t(0.08) * 30)
    place(out, wheel * 1.4, 0.0)
    for k in range(6):
        place(out, bandpass(rng.normal(0, 1, int(0.004 * SR)), 5000, 12000) * 0.7, 0.02 + k * 0.012)
    flame_t = t(0.7)
    flame = lowpass(rng.normal(0, 1, len(flame_t)), 900) * (1 - np.exp(-flame_t * 30)) * np.exp(-flame_t * 2.5)
    place(out, flame * 1.6, 0.07)
    return out


def lighter_fail():
    out = np.zeros(int(0.25 * SR))
    place(out, bandpass(rng.normal(0, 1, int(0.08 * SR)), 2000, 9000) * np.exp(-t(0.08) * 30), 0)
    return out


def inhale():
    tt = t(1.4)
    env = np.sin(np.pi * np.clip(tt / 1.4, 0, 1)) ** 1.5
    crackle = np.zeros(len(tt))
    for k in range(40):
        place(crackle, bandpass(rng.normal(0, 1, int(0.003 * SR)), 3000, 10000) * rng.uniform(0.05, 0.25), rng.uniform(0.1, 1.2))
    return bandpass(rng.normal(0, 1, len(tt)), 400, 3200) * env * 0.5 + crackle


def exhale():
    tt = t(1.6)
    env = (1 - np.exp(-tt * 12)) * np.exp(-tt * 1.6)
    return bandpass(rng.normal(0, 1, len(tt)), 250, 2200) * env


def cough():
    """Кашель: три толчка воздуха с «голосовым» формантным призвуком."""
    out = np.zeros(int(1.3 * SR))
    for k, at in enumerate((0.0, 0.35, 0.68)):
        d = 0.26
        tt = t(d)
        env = (1 - np.exp(-tt * 200)) * np.exp(-tt * 14)
        noise = bandpass(rng.normal(0, 1, len(tt)), 300, 3500)
        f0 = 150 - k * 12
        voice = np.sign(np.sin(2 * np.pi * f0 * tt)) * 0.3
        voice = bandpass(voice, 300, 1200)
        place(out, (noise + voice) * env * (1 - k * 0.15), at)
    return out


def radio_on():
    """Рация: тангента нажата — щелчок и короткий «пик»."""
    out = np.zeros(int(0.22 * SR))
    place(out, bandpass(rng.normal(0, 1, int(0.012 * SR)), 1000, 6000) * 1.5, 0)
    tt = t(0.09)
    place(out, np.sin(2 * np.pi * 1750 * tt) * np.exp(-tt * 10) * 0.5, 0.03)
    return out


def radio_off():
    """Отпустил тангенту — шипение «roger beep»."""
    out = np.zeros(int(0.35 * SR))
    tt = t(0.25)
    place(out, bandpass(rng.normal(0, 1, len(tt)), 1200, 5000) * np.exp(-tt * 9) * 0.8, 0.0)
    t2 = t(0.07)
    place(out, np.sin(2 * np.pi * 1200 * t2) * 0.4, 0.02)
    return out


def type_tick():
    """Печатная машинка: удар литеры."""
    tt = t(0.07)
    hit = bandpass(rng.normal(0, 1, len(tt)), 1500, 7000) * np.exp(-tt * 140)
    body = np.sin(2 * np.pi * 420 * tt) * np.exp(-tt * 60) * 0.5
    return hit + body


def zone_bell():
    """Колокольчик каретки — в конце надписи зоны."""
    return ping(2600, 1.2, 4.5)


def money():
    """Шелест купюр."""
    out = np.zeros(int(0.6 * SR))
    for k in range(10):
        d = rng.uniform(0.02, 0.06)
        place(out, bandpass(rng.normal(0, 1, int(d * SR)), 1500, 8000) * np.hanning(int(d * SR)) * rng.uniform(0.4, 1), rng.uniform(0, 0.5))
    return out


def main():
    save("keys.wav", keys(), 0.6)
    save("lock_turn.wav", lock_turn(), 0.7)
    save("lighter.wav", lighter(), 0.7)
    save("lighter_fail.wav", lighter_fail(), 0.6)
    save("smoke_inhale.wav", inhale(), 0.45)
    save("smoke_exhale.wav", exhale(), 0.45)
    save("cough.wav", cough(), 0.75)
    save("radio_on.wav", radio_on(), 0.5)
    save("radio_off.wav", radio_off(), 0.5)
    save("type.wav", type_tick(), 0.45)
    save("zone_bell.wav", zone_bell(), 0.35)
    save("money.wav", money(), 0.6)
    print("item sounds ok")


if __name__ == "__main__":
    main()
