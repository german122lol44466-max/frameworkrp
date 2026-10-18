"""Иконки HUD -> content/materials/whitesilence/icons/*.png (белые, 128x128, на прозрачном фоне)

    python3 tools/content/hud_icons.py        (нужны resvg-py, Pillow)

Иконки — Tabler Icons (MIT, tabler.io/icons), пакет @tabler/icons из npm; «патрон» нарисован здесь.
"""
import io
import json
import os
import tarfile
import urllib.request

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "content", "materials", "whitesilence", "icons")
CACHE = os.environ.get("WS_ICON_CACHE", "/tmp/ws_tabler")

ICONS = {  # имя в режиме -> файл Tabler
    "health": "filled/medical-cross", "armor": "filled/shield", "stamina": "outline/run",
    "battery": "filled/battery-3", "nvg": "outline/binoculars", "thermal": "filled/flame",
    "mic": "filled/microphone", "user": "filled/user", "squad": "filled/shield-check", "skull": "outline/skull",
    "radio": "outline/radio", "chat": "filled/messages", "ping": "outline/antenna-bars-4", "steps": "outline/footsteps",
    "heart": "filled/heart", "alert": "outline/alert-triangle", "users": "outline/users", "eye": "outline/eye",
}


def tabler():
    pkg = os.path.join(CACHE, "package")
    if not os.path.isdir(pkg):
        os.makedirs(CACHE, exist_ok=True)
        meta = json.load(urllib.request.urlopen("https://registry.npmjs.org/@tabler/icons/latest"))
        data = urllib.request.urlopen(meta["dist"]["tarball"]).read()
        with tarfile.open(fileobj=io.BytesIO(data)) as tf:
            tf.extractall(CACHE, filter="data")
    return os.path.join(pkg, "icons")


def render(svg_path, size=128):
    import resvg_py
    svg = open(svg_path, encoding="utf-8").read().replace("currentColor", "#ffffff")
    png = resvg_py.svg_to_bytes(svg_string=svg, width=size, height=size)
    return Image.open(io.BytesIO(bytes(png))).convert("RGBA")


def bullet(size=128):
    ss = 4
    S = size * ss
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    w = S * 0.26
    x0, x1 = S / 2 - w / 2, S / 2 + w / 2
    d.rectangle((x0, S * 0.42, x1, S * 0.86), fill=(255, 255, 255, 255))            # гильза
    d.rectangle((x0 - S * 0.02, S * 0.86, x1 + S * 0.02, S * 0.92), fill=(255, 255, 255, 255))  # закраина
    d.pieslice((x0, S * 0.1, x1, S * 0.62), 180, 360, fill=(255, 255, 255, 255))      # пуля
    d.rectangle((x0, S * 0.36, x1, S * 0.40), fill=(255, 255, 255, 255))
    return im.resize((size, size), Image.LANCZOS)


def main():
    icons = tabler()
    os.makedirs(OUT, exist_ok=True)
    for name, src in ICONS.items():
        render(os.path.join(icons, src + ".svg")).save(os.path.join(OUT, name + ".png"))
        print("  ", name)
    bullet().save(os.path.join(OUT, "ammo.png"))
    print("   ammo")


if __name__ == "__main__":
    main()
