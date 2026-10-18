"""Кадры главного меню и лобби так, как их нарисует игра (2D-часть; 3D-бойцы без движка не рисуются).

    python3 tools/test/menu_frames.py [папка]          (по умолчанию /tmp/ws_menu_frames)
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import intro_frames as fr  # noqa: E402
import intro_sim as sim  # noqa: E402
import menu_sim as ms  # noqa: E402

LAYOUT = r'''
-- раскладка панелей для превью: смещения детей, Dock TOP/FILL
function PanelMeta:SetPos(x, y) self.x, self.y = x, y end
function PanelMeta:Dock(d) self.dock = d end
local CH = {}
local function offset(fn, ix, iy)
  return function(...)
    local a = { ... }
    a[ix] = a[ix] + OFFX
    a[iy] = a[iy] + OFFY
    return fn(table.unpack(a, 1, select("#", ...)))
  end
end
function WrapOffsets()
  for _, n in ipairs({ "DrawRect", "DrawOutlinedRect", "DrawTexturedRect", "DrawTexturedRectUV", "DrawTexturedRectRotated", "SetTextPos" }) do
    surface[n] = offset(surface[n], 1, 2)
  end
  draw.SimpleText = offset(draw.SimpleText, 3, 4)
  draw.RoundedBox = offset(draw.RoundedBox, 2, 3)
end
OFFX, OFFY = 0, 0
function PaintTree(p, depth, ox, oy)
  if p.__removed or (depth or 0) > 12 or p.visible == false then return end
  ox, oy = (ox or 0) + (p.x or 0), (oy or 0) + (p.y or 0)
  OFFX, OFFY = ox, oy
  if p.cls == "AvatarImage" then
    surface.SetDrawColor(70, 80, 95, 255) surface.DrawRect(0, 0, p.w or 40, p.h or 40)
    surface.SetDrawColor(120, 135, 150, 255) surface.DrawRect((p.w or 40) * 0.3, (p.h or 40) * 0.2, (p.w or 40) * 0.4, (p.h or 40) * 0.4)
  end
  if p.Paint then p:Paint(p.w or 200, p.h or 40) end
  local ty = 0
  for _, c in ipairs(p.children) do
    if c.dock == TOP then c.x, c.y, c.w = 0, ty, p.w ty = ty + (c.h or 30) end
    if c.dock == FILL then c.x, c.y, c.w, c.h = 0, 0, p.w, p.h end
    PaintTree(c, (depth or 0) + 1, ox, oy)
    OFFX, OFFY = ox, oy
  end
  if p.PaintOver then p:PaintOver(p.w or 200, p.h or 40) end
end
function PanelMeta:SetVisible(v) self.visible = v end
'''


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ws_menu_frames"
    os.makedirs(out, exist_ok=True)
    W, H = 1280, 720
    base = sim.PRELUDE
    sim.PRELUDE = base + ms.EXTRA + ms.VGUI + LAYOUT
    try:
        lua = sim.realm(False)
    finally:
        sim.PRELUDE = base
    g = lua.globals()
    g.SCRW, g.SCRH = W, H
    cv = fr.Canvas(W, H)
    fr.bind(lua, cv)
    lua.execute("WrapOffsets()")
    lua.execute("""
      Me = MakePlayer("Me", 1) Fr = MakePlayer("Friend", 2) Ot = MakePlayer("Ghost-7", 3)
      Me.name = "John Make" Fr.name = "Сокол" Me:SetNW2String("ws_callsign", "Купол-1")
      Me:SetNW2Int("ws_lobby", 3) Me:SetNW2Bool("ws_lead", true) Fr:SetNW2Int("ws_lobby", 3) Fr:SetNW2Float("ws_lobby_t", 5)
      Ot:SetNW2Int("ws_lobby", 9)
      WS.Intro.IsPlaying = function() return false end
      WS.Menu.Open()
      for _, p in ipairs(VGUI_ALL) do if p.cls == "EditablePanel" then ROOT = p end end
      ROOT.w, ROOT.h = SCRW, SCRH
    """)

    def frame(name, steps, hover=None):
        for i in range(steps):
            g.NOW = g.NOW + 1 / 30
            cv.img[:] = 0
            if hover:
                lua.execute('local b = FindButton("%s") if b then b.hover = true end' % hover)
            lua.execute("PaintTree(ROOT)")
            lua.execute("local t = TIMERS TIMERS = {} for _, fn in ipairs(t) do fn() end")
        Image.fromarray(np.clip(cv.img, 0, 255).astype(np.uint8)).save(os.path.join(out, name + ".jpg"), quality=90)
        print(name)

    frame("1_main", 60)
    frame("2_main_hover", 90, hover="ИГРАТЬ")
    lua.execute('FindButton("ИГРАТЬ").hover = false FindButton("ИГРАТЬ"):DoClick()')
    frame("3_lobby", 45)
    lua.execute('net.inent, net.inf = Ot, 30 net.r["ws.lobby.invited"]() net.instr = { "Приглашение отправлено: Ghost-7.", "" } net.r["ws.lobby.notify"]()')
    frame("4_lobby_invite", 20)


if __name__ == "__main__":
    main()
