"""Мелкие предметы New-York Roleplay (Blender / bpy) -> модели и текстуры.

Запуск:  python3 tools/models/build_props.py [имя ...]
Делает (content/models/nyrp/props/*.mdl, content/materials/models/nyrp/props/*):
  w_money       пачка долларов с бумажной лентой (выброшенные деньги)
  w_keys        связка ключей на кольце с брелоком
  mailbox       стена почтовых ящиков (6 × 5 дверок) с граффити
  w_radio       портативная рация с антенной
  w_cigarette   сигарета;  w_cigpack — пачка «Liberty Lights»;  w_lighter — зажигалка
  w_vest        бронежилет (плитник: передняя и задняя плиты, лямки)
  w_helmet      каска
и геометрию для вьюмоделей рук (tools/models/src/<имя>_vm.npz): keys, radio, lighter, cigarette.

Оси: +X — «лицо» предмета, +Z — вверх. Единицы Source (≈ 1.9 см).
"""
import math
import os
import sys

import bpy  # noqa: I001
import bmesh
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import textures  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GM = os.path.join(ROOT, "gamemodes", "newyorkrp")
SRC = os.path.join(HERE, "src")
MATDIR = os.path.join(GM, "content", "materials", "models", "nyrp", "props")
OUT = os.path.join(GM, "content", "models", "nyrp", "props")
FONTS = os.path.join(GM, "content", "resource", "fonts")


def font(name, size):
    for n in (name, "Manrope_800ExtraBold.ttf", "Oswald_600SemiBold.ttf"):
        try:
            return ImageFont.truetype(os.path.join(FONTS, n), size)
        except OSError:
            continue
    return ImageFont.load_default()


def noise(S, amp, seed, blur=0):
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 1, (S, S))
    if blur:
        im = Image.fromarray(((n - n.min()) / (n.max() - n.min()) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur))
        n = np.asarray(im, np.float32) / 255 * 2 - 1
    return n * amp


def solid(color, S=128, amp=0.04, seed=1, blur=1):
    v = 1 + noise(S, amp, seed, blur)
    return np.clip(np.array(color, np.float32)[None, None] * v[..., None], 0, 255).astype(np.uint8)


def brushed(color, S=256, amp=0.05, seed=2):
    rng = np.random.default_rng(seed)
    st = np.cumsum(rng.normal(0, 1, (S, S)), axis=1)
    st = (st - st.mean(1, keepdims=True)) / (st.std() + 1e-6)
    v = 1 + amp * st
    return np.clip(np.array(color, np.float32)[None, None] * v[..., None], 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- текстуры --
def tex_money_top(S=512):
    """Лицевая сторона купюры $100 (стилизованная): зелёно-серая гильошировка, портрет в овале, номиналы."""
    base = np.array((196, 206, 186), np.float32)
    yy, xx = np.mgrid[0:S, 0:S] / S
    g = (np.sin(xx * 90 + np.sin(yy * 30) * 3) * 0.5 + 0.5) * 0.08 + (np.sin(yy * 140) * 0.5 + 0.5) * 0.04
    img = base[None, None] * (1 - g[..., None])
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    # купюра вытянута: текстура ложится на 8.2 × 3.5 — рисуем в «сжатых» координатах по Y
    d.rectangle([10, 10, S - 10, S - 10], outline=(70, 96, 72), width=8)
    d.rectangle([28, 28, S - 28, S - 28], outline=(110, 130, 104), width=3)
    cx, cy = S // 2, S // 2
    d.ellipse([cx - 70, cy - 170, cx + 70, cy + 170], fill=(150, 160, 140), outline=(60, 80, 62), width=6)
    d.ellipse([cx - 40, cy - 110, cx + 40, cy + 30], fill=(96, 108, 92))
    d.rectangle([cx - 58, cy + 20, cx + 58, cy + 150], fill=(96, 108, 92))
    f = font("Oswald_600SemiBold.ttf", 120)
    for x, y in ((40, 40), (S - 210, S - 170)):
        d.text((x, y), "100", font=f, fill=(56, 84, 60))
    f2 = font("Manrope_800ExtraBold.ttf", 34)
    d.text((40, S - 80), "UNITED STATES", font=f2, fill=(60, 80, 62))
    d.text((S - 290, 50), "OF AMERICA", font=f2, fill=(60, 80, 62))
    # синяя защитная лента
    d.rectangle([cx + 110, 0, cx + 130, S], fill=(70, 110, 170))
    return np.array(im.filter(ImageFilter.GaussianBlur(0.6)))


def tex_money_side(S=128):
    """Торцы пачки: тонкие слои бумаги."""
    img = np.zeros((S, S, 3), np.float32)
    rng = np.random.default_rng(5)
    rows = 0.86 + rng.random(S) * 0.14
    img[:] = np.array((205, 210, 196))[None, None] * rows[None, :, None]
    return np.clip(img, 0, 255).astype(np.uint8)


def tex_band(S=128):
    img = solid((200, 160, 70), S, 0.03, 7)
    im = Image.fromarray(img)
    d = ImageDraw.Draw(im)
    f = font("Oswald_600SemiBold.ttf", 40)
    d.text((14, 40), "$10K", font=f, fill=(120, 80, 20))
    return np.array(im)


def tex_brass(S=128):
    return brushed((196, 160, 82), S, 0.08, 11)


def tex_steel(S=128):
    return brushed((170, 174, 180), S, 0.07, 12)


def tex_black(S=64):
    return solid((28, 29, 32), S, 0.05, 13)


def tex_fob(S=128):
    img = solid((22, 24, 28), S, 0.04, 14)
    im = Image.fromarray(img)
    d = ImageDraw.Draw(im)
    d.ellipse([S * 0.3, S * 0.3, S * 0.7, S * 0.7], outline=(247, 198, 0), width=6)
    return np.array(im)


MB_COLS, MB_ROWS = 6, 5
MB_W, MB_H, MB_D = 42.0, 36.0, 9.0


def tex_mailbox_front(S=1024):
    """Стена ящиков: шлифованная сталь, дверки с номерами, замками и прорезями; поверх — граффити."""
    img = brushed((150, 154, 160), S, 0.06, 21).astype(np.float32)
    im = Image.fromarray(img.astype(np.uint8))
    d = ImageDraw.Draw(im)
    m = int(S * 0.025)
    cw, ch = (S - 2 * m) / MB_COLS, (S - 2 * m) / MB_ROWS
    fnum = font("Manrope_800ExtraBold.ttf", int(ch * 0.13))
    n = 1
    for r in range(MB_ROWS):
        for c in range(MB_COLS):
            x0, y0 = m + c * cw, m + r * ch
            x1, y1 = x0 + cw, y0 + ch
            # зазор между дверками
            d.rectangle([x0, y0, x1, y1], outline=(60, 62, 66), width=4)
            d.rectangle([x0 + 4, y0 + 4, x1 - 4, y1 - 4], outline=(196, 200, 206), width=2)
            # табличка номера
            px, py = x0 + cw * 0.12, y0 + ch * 0.12
            d.rectangle([px, py, px + cw * 0.36, py + ch * 0.2], fill=(40, 42, 46))
            d.text((px + cw * 0.04, py + ch * 0.02), f"{100 + n}", font=fnum, fill=(230, 232, 236))
            # замок
            lx, ly = x0 + cw * 0.78, y0 + ch * 0.28
            d.ellipse([lx - ch * 0.07, ly - ch * 0.07, lx + ch * 0.07, ly + ch * 0.07], fill=(110, 112, 118), outline=(50, 52, 56), width=3)
            d.rectangle([lx - 2, ly - ch * 0.04, lx + 2, ly + ch * 0.04], fill=(30, 30, 34))
            # вентиляционные прорези
            for k in range(4):
                yy = y0 + ch * (0.55 + k * 0.08)
                d.rectangle([x0 + cw * 0.2, yy, x1 - cw * 0.2, yy + ch * 0.025], fill=(52, 54, 58))
            n += 1
    # граффити: мазки баллончиком и теги
    rng = np.random.default_rng(4)
    tag = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(tag)
    colors = [(30, 30, 34, 230), (220, 40, 60, 220), (40, 120, 220, 210), (250, 250, 250, 200), (240, 200, 0, 210)]
    for i in range(14):
        pts = []
        x, y = rng.uniform(0, S), rng.uniform(0, S)
        for _ in range(rng.integers(5, 12)):
            x += rng.normal(0, S * 0.05)
            y += rng.normal(0, S * 0.03)
            pts.append((x, y))
        td.line(pts, fill=colors[i % len(colors)], width=int(rng.uniform(6, 16)), joint="curve")
    ftag = font("Oswald_600SemiBold.ttf", int(S * 0.11))
    for text, pos, col, rot in (("NYC", (0.1, 0.35), (220, 40, 60, 235), 12), ("BX 99", (0.5, 0.15), (30, 30, 34, 240), -8),
                                ("KING", (0.45, 0.62), (40, 120, 220, 230), 6)):
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(layer).text((pos[0] * S, pos[1] * S), text, font=ftag, fill=col, stroke_width=6, stroke_fill=(250, 250, 250, 220))
        tag = Image.alpha_composite(tag, layer.rotate(rot, center=(pos[0] * S + S * 0.15, pos[1] * S + S * 0.05)))
    tag = tag.filter(ImageFilter.GaussianBlur(1.2))
    im = Image.alpha_composite(im.convert("RGBA"), tag).convert("RGB")
    # грязь снизу
    arr = np.asarray(im, np.float32)
    yy = np.linspace(0, 1, S)[:, None, None]
    arr *= 1 - 0.25 * np.clip((yy - 0.7) / 0.3, 0, 1) * (0.6 + 0.4 * (noise(S, 1, 5, 6)[..., None] * 0.5 + 0.5))
    return np.clip(arr, 0, 255).astype(np.uint8)


def tex_mailbox_body(S=256):
    return brushed((120, 124, 130), S, 0.05, 22)


def tex_radio_front(S=256):
    img = solid((26, 28, 30), S, 0.03, 31)
    im = Image.fromarray(img)
    d = ImageDraw.Draw(im)
    # экран частоты сверху и решётка динамика
    d.rectangle([S * 0.18, S * 0.08, S * 0.82, S * 0.26], fill=(40, 70, 46), outline=(10, 10, 12), width=4)
    d.text((S * 0.24, S * 0.11), "150.0", font=font("Manrope_800ExtraBold.ttf", int(S * 0.11)), fill=(150, 230, 140))
    for r in range(8):
        for c in range(6):
            x, y = S * (0.24 + c * 0.1), S * (0.4 + r * 0.065)
            d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(8, 8, 10))
    d.text((S * 0.3, S * 0.9), "NY-COMM", font=font("Manrope_800ExtraBold.ttf", int(S * 0.07)), fill=(247, 198, 0))
    return np.array(im)


def tex_paper(S=64):
    return solid((236, 234, 228), S, 0.02, 41)


def tex_filter(S=64):
    img = solid((206, 140, 70), S, 0.06, 42, 0)
    return img


def tex_ash(S=64):
    return solid((90, 86, 80), S, 0.2, 43, 0)


def tex_cigpack(S=512):
    """Пачка «Liberty Lights»: белая, с синей полосой и жёлтой звездой; предупреждение снизу."""
    im = Image.new("RGB", (S, S), (240, 240, 236))
    d = ImageDraw.Draw(im)
    d.rectangle([0, int(S * 0.36), S, int(S * 0.58)], fill=(28, 56, 140))
    d.polygon([(S * 0.5, S * 0.12), (S * 0.56, S * 0.27), (S * 0.72, S * 0.27), (S * 0.59, S * 0.35), (S * 0.64, S * 0.5),
               (S * 0.5, S * 0.41), (S * 0.36, S * 0.5), (S * 0.41, S * 0.35), (S * 0.28, S * 0.27), (S * 0.44, S * 0.27)],
              fill=(247, 198, 0))
    f = font("Oswald_600SemiBold.ttf", int(S * 0.1))
    d.text((S * 0.12, S * 0.4), "LIBERTY", font=f, fill=(255, 255, 255))
    d.text((S * 0.3, S * 0.6), "LIGHTS", font=font("Manrope_800ExtraBold.ttf", int(S * 0.07)), fill=(28, 56, 140))
    d.rectangle([0, int(S * 0.8), S, S], fill=(10, 10, 10))
    d.text((S * 0.06, S * 0.84), "SMOKING KILLS", font=font("Oswald_600SemiBold.ttf", int(S * 0.075)), fill=(255, 255, 255))
    return np.array(im)


def tex_lighter(S=128):
    return solid((200, 40, 50), S, 0.04, 51)


def tex_cordura(S=256):
    """Оливковая кордура с полосами MOLLE."""
    img = solid((70, 76, 52), S, 0.06, 61, 0).astype(np.float32)
    rng = np.random.default_rng(62)
    img *= (1 + rng.normal(0, 0.03, (S, 1, 1)))
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for k in range(5):
        y = int(S * (0.15 + k * 0.17))
        d.rectangle([0, y, S, y + int(S * 0.06)], fill=(54, 58, 40))
        for x in range(0, S, int(S * 0.12)):
            d.rectangle([x, y, x + 3, y + int(S * 0.06)], fill=(40, 42, 30))
    return np.array(im)


def tex_helmet(S=256):
    return solid((74, 80, 58), S, 0.05, 71, 2)


MATS = {
    "money_top": (tex_money_top, False), "money_side": (tex_money_side, False), "money_band": (tex_band, False),
    "brass": (tex_brass, True), "steel": (tex_steel, True), "plastic_black": (tex_black, False), "fob": (tex_fob, False),
    "mailbox_front": (tex_mailbox_front, True), "mailbox_body": (tex_mailbox_body, True),
    "radio_front": (tex_radio_front, False),
    "cig_paper": (tex_paper, False), "cig_filter": (tex_filter, False), "cig_ash": (tex_ash, False),
    "cigpack": (tex_cigpack, False), "lighter": (tex_lighter, True),
    "cordura": (tex_cordura, False), "helmet": (tex_helmet, False),
}


def build_textures():
    os.makedirs(MATDIR, exist_ok=True)
    for name, (fn, phong) in MATS.items():
        img = fn()
        textures.write_vtf(os.path.join(MATDIR, name + ".vtf"), img[..., :3])
        textures.write_vmt(os.path.join(MATDIR, name + ".vmt"), "models/nyrp/props/" + name, phong, 20, 1.5)
    print("textures ok")


def blender_material(name):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
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
    bsdf.inputs["Roughness"].default_value = 0.5
    return m


# --------------------------------------------------------------- геометрия --
def _finish(bm, name, mats, loc=(0, 0, 0), rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(blender_material(m))
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    bpy.context.collection.objects.link(ob)
    return ob


def box(name, size, center=(0, 0, 0), mats="steel", fit=(), tile=8.0, rot=(0, 0, 0)):
    """Коробка; mats — материал или {грань: материал} («*» — остальные); грани из fit — текстура целиком."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    half = (hx, hy, hz)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    names = []
    faces = {"+x": (0, 1), "-x": (0, -1), "+y": (1, 1), "-y": (1, -1), "+z": (2, 1), "-z": (2, -1)}
    for key, (axis, sgn) in faces.items():
        others = [i for i in range(3) if i != axis]
        corners = []
        for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            p = [0.0, 0.0, 0.0]
            p[axis] = sgn * half[axis]
            p[others[0]] = a * half[others[0]]
            p[others[1]] = b * half[others[1]]
            corners.append(p)
        f = bm.faces.new([bm.verts.new(c) for c in corners])
        f.normal_update()
        nv = [0, 0, 0]
        nv[axis] = sgn
        if f.normal.dot(nv) < 0:
            f.normal_flip()
        mat = mats.get(key, mats.get("*", "steel")) if isinstance(mats, dict) else mats
        if mat not in names:
            names.append(mat)
        f.material_index = names.index(mat)
        for loop in f.loops:
            co = loop.vert.co
            if key in fit:
                ua = {"+x": 1, "-x": 1, "+y": 0, "-y": 0, "+z": 1, "-z": 1}[key]
                va = {"+x": 2, "-x": 2, "+y": 2, "-y": 2, "+z": 0, "-z": 0}[key]
                u = (co[ua] / half[ua] + 1) / 2
                if key in ("-x", "+y"):     # чтобы надпись читалась, если смотреть на грань снаружи
                    u = 1 - u
                v = (co[va] / half[va] + 1) / 2
                if key == "+z":
                    v = 1 - v
                loop[uvl].uv = (u, v)
            else:
                ua, va = others
                loop[uvl].uv = ((co[ua] + center[ua]) / tile, (co[va] + center[va]) / tile)
    bm.normal_update()
    return _finish(bm, name, names, center, rot)


def cyl(name, r, h, center=(0, 0, 0), mats="steel", seg=16, rot=(0, 0, 0), r2=None, cap="steel"):
    """Цилиндр вдоль Z; бок — mats (u — по окружности, v — по высоте), торцы — cap."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    r2 = r if r2 is None else r2
    bot, top = [], []
    for i in range(seg + 1):
        a = 2 * math.pi * i / seg
        bot.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, -h / 2)))
        top.append(bm.verts.new((math.cos(a) * r2, math.sin(a) * r2, h / 2)))
    names = [mats] if mats == cap else [mats, cap]
    for i in range(seg):
        f = bm.faces.new((bot[i], bot[i + 1], top[i + 1], top[i]))
        f.material_index = 0
        for loop, (u, v) in zip(f.loops, ((i / seg, 0), ((i + 1) / seg, 0), ((i + 1) / seg, 1), (i / seg, 1))):
            loop[uvl].uv = (u, v)
    for ring, z, flip in ((bot, -h / 2, True), (top, h / 2, False)):
        vs = ring[:-1]
        if flip:
            vs = vs[::-1]
        f = bm.faces.new(vs)
        f.material_index = names.index(cap)
        for loop in f.loops:
            co = loop.vert.co
            loop[uvl].uv = (co.x / (2 * max(r, r2)) + 0.5, co.y / (2 * max(r, r2)) + 0.5)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bm.normal_update()
    return _finish(bm, name, names, center, rot)


def torus(name, R, r, center=(0, 0, 0), mats="steel", seg=24, sseg=8, rot=(0, 0, 0)):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    grid = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        row = []
        for j in range(sseg):
            b = 2 * math.pi * j / sseg
            p = (math.cos(a) * (R + r * math.cos(b)), math.sin(a) * (R + r * math.cos(b)), r * math.sin(b))
            row.append(bm.verts.new(p))
        grid.append(row)
    for i in range(seg):
        for j in range(sseg):
            a, b = grid[i][j], grid[(i + 1) % seg][j]
            c, d = grid[(i + 1) % seg][(j + 1) % sseg], grid[i][(j + 1) % sseg]
            f = bm.faces.new((a, b, c, d))
            for loop, (u, v) in zip(f.loops, ((i / seg, j / sseg), ((i + 1) / seg, j / sseg), ((i + 1) / seg, (j + 1) / sseg), (i / seg, (j + 1) / sseg))):
                loop[uvl].uv = (u * 4, v)
    bm.normal_update()
    return _finish(bm, name, [mats], center, rot)


def dome(name, r, center=(0, 0, 0), mats="helmet", seg=20, rings=8, cut=0.0, scale=(1, 1, 1)):
    """Полусфера (каска): от экватора (z = cut·r) до макушки."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    rows = []
    for j in range(rings + 1):
        t = math.asin(cut) + (math.pi / 2 - math.asin(cut)) * j / rings
        row = []
        for i in range(seg + 1):
            a = 2 * math.pi * i / seg
            row.append(bm.verts.new((math.cos(a) * math.cos(t) * r * scale[0], math.sin(a) * math.cos(t) * r * scale[1], math.sin(t) * r * scale[2])))
        rows.append(row)
    for j in range(rings):
        for i in range(seg):
            f = bm.faces.new((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]))
            for loop, (u, v) in zip(f.loops, ((i / seg, j / rings), ((i + 1) / seg, j / rings), ((i + 1) / seg, (j + 1) / rings), (i / seg, (j + 1) / rings))):
                loop[uvl].uv = (u * 3, v)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bm.normal_update()
    # наружу
    for f in bm.faces:
        c = f.calc_center_median()
        if f.normal.dot(c) < 0:
            f.normal_flip()
    return _finish(bm, name, [mats], center)


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


# ------------------------------------------------------------------ модели --
def m_money():
    return [box("bills", (8.2, 3.5, 0.6), (0, 0, 0.3), {"+z": "money_top", "-z": "money_top", "*": "money_side"}, fit=("+z", "-z")),
            box("band", (1.4, 3.56, 0.66), (0, 0, 0.3), {"*": "money_band"}, fit=("+z", "-z", "+y", "-y"))]


def m_keys():
    obs = [torus("ring", 0.62, 0.06, (0, 0, 0), "steel", rot=(90, 0, 0))]
    # два ключа: головка + бородка, свисают с кольца
    for i, (mat, ang) in enumerate((("brass", -16), ("steel", 18))):
        x = math.sin(math.radians(ang)) * 1.2
        obs.append(cyl(f"bow{i}", 0.5, 0.08, (x * 0.6, 0, -1.0), mat, 14, rot=(90, ang, 0), cap=mat))
        obs.append(box(f"blade{i}", (0.3, 0.07, 1.9), (x * 1.35, 0, -2.3), mat, rot=(0, ang, 0)))
        obs.append(box(f"teeth{i}", (0.18, 0.07, 1.2), (x * 1.35 + 0.2, 0, -2.4), mat, rot=(0, ang, 0)))
    obs.append(box("fob", (0.9, 0.35, 1.4), (0, 0, 1.3), {"+y": "fob", "-y": "fob", "*": "plastic_black"}, fit=("+y", "-y")))
    return obs


def m_mailbox():
    # стоит на полу/висит на стене, лицом в +X; основание в z = 0
    return [box("cab", (MB_D, MB_W + 1.6, MB_H + 1.6), (-MB_D / 2, 0, (MB_H + 1.6) / 2), {"*": "mailbox_body"}),
            box("front", (0.3, MB_W, MB_H), (0.15, 0, MB_H / 2 + 0.8), {"+x": "mailbox_front", "*": "mailbox_body"}, fit=("+x",)),
            box("cap", (MB_D + 1.2, MB_W + 2.6, 0.8), (-MB_D / 2 + 0.6, 0, MB_H + 1.6 + 0.4), {"*": "mailbox_body"})]


def m_radio():
    return [box("body", (1.5, 2.6, 5.4), (0, 0, 2.7), {"+x": "radio_front", "*": "plastic_black"}, fit=("+x",)),
            cyl("antenna", 0.22, 3.4, (0, 0.65, 5.4 + 1.7), "plastic_black", 10, r2=0.14, cap="plastic_black"),
            cyl("knob", 0.32, 0.5, (0, -0.6, 5.65), "steel", 12, cap="steel"),
            box("ptt", (0.9, 0.3, 1.4), (0, 1.38, 3.4), "plastic_black")]


CIG_L, CIG_R = 3.2, 0.17


def m_cigarette():
    # вдоль +X: фильтр у x = 0, огонёк у x = CIG_L
    return [cyl("filter", CIG_R, 1.0, (0.5, 0, 0), "cig_filter", 10, rot=(0, 90, 0), cap="cig_filter"),
            cyl("paper", CIG_R, CIG_L - 1.15, (1.0 + (CIG_L - 1.15) / 2, 0, 0), "cig_paper", 10, rot=(0, 90, 0), cap="cig_paper"),
            cyl("ash", CIG_R * 0.95, 0.15, (CIG_L - 0.075, 0, 0), "cig_ash", 10, rot=(0, 90, 0), cap="cig_ash")]


def m_cigpack():
    return [box("pack", (1.1, 2.2, 3.4), (0, 0, 1.7), {"+x": "cigpack", "-x": "cigpack", "*": "cig_paper"}, fit=("+x", "-x"))]


def m_lighter():
    return [box("body", (0.55, 1.3, 2.2), (0, 0, 1.1), "lighter"),
            box("hood", (0.58, 1.33, 0.5), (0, 0, 2.45), "steel"),
            cyl("wheel", 0.2, 0.35, (0, -0.25, 2.85), "steel", 10, rot=(0, 90, 0), cap="steel")]


def m_vest():
    # надевается на кость Spine2: центр торса в 0, +X вперёд (грудь), +Z вверх
    return [box("front", (1.6, 11.5, 12.5), (4.6, 0, -1.0), {"*": "cordura"}, tile=6),
            box("back", (1.6, 11.5, 13.5), (-4.6, 0, -0.5), {"*": "cordura"}, tile=6),
            box("strapL", (9.0, 2.2, 0.9), (0, 4.1, 6.0), {"*": "cordura"}, tile=6),
            box("strapR", (9.0, 2.2, 0.9), (0, -4.1, 6.0), {"*": "cordura"}, tile=6),
            box("sideL", (8.0, 0.8, 5.0), (0, 6.1, -4.5), {"*": "cordura"}, tile=6),
            box("sideR", (8.0, 0.8, 5.0), (0, -6.1, -4.5), {"*": "cordura"}, tile=6),
            box("pouch", (1.4, 7.0, 3.2), (5.9, 0, -4.0), {"*": "cordura"}, tile=6)]


def m_helmet():
    return [dome("shell", 5.0, (0, 0, 0), "helmet", cut=-0.1, scale=(1.12, 1.0, 0.92)),
            cyl("rim", 5.25, 0.5, (0, 0, -0.45), "helmet", 24, cap="helmet")]


MODELS = {
    "w_money": (m_money, "paper", 0.2),
    "w_keys": (m_keys, "metal", 0.1),
    "mailbox": (m_mailbox, "metal", 400),
    "w_radio": (m_radio, "plastic", 0.5),
    "w_cigarette": (m_cigarette, "paper", 0.01),
    "w_cigpack": (m_cigpack, "paper", 0.05),
    "w_lighter": (m_lighter, "plastic", 0.05),
    "w_vest": (m_vest, "flesh", 5),
    "w_helmet": (m_helmet, "metal", 2),
}
# предметы, которые держат руки вьюмодели (геометрия в своих осях, как у мировой модели)
VM = {"keys": "w_keys", "radio": "w_radio", "lighter": "w_lighter", "cigarette": "w_cigarette"}


def render_preview(path, groups):
    """Все предметы в ряд (Cycles) — для проверки глазами."""
    from mathutils import Vector
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 32
    scn.render.resolution_x, scn.render.resolution_y = 640, 640
    world = bpy.data.worlds.new("w")
    scn.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.37, 0.42, 1)
    cam_d = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_d)
    bpy.context.collection.objects.link(cam)
    scn.camera = cam
    ld = bpy.data.lights.new("l", "SUN")
    ld.energy = 4
    lo = bpy.data.objects.new("l", ld)
    lo.rotation_euler = (math.radians(40), math.radians(20), math.radians(30))
    bpy.context.collection.objects.link(lo)
    tiles = []
    for name, obs in groups:
        for o in bpy.context.collection.objects:
            if o.type == "MESH":
                o.hide_render = o not in obs
        pts = [o.matrix_world @ Vector(c) for o in obs for c in o.bound_box]
        mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        c = (mn + mx) / 2
        r = (mx - mn).length / 2
        loc = c + Vector((1.0, -0.8, 0.55)).normalized() * r * 3.0
        cam.location = loc
        cam.rotation_euler = (c - loc).to_track_quat("-Z", "Y").to_euler()
        cam_d.lens = 50
        scn.render.filepath = path.replace(".png", f"_{name}.png")
        bpy.ops.render.render(write_still=True)
        im = Image.open(scn.render.filepath).convert("RGB")
        ImageDraw.Draw(im).text((10, 10), name, fill=(255, 255, 255))
        tiles.append(im)
        os.remove(scn.render.filepath)
    cols = 3
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (640 * cols, 640 * rows))
    for i, t in enumerate(tiles):
        sheet.paste(t, (640 * (i % cols), 640 * (i // cols)))
    sheet.save(path)
    print("preview", path)


def main():
    import mdlc
    only = set(sys.argv[1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_textures()
    os.makedirs(SRC, exist_ok=True)
    groups = []
    for name, (fn, surf, mass) in MODELS.items():
        if only and name not in only:
            continue
        obs = fn()
        tris = collect(obs)
        mdlc.compile_model(OUT, name, f"nyrp/props/{name}.mdl", tris, "models/nyrp/props", surf, mass)
        print(name, "triangles:", sum(len(v) for v in tris.values()))
        for vm, src in VM.items():
            if src == name:
                np.savez_compressed(os.path.join(SRC, f"{vm}_vm.npz"), **{
                    "item|" + m: np.array([[*p, *n, *uv] for tri in tl for p, n, uv in tri], np.float32) for m, tl in tris.items()})
        groups.append((name, obs))
    if os.environ.get("NYRP_PREVIEW"):
        render_preview(os.environ["NYRP_PREVIEW"], groups)


if __name__ == "__main__":
    main()
