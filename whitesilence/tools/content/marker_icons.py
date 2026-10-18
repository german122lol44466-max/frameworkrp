"""Метки задач -> content/materials/whitesilence/markers/*.png (белые, тонируются в игре)

    python3 tools/content/marker_icons.py        (нужны resvg-py, Pillow; иконки — tools/content/hud_icons.py)

  <kind>.png  — ромб-рамка с иконкой внутри (128x128)
  glow.png    — мягкое свечение под меткой
  arrow.png   — шеврон для метки за краем экрана
  ring.png    — тонкое кольцо (пульс при появлении / зона удержания)
  zone.png    — круг зоны на земле (мягкий край)
Иконки внутри — Tabler Icons (MIT).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_icons as H  # noqa: E402

OUT = os.path.join(H.ROOT, "content", "materials", "whitesilence", "markers")
S = 128
SS = 4   # суперсэмплинг

KINDS = {  # вид метки -> иконка Tabler (None — точка)
    "goto": None,
    "interact": "outline/hand-click",
    "search": "outline/search",
    "defend": "filled/shield",
    "extract": "outline/helicopter",
    "charge": "filled/bomb",
    "radio": "outline/antenna",
    "door": "outline/door-enter",
    "enemy": "outline/alert-triangle",
    "intel": "outline/file-text",
    "power": "filled/bolt",
}


def diamond(width=0.075, inset=0.12):
    big = S * SS
    im = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(im)
    c = big / 2
    r = big / 2 - big * inset
    pts = [(c, c - r), (c + r, c), (c, c + r), (c - r, c)]
    d.polygon(pts, fill=255)
    r2 = r - big * width * 1.41
    d.polygon([(c, c - r2), (c + r2, c), (c, c + r2), (c - r2, c)], fill=0)
    # засечки по углам — «прицельный» вид
    t = big * 0.018
    for (x, y), (dx, dy) in zip(pts, ((0, -1), (1, 0), (0, 1), (-1, 0))):
        d.line((x + dx * big * 0.02, y + dy * big * 0.02, x + dx * big * 0.09, y + dy * big * 0.09), fill=255, width=int(t * 2))
    return im.resize((S, S), Image.LANCZOS)


def white(alpha):
    out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def marker(icon):
    a = diamond()
    if icon:
        g = H.render(os.path.join(H.tabler(), icon + ".svg"), size=int(S * 0.42)).split()[3]
        off = (S - g.size[0]) // 2
        a.paste(Image.eval(g, lambda v: v), (off, off), g)
    else:
        big = Image.new("L", (S * SS, S * SS), 0)
        ImageDraw.Draw(big).ellipse([S * SS * 0.42] * 2 + [S * SS * 0.58] * 2, fill=255)
        dot = big.resize((S, S), Image.LANCZOS)
        a = Image.composite(dot, a, dot)
    # тёмная обводка, чтобы метку было видно на снегу
    shadow = a.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(2))
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    base.paste((10, 14, 20, 255), (0, 0), Image.eval(shadow, lambda v: int(v * 0.55)))
    return Image.alpha_composite(base, white(a))


def glow():
    big = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(big)
    d.ellipse((S * 0.3, S * 0.3, S * 0.7, S * 0.7), fill=255)
    return white(big.filter(ImageFilter.GaussianBlur(S * 0.11)))


def arrow():
    big = Image.new("L", (S * SS, S * SS), 0)
    d = ImageDraw.Draw(big)
    B = S * SS
    d.polygon([(B * 0.5, B * 0.18), (B * 0.86, B * 0.62), (B * 0.66, B * 0.62), (B * 0.5, B * 0.42),
               (B * 0.34, B * 0.62), (B * 0.14, B * 0.62)], fill=255)
    d.polygon([(B * 0.5, B * 0.5), (B * 0.76, B * 0.82), (B * 0.62, B * 0.82), (B * 0.5, B * 0.67),
               (B * 0.38, B * 0.82), (B * 0.24, B * 0.82)], fill=150)
    return white(big.resize((S, S), Image.LANCZOS))


def ring():
    B = S * SS
    big = Image.new("L", (B, B), 0)
    ImageDraw.Draw(big).ellipse((B * 0.04, B * 0.04, B * 0.96, B * 0.96), outline=255, width=int(B * 0.03))
    return white(big.resize((S, S), Image.LANCZOS))


def zone():
    n = 256
    big = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(big)
    d.ellipse((4, 4, n - 4, n - 4), fill=60)
    d.ellipse((4, 4, n - 4, n - 4), outline=255, width=6)
    return white(big.filter(ImageFilter.GaussianBlur(1.5)))


def main():
    os.makedirs(OUT, exist_ok=True)
    for kind, icon in KINDS.items():
        marker(icon).save(os.path.join(OUT, kind + ".png"))
        print("  ", kind)
    glow().save(os.path.join(OUT, "glow.png"))
    arrow().save(os.path.join(OUT, "arrow.png"))
    ring().save(os.path.join(OUT, "ring.png"))
    zone().save(os.path.join(OUT, "zone.png"))
    print("   glow arrow ring zone")


if __name__ == "__main__":
    main()
