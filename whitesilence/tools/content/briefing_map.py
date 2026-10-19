"""Тактическая карта района для брифинга -> content/materials/whitesilence/menu/briefing_map.jpg

    python3 tools/content/briefing_map.py        (numpy, scipy, Pillow)

Рельеф — шум нескольких масштабов, горизонтали каждые 0.04 высоты (толще — каждая пятая), отмывка рельефа,
замёрзшее озеро, сетка квадратов с подписями. Маршрут и метки рисует игра поверх (cl_briefing.lua),
координаты точек — доли ширины/высоты карты.
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "content", "materials", "whitesilence", "menu", "briefing_map.jpg")
FONTS = os.path.join(ROOT, "content", "resource", "fonts")
W, H = 1600, 900


def height():
    rng = np.random.default_rng(14)
    h = np.zeros((H, W), np.float32)
    for scale, amp in ((240, 1.0), (110, 0.45), (48, 0.2), (18, 0.07)):
        n = rng.random((H // scale + 2, W // scale + 2)).astype(np.float32)
        h += amp * ndimage.zoom(n, (H / (n.shape[0] - 1), W / (n.shape[1] - 1)), order=3)[:H, :W]
    h = (h - h.min()) / (h.max() - h.min())
    # озеро на северо-востоке — низина
    yy, xx = np.mgrid[0:H, 0:W]
    lake = np.exp(-(((xx - W * 0.8) / (W * 0.1)) ** 2 + ((yy - H * 0.24) / (H * 0.12)) ** 2))
    h = h * (1 - 0.8 * lake)
    return h, lake


def main():
    h, lake = height()
    # отмывка: свет с северо-запада
    gy, gx = np.gradient(h * 60)
    shade = np.clip(0.75 + (gx * -0.6 + gy * -0.6), 0.35, 1.2)
    base = np.array([28, 34, 40], np.float32) + h[..., None] * np.array([40, 44, 48], np.float32)
    img = base * shade[..., None]
    ice = lake > 0.45
    img[ice] = img[ice] * 0.5 + np.array([60, 90, 110]) * 0.5
    # горизонтали
    levels = (h / 0.04).astype(int)
    edge = (levels != np.roll(levels, 1, 0)) | (levels != np.roll(levels, 1, 1))
    major = edge & (levels % 5 == 0)
    img[edge] = img[edge] * 0.6 + np.array([120, 140, 150]) * 0.4
    img[major] = img[major] * 0.3 + np.array([170, 190, 200]) * 0.7
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(os.path.join(FONTS, "IBMPlexMono_400Regular.ttf"), 14)
    step = 100
    for x in range(0, W, step):
        d.line((x, 0, x, H), fill=(80, 100, 112), width=1)
        d.text((x + 4, 4), "%02d" % (x // step + 40), font=f, fill=(140, 160, 170))
    for y in range(0, H, step):
        d.line((0, y, W, y), fill=(80, 100, 112), width=1)
        d.text((4, y + 4), "%02d" % (y // step + 71), font=f, fill=(140, 160, 170))
    fb = ImageFont.truetype(os.path.join(FONTS, "Oswald_500Medium.ttf"), 22)
    d.text((W * 0.74, H * 0.36), "оз. Безымянное", font=fb, fill=(150, 190, 210))
    d.text((W * 0.06, H * 0.9), "ЛИСТ 71-44 · МАСШТАБ 1:25000 · ГРИФ «СОВ. СЕКРЕТНО»", font=f, fill=(150, 160, 170))
    im = im.filter(ImageFilter.GaussianBlur(0.4))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    im.save(OUT, quality=88)
    print("   карта:", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
