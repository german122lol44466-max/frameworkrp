"""Процедурные бесшовные текстуры для моделей NYRP (numpy) и запись в VTF.

kind: cordura | webbing | metal | lining | leather | denim | knit | plastic | photo
"""
import os
import struct
import zlib

import numpy as np

SIZE = 256


def _blur(a, r):
    """Бесшовный box-blur (заворачивается по краям)."""
    out = a.astype(np.float32)
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for d in range(-r, r + 1):
            acc += np.roll(out, d, axis=axis)
        out = acc / (2 * r + 1)
    return out


def _noise(rng, r):
    n = _blur(rng.standard_normal((SIZE, SIZE)), r)
    return n / (np.abs(n).max() + 1e-6)


def make(kind, color, seed=0):
    rng = np.random.default_rng(zlib.crc32(f"{kind}:{seed}".encode()))
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    base = np.array(color, np.float32) / 255.0
    lum = np.ones((SIZE, SIZE), np.float32)
    tint = np.zeros((SIZE, SIZE, 3), np.float32)

    if kind == "cordura":
        weave = np.where(((x // 2) + (y // 2)) % 2 == 0, 1.06, 0.94)
        weave *= 1 + 0.05 * np.sin(x * np.pi / 2) * np.sin(y * np.pi / 2)
        rip = ((x % 32) < 2) | ((y % 32) < 2)
        lum = weave * np.where(rip, 1.12, 1.0)
        lum *= 1 + 0.10 * _noise(rng, 12) + 0.05 * _noise(rng, 2)
    elif kind == "webbing":
        rib = 0.88 + 0.16 * (0.5 + 0.5 * np.cos(x * 2 * np.pi / 6))
        cross = 1 + 0.04 * np.sin(y * 2 * np.pi / 3)
        lum = rib * cross * (1 + 0.06 * _noise(rng, 6))
        edge = ((x % 64) < 3) | ((x % 64) > 60)
        lum = np.where(edge, lum * 0.8, lum)
    elif kind == "metal":
        streak = _blur(rng.standard_normal((SIZE, SIZE)), 1)
        streak = np.cumsum(streak, axis=1)
        streak = streak - _blur(streak, 24)
        lum = 1 + 0.08 * streak / (np.abs(streak).max() + 1e-6) + 0.04 * _noise(rng, 20)
    elif kind == "lining":
        diag = 0.5 + 0.5 * np.sin((x + y) * 2 * np.pi / 16)
        lum = 0.93 + 0.1 * diag + 0.05 * _noise(rng, 3)
    elif kind == "leather":
        cells = _noise(rng, 3)
        grain = np.abs(cells) ** 0.5
        lum = 0.86 + 0.18 * grain + 0.08 * _noise(rng, 24)
        lum += 0.04 * np.clip(_noise(rng, 1), 0, 1)
    elif kind == "denim":
        twill = ((x + y) % 4 < 2).astype(np.float32)
        lum = 0.9 + 0.14 * twill + 0.06 * _noise(rng, 2) + 0.08 * _noise(rng, 30)
        white = np.clip(_noise(rng, 1) * 2 - 1.2, 0, 1) * 0.35 + twill * 0.12
        tint = white[..., None] * (np.array([0.75, 0.78, 0.82]) - base)
    elif kind == "knit":
        v = np.abs(((x % 8) - 3.5)) / 3.5
        rows = 0.5 + 0.5 * np.cos((y + v * 4) * 2 * np.pi / 6)
        lum = 0.88 + 0.16 * rows + 0.05 * _noise(rng, 3)
    elif kind == "plastic":
        lum = 1 + 0.03 * _noise(rng, 16)
    else:
        lum = 1 + 0.05 * _noise(rng, 8)

    img = base[None, None, :] * lum[..., None] + tint
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def write_vtf(path, img):
    """VTF 7.2, BGR888, полный набор мипов, тайлится (без clamp)."""
    size = img.shape[0]
    mips = []
    cur = img.astype(np.float32)
    while True:
        mips.append(cur)
        if cur.shape[0] == 1:
            break
        s = cur.shape[0] // 2
        cur = cur.reshape(s, 2, s, 2, 3).mean(axis=(1, 3))
    header = struct.pack("<4s2II", b"VTF\0", 7, 2, 80)
    header += struct.pack("<HHIHH4x3f4xfIBIBBH", size, size, 0x0010, 1, 0,
                          0.2, 0.2, 0.2, 1.0, 3, len(mips), 0xFFFFFFFF, 0, 0, 1)
    header += b"\0" * (80 - len(header))
    data = b"".join(np.clip(m[..., ::-1], 0, 255).astype(np.uint8).tobytes() for m in reversed(mips))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(header + data)


def write_vmt(path, texname, phong=False, exponent=30, boost=2):
    extra = ""
    if phong:
        extra = (f'\t"$phong" "1"\n\t"$phongexponent" "{exponent}"\n\t"$phongboost" "{boost}"\n'
                 '\t"$phongfresnelranges" "[0.5 0.8 1]"\n')
    with open(path, "w") as f:
        f.write(f'"VertexLitGeneric"\n{{\n\t"$basetexture" "{texname}"\n{extra}}}\n')
