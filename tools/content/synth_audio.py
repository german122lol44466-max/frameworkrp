"""Процедурные звуки и фоновая музыка New-York Roleplay.

Запуск: python3 tools/content/synth_audio.py
Всё детерминировано (фиксированный seed), результат в content/sound/nyrp/.
"""
import os
import subprocess

import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOUND = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "sound", "nyrp")
rng = np.random.default_rng(1993)


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="low", fs=SR, output="sos"), x)


def highpass(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="high", fs=SR, output="sos"), x)


def norm(x, peak=0.89):
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def fade(x, a=0.005, b=0.02):
    n1, n2 = int(a * SR), int(b * SR)
    x = x.copy()
    if n1:
        x[:n1] *= np.linspace(0, 1, n1)
    if n2:
        x[-n2:] *= np.linspace(1, 0, n2)
    return x


def save(path, x, sr=SR):
    p = os.path.join(SOUND, path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    if p.endswith(".ogg"):
        # libsndfile падает на длинных vorbis-записях, поэтому через ffmpeg
        tmp = p[:-4] + ".tmp.wav"
        sf.write(tmp, x, sr, subtype="PCM_16")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", p], check=True)
        os.remove(tmp)
    else:
        sf.write(p, x, sr, subtype="PCM_16")
    print("wrote", os.path.relpath(p, ROOT), f"{len(x) / sr:.2f}s")


def reverb_ir(dur=2.0, decay=0.5, stereo=True, bright=5000):
    t = t_axis(dur)
    chans = []
    for _ in range(2 if stereo else 1):
        n = rng.standard_normal(len(t)) * np.exp(-t / decay)
        n = lowpass(n, bright)
        n[: int(0.012 * SR)] = 0
        chans.append(n / np.sqrt(np.sum(n ** 2)))
    return np.stack(chans, 1) if stereo else chans[0]


# ------------------------------------------------------------------- SFX ---

def zipper(dur=0.75, rate=(90, 260)):
    """Молния сумки: быстрые щелчки зубчиков с ускорением и замедлением."""
    n = int(dur * SR)
    out = np.zeros(n)
    pos = 0.02
    while pos < dur - 0.03:
        p = pos / dur
        r = rate[0] + (rate[1] - rate[0]) * np.sin(np.pi * p) ** 0.7
        i = int(pos * SR)
        click_len = int(0.004 * SR)
        click = rng.standard_normal(click_len) * np.exp(-np.linspace(0, 6, click_len))
        amp = 0.55 + 0.45 * np.sin(np.pi * p) + rng.uniform(-0.15, 0.15)
        out[i:i + click_len] += click * amp
        pos += 1 / r * rng.uniform(0.8, 1.2)
    out = bandpass(out, 1800, 7500, 2) + 0.25 * bandpass(out, 300, 1500, 1)
    body = bandpass(rng.standard_normal(n), 200, 900) * 0.08 * np.sin(np.pi * np.linspace(0, 1, n))
    return fade(norm(out + body, 0.8), 0.002, 0.05)


def cloth(dur=0.9):
    """Шорох ткани — надевание одежды."""
    n = int(dur * SR)
    env = np.zeros(n)
    for _ in range(7):
        c = rng.uniform(0.05, dur - 0.1)
        w = rng.uniform(0.04, 0.16)
        env += rng.uniform(0.4, 1) * np.exp(-((t_axis(dur) - c) / w) ** 2)
    x = rng.standard_normal(n)
    x = bandpass(x, 400, 5000, 2) * 0.7 + bandpass(x, 150, 600, 1) * 0.3
    return fade(norm(x * env, 0.7), 0.01, 0.08)


class Formant:
    """Полосовой фильтр с переменной частотой (поблочно, с сохранением состояния)."""

    def __init__(self):
        self.zi = None

    def run(self, x, f, bw):
        b, a = signal.iirpeak(min(f, SR / 2 - 100), max(f / bw, 0.5), fs=SR)
        if self.zi is None:
            self.zi = signal.lfilter_zi(b, a) * 0
        y, self.zi = signal.lfilter(b, a, x, zi=self.zi)
        return y


def yawn(female=False):
    """Зевок: вдох с шумом + голосовая «а-а-ах» с падающим тоном + выдох."""
    dur = 2.7
    t = t_axis(dur)
    n = len(t)
    base = 1.65 if female else 1.0
    # контур основного тона
    f0 = np.interp(t, [0, 0.75, 1.0, 1.5, 2.2, 2.7], [0, 0, 230, 205, 120, 100]) * base
    f0 *= 1 + 0.012 * np.sin(2 * np.pi * 5.2 * t)
    phase = np.cumsum(f0 / SR)
    glottal = (phase % 1.0) * 2 - 1
    glottal = lowpass(glottal - 0.6 * np.sign(glottal) * (np.abs(glottal) ** 3), 3500)
    voiced_env = np.interp(t, [0, 0.8, 1.05, 1.6, 2.1, 2.45], [0, 0, 0.9, 1.0, 0.55, 0])
    breath = rng.standard_normal(n)
    breath_env = np.interp(t, [0, 0.15, 0.7, 0.85, 1.6, 2.2, 2.7], [0, 0.35, 0.6, 0.15, 0.25, 0.45, 0])
    src = glottal * voiced_env + breath * (breath_env + 0.18 * voiced_env)

    # форманты: широкое «а» -> «о» -> «х»
    F1 = np.interp(t, [0, 1.0, 1.7, 2.3, 2.7], [600, 800, 760, 520, 450]) * (1.12 if female else 1)
    F2 = np.interp(t, [0, 1.0, 1.7, 2.3, 2.7], [1300, 1250, 1150, 880, 900]) * (1.15 if female else 1)
    F3 = np.full(n, 2650.0) * (1.12 if female else 1)
    blk = 256
    filt = [Formant(), Formant(), Formant()]
    y = np.zeros(n)
    for i in range(0, n, blk):
        seg = src[i:i + blk]
        y[i:i + blk] = (filt[0].run(seg, F1[i], 6) * 1.0 + filt[1].run(seg, F2[i], 8) * 0.6
                        + filt[2].run(seg, F3[i], 10) * 0.25)
    y = highpass(y, 90) + 0.05 * bandpass(breath * breath_env, 500, 3000)
    rev = signal.fftconvolve(y, reverb_ir(0.6, 0.12, stereo=False))[:n]
    return fade(norm(y + 0.18 * rev, 0.85), 0.01, 0.1)


def heartbeat():
    dur = 1.0
    t = t_axis(dur)
    x = np.zeros(len(t))
    for start, amp in ((0.0, 1.0), (0.24, 0.7)):
        tt = t - start
        m = tt >= 0
        x[m] += amp * np.sin(2 * np.pi * (48 + 30 * np.exp(-tt[m] * 30)) * tt[m]) * np.exp(-tt[m] * 14)
    return fade(norm(lowpass(np.tanh(x * 1.6), 300), 0.9), 0.001, 0.05)


def death():
    dur = 3.5
    t = t_axis(dur)
    boom = np.sin(2 * np.pi * np.cumsum(35 + 70 * np.exp(-t * 6)) / SR) * np.exp(-t * 1.6)
    hit = lowpass(rng.standard_normal(len(t)), 900) * np.exp(-t * 9) * 0.6
    ring = np.sin(2 * np.pi * 3400 * t) * 0.025 * np.interp(t, [0, 0.3, 2.2, 3.5], [0, 1, 0.6, 0])
    x = boom + hit
    rev = signal.fftconvolve(x, reverb_ir(2.5, 0.8, stereo=False))[:len(t)]
    return fade(norm(x + 0.5 * rev + ring, 0.9), 0.001, 0.4)


def inhale():
    """Резкий вдох при пробуждении."""
    dur = 1.1
    t = t_axis(dur)
    env = np.interp(t, [0, 0.55, 0.75, 1.1], [0, 1, 0.3, 0])
    x = bandpass(rng.standard_normal(len(t)), 700, 3200) * env
    return fade(norm(x, 0.6), 0.02, 0.1)


# ----------------------------------------------------------------- music ---

def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def ep_note(freq, dur, vel=1.0):
    """Электропиано (FM, похоже на Rhodes)."""
    t = t_axis(dur)
    idx = 2.2 * np.exp(-t * 7) + 0.3
    mod = np.sin(2 * np.pi * freq * t) * idx
    car = np.sin(2 * np.pi * freq * t + mod)
    bell = np.sin(2 * np.pi * freq * 4.0 * t) * 0.08 * np.exp(-t * 12)
    env = np.exp(-t * 1.4) * (1 - np.exp(-t * 400))
    env[-int(0.06 * SR):] *= np.linspace(1, 0, int(0.06 * SR))
    return (car + bell) * env * vel


def pad_note(freq, dur):
    t = t_axis(dur)
    x = np.zeros(len(t))
    for det in (-0.12, 0.0, 0.11):
        f = freq * 2 ** (det / 12)
        x += 2 * ((t * f + rng.uniform()) % 1) - 1
    x = lowpass(x, 900, 2)
    env = np.minimum(1, t / 1.2) * np.minimum(1, (dur - t) / 1.2)
    return x * env * 0.12


def kick():
    t = t_axis(0.45)
    f = 45 + 80 * np.exp(-t * 28)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7) * 0.9


def snare():
    t = t_axis(0.3)
    n = bandpass(rng.standard_normal(len(t)), 1200, 6000) * np.exp(-t * 18)
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.4
    return (n * 0.55 + body) * 0.6


def hat(open_=False):
    t = t_axis(0.25 if open_ else 0.06)
    return highpass(rng.standard_normal(len(t)), 7000) * np.exp(-t * (14 if open_ else 70)) * 0.18


def siren(dur=6.0):
    t = t_axis(dur)
    f = 700 + 220 * np.sin(2 * np.pi * 0.33 * t)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    env = np.sin(np.pi * t / dur) ** 2
    return lowpass(x, 1200) * env * 0.05


def music():
    bpm = 78
    beat = 60 / bpm
    bar = beat * 4
    # ii–V–I–vi в до мажоре, джазовые расширения
    chords = [
        [50, 53, 57, 60, 64],   # Dm9
        [43, 53, 57, 59, 64],   # G13
        [48, 52, 55, 59, 62],   # Cmaj9
        [45, 55, 60, 64, 67],   # Am9 (A C E G B -> обращение)
    ]
    bass = [38, 31, 36, 33]
    sections = ["intro"] * 4 + ["A"] * 8 + ["B"] * 8 + ["A"] * 8 + ["outro"] * 4
    total = len(sections) * bar + 2.5
    n = int(total * SR)
    L = np.zeros((n, 2))
    dry_keys = np.zeros((n, 2))

    def add(buf, x, start, pan=0.0, gain=1.0):
        i = int(start * SR)
        if i >= n:
            return
        x = x[: n - i]
        l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        buf[i:i + len(x), 0] += x * gain * l
        buf[i:i + len(x), 1] += x * gain * r

    swing = 0.09 * beat
    melody_scale = [72, 74, 76, 79, 81, 84]
    for b, sec in enumerate(sections):
        t0 = b * bar
        ch = chords[b % 4]
        # пэд
        for k, note in enumerate(ch[1:]):
            add(L, pad_note(midi(note), bar + 0.6), t0, pan=-0.4 + k * 0.25, gain=0.9 if sec != "intro" else 0.6)
        # электропиано: удар на 1 и синкопа на «и» второй доли
        vel = 0.55 if sec in ("intro", "outro") else 0.7
        for hit_t, v in ((0, 1.0), (beat * 1.5 + swing, 0.7), (beat * 3, 0.5)):
            for k, note in enumerate(ch[1:]):
                add(dry_keys, ep_note(midi(note), beat * 2.2, vel * v * rng.uniform(0.85, 1.0)),
                    t0 + hit_t + k * 0.012, pan=-0.3 + k * 0.15)
        if sec != "intro" and sec != "outro":
            # бас
            for bt, length in ((0, 1.6), (beat * 2.5 + swing, 1.0)):
                t = t_axis(beat * length)
                f = midi(bass[b % 4] + (0 if bt == 0 else 7))
                x = np.tanh(1.5 * np.sin(2 * np.pi * f * t)) * np.exp(-t * 1.2) * (1 - np.exp(-t * 300))
                add(L, lowpass(x, 500) * 0.55, t0 + bt)
            # ударные (свинг на восьмых)
            for i8 in range(8):
                st = t0 + i8 * beat / 2 + (swing if i8 % 2 else 0)
                if i8 in (0, 5):
                    add(L, kick(), st, gain=0.75)
                if i8 in (2, 6):
                    add(L, snare(), st, gain=0.5, pan=0.05)
                add(L, hat(open_=(i8 == 7)), st, pan=0.3, gain=rng.uniform(0.5, 0.9))
        if sec == "B":
            # мелодия-колокольчик по пентатонике
            for i8 in range(8):
                if rng.random() < 0.45:
                    note = melody_scale[rng.integers(0, len(melody_scale))]
                    st = t0 + i8 * beat / 2 + (swing if i8 % 2 else 0)
                    add(dry_keys, ep_note(midi(note), beat * 1.5, 0.35), st, pan=0.35)

    # реверб на клавишах и пэде
    ir = reverb_ir(2.6, 0.7)
    wet = np.stack([signal.fftconvolve(dry_keys[:, c] + L[:, c] * 0.3, ir[:, c])[:n] for c in range(2)], 1)
    mix = L + dry_keys + 0.35 * wet

    # город: дождь, винил, далёкая сирена
    rain = lowpass(rng.standard_normal((n, 2)).T, 2500).T * 0.035
    drops = (rng.random((n, 2)) < 0.0009) * rng.standard_normal((n, 2)) * 0.25
    crackle = (rng.random((n, 2)) < 0.00025) * rng.standard_normal((n, 2)) * 0.35
    mix += rain + highpass(drops.T, 2000).T + highpass(crackle.T, 3000).T
    for st in (bar * 6.5, bar * 21):
        s = siren()
        i = int(st * SR)
        mix[i:i + len(s), 0] += s * 0.8
        mix[i:i + len(s), 1] += s * 0.5

    # лоу-фай: лёгкая сатурация и срез верхов
    mix = np.tanh(mix * 1.3) / 1.3
    mix = np.stack([lowpass(mix[:, c], 7000) for c in range(2)], 1)

    # бесшовная петля: хвост смешиваем с началом
    loop_len = int(len(sections) * bar * SR)
    tail = mix[loop_len:]
    out = mix[:loop_len].copy()
    out[: len(tail)] += tail
    xf = int(0.05 * SR)
    out[:xf] *= np.linspace(0.6, 1, xf)[:, None]
    return norm(out, 0.8)


if __name__ == "__main__":
    import sys
    if "--music-only" in sys.argv:
        save("music/night_city.ogg", music())
        sys.exit()
    save("fx/zipper.wav", zipper())
    save("fx/cloth.wav", cloth())
    save("fx/death.wav", death())
    save("music/night_city.ogg", music())
