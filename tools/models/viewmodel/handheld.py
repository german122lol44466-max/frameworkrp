"""Предметы в правой руке (ключи, рация, зажигалка): хват, позы и последовательности вьюмоделей.

Предмет описан коробкой T × W × H (по X — толщина, «лицо» смотрит на камеру; Y — ширина; Z — высота)
с центром в начале своей системы. Хват (Grip) подобран оптимизацией по сетке рук c_arms:
  python3 handheld.py opt <kind> [seed]   — печатает параметры хвата для таблицы ITEMS ниже.
Последовательности: draw, idle, use, idle_use (цикл, если есть), unuse, holster.
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import anims  # noqa: E402
import vmlib  # noqa: E402
from anims import Grip, channel, rest_hand  # noqa: E402

# box — (T, W, H); center — центр коробки в координатах модели (build_props.py);
# grip — (K, Z, UP, R, L, c0, c1, c2, thumb) из оптимизатора; poses — {имя: (pos, tilt, roll)}
ITEMS = {
    "keys": {
        "model": "w_keys", "box": (0.35, 0.9, 1.4), "center": (0.0, 0.0, 1.3),
        "grip": (-0.209, -1.197, 0.500, 2.401, 1.651, 0.118, 1.115, 0.754, 0.213),
        "poses": {"low": ((9.0, -8.5, -21.0), 0.5, 25), "idle": ((13.0, -4.2, -4.0), 0.25, 10),
                  "use": ((19.0, -2.4, -2.6), 0.1, 80)},
    },
    "radio": {
        "model": "w_radio", "box": (1.5, 2.6, 5.4), "center": (0.0, 0.0, 2.7),
        "grip": (-0.896, 1.111, 0.338, 2.888, 1.456, -0.436, 0.762, -0.367, 0.154),
        "poses": {"low": ((9.0, -8.5, -21.0), 0.5, 25), "idle": ((13.0, -4.6, -4.4), 0.3, 6),
                  "use": ((10.0, -5.0, -3.2), 0.05, -20)},
    },
    "lighter": {
        "model": "w_lighter", "box": (0.55, 1.3, 2.2), "center": (0.0, 0.0, 1.35),
        "grip": (1.488, 1.011, 0.605, 4.508, 1.660, -0.145, 1.255, 0.096, 0.286),
        "poses": {"low": ((9.0, -8.5, -21.0), 0.5, 25), "idle": ((12.5, -4.0, -4.2), 0.3, 6),
                  "use": ((8.4, -0.9, -3.2), 0.0, 0)},
    },
    # службы (модели — build_city.py, папка city)
    "extinguisher": {
        "model": "../city/extinguisher", "box": (1.4, 1.4, 2.6), "center": (0.0, 0.0, 18.6),   # хват за вентиль, баллон висит ниже
        "grip": (0.114, 0.795, 0.242, 3.360, 1.368, -0.400, 0.944, 1.607, 0.101),
        "poses": {"low": ((9.0, -10.0, -28.0), 0.5, 25), "idle": ((16.0, -7.5, -4.0), 0.1, 4),
                  "use": ((19.0, -4.0, -1.0), 0.0, 0)},
    },
    "handcuffs": {
        "model": "../city/handcuffs", "box": (0.5, 7.6, 3.4), "center": (0.0, 0.0, 0.0),
        "grip": (2.534, -2.701, 1.176, 4.591, 1.282, -0.473, -0.487, -0.033, -1.046),
        "poses": {"low": ((9.0, -8.5, -21.0), 0.5, 25), "idle": ((13.0, -4.4, -4.0), 0.25, 10),
                  "use": ((20.0, -2.0, -3.0), 0.1, 0)},
    },
    "defib": {
        "model": "../city/defib", "box": (2.0, 6.0, 1.2), "center": (0.0, 0.0, 10.6),            # за ручку сверху
        "grip": (2.587, 1.071, 0.097, 6.378, 1.575, -0.426, -0.330, -0.418, -0.500),
        "poses": {"low": ((9.0, -10.0, -26.0), 0.5, 25), "idle": ((15.0, -6.5, -3.5), 0.1, 4),
                  "use": ((19.0, -1.5, -1.5), 0.0, 0)},
    },
}


def _matrix(kind, pose):
    pos, tilt, roll = ITEMS[kind]["poses"][pose] if isinstance(pose, str) else pose
    return anims._phone_matrix(np.array(pos, float), tilt, roll)


def parts_at(kind, f, keys):
    P = ITEMS[kind]["poses"]
    pos = channel({k: tuple(P[v][0]) for k, v in keys.items()}, f)
    tilt = channel({k: P[v][1] for k, v in keys.items()}, f)
    roll = channel({k: P[v][2] for k, v in keys.items()}, f)
    return {"item": anims._phone_matrix(np.array(pos, float), tilt, roll)}


def grip_of(kind, parts, x=None, thumb_add=0.0):
    T, W, H = ITEMS[kind]["box"]
    m = parts["item"]
    sgn = 1.0 if (m[:3, 1] @ np.array((0, 1, 0))) > 0 else -1.0
    K, Z, UP, R, L, c0, c1, c2, th = ITEMS[kind]["grip"] if x is None else x
    g = Grip("item", (-T / 2, sgn * K, Z), (1, 0, 0), (0.0, sgn, UP), reach=R, lift=L,
             curl=np.array((c0, c1, c2)), thumb=th + thumb_add)
    return {"R": g.world(parts), "L": rest_hand("L")}


def seqs(kind):
    """[(имя, функция(f) -> (parts, hands, extra), кадров, цикл, обратно)]"""
    def draw(f):
        p = parts_at(kind, f, {0: "low", 18: "idle"})
        return p, grip_of(kind, p), {}

    def idle(f):
        p = parts_at(kind, 0, {0: "idle"})
        m = p["item"].copy()
        m[:3, 3] += np.array((0, 0.08 * math.sin(f / 60 * 2 * math.pi), 0.12 * math.sin(f / 60 * 2 * math.pi + 1)))
        p = {"item": m}
        return p, grip_of(kind, p), {}

    def holster(f):
        p = parts_at(kind, f, {0: "idle", 16: "low"})
        return p, grip_of(kind, p), {}

    if kind == "keys":
        # вставить в замок и повернуть: вперёд, поворот кисти, обратно
        def use(f):
            p = parts_at(kind, f, {0: "idle", 10: "use", 26: "use", 36: "idle"})
            m = p["item"].copy()
            turn = channel({0: 0.0, 12: 0.0, 18: 1.0, 24: 1.0, 30: 0.0}, f)
            R = anims.ang_mat(0, 0, 0)
            c, s = math.cos(turn * 1.2), math.sin(turn * 1.2)
            axis = vmlib.norm(m[:3, 0])
            K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
            R = np.eye(3) + s * K + (1 - c) * K @ K
            m[:3, :3] = R @ m[:3, :3]
            p = {"item": m}
            return p, grip_of(kind, p), {}
        return [("draw", draw, 18, False, False), ("idle", idle, 60, True, False), ("use", use, 36, False, False),
                ("holster", holster, 16, False, False)]

    if kind == "radio":
        def up(f):
            p = parts_at(kind, f, {0: "idle", 12: "use"})
            return p, grip_of(kind, p), {}

        def talk(f):
            p = parts_at(kind, 12, {0: "idle", 12: "use"})
            m = p["item"].copy()
            m[:3, 3] += np.array((0, 0.05 * math.sin(f / 40 * 2 * math.pi), 0.06 * math.sin(f / 40 * 2 * math.pi + 2)))
            p = {"item": m}
            # большой палец жмёт тангенту
            return p, grip_of(kind, p, thumb_add=0.25), {}
        return [("draw", draw, 18, False, False), ("idle", idle, 60, True, False), ("use", up, 12, False, False),
                ("idle_use", talk, 40, True, False), ("unuse", up, 12, False, True), ("holster", holster, 16, False, False)]

    if kind == "lighter":
        # поднести к сигарете, чиркнуть большим пальцем (два раза), опустить
        def use(f):
            p = parts_at(kind, f, {0: "idle", 12: "use", 40: "use", 52: "idle"})
            flick = channel({0: 0.0, 14: 0.0, 18: 0.9, 22: 0.0, 26: 0.0, 30: 0.9, 34: 0.0}, f)
            return p, grip_of(kind, p, thumb_add=flick), {}
        return [("draw", draw, 18, False, False), ("idle", idle, 60, True, False), ("use", use, 52, False, False),
                ("holster", holster, 16, False, False)]
    # общий вариант (огнетушитель, наручники, дефибриллятор): действие — вперёд и обратно
    def use(f):
        p = parts_at(kind, f, {0: "idle", 10: "use", 26: "use", 36: "idle"})
        return p, grip_of(kind, p), {}
    return [("draw", draw, 18, False, False), ("idle", idle, 60, True, False), ("use", use, 36, False, False),
            ("holster", holster, 16, False, False)]


# ---------------------------------------------------------- оптимизация хвата
def optimize(kind, seed=0, iters=2500):
    from mdl_read import MDL
    arms = vmlib.Arms()
    am = MDL(os.path.join(vmlib.CARMS, "c_arms_animations.mdl"))
    base = arms.pose_from(am, [a["name"] for a in am.anims].index("a_fists_idle_01"), 0)
    rig = vmlib.Rig(arms, base)
    parts = parts_at(kind, 0, {0: "idle"})
    M = parts["item"]
    inv = np.linalg.inv(M)
    sgn = 1.0 if (M[:3, 1] @ np.array((0, 1, 0))) > 0 else -1.0
    T, W, H = ITEMS[kind]["box"]
    idx = lambda n: arms.index["ValveBiped.Bip01_R_" + n]  # noqa: E731
    hand_ids = {i for i, b in enumerate(arms.bones) if b["name"].startswith("ValveBiped.Bip01_R_")
                and ("Hand" in b["name"] or "Finger" in b["name"] or "Wrist" in b["name"])}
    mask = np.array([arms.w_idx[i, 0] in hand_ids for i in range(len(arms.pos))])
    sw_idx, sw_val = arms.w_idx[mask], arms.w_val[mask]
    hp = np.c_[arms.pos[mask], np.ones(mask.sum())]
    tipb = [idx(n) for n in ("Finger12", "Finger22", "Finger32", "Finger42")]

    def skin(w):
        sk = np.stack([w[i] @ arms.pose_to_bone[i] for i in range(len(arms.bones))])
        out = np.zeros((len(hp), 3))
        for k in range(3):
            out += sw_val[:, k:k + 1] * np.einsum("nij,nj->ni", sk[sw_idx[:, k]], hp)[:, :3]
        return out

    def evaluate(x, verbose=False):
        c0, c1, c2 = x[5:8]
        cost = sum(max(0, v - 1.6) ** 2 + max(0, -0.4 - v) ** 2 for v in (c0, c1, c2)) * 10
        hands = grip_of(kind, parts, x)
        wrist, Rh, curl, thumb = hands["R"][:4]
        loc = rig.solve(list(base), "R", wrist, Rh, anims.POLES["R"])
        loc = rig.fingers(loc, "R", curl, thumb)
        loc = vmlib.fix_proc_bones(arms, loc)
        w = vmlib.fk(arms.bones, loc)
        v = (np.c_[skin(w), np.ones(len(hp))] @ inv.T)[:, :3]
        v[:, 1] *= sgn
        dx, dy, dz = T / 2 + 0.05 - np.abs(v[:, 0]), W / 2 + 0.05 - np.abs(v[:, 1]), H / 2 + 0.05 - np.abs(v[:, 2])
        inside = (dx > 0) & (dy > 0) & (dz > 0)
        cost += np.sum(np.minimum(np.minimum(dx, dy), dz)[inside] ** 2) * 30 + inside.sum() * 0.02
        front = (v[:, 0] > T / 2) & (np.abs(v[:, 1]) < W / 2 - 0.4) & (np.abs(v[:, 2]) < H / 2 - 0.3)
        cost += front.sum() * 0.02
        back = v[(np.abs(v[:, 1]) < W / 2) & (np.abs(v[:, 2]) < H / 2) & (v[:, 0] < 0)]
        gap = (-T / 2 - back[:, 0].max()) if len(back) else 3.0
        cost += max(0, gap - 0.05) ** 2 * 20
        for b in tipb:
            t = inv @ (w[b] @ np.array([0.75, 0, 0, 1]))
            t = np.array([t[0], t[1] * sgn, t[2]])
            cost += max(0, W / 2 - 0.1 - t[1]) ** 2 * 2 + max(0, t[1] - W / 2 - 0.6) ** 2 * 2
            cost += max(0, -T / 2 - 0.1 - t[0]) ** 2 * 2 + max(0, t[0] - T / 2 - 0.4) ** 2 * 2
            cost += max(0, abs(t[2]) - H / 2 - 0.8) ** 2
        th2 = inv @ (w[idx("Finger02")] @ np.array([0.7, 0, 0, 1]))
        th2 = np.array([th2[0], th2[1] * sgn, th2[2]])
        cost += max(0, T / 2 + 0.1 - th2[0]) ** 2 * 3 + (th2[1] + W / 2 - 0.1) ** 2 * 2
        if verbose:
            print("inside", int(inside.sum()), "front", int(front.sum()), "gap %.2f" % gap, "thumb", np.round(th2, 2))
        return cost

    x0 = np.array(ITEMS[kind]["grip"], float)
    rng = np.random.default_rng(seed)
    best, bc = x0, evaluate(x0)
    step = np.array([0.3, 0.4, 0.25, 0.5, 0.3, 0.3, 0.3, 0.3, 0.4])
    for it in range(iters):
        xx = best + rng.normal(0, 1, len(best)) * step * (0.3 if it > iters // 2 else 1)
        c = evaluate(xx)
        if c < bc:
            best, bc = xx, c
    print(kind, "cost %.3f" % bc, "(" + ", ".join("%.3f" % v for v in best) + ")")
    evaluate(best, True)
    return best


if __name__ == "__main__":
    if sys.argv[1] == "opt":
        optimize(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 0, int(sys.argv[4]) if len(sys.argv) > 4 else 2500)
