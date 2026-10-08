--[[
	Руки — выдаются всем. Вьюмодель не рисуется (руки видно у тела).
	Перенос как в ix_hands (Helix): ПКМ по предмету, телу или любому незакреплённому объекту — взять,
	ещё раз ПКМ — отпустить. Объект держится перед вами (тело — ниже, волочится);
	ЛКМ — бросить предмет, R + мышь — повернуть.
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
end

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
	self.heldAngle = Angle()
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
	if not IsValid(phys) or not phys:IsMoveable() or not phys:IsMotionEnabled() then return false end
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

function SWEP:PrimaryAttack()
	if CLIENT or not self:IsGrabbing() then return end
	self:Drop(true)
	self:SetNextPrimaryFire(CurTime() + 0.5)
	self:SetNextSecondaryFire(CurTime() + 0.5)
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
	local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 84, filter = { self, ply } })
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
