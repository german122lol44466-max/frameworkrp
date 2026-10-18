"""Инструменты для «рисованных» кадров интро: шум, градиенты, силуэты и живописный проход кистью.

Всё рисуется кодом (numpy + Pillow), поэтому картинки свои и пересобираются одной командой.
"""
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 2560, 1440


# ---------------------------------------------------------------- шум и маски

def value_noise(w, h, cell, seed):
    """Гладкий шум: случайная сетка, растянутая бикубикой. cell — размер ячейки в пикселях."""
    rng = np.random.default_rng(seed)
    gw, gh = max(2, int(w / cell) + 3), max(2, int(h / cell) + 3)
    grid = rng.random((gh, gw)).astype(np.float32)
    img = Image.fromarray((grid * 255).astype(np.uint8)).resize((int(gw * cell), int(gh * cell)), Image.BICUBIC)
    a = np.asarray(img, dtype=np.float32)[:h, :w] / 255.0
    return a


def fbm(w, h, cell, octaves, seed, gain=0.5):
    total, amp, norm = np.zeros((h, w), np.float32), 1.0, 0.0
    for o in range(octaves):
        total += value_noise(w, h, max(2, cell / (2 ** o)), seed + o * 101) * amp
        norm += amp
        amp *= gain
    return total / norm


def stretched_fbm(w, h, cell, octaves, seed, sx=4.0, sy=1.0):
    """Шум, вытянутый по горизонтали (облака, заструги)."""
    n = fbm(int(w / sx) + 2, int(h / sy) + 2, cell, octaves, seed)
    img = Image.fromarray((np.clip(n, 0, 1) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0


def ridge_line(w, base, amp, cell, octaves, seed, sharp=1.0):
    """Профиль хребта: y(x) в пикселях."""
    rng = np.random.default_rng(seed)
    x = np.arange(w, dtype=np.float32)
    y = np.zeros(w, np.float32)
    a, c = amp, cell
    for o in range(octaves):
        pts = rng.random(int(w / c) + 3)
        xi = x / c
        i0 = np.floor(xi).astype(int)
        t = xi - i0
        t = t * t * (3 - 2 * t)
        v = pts[i0] * (1 - t) + pts[i0 + 1] * t
        v = 1 - np.abs(v * 2 - 1) ** sharp if o < 2 else v
        y += (v - 0.5) * a
        a *= 0.5
        c /= 2.1
    return base - y


def vgrad(h, w, stops):
    """Вертикальный градиент: stops = [(t, (r,g,b)), ...]."""
    t = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    out = np.zeros((h, w, 3), np.float32)
    ts = [s[0] for s in stops]
    for c in range(3):
        col = np.interp(t[:, 0], ts, [s[1][c] for s in stops]).astype(np.float32)
        out[:, :, c] = col[:, None]
    return out


def mask_below(w, h, line):
    yy = np.arange(h, dtype=np.float32)[:, None]
    return np.clip((yy - line[None, :]) * 0.7 + 0.5, 0, 1)


def blend(dst, src, a):
    a = a[..., None] if a.ndim == 2 else a
    return dst * (1 - a) + src * a


def to_img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def gaussian(arr, r):
    if arr.ndim == 2:
        img = Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8))
        return np.asarray(img.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0
    return np.asarray(to_img(arr).filter(ImageFilter.GaussianBlur(r)), np.float32)


# ---------------------------------------------------------------- живописный проход

def painterly(rgb, alpha=None, seed=1, passes=((22, 0.9), (11, 1.6), (5, 2.6)), jitter=6.0, length=2.6):
    """Перерисовывает картинку мазками: цвет берётся из размытой основы, мазок идёт вдоль контура.

    rgb — float32 HxWx3 (0..255). alpha — маска 0..1 (мазки только там, где она есть).
    passes — (радиус кисти, плотность); мелкие кисти кладутся там, где больше деталей.
    """
    rnd = random.Random(seed)
    h, w, _ = rgb.shape
    canvas = to_img(gaussian(rgb, passes[0][0] * 0.6))
    draw = ImageDraw.Draw(canvas)
    lum = rgb.mean(axis=2)
    for r, density in passes:
        ref = gaussian(rgb, max(1, r * 0.35))
        gl = gaussian(lum / 255.0, max(1, r * 0.5))
        gy, gx = np.gradient(gl)
        mag = np.hypot(gx, gy)
        detail = gaussian(np.clip(mag * 60, 0, 1), r)
        n = int(w * h / (r * r) * density)
        xs = np.random.default_rng(seed + r).random(n) * w
        ys = np.random.default_rng(seed + r * 7).random(n) * h
        for i in range(n):
            x, y = int(xs[i]), int(ys[i])
            if alpha is not None and alpha[y, x] < 0.05:
                continue
            # мелкая кисть — только по деталям, крупная — везде
            if r < passes[0][0] and rnd.random() > 0.25 + detail[y, x] * 1.4:
                continue
            ang = math.atan2(gy[y, x], gx[y, x]) + math.pi / 2
            if mag[y, x] < 1e-4:
                ang = rnd.uniform(-0.25, 0.25)  # на ровном — почти горизонтальные мазки (снег, небо)
            ln = r * length * rnd.uniform(0.6, 1.3)
            dx, dy = math.cos(ang) * ln * 0.5, math.sin(ang) * ln * 0.5
            c = ref[y, x]
            j = rnd.uniform(-jitter, jitter)
            col = (int(c[0] + j), int(c[1] + j), int(c[2] + j * 1.2))
            draw.line((x - dx, y - dy, x + dx, y + dy), fill=col, width=max(1, int(r * rnd.uniform(0.55, 0.9))))
    out = np.asarray(canvas, np.float32)
    # лёгкая «фактура холста»
    tex = fbm(w, h, 3, 2, seed + 900) - 0.5
    out += tex[..., None] * 9
    return out


def canvas_grain(rgb, seed, amount=5.0):
    rng = np.random.default_rng(seed)
    return rgb + rng.normal(0, amount, rgb.shape[:2]).astype(np.float32)[..., None]


# ---------------------------------------------------------------- силуэты (рисуются с запасом x4 и сжимаются)

class Sil:
    """Чёрно-белая маска силуэтов в увеличенном масштабе. lean — наклон фигуры вперёд (сдвиг по высоте)."""

    def __init__(self, w, h, ss=3):
        self.ss = ss
        self.img = Image.new("L", (w * ss, h * ss), 0)
        self.d = ImageDraw.Draw(self.img)
        self.y0, self.k = 0.0, 0.0

    def lean(self, y0, k):
        self.y0, self.k = y0, k

    def _t(self, x, y):
        return ((x + self.k * (self.y0 - y)) * self.ss, y * self.ss)

    def P(self, pts, v=255):
        self.d.polygon([self._t(x, y) for x, y in pts], fill=v)

    def E(self, cx, cy, rx, ry, v=255):
        x, y = self._t(cx, cy)
        s = self.ss
        self.d.ellipse((x - rx * s, y - ry * s, x + rx * s, y + ry * s), fill=v)

    def L(self, pts, width, v=255):
        s = self.ss
        self.d.line([self._t(x, y) for x, y in pts], fill=v, width=max(1, int(width * s)), joint="curve")
        for x, y in (pts[0], pts[-1]):
            self.E(x, y, width / 2, width / 2, v)

    def mask(self, blur=0.0):
        m = self.img.resize((self.img.width // self.ss, self.img.height // self.ss), Image.LANCZOS)
        if blur:
            m = m.filter(ImageFilter.GaussianBlur(blur))
        return np.asarray(m, np.float32) / 255.0


def limb(s, a, b, wa, wb):
    """Конечность-трапеция от точки a к b с толщиной wa..wb."""
    ax, ay = a
    bx, by = b
    ang = math.atan2(by - ay, bx - ax) + math.pi / 2
    ca, sa = math.cos(ang), math.sin(ang)
    s.P([(ax + ca * wa / 2, ay + sa * wa / 2), (bx + ca * wb / 2, by + sa * wb / 2),
         (bx - ca * wb / 2, by - sa * wb / 2), (ax - ca * wa / 2, ay - sa * wa / 2)])
    s.E(ax, ay, wa / 2, wa / 2)
    s.E(bx, by, wb / 2, wb / 2)


def _head(s, hx, hy, u, f, hood=True):
    """Шлем поверх капюшона, очки на шлеме, балаклава."""
    if hood:
        s.E(hx - f * 1.0 * u, hy + 2.0 * u, 7.6 * u, 8.6 * u)       # капюшон/балаклава
    s.E(hx, hy - 2.6 * u, 7.8 * u, 6.4 * u)                          # купол шлема
    s.P([(hx - 8.4 * u, hy - 1.5 * u), (hx + 8.4 * u, hy - 1.5 * u), (hx + 8.0 * u, hy + 1.0 * u), (hx - 8.0 * u, hy + 1.0 * u)])
    s.E(hx + f * 6.0 * u, hy + 2.2 * u, 2.6 * u, 2.0 * u)             # очки/нос маски


def _rifle(s, a, b, u):
    """Автомат от приклада a до дульного среза b."""
    ax, ay = a
    bx, by = b
    s.L([a, (ax + (bx - ax) * 0.42, ay + (by - ay) * 0.42)], 4.4 * u)
    s.L([(ax + (bx - ax) * 0.4, ay + (by - ay) * 0.4), b], 2.3 * u)
    mx, my = ax + (bx - ax) * 0.38, ay + (by - ay) * 0.38
    dx, dy = (bx - ax), (by - ay)
    ln = math.hypot(dx, dy)
    nx, ny = -dy / ln, dx / ln
    s.L([(mx, my), (mx + nx * 7 * u + dx / ln * 1.5 * u, my + ny * 7 * u + dy / ln * 1.5 * u)], 3.0 * u)  # магазин


def soldier(s, x, y, h, face=1, pose="stand", rnd=None, tilt=0.0, lean=0.08, pack=True, antenna=False):
    """Солдат в зимней экипировке сбоку/в три четверти: шлем, парка, разгрузка, рюкзак, автомат.

    x, y — точка между ступнями; h — рост; face — 1 смотрит вправо, -1 влево; tilt — наклон головы (рад).
    Возвращает координаты «глаз» (очков) — для отблеска.
    """
    rnd = rnd or random.Random(0)
    f = face
    u = h / 100.0
    s.lean(y, lean * f)
    hip = (x, y - 48 * u)
    neck = (x + f * 1.0 * u, y - 82 * u)

    if pose == "walk":
        legs = [((x - f * 3 * u, y - 25 * u), (x - f * 12 * u, y)), ((x + f * 7 * u, y - 26 * u), (x + f * 11 * u, y))]
    else:
        legs = [((x - f * 4 * u, y - 25 * u), (x - f * 8 * u, y)), ((x + f * 4 * u, y - 25 * u), (x + f * 8 * u, y))]
    for knee, ft in legs:
        limb(s, (hip[0], hip[1] + 3 * u), knee, 12.5 * u, 9.5 * u)
        limb(s, knee, (ft[0], ft[1] - 4 * u), 9.5 * u, 8.0 * u)
        s.P([(ft[0] - f * 5 * u, ft[1] - 7.5 * u), (ft[0] + f * 6 * u, ft[1] - 5 * u), (ft[0] + f * 9 * u, ft[1] - 1.2 * u),
             (ft[0] + f * 8.5 * u, ft[1]), (ft[0] - f * 5.5 * u, ft[1])])

    # рюкзак — за спиной, скруглённый, чуть выше плеч
    if pack:
        bx, by = neck[0] - f * 11.5 * u, neck[1] + 15 * u
        s.E(bx, by - 9 * u, 7.5 * u, 5 * u)
        s.P([(bx - 7.5 * u, by - 9 * u), (bx + 7.5 * u, by - 9 * u), (bx + 8 * u, by + 13 * u), (bx - 8 * u, by + 13 * u)])
        s.E(bx, by + 13 * u, 8 * u, 3.5 * u)
        if antenna:
            s.L([(bx - f * 3 * u, by - 12 * u), (bx - f * 7 * u, by - 46 * u)], 0.7 * u)

    # парка: плечи шире, к поясу уже, подол чуть расклёшен; разгрузка спереди
    s.P([(neck[0] - f * 10 * u, neck[1] + 1 * u), (neck[0] + f * 9 * u, neck[1] + 1 * u),
         (neck[0] + f * 11.5 * u, neck[1] + 14 * u), (hip[0] + f * 10.5 * u, hip[1] - 2 * u),
         (hip[0] + f * 12 * u, hip[1] + 8 * u), (hip[0] - f * 12 * u, hip[1] + 9 * u),
         (hip[0] - f * 10 * u, hip[1] - 4 * u), (neck[0] - f * 11 * u, neck[1] + 12 * u)])
    s.E(neck[0], neck[1] + 4 * u, 10.5 * u, 6 * u)
    s.E(neck[0] + f * 8 * u, neck[1] + 24 * u, 5 * u, 9 * u)  # подсумки на груди

    hx = neck[0] + f * 1.5 * u + math.sin(tilt) * 10 * u
    hy = neck[1] - 8.5 * u + (1 - math.cos(tilt)) * 7 * u
    _head(s, hx, hy, u, f)
    # шарф, бьющийся на ветру (ветер слева направо)
    s.P([(neck[0] - f * 4 * u, neck[1] - 1 * u), (neck[0] - f * 3 * u, neck[1] + 3 * u),
         (neck[0] + 14 * u * rnd.uniform(0.8, 1.2), neck[1] + 6 * u + rnd.uniform(-2, 2) * u),
         (neck[0] + 9 * u, neck[1] + 1 * u)])

    # руки держат автомат стволом вниз-вперёд
    shoulder = (neck[0] + f * 1 * u, neck[1] + 5 * u)
    elbow_b = (neck[0] - f * 2 * u, neck[1] + 22 * u)
    grip = (x + f * 9 * u, y - 55 * u)
    elbow_f = (neck[0] + f * 11 * u, neck[1] + 19 * u)
    fore = (x + f * 19 * u, y - 62 * u)
    stock = (neck[0] + f * 3 * u, neck[1] + 12 * u)
    muzzle = (x + f * 31 * u, y - 60 * u + 2 * u)
    _rifle(s, stock, muzzle, u)
    limb(s, shoulder, elbow_b, 8 * u, 7 * u)
    limb(s, elbow_b, grip, 7 * u, 5.8 * u)
    limb(s, shoulder, elbow_f, 8 * u, 7 * u)
    limb(s, elbow_f, fore, 7 * u, 5.8 * u)
    s.E(fore[0], fore[1], 3.2 * u, 2.8 * u)
    s.E(grip[0], grip[1], 3.2 * u, 2.8 * u)
    s.lean(0, 0)
    ex, ey = hx + f * 6.0 * u, hy + 1.6 * u
    return (ex + lean * f * (y - ey), ey)


def soldier_back(s, x, y, h, rnd=None, tilt=0.0, arm_drop=False, lean=0.05):
    """Солдат спиной к зрителю (виден рюкзак), автомат на ремне."""
    rnd = rnd or random.Random(0)
    u = h / 100.0
    s.lean(y, lean)
    hip = (x, y - 48 * u)
    neck = (x, y - 82 * u)
    for side in (-1, 1):
        k = (x + side * 5 * u, y - 25 * u)
        ft = (x + side * 7 * u, y)
        limb(s, (hip[0] + side * 5 * u, hip[1] + 2 * u), k, 12 * u, 9.5 * u)
        limb(s, k, (ft[0], ft[1] - 4 * u), 9.5 * u, 8.5 * u)
        s.P([(ft[0] - 5 * u, ft[1] - 6 * u), (ft[0] + 5 * u, ft[1] - 6 * u), (ft[0] + 5.5 * u, ft[1]), (ft[0] - 5.5 * u, ft[1])])
    s.P([(neck[0] - 13 * u, neck[1] + 1 * u), (neck[0] + 13 * u, neck[1] + 1 * u), (hip[0] + 12 * u, hip[1] - 2 * u),
         (hip[0] + 13 * u, hip[1] + 8 * u), (hip[0] - 13 * u, hip[1] + 8 * u), (hip[0] - 12 * u, hip[1] - 2 * u)])
    s.E(neck[0], neck[1] + 4 * u, 13.5 * u, 6 * u)
    # рюкзак: виден целиком, скатка сверху
    s.E(neck[0], neck[1] + 2 * u, 9.5 * u, 4 * u)
    s.P([(neck[0] - 9.5 * u, neck[1] + 2 * u), (neck[0] + 9.5 * u, neck[1] + 2 * u), (neck[0] + 10 * u, neck[1] + 30 * u),
         (neck[0] - 10 * u, neck[1] + 30 * u)])
    s.L([(neck[0] - 11 * u, neck[1] - 1 * u), (neck[0] + 11 * u, neck[1] - 1 * u)], 5 * u)
    for side in (-1, 1):
        drop = arm_drop and side == 1
        sh = (neck[0] + side * 12 * u, neck[1] + 5 * u)
        el = (neck[0] + side * (15 if not drop else 14.5) * u, neck[1] + 22 * u)
        hand = (neck[0] + side * 14 * u, neck[1] + 40 * u) if drop else (neck[0] + side * 9 * u, neck[1] + 33 * u)
        limb(s, sh, el, 8 * u, 7 * u)
        limb(s, el, hand, 7 * u, 5.8 * u)
    _rifle(s, (neck[0] - 12 * u, neck[1] + 4 * u), (neck[0] - 26 * u, neck[1] + 46 * u), u)
    hx = neck[0] + math.sin(tilt) * 10 * u
    hy = neck[1] - 8.5 * u + (1 - math.cos(tilt)) * 7 * u
    s.E(hx, hy + 2 * u, 7.6 * u, 8.6 * u)
    s.E(hx, hy - 2.6 * u, 8 * u, 6.6 * u)
    s.P([(hx - 8.6 * u, hy - 1.5 * u), (hx + 8.6 * u, hy - 1.5 * u), (hx + 8.2 * u, hy + 1 * u), (hx - 8.2 * u, hy + 1 * u)])
    s.lean(0, 0)


def soldier_seated_front(s, x, ys, h, rnd=None, tilt=0.0):
    """Боец сидит лицом к зрителю, автомат стволом вниз между колен. ys — уровень сиденья, h — рост стоя."""
    rnd = rnd or random.Random(0)
    u = h / 100.0
    floor = ys + 46 * u
    # голени и ботинки (колени раздвинуты)
    for side in (-1, 1):
        knee = (x + side * 12 * u, ys + 6 * u)
        ft = (x + side * 14 * u, floor - 3 * u)
        limb(s, (x + side * 7 * u, ys - 2 * u), knee, 14 * u, 13 * u)   # бедро (в ракурсе)
        limb(s, knee, ft, 11 * u, 9 * u)
        s.P([(ft[0] - 7 * u, ft[1] - 4 * u), (ft[0] + 7 * u, ft[1] - 4 * u), (ft[0] + 8.5 * u, floor), (ft[0] - 8.5 * u, floor)])
    # торс: плечи, разгрузка
    s.P([(x - 17 * u, ys - 51 * u), (x + 17 * u, ys - 51 * u), (x + 15 * u, ys - 30 * u), (x + 13.5 * u, ys - 6 * u),
         (x - 13.5 * u, ys - 6 * u), (x - 15 * u, ys - 30 * u)])
    s.E(x - 15 * u, ys - 48 * u, 6.5 * u, 6 * u)   # объёмные плечи парки
    s.E(x + 15 * u, ys - 48 * u, 6.5 * u, 6 * u)
    s.E(x, ys - 52 * u, 13 * u, 5.5 * u)
    for px in (-8, 0, 8):                           # подсумки на разгрузке
        s.P([(x + (px - 3.2) * u, ys - 30 * u), (x + (px + 3.2) * u, ys - 30 * u), (x + (px + 3.5) * u, ys - 18 * u), (x + (px - 3.5) * u, ys - 18 * u)])
    # голова: балаклава, шлем, очки
    hx, hy = x + math.sin(tilt) * 9 * u, ys - 63 * u + (1 - math.cos(tilt)) * 6 * u
    s.E(hx, hy + 2.5 * u, 6.4 * u, 7.8 * u)
    s.E(hx, hy - 2.5 * u, 7.9 * u, 6.6 * u)
    s.P([(hx - 8.5 * u, hy - 1 * u), (hx + 8.5 * u, hy - 1 * u), (hx + 8.1 * u, hy + 1.5 * u), (hx - 8.1 * u, hy + 1.5 * u)])
    s.E(hx, hy - 6.5 * u, 6.5 * u, 2.2 * u)          # очки, поднятые на шлем
    # автомат вертикально: приклад у груди, ствол в пол
    s.L([(x + 1 * u, ys - 34 * u), (x + 1.5 * u, ys + 6 * u)], 4.6 * u)
    s.L([(x + 1.5 * u, ys + 6 * u), (x + 2 * u, floor - 1 * u)], 2.4 * u)
    s.L([(x + 1.5 * u, ys - 8 * u), (x + 8 * u, ys - 4 * u)], 3.2 * u)  # магазин
    # руки лежат на автомате
    for side in (-1, 1):
        sh = (x + side * 14 * u, ys - 47 * u)
        el = (x + side * 16 * u, ys - 24 * u)
        hand = (x + side * 3 * u, ys - 14 * u - (side + 1) * 4 * u)
        limb(s, sh, el, 9 * u, 8 * u)
        limb(s, el, hand, 8 * u, 6.5 * u)
        s.E(hand[0], hand[1], 3.6 * u, 3.2 * u)
    return (hx, hy + 1 * u)
