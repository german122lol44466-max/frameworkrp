"""Проверка главного меню и отрядов без Garry's Mod.

Сервер: несколько фейковых игроков с NW2-переменными проходят сценарий — открыть лобби, пригласить,
принять/отклонить, позывной (в т.ч. мусорный), исключить, покинуть, выдвинуться. Проверяется состояние.
Клиент: меню открывается после интро, рисуется ~15 с (3D-сцена, искры, кнопки), переходит в лобби,
показывает приглашение, закрывается по ws.lobby.started. Ловятся ошибки Lua и nil/NaN в отрисовке.

    python3 tools/test/menu_sim.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import intro_sim as sim  # noqa: E402

EXTRA = r'''
function CHECK_NUM(fn, ...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v == nil or (type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge)) then
      error(fn .. ": аргумент " .. i .. " = " .. tostring(v), 2)
    end
  end
end
-- игроки с NW2
PLAYERS = {}
local PlyMeta = {}
PlyMeta.__index = PlyMeta
function MakePlayer(name, idx)
  local p = setmetatable({ name = name, idx = idx, nw = {}, frozen = false, god = false, nodraw = false, pdata = {},
    weps = {}, spawned = 0, model = "" }, PlyMeta)
  PLAYERS[#PLAYERS + 1] = p
  return p
end
function PlyMeta:GetNW2Int(k, d) local v = self.nw[k] if v == nil then return d end return v end
PlyMeta.GetNW2Bool = PlyMeta.GetNW2Int PlyMeta.GetNW2Float = PlyMeta.GetNW2Int PlyMeta.GetNW2String = PlyMeta.GetNW2Int
function PlyMeta:SetNW2Int(k, v) self.nw[k] = v end
PlyMeta.SetNW2Bool = PlyMeta.SetNW2Int PlyMeta.SetNW2Float = PlyMeta.SetNW2Int PlyMeta.SetNW2String = PlyMeta.SetNW2Int
function PlyMeta:Nick() return self.name end
function PlyMeta:IsPlayer() return true end
function PlyMeta:IsBot() return false end
function PlyMeta:EntIndex() return self.idx end
function PlyMeta:IsSuperAdmin() return false end
function PlyMeta:Freeze(b) self.frozen = b end
function PlyMeta:GodEnable() self.god = true end
function PlyMeta:GodDisable() self.god = false end
function PlyMeta:SetNoDraw(b) self.nodraw = b end
function PlyMeta:SetNotSolid() end
function PlyMeta:DrawShadow() end
function PlyMeta:StripWeapons() self.weps = {} end
function PlyMeta:Give(c) self.weps[#self.weps + 1] = c end
function PlyMeta:SelectWeapon() end
function PlyMeta:SetModel(m) self.model = m end
function PlyMeta:SetupHands() end
function PlyMeta:Spawn() self.spawned = self.spawned + 1 hook.Run("PlayerSpawn", self) hook.Run("PlayerLoadout", self) hook.Run("PlayerSetModel", self) end
for _, m in ipairs({ "SetWalkSpeed", "SetRunSpeed", "SetSlowWalkSpeed", "SetCrouchedWalkSpeed", "SetJumpPower",
  "SetDuckSpeed", "SetUnDuckSpeed", "AllowFlashlight", "Flashlight", "SetAvoidPlayers" }) do
  PlyMeta[m] = PlyMeta[m] or function(self, v) self["_" .. m] = v end
end
function PlyMeta:Alive() return true end
function PlyMeta:SetPos(p) self.pos = p end
function PlyMeta:GetPos() return self.pos or Vector() end
function PlyMeta:SetEyeAngles() end
function PlyMeta:SetNW2Entity() end
function PlyMeta:GetAmmoCount(t) self.ammo = self.ammo or {} return self.ammo[t] or 0 end
function PlyMeta:SetAmmo(n, t) self.ammo = self.ammo or {} self.ammo[t] = n end
function PlyMeta:SetHealth(h) self.hp = h end
function PlyMeta:Health() return self.hp or 100 end
function PlyMeta:GetMaxHealth() return 100 end
function PlyMeta:EmitSound() end
function PlyMeta:ChatPrint() end
function PlyMeta:UnSpectate() end
function PlyMeta:Spectate() end
function PlyMeta:GetPData(k, d) return self.pdata[k] or d end
function PlyMeta:SetPData(k, v) self.pdata[k] = v end
function PlyMeta:RemovePData(k) self.pdata[k] = nil end
player = { GetAll = function() local o = {} for _, p in ipairs(PLAYERS) do if not p.gone then o[#o + 1] = p end end return o end }
function LocalPlayer() return PLAYERS[1] end
function string.Trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
function isstring(v) return type(v) == "string" end
NET_TO = {}
net.Send = function(target)
  for _, pre in ipairs({ "ws.story", "ws.ach", "ws.inv", "ws.hand" }) do   -- сюжет, достижения, инвентарь здесь не проверяются
    if string.StartWith(net.cur.name, pre) then return end
  end
  NET_TO[#NET_TO + 1] = { name = net.cur.name, target = target, data = net.cur }
end
net.WriteEntity = function(e) net.cur.ent = e end
net.WriteString = function(s) net.cur.str = (net.cur.str and (net.cur.str .. "\0") or "") .. s end
net.WriteFloat = function(f) net.cur.f = f end
net.ReadEntity = function() return net.inent end
net.ReadString = function() local v = net.instr and table.remove(net.instr, 1) or "" return v end
net.ReadFloat = function() return net.inf or 30 end
function RecvAs(name, ply, fields)
  net.inb, net.inent, net.instr, net.inf = fields.b, fields.ent, fields.str, fields.f
  net.r[name](0, ply)
end
weapons = { GetStored = function(c) if c == "tfa_ins2_ak12" or c == "tfa_ins2_usp_match" then return { WorldModel = "models/w_ak12.mdl" } end end }
util.IsValidModel = function(m) return m ~= "models/kuma96/winterizedarmor/winterizedarmor_pm.mdl" end
timer.Create = function() end
timer.Remove = function() end

-- клиентские заглушки для 3D и vgui
local function permissive(name)
  local t = {}
  return setmetatable(t, { __index = function(_, k) return function() end end })
end
cam = { Start3D = function(...) CHECK_NUM("cam.Start3D", ...) end, End3D = function() end }
for _, f in ipairs({ "ClearDepth", "SuppressEngineLighting", "ResetModelLighting", "SetModelLighting", "FogMode",
  "FogStart", "FogEnd", "FogMaxDensity", "FogColor", "SetBlend" }) do
  render[f] = function(...) CHECK_NUM("render." .. f, ...) end
end
BOX_TOP, BOX_FRONT, BOX_BACK, BOX_RIGHT, BOX_LEFT, BOX_BOTTOM = 0, 1, 2, 3, 4, 5
MATERIAL_FOG_LINEAR, MATERIAL_FOG_NONE, RENDERGROUP_OPAQUE, EF_BONEMERGE = 1, 0, 7, 1
MOUSE_LEFT, TOP, FILL = 107, 4, 1
MODELS = 0
local EntMeta = {}
EntMeta.__index = EntMeta
function ClientsideModel(m) MODELS = MODELS + 1 return setmetatable({ mdl = m, pose = {}, cycle = 0 }, EntMeta) end
function EntMeta:SetNoDraw() end
function EntMeta:SetSkin() end
function EntMeta:SetParent() end
function EntMeta:AddEffects() end
function EntMeta:LookupSequence(n) if n == "walk_ar2" then return 5 elseif n == "idle_ar2" then return 3 end return -1 end
function EntMeta:GetSequenceGroundSpeed() return 76 end
function EntMeta:SequenceDuration() return 1.1 end
function EntMeta:SetPos(p) CHECK_NUM("SetPos", p.x, p.y, p.z) self.pos = p end
function EntMeta:SetAngles(a) CHECK_NUM("SetAngles", a.p, a.y, a.r) end
function EntMeta:SetSequence(s) self.seq = s end
function EntMeta:SetPoseParameter(k, v) CHECK_NUM("SetPoseParameter", v) end
function EntMeta:SetCycle(c) CHECK_NUM("SetCycle", c) if c < 0 or c > 1 then error("cycle " .. c) end end
function EntMeta:InvalidateBoneCache() end
function EntMeta:SetupBones() end
function EntMeta:DrawModel() DRAWS = DRAWS + 1 end
function EntMeta:Remove() self.__removed = true MODELS = MODELS - 1 end

local VecMeta = {}
VecMeta.__index = VecMeta
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VecMeta) end
VecMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VecMeta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VecMeta.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function VecMeta:Distance(o) return math.sqrt((self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2) end
function VecMeta:GetNormalized() local l = math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) if l == 0 then return Vector() end return Vector(self.x / l, self.y / l, self.z / l) end
function VecMeta:Angle() return Angle(0, math.deg(math.atan(self.y, self.x)), 0) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
input = input or {} input.IsMouseDown = function() return false end
function RunConsoleCommand(...) CMDS = (CMDS or "") .. table.concat({ ... }, " ") .. ";" end
function utf8.sub(s, a, b) return s end
'''

# vgui в клиентском режиме: панели с методами-заглушками, но настоящими Paint/DoClick
VGUI = r'''
local PanelMeta = {}
PanelMeta.__index = function(t, k)
  local v = rawget(PanelMeta, k)
  if v ~= nil then return v end
  if type(k) == "string" and k:sub(1, 2) == "__" then return nil end   -- служебные поля (__removed) не подменяем
  if type(k) == "string" and k:match("^[A-Z]") and k ~= "Paint" and k ~= "PaintOver" and k ~= "Think"
    and k ~= "DoClick" and k ~= "OnCursorEntered" and k ~= "OnEnter" and k ~= "OnLoseFocus" then
    return function() end
  end
  return nil
end
function PanelMeta:SetSize(w, h) CHECK_NUM("SetSize", w, h) self.w, self.h = w, h end
function PanelMeta:SetPos(x, y) CHECK_NUM("SetPos", x, y) end
function PanelMeta:GetWide() return self.w or 100 end
function PanelMeta:GetTall() return self.h or 30 end
function PanelMeta:SetTall(h) self.h = h end
function PanelMeta:LocalToScreen(x, y) return x, y end
function PanelMeta:IsHovered() return self.hover or false end
function PanelMeta:IsChildHovered() return false end
function PanelMeta:Remove() self.__removed = true end
function PanelMeta:GetValue() return self.value or "" end
function PanelMeta:SetText(t) self.text = t end
VGUI_ALL = {}
vgui.Create = function(cls, parent)
  local p = setmetatable({ cls = cls, parent = parent, children = {} }, PanelMeta)
  if parent then parent.children[#parent.children + 1] = p end
  VGUI_ALL[#VGUI_ALL + 1] = p
  PANELS[#PANELS + 1] = p
  return p
end
function PaintTree(p, depth)
  if p.__removed or (depth or 0) > 12 then return end
  if p.Paint then p:Paint(p.w or 200, p.h or 40) end
  if p.Think then p:Think() end
  for _, c in ipairs(p.children) do PaintTree(c, (depth or 0) + 1) end
  if p.PaintOver then p:PaintOver(p.w or 200, p.h or 40) end
end
function FindButton(label)
  for _, p in ipairs(VGUI_ALL) do
    if not p.__removed and p.Label == label then
      local q, ok = p, true
      while q do if q.__removed then ok = false end q = q.parent end
      if ok then return p end
    end
  end
end
'''


def server_test(errors):
    lua = sim.realm(True)
    lua.execute(EXTRA)
    # заново подключить модуль лобби поверх новых заглушек player/net
    for f in ("whitesilence/gamemode/modules/lobby/sh_lobby.lua", "whitesilence/gamemode/modules/lobby/sv_lobby.lua"):
        lua.globals().include(f)
    run = lua.execute
    run("""
      A = MakePlayer("Alpha", 1) B = MakePlayer("Bravo", 2) Cc = MakePlayer("Charlie", 3) D = MakePlayer("Delta", 4)
      for _, p in ipairs(PLAYERS) do hook.Run("PlayerInitialSpawn", p) p:Spawn() end
      local function tick() NOW = NOW + 2 local t = TIMERS TIMERS = {} for _, fn in ipairs(t) do fn() end end
      for _, p in ipairs(PLAYERS) do RecvAs("ws.lobby.open", p, {}) end
      assert(A:GetNW2Int("ws_lobby") > 0 and A:GetNW2Int("ws_lobby") ~= B:GetNW2Int("ws_lobby"), "у каждого свой отряд")
      assert(A:GetNW2Bool("ws_lead"), "A командир своего")
      assert(#A.weps == 0, "в меню без оружия")
      -- A приглашает B, B принимает
      RecvAs("ws.lobby.invite", A, { ent = B }) tick()
      assert(NET_TO[#NET_TO - 1].name == "ws.lobby.invited" and NET_TO[#NET_TO - 1].target == B, "B получил приглашение")
      RecvAs("ws.lobby.answer", B, { b = true }) tick()
      assert(B:GetNW2Int("ws_lobby") == A:GetNW2Int("ws_lobby"), "B в отряде A")
      assert(not B:GetNW2Bool("ws_lead"), "B не командир")
      -- C отклоняет
      RecvAs("ws.lobby.invite", A, { ent = Cc }) tick()
      RecvAs("ws.lobby.answer", Cc, { b = false }) tick()
      assert(Cc:GetNW2Int("ws_lobby") ~= A:GetNW2Int("ws_lobby"), "C отказался")
      -- ответ без приглашения игнорируется
      RecvAs("ws.lobby.answer", D, { b = true }) tick()
      assert(D:GetNW2Int("ws_lobby") ~= A:GetNW2Int("ws_lobby"), "D без приглашения не вошёл")
      -- позывные
      RecvAs("ws.lobby.callsign", B, { str = { "Сокол-2" } }) tick()
      assert(B:GetNW2String("ws_callsign") == "Сокол-2", "позывной кириллицей")
      RecvAs("ws.lobby.callsign", B, { str = { "<script>" } }) tick()
      assert(B:GetNW2String("ws_callsign") == "Сокол-2", "мусорный позывной отклонён")
      RecvAs("ws.lobby.callsign", B, { str = { "x" } }) tick()
      assert(B:GetNW2String("ws_callsign") == "Сокол-2", "слишком короткий отклонён")
      assert(WS.Lobby.Name(B) == "Сокол-2" and WS.Lobby.Name(A) == "Alpha", "имя = позывной или ник")
      -- B (не командир) не может выдвинуть отряд и исключать
      RecvAs("ws.lobby.start", B, {}) tick()
      assert(not A:GetNW2Bool("ws_ingame"), "боец не может выдвинуть отряд")
      RecvAs("ws.lobby.kick", B, { ent = A }) tick()
      assert(A:GetNW2Int("ws_lobby") == B:GetNW2Int("ws_lobby"), "боец не может исключать")
      -- D в отряд, затем командир исключает D
      RecvAs("ws.lobby.invite", A, { ent = D }) tick()
      RecvAs("ws.lobby.answer", D, { b = true }) tick()
      assert(D:GetNW2Int("ws_lobby") == A:GetNW2Int("ws_lobby"), "D вошёл")
      RecvAs("ws.lobby.kick", A, { ent = D }) tick()
      assert(D:GetNW2Int("ws_lobby") ~= A:GetNW2Int("ws_lobby") and D:GetNW2Bool("ws_lead"), "D исключён и получил свой отряд")
      -- командир уходит — командиром становится B
      RecvAs("ws.lobby.leave", A, {}) tick()
      assert(B:GetNW2Bool("ws_lead"), "B стал командиром после ухода A")
      -- A обратно, B выдвигает
      RecvAs("ws.lobby.invite", B, { ent = A }) tick()
      RecvAs("ws.lobby.answer", A, { b = true }) tick()
      RecvAs("ws.lobby.start", B, {}) tick()
      assert(A:GetNW2Bool("ws_ingame") and B:GetNW2Bool("ws_ingame"), "отряд в игре")
      assert(not A.frozen and not A.nodraw and not A.god, "в игре: разморожен, видим")
      assert(#A.weps == 2 and A.weps[1] == "tfa_ins2_ak12", "оружие выдано")
      assert(A.model == "models/player/combine_super_soldier.mdl", "запасная модель, если аддона нет")
      assert(not Cc:GetNW2Bool("ws_ingame") and Cc.frozen and Cc.nodraw, "C остался в меню")
      -- приглашать тех, кто в игре, нельзя
      local before = #NET_TO
      RecvAs("ws.lobby.invite", Cc, { ent = A }) tick()
      assert(NET_TO[#NET_TO].target ~= A or NET_TO[#NET_TO].name ~= "ws.lobby.invited", "нельзя пригласить игрока в игре")
      -- переполнение: отряд из 5
      E1 = MakePlayer("E1", 5) E2 = MakePlayer("E2", 6) E3 = MakePlayer("E3", 7) E4 = MakePlayer("E4", 8) E5 = MakePlayer("E5", 9)
      for _, p in ipairs({ E1, E2, E3, E4, E5 }) do hook.Run("PlayerInitialSpawn", p) p:Spawn() RecvAs("ws.lobby.open", p, {}) end
      for _, p in ipairs({ E2, E3, E4, E5 }) do RecvAs("ws.lobby.invite", E1, { ent = p }) tick() RecvAs("ws.lobby.answer", p, { b = true }) tick() end
      assert(#WS.Lobby.Members(E1:GetNW2Int("ws_lobby")) == 5, "в отряде 5")
      RecvAs("ws.lobby.invite", E1, { ent = D }) tick()
      assert(NET_TO[#NET_TO].name == "ws.lobby.notify", "шестого пригласить нельзя")
      -- уход игрока с сервера: командирство переходит
      E1.gone = true hook.Run("PlayerDisconnected", E1)
      local t = TIMERS TIMERS = {} for _, fn in ipairs(t) do fn() end
      local m = WS.Lobby.Members(E2:GetNW2Int("ws_lobby"))
      assert(#m == 4 and WS.Lobby.IsLeader(m[1]), "после выхода командира новый командир есть")
    """)
    print("сервер: сценарий отрядов пройден")


def client_test(errors):
    # заглушки 3D и vgui нужны до загрузки режима (Vector в cl_menu_scene.lua вызывается при загрузке)
    base = sim.PRELUDE
    sim.PRELUDE = base + EXTRA + VGUI
    try:
        lua = sim.realm(False)
    finally:
        sim.PRELUDE = base
    run = lua.execute
    run("""
      Me = MakePlayer("Me", 1) Fr = MakePlayer("Friend", 2) Ot = MakePlayer("Other", 3)
      Me:SetNW2Int("ws_lobby", 7) Me:SetNW2Bool("ws_lead", true) Fr:SetNW2Int("ws_lobby", 7) Fr:SetNW2Float("ws_lobby_t", 5)
      Ot:SetNW2Int("ws_lobby", 9)
      WS.Intro.IsPlaying = function() return false end
      hook.Run("WSIntroFinished")
      assert(WS.Menu.IsOpen(), "меню открылось после интро")
      ROOT = nil
      for _, p in ipairs(VGUI_ALL) do if p.cls == "EditablePanel" then ROOT = p end end
      for i = 1, 15 * 30 do NOW = NOW + 1 / 30 PaintTree(ROOT) hook.Run("Think") end
      local play = FindButton("ИГРАТЬ") assert(play, "кнопка Играть")
      play.hover = true PaintTree(ROOT) play:OnCursorEntered() play:DoClick()
      local t = TIMERS TIMERS = {} for _, fn in ipairs(t) do fn() end
      for i = 1, 60 do NOW = NOW + 1 / 30 PaintTree(ROOT) hook.Run("Think") end
      assert(FindButton("ВЫДВИГАТЬСЯ"), "лобби: кнопка выдвинуться у командира")
      assert(FindButton("ПОКИНУТЬ ОТРЯД"), "лобби: покинуть (в отряде двое)")
      assert(FindButton("Позывной"), "лобби: смена позывного в своей строке")
      assert(FindButton("Исключить"), "лобби: командир может исключить")
      -- смена состава пересобирает лобби
      Ot:SetNW2Int("ws_lobby", 7) Ot:SetNW2Float("ws_lobby_t", 9)
      for i = 1, 10 do NOW = NOW + 1 / 30 PaintTree(ROOT) end
      -- приглашение от другого игрока
      net.inent, net.inf = Ot, 30 net.r["ws.lobby.invited"]()
      net.instr = { "Тест уведомления", "join" } net.r["ws.lobby.notify"]()
      for i = 1, 30 do NOW = NOW + 1 / 30 PaintTree(ROOT) end
      assert(FindButton("Принять") and FindButton("Отклонить"), "окно приглашения")
      FindButton("Принять"):DoClick()
      -- назад в главное и выход в игру
      FindButton("НАЗАД"):DoClick()
      for i = 1, 30 do NOW = NOW + 1 / 30 PaintTree(ROOT) end
      net.r["ws.lobby.started"]()
      for i = 1, 30 do NOW = NOW + 1 / 30 PaintTree(ROOT) end
      local t = TIMERS TIMERS = {} for _, fn in ipairs(t) do fn() end
      assert(not WS.Menu.IsOpen(), "меню закрылось после выдвижения")
    """)
    snd = sorted(set(os.path.basename(s) for s in lua.globals().SOUNDS.values()))
    print("клиент: меню, лобби, приглашение, выход — без ошибок; звуки:", ", ".join(snd))
    sim.check_paths(lua, errors)


def main():
    errors = []
    server_test(errors)
    client_test(errors)
    for e in sorted(set(errors)):
        print("ОШИБКА:", e)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
