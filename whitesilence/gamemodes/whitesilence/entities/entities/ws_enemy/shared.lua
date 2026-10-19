--[[
	ws_enemy — «Дельта-14»: то, что носит снаряжение погибшего отряда.

	NextBot на модели игрока (winterizedarmor) с анимациями игрока (ACT_HL2MP_*_AR2), поэтому не стоит «буквой Т»,
	как обычный NPC с моделью игрока. Оружие — модель мира tfa_ins2_ak12 на костях руки (bonemerge), звук и
	темп стрельбы берутся из самого оружия TFA; если аддона нет — АК-47 из CS:S/HL2.

	Режимы (ent.wsMode): guard — стоит на месте и осматривается, patrol — ходит между точками группы,
	assault — идёт к цели (ent.wsGoal), hunt — ищет ближайшего бойца. Увидев бойца, любой режим переходит в бой:
	  • ищет укрытие (место, где сидя не видно, а встав — можно стрелять) и бьёт из-за него: высунулся —
	    очередь — спрятался;
	  • в группе распределяет роли: кто-то давит огнём, один-два обходят с фланга;
	  • засевшего — подавляет огнём по последнему месту, выкуривает гранатой (по баллистике), потом ищет;
	  • раненый отходит в укрытие подальше; через своих не стреляет — делает шаг в сторону;
	  • первые выстрелы по новой цели шире, потом пристреливается; перезаряжается пригнувшись.
	Слышат стрельбу и шаги бега, зовут своих, реагируют голосом (обнаружение, перезарядка, граната, обход,
	ранение, потеря цели, гибель товарища).
]]
AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "Дельта-14"
ENT.Author = "John Make"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Category = "SCP: Белая тишина"

local ACT_IDLE_ = ACT_HL2MP_IDLE_AR2
local ACT_WALK_ = ACT_HL2MP_WALK_AR2
local ACT_RUN_ = ACT_HL2MP_RUN_AR2
local ACT_CIDLE = ACT_HL2MP_IDLE_CROUCH_AR2
local ACT_CWALK = ACT_HL2MP_WALK_CROUCH_AR2
local ACT_FIRE = ACT_HL2MP_GESTURE_RANGE_ATTACK_AR2
local ACT_RELOAD_ = ACT_HL2MP_GESTURE_RELOAD_AR2

local function cfg() return WS and WS.Config or {} end

if CLIENT then
	local glow = Material("sprites/light_glow02_add")

	-- глаза чуть светятся холодным светом — «что-то в них было уже не так»
	function ENT:Draw()
		self:DrawModel()
		if self:Health() <= 0 then return end
		local att = self:LookupAttachment("eyes")
		if not att or att <= 0 then return end
		local a = self:GetAttachment(att)
		if not a then return end
		local d = EyePos():Distance(a.Pos)
		if d > 1800 then return end
		local k = (1 - d / 1800) * (0.7 + 0.3 * math.sin(CurTime() * 3 + self:EntIndex()))
		local right = a.Ang:Right()
		render.SetMaterial(glow)
		for _, s in ipairs({ -1.4, 1.4 }) do
			render.DrawSprite(a.Pos + right * s + a.Ang:Forward() * 1.5, 5, 5, Color(170, 220, 255, 200 * k))
		end
	end

	return
end

-- ======================================================================== сервер

local BARK_SPOT = { "whitesilence/game/enemy_spot1.mp3", "whitesilence/game/enemy_spot2.mp3", "whitesilence/game/enemy_spot3.mp3" }
local BARK_IDLE = { "whitesilence/game/enemy_idle1.mp3", "whitesilence/game/enemy_idle2.mp3", "whitesilence/game/enemy_idle3.mp3" }
local BARK_RELOAD = { "whitesilence/game/enemy_reload1.mp3", "whitesilence/game/enemy_reload2.mp3" }
local BARK_GRENADE = { "whitesilence/game/enemy_grenade1.mp3", "whitesilence/game/enemy_grenade2.mp3" }
local BARK_FLANK = { "whitesilence/game/enemy_flank1.mp3", "whitesilence/game/enemy_flank2.mp3" }
local BARK_HURT = { "whitesilence/game/enemy_hurt1.mp3", "whitesilence/game/enemy_hurt2.mp3" }
local BARK_LOST = { "whitesilence/game/enemy_lost1.mp3", "whitesilence/game/enemy_lost2.mp3" }
local BARK_DOWN = { "whitesilence/game/enemy_down1.mp3", "whitesilence/game/enemy_down2.mp3" }
local lastBark = 0

local function bark(self, list, chance)
	if math.random() > (chance or 1) or CurTime() - lastBark < 4 or (self.nextBark or 0) > CurTime() then return end
	lastBark = CurTime()
	self.nextBark = CurTime() + math.Rand(10, 20)
	self:EmitSound(list[math.random(#list)], 78, math.random(94, 102), 1, CHAN_VOICE)
end

function ENT:Initialize()
	local C = cfg()
	local mdl = C.EnemyModel or "models/player/combine_soldier.mdl"
	if not util.IsValidModel(mdl) then mdl = C.SquadModelFallback or "models/player/combine_soldier.mdl" end
	self:SetModel(mdl)
	if self:SkinCount() > 1 then self:SetSkin(math.random(0, self:SkinCount() - 1)) end
	self:SetHealth(C.EnemyHealth or 110)
	self:SetMaxHealth(C.EnemyHealth or 110)
	self:SetBloodColor(BLOOD_COLOR_RED)
	self:SetCollisionBounds(Vector(-13, -13, 0), Vector(13, 13, 72))
	self:SetCollisionGroup(COLLISION_GROUP_NPC)

	self.loco:SetStepHeight(20)
	self.loco:SetJumpHeight(60)
	self.loco:SetDeathDropHeight(300)
	self.loco:SetAcceleration(700)
	self.loco:SetDeceleration(1200)
	self.loco:SetMaxYawRate(260)

	self:GiveWeapon(C.EnemyWeapon or "tfa_ins2_ak12")
	self.wsMode = self.wsMode or "guard"
	self.home = self:GetPos()
	self.homeYaw = self:GetAngles().y
	self.nextSense = 0
	self.crouch = false
	self.aimPitch, self.aimYaw = 0, 0
	self.nextStep = 0
end

function ENT:GiveWeapon(cls)
	local C = cfg()
	local st = weapons.GetStored(cls)
	local mdl = st and st.WorldModel
	if not mdl or mdl == "" or not util.IsValidModel(mdl) then mdl = C.EnemyWeaponFallback or "models/weapons/w_rif_ak47.mdl" end
	local w = ents.Create("prop_dynamic")
	if IsValid(w) then
		w:SetModel(mdl)
		w:SetPos(self:GetPos())
		w:SetAngles(self:GetAngles())
		w:SetParent(self)
		w:AddEffects(EF_BONEMERGE)
		w:SetSolid(SOLID_NONE)
		w:Spawn()
		self:DeleteOnRemove(w)
		self.wep = w
	end
	local prim = st and st.Primary or {}
	self.wepModel = mdl
	self.shotSound = isstring(prim.Sound) and prim.Sound or "Weapon_AK47.Single"
	self.rpm = math.Clamp(tonumber(prim.RPM) or 600, 300, 900)
	self.magSize = math.Clamp(tonumber(prim.ClipSize) or 30, 10, 60)
	self.ammo = self.magSize
end

-- ---------------------------------------------------------------- восприятие

local function shootPos(self)
	if IsValid(self.wep) then
		local a = self.wep:GetAttachment(1)
		if a then return a.Pos end
	end
	return self:GetPos() + Vector(0, 0, self.crouch and 38 or 60)
end

function ENT:EyeSpot() return self:GetPos() + Vector(0, 0, self.crouch and 44 or 64) end

local function validTarget(p)
	return IsValid(p) and p:IsPlayer() and p:Alive() and WS.Lobby.InGame(p) and not p.wsEditing
		and not p:IsFlagSet(FL_NOTARGET) and p:GetMoveType() ~= MOVETYPE_NOCLIP
end

function ENT:CanSee(p)
	local C = cfg()
	local eye = self:EyeSpot()
	local tgt = p:EyePos()
	local d = eye:Distance(tgt)
	local view = C.EnemyViewDist or 2600
	if d > view then return false end
	-- в спокойном состоянии — только перед собой; близко замечают и сзади (шаги в снегу)
	if not self.alerted and d > 260 then
		local dir = (tgt - eye):GetNormalized()
		if dir:Dot(self:GetForward()) < 0.45 then return false end
	end
	local tr = util.TraceLine({ start = eye, endpos = tgt, filter = { self, self.wep }, mask = MASK_SHOT })
	return tr.Entity == p or tr.Fraction > 0.97
end

function ENT:SetTarget(p)
	if self.target ~= p then
		self.target = p
		self.reactT = CurTime() + (cfg().EnemyReaction or 0.7) * math.Rand(0.8, 1.4)
		if IsValid(p) then bark(self, BARK_SPOT, 0.5) end
	end
	self.alerted = true
end

-- зовём своих в радиусе
function ENT:CallAllies(p, pos)
	for _, e in ipairs(ents.FindInSphere(self:GetPos(), 1400)) do
		if e ~= self and e:GetClass() == "ws_enemy" and e:Health() > 0 and not IsValid(e.target) then
			e.alerted = true
			e.lastKnown = pos
			e.lastKnownT = CurTime()
			if IsValid(p) and e:CanSee(p) then e:SetTarget(p) end
		end
	end
end

function ENT:Sense()
	local best, bd
	for _, p in ipairs(player.GetAll()) do
		if validTarget(p) then
			local d = p:GetPos():DistToSqr(self:GetPos())
			if (not bd or d < bd) and self:CanSee(p) then best, bd = p, d end
		end
	end
	if best then
		local fresh = not IsValid(self.target)
		self:SetTarget(best)
		self.targetVisible = true
		self.lastKnown = best:GetPos()
		self.lastKnownT = CurTime()
		self.wsSeenT = CurTime()
		if fresh then self:CallAllies(best, best:GetPos()) end
	else
		self.targetVisible = false
		-- цель помнится 8 с: успеть подавить огнём, бросить гранату, обойти
		if IsValid(self.target) and (not validTarget(self.target) or CurTime() - (self.lastKnownT or 0) > 8) then
			self.target = nil
		end
		-- бег в снегу слышно метров за десять
		for _, p in ipairs(player.GetAll()) do
			if validTarget(p) and p:GetVelocity():Length2D() > 170 and p:GetPos():DistToSqr(self:GetPos()) < 560 * 560 then
				self.alerted = true
				if not IsValid(self.target) then
					self.lastKnown = p:GetPos()
					self.lastKnownT = CurTime()
				end
			end
		end
	end
end

function ENT:Think()
	if self:Health() <= 0 then return end
	if CurTime() >= self.nextSense then
		self.nextSense = CurTime() + 0.25
		self:Sense()
		if not self.alerted and math.random() < 0.02 then
			for _, p in ipairs(player.GetAll()) do
				if validTarget(p) and p:GetPos():DistToSqr(self:GetPos()) < 900 * 900 then bark(self, BARK_IDLE, 0.4) break end
			end
		end
	end
	-- прицеливание корпусом и руками
	local wantP, wantY = 0, 0
	if IsValid(self.target) and self.targetVisible then
		local ang = (self.target:EyePos() - Vector(0, 0, 10) - self:EyeSpot()):Angle()
		wantP = math.NormalizeAngle(ang.p)
		wantY = math.NormalizeAngle(ang.y - self:GetAngles().y)
	end
	local ft = FrameTime()
	self.aimPitch = Lerp(math.min(ft * 8, 1), self.aimPitch, math.Clamp(wantP, -60, 60))
	self.aimYaw = Lerp(math.min(ft * 8, 1), self.aimYaw, math.Clamp(wantY, -60, 60))
	self:SetPoseParameter("aim_pitch", self.aimPitch)
	self:SetPoseParameter("aim_yaw", self.aimYaw)
	-- шаги по снегу
	local speed = self.loco:GetVelocity():Length2D()
	if speed > 30 and self.loco:IsOnGround() and CurTime() > self.nextStep then
		self.nextStep = CurTime() + (speed > 150 and 0.3 or 0.5)
		self:EmitSound("player/footsteps/snow" .. math.random(1, 6) .. ".wav", speed > 150 and 72 or 62, math.random(95, 105), 0.6)
	end
end

-- ---------------------------------------------------------------- анимация

function ENT:BodyUpdate()
	local act = self:GetActivity()
	if act == ACT_WALK_ or act == ACT_RUN_ or act == ACT_CWALK then
		self:BodyMoveXY()
		return
	end
	self:FrameAdvance()
end

function ENT:Act(act)
	if self:GetActivity() ~= act then self:StartActivity(act) end
end

-- ---------------------------------------------------------------- движение (внутри корутины)

-- check() -> true прерывает движение (например, появилась цель)
function ENT:MoveTo(pos, o)
	o = o or {}
	local C = cfg()
	local run = o.run
	self.crouch = false
	self.loco:SetDesiredSpeed(run and (C.EnemyRunSpeed or 205) or (C.EnemyWalkSpeed or 80))
	self:Act(run and ACT_RUN_ or ACT_WALK_)
	local deadline = CurTime() + (o.maxTime or 25)
	local tol = o.tolerance or 48
	if navmesh.IsLoaded() then
		local path = Path("Follow")
		path:SetMinLookAheadDistance(200)
		path:SetGoalTolerance(tol)
		path:Compute(self, pos)
		if path:IsValid() then
			while path:IsValid() do
				if o.check and o.check() then return "interrupted" end
				if CurTime() > deadline then return "timeout" end
				path:Update(self)
				if self.loco:IsStuck() then self:Unstick() return "stuck" end
				if o.follow and path:GetAge() > 0.8 then
					local f = o.follow()
					if f then path:Compute(self, f) end
				end
				coroutine.yield()
			end
			return "ok"
		end
	end
	-- без навмеша — напрямую, обходя мелкие препятствия прыжком
	local lastPos, lastMoveT = self:GetPos(), CurTime()
	while self:GetPos():Distance2D(pos) > tol do
		if o.check and o.check() then return "interrupted" end
		if CurTime() > deadline then return "timeout" end
		if o.follow then pos = o.follow() or pos end
		self.loco:Approach(pos, 1)
		self.loco:FaceTowards(pos)
		if self:GetPos():DistToSqr(lastPos) > 24 * 24 then
			lastPos, lastMoveT = self:GetPos(), CurTime()
		elseif CurTime() - lastMoveT > 1.2 then
			if self.loco:IsOnGround() then self.loco:Jump() end
			if CurTime() - lastMoveT > 3 then self:Unstick() return "stuck" end
		end
		coroutine.yield()
	end
	return "ok"
end

function ENT:Unstick()
	self.loco:ClearStuck()
	local dir = VectorRand()
	dir.z = 0
	self.loco:Approach(self:GetPos() + dir:GetNormalized() * 80, 1)
end

function ENT:Wait(sec, face)
	local untilT = CurTime() + sec
	while CurTime() < untilT do
		if face then
			local f = face()
			if f then self.loco:FaceTowards(f) end
		end
		coroutine.yield()
	end
end

-- ---------------------------------------------------------------- бой

function ENT:Shoot(suppress)
	local C = cfg()
	local t = self.target
	local src = shootPos(self)
	local aim
	if suppress or not IsValid(t) then
		-- подавление: по месту, где видели в последний раз, — шире и чаще
		aim = (self.lastKnown or (IsValid(t) and t:GetPos()) or self:GetPos() + self:GetForward() * 500) + Vector(0, 0, 40)
	else
		aim = t:GetPos() + Vector(0, 0, t:Crouching() and 32 or 46)
	end
	local dir = (aim - src):GetNormalized()
	-- не стрелять через своих
	local tr = util.TraceLine({ start = src, endpos = src + dir * 1500, filter = { self, self.wep }, mask = MASK_SHOT })
	if IsValid(tr.Entity) and tr.Entity:GetClass() == "ws_enemy" then
		self.blocked = (self.blocked or 0) + 1
		return false
	end
	local moving = IsValid(t) and math.Clamp(t:GetVelocity():Length() / 220, 0, 1.5) or 0.5
	local dist = math.Clamp(src:Distance(aim) / 1500, 0.3, 1.6)
	-- пристрелка: первые выстрелы по новой цели хуже, потом точнее
	local zero = math.Clamp(1.8 - (CurTime() - (self.engageT or CurTime())) * 0.18, 0.8, 1.8)
	local spread = (C.EnemySpread or 0.032) * (1 + moving) * dist * zero * (self.crouch and 0.75 or 1) * (suppress and 3 or 1)
	if self:Health() < self:GetMaxHealth() * 0.35 then spread = spread * 1.3 end
	self:FireBullets({
		Attacker = self, Inflictor = self, Num = 1, Src = src, Dir = dir,
		Spread = Vector(spread, spread, 0), Damage = C.EnemyDamage or 9, Force = 4,
		Tracer = 1, TracerName = "Tracer", IgnoreEntity = self,
	})
	self:EmitSound(self.shotSound, 95, math.random(97, 103), 1, CHAN_WEAPON)
	if IsValid(self.wep) then
		local ed = EffectData()
		ed:SetEntity(self.wep)
		ed:SetAttachment(1)
		ed:SetFlags(1)
		util.Effect("MuzzleFlash", ed, true, true)
		local att = self.wep:GetAttachment(1)
		if att then
			local sh = EffectData()
			sh:SetOrigin(att.Pos)
			sh:SetAngles(self:GetAngles())
			util.Effect("RifleShellEject", sh, true, true)
		end
	end
	self:RestartGesture(ACT_FIRE)
	self.ammo = self.ammo - 1
	return true
end

function ENT:Reload()
	bark(self, BARK_RELOAD, 0.5)
	self:RestartGesture(ACT_RELOAD_)
	self:EmitSound("weapons/ar2/npc_ar2_reload.wav", 65)
	-- перезаряжаться — пригнувшись
	self.crouch = true
	self:Act(ACT_CIDLE)
	self:Wait(2.3, function() return self.lastKnown end)
	self.ammo = self.magSize
end

-- ---------------------------------------------------------------- укрытия

local function groundAt(pos)
	local tr = util.TraceLine({ start = pos + Vector(0, 0, 40), endpos = pos - Vector(0, 0, 200), mask = MASK_NPCSOLID_BRUSHONLY })
	if tr.Hit and tr.HitNormal.z > 0.65 then return tr.HitPos end
end

local function blocked(a, b)
	local tr = util.TraceLine({ start = a, endpos = b, mask = MASK_OPAQUE })
	return tr.Hit
end

-- Место, где цель не видит сидящего; лучше — откуда можно высунуться. away — уходить от угрозы.
function ENT:FindCover(threat, away)
	if (self.nextCoverSearch or 0) > CurTime() then return self.cover end
	self.nextCoverSearch = CurTime() + 2.5
	local my = self:GetPos()
	local eye = threat + Vector(0, 0, 60)
	local cands = {}
	if navmesh.IsLoaded() then
		for _, a in ipairs(navmesh.Find(my, away and 900 or 600, 120, 120)) do
			cands[#cands + 1] = a:GetRandomPoint()
			if #cands > 24 then break end
		end
	else
		for i = 1, 20 do
			local ang = i / 20 * math.pi * 2 + math.Rand(-0.1, 0.1)
			local d = math.Rand(140, away and 800 or 520)
			local g = groundAt(my + Vector(math.cos(ang) * d, math.sin(ang) * d, 0))
			if g then cands[#cands + 1] = g end
		end
	end
	local best, bestScore
	for _, c in ipairs(cands) do
		local dThreat = c:Distance(threat)
		if dThreat > 280 and (not away or dThreat > my:Distance(threat)) then
			if blocked(c + Vector(0, 0, 36), eye) then
				local peek = not blocked(c + Vector(0, 0, 64), eye)
				local score = c:Distance(my) - (peek and 250 or 0) + (away and -dThreat * 0.3 or math.abs(dThreat - 700) * 0.4)
				-- не в одну точку с союзником
				for _, e in ipairs(ents.FindInSphere(c, 70)) do
					if e ~= self and e:GetClass() == "ws_enemy" then score = score + 400 end
				end
				if not bestScore or score < bestScore then best, bestScore = { pos = c, peek = peek }, score end
			end
		end
	end
	self.cover = best
	return best
end

-- ---------------------------------------------------------------- граната

local lastGrenade = 0
function ENT:ThrowGrenade(pos)
	if CurTime() - lastGrenade < 8 or (self.nextGrenade or 0) > CurTime() then return false end
	local src = self:GetPos() + Vector(0, 0, 70)
	local d = pos - src
	local flat = Vector(d.x, d.y, 0):Length()
	if flat < 280 or flat > 1100 then return false end
	lastGrenade, self.nextGrenade = CurTime(), CurTime() + math.Rand(20, 35)
	bark(self, BARK_GRENADE, 1)
	self.loco:FaceTowards(pos)
	self:RestartGesture(ACT_HL2MP_GESTURE_RANGE_ATTACK_GRENADE)
	self:Wait(0.45, function() return pos end)
	local g = ents.Create("npc_grenade_frag")
	if not IsValid(g) then return false end
	g:SetPos(src + self:GetForward() * 14)
	g:SetOwner(self)
	g:Spawn()
	g:Fire("SetTimer", "2.8")
	-- баллистика: время полёта по дальности, гравитация движка
	local t = math.Clamp(flat / 650, 0.7, 1.7)
	local grav = physenv.GetGravity()
	local vel = (d - grav * 0.5 * t * t) / t
	local ph = g:GetPhysicsObject()
	if IsValid(ph) then ph:SetVelocity(vel) ph:AddAngleVelocity(VectorRand() * 400) end
	self:Wait(0.4)
	return true
end

-- ---------------------------------------------------------------- бой

-- роль в группе: часть отряда давит огнём, один-два обходят с фланга
function ENT:PickRole(t)
	local engaged, flankers = 0, 0
	for _, e in ipairs(ents.FindInSphere(self:GetPos(), 1600)) do
		if e ~= self and e:GetClass() == "ws_enemy" and e.target == t then
			engaged = engaged + 1
			if e.role == "flank" then flankers = flankers + 1 end
		end
	end
	if engaged >= 2 and flankers < 2 and math.random() < 0.45 then return "flank" end
	return "fight"
end

-- очередь по видимой цели (из укрытия — высунувшись)
function ENT:Burst(t)
	local d = self:GetPos():Distance(t:GetPos())
	while CurTime() < (self.reactT or 0) and IsValid(t) do
		self.loco:FaceTowards(t:GetPos())
		coroutine.yield()
	end
	local n = math.random(3, d < 500 and 8 or 5)
	local gap = 60 / self.rpm
	self.blocked = 0
	for i = 1, n do
		if not IsValid(t) or not self.targetVisible or self.ammo <= 0 then break end
		self.burstShot = i
		self.loco:FaceTowards(t:GetPos())
		local to = (t:GetPos() - self:GetPos()):GetNormalized()
		if to:Dot(self:GetForward()) > 0.85 then
			if not self:Shoot() and self.blocked > 1 then
				-- свой на линии огня — шаг в сторону
				local side = to:Angle():Right() * (math.random() < 0.5 and -1 or 1)
				self:MoveTo(self:GetPos() + side * 120, { run = true, maxTime = 1, tolerance = 25 })
				return
			end
		end
		self:Wait(gap, function() return IsValid(t) and t:GetPos() end)
	end
	if self.ammo <= 0 then self:Reload() end
end

function ENT:Combat()
	local C = cfg()
	local t = self.target
	self.engageT = CurTime()
	self.role = self:PickRole(t)
	if self.role == "flank" then bark(self, BARK_FLANK, 0.7) end
	local hiddenSince
	while IsValid(self.target) do
		t = self.target
		local myPos, tPos = self:GetPos(), t:GetPos()
		local d = myPos:Distance(tPos)
		local hurt = self:Health() < self:GetMaxHealth() * 0.35

		-- ранен — отойти в укрытие подальше
		if hurt and not self.retreated then
			self.retreated = true
			bark(self, BARK_HURT, 0.8)
			local c = self:FindCover(tPos, true)
			if c then self:MoveTo(c.pos, { run = true, maxTime = 6, tolerance = 30 }) end
		end

		if not self.targetVisible then
			hiddenSince = hiddenSince or CurTime()
			local lost = CurTime() - hiddenSince
			-- цель засела: граната, подавляющий огонь, потом — искать
			if lost > 3 and self.lastKnown and math.random() < 0.35 and self:ThrowGrenade(self.lastKnown) then
				hiddenSince = CurTime()
			elseif lost > 1.2 and lost < 5 and self.lastKnown and self.role ~= "flank" and math.random() < 0.5 then
				self.loco:FaceTowards(self.lastKnown)
				self:Act(self.crouch and ACT_CIDLE or ACT_IDLE_)
				for _ = 1, math.random(3, 6) do
					if self.ammo <= 0 or self.targetVisible then break end
					self:Shoot(true)
					self:Wait(60 / self.rpm * 1.4)
				end
				if self.ammo <= 0 then self:Reload() end
			else
				self:Wait(math.Rand(0.4, 0.9), function() return self.lastKnown end)
			end
			if lost > 6 then break end      -- дальше — Investigate / обход
		else
			hiddenSince = nil
			if self.role == "flank" and d > 450 then
				-- обход: точка сбоку от цели
				local side = (tPos - myPos):Angle():Right() * (self:EntIndex() % 2 == 0 and 1 or -1)
				local goal = tPos + side * math.Rand(450, 650)
				local g = groundAt(goal) or goal
				self:MoveTo(g, { run = true, maxTime = 7, tolerance = 80, check = function()
					return IsValid(t) and self.targetVisible and self:GetPos():Distance(t:GetPos()) < 500
				end })
				self.role = "fight"
			elseif d > (C.EnemyEngage or 1300) then
				self:MoveTo(tPos, { run = true, maxTime = 2.5, tolerance = 200, check = function()
					return self.targetVisible and self:GetPos():Distance(t:GetPos()) < (C.EnemyEngage or 1300) * 0.8
				end, follow = function() return IsValid(t) and t:GetPos() or nil end })
			else
				-- к укрытию, если оно рядом; иначе — присесть и стрелять
				local cover = self.cover
				if (not cover or cover.pos:Distance(myPos) > 60) and math.random() < 0.55 then
					cover = self:FindCover(tPos)
					if cover and cover.pos:Distance(myPos) < 520 then
						self:MoveTo(cover.pos, { run = true, maxTime = 4, tolerance = 30 })
					end
				end
				local inCover = cover and cover.pos:Distance(self:GetPos()) < 70
				if inCover then
					-- высунуться, очередь, спрятаться
					self.crouch = false
					self:Act(ACT_IDLE_)
					self:Burst(t)
					self.crouch = true
					self:Act(ACT_CIDLE)
					self:Wait(math.Rand(0.8, 2.0), function() return IsValid(t) and t:GetPos() end)
				else
					self.crouch = math.random() < 0.4 and d > 300
					self:Act(self.crouch and ACT_CIDLE or ACT_IDLE_)
					self.loco:SetDesiredSpeed(0)
					self:Burst(t)
					self:Wait(math.Rand(0.35, 1.1), function() return IsValid(t) and t:GetPos() end)
					if math.random() < 0.3 and IsValid(t) then
						local side = (t:GetPos() - self:GetPos()):Angle():Right() * (math.random() < 0.5 and -1 or 1)
						self:MoveTo(self:GetPos() + side * math.Rand(140, 260), { run = true, maxTime = 1.6, tolerance = 30 })
					end
				end
			end
		end
		coroutine.yield()
	end
	self.crouch = false
	self.role = nil
end

-- ---------------------------------------------------------------- поведение

function ENT:Investigate()
	local pos = self.lastKnown
	self.lastKnown = nil
	if not pos then return end
	bark(self, BARK_LOST, 0.4)
	self:MoveTo(pos, { run = true, maxTime = 12, tolerance = 80, check = function() return IsValid(self.target) end })
	if IsValid(self.target) then return end
	-- осмотреться
	self:Act(ACT_IDLE_)
	for _ = 1, 3 do
		local yaw = math.Rand(0, 360)
		self:Wait(math.Rand(0.8, 1.6), function() return self:GetPos() + Angle(0, yaw, 0):Forward() * 100 end)
		if IsValid(self.target) then return end
	end
end

local function huntGoal(self)
	local best, bd
	for _, p in ipairs(player.GetAll()) do
		if validTarget(p) then
			local d = p:GetPos():DistToSqr(self:GetPos())
			if not bd or d < bd then best, bd = p, d end
		end
	end
	return best and best:GetPos()
end

function ENT:Idle()
	local mode = self.wsMode
	local seesTarget = function() return IsValid(self.target) or self.lastKnown ~= nil end
	if mode == "assault" or mode == "hunt" then
		local goal = mode == "hunt" and huntGoal(self) or self.wsGoal
		if goal and self:GetPos():Distance(goal) > 200 then
			self:MoveTo(goal, { run = true, maxTime = 6, tolerance = 150, check = seesTarget })
			return
		end
		-- дошли: дальше ищут ближайшего бойца
		self.wsMode = "hunt"
		local g = huntGoal(self)
		if g then
			self:MoveTo(g, { run = false, maxTime = 5, tolerance = 200, check = seesTarget })
			return
		end
	elseif mode == "patrol" then
		local spots = self.wsSpots or {}
		local dest
		if #spots > 1 then
			dest = spots[math.random(#spots)].pos
		else
			local dir = Angle(0, math.Rand(0, 360), 0):Forward()
			dest = self.home + dir * math.Rand(150, 600)
		end
		self:MoveTo(dest, { run = false, maxTime = 15, tolerance = 60, check = seesTarget })
		if seesTarget() then return end
	elseif mode == "guard" and self:GetPos():Distance(self.home) > 120 then
		self:MoveTo(self.home, { run = false, maxTime = 10, tolerance = 60, check = seesTarget })
		if seesTarget() then return end
	end
	-- постоять, осмотреться
	self:Act(ACT_IDLE_)
	local yaw = (mode == "guard" and self.homeYaw or self:GetAngles().y) + math.Rand(-70, 70)
	self:Wait(math.Rand(1.5, 4), function() return self:GetPos() + Angle(0, yaw, 0):Forward() * 100 end)
end

function ENT:RunBehaviour()
	while true do
		if IsValid(self.target) then
			self:Combat()
		elseif self.lastKnown then
			self:Investigate()
		else
			self:Idle()
		end
		coroutine.yield()
	end
end

-- ---------------------------------------------------------------- урон и смерть

function ENT:OnTraceAttack(dmg, dir, tr)
	if tr.HitGroup == HITGROUP_HEAD then
		dmg:ScaleDamage(cfg().EnemyHeadshot or 3)
		self.wsHeadHit = CurTime()
	end
end

function ENT:OnInjured(dmg)
	local a = dmg:GetAttacker()
	if validTarget(a) then
		self.alerted = true
		self.lastKnown = a:GetPos()
		self.lastKnownT = CurTime()
		if self:CanSee(a) then self:SetTarget(a) end
		self:CallAllies(a, a:GetPos())
	end
end

function ENT:OnKilled(dmg)
	hook.Run("OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor())
	-- ближайший союзник реагирует на гибель
	for _, e in ipairs(ents.FindInSphere(self:GetPos(), 900)) do
		if e ~= self and e:GetClass() == "ws_enemy" and e:Health() > 0 then
			bark(e, BARK_DOWN, 0.6)
			e.alerted = true
			e.lastKnown = e.lastKnown or self:GetPos()
			break
		end
	end
	hook.Run("WSEnemyKilled", self, dmg:GetAttacker())
	-- оружие падает на землю
	if IsValid(self.wep) and self.wepModel then
		local p = ents.Create("prop_physics")
		if IsValid(p) then
			p:SetModel(self.wepModel)
			p:SetPos(self.wep:GetPos())
			p:SetAngles(self.wep:GetAngles())
			p:Spawn()
			p:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
			SafeRemoveEntityDelayed(p, 60)
		end
	end
	local rag = self:BecomeRagdoll(dmg)
	if IsValid(rag) then SafeRemoveEntityDelayed(rag, 90) end
end

-- выстрелы бойцов слышно далеко: враги идут на звук
hook.Add("EntityFireBullets", "ws.enemy.hear", function(ent)
	if not (IsValid(ent) and ent:IsPlayer() and WS.Lobby.InGame(ent)) then return end
	if (ent.wsHeardT or 0) > CurTime() then return end
	ent.wsHeardT = CurTime() + 0.5
	local pos = ent:GetPos()
	for _, e in ipairs(ents.FindByClass("ws_enemy")) do
		if e:Health() > 0 and not IsValid(e.target) and e:GetPos():DistToSqr(pos) < 2200 * 2200 then
			e.alerted = true
			e.lastKnown = pos + VectorRand() * 150
			e.lastKnownT = CurTime()
		end
	end
end)
