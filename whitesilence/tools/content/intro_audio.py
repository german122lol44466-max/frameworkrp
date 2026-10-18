"""Звуки интро «Белая тишина» -> content/sound/whitesilence/intro/*.ogg

    python3 tools/content/intro_audio.py      (нужны numpy, scipy, ffmpeg; для голоса — sherpa-onnx)

Источники:
  ветер (запись): react-sounds, sounds/ambient/wind.mp3 — MIT (github.com/e3ntity/react-sounds)
  сердцебиение: react-sounds, sounds/ambient/heartbeat.mp3 — MIT
  голос в рации: нейросеть Piper, голоса ru_RU-dmitri / ru_RU-denis (датасет CC0, NabuCasa),
                 модели из релиза k2-fsa/sherpa-onnx (tts-models)
  остальное — синтез здесь же: метель, вертолёт изнутри, удары и гул затемнений, помехи рации.
"""
import os
import subprocess
import sys
import tarfile
import urllib.request

import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "content", "sound", "whitesilence", "intro")
CACHE = os.environ.get("WS_SND_CACHE", "/tmp/ws_snd_cache")
RS = "https://raw.githubusercontent.com/e3ntity/react-sounds/master/sounds/ambient/"
VOICES = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-{}-medium.tar.bz2"
rng = np.random.default_rng(14)


# ---------------------------------------------------------------- база

def fetch(url, name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print("  скачиваю", url)
        urllib.request.urlretrieve(url, path)
    return path


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).copy()


def save(x, name, q=5):
    os.makedirs(OUT, exist_ok=True)
    x = np.asarray(x, np.float32)
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    peak = np.abs(x).max()
    if peak > 0.98:
        x *= 0.98 / peak
    path = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", str(SR), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(q), path], input=x.tobytes(), check=True)
    print("  ", name, "%.1f c" % (len(x) / SR))


def t(sec):
    return np.arange(int(sec * SR)) / SR


def noise(sec, ch=1):
    n = rng.standard_normal((int(sec * SR), ch)).astype(np.float32)
    return n[:, 0] if ch == 1 else n


def pink(sec):
    w = rng.standard_normal(int(sec * SR))
    f = np.fft.rfft(w)
    k = np.arange(len(f))
    k[0] = 1
    return np.fft.irfft(f / np.sqrt(k), len(w)).astype(np.float32) * 30


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "lowpass", fs=SR, output="sos"), x, axis=0)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "highpass", fs=SR, output="sos"), x, axis=0)


def smooth_lfo(sec, rate, seed, lo=0.0, hi=1.0):
    """Медленная случайная огибающая (порывы)."""
    r = np.random.default_rng(seed)
    n = max(4, int(sec * rate) + 4)
    pts = r.random(n)
    xs = np.linspace(0, sec, n)
    v = np.interp(t(sec), xs, pts)
    v = lp(v, rate * 2 + 0.01, 1)
    v = (v - v.min()) / (np.ptp(v) + 1e-9)
    return lo + v * (hi - lo)


def sweep_bp(x, centers, q=6.0, block=1024):
    """Полосовой фильтр с плавающей центральной частотой — «вой» ветра."""
    out = np.zeros_like(x)
    zi = None
    for i in range(0, len(x), block):
        fc = float(np.clip(centers[min(i, len(centers) - 1)], 60, SR / 2.5))
        b, a = signal.iirpeak(fc, q, fs=SR)
        if zi is None:
            zi = signal.lfilter_zi(b, a) * 0
        seg, zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
        out[i:i + block] = seg
    return out


def reverb(x, sec=2.5, mix=0.35, damp=3000, seed=1):
    """Свёртка с синтетическим хвостом (шум с экспоненциальным спадом)."""
    r = np.random.default_rng(seed)
    n = int(sec * SR)
    env = np.exp(-np.linspace(0, 7, n))
    ir = np.stack([r.standard_normal(n) * env, r.standard_normal(n) * env], 1)
    ir = lp(ir, damp)
    ir /= np.sqrt((ir ** 2).sum(0))
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    wet = np.stack([signal.fftconvolve(x[:, c], ir[:, c]) for c in range(2)], 1)
    dry = np.vstack([x, np.zeros((len(wet) - len(x), 2))])
    return dry * (1 - mix) + wet * mix


def stereo(x, width=0.3, seed=2):
    """Псевдостерео: правый канал чуть задержан и окрашен."""
    if x.ndim == 2:
        return x
    d = int(0.011 * SR)
    r = np.concatenate([np.zeros(d), x[:-d]])
    return np.stack([x * (1 - width * 0.3) + r * width * 0.3, r * (1 - width * 0.3) + x * width * 0.3], 1)


def loopify(x, fade=3.0):
    """Делает петлю: хвост перетекает в начало."""
    n = int(fade * SR)
    k = np.linspace(0, 1, n)[:, None] if x.ndim == 2 else np.linspace(0, 1, n)
    head = x[:n] * k + x[-n:] * (1 - k)
    return np.concatenate([head, x[n:-n]])


def env_ad(sec, a, d, curve=4.0):
    tt = t(sec)
    e = np.where(tt < a, tt / max(a, 1e-4), np.exp(-(tt - a) / max(d, 1e-4) * curve / 4))
    return e


def norm(x, peak=0.9):
    return x / (np.abs(x).max() + 1e-9) * peak


# ---------------------------------------------------------------- метель

def blizzard():
    sec = 48
    base = pink(sec)
    # гул ветра: широкая полоса, порывы
    gust = smooth_lfo(sec, 0.25, 11, 0.35, 1.0)
    roar = bp(base, 90, 900) * gust
    # вой: узкие полосы, частота плывёт вместе с порывом
    howl = 0
    for i, (lo, hi) in enumerate(((280, 620), (520, 1100), (900, 1700))):
        c = lo + smooth_lfo(sec, 0.35, 20 + i) * (hi - lo)
        h = sweep_bp(noise(sec), c, q=14 + i * 6)
        howl = howl + h * smooth_lfo(sec, 0.2, 30 + i, 0.0, 1.0) ** 2 * (0.5 / (i + 1))
    # шипение снега по насту
    hiss = hp(noise(sec), 3500) * smooth_lfo(sec, 0.5, 40, 0.2, 0.7) * 0.025
    mono = norm(roar) * 0.7 + norm(howl) * 0.45 + hiss
    st = stereo(mono, 0.8)
    # реальная запись ветра — подложкой (MIT)
    rec = load(fetch(RS + "wind.mp3", "rs_wind.mp3"))
    rec = rec[: len(st)]
    reps = int(np.ceil(len(st) / len(rec)))
    rec = loopify(np.tile(rec, (reps + 1, 1)), 2.0)[: len(st)]
    st = lp(norm(st) * 0.75 + norm(rec) * 0.4, 5500)
    save(norm(loopify(st, 4.0), 0.8), "blizzard")


# ---------------------------------------------------------------- затемнения

def boom():
    """Глухой удар затемнения: суб-бас с падающей частотой + тёмный шумовой хвост."""
    sec = 6
    tt = t(sec)
    f = 52 * np.exp(-tt * 1.4) + 30
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 1.1)
    thump = lp(noise(sec), 180) * np.exp(-tt * 9) * 4
    tail = lp(pink(sec), 600) * np.exp(-tt * 1.5) * 0.15
    x = norm(sub) * 0.9 + norm(thump) * 0.5 + norm(tail) * 0.35
    save(norm(reverb(x, 4.0, 0.4, 900), 0.9), "fade_boom")


def riser():
    """Нарастающий «вдох» перед кадром: шум и тон, разгоняются и обрываются."""
    sec = 3.2
    tt = t(sec)
    e = (tt / sec) ** 3
    w = bp(pink(sec), 300, 3000) * e
    tone = np.sin(2 * np.pi * (110 + 220 * (tt / sec) ** 2) * tt) * e * 0.3
    x = norm(w) * 0.8 + tone
    x[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    save(norm(reverb(x, 1.5, 0.3, 4000), 0.7), "fade_riser")


def dread():
    """Тревожный гул для «Но что-то в них было уже не так...»: биения, низкий кластер, скрип."""
    sec = 9
    tt = t(sec)
    fade = np.clip(tt / 2.5, 0, 1) * np.clip((sec - tt) / 2.0, 0, 1)
    cluster = sum(np.sin(2 * np.pi * f * tt + p) for f, p in ((55, 0), (58.3, 1), (82.4, 2), (87.3, 0.5), (116.5, 1.4)))
    cluster *= 0.5 + 0.5 * np.sin(2 * np.pi * 0.21 * tt)
    # высокий «стеклянный» тон, медленно уезжающий вниз
    glass = np.sin(2 * np.pi * (1760 - 120 * tt / sec) * tt) * 0.08 * smooth_lfo(sec, 0.6, 5)
    # скрежет: модулированный шум
    scrape = bp(noise(sec), 700, 1600) * (smooth_lfo(sec, 2.0, 6) ** 6) * 0.6
    x = (norm(cluster) * 0.7 + glass + scrape * 0.3) * fade
    save(norm(reverb(stereo(x, 0.7), 3.5, 0.45, 2500), 0.8), "dread")


def heartbeat():
    x = load(fetch(RS + "heartbeat.mp3", "rs_heartbeat.mp3"))
    x = lp(x, 900)
    save(norm(x[: int(12 * SR)], 0.8), "heartbeat")


# ---------------------------------------------------------------- рация

def tts(text, voice="dmitri", speed=0.95):
    import sherpa_onnx
    path = fetch(VOICES.format(voice), "vits-%s.tar.bz2" % voice)
    d = os.path.join(CACHE, "vits-piper-ru_RU-%s-medium" % voice)
    if not os.path.isdir(d):
        with tarfile.open(path) as tf:
            tf.extractall(CACHE, filter="data")
    cfg = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
        vits=sherpa_onnx.OfflineTtsVitsModelConfig(model=os.path.join(d, "ru_RU-%s-medium.onnx" % voice),
                                                   tokens=os.path.join(d, "tokens.txt"),
                                                   data_dir=os.path.join(d, "espeak-ng-data")),
        num_threads=4))
    a = sherpa_onnx.OfflineTts(cfg).generate(text, sid=0, speed=speed)
    x = np.array(a.samples, np.float32)
    return signal.resample_poly(x, SR, a.sample_rate).astype(np.float32)


def radio_voice(x, seed):
    """Голос через рацию: узкая полоса, перегруз, выпадения сигнала."""
    r = np.random.default_rng(seed)
    x = bp(x, 380, 2900, 4)
    x = np.tanh(x * 6) * 0.5
    # выпадения: куски глушатся шумом
    gate = np.ones(len(x))
    pos = 0
    while pos < len(x):
        pos += int(r.uniform(0.25, 0.9) * SR)
        if r.random() < 0.45:
            ln = int(r.uniform(0.04, 0.22) * SR)
            gate[pos:pos + ln] = r.uniform(0.0, 0.2)
    gate = lp(gate, 60, 1)
    return x * gate


def static_bed(sec, seed):
    r = np.random.default_rng(seed)
    s = bp(noise(sec), 400, 3800) * 0.08
    # треск
    cr = np.zeros(int(sec * SR))
    for _ in range(int(sec * 25)):
        p = r.integers(0, len(cr) - 200)
        cr[p:p + r.integers(20, 200)] += r.uniform(-1, 1)
    s += hp(cr, 1200) * 0.22
    # «плавание» несущей — свист
    car = np.sin(2 * np.pi * (1200 + 300 * smooth_lfo(sec, 0.5, seed)) * t(sec)) * 0.03
    return s * smooth_lfo(sec, 1.5, seed + 1, 0.5, 1.0) + car


def squelch():
    sec = 0.18
    tt = t(sec)
    return (bp(noise(sec), 800, 3000) * np.exp(-tt * 25) * 0.8 + np.sin(2 * np.pi * 1450 * tt) * np.exp(-tt * 40) * 0.3)


def radio():
    """Сцена с погибшим: кто-то вызывает отряд, ответа нет."""
    lines = [
        ("Дельта-четырнадцать, это «Купол». Ответьте. Приём.", "dmitri", 0.6),
        ("Дельта-четырнадцать, как слышите? Доложите обстановку.", "dmitri", 4.4),
        ("Дельта... ответьте... кто-нибудь...", "denis", 8.6),
    ]
    sec = 13.5
    bed = static_bed(sec, 3)
    mix = np.zeros(int(sec * SR))
    for text, voice, at in lines:
        v = radio_voice(tts(text, voice), hash(text) % 1000)
        p = int(at * SR)
        q = squelch()
        mix[max(0, p - len(q)):p] += q[: p - max(0, p - len(q))]
        mix[p:p + len(v)] += v[: len(mix) - p] * 1.4
        e = p + len(v)
        if e + len(q) < len(mix):
            mix[e:e + len(q)] += q
    x = mix + bed
    fade = np.clip(t(sec) / 0.4, 0, 1) * np.clip((sec - t(sec)) / 1.5, 0, 1)
    x = hp(x, 250) * fade
    save(norm(reverb(stereo(x, 0.2), 0.8, 0.12, 5000), 0.75), "radio")


# ---------------------------------------------------------------- вертолёт изнутри

def heli():
    """Салон: удары лопастей (~17 Гц, «хоп-хоп»), вой турбины, гул редуктора, вибрация корпуса."""
    sec = 30
    tt = t(sec)
    bpf = 17.2 + 0.3 * np.sin(2 * np.pi * 0.05 * tt)            # частота прохода лопастей
    phase = np.cumsum(bpf) / SR
    frac = phase % 1.0
    slap = np.exp(-frac * 9) * (0.85 + 0.15 * smooth_lfo(sec, 1.0, 9))
    thump = lp(noise(sec), 140, 4) * slap * 3 + np.sin(2 * np.pi * phase) * 0.6
    rumble = lp(pink(sec), 220, 3) * 0.6
    gear = (np.sin(2 * np.pi * 312 * tt) * 0.06 + np.sin(2 * np.pi * 624 * tt) * 0.03) * (0.7 + 0.3 * slap)
    turbine = bp(noise(sec), 5200, 6400, 4) * 0.04 + np.sin(2 * np.pi * 5800 * tt) * 0.006
    cabin = bp(pink(sec), 300, 1800) * 0.25 * (0.6 + 0.4 * slap)
    x = norm(thump) * 0.9 + norm(rumble) * 0.6 + gear + turbine + norm(cabin) * 0.25
    x = lp(x, 7000)
    st = stereo(x, 0.5)
    save(norm(loopify(st, 3.0), 0.78), "heli_interior")


# ---------------------------------------------------------------- баннер

def banner_hit():
    """Финальный удар под знак Фонда: суб-бас, металлический звон, длинный хвост."""
    sec = 7
    tt = t(sec)
    sub = np.sin(2 * np.pi * (40 + 25 * np.exp(-tt * 3)) * tt) * np.exp(-tt * 0.9)
    metal = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * d) * a
                for f, d, a in ((233, 0.9, 0.3), (466.5, 1.2, 0.2), (699, 1.7, 0.12), (1053, 2.4, 0.08), (1571, 3.1, 0.05)))
    click = hp(noise(sec), 2000) * np.exp(-tt * 60) * 0.5
    x = norm(sub) * 0.8 + norm(metal) * 0.45 + click
    save(norm(reverb(x, 5.0, 0.45, 2500), 0.9), "banner_hit")


def skip():
    sec = 0.9
    tt = t(sec)
    x = bp(pink(sec), 200, 2500) * np.sin(np.pi * tt / sec) ** 2 * (1 - tt / sec)
    save(norm(reverb(x, 0.8, 0.2), 0.5), "skip")


ALL = {"blizzard": blizzard, "boom": boom, "riser": riser, "dread": dread, "heartbeat": heartbeat,
       "radio": radio, "heli": heli, "banner": banner_hit, "skip": skip}

if __name__ == "__main__":
    for n in sys.argv[1:] or list(ALL):
        print(n)
        ALL[n]()
