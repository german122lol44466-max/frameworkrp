"""Общие функции вьюмодели: FK скелета Source, скиннинг рук, рендер превью в Blender."""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from mdl_read import MDL  # noqa: E402

CARMS = os.environ.get("NYRP_CARMS", "/tmp/claude-0/-home-user/2c6fa45e-d882-541c-b296-0d1db1f0d39c/scratchpad/carms")


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def mat_to_quat(m):
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        return ((m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s)
    if m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        return (0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s)
    if m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        return ((m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s)
    s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
    return ((m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s)


def mat4(pos, quat):
    m = np.eye(4)
    m[:3, :3] = quat_to_mat(quat)
    m[:3, 3] = pos
    return m


def fk(bones, locals_):
    """Локальные (pos, quat) -> мировые 4x4 (в пространстве модели)."""
    world = [None] * len(bones)
    for i, b in enumerate(bones):
        m = mat4(*locals_[i])
        world[i] = m if b["parent"] < 0 else world[b["parent"]] @ m
    return world


class Arms:
    """Руки c_arms_citizen: скелет + сетка, скиннинг по мировым матрицам костей."""

    def __init__(self, name="c_arms_citizen"):
        self.mdl = MDL(os.path.join(CARMS, name + ".mdl"))
        self.bones = self.mdl.bones
        self.proc = load_proc_rules(os.path.join(CARMS, name + ".mdl"))
        self.index = {b["name"]: i for i, b in enumerate(self.bones)}
        verts, tris = self.mdl.load_mesh(os.path.join(CARMS, name))
        self.verts = verts
        self.tris = tris
        self.pos = np.array([v[0] for v in verts], np.float64)
        n = len(verts)
        self.w_idx = np.zeros((n, 3), np.int64)
        self.w_val = np.zeros((n, 3), np.float64)
        for i, v in enumerate(verts):
            for k, (b, w) in enumerate(v[3]):
                self.w_idx[i, k], self.w_val[i, k] = b, w
        self.pose_to_bone = []
        for b in self.bones:
            p = np.eye(4)
            p[:3, :] = np.array(b["poseToBone"]).reshape(3, 4)
            self.pose_to_bone.append(p)
        self.rest = [(b["pos"], b["quat"]) for b in self.bones]

    def skin(self, world):
        skin = np.stack([world[i] @ self.pose_to_bone[i] for i in range(len(self.bones))])
        hp = np.concatenate([self.pos, np.ones((len(self.pos), 1))], 1)
        out = np.zeros_like(self.pos)
        for k in range(3):
            m = skin[self.w_idx[:, k]]
            out += self.w_val[:, k:k + 1] * np.einsum("nij,nj->ni", m, hp)[:, :3]
        return out

    def pose_from(self, anim_mdl, anim_index, frame):
        """Поза из анимации другой модели (по именам костей), остальные — покой."""
        src = anim_mdl.anim_frame(anim_index, frame)
        names = [b["name"] for b in anim_mdl.bones]
        loc = list(self.rest)
        for i, n in enumerate(names):
            j = self.index.get(n)
            if j is not None:
                loc[j] = src[i]
        return loc


def load_proc_rules(path):
    """Правила quaternion-procedural костей (Ulna/Wrist) из .mdl: {bone: (control, [(inv_tol, trig, pos, quat)])}."""
    import struct
    d = open(path, "rb").read()
    nb, bi = struct.unpack_from("<ii", d, 156)
    rules = {}
    for i in range(nb):
        o = bi + i * 216
        ptype, pidx = struct.unpack_from("<ii", d, o + 164)
        if ptype != 2:
            continue
        q = o + pidx
        control, n, ti = struct.unpack_from("<iii", d, q)
        trig = []
        for k in range(n):
            t = struct.unpack_from("<f4f3f4f", d, q + ti + k * 48)
            trig.append((t[0], np.array(t[1:5]), t[5:8], np.array(t[8:12])))
        rules[i] = (control, trig)
    return rules


def fix_proc_bones(arms, loc):
    """Процедурные Ulna/Wrist считаем так же, как движок (STUDIO_PROC_QUATINTERP): по повороту кисти
    относительно предплечья. Иначе при бонмердже скрутка запястья застывает и кисть «ломается»."""
    out = list(loc)
    if os.environ.get("NYRP_NOPROC"):
        return out
    for bone, (control, trig) in arms.proc.items():
        src = np.array(loc[control][1], float)
        w = [max(0.0, 1 - 2 * math.acos(min(1.0, abs(float(np.dot(t[1], src))))) * t[0]) for t in trig]
        sc = sum(w)
        if sc <= 0.001:
            out[bone] = (tuple(trig[0][2]), tuple(trig[0][3]))
            continue
        quat = np.zeros(4)
        pos = np.zeros(3)
        for wi, t in zip(w, trig):
            if wi == 0:
                continue
            k = wi / sc
            tq = t[3] if np.dot(t[3], quat) >= 0 else -t[3]
            quat += k * tq
            pos += k * np.array(t[2])
        quat /= np.linalg.norm(quat)
        out[bone] = (tuple(pos), tuple(quat))
    return out


# ------------------------------------------------------------------ IK и позы

# доля скрутки кисти, отдаваемая предплечью (остальное делают процедурные Ulna/Wrist)
TWIST_TO_FOREARM = float(os.environ.get("NYRP_TWIST", "0.0"))


def norm(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def look_basis(x, z_hint):
    """Ортонормальный базис: X = x, Z ~ z_hint."""
    x = norm(np.asarray(x, float))
    y = norm(np.cross(z_hint, x))
    z = np.cross(x, y)
    return np.stack([x, y, z], 1)


def hand_basis(finger_dir, palm_normal):
    """Мировая ориентация кисти: пальцы вдоль finger_dir, ладонь «смотрит» в palm_normal.
    У c_arms пальцы — +X кисти, ладонь — в сторону -Y."""
    x = norm(np.asarray(finger_dir, float))
    y = -norm(np.asarray(palm_normal, float) - x * np.dot(palm_normal, x))
    z = np.cross(x, y)
    return np.stack([x, y, z], 1)


class Rig:
    """Поза рук: базовая (из анимации idle) + IK рук + сгибание пальцев."""

    def __init__(self, arms, base_locals):
        self.arms = arms
        self.base = list(base_locals)
        self.idx = arms.index
        b = arms.bones
        side = {}
        for s in ("L", "R"):
            u, f, h = (self.idx[f"ValveBiped.Bip01_{s}_{n}"] for n in ("UpperArm", "Forearm", "Hand"))
            side[s] = {"u": u, "f": f, "h": h,
                       "l1": np.linalg.norm(b[f]["pos"]), "l2": np.linalg.norm(b[h]["pos"])}
        self.side = side
        # знак сгиба локтя (ось Z плеча) берём из базовой позы
        w = fk(b, self.base)
        for s, d in side.items():
            xu = w[d["u"]][:3, 0]
            xf = w[d["f"]][:3, 0]
            zu = w[d["u"]][:3, 2]
            d["sign"] = 1.0 if np.dot(np.cross(xu, xf), zu) >= 0 else -1.0

    def solve(self, locals_, s, target, hand_rot, pole):
        """Двухзвенная IK: запястье в target, кисть с мировым поворотом hand_rot, локоть к pole."""
        d = self.side[s]
        b = self.arms.bones
        w = fk(b, locals_)
        parent = b[d["u"]]["parent"]
        pw = w[parent]
        S = (pw @ mat4(*locals_[d["u"]]))[:3, 3]
        T = np.asarray(target, float)
        l1, l2 = d["l1"], d["l2"]
        to = T - S
        dist = np.clip(np.linalg.norm(to), abs(l1 - l2) + 0.1, l1 + l2 - 0.05)
        dirn = norm(to)
        # плоскость сгиба через полюс
        pv = np.asarray(pole, float) - S
        bend = norm(pv - dirn * np.dot(pv, dirn))
        a = math.acos(np.clip((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1))
        E = S + dirn * math.cos(a) * l1 + bend * math.sin(a) * l1
        T = S + dirn * dist
        xu = norm(E - S)
        xf = norm(T - E)
        zplane = norm(np.cross(xu, xf)) * d["sign"]
        Ru = np.stack([xu, np.cross(zplane, xu), zplane], 1)
        Rf = np.stack([xf, np.cross(zplane, xf), zplane], 1)
        # Скрут кисти отдаём в основном предплечью (как у живой руки), изгиб запястья ограничиваем.
        hl = Rf.T @ hand_rot
        qx, qy, qz, qw = mat_to_quat(hl)
        twist = 2 * math.atan2(qx, qw)
        twist = (twist + math.pi) % (2 * math.pi) - math.pi
        c, s_ = math.cos(twist * TWIST_TO_FOREARM), math.sin(twist * TWIST_TO_FOREARM)
        Rf = Rf @ np.array([[1, 0, 0], [0, c, -s_], [0, s_, c]])
        hl = Rf.T @ hand_rot
        bend = math.degrees(math.acos(np.clip(hl[0, 0], -1, 1)))  # угол между осью кисти и предплечья
        if bend > 65:
            k = 65 / bend
            q0 = np.array([0, 0, 0, 1.0])
            q1 = np.array(mat_to_quat(hl))
            if q1[3] < 0:
                q1 = -q1
            ang = math.acos(np.clip(q1[3], -1, 1))
            if ang > 1e-6:
                axis = q1[:3] / math.sin(ang)
                qk = np.append(axis * math.sin(ang * k), math.cos(ang * k))
                hl = quat_to_mat(qk)
        hand_rot = Rf @ hl
        Wu = np.eye(4); Wu[:3, :3] = Ru; Wu[:3, 3] = S
        Wf = np.eye(4); Wf[:3, :3] = Rf; Wf[:3, 3] = E
        Wh = np.eye(4); Wh[:3, :3] = hand_rot; Wh[:3, 3] = T
        lu = np.linalg.inv(pw) @ Wu
        lf = np.linalg.inv(Wu) @ Wf
        lh = np.linalg.inv(Wf) @ Wh
        out = list(locals_)
        for i, m in ((d["u"], lu), (d["f"], lf), (d["h"], lh)):
            out[i] = (tuple(m[:3, 3]), mat_to_quat(m[:3, :3]))
        return out

    def fingers(self, locals_, s, curl, thumb=None, spread=0.0):
        """curl 0..1 — сгиб пальцев (0 — прямые, 1 — кулак), thumb — отдельно для большого."""
        out = list(locals_)
        b = self.arms.bones
        thumb = curl if thumb is None else thumb
        for f in range(5):
            for k, suffix in enumerate(("", "1", "2")):
                c = thumb if f == 0 else curl
                # curl: число; (c0, c1, c2) — по фалангам; 5 значений — по пальцам (0 — большой, не используется)
                if np.ndim(c) and len(c) == 5:
                    c = c[f] if f else thumb
                amount = float(c[k]) if np.ndim(c) else c
                i = self.idx.get(f"ValveBiped.Bip01_{s}_Finger{f}{suffix}")
                if i is None:
                    continue
                pos, q = b[i]["pos"], b[i]["quat"]
                R = quat_to_mat(q)
                ang = -amount * (0.9 if f else 0.55) * (1.0 if k else 0.8)
                if f == 0:
                    ang = amount * 0.5
                c, si = math.cos(ang), math.sin(ang)
                Rz = np.array([[c, -si, 0], [si, c, 0], [0, 0, 1]])
                if f == 4 and k == 0:
                    Rz = Rz @ np.array([[1, 0, 0], [0, math.cos(spread), -math.sin(spread)], [0, math.sin(spread), math.cos(spread)]])
                out[i] = (pos, mat_to_quat(R @ Rz))
        return out
