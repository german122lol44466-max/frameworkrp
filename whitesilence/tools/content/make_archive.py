"""Архивы для установки -> dist/

    python3 tools/content/make_archive.py

  whitesilence_gamemode.zip — только код: распаковать в garrysmod/  ->  garrysmod/gamemodes/whitesilence
  whitesilence_content.zip  — контент:    распаковать в garrysmod/  ->  garrysmod/addons/whitesilence_content
Плюс иконка и лого режима для меню (из знака Фонда).
"""
import json
import os
import zipfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GM = os.path.join(ROOT, "gamemodes", "whitesilence")
CONTENT = os.path.join(ROOT, "content")
DIST = os.path.join(ROOT, "dist")


def menu_images():
    logo = Image.open(os.path.join(CONTENT, "materials", "whitesilence", "intro", "scp_logo.png"))
    logo.resize((24, 24), Image.LANCZOS).save(os.path.join(GM, "icon24.png"))
    # лого в меню выбора режима: знак + название
    img = Image.new("RGBA", (288, 128), (0, 0, 0, 0))
    img.alpha_composite(logo.resize((104, 104), Image.LANCZOS), (8, 12))
    d = ImageDraw.Draw(img)
    fonts = os.path.join(CONTENT, "resource", "fonts")
    d.text((124, 30), "SCP", font=ImageFont.truetype(os.path.join(fonts, "Oswald_500Medium.ttf"), 34), fill=(232, 236, 242))
    d.text((124, 72), "БЕЛАЯ ТИШИНА", font=ImageFont.truetype(os.path.join(fonts, "Oswald_300Light.ttf"), 21), fill=(170, 205, 235))
    d.rectangle((124, 68, 270, 69), fill=(196, 38, 38))
    img.save(os.path.join(GM, "logo.png"))


def add_tree(z, src, arc):
    for base, _, files in os.walk(src):
        for f in sorted(files):
            p = os.path.join(base, f)
            z.write(p, os.path.join(arc, os.path.relpath(p, src)))


def main():
    menu_images()
    os.makedirs(DIST, exist_ok=True)
    with open(os.path.join(CONTENT, "addon.json"), "w", encoding="utf-8") as f:
        json.dump({"title": "SCP: Белая тишина — контент", "type": "servercontent", "tags": ["scenic", "fun"],
                   "ignore": ["*.psd", "LICENSES/*"]}, f, ensure_ascii=False, indent="\t")
    out = os.path.join(DIST, "whitesilence_gamemode.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        add_tree(z, GM, "gamemodes/whitesilence")
    print(out, os.path.getsize(out) // 1024, "КБ")
    out = os.path.join(DIST, "whitesilence_content.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        add_tree(z, CONTENT, "addons/whitesilence_content")
    print(out, os.path.getsize(out) // 1024, "КБ")


if __name__ == "__main__":
    main()
