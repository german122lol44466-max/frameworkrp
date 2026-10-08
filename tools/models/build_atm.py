"""Банкомат и банковская карта New-York Roleplay (Blender / bpy) -> модели и текстуры.

Запуск:  python3 tools/models/build_atm.py
Делает:
  content/models/nyrp/atm/atm.mdl          напольный банкомат (лицом в +X)
  content/models/nyrp/atm/w_bankcard.mdl   карта (предмет)
  tools/models/src/atm_vm.npz              карта для вьюмодели рук (viewmodel/build_vm.py atm)
  content/materials/models/nyrp/atm/*      текстуры
  branding/atm_preview.png

Геометрия (ед. Source), лицевая сторона — плоскость x = 9:
  экран: x = 8.6, y ∈ [-7, 7], z ∈ [38, 52]
  клавиатура: полка под экраном, центр (12.0, -1.2, 31.6), наклон 18° (передний край ниже)
  картоприёмник: справа от клавиатуры (для стоящего перед банкоматом), центр (9, 7.6, 34)
  выдача наличных: (9, 0, 25)
  вывеска сверху: z ∈ [62, 72] (название банка рисуется в игре)
Эти же числа — в modules/bank/sh_bank.lua (ATM_GEOM) и viewmodel/anims.py (ATM).
"""
import math
import os
import sys

import bpy  # noqa: I001
import bmesh
import numpy as np
from mathutils import Vector
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import textures  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GM = os.path.join(ROOT, "gamemodes", "newyorkrp")
SRC = os.path.join(HERE, "src")
MATDIR = os.path.join(GM, "content", "materials", "models", "nyrp", "atm")
FONTS = os.path.join(GM, "content", "resource", "fonts")


def font(name, size):
    try:
        return ImageFont.truetype(os.path.join(FONTS, name), size)
    except OSError:
        return ImageFont.load_default()


# ---------------------------------------------------------------- текстуры --
def brushed(S, base, amp=0.035, seed=1, vertical=False):
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 1, (S, S))
    st = np.cumsum(n, axis=0 if vertical else 1)
    st = (st - st.mean(0 if vertical else 1, keepdims=True)) / (st.std() + 1e-6)
    v = 1 + amp * st + 0.015 * rng.normal(0, 1, (S, S))
    return np.clip(np.array(base)[None, None] / 255 * v[..., None], 0, 1)


def tex_body(S=512):
    """Графитовый порошковый металл с едва заметными стыками панелей."""
    img = brushed(S, (46, 49, 56), 0.02, 3, vertical=True)
    im = Image.fromarray((img * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for y in (int(S * 0.33), int(S * 0.66)):
        d.line([0, y, S, y], fill=(28, 30, 35), width=2)
        d.line([0, y + 2, S, y + 2], fill=(70, 74, 82), width=1)
    return np.array(im)


def tex_trim(S=256):
    return (brushed(S, (150, 154, 162), 0.05, 4) * 255).astype(np.uint8)


def tex_accent(S=128):
    """Жёлтая полоса «такси» (подсветка по краю)."""
    img = np.zeros((S, S, 3), np.uint8)
    img[:] = (247, 198, 0)
    img[:, ::16] = (200, 150, 0)
    return img


def tex_screen(S=256):
    yy, xx = np.mgrid[0:S, 0:S] / S
    v = 0.05 + 0.06 * (1 - yy)
    img = np.dstack([v * 0.6, v * 0.8, v * 1.6])
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def tex_keypad(S=512):
    """Клавиатура: 4 ряда × 3 цифры + столбец функциональных клавиш (красная/жёлтая/зелёная)."""
    im = Image.new("RGB", (S, S), (120, 124, 132))
    d = ImageDraw.Draw(im)
    f = font("Oswald_600SemiBold.ttf", int(S * 0.085))
    fs = font("Oswald_600SemiBold.ttf", int(S * 0.045))
    keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]
    kw, kh, gap = S * 0.19, S * 0.19, S * 0.035
    x0, y0 = S * 0.06, S * 0.06
    for i, k in enumerate(keys):
        c, r = i % 3, i // 3
        x, y = x0 + c * (kw + gap), y0 + r * (kh + gap)
        d.rounded_rectangle([x + 3, y + 4, x + kw + 3, y + kh + 4], radius=S // 40, fill=(70, 72, 78))
        d.rounded_rectangle([x, y, x + kw, y + kh], radius=S // 40, fill=(214, 216, 222), outline=(160, 162, 170), width=2)
        d.text((x + kw / 2, y + kh / 2), k, font=f, fill=(30, 32, 40), anchor="mm")
    fx = x0 + 3 * (kw + gap) + gap
    for j, (col, t) in enumerate((((210, 50, 45), "CANCEL"), ((240, 190, 20), "CLEAR"), ((40, 170, 80), "ENTER"))):
        y = y0 + j * (kh * 1.33 + gap)
        d.rounded_rectangle([fx + 3, y + 4, S - S * 0.06 + 3, y + kh * 1.33 + 4], radius=S // 40, fill=(70, 72, 78))
        d.rounded_rectangle([fx, y, S - S * 0.06, y + kh * 1.33], radius=S // 40, fill=col)
        d.text(((fx + S - S * 0.06) / 2, y + kh * 0.66), t, font=fs, fill=(255, 255, 255), anchor="mm")
    return np.array(im.filter(ImageFilter.GaussianBlur(0.4)))


def tex_slot(S=256):
    """Картоприёмник: чёрная рамка, щель, зелёная подсветка и значок карты."""
    im = Image.new("RGB", (S, S), (20, 21, 24))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([S * 0.08, S * 0.3, S * 0.92, S * 0.7], radius=S // 10, fill=(34, 36, 40), outline=(80, 84, 90), width=3)
    d.rectangle([S * 0.16, S * 0.47, S * 0.84, S * 0.53], fill=(2, 2, 3))
    d.rectangle([S * 0.16, S * 0.6, S * 0.84, S * 0.63], fill=(40, 230, 110))
    d.rounded_rectangle([S * 0.38, S * 0.1, S * 0.62, S * 0.24], radius=4, outline=(200, 200, 205), width=3)
    d.rectangle([S * 0.42, S * 0.13, S * 0.48, S * 0.18], fill=(214, 172, 70))
    return np.array(im)


def tex_cash(S=256):
    im = Image.new("RGB", (S, S), (24, 25, 28))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([S * 0.05, S * 0.32, S * 0.95, S * 0.68], radius=S // 12, fill=(36, 38, 42), outline=(90, 94, 100), width=3)
    d.rectangle([S * 0.1, S * 0.46, S * 0.9, S * 0.54], fill=(3, 3, 4))
    d.text((S * 0.5, S * 0.2), "CASH", font=font("Oswald_600SemiBold.ttf", int(S * 0.12)), fill=(170, 174, 180), anchor="mm")
    return np.array(im)


def tex_topper(S=256):
    """Вывеска: светящийся короб (название банка поверх рисует игра)."""
    yy = np.linspace(0, 1, S)[:, None, None]
    img = np.ones((S, S, 3)) * (0.92 - 0.08 * yy)
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def tex_card(S=512):
    """Банковская карта: тёмно-синяя с золотым чипом, логотип NY, «полоса» как у VISA."""
    W_, H_ = S, int(S * 0.63)
    im = Image.new("RGB", (S, S), (14, 22, 48))
    d = ImageDraw.Draw(im)
    yy, xx = np.mgrid[0:S, 0:S] / S
    g = np.dstack([14 + 30 * xx, 22 + 26 * xx, 48 + 50 * (1 - yy)])
    im = Image.fromarray(np.clip(g, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([S * 0.1, S * 0.32, S * 0.26, S * 0.44], radius=6, fill=(214, 172, 70), outline=(150, 110, 30), width=2)
    for k in (0.36, 0.4):
        d.line([S * 0.1, S * k, S * 0.26, S * k], fill=(160, 120, 40), width=2)
    d.text((S * 0.1, S * 0.12), "NY BANK", font=font("Oswald_600SemiBold.ttf", int(S * 0.07)), fill=(247, 198, 0))
    d.text((S * 0.1, S * 0.55), "4000 1234 5678 9010", font=font("Oswald_600SemiBold.ttf", int(S * 0.06)), fill=(230, 232, 240))
    d.text((S * 0.9, S * 0.8), "VISA", font=font("Oswald_600SemiBold.ttf", int(S * 0.1)), fill=(255, 255, 255), anchor="rm")
    del W_, H_
    return np.array(im)


MATS = {
    # имя: (функция, фонг, selfillum)
    "atm_body": (tex_body, True, False),
    "atm_trim": (tex_trim, True, False),
    "atm_accent": (tex_accent, False, True),
    "atm_screen": (tex_screen, True, True),
    "atm_keypad": (tex_keypad, True, False),
    "atm_slot": (tex_slot, True, False),
    "atm_cash": (tex_cash, True, False),
    "atm_topper": (tex_topper, False, True),
    "atm_card": (tex_card, True, False),
}


def build_textures():
    os.makedirs(MATDIR, exist_ok=True)
    for name, (fn, phong, selfillum) in MATS.items():
        img = fn()
        textures.write_vtf(os.path.join(MATDIR, name + ".vtf"), img[..., :3])
        with open(os.path.join(MATDIR, name + ".vmt"), "w") as f:
            extra = ""
            if phong:
                extra += '\t"$phong" "1"\n\t"$phongexponent" "24"\n\t"$phongboost" "2"\n\t"$phongfresnelranges" "[0.3 0.6 1]"\n'
            if selfillum:
                extra += '\t"$selfillum" "1"\n'
            f.write(f'"VertexLitGeneric"\n{{\n\t"$basetexture" "models/nyrp/atm/{name}"\n{extra}}}\n')
    print("textures ok")


def blender_material(name):
    arr = MATS[name][0]().astype(np.float32) / 255.0
    rgba = np.concatenate([arr[::-1, :, :3], np.ones((*arr.shape[:2], 1), np.float32)], axis=2)
    img = bpy.data.images.new(name + "_tex", arr.shape[1], arr.shape[0])
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.4
    bsdf.inputs["Metallic"].default_value = 0.7 if name in ("atm_body", "atm_trim") else 0.0
    if MATS[name][2]:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 0.8
    return m


# --------------------------------------------------------------- геометрия --
FACES = {  # нормаль: (вершины по углам куба, оси UV)
    "+x": ((1, 0, 0), (2, 1)), "-x": ((-1, 0, 0), (2, 1)),
    "+y": ((0, 1, 0), (2, 0)), "-y": ((0, -1, 0), (2, 0)),
    "+z": ((0, 0, 1), (0, 1)), "-z": ((0, 0, -1), (0, 1)),
}


def box(name, size, center=(0, 0, 0), mats="atm_body", fit=(), tile=24.0, rot=(0, 0, 0)):
    """Коробка size=(dx, dy, dz). mats — материал или {грань: материал}; грани из fit — текстура целиком,
    остальные — с повтором через tile единиц."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    names = []
    for key, (n, (ua, va)) in FACES.items():
        axis = [abs(c) for c in n].index(1)
        sgn = n[axis]
        others = [i for i in range(3) if i != axis]
        corners = []
        for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            p = [0.0, 0.0, 0.0]
            p[axis] = sgn * (hx, hy, hz)[axis]
            p[others[0]] = a * (hx, hy, hz)[others[0]]
            p[others[1]] = b * (hx, hy, hz)[others[1]]
            corners.append(p)
        vs = [bm.verts.new(c) for c in corners]
        f = bm.faces.new(vs)
        # правильная ориентация наружу
        f.normal_update()
        if f.normal.dot(Vector(n)) < 0:
            f.normal_flip()
        mat = mats.get(key, mats.get("*", "atm_body")) if isinstance(mats, dict) else mats
        if mat not in names:
            names.append(mat)
        f.material_index = names.index(mat)
        half = (hx, hy, hz)
        for loop in f.loops:
            co = loop.vert.co
            if key in fit:
                # «лицом» к наблюдателю: u слева направо, v снизу вверх
                u_axis = {"+x": 1, "-x": 1, "+y": 0, "-y": 0, "+z": 1, "-z": 1}[key]
                v_axis = {"+x": 2, "-x": 2, "+y": 2, "-y": 2, "+z": 0, "-z": 0}[key]
                u = (co[u_axis] / half[u_axis] + 1) / 2
                if key in ("+x", "-y", "-z"):
                    u = 1 - u if key != "+x" else u
                v = (co[v_axis] / half[v_axis] + 1) / 2
                if key == "+z":
                    v = 1 - v
                loop[uvl].uv = (u, v)
            else:
                loop[uvl].uv = ((co[ua] + center[ua]) / tile, (co[va] + center[va]) / tile)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in names:
        me.materials.append(bpy.data.materials[m])
    ob = bpy.data.objects.new(name, me)
    ob.location = center
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    bpy.context.collection.objects.link(ob)
    return ob


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for m in MATS:
        blender_material(m)
    obs = []
    # основание и корпус
    obs.append(box("plinth", (20, 26, 5), (0, 0, 2.5), {"*": "atm_trim"}))
    obs.append(box("body", (18, 24, 57), (0, 0, 33.5)))
    # боковые «щёки», выступающие вперёд, и козырёк над экраном
    for s in (-1, 1):
        obs.append(box(f"cheek{s}", (6, 2, 40), (9 + 1.5, s * 11, 41), {"*": "atm_body"}))
        obs.append(box(f"accent{s}", (0.3, 0.6, 38), (13.65, s * 11, 41), {"*": "atm_accent"}))
    obs.append(box("hood", (6, 24, 2.5), (10.5, 0, 59.5), {"*": "atm_body"}))
    # экран в рамке
    obs.append(box("bezel", (0.6, 16, 16), (9.1, 0, 45), {"*": "atm_trim"}))
    obs.append(box("screen", (0.2, 14, 14), (9.45, 0, 45), {"+x": "atm_screen", "*": "atm_trim"}, fit=("+x",)))
    # полка с клавиатурой (наклон к пользователю)
    obs.append(box("shelf", (6, 20, 1.6), (12, 0, 30.6), {"*": "atm_trim"}, rot=(0, 18, 0)))
    obs.append(box("keypad", (5.2, 7.4, 0.3), (12.0, -1.2, 31.6), {"+z": "atm_keypad", "*": "atm_trim"}, fit=("+z",), rot=(0, 18, 0)))
    # картоприёмник справа (если стоять лицом к банкомату — справа = +Y)
    obs.append(box("cardslot", (0.8, 4.2, 3.4), (9.4, 7.6, 34), {"+x": "atm_slot", "*": "atm_trim"}, fit=("+x",)))
    # выдача наличных и чеков
    obs.append(box("cash", (0.8, 12, 4), (9.4, 0, 25), {"+x": "atm_cash", "*": "atm_trim"}, fit=("+x",)))
    obs.append(box("receipt", (0.6, 3, 0.8), (9.3, -7, 25), {"*": "atm_trim"}))
    # вывеска сверху
    obs.append(box("topper", (8, 25, 10), (3, 0, 67), {"+x": "atm_topper", "-x": "atm_topper", "*": "atm_body"}, fit=("+x", "-x")))
    obs.append(box("topper_trim", (8.4, 25.4, 0.6), (3, 0, 62.3), {"*": "atm_accent"}))
    return obs


def collect(obs):
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    out = {}
    for ob in obs:
        eo = ob.evaluated_get(deps)
        me = eo.to_mesh()
        me.calc_loop_triangles()
        uvl = me.uv_layers.active.data
        mw = ob.matrix_world
        nm = mw.to_3x3()
        for tri in me.loop_triangles:
            mat = ob.material_slots[tri.material_index].material.name
            vs = []
            for li in tri.loops:
                v = me.vertices[me.loops[li].vertex_index]
                co = mw @ v.co
                n = (nm @ tri.normal).normalized()
                u = uvl[li].uv
                vs.append(((co.x, co.y, co.z), (n.x, n.y, n.z), (u[0], 1 - u[1])))
            out.setdefault(mat, []).append(vs)
        eo.to_mesh_clear()
    return out


def render_preview(path, obs):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 48
    scn.render.resolution_x, scn.render.resolution_y = 960, 960
    world = bpy.data.worlds.new("w")
    scn.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.055, 0.07, 1)
    cam_d = bpy.data.cameras.new("cam")
    cam_d.lens = 50
    cam = bpy.data.objects.new("cam", cam_d)
    bpy.context.collection.objects.link(cam)
    scn.camera = cam
    for loc, e in (((80, -60, 90), 60000), ((-40, 60, 50), 20000)):
        ld = bpy.data.lights.new("l", "AREA")
        ld.energy = e
        ld.size = 30
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 36)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(lo)
    shots = []
    for i, loc in enumerate(((110, -55, 60), (60, 30, 48))):
        cam.location = loc
        cam.rotation_euler = (Vector((4, 0, 38)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = path.replace(".png", f"_{i}.png")
        bpy.ops.render.render(write_still=True)
        shots.append(Image.open(scn.render.filepath))
    out = Image.new("RGB", (1920, 960))
    for i, s in enumerate(shots):
        out.paste(s, (960 * i, 0))
        os.remove(path.replace(".png", f"_{i}.png"))
    out.save(path)
    print("preview", path)


def main():
    import mdlc
    build_textures()
    obs = build()
    tris = collect(obs)
    print("triangles:", sum(len(v) for v in tris.values()))
    out = os.path.join(GM, "content", "models", "nyrp", "atm")
    mdlc.compile_model(out, "atm", "nyrp/atm/atm.mdl", tris, "models/nyrp/atm", "metal", 300)
    # карта: 3.37 × 2.13 (крупнее настоящей в ~1.3 раза, как сим-карта), лежит плашмя
    for ob in obs:
        ob.hide_render = True
    card = box("card", (3.37, 2.13, 0.05), (0, 0, 0), {"+z": "atm_card", "-z": "atm_card", "*": "atm_trim"}, fit=("+z", "-z"))
    ctris = collect([card])
    mdlc.compile_model(out, "w_bankcard", "nyrp/atm/w_bankcard.mdl", ctris, "models/nyrp/atm", "plastic", 0.05)
    os.makedirs(SRC, exist_ok=True)
    np.savez_compressed(os.path.join(SRC, "atm_vm.npz"), **{
        "card|" + m: np.array([[*p, *n, *uv] for tri in tl for p, n, uv in tri], np.float32) for m, tl in ctris.items()})
    bpy.data.objects.remove(card)
    for ob in obs:
        ob.hide_render = False
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "atm.blend"))
    render_preview(os.path.join(ROOT, "branding", "atm_preview.png"), obs)


if __name__ == "__main__":
    main()
