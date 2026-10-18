"""Кадры интро «Белая тишина» — рисуются кодом и пишутся в content/materials/whitesilence/intro.

    python3 tools/content/intro_art.py [сцена ...]     (без аргументов — все)

Сцены:
  arctic  — ледяная пустошь в метели, отряд МОГ «Дельта-14» (слои: фон, силуэты, «глаза», передний сугроб)
  dead    — тело бойца в снегу: кровь на перчатке и на снегу, рация рядом
  heli    — салон вертолёта: бойцы в арктическом камуфляже, открытая дверь, внизу тундра (лента для прокрутки)
  banner  — знак Фонда
  fx      — служебные текстуры: снежинка, туман, зерно, виньетка
Каждый кадр 2560x1440 (запас под наезд камеры), плюс размытая копия *_blur для эффекта проявления.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paint import (W, H, Sil, blend, canvas_grain, fbm, gaussian, limb, mask_below, painterly, ridge_line,  # noqa: E402
                   soldier, soldier_back, soldier_seated_front, stretched_fbm, to_img, vgrad)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "content", "materials", "whitesilence", "intro")
PREVIEW = os.environ.get("WS_PREVIEW")  # папка для превью-композиций (не идут в игру)


def save_jpg(arr, name, q=90):
    os.makedirs(OUT, exist_ok=True)
    img = to_img(arr)
    img.save(os.path.join(OUT, name + ".jpg"), quality=q, optimize=True, progressive=False)
    # размытая копия — кадр «проявляется» из неё
    small = img.resize((640, 360), Image.LANCZOS).filter(ImageFilter.GaussianBlur(5))
    small.save(os.path.join(OUT, name + "_blur.jpg"), quality=85)
    return img


def save_png(rgb, alpha, name, size=None):
    os.makedirs(OUT, exist_ok=True)
    a = np.clip(alpha * 255, 0, 255).astype(np.uint8)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), a]), "RGBA")
    if size:
        img = img.resize(size, Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"), optimize=True)
    return img


def preview(img, name):
    if PREVIEW:
        os.makedirs(PREVIEW, exist_ok=True)
        img.convert("RGB").resize((1280, 720), Image.LANCZOS).save(os.path.join(PREVIEW, name + ".jpg"), quality=88)


def fill_out(rgb, alpha, r=6):
    """Растягивает цвета силуэта за его края, чтобы мазки по краю не тянули цвет фона."""
    out = np.broadcast_to((rgb * alpha[..., None]).sum((0, 1)) / max(alpha.sum(), 1.0), rgb.shape).copy()
    for rr in (r * 9, r * 3, r):
        num = gaussian(rgb * alpha[..., None], rr)
        den = gaussian(alpha, rr)
        ok = den > 0.03
        out[ok] = num[ok] / den[ok][:, None]
    return blend(out, rgb, np.clip(alpha * 2, 0, 1))


# ================================================================ сцена 1: арктика, отряд

FOG = np.array([150, 163, 178], np.float32)


def arctic():
    rnd = random.Random(14)
    yy = np.arange(H, dtype=np.float32)[:, None]

    # небо: тяжёлые снеговые тучи, светлее у горизонта; слева — тусклое пятно низкого солнца
    sky = vgrad(H, W, [(0, (38, 46, 60)), (0.35, (78, 90, 107)), (0.56, (150, 162, 176)), (1, (170, 180, 192))])
    clouds = stretched_fbm(W, H, 90, 5, 3, sx=5)
    sky += (clouds[..., None] - 0.5) * np.array([60, 62, 66], np.float32) * (1 - yy / H)[..., None]
    gx = np.arange(W, dtype=np.float32)[None, :]
    sun = np.exp(-(((gx - W * 0.27) / 520) ** 2 + ((yy - H * 0.47) / 260) ** 2))
    sky += sun[..., None] * np.array([46, 44, 40], np.float32)
    img = sky

    # дальние горы в дымке
    far = ridge_line(W, H * 0.545, 210, 700, 6, 21, sharp=1.4)
    m = mask_below(W, H, far)
    rock = fbm(W, H, 40, 4, 5)
    col = np.array([104, 117, 134], np.float32) + (rock[..., None] - 0.5) * 30
    # снежные гребни светлее
    snow = np.clip((rock - 0.45) * 3, 0, 1) * np.clip(1 - (yy - far[None, :]) / 140, 0, 1)
    col = blend(col, np.array([160, 172, 186], np.float32), snow * 0.7)
    img = blend(img, col, m * 0.85)

    # средний план: торосы и ледяные гряды
    mid = ridge_line(W, H * 0.655, 95, 380, 6, 33, sharp=2.0)
    m2 = mask_below(W, H, mid)
    n2 = fbm(W, H, 18, 4, 9)
    depth = np.clip((yy - mid[None, :]) / 120, 0, 1)
    ice = np.array([118, 134, 152], np.float32) + (n2[..., None] - 0.5) * 34
    ice = blend(np.array([196, 205, 214], np.float32) + (n2[..., None] - 0.5) * 18, ice, np.clip(depth * 1.6, 0, 1) * 0.6)
    img = blend(img, ice, m2)

    # снежное поле: заструги (вытянутые волны снега), синие тени
    ground_y = ridge_line(W, H * 0.70, 26, 600, 4, 41)
    m3 = mask_below(W, H, ground_y)
    sas = stretched_fbm(W, H, 26, 5, 12, sx=7, sy=1)
    t = np.clip((yy - H * 0.70) / (H * 0.30), 0, 1)
    field = vgrad(H, W, [(0, (180, 190, 202)), (0.7, (190, 199, 210)), (1, (172, 184, 199))])
    field += (sas[..., None] - 0.5) * np.array([44, 40, 30], np.float32) * (0.4 + t[..., None])
    img = blend(img, field, m3)

    # следы, ведущие к отряду
    trail = Image.new("L", (W, H), 0)
    td = ImageDraw.Draw(trail)
    for i in range(70):
        k = i / 70
        x = W * (0.86 - k * 0.32) + math.sin(k * 7) * 30
        y = H * (1.02 - k * 0.27)
        s = 13 * (1 - k) + 3
        td.ellipse((x - s * 1.6, y - s * 0.5, x + s * 1.6, y + s * 0.5), fill=130)
    trail = np.asarray(trail.filter(ImageFilter.GaussianBlur(3)), np.float32) / 255.0
    img = blend(img, np.array([120, 136, 160], np.float32), trail * 0.55)

    # метель: полосы позёмки и общая дымка, сильнее у горизонта
    haze = np.exp(-((yy - H * 0.62) / 260) ** 2)
    streak = stretched_fbm(W, H, 40, 4, 77, sx=12)
    img = blend(img, FOG, np.clip(haze * 0.38 + (streak - 0.5) * 0.35 * haze, 0, 0.75))
    bg = painterly(img, seed=101)
    bg = canvas_grain(bg, 5, 2.5)

    # ---- отряд: шесть силуэтов колонной, ближний крупнее
    sil = Sil(W, H)
    eyes = []
    squad = [  # x, ступни y, рост, вид, поза, наклон головы, лицом
        (0.430, 0.752, 270, "side", "walk", 0.0, 1),
        (0.515, 0.738, 250, "side", "stand", 0.12, -1),
        (0.585, 0.728, 232, "back", None, 0.0, 1),
        (0.648, 0.721, 214, "side", "walk", -0.04, 1),
        (0.700, 0.716, 200, "side", "stand", 0.48, -1),  # голова склонена неестественно
        (0.742, 0.711, 186, "back", None, 0.0, 1),
    ]
    for i, (x, y, h, kind, pose, tilt, face) in enumerate(squad):
        if kind == "back":
            soldier_back(sil, W * x, H * y, h, rnd, tilt=tilt, arm_drop=(i == 2))
        else:
            e = soldier(sil, W * x, H * y, h, face=face, pose=pose, rnd=rnd, tilt=tilt, antenna=(i == 0))
            eyes.append((e[0], e[1], h, face))
    a = sil.mask(blur=1.1)
    # ближние темнее, дальние тонут в метели; снизу лёгкая подсветка от снега
    dist = np.interp(np.arange(W), [W * 0.42, W * 0.78], [0.0, 1.0]).astype(np.float32)[None, :]
    base = np.array([16, 19, 24], np.float32)
    srgb = np.broadcast_to(base, (H, W, 3)).copy()
    srgb = blend(srgb, FOG * 0.62, np.clip(dist * 0.42, 0, 1) * np.ones((H, W), np.float32))
    rim = np.clip((yy - H * 0.55) / (H * 0.2), 0, 1)
    srgb += rim[..., None] * np.array([6, 8, 12], np.float32)
    srgb = fill_out(srgb, a)
    sp = painterly(srgb, alpha=a, seed=202, passes=((7, 1.2), (3, 2.0)), jitter=4)
    # тени под ногами
    shadow = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(shadow)
    for x, y, h, *_ in squad:
        sd.ellipse((W * x - h * 0.3, H * y - h * 0.03, W * x + h * 0.4, H * y + h * 0.035), fill=150)
    sh = np.asarray(shadow.filter(ImageFilter.GaussianBlur(10)), np.float32) / 255.0
    bg = blend(bg, np.array([96, 110, 134], np.float32), sh * 0.5)

    soldiers = save_png(sp, a, "arctic_squad")
    bgimg = save_jpg(bg, "arctic_bg")

    # ---- «глаза»: еле заметные бледные отблески в очках (проявляются во второй сцене)
    gl = Image.new("L", (W, H), 0)
    gd = ImageDraw.Draw(gl)
    for x, y, h, face in eyes:
        r = h * 0.012
        gd.ellipse((x - r, y - r * 0.6, x + r, y + r * 0.6), fill=255)
    glow = np.asarray(gl.filter(ImageFilter.GaussianBlur(2)), np.float32) / 255.0
    halo = np.asarray(gl.filter(ImageFilter.GaussianBlur(10)), np.float32) / 255.0
    ga = np.clip(glow * 1.0 + halo * 1.6, 0, 1)
    save_png(np.broadcast_to(np.array([214, 236, 255], np.float32), (H, W, 3)), ga, "arctic_eyes")

    # ---- передний план: сугроб у нижнего края (для параллакса)
    xs = np.arange(W, dtype=np.float32)
    top = H * 0.935 + np.sin(xs / 310) * 40 + np.sin(xs / 97 + 1) * 12 + (fbm(W, 1, 80, 3, 61)[0] - 0.5) * 60
    fm = mask_below(W, H, top)
    fm = gaussian(fm, 6)
    fn = fbm(W, H, 20, 4, 63)
    frgb = np.array([198, 207, 218], np.float32) + (fn[..., None] - 0.5) * 30
    frgb = blend(frgb, np.array([150, 164, 186], np.float32), np.clip((yy - top[None, :]) / 140, 0, 1) * 0.6)
    frgb = painterly(fill_out(frgb, fm), alpha=fm, seed=303, passes=((16, 1.0), (7, 1.5)))
    fore = save_png(frgb, fm, "arctic_fore")

    if PREVIEW:
        comp = bgimg.convert("RGBA")
        comp.alpha_composite(soldiers)
        comp.alpha_composite(fore)
        preview(comp, "arctic")
        crop = comp.crop((int(W * 0.45), int(H * 0.38), int(W * 0.85), int(H * 0.78)))
        e = Image.open(os.path.join(OUT, "arctic_eyes.png"))
        crop.alpha_composite(e.crop((int(W * 0.45), int(H * 0.38), int(W * 0.85), int(H * 0.78))))
        preview(crop, "arctic_close")


# ================================================================ сцена 3: погибший боец

def shade_height(hgt, light=(-0.6, -0.8), k=900.0):
    gy, gx = np.gradient(hgt)
    return np.clip(0.5 - (gx * light[0] + gy * light[1]) * k, 0, 1)


def blob_mask(cx, cy, rx, ry, seed, rough=0.45, cell=40):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    n = fbm(W, H, cell, 4, seed)
    return np.clip((1.0 - d + (n - 0.5) * rough * 2) * 6, 0, 1)


RADIO_LED = (0.0, 0.0)  # заполняется в dead(): нормированные координаты лампочки рации


def dead():
    global RADIO_LED
    rnd = random.Random(7)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

    # снег: рельеф с мягкими тенями, холодный свет сверху-слева
    hgt = fbm(W, H, 420, 3, 70) + stretched_fbm(W, H, 120, 2, 71, sx=4) * 0.05
    sh = gaussian(shade_height(hgt, k=420), 6)
    img = np.array([150, 162, 182], np.float32) + (sh[..., None] - 0.5) * np.array([62, 58, 46], np.float32)
    img += (fbm(W, H, 6, 2, 72)[..., None] - 0.5) * 8
    # свет падает пятном в центр, края кадра в сумерках
    light = np.exp(-(((xx - W * 0.52) / (W * 0.55)) ** 2 + ((yy - H * 0.55) / (H * 0.6)) ** 2))
    img *= (0.62 + 0.38 * light)[..., None]
    # мелкая рябь, надутая ветром, и редкие искры наста
    rip = stretched_fbm(W, H, 14, 3, 73, sx=6)
    img += (rip[..., None] - 0.5) * 22
    sparkle = np.clip((np.random.default_rng(74).random((H, W)) - 0.9985) * 700, 0, 1).astype(np.float32)
    img += gaussian(sparkle, 0.8)[..., None] * 150
    # тень от тела/предметов (мягкая, синяя)
    shadow = np.zeros((H, W), np.float32)

    # ---- кровь в снегу: пятно под рукой, впитавшиеся розовые края, брызги
    pool = blob_mask(1290, 905, 330, 150, 80, rough=0.6, cell=55)
    core = blob_mask(1270, 900, 220, 95, 81, rough=0.5, cell=40)
    soak = gaussian(pool, 26)
    img = blend(img, np.array([150, 82, 96], np.float32), np.clip(soak * 1.1, 0, 1) * 0.5)
    img = blend(img, np.array([108, 18, 26], np.float32), pool * 0.85)
    img = blend(img, np.array([72, 6, 12], np.float32), core * 0.85)
    drops = Image.new("L", (W, H), 0)
    dd = ImageDraw.Draw(drops)
    for _ in range(75):
        a = rnd.uniform(-0.9, 2.4)
        r = rnd.uniform(240, 700) ** 1.0
        x, y = 1290 + math.cos(a) * r * 1.4, 900 + math.sin(a) * r * 0.55
        sz = rnd.uniform(1.5, 1.0 + 12 * (1 - r / 760)) * rnd.choice((1, 1, 1, 1.8))
        el = rnd.uniform(1.2, 2.8)  # капли вытянуты от центра
        for k in range(4):  # капля-«головастик»: крупная голова и тающий хвост от центра
            q = sz * el * k * 0.7
            e = sz * (1 - k * 0.22)
            cx, cy = x + math.cos(a) * q, y + math.sin(a) * q * 0.5
            dd.ellipse((cx - e, cy - e * 0.7, cx + e, cy + e * 0.7), fill=255)
        if rnd.random() < 0.3:  # мелкие брызги-спутники
            for _ in range(3):
                q = rnd.uniform(4, 22)
                e = rnd.uniform(0.6, 2.0)
                dd.ellipse((x + math.cos(a) * q - e, y + math.sin(a) * q * 0.5 - e, x + math.cos(a) * q + e, y + math.sin(a) * q * 0.5 + e), fill=230)
    dm = np.asarray(drops.filter(ImageFilter.GaussianBlur(1.6)), np.float32) / 255.0
    img = blend(img, np.array([150, 70, 82], np.float32), gaussian(dm, 9) * 0.6)
    img = blend(img, np.array([92, 10, 16], np.float32), dm * 0.92)
    # кровавый след: рука тянулась к рации
    smear = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(smear)
    sd.line([(1420, 840), (1530, 800), (1620, 780)], fill=200, width=34, joint="curve")
    smear = np.asarray(smear.filter(ImageFilter.GaussianBlur(9)), np.float32) / 255.0
    smear *= np.clip(fbm(W, H, 14, 3, 83) * 1.8 - 0.3, 0, 1)
    img = blend(img, np.array([110, 18, 24], np.float32), smear * 0.8)

    # ---- рукав: от нижнего левого угла к запястью
    s = Sil(W, H)
    limb(s, (-260, 1640), (700, 1060), 430, 300)
    limb(s, (700, 1060), (1040, 870), 300, 220)
    sleeve = s.mask(blur=1.5)
    cuff = Sil(W, H)
    limb(cuff, (980, 905), (1075, 852), 238, 222)
    cm = cuff.mask(blur=1.2)
    folds = stretched_fbm(W, H, 30, 4, 90, sx=1, sy=3)
    along = (xx * 0.5 + yy * 0.86)
    crease = (np.sin(along / 37 + folds * 6) * 0.5 + 0.5)
    sl = np.array([30, 33, 36], np.float32) + (crease[..., None] - 0.5) * 30 + (folds[..., None] - 0.5) * 20
    # освещённая верхняя кромка рукава
    edge_up = gaussian(np.clip(sleeve - np.roll(sleeve, 22, axis=0), 0, 1), 10)
    sl += edge_up[..., None] * np.array([46, 50, 58], np.float32)
    img = blend(img, sl, sleeve)
    img = blend(img, np.array([30, 32, 34], np.float32) + (crease[..., None] - 0.5) * 12, cm)
    shadow = np.maximum(shadow, gaussian(np.roll(np.roll(sleeve, 30, 0), 26, 1), 24))

    # ---- перчатка: ладонь вниз, пальцы чуть подогнуты, тянется вправо
    g = Sil(W, H)
    g.P([(1050, 790), (1170, 742), (1295, 752), (1352, 800), (1345, 880), (1230, 925), (1090, 930), (1040, 880)])
    fingers = [((1300, 765), (1430, 742), (1475, 768)), ((1325, 805), (1462, 800), (1500, 836)),
               ((1320, 845), (1440, 862), (1468, 902)), ((1290, 880), (1385, 912), (1400, 948))]
    for a, b, c in fingers:
        limb(g, a, b, 50, 44)
        limb(g, b, c, 44, 36)
    limb(g, (1130, 760), (1215, 690), 60, 50)
    limb(g, (1215, 690), (1288, 680), 50, 42)
    gm = g.mask(blur=1.2)
    gn = fbm(W, H, 9, 3, 95)
    glove = np.array([24, 24, 27], np.float32) + (gn[..., None] - 0.5) * 18
    # мягкий свет на костяшках
    knuckle = blob_mask(1320, 770, 150, 60, 96, rough=0.3)
    glove += knuckle[..., None] * np.array([34, 36, 42], np.float32) * 0.7
    img = blend(img, glove, gm)
    # кровь на перчатке и запястье: тёмная, с влажными бликами
    gb = blob_mask(1250, 860, 150, 70, 97, rough=0.8, cell=30) * gm
    gb = np.maximum(gb, blob_mask(1040, 885, 60, 45, 98, rough=0.7, cell=25) * np.maximum(cm, gm))
    img = blend(img, np.array([58, 6, 10], np.float32), gb * 0.95)
    spec = np.clip((fbm(W, H, 5, 2, 99) - 0.72) * 9, 0, 1) * gb
    img = blend(img, np.array([210, 120, 120], np.float32), spec * 0.55)
    shadow = np.maximum(shadow, gaussian(np.roll(np.roll(gm, 22, 0), 18, 1), 16) * 0.9)

    # ---- рация: лежит в снегу под углом, наполовину занесена
    rw, rh = 600, 760
    rad = Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rad)
    bx0, by0, bx1, by1 = 210, 250, 390, 690
    rd.line([(260, 260), (250, 20)], fill=(22, 22, 24, 255), width=17)            # антенна
    rd.ellipse((241, 8, 259, 30), fill=(22, 22, 24, 255))
    rd.rounded_rectangle((300, 205, 336, 262), 8, fill=(30, 30, 33, 255))           # ручка громкости
    rd.rounded_rectangle((bx0, by0, bx1, by1), 26, fill=(34, 35, 38, 255))          # корпус
    rd.rounded_rectangle((bx0 + 8, by0 + 8, bx1 - 8, by1 - 8), 22, outline=(52, 54, 58, 255), width=4)
    rd.rounded_rectangle((bx0 + 30, by0 + 50, bx1 - 30, by0 + 120), 6, fill=(30, 52, 44, 255))  # дисплей (погас)
    for i in range(9):                                                              # решётка динамика
        y = by0 + 170 + i * 22
        rd.rounded_rectangle((bx0 + 34, y, bx1 - 34, y + 9), 4, fill=(18, 18, 20, 255))
    rd.rounded_rectangle((bx0 - 16, by0 + 120, bx0 + 2, by0 + 230), 5, fill=(26, 26, 29, 255))  # тангента
    led = (338, 232)
    rd.ellipse((led[0] - 8, led[1] - 8, led[0] + 8, led[1] + 8), fill=(60, 14, 14, 255))
    rad = rad.rotate(-28, resample=Image.BICUBIC, expand=False, center=(300, 470))
    ra = np.asarray(rad, np.float32)
    px, py = 1570, 300
    ang = math.radians(28)
    lx, ly = led[0] - 300, led[1] - 470
    led_pos = (px + 300 + lx * math.cos(ang) - ly * math.sin(ang), py + 470 + lx * math.sin(ang) + ly * math.cos(ang))
    RADIO_LED = (led_pos[0] / W, led_pos[1] / H)
    full = np.zeros((H, W, 4), np.float32)
    full[py:py + rh, px:px + rw] = ra
    rmask = full[..., 3] / 255.0
    rrgb = full[..., :3]
    # блик на корпусе сверху-слева
    hl = gaussian(np.clip(rmask - np.roll(np.roll(rmask, 12, 0), 10, 1), 0, 1), 4)
    rrgb = rrgb + hl[..., None] * 40
    shadow = np.maximum(shadow, gaussian(np.roll(np.roll(rmask, 24, 0), 20, 1), 18) * 0.85)
    img = blend(img, np.array([120, 134, 160], np.float32), shadow * 0.5)
    img = blend(img, rrgb, rmask)

    # ---- снег поверх: занос на рации и рукаве, свежие хлопья
    drift = np.clip((yy - (py + 560 + (xx - px - 300) * 0.55)) / 90, 0, 1) * rmask
    drift = gaussian(drift * np.clip(fbm(W, H, 30, 3, 120) * 2 - 0.4, 0, 1), 6) * 0.85
    snow_on = np.clip(edge_up * 1.6 * np.clip(fbm(W, H, 18, 3, 121) * 2.2 - 0.7, 0, 1), 0, 1)
    flakes = np.clip((fbm(W, H, 3, 2, 122) - 0.74) * 6, 0, 1) * np.maximum(sleeve, np.maximum(gm, rmask))
    # снег на рукаве, у его нижней кромки и у рации — предметы «лежат», а не парят
    low_edge = np.clip(np.roll(sleeve, -26, axis=0) - sleeve, 0, 1)
    low_edge = np.maximum(low_edge, np.clip(np.roll(sleeve, 30, axis=0) - sleeve, 0, 1) * 0.7)
    low_edge = np.maximum(low_edge, np.clip(np.roll(np.roll(rmask, 26, axis=0), -14, axis=1) - rmask, 0, 1))
    piles = gaussian(low_edge, 14) * 2.2 * np.clip(fbm(W, H, 25, 3, 123) * 2.2 - 0.5, 0, 1)
    piles = np.clip(piles, 0, 1)
    cover = np.clip(drift + snow_on * 0.9 + flakes * 0.8 + piles, 0, 1)
    img = blend(img, np.array([172, 182, 200], np.float32) + (gn[..., None] - 0.5) * 16, cover)

    img = painterly(img, seed=404, passes=((16, 0.9), (8, 1.5), (4, 2.6)), jitter=5)
    img = canvas_grain(img, 9, 2.5)
    out = save_jpg(img, "dead")
    print("  лампочка рации:", RADIO_LED)
    preview(out, "dead")


# ================================================================ сцена 4: вертолёт

def heli_outside():
    """Вид из двери: сумеречная тундра с высоты, лента 4096x1024, бесшовная по горизонтали."""
    w, h, ov = 4096, 1024, 640  # степени двойки: текстура крутится по кругу (noclamp)
    ww = w + ov
    yy = np.arange(h, dtype=np.float32)[:, None]
    sky = vgrad(h, ww, [(0, (52, 62, 80)), (0.3, (104, 116, 134)), (0.42, (176, 168, 160)), (1, (176, 168, 160))])
    clouds = stretched_fbm(ww, h, 70, 5, 501, sx=6)
    sky += (clouds[..., None] - 0.5) * 50 * (1 - yy / h)[..., None]
    img = sky
    far = ridge_line(ww, h * 0.40, 70, 500, 6, 502, sharp=1.6)
    m = mask_below(ww, h, far)
    img = blend(img, np.array([118, 128, 146], np.float32) + (fbm(ww, h, 30, 4, 503)[..., None] - 0.5) * 26, m * 0.9)
    # равнина сверху: светлый снег, тёмные трещины и выходы камня, уходит в дымку
    plain_top = ridge_line(ww, h * 0.47, 18, 400, 4, 504)
    m2 = mask_below(ww, h, plain_top)
    t = np.clip((yy - h * 0.47) / (h * 0.53), 0, 1)
    snow = np.array([182, 190, 204], np.float32) + (fbm(ww, h, 60, 5, 505)[..., None] - 0.5) * 40
    rocks = np.clip((stretched_fbm(ww, h, 40, 5, 506, sx=5) - 0.66) * 4, 0, 1) * (0.2 + t * 0.8)
    snow = blend(snow, np.array([58, 64, 76], np.float32), rocks)
    snow = blend(snow, np.array([150, 158, 172], np.float32), (1 - t) ** 3 * 0.8)
    img = blend(img, snow, m2)
    img = painterly(img, seed=507, passes=((14, 0.9), (7, 1.4)), jitter=5)
    # бесшовность: хвост плавно переходит в начало
    k = np.linspace(0, 1, ov, dtype=np.float32)[None, :, None]
    img[:, :ov] = img[:, :ov] * k + img[:, w:w + ov] * (1 - k)
    img = img[:, :w]
    os.makedirs(OUT, exist_ok=True)
    to_img(img).save(os.path.join(OUT, "heli_outside.jpg"), quality=88)
    return to_img(img)


DOOR = (1400, 250, 2330, 1150)  # проём двери в кадре салона


def heli():
    rnd = random.Random(44)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    outside = heli_outside()

    # ---- стены салона: тёмный металл, рёбра, заклёпки; потолок и пол в перспективе
    wall = np.array([46, 50, 50], np.float32) + (fbm(W, H, 12, 4, 601)[..., None] - 0.5) * 16
    for x0 in range(80, W, 330):  # рёбра шпангоутов
        rib = np.exp(-((xx - x0) / 16) ** 2)
        wall += rib[..., None] * 16
        wall -= np.exp(-((xx - x0 - 26) / 10) ** 2)[..., None] * 12
    ceil_line = 230 + (xx - W / 2) ** 2 / 9000
    floor_line = 1210 - (xx - W / 2) ** 2 / 14000
    ceil = np.clip((ceil_line - yy) / 3, 0, 1)
    floor = np.clip((yy - floor_line) / 3, 0, 1)
    wall = blend(wall, np.array([30, 32, 34], np.float32) + (fbm(W, H, 20, 3, 602)[..., None] - 0.5) * 12, ceil)
    wall = blend(wall, np.array([26, 27, 28], np.float32) + (stretched_fbm(W, H, 8, 3, 603, sx=6)[..., None] - 0.5) * 14, floor)
    # скамья-сетка вдоль стены
    bench = ((yy > 800) & (yy < 850) & (xx < DOOR[0] - 30)).astype(np.float32)
    web = ((yy > 480) & (yy < 800) & (xx < DOOR[0] - 30)).astype(np.float32)
    net = (np.abs(np.sin(xx / 14 + yy / 14)) > 0.9) | (np.abs(np.sin(xx / 14 - yy / 14)) > 0.9)
    wall = blend(wall, np.array([70, 64, 52], np.float32), web * net * 0.55)
    wall = blend(wall, np.array([60, 58, 50], np.float32), gaussian(bench, 1.5))
    # красная дежурная лампа у потолка слева
    lamp = np.exp(-(((xx - 420) / 700) ** 2 + ((yy - 120) / 520) ** 2))
    wall += lamp[..., None] * np.array([120, 18, 14], np.float32) * 0.8
    lampcore = np.exp(-(((xx - 420) / 46) ** 2 + ((yy - 118) / 22) ** 2))
    wall = blend(wall, np.array([255, 90, 70], np.float32), np.clip(lampcore * 1.4, 0, 1))
    # холодный свет из двери на стенах и полу
    door_cx = (DOOR[0] + DOOR[2]) / 2
    spill = np.exp(-(((xx - door_cx) / 900) ** 2)) * np.clip((yy - 300) / 900, 0, 1)
    wall += spill[..., None] * np.array([40, 48, 62], np.float32)
    floor_spill = floor * np.exp(-(((xx - door_cx + 200) / 700) ** 2)) * np.exp(-((yy - floor_line) / 160))
    wall += floor_spill[..., None] * np.array([80, 92, 112], np.float32)

    # проём двери (прозрачный), с толстой рамой и направляющей сверху
    dm = Image.new("L", (W, H), 0)
    ImageDraw.Draw(dm).rounded_rectangle(DOOR, 60, fill=255)
    door = np.asarray(dm.filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255.0
    frame = gaussian(door, 22) * (1 - door)
    wall = blend(wall, np.array([86, 96, 112], np.float32), np.clip(frame * 2.4, 0, 1) * 0.7)
    rail = ((yy > DOOR[1] - 70) & (yy < DOOR[1] - 44) & (xx > DOOR[0] - 120) & (xx < DOOR[2] + 120)).astype(np.float32)
    wall = blend(wall, np.array([70, 74, 78], np.float32), gaussian(rail, 1.5))

    # ---- бойцы: двое сидят на скамье лицом к нам, третий стоит у двери против света
    sil = Sil(W, H)
    soldier_seated_front(sil, 430, 815, 800, rnd, tilt=0.05)
    soldier_seated_front(sil, 1010, 818, 820, rnd, tilt=-0.14)
    seated = sil.mask(blur=1.0)
    st = Sil(W, H)
    soldier(st, 1640, 1235, 980, face=1, pose="stand", rnd=rnd, tilt=0.1, lean=0.02)
    stand = st.mask(blur=1.0)

    camo = fbm(W, H, 16, 4, 610)
    camo_rgb = np.array([150, 156, 164], np.float32)
    camo_rgb = blend(np.broadcast_to(camo_rgb, (H, W, 3)), np.array([92, 98, 108], np.float32), np.clip((camo - 0.52) * 6, 0, 1))
    camo_rgb = blend(camo_rgb, np.array([196, 202, 210], np.float32), np.clip((0.4 - camo) * 6, 0, 1) * 0.6)
    # сидящих освещают: красная лампа слева сверху, холодный свет двери справа (контровой)
    lit = camo_rgb * 0.13
    rim = np.clip(seated - np.roll(seated, -18, axis=1), 0, 1) * gaussian(seated, 6)  # тонкие детали (ствол) не светятся
    rim = gaussian(rim, 7)
    lit += rim[..., None] * np.array([70, 84, 104], np.float32)
    redside = np.clip(seated - np.roll(seated, 22, axis=1), 0, 1)
    lit += gaussian(redside, 12)[..., None] * np.array([34, 6, 5], np.float32)
    lit += lamp[..., None] * np.array([40, 6, 5], np.float32)
    # очки бойцов поблёскивают
    img = blend(wall, lit, seated)
    # стоящий у двери — почти чёрный силуэт, тонкий холодный ореол
    srim = gaussian(np.clip(stand - np.roll(stand, 10, axis=1), 0, 1) + np.clip(stand - np.roll(stand, -10, axis=1), 0, 1), 4)
    srgb = np.array([14, 16, 20], np.float32) + srim[..., None] * np.array([90, 104, 128], np.float32)
    img = blend(img, srgb, stand)
    alpha = np.clip(1 - door + stand, 0, 1)

    img = painterly(fill_out(img, alpha), alpha=alpha, seed=611, passes=((14, 0.9), (7, 1.4), (3, 2.2)), jitter=5)
    cabin = save_png(img, alpha, "heli_cabin")
    if PREVIEW:
        comp = Image.new("RGBA", (W, H))
        o = outside.resize((int(outside.width * H / outside.height * 0.9), int(H * 0.9))).convert("RGBA")
        comp.paste(o, (DOOR[0] - 200, 120))
        comp.alpha_composite(cabin)
        preview(comp, "heli")
        preview(outside.convert("RGBA"), "heli_outside")


# ================================================================ сцена 5: знак Фонда и служебные текстуры

def scp_logo(size=1024):
    """Знак Фонда SCP (CC BY-SA 3.0, SCP Wiki): внешнее кольцо, три стрелы к центру, внутреннее кольцо."""
    ss = 4
    S = size * ss
    c = S / 2
    img = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(img)
    R, t = S * 0.40, S * 0.075
    d.ellipse((c - R, c - R, c + R, c + R), fill=255)
    d.ellipse((c - R + t, c - R + t, c + R - t, c + R - t), fill=0)
    r, t2 = S * 0.185, S * 0.05
    d.ellipse((c - r, c - r, c + r, c + r), fill=255)
    d.ellipse((c - r + t2, c - r + t2, c + r - t2, c + r - t2), fill=0)

    def arrow(ang, grow, val):
        # стрела снаружи кольца остриём к центру; grow — расширение для вырезания зазора
        ca, sa = math.cos(ang), math.sin(ang)
        px, py = -sa, ca

        def P(rad, off):
            return (c + ca * rad + px * off, c + sa * rad + py * off)
        sw = S * 0.035 + grow
        hw = S * 0.085 + grow
        tip = S * 0.215 - grow * 1.3
        neck = S * 0.335 + grow * 0.2
        tail = S * 0.50 + grow
        d.polygon([P(tail, -sw), P(neck, -sw), P(neck, -hw), P(tip, 0), P(neck, hw), P(neck, sw), P(tail, sw)], fill=val)
    for k in range(3):
        arrow(math.radians(-90 + k * 120), S * 0.03, 0)
    for k in range(3):
        arrow(math.radians(-90 + k * 120), 0, 255)
    return img.resize((size, size), Image.LANCZOS)


def banner():
    logo = scp_logo()
    a = np.asarray(logo, np.float32) / 255.0
    rgb = np.broadcast_to(np.array([226, 230, 236], np.float32), a.shape + (3,))
    os.makedirs(OUT, exist_ok=True)
    save_png(rgb, a, "scp_logo")
    # фон: тёмный бетон с холодным пятном света
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    bg = np.array([14, 16, 19], np.float32) + (fbm(W, H, 30, 5, 701)[..., None] - 0.5) * 16
    bg += (fbm(W, H, 4, 2, 702)[..., None] - 0.5) * 7
    spot = np.exp(-(((xx - W / 2) / 900) ** 2 + ((yy - H * 0.44) / 560) ** 2))
    bg += spot[..., None] * np.array([26, 30, 36], np.float32)
    img = save_jpg(bg, "banner_bg")
    if PREVIEW:
        comp = img.convert("RGBA")
        lg = Image.open(os.path.join(OUT, "scp_logo.png")).resize((560, 560))
        comp.alpha_composite(lg, (W // 2 - 280, int(H * 0.44) - 330))
        preview(comp, "banner")


def fx():
    """Служебные текстуры: снежинка, полосы метели, туман (бесшовный), зерно плёнки, виньетка."""
    os.makedirs(OUT, exist_ok=True)
    n = 64
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.hypot(xx - n / 2 + 0.5, yy - n / 2 + 0.5) / (n / 2)
    flake = np.clip(1 - d, 0, 1) ** 1.8
    save_png(np.full((n, n, 3), 255, np.float32), flake, "flake")
    # полоса снега, летящего в двери вертолёта
    sw, sh = 128, 16
    yy, xx = np.mgrid[0:sh, 0:sw].astype(np.float32)
    streak = np.exp(-((yy - sh / 2) / 3.2) ** 2) * np.clip(1 - np.abs(xx - sw / 2) / (sw / 2), 0, 1) ** 1.5
    save_png(np.full((sh, sw, 3), 255, np.float32), streak, "streak")
    # туман: бесшовный (сумма четырёх сдвинутых копий с весами)
    t = 512
    f = fbm(t * 2, t * 2, 120, 5, 801)[:t, :t]
    yy, xx = np.mgrid[0:t, 0:t].astype(np.float32)
    wx = np.sin(np.pi * xx / t) ** 2
    wy = np.sin(np.pi * yy / t) ** 2
    tile = (f * wx * wy + np.roll(f, t // 2, 1) * (1 - wx) * wy + np.roll(f, t // 2, 0) * wx * (1 - wy)
            + np.roll(np.roll(f, t // 2, 0), t // 2, 1) * (1 - wx) * (1 - wy))
    tile = np.clip((tile - 0.35) * 2.2, 0, 1)
    save_png(np.full((t, t, 3), 255, np.float32), tile, "fog")
    # зерно: серый шум с прозрачностью
    g = 256
    rng = np.random.default_rng(802)
    grain = rng.random((g, g)).astype(np.float32)
    save_png(np.dstack([grain * 255] * 3), np.full((g, g), 1.0, np.float32), "grain")
    # виньетка: чёрный по краям
    vw, vh = 512, 288
    yy, xx = np.mgrid[0:vh, 0:vw].astype(np.float32)
    d = np.hypot((xx - vw / 2) / (vw / 2), (yy - vh / 2) / (vh / 2)) / 1.414
    vig = np.clip((d - 0.35) / 0.65, 0, 1) ** 1.6
    save_png(np.zeros((vh, vw, 3), np.float32), vig, "vignette")


SCENES = {"arctic": arctic, "dead": dead, "heli": heli, "banner": banner, "fx": fx}

if __name__ == "__main__":
    names = sys.argv[1:] or list(SCENES)
    for n in names:
        print("рисую", n)
        SCENES[n]()
