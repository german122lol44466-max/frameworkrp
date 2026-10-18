"""Картинки интро и меню «Белая тишина» -> content/materials/whitesilence/{intro,menu}

    python3 tools/content/intro_art.py [paintings|logo|fx|masks|menu ...]     (без аргументов — всё)

paintings — картины сцен из tools/content/paintings/*.png. Их нарисовала нейросеть Stable Diffusion XL
            (tools/content/gen_paintings.py, стиль — цифровой концепт-арт с крупными мазками). Здесь они
            растягиваются до 2560x1440, получают общий холодный цветокор, лёгкую фактуру и размытую копию
            *_blur для эффекта проявления.
logo      — знак Фонда SCP из векторного scp_logo.svg (Simple Icons; сам знак — SCP Wiki, CC BY-SA 3.0).
fx        — служебные текстуры: снежинка, ледяная крошка, полоса снега, туман, зерно, виньетка.
masks     — маски проявления кадров мазками кисти.
menu      — фон главного меню и изображение отряда (paintings/menu_bg.png, squad.png).
"""
import io
import os
import sys

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "content", "materials", "whitesilence", "intro")
SRC = os.path.join(HERE, "paintings")
W, H = 2560, 1440

# сцена -> (насыщенность, контраст, яркость, оттенок теней RGB)
GRADE = {
    "arctic": (0.85, 1.05, 1.0, (4, 8, 16)),
    "closeup": (0.8, 1.08, 0.92, (4, 10, 22)),
    "dead": (0.95, 1.05, 0.95, (4, 8, 18)),
    "heli": (0.9, 1.08, 0.95, (6, 8, 16)),
    "banner_bg": (0.7, 1.0, 0.45, (2, 6, 14)),
}


def fbm(w, h, cell, octaves, seed):
    rng = np.random.default_rng(seed)
    total, amp, norm = np.zeros((h, w), np.float32), 1.0, 0.0
    for o in range(octaves):
        c = max(2, cell / (2 ** o))
        gw, gh = int(w / c) + 3, int(h / c) + 3
        g = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8)).resize((int(gw * c), int(gh * c)), Image.BICUBIC)
        total += np.asarray(g, np.float32)[:h, :w] / 255 * amp
        norm += amp
        amp *= 0.5
    return total / norm


def save_png(rgb, alpha, name):
    os.makedirs(OUT, exist_ok=True)
    a = np.clip(alpha * 255, 0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), a]), "RGBA").save(os.path.join(OUT, name + ".png"), optimize=True)


def paintings():
    os.makedirs(OUT, exist_ok=True)
    for name, (sat, con, bri, shadow) in GRADE.items():
        src = os.path.join(SRC, name + ".png")
        if not os.path.exists(src):
            print("  нет", src)
            continue
        im = Image.open(src).convert("RGB")
        # кадр 16:9 по центру, затем растяжение
        w, h = im.size
        tw = min(w, int(h * 16 / 9))
        th = int(tw * 9 / 16)
        im = im.crop(((w - tw) // 2, (h - th) // 2, (w - tw) // 2 + tw, (h - th) // 2 + th))
        im = im.resize((W, H), Image.LANCZOS).filter(ImageFilter.UnsharpMask(2.2, 60, 2))
        im = ImageEnhance.Color(im).enhance(sat)
        im = ImageEnhance.Contrast(im).enhance(con)
        im = ImageEnhance.Brightness(im).enhance(bri)
        a = np.asarray(im, np.float32)
        lum = a.mean(axis=2, keepdims=True) / 255
        a += (1 - lum) ** 2 * np.array(shadow, np.float32)      # холодные тени
        a += (fbm(W, H, 3, 2, 9)[..., None] - 0.5) * 8          # фактура холста
        img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
        img.save(os.path.join(OUT, name + ".jpg"), quality=90)
        img.resize((640, 360), Image.LANCZOS).filter(ImageFilter.GaussianBlur(5)).save(os.path.join(OUT, name + "_blur.jpg"), quality=85)
        print("  ", name)


def logo(size=1024):
    import resvg_py
    svg = open(os.path.join(HERE, "scp_logo.svg"), encoding="utf-8").read().replace("<svg ", '<svg fill="#e6e9ee" ', 1)
    png = resvg_py.svg_to_bytes(svg_string=svg, width=size, height=size)
    os.makedirs(OUT, exist_ok=True)
    Image.open(io.BytesIO(bytes(png))).save(os.path.join(OUT, "scp_logo.png"), optimize=True)
    print("   scp_logo")


def fx():
    """Служебные текстуры: снежинка, полосы метели, туман (бесшовный), зерно плёнки, виньетка."""
    os.makedirs(OUT, exist_ok=True)
    n = 64
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.hypot(xx - n / 2 + 0.5, yy - n / 2 + 0.5) / (n / 2)
    flake = np.clip(1 - d, 0, 1) ** 1.8
    save_png(np.full((n, n, 3), 255, np.float32), flake, "flake")
    # ледяная крошка: неровный мазок кистью
    dw, dh = 64, 32
    yy2, xx2 = np.mgrid[0:dh, 0:dw].astype(np.float32)
    edge = fbm(dw, dh, 5, 2, 803)
    dab = np.clip((1 - np.maximum(np.abs(xx2 - dw / 2) / (dw / 2), np.abs(yy2 - dh / 2) / (dh / 2)) ** 3) * 1.6 - edge * 0.6, 0, 1)
    save_png(np.full((dh, dw, 3), 255, np.float32), dab, "dab")
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



def brush_masks(frames=24, w=640, h=360, seed=5):
    """Маски проявления кадра мазками: reveal_00 — всё закрыто, reveal_<N-1> — всё открыто.

    Каждый мазок кисти получает «время», растущее от центра к краям; пиксель открывается, когда до него
    доходит первый накрывший его мазок. Края мазков рваные (сухая кисть).
    """
    from PIL import ImageDraw
    rng = np.random.default_rng(seed)
    ss = 2
    T = np.full((h * ss, w * ss), 2.0, np.float32)
    yy, xx = np.mgrid[0:h * ss, 0:w * ss].astype(np.float32)
    for i in range(260):
        cx, cy = rng.normal(0.5, 0.28) * w * ss, rng.normal(0.5, 0.3) * h * ss
        d = np.hypot((cx / (w * ss) - 0.5) * 1.6, cy / (h * ss) - 0.5)
        tm = np.clip(d * 1.25 + rng.uniform(-0.12, 0.12), 0, 1)
        ang = rng.normal(-0.15, 0.35)
        ln = rng.uniform(0.18, 0.5) * w * ss
        wd = rng.uniform(0.05, 0.13) * h * ss
        img = Image.new("L", (w * ss, h * ss), 0)
        dx, dy = np.cos(ang) * ln / 2, np.sin(ang) * ln / 2
        ImageDraw.Draw(img).line((cx - dx, cy - dy, cx + dx, cy + dy), fill=255, width=int(wd))
        m = np.asarray(img, np.float32) / 255 > 0.5
        # мазок кладётся от начала к концу: время растёт вдоль него
        along = ((xx - (cx - dx)) * dx + (yy - (cy - dy)) * dy) / (dx * dx + dy * dy + 1e-6)
        tt = tm + np.clip(along, 0, 1) * 0.08
        T = np.where(m & (tt < T), tt, T)
    T = np.where(T > 1.5, 1.0, T)
    T += (fbm(w * ss, h * ss, 16, 3, seed + 1) - 0.5) * 0.1      # сухая кисть: рваные края
    T = np.asarray(Image.fromarray(np.clip(T * 200, 0, 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), np.float32) / 200
    for k in range(frames):
        p = k / (frames - 1) * 1.15 - 0.05
        cover = np.clip((T - p) / 0.09 + 0.5, 0, 1)            # 1 — ещё закрыто
        save_png(np.zeros((h, w, 3), np.float32), cover, "reveal_%02d" % k)


def menu():
    """Картины главного меню: тёмный фон 2560x1440 и изображение отряда для правой панели лобби."""
    out = os.path.join(ROOT, "content", "materials", "whitesilence", "menu")
    os.makedirs(out, exist_ok=True)
    src = os.path.join(SRC, "menu_bg.png")
    if os.path.exists(src):
        im = Image.open(src).convert("RGB")
        w, h = im.size
        th = int(w * 9 / 16)
        im = im.crop((0, (h - th) // 2, w, (h - th) // 2 + th)).resize((W, H), Image.LANCZOS)
        im = im.filter(ImageFilter.UnsharpMask(2, 50, 2))
        im = ImageEnhance.Color(im).enhance(0.7)
        im = ImageEnhance.Brightness(im).enhance(0.55)          # меню тёмное, как на референсе
        a = np.asarray(im, np.float32)
        a += (fbm(W, H, 3, 2, 21)[..., None] - 0.5) * 6
        Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(out, "menu_bg.jpg"), quality=90)
        print("   menu_bg")
    src = os.path.join(SRC, "squad.png")
    if os.path.exists(src):
        im = Image.open(src).convert("RGB").resize((1200, 1543), Image.LANCZOS).filter(ImageFilter.UnsharpMask(2, 50, 2))
        im = ImageEnhance.Color(im).enhance(0.85)
        im.save(os.path.join(out, "squad.jpg"), quality=90)
        print("   squad")


ALL = {"paintings": paintings, "logo": logo, "fx": fx, "masks": brush_masks, "menu": menu}

if __name__ == "__main__":
    for n in sys.argv[1:] or list(ALL):
        print(n)
        ALL[n]()
