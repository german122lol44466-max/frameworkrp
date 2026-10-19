"""Скелет рук (c_arms_citizen.mdl) -> gamemode/modules/hands/cl_bones.lua и разбор сетки для превью.

    python3 tools/content/hands_data.py <папка с c_arms_citizen.mdl/.vvd/.dx90.vtx>

Из MDL берутся кости и их положение в позе привязки (poseToBone), из VVD — вершины с весами костей, из VTX —
треугольники. В Lua уходят только смещения костей относительно родителя (для пальцев и вспомогательных
костей) — сами руки в игре ставятся процедурно (cl_hands.lua). Модель берётся та, что у игрока (GetHands),
скелет у всех рук ValveBiped одинаковый.
"""
import os
import struct
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "gamemodes", "whitesilence", "gamemode", "modules", "hands", "cl_bones.lua")


def read_mdl(path):
    b = open(path, "rb").read()
    nb, bi = struct.unpack_from("<ii", b, 156)
    bones = []
    for i in range(nb):
        o = bi + i * 216
        ni, par = struct.unpack_from("<ii", b, o)
        name = b[o + ni:o + ni + 64].split(b"\0")[0].decode()
        p2b = np.array(struct.unpack_from("<12f", b, o + 96)).reshape(3, 4)
        M = np.eye(4)
        M[:3, :] = p2b
        bones.append({"name": name, "parent": par, "pose2bone": M, "bind": np.linalg.inv(M)})
    # части тела → модели → меши (смещения вершин мешей)
    nbp, bpi = struct.unpack_from("<ii", b, 232)
    meshes = []
    for p in range(nbp):
        o = bpi + p * 16
        _, nmod, _, modi = struct.unpack_from("<iiii", b, o)
        for m in range(nmod):
            mo = o + modi + m * 148
            nmesh, meshi, nvert, verti = struct.unpack_from("<iiii", b, mo + 72)
            for k in range(nmesh):
                me = mo + meshi + k * 116
                mat, _, mnv, mvo = struct.unpack_from("<iiii", b, me)
                meshes.append({"bodypart": p, "model": m, "mesh": k, "material": mat, "vstart": verti // 48 + mvo, "nverts": mnv})
    return bones, meshes


def read_vvd(path):
    v = open(path, "rb").read()
    nverts = struct.unpack_from("<8i", v, 16)[0]
    _, _, vstart, _ = struct.unpack_from("<iiii", v, 48)
    out = np.zeros((nverts, 13), np.float32)
    for k in range(nverts):
        o = vstart + k * 48
        out[k, 0:3] = struct.unpack_from("<3f", v, o)
        out[k, 3:6] = struct.unpack_from("<3B", v, o + 12)
        out[k, 6] = v[o + 15]
        out[k, 7:10] = struct.unpack_from("<3f", v, o + 16)
        out[k, 10:13] = struct.unpack_from("<3f", v, o + 28)
    return out


def read_vtx(path, meshes):
    """Треугольники LOD 0 (индексы вершин VVD)."""
    b = open(path, "rb").read()
    nbp, bpo = struct.unpack_from("<ii", b, 28)
    tris = []
    mi = 0
    for p in range(nbp):
        po = bpo + p * 8
        nmod, mo = struct.unpack_from("<ii", b, po)
        for m in range(nmod):
            mdo = po + mo + m * 8
            nlod, lo = struct.unpack_from("<ii", b, mdo)
            lod0 = mdo + lo
            nmesh, meo = struct.unpack_from("<ii", b, lod0)
            for k in range(nmesh):
                mso = lod0 + meo + k * 9
                nsg, sgo = struct.unpack_from("<ii", b, mso)
                base = meshes[mi]["vstart"] if mi < len(meshes) else 0
                mi += 1
                for g in range(nsg):
                    go = mso + sgo + g * 25
                    nv, vo, ni, io, _, _ = struct.unpack_from("<iiiiiiB", b, go)[:6]
                    vids = [struct.unpack_from("<h", b, go + vo + j * 9 + 4)[0] for j in range(nv)]
                    idx = [struct.unpack_from("<H", b, go + io + j * 2)[0] for j in range(ni)]
                    for j in range(0, ni - 2, 3):
                        tris.append((base + vids[idx[j]], base + vids[idx[j + 1]], base + vids[idx[j + 2]]))
    return np.array(tris, np.int32)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "."
    bones, _ = read_mdl(os.path.join(src, "c_arms_citizen.mdl"))
    lines = ["-- Сгенерировано tools/content/hands_data.py из c_arms_citizen.mdl: кость, родитель, матрица относительно родителя",
             "-- (строки 3×4: оси X Y Z и смещение). Скелет ValveBiped, одинаковый у рук всех моделей.",
             "WS.HandsData = {"]
    for b in bones:
        par = b["parent"]
        rel = b["bind"] if par < 0 else np.linalg.inv(bones[par]["bind"]) @ b["bind"]
        rows = ", ".join("{ %s }" % ", ".join("%.5f" % x for x in rel[r, :4]) for r in range(3))
        pname = bones[par]["name"] if par >= 0 else ""
        lines.append('\t{ name = "%s", parent = "%s", m = { %s } },' % (b["name"], pname, rows))
    lines.append("}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("костей: %d -> %s" % (len(bones), os.path.relpath(OUT, ROOT)))


if __name__ == "__main__":
    main()
