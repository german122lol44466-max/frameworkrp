"""Раскадровка анимации в PNG (для проверки): python3 render_sheet.py waistbag 0,8,14,20,26,32,38,44,48"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402,I001
import numpy as np  # noqa: E402

import anims  # noqa: E402
import preview  # noqa: E402
import vmlib  # noqa: E402
from mdl_read import MDL  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BAGS = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "models", "nyrp", "bags")
PHONE_DIR = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "models", "nyrp", "phone")
ATM_DIR = os.path.join(ROOT, "gamemodes", "newyorkrp", "content", "models", "nyrp", "atm")
OUT = os.environ.get("NYRP_SHEET_OUT", "/tmp/claude-0/-home-user/2c6fa45e-d882-541c-b296-0d1db1f0d39c/scratchpad/sheet")
COLORS = {"phone_frame": (0.12, 0.12, 0.13, 1), "phone_back": (0.03, 0.05, 0.1, 1), "phone_glass": (0.01, 0.01, 0.015, 1),
          "phone_screen": (0.3, 0.25, 0.6, 1), "phone_lens": (0.02, 0.02, 0.03, 1),
          "bag_fabric": (0.08, 0.09, 0.1, 1), "bag_strap": (0.02, 0.02, 0.025, 1), "bag_metal": (0.6, 0.6, 0.62, 1),
          "bag_accent": (0.9, 0.6, 0.0, 1), "bag_inner": (0.25, 0.04, 0.04, 1)}


def load_part(name):
    base = os.path.join(PHONE_DIR if name.startswith("w_phone") else ATM_DIR if name in ("w_bankcard", "atm") else BAGS, name)
    m = MDL(base + ".mdl")
    verts, tris = m.load_mesh(base)
    pos = np.array([v[0] for v in verts])
    out = {m.textures[k]: v for k, v in tris.items()}
    if name == "waistbag_root":
        # в руках пояс и пряжка не нужны: выкидываем всё, что за задней стенкой сумки
        L = 10.5
        out = {k: [t for t in v if pos[t].mean(0)[0] > -2.05 and abs(pos[t].mean(0)[1]) <= L / 2 + 0.25] for k, v in out.items()}
    return pos, out


def main():
    which = sys.argv[1]
    frames = [int(x) for x in sys.argv[2].split(",")]
    fn = anims.ANIMS[which][0] if which in anims.ANIMS else getattr(anims, which)
    arms = vmlib.Arms()
    am = MDL(os.path.join(vmlib.CARMS, "c_arms_animations.mdl"))
    base = arms.pose_from(am, [a["name"] for a in am.anims].index("a_fists_idle_01"), 0)
    rig = vmlib.Rig(arms, base)
    preview.setup_scene()
    if os.environ.get("NYRP_CAM"):  # отладочный ракурс: NYRP_CAM="x,y,z" NYRP_CAM_T="x,y,z"
        cam = bpy.context.scene.camera
        cam.location = [float(v) for v in os.environ["NYRP_CAM"].split(",")]
        tgt = bpy.data.objects.new("tgt", None)
        bpy.context.collection.objects.link(tgt)
        tgt.location = [float(v) for v in os.environ.get("NYRP_CAM_T", "11,-3,-1").split(",")]
        c = cam.constraints.new("TRACK_TO")
        c.target, c.track_axis, c.up_axis = tgt, "TRACK_NEGATIVE_Z", "UP_Y"
    tris0 = {k: v for k, v in arms.tris.items() if k in (0, 1)}
    arm_ob = preview.mesh_object("arms", arms.pos, tris0, {0: (0.25, 0.3, 0.4, 1), 1: (0.8, 0.6, 0.5, 1)})
    kind = "phone" if which.startswith("phone") else "atm" if which.startswith("atm") else ("backpack" if "backpack" in which else "waistbag")
    partnames = {"waistbag": {"root": "waistbag_root", "lid": "waistbag_lid", "zipper": "waistbag_zipper"},
                 "backpack": {"root": "backpack_root", "flap": "backpack_flap"},
                 "phone": {"phone": "w_phone"}, "atm": {"card": "w_bankcard"}}[kind]
    bag_obs = {}
    for part, mdl in partnames.items():
        pos, tris = load_part(mdl)
        mats = {i: COLORS.get(name, (0.5, 0.5, 0.5, 1)) for i, name in enumerate(tris)}
        ob = preview.mesh_object(part, pos, {i: t for i, t in enumerate(tris.values())}, mats)
        bag_obs[part] = (ob, pos)
    if kind == "atm":
        # сам банкомат в пространстве камеры ввода PIN
        pos, tris = load_part("atm")
        pc = np.array([anims.atm_to_cam(v, scaled=True) for v in pos])
        mats = {i: (0.3, 0.32, 0.36, 1) for i, _ in enumerate(tris)}
        for i, name in enumerate(tris):
            if "keypad" in name:
                mats[i] = (0.7, 0.7, 0.72, 1)
            elif "screen" in name:
                mats[i] = (0.05, 0.1, 0.3, 1)
            elif "slot" in name:
                mats[i] = (0.1, 0.5, 0.2, 1)
        preview.mesh_object("atm", pc, {i: t for i, t in enumerate(tris.values())}, mats)
    os.makedirs(OUT, exist_ok=True)
    shots = []
    for f in frames:
        loc, parts, _ = anims.pose(rig, base, fn, f, kind)
        preview.set_verts(arm_ob, arms.skin(vmlib.fk(arms.bones, loc)))
        for part, (ob, pos) in bag_obs.items():
            m = parts[part]
            preview.set_verts(ob, (np.c_[pos, np.ones(len(pos))] @ m.T)[:, :3])
        p = os.path.join(OUT, f"{which}_{f:03d}.png")
        preview.render(p)
        shots.append(p)
    from PIL import Image, ImageDraw
    ims = [Image.open(p) for p in shots]
    cols = 3
    w, h = ims[0].width // 2, ims[0].height // 2
    sheet = Image.new("RGB", (w * cols, h * ((len(ims) + cols - 1) // cols)))
    for i, (im, f) in enumerate(zip(ims, frames)):
        im = im.resize((w, h))
        ImageDraw.Draw(im).text((8, 6), f"{which} f{f}", fill=(255, 255, 0))
        sheet.paste(im, ((i % cols) * w, (i // cols) * h))
    sheet.save(os.path.join(OUT, f"{which}_sheet.png"))
    print("sheet", os.path.join(OUT, f"{which}_sheet.png"))


if __name__ == "__main__":
    main()
