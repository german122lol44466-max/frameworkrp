"""Раскадровка анимаций рук с сумкой/рюкзаком (пространство вьюмодели: камера в 0, +X вперёд, +Y влево, +Z вверх).

Каждая анимация — набор каналов с ключами {кадр: значение}, между ключами — плавная интерполяция.
Руки ставятся IK в точки хвата на сумке, поэтому ладони «прилипают» к сумке, бегунку и крышке.
"""
import math
import os

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
        wrist, Rh, curl, thumb = hands[s][:4]
        tip = hands[s][4] if len(hands[s]) > 4 else None   # точка, куда должен попасть кончик указательного
        palm = -Rh[:, 1]                     # нормаль ладони (в сторону предмета)
        mask = hand_vertex_mask(arms, s)
        trial = None
        for it in range(10):
            trial = rig.solve(loc, s, wrist, Rh, POLES[s])
            trial = rig.fingers(trial, s, curl, thumb)
            if tip is not None:
                # двигаем запястье, пока кончик пальца не окажется ровно в точке
                w_ = fk(arms.bones, trial)
                ft = w_[arms.index[f"ValveBiped.Bip01_{s}_Finger12"]] @ np.array([0.75, 0, 0, 1])
                err = np.asarray(tip, float) - ft[:3]
                if np.linalg.norm(err) < 0.03:
                    break
                wrist = wrist + err
                continue
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
    return vmlib.fix_proc_bones(arms, loc), parts, extra


# ------------------------------------------------------------------ телефон
# Телефон в правой руке: экран смотрит на камеру, ладонь под задней крышкой,
# пальцы обхватывают левый (от зрителя) край, большой палец — у правого края экрана.
PHONE = {"H": 7.9, "W": 3.7, "T": 0.42}
# корпус тонкий — подгонка «касания» проталкивала кисть сквозь него, поэтому для телефона без неё
VOLUMES["phone"] = []


def _basis(xdir, zhint):
    x = vmlib.norm(np.array(xdir, float))
    z = np.array(zhint, float)
    z = vmlib.norm(z - x * np.dot(z, x))
    y = np.cross(z, x)
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2] = x, y, z
    return m


def _phone_matrix(pos, tilt, roll=0.0):
    """Телефон в точке pos, экран на камеру; tilt — насколько «лежит» к взгляду, roll — крен."""
    p = np.array(pos, float)
    to_eye = vmlib.norm(-p)
    m = _basis(to_eye, (math.sin(math.radians(roll)) * 0.4, 0, 1) + np.array((tilt, 0, 0)))
    m[:3, 3] = p
    return m


PHONE_POSES = {
    "low": ((9.0, -8.5, -21.0), 0.5, 25),     # опущен, вне кадра
    "idle": ((12.5, -3.6, -2.6), 0.3, 4),     # в руке, внизу справа
    "open": ((10.8, -2.7, -1.0), 0.15, 0),    # поднесён ближе — смотрим в экран
}


def _phone_pose(name):
    pos, tilt, roll = PHONE_POSES[name]
    return np.array(pos, float), tilt, roll


def _phone_parts(f, keys):
    pos = channel({k: tuple(_phone_pose(v)[0]) for k, v in keys.items()}, f)
    tilt = channel({k: _phone_pose(v)[1] for k, v in keys.items()}, f)
    roll = channel({k: _phone_pose(v)[2] for k, v in keys.items()}, f)
    return {"phone": _phone_matrix(pos, tilt, roll)}


def _phone_hands(parts):
    m = parts["phone"]
    # «влево от зрителя» в осях телефона: какая из ±Y смотрит в мировой +Y
    sgn = 1.0 if (m[:3, 1] @ np.array((0, 1, 0))) > 0 else -1.0
    T = PHONE["T"]
    # Хват подобран оптимизацией по сетке c_arms (без пересечений с корпусом): ладонь лежит на спинке
    # (кость кисти у c_arms у тыльной стороны, ладонь толщиной ~1.2), пальцы выходят к левой кромке,
    # большой палец — вдоль правой.
    grip = Grip("phone", (-T / 2, sgn * 1.318, -0.397), (1, 0, 0), (0.0, sgn, 0.371), reach=5.184, lift=1.919,
                curl=np.array((-0.315, -0.021, 0.057)), thumb=-0.377)
    return {"R": grip.world(parts), "L": rest_hand("L")}


def phone_draw(f):
    parts = _phone_parts(f, {0: "low", 18: "idle"})
    return parts, _phone_hands(parts), {}


def phone_idle(f):
    parts = _phone_parts(0, {0: "idle"})
    # лёгкое «дыхание»
    m = parts["phone"].copy()
    m[:3, 3] += np.array((0, 0.08 * math.sin(f / 60 * 2 * math.pi), 0.12 * math.sin(f / 60 * 2 * math.pi + 1)))
    parts = {"phone": m}
    return parts, _phone_hands(parts), {}


def phone_open(f):
    parts = _phone_parts(f, {0: "idle", 12: "open"})
    return parts, _phone_hands(parts), {}


def phone_holster(f):
    parts = _phone_parts(f, {0: "idle", 16: "low"})
    return parts, _phone_hands(parts), {}


# последовательности вьюмодели телефона: (имя, функция, кадров, цикл, обратно)
PHONE_SEQS = [
    ("draw", phone_draw, 18, False, False),
    ("idle", phone_idle, 60, True, False),
    ("open", phone_open, 12, False, False),
    ("idle_open", lambda f: phone_open(12), 2, True, False),
    ("close", phone_open, 12, False, True),
    ("holster", phone_holster, 16, False, False),
]


# ------------------------------------------------------------------ банкомат
# Банкомат в игре в ATM_K раз больше «чертёжных» размеров build_atm.py (реальный рост ~1.6 м).
# Камера ввода PIN (modules/bank/sh_bank.lua, camPin) — как у человека, склонившегося к клавиатуре:
# в координатах банкомата (лицом в +X) точка ATM_CAM["pos"], взгляд в -X, наклон вниз ATM_CAM["pitch"].
ATM_K = 1.5
ATM_CAM = {"pos": np.array((31.4, 1.5, 60.8)), "pitch": 27.0}


def _cam_axes():
    pitch = math.radians(ATM_CAM["pitch"])
    f = np.array((-math.cos(pitch), 0, -math.sin(pitch)))
    up = np.array((-math.sin(pitch), 0, math.cos(pitch)))
    return f, up


def atm_to_cam(p, scaled=False):
    """Точка банкомата (чертёжные единицы, если scaled=False) -> пространство камеры (X вперёд, Y влево, Z вверх)."""
    p = np.array(p, float) * (1.0 if scaled else ATM_K)
    f, up = _cam_axes()
    d = p - ATM_CAM["pos"]
    return np.array((d @ f, -d[1], d @ up))


def atm_dir(v):
    f, up = _cam_axes()
    v = np.array(v, float)
    return np.array((v @ f, -v[1], v @ up))


# клавиатура: коробка 5.2 × 7.4 (чертёж), центр (12, -1.2, 31.6), повёрнута на 18° вокруг Y (передний край ниже)
KP = {"center": (12.0, -1.2, 31.6), "hx": 2.6, "hy": 3.7, "tilt": 18.0}


def _kp_rot(v):
    t = math.radians(KP["tilt"])
    x, y, z = v
    return np.array((x * math.cos(t) + z * math.sin(t), y, -x * math.sin(t) + z * math.cos(t)))


def keypad_point(fx, fy, h=0.15):
    """Точка на клавиатуре по долям текстуры (fx — слева направо, fy — сверху = дальний край) -> чертёж."""
    local = ((fy * 2 - 1) * KP["hx"], (fx * 2 - 1) * KP["hy"], h)
    return np.array(KP["center"]) + _kp_rot(local)


# раскладка клавиш на текстуре (как tex_keypad в build_atm.py)
def _key_layout():
    keys = []
    kw, gap, x0 = 0.19, 0.035, 0.06
    for i, k in enumerate(["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]):
        c, r = i % 3, i // 3
        keys.append((k, x0 + c * (kw + gap) + kw / 2, x0 + r * (kw + gap) + kw / 2))
    fx = (x0 + 3 * (kw + gap) + gap + 0.94) / 2
    for j, k in enumerate(["cancel", "clear", "enter"]):
        keys.append((k, fx, x0 + j * (kw * 1.33 + gap) + kw * 1.33 / 2))
    return keys


ATM_KEYS = _key_layout()                         # 15 клавиш: имя, fx, fy
KEY_N = atm_dir(_kp_rot((0, 0, 1)))              # нормаль клавиатуры (в камере)
SLOT = atm_to_cam((9.8, 7.6, 34.0))              # щель картоприёмника
INSERT = atm_dir((-1, 0, 0))                     # «внутрь»
CARD_N = atm_dir((0, 0, 1))
VOLUMES["atm"] = []

CARD_L = 4.5                                     # реальная карта 85.6 мм
CARD_LOW = np.array((12.0, -10.0, -20.0))        # карта в опущенной руке (вне кадра)
CARD_OUT = SLOT - INSERT * (CARD_L / 2 + 0.3)    # перед щелью
CARD_IN = SLOT + INSERT * (CARD_L / 2 - 1.1)     # вставлена (снаружи торчит край)


def _card_matrix(center):
    m = _basis(INSERT, CARD_N)
    m[:3, 3] = center
    return m


def _card_grip():
    # держим за боковой край у заднего конца: карта видна слева от руки
    return Grip("card", (-CARD_L / 2 + 0.35, -1.25, 0.0), (0, -1, 0), (1, 0, 0.1), reach=3.0, lift=0.4, curl=0.6, thumb=0.7)


def atm_insert(f):
    """0–12 рука с картой поднимается к щели, 12–22 вставляет, 22–34 отпускает и опускается."""
    c = channel({0: tuple(CARD_LOW), 12: tuple(CARD_OUT), 22: tuple(CARD_IN)}, f)
    parts = {"card": _card_matrix(np.array(c))}
    held = _card_grip().world(parts)
    away = blend_hand(held, rest_hand("R"), (f - 22) / 12)
    return parts, {"R": held if f <= 22 else away, "L": rest_hand("L")}, {}


def _key_cam(i, h):
    _, fx, fy = ATM_KEYS[i]
    return atm_to_cam(keypad_point(fx, fy, 0.15 + h))


NEUTRAL_H = 2.2


def _point_hand(tip):
    """Указательный вытянут и смотрит вперёд-вниз, остальные пальцы поджаты; кончик — точно в tip."""
    fdir = vmlib.norm(np.array((1.0, 0.25, -0.8)))
    Rh = vmlib.hand_basis(fdir, (0.0, 0.0, -1.0))
    wrist = np.asarray(tip) - Rh @ np.array((6.4, -2.5, -1.2))
    curl = np.array((0.0, 0.0, 0.85, 0.9, 0.95))
    return wrist, Rh, curl, 0.7, np.asarray(tip)


SEG = 14                                          # кадров на одно нажатие


def atm_keys(f):
    """15 отрезков по 14 кадров: из положения над центром клавиатуры к клавише i, нажать, вернуться."""
    parts = {"card": _card_matrix(CARD_IN)}
    i = min(int(f // SEG), len(ATM_KEYS) - 1)
    t = f - i * SEG
    neutral = atm_to_cam(keypad_point(0.4, 0.55, NEUTRAL_H))
    tip = channel({0: tuple(neutral), 5: tuple(_key_cam(i, 1.1)), 8: tuple(_key_cam(i, 0.0)), 10: tuple(_key_cam(i, 1.1)),
                   SEG: tuple(neutral)}, t)
    return parts, {"R": _point_hand(np.array(tip)), "L": rest_hand("L")}, {}


def atm_reach(f):
    """12 кадров: от опущенной руки к положению над клавиатурой."""
    parts, hands, extra = atm_keys(0)
    if f >= 12:
        return parts, hands, extra
    low = rest_hand("R")
    hands["R"] = blend_hand(low, hands["R"][:4], f / 12)
    return parts, hands, extra


def atm_menu(f):
    """Руки опущены, карта в банкомате."""
    return {"card": _card_matrix(CARD_IN)}, {"R": rest_hand("R"), "L": rest_hand("L")}, {}


# последовательности вьюмодели банкомата: (имя, функция, кадров, цикл, обратно)
ATM_SEQS = [
    ("insert", atm_insert, 34, False, False),
    ("reach", atm_reach, 12, False, False),
    ("keys", atm_keys, SEG * len(ATM_KEYS), False, False),
    ("menu", atm_menu, 2, True, False),
    ("take", atm_insert, 34, False, True),
]
