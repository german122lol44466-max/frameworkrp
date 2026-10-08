--[[
	Руки — выдаются всем. Вьюмодель не рисуется (руки видно у тела).
	ЛКМ (удерживать) по предмету, телу или любому незакреплённому объекту — тащить его:
	от руки к точке захвата тянется линия, объект следует за взглядом. Отпустить — отпустить ЛКМ.
	Колесо мыши при захвате — ближе/дальше. Слишком тяжёлое не поднять.
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
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local REACH = 95          -- откуда можно схватить
local MAX_MASS = 120      -- тяжелее (кроме тел) — не поднять
local BREAK = 150         -- дальше — выскальзывает

function SWEP:SetupDataTables()
	self:NetworkVar("Entity", 0, "GrabEnt")
	self:NetworkVar("Int", 0, "GrabBone")
	self:NetworkVar("Vector", 0, "GrabLocal")
	self:NetworkVar("Float", 0, "GrabDist")
end

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:IsGrabbing() return IsValid(self:GetGrabEnt()) end

-- Точка захвата в мире (по физ. кости и локальному смещению).
function SWEP:GrabPoint()
	local ent = self:GetGrabEnt()
	if not IsValid(ent) then return end
	local bone = self:GetGrabBone()
	if ent:GetClass() == "prop_ragdoll" and bone >= 0 then
		if SERVER then
			-- на сервере — по физическому объекту кости (матрицы костей там не обновляются)
			local phys = ent:GetPhysicsObjectNum(bone)
			if IsValid(phys) then return LocalToWorld(self:GetGrabLocal(), Angle(), phys:GetPos(), phys:GetAngles()) end
			return
		end
		local b = ent:TranslatePhysBoneToBone(bone)
		local m = b and ent:GetBoneMatrix(b)
		if m then return LocalToWorld(self:GetGrabLocal(), Angle(), m:GetTranslation(), m:GetAngles()) end
	end
	return ent:LocalToWorld(self:GetGrabLocal())
end

local function canGrab(ent, phys)
	if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsVehicle() then return false end
	if not IsValid(phys) or not phys:IsMoveable() or not phys:IsMotionEnabled() then return false end
	if ent:GetClass() == "nyrp_container" or ent:GetClass() == "nyrp_vending" then return false end
	return true
end

function SWEP:PrimaryAttack()
	if CLIENT or self:IsGrabbing() then return end
	local ply = self:GetOwner()
	if not IsValid(ply) or (NYRP.Cond and NYRP.Cond.KO(ply)) then return end
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * REACH, filter = ply })
	local ent = tr.Entity
	local physBone = tr.PhysicsBone or 0
	local phys = IsValid(ent) and ent:GetPhysicsObjectNum(physBone)
	if not canGrab(ent, phys) then return end
	local isBody = ent:GetClass() == "prop_ragdoll"
	if not isBody and phys:GetMass() > MAX_MASS then
		if (self.nextHeavy or 0) < CurTime() then
			self.nextHeavy = CurTime() + 2
			NYRP.Notify(ply, "Слишком тяжело", "warning", 2)
		end
		return
	end
	local localPos
	if isBody then
		localPos = WorldToLocal(tr.HitPos, Angle(), phys:GetPos(), phys:GetAngles())
	else
		localPos = ent:WorldToLocal(tr.HitPos)
	end
	self:SetGrabEnt(ent)
	self:SetGrabBone(isBody and physBone or -1)
	self:SetGrabLocal(localPos)
	self:SetGrabDist(math.Clamp(tr.HitPos:Distance(ply:EyePos()), 40, REACH))
	ply:SetNW2Bool("nyrp.dragging", isBody)
	ent:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 55, 110)
end

function SWEP:Release()
	local ply = self:GetOwner()
	if IsValid(ply) then ply:SetNW2Bool("nyrp.dragging", false) end
	self:SetGrabEnt(NULL)
end

function SWEP:SecondaryAttack() end
function SWEP:Holster() if SERVER then self:Release() end return true end
function SWEP:OnRemove() if SERVER then self:Release() end end
function SWEP:OnDrop() if SERVER then self:Release() end end

function SWEP:Think()
	if CLIENT or not self:IsGrabbing() then return end
	local ply = self:GetOwner()
	local ent = self:GetGrabEnt()
	if not IsValid(ply) or not ply:Alive() or not ply:KeyDown(IN_ATTACK) or (NYRP.Cond and NYRP.Cond.KO(ply)) then
		self:Release()
		return
	end
	local point = self:GrabPoint()
	if not point or point:Distance(ply:EyePos()) > BREAK then self:Release() return end
	local isBody = ent:GetClass() == "prop_ragdoll"
	local phys = ent:GetPhysicsObjectNum(isBody and self:GetGrabBone() or 0)
	if not IsValid(phys) then self:Release() return end

	-- точка, куда тянем: перед глазами на сохранённой дистанции (тела — ниже, у земли)
	local aim = ply:GetAimVector()
	local target = ply:EyePos() + aim * self:GetGrabDist()
	if isBody then target.z = math.min(target.z, ply:GetPos().z + 40) end
	local delta = target - point
	local vel = delta * (isBody and 8 or 12)
	local maxV = isBody and 260 or 420
	if vel:Length() > maxV then vel = vel:GetNormalized() * maxV end
	-- гасим собственную скорость и вращение, чтобы не болталось
	phys:SetVelocity(phys:GetVelocity() * 0.5 + vel)
	if not isBody then phys:AddAngleVelocity(-phys:GetAngleVelocity() * 0.25) end
	phys:Wake()
end

-- Колесо мыши — ближе/дальше, пока держим.
hook.Add("PlayerBindPress", "nyrp.hands.dist", function(ply, bind, pressed)
	local w = ply:GetActiveWeapon()
	if not IsValid(w) or w:GetClass() ~= "nyrp_hands" or not w:IsGrabbing() then return end
	if bind == "invnext" or bind == "invprev" then
		net.Start("nyrp.hands.dist")
		net.WriteBool(bind == "invnext")
		net.SendToServer()
		return true
	end
end)

if SERVER then
	util.AddNetworkString("nyrp.hands.dist")
	net.Receive("nyrp.hands.dist", function(_, ply)
		local w = ply:GetActiveWeapon()
		if not IsValid(w) or w:GetClass() ~= "nyrp_hands" or not w:IsGrabbing() then return end
		w:SetGrabDist(math.Clamp(w:GetGrabDist() + (net.ReadBool() and -8 or 8), 35, REACH + 20))
	end)
end

function SWEP:DrawWorldModel() end
function SWEP:ShouldDrawViewModel() return false end

if CLIENT then
	-- Линия от руки к точке захвата — видна всем.
	local mat = Material("cable/rope")
	local white = Material("sprites/light_glow02_add")
	hook.Add("PostDrawTranslucentRenderables", "nyrp.hands.line", function(depth, sky)
		if sky then return end
		for _, ply in ipairs(player.GetAll()) do
			local w = IsValid(ply) and ply:GetActiveWeapon()
			if IsValid(w) and w:GetClass() == "nyrp_hands" and w.IsGrabbing and w:IsGrabbing() then
				local point = w:GrabPoint()
				local hb = ply:LookupBone("ValveBiped.Bip01_R_Hand")
				local hand = hb and ply:GetBonePosition(hb)
				if ply == LocalPlayer() and not NYRP.Camera.IsThirdPerson() then
					-- от первого лица — из-под камеры справа, чтобы линию было видно
					hand = EyePos() + EyeAngles():Right() * 6 - EyeAngles():Up() * 7 + EyeAngles():Forward() * 10
				end
				if point and hand then
					render.SetMaterial(mat)
					local segs = 10
					local sag = math.min(point:Distance(hand) * 0.08, 6)
					render.StartBeam(segs + 1)
					for i = 0, segs do
						local t = i / segs
						local p = LerpVector(t, hand, point) - Vector(0, 0, math.sin(t * math.pi) * sag)
						render.AddBeam(p, 0.8, t * 3, Color(255, 255, 255))
					end
					render.EndBeam()
					render.SetMaterial(white)
					render.DrawSprite(point, 5, 5, Color(247, 198, 0, 200))
				end
			end
		end
	end)
end
