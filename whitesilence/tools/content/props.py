"""Свои модели предметов и сюжетных объектов (без studiomdl): геометрия + текстуры кодом.

    python3 tools/content/props.py            (numpy, Pillow; VTF — tools/content/vtf.py)

Каждая модель — низкополигональная сетка из примитивов (параллелепипеды, цилиндры, призмы) в юнитах
Source (z вверх, x вперёд, начало координат — центр дна) и своя текстура 512×512, нарисованная здесь же:
ткань с прострочкой, крашеный металл с потёртостями, картон, бумага, трафаретные надписи шрифтами режима.

Результат:
  content/materials/whitesilence/props/<id>.vtf + .vmt     материал (UnlitGeneric; свет считает игра)
  gamemode/modules/props/cl_mesh_data.lua                  вершины и треугольники
  gamemode/modules/props/sh_props_bounds.lua               габариты (для физики на сервере)
  dist/props_preview.png                                   превью всех моделей (программная отрисовка)
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vtf import save_vmt, save_vtf  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAT = os.path.join(ROOT, "content", "materials", "whitesilence", "props")
LUA = os.path.join(ROOT, "gamemodes", "whitesilence", "gamemode", "modules", "props")
FONTS = os.path.join(ROOT, "content", "resource", "fonts")
T = 512
RNG = np.random.default_rng(42)


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


# ======================================================================== геометрия

def rot(p=0, y=0, r=0):
    p, y, r = map(math.radians, (p, y, r))
    Rz = np.array([[math.cos(y), -math.sin(y), 0], [math.sin(y), math.cos(y), 0], [0, 0, 1]])
    Ry = np.array([[math.cos(p), 0, math.sin(p)], [0, 1, 0], [-math.sin(p), 0, math.cos(p)]])
    Rx = np.array([[1, 0, 0], [0, math.cos(r), -math.sin(r)], [0, math.sin(r), math.cos(r)]])
    return Rz @ Ry @ Rx


class Mesh:
    def __init__(self):
        self.v = []      # x y z nx ny nz u v
        self.t = []
        self.fullbright = False

    def vert(self, p, n, uv):
        self.v.append((*p, *n, uv[0] / T, uv[1] / T))
        return len(self.v) - 1

    def quad(self, pts, n, uvs):
        ids = [self.vert(p, n, uv) for p, uv in zip(pts, uvs)]
        self.t += [(ids[0], ids[1], ids[2]), (ids[0], ids[2], ids[3])]

    def tri(self, pts, ns, uvs):
        ids = [self.vert(p, n, uv) for p, n, uv in zip(pts, ns, uvs)]
        self.t.append(tuple(ids))

    def bounds(self):
        a = np.array([v[:3] for v in self.v])
        return a.min(0), a.max(0)


def _rect_uv(rect, turn=0):
    """Углы грани: левый-низ, правый-низ, правый-верх, левый-верх; turn — поворот текстуры на 90° × turn."""
    u0, v0, u1, v1 = rect
    base = [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
    turn %= 4
    return base[turn:] + base[:turn]


def box(m, size, at=(0, 0, 0), R=None, uv=None):
    """Параллелепипед: size (x,y,z), at — центр. uv: прямоугольник или словарь граней
    (front +x, back -x, left +y, right -y, top +z, bottom -z, side — для остальных)."""
    R = np.eye(3) if R is None else R
    at = np.array(at, float)
    sx, sy, sz = (s / 2 for s in size)
    faces = {
        "front": ((1, 0, 0), [(sx, -sy, -sz), (sx, sy, -sz), (sx, sy, sz), (sx, -sy, sz)]),
        "back": ((-1, 0, 0), [(-sx, sy, -sz), (-sx, -sy, -sz), (-sx, -sy, sz), (-sx, sy, sz)]),
        "left": ((0, 1, 0), [(sx, sy, -sz), (-sx, sy, -sz), (-sx, sy, sz), (sx, sy, sz)]),
        "right": ((0, -1, 0), [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz), (-sx, -sy, sz)]),
        "top": ((0, 0, 1), [(sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz), (-sx, -sy, sz)]),
        "bottom": ((0, 0, -1), [(-sx, -sy, -sz), (-sx, sy, -sz), (sx, sy, -sz), (sx, -sy, -sz)]),
    }
    turns = uv.get("turn", {}) if isinstance(uv, dict) else {}
    for name, (n, pts) in faces.items():
        if isinstance(uv, dict):
            rect = uv.get(name) or uv.get("side") or uv.get("all")
        else:
            rect = uv
        pts = [tuple(R @ np.array(p) + at) for p in pts]
        m.quad(pts, tuple(R @ np.array(n)), _rect_uv(rect, turns.get(name, 0)))


def cyl(m, r, h, at=(0, 0, 0), R=None, seg=14, side=None, cap=None, r2=None, caps=(True, True), smooth=True):
    """Цилиндр (или усечённый конус r→r2) вдоль локальной оси z; at — центр нижнего основания."""
    R = np.eye(3) if R is None else R
    at = np.array(at, float)
    r2 = r if r2 is None else r2
    u0, v0, u1, v1 = side
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        p = [(r * math.cos(a0), r * math.sin(a0), 0), (r * math.cos(a1), r * math.sin(a1), 0),
             (r2 * math.cos(a1), r2 * math.sin(a1), h), (r2 * math.cos(a0), r2 * math.sin(a0), h)]
        pts = [tuple(R @ np.array(q) + at) for q in p]
        ua, ub = u0 + (u1 - u0) * i / seg, u0 + (u1 - u0) * (i + 1) / seg
        uvs = [(ua, v1), (ub, v1), (ub, v0), (ua, v0)]
        slope = (r - r2) / max(h, 1e-6)
        if smooth:
            ns = [tuple(R @ np.array((math.cos(a), math.sin(a), slope)) / math.sqrt(1 + slope * slope)) for a in (a0, a1, a1, a0)]
            ids = [m.vert(pt, n, uv) for pt, n, uv in zip(pts, ns, uvs)]
            m.t += [(ids[0], ids[1], ids[2]), (ids[0], ids[2], ids[3])]
        else:
            am = (a0 + a1) / 2
            m.quad(pts, tuple(R @ np.array((math.cos(am), math.sin(am), slope))), uvs)
    if cap:
        cu0, cv0, cu1, cv1 = cap
        cx, cy, rr = (cu0 + cu1) / 2, (cv0 + cv1) / 2, (cu1 - cu0) / 2
        for z, rad, n, on in ((h, r2, (0, 0, 1), caps[1]), (0, r, (0, 0, -1), caps[0])):
            if not on:
                continue
            c = tuple(R @ np.array((0, 0, z)) + at)
            nn = tuple(R @ np.array(n))
            for i in range(seg):
                a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
                if n[2] < 0:
                    a0, a1 = a1, a0
                q0 = tuple(R @ np.array((rad * math.cos(a0), rad * math.sin(a0), z)) + at)
                q1 = tuple(R @ np.array((rad * math.cos(a1), rad * math.sin(a1), z)) + at)
                m.tri([c, q0, q1], [nn] * 3, [(cx, cy), (cx + rr * math.cos(a0), cy - rr * math.sin(a0)),
                                             (cx + rr * math.cos(a1), cy - rr * math.sin(a1))])


def rod(m, p0, p1, r, side, seg=6, cap=None):
    """Цилиндр от точки p0 до p1 (антенны, ножки, провода)."""
    p0, p1 = np.array(p0, float), np.array(p1, float)
    d = p1 - p0
    ln = float(np.linalg.norm(d))
    z = d / ln
    x = np.cross(z, (0, 0, 1)) if abs(z[2]) < 0.95 else np.cross(z, (0, 1, 0))
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    cyl(m, r, ln, tuple(p0), R=np.stack([x, y, z], 1), seg=seg, side=side, cap=cap)


def prism(m, rings, side, cap=None):
    """Неправильная призма: rings = [(z, [(x,y), ...]), ...] с одинаковым числом точек; плоские нормали."""
    u0, v0, u1, v1 = side
    zmin, zmax = rings[0][0], rings[-1][0]
    for (za, A), (zb, B) in zip(rings[:-1], rings[1:]):
        n = len(A)
        for i in range(n):
            j = (i + 1) % n
            p = [(A[i][0], A[i][1], za), (A[j][0], A[j][1], za), (B[j][0], B[j][1], zb), (B[i][0], B[i][1], zb)]
            e1, e2 = np.subtract(p[1], p[0]), np.subtract(p[3], p[0])
            nrm = np.cross(e1, e2)
            nrm = tuple(nrm / (np.linalg.norm(nrm) + 1e-9))
            ua, ub = u0 + (u1 - u0) * i / n, u0 + (u1 - u0) * (i + 1) / n
            va = v1 - (v1 - v0) * (za - zmin) / (zmax - zmin)
            vb = v1 - (v1 - v0) * (zb - zmin) / (zmax - zmin)
            m.quad(p, nrm, [(ua, va), (ub, va), (ub, vb), (ua, vb)])
    if cap:
        z, P = rings[-1]
        c = (sum(q[0] for q in P) / len(P), sum(q[1] for q in P) / len(P), z)
        cu0, cv0, cu1, cv1 = cap
        for i in range(len(P)):
            j = (i + 1) % len(P)
            m.tri([c, (P[i][0], P[i][1], z), (P[j][0], P[j][1], z)], [(0, 0, 1)] * 3,
                  [((cu0 + cu1) / 2, (cv0 + cv1) / 2), (cu0, cv1), (cu1, cv1)])


# ======================================================================== текстуры

def noise(w, h, scale=8, seed=None):
    rng = np.random.default_rng(seed) if seed is not None else RNG
    small = rng.random((max(2, h // scale), max(2, w // scale))).astype(np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img, np.float32) / 255.0


def fill(img, rect, col, var=0.08, scale=6, ao=0.25, grain=0.05):
    """Заливка области: цвет + крупный шум + мелкое зерно + затемнение к краям (фальшивое AO)."""
    x0, y0, x1, y1 = map(int, rect)
    w, h = x1 - x0, y1 - y0
    if w <= 0 or h <= 0:
        return
    n = noise(w, h, scale) * 0.7 + noise(w, h, max(2, scale // 3)) * 0.3
    g = RNG.random((h, w)).astype(np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    a = 1 - ao * np.exp(-edge / max(3.0, min(w, h) * 0.08))
    k = (1 + (n - 0.5) * 2 * var + (g - 0.5) * grain) * a
    base = np.array(col[:3], np.float32)
    arr = np.clip(base[None, None, :] * k[..., None], 0, 255).astype(np.uint8)
    img.paste(Image.fromarray(arr, "RGB"), (x0, y0))


def wear(img, rect, amount=0.5, col=(150, 150, 140)):
    """Потёртости краски у краёв и царапины."""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = rect
    for _ in range(int(40 * amount)):
        side = RNG.integers(4)
        if side == 0:
            x, y = RNG.uniform(x0, x1), RNG.uniform(y0, y0 + 6)
        elif side == 1:
            x, y = RNG.uniform(x0, x1), RNG.uniform(y1 - 6, y1)
        elif side == 2:
            x, y = RNG.uniform(x0, x0 + 6), RNG.uniform(y0, y1)
        else:
            x, y = RNG.uniform(x1 - 6, x1), RNG.uniform(y0, y1)
        r = RNG.uniform(0.6, 2.2)
        d.ellipse((x - r, y - r * 0.6, x + r, y + r * 0.6), fill=col)
    for _ in range(int(12 * amount)):
        x, y = RNG.uniform(x0, x1), RNG.uniform(y0, y1)
        ang = RNG.uniform(0, math.pi)
        ln = RNG.uniform(4, 18)
        d.line((x, y, x + math.cos(ang) * ln, y + math.sin(ang) * ln), fill=tuple(int(c * 0.9) for c in col), width=1)


def stitch(img, rect, col=(30, 30, 26), inset=4, dash=5):
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = (rect[0] + inset, rect[1] + inset, rect[2] - inset, rect[3] - inset)
    for x in np.arange(x0, x1, dash * 2):
        d.line((x, y0, min(x + dash, x1), y0), fill=col)
        d.line((x, y1, min(x + dash, x1), y1), fill=col)
    for y in np.arange(y0, y1, dash * 2):
        d.line((x0, y, x0, min(y + dash, y1)), fill=col)
        d.line((x1, y, x1, min(y + dash, y1)), fill=col)


def weave(img, rect, k=0.06):
    x0, y0, x1, y1 = map(int, rect)
    a = np.asarray(img.crop((x0, y0, x1, y1)), np.float32)
    yy, xx = np.mgrid[0:y1 - y0, 0:x1 - x0]
    pat = ((xx // 2 + yy // 2) % 2) * 2 - 1
    a = np.clip(a * (1 + pat[..., None] * k), 0, 255).astype(np.uint8)
    img.paste(Image.fromarray(a, "RGB"), (x0, y0))


def text(img, rect, s, fname="Oswald_500Medium.ttf", size=28, col=(230, 230, 220), rotate=0, alpha=230, rough=True):
    """Надпись по центру прямоугольника; rough — «трафарет» с выщербинами."""
    x0, y0, x1, y1 = rect
    f = font(fname, size)
    lay = Image.new("L", (int(x1 - x0), int(y1 - y0)), 0)
    d = ImageDraw.Draw(lay)
    lines = s.split("\n")
    hs = [d.textbbox((0, 0), ln, font=f) for ln in lines]
    total = sum(b[3] - b[1] for b in hs) + (len(lines) - 1) * size * 0.25
    y = (lay.size[1] - total) / 2
    for ln, b in zip(lines, hs):
        d.text(((lay.size[0] - (b[2] - b[0])) / 2 - b[0], y - b[1]), ln, font=f, fill=alpha)
        y += (b[3] - b[1]) + size * 0.25
    if rotate:
        lay = lay.rotate(rotate, expand=False)
    if rough:
        n = (noise(lay.size[0], lay.size[1], 3) > 0.25).astype(np.float32)
        lay = Image.fromarray((np.asarray(lay, np.float32) * n).astype(np.uint8))
    img.paste(Image.new("RGB", lay.size, col), (int(x0), int(y0)), lay)


def cross(img, rect, col=(196, 30, 30), bg=(236, 236, 228)):
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = rect
    d.rectangle(rect, fill=bg)
    cx, cy, w = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0)
    t = w * 0.18
    d.rectangle((cx - t, y0 + w * 0.15, cx + t, y1 - w * 0.15), fill=col)
    d.rectangle((x0 + w * 0.15, cy - t, x1 - w * 0.15, cy + t), fill=col)


def tex():
    return Image.new("RGB", (T, T), (128, 128, 128))


# ======================================================================== модели

PROPS = {}


def prop(pid, name, mass=2.0, fullbright=False):
    def deco(fn):
        PROPS[pid] = (name, mass, fullbright, fn)
        return fn
    return deco


@prop("medkit", "Аптечка", 2.0)
def medkit():
    im, m = tex(), Mesh()
    OLIVE = (92, 98, 62)
    fill(im, (0, 0, 256, 160), OLIVE, scale=4)            # бока
    weave(im, (0, 0, 256, 160))
    stitch(im, (0, 0, 256, 160))
    fill(im, (256, 0, 512, 160), OLIVE, scale=4)          # верх/низ
    weave(im, (256, 0, 512, 160))
    stitch(im, (256, 0, 512, 160))
    cross(im, (334, 26, 434, 126))                        # нашивка с крестом
    stitch(im, (334, 26, 434, 126), col=(120, 20, 20), inset=3, dash=3)
    fill(im, (0, 160, 256, 320), OLIVE, scale=4)          # торцы
    weave(im, (0, 160, 256, 320))
    text(im, (8, 170, 248, 230), "АПТЕЧКА", size=34, col=(20, 22, 16))
    text(im, (8, 236, 248, 290), "ИНДИВИДУАЛЬНАЯ · АИ-4", size=18, col=(24, 26, 20), fname="Exo2_600SemiBold.ttf")
    fill(im, (256, 160, 512, 200), (40, 40, 36), scale=2) # стропа
    weave(im, (256, 160, 512, 200), 0.15)
    fill(im, (256, 200, 512, 240), (150, 140, 120), scale=2, var=0.05)  # молния
    d = ImageDraw.Draw(im)
    for x in range(256, 512, 4):
        d.line((x, 214, x + 2, 226), fill=(70, 66, 58))
    side = (0, 0, 256, 160)
    top = (256, 0, 512, 160)
    end = (0, 160, 256, 320)
    strap = (256, 160, 512, 200)
    zip_ = (256, 200, 512, 240)
    # корпус: мягкий короб с «подушкой» по центру
    box(m, (14, 7, 9), (0, 0, 4.5), uv={"top": top, "bottom": top, "front": end, "back": end, "side": side})
    box(m, (13.4, 7.4, 1.0), (0, 0, 6.2), uv=zip_)                         # молния по кругу
    box(m, (2.0, 7.6, 9.6), (-3.5, 0, 4.6), uv=strap)                      # стропы
    box(m, (2.0, 7.6, 9.6), (3.5, 0, 4.6), uv=strap)
    box(m, (6, 1.0, 0.6), (0, 0, 9.6), uv=strap)                           # ручка
    box(m, (0.8, 1.0, 1.6), (-2.6, 0, 9.0), uv=strap)
    box(m, (0.8, 1.0, 1.6), (2.6, 0, 9.0), uv=strap)
    return im, m


@prop("bandage", "Бинт", 0.2)
def bandage():
    im, m = tex(), Mesh()
    fill(im, (0, 0, 512, 128), (232, 228, 214), scale=3, var=0.05)
    weave(im, (0, 0, 512, 128), 0.08)
    d = ImageDraw.Draw(im)
    for x in range(0, 512, 24):
        d.line((x, 0, x + 6, 128), fill=(214, 208, 192), width=2)
    fill(im, (0, 128, 128, 256), (228, 224, 208), scale=2)
    for r in range(4, 60, 5):
        d.ellipse((64 - r, 192 - r, 64 + r, 192 + r), outline=(200, 194, 178))
    fill(im, (128, 128, 512, 256), (210, 196, 160), scale=3)              # бумажная обёртка
    text(im, (128, 136, 512, 200), "БИНТ СТЕРИЛЬНЫЙ", size=26, col=(60, 50, 40), rough=False)
    text(im, (128, 200, 512, 250), "7 м × 14 см · ГОСТ 1172-93", size=18, col=(80, 70, 56), fname="Exo2_400Regular.ttf", rough=False)
    cyl(m, 1.7, 3.6, (0, 0, 1.7), R=rot(90, 0, 0) @ rot(0, 0, 0), seg=16, side=(0, 0, 512, 128), cap=(4, 132, 124, 252))
    box(m, (2.4, 3.8, 0.12), (1.6, 0, 0.06), uv=(0, 0, 128, 128))          # свисающий конец
    box(m, (3.2, 3.9, 0.3), (-0.8, 0, 3.55), uv=(128, 128, 512, 256))      # обёртка поверх
    return im, m


@prop("painkillers", "Промедол", 0.1)
def painkillers():
    im, m = tex(), Mesh()
    fill(im, (0, 0, 512, 200), (196, 98, 30), scale=4, var=0.06, ao=0.1)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 40, 512, 170), fill=(238, 234, 222))
    text(im, (0, 44, 512, 120), "ПРОМЕДОЛ", size=46, col=(30, 40, 90), rough=False)
    text(im, (0, 116, 512, 166), "ОБЕЗБОЛИВАЮЩЕЕ · 10 ТАБ.", size=20, col=(60, 60, 60), fname="Exo2_600SemiBold.ttf", rough=False)
    fill(im, (0, 200, 512, 300), (236, 236, 232), scale=2, var=0.03)
    for x in range(0, 512, 12):
        d.line((x, 200, x, 300), fill=(210, 210, 206), width=3)
    fill(im, (0, 300, 120, 420), (240, 240, 236), scale=2)
    cyl(m, 1.2, 3.0, (0, 0, 0), seg=16, side=(0, 0, 512, 200), cap=(0, 300, 120, 420))
    cyl(m, 1.28, 0.8, (0, 0, 3.0), seg=16, side=(0, 200, 512, 300), cap=(0, 300, 120, 420))
    return im, m


def ammo_can(label, sub, size, col):
    im, m = tex(), Mesh()
    fill(im, (0, 0, 512, 256), col, scale=6, var=0.07)
    wear(im, (0, 0, 512, 256), 1.0, col=(120, 120, 108))
    text(im, (0, 30, 512, 150), label, size=64, col=(232, 220, 170))
    text(im, (0, 150, 512, 230), sub, size=28, col=(232, 220, 170))
    fill(im, (0, 256, 512, 512), col, scale=6, var=0.07)
    wear(im, (0, 256, 512, 512), 0.8, col=(120, 120, 108))
    d = ImageDraw.Draw(im)
    for y in range(290, 480, 40):                                          # рёбра жёсткости
        d.rectangle((20, y, 492, y + 8), fill=tuple(int(c * 1.15) for c in col))
        d.rectangle((20, y + 8, 492, y + 11), fill=tuple(int(c * 0.7) for c in col))
    sx, sy, sz = size
    box(m, size, (0, 0, sz / 2), uv={"front": (0, 0, 512, 256), "back": (0, 0, 512, 256), "side": (0, 256, 512, 512)})
    box(m, (sx + 0.3, sy + 0.3, sz * 0.12), (0, 0, sz * 0.92), uv=(0, 256, 512, 300))   # крышка
    box(m, (sx * 0.4, 0.6, 0.5), (0, 0, sz + 0.25), uv=(0, 256, 512, 300))            # ручка
    return im, m


@prop("ammo_rifle", "Патроны 5.45×39", 1.6)
def ammo_rifle():
    return ammo_can("5.45×39", "120 ПАТР. · ПС · ЛОТ 07-24", (10, 4.4, 6.5), (74, 84, 58))


@prop("ammo_pistol", "Пистолетные патроны", 0.5)
def ammo_pistol():
    im, m = tex(), Mesh()
    fill(im, (0, 0, 512, 512), (176, 150, 108), scale=5, var=0.06)       # картон
    d = ImageDraw.Draw(im)
    d.rectangle((0, 60, 512, 200), fill=(150, 36, 30))
    text(im, (0, 64, 512, 196), ".45 ACP · 50", size=56, col=(240, 230, 210), rough=False)
    text(im, (0, 210, 512, 300), "ПИСТОЛЕТНЫЕ ПАТРОНЫ", size=30, col=(60, 40, 30), rough=False)
    box(m, (4.4, 3.0, 1.8), (0, 0, 0.9), uv={"top": (0, 0, 512, 320), "side": (0, 200, 512, 320)})
    return im, m


@prop("battery", "Батарея ПНВ", 0.3)
def battery():
    im, m = tex(), Mesh()
    fill(im, (0, 0, 256, 384), (38, 40, 42), scale=4, var=0.05)            # лицевая сторона (вертикальная)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 70, 256, 150), fill=(210, 160, 40))
    text(im, (0, 70, 256, 150), "1ПН138", size=40, col=(30, 30, 30), rough=False)
    text(im, (0, 170, 256, 250), "АКБ ПНВ", size=36, col=(220, 220, 220), rough=False)
    text(im, (0, 250, 256, 310), "3.7 В · 2600 мА·ч", size=20, col=(170, 170, 170), fname="Exo2_600SemiBold.ttf", rough=False)
    fill(im, (256, 0, 512, 384), (34, 36, 38), scale=4, var=0.05)          # бока
    fill(im, (0, 384, 128, 512), (190, 170, 120), scale=2)                 # клеммы
    box(m, (1.4, 3.0, 4.4), (0, 0, 2.2), uv={"front": (0, 0, 256, 384), "back": (0, 0, 256, 384), "side": (256, 0, 512, 384)})
    for y in (-0.7, 0.7):
        cyl(m, 0.25, 0.3, (0, y, 4.4), seg=8, side=(0, 384, 128, 512), cap=(0, 384, 128, 512))
    return im, m


@prop("crate", "Ящик снабжения", 30)
def crate():
    im, m = tex(), Mesh()
    G = (70, 78, 56)
    fill(im, (0, 0, 512, 256), G, scale=8, var=0.08)
    wear(im, (0, 0, 512, 256), 1.5)
    d = ImageDraw.Draw(im)
    for x in (0, 492):
        d.rectangle((x, 0, x + 20, 256), fill=(52, 58, 42))
    text(im, (30, 30, 482, 140), "СНАБЖЕНИЕ", size=72, col=(226, 222, 200))
    text(im, (30, 140, 482, 230), "ФОНД SCP · МОГ «БУРАН» · НЕ БРОСАТЬ", size=26, col=(226, 222, 200))
    fill(im, (0, 256, 512, 512), G, scale=8, var=0.08)
    wear(im, (0, 256, 512, 512), 1.0)
    for y in range(256, 512, 64):
        d.line((0, y, 512, y), fill=(44, 50, 36), width=3)
    fill(im, (0, 0, 1, 1), G)
    metal = (0, 480, 64, 512)
    fill(im, metal, (110, 112, 110), scale=2)
    box(m, (32, 20, 16), (0, 0, 8), uv={"front": (0, 0, 512, 256), "back": (0, 0, 512, 256), "side": (0, 256, 512, 512)})
    box(m, (33, 21, 2), (0, 0, 16.5), uv=(0, 256, 512, 320))               # крышка
    for x in (-15.5, 15.5):                                                # металлические углы
        for y in (-9.5, 9.5):
            box(m, (2, 2, 17.6), (x, y, 8.8), uv=metal)
    for x in (-8, 8):                                                      # замки
        box(m, (2.4, 21.4, 2.6), (x, 0, 15), uv=metal)
    return im, m


@prop("radio", "Ретранслятор Р-168", 40)
def radio():
    im, m = tex(), Mesh()
    G = (78, 86, 74)
    fill(im, (0, 0, 512, 256), G, scale=6)
    wear(im, (0, 0, 512, 256), 1.2)
    d = ImageDraw.Draw(im)
    d.rectangle((24, 24, 488, 232), fill=(34, 36, 34))                     # передняя панель
    for i, x in enumerate(range(60, 460, 80)):                             # ручки и шкалы
        d.ellipse((x - 22, 50, x + 22, 94), fill=(20, 20, 20), outline=(140, 140, 130), width=2)
        d.line((x, 72, x + 14 * math.cos(i), 72 - 14 * math.sin(i + 1)), fill=(220, 220, 210), width=3)
    d.rectangle((60, 120, 300, 170), fill=(60, 90, 70))
    text(im, (60, 120, 300, 170), "КАНАЛ 07  ·  148.25", size=22, col=(160, 240, 170), fname="IBMPlexMono_400Regular.ttf", rough=False)
    for x in range(330, 470, 18):
        d.ellipse((x, 128, x + 10, 138), fill=(180, 40, 30) if x < 370 else (60, 160, 60))
    text(im, (24, 186, 488, 232), "Р-168 · ФОНД SCP", size=26, col=(200, 200, 190))
    fill(im, (0, 256, 512, 384), G, scale=6)
    wear(im, (0, 256, 512, 384), 1.0)
    fill(im, (0, 384, 512, 448), (40, 40, 40), scale=2)                    # мачта/кабель
    fill(im, (0, 448, 512, 512), (150, 150, 150), scale=2)                 # металл
    front, side, dark, steel = (0, 0, 512, 256), (0, 256, 512, 384), (0, 384, 512, 448), (0, 448, 512, 512)
    box(m, (16, 24, 16), (0, 0, 8), uv={"front": front, "side": side})
    box(m, (17, 25, 1.2), (0, 0, 16.6), uv=side)
    box(m, (6, 3, 1.2), (0, 0, 17.6), uv=dark)                             # ручка
    cyl(m, 0.7, 64, (-5, 9, 16), seg=8, side=steel, cap=steel)             # мачта
    for k in range(4):                                                     # антенны-«метёлка»
        a = k * math.pi / 2 + 0.6
        rod(m, (-5, 9, 78), (-5 + math.cos(a) * 18, 9 + math.sin(a) * 18, 70), 0.25, steel)
    rod(m, (8, -9, 6), (2, -16, 1), 0.6, dark)                             # кабель к аккумулятору
    box(m, (6, 8, 5), (2, -18, 2.5), uv=side)                              # аккумулятор рядом
    return im, m


@prop("generator", "Дизель-генератор ДГУ-5", 120)
def generator():
    im, m = tex(), Mesh()
    Y = (170, 140, 52)
    fill(im, (0, 0, 512, 256), Y, scale=6, var=0.09)
    wear(im, (0, 0, 512, 256), 2.0, col=(90, 86, 70))
    d = ImageDraw.Draw(im)
    for y in range(40, 220, 14):                                           # жалюзи
        d.rectangle((40, y, 300, y + 6), fill=(60, 54, 30))
    d.rectangle((320, 40, 480, 220), fill=(40, 40, 38))
    text(im, (320, 50, 480, 110), "ДГУ-5", size=40, col=(230, 230, 220))
    for i, x in enumerate((350, 400, 450)):
        d.ellipse((x - 14, 130, x + 14, 158), fill=(230, 230, 220))
        d.line((x, 144, x + 10 * math.cos(i * 2), 144 - 10 * math.sin(i * 2 + 1)), fill=(180, 30, 30), width=2)
    d.rectangle((340, 180, 460, 206), fill=(180, 30, 30))
    text(im, (340, 180, 460, 206), "ПУСК", size=18, col=(240, 240, 240), rough=False)
    fill(im, (0, 256, 512, 384), Y, scale=6, var=0.09)
    wear(im, (0, 256, 512, 384), 1.5, col=(90, 86, 70))
    text(im, (0, 256, 512, 384), "ОГНЕОПАСНО · ДИЗЕЛЬ", size=34, col=(40, 34, 20))
    fill(im, (0, 384, 512, 448), (40, 40, 40), scale=2)                    # шины/рама
    fill(im, (0, 448, 512, 512), (110, 110, 108), scale=2)
    front, side, dark, steel = (0, 0, 512, 256), (0, 256, 512, 384), (0, 384, 512, 448), (0, 448, 512, 512)
    box(m, (44, 26, 24), (0, 0, 20), uv={"front": front, "back": side, "side": side})
    box(m, (46, 28, 2), (0, 0, 33), uv=steel)                              # крыша
    box(m, (50, 30, 3), (0, 0, 6.5), uv=dark)                              # рама
    for x in (-14, 14):                                                    # колёса
        for y in (-16, 16):
            cyl(m, 6.5, 3, (x, y, 6.5), R=rot(0, 0, 90), seg=12, side=dark, cap=dark)
    cyl(m, 1.4, 16, (-18, 8, 34), seg=10, side=dark, cap=dark)             # выхлоп
    cyl(m, 5, 20, (14, 0, 33), R=rot(0, 0, 90) @ rot(0, 0, 0), seg=12, side=side, cap=steel)  # бак
    box(m, (6, 2, 8), (-26, 0, 10), uv=steel)                              # дышло
    return im, m


@prop("charge", "Заряд", 1.5)
def charge():
    im, m = tex(), Mesh()
    fill(im, (0, 0, 512, 256), (190, 176, 140), scale=3, var=0.05)        # пластит
    text(im, (0, 20, 512, 140), "ПВВ-5А", size=60, col=(70, 50, 30))
    text(im, (0, 140, 512, 230), "ВЗРЫВЧАТОЕ ВЕЩЕСТВО · 400 г", size=24, col=(70, 50, 30))
    fill(im, (0, 256, 512, 320), (40, 40, 44), scale=2)                    # изолента
    weave(im, (0, 256, 512, 320), 0.05)
    fill(im, (0, 320, 256, 448), (26, 26, 28), scale=2)                    # таймер
    d = ImageDraw.Draw(im)
    d.rectangle((20, 350, 236, 418), fill=(14, 4, 4))
    text(im, (20, 350, 236, 418), "00:30", size=50, col=(255, 40, 30), fname="IBMPlexMono_400Regular.ttf", rough=False)
    fill(im, (256, 320, 512, 448), (170, 30, 30), scale=2)                 # провода
    box(m, (8, 4.4, 2.4), (0, 0, 1.2), uv={"top": (0, 0, 512, 256), "side": (0, 0, 512, 64), "turn": {"top": 3}})
    for x in (-2.5, 2.5):
        box(m, (1.2, 4.8, 2.8), (x, 0, 1.3), uv=(0, 256, 512, 320))
    box(m, (3.6, 2.4, 1.0), (0, 0, 2.9), uv={"top": (0, 320, 256, 448), "side": (0, 256, 512, 320), "turn": {"top": 3}})
    rod(m, (1.6, 0.8, 3.0), (4.6, 2.2, 2.4), 0.18, (256, 320, 512, 448), seg=5)    # провода к детонатору
    rod(m, (1.6, -0.8, 3.0), (4.4, -2.4, 2.2), 0.18, (0, 256, 512, 320), seg=5)
    return im, m


@prop("docs", "Документы", 0.4)
def docs():
    im, m = tex(), Mesh()
    fill(im, (0, 0, 256, 352), (132, 104, 64), scale=4, var=0.06)          # картонная папка
    text(im, (0, 40, 256, 120), "ДЕЛО №", size=36, col=(50, 34, 20))
    text(im, (0, 110, 256, 170), "МОГ «ДЕЛЬТА-14»", size=24, col=(50, 34, 20))
    d = ImageDraw.Draw(im)
    d.rectangle((30, 220, 226, 280), outline=(160, 30, 30), width=4)
    text(im, (30, 220, 226, 280), "СОВ. СЕКРЕТНО", size=26, col=(170, 30, 30))
    fill(im, (256, 0, 512, 352), (226, 222, 206), scale=3, var=0.04, ao=0.1)
    for y in range(30, 340, 16):                                           # строки машинописи
        ln = RNG.uniform(140, 230)
        d.line((280, y, 280 + ln, y), fill=(90, 90, 96), width=2)
    fill(im, (0, 352, 512, 384), (200, 196, 180), scale=2)                 # срез стопки
    for x in range(0, 512, 3):
        d.line((x, 352, x, 384), fill=(180 + (x % 7) * 4,) * 3)
    cover = {"top": (0, 0, 256, 352), "bottom": (0, 0, 256, 352), "side": (0, 352, 512, 384), "turn": {"top": 3, "bottom": 3}}
    box(m, (12, 9, 0.25), (0, 0, 0.125), uv=cover)
    box(m, (11.4, 8.4, 0.5), (0.1, 0.2, 0.5), R=rot(0, 3, 0), uv={"top": (256, 0, 512, 352), "side": (0, 352, 512, 384), "turn": {"top": 3}})
    box(m, (12, 9, 0.2), (-0.1, 0.05, 0.85), R=rot(0, -2, 0), uv=cover)
    return im, m


@prop("map", "Карта", 0.2)
def map_():
    im, m = tex(), Mesh()
    fill(im, (0, 0, 512, 512), (220, 214, 190), scale=4, var=0.05, ao=0.05)
    d = ImageDraw.Draw(im)
    # горизонтали
    cx, cy = 260, 240
    for k in range(18):
        r = 20 + k * 14
        pts = []
        for i in range(60):
            a = 2 * math.pi * i / 60
            rr = r * (1 + 0.18 * math.sin(a * 3 + k * 0.4) + 0.08 * math.sin(a * 7))
            pts.append((cx + math.cos(a) * rr * 1.2, cy + math.sin(a) * rr))
        d.line(pts + [pts[0]], fill=(160, 120, 80), width=1 if k % 5 else 2)
    for x in range(0, 512, 64):
        d.line((x, 0, x, 512), fill=(120, 140, 170), width=1)
        d.line((0, x, 512, x), fill=(120, 140, 170), width=1)
    d.line([(40, 470), (150, 380), (260, 300), (330, 180), (420, 90)], fill=(200, 30, 30), width=4)
    for p in ((150, 380), (330, 180), (420, 90)):
        d.ellipse((p[0] - 8, p[1] - 8, p[0] + 8, p[1] + 8), outline=(200, 30, 30), width=3)
    text(im, (360, 50, 500, 90), "ОБЪЕКТ 7", size=22, col=(200, 30, 30), rough=False)
    # сложенная карта: три панели «гармошкой»
    for i, (x, a) in enumerate(((-3.3, 4), (0, -4), (3.3, 4))):
        u0 = i * 512 / 3
        box(m, (3.3, 8, 0.12), (x, 0, 0.1 + 0.12 * (i == 1)), R=rot(a, 0, 0), uv={"top": (u0, 0, u0 + 512 / 3, 512), "side": (0, 0, 8, 8)})
    return im, m


@prop("core", "Источник", 400, fullbright=True)
def core():
    im, m = tex(), Mesh()
    a = np.zeros((T, T, 3), np.float32)
    n = noise(T, T, 16) * 0.6 + noise(T, T, 4) * 0.4
    a[..., 0] = 120 + n * 60
    a[..., 1] = 160 + n * 60
    a[..., 2] = 200 + n * 50
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    for _ in range(26):                                                    # светящиеся трещины
        x, y = RNG.uniform(0, T), RNG.uniform(0, T)
        pts = [(x, y)]
        for _ in range(8):
            x += RNG.uniform(-30, 30)
            y += RNG.uniform(10, 40)
            pts.append((x, y))
        d.line(pts, fill=(210, 245, 255), width=int(RNG.integers(1, 4)))
    glow = img.filter(ImageFilter.GaussianBlur(3))
    im = Image.blend(img, glow, 0.35)
    rings = []
    for z, rad in ((0, 22), (20, 19), (52, 14), (80, 8), (94, 2)):
        pts = []
        for i in range(7):
            ang = 2 * math.pi * i / 7 + z * 0.01
            rr = rad * RNG.uniform(0.75, 1.15)
            pts.append((math.cos(ang) * rr, math.sin(ang) * rr))
        rings.append((z, pts))
    prism(m, rings, (0, 0, 512, 512), cap=(0, 0, 64, 64))
    for k in range(5):                                                     # осколки у основания
        ang = k * 1.3
        box(m, (5, 3, 9), (math.cos(ang) * 26, math.sin(ang) * 26, 3), R=rot(RNG.uniform(-25, 25), math.degrees(ang), RNG.uniform(-20, 20)),
            uv=(0, 0, 128, 256))
    return im, m


@prop("terminal", "Полевой терминал", 6)
def terminal():
    im, m = tex(), Mesh()
    fill(im, (0, 0, 512, 256), (52, 56, 50), scale=5)
    wear(im, (0, 0, 512, 256), 1.0)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 256, 512, 512), fill=(10, 18, 14))                    # экран
    for i, ln in enumerate(["ФОНД SCP // ТЕРМИНАЛ 7-Б", "> СВЯЗЬ: НЕТ", "> ЖУРНАЛ ОБЪЕКТА 7...", "> ЗАПИСИ: 214",
                            "> ПОСЛЕДНИЙ ВХОД:", "  ОРЛОВ А.С.", "> _"]):
        text(im, (20, 270 + i * 32, 500, 300 + i * 32), ln, size=20, col=(110, 230, 140), fname="IBMPlexMono_400Regular.ttf", rough=False)
    for y in range(256, 512, 3):
        d.line((0, y, 512, y), fill=(0, 0, 0))
    fill(im, (256, 0, 512, 128), (30, 30, 30), scale=2)                    # клавиатура
    for y in range(8, 120, 22):
        for x in range(264, 504, 24):
            d.rectangle((x, y, x + 18, y + 16), fill=(60, 60, 60))
    case, screen, keys = (0, 0, 256, 256), (0, 256, 512, 512), (256, 0, 512, 128)
    box(m, (12, 16, 1.6), (0, 0, 0.8), uv={"top": keys, "side": case})
    box(m, (0.8, 16, 11), (-6.3, 0, 6.5), R=rot(-12, 0, 0), uv={"front": screen, "side": case})
    return im, m


@prop("beacon", "Маяк", 12)
def beacon():
    im, m = tex(), Mesh()
    fill(im, (0, 0, 512, 256), (190, 60, 30), scale=4)
    wear(im, (0, 0, 512, 256), 1.0)
    text(im, (0, 60, 512, 200), "МАЯК · SOS", size=60, col=(240, 236, 226))
    fill(im, (0, 256, 512, 384), (60, 60, 60), scale=3)
    fill(im, (0, 384, 512, 512), (230, 60, 40), scale=2, var=0.02)
    steel, red, lamp = (0, 256, 512, 384), (0, 0, 512, 256), (0, 384, 512, 512)
    for k in range(3):                                                     # тренога
        a = k * 2 * math.pi / 3
        rod(m, (math.cos(a) * 13, math.sin(a) * 13, 0), (math.cos(a) * 2.5, math.sin(a) * 2.5, 30), 0.5, steel)
    box(m, (8, 8, 10), (0, 0, 34), uv=red)
    cyl(m, 2.2, 5, (0, 0, 39), seg=10, side=lamp, cap=lamp)
    return im, m


# ======================================================================== вывод

def lua_numbers(vals, fmt):
    return ",".join(fmt % v for v in vals).replace(".000", "").replace("-0,", "0,")


def raster(cell, m, im, yaw=215, pitch=24):
    """Программная отрисовка с z-буфером: текстура по UV, свет по нормали (как увидит игра, без теней)."""
    V = np.array([v[:3] for v in m.v])
    N = np.array([v[3:6] for v in m.v])
    UV = np.array([v[6:8] for v in m.v])
    lo, hi = V.min(0), V.max(0)
    c = (lo + hi) / 2
    cy_, sy_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    # камера смотрит на модель спереди-сбоку-сверху: x экрана, y экрана, глубина
    def proj(P):
        P = P - c
        x = P[:, 0] * sy_ - P[:, 1] * cy_
        f = P[:, 0] * cy_ + P[:, 1] * sy_
        y = P[:, 2] * cp + f * sp
        dpt = f * cp - P[:, 2] * sp
        return np.stack([x, y, dpt], 1)
    S = proj(V)
    span = max(np.ptp(S[:, 0]), np.ptp(S[:, 1])) or 1
    sc = cell * 0.78 / span
    sx = cell / 2 - S[:, 0] * sc * -1
    sy = cell / 2 - S[:, 1] * sc
    zb = np.full((cell, cell), np.inf)
    out = np.zeros((cell, cell, 3), np.float32)
    mask = np.zeros((cell, cell), bool)
    tex_ = np.asarray(im, np.float32)
    light = np.array([0.45, -0.35, 0.82])
    light /= np.linalg.norm(light)
    for t in m.t:
        i, j, k = t
        x0, y0, x1, y1, x2, y2 = sx[i], sy[i], sx[j], sy[j], sx[k], sy[k]
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-9:
            continue
        bx0, bx1 = int(max(0, math.floor(min(x0, x1, x2)))), int(min(cell - 1, math.ceil(max(x0, x1, x2))))
        by0, by1 = int(max(0, math.floor(min(y0, y1, y2)))), int(min(cell - 1, math.ceil(max(y0, y1, y2))))
        if bx1 < bx0 or by1 < by0:
            continue
        yy, xx = np.mgrid[by0:by1 + 1, bx0:bx1 + 1] + 0.5
        w0 = ((y1 - y2) * (xx - x2) + (x2 - x1) * (yy - y2)) / den
        w1 = ((y2 - y0) * (xx - x2) + (x0 - x2) * (yy - y2)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        if not inside.any():
            continue
        z = w0 * S[i, 2] + w1 * S[j, 2] + w2 * S[k, 2]
        sub = zb[by0:by1 + 1, bx0:bx1 + 1]
        upd = inside & (z < sub)
        if not upd.any():
            continue
        u = w0 * UV[i, 0] + w1 * UV[j, 0] + w2 * UV[k, 0]
        v = w0 * UV[i, 1] + w1 * UV[j, 1] + w2 * UV[k, 1]
        tx = tex_[np.clip((v * T).astype(int), 0, T - 1), np.clip((u * T).astype(int), 0, T - 1)]
        n = N[i] * w0[..., None] + N[j] * w1[..., None] + N[k] * w2[..., None]
        n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
        shade = np.ones_like(u) if m.fullbright else 0.38 + 0.62 * np.clip(n @ light, 0, 1)
        col = tx * shade[..., None]
        sub[upd] = z[upd]
        o = out[by0:by1 + 1, bx0:bx1 + 1]
        o[upd] = col[upd]
        mask[by0:by1 + 1, bx0:bx1 + 1] |= upd
    img = Image.new("RGB", (cell, cell), (40, 44, 52))
    arr = np.asarray(img, np.float32).copy()
    arr[mask] = out[mask]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def render_preview(items):
    cell = 360
    cols = 4
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cell * cols, cell * rows), (40, 44, 52))
    d = ImageDraw.Draw(sheet)
    for idx, (pid, name, im, m) in enumerate(items):
        ox, oy = (idx % cols) * cell, (idx // cols) * cell
        sheet.paste(raster(cell, m, im), (ox, oy))
        d.text((ox + 10, oy + 8), "%s  (%d тр.)" % (name, len(m.t)), fill=(230, 230, 230), font=font("Exo2_600SemiBold.ttf", 16))
    return sheet


def main():
    os.makedirs(MAT, exist_ok=True)
    os.makedirs(LUA, exist_ok=True)
    items = []
    data = ["-- Сгенерировано tools/content/props.py: сетки моделей (x y z nx ny nz u v; треугольники от 0)",
            "WS.MeshData = WS.MeshData or {}"]
    bounds = ["-- Сгенерировано tools/content/props.py: габариты и параметры моделей",
              "WS.Props = WS.Props or {}", "WS.Props.Defs = {"]
    for pid, (name, mass, fullbright, fn) in PROPS.items():
        im, m = fn()
        m.fullbright = fullbright
        save_vtf(im, os.path.join(MAT, pid + ".vtf"), fmt="dxt1")
        save_vmt(os.path.join(MAT, pid + ".vmt"), "UnlitGeneric", {
            "$basetexture": "whitesilence/props/" + pid, "$vertexcolor": "1", "$nocull": "1"})
        vflat = []
        for v in m.v:
            vflat += v
        fmt = []
        data.append("WS.MeshData[%r] = { fullbright = %s, v = { %s }, t = { %s } }" % (
            pid, "true" if fullbright else "false",
            ",".join(("%.2f" % x).rstrip("0").rstrip(".") if i % 8 < 6 else ("%.4f" % x).rstrip("0").rstrip(".")
                     for i, x in enumerate(vflat)),
            ",".join(str(i) for t in m.t for i in t)))
        lo, hi = m.bounds()
        bounds.append('\t[%r] = { name = %r, mass = %g, mins = Vector(%.1f, %.1f, %.1f), maxs = Vector(%.1f, %.1f, %.1f) },' % (
            pid, name, mass, *lo, *hi))
        items.append((pid, name, im, m))
        print("  %-12s %4d верш. %4d тр.  %s" % (pid, len(m.v), len(m.t), name))
        _ = fmt
    bounds.append("}")
    with open(os.path.join(LUA, "cl_mesh_data.lua"), "w", encoding="utf-8") as f:
        f.write("\n".join(data).replace("'", '"') + "\n")
    with open(os.path.join(LUA, "sh_props_bounds.lua"), "w", encoding="utf-8") as f:
        f.write("\n".join(bounds).replace("'", '"') + "\n")
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    render_preview(items).save(os.path.join(ROOT, "dist", "props_preview.png"))
    print("  превью: dist/props_preview.png")


if __name__ == "__main__":
    main()
