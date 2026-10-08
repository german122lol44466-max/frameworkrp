--[[
	Предмет, лежащий в мире. E — подобрать в сумку.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Предмет"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPIcon = "hand"

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "ItemID")
	self:NetworkVar("Int", 0, "Amount")
end

function ENT:GetDef()
	return NYRP.Items.Get(self:GetItemID())
end

function ENT:GetInteractText()
	local def = self:GetDef()
	if not def then return "Взять" end
	local n = self:GetAmount()
	return "Взять " .. def.name .. (n > 1 and (" ×" .. n) or "")
end

if SERVER then
	function ENT:SetItem(id, n, data)
		self:SetItemID(id)
		self:SetAmount(n or 1)
		self.ItemData = data and table.Copy(data) or nil
		local def = NYRP.Items.Get(id)
		self:SetModel(def and def.model or "models/props_junk/cardboard_box004a.mdl")
	end

	function ENT:Initialize()
		if self:GetModel() == "" or not self:GetModel() then self:SetModel("models/props_junk/cardboard_box004a.mdl") end
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
		if IsValid(phys) then phys:Wake() end
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or not NYRP.HasCharacter(ply) then return end
		if (self.NextUse or 0) > CurTime() then return end
		self.NextUse = CurTime() + 0.4
		local def = self:GetDef()
		if not def then self:Remove() return end
		local n = self:GetAmount()
		if not NYRP.Inv.CanTake(ply, self.ItemData) then return end
		local data = self.ItemData and table.Copy(self.ItemData) or nil
		if data then
			data.nyrpFrom = nil
			if table.IsEmpty(data) then data = nil end -- обычные предметы снова складываются в стопки
		end
		local added = NYRP.Inv.Add(ply, def.id, n, data)
		if added <= 0 then
			NYRP.Notify(ply, "В сумке нет места", "error")
			return
		end
		ply:EmitSound("items/ammo_pickup.wav", 55, 110)
		ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_PLACE, true)
		NYRP.Notify(ply, "Подобрано: " .. def.name .. (added > 1 and (" ×" .. added) or ""), "item", 3)
		if added >= n then self:Remove() else self:SetAmount(n - added) end
	end
else
	function ENT:Draw()
		self:DrawModel()
	end
end
