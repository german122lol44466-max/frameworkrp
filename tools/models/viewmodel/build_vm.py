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
PARTS = {"waistbag": ["root", "lid", "zipper"], "backpack": ["root", "flap"], "phone": ["phone"], "atm": ["card"]}


def local_of(parent_w, child_w):
    m = np.linalg.inv(parent_w) @ child_w
    return tuple(m[:3, 3]), vmlib.mat_to_quat(m[:3, :3])


def frame_locals(arms, rig, base, fn, f, kind):
    loc, parts, _ = anims.pose(rig, base, fn, f, kind)
    out = [(tuple(map(float, p)), tuple(map(float, q))) for p, q in loc]
    for part in PARTS[kind]:
        pw = np.eye(4) if part in ("root", "phone", "card") else parts["root"]
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


def build_phone():
    """v_phone.mdl: руки c_arms + кость телефона; draw/idle/open/idle_open/close/holster."""
    arms = vmlib.Arms()
    am = MDL(os.path.join(vmlib.CARMS, "c_arms_animations.mdl"))
    base = arms.pose_from(am, [a["name"] for a in am.anims].index("a_fists_idle_01"), 0)
    rig = vmlib.Rig(arms, base)
    seqs = []
    for name, fn, n, loop, rev in anims.PHONE_SEQS:
        frames = [frame_locals(arms, rig, base, fn, f, "phone")[0] for f in range(n + 1)]
        if rev:
            frames = frames[::-1]
        seqs.append({"name": name, "fps": anims.FPS, "loop": loop, "frames": frames})
    rest = seqs[1]["frames"][0]
    bones = [{"name": b["name"], "parent": b["parent"], "pos": rest[i][0], "quat": rest[i][1]} for i, b in enumerate(arms.bones)]
    pi = len(bones)
    bones.append({"name": "nyrp_phone", "parent": -1, "pos": rest[pi][0], "quat": rest[pi][1]})
    rest_w = mdlc_anim.world_matrices(bones, [(b["pos"], b["quat"]) for b in bones])
    data = np.load(os.path.join(SRC, "phone_vm.npz"))
    meshes = {}
    m = rest_w[pi]
    for key in data.files:
        _, mat = key.split("|")
        arr = data[key].astype(np.float64)
        p = arr[:, :3] @ m[:3, :3].T + m[:3, 3]
        nrm = arr[:, 3:6] @ m[:3, :3].T
        tl = meshes.setdefault(mat, [])
        for t in range(0, len(arr), 3):
            tl.append([(tuple(p[t + k]), tuple(nrm[t + k]), (float(arr[t + k, 6]), float(arr[t + k, 7])), pi) for k in range(3)])
    out = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "models", "nyrp", "phone")
    mdlc_anim.compile_animated(out, "v_phone", "nyrp/phone/v_phone.mdl", bones, meshes, seqs, "models/nyrp/phone", "plastic")
    m2 = MDL(os.path.join(out, "v_phone.mdl"))
    print("v_phone: bones", len(m2.bones), "seqs", [x["name"] for x in m2.seqs])
    # проверка декодированием
    worst = 0
    for si, sq in enumerate(seqs):
        for f in range(0, len(sq["frames"]), 3):
            a = vmlib.fk(m2.bones, m2.anim_frame(si, f))
            b = vmlib.fk(m2.bones, sq["frames"][f])
            for i in range(len(bones)):
                worst = max(worst, float(np.abs(a[i][:3, 3] - b[i][:3, 3]).max()))
    print("max err", worst)
    assert worst < 0.05


def build_atm():
    """v_atm.mdl: руки c_arms + кость карты; insert/reach/type/menu/take."""
    arms = vmlib.Arms()
    am = MDL(os.path.join(vmlib.CARMS, "c_arms_animations.mdl"))
    base = arms.pose_from(am, [a["name"] for a in am.anims].index("a_fists_idle_01"), 0)
    rig = vmlib.Rig(arms, base)
    seqs = []
    for name, fn, n, loop, rev in anims.ATM_SEQS:
        frames = [frame_locals(arms, rig, base, fn, f, "atm")[0] for f in range(n + 1)]
        if rev:
            frames = frames[::-1]
        seqs.append({"name": name, "fps": anims.FPS, "loop": loop, "frames": frames})
    rest = seqs[2]["frames"][0]
    bones = [{"name": b["name"], "parent": b["parent"], "pos": rest[i][0], "quat": rest[i][1]} for i, b in enumerate(arms.bones)]
    ci = len(bones)
    bones.append({"name": "nyrp_card", "parent": -1, "pos": rest[ci][0], "quat": rest[ci][1]})
    rest_w = mdlc_anim.world_matrices(bones, [(b["pos"], b["quat"]) for b in bones])
    data = np.load(os.path.join(SRC, "atm_vm.npz"))
    meshes = {}
    m = rest_w[ci]
    for key in data.files:
        _, mat = key.split("|")
        arr = data[key].astype(np.float64)
        p = arr[:, :3] @ m[:3, :3].T + m[:3, 3]
        nrm = arr[:, 3:6] @ m[:3, :3].T
        tl = meshes.setdefault(mat, [])
        for t in range(0, len(arr), 3):
            tl.append([(tuple(p[t + k]), tuple(nrm[t + k]), (float(arr[t + k, 6]), float(arr[t + k, 7])), ci) for k in range(3)])
    out = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "models", "nyrp", "atm")
    mdlc_anim.compile_animated(out, "v_atm", "nyrp/atm/v_atm.mdl", bones, meshes, seqs, "models/nyrp/atm", "plastic")
    m2 = MDL(os.path.join(out, "v_atm.mdl"))
    worst = 0
    for si, sq in enumerate(seqs):
        for f in range(0, len(sq["frames"]), 3):
            a = vmlib.fk(m2.bones, m2.anim_frame(si, f))
            b = vmlib.fk(m2.bones, sq["frames"][f])
            for i in range(len(bones)):
                worst = max(worst, float(np.abs(a[i][:3, 3] - b[i][:3, 3]).max()))
    print("v_atm: bones", len(m2.bones), "seqs", [x["name"] for x in m2.seqs], "max err", worst)
    assert worst < 0.05


def build_handheld(kind):
    """v_<kind>.mdl (ключи, рация, зажигалка): руки c_arms + кость предмета; последовательности из handheld.py."""
    import handheld
    arms = vmlib.Arms()
    am = MDL(os.path.join(vmlib.CARMS, "c_arms_animations.mdl"))
    base = arms.pose_from(am, [a["name"] for a in am.anims].index("a_fists_idle_01"), 0)
    rig = vmlib.Rig(arms, base)

    def frame(fn, f):
        loc, parts, _ = anims.pose(rig, base, fn, f, "phone")
        out = [(tuple(map(float, p)), tuple(map(float, q))) for p, q in loc]
        out.append(local_of(np.eye(4), parts["item"]))
        return out

    seqs = []
    for name, fn, n, loop, rev in handheld.seqs(kind):
        frames = [frame(fn, f) for f in range(n + 1)]
        if rev:
            frames = frames[::-1]
        seqs.append({"name": name, "fps": anims.FPS, "loop": loop, "frames": frames})
    rest = seqs[1]["frames"][0]
    bones = [{"name": b["name"], "parent": b["parent"], "pos": rest[i][0], "quat": rest[i][1]} for i, b in enumerate(arms.bones)]
    ii = len(bones)
    bones.append({"name": f"nyrp_{kind}", "parent": -1, "pos": rest[ii][0], "quat": rest[ii][1]})
    rest_w = mdlc_anim.world_matrices(bones, [(b["pos"], b["quat"]) for b in bones])
    data = np.load(os.path.join(SRC, f"{kind}_vm.npz"))
    center = np.array(handheld.ITEMS[kind]["center"])
    meshes = {}
    m = rest_w[ii]
    for key in data.files:
        _, mat = key.split("|")
        arr = data[key].astype(np.float64)
        p = (arr[:, :3] - center) @ m[:3, :3].T + m[:3, 3]
        nrm = arr[:, 3:6] @ m[:3, :3].T
        tl = meshes.setdefault(mat, [])
        for t in range(0, len(arr), 3):
            tl.append([(tuple(p[t + k]), tuple(nrm[t + k]), (float(arr[t + k, 6]), float(arr[t + k, 7])), ii) for k in range(3)])
    sub = "city" if handheld.ITEMS[kind]["model"].startswith("../city/") else "props"
    out = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "models", "nyrp", sub)
    mdlc_anim.compile_animated(out, f"v_{kind}", f"nyrp/{sub}/v_{kind}.mdl", bones, meshes, seqs, f"models/nyrp/{sub}", "plastic")
    m2 = MDL(os.path.join(out, f"v_{kind}.mdl"))
    worst = 0
    for si, sq in enumerate(seqs):
        for f in range(0, len(sq["frames"]), 3):
            a = vmlib.fk(m2.bones, m2.anim_frame(si, f))
            b = vmlib.fk(m2.bones, sq["frames"][f])
            for i in range(len(bones)):
                worst = max(worst, float(np.abs(a[i][:3, 3] - b[i][:3, 3]).max()))
    print(f"v_{kind}: bones", len(m2.bones), "seqs", [x["name"] for x in m2.seqs], "max err", round(worst, 4))
    assert worst < 0.05


if __name__ == "__main__":
    if sys.argv[1:2] == ["handheld"]:
        for k in sys.argv[2:] or ["keys", "radio", "lighter"]:
            build_handheld(k)
        sys.exit()
    if sys.argv[1:] == ["phone"]:
        build_phone()
        sys.exit()
    if sys.argv[1:] == ["atm"]:
        build_atm()
        sys.exit()
    for k in sys.argv[1:] or ["waistbag", "backpack"]:
        build(k)
