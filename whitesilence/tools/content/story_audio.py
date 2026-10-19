"""Озвучка сюжета -> content/sound/whitesilence/story/*.ogg и голоса врагов -> content/sound/whitesilence/game/enemy_*.mp3

    python3 tools/content/story_audio.py            всё
    python3 tools/content/story_audio.py lines      только реплики сюжета
    python3 tools/content/story_audio.py enemy      только голоса врагов
    (нужны numpy, scipy, ffmpeg, sherpa-onnx)

Реплики читаются из gamemode/modules/story/sh_story.lua (S.Lines), длительности пишутся в sh_story_len.lua.
Голоса — Piper (ru_RU-dmitri, ru_RU-denis; датасеты CC0), эфир — реальные записи помех (см. intro_audio.py),
вдохи между фразами — SCP – Containment Breach (CC BY-SA 3.0, как и звуки дыхания в игре).

Как собирается реплика:
  • текст режется на фразы; каждая синтезируется отдельно, с лёгким разбросом темпа и высоты, «!» — быстрее и
    громче; между фразами — паузы по знакам препинания и иногда вдох;
  • hq (Ледник)  — dmitri; полоса рации, компрессия, щелчок тангенты, в конце — двухтоновый «роджер-бип»,
                   под голосом — гул аппаратной;
  • pilot (Борт) — denis; рация, гул винтов и двигателя, вибрация голоса от тряски;
  • delta        — denis ниже и медленнее; голос раздвоен (второй — чуть ниже и позже), перед словами —
                   обратное эхо, поверх — шёпот по огибающей речи, рация с выпадениями и «заиканием» цифры.
Голоса врагов в мире — без рации: из-под балаклавы, с тем же раздвоением.
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
CB = "https://raw.githubusercontent.com/Regalis11/scpcb/edb8fe0840b78f14d1aef3a0bf6174630e7be296/"

ENEMY = {  # звучат в мире (EmitSound) — mp3; голос: d — denis, m — dmitri
    "enemy_spot1": ("d", "Вижу вас."),
    "enemy_spot2": ("d", "Свои! Не стреляйте!"),
    "enemy_spot3": ("m", "Мы здесь. Мы рядом."),
    "enemy_idle1": ("d", "Ледник… приём… Ледник…"),
    "enemy_idle2": ("m", "Холодно. Так холодно."),
    "enemy_idle3": ("d", "Мы на позиции. Потерь нет."),
    "enemy_reload1": ("d", "Перезаряжаюсь."),
    "enemy_reload2": ("m", "Прикройте… меня."),
    "enemy_grenade1": ("d", "Граната!"),
    "enemy_grenade2": ("m", "Выходите. Выходите к нам."),
    "enemy_flank1": ("d", "Обходим. Слева."),
    "enemy_flank2": ("m", "Я зайду сбоку."),
    "enemy_hurt1": ("d", "Не больно. Уже не больно."),
    "enemy_hurt2": ("m", "Отхожу…"),
    "enemy_lost1": ("d", "Где вы? Мы вас слышим."),
    "enemy_lost2": ("m", "Не прячьтесь. Здесь некуда прятаться."),
    "enemy_down1": ("d", "Минус один. Нас станет больше."),
    "enemy_down2": ("m", "Он вернётся. Мы все возвращаемся."),
}


def lines():
    src = open(os.path.join(LUA, "sh_story.lua"), encoding="utf-8").read()
    return re.findall(r'(\w+)\s*=\s*\{\s*who\s*=\s*"(\w+)",\s*text\s*=\s*"([^"]+)"', src)


def clean(text):
    return text.replace("«", "").replace("»", "").replace("…", "...").replace("—", ",")


def fit(x, n):
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:n]


def pad(x, sec):
    return np.concatenate([x, np.zeros(int(sec * A.SR), np.float32)])


def phrases(text):
    """Разбить на фразы с паузой после каждой (по знаку препинания)."""
    parts = re.findall(r"[^.!?…]+[.!?…]*", text)
    out = []
    for p in parts:
        p = p.strip()
        if not p:
            continue
        end = p[-1]
        pause = {"!": 0.32, "?": 0.42, ".": 0.38, "…": 0.6}.get(end, 0.22)
        if p.endswith("..."):
            pause = 0.6
        out.append((p, end == "!", pause))
    return out or [(text, False, 0.3)]


_breaths = None


def breath(rng):
    global _breaths
    if _breaths is None:
        _breaths = []
        for n in ("breath1", "breath2", "breath3"):
            try:
                x = A.mono(A.load(A.fetch(CB + "SFX/Character/D9341/%s.ogg" % n, "cb_SFX_Character_D9341_%s.ogg" % n)))
                _breaths.append(A.norm(x[: int(0.7 * A.SR)], 0.25))
            except Exception:  # noqa: BLE001 — без сети: вдохов не будет
                pass
    if not _breaths:
        return np.zeros(0, np.float32)
    b = _breaths[rng.integers(len(_breaths))]
    return b * np.linspace(1, 0, len(b)) ** 0.5


def speak(text, voice, speed, rng, breaths=True):
    """Фразы по отдельности, с разбросом и паузами."""
    out = []
    for i, (p, excl, pause) in enumerate(phrases(text)):
        sp = speed * rng.uniform(0.96, 1.04) * (1.07 if excl else 1)
        x = A.tts(clean(p), voice, speed=sp)
        k = rng.uniform(0.985, 1.015)                      # высота чуть гуляет от фразы к фразе
        x = A.speed(x, k)
        x = A.norm(x, 0.95 if excl else 0.8)
        out.append(x)
        if i < len(phrases(text)) - 1:
            gap = np.zeros(int(pause * A.SR * rng.uniform(0.85, 1.2)), np.float32)
            if breaths and pause >= 0.35 and rng.random() < 0.55:
                b = breath(rng) * 0.6
                gap = fit(gap, max(len(gap), len(b)))
                gap[: len(b)] += b[: len(gap)]
            out.append(gap)
    return np.concatenate(out)


def compress(x, thr=0.25, ratio=4.0):
    env = A.lp(np.abs(x), 30)
    gain = np.where(env > thr, (thr + (env - thr) / ratio) / np.maximum(env, 1e-6), 1.0)
    return x * gain


def radio(x, lo=320, hi=3300, drive=4):
    x = A.bp(x, lo, hi, 4)
    x = compress(x)
    return np.tanh(x * drive) * 0.5


def roger(sec=0.22):
    tt = A.t(sec)
    half = len(tt) // 2
    f = np.where(np.arange(len(tt)) < half, 1250, 1650)
    return np.sin(2 * np.pi * f * tt) * 0.18 * np.clip(tt / 0.005, 0, 1)


def stutter(x, rng, n=3):
    """«Заикание» цифрового канала: короткий кусок повторяется."""
    x = x.copy()
    for _ in range(n):
        ln = int(rng.uniform(0.04, 0.09) * A.SR)
        at = int(rng.uniform(0.15, 0.85) * max(len(x) - ln * 4, 1))
        piece = x[at:at + ln].copy()
        for r in range(1, int(rng.integers(2, 4))):
            x[at + r * ln: at + (r + 1) * ln] = piece[: len(x[at + r * ln: at + (r + 1) * ln])]
    return x


def eerie_voice(x, rng):
    """Раздвоенный, чужой голос: ниже, второй голос — ещё ниже и позже, обратное эхо, шёпот."""
    x = A.speed(x, 0.94)
    twin = A.speed(x, 0.965)
    twin = np.concatenate([np.zeros(int(0.035 * A.SR), np.float32), twin])
    n = max(len(x), len(twin))
    body = fit(x, n) + fit(twin, n) * 0.55
    # обратное эхо: реверберация задом наперёд перед словами
    rev = A.mono(A.reverb(body[::-1].copy(), 1.6, 1.0, 2400, int(rng.integers(1000))))[::-1]
    lead = int(0.5 * A.SR)
    pre = np.concatenate([np.zeros(0, np.float32), rev])
    n2 = len(pre)
    out = fit(np.concatenate([np.zeros(n2 - n, np.float32), body]), n2) + pre * 0.35
    # шёпот: шум в верхней полосе по огибающей речи
    env = A.lp(np.abs(fit(np.concatenate([np.zeros(n2 - n, np.float32), body]), n2)), 18)
    wh = A.bp(A.noise(n2 / A.SR), 2500, 7000)[:n2] * env * 1.6
    _ = lead
    return out + wh


def story_line(lid, who, text, seed):
    rng = np.random.default_rng(seed)
    voice = "dmitri" if who == "hq" else "denis"
    v = speak(text, voice, 0.84 if who == "delta" else 1.0, rng, breaths=who != "delta")
    if who == "delta":
        v = eerie_voice(v, rng)
        v = A.radio_voice(radio(v, 300, 3000, 5), seed)
        v = stutter(v, rng, 2)
    elif who == "pilot":
        tt = A.t(len(v) / A.SR)
        v = v * (1 + 0.05 * np.sin(2 * np.pi * 11 * tt))          # голос дрожит от вибрации
        v = radio(v, 300, 3200, 5)
    else:
        v = radio(v, 330, 3300, 3.5)
    lead, tail = 0.2, 0.25
    body = np.concatenate([np.zeros(int(lead * A.SR)), A.norm(v, 0.8), np.zeros(int(tail * A.SR))])
    sec = len(body) / A.SR
    bed = fit(A.static_bed(sec, seed), len(body)) * (0.6 if who == "delta" else 0.3)
    tt = A.t(sec)
    if who == "pilot":
        rotor = A.lp(A.noise(sec), 180) * (0.6 + 0.4 * np.sin(2 * np.pi * 5.5 * tt) ** 2)
        engine = A.bp(A.noise(sec), 700, 1400) * 0.25
        bed = bed + fit(A.norm(rotor + engine, 0.3), len(body))
    elif who == "hq":
        hum = np.sin(2 * np.pi * 50 * tt) * 0.02 + np.sin(2 * np.pi * 100 * tt) * 0.012
        bed = bed + fit(hum, len(body)) + fit(A.lp(A.noise(sec), 400) * 0.03, len(body))
    x = body + bed
    sq = A.squelch()
    end = [sq * 0.8]
    if who == "hq":
        end = [np.zeros(int(0.05 * A.SR)), roger(), sq * 0.6]
    x = np.concatenate([sq, x] + end)
    out = A.norm(A.stereo(x, 0.08), 0.85)
    A.OUT = OUT_STORY
    A.save(out, lid)
    return len(out) / A.SR


def enemy_bark(name, voice, text, seed):
    rng = np.random.default_rng(seed)
    v = speak(text, "denis" if voice == "d" else "dmitri", 0.82, rng, breaths=False)
    v = A.norm(v, 0.9)
    v = eerie_voice(v, rng)
    v = A.lp(A.hp(v, 160), 3600)                          # из-под балаклавы
    wet = A.mono(A.reverb(v, 1.4, 1.0, 2200, seed))
    v = np.concatenate([v, np.zeros(len(wet) - len(v))]) * 0.85 + wet * 0.3
    A.OUT = OUT_GAME
    A.save(A.norm(A.stereo(v, 0.05), 0.9), name)
    ogg = os.path.join(OUT_GAME, name + ".ogg")
    A.subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ogg, "-ac", "1", "-ar", "44100", "-b:a", "96k",
                      os.path.join(OUT_GAME, name + ".mp3")], check=True)
    os.remove(ogg)


def main():
    parts = sys.argv[1:] or ["lines", "enemy"]
    if "lines" in parts:
        os.makedirs(OUT_STORY, exist_ok=True)
        lens = {}
        for i, (lid, who, text) in enumerate(lines()):
            lens[lid] = story_line(lid, who, text, 100 + i)
            print("  %-7s %-6s %.1f с  %s" % (lid, who, lens[lid], text[:60]))
        with open(os.path.join(LUA, "sh_story_len.lua"), "w", encoding="utf-8") as f:
            f.write("-- Сгенерировано tools/content/story_audio.py: длительность реплик (с)\n")
            f.write("WS.Story = WS.Story or {}\nWS.Story.LineLength = {\n")
            for lid, sec in lens.items():
                f.write("\t%s = %.2f,\n" % (lid, sec))
            f.write("}\n")
        print("  всего %.1f с реплик" % sum(lens.values()))
    if "enemy" in parts:
        for i, (name, (voice, text)) in enumerate(ENEMY.items()):
            enemy_bark(name, voice, text, 300 + i)
            print("  ", name)


if __name__ == "__main__":
    main()
