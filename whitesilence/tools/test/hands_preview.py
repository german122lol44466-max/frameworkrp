"""Превью анимации рук без игры: поза считается кодом режима (cl_hands.lua через lupa), сетка — настоящая
модель рук (c_arms_citizen: VVD + VTX), скиннинг по матрицам костей, отрисовка с z-буфером из глаз игрока
с FOV оружия (54°). Кадры каждого вида анимации — в dist/hands_preview.png.

    python3 tools/test/hands_preview.py <папка с c_arms_citizen.*>
"""
import math
import os
import sys

import lupa
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "content"))
import hands_data as HD  # noqa: E402

GM = os.path.join(ROOT, "gamemodes", "whitesilence", "gamemode")

PRE = r'''
WS = { Lobby = {}, Camera = {} }
function CreateClientConVar() return { GetBool = function() return true end } end
net = { Receive = function() end }
hook = { Add = function() end }
function math.Clamp(v, a, b) return math.min(math.max(v, a), b) end
function RealTime() return 0 end
'''


def pose_frames(lua, kind, u, target=None):
    eye = lua.table(x=0, y=0, z=64)
    ctx = lua.table(eye=eye, F=lua.table(x=1, y=0, z=0), R=lua.table(x=0, y=-1, z=0), U=lua.table(x=0, y=0, z=1),
                    kind=kind, u=u, target=target, hold=False)
    P, out, S = lua.globals().WS.Hands.Pose(ctx)
    res = {}
    for name, f in P.items():
        M = np.eye(4)
        for c, k in enumerate(("X", "Y", "Z")):
            M[:3, c] = (f[k].x, f[k].y, f[k].z)
        M[:3, 3] = (f.T.x, f.T.y, f.T.z)
        res[name] = M
    return res, out


def render(V, tris, bones, mats, W=480, H=270, fov=54):
    names = [b["name"] for b in bones]
    skin = np.zeros((len(names), 4, 4))
    for i, b in enumerate(bones):
        M = mats.get(b["name"])
        if M is None:
            M = np.zeros((4, 4))
            M[:3, 3] = (-200, 0, 64)
            M[3, 3] = 1
        skin[i] = M @ b["pose2bone"]
    P = np.c_[V[:, 7:10], np.ones(len(V))]
    N = V[:, 10:13]
    out = np.zeros((len(V), 3))
    nrm = np.zeros((len(V), 3))
    for j in range(3):
        w = V[:, j][:, None]
        idx = V[:, 3 + j].astype(int)
        valid = (j < V[:, 6])[:, None]
        tp = np.einsum("nij,nj->ni", skin[idx], P)[:, :3]
        tn = np.einsum("nij,nj->ni", skin[idx][:, :3, :3], N)
        out += np.where(valid, w * tp, 0)
        nrm += np.where(valid, w * tn, 0)
    # камера: глаз (0,0,64), вперёд +x, вправо −y, вверх +z
    rel = out - np.array([0, 0, 64])
    z = rel[:, 0]
    # FOV в Source задан для 4:3 — на широком экране по горизонтали видно больше
    f = (H / 2) / (math.tan(math.radians(fov / 2)) * 0.75)
    sx = W / 2 + (-rel[:, 1]) * f / np.maximum(z, 0.1)
    sy = H / 2 - rel[:, 2] * f / np.maximum(z, 0.1)
    img = np.zeros((H, W, 3), np.float32)
    img[:] = (52, 58, 70)
    img[int(H * 0.62):] = (196, 204, 214)            # «снег» внизу для ориентира
    zb = np.full((H, W), np.inf)
    light = np.array([0.3, 0.5, 0.8])
    light /= np.linalg.norm(light)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9
    for t in tris:
        i, j, k = t
        if min(z[i], z[j], z[k]) < 1:
            continue
        x0, y0, x1, y1, x2, y2 = sx[i], sy[i], sx[j], sy[j], sx[k], sy[k]
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-9:
            continue
        bx0, bx1 = max(0, int(min(x0, x1, x2))), min(W - 1, int(max(x0, x1, x2)) + 1)
        by0, by1 = max(0, int(min(y0, y1, y2))), min(H - 1, int(max(y0, y1, y2)) + 1)
        if bx1 < bx0 or by1 < by0:
            continue
        yy, xx = np.mgrid[by0:by1 + 1, bx0:bx1 + 1] + 0.5
        a = ((y1 - y2) * (xx - x2) + (x2 - x1) * (yy - y2)) / den
        b = ((y2 - y0) * (xx - x2) + (x0 - x2) * (yy - y2)) / den
        c = 1 - a - b
        ins = (a >= 0) & (b >= 0) & (c >= 0)
        dz = a * z[i] + b * z[j] + c * z[k]
        sub = zb[by0:by1 + 1, bx0:bx1 + 1]
        upd = ins & (dz < sub)
        if not upd.any():
            continue
        n = nrm[i] * a[..., None] + nrm[j] * b[..., None] + nrm[k] * c[..., None]
        n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
        sh = 0.35 + 0.65 * np.abs(n @ light)
        col = np.array([150, 140, 120]) * sh[..., None]
        sub[upd] = dz[upd]
        img[by0:by1 + 1, bx0:bx1 + 1][upd] = col[upd]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "."
    bones, meshes = HD.read_mdl(os.path.join(src, "c_arms_citizen.mdl"))
    V = HD.read_vvd(os.path.join(src, "c_arms_citizen.vvd"))
    T = HD.read_vtx(os.path.join(src, "c_arms_citizen.dx90.vtx"), meshes)
    # рукава + перчатки (часть 1, модель 1 — как у winterizedarmor); без голых рук
    keep = np.zeros(len(V), bool)
    for m in meshes:
        if m["bodypart"] == 0 or (m["bodypart"] == 1 and m["model"] == 1):
            keep[m["vstart"]:m["vstart"] + m["nverts"]] = True
    T = T[keep[T].all(1)]
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRE)
    lua.execute(open(os.path.join(GM, "modules", "hands", "cl_bones.lua"), encoding="utf-8").read())
    lua.execute(open(os.path.join(GM, "modules", "hands", "cl_hands.lua"), encoding="utf-8").read())
    target = lua.table(x=60, y=-10, z=0)            # предмет на земле впереди-справа
    shots = [("pickup", 0.15), ("pickup", 0.4), ("pickup", 0.6), ("pickup", 0.85),
             ("interact", 0.2), ("interact", 0.5), ("use", 0.3), ("use", 0.6)]
    W, H = 480, 270
    sheet = Image.new("RGB", (W * 2, H * 4))
    d = ImageDraw.Draw(sheet)
    fnt = ImageFont.truetype(os.path.join(ROOT, "content", "resource", "fonts", "Exo2_600SemiBold.ttf"), 16)
    for i, (kind, u) in enumerate(shots):
        mats, out = pose_frames(lua, kind, u, target if kind == "pickup" else None)
        im = render(V, T, bones, mats, W, H)
        sheet.paste(im, ((i % 2) * W, (i // 2) * H))
        d.text(((i % 2) * W + 8, (i // 2) * H + 6), "%s  u=%.2f  оружие вниз %.0f%%" % (kind, u, out * 100), fill=(240, 240, 240), font=fnt)
    out = os.path.join(ROOT, "dist", "hands_preview.png")
    sheet.save(out)
    print("превью:", os.path.relpath(out, ROOT))


if __name__ == "__main__":
    main()
