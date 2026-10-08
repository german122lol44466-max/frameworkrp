--[[
	Автомат с газировкой — пример энтити с взаимодействием.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Автомат с газировкой"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.NYRPInteract = true
ENT.NYRPIcon = "pointer"

function ENT:GetInteractText()
	return "Взаимодействовать с: " .. self.PrintName
end

if SERVER then
	function ENT:SpawnFunction(ply, tr, class)
		if not tr.Hit then return end
		local ent = ents.Create(class)
		ent:SetPos(tr.HitPos + tr.HitNormal * 2)
		ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
		ent:Spawn()
		return ent
	end

	function ENT:Initialize()
		self:SetModel("models/props_interiors/VendingMachineSoda01a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or not NYRP.HasCharacter(ply) then return end
		if (self.NextUse or 0) > CurTime() then return end
		self.NextUse = CurTime() + 2
		self:EmitSound("buttons/button4.wav", 65)
		timer.Simple(0.6, function()
			if not IsValid(self) or not IsValid(ply) then return end
			self:EmitSound("physics/metal/soda_can_impact_hard" .. math.random(1, 3) .. ".wav", 65)
			if NYRP.Inv.Add(ply, "soda", 1) > 0 then
				NYRP.Notify(ply, "Автомат выдал банку Liberty Cola", "item", 3)
			else
				NYRP.Notify(ply, "В сумке нет места", "error")
			end
		end)
	end
end
