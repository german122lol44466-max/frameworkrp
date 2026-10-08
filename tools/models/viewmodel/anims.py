"""Раскадровка анимаций рук с сумкой/рюкзаком (пространство вьюмодели: камера в 0, +X вперёд, +Y влево, +Z вверх).

Каждая анимация — набор каналов с ключами {кадр: значение}, между ключами — плавная интерполяция.
Руки ставятся IK в точки хвата на сумке, поэтому ладони «прилипают» к сумке, бегунку и крышке.
"""
import math

import numpy as np

import vmlib
from vmlib import fk

FPS = 30

# Геометрия сумок (как в build_bags.py)
WAIST = {"L": 10.5, "D": 3.8, "H": 5.4, "seam": 0.9}
WAIST["lid_pivot"] = (-WAIST["D"] / 2, 0.0, WAIST["seam"])
WAIST["zip_pivot"] = (WAIST["D"] / 2 + 0.08, WAIST["L"] / 2 - 2.0, WAIST["seam"] + 0.08)
BACK = {"W": 11.0, "D": 5.0, "H": 15.0}
BACK["flap_pivot"] = (-BACK["D"] / 2 + 0.15, 0.0, BACK["H"] / 2 + 0.4)


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def channel(keys, f):
    """Интерполяция ключей {кадр: число|tuple}."""
    ks = sorted(keys)
    if f <= ks[0]:
        return keys[ks[0]]
    if f >= ks[-1]:
        return keys[ks[-1]]
    for a, b in zip(ks, ks[1:]):
        if a <= f <= b:
            t = smooth((f - a) / (b - a))
            va, vb = keys[a], keys[b]
            if isinstance(va, (tuple, list)):
                return tuple(x + (y - x) * t for x, y in zip(va, vb))
            return va + (vb - va) * t


def ang_mat(p, y, r):
    p, y, r = (math.radians(v) for v in (p, y, r))
    cz, sz, cy, sy, cx, sx = math.cos(y), math.sin(y), math.cos(p), math.sin(p), math.cos(r), math.sin(r)
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    return Rz @ Ry @ Rx


def xform(pos, ang):
    m = np.eye(4)
    m[:3, :3] = ang_mat(*ang)
    m[:3, 3] = pos
    return m


class Grip:
    """Хват в локальных координатах части сумки: точка контакта, нормаль ладони, направление пальцев."""

    def __init__(self, part, point, palm, fingers, reach=2.6, lift=1.1, curl=0.55, thumb=None):
        self.part, self.point, self.palm, self.fingers = part, np.array(point, float), np.array(palm, float), np.array(fingers, float)
        self.reach, self.lift, self.curl, self.thumb = reach, lift, curl, thumb

    def world(self, parts):
        m = parts[self.part]
        R = m[:3, :3]
        p = (m @ np.append(self.point, 1))[:3]
        n = vmlib.norm(R @ self.palm)
        f = vmlib.norm(R @ self.fingers)
        wrist = p - f * self.reach - n * self.lift   # запястье — «до» точки контакта вдоль пальцев и от поверхности
        return wrist, vmlib.hand_basis(f, n), self.curl, self.thumb


def blend_hand(a, b, t):
    """Смешивание двух положений руки (wrist, R, curl, thumb)."""
    if t <= 0:
        return a
    if t >= 1:
        return b
    t = smooth(t)
    wrist = a[0] + (b[0] - a[0]) * t
    qa, qb = np.array(vmlib.mat_to_quat(a[1])), np.array(vmlib.mat_to_quat(b[1]))
    if np.dot(qa, qb) < 0:
        qb = -qb
    q = vmlib.norm(qa + (qb - qa) * t)
    curl = a[2] + (b[2] - a[2]) * t
    ta = a[3] if a[3] is not None else a[2]
    tb = b[3] if b[3] is not None else b[2]
    return wrist, vmlib.quat_to_mat(q), curl, ta + (tb - ta) * t


def rest_hand(side):
    s = 1 if side == "L" else -1
    return np.array([10.0, 9.0 * s, -26.0]), vmlib.hand_basis((0.6, 0, 1), (0, -s, 0)), 0.25, None


# ------------------------------------------------------------- поясная сумка
def waistbag(f):
    W = WAIST
    L = W["L"]
    root = xform(channel({0: (9, -9, -24), 12: (16.5, -1.2, -2.6), 16: (16.5, -0.8, -2.4), 44: (16.5, -0.6, -2.2), 48: (16.5, -0.6, -2.2)}, f),
                 channel({0: (10, 140, -25), 12: (37, 184, -4), 16: (35, 180, 0), 24: (35, 178, 2), 30: (35, 182, -2),
                          34: (35, 180, 0), 44: (33, 180, 0), 48: (33, 180, 0)}, f))
    zip_y = channel({0: W["zip_pivot"][1], 18: W["zip_pivot"][1], 32: -W["zip_pivot"][1], 48: -W["zip_pivot"][1]}, f)
    lid = channel({0: 0.0, 34: 0.0, 44: -72.0, 48: -72.0}, f)
    zp = W["zip_pivot"]
    parts = {
        "root": root,
        "zipper": root @ xform((zp[0], zip_y, zp[2]), (0, 0, 0)),
        "lid": root @ xform(W["lid_pivot"], (lid, 0, 0)),
    }
    # обхват за боковины: ладонь на торце, пальцы заходят за заднюю стенку, большой палец спереди
    grip_r = Grip("root", (0.6, L / 2, -0.7), (0, -1, 0), (-1, 0, 0), reach=1.6, lift=0.85, curl=0.78, thumb=0.45)
    grip_l = Grip("root", (0.6, -L / 2, -0.7), (0, 1, 0), (-1, 0, 0), reach=1.6, lift=0.85, curl=0.78, thumb=0.45)
    # язычок: кисть снизу-спереди, пальцы вверх, щипок большим и указательным
    pinch = Grip("zipper", (0.35, 0, -0.55), (-1, 0, 0.25), (0.1, 0.25, 1), reach=4.0, lift=0.8, curl=0.5, thumb=0.85)
    # край крышки: ладонью к сумке, пальцы загибаются через край
    edge = Grip("lid", (3.5, 0.6, 0.3), (-1, 0, -0.3), (0.2, 0, 1), reach=3.6, lift=0.9, curl=0.6)

    R = grip_r.world(parts)
    rest = rest_hand("L")
    if f < 8:
        Lh = rest
    elif f < 17:
        Lh = blend_hand(rest, pinch.world(parts), (f - 8) / 9)
    elif f < 32:
        Lh = pinch.world(parts)
    elif f < 35:
        Lh = blend_hand(pinch.world(parts), edge.world(parts), (f - 32) / 3)
    elif f < 39:
        Lh = edge.world(parts)               # поднимает крышку снизу
    elif f < 42:
        e = edge.world(parts)
        Lh = blend_hand(e, (e[0] + np.array([-1.5, 1.5, -4.0]), e[1], 0.25, None), (f - 39) / 3)  # отпускает вниз
    else:
        e = edge.world(parts)
        mid = (e[0] + np.array([-1.5, 1.5, -4.0]), e[1], 0.25, None)
        Lh = blend_hand(mid, grip_l.world(parts), (f - 42) / 5)
    return parts, {"R": R, "L": Lh}, {"zipper": zip_y, "lid": lid}


# ------------------------------------------------------------------ рюкзак
def backpack(f):
    B = BACK
    Wd = B["W"]
    root = xform(channel({0: (12, -16, -32), 14: (25, 0.5, -3.4), 18: (25, 0, -3.2), 48: (25, 0, -3.2)}, f),
                 channel({0: (0, 130, 30), 14: (9, 182, -3), 18: (8, 180, 0), 30: (8, 180, -2), 40: (8, 180, 0), 48: (8, 180, 0)}, f))
    flap = channel({0: 0.0, 22: 0.0, 30: -55.0, 37: -118.0, 48: -118.0}, f)
    parts = {"root": root, "flap": root @ xform(B["flap_pivot"], (flap, 0, 0))}
    grip_r = Grip("root", (1.0, Wd / 2, -2.5), (0, -1, 0), (-1, 0, 0), reach=1.6, lift=0.85, curl=0.78, thumb=0.45)
    grip_l = Grip("root", (1.0, -Wd / 2, -2.5), (0, 1, 0), (-1, 0, 0), reach=1.6, lift=0.85, curl=0.78, thumb=0.45)
    flap_edge = Grip("flap", (5.2, 0.8, -4.6), (-1, 0, -0.2), (0.15, 0, 1), reach=3.6, lift=0.9, curl=0.6)

    rest = rest_hand("L")
    Lh = rest if f < 6 else blend_hand(rest, grip_l.world(parts), (f - 6) / 10)
    Rg = grip_r.world(parts)
    if f < 17:
        Rh = Rg
    elif f < 22:
        Rh = blend_hand(Rg, flap_edge.world(parts), (f - 17) / 5)
    elif f < 29:
        Rh = flap_edge.world(parts)          # тянет клапан вверх
    else:
        Rh = blend_hand(flap_edge.world(parts), Rg, (f - 29) / 9)  # отпускает, клапан откидывается сам
    return parts, {"R": Rh, "L": Lh}, {"flap": flap}


# Объёмы частей как скруглённые боксы (локально к части): (part, центр, полуразмеры, радиус скругления).
VOLUMES = {
    "waistbag": [("root", (0, 0, -0.9), (1.9, 5.25, 1.8), 1.2), ("root", (2.3, 0, -1.9), (0.45, 3.25, 1.08), 0.35),
                 ("lid", (1.9, 0, 0.9), (1.9, 5.25, 0.9), 0.9)],
    "backpack": [("root", (0, 0, 0), (2.5, 5.5, 7.5), 1.9), ("root", (3.2, 0, -3.9), (0.95, 3.96, 2.7), 0.75),
                 ("flap", (2.5, 0, -0.35), (2.8, 5.7, 0.45), 0.42), ("flap", (5.13, 0, -2.8), (0.4, 4.4, 2.6), 0.35)],
}


CONTACT_DEPTH = -0.3   # ладонь/пальцы чуть вдавлены в мягкую ткань
CONTACT_RANGE = 2.5


def _min_sd(pts, parts, vols):
    """Наименьшее расстояние со знаком от точек кисти до поверхности сумки."""
    best = np.inf
    for part, c, h, r in vols:
        inv = np.linalg.inv(parts[part])
        lp = (np.c_[pts, np.ones(len(pts))] @ inv.T)[:, :3] - np.array(c)
        q = np.abs(lp) - (np.array(h) - r)
        sd = np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(q.max(1), 0) - r
        best = min(best, float(sd.min()))
    return best


def _inside_count(pts, parts, vols, tol=0.15):
    """Сколько точек глубже tol внутри скруглённых боксов (SDF)."""
    n = 0
    for part, c, h, r in vols:
        inv = np.linalg.inv(parts[part])
        lp = (np.c_[pts, np.ones(len(pts))] @ inv.T)[:, :3] - np.array(c)
        q = np.abs(lp) - (np.array(h) - r)
        sd = np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(q.max(1), 0) - r
        n += int((sd < -tol).sum())
    return n


ANIMS = {
    "waistbag": (waistbag, 48),
    "backpack": (backpack, 48),
}

POLES = {"R": (4, -22, -26), "L": (4, 22, -26)}


_hand_verts = {}


def hand_vertex_mask(arms, side):
    """Вершины кисти и пальцев (по весам костей) — их проверяем на пересечение с сумкой."""
    if side not in _hand_verts:
        ids = {i for i, b in enumerate(arms.bones)
               if b["name"].startswith(f"ValveBiped.Bip01_{side}_Finger") or b["name"] in (f"ValveBiped.Bip01_{side}_Hand",)}
        main = arms.w_idx[np.arange(len(arms.w_idx)), np.argmax(arms.w_val, 1)]
        _hand_verts[side] = np.array([i for i, m in enumerate(main) if m in ids])
    return _hand_verts[side]


def pose(rig, base, fn, f, which=None):
    parts, hands, extra = fn(f)
    vols = VOLUMES.get(which or fn.__name__, [])
    loc = list(base)
    arms = rig.arms
    for s in ("R", "L"):
        wrist, Rh, curl, thumb = hands[s]
        palm = -Rh[:, 1]                     # нормаль ладони (в сторону предмета)
        mask = hand_vertex_mask(arms, s)
        trial = None
        for it in range(10):
            trial = rig.solve(loc, s, wrist, Rh, POLES[s])
            trial = rig.fingers(trial, s, curl, thumb)
            if not vols:
                break
            pts = arms.skin(fk(arms.bones, trial))[mask]
            d = _min_sd(pts, parts, vols)
            if d > CONTACT_RANGE:          # рука далеко от сумки (опущена) — не трогаем
                break
            err = d - CONTACT_DEPTH        # >0 висит в воздухе, <0 слишком глубоко
            if abs(err) < 0.08:
                break
            # прижимаем/отодвигаем кисть по нормали ладони, чтобы она лежала на ткани
            wrist = wrist + palm * float(np.clip(err, -0.6, 0.6))
        loc = trial
    return loc, parts, extra
