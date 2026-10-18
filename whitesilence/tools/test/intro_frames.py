"""Кадры интро так, как их нарисует игра: тот же Lua-код, но surface.* рисуют в картинку (Pillow).

    python3 tools/test/intro_frames.py [папка] [секунды через запятую]

По умолчанию пишет в /tmp/ws_frames кадры на ключевых секундах (1280x720). Нужно для проверки композиции,
титров и эффектов без запуска Garry's Mod. Смешивание и фильтрация упрощены (как в игре — не до пикселя).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import intro_sim as sim  # noqa: E402

FONTS = os.path.join(sim.CONTENT, "resource", "fonts")
FAMILY = {
    ("Cormorant Garamond Medium", False): "CormorantGaramond_500Medium.ttf",
    ("Cormorant Garamond Medium", True): "CormorantGaramond_500Medium_Italic.ttf",
    ("Cormorant Garamond SemiBold", False): "CormorantGaramond_600SemiBold.ttf",
    ("Oswald Medium", False): "Oswald_500Medium.ttf",
    ("Oswald Light", False): "Oswald_300Light.ttf",
    ("IBM Plex Mono", False): "IBMPlexMono_400Regular.ttf",
    ("Alegreya Sans SC", False): "AlegreyaSansSC_700Bold.ttf",
    ("Alegreya Sans SC Medium", False): "AlegreyaSansSC_500Medium.ttf",
    ("Alegreya Sans SC ExtraBold", False): "AlegreyaSansSC_800ExtraBold.ttf",
    ("Exo 2", False): "Exo2_400Regular.ttf",
    ("Exo 2 Light", False): "Exo2_300Light.ttf",
    ("Exo 2 SemiBold", False): "Exo2_600SemiBold.ttf",
    ("Exo 2 Bold", False): "Exo2_700Bold.ttf",
}


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = np.zeros((h, w, 3), np.float32)
        self.col = (255, 255, 255, 255)
        self.tcol = (255, 255, 255, 255)
        self.mat = None
        self.add = False
        self.sc = None
        self.font = None
        self.tpos = (0, 0)
        self.tex = {}
        self.sized = {}
        self.fonts = {}
        self.fontdefs = {}

    # ------------------------------------------------ смешивание
    def comp(self, rgb, a, x, y):
        h, w = a.shape
        x0, y0 = int(round(x)), int(round(y))
        cx0, cy0, cx1, cy1 = 0, 0, self.w, self.h
        if self.sc:
            cx0, cy0, cx1, cy1 = [int(v) for v in self.sc]
        ax0, ay0 = max(x0, cx0, 0), max(y0, cy0, 0)
        ax1, ay1 = min(x0 + w, cx1, self.w), min(y0 + h, cy1, self.h)
        if ax1 <= ax0 or ay1 <= ay0:
            return
        s = (slice(ay0 - y0, ay1 - y0), slice(ax0 - x0, ax1 - x0))
        d = (slice(ay0, ay1), slice(ax0, ax1))
        aa = a[s][..., None]
        if self.add:
            self.img[d] = np.minimum(self.img[d] + rgb[s] * aa, 255)
        else:
            self.img[d] = self.img[d] * (1 - aa) + rgb[s] * aa

    def texture(self, path):
        if path not in self.tex:
            im = Image.open(os.path.join(sim.CONTENT, "materials", path)).convert("RGBA")
            self.tex[path] = im
        return self.tex[path]

    def sprite(self, w, h):
        w, h = max(1, int(round(w))), max(1, int(round(h)))
        key = (self.mat, w, h)
        if key not in self.sized:
            im = self.texture(self.mat).resize((w, h), Image.BILINEAR)
            arr = np.asarray(im, np.float32)
            if len(self.sized) > 400:
                self.sized.clear()
            self.sized[key] = arr
        return self.sized[key]

    def tinted(self, arr):
        r, g, b, a = self.col
        rgb = arr[..., :3] * (np.array([r, g, b], np.float32) / 255)
        return rgb, arr[..., 3] / 255 * (a / 255)

    # ------------------------------------------------ surface.*
    def SetDrawColor(self, r, g=None, b=None, a=255):
        if isinstance(r, (int, float)):
            self.col = (r, g, b, a if a is not None else 255)
        else:
            self.col = (r["r"], r["g"], r["b"], r["a"] or 255)

    def DrawRect(self, x, y, w, h):
        w, h = int(round(w)), int(round(h))
        if w <= 0 or h <= 0:
            return
        r, g, b, a = self.col
        rgb = np.broadcast_to(np.array([r, g, b], np.float32), (h, w, 3))
        self.comp(rgb, np.full((h, w), a / 255, np.float32), x, y)

    def DrawOutlinedRect(self, x, y, w, h, t=1):
        self.DrawRect(x, y, w, t)
        self.DrawRect(x, y + h - t, w, t)
        self.DrawRect(x, y, t, h)
        self.DrawRect(x + w - t, y, t, h)

    def DrawTexturedRect(self, x, y, w, h):
        if w < 1 or h < 1 or x > self.w or y > self.h or x + w < 0 or y + h < 0:
            return
        # большие картинки: режем видимую часть до ресайза
        tex = self.texture(self.mat)
        if w * h > 4e5:
            tw, th = tex.size
            vx0, vy0 = max(0, -x), max(0, -y)
            vx1, vy1 = min(w, self.w - x), min(h, self.h - y)
            box = (vx0 / w * tw, vy0 / h * th, vx1 / w * tw, vy1 / h * th)
            im = tex.resize((int(vx1 - vx0) + 1, int(vy1 - vy0) + 1), Image.BILINEAR, box=box)
            rgb, a = self.tinted(np.asarray(im, np.float32))
            self.comp(rgb, a, x + vx0, y + vy0)
            return
        rgb, a = self.tinted(self.sprite(w, h))
        self.comp(rgb, a, x, y)

    def DrawTexturedRectUV(self, x, y, w, h, u0, v0, u1, v1):
        w, h = int(round(w)), int(round(h))
        if w <= 0 or h <= 0:
            return
        tex = np.asarray(self.texture(self.mat), np.float32)
        th, tw = tex.shape[:2]
        us = ((u0 + (u1 - u0) * (np.arange(w) + 0.5) / w) * tw).astype(int) % tw
        vs = ((v0 + (v1 - v0) * (np.arange(h) + 0.5) / h) * th).astype(int) % th
        arr = tex[vs][:, us]
        rgb, a = self.tinted(arr)
        self.comp(rgb, a, x, y)

    def DrawTexturedRectRotated(self, x, y, w, h, rot):
        arr = self.sprite(w, h)
        im = Image.fromarray(arr.astype(np.uint8), "RGBA").rotate(rot, expand=True, resample=Image.BILINEAR)
        rgb, a = self.tinted(np.asarray(im, np.float32))
        self.comp(rgb, a, x - im.width / 2, y - im.height / 2)

    def SetMaterial(self, m):
        self.mat = m["path"]

    # ------------------------------------------------ текст
    def CreateFont(self, name, d):
        fam = d["font"]
        if fam == "Exo 2" and (d["weight"] or 400) >= 700:
            fam = "Exo 2 Bold"   # в GMod «Exo 2» с weight 700 берёт жирное начертание
        self.fontdefs[name] = (fam, bool(d["italic"]), int(d["size"]), int(d["blursize"] or 0))

    def pil_font(self, name):
        if name not in self.fonts:
            fam, it, size, blur = self.fontdefs[name]
            path = os.path.join(FONTS, FAMILY.get((fam, it), "IBMPlexMono_400Regular.ttf"))
            self.fonts[name] = (ImageFont.truetype(path, size), blur)
        return self.fonts[name]

    def SetFont(self, f):
        self.font = f

    def GetTextSize(self, s):
        f, _ = self.pil_font(self.font)
        asc, desc = f.getmetrics()
        return f.getlength(s), asc + desc

    def SetTextColor(self, r, g=None, b=None, a=255):
        if isinstance(r, (int, float)):
            self.tcol = (r, g, b, a if a is not None else 255)
        else:
            self.tcol = (r["r"], r["g"], r["b"], r["a"] or 255)

    def SetTextPos(self, x, y):
        self.tpos = (x, y)

    def DrawText(self, s):
        f, blur = self.pil_font(self.font)
        tw, th = self.GetTextSize(s)
        pad = blur * 3 + 4
        im = Image.new("L", (int(tw) + pad * 2 + 2, int(th) + pad * 2 + 2), 0)
        ImageDraw.Draw(im).text((pad, pad), s, font=f, fill=255)
        if blur:
            im = im.filter(ImageFilter.GaussianBlur(blur * 0.6))
        r, g, b, a = self.tcol
        al = np.asarray(im, np.float32) / 255 * (a / 255)
        rgb = np.broadcast_to(np.array([r, g, b], np.float32), al.shape + (3,))
        self.comp(rgb, al, self.tpos[0] - pad, self.tpos[1] - pad)
        self.tpos = (self.tpos[0] + tw, self.tpos[1])

    def SimpleText(self, t, font, x, y, col, ax=0, ay=0):
        self.SetFont(font)
        w, h = self.GetTextSize(t)
        x = x - (w / 2 if ax == 1 else (w if ax == 2 else 0))
        y = y - (h / 2 if ay == 1 else (h if ay == 4 else 0))
        self.SetTextColor(col)
        self.SetTextPos(x, y)
        self.DrawText(t)

    def RoundedBox(self, r, x, y, w, h, col):
        self.SetDrawColor(col)
        self.DrawRect(x, y, w, h)

    def Scissor(self, x0, y0, x1, y1, on):
        self.sc = (x0, y0, x1, y1) if on else None

    def Blend(self, on, *a):
        self.add = bool(on)


def bind(lua, cv):
    g = lua.globals()
    s = g.surface
    for n in ("SetDrawColor", "DrawRect", "DrawOutlinedRect", "DrawTexturedRect", "DrawTexturedRectUV",
              "DrawTexturedRectRotated", "SetMaterial", "SetFont", "GetTextSize", "SetTextColor", "SetTextPos", "DrawText"):
        s[n] = getattr(cv, n)
    orig_create = s.CreateFont

    def create(name, d):
        orig_create(name, d)
        cv.CreateFont(name, d)
    s.CreateFont = create
    g.draw.SimpleText = cv.SimpleText
    g.draw.RoundedBox = cv.RoundedBox
    g.render.SetScissorRect = cv.Scissor
    g.render.OverrideBlend = cv.Blend


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ws_frames"
    times = [float(x) for x in sys.argv[2].split(",")] if len(sys.argv) > 2 else \
        [0.8, 2.5, 5.0, 9.0, 11.3, 13.5, 16.5, 18.8, 21.5, 25.0, 28.5, 32.0, 36.0, 40.0, 43.4, 46.0, 48.5]
    os.makedirs(out, exist_ok=True)
    W, H = 1280, 720
    lua = sim.realm(False)
    g = lua.globals()
    g.SCRW, g.SCRH = W, H
    real = {}
    for n in ("SetDrawColor", "DrawRect", "DrawOutlinedRect", "DrawTexturedRect", "DrawTexturedRectUV",
              "DrawTexturedRectRotated", "SetMaterial", "SetFont", "GetTextSize", "SetTextColor", "SetTextPos", "DrawText"):
        real[n] = g.surface[n]
    real_simple = g.draw.SimpleText
    cv = Canvas(W, H)
    bind(lua, cv)  # шрифты создаются и в Canvas
    lua.execute("hook.Remove('WSIntroFinished', 'ws.menu') hook.Remove('InitPostEntity', 'ws.menu')")
    lua.execute("hook.Run('InitPostEntity')")
    sim.run_timers(lua)
    lua.execute("INTRO = PANELS[#PANELS]")
    t0 = g.NOW
    todo = sorted(times)
    while todo and not lua.eval("INTRO.__removed"):
        g.NOW = g.NOW + 1 / 30
        t = g.NOW - t0
        shoot = t >= todo[0] - 1e-6
        # рисуем в картинку только нужные кадры, остальные — через быстрые заглушки
        for n, fn in real.items():
            g.surface[n] = getattr(cv, n) if shoot else fn
        g.draw.SimpleText = cv.SimpleText if shoot else real_simple
        cv.img[:] = 0
        lua.eval("INTRO.Paint(INTRO, SCRW, SCRH)")
        lua.execute("hook.Run('Think')")
        if shoot:
            Image.fromarray(np.clip(cv.img, 0, 255).astype(np.uint8)).save(os.path.join(out, "t%05.1f.jpg" % t), quality=90)
            print("кадр %.1f с" % t)
            todo.pop(0)


if __name__ == "__main__":
    main()
