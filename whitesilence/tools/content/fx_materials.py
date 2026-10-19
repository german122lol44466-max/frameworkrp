"""Материалы эффектов -> content/materials/whitesilence/fx/*.vtf + *.vmt

    python3 tools/content/fx_materials.py        (Pillow, numpy; запись VTF — tools/content/vtf.py)

  outline_fill — штриховка силуэта товарищей сквозь стены (диагональные линии и шум, тонируется в коде)
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vtf import save_vmt, save_vtf  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "content", "materials", "whitesilence", "fx")


def outline_fill(n=256):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    d = (x + y) % 10.0
    lines = np.clip(1.0 - np.abs(d - 5.0) / 1.2, 0, 1)            # мягкие диагональные штрихи
    rng = np.random.default_rng(7)
    noise = rng.random((n // 4, n // 4)).astype(np.float32)
    noise = np.array(Image.fromarray((noise * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
    a = np.clip(lines * (0.55 + 0.45 * noise) + 0.12, 0, 1)
    rgba = np.dstack([np.full((n, n), 255), np.full((n, n), 255), np.full((n, n), 255), a * 255]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def main():
    os.makedirs(OUT, exist_ok=True)
    save_vtf(outline_fill(), os.path.join(OUT, "outline_fill.vtf"), fmt="dxt5")
    save_vmt(os.path.join(OUT, "outline_fill.vmt"), "UnlitGeneric", {
        "$basetexture": "whitesilence/fx/outline_fill", "$translucent": "1", "$additive": "1",
        "$vertexcolor": "1", "$vertexalpha": "1", "$ignorez": "1", "$nocull": "1"})
    print("   outline_fill")


if __name__ == "__main__":
    main()
