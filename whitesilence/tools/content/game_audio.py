"""Звуки игры -> content/sound/whitesilence/game/*.ogg

    python3 tools/content/game_audio.py        (нужны numpy, scipy, ffmpeg, sherpa-onnx)

  дыхание, сердцебиение, падение тела, «ужас» при смерти — SCP – Containment Breach (CC BY-SA 3.0)
  ПНВ и тепловизор (включение/выключение), щелчок выбора оружия — синтез здесь же
  голосовые фразы (G) — нейросеть Piper, голоса ru_RU-dmitri и ru_RU-denis (датасет CC0), приглушены «балаклавой»
"""
import os
import sys
import urllib.parse

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import intro_audio as A  # noqa: E402

A.OUT = os.path.join(A.ROOT, "content", "sound", "whitesilence", "game")
CB = "https://raw.githubusercontent.com/Regalis11/scpcb/edb8fe0840b78f14d1aef3a0bf6174630e7be296/"

PHRASES = {  # id -> текст (порядок = порядок в радиальном меню G)
    "forward": "Вперёд!",
    "cover": "Прикрываю!",
    "contact": "Контакт! Вижу цель!",
    "reload": "Перезаряжаюсь!",
    "fallback": "Отходим!",
    "help": "Нужна помощь!",
    "clear": "Чисто.",
    "listen": "Тихо... Слышите?",
}


def cb(path):
    return A.load(A.fetch(CB + urllib.parse.quote(path), "cb_" + path.replace("/", "_")))


def from_cb():
    for name, path, vol in (
        ("breath1", "SFX/Character/D9341/breath1.ogg", 0.7), ("breath2", "SFX/Character/D9341/breath2.ogg", 0.7),
        ("breath3", "SFX/Character/D9341/breath3.ogg", 0.7), ("heartbeat", "SFX/Character/D9341/Heartbeat.ogg", 0.8),
        ("wake", "SFX/Ending/MenuBreath.ogg", 0.8), ("bodyfall", "SFX/General/BodyFall.ogg", 0.8),
        ("death", "SFX/Horror/Horror3.ogg", 0.8), ("tick", "SFX/Interact/Button.ogg", 0.5),
        ("select", "SFX/Interact/PickItem1.ogg", 0.6), ("radio", "SFX/Character/MTF/Beep.ogg", 0.5),
    ):
        x = cb(path)
        A.save(A.norm(x, vol), name)


def whine(f0, f1, sec, rise=True):
    tt = A.t(sec)
    k = tt / sec
    f = f0 + (f1 - f0) * (k ** 0.6 if rise else 1 - k)
    ph = np.cumsum(f) / A.SR * 2 * np.pi
    env = np.clip(tt / 0.02, 0, 1) * (np.exp(-tt * 1.2) if rise else (1 - k))
    return np.sin(ph) * env * 0.25


def click(sec=0.05):
    tt = A.t(sec)
    return A.bp(A.noise(sec), 1500, 6000) * np.exp(-tt * 120) * 0.8


def synth():
    # ПНВ: щелчок тумблера + нарастающий писк инвертора (классика)
    on = np.concatenate([click(), whine(1800, 9000, 1.6)])
    A.save(A.norm(A.reverb(A.stereo(on, 0.3), 0.3, 0.1), 0.6), "nvg_on")
    off = np.concatenate([click(), whine(7000, 1500, 0.5, rise=False)])
    A.save(A.norm(A.stereo(off, 0.3), 0.55), "nvg_off")
    # тепловизор: два коротких тона и низкий гул
    tt = A.t(0.12)
    beep = lambda f: np.sin(2 * np.pi * f * tt) * np.clip(tt / 0.005, 0, 1) * np.exp(-tt * 18)
    th = np.concatenate([click(), beep(1200), np.zeros(int(0.05 * A.SR)), beep(1600), whine(400, 2400, 0.8) * 0.6])
    A.save(A.norm(A.stereo(th, 0.3), 0.6), "thermal_on")
    # батарея села
    tt = A.t(0.5)
    low = np.sin(2 * np.pi * 440 * tt) * (np.sin(2 * np.pi * 6 * tt) > 0) * np.exp(-tt * 3) * 0.4
    A.save(A.norm(A.stereo(low, 0.2), 0.5), "battery_low")


def phrases():
    for voice in ("dmitri", "denis"):
        for pid, text in PHRASES.items():
            v = A.tts(text, voice, speed=1.05)
            v = A.lp(A.hp(v, 140), 4200)                       # балаклава и шлем
            v = np.tanh(v * 2.2) * 0.5
            name = "vo_%s_%s" % (voice, pid)
            A.save(A.norm(A.reverb(A.stereo(v, 0.1), 0.35, 0.08, 4000), 0.85), name)
            # фразы звучат в мире через EmitSound — для движка Source надёжнее mp3 (моно, 44.1 кГц)
            ogg = os.path.join(A.OUT, name + ".ogg")
            A.subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ogg, "-ac", "1", "-ar", "44100", "-b:a", "96k",
                              os.path.join(A.OUT, name + ".mp3")], check=True)
            os.remove(ogg)


if __name__ == "__main__":
    parts = sys.argv[1:] or ["cb", "synth", "phrases"]
    if "cb" in parts:
        from_cb()
    if "synth" in parts:
        synth()
    if "phrases" in parts:
        phrases()
