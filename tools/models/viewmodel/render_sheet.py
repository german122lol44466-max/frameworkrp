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
OUT = os.environ.get("NYRP_SHEET_OUT", "/tmp/claude-0/-home-user/2c6fa45e-d882-541c-b296-0d1db1f0d39c/scratchpad/sheet")
COLORS = {"bag_fabric": (0.08, 0.09, 0.1, 1), "bag_strap": (0.02, 0.02, 0.025, 1), "bag_metal": (0.6, 0.6, 0.62, 1),
          "bag_accent": (0.9, 0.6, 0.0, 1), "bag_inner": (0.25, 0.04, 0.04, 1)}


def load_part(name):
    m = MDL(os.path.join(BAGS, name + ".mdl"))
    verts, tris = m.load_mesh(os.path.join(BAGS, name))
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
    fn, _ = anims.ANIMS[which]
    arms = vmlib.Arms()
    am = MDL(os.path.join(vmlib.CARMS, "c_arms_animations.mdl"))
    base = arms.pose_from(am, [a["name"] for a in am.anims].index("a_fists_idle_01"), 0)
    rig = vmlib.Rig(arms, base)
    preview.setup_scene()
    tris0 = {k: v for k, v in arms.tris.items() if k in (0, 1)}
    arm_ob = preview.mesh_object("arms", arms.pos, tris0, {0: (0.25, 0.3, 0.4, 1), 1: (0.8, 0.6, 0.5, 1)})
    kind = "backpack" if "backpack" in which else "waistbag"
    partnames = {"waistbag": {"root": "waistbag_root", "lid": "waistbag_lid", "zipper": "waistbag_zipper"},
                 "backpack": {"root": "backpack_root", "flap": "backpack_flap"}}[kind]
    bag_obs = {}
    for part, mdl in partnames.items():
        pos, tris = load_part(mdl)
        mats = {i: COLORS.get(name, (0.5, 0.5, 0.5, 1)) for i, name in enumerate(tris)}
        ob = preview.mesh_object(part, pos, {i: t for i, t in enumerate(tris.values())}, mats)
        bag_obs[part] = (ob, pos)
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
