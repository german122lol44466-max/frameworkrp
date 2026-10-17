--[[
	Улика на месте происшествия (NYPD, занятия на дежурстве). Появляется вместе с вызовом 911
	«Подозрительная активность». Полицейский на дежурстве: E — осмотр 4 с, отчёт и премия.
	Логика — modules/duty_tasks/sv_duty_tasks.lua (NYRP.DutyTasks.EvidenceUse). Исчезает через 10 минут.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Улика"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPIcon = "eye"

local MODELS = {
	"models/props_c17/briefcase001a.mdl",
	"models/props_c17/suitcase001a.mdl",
	"models/props_junk/garbage_bag001a.mdl",
	"models/props_junk/shoe001a.mdl",
}

function ENT:GetInteractText() return "Осмотреть место происшествия" end

-- подсказка только у полиции
function ENT:NYRPCanInteract(ply) return IsValid(ply) and ply:GetNW2String("nyrp.role", "") == "police" end

if SERVER then
	function ENT:Initialize()
		local mdl = MODELS[math.random(#MODELS)]
		if not util.IsValidModel(mdl) then mdl = "models/props_junk/cardboard_box004a.mdl" end
		self:SetModel(mdl)
		self:PhysicsInit(SOLID_VPHYSICS)
		if not IsValid(self:GetPhysicsObject()) then self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs()) end
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		self:SetUseType(SIMPLE_USE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		-- положить на пол
		local tr = util.TraceLine({ start = self:GetPos() + Vector(0, 0, 20), endpos = self:GetPos() - Vector(0, 0, 120), filter = self, mask = MASK_SOLID_BRUSHONLY })
		if tr.Hit then self:SetPos(tr.HitPos - Vector(0, 0, self:OBBMins().z)) end
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() then return end
		if (ply.nyrpEvidenceUse or 0) > CurTime() then return end
		ply.nyrpEvidenceUse = CurTime() + 0.6
		local D = NYRP.DutyTasks
		if D and D.EvidenceUse then D.EvidenceUse(ply, self) end
	end

	function ENT:OnRemove()
		local D = NYRP.DutyTasks
		if D and D.IncidentGone then D.IncidentGone(self) end
	end
else
	function ENT:Draw()
		self:DrawModel()
	end
end
