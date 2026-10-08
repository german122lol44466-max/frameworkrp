"""Иконки состояний (game-icons.net, CC BY 3.0 — авторы: Lorc, Delapouite и др.) -> PNG.

Берутся из npm-пакета @iconify-json/game-icons, все рисуются одинаково: белый силуэт 128x128,
цвет задаётся в игре. python3 tools/content/status_icons.py
"""
import io
import json
import os
import tarfile
import urllib.request

import cairosvg

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "materials", "nyrp", "status")

ICONS = {
    "tired": "lungs", "hunger": "meal", "thirst": "water-drop", "wet": "droplets", "fall": "falling",
    "injured": "bleeding-wound", "critical": "heart-beats", "bruise": "broken-bone", "concussion": "knockout",
    "stamina": "run", "unconscious": "knockout", "cold": "thermometer-cold",
}


def main():
    meta = json.load(urllib.request.urlopen("https://registry.npmjs.org/@iconify-json/game-icons/latest"))
    data = urllib.request.urlopen(meta["dist"]["tarball"]).read()
    with tarfile.open(fileobj=io.BytesIO(data)) as t:
        icons = json.load(t.extractfile("package/icons.json"))
    size = icons.get("width", 512)
    os.makedirs(OUT, exist_ok=True)
    for name, gi in ICONS.items():
        body = icons["icons"][gi]["body"].replace('fill="currentColor"', 'fill="#ffffff"')
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" fill="#ffffff">{body}</svg>'
        cairosvg.svg2png(bytestring=svg.encode(), write_to=os.path.join(OUT, name + ".png"), output_width=128, output_height=128)
    with open(os.path.join(OUT, "CREDITS.txt"), "w") as f:
        f.write("Иконки состояний: game-icons.net (CC BY 3.0) — Lorc, Delapouite и другие авторы.\n")
        for name, gi in ICONS.items():
            f.write(f"{name}.png <- {gi}\n")
    print("status icons:", len(ICONS))


if __name__ == "__main__":
    main()
