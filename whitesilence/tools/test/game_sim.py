"""Прогон игры без Garry's Mod: сюжет от выдвижения до финала, враги, редактор точек, клиентский экран.

Сервер: плоский «мир» (земля на z=0, без стен), два бойца выдвигаются, идут к меткам бегом (220 ю/с),
удерживают E у предметов, отстреливаются (по врагу в радиусе 1500 раз в ~3 с). Враги — настоящий
entities/ws_enemy (корутина RunBehaviour, восприятие, стрельба, урон, смерть). По ходу: гибель бойца и
возвращение «к отряду», гибель всего отряда и откат главы, финал и возврат в меню. Печатается время прохождения
в таких условиях (нижняя оценка: в игре есть рельеф, укрытия и промахи).
Редактор: scp_edit, все операции, сохранение и загрузка файла точек.
Клиент: состояние сюжета, реплики, карточка главы, метки (включая исчезновение вблизи), кольцо E, подрыв,
финал, редактор с панелью — HUDPaint и 3D-хуки, ловятся ошибки Lua и nil/NaN в отрисовке.

    python3 tools/test/game_sim.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import intro_sim as sim  # noqa: E402
import menu_sim  # noqa: E402

WORLD = r'''
local function noop() end
-- полноценная векторная математика
local VecMeta = {}
VecMeta.__index = VecMeta
function Vector(x, y, z)
  if type(x) == "table" then x, y, z = x.x, x.y, x.z end
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VecMeta)
end
VecMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VecMeta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VecMeta.__mul = function(a, b) if type(a) == "number" then a, b = b, a end
  if type(b) == "table" then return Vector(a.x * b.x, a.y * b.y, a.z * b.z) end return Vector(a.x * b, a.y * b, a.z * b) end
VecMeta.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
VecMeta.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
VecMeta.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
VecMeta.__tostring = function(a) return string.format("%.1f %.1f %.1f", a.x, a.y, a.z) end
function VecMeta:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function VecMeta:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function VecMeta:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function VecMeta:Distance(o) return (self - o):Length() end
function VecMeta:DistToSqr(o) return (self - o):LengthSqr() end
function VecMeta:Distance2D(o) return math.sqrt((self.x - o.x) ^ 2 + (self.y - o.y) ^ 2) end
function VecMeta:Distance2DSqr(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 end
function VecMeta:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function VecMeta:GetNormalized() local l = self:Length() if l == 0 then return Vector() end return self / l end
function VecMeta:Normalize() local n = self:GetNormalized() self.x, self.y, self.z = n.x, n.y, n.z end
function VecMeta:Angle()
  local l2 = math.sqrt(self.x ^ 2 + self.y ^ 2)
  return Angle(-math.deg(math.atan(self.z, l2)), math.deg(math.atan(self.y, self.x)), 0)
end
function VecMeta:IsZero() return self.x == 0 and self.y == 0 and self.z == 0 end
-- экран: камера локального игрока, FOV 90
function VecMeta:ToScreen()
  local eye, ang = EyePos(), EyeAngles()
  local d = self - eye
  local f, r, u = ang:Forward(), ang:Right(), ang:Up()
  local z = d:Dot(f)
  local x, y = d:Dot(r), d:Dot(u)
  if z < 1 then return { x = SCRW / 2 + (x >= 0 and 1 or -1) * SCRW, y = SCRH / 2, visible = false } end
  local k = (SCRW / 2) / z
  return { x = SCRW / 2 + x * k, y = SCRH / 2 - y * k, visible = true }
end
local AngMeta = {}
AngMeta.__index = AngMeta
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, AngMeta) end
function AngMeta:Forward()
  local p, y = math.rad(self.p), math.rad(self.y)
  return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end
function AngMeta:Right() local y = math.rad(self.y) return Vector(math.sin(y), -math.cos(y), 0) end
function AngMeta:Up() local f, r = self:Forward(), self:Right() return Vector(r.y * f.z - r.z * f.y, r.z * f.x - r.x * f.z, r.x * f.y - r.y * f.x) * -1 end
function AngMeta:RotateAroundAxis() end
AngMeta.__add = function(a, b) return Angle(a.p + b.p, a.y + b.y, a.r + b.r) end
AngMeta.__sub = function(a, b) return Angle(a.p - b.p, a.y - b.y, a.r - b.r) end
vector_up, vector_origin, angle_zero = Vector(0, 0, 1), Vector(0, 0, 0), Angle(0, 0, 0)
function LerpVector(t, a, b) return a + (b - a) * t end
function LerpAngle(t, a, b) return Angle(a.p + (b.p - a.p) * t, a.y + (b.y - a.y) * t, a.r + (b.r - a.r) * t) end
function VectorRand() return Vector(math.Rand(-1, 1), math.Rand(-1, 1), math.Rand(-1, 1)) end
bit = { band = function(a, b) return math.floor(a) & math.floor(b) end, bor = function(...) local r = 0 for _, v in ipairs({ ... }) do r = r | math.floor(v) end return r end }
function math.NormalizeAngle(a) return (a + 180) % 360 - 180 end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isnumber(v) return type(v) == "number" end
function tobool(v) return v and v ~= 0 and v ~= "0" end
string.Trim = string.Trim or function(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
util.Decal, util.Effect, util.ScreenShake = noop, function(n, ed) EFFECTS[n] = (EFFECTS[n] or 0) + 1 end, noop
EFFECTS = {}
SOUNDPLAY = 0
sound.Play = function() SOUNDPLAY = SOUNDPLAY + 1 end
function EffectData() return setmetatable({}, { __index = function() return noop end }) end
function SafeRemoveEntityDelayed(e) end
CHATLOG = {}
function PrintMessage(_, t) CHATLOG[#CHATLOG + 1] = t end
game.GetWorld = function() return WORLDENT end
game.SinglePlayer = function() return false end

-- таймеры с задержкой
TIMERS = {}
timer.Simple = function(d, fn) TIMERS[#TIMERS + 1] = { at = NOW + (d or 0), fn = fn } end
timer.Create, timer.Remove = noop, noop
function RunTimers()
  local due, keep = {}, {}
  for _, t in ipairs(TIMERS) do if t.at <= NOW then due[#due + 1] = t else keep[#keep + 1] = t end end
  TIMERS = keep
  for _, t in ipairs(due) do t.fn() end
end
SIMDT = 0.1
function FrameTime() return SIMDT end

-- файлы в памяти
FILES = {}
file.Read = function(p) return FILES[p] end
file.Write = function(p, s) FILES[p] = s end
file.CreateDir = noop
file.Exists = function(p) return FILES[p] ~= nil end

-- мир: земля z=0, стен нет
util.TraceLine = function(t)
  local s, e = t.start, t.endpos
  if e.z < 0 and s.z >= 0 then
    local k = s.z / (s.z - e.z)
    return { Hit = true, HitPos = s + (e - s) * k, HitNormal = Vector(0, 0, 1), Fraction = k, HitSky = false, StartSolid = false }
  end
  return { Hit = false, HitPos = e, Fraction = 1, HitNormal = Vector(0, 0, 1) }
end
util.TraceHull = function(t) return { Hit = false, HitPos = t.endpos, Fraction = 1 } end
navmesh = { IsLoaded = function() return false end }
weapons = { GetStored = function(c)
  if c == "tfa_ins2_ak12" then return { WorldModel = "models/weapons/tfa_ins2/w_ak12.mdl", Primary = { Sound = "TFA_INS2.AK12.1", RPM = 700, ClipSize = 30, Ammo = "ar2" } } end
  if c == "tfa_ins2_usp_match" then return { WorldModel = "models/w_usp.mdl", Primary = { Ammo = "pistol" } } end
end }
game.GetAmmoID = function(n) return n == "ar2" and 1 or (n == "pistol" and 3 or 9) end
physenv = { GetGravity = function() return Vector(0, 0, -600) end }
navmesh.Find = function() return {} end
os.date = os.date or function() return "12:00" end
util.IsValidModel = function(m) return type(m) == "string" and m ~= "" end

-- сущности
ENTS = {}
local nextIdx = 100
EntMeta2 = {}
EntMeta2.__index = EntMeta2
function NewEnt(cls)
  nextIdx = nextIdx + 1
  local e = setmetatable({ cls = cls, pos = Vector(), ang = Angle(), hp = 100, maxhp = 100, idx = nextIdx, nw = {}, children = {} }, EntMeta2)
  ENTS[#ENTS + 1] = e
  return e
end
for _, m in ipairs({ "SetKeyValue", "SetSolid", "SetCollisionGroup", "AddEffects", "SetBloodColor", "SetCollisionBounds",
  "SetSkin", "DrawShadow", "SetNoDraw", "SetNotSolid", "SetMoveType", "PhysicsInit", "AddFlags", "SetUseType",
  "PhysicsInitBox", "SetRenderBounds", "SetOwner", "SetVelocity" }) do
  EntMeta2[m] = noop
end
FIRED = {}
function EntMeta2:Fire(input, val) FIRED[#FIRED + 1] = { self.cls, input, val } end
local PhysMeta = {}
PhysMeta.__index = PhysMeta
for _, m in ipairs({ "SetMass", "SetMaterial", "EnableMotion", "Wake", "AddAngleVelocity" }) do PhysMeta[m] = noop end
function PhysMeta:SetVelocity(v) CHECK_NUM("Phys.SetVelocity", v.x, v.y, v.z) self.vel = v end
function PhysMeta:IsValid() return true end
function EntMeta2:GetPhysicsObject() self.phys = self.phys or setmetatable({}, PhysMeta) return self.phys end
function EntMeta2:GetPhysicsObjectNum() return self:GetPhysicsObject() end
function EntMeta2:WorldSpaceCenter() return self.pos + Vector(0, 0, 8) end
function EntMeta2:SetNW2Entity(k, v) self.nw[k] = v end
function EntMeta2:GetNW2Entity(k) return self.nw[k] end
-- NetworkVar как в GMod: Set*/Get* по имени
local NV_DEFAULT = { String = "", Int = 0, Bool = false, Float = 0 }
function EntMeta2:NetworkVar(typ, idx, name)
  local key = "_nv_" .. name
  self["Set" .. name] = function(s, v) s[key] = v end
  self["Get" .. name] = function(s) local v = s[key] if v == nil then return NV_DEFAULT[typ] end return v end
end
function EntMeta2:GetClass() return self.cls end
function EntMeta2:SetModel(m) assert(type(m) == "string", "SetModel") self.mdl = m end
function EntMeta2:GetModel() return self.mdl end
function EntMeta2:SetPos(p) CHECK_NUM("Ent.SetPos", p.x, p.y, p.z) self.pos = Vector(p) end
function EntMeta2:GetPos() return Vector(self.pos) end
function EntMeta2:SetAngles(a) self.ang = Angle(a.p, a.y, a.r) end
function EntMeta2:GetAngles() return Angle(self.ang.p, self.ang.y, self.ang.r) end
function EntMeta2:GetForward() return self.ang:Forward() end
function EntMeta2:GetRight() return self.ang:Right() end
function EntMeta2:SetParent(p) self.parent = p end
function EntMeta2:Spawn() if self.Initialize then self:Initialize() end end
function EntMeta2:Remove() self.__removed = true end
function EntMeta2:IsValid() return not self.__removed end
function EntMeta2:DeleteOnRemove() end
function EntMeta2:EntIndex() return self.idx end
function EntMeta2:Health() return self.hp end
function EntMeta2:SetHealth(h) self.hp = h end
function EntMeta2:SetMaxHealth(h) self.maxhp = h end
function EntMeta2:GetMaxHealth() return self.maxhp end
function EntMeta2:SkinCount() return 2 end
function EntMeta2:GetPhysicsObjectCount() return 0 end
function EntMeta2:GetAttachment() return nil end
function EntMeta2:LookupAttachment() return 0 end
function EntMeta2:EmitSound() SOUNDPLAY = SOUNDPLAY + 1 end
function EntMeta2:IsPlayer() return false end
function EntMeta2:IsNPC() return false end
function EntMeta2:IsNextBot() return self.cls == "ws_enemy" end
function EntMeta2:GetVelocity() return Vector() end
function EntMeta2:OBBCenter() return Vector(0, 0, 36) end
function EntMeta2:TakeDamageInfo(d)
  if self.__removed or self.hp <= 0 then return end
  self.hp = self.hp - d:GetDamage()
  if self.OnInjured then self:OnInjured(d) end
  if self.hp <= 0 and self.OnKilled then self:OnKilled(d) end
end
WORLDENT = NewEnt("worldspawn")

ents.Create = function(cls)
  local e = NewEnt(cls)
  local meta = SENTS[cls]
  if meta then
    setmetatable(e, meta)
    if e.SetupDataTables then e:SetupDataTables() end
    if meta.Type == "nextbot" then e:SimInit() end
  end
  return e
end
ents.FindByClass = function(c)
  local o = {}
  for _, e in ipairs(ENTS) do if not e.__removed and e.cls == c then o[#o + 1] = e end end
  return o
end
ents.FindInSphere = function(pos, r)
  local o = {}
  for _, e in ipairs(ENTS) do if not e.__removed and e.pos and e.pos:Distance(pos) <= r then o[#o + 1] = e end end
  return o
end
ents.GetAll = function() return ENTS end

function DamageInfo()
  local d = { dmg = 0 }
  function d:SetDamage(v) self.dmg = v end
  function d:GetDamage() return self.dmg end
  function d:ScaleDamage(k) self.dmg = self.dmg * k end
  function d:SetDamageType(t) self.type = t end
  function d:GetDamageType() return self.type or 0 end
  function d:SetAttacker(a) self.att = a end
  function d:GetAttacker() return self.att end
  function d:SetInflictor(a) self.inf = a end
  function d:GetInflictor() return self.inf end
  return d
end

-- NextBot: базовые методы и locomotion; RunBehaviour крутится корутиной
SENTS = {}
local NB = {}
for k, v in pairs(EntMeta2) do NB[k] = v end
function NB:SimInit()
  local ent = self
  self.loco = {
    speed = 100, vel = Vector(),
    SetDesiredSpeed = function(l, s) CHECK_NUM("SetDesiredSpeed", s) l.speed = s end,
    Approach = function(l, pos, w)
      local d = pos - ent.pos d.z = 0
      local len = d:Length()
      if len < 1 then return end
      local step = math.min(len, l.speed * SIMDT)
      ent.pos = ent.pos + d / len * step
      l.vel = d / len * l.speed
      l.moved = true
    end,
    FaceTowards = function(l, pos) CHECK_NUM("FaceTowards", pos.x, pos.y, pos.z) local a = (pos - ent.pos):Angle() ent.ang = Angle(0, a.y, 0) end,
    GetVelocity = function(l) return l.vel end,
    IsOnGround = function() return true end, IsStuck = function() return false end,
    Jump = noop, ClearStuck = noop,
  }
  for _, m in ipairs({ "SetStepHeight", "SetJumpHeight", "SetDeathDropHeight", "SetAcceleration", "SetDeceleration", "SetMaxYawRate" }) do
    self.loco[m] = noop
  end
  self.act = 0
  self.co = coroutine.create(function() self:RunBehaviour() end)
end
function NB:StartActivity(a) self.act = a end
function NB:GetActivity() return self.act end
function NB:BodyMoveXY() end
function NB:FrameAdvance() end
function NB:SetPoseParameter(k, v) CHECK_NUM("SetPoseParameter " .. k, v) end
function NB:RestartGesture() end
function NB:FireBullets(b)
  CHECK_NUM("FireBullets", b.Damage, b.Spread.x, b.Dir.x, b.Src.x)
  SHOTS = SHOTS + 1
  -- попадает с вероятностью 8%: бойцы иногда получают урон
  local t = self.target
  if t and math.random() < 0.08 and t.TakeBullet then t:TakeBullet(b.Damage, self) end
end
SHOTS = 0
function NB:BecomeRagdoll() self.__removed = true RAGDOLLS = RAGDOLLS + 1 return NewEnt("prop_ragdoll") end
RAGDOLLS = 0
function NB:SimTick()
  if self.__removed then return end
  self.loco.moved = false
  if self.Think then self:Think() end
  if self.BodyUpdate then self:BodyUpdate() end
  if coroutine.status(self.co) ~= "dead" then
    local ok, err = coroutine.resume(self.co)
    if not ok then error("ws_enemy: " .. tostring(err)) end
  end
  if not self.loco.moved then self.loco.vel = Vector() end
end
function LoadSENT(cls, src)
  ENT = {}
  local f = assert(load(src, "@entities/" .. cls))
  f()
  local meta = {}
  local base = SENTS[ENT.Base]
  for k, v in pairs(base or NB) do meta[k] = v end
  if base then meta.BaseClass = base end
  for k, v in pairs(ENT) do meta[k] = v end
  if not base and ENT.Type ~= "nextbot" then meta.SimInit = nil end
  meta.__index = meta
  SENTS[cls] = meta
  ENT = nil
end

-- игроки: позиция, взгляд, клавиши, урон и смерть
for _, m in ipairs({ "SetMoveType", "ChatPrint", "SetNW2Entity", "Flashlight", "AllowFlashlight", "AnimRestartGesture" }) do
  PLYMETA[m] = function(self, v) if m == "SetMoveType" then self.movetype = v end if m == "ChatPrint" then CHATLOG[#CHATLOG + 1] = v end end
end
function PLYMETA:GetMoveType() return self.movetype or 2 end
function PLYMETA:GetPos() return Vector(self.pos or Vector()) end
function PLYMETA:SetPos(p) CHECK_NUM("Ply.SetPos", p.x, p.y, p.z) self.pos = Vector(p) end
function PLYMETA:EyePos() return self:GetPos() + Vector(0, 0, 64) end
function PLYMETA:EyeAngles() return Angle(self.pitch or 0, self.yaw or 0, 0) end
function PLYMETA:SetEyeAngles(a) self.yaw, self.pitch = a.y, a.p end
function PLYMETA:GetAimVector() return self:EyeAngles():Forward() end
function PLYMETA:GetForward() return Angle(0, self.yaw or 0, 0):Forward() end
function PLYMETA:KeyDown(k) return self.keys and self.keys[k] or false end
function PLYMETA:Alive() return not self.dead end
function PLYMETA:Health() return self.hp or 100 end
function PLYMETA:Crouching() return false end
function PLYMETA:GetVelocity() return self.vel or Vector() end
function PLYMETA:IsFlagSet() return false end
function PLYMETA:IsListenServerHost() return false end
function PLYMETA:IsSuperAdmin() return self.admin or false end
function PLYMETA:IsNextBot() return false end
function PLYMETA:IsNPC() return false end
function PLYMETA:EmitSound() end
function PLYMETA:GetActiveWeapon() return nil end
function PLYMETA:IsValid() return not self.gone end
function PLYMETA:TakeBullet(dmg, att)
  if self.dead or self.god then return end
  self.hp = (self.hp or 100) - dmg
  HITS = HITS + 1
  if self.hp <= 0 then self:Kill(att) end
end
HITS = 0
function PLYMETA:Kill(att)
  if self.dead then return end
  self.dead = true
  self.hp = 0
  self.wsLastDmg = 2
  hook.Run("PlayerDeath", self, att, att)
end
function PLYMETA:SetHealth(h) self.hp = h end
function PLYMETA:GetMaxHealth() return 100 end
function PLYMETA:Armor() return 50 end
function PLYMETA:SetVelocity() end
function PLYMETA:Spectate(m) self.obsMode = m end
function PLYMETA:SpectateEntity(e) self.obsTarget = e end
function PLYMETA:UnSpectate() self.obsMode, self.obsTarget = nil, nil end
function PLYMETA:GetObserverTarget() return self.obsTarget end
function PLYMETA:GetObserverMode() return self.obsMode or 0 end
function PLYMETA:SetNW2Entity(k, v) self.nw[k] = v end
function PLYMETA:GetNW2Entity(k) return self.nw[k] end
function PLYMETA:GetEyeTrace() return { Entity = nil, HitPos = self:EyePos() + self:GetAimVector() * 100 } end
function PLYMETA:GetAmmoCount(t) self.ammo = self.ammo or {} return self.ammo[t] or 0 end
function PLYMETA:SetAmmo(n, t) self.ammo = self.ammo or {} self.ammo[t] = n end
local spawn0 = PLYMETA.Spawn
function PLYMETA:Spawn() self.dead = false self.hp = 100 spawn0(self) end
function PLYMETA:Alive() return not self.dead end

-- исходящие: записываем всё (в отличие от menu_sim)
net.Send = function(target) NET_TO[#NET_TO + 1] = { name = net.cur.name, target = target, data = net.cur } end
net.Broadcast = function() NET_TO[#NET_TO + 1] = { name = net.cur.name, data = net.cur } end

-- входящие сообщения: очередь значений для net.Read*
NETQ = {}
local function pop() return table.remove(NETQ, 1) end
net.ReadBool, net.ReadUInt, net.ReadString, net.ReadFloat, net.ReadVector, net.ReadEntity = pop, pop, pop, pop, pop, pop
function Recv(name, ply, ...)
  NETQ = { ... }
  net.r[name](0, ply)
end
'''

# серверная часть: сценарий от выдвижения до финала
SERVER = r'''
local S, P, C, I, ACH = WS.Story, WS.Story.P, WS.Config, WS.Inv, WS.Ach
assert(S.P, "точки сюжета загружены")
A = MakePlayer("Alpha", 1) B = MakePlayer("Bravo", 2)
A.admin = true
for _, p in ipairs(PLAYERS) do hook.Run("PlayerInitialSpawn", p) p:Spawn() end
LOG = {}
function log(fmt, ...)
  local line = string.format("%6.0f с  " .. fmt, NOW - (T0 or NOW), ...)
  LOG[#LOG + 1] = line
  print("    " .. line)
end

function Tick()
  NOW = NOW + SIMDT
  RunTimers()
  hook.Run("Think")
  for _, e in ipairs(ENTS) do if e.co and not e.__removed then e:SimTick() end end
end
function Run(sec, fn) local untilT = NOW + sec while NOW < untilT do Tick() if fn and fn() then return true end end return false end

-- боты-игроки: бегом к цели, E у предметов, стреляют по ближайшему врагу, подбирают лут
local function moveTo(p, pos, speed)
  local d = pos - p.pos d.z = 0
  local len = d:Length()
  if len < 1 then p.vel = Vector() return true end
  local step = math.min(len, speed * SIMDT)
  p.pos = p.pos + d / len * step
  p.vel = d / len * speed
  p.yaw = d:Angle().y
  return len < 30
end
local nextShot = {}
SHOTS_P = 0
function Brain()
  local cur = S.Current()
  for _, p in ipairs(PLAYERS) do
    p.keys = {}
    if p.dead or not WS.Lobby.InGame(p) then goto skip end
    do
      local foe, fd
      for _, e in ipairs(ents.FindByClass("ws_enemy")) do
        local d = e.pos:Distance(p.pos)
        if e.hp > 0 and d < 1500 and (not fd or d < fd) then foe, fd = e, d end
      end
      if foe then
        p.yaw = (foe.pos - p.pos):Angle().y
        if NOW >= (nextShot[p] or 0) then
          nextShot[p] = NOW + math.Rand(1.0, 2.0)
          SHOTS_P = SHOTS_P + 1
          local d = DamageInfo() d:SetDamage(60) d:SetAttacker(p) d:SetInflictor(p)
          if math.random() < 0.3 then foe.wsHeadHit = CurTime() end
          foe:TakeDamageInfo(d)
          hook.Run("EntityFireBullets", p, {})
          -- перезарядка списывает патроны из коробок
          local t = 1
          if p:GetAmmoCount(t) > 0 then p:SetAmmo(p:GetAmmoCount(t) - 3, t) end
        end
        goto skip
      end
      -- лут рядом — подобрать
      for _, it in ipairs(ents.FindByClass("ws_item")) do
        if not it.__removed and it.pos:Distance(p.pos) < 300 then
          if moveTo(p, it.pos, C.RunSpeed) or it.pos:Distance(p.pos) < 60 then it:Use(p) end
          goto skip
        end
      end
      if not cur then goto skip end
      local def = cur.def
      local target
      if def.type == "goto" or def.type == "hold" then
        target = P.Get(def.point)
      elseif def.type == "interact" then
        for _, pid in ipairs(def.points) do if not cur.used[pid] then target = P.Get(pid) break end end
        if target and p.pos:Distance(target) < 80 then
          local to = (target + Vector(0, 0, 16)) - p:EyePos()
          local a = to:Angle()
          p.yaw, p.pitch = a.y, a.p
          p.keys[IN_USE] = true
          goto skip
        end
      elseif def.type == "kill" then
        local best, bd
        for _, e in ipairs(ents.FindByClass("ws_enemy")) do
          local d = e.pos:Distance(p.pos)
          if e.hp > 0 and (not bd or d < bd) then best, bd = e, d end
        end
        target = best and best.pos
      end
      if target then moveTo(p, target + Vector((p.idx - 1.5) * 60, 0, 0), C.RunSpeed) end
    end
    ::skip::
  end
end
function Play(sec, cond) return Run(sec, function() Brain() return cond and cond() end) end

-- 1. выдвижение: брифинг, затем первая глава
T0 = NOW
for _, p in ipairs(PLAYERS) do Recv("ws.lobby.open", p) end
B:SetNW2Int("ws_lobby", A:GetNW2Int("ws_lobby")) B:SetNW2Bool("ws_lead", false)
Recv("ws.lobby.start", A)
assert(A:GetNW2Bool("ws_ingame") and B:GetNW2Bool("ws_ingame"), "отряд в игре")
local brief = false
for _, m in ipairs(NET_TO) do if m.name == "ws.story.briefing" then brief = true end end
assert(brief, "брифинг отправлен")
Run(5)
assert(not S.State.running, "во время брифинга глава ещё не началась")
Run(C.BriefingTime)
assert(S.State.running and S.State.ch == 1, "после брифинга — глава 1")
-- набор
assert(I.Count(I.List(A), "bandage") >= 3 and I.Count(I.List(A), "medkit") >= 1, "набор выдан")
assert(A:GetAmmoCount(1) == I.CountAmmo(I.List(A), 1) and A:GetAmmoCount(1) >= 200, "запас оружия = патроны в коробках: " .. A:GetAmmoCount(1))
assert(A:GetAmmoCount(3) == 50, "пистолетные патроны: " .. A:GetAmmoCount(3))
log("брифинг, глава 1, набор: %d предм., %d патр.", #I.List(A), A:GetAmmoCount(1))

-- инвентарь: патроны списываются при перезарядке
local before = I.CountAmmo(I.List(A), 1)
A:SetAmmo(A:GetAmmoCount(1) - 30, 1)
Run(0.5)
assert(I.CountAmmo(I.List(A), 1) == before - 30, "перезарядка списала 30 патронов из коробок")
-- кровотечение и бинт
A:SetNW2Int("ws_bleed", 2)
local hp0 = A.hp
Run(4)
assert(A.hp < hp0, "кровотечение отнимает здоровье")
Recv("ws.inv.quick", A, 4)
assert(A.wsUsing, "бинт применяется")
Run(3.5)
assert(A:GetNW2Int("ws_bleed", 0) == 0, "бинт остановил кровотечение")
assert(ACH.Prog == nil or true)
-- перенос предмета в сетке и выброс
local it = I.List(A)[1]
Recv("ws.inv.move", A, it.uid, 6, 4, false)
local dropped = #ents.FindByClass("ws_item")
local last = I.List(A)[#I.List(A)]
Recv("ws.inv.drop", A, last.uid)
assert(#ents.FindByClass("ws_item") == dropped + 1, "предмет выброшен на землю")
log("инвентарь: перезарядка, кровотечение, бинт, перенос, выброс — ок")

local lastCh, lastStep = 0, 0
local died, wiped, specSeen, revived, crashed = false, false, false, false, false
local function watch()
  if S.State.ch ~= lastCh or S.State.step ~= lastStep then
    lastCh, lastStep = S.State.ch, S.State.step
    local cur = S.Current()
    log("глава %d «%s», шаг %d: %s %s", lastCh, S.Chapters[lastCh].title, lastStep, cur and cur.def.type or "-", cur and (cur.def.text or "") or "")
  end
end

-- 2. играем; в главе 2 гибнет Bravo (наблюдает до чекпоинта), в главе 4 гибнет весь отряд
local finished = false
local guard = 0
local wall = os.clock()
while not finished do
  guard = guard + 1
  if guard > 9000 or os.clock() - wall > 900 then
    for _, l in ipairs(LOG) do print(l) end
    error("сюжет завис: глава " .. S.State.ch .. " шаг " .. S.State.step .. " running=" .. tostring(S.State.running))
  end
  Play(1)
  watch()
  for _, m in ipairs(NET_TO) do
    if m.name == "ws.story.finish" then finished = true end
    if m.name == "ws.story.cutscene" then crashed = true end
  end
  if S.State.ch == 2 and not died then
    died = true
    B:Kill(WORLDENT)
    Run(6)
    assert(B:GetNW2Bool("ws_spectating") and B.obsTarget == A, "Bravo наблюдает за Alpha")
    assert(WS.Lobby.InGame(B), "наблюдатель остаётся в игре")
    -- голос и чат павшего живые не слышат
    assert(hook.Run("PlayerCanHearPlayersVoice", A, B) == false, "живой не слышит павшего")
    assert(hook.Run("PlayerCanHearPlayersVoice", B, A) == true, "павший слышит живого")
    specSeen = true
    log("Bravo погиб → наблюдает за Alpha")
  end
  if specSeen and not revived and not B.dead then
    revived = true
    assert(not B:GetNW2Bool("ws_spectating"), "после чекпоинта — не наблюдатель")
    log("Bravo вернулся в бой на чекпоинте (глава %d, шаг %d)", S.State.ch, S.State.step)
  end
  if S.State.ch == 4 and S.State.step >= 2 and not wiped then
    wiped = true
    A:Kill(WORLDENT) B:Kill(WORLDENT)
    Run(C.StoryWipeDelay + 1)
    assert(not S.State.running and S.State.ch == 4, "гибель отряда: глава откатилась")
    Run(5)
    assert(S.State.running and S.State.ch == 4 and not A.dead and not B.dead, "глава 4 началась заново, все живы")
    log("отряд погиб — глава 4 заново, все вернулись")
  end
  -- случайные гибели от огня врагов: наблюдение до чекпоинта, иногда — откат главы
end
local total = NOW - T0
assert(died and wiped and revived, "сценарии гибели пройдены")
assert(crashed, "сцена крушения вертолёта была")
log("финал")
assert(ACH.Has(A, "first_blood") and ACH.Has(A, "complete"), "достижения: первый контакт, операция завершена")
-- 3. финал: через StoryEndTime все в меню, сюжет сброшен
Run(C.StoryEndTime + 1)
assert(not A:GetNW2Bool("ws_ingame") and not B:GetNW2Bool("ws_ingame"), "после финала — меню")
assert(not S.State.running and S.State.ch == 1, "операция сброшена")
-- награды за достижения — в наборе
local extra = hook.Run("WSExtraKit", A) or {}
assert(#extra >= 1, "награда «Белая тишина» добавляет к набору")
local got = {}
for _, a in ipairs(ACH.List) do if ACH.Has(A, a.id) then got[#got + 1] = a.id end end
RESULT = { total = total, kills = S.Stats.kills, deaths = S.Stats.deaths, shots = SHOTS, hits = HITS, ragdolls = RAGDOLLS,
  ach = table.concat(got, ", "), grenades = 0, items = #ents.FindByClass("ws_item") }
for _, f in ipairs(FIRED) do if f[1] == "npc_grenade_frag" then RESULT.grenades = RESULT.grenades + 1 end end

-- ИИ отдельно: стена x = 200 (выше 90 — нет), укрытие и граната
do
  local trace0 = util.TraceLine
  util.TraceLine = function(t)
    local a, b = t.start, t.endpos
    if (a.x - 200) * (b.x - 200) < 0 then
      local k = (200 - a.x) / (b.x - a.x)
      local z = a.z + (b.z - a.z) * k
      if z < 50 then return { Hit = true, HitPos = a + (b - a) * k, Fraction = k, HitNormal = Vector(-1, 0, 0), HitWorld = true } end
    end
    return trace0(t)
  end
  local e = ents.Create("ws_enemy")
  e:SetPos(Vector(260, 0, 0))
  e:Spawn()
  local threat = Vector(900, 40, 0)
  local c = e:FindCover(threat)
  AI_COVER = c and string.format("(%.0f, %.0f)%s", c.pos.x, c.pos.y, c.peek and " с выглядыванием" or "") or "нет"
  assert(c and c.pos.x < 200, "укрытие — за стеной от угрозы")
  local fired0 = #FIRED
  local co = coroutine.create(function() return e:ThrowGrenade(threat) end)
  local ok, thrown
  for _ = 1, 200 do
    ok, thrown = coroutine.resume(co)
    assert(ok, tostring(thrown))
    if coroutine.status(co) == "dead" then break end
    NOW = NOW + 0.1
  end
  AI_GRENADE = tostring(thrown)
  assert(thrown and #FIRED > fired0, "граната брошена, запал выставлен")
  util.TraceLine = trace0
  e:Remove()
end

-- 4. звание за достижение
Recv("ws.ach.title", A, "Белая тишина")
assert(A:GetNW2String("ws_title") == "Белая тишина", "звание выбрано")
Recv("ws.ach.title", A, "Несуществующее")
assert(A:GetNW2String("ws_title") == "Белая тишина", "чужое звание не выдаётся")

-- 5. редактор
concommand.t["scp_edit"](B)
assert(not B.wsEditing, "не-админу редактор недоступен")
concommand.t["scp_edit"](A)
assert(A.wsEditing and A.movetype == MOVETYPE_NOCLIP, "редактор включён, полёт")
local function op(name, ...) A.wsEditNext = 0 Recv("ws.edit.op", A, name, ...) end
op("set", "crash", Vector(1000, 2000, 0), 90)
assert(P.IsSet("crash") and P.Get("crash"):Distance(Vector(1000, 2000, 0)) < 1, "точка поставлена")
op("radius", "crash", 640)
local _, _, r = P.Get("crash") assert(r == 640, "радиус")
op("set", "nope", Vector(1, 1, 1), 0)
assert(not P.Data.points["nope"], "чужие точки отклоняются")
op("set", "relay", Vector(0 / 0, 0, 0), 0)
assert(not P.IsSet("relay"), "NaN отклоняется")
op("gadd", "ambush", Vector(500, 500, 0), 10) op("gadd", "ambush", Vector(600, 500, 0), 20) op("gadd", "ambush", Vector(700, 500, 0), 30)
assert(#P.GroupSpots("ambush") == 3, "точки группы")
op("gdel", "ambush", 2)
assert(#P.GroupSpots("ambush") == 2 and P.GroupSpots("ambush")[2].pos.x == 700, "удаление точки группы")
op("test", "ambush")
assert(#ents.FindByClass("ws_enemy") >= 3, "тестовый спавн группы")
for i = 1, 20 do Tick() end
op("clear")
assert(#ents.FindByClass("ws_enemy") == 0, "убрать врагов")
op("auto")
for _, d in ipairs(S.Points) do assert(P.IsSet(d.id), "авто: " .. d.id) end
op("save")
local f = FILES["whitesilence/points/gm_snowtest.json"]
assert(f and f:find("crash") and f:find("pylon3"), "файл точек записан (вместе с новыми главами)")
op("reset", "crash")
assert(not P.IsSet("crash"), "сброс точки")
op("reload")
assert(P.IsSet("crash") and P.Get("crash"):Distance(Vector(1000, 2000, 0)) < 1, "загрузка из файла")
op("story", 9)
assert(S.State.running and S.State.ch == 9, "редактор: запуск главы 9")
op("story", 0)
assert(not S.State.running, "редактор: стоп")
concommand.t["scp_edit"](A)
assert(not A.wsEditing, "редактор выключен")
EDITOR_OK = true
'''

CLIENT = r'''
local S, I, ACH = WS.Story, WS.Inv, WS.Ach
local me = LOCALPLY
me.nw.ws_ingame = true
me.nw.ws_lobby = 3
me.pos = Vector(0, 0, 0)
function me:GetPos() return self.pos end
function me:EyePos() return self.pos + Vector(0, 0, 64) end
function me:GetVelocity() return Vector(180, 40, 0) end
function me:IsOnGround() return true end
function me:GetViewEntity() return self end
function me:GetMoveType() return MOVETYPE_WALK end
function me:GetHands() return nil end
function me:GetObserverTarget() return self.obs end
function me:GetNW2Entity(k) return self.nw[k] end
function me:GetEyeTrace() return { Entity = nil, HitPos = Vector(100, 0, 64) } end
function me:GetMaxHealth() return 100 end
-- оружие в руках
local function weapon(cls, clip)
  return setmetatable({ cls = cls }, { __index = function(t, k)
    if k == "GetWeaponWorldModel" or k == "GetModel" then return function() return "models/w_" .. cls .. ".mdl" end end
    if k == "Clip1" then return function() return clip end end
    if k == "GetPrimaryAmmoType" then return function() return 1 end end
    if k == "GetPrintName" then return function() return cls end end
    if k == "GetClass" then return function() return cls end end
    if k == "IsValid" then return function() return true end end
    if k == "IsTFAWeapon" then return true end
    if k == "GetIronSights" then return function() return false end end
    if k == "GetMaxClip1" then return function() return 30 end end
    if k == "Clip2" or k == "GetSecondaryAmmoType" then return function() return -1 end end
    if k == "Instructions" or k == "PrintName" then return cls end
    if type(k) == "string" and k:match("^[A-Z]") then return function() return nil end end
  end })
end
me.weps = { weapon("tfa_ins2_ak12", 27), weapon("tfa_ins2_usp_match", 12) }
function me:GetActiveWeapon() return self.weps[1] end
-- товарищ (для контура, имён, наблюдения, аватаров в чате)
MATE = MakeFakePlayer(2, "Bravo")
MATE.nw.ws_ingame = true MATE.nw.ws_lobby = 3
MATE.pos = Vector(400, 120, 0)
function MATE:GetPos() return self.pos end
function MATE:EyePos() return self.pos + Vector(0, 0, 64) end
function MATE:GetChildren() return {} end
function MATE:GetActiveWeapon() return nil end
player.GetAll = function() return { me, MATE } end
function EyePos() return me:EyePos() end
function EyeAngles() return Angle(0, 0, 0) end
WS.Intro.IsPlaying = function() return false end
WS.Menu.IsOpen = function() return false end
GAMEMODE = { CalcView = function(_, ply, o, a, f) return { origin = o, angles = a, fov = f } end,
  CalcViewModelView = function(_, w, vm, op, oa, p, a) return p, a end }
local vm = { ViewModelIndex = function() return 0 end, IsValid = function() return true end }
local function frame(n)
  for i = 1, n or 1 do
    NOW = NOW + 1 / 30
    hook.Run("Think")
    hook.Run("CalcView", me, me:EyePos(), Angle(0, 0, 0), 90, 1, 30000)
    hook.Run("CalcViewModelView", me.weps[1], vm, Vector(), Angle(), Vector(), Angle())
    hook.Run("CreateMove", setmetatable({}, { __index = function() return function() end end }))
    hook.Run("SetupWorldFog")
    hook.Run("RenderScreenspaceEffects")
    hook.Run("PostDrawTranslucentRenderables", false, false)
    hook.Run("PostDrawViewModel", vm, me, me.weps[1])
    hook.Run("PostDrawEffects")
    hook.Run("HUDPaint")
  end
end
WS.Wake.Start = WS.Wake.Start or function() end

-- брифинг (с выходом в игру): карта, поля, голос — и пробуждение после
hook.Run("WSDeployed")
Recv("ws.story.briefing", nil)
assert(WS.Briefing.Active(), "брифинг идёт")
assert(not WS.HUD.Visible(), "во время брифинга HUD скрыт")
local t = TIMERS TIMERS = {} for _, x in ipairs(t) do x.fn() end
frame(30 * 25)
assert(not WS.Briefing.Active(), "брифинг закончился")

-- инвентарь: состояние с сервера, микро-слоты, кольцо применения
Recv("ws.inv", nil, 4,
  1, "bandage", 1, 1, false, 3, 0,
  2, "medkit", 2, 1, false, 1, 3,
  3, "ammo_rifle", 1, 2, false, 120, 0,
  4, "battery", 4, 1, false, 1, 0)
assert(#I.Mine == 4, "рюкзак принят")
me.nw.ws_bleed = 2
me.nw.ws_weight = 21
me.nw.ws_using_until = CurTime() + 2 me.nw.ws_using_dur = 3 me.nw.ws_using_item = "bandage"
frame(60)
me.nw.ws_using_until = 0 me.nw.ws_bleed = 0
Recv("ws.inv.notify", nil, "Нет места в рюкзаке")
frame(10)
-- руки: подобрать, применить, удерживать E
Recv("ws.hand", nil, "pickup", Vector(60, -10, 0), 0.9)
assert(WS.Hands.Active(), "анимация руки")
frame(15)
assert(WS.Hands.Lower > 0.3, "оружие опущено, пока рука работает: " .. WS.Hands.Lower)
frame(30)
Recv("ws.hand", nil, "use", Vector(), 3)
frame(100)
me.nw.ws_use = 0.4 frame(20) me.nw.ws_use = 0 frame(40)
-- меню Q: окно, сетка, перетаскивание, R, двойной клик
hook.Run("OnSpawnMenuOpen")
local root
for _, p in ipairs(VGUI_ALL) do if p.cls == "DPanel" and not p.parent and not p.__removed then root = p end end
assert(root, "окно снаряжения открыто")
for i = 1, 10 do PaintTree(root) if root.PaintOver then root:PaintOver(1500, 760) end frame(1) end
local grid
for _, p in ipairs(VGUI_ALL) do if p.parent == root and p.OnMousePressed then grid = p end end
assert(grid, "сетка рюкзака")
grid.CursorPos = function() return 10, 10 end
grid:OnMousePressed(MOUSE_LEFT)
PaintTree(grid)
KEYS_DOWN[KEY_R] = true grid:Think() KEYS_DOWN[KEY_R] = false grid:Think()
grid.CursorPos = function() return 300, 100 end
PaintTree(grid)
grid:OnMouseReleased(MOUSE_LEFT)
local moved = false
for _, m in ipairs(NET_SENT) do if m.name == "ws.inv.move" then moved = true end end
assert(moved, "перенос отправлен на сервер")
grid.CursorPos = function() return 10, 10 end
grid:OnMousePressed(MOUSE_LEFT) grid:OnMouseReleased(MOUSE_LEFT) grid:OnMousePressed(MOUSE_LEFT)
grid:OnMousePressed(MOUSE_RIGHT)
hook.Run("OnSpawnMenuOpen")
frame(10)

-- сюжет: состояние, метки (вблизи пропадают), реплики, глава, подрыв, крушение
local function state(text, prog, frac, marks)
  local q = { true, 3, text, prog, frac, #marks }
  for _, m in ipairs(marks) do
    q[#q + 1] = m[1] q[#q + 1] = m[2] q[#q + 1] = m[3] q[#q + 1] = m[4] q[#q + 1] = m[5] or NULL
  end
  Recv("ws.story.state", nil, table.unpack(q))
end
state("Удерживать ретранслятор", "1:42", 0.3, {
  { Vector(3000, 0, 0), "defend", "Удерживать", 450 },
  { Vector(0, 2000, 0), "radio", "Запустить", 0 },
  { Vector(-2000, 0, 0), "extract", "", 0 },
})
frame(60)
state("Дойти", "", -1, { { Vector(60, 0, 0), "goto", "", 0 } })
local d0 = DRAWS frame(10) local nearDraws = DRAWS - d0
state("Дойти", "", -1, { { Vector(2500, 0, 0), "goto", "", 0 } })
d0 = DRAWS frame(10) local farDraws = DRAWS - d0
assert(farDraws > nearDraws, "метка вблизи не рисуется")
for _, id in ipairs({ "c1_a", "c2_b", "c7_e", "c10_d" }) do Recv("ws.story.line", nil, id) frame(30) end
Recv("ws.story.chapter", nil, 8) frame(90)
Recv("ws.story.boom", nil, Vector(500, 0, 0)) frame(60)
Recv("ws.story.cutscene", nil, "crash")
frame(60)
t = TIMERS TIMERS = {} for _, x in ipairs(t) do x.fn() end
frame(10)
Recv("ws.story.checkpoint", nil)

-- достижения: состояние, «получено», экран в меню
local q = { #ACH.List }
for i, a in ipairs(ACH.List) do q[#q + 1] = i % 3 == 0 q[#q + 1] = i * 3 end
Recv("ws.ach.state", nil, table.unpack(q))
Recv("ws.ach.unlock", nil, "first_blood")
frame(60)
local achPanel = ACH.OpenPanel(nil)
for _, p in ipairs(VGUI_ALL) do if p.parent == achPanel and p.DoClick then p.hover = true PaintTree(p) p:DoClick() end end
PaintTree(achPanel)

-- чат: открыть, отправить, лента с аватаром, «печатает» у товарища
MATE.nw.ws_typing = true
local CH = WS.Chat
CH.Open("squad")
frame(5)
Recv("ws.chat.msg", nil, MATE, 2, "Контакт слева!")
Recv("ws.chat.msg", nil, MATE, 6, "я наблюдаю")
Recv("ws.chat.msg", nil, me, 1, "принял")
hook.Run("ChatText", 0, "", "Игрок подключился", "joinleave")
frame(20)
CH.Close()
frame(30 * 13)

-- гибель → экран смерти → наблюдение
me.alive = false
frame(5)
Recv("ws.death", nil, "Убит: Дельта-14")
frame(30 * 4)
me.nw.ws_spectating = true
me.nw.ws_spec_target = MATE
me.obs = MATE
frame(60)
KEYS_DOWN[KEY_SPACE] = true frame(2) KEYS_DOWN[KEY_SPACE] = false frame(2)
local nextSent = false
for _, m in ipairs(NET_SENT) do if m.name == "ws.spec.next" then nextSent = true end end
assert(nextSent, "переключение наблюдения")
me.alive = true me.nw.ws_spectating = false
frame(30)

-- финал
Recv("ws.story.finish", nil, 3325.5, 204, 9)
frame(30 * 22)
assert(S.Ending, "финальные титры")
me.nw.ws_ingame = false frame(5)
assert(not S.Ending, "финал закрылся после возврата в меню")
me.nw.ws_ingame = true

-- редактор
local q2 = { true, true, 2, 1 }
for _, d in ipairs(S.Points) do q2[#q2 + 1] = Vector(math.random(-3000, 3000), math.random(-3000, 3000), 0) q2[#q2 + 1] = 45 q2[#q2 + 1] = d.r or 0 q2[#q2 + 1] = math.random() < 0.5 end
for i, g in ipairs(S.Groups) do
  local n = i % 3 q2[#q2 + 1] = n
  for k = 1, n do q2[#q2 + 1] = Vector(k * 100, i * 100, 0) q2[#q2 + 1] = 0 end
end
Recv("ws.edit.state", nil, table.unpack(q2))
assert(S.Editor.on, "редактор включён")
local eroot
for _, p in ipairs(VGUI_ALL) do if p.cls == "DPanel" and not p.parent and not p.__removed and p ~= achPanel then eroot = p end end
hook.Run("OnContextMenuOpen")
for i = 1, 10 do PaintTree(eroot) frame(1) end
local rows = {}
for _, p in ipairs(VGUI_ALL) do if p.cls == "DButton" and p.parent and p.parent.cls == "DScrollPanel" and not p.__removed then rows[#rows + 1] = p end end
assert(#rows == #S.Points + #S.Groups, "в списке все точки и группы: " .. #rows)
rows[2]:DoClick() PaintTree(eroot)
rows[#S.Points + 1]:DoClick() PaintTree(eroot)
hook.Run("OnContextMenuClose")
Recv("ws.edit.state", nil, false)
frame(10)
CLICKED = #rows
'''


def load_entity(lua, cls):
    path = os.path.join(sim.GM, "whitesilence", "entities", "entities", cls, "shared.lua")
    lua.globals().LoadSENT(cls, open(path, encoding="utf-8").read())


def server_test(errors):
    base = sim.PRELUDE
    sim.PRELUDE = base + menu_sim.EXTRA.replace("local PlyMeta = {}", "PlyMeta = {} PLYMETA = PlyMeta") \
        .replace("function PlyMeta:Alive() return true end", "") + WORLD
    try:
        lua = sim.realm(True)
    finally:
        sim.PRELUDE = base
    g = lua.globals()
    g.SERVER, g.CLIENT = True, False
    for cls in ("ws_enemy", "ws_prop", "ws_item", "ws_crate"):
        load_entity(lua, cls)
    # JSON как в GMod
    def to_py(v):
        if lupa_type(v) == "table":
            keys = list(v.keys())
            if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
                return [to_py(v[k]) for k in sorted(keys)]
            return {str(k): to_py(v[k]) for k in keys}
        return v
    import lupa
    lupa_type = lupa.lua_type

    def from_py(o):
        if isinstance(o, dict):
            t = lua.table()
            for k, v in o.items():
                t[k] = from_py(v)
            return t
        if isinstance(o, list):
            t = lua.table()
            for i, v in enumerate(o):
                t[i + 1] = from_py(v)
            return t
        return o
    g.util.TableToJSON = lambda t, pretty=False: json.dumps(to_py(t), ensure_ascii=False, indent=1 if pretty else None)
    def json_to_table(src):
        try:
            return from_py(json.loads(src))
        except (ValueError, TypeError):
            return None          # как в GMod: мусор → nil
    g.util.JSONToTable = json_to_table
    lua.execute(SERVER)
    r = g.RESULT
    print("сервер: 10 глав от брифинга до финала; гибель → наблюдение → чекпоинт; гибель отряда → глава заново;")
    print("        крушение вертолёта; инвентарь (набор, патроны из коробок, кровотечение, бинт, лут); достижения")
    print("   время прохождения (бег без препятствий, ровное поле, боты-стрелки): %d мин %d с" % (r.total // 60, r.total % 60))
    print("   уничтожено врагов: %d, гибелей бойцов: %d, выстрелов врагов: %d, попаданий по бойцам: %d, гранат: %d"
          % (r.kills, r.deaths, r.shots, r.hits, r.grenades))
    print("   достижения Alpha:", r.ach)
    assert g.EDITOR_OK
    print("сервер: scp_edit — точки, радиус, группы, тест-спавн, авто, сохранение/загрузка, запуск главы — ок")
    if r.total < 18 * 60:          # нижняя граница: обязательные удержания (~19 мин) и реплики
        errors.append("сюжет короче 18 минут даже в упрощённом прогоне: %d с" % r.total)
    print("   ИИ: укрытие за стеной найдено %s, граната брошена: %s" % (g.AI_COVER, g.AI_GRENADE))


def client_test(errors):
    base = sim.PRELUDE
    sim.PRELUDE = base + menu_sim.EXTRA.replace("local PlyMeta = {}", "PlyMeta = {} PLYMETA = PlyMeta").replace("local EntMeta = {}", "EntMeta = {}") \
        + menu_sim.VGUI + WORLD.split("-- игроки: позиция")[0] + r'''
NETQ = {}
local function pop() return table.remove(NETQ, 1) end
net.ReadBool, net.ReadUInt, net.ReadString, net.ReadFloat, net.ReadVector, net.ReadEntity = pop, pop, pop, pop, pop, pop
function Recv(name, ply, ...) NETQ = { ... } net.r[name](0, ply) end
function LocalPlayer() return LOCALPLY end
-- клиентские API, которых нет в общей заготовке: значения-заглушки, аргументы-числа проверяются там, где важно
local function permissive(t)
  return setmetatable(t or {}, { __index = function(_, k) return function() return nil end end })
end
local r0 = render
render = permissive({})
for k, v in pairs(r0) do render[k] = v end
render.ComputeLighting = function() return Vector(0.4, 0.42, 0.45) end
render.ComputeDynamicLighting = function() return Vector(0, 0, 0) end
cam = permissive(cam)
mesh = permissive({})
function Mesh() return permissive({}) end
local MatM = {}
MatM.__index = MatM
function Matrix(t) return setmetatable({ rows = t }, MatM) end
function MatM:SetAngles(a) self.ang = a end
MatM.__mul = function(m, v) return v end
function GetRenderTargetEx(n) return { GetName = function() return n end } end
function ParticleEmitter() return permissive({ IsValid = function() return true end, Add = function() return permissive({}) end }) end
function DrawBloom() end
function DrawMotionBlur() end
surface.DrawLine = function(...) CHECK_NUM("surface.DrawLine", ...) end
surface.PlaySound = function(p) SOUNDS[#SOUNDS + 1] = "sound/" .. p end
draw.RoundedBoxEx = function(r, x, y, w, h) CHECK_NUM("draw.RoundedBoxEx", r, x, y, w, h) end
draw.SimpleTextOutlined = function(t, f, x, y) CHECK_NUM("draw.SimpleTextOutlined", x, y) surface.SetFont(f) end
EntMeta.AddCallback = function(self, n, fn) self.cb = fn end
EntMeta.GetBoneName = function(self, i) return "ValveBiped.Bip01_R_Hand" end
EntMeta.SetBoneMatrix = function() end
EntMeta.GetModelBounds = function() return Vector(-10, -2, -3), Vector(20, 2, 6) end
EntMeta.SetBodygroup = function() end
EntMeta.SetAlpha = function() end
EntMeta.IsValid = function(self) return not self.__removed end
local cm0 = ClientsideModel
function ClientsideModel(m) local e = cm0(m) e.IsValid = function(s) return not s.__removed end return e end
FakePlyMeta = getmetatable(LOCALPLY).__index
FakePlyMeta.GetChildren = function() return {} end
FakePlyMeta.GetNW2Entity = function(self, k) return self.nw[k] end
FakePlyMeta.GetVelocity = function() return Vector() end
FakePlyMeta.GetPrimaryAmmoType = function() return 1 end
FakePlyMeta.LookupAttachment = function() return 0 end
FakePlyMeta.IsFlagSet = function() return false end
FakePlyMeta.DrawModel = function() DRAWS = DRAWS + 1 end
FakePlyMeta.IsOnGround = function() return true end
FakePlyMeta.GetViewEntity = function(self) return self end
FakePlyMeta.GetMoveType = function() return MOVETYPE_WALK end
FakePlyMeta.GetMaxHealth = function() return 100 end
os.date = os.date or function() return "12:00" end
local vc0 = vgui.Create
vgui.Create = function(cls, parent)
  local p = vc0(cls, parent)
  if cls == "DModelPanel" then rawset(p, "Entity", false) end   -- модели в панели нет (заглушка)
  rawset(p, "CursorPos", function() return 0, 0 end)
  return p
end
local mat0 = Material
function Material(p, f) return setmetatable(mat0(p, f), { __index = function() return function() end end }) end
local cmat0 = CreateMaterial
function CreateMaterial(n, sh, t) return setmetatable(cmat0(n, sh, t), { __index = function() return function() end end }) end
player = { GetAll = function() return { LOCALPLY } end, GetCount = function() return 1 end }
'''
    try:
        lua = sim.realm(False)
    finally:
        sim.PRELUDE = base
    lua.execute(CLIENT)
    snd = sorted(set(os.path.basename(s) for s in lua.globals().SOUNDS.values()))
    print("клиент: брифинг, инвентарь и микро-слоты, руки и опускание оружия, меню Q (сетка, перенос, R), метки,")
    print("        реплики, глава, подрыв, крушение, достижения, чат (лента, аватары, «печатает»), смерть → наблюдение,")
    print("        финал, редактор (%d строк) — без ошибок Lua и nil/NaN в отрисовке" % lua.globals().CLICKED)
    print("   звуки:", ", ".join(snd))
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
