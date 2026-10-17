--[[
	Пострадавший на улице (EMS, занятия на дежурстве). Лежит на земле (модель горожанина, поза лёжа).
	Появляется вместе с вызовом 911 «Человеку плохо». Медик на дежурстве: E — меню
	«Осмотреть / Перевязать / Дефибриллятор». Логика — modules/duty_tasks/sv_duty_tasks.lua.
	Если никто не пришёл — исчезает через 10 минут (вызов и метки снимаются).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Пострадавший"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPIcon = "medkit"
ENT.RenderGroup = RENDERGROUP_OPAQUE

local POSES = { "zombie_slump_idle_02", "zombie_slump_idle_01", "sit_zen" }

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Diagnosis")
	self:NetworkVar("Bool", 0, "Female")
end

function ENT:GetInteractText()
	local d = self:GetDiagnosis()
	return d ~= "" and ("Пострадавший: " .. d) or "Помочь пострадавшему"
end

-- подсказка только у медиков
function ENT:NYRPCanInteract(ply) return IsValid(ply) and ply:GetNW2String("nyrp.role", "") == "medic" end

function ENT:ApplyPose()
	for _, name in ipairs(POSES) do
		local seq = self:LookupSequence(name)
		if seq and seq >= 0 then
			if self:GetSequence() ~= seq then self:ResetSequence(seq) end
			return
		end
	end
end

if SERVER then
	function ENT:Initialize()
		local female = math.random() < 0.35
		local mdl = female and ("models/player/group01/female_0" .. math.random(1, 6) .. ".mdl")
			or ("models/player/group01/male_0" .. math.random(1, 9) .. ".mdl")
		if not util.IsValidModel(mdl) then mdl = "models/player/group01/male_02.mdl" end
		self:SetModel(mdl)
		self:SetFemale(female)
		self:SetDiagnosis("")
		local mins, maxs = Vector(-34, -34, 0), Vector(34, 34, 16)
		self:PhysicsInitBox(mins, maxs)
		self:SetCollisionBounds(mins, maxs)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_BBOX)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		self:SetUseType(SIMPLE_USE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		local tr = util.TraceLine({ start = self:GetPos() + Vector(0, 0, 20), endpos = self:GetPos() - Vector(0, 0, 120), filter = self, mask = MASK_SOLID_BRUSHONLY })
		if tr.Hit then self:SetPos(tr.HitPos) end
		self:ApplyPose()
		self.nyrpNeed = math.random() < 0.5 and "bandage" or "defib"
		self.nextMoan = CurTime() + math.random(5, 15)
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() then return end
		if (ply.nyrpPatientUse or 0) > CurTime() then return end
		ply.nyrpPatientUse = CurTime() + 0.6
		local D = NYRP.DutyTasks
		if D and D.PatientUse then D.PatientUse(ply, self) end
	end

	function ENT:Think()
		if CurTime() > (self.nextMoan or 0) then
			self.nextMoan = CurTime() + math.random(12, 25)
			local who = self:GetFemale() and "female01" or "male01"
			self:EmitSound("vo/npc/" .. who .. "/moan0" .. math.random(1, 5) .. ".wav", 60)
		end
		self:NextThink(CurTime() + 1)
		return true
	end

	function ENT:OnRemove()
		local D = NYRP.DutyTasks
		if D and D.IncidentGone then D.IncidentGone(self) end
	end
else
	function ENT:Initialize()
		self:SetRenderBounds(Vector(-50, -50, 0), Vector(50, 50, 40))
	end

	function ENT:Draw()
		self:ApplyPose()
		self:FrameAdvance()
		self:DrawModel()
	end
end
