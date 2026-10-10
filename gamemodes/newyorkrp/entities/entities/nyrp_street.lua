--[[
	База уличных объектов (гидрант, газетный автомат, ...). Виды и действия — modules/street.
	Наследники: nyrp_street_<вид> (ENT.Kind).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Уличный объект"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPStreet = true
ENT.Kind = ""

function ENT:GetInteractText()
	local t = NYRP.Street.Types[self.Kind]
	return t and t.text or "Использовать"
end

if SERVER then
	function ENT:Initialize()
		local t = NYRP.Street.Types[self.Kind]
		self:SetModel(t and t.model or "models/props_junk/cardboard_box004a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		if not IsValid(self:GetPhysicsObject()) then self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs()) end
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
	end

	function ENT:SpawnFunction(ply, tr)
		if not tr.Hit then return end
		local e = NYRP.Street.Spawn(self.Kind or string.gsub(self.ClassName or "", "^nyrp_street_", ""), tr.HitPos, Angle(0, ply:EyeAngles().y + 180, 0))
		timer.Simple(0, NYRP.Street.Save)
		return e
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or not NYRP.HasCharacter(ply) then return end
		if (ply.nyrpStreetUse or 0) > CurTime() then return end
		ply.nyrpStreetUse = CurTime() + 0.6
		local fn = NYRP.Street.Use[self.Kind]
		if fn then fn(ply, self) end
	end

	function ENT:OnRemove()
		if not NYRP.Street.Loading then timer.Simple(0, function() NYRP.Street.Save() end) end
	end
end
