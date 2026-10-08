"""Текстуры эффектов экрана: кровь по краям (ранение). python3 tools/content/fx_textures.py"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "materials", "nyrp", "ui")


def fbm(W, H, rng, octaves=5):
    out = np.zeros((H, W), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cw, ch = max(2, W // (64 >> o) if (64 >> o) else W), max(2, H // (64 >> o) if (64 >> o) else H)
        n = Image.fromarray((rng.random((ch, cw)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
        out += np.array(n, np.float32) / 255 * amp
        tot += amp
        amp *= 0.55
    return out / tot


def blood_edges(W=1024, H=576, seed=7):
    """Кровь по краям: рваная «дымчатая» кромка (шум) + мелкие брызги, без мультяшных кругов."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W]
    dx = np.minimum(xx, W - 1 - xx) / (W * 0.5)
    dy = np.minimum(yy, H - 1 - yy) / (H * 0.5)
    dist = np.minimum(dx * 1.45, dy * 1.1)            # 0 у края, ~1 в центре
    n = fbm(W, H, rng)
    edge = np.clip(1 - (dist + (n - 0.5) * 0.55) / 0.55, 0, 1) ** 1.8
    # брызги: маленькие капли в полосе у края
    sp = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(sp)
    for _ in range(1400):
        x, y = rng.random() * W, rng.random() * H
        dd = min(x / W, 1 - x / W) * 1.45 * 2, min(y / H, 1 - y / H) * 1.1 * 2
        k = min(dd)
        if k > 0.55 or rng.random() < k * 1.6:
            continue
        r = rng.uniform(0.6, 3.2) * (1.2 - k)
        d.ellipse([x - r, y - r, x + r, y + r], fill=int(rng.uniform(120, 255)))
    sp = np.array(sp.filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255
    alpha = np.clip(edge * 0.95 + sp * 0.8, 0, 1)
    dark = np.clip(edge * 0.6 + n * 0.4, 0, 1)
    r = (120 - 70 * dark).astype(np.uint8)
    g = (6 - 4 * dark).astype(np.uint8)
    b = (10 - 6 * dark).astype(np.uint8)
    img = np.dstack([r, g, b, (alpha * 255).astype(np.uint8)])
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, "blood_edges.png"))
    print("blood_edges.png")


if __name__ == "__main__":
    blood_edges()
