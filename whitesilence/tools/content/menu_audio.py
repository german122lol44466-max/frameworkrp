"""Звуки главного меню и лобби -> content/sound/whitesilence/menu/*.ogg

    python3 tools/content/menu_audio.py        (нужен ffmpeg)

Все звуки — из SCP – Containment Breach (github.com/Regalis11/scpcb, коммит закреплён), лицензия CC BY-SA 3.0,
авторы звука и музыки CB: Joonas Rikkonen («Regalis»), Caleb Yu, Class401, FireFox, gmodfan11, Kevin MacLeod,
phlip45, revo794, Shaun Gaylard, Slagar, Tim Morrison. Изменения: громкость, обрезка, затухания.
"""
import os
import subprocess
import urllib.parse
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "content", "sound", "whitesilence", "menu")
CACHE = os.environ.get("WS_SND_CACHE", "/tmp/ws_snd_cache")
CB = "https://raw.githubusercontent.com/Regalis11/scpcb/edb8fe0840b78f14d1aef3a0bf6174630e7be296/"

# имя в режиме -> (файл в CB, фильтр ffmpeg)
SOUNDS = {
    "music": ("SFX/Music/Menu.ogg", "loudnorm=I=-20:TP=-2"),                  # тема главного меню CB, петля
    "drone": ("SFX/Ambient/Room ambience/lowdrone.ogg", "volume=0.8"),       # низкий гул под музыкой, петля
    "hover": ("SFX/Interact/Button.ogg", "volume=0.7"),                      # наведение на кнопку
    "click": ("SFX/Interact/Button2.ogg", "volume=0.9"),                     # нажатие
    "open": ("SFX/Interact/KeycardUse1.ogg", "volume=0.8"),                  # переход в лобби
    "invite": ("SFX/Character/MTF/Beep.ogg", "volume=0.9"),                  # пришло приглашение
    "join": ("SFX/Interact/ScannerUse1.ogg", "volume=0.8"),                  # кто-то вошёл в отряд
    "error": ("SFX/Radio/Buzz.ogg", "volume=0.6"),                           # отказ / ошибка
    "spark": ("SFX/Door/DoorSparks.ogg", "volume=0.55"),                     # вспышка искр на фоне
    "flicker": ("SFX/Room/Intro/Light1.ogg", "volume=0.5"),                  # мигание прожектора
    "deploy": ("SFX/Character/MTF/Announc.ogg", "loudnorm=I=-18:TP=-2"),     # объявление МОГ при выдвижении
}


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(CACHE, exist_ok=True)
    for name, (src, flt) in SOUNDS.items():
        cache = os.path.join(CACHE, "cb_" + src.replace("/", "_").replace(" ", "_"))
        if not os.path.exists(cache):
            urllib.request.urlretrieve(CB + urllib.parse.quote(src), cache)
        out = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", cache, "-af", flt, "-ar", "44100", "-ac", "2",
                        "-c:a", "libvorbis", "-q:a", "5", out], check=True)
        print("  ", name, "<-", src)


if __name__ == "__main__":
    main()
