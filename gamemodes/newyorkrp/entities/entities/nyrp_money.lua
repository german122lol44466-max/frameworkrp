--[[
	Наличные на земле (выброшены через меню C). E — подобрать.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Деньги"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPIcon = "cash"

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Amount")
end

function ENT:GetInteractText()
	return "Подобрать " .. NYRP.Money.Format(self:GetAmount())
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/nyrp/props/w_money.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		if not IsValid(self:GetPhysicsObject()) then
			local mn, mx = self:GetModelBounds()
			self:PhysicsInitBox(mn, mx)
		end
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:SetMass(1) phys:Wake() end
		-- через 30 минут деньги «подбирает» город
		timer.Simple(1800, function() if IsValid(self) then self:Remove() end end)
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or not NYRP.HasCharacter(ply) or not ply:Alive() then return end
		if self.Taken then return end
		self.Taken = true
		local n = self:GetAmount()
		NYRP.Money.Add(ply, n)
		ply:EmitSound("nyrp/fx/money.wav", 55)
		ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_PLACE, true)
		NYRP.Notify(ply, "Подобрано: " .. NYRP.Money.Format(n), "success", 3)
		self:Remove()
	end
end
