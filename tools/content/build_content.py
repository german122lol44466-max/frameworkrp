"""Сборка контента New-York Roleplay.

Шрифты  — Google Fonts (Oswald, Manrope; OFL) из npm-пакетов @expo-google-fonts.
Иконки  — Tabler Icons (MIT), SVG -> PNG.
UI-звуки — uisfx (MIT), ogg -> wav.
Остальное (курсоры, виньетка, текстуры, вотермарк) рисуется здесь.

Запуск:  python3 tools/content/build_content.py <путь к node_modules>
"""
import os
import shutil
import subprocess
import sys

import cairosvg
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CONTENT = os.path.join(ROOT, "gamemodes", "newyorkrp", "content")
NM = sys.argv[1] if len(sys.argv) > 1 else "node_modules"

TAXI = (247, 198, 0)
ORANGE = (255, 138, 36)
NAVY = (10, 14, 28)


def out(*parts):
    p = os.path.join(CONTENT, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


# ------------------------------------------------------------------ fonts ---
FONTS = {
    "manrope": ["400Regular", "500Medium", "600SemiBold", "800ExtraBold"],
    "oswald": ["300Light", "500Medium", "600SemiBold"],
}


def build_fonts():
    for fam, weights in FONTS.items():
        for w in weights:
            name = f"{fam.capitalize()}_{w}.ttf"
            src = os.path.join(NM, "@expo-google-fonts", fam, w, name)
            shutil.copy(src, out("resource", "fonts", name))
    print("fonts ok")


# ------------------------------------------------------------------ icons ---
ICONS = {
    # имя в игре: имя в Tabler
    "settings": "settings", "mic": "microphone", "question": "question-mark",
    "door": "door", "hand": "hand-grab", "interact": "hand-finger", "item": "package",
    "arrow_right": "arrow-right", "arrow_left": "arrow-left", "chevron_right": "chevron-right",
    "chevron_left": "chevron-left", "users": "users", "world": "world", "logout": "logout",
    "trash": "trash", "play": "player-play", "user_plus": "user-plus", "backpack": "backpack",
    "briefcase": "briefcase", "shirt": "shirt", "helmet": "helmet", "mask": "mask",
    "jacket": "jacket", "gloves": "hand-stop", "pants": "hanger-2", "shoe": "shoe",
    "glasses": "sunglasses", "watch": "device-watch", "sword": "sword", "crosshair": "crosshair",
    "target": "target", "keyboard": "keyboard", "volume": "volume", "music": "music", "eye": "eye",
    "skull": "skull", "heart": "heart", "droplet": "droplet", "food": "tools-kitchen-2",
    "copy": "copy", "id": "id", "user": "user", "bell": "bell", "info": "info-circle",
    "warning": "alert-triangle", "check": "check", "close": "x", "message": "message-circle",
    "camera": "camera", "clock": "clock", "hanger": "hanger", "lock": "lock", "unlock": "lock-open",
    "home": "home", "refresh": "refresh", "plus": "plus", "minus": "minus", "move": "arrows-move",
    "rotate": "rotate", "save": "device-floppy", "steam": "brand-steam", "layout": "layout-grid",
    "adjust": "adjustments", "mouse": "mouse", "box": "box", "shield": "shield", "bolt": "bolt",
    "run": "run", "walk": "walk", "medkit": "first-aid-kit", "bottle": "bottle", "coffee": "coffee",
    "bandage": "bandage", "burger": "burger", "hourglass": "hourglass", "speaker": "speakerphone",
    "ear": "ear", "pointer": "hand-click", "door_exit": "door-exit", "menu": "menu-2",
}


def build_icons():
    base = os.path.join(NM, "@tabler", "icons", "icons", "outline")
    for name, tab in ICONS.items():
        svg = open(os.path.join(base, tab + ".svg")).read()
        svg = svg.replace('stroke="currentColor"', 'stroke="#ffffff"').replace('stroke-width="2"', 'stroke-width="1.8"')
        cairosvg.svg2png(bytestring=svg.encode(), write_to=out("materials", "nyrp", "icons", name + ".png"),
                         output_width=128, output_height=128)
    print("icons ok:", len(ICONS))


# ----------------------------------------------------------------- sounds ---
UI_SOUNDS = {
    "hover": ("soft", "hover"), "click": ("soft", "select"), "open": ("soft", "open"),
    "close": ("soft", "close"), "notify": ("soft", "notification"), "error": ("soft", "error"),
    "success": ("soft", "success"), "drag": ("soft", "drag-start"), "drop": ("soft", "drop"),
    "swipe": ("cinematic", "swipe"), "expand": ("cinematic", "expand"),
    "progress": ("soft", "progress-step"), "complete": ("soft", "complete"), "copy": ("soft", "copy"),
    "delete": ("soft", "delete"), "toggle": ("soft", "toggle-on"), "warning": ("soft", "warning"),
    "spawn": ("cinematic", "wake"), "start": ("cinematic", "start"), "back": ("soft", "back"),
}


def to_wav(src, dst):
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-ar", "44100", "-ac", "1",
                    "-sample_fmt", "s16", dst], check=True)


def build_ui_sounds():
    for name, (pack, cue) in UI_SOUNDS.items():
        to_wav(os.path.join(NM, "uisfx", "sounds", pack, cue + ".ogg"), out("sound", "nyrp", "ui", name + ".wav"))
    print("ui sounds ok:", len(UI_SOUNDS))


# ----------------------------------------------------------------- images ---
def build_cursors():
    S = 64
    k = 4

    def arrow(fill, accent):
        img = Image.new("RGBA", (S * k, S * k), (0, 0, 0, 0))
        pts = [(4, 3), (4, 44), (14, 34), (21, 50), (28, 47), (21, 31), (35, 31)]
        pts = [(x * k, y * k) for x, y in pts]
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).polygon([(x + 2 * k, y + 3 * k) for x, y in pts], fill=(0, 0, 0, 150))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(3 * k)))
        d = ImageDraw.Draw(img)
        d.polygon(pts, fill=(14, 16, 26, 255))
        inner = [(4, 3), (4, 44), (14, 34), (21, 50), (28, 47), (21, 31), (35, 31)]
        cx, cy = 12, 28
        inner = [((x - cx) * 0.78 + cx, (y - cy) * 0.78 + cy) for x, y in inner]
        d.polygon([(x * k, y * k) for x, y in inner], fill=fill)
        d.ellipse([3 * k, 2 * k, 9 * k, 8 * k], fill=accent)
        return img.resize((S, S), Image.LANCZOS)

    arrow((245, 246, 250, 255), TAXI + (255,)).save(out("materials", "nyrp", "cursor", "arrow.png"))
    arrow(ORANGE + (255,), (255, 255, 255, 255)).save(out("materials", "nyrp", "cursor", "hand.png"))

    img = Image.new("RGBA", (S * k, S * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for col, wdt in (((14, 16, 26, 255), 9), ((245, 246, 250, 255), 4)):
        d.line([(32 * k, 10 * k), (32 * k, 54 * k)], fill=col, width=wdt * k // 2)
        d.line([(24 * k, 10 * k), (40 * k, 10 * k)], fill=col, width=wdt * k // 2)
        d.line([(24 * k, 54 * k), (40 * k, 54 * k)], fill=col, width=wdt * k // 2)
    img.resize((S, S), Image.LANCZOS).save(out("materials", "nyrp", "cursor", "text.png"))
    print("cursors ok")


def build_shapes():
    S = 512
    img = Image.new("L", (S, S), 0)
    ImageDraw.Draw(img).ellipse([2, 2, S - 3, S - 3], fill=255)
    a = img.resize((256, 256), Image.LANCZOS)
    Image.merge("RGBA", (a.point(lambda _: 255),) * 3 + (a,)).save(out("materials", "nyrp", "ui", "circle.png"))

    img = Image.new("L", (S, S), 0)
    ImageDraw.Draw(img).ellipse([4, 4, S - 5, S - 5], outline=255, width=40)
    a = img.resize((256, 256), Image.LANCZOS)
    Image.merge("RGBA", (a.point(lambda _: 255),) * 3 + (a,)).save(out("materials", "nyrp", "ui", "ring.png"))

    # мягкое радиальное свечение
    g = Image.new("L", (256, 256), 0)
    gd = ImageDraw.Draw(g)
    for r in range(128, 0, -1):
        t = 1 - r / 128
        gd.ellipse([128 - r, 128 - r, 128 + r, 128 + r], fill=int(255 * (t ** 1.8)))
    Image.merge("RGBA", (g.point(lambda _: 255),) * 3 + (g,)).save(out("materials", "nyrp", "ui", "glow.png"))

    # виньетка: прозрачный центр, тёмные края
    V = 512
    v = Image.new("L", (V, V), 0)
    px = v.load()
    for y in range(V):
        for x in range(V):
            dx, dy = (x - V / 2) / (V / 2), (y - V / 2) / (V / 2)
            dd = (dx * dx + dy * dy) ** 0.5
            t = min(max((dd - 0.55) / 0.85, 0), 1)
            px[x, y] = int(255 * (t ** 1.6))
    Image.merge("RGBA", (v.point(lambda _: 0),) * 3 + (v,)).save(out("materials", "nyrp", "ui", "vignette.png"))
    print("shapes ok")


def build_bag_textures():
    """Материалы окна инвентаря: ткань, зубья молнии, бегунок с язычком, строчка, заклёпка."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "models"))
    import textures
    Image.fromarray(textures.make("cordura", (42, 44, 50), "inv")).save(out("materials", "nyrp", "ui", "fabric.png"))

    k = 4
    # зубья молнии 32x16 (повторяются по горизонтали)
    z = Image.new("RGBA", (32 * k, 16 * k), (0, 0, 0, 0))
    zd = ImageDraw.Draw(z)
    for x0, y0 in ((4, 1), (20, 7)):
        zd.rounded_rectangle([x0 * k, y0 * k, (x0 + 8) * k, (y0 + 8) * k], radius=6, fill=(120, 116, 108, 255))
        zd.rounded_rectangle([(x0 + 1) * k, (y0 + 1) * k, (x0 + 7) * k, (y0 + 4) * k], radius=4, fill=(205, 198, 182, 255))
    z.resize((32, 16), Image.LANCZOS).save(out("materials", "nyrp", "ui", "zipper.png"))

    # бегунок молнии с жёлтым кожаным язычком 64x128
    W, H = 64 * k, 128 * k
    pull = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.rounded_rectangle([14 * k, 8 * k, 52 * k, 40 * k], radius=8 * k, fill=(0, 0, 0, 150))
    sd.rounded_rectangle([16 * k, 48 * k, 50 * k, 124 * k], radius=8 * k, fill=(0, 0, 0, 150))
    pull.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4 * k)), (2 * k, 4 * k))
    d = ImageDraw.Draw(pull)
    # металлический корпус бегунка (вертикальный градиент)
    body = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    for i in range(34 * k):
        t = i / (34 * k)
        c = int(225 - 110 * t + 25 * (t > 0.45))
        bd.line([(12 * k, (6 * k) + i), (52 * k, (6 * k) + i)], fill=(c, c - 2, c - 8, 255))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([12 * k, 6 * k, 52 * k, 40 * k], radius=9 * k, fill=255)
    pull.paste(body, (0, 0), mask)
    d.rounded_rectangle([12 * k, 6 * k, 52 * k, 40 * k], radius=9 * k, outline=(60, 58, 54, 255), width=k)
    d.line([(17 * k, 11 * k), (47 * k, 11 * k)], fill=(255, 255, 250, 200), width=k)
    # кольцо
    d.rounded_rectangle([24 * k, 34 * k, 40 * k, 54 * k], radius=6 * k, outline=(150, 146, 138, 255), width=3 * k)
    # язычок
    tab = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    td = ImageDraw.Draw(tab)
    for i in range(76 * k):
        t = i / (76 * k)
        td.line([(14 * k, 46 * k + i), (50 * k, 46 * k + i)], fill=(int(248 - 40 * t), int(200 - 45 * t), int(30 - 20 * t), 255))
    tmask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(tmask).rounded_rectangle([14 * k, 46 * k, 50 * k, 122 * k], radius=9 * k, fill=255)
    pull.paste(tab, (0, 0), tmask)
    d.rounded_rectangle([14 * k, 46 * k, 50 * k, 122 * k], radius=9 * k, outline=(120, 86, 0, 255), width=k)
    for y in range(58 * k, 114 * k, 7 * k):  # строчка по краю язычка
        d.line([(19 * k, y), (19 * k, y + 4 * k)], fill=(110, 76, 0, 255), width=k)
        d.line([(45 * k, y), (45 * k, y + 4 * k)], fill=(110, 76, 0, 255), width=k)
    d.ellipse([27 * k, 50 * k, 37 * k, 60 * k], fill=(70, 66, 60, 255), outline=(190, 186, 176, 255), width=2 * k)
    d.text((32 * k, 90 * k), "NY", fill=(120, 86, 0, 255), anchor="mm",
           font=ImageFont.truetype("/usr/share/fonts/opentype/inter/InterDisplay-Black.otf", 18 * k))
    pull.resize((64, 128), Image.LANCZOS).save(out("materials", "nyrp", "ui", "zipper_pull.png"))

    # строчка (нитка с тенью), горизонтальная и вертикальная
    st = Image.new("RGBA", (32 * k, 6 * k), (0, 0, 0, 0))
    sdr = ImageDraw.Draw(st)
    sdr.rounded_rectangle([4 * k, 3 * k, 24 * k, 5 * k], radius=k, fill=(0, 0, 0, 140))
    sdr.rounded_rectangle([4 * k, 1 * k, 24 * k, 3 * k], radius=k, fill=(222, 214, 196, 230))
    st = st.resize((32, 6), Image.LANCZOS)
    st.save(out("materials", "nyrp", "ui", "stitch_h.png"))
    st.rotate(90, expand=True).save(out("materials", "nyrp", "ui", "stitch_v.png"))

    # заклёпка 32x32
    R = 32 * k
    rv = Image.new("RGBA", (R, R), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rv)
    rd.ellipse([3 * k, 5 * k, 29 * k, 31 * k], fill=(0, 0, 0, 120))
    for i in range(12 * k, 0, -1):
        t = i / (12 * k)
        c = int(240 - 140 * t)
        off = int((1 - t) * 3 * k)
        rd.ellipse([16 * k - i - off, 15 * k - i - off, 16 * k + i - off, 15 * k + i - off], fill=(c, c - 4, c - 12, 255))
    rv = rv.filter(ImageFilter.GaussianBlur(k * 0.4)).resize((32, 32), Image.LANCZOS)
    rv.save(out("materials", "nyrp", "ui", "rivet.png"))
    print("bag ui materials ok")


def build_branding():
    shutil.copy(os.path.join(ROOT, "branding", "logo_512.png"), out("materials", "nyrp", "logo.png"))
    shutil.copy(os.path.join(ROOT, "branding", "banner_1920x600.png"), out("materials", "nyrp", "banner.png"))

    # вотермарк «Работа в процессе» (правый нижний угол)
    k = 2
    W, H = 600 * k, 120 * k
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    logo = Image.open(os.path.join(ROOT, "branding", "logo_512.png")).resize((96 * k, 96 * k), Image.LANCZOS)
    img.alpha_composite(logo, (W - 96 * k - 12 * k, 12 * k))
    d = ImageDraw.Draw(img)
    f1 = ImageFont.truetype("/usr/share/fonts/opentype/inter/InterDisplay-Black.otf", 32 * k)
    f2 = ImageFont.truetype("/usr/share/fonts/opentype/inter/InterDisplay-SemiBold.otf", 19 * k)
    right = W - 96 * k - 28 * k
    t1 = "NEW-YORK ROLEPLAY"
    w1 = d.textlength(t1, font=f1)
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.text((right - w1, 24 * k + 3 * k), t1, font=f1, fill=(0, 0, 0, 200))
    t2 = "Работа в процессе"
    w2 = d.textlength(t2, font=f2)
    sd.text((right - w2, 70 * k + 3 * k), t2, font=f2, fill=(0, 0, 0, 200))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4 * k)), (0, 0))
    d = ImageDraw.Draw(img)
    d.text((right - w1, 24 * k), t1, font=f1, fill=(245, 246, 250, 255))
    d.rectangle([right - w2 - 14 * k, 75 * k, right - w2 - 6 * k, 83 * k], fill=TAXI)
    d.text((right - w2, 70 * k), t2, font=f2, fill=TAXI + (255,))
    img.save(out("materials", "nyrp", "watermark.png"))
    img.save(os.path.join(ROOT, "branding", "watermark.png"))
    print("branding ok")


if __name__ == "__main__":
    build_fonts()
    build_icons()
    build_ui_sounds()
    build_cursors()
    build_shapes()
    build_bag_textures()
    build_branding()
