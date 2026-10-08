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
    # одежда (freesound 770050 «Leather jacket - Dress undress», Kenney cloth) — CC0
    "leather1": CONQ + "equip-leather-1.f9c2f19b.mp3", "leather2": CONQ + "equip-leather-2.5a7e8364.mp3",
    "leather3": CONQ + "equip-leather-3.aa76dd26.mp3", "kcloth1": CONQ + "equip-cloth-1.42a9136d.mp3",
    "kcloth2": CONQ + "equip-cloth-2.9ff02c3f.mp3",
    # оружие: кобура/ремень (Schupke leather squeeze, Still North draw/sheath) — CC0
    "squeeze2": CONQ + "pickup-2.0ef4283c.mp3", "squeeze3": CONQ + "pickup-3.2c948442.mp3",
    "draw1": CONQ + "unsheathe-1.402ea1fd.mp3", "sheath1": CONQ + "sheathe-1.16e5aee7.mp3",
    # еда и питьё (freesound 807393 «Eating a fruit», 805468 «Drinking from bottle») — CC0
    "eat1": CONQ + "eat-1.88fd00f7.mp3", "eat2": CONQ + "eat-2.bf7b4104.mp3", "eat3": CONQ + "eat-3.0b0a29e5.mp3",
    "drink1": CONQ + "potion-drink-1.afae4959.mp3", "drink2": CONQ + "potion-drink-2.a6b1205c.mp3",
    "drink3": CONQ + "potion-drink-3.ac0fd9a5.mp3",
    # падение тела (freesound 504626 «BODY FALL - V HVY», 181177 «Body falling to floor») — CC0
    "thud_big2": CONQ + "death-thud-big-2.d2ef6a15.mp3", "thud_big3": CONQ + "death-thud-big-3.8af1e4d2.mp3",
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


def mix(a, b, offset=0.0, gain=1.0):
    """b поверх a со сдвигом offset (с) и громкостью gain."""
    o = int(offset * SR)
    out = np.zeros(max(len(a), o + len(b)), np.float32)
    out[:len(a)] += a
    out[o:o + len(b)] += b * gain
    return out


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

    # одежда: надеть / снять
    save("cloth_on.wav", fade(norm(mix(load("leather1"), load("kcloth1"), 0.15, 0.5), 0.75), 0.002, 0.08))
    save("cloth_off.wav", fade(norm(mix(load("leather2"), load("kcloth2"), 0.1, 0.45), 0.7), 0.002, 0.08))
    # оружие: достать из кобуры / убрать
    save("weapon_draw.wav", fade(norm(mix(load("squeeze2"), load("draw1"), 0.12, 0.35), 0.75), 0.002, 0.06))
    save("weapon_holster.wav", fade(norm(mix(load("sheath1"), load("squeeze3"), 0.18, 0.5), 0.7), 0.002, 0.06))
    # еда и питьё
    for i in range(1, 4):
        save(f"eat{i}.wav", fade(norm(load(f"eat{i}"), 0.8), 0.002, 0.08))
        save(f"drink{i}.wav", fade(norm(load(f"drink{i}"), 0.8), 0.002, 0.08))
    # несколько укусов подряд — «ест»
    bites = [norm(load(f"eat{i}"), 0.8) for i in (1, 3, 2)]
    chew = np.zeros(int(1.5 * SR), np.float32)
    for k, b in enumerate(bites):
        o = int(k * 0.48 * SR)
        chew[o:o + len(b)] += b[:len(chew) - o]
    save("eat.wav", fade(norm(chew, 0.8), 0.002, 0.1))
    # падение тела — тяжёлый глухой удар
    save("body_fall.wav", fade(norm(mix(load("thud_big2"), load("thud_big3"), 0.03, 0.55), 0.92), 0.001, 0.12))

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
