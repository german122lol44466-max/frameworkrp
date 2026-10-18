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
vector_up, vector_origin, angle_zero = Vector(0, 0, 1), Vector(0, 0, 0), Angle(0, 0, 0)
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
  if c == "tfa_ins2_ak12" then return { WorldModel = "models/weapons/tfa_ins2/w_ak12.mdl", Primary = { Sound = "TFA_INS2.AK12.1", RPM = 700, ClipSize = 30 } } end
  if c == "tfa_ins2_usp_match" then return { WorldModel = "models/w_usp.mdl", Primary = {} } end
end }
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
  "SetSkin", "DrawShadow", "SetNoDraw", "SetNotSolid", "SetMoveType", "PhysicsInit", "SetNW2Entity", "AddFlags" }) do
  EntMeta2[m] = noop
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
  if SENTS[cls] then setmetatable(e, SENTS[cls]) e:SimInit() end
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
  -- попадает с вероятностью 15%: бойцы иногда получают урон
  local t = self.target
  if t and math.random() < 0.15 and t.TakeBullet then t:TakeBullet(b.Damage, self) end
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
  for k, v in pairs(NB) do meta[k] = v end
  for k, v in pairs(ENT) do meta[k] = v end
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
  self.dead = true
  self.hp = 0
  self.wsLastDmg = 2
  hook.Run("PlayerDeath", self, att, att)
end
local spawn0 = PLYMETA.Spawn
function PLYMETA:Spawn() self.dead = false self.hp = 100 spawn0(self) end

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
local S, P, C = WS.Story, WS.Story.P, WS.Config
assert(S.P, "точки сюжета загружены")
A = MakePlayer("Alpha", 1) B = MakePlayer("Bravo", 2)
A.admin = true
for _, p in ipairs(PLAYERS) do hook.Run("PlayerInitialSpawn", p) p:Spawn() end
LOG = {}
function log(fmt, ...) LOG[#LOG + 1] = string.format("%6.0f с  " .. fmt, NOW - T0, ...) end

function Tick()
  NOW = NOW + SIMDT
  RunTimers()
  hook.Run("Think")
  for _, e in ipairs(ENTS) do if e.SimTick and not e.__removed then e:SimTick() end end
end
function Run(sec, fn) local untilT = NOW + sec while NOW < untilT do Tick() if fn and fn() then return true end end return false end

-- игроки: идти к цели бегом, у предметов — удерживать E; отстреливаться
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
function Brain()
  local cur = S.Current()
  for _, p in ipairs(PLAYERS) do
    p.keys = {}
    if p.dead or not WS.Lobby.InGame(p) then goto skip end
    do
      -- бой: ближайший видимый враг в 1500 — выстрел раз в ~3 с (урон 40), стоим на месте
      local foe, fd
      for _, e in ipairs(ents.FindByClass("ws_enemy")) do
        local d = e.pos:Distance(p.pos)
        if e.hp > 0 and d < 1500 and (not fd or d < fd) then foe, fd = e, d end
      end
      if foe then
        p.yaw = (foe.pos - p.pos):Angle().y
        if NOW >= (nextShot[p] or 0) then
          nextShot[p] = NOW + math.Rand(2, 4)
          local d = DamageInfo() d:SetDamage(40) d:SetAttacker(p) d:SetInflictor(p)
          foe:TakeDamageInfo(d)
          hook.Run("EntityFireBullets", p, {})
        end
        goto skip
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
      if target then
        local off = Vector((p.idx - 1.5) * 60, 0, 0)
        moveTo(p, target + off, C.RunSpeed)
      end
    end
    ::skip::
  end
end
function Play(sec, cond) return Run(sec, function() Brain() return cond and cond() end) end

-- 1. выдвижение отряда
T0 = NOW
for _, p in ipairs(PLAYERS) do Recv("ws.lobby.open", p) end
B.wsThrottle = nil
local lobbyA = A:GetNW2Int("ws_lobby")
B:SetNW2Int("ws_lobby", lobbyA) B:SetNW2Bool("ws_lead", false)
Recv("ws.lobby.start", A)
assert(A:GetNW2Bool("ws_ingame") and B:GetNW2Bool("ws_ingame"), "отряд в игре")
Run(7)
assert(S.State.running and S.State.ch == 1 and S.State.step >= 1, "глава 1 началась")
local spawnPos = P.Get("spawn")
assert(A.pos:Distance(spawnPos) < 400, "появились у точки высадки")
log("глава 1, шаг %d", S.State.step)

local lastCh, lastStep = 0, 0
local died, wiped = false, false
local function watch()
  if S.State.ch ~= lastCh or S.State.step ~= lastStep then
    lastCh, lastStep = S.State.ch, S.State.step
    local cur = S.Current()
    log("глава %d «%s», шаг %d: %s %s", lastCh, S.Chapters[lastCh].title, lastStep, cur and cur.def.type or "-", cur and (cur.def.text or "") or "")
  end
end

-- 2. играем; в главе 2 гибнет Bravo и возвращается к отряду; в главе 3 гибнет весь отряд
local finished = false
local guard = 0
while not finished do
  guard = guard + 1
  if guard >= 40000 then for _, l in ipairs(LOG) do print(l) end end
  assert(guard < 40000, "сюжет завис: глава " .. S.State.ch .. " шаг " .. S.State.step .. " running=" .. tostring(S.State.running))
  Play(1)
  watch()
  for _, m in ipairs(NET_TO) do if m.name == "ws.story.finish" then finished = true end end
  -- случайные гибели от огня врагов: экран смерти → меню → к отряду (или заново, если погибли все)
  for _, p in ipairs(PLAYERS) do
    if p.dead and WS.Lobby.InGame(p) and NOW - (p.wsDeathT or NOW) > 6 then
      Recv("ws.death.return", p)
      log("%s погиб в бою", p.name)
    end
  end
  for _, p in ipairs(PLAYERS) do
    if not WS.Lobby.InGame(p) and not finished then
      local anyAlive = false
      for _, q in ipairs(PLAYERS) do if WS.Lobby.InGame(q) and not q.dead then anyAlive = true end end
      if anyAlive or (not S.State.running and (p == A)) then
        p.wsThrottle = nil
        Recv("ws.lobby.start", p)
      end
    end
  end
  if S.State.ch == 2 and not died then
    died = true
    B:Kill(WORLDENT)
    assert(B:GetNW2Bool("ws_ingame"), "погибший пока в игре (экран смерти)")
    Run(6)
    Recv("ws.death.return", B)
    assert(not B:GetNW2Bool("ws_ingame"), "после экрана смерти — в меню")
    B.wsThrottle = nil
    Recv("ws.lobby.start", B)
    assert(B:GetNW2Bool("ws_ingame") and not B.dead, "вернулся к отряду")
    Run(0.2)
    assert(B.pos:Distance(A.pos) < 400, "подкрепление появилось рядом с товарищем")
    log("Bravo погиб и вернулся к отряду")
  end
  if S.State.ch == 3 and S.State.step >= 3 and not wiped then
    wiped = true
    A:Kill(WORLDENT) B:Kill(WORLDENT)
    Run(C.StoryWipeDelay + 1)
    assert(not S.State.running and S.State.ch == 3, "гибель отряда: глава откатилась и ждёт")
    assert(#ents.FindByClass("ws_enemy") == 0, "враги убраны после отката")
    Run(6)
    Recv("ws.death.return", A) Recv("ws.death.return", B)
    A.wsThrottle = nil
    Recv("ws.lobby.start", A)
    Run(7)
    assert(S.State.running and S.State.ch == 3, "глава 3 началась заново")
    log("отряд погиб — глава 3 заново")
  end
end
local total = NOW - T0
log("финал")
assert(died and wiped, "сценарии гибели пройдены")
-- 3. финал: через StoryEndTime все в меню, сюжет сброшен
Run(C.StoryEndTime + 1)
assert(not A:GetNW2Bool("ws_ingame") and not B:GetNW2Bool("ws_ingame"), "после финала — меню")
assert(not S.State.running and S.State.ch == 1, "операция сброшена")
RESULT = { total = total, kills = S.Stats.kills, deaths = S.Stats.deaths, shots = SHOTS, hits = HITS, ragdolls = RAGDOLLS }

-- 4. редактор
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
local tested = #ents.FindByClass("ws_enemy")
assert(tested >= 3, "тестовый спавн группы")
for i = 1, 20 do Tick() end
op("clear")
assert(#ents.FindByClass("ws_enemy") == 0, "убрать врагов")
op("auto")
for _, d in ipairs(S.Points) do assert(P.IsSet(d.id), "авто: " .. d.id) end
op("save")
local f = FILES["whitesilence/points/gm_snowtest.json"]
assert(f and f:find("crash"), "файл точек записан")
op("reset", "crash")
assert(not P.IsSet("crash"), "сброс точки")
op("reload")
assert(P.IsSet("crash") and P.Get("crash"):Distance(Vector(1000, 2000, 0)) < 1, "загрузка из файла")
local _, _, r2 = P.Get("crash") assert(r2 == 640, "радиус из файла")
assert(#P.GroupSpots("ambush") == 2, "группа из файла")
op("story", 5)
assert(S.State.running and S.State.ch == 5, "редактор: запуск главы")
op("story", 0)
assert(not S.State.running, "редактор: стоп")
concommand.t["scp_edit"](A)
assert(not A.wsEditing, "редактор выключен")
EDITOR_OK = true
'''

CLIENT = r'''
local S = WS.Story
local me = LOCALPLY
me.nw.ws_ingame = true
me.pos = Vector(0, 0, 0)
function me:GetPos() return self.pos end
function me:EyePos() return self.pos + Vector(0, 0, 64) end
function EyePos() return me:EyePos() end
function EyeAngles() return Angle(0, 0, 0) end
WS.Intro.IsPlaying = function() return false end
WS.Menu.IsOpen = function() return false end
local function frame(n)
  for i = 1, n or 1 do
    NOW = NOW + 1 / 30
    hook.Run("Think")
    hook.Run("HUDPaint")
    hook.Run("PostDrawTranslucentRenderables", false, false)
  end
end
WS.Wake.Start = WS.Wake.Start or function() end
frame(60)
-- состояние: задача + метки (впереди далеко, вблизи, сбоку, сзади, зона, враг-сущность)
local foe = setmetatable({ pos = Vector(900, 300, 0) }, { __index = function(t, k) if k == "GetPos" then return function(s) return s.pos end end end })
local function state(text, prog, frac, marks)
  local q = { true, 3, text, prog, frac, #marks }
  for _, m in ipairs(marks) do
    q[#q + 1] = m[1] q[#q + 1] = m[2] q[#q + 1] = m[3] q[#q + 1] = m[4] q[#q + 1] = m[5] or NULL
  end
  Recv("ws.story.state", nil, table.unpack(q))
end
state("Удерживать ретранслятор", "1:42", 0.3, {
  { Vector(3000, 0, 0), "defend", "Удерживать", 450 },
  { Vector(120, 0, 0), "goto", "", 0 },
  { Vector(0, 2000, 0), "radio", "Запустить", 0 },
  { Vector(-2000, 0, 0), "extract", "", 0 },
  { Vector(0, 0, 0), "enemy", "", 0, foe },
})
assert(#WS.Markers.List == 5, "метки приняты")
frame(90)
-- метка вблизи исчезает: считаем отрисовки ромба
local near = 0
local orig = surface.DrawTexturedRect
state("Дойти", "", -1, { { Vector(60, 0, 0), "goto", "", 0 } })
local d0 = DRAWS frame(10) local nearDraws = DRAWS - d0
state("Дойти", "", -1, { { Vector(2500, 0, 0), "goto", "", 0 } })
d0 = DRAWS frame(10) local farDraws = DRAWS - d0
assert(farDraws > nearDraws, "метка вблизи не рисуется (" .. nearDraws .. " против " .. farDraws .. ")")
-- реплики всех говорящих, карточка главы, кольцо E, подрыв
for _, id in ipairs({ "c1_a", "c1_c", "c2_b" }) do Recv("ws.story.line", nil, id) frame(40) end
Recv("ws.story.chapter", nil, 4) frame(120)
me.nw.ws_use = 0.6 me.nw.ws_use_label = "Осмотреть" frame(10)
me.nw.ws_use = 0 frame(2)
state("Осмотреть тела", "1 / 3", 0.33, { { Vector(90, 0, 40), "search", "Осмотреть", 0 } })
frame(10)
Recv("ws.story.boom", nil, Vector(500, 0, 0)) frame(100)
-- финал
Recv("ws.story.finish", nil, 1925.5, 47, 3)
frame(30 * 22)
assert(S.Ending, "финальные титры")
me.nw.ws_ingame = false frame(5)
assert(not S.Ending, "финал закрылся после возврата в меню")
me.nw.ws_ingame = true
-- редактор
local q = { true, true, 2, 1 }
for _, d in ipairs(S.Points) do q[#q + 1] = Vector(math.random(-3000, 3000), math.random(-3000, 3000), 0) q[#q + 1] = 45 q[#q + 1] = d.r or 0 q[#q + 1] = math.random() < 0.5 end
for i, g in ipairs(S.Groups) do
  local n = i % 3 q[#q + 1] = n
  for k = 1, n do q[#q + 1] = Vector(k * 100, i * 100, 0) q[#q + 1] = 0 end
end
Recv("ws.edit.state", nil, table.unpack(q))
assert(S.Editor.on, "редактор включён")
local root
for _, p in ipairs(VGUI_ALL) do if p.cls == "DPanel" and not p.parent and not p.__removed then root = p end end
assert(root, "панель редактора")
hook.Run("OnContextMenuOpen")
for i = 1, 30 do PaintTree(root) frame(1) end
-- выбрать точку и группу, нажать все кнопки
local function clickAll()
  local n = 0
  for _, p in ipairs(VGUI_ALL) do
    if not p.__removed and p.cls == "DButton" and p.DoClick then
      local alive, q = true, p
      while q do if q.__removed then alive = false end q = q.parent end
      if alive and p ~= SKIP then p.hover = true PaintTree(p) p:DoClick() n = n + 1 end
    end
  end
  return n
end
SENT0 = #NET_SENT
-- строки списка: первая точка, затем группа
local rows = {}
for _, p in ipairs(VGUI_ALL) do if p.cls == "DButton" and p.parent and p.parent.cls == "DScrollPanel" then rows[#rows + 1] = p end end
assert(#rows == #S.Points + #S.Groups, "в списке все точки и группы: " .. #rows)
rows[2]:DoClick() PaintTree(root)
rows[#S.Points + 1]:DoClick() PaintTree(root)
rows[3]:DoClick() PaintTree(root)
local clicked = clickAll()
for i = 1, 10 do PaintTree(root) frame(1) end
hook.Run("OnContextMenuClose")
Recv("ws.edit.state", nil, false)
assert(not S.Editor.on, "редактор выключен")
frame(10)
CLICKED = clicked
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
    load_entity(lua, "ws_enemy")
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
    g.util.JSONToTable = lambda s: from_py(json.loads(s))
    lua.execute(SERVER)
    r = g.RESULT
    print("сервер: сюжет пройден от выдвижения до финала, гибель бойца и всего отряда, возврат в меню")
    for line in g.LOG.values():
        print("   ", line)
    print("   время прохождения (бег без препятствий, ровное поле, боты-стрелки): %d мин %d с" % (r.total // 60, r.total % 60))
    print("   уничтожено врагов: %d, гибелей: %d, выстрелов врагов: %d, попаданий по бойцам: %d" % (r.kills, r.deaths, r.shots, r.hits))
    assert g.EDITOR_OK
    print("сервер: scp_edit — точки, радиус, группы, тест-спавн, авто, сохранение/загрузка, запуск главы — ок")
    print("   json:", (g.FILES["whitesilence/points/gm_snowtest.json"] or "")[:160].replace("\n", " "), "…")
    if r.total < 25 * 60:
        errors.append("сюжет короче 25 минут даже в упрощённом прогоне: %d с" % r.total)


def client_test(errors):
    base = sim.PRELUDE
    sim.PRELUDE = base + menu_sim.EXTRA.replace("local PlyMeta = {}", "PlyMeta = {} PLYMETA = PlyMeta") + menu_sim.VGUI + WORLD.split("-- игроки: позиция")[0] + r'''
NETQ = {}
local function pop() return table.remove(NETQ, 1) end
net.ReadBool, net.ReadUInt, net.ReadString, net.ReadFloat, net.ReadVector, net.ReadEntity = pop, pop, pop, pop, pop, pop
function Recv(name, ply, ...) NETQ = { ... } net.r[name](0, ply) end
function LocalPlayer() return LOCALPLY end
player = { GetAll = function() return { LOCALPLY } end, GetCount = function() return 1 end }
'''
    try:
        lua = sim.realm(False)
    finally:
        sim.PRELUDE = base
    lua.execute(CLIENT)
    snd = sorted(set(os.path.basename(s) for s in lua.globals().SOUNDS.values()))
    print("клиент: задача, метки (исчезают вблизи), реплики, глава, E, подрыв, финал, редактор (%d кнопок) — без ошибок"
          % lua.globals().CLICKED)
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
