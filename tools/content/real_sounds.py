"""Реальные записи (CC0 / MIT) -> звуки режима.

Источники (скачиваются с raw.githubusercontent.com):
  hoffspot/conquest client/sounds — записи с freesound.org под CC0:
    дыхание при беге: freesound 609482 (Lashim, CC0), 543243 (myfreesoundaccount1998, CC0)
    стоны от боли: freesound 464486, 547209, 416839, 347337 (CC0)
    падение тела: freesound 853591 (Wigglesworth, CC0), 810885 (Vrymaa, CC0)
    шуршание одежды: Kenney RPG Audio (CC0)
  e3ntity/react-sounds sounds/ambient/heartbeat.mp3 — MIT

python3 tools/content/real_sounds.py   (нужен ffmpeg)
Зацикленные звуки пишутся с cue-точкой: Source крутит такой wav по кругу (CreateSound).
"""
import os
import struct
import subprocess
import urllib.request

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "sound", "nyrp", "fx")
CACHE = os.environ.get("NYRP_SND_CACHE", "/tmp/nyrp_snd_cache")
SR = 44100

CONQ = "https://raw.githubusercontent.com/hoffspot/conquest/main/client/sounds/"
FILES = {
    "breath1": CONQ + "breath-1.07b772be.mp3", "breath2": CONQ + "breath-2.0561bb0f.mp3",
    "breath3": CONQ + "breath-3.0fbb7c53.mp3", "breath4": CONQ + "breath-4.9f41a97e.mp3",
    "hurt1": CONQ + "human-hurt-1.f35f15fa.mp3", "hurt2": CONQ + "human-hurt-2.1bebad44.mp3",
    "hurt3": CONQ + "human-hurt-3.1f8facbc.mp3", "hurt4": CONQ + "human-hurt-4.35c07b6d.mp3",
    "thud_big": CONQ + "death-thud-big-1.cac73169.mp3", "thud_mid": CONQ + "death-thud-mid-3.5e55821f.mp3",
    "fall": CONQ + "fall-3.c5908a39.mp3",
    "cloth1": CONQ + "cloth-rustle-1.2b5c6eaa.mp3", "cloth2": CONQ + "cloth-rustle-3.7f459adb.mp3",
    "heart": "https://raw.githubusercontent.com/e3ntity/react-sounds/master/sounds/ambient/heartbeat.mp3",
}


def load(key):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, key + ".mp3")
    if not os.path.exists(path):
        urllib.request.urlretrieve(FILES[key], path)
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.int16).astype(np.float32) / 32768


def norm(x, peak=0.85):
    m = np.abs(x).max()
    return x * (peak / m) if m > 0 else x


def fade(x, a=0.01, b=0.05):
    x = x.copy()
    na, nb = int(a * SR), int(b * SR)
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nb:
        x[-nb:] *= np.linspace(1, 0, nb)
    return x


def xfade_concat(parts, xf=0.12):
    n = int(xf * SR)
    out = parts[0]
    for p in parts[1:]:
        r = np.linspace(0, 1, n)
        mid = out[-n:] * (1 - r) + p[:n] * r
        out = np.concatenate([out[:-n], mid, p[n:]])
    return out


def loop_seam(x, xf=0.15):
    """Конец плавно переходит в начало: хвост подмешиваем к началу и отрезаем."""
    n = int(xf * SR)
    r = np.linspace(0, 1, n)
    head = x[:n] * r + x[-n:] * (1 - r)
    return np.concatenate([head, x[n:-n]])


def save(name, x, loop=False):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    chunks = b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16)
    chunks += b"data" + struct.pack("<I", len(pcm)) + pcm
    if len(pcm) % 2:
        chunks += b"\0"
    if loop:
        # cue-точка в начале: движок зацикливает звук от неё до конца
        chunks += b"cue " + struct.pack("<II", 28, 1) + struct.pack("<II4sIII", 1, 0, b"data", 0, 0, 0)
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
    print(name, f"{len(x) / SR:.2f}s", "loop" if loop else "")


def main():
    # дыхание после бега — ~9 с по кругу
    b = [norm(load(k), 0.8) for k in ("breath1", "breath3", "breath2", "breath4")]
    save("breath_run.wav", norm(loop_seam(xfade_concat(b)), 0.8), loop=True)

    # сердцебиение: 16 ударов (период 0.5 с) — ровная петля
    h = load("heart")
    save("heartbeat_loop.wav", norm(loop_seam(h[:int(8.0 * SR) + int(0.15 * SR)]), 0.9), loop=True)
    save("heartbeat.wav", fade(norm(h[:int(0.62 * SR)], 0.9), 0.002, 0.08))

    # боль / жёсткое приземление / падение тела
    for i in range(1, 5):
        save(f"pain{i}.wav", fade(norm(load(f"hurt{i}"), 0.8), 0.002, 0.04))
    save("land_hard.wav", fade(norm(load("fall"), 0.9), 0.001, 0.06))
    save("body_fall.wav", fade(norm(load("thud_big"), 0.9), 0.001, 0.1))

    # пробуждение: шорох одежды, затем один глубокий вдох-выдох (замедленная запись дыхания)
    c = norm(load("cloth1"), 0.5)
    br = load("breath4")
    slow = subprocess.run(["ffmpeg", "-v", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                           "-af", "atempo=0.7,asetrate=44100*0.92,aresample=44100,lowpass=f=5200",
                           "-f", "s16le", "-"], input=(br * 32767).astype("<i2").tobytes(), capture_output=True, check=True).stdout
    slow = np.frombuffer(slow, np.int16).astype(np.float32) / 32768
    wake = np.zeros(int(0.35 * SR) + len(slow))
    wake[:len(c)] += c
    wake[int(0.35 * SR):] += norm(slow, 0.55)
    save("wake.wav", fade(norm(wake, 0.7), 0.005, 0.25))


if __name__ == "__main__":
    main()
