"""Сборка вьюмоделей рук с сумкой: models/nyrp/bags/v_waistbag.mdl, v_backpack.mdl

Скелет = кости c_arms_citizen (руки игрока прицепляются к ним бонмерджем) + кости сумки.
Сетка = только сумка (жёстко на своих костях). Последовательности:
  open (0..N), close (N..0), idle_open (кадр N, цикл), idle_closed (кадр 0).

python3 build_vm.py [waistbag|backpack ...]
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import anims  # noqa: E402
import mdlc_anim  # noqa: E402
import vmlib  # noqa: E402
from mdl_read import MDL  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "models", "nyrp", "bags")
SRC = os.path.join(os.path.dirname(HERE), "src")
PARTS = {"waistbag": ["root", "lid", "zipper"], "backpack": ["root", "flap"]}


def local_of(parent_w, child_w):
    m = np.linalg.inv(parent_w) @ child_w
    return tuple(m[:3, 3]), vmlib.mat_to_quat(m[:3, :3])


def frame_locals(arms, rig, base, fn, f, kind):
    loc, parts, _ = anims.pose(rig, base, fn, f, kind)
    out = [(tuple(map(float, p)), tuple(map(float, q))) for p, q in loc]
    for part in PARTS[kind]:
        pw = np.eye(4) if part == "root" else parts["root"]
        out.append(local_of(pw, parts[part]))
    return out, parts


def build(kind):
    fn, n = anims.ANIMS[kind]
    arms = vmlib.Arms()
    am = MDL(os.path.join(vmlib.CARMS, "c_arms_animations.mdl"))
    base = arms.pose_from(am, [a["name"] for a in am.anims].index("a_fists_idle_01"), 0)
    rig = vmlib.Rig(arms, base)

    frames = [frame_locals(arms, rig, base, fn, f, kind)[0] for f in range(n + 1)]
    # поза покоя модели = последний кадр (сумка раскрыта перед камерой)
    rest = frames[n]
    bones = [{"name": b["name"], "parent": b["parent"], "pos": rest[i][0], "quat": rest[i][1]}
             for i, b in enumerate(arms.bones)]
    nb_arms = len(bones)
    bag_index = {}
    for part in PARTS[kind]:
        bag_index[part] = len(bones)
        bones.append({"name": f"nyrp_{kind}_{part}", "parent": -1 if part == "root" else nb_arms,
                      "pos": rest[len(bones)][0], "quat": rest[len(bones)][1]})
    rest_w = mdlc_anim.world_matrices(bones, [(b["pos"], b["quat"]) for b in bones])

    data = np.load(os.path.join(SRC, f"{kind}_vm.npz"))
    meshes = {}
    for key in data.files:
        part, mat = key.split("|")
        bi = bag_index[part]
        m = rest_w[bi]
        arr = data[key].astype(np.float64)
        p = arr[:, :3] @ m[:3, :3].T + m[:3, 3]
        nrm = arr[:, 3:6] @ m[:3, :3].T
        tl = meshes.setdefault(mat, [])
        for t in range(0, len(arr), 3):
            tl.append([(tuple(p[t + k]), tuple(nrm[t + k]), (float(arr[t + k, 6]), float(arr[t + k, 7])), bi)
                       for k in range(3)])

    seqs = [
        {"name": "open", "fps": anims.FPS, "loop": False, "frames": frames},
        {"name": "close", "fps": anims.FPS, "loop": False, "frames": frames[::-1]},
        {"name": "idle_open", "fps": anims.FPS, "loop": True, "frames": [frames[n], frames[n]]},
        {"name": "idle_closed", "fps": anims.FPS, "loop": True, "frames": [frames[0], frames[0]]},
    ]
    name = f"v_{kind}"
    mdlc_anim.compile_animated(OUT, name, f"nyrp/bags/{name}.mdl", bones, meshes, seqs, "models/nyrp/bags")
    validate(name, bones, frames)


def validate(name, bones, frames):
    """Декодируем скомпилированную модель и сравниваем мировые позиции костей с исходником."""
    m = MDL(os.path.join(OUT, name + ".mdl"))
    assert [b["name"] for b in m.bones] == [b["name"] for b in bones]
    worst = 0.0
    for f in range(0, len(frames), 4):
        dec = m.anim_frame(0, f)
        a = vmlib.fk(m.bones, dec)
        b = vmlib.fk(m.bones, frames[f])
        for i in range(len(bones)):
            worst = max(worst, float(np.abs(a[i][:3, 3] - b[i][:3, 3]).max()),
                        float(np.abs(a[i][:3, :3] - b[i][:3, :3]).max()) * 10)
    print(f"{name}: bones={len(bones)} seqs={[s['name'] for s in m.seqs]} max err={worst:.4f}")
    assert worst < 0.05, worst


if __name__ == "__main__":
    for k in sys.argv[1:] or ["waistbag", "backpack"]:
        build(k)
