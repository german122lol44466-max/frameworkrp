"""Звуки телефона (синтез): DTMF-кнопки, гудки (американские частоты), рингтоны, будильники,
затвор камеры, уведомление, блокировка. python3 tools/content/phone_sounds.py"""
import os
import struct

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "sound", "nyrp", "phone")
SR = 44100


def t(d):
    return np.arange(int(d * SR)) / SR


def env(x, a=0.005, r=0.02):
    x = x.copy()
    na, nr = int(a * SR), int(r * SR)
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nr:
        x[-nr:] *= np.linspace(1, 0, nr)
    return x


def save(name, x, loop=False, peak=0.8):
    x = x / (np.abs(x).max() + 1e-9) * peak
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    chunks = b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16) + b"data" + struct.pack("<I", len(pcm)) + pcm
    if loop:
        chunks += b"cue " + struct.pack("<II", 28, 1) + struct.pack("<II4sIII", 1, 0, b"data", 0, 0, 0)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


def tone(freqs, d, a=0.004, r=0.01):
    tt = t(d)
    return env(sum(np.sin(2 * np.pi * f * tt) for f in freqs) / len(freqs), a, r)


def silence(d):
    return np.zeros(int(d * SR))


def bell(f, d, bright=1.0):
    """Мягкий «маримба/колокольчик»: FM с быстрым затуханием."""
    tt = t(d)
    mod = np.sin(2 * np.pi * f * 3.5 * tt) * np.exp(-tt * 12) * 2.2 * bright
    x = np.sin(2 * np.pi * f * tt + mod) * np.exp(-tt * 5.5)
    x += 0.3 * np.sin(2 * np.pi * f * 2 * tt) * np.exp(-tt * 9)
    return env(x, 0.002, 0.05)


def melody(notes, step, total, bright=1.0):
    out = np.zeros(int(total * SR))
    for i, n in enumerate(notes):
        if n is None:
            continue
        f = 440 * 2 ** ((n - 69) / 12)
        b = bell(f, min(step * 3, 1.2), bright)
        o = int(i * step * SR)
        out[o:o + len(b)] += b[:len(out) - o]
    return out


def main():
    dtmf = {"1": (697, 1209), "2": (697, 1336), "3": (697, 1477), "4": (770, 1209), "5": (770, 1336), "6": (770, 1477),
            "7": (852, 1209), "8": (852, 1336), "9": (852, 1477), "star": (941, 1209), "0": (941, 1336), "hash": (941, 1477)}
    for k, fs in dtmf.items():
        save(f"dtmf_{k}.wav", tone(fs, 0.13), peak=0.5)
    # гудки вызова (США): 440+480 Гц, 2 с звук / 4 с тишина — по кругу
    save("ringback.wav", np.concatenate([tone((440, 480), 2.0, 0.02, 0.03), silence(4.0)]), loop=True, peak=0.45)
    # занято: 480+620, 0.5/0.5
    save("busy.wav", np.concatenate([np.concatenate([tone((480, 620), 0.5), silence(0.5)]) for _ in range(4)]), peak=0.45)
    # отбой: три нисходящих сигнала
    save("hangup.wav", np.concatenate([tone((f,), 0.12, 0.003, 0.03) for f in (880, 660, 440)]), peak=0.4)
    # рингтоны (зацикленные): «Манхэттен», «Бруклин», «Гарлем»
    save("ring1.wav", melody([76, 79, 84, 83, None, 79, 81, 76, None, None, None, None], 0.16, 2.6), loop=True)
    save("ring2.wav", melody([72, 76, 79, 76, 72, 76, 79, 84, None, None, None, None, None], 0.14, 2.4, 0.6), loop=True)
    save("ring3.wav", melody([67, 70, 72, 75, 72, 70, 67, None, 63, 65, 67, None, None, None], 0.13, 2.4, 1.4), loop=True)
    # будильники
    beep = np.concatenate([tone((2400,), 0.09, 0.002, 0.01), silence(0.07)] * 4 + [silence(0.6)])
    save("alarm1.wav", beep, loop=True, peak=0.55)
    save("alarm2.wav", melody([79, 84, 88, 91, None, 88, 84, 79, None, None], 0.22, 2.6, 0.8), loop=True)
    # затвор камеры: щелчок шума + механика
    rng = np.random.default_rng(3)
    tt = t(0.18)
    click = rng.normal(0, 1, len(tt)) * np.exp(-tt * 70)
    click2 = np.zeros_like(click)
    o = int(0.07 * SR)
    click2[o:] = rng.normal(0, 1, len(tt) - o) * np.exp(-(tt[o:] - tt[o]) * 90) * 0.7
    save("shutter.wav", click + click2, peak=0.7)
    save("notify.wav", melody([84, 88], 0.09, 0.7, 0.5), peak=0.5)
    save("unlock.wav", melody([79, 86], 0.06, 0.45, 0.3), peak=0.4)
    save("lock.wav", tone((900,), 0.03, 0.001, 0.02) * 0.6, peak=0.35)
    save("key.wav", tone((1500,), 0.02, 0.001, 0.015), peak=0.25)
    save("rec_start.wav", melody([76, 83], 0.08, 0.5, 0.4), peak=0.45)
    save("rec_stop.wav", melody([83, 76], 0.08, 0.5, 0.4), peak=0.45)
    # игры: проигрыш — короткая нисходящая «8-битная» фраза, новый рекорд — восходящее арпеджио
    def square(f, d):
        tt = t(d)
        return env(np.sign(np.sin(2 * np.pi * f * tt)) * 0.5 + np.sin(2 * np.pi * f * tt) * 0.5, 0.003, 0.03)
    save("game_over.wav", np.concatenate([square(440 * 2 ** ((n - 69) / 12), 0.11) for n in (72, 67, 64, 60)]), peak=0.35)
    save("game_record.wav", melody([72, 76, 79, 84, 88], 0.07, 1.0, 0.9), peak=0.5)
    print("phone sounds ok")


if __name__ == "__main__":
    main()
