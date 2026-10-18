"""Озвучка сюжета -> content/sound/whitesilence/story/*.ogg и голоса врагов -> content/sound/whitesilence/game/enemy_*.mp3

    python3 tools/content/story_audio.py        (нужны numpy, scipy, ffmpeg, sherpa-onnx)

Реплики читаются из gamemode/modules/story/sh_story.lua (S.Lines), длительности пишутся в sh_story_len.lua.
Голоса — Piper (ru_RU-dmitri, ru_RU-denis; датасеты CC0), эфир — реальные записи помех (см. intro_audio.py).
  hq (Ледник)      — dmitri, рация
  pilot (Борт-7)   — denis, рация + гул винтов
  delta (Дельта-14)— denis ниже и медленнее, рация с выпадениями и «эхом» — голос того, что притворяется отрядом
"""
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import intro_audio as A  # noqa: E402

LUA = os.path.join(A.ROOT, "gamemodes", "whitesilence", "gamemode", "modules", "story")
OUT_STORY = os.path.join(A.ROOT, "content", "sound", "whitesilence", "story")
OUT_GAME = os.path.join(A.ROOT, "content", "sound", "whitesilence", "game")

ENEMY = {  # звучат в мире (EmitSound) — mp3
    "enemy_spot1": "Вижу вас.",
    "enemy_spot2": "Свои! Не стреляйте!",
    "enemy_spot3": "Мы здесь. Мы рядом.",
    "enemy_idle1": "Ледник… приём… Ледник…",
    "enemy_idle2": "Холодно. Так холодно.",
    "enemy_idle3": "Мы на позиции. Потерь нет.",
}


def lines():
    src = open(os.path.join(LUA, "sh_story.lua"), encoding="utf-8").read()
    return re.findall(r'(\w+)\s*=\s*\{\s*who\s*=\s*"(\w+)",\s*text\s*=\s*"([^"]+)"', src)


def clean(text):
    return text.replace("«", "").replace("»", "").replace("…", "...")


def fit(x, n):
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:n]


def radio_clear(x):
    x = A.bp(x, 320, 3300, 4)
    return np.tanh(x * 4) * 0.5


def eerie(x, seed):
    x = A.speed(x, 0.93)                                  # ниже
    wet = A.mono(A.reverb(x, 1.8, 1.0, 2500, seed))   # «эхо» без сухого сигнала
    tail = np.concatenate([np.zeros(int(0.12 * A.SR)), wet])[:len(x) + int(0.8 * A.SR)]
    x = np.concatenate([x, np.zeros(len(tail) - len(x))]) + tail * 0.45
    return A.radio_voice(x, seed)


def story_line(lid, who, text, seed):
    voice = "dmitri" if who == "hq" else "denis"
    v = A.tts(clean(text), voice, speed=0.86 if who == "delta" else 1.0)
    v = A.norm(v, 0.9)
    v = eerie(v, seed) if who == "delta" else radio_clear(v)
    pad = int(0.25 * A.SR)
    sec = (len(v) + 2 * pad) / A.SR
    body = np.concatenate([np.zeros(pad), A.norm(v, 0.8), np.zeros(pad)])
    bed = fit(A.static_bed(sec, seed), len(body)) * (0.6 if who == "delta" else 0.35)
    if who == "pilot":
        tt = A.t(sec)
        rotor = A.lp(A.noise(sec), 180) * (0.6 + 0.4 * np.sin(2 * np.pi * 5.5 * tt) ** 2)
        bed = bed + fit(A.norm(rotor, 0.25), len(body))
    x = body + bed
    sq = A.squelch()
    x = np.concatenate([sq, x, sq * 0.8])
    out = A.norm(A.stereo(x, 0.08), 0.85)
    A.OUT = OUT_STORY
    A.save(out, lid)
    return len(out) / A.SR


def enemy_bark(name, text, seed):
    v = A.tts(clean(text), "denis", speed=0.82)
    v = A.norm(v, 0.9)
    v = A.speed(v, 0.9)
    v = A.lp(A.hp(v, 160), 3600)                          # из-под балаклавы
    wet = A.mono(A.reverb(v, 1.4, 1.0, 2200, seed))
    v = np.concatenate([v, np.zeros(len(wet) - len(v))]) * 0.85 + wet * 0.35
    A.OUT = OUT_GAME
    A.save(A.norm(A.stereo(v, 0.05), 0.9), name)
    ogg = os.path.join(OUT_GAME, name + ".ogg")
    A.subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ogg, "-ac", "1", "-ar", "44100", "-b:a", "96k",
                      os.path.join(OUT_GAME, name + ".mp3")], check=True)
    os.remove(ogg)


def main():
    os.makedirs(OUT_STORY, exist_ok=True)
    lens = {}
    for i, (lid, who, text) in enumerate(lines()):
        lens[lid] = story_line(lid, who, text, 100 + i)
        print("  %-6s %-6s %.1f с  %s" % (lid, who, lens[lid], text[:60]))
    with open(os.path.join(LUA, "sh_story_len.lua"), "w", encoding="utf-8") as f:
        f.write("-- Сгенерировано tools/content/story_audio.py: длительность реплик (с)\n")
        f.write("WS.Story = WS.Story or {}\nWS.Story.LineLength = {\n")
        for lid, sec in lens.items():
            f.write("\t%s = %.2f,\n" % (lid, sec))
        f.write("}\n")
    print("  всего %.1f с реплик" % sum(lens.values()))
    for i, (name, text) in enumerate(ENEMY.items()):
        enemy_bark(name, text, 300 + i)
        print("  ", name)


if __name__ == "__main__":
    main()
