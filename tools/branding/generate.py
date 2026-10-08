"""Генератор логотипа и баннера New-York Roleplay.

Запуск:  python3 tools/branding/generate.py
Результат кладётся в branding/ и в gamemodes/newyorkrp/ (logo.png, icon24.png).
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "branding")
GM = os.path.join(ROOT, "gamemodes", "newyorkrp")

FONT_BLACK = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
FONT_BOLD = "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf"

NAVY = (10, 14, 28)
NAVY2 = (22, 30, 58)
TAXI = (247, 198, 0)
WHITE = (245, 246, 250)
SKY_TOP = (6, 9, 22)
SKY_BOTTOM = (52, 36, 78)
GLOW = (255, 140, 60)


def font(path, size):
    return ImageFont.truetype(path, size)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def vgradient(w, h, top, bottom):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        d.line([(0, y), (w, y)], fill=lerp(top, bottom, y / max(h - 1, 1)))
    return img


# ---------------------------------------------------------------- skyline ---

def empire_state(x, base, s):
    """Полигон Эмпайр-стейт-билдинг: x — центр, base — земля, s — масштаб."""
    steps = [(60, 0), (60, 150), (46, 150), (46, 300), (36, 300), (36, 420),
             (26, 420), (26, 470), (16, 470), (16, 505), (8, 505), (8, 540),
             (3, 540), (2, 610)]
    left = [(x - w * s, base - h * s) for w, h in steps]
    right = [(x + w * s, base - h * s) for w, h in reversed(steps)]
    return left + [(x, base - 640 * s)] + right


def chrysler(x, base, s):
    pts = [(x - 40 * s, base), (x - 40 * s, base - 330 * s), (x - 30 * s, base - 330 * s),
           (x - 30 * s, base - 380 * s)]
    # корона из ступенчатых арок
    for i in range(5):
        w = 30 - i * 6
        pts += [(x - w * s, base - (380 + i * 26) * s), (x - (w - 3) * s, base - (395 + i * 26) * s)]
    pts += [(x - 2 * s, base - 520 * s), (x, base - 600 * s), (x + 2 * s, base - 520 * s)]
    for i in reversed(range(5)):
        w = 30 - i * 6
        pts += [(x + (w - 3) * s, base - (395 + i * 26) * s), (x + w * s, base - (380 + i * 26) * s)]
    pts += [(x + 30 * s, base - 380 * s), (x + 30 * s, base - 330 * s),
            (x + 40 * s, base - 330 * s), (x + 40 * s, base)]
    return pts


def one_wtc(x, base, s):
    return [(x - 48 * s, base), (x - 48 * s, base - 60 * s), (x - 22 * s, base - 520 * s),
            (x - 3 * s, base - 520 * s), (x - 1.5 * s, base - 700 * s), (x + 1.5 * s, base - 700 * s),
            (x + 3 * s, base - 520 * s), (x + 22 * s, base - 520 * s), (x + 48 * s, base - 60 * s),
            (x + 48 * s, base)]


def draw_skyline(img, base, scale, color, rng, windows=True, landmarks=True, density=1.0,
                 hmax=330, lm_scale=None, lm_x=(0.30, 0.47, 0.78)):
    w, _ = img.size
    d = ImageDraw.Draw(img)
    x = -20
    boxes = []
    while x < w + 20:
        bw = rng.randint(int(28 * scale), int(80 * scale))
        bh = rng.randint(int(min(90, hmax * 0.4) * scale), int(hmax * scale))
        top = base - bh
        d.rectangle([x, top, x + bw, base], fill=color)
        if rng.random() < 0.35:  # надстройка / водонапорная башня
            tw = bw * rng.uniform(0.3, 0.6)
            th = rng.randint(int(12 * scale), int(50 * scale))
            tx = x + rng.uniform(0, bw - tw)
            d.rectangle([tx, top - th, tx + tw, top], fill=color)
            if rng.random() < 0.4:
                d.line([(tx + tw / 2, top - th), (tx + tw / 2, top - th - 30 * scale)], fill=color, width=max(1, int(2 * scale)))
        boxes.append((x, top, bw, bh))
        x += bw + rng.randint(-6, int(6 * scale))

    if landmarks:
        ls = lm_scale or scale
        d.polygon(empire_state(w * lm_x[0], base, ls * 0.95), fill=color)
        d.polygon(chrysler(w * lm_x[1], base, ls * 0.85), fill=color)
        d.polygon(one_wtc(w * lm_x[2], base, ls * 0.95), fill=color)

    if windows:
        for (bx, top, bw, bh) in boxes:
            step = max(5, int(11 * scale))
            for wy in range(int(top + step), int(base - step), step):
                for wx in range(int(bx + 4), int(bx + bw - 4), step):
                    if rng.random() < 0.18 * density:
                        c = rng.choice([(255, 214, 120), (255, 236, 180), (180, 210, 255), TAXI])
                        a = max(2, int(4 * scale))
                        d.rectangle([wx, wy, wx + a, wy + int(a * 1.4)], fill=c)


def stars(img, n, rng, maxy):
    d = ImageDraw.Draw(img)
    w, _ = img.size
    for _ in range(n):
        x, y = rng.randint(0, w), rng.randint(0, maxy)
        b = rng.randint(120, 255)
        d.point((x, y), fill=(b, b, min(255, b + 20)))


def checker(d, x0, y0, x1, y1, cell, c1, c2):
    rows = max(1, round((y1 - y0) / cell))
    ch = (y1 - y0) / rows
    cols = int((x1 - x0) / ch) + 1
    for r in range(rows):
        for c in range(cols):
            cx = x0 + c * ch
            d.rectangle([cx, y0 + r * ch, min(cx + ch, x1), y0 + (r + 1) * ch],
                        fill=c1 if (r + c) % 2 == 0 else c2)


def text_center(d, cx, y, txt, f, fill, tracking=0):
    if tracking == 0:
        tw = d.textlength(txt, font=f)
        d.text((cx - tw / 2, y), txt, font=f, fill=fill)
        return
    widths = [d.textlength(ch, font=f) for ch in txt]
    total = sum(widths) + tracking * (len(txt) - 1)
    x = cx - total / 2
    for ch, cw in zip(txt, widths):
        d.text((x, y), ch, font=f, fill=fill)
        x += cw + tracking


def shadowed(img, draw_fn, offset=(0, 6), blur=10, alpha=170):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(sh), (0, 0, 0, alpha), offset)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(sh)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer), None, (0, 0))
    img.alpha_composite(layer)


# ------------------------------------------------------------------- logo ---

def make_logo(size=1024):
    S = size
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # фон-плашка: скруглённый квадрат с ночным небом
    sky = vgradient(S, S, SKY_TOP, (40, 30, 70)).convert("RGBA")
    rng = random.Random(7)
    stars(sky, 160, rng, int(S * 0.5))
    # закатное свечение у горизонта
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([S * 0.1, S * 0.45, S * 0.9, S * 0.95], fill=GLOW + (90,))
    sky.alpha_composite(glow.filter(ImageFilter.GaussianBlur(S * 0.08)))
    draw_skyline(sky, int(S * 0.70), S / 1024 * 1.05, (14, 16, 34), random.Random(3), density=0.9)

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.18), fill=255)
    img.paste(sky, (0, 0), mask)

    d = ImageDraw.Draw(img)
    # такси-полоса с шашечками
    band_top, band_bot = int(S * 0.70), int(S * 0.79)
    d.rectangle([0, band_top, S, band_bot], fill=TAXI)
    checker(d, 0, band_bot, S, int(S * 0.84), S * 0.025, (16, 16, 20), TAXI)
    d.rectangle([0, int(S * 0.84), S, S], fill=NAVY)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (S, S), 0), mask))

    # «NY»
    f_ny = font(FONT_BLACK, int(S * 0.46))
    def ny(dd, fill, off):
        text_center(dd, S / 2 + off[0], S * 0.13 + off[1], "NY", f_ny, fill or WHITE, tracking=-S * 0.01)
    shadowed(img, ny, offset=(0, int(S * 0.012)), blur=int(S * 0.02))

    d = ImageDraw.Draw(img)
    f_rp = font(FONT_BLACK, int(S * 0.07))
    text_center(d, S / 2, band_top + (band_bot - band_top) / 2 - S * 0.047, "ROLEPLAY", f_rp, NAVY, tracking=S * 0.018)
    f_sub = font(FONT_BOLD, int(S * 0.042))
    text_center(d, S / 2, S * 0.885, "NEW-YORK  •  GMOD", f_sub, (200, 205, 225), tracking=S * 0.008)

    # обводка
    ImageDraw.Draw(img).rounded_rectangle([2, 2, S - 3, S - 3], radius=int(S * 0.18), outline=TAXI, width=int(S * 0.012))
    return img


# ----------------------------------------------------------------- banner ---

def make_banner(w=1920, h=600):
    img = vgradient(w, h, SKY_TOP, SKY_BOTTOM).convert("RGBA")
    rng = random.Random(11)
    stars(img, 500, rng, int(h * 0.55))

    # луна
    moon = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    md = ImageDraw.Draw(moon)
    mx, my, mr = w * 0.86, h * 0.20, h * 0.07
    md.ellipse([mx - mr * 3, my - mr * 3, mx + mr * 3, my + mr * 3], fill=(200, 210, 255, 40))
    moon = moon.filter(ImageFilter.GaussianBlur(30))
    ImageDraw.Draw(moon).ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(240, 236, 220, 255))
    img.alpha_composite(moon)

    # свечение города
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-w * 0.1, h * 0.55, w * 1.1, h * 1.3], fill=GLOW + (110,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(80)))

    far = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw_skyline(far, int(h * 0.90), 1.0, (40, 34, 70, 255), random.Random(5), windows=False,
                 hmax=h * 0.42, lm_scale=h / 1000, lm_x=(0.10, 0.20, 0.90))
    img.alpha_composite(far)
    near = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw_skyline(near, int(h * 0.90), 1.0, (12, 13, 28, 255), random.Random(9), density=1.0,
                 hmax=h * 0.30, landmarks=False)
    img.alpha_composite(near)

    # затемнение под текст
    shade = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shade).ellipse([w * 0.12, h * 0.05, w * 0.88, h * 0.85], fill=(5, 6, 15, 150))
    img.alpha_composite(shade.filter(ImageFilter.GaussianBlur(90)))

    d = ImageDraw.Draw(img)
    # полоса такси снизу
    d.rectangle([0, int(h * 0.90), w, h], fill=TAXI)
    checker(d, 0, int(h * 0.90), w, int(h * 0.94), h * 0.02, (16, 16, 20), TAXI)

    f_title = font(FONT_BLACK, int(h * 0.27))
    def title(dd, fill, off):
        text_center(dd, w / 2 + off[0], h * 0.12 + off[1], "NEW-YORK", f_title, fill or WHITE, tracking=8)
    shadowed(img, title, offset=(0, 8), blur=14, alpha=200)

    d = ImageDraw.Draw(img)
    f_rp = font(FONT_BLACK, int(h * 0.085))
    label = "ROLEPLAY"
    track = 26
    widths = sum(d.textlength(c, font=f_rp) for c in label) + track * (len(label) - 1)
    px, py = 46, 14
    bx0, by0 = w / 2 - widths / 2 - px, h * 0.50
    bh = h * 0.085 + py * 2 + 10
    d.rectangle([bx0, by0, w - bx0, by0 + bh], fill=TAXI)
    text_center(d, w / 2, by0 + py - 4, label, f_rp, NAVY, tracking=track)

    f_tag = font(FONT_BOLD, int(h * 0.04))
    tag = "GARRY'S MOD  ·  ROLEPLAY FRAMEWORK"
    tw = sum(d.textlength(c, font=f_tag) for c in tag) + 6 * (len(tag) - 1)
    pill = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(pill).rounded_rectangle([w / 2 - tw / 2 - 28, by0 + bh + 14, w / 2 + tw / 2 + 28, by0 + bh + 26 + h * 0.04 + 18],
                                           radius=22, fill=(8, 9, 20, 215))
    img.alpha_composite(pill)
    d = ImageDraw.Draw(img)
    text_center(d, w / 2, by0 + bh + 26, "GARRY'S MOD  ·  ROLEPLAY FRAMEWORK", f_tag, (215, 218, 235), tracking=6)
    f_small = font(FONT_BOLD, int(h * 0.03))
    d.text((w - 30 - d.textlength("NYRP", font=f_small), int(h * 0.945)), "NYRP", font=f_small, fill=NAVY)
    return img


def save(img, name, size=None, rgb=False):
    if size:
        img = img.resize(size, Image.LANCZOS)
    if rgb:
        bg = Image.new("RGB", img.size, NAVY)
        bg.paste(img, (0, 0), img)
        img = bg
    path = os.path.join(OUT, name) if not os.path.isabs(name) else name
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT), img.size)


def make_menu_logo(w=288, h=128):
    """Логотип для главного меню GMod (gamemodes/<gm>/logo.png)."""
    k = 4
    W, H = w * k, h * k
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    fs = int(H * 0.46)
    while ImageDraw.Draw(img).textlength("NEW-YORK", font=font(FONT_BLACK, fs)) > W * 0.96:
        fs -= 2
    f1 = font(FONT_BLACK, fs)
    def t(dd, fill, off):
        dd.text((W * 0.02 + off[0], H * 0.02 + off[1]), "NEW-YORK", font=f1, fill=fill or WHITE)
    shadowed(img, t, offset=(0, 8), blur=10, alpha=200)
    d = ImageDraw.Draw(img)
    f2 = font(FONT_BLACK, int(H * 0.2))
    tw = d.textlength("ROLEPLAY", font=f2) + 10 * 7
    y0 = H * 0.02 + fs * 1.12
    d.rectangle([W * 0.02, y0, W * 0.02 + tw + 60, y0 + H * 0.28], fill=TAXI)
    x = W * 0.02 + 30
    for ch in "ROLEPLAY":
        d.text((x, y0 + H * 0.025), ch, font=f2, fill=NAVY)
        x += d.textlength(ch, font=f2) + 10
    return img.resize((w, h), Image.LANCZOS)


def make_menu_banner(w=1500, h=440):
    """Баннер главного меню: прозрачный фон, лого + надпись, без «коробки» с городом."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    logo = make_logo(1024).resize((360, 360), Image.LANCZOS)
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 170), (40, 50, 400, 410), logo.getchannel("A").point(lambda a: a))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)), (0, 0))
    img.alpha_composite(logo, (30, 30))

    x0 = 440
    f_title = font(FONT_BLACK, 170)
    def title(dd, fill, off):
        dd.text((x0 + off[0], 26 + off[1]), "NEW-YORK", font=f_title, fill=fill or WHITE)
    shadowed(img, title, offset=(0, 8), blur=14, alpha=210)

    d = ImageDraw.Draw(img)
    f_rp = font(FONT_BLACK, 52)
    label, track = "ROLEPLAY", 22
    lw = sum(d.textlength(c, font=f_rp) for c in label) + track * (len(label) - 1)
    bx0, by0 = x0 + 6, 236
    d.rectangle([bx0, by0, bx0 + lw + 56, by0 + 78], fill=TAXI)
    checker(d, bx0, by0 + 78, bx0 + lw + 56, by0 + 92, 7, (16, 16, 20), TAXI)
    x = bx0 + 28
    for ch in label:
        d.text((x, by0 + 8), ch, font=f_rp, fill=NAVY)
        x += d.textlength(ch, font=f_rp) + track
    f_tag = font(FONT_BOLD, 30)
    def tag(dd, fill, off):
        dd.text((x0 + 10 + off[0], 352 + off[1]), "GARRY'S MOD  ·  ROLEPLAY FRAMEWORK", font=f_tag, fill=fill or (225, 228, 240))
    shadowed(img, tag, offset=(0, 3), blur=6, alpha=200)
    return img


def make_header_skyline(w=1200, h=420):
    """Фон для шапок (список игроков и т.п.): ночное небо и город, без текста."""
    img = vgradient(w, h, SKY_TOP, SKY_BOTTOM).convert("RGBA")
    rng = random.Random(21)
    stars(img, 260, rng, int(h * 0.6))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-w * 0.1, h * 0.55, w * 1.1, h * 1.4], fill=GLOW + (110,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60)))
    far = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw_skyline(far, int(h * 0.98), 0.9, (40, 34, 70, 255), random.Random(6), windows=False,
                 hmax=h * 0.55, lm_scale=h / 1100, lm_x=(0.2, 0.42, 0.8))
    img.alpha_composite(far)
    near = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw_skyline(near, int(h * 1.0), 0.9, (12, 13, 28, 255), random.Random(8), density=1.0, hmax=h * 0.38, landmarks=False)
    img.alpha_composite(near)
    return img


if __name__ == "__main__":
    logo = make_logo()
    save(logo, "logo_1024.png")
    save(logo, "logo_512.png", (512, 512))
    save(logo, "logo_256.png", (256, 256))
    banner = make_banner()
    save(banner, "banner_1920x600.png", rgb=True)
    save(make_banner(1920, 1080), "wallpaper_1920x1080.png", rgb=True)
    save(make_menu_logo(), os.path.join(GM, "logo.png"))
    save(logo, os.path.join(GM, "icon24.png"), (24, 24))
    mb = make_menu_banner()
    save(mb, "menu_banner.png")
    save(mb, os.path.join(GM, "content", "materials", "nyrp", "menu_banner.png"))
    hs = make_header_skyline()
    save(hs, "header_skyline.png", rgb=True)
    save(hs, os.path.join(GM, "content", "materials", "nyrp", "header_skyline.png"), rgb=True)
