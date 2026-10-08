"""Смартфон New-York Roleplay (Blender / bpy) -> модели и текстуры.

Запуск:  python3 tools/models/build_phone.py
Делает:
  content/models/nyrp/phone/w_phone.mdl        мировая модель (предмет, рука от третьего лица)
  tools/models/src/phone_vm.npz                геометрия для вьюмодели (viewmodel/build_vm.py phone)
  content/materials/models/nyrp/phone/*.vtf/.vmt  текстуры
  tools/models/phone.blend, branding/phone_preview.png

Оси телефона: +X — нормаль экрана, +Y — ширина (влево, если смотреть на экран), +Z — вверх (длинная сторона).
Размеры (ед. Source ≈ 1.9 см): 7.9 × 3.7 × 0.42.
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
MATDIR = os.path.join(GM, "content", "materials", "models", "nyrp", "phone")
UI_DIR = os.path.join(GM, "content", "materials", "nyrp", "phone")

H, W, T = 7.9, 3.7, 0.42      # высота, ширина, толщина
R = 0.62                      # скругление углов
SEG = 10


# ---------------------------------------------------------------- текстуры --
def tex_frame(S=256):
    """Графитовый алюминий: шлифовка вдоль, мягкий блик."""
    rng = np.random.default_rng(1)
    n = rng.normal(0, 1, (S, S))
    streak = np.cumsum(n, axis=1)
    streak = (streak - streak.mean(1, keepdims=True)) / (streak.std() + 1e-6)
    v = 0.30 + 0.035 * streak + 0.02 * rng.normal(0, 1, (S, S))
    img = np.dstack([v * 0.92, v * 0.95, v * 1.02])
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def tex_back(S=512):
    """Матовое стекло цвета «полночный синий» с гравировкой NY и тонкой полосой «шашечек»."""
    rng = np.random.default_rng(2)
    yy, xx = np.mgrid[0:S, 0:S] / S
    base = np.array([16, 24, 44]) / 255
    grad = 0.85 + 0.25 * (1 - yy) + 0.05 * xx
    frost = rng.normal(0, 0.012, (S, S))
    img = base[None, None] * grad[..., None] + frost[..., None]
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype(os.path.join(GM, "content", "resource", "fonts", "Oswald_600SemiBold.ttf"), int(S * 0.16))
    except OSError:
        font = ImageFont.load_default()
    # гравировка «NY» — чуть светлее и с тенью
    d.text((S * 0.5 + 2, S * 0.56 + 2), "NY", font=font, fill=(6, 10, 22), anchor="mm")
    d.text((S * 0.5, S * 0.56), "NY", font=font, fill=(52, 64, 92), anchor="mm")
    cs = S // 64
    y0 = int(S * 0.66)
    for i in range(0, S // cs):
        for r in range(2):
            if (i + r) % 2 == 0:
                d.rectangle([S * 0.36 + i * cs * 0.5, y0 + r * cs * 0.5, S * 0.36 + i * cs * 0.5 + cs * 0.5, y0 + (r + 1) * cs * 0.5],
                            fill=(170, 140, 30)) if S * 0.36 + i * cs * 0.5 < S * 0.64 else None
    return np.array(im.filter(ImageFilter.GaussianBlur(0.6)))


def tex_glass(S=128):
    yy, xx = np.mgrid[0:S, 0:S] / S
    v = 0.03 + 0.03 * (1 - yy)
    img = np.dstack([v, v, v * 1.3])
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def wallpaper(S=512, variant=0):
    """Обои: ночной Нью-Йорк — градиент неба, силуэты небоскрёбов с окнами, жёлтое такси-свечение."""
    rng = np.random.default_rng(10 + variant)
    skies = [((10, 14, 40), (120, 60, 110)), ((6, 20, 40), (40, 120, 140)), ((20, 10, 30), (200, 90, 50)),
             ((8, 8, 12), (60, 60, 70)), ((12, 18, 30), (247, 198, 0))]
    top, bot = skies[variant % len(skies)]
    yy = np.linspace(0, 1, S)[:, None, None]
    sky = np.array(top)[None, None] * (1 - yy ** 1.4) + np.array(bot)[None, None] * yy ** 1.4
    img = np.repeat(sky, S, axis=1).astype(np.float32)
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    # звёзды
    for _ in range(80):
        x, y = rng.integers(0, S), rng.integers(0, int(S * 0.45))
        b = int(rng.integers(120, 255))
        d.point((int(x), int(y)), fill=(b, b, b))
    # силуэты зданий
    x = 0
    while x < S:
        w = int(rng.integers(S // 18, S // 7))
        h = int(rng.integers(int(S * 0.15), int(S * 0.55)))
        top_y = S - h
        d.rectangle([x, top_y, x + w, S], fill=(8, 9, 14))
        if rng.random() < 0.3:  # шпиль
            d.polygon([(x + w // 2 - 3, top_y), (x + w // 2, top_y - S // 12), (x + w // 2 + 3, top_y)], fill=(8, 9, 14))
        for wy in range(top_y + 6, S - 4, 9):
            for wx in range(x + 4, x + w - 4, 7):
                if rng.random() < 0.35:
                    c = (255, 214, 120) if rng.random() < 0.8 else (180, 210, 255)
                    d.rectangle([wx, wy, wx + 2, wy + 3], fill=c)
        x += w + int(rng.integers(0, 4))
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse([S * 0.1, S * 0.85, S * 0.9, S * 1.2], fill=(120, 90, 10))
    im = Image.blend(im, Image.composite(glow, im, glow.convert("L").point(lambda v: 255 if v else 0)), 0.25)
    return np.array(im)


def tex_lens(S=64):
    yy, xx = np.mgrid[0:S, 0:S] / S - 0.5
    r = np.sqrt(xx ** 2 + yy ** 2) * 2
    v = np.clip(0.05 + 0.4 * np.exp(-((r - 0.35) ** 2) / 0.004), 0, 1)
    img = np.dstack([v * 0.6, v * 0.7, v * 1.0])
    img[r > 0.92] = [0.45, 0.46, 0.5]
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def tex_sim(S=256):
    """Сим-карта: белый пластик с золотым чипом и надписью NY MOBILE."""
    im = Image.new("RGB", (S, S), (236, 236, 238))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([S * 0.1, S * 0.32, S * 0.48, S * 0.68], radius=S // 24, fill=(214, 172, 70), outline=(150, 110, 30), width=2)
    for k in range(1, 4):
        d.line([S * 0.1, S * (0.32 + 0.09 * k), S * 0.48, S * (0.32 + 0.09 * k)], fill=(160, 120, 40), width=2)
    d.line([S * 0.29, S * 0.32, S * 0.29, S * 0.68], fill=(160, 120, 40), width=2)
    d.rectangle([S * 0.56, S * 0.4, S * 0.92, S * 0.47], fill=(247, 198, 0))
    d.rectangle([S * 0.56, S * 0.53, S * 0.86, S * 0.58], fill=(40, 44, 60))
    return np.array(im)


MATS = {
    "phone_sim": (tex_sim, False, False),
    # имя: (функция текстуры, фонг, selfillum)
    "phone_frame": (tex_frame, True, False),
    "phone_back": (tex_back, True, False),
    "phone_glass": (tex_glass, True, False),
    "phone_screen": (lambda: wallpaper(512, 0), False, True),
    "phone_lens": (tex_lens, True, False),
}


def build_textures():
    os.makedirs(MATDIR, exist_ok=True)
    for name, (fn, phong, selfillum) in MATS.items():
        img = fn()
        textures.write_vtf(os.path.join(MATDIR, name + ".vtf"), img[..., :3])
        with open(os.path.join(MATDIR, name + ".vmt"), "w") as f:
            extra = ""
            if phong:
                extra += '\t"$phong" "1"\n\t"$phongexponent" "40"\n\t"$phongboost" "4"\n\t"$phongfresnelranges" "[0.4 0.8 1]"\n'
            if selfillum:
                extra += '\t"$selfillum" "1"\n'
            f.write(f'"VertexLitGeneric"\n{{\n\t"$basetexture" "models/nyrp/phone/{name}"\n{extra}}}\n')
    # обои для интерфейса телефона (PNG)
    os.makedirs(UI_DIR, exist_ok=True)
    for v in range(5):
        Image.fromarray(wallpaper(512, v)).resize((360, 640), Image.LANCZOS).save(os.path.join(UI_DIR, f"wall{v + 1}.png"))
    print("textures ok")


def blender_material(name):
    fn = MATS[name][0]
    arr = fn().astype(np.float32) / 255.0
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
    bsdf.inputs["Roughness"].default_value = 0.25 if name != "phone_back" else 0.55
    bsdf.inputs["Metallic"].default_value = 0.9 if name == "phone_frame" else 0.0
    if name == "phone_screen":
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    return m


# --------------------------------------------------------------- геометрия --
def rounded_rect(w, h, r, seg=SEG):
    """Контур скруглённого прямоугольника (y, z) против часовой."""
    pts = []
    for cx, cz, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
    return pts


def slab(name, outline, x0, x1, mat_front, mat_back, mat_side, chamfer=0.0, uv_box=(W, H)):
    """Плита по контуру между плоскостями x0 (зад) и x1 (перед); фаска chamfer на передней кромке."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    n = len(outline)
    rings = []
    layers = [(x0, 1.0), (x1 - chamfer, 1.0)]
    if chamfer > 0:
        layers.append((x1, 1.0 - chamfer / max(uv_box)))
    for x, sc in layers:
        rings.append([bm.verts.new((x, y * sc, z * sc)) for y, z in outline])
    mats = [mat_front, mat_back, mat_side]
    # бока
    perim = [0.0]
    for i in range(1, n + 1):
        a, b = outline[i - 1], outline[i % n]
        perim.append(perim[-1] + math.dist(a, b))
    pos = {}
    for ring in rings:
        for k, v in enumerate(ring):
            pos[v] = k
    for ri in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            f = bm.faces.new((rings[ri][i], rings[ri][j], rings[ri + 1][j], rings[ri + 1][i]))
            f.material_index = 2
            f.smooth = True
            for loop in f.loops:
                k = pos[loop.vert]
                if i == n - 1 and k == 0:
                    k = n   # шов: последняя грань тянется до конца развёртки
                loop[uv].uv = (perim[k] / perim[-1] * 4, loop.vert.co.x * 2)
    # крышки
    for ring, idx, rev in ((rings[-1], 0, False), (rings[0], 1, True)):
        vs = list(reversed(ring)) if rev else ring
        f = bm.faces.new(vs)
        f.material_index = idx
        for loop in f.loops:
            loop[uv].uv = (0.5 - loop.vert.co.y / uv_box[0], 0.5 + loop.vert.co.z / uv_box[1])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(bpy.data.materials[m])
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def cylinder(name, center, radius, x0, x1, mat_front, mat_side, seg=20):
    cy, cz = center
    outline = [(cy + math.cos(2 * math.pi * k / seg) * radius, cz + math.sin(2 * math.pi * k / seg) * radius) for k in range(seg)]
    # для UV крышки — локально к центру
    ob = slab(name, outline, x0, x1, mat_front, mat_side, mat_side, uv_box=(radius * 2, radius * 2))
    me = ob.data
    uvl = me.uv_layers.active.data
    for poly in me.polygons:
        if poly.material_index == 0:
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                uvl[li].uv = (0.5 - (co.y - cy) / (radius * 2), 0.5 + (co.z - cz) / (radius * 2))
    return ob


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for m in MATS:
        blender_material(m)
    obs = []
    # корпус: рамка по бокам, стекло спереди, задняя крышка
    obs.append(slab("body", rounded_rect(W, H, R), -T / 2, T / 2, "phone_glass", "phone_back", "phone_frame", chamfer=0.05))
    # экран (чуть над стеклом, скругление меньше рамки)
    sw, sh = W - 0.26, H - 0.3
    scr = slab("screen", rounded_rect(sw, sh, R - 0.13), T / 2 + 0.003, T / 2 + 0.006, "phone_screen", "phone_glass", "phone_glass",
               uv_box=(sw, sh))
    obs.append(scr)
    # блок камер сзади (верхний левый угол, если смотреть на заднюю крышку)
    bump_c = (W / 2 - 0.95, H / 2 - 0.95)
    bump = [(bump_c[0] + y, bump_c[1] + z) for y, z in rounded_rect(1.45, 1.45, 0.38, 6)]
    obs.append(slab("bump", bump, -T / 2 - 0.09, -T / 2 + 0.01, "phone_back", "phone_frame", "phone_frame", uv_box=(W, H)))
    for k, (dy, dz) in enumerate(((-0.33, 0.33), (0.33, 0.0), (-0.33, -0.33))):
        c = (bump_c[0] + dy, bump_c[1] + dz)
        ob = cylinder(f"lens{k}", c, 0.27, -T / 2 - 0.16, -T / 2 - 0.08, "phone_lens", "phone_frame")
        obs.append(ob)
    # вспышка
    obs.append(cylinder("flash", (bump_c[0] + 0.33, bump_c[1] + 0.42), 0.09, -T / 2 - 0.12, -T / 2 - 0.085, "phone_glass", "phone_frame", 10))
    # кнопки: громкость слева, питание справа
    for name, y, z, h in (("btn_vol_up", W / 2 - 0.035, 1.6, 0.55), ("btn_vol_dn", W / 2 - 0.035, 0.9, 0.55), ("btn_power", -W / 2 + 0.035, 1.2, 0.9)):
        ob = slab(name, rounded_rect(0.12, h, 0.05, 3), -0.08, 0.08, "phone_frame", "phone_frame", "phone_frame")
        # повернём «плиту» так, чтобы кнопка торчала из боковой грани
        ob.rotation_euler = (0, 0, math.radians(90))
        ob.location = (0, y, z)
        obs.append(ob)
    # фронтальная камера («капля» в экране)
    obs.append(cylinder("selfie", (0.0, H / 2 - 0.38), 0.075, T / 2 + 0.006, T / 2 + 0.008, "phone_lens", "phone_glass", 12))
    return obs


def collect(obs):
    """Треугольники по материалам в координатах телефона."""
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
                n = (nm @ (me.loops[li].normal if tri.use_smooth else tri.normal)).normalized()
                u = uvl[li].uv
                vs.append(((co.x, co.y, co.z), (n.x, n.y, n.z), (u[0], 1 - u[1])))
            out.setdefault(mat, []).append(vs)
        eo.to_mesh_clear()
    return out


def render_preview(path):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 48
    scn.render.resolution_x, scn.render.resolution_y = 960, 640
    world = bpy.data.worlds.new("w")
    scn.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.055, 0.07, 1)
    cam_d = bpy.data.cameras.new("cam")
    cam_d.lens = 70
    cam = bpy.data.objects.new("cam", cam_d)
    bpy.context.collection.objects.link(cam)
    scn.camera = cam
    for loc, e in (((14, -10, 12), 4000), ((-12, 8, 6), 1500), ((4, 14, -6), 800)):
        ld = bpy.data.lights.new("l", "AREA")
        ld.energy = e
        ld.size = 6
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(lo)
    shots = []
    for i, (loc, rot) in enumerate((((26, -9, 6), 0), ((-26, 9, 6), 0))):
        cam.location = loc
        cam.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = path.replace(".png", f"_{i}.png")
        bpy.ops.render.render(write_still=True)
        shots.append(Image.open(scn.render.filepath))
    out = Image.new("RGB", (1920, 640))
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
    out = os.path.join(GM, "content", "models", "nyrp", "phone")
    mdlc.compile_model(out, "w_phone", "nyrp/phone/w_phone.mdl", tris, "models/nyrp/phone", "plastic", 0.4)
    # сим-карта: плоская карточка (крупнее настоящей, чтобы было видно в мире)
    for ob in bpy.data.objects:
        ob.hide_render = True
    sim = slab("simcard", rounded_rect(1.3, 0.9, 0.08, 3), -0.025, 0.025, "phone_sim", "phone_sim", "phone_frame", uv_box=(1.3, 0.9))
    sim.rotation_euler = (0, math.radians(90), 0)
    mdlc.compile_model(out, "w_simcard", "nyrp/phone/w_simcard.mdl", collect([sim]), "models/nyrp/phone", "plastic", 0.05)
    bpy.data.objects.remove(sim)
    for ob in bpy.data.objects:
        ob.hide_render = False
    # для вьюмодели — массив вершин по материалам (pos, normal, uv)
    os.makedirs(SRC, exist_ok=True)
    np.savez_compressed(os.path.join(SRC, "phone_vm.npz"), **{
        "phone|" + m: np.array([[*p, *n, *uv] for tri in tl for p, n, uv in tri], np.float32) for m, tl in tris.items()})
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "phone.blend"))
    render_preview(os.path.join(ROOT, "branding", "phone_preview.png"))


if __name__ == "__main__":
    main()
