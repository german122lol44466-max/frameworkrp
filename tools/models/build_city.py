"""Городские объекты New-York Roleplay (Blender / bpy) -> content/models/nyrp/city/*.mdl.

Улица: hydrant (гидрант), newsbox (газетный автомат), parkingmeter (паркомат), usps_box (синий почтовый ящик),
       hotdog_cart (тележка хот-догов), trash_basket (урна-корзина), payphone (таксофон), bus_stop (знак остановки).
Службы: extinguisher (огнетушитель), handcuffs (наручники), defib (дефибриллятор), terminal (компьютер службы),
        hospital_bed (больничная койка).
Работа: van (грузовой фургон), job_sign (табличка «точка работы»).
Размеры — реальные: 1 м ≈ 39 ед. Source. Ось +X — «лицо» объекта, +Z — вверх, основание в z = 0.

python3 tools/models/build_city.py [имя ...]
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_props as bp  # noqa: E402
import textures  # noqa: E402

GM = bp.GM
MATDIR = os.path.join(GM, "content", "materials", "models", "nyrp", "city")
OUT = os.path.join(GM, "content", "models", "nyrp", "city")
M = 39.0  # единиц в метре


def paint(color, S=128, seed=1, chips=0.0):
    img = bp.solid(color, S, 0.05, seed, 1).astype(np.float32)
    if chips:
        rng = np.random.default_rng(seed)
        mask = rng.random((S, S)) < chips
        img[mask] = img[mask] * 0.55 + 60
    return np.clip(img, 0, 255).astype(np.uint8)


def label(bg, lines, S=512, fg=(255, 255, 255), sizes=None, border=None):
    im = Image.new("RGB", (S, S), bg)
    d = ImageDraw.Draw(im)
    if border:
        d.rectangle([12, 12, S - 12, S - 12], outline=border, width=10)
    sizes = sizes or [int(S * 0.16)] * len(lines)
    y = S * 0.5 - sum(sizes) * 0.6
    for t, sz in zip(lines, sizes):
        f = bp.font("Oswald_600SemiBold.ttf", sz)
        w = d.textlength(t, font=f)
        d.text(((S - w) / 2, y), t, font=f, fill=fg)
        y += sz * 1.2
    return np.array(im)


def tex_newsbox():
    im = Image.fromarray(label((200, 30, 40), [], 512))
    d = ImageDraw.Draw(im)
    d.rectangle([40, 150, 472, 470], fill=(30, 34, 40), outline=(230, 230, 230), width=8)   # окошко с газетой
    d.rectangle([70, 180, 442, 440], fill=(225, 222, 210))
    f = bp.font("Oswald_600SemiBold.ttf", 46)
    d.text((95, 195), "NEW YORK", font=f, fill=(20, 20, 20))
    d.text((95, 250), "DAILY NEWS", font=f, fill=(20, 20, 20))
    for k in range(6):
        d.rectangle([95, 320 + k * 18, 420, 328 + k * 18], fill=(120, 120, 120))
    d.text((120, 40), "DAILY NEWS", font=bp.font("Oswald_600SemiBold.ttf", 78), fill=(255, 255, 255))
    return np.array(im)


def tex_meter():
    im = Image.fromarray(label((50, 54, 60), [], 256))
    d = ImageDraw.Draw(im)
    d.rectangle([40, 30, 216, 120], fill=(30, 60, 40), outline=(10, 10, 10), width=6)
    d.text((60, 45), "PARK", font=bp.font("Oswald_600SemiBold.ttf", 52), fill=(140, 230, 140))
    d.text((60, 150), "NYC DOT", font=bp.font("Oswald_600SemiBold.ttf", 34), fill=(230, 230, 230))
    d.ellipse([100, 200, 156, 240], fill=(20, 20, 20))
    return np.array(im)


def tex_usps():
    im = Image.fromarray(paint((32, 70, 150), 512, 5))
    d = ImageDraw.Draw(im)
    f = bp.font("Oswald_600SemiBold.ttf", 70)
    d.text((95, 70), "U.S. MAIL", font=f, fill=(255, 255, 255))
    d.rectangle([60, 200, 452, 230], fill=(220, 220, 225))
    d.polygon([(256, 270), (330, 330), (256, 390), (182, 330)], fill=(220, 40, 40))
    d.text((150, 420), "UNITED STATES POSTAL SERVICE", font=bp.font("Manrope_800ExtraBold.ttf", 18), fill=(255, 255, 255))
    return np.array(im)


def tex_hotdog():
    im = Image.fromarray(paint((230, 230, 225), 512, 7))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 512, 120], fill=(30, 90, 170))
    d.text((70, 10), "HOT DOGS", font=bp.font("Oswald_600SemiBold.ttf", 92), fill=(255, 220, 40))
    d.text((40, 170), "HOT DOG  $3", font=bp.font("Oswald_600SemiBold.ttf", 56), fill=(200, 40, 40))
    d.text((40, 250), "PRETZEL  $2", font=bp.font("Oswald_600SemiBold.ttf", 56), fill=(200, 40, 40))
    d.text((40, 330), "SODA     $1", font=bp.font("Oswald_600SemiBold.ttf", 56), fill=(200, 40, 40))
    d.rectangle([0, 440, 512, 512], fill=(30, 90, 170))
    return np.array(im)


def tex_umbrella():
    S = 256
    yy, xx = np.mgrid[0:S, 0:S] / S
    stripes = ((xx * 8).astype(int) % 2 == 0)
    img = np.zeros((S, S, 3), np.uint8)
    img[stripes] = (230, 50, 40)
    img[~stripes] = (245, 210, 60)
    return img


def tex_wire():
    S = 128
    img = np.full((S, S, 3), (30, 70, 40), np.uint8)
    img[::8, :] = (90, 140, 95)
    img[:, ::8] = (90, 140, 95)
    return img


def tex_payphone():
    im = Image.fromarray(paint((170, 172, 178), 512, 9))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 512, 90], fill=(30, 40, 60))
    d.text((150, 5), "PHONE", font=bp.font("Oswald_600SemiBold.ttf", 70), fill=(255, 255, 255))
    for r in range(4):
        for c in range(3):
            x, y = 170 + c * 60, 200 + r * 60
            d.rectangle([x, y, x + 46, y + 46], fill=(230, 230, 230), outline=(60, 60, 60), width=3)
            d.text((x + 12, y + 2), "123456789*0#"[r * 3 + c], font=bp.font("Oswald_600SemiBold.ttf", 34), fill=(20, 20, 20))
    d.rectangle([150, 120, 360, 170], fill=(20, 40, 30))
    d.text((170, 125), "911 FREE", font=bp.font("Oswald_600SemiBold.ttf", 34), fill=(120, 230, 120))
    return np.array(im)


def tex_busstop():
    im = Image.fromarray(label((20, 70, 160), [], 256))
    d = ImageDraw.Draw(im)
    d.ellipse([20, 20, 236, 236], fill=(255, 255, 255))
    d.ellipse([34, 34, 222, 222], fill=(20, 70, 160))
    d.text((70, 60), "M15", font=bp.font("Oswald_600SemiBold.ttf", 76), fill=(255, 255, 255))
    d.text((66, 150), "BUS STOP", font=bp.font("Oswald_600SemiBold.ttf", 30), fill=(255, 255, 255))
    return np.array(im)


def tex_terminal():
    im = Image.new("RGB", (512, 512), (12, 24, 48))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 512, 60], fill=(30, 70, 150))
    d.text((20, 6), "NYC CITY TERMINAL", font=bp.font("Oswald_600SemiBold.ttf", 40), fill=(255, 255, 255))
    for k in range(10):
        d.rectangle([30, 90 + k * 38, 30 + (k * 53) % 400 + 60, 106 + k * 38], fill=(70, 120, 200))
    return np.array(im)


def tex_van():
    im = Image.fromarray(paint((236, 236, 238), 512, 11))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 300, 512, 360], fill=(247, 198, 0))
    d.text((40, 120), "NY DELIVERY", font=bp.font("Oswald_600SemiBold.ttf", 92), fill=(30, 40, 70))
    d.text((40, 230), "Brooklyn · Queens · Manhattan", font=bp.font("Manrope_800ExtraBold.ttf", 28), fill=(60, 60, 70))
    return np.array(im)


def tex_glass():
    return bp.solid((30, 40, 55), 64, 0.05, 13, 1)


def tex_tire():
    return bp.solid((22, 22, 24), 64, 0.08, 14, 0)


def tex_jobsign():
    im = Image.fromarray(paint((247, 198, 0), 512, 15))
    d = ImageDraw.Draw(im)
    d.rectangle([24, 24, 488, 488], outline=(20, 20, 20), width=14)
    d.text((80, 90), "РАБОТА", font=bp.font("Oswald_600SemiBold.ttf", 110), fill=(20, 20, 20))
    d.text((90, 250), "NOW HIRING", font=bp.font("Oswald_600SemiBold.ttf", 70), fill=(20, 20, 20))
    d.text((120, 360), "E — начать", font=bp.font("Manrope_800ExtraBold.ttf", 44), fill=(20, 20, 20))
    return np.array(im)


def tex_sheet():
    return bp.solid((236, 238, 242), 128, 0.03, 16, 2)


def tex_defib():
    im = Image.fromarray(paint((240, 120, 30), 256, 17))
    d = ImageDraw.Draw(im)
    d.rectangle([30, 30, 226, 110], fill=(20, 20, 20))
    d.line([40, 70, 80, 70, 95, 40, 115, 100, 130, 70, 216, 70], fill=(80, 240, 120), width=5)
    d.text((60, 140), "AED", font=bp.font("Oswald_600SemiBold.ttf", 70), fill=(255, 255, 255))
    return np.array(im)


NEW_MATS = {
    "c_red": (lambda: paint((190, 30, 30), 128, 21, 0.03), True),
    "c_silver": (lambda: bp.brushed((175, 178, 184), 128, 0.08, 22), True),
    "c_dark": (lambda: paint((40, 42, 46), 64, 23), False),
    "c_newsbox": (tex_newsbox, False),
    "c_meter": (tex_meter, True),
    "c_usps": (tex_usps, False),
    "c_blue": (lambda: paint((32, 70, 150), 128, 24), False),
    "c_hotdog": (tex_hotdog, True),
    "c_umbrella": (tex_umbrella, False),
    "c_wire": (tex_wire, False),
    "c_payphone": (tex_payphone, True),
    "c_busstop": (tex_busstop, False),
    "c_terminal": (tex_terminal, False),
    "c_van": (tex_van, True),
    "c_white": (lambda: paint((236, 236, 238), 128, 25), True),
    "c_glass": (tex_glass, True),
    "c_tire": (tex_tire, False),
    "c_jobsign": (tex_jobsign, False),
    "c_sheet": (tex_sheet, False),
    "c_defib": (tex_defib, False),
    "c_orange": (lambda: paint((240, 120, 30), 64, 26), False),
}


def build_textures():
    os.makedirs(MATDIR, exist_ok=True)
    for name, (fn, phong) in NEW_MATS.items():
        img = fn()
        textures.write_vtf(os.path.join(MATDIR, name + ".vtf"), img[..., :3])
        textures.write_vmt(os.path.join(MATDIR, name + ".vmt"), "models/nyrp/city/" + name, phong, 16, 1.2)
    # материалы Blender ищут текстуры в bp.MATS
    bp.MATS.update(NEW_MATS)
    print("city textures ok")


B, C = bp.box, bp.cyl


def m_hydrant():           # ~75 см
    return [C("base", 7, 2, (0, 0, 1), "c_red", 16, cap="c_red"),
            C("body", 5, 20, (0, 0, 12), "c_red", 16, cap="c_red"),
            C("ring", 5.8, 1.6, (0, 0, 21.5), "c_red", 16, cap="c_red"),
            C("cap", 5, 4, (0, 0, 24.3), "c_red", 16, r2=2.6, cap="c_red"),
            C("nut", 1.4, 2, (0, 0, 27.2), "c_silver", 6, cap="c_silver"),
            C("noz1", 2.2, 4, (0, 6.5, 15), "c_silver", 12, rot=(90, 0, 0), cap="c_silver"),
            C("noz2", 2.2, 4, (0, -6.5, 15), "c_silver", 12, rot=(90, 0, 0), cap="c_silver"),
            C("noz3", 2.8, 4, (6.5, 0, 14), "c_silver", 12, rot=(0, 90, 0), cap="c_silver")]


def m_newsbox():           # 50 × 45 × 105 см
    return [B("legs", (16, 14, 14), (0, 0, 7), "c_dark"),
            B("body", (18, 20, 26), (0, 0, 27), {"+x": "c_newsbox", "*": "c_red"}, fit=("+x",)),
            B("top", (19, 21, 2), (0, 0, 41), "c_red")]


def m_parkingmeter():      # 1.3 м
    return [C("pole", 1.1, 40, (0, 0, 20), "c_dark", 10, cap="c_dark"),
            B("head", (5, 6.5, 11), (0, 0, 45), {"+x": "c_meter", "*": "c_dark"}, fit=("+x",)),
            C("dome", 3.2, 2, (0, 0, 51.5), "c_dark", 12, r2=2.2, cap="c_dark")]


def m_usps():              # 55 × 50 × 125 см
    return [B("legs", (18, 16, 8), (0, 0, 4), "c_blue"),
            B("body", (19.5, 21.5, 36), (0, 0, 26), {"+x": "c_usps", "-x": "c_usps", "*": "c_blue"}, fit=("+x", "-x")),
            C("dome", 9.75, 21.5, (0, 0, 44), "c_blue", 20, rot=(90, 0, 0), cap="c_blue"),
            B("slot", (0.6, 10, 1.4), (10.8, 0, 40), "c_dark")]


def m_hotdog():            # тележка 1.6 × 0.8 м + зонт
    obs = [B("cart", (62, 30, 30), (0, 0, 27), {"+y": "c_hotdog", "-y": "c_hotdog", "*": "c_silver"}, fit=("+y", "-y")),
           B("lid", (64, 32, 2), (0, 0, 43), "c_silver"),
           C("pole", 0.8, 60, (0, 0, 74), "c_silver", 8, cap="c_silver"),
           C("umbrella", 34, 12, (0, 0, 104), "c_umbrella", 16, r2=0.5, cap="c_umbrella"),
           B("handle", (2, 26, 2), (-34, 0, 40), "c_silver")]
    for x in (-22, 22):
        obs.append(C(f"wheel{x}", 7, 3, (x, 16, 7), "c_tire", 14, rot=(90, 0, 0), cap="c_tire"))
        obs.append(C(f"wheel{x}b", 7, 3, (x, -16, 7), "c_tire", 14, rot=(90, 0, 0), cap="c_tire"))
    return obs


def m_trash():             # урна-корзина d 60 см × 80 см
    return [C("basket", 11.5, 30, (0, 0, 15), "c_wire", 18, r2=12.5, cap="c_dark"),
            bp.torus("rim", 12.5, 0.6, (0, 0, 30), "c_dark")]


def m_payphone():          # стойка 2 м
    return [B("post", (5, 6, 60), (-2, 0, 30), "c_silver"),
            B("box", (8, 18, 28), (2.5, 0, 66), {"+x": "c_payphone", "*": "c_silver"}, fit=("+x",)),
            B("hood", (14, 22, 2), (3, 0, 81), "c_dark"),
            B("handset", (2.2, 2.4, 9), (7.3, 7.2, 62), "c_dark")]


def m_busstop():           # знак 2.5 м
    return [C("pole", 1.2, 90, (0, 0, 45), "c_silver", 10, cap="c_silver"),
            B("sign", (0.6, 20, 20), (1.2, 0, 86), {"+x": "c_busstop", "-x": "c_busstop", "*": "c_blue"}, fit=("+x", "-x"))]


def m_extinguisher():      # Ø 15 × 50 см
    return [C("tank", 2.9, 16, (0, 0, 8), "c_red", 14, cap="c_red"),
            C("top", 2.9, 1.6, (0, 0, 16.8), "c_red", 14, r2=1.4, cap="c_red"),
            B("valve", (1.4, 1.4, 2.6), (0, 0, 18.6), "c_dark"),
            B("lever", (4.6, 0.8, 0.5), (1.5, 0, 20.2), "c_silver"),
            C("hose", 0.45, 9, (2.2, 0, 13.5), "c_dark", 8, rot=(0, 15, 0), cap="c_dark"),
            C("nozzle", 0.7, 2, (3.4, 0, 8.5), "c_dark", 8, cap="c_dark")]


def m_handcuffs():         # браслеты Ø 7 см
    return [bp.torus("cuffA", 1.6, 0.25, (0, -1.9, 0), "c_silver", rot=(90, 0, 0)),
            bp.torus("cuffB", 1.6, 0.25, (0, 1.9, 0), "c_silver", rot=(90, 0, 0)),
            B("chain", (0.3, 0.9, 0.3), (0, 0, 0), "c_silver")]


def m_defib():             # кейс 30 × 25 × 12 см + электроды
    return [B("case", (6, 12, 10), (0, 0, 5), {"+x": "c_defib", "*": "c_orange"}, fit=("+x",)),
            B("handle", (2, 6, 1), (0, 0, 10.6), "c_dark"),
            B("padA", (1.2, 3, 4), (0, -7.6, 4), "c_dark"),
            B("padB", (1.2, 3, 4), (0, 7.6, 4), "c_dark")]


def m_terminal():          # монитор на столе
    return [B("desk", (24, 40, 2), (0, 0, 29), "c_dark"),
            B("leg1", (22, 2, 29), (0, -18, 14.5), "c_dark"),
            B("leg2", (22, 2, 29), (0, 18, 14.5), "c_dark"),
            B("stand", (3, 3, 4), (-4, 0, 32), "c_dark"),
            B("monitor", (1.4, 20, 13), (-4, 0, 40.5), {"+x": "c_terminal", "*": "c_dark"}, fit=("+x",)),
            B("keyboard", (5, 14, 0.8), (5, 0, 30.4), "c_dark"),
            B("tower", (16, 6, 15), (0, 13, 37.5), "c_dark")]


def m_bed():               # койка 2 × 0.9 м
    obs = [B("frame", (78, 35, 3), (0, 0, 19), "c_silver"),
           B("mattress", (76, 33, 5), (0, 0, 23), "c_sheet"),
           B("pillow", (12, 22, 3), (-30, 0, 27), "c_sheet"),
           B("headboard", (2, 35, 16), (-39, 0, 28), "c_silver")]
    for x in (-36, 36):
        for y in (-15, 15):
            obs.append(C(f"leg{x}{y}", 0.8, 18, (x, y, 9), "c_silver", 8, cap="c_silver"))
    return obs


def m_van():               # 5.2 × 2.0 × 2.3 м
    obs = [B("cargo", (140, 78, 76), (-25, 0, 52), {"+y": "c_van", "-y": "c_van", "*": "c_white"}, fit=("+y", "-y")),
           B("cab", (58, 76, 52), (74, 0, 40), "c_white"),
           B("hoodtop", (30, 76, 18), (96, 0, 31), "c_white"),
           B("windshield", (2, 66, 26), (102, 0, 52), "c_glass", rot=(0, -25, 0)),
           B("sidewinL", (30, 0.6, 18), (76, 38.3, 54), "c_glass"),
           B("sidewinR", (30, 0.6, 18), (76, -38.3, 54), "c_glass"),
           B("bumper", (4, 80, 8), (112, 0, 17), "c_dark"),
           B("rearbumper", (4, 80, 8), (-96, 0, 17), "c_dark")]
    for x in (-70, 72):
        for y in (-35, 35):
            obs.append(C(f"w{x}{y}", 13, 9, (x, y, 13), "c_tire", 16, rot=(90, 0, 0), cap="c_silver"))
    return obs


def m_jobsign():           # стойка-«домик» 1.1 м
    return [B("boardA", (1.2, 26, 40), (4.5, 0, 22), {"+x": "c_jobsign", "-x": "c_jobsign", "*": "c_dark"}, fit=("+x", "-x"), rot=(0, -12, 0)),
            B("boardB", (1.2, 26, 40), (-4.5, 0, 22), {"+x": "c_jobsign", "-x": "c_jobsign", "*": "c_dark"}, fit=("+x", "-x"), rot=(0, 12, 0))]


MODELS = {
    "hydrant": (m_hydrant, "metal", 200), "newsbox": (m_newsbox, "metal", 60), "parkingmeter": (m_parkingmeter, "metal", 80),
    "usps_box": (m_usps, "metal", 120), "hotdog_cart": (m_hotdog, "metal", 120), "trash_basket": (m_trash, "metal", 30),
    "payphone": (m_payphone, "metal", 150), "bus_stop": (m_busstop, "metal", 60),
    "extinguisher": (m_extinguisher, "metal", 8), "handcuffs": (m_handcuffs, "metal", 0.5), "defib": (m_defib, "plastic", 4),
    "terminal": (m_terminal, "wood", 40), "hospital_bed": (m_bed, "metal", 80),
    "van": (m_van, "metal", 2000), "job_sign": (m_jobsign, "wood", 10),
}
VM = {"extinguisher": "extinguisher", "handcuffs": "handcuffs", "defib": "defib"}


def main():
    import bpy
    import mdlc
    only = set(sys.argv[1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bp.build_textures()
    build_textures()
    groups = []
    for name, (fn, surf, mass) in MODELS.items():
        if only and name not in only:
            continue
        obs = fn()
        tris = bp.collect(obs)
        mdlc.compile_model(OUT, name, f"nyrp/city/{name}.mdl", tris, "models/nyrp/city", surf, mass)
        print(name, "triangles:", sum(len(v) for v in tris.values()))
        for vm, src in VM.items():
            if src == name:
                np.savez_compressed(os.path.join(bp.SRC, f"{vm}_vm.npz"), **{
                    "item|" + m: np.array([[*p, *n, *uv] for tri in tl for p, n, uv in tri], np.float32) for m, tl in tris.items()})
        groups.append((name, obs))
    if os.environ.get("NYRP_PREVIEW"):
        bp.render_preview(os.environ["NYRP_PREVIEW"], groups)


if __name__ == "__main__":
    main()
