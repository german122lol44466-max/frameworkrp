"""Звуки интро «Белая тишина» -> content/sound/whitesilence/intro/*.ogg

    python3 tools/content/intro_audio.py      (нужны numpy, scipy, ffmpeg; для голоса — sherpa-onnx)

Основа — реальные записи (скачиваются с raw.githubusercontent.com, коммиты закреплены), поверх — обработка
(фильтры, реверберация, склейка в петли) и немного синтеза. Источники и лицензии — в REAL ниже и в
content/LICENSES/SOURCES.txt.
  голос в рации: нейросеть Piper, голоса ru_RU-dmitri / ru_RU-denis (датасет CC0, NabuCasa),
                 модели из релиза k2-fsa/sherpa-onnx (tts-models)
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
CC0 = "https://raw.githubusercontent.com/lavenderdotpet/CC0-Public-Domain-Sounds/f2b6264f9ab89fabc266914c3654685d68c5a39b/"
RE = "https://raw.githubusercontent.com/redeclipse/sounds/a5e31a50d899e238febe7db0f80b53cd9a8b089e/ambience/"
OSFX = "https://raw.githubusercontent.com/OpenTTD/OpenSFX/d0bf8d4deda22d5a7f8d01953433cb2644663e9f/src/wav/"

# имя -> (ссылка, лицензия и автор)
REAL = {
    "windy": (RE + "windy.ogg", "Red Eclipse, CC BY-SA 4.0"),
    "wind_bb": (RE + "wind.ogg", "Batuhan Bozkurt (freesound), CC BY-SA 3.0, через Red Eclipse"),
    "stormwind": (RE + "morph/stormwind.ogg", "Q009 (morph), CC BY 3.0, через Red Eclipse"),
    "heli": (OSFX + "osfx_24.wav", "Lorenzo Sutton «helicopterRaw_16sec», ред. Wuzzy, CC BY-SA 3.0, через OpenSFX"),
    "morse": (OSFX + "osfx_22.wav", "Janis Lukss, CC BY 3.0, через OpenSFX"),
    "thunder": (CC0 + "100-cc0-sfx-2/sfx100v2_thunder_01.ogg", "100 CC0 SFX #2, CC0"),
    "fake_thunder": (CC0 + "Micro%20Pack%20-%20Chairmat/Fake%20Thunder%202.wav", "Chairmat, CC0"),
    "boom": (CC0 + "BB_2HTC%20Samples%20Vol%204/Drums/2022-08-17%20Approaching%20the%20Crash%20Site%20-%20Boom.wav", "Ben Burnes, CC0"),
    "bass_swell": (CC0 + "BB_2HTC%20Samples%20Vol%204/Weird/2022-08-17%20Approaching%20the%20Crash%20Site%20-%20Bass%20Swell.wav", "Ben Burnes, CC0"),
    "crash_pad": (CC0 + "BB_2HTC%20Samples%20Vol%204/Pads/2022-08-17%20Approaching%20the%20Crash%20Site%20-%20Fadeout.wav", "Ben Burnes, CC0"),
    "cell": (CC0 + "Micro%20Pack%20-%20NazdyNate%20-%20Electromagnetic%20Sounds/NazdyNate%20-Cell%20Reception%201.wav", "NazdyNate, CC0"),
    "em_room": (CC0 + "Micro%20Pack%20-%20NazdyNate%20-%20Electromagnetic%20Sounds/NazdyNate%20-%20EM%20Room%20Noise%202.wav", "NazdyNate, CC0"),
    "crackle": (CC0 + "Micro%20Pack%20-%20Record%20Fuzzies/Good%20Clean%20Noise.wav", "MadameBerry, CC0"),
    "fan": (CC0 + "bb%20-%20Fans%20and%20Drones%20(Jul%202021)/Large%20Fan.wav", "Ben Burnes, CC0"),
    "swish": (CC0 + "Micro%20Pack%20-%20Organic%20Wooshes/Gentle%20Swish.wav", "Ben Burnes, CC0"),
    "swish3": (CC0 + "Micro%20Pack%20-%20Organic%20Wooshes/Swish%203.wav", "Ben Burnes, CC0"),
}
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


def real(key):
    url = REAL[key][0]
    return load(fetch(url, key + os.path.splitext(url)[1]))


def tile(x, sec, xfade=0.4):
    """Склеивает короткую запись в длинную полосу с перекрёстными затуханиями."""
    n, f = int(sec * SR), int(xfade * SR)
    out = x[:0]
    while len(out) < n + f:
        if len(out) == 0:
            out = x.copy()
        else:
            k = np.linspace(0, 1, f)[:, None]
            out = np.concatenate([out[:-f], out[-f:] * (1 - k) + x[:f] * k, x[f:]])
    return out[:n]


def speed(x, k):
    """Замедление (k < 1, ниже и длиннее) или ускорение записи."""
    from fractions import Fraction
    fr = Fraction(k).limit_denominator(100)
    return signal.resample_poly(x, fr.denominator, fr.numerator, axis=0).astype(np.float32)


def mono(x):
    return x.mean(axis=1) if x.ndim == 2 else x


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
    """Метель: три реальные записи ветра + ледяной шорох + немного синтетического воя, петля 48 с."""
    sec = 48
    windy = loopify(tile(real("windy"), sec + 4, 2.0), 4.0)[: int(sec * SR)]
    wbb = tile(real("wind_bb"), sec, 2.0)
    storm = hp(tile(real("stormwind"), sec, 2.0), 1800)          # шорох снега и льда по насту
    howl = 0
    for i, (lo, hi) in enumerate(((300, 640), (560, 1100))):
        c = lo + smooth_lfo(sec, 0.35, 20 + i) * (hi - lo)
        howl = howl + sweep_bp(noise(sec), c, q=14 + i * 6) * smooth_lfo(sec, 0.2, 30 + i) ** 2 * (0.5 / (i + 1))
    gust = smooth_lfo(sec, 0.22, 11, 0.7, 1.0)[:, None]
    mix = (norm(windy) * 0.75 + norm(wbb) * 0.5 + norm(storm) * 0.22) * gust + stereo(norm(howl), 0.8) * 0.18
    save(norm(loopify(lp(mix, 9000), 4.0), 0.8), "blizzard")


# ---------------------------------------------------------------- затемнения и проявления

def boom():
    """Удар затемнения: глухой бум + раскат далёкого грома + суб."""
    sec = 7
    tt = t(sec)
    th = real("thunder")
    x = np.zeros((int(sec * SR), 2), np.float32)
    x[: len(th)] += norm(lp(th, 2500))[: len(x)] * 0.6
    b = real("boom")
    x[: len(b)] += norm(b) * 0.9
    sub = np.sin(2 * np.pi * np.cumsum(48 * np.exp(-tt * 1.4) + 30) / SR) * np.exp(-tt * 1.2)
    x += stereo(norm(sub) * 0.55)
    save(norm(reverb(x, 4.0, 0.35, 1200), 0.9), "fade_boom")


def riser():
    """Нарастание перед ударом: басовый свэлл + перевёрнутый взмах, обрывается в конце."""
    sw = norm(real("bass_swell"))
    rev = norm(speed(real("swish"), 0.6))[::-1]
    n = max(len(sw), len(rev))
    x = np.zeros((n, 2), np.float32)
    x[n - len(sw):] += sw * 0.8
    x[n - len(rev):] += rev * 0.6
    x[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))[:, None]
    save(norm(reverb(x, 1.2, 0.25, 4000), 0.75), "fade_riser")


def reveal():
    """Проявление кадра мазками: мягкий взмах кисти, замедленный и с хвостом."""
    x = norm(speed(real("swish"), 0.7))
    save(norm(reverb(lp(x, 6000), 2.2, 0.4, 3500), 0.7), "reveal")


def opening():
    """Начало интро: из тишины поднимается низкий гул, вдалеке гром, короткий обрывок эфира."""
    sec = 6
    x = np.zeros((int(sec * SR), 2), np.float32)
    sw = norm(speed(real("bass_swell"), 0.6))
    x[: len(sw)] += sw[: len(x)] * 0.7
    th = norm(lp(speed(real("fake_thunder"), 0.8), 1500))
    p = int(1.2 * SR)
    x[p:p + len(th)] += th[: len(x) - p] * 0.45
    cell = norm(bp(real("cell"), 500, 3500))[int(2 * SR):int(2.6 * SR)]
    p = int(0.6 * SR)
    x[p:p + len(cell)] += cell * np.hanning(len(cell))[:, None] * 0.25
    fade = (np.clip(t(sec) / 1.5, 0, 1) * np.clip((sec - t(sec)) / 2.0, 0, 1))[:, None]
    save(norm(reverb(x * fade, 3.0, 0.4, 2500), 0.8), "opening")


def dread():
    """Тревога для «Но что-то в них было уже не так...»: тёмный пэд, замедленный, плюс диссонанс."""
    sec = 11
    tt = t(sec)
    pad = norm(lp(speed(real("crash_pad"), 0.8), 3000))[: int(sec * SR)]
    if len(pad) < int(sec * SR):
        pad = np.vstack([pad, np.zeros((int(sec * SR) - len(pad), 2), np.float32)])
    cluster = sum(np.sin(2 * np.pi * f * tt + ph) for f, ph in ((55, 0), (58.3, 1), (82.4, 2), (87.3, 0.5)))
    cluster *= 0.5 + 0.5 * np.sin(2 * np.pi * 0.21 * tt)
    fade = (np.clip(tt / 2.0, 0, 1) * np.clip((sec - tt) / 2.0, 0, 1))[:, None]
    x = (pad * 0.8 + stereo(norm(cluster), 0.7) * 0.3) * fade
    save(norm(reverb(x, 3.5, 0.4, 2500), 0.8), "dread")


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
    """Эфир: реальные электромагнитные помехи (CC0) в полосе рации + треск."""
    cell = mono(tile(real("cell"), sec, 1.0))
    em = mono(tile(real("em_room"), sec, 1.0))
    cr = mono(tile(real("crackle"), sec, 1.0))
    s = norm(bp(cell, 350, 3800)) * 0.22 + norm(bp(em, 200, 3000)) * 0.12 + norm(hp(cr, 1500)) * 0.15
    return s * smooth_lfo(sec, 1.2, seed + 1, 0.6, 1.0)


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
    # морзянка в начале — кто-то стучит на частоте отряда
    mo = bp(mono(real("morse")), 500, 2500)
    mix[: len(mo)] += norm(mo)[: len(mix)] * 0.25
    x = mix + bed
    fade = np.clip(t(sec) / 0.4, 0, 1) * np.clip((sec - t(sec)) / 1.5, 0, 1)
    x = hp(x, 250) * fade
    save(norm(reverb(stereo(x, 0.2), 0.8, 0.12, 5000), 0.75), "radio")


# ---------------------------------------------------------------- вертолёт изнутри

def heli():
    """Салон: реальная запись вертолёта (удары лопастей), приглушённая обшивкой, + гул вентилятора как турбина."""
    sec = 30
    rec = real("heli")
    rotor = lp(tile(rec, sec, 0.35), 2600)                       # внутри верх срезан обшивкой
    rotor = rotor + lp(rotor, 180) * 1.5                          # и сильнее «хоп-хоп» в корпусе
    fan = lp(tile(real("fan"), sec, 2.0), 1600)
    rumble = stereo(lp(pink(sec), 160, 3), 0.5)
    whine = stereo(bp(noise(sec), 5200, 6200, 4) * 0.015, 0.4)
    mix = norm(rotor) * 0.85 + norm(fan) * 0.3 + norm(rumble) * 0.35 + whine
    save(norm(loopify(mix, 3.0), 0.8), "heli_interior")


# ---------------------------------------------------------------- баннер

def banner_hit():
    """Финальный удар под знак Фонда: бум + раскат + металлический звон."""
    sec = 8
    tt = t(sec)
    x = np.zeros((int(sec * SR), 2), np.float32)
    b = real("boom")
    x[: len(b)] += norm(b) * 0.9
    ft = norm(lp(real("fake_thunder"), 1800))[: len(x)]
    x[: len(ft)] += ft * 0.45
    metal = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * d) * a
                for f, d, a in ((233, 0.9, 0.3), (466.5, 1.2, 0.2), (699, 1.7, 0.12), (1053, 2.4, 0.08)))
    x += stereo(norm(metal) * 0.3)
    save(norm(reverb(x, 5.0, 0.4, 2500), 0.9), "banner_hit")


def skip():
    x = norm(speed(real("swish3"), 0.8))
    save(norm(reverb(x, 0.8, 0.2), 0.5), "skip")


ALL = {"blizzard": blizzard, "boom": boom, "riser": riser, "reveal": reveal, "opening": opening,
       "dread": dread, "heartbeat": heartbeat,
       "radio": radio, "heli": heli, "banner": banner_hit, "skip": skip}

if __name__ == "__main__":
    for n in sys.argv[1:] or list(ALL):
        print(n)
        ALL[n]()
