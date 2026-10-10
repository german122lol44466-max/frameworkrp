--[[
	Руки — выдаются всем. Вьюмодель не рисуется (руки видно у тела).
	Перенос как в ix_hands (Helix): ПКМ по предмету, телу или любому незакреплённому объекту — взять,
	ещё раз ПКМ — отпустить. Объект держится перед вами (тело — ниже, волочится);
	ЛКМ — бросить предмет, R + мышь — повернуть.
	С пустыми руками ЛКМ — удар кулаком (левой/правой по очереди, третий подряд — апперкот),
	руки поднимаются в стойку на 3 секунды; по двери — постучать.
	Пока держите — справа панель с названием, от неё к точке захвата тонкая линия с квадратом
	(как у подсказок Helix), линия «дорисовывается» при захвате.
]]

AddCSLuaFile()

SWEP.PrintName = "Руки"
SWEP.Author = "NYRP"
SWEP.Slot = 0
SWEP.SlotPos = 1
SWEP.Spawnable = false
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = true
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.HoldType = "normal"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.holdDistance = 60
SWEP.maxHoldDistance = 100   -- дальше — выскальзывает
SWEP.maxHoldStress = 4000
SWEP.maxMass = 120           -- тяжелее (кроме тел) — не поднять
SWEP.throwForce = 700

function SWEP:SetupDataTables()
	self:NetworkVar("Entity", 0, "GrabEnt")
	self:NetworkVar("Int", 0, "GrabBone")
	self:NetworkVar("Vector", 0, "GrabLocal")
	self:NetworkVar("Float", 0, "GrabTime")
	self:NetworkVar("Float", 1, "RaisedUntil")
	self:NetworkVar("Float", 2, "PunchTime")
	self:NetworkVar("Int", 1, "PunchCount")
end

function SWEP:Initialize()
	-- две таблицы поз: обычная (руки опущены) и «fist» (стойка) — переключаются TranslateActivity
	self:SetHoldType("fist")
	self.FistAT = table.Copy(self.ActivityTranslate or {})
	self:SetHoldType(self.HoldType)
	self.NormalAT = table.Copy(self.ActivityTranslate or {})
	self.heldAngle = Angle()
end

function SWEP:Raised() return self:GetRaisedUntil() > CurTime() end

function SWEP:TranslateActivity(act)
	local t = self:Raised() and self.FistAT or self.NormalAT
	if t and t[act] then return t[act] end
	return -1
end

function SWEP:IsGrabbing() return IsValid(self:GetGrabEnt()) end

-- Точка захвата в мире.
function SWEP:GrabPoint()
	local ent = self:GetGrabEnt()
	if not IsValid(ent) then return end
	local bone = self:GetGrabBone()
	if bone >= 0 and ent:IsRagdoll() then
		if SERVER then
			local phys = ent:GetPhysicsObjectNum(bone)
			return IsValid(phys) and LocalToWorld(self:GetGrabLocal(), Angle(), phys:GetPos(), phys:GetAngles()) or nil
		end
		local m = ent:GetBoneMatrix(ent:TranslatePhysBoneToBone(bone))
		if m then return LocalToWorld(self:GetGrabLocal(), Angle(), m:GetTranslation(), m:GetAngles()) end
		return ent:GetPos()
	end
	return ent:LocalToWorld(self:GetGrabLocal())
end

local function canHold(ent, phys, isBody, maxMass)
	if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsVehicle() then return false end
	if not IsValid(phys) or not phys:IsMotionEnabled() then return false end
	local cls = ent:GetClass()
	if cls == "nyrp_container" or cls == "nyrp_vending" or cls == "nyrp_npc" then return false end
	if ent.nyrpHeldBy and IsValid(ent.nyrpHeldBy) then return false end
	return isBody or phys:GetMass() <= maxMass
end

if SERVER then
	function SWEP:Pickup(ent, tr)
		local isBody = ent:IsRagdoll()
		local bone = isBody and (tr.PhysicsBone or 0) or 0
		local phys = ent:GetPhysicsObjectNum(bone)
		if not canHold(ent, phys, isBody, self.maxMass) then
			if IsValid(phys) and not isBody and phys:GetMass() > self.maxMass and IsValid(ent) and not ent:IsPlayer() then
				NYRP.Notify(self:GetOwner(), "Слишком тяжело", "warning", 2)
			elseif IsValid(phys) and not phys:IsMotionEnabled() and IsValid(ent) and not ent:IsPlayer() then
				NYRP.Notify(self:GetOwner(), "Закреплено — не взять", "warning", 2)
			end
			return
		end
		local ply = self:GetOwner()
		ent.nyrpHeldBy = ply
		ent.nyrpOldGroup = ent:GetCollisionGroup()
		ent:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		phys:AddGameFlag(FVPHYSICS_PLAYER_HELD)
		if not isBody then phys:EnableGravity(false) end

		-- невидимая «рука», к которой приварен предмет; её ведём ComputeShadowControl
		local hold = ents.Create("prop_physics")
		hold:SetModel("models/weapons/w_bugbait.mdl")
		hold:SetPos(isBody and phys:GetPos() or ent:LocalToWorld(ent:OBBCenter()))
		hold:SetAngles(isBody and phys:GetAngles() or ent:GetAngles())
		hold:SetOwner(ply)
		hold:SetNoDraw(true)
		hold:SetNotSolid(true)
		hold:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		hold:DrawShadow(false)
		hold:Spawn()
		local hp = hold:GetPhysicsObject()
		if IsValid(hp) then
			hp:SetMass(2048)
			hp:SetDamping(0, 1000)
			hp:EnableGravity(false)
			hp:EnableCollisions(false)
			hp:EnableMotion(false)
		end
		self.hold = hold
		self.weld = constraint.Weld(hold, ent, 0, bone, 0, true, true)
		self.heldAngle = isBody and phys:GetAngles() or ent:GetAngles()
		self.lastYaw = ply:EyeAngles().y

		self:SetGrabEnt(ent)
		self:SetGrabBone(isBody and bone or -1)
		self:SetGrabLocal(isBody and WorldToLocal(tr.HitPos, Angle(), phys:GetPos(), phys:GetAngles()) or ent:WorldToLocal(tr.HitPos))
		self:SetGrabTime(CurTime())
		ply:SetNW2Bool("nyrp.dragging", isBody)
		ply:EmitSound(isBody and "physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav" or "Flesh.ImpactSoft", 60)
	end

	function SWEP:Drop(throw)
		local ent = self:GetGrabEnt()
		local ply = self:GetOwner()
		if IsValid(self.weld) then self.weld:Remove() end
		if IsValid(self.hold) then self.hold:Remove() end
		self.weld, self.hold = nil, nil
		if IsValid(ply) then ply:SetNW2Bool("nyrp.dragging", false) end
		self:SetGrabEnt(NULL)
		if not IsValid(ent) then return end
		ent.nyrpHeldBy = nil
		ent:SetCollisionGroup(ent.nyrpOldGroup or COLLISION_GROUP_NONE)
		for i = 0, ent:GetPhysicsObjectCount() - 1 do
			local p = ent:GetPhysicsObjectNum(i)
			if IsValid(p) then
				p:EnableGravity(true)
				p:ClearGameFlag(FVPHYSICS_PLAYER_HELD)
				p:Wake()
			end
		end
		if throw and IsValid(ply) and not ent:IsRagdoll() then
			timer.Simple(0, function()
				local p = IsValid(ent) and ent:GetPhysicsObject()
				if IsValid(p) and IsValid(ply) then
					p:AddGameFlag(FVPHYSICS_WAS_THROWN)
					p:ApplyForceCenter(ply:GetAimVector() * math.min(self.throwForce * p:GetMass() / 10, 9000))
				end
			end)
		end
	end
end

local PUNCH_RANGE = 52
local SWING = { "WeaponFrag.Throw" }

local function isDoor(e)
	if not IsValid(e) then return false end
	local c = e:GetClass()
	return c == "prop_door_rotating" or c == "func_door" or c == "func_door_rotating"
end

function SWEP:PrimaryAttack()
	if self:IsGrabbing() then
		if SERVER then self:Drop(true) end
		self:SetNextPrimaryFire(CurTime() + 0.5)
		self:SetNextSecondaryFire(CurTime() + 0.5)
		return
	end
	local ply = self:GetOwner()
	if not IsValid(ply) or (NYRP.Cond and NYRP.Cond.KO(ply)) then return end
	if NYRP.Factions and NYRP.Factions.Cuffed and NYRP.Factions.Cuffed(ply) then return end
	local start, dir = ply:GetShootPos(), ply:GetAimVector()
	local tr = util.TraceLine({ start = start, endpos = start + dir * 70, filter = ply, mask = MASK_SHOT_HULL })
	-- стук в дверь
	if isDoor(tr.Entity) and not self:Raised() then
		self:SetNextPrimaryFire(CurTime() + 0.9)
		ply:SetAnimation(PLAYER_ATTACK1)
		if SERVER then
			for i = 0, 2 do
				timer.Simple(i * 0.18, function()
					if IsValid(tr.Entity) then tr.Entity:EmitSound("physics/wood/wood_crate_impact_hard" .. math.random(2, 3) .. ".wav", 70, math.random(95, 110), 0.8) end
				end)
			end
		end
		return
	end
	-- удар
	local st = ply:GetNW2Float("nyrp.stamina", 100)
	if st < 8 then
		self:SetNextPrimaryFire(CurTime() + 0.5)
		return
	end
	local n = (CurTime() - self:GetPunchTime() < 1.2) and self:GetPunchCount() + 1 or 1
	self:SetPunchCount(n)
	self:SetPunchTime(CurTime())
	self:SetRaisedUntil(CurTime() + 3)
	local upper = n % 3 == 0
	self:SetNextPrimaryFire(CurTime() + (upper and 0.85 or 0.5))
	ply:SetAnimation(PLAYER_ATTACK1)
	ply:ViewPunch(Angle(upper and -3 or 1.5, (n % 2 == 0) and 1.5 or -1.5, 0))
	if CLIENT then return end
	ply:SetNW2Float("nyrp.stamina", math.max(0, st - (upper and 9 or 6)))
	ply:EmitSound(SWING[1], 60, math.random(95, 110), 0.6)
	ply:LagCompensation(true)
	local hit = util.TraceHull({ start = start, endpos = start + dir * PUNCH_RANGE, filter = ply, mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8), mask = MASK_SHOT_HULL })
	ply:LagCompensation(false)
	timer.Simple(0.12, function()
		if not IsValid(ply) or not IsValid(self) then return end
		local e = hit.Entity
		if not hit.Hit then return end
		if not IsValid(e) then
			ply:EmitSound("Flesh.ImpactSoft", 60)
			return
		end
		local SK = NYRP.Skills
		local lvl = SK and SK.Level and SK.Level(ply, "strength") or 0
		local dmg = math.random(4, 7) + lvl * 0.8 + (upper and 4 or 0)
		local d = DamageInfo()
		d:SetDamage(dmg)
		d:SetDamageType(DMG_CLUB)
		d:SetAttacker(ply)
		d:SetInflictor(self)
		d:SetDamageForce(dir * (upper and 9000 or 4000))
		d:SetDamagePosition(hit.HitPos)
		e:TakeDamageInfo(d)
		if e:IsPlayer() or e:IsNPC() or e:IsRagdoll() then
			e:EmitSound("Flesh.ImpactHard", 70, math.random(95, 110))
			if e:IsPlayer() then e:ViewPunch(Angle(math.Rand(-6, -2), math.Rand(-4, 4), 0)) end
		else
			e:EmitSound("Flesh.ImpactSoft", 60)
			local ph = e:GetPhysicsObject()
			if IsValid(ph) then ph:ApplyForceOffset(dir * 3000, hit.HitPos) end
		end
	end)
end

function SWEP:SecondaryAttack()
	if CLIENT then return end
	-- ПКМ: взять, ещё раз ПКМ — отпустить
	if self:IsGrabbing() then
		self:Drop(false)
		self:SetNextSecondaryFire(CurTime() + 0.3)
		return
	end
	local ply = self:GetOwner()
	if not IsValid(ply) or (NYRP.Cond and NYRP.Cond.KO(ply)) then return end
	-- луч + «толстый» луч: мелкие предметы (группа столкновений WEAPON) обычный луч мог не задевать
	local start, dir = ply:GetShootPos(), ply:GetAimVector()
	local tr = util.TraceLine({ start = start, endpos = start + dir * 90, filter = { self, ply }, mask = MASK_SHOT })
	if not IsValid(tr.Entity) or tr.Entity:IsWorld() then
		tr = util.TraceHull({ start = start, endpos = start + dir * 90, mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4),
			filter = { self, ply }, mask = MASK_SHOT, ignoreworld = true })
	end
	if IsValid(tr.Entity) then self:Pickup(tr.Entity, tr) end
	self:SetNextSecondaryFire(CurTime() + 0.4)
end

function SWEP:Reload() end -- R занят вращением

function SWEP:Holster() if SERVER then self:Drop(false) end return true end
function SWEP:OnRemove() if SERVER then self:Drop(false) end end
function SWEP:OnDrop() if SERVER then self:Drop(false) end end
function SWEP:OwnerChanged() if SERVER then self:Drop(false) end end

function SWEP:Think()
	if CLIENT or not self:IsGrabbing() then return end
	local ply = self:GetOwner()
	local ent = self:GetGrabEnt()
	if not IsValid(ply) or not ply:Alive() or not IsValid(self.hold) or (NYRP.Cond and NYRP.Cond.KO(ply)) then
		self:Drop(false)
		return
	end
	local isBody = ent:IsRagdoll()
	local dist = isBody and self.holdDistance * 0.6 or self.holdDistance
	local target = ply:GetShootPos() + ply:GetAimVector() * dist
	if isBody then target.z = math.min(target.z, ply:GetShootPos().z - 32) end

	local phys = ent:GetPhysicsObjectNum(isBody and self:GetGrabBone() or 0)
	if not IsValid(phys) or phys:GetPos():DistToSqr(target) > self.maxHoldDistance ^ 2 or phys:GetStress() > self.maxHoldStress then
		self:Drop(false)
		return
	end
	-- ПКМ + мышь — вращение; поворот головы — вращает предмет вместе с вами
	local eye = ply:EyeAngles()
	if ply:KeyDown(IN_RELOAD) and not isBody then
		local cmd = ply:GetCurrentCommand()
		self.heldAngle:RotateAroundAxis(eye:Forward(), cmd:GetMouseX() / 15)
		self.heldAngle:RotateAroundAxis(eye:Right(), cmd:GetMouseY() / 15)
	end
	self.heldAngle.y = self.heldAngle.y - math.AngleDifference(self.lastYaw or eye.y, eye.y)
	self.lastYaw = eye.y

	local hp = self.hold:GetPhysicsObject()
	if not IsValid(hp) then self:Drop(false) return end
	hp:Wake()
	hp:ComputeShadowControl({
		secondstoarrive = 0.01, pos = target, angle = self.heldAngle,
		maxangular = 256, maxangulardamp = 10000, maxspeed = isBody and 180 or 256, maxspeeddamp = 10000,
		dampfactor = 0.8, teleportdistance = self.maxHoldDistance * 0.75, deltatime = FrameTime(),
	})
end

-- R + мышь: пока вращаем предмет, камера стоит на месте.
if CLIENT then
	hook.Add("CreateMove", "nyrp.hands.rotate", function(cmd)
		local ply = LocalPlayer()
		local w = ply:GetActiveWeapon()
		if IsValid(w) and w:GetClass() == "nyrp_hands" and w.IsGrabbing and w:IsGrabbing() and cmd:KeyDown(IN_RELOAD)
			and not w:GetGrabEnt():IsRagdoll() then
			cmd:ClearMovement()
			local a = RenderAngles()
			a.z = 0
			cmd:SetViewAngles(a)
		end
	end)
end

function SWEP:DrawWorldModel() end
function SWEP:ShouldDrawViewModel() return false end

-- ---------------------------------------------------- кулаки от 1-го лица --
-- Камера «с телом» не показывает вьюмодель — рисуем c_arms с анимациями кулаков сами, пока руки в стойке.
if CLIENT then
	local VM_FOV = 62
	local vm, hands, seqName, seqStart, lastPunch = nil, nil, nil, 0, 0

	local function cleanup()
		if IsValid(hands) then hands:Remove() end
		if IsValid(vm) then vm:Remove() end
		vm, hands = nil, nil
	end

	local function ensure()
		if not IsValid(vm) then
			vm = ClientsideModel("models/weapons/c_arms.mdl", RENDERGROUP_OPAQUE)
			if not IsValid(vm) then return end
			vm:SetNoDraw(true)
		end
		local ph = LocalPlayer():GetHands()
		local mdl = IsValid(ph) and ph:GetModel() or "models/weapons/c_arms_citizen.mdl"
		if not IsValid(hands) or hands:GetModel() ~= mdl then
			if IsValid(hands) then hands:Remove() end
			hands = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
			if not IsValid(hands) then return end
			hands:SetNoDraw(true)
			hands:SetParent(vm)
			hands:AddEffects(EF_BONEMERGE)
		end
		if IsValid(ph) then
			hands:SetSkin(ph:GetSkin())
			for i = 0, ph:GetNumBodyGroups() - 1 do hands:SetBodygroup(i, ph:GetBodygroup(i)) end
		end
		return vm, hands
	end

	local function play(name)
		if seqName == name then return end
		seqName, seqStart = name, RealTime()
	end

	hook.Add("HUDPaintBackground", "nyrp.hands.fists", function()
		local ply = LocalPlayer()
		local w = IsValid(ply) and ply:GetActiveWeapon()
		local Cam = NYRP.Camera
		local first = not (Cam and Cam.IsThirdPerson and Cam.IsThirdPerson())
		if not IsValid(w) or w:GetClass() ~= "nyrp_hands" or not ply:Alive() or not first or w:IsGrabbing() then
			if IsValid(vm) then cleanup() end
			seqName = nil
			return
		end
		local raised = w:Raised()
		if not raised and not seqName then return end
		local v, h = ensure()
		if not IsValid(v) or not IsValid(h) then return end
		-- выбор анимации
		if w:GetPunchTime() ~= lastPunch then
			lastPunch = w:GetPunchTime()
			local n = w:GetPunchCount()
			seqName = nil
			play(n % 3 == 0 and "fists_uppercut" or (n % 2 == 0 and "fists_left" or "fists_right"))
		elseif not seqName then
			play("fists_draw")
		end
		local seq = v:LookupSequence(seqName or "fists_idle_01")
		if seq < 0 then return end
		local dur = math.max(v:SequenceDuration(seq), 0.01)
		local t = (RealTime() - seqStart) / dur
		if t >= 1 then
			if not raised then
				if seqName == "fists_holster" then seqName = nil cleanup() return end
				play("fists_holster")
			elseif seqName ~= "fists_idle_01" then
				play("fists_idle_01")
			end
			seq = v:LookupSequence(seqName)
			if seq < 0 then return end
			dur = math.max(v:SequenceDuration(seq), 0.01)
			t = (RealTime() - seqStart) / dur
		end
		if v:GetSequence() ~= seq then v:ResetSequence(seq) end
		v:SetPlaybackRate(0)
		v:SetCycle(seqName == "fists_idle_01" and t % 1 or math.Clamp(t, 0, 0.999))
		local eye, view = EyePos(), EyeAngles()
		v:SetPos(eye)
		v:SetAngles(view)
		v:InvalidateBoneCache()
		v:SetupBones()
		h:InvalidateBoneCache()
		h:SetupBones()
		cam.Start3D(eye, view, VM_FOV, nil, nil, nil, nil, 1, 300)
		render.ClearDepth()
		v:DrawModel()
		h:DrawModel()
		cam.End3D()
	end)
end

-- ---------------------------------------------------------------- линия --
if CLIENT then
	local UI = NYRP.UI

	local function nameOf(ent)
		if ent:IsRagdoll() then
			local owner = ent:GetNW2Entity("nyrp.koOwner")
			if IsValid(owner) and NYRP.Cond and NYRP.Cond.KO(owner) then return "Человек без сознания", "Тело" end
			if ent:GetNW2Bool("nyrp.corpse") then return "Тело", "Без признаков жизни" end
			return "Тело", "Тяжёлое"
		end
		if ent:GetClass() == "nyrp_item" and ent.GetDef then
			local def = ent:GetDef()
			if def then return def.name, "Предмет" end
		end
		return language.GetPhrase(ent.PrintName or "") ~= "" and ent.PrintName or "Предмет", "Объект"
	end

	-- Как ixTooltip: панель справа от центра, к объекту — линия 1px и квадрат 4×4, «вырастает» за 0.3 с.
	hook.Add("HUDPaint", "nyrp.hands.line", function()
		local ply = LocalPlayer()
		local w = IsValid(ply) and ply:GetActiveWeapon()
		if not IsValid(w) or w:GetClass() ~= "nyrp_hands" or not w.IsGrabbing or not w:IsGrabbing() then return end
		if not GetConVar("nyrp_drag_hint"):GetBool() then return end -- выключено в настройках
		local ent = w:GetGrabEnt()
		local point = w:GrabPoint()
		if not point then return end
		local frac = UI.Ease(math.Clamp((CurTime() - w:GetGrabTime()) / 0.3, 0, 1))
		local title, sub = nameOf(ent)
		local isBody = ent:IsRagdoll()
		local hint = isBody and "ПКМ — отпустить" or "ПКМ — отпустить · ЛКМ — бросить · R+мышь — повернуть"
		local fontT, fontS = NYRP.Font("bold", 16), NYRP.Font("regular", 12)
		local pw = math.max(UI.TextSize(title, fontT), UI.TextSize(hint, fontS)) + UI.S(28)
		local ph = UI.S(62)
		local px, py = ScrW() / 2 + UI.S(90), ScrH() / 2 - ph / 2
		local sc = point:ToScreen()
		local ax, ay = math.Clamp(sc.x, 0, ScrW()), math.Clamp(sc.y, 0, ScrH())
		-- линия от левого края панели к точке захвата
		surface.SetDrawColor(255, 255, 255, 200)
		local lx, ly = px + (ax - px) * frac, py + (ay - py) * frac
		surface.DrawLine(px, py, lx, ly)
		surface.DrawRect(lx - 2, ly - 2, 4, 4)
		-- панель (раскрывается по ширине вместе с линией)
		render.SetScissorRect(px, py, px + pw * frac, py + ph, true)
		surface.SetDrawColor(10, 11, 16, 220)
		surface.DrawRect(px, py, pw, ph)
		surface.SetDrawColor(255, 255, 255, 230)
		surface.DrawRect(px, py, pw, UI.S(24))
		draw.SimpleText(title, fontT, px + UI.S(10), py + UI.S(12), Color(14, 14, 18), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(sub, fontS, px + pw - UI.S(10), py + UI.S(12), Color(60, 62, 70), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		draw.SimpleText(hint, fontS, px + UI.S(10), py + UI.S(43), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		render.SetScissorRect(0, 0, 0, 0, false)
	end)
end
