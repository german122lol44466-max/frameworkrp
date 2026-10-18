"""Прогон интро без Garry's Mod.

Загружает гейммод в обоих реалмах (Lua 5.4 через lupa, API GMod — проверяющие заглушки), затем покадрово
«проигрывает» интро от начала до конца (и отдельно — с пропуском на пробел). Ловит:
  - ошибки Lua в загрузке и в отрисовке каждого кадра;
  - nil / NaN / inf в аргументах surface.* и render.*;
  - ссылки на несуществующие материалы и звуки в content/;
  - что интро завершается и сообщает серверу.

    pip install lupa
    python3 tools/test/intro_sim.py
"""
import os
import sys

import lupa

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GM = os.path.join(ROOT, "gamemodes")
CONTENT = os.path.join(ROOT, "content")

PRELUDE = r'''
local CHECK = {}
function CHECK.num(fn, ...)
  local n = select("#", ...)
  for i = 1, n do
    local v = select(i, ...)
    if type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then
      error(fn .. ": аргумент " .. i .. " = " .. tostring(v), 3)
    end
    if v == nil then error(fn .. ": аргумент " .. i .. " = nil", 3) end
  end
end

function string.StartWith(s, p) return string.sub(s, 1, #p) == p end
function string.GetFileFromFilename(p) return string.match(p, "([^/]+)$") or p end
function string.Explode(sep, s)
  local out, pos = {}, 1
  while true do
    local a, b = string.find(s, sep, pos, true)
    if not a then out[#out + 1] = string.sub(s, pos) break end
    out[#out + 1] = string.sub(s, pos, a - 1)
    pos = b + 1
  end
  return out
end
function table.HasValue(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function table.Copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
math.atan2 = math.atan2 or math.atan  -- в LuaJIT (GMod) есть, в Lua 5.4+ — нет
function math.Clamp(v, a, b) return math.min(math.max(v, a), b) end
function math.Round(v, d) local m = 10 ^ (d or 0) return math.floor(v * m + 0.5) / m end
function math.Rand(a, b) return a + (b - a) * math.random() end
function math.Approach(c, t, d) if c < t then return math.min(c + d, t) else return math.max(c - d, t) end end
function Lerp(t, a, b) return a + (b - a) * t end
function IsValid(v) return v ~= nil and v ~= false and (type(v) ~= "table" or not v.__removed) end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
color_white = Color(255, 255, 255)
unpack = table.unpack
function MsgC(...) local t = {} for _, v in ipairs({ ... }) do if type(v) == "string" then t[#t + 1] = v end end print(table.concat(t)) end
function Msg(...) print(...) end

NOW = 100
function RealTime() return NOW end
function SysTime() return NOW end
function CurTime() return NOW end
function FrameTime() return 1 / 30 end
function ScrW() return SCRW end
function ScrH() return SCRH end
SCRW, SCRH = 1920, 1080

KEY_SPACE = 65
GMOD_CHANNEL_STOPPED, GMOD_CHANNEL_PLAYING = 0, 1
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = 0, 1, 2
BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD = 4, 1, 0
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 128, 8192, 256

-- хуки
hook = { t = {} }
function hook.Add(ev, id, fn) hook.t[ev] = hook.t[ev] or {} hook.t[ev][id] = fn end
function hook.Remove(ev, id) if hook.t[ev] then hook.t[ev][id] = nil end end
function hook.Run(ev, ...) for _, fn in pairs(hook.t[ev] or {}) do local r = fn(...) if r ~= nil then return r end end end
TIMERS = {}
timer = {}
function timer.Simple(d, fn) TIMERS[#TIMERS + 1] = fn end
function timer.Create(id, d, r, fn) end
function timer.Remove(id) end

-- конвары и cookie
local cvars = {}
local function cv(name, def)
  local c = { v = tostring(def) }
  function c:GetInt() return math.floor(tonumber(self.v) or 0) end
  function c:GetFloat() return tonumber(self.v) or 0 end
  function c:GetBool() return (tonumber(self.v) or 0) ~= 0 end
  function c:GetString() return self.v end
  cvars[name] = c
  return c
end
function CreateClientConVar(n, d) return cv(n, d) end
function CreateConVar(n, d) return cv(n, d) end
function GetConVar(n) return cvars[n] end
local cookies = {}
cookie = { Set = function(k, v) cookies[k] = v end, GetString = function(k, d) return cookies[k] or d end }
concommand = { t = {} }
function concommand.Add(n, fn) concommand.t[n] = fn end

-- сеть
NET_SENT = {}
net = { r = {} }
function net.Start(n) net.cur = { name = n } end
function net.WriteBool(b) net.cur.b = b end
function net.SendToServer() NET_SENT[#NET_SENT + 1] = net.cur end
function net.Receive(n, fn) net.r[n] = fn end
function net.ReadBool() return net.inb end
util = { AddNetworkString = function() end }
resource = { AddSingleFile = function(p) RESOURCES[#RESOURCES + 1] = p end, AddWorkshop = function() end }
RESOURCES = {}

-- отрисовка: всё проверяет аргументы
DRAWS = 0
local function drawfn(name) return function(...) CHECK.num(name, ...) DRAWS = DRAWS + 1 end end
local font = "Default"
surface = {
  SetDrawColor = drawfn("surface.SetDrawColor"), DrawRect = drawfn("surface.DrawRect"),
  DrawTexturedRect = drawfn("surface.DrawTexturedRect"), DrawTexturedRectUV = drawfn("surface.DrawTexturedRectUV"),
  DrawTexturedRectRotated = drawfn("surface.DrawTexturedRectRotated"), DrawOutlinedRect = drawfn("surface.DrawOutlinedRect"),
  SetTextColor = drawfn("surface.SetTextColor"), SetTextPos = drawfn("surface.SetTextPos"),
}
function surface.SetMaterial(m) if type(m) ~= "table" or not m.__mat then error("SetMaterial: не материал", 2) end end
function surface.SetFont(f) if not FONTS[f] then error("SetFont: шрифт не создан: " .. tostring(f), 2) end font = f end
function surface.DrawText(s) if type(s) ~= "string" then error("DrawText: " .. type(s), 2) end end
function surface.GetTextSize(s) return utf8.len(s) * (FONTS[font] and FONTS[font].size or 12) * 0.5, (FONTS[font] and FONTS[font].size or 12) end
FONTS = {}
function surface.CreateFont(n, d) CHECK.num("CreateFont", d.size) FONTS[n] = d end
draw = {}
function draw.SimpleText(t, f, x, y, c) CHECK.num("draw.SimpleText", x, y) surface.SetFont(f) end
function draw.RoundedBox(r, x, y, w, h, c) CHECK.num("draw.RoundedBox", r, x, y, w, h) end
render = {}
function render.SetScissorRect(...) CHECK.num("render.SetScissorRect", ...) end
function render.OverrideBlend(on, ...) if on then CHECK.num("render.OverrideBlend", ...) end end

MATERIALS = {}
function Material(p, flags) MATERIALS[#MATERIALS + 1] = p return { __mat = true, path = p } end

-- звук
SOUNDS = {}
sound = {}
function sound.PlayFile(path, flags, cb)
  SOUNDS[#SOUNDS + 1] = path
  local ch = { vol = 0, playing = false }
  function ch:SetVolume(v) CHECK.num("SetVolume", v) self.vol = v end
  function ch:Play() self.playing = true end
  function ch:Stop() self.playing = false self.__removed = true end
  function ch:EnableLooping() end
  function ch:GetState() return self.playing and GMOD_CHANNEL_PLAYING or GMOD_CHANNEL_STOPPED end
  -- как в игре: после Stop() канал становится NULL, любой вызов метода — ошибка
  for k, fn in pairs({ SetVolume = ch.SetVolume, Play = ch.Play, Stop = ch.Stop, EnableLooping = ch.EnableLooping, GetState = ch.GetState }) do
    ch[k] = function(self, ...)
      if self.__removed then error("Tried to use a NULL IGModAudioChannel!", 2) end
      return fn(self, ...)
    end
  end
  cb(ch, 0, nil)
end

-- vgui
PANELS = {}
vgui = {}
function vgui.Create(cls)
  local p = { cls = cls }
  function p:SetSize(w, h) end
  function p:SetPos() end
  function p:MakePopup() end
  function p:SetKeyboardInputEnabled() end
  function p:SetMouseInputEnabled() end
  function p:SetCursor() end
  function p:Remove() self.__removed = true end
  PANELS[#PANELS + 1] = p
  return p
end

-- файлы: LUA -> gamemodes/, GAME -> content/
function file.Find(pattern, where) return FIND(pattern, where) end
'''


def find(lua, pattern, where):
    import fnmatch
    base = GM if where == "LUA" else CONTENT
    d, pat = os.path.split(pattern)
    full = os.path.join(base, d)
    files, dirs = [], []
    if os.path.isdir(full):
        for n in sorted(os.listdir(full)):
            if fnmatch.fnmatch(n, pat):
                (dirs if os.path.isdir(os.path.join(full, n)) else files).append(n)
    return lua.table_from(files), lua.table_from(dirs)


def realm(server):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("file = {}")
    lua.execute(PRELUDE)
    g = lua.globals()
    g.FIND = lambda p, w: find(lua, p, w)
    g.SERVER, g.CLIENT = server, not server
    cur = ["whitesilence/gamemode"]

    def include(path):
        p = path if path.startswith("whitesilence/") else cur[0] + "/" + path
        src = open(os.path.join(GM, p), encoding="utf-8").read()
        prev = cur[0]
        cur[0] = os.path.dirname(p)
        try:
            return lua.execute(src, name="@" + p) if False else lua.eval("function(src, name) return assert(load(src, name))() end")(src, "@" + p)
        finally:
            cur[0] = prev
    g.include = include
    g.AddCSLuaFile = lambda *a: None
    g.DeriveGamemode = lambda *a: None
    lua.execute("GM = { FolderName = 'whitesilence' }")
    include("whitesilence/gamemode/" + ("init.lua" if server else "cl_init.lua"))
    return lua


def run_timers(lua):
    lua.execute("local t = TIMERS TIMERS = {} for _, fn in ipairs(t) do fn() end")


def check_paths(lua, errors):
    for p in lua.globals().MATERIALS.values():
        if not os.path.exists(os.path.join(CONTENT, "materials", p)):
            errors.append("нет материала: materials/" + p)
    for p in lua.globals().SOUNDS.values():
        if not os.path.exists(os.path.join(CONTENT, p)):
            errors.append("нет звука: " + p)


def play(skip_at=None, w=1920, h=1080):
    lua = realm(False)
    g = lua.globals()
    g.SCRW, g.SCRH = w, h
    # меню после интро проверяет tools/test/menu_sim.py; здесь — только интро
    lua.execute("hook.Remove('WSIntroFinished', 'ws.menu') hook.Remove('InitPostEntity', 'ws.menu')")
    lua.execute("hook.Run('InitPostEntity')")
    run_timers(lua)
    lua.execute("INTRO = PANELS[#PANELS]")
    assert lua.eval("INTRO") is not None, "панель интро не создана"
    t0 = g.NOW
    frames, skipped = 0, False
    while not lua.eval("INTRO.__removed"):
        dt = 1 / 30
        g.NOW = g.NOW + dt
        if skip_at and not skipped and g.NOW - t0 >= skip_at:
            lua.eval("INTRO.OnKeyCodePressed(INTRO, KEY_SPACE)")
            skipped = True
        lua.eval("INTRO.Paint(INTRO, SCRW, SCRH)")
        lua.execute("hook.Run('Think')")
        frames += 1
        if frames > 30 * 70:
            raise RuntimeError("интро не закончилось за 70 с")
    # выход из черноты в игру
    for _ in range(60):
        g.NOW = g.NOW + 1 / 30
        lua.execute("hook.Run('HUDPaint') hook.Run('Think')")
    sent = [(m["name"], m["b"]) for m in g.NET_SENT.values()]
    return lua, frames, sent


def main():
    errors = []
    srv = realm(True)
    ply = srv.eval("""(function()
        local p = { frozen = false, god = false, nw = {} }
        function p:Freeze(b) self.frozen = b end
        function p:GodEnable() self.god = true end
        function p:GodDisable() self.god = false end
        function p:EntIndex() return 1 end
        function p:GetNW2Bool(k, d) local v = self.nw[k] if v == nil then return d end return v end
        function p:StripWeapons() end
        function p:SetNoDraw(b) self.nodraw = b end
        function p:SetNotSolid() end
        function p:DrawShadow() end
        return p end)()""")
    srv.globals().net.inb = True
    srv.eval("net.r['ws.intro']")(None, ply)
    assert ply.frozen and ply.god, "сервер не заморозил игрока"
    srv.globals().NOW = srv.globals().NOW + 2
    srv.globals().net.inb = False
    srv.eval("net.r['ws.intro']")(None, ply)
    # после интро игрок в главном меню: остаётся замороженным и невидимым, пока отряд не выдвинется
    assert ply.frozen and ply.god and ply.nodraw, "после интро игрок не в состоянии меню"
    res = list(srv.globals().RESOURCES.values())
    print("сервер: заморозка на интро и состояние меню после него — ок, файлов в раздаче:", len(res))

    for label, kw in (("целиком 1920x1080", {}), ("целиком 2560x1080 (21:9)", {"w": 2560, "h": 1080}),
                      ("целиком 1280x1024 (5:4)", {"w": 1280, "h": 1024}), ("пропуск на 7 с", {"skip_at": 7.0})):
        lua, frames, sent = play(**kw)
        check_paths(lua, errors)
        print("%-26s кадров %4d (%.1f с), отрисовок %d, сеть %s" % (label, frames, frames / 30, lua.globals().DRAWS, sent))
        if sent != [("ws.intro", True), ("ws.intro", False)]:
            errors.append(label + ": неверные сообщения серверу " + str(sent))
    snd = sorted(set(lua.globals().SOUNDS.values()))
    print("звуки:", ", ".join(os.path.basename(s) for s in snd))
    for e in sorted(set(errors)):
        print("ОШИБКА:", e)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
