--[[
	Контейнер: тип задаётся NW2String "nyrp.ctype" (см. modules/containers/sh_containers.lua).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Контейнер"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.NYRPInteract = true
ENT.NYRPIcon = "box"

function ENT:GetInteractText()
	return "Открыть: " .. NYRP.Containers.TypeOf(self).name
end

if SERVER then
	function ENT:SpawnFunction(ply, tr, class)
		if not tr.Hit then return end
		return NYRP.Containers.Spawn("crate", tr.HitPos + tr.HitNormal * 4, Angle(0, ply:EyeAngles().y + 180, 0))
	end

	function ENT:Initialize()
		local def = NYRP.Containers.TypeOf(self)
		self:SetModel(def.model)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		self.Slots = self.Slots or {}
		self.Viewers = {}
	end

	function ENT:Use(ply)
		if IsValid(ply) and ply:IsPlayer() then NYRP.Containers.BeginOpen(ply, self) end
	end
end
