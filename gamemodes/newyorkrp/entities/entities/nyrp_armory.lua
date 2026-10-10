--[[
	Шкаф снаряжения службы: выдаёт сотруднику ROLE.Items (или ROLE.ArmoryItems) раз в 10 минут.
	Ставит админ: /armory <роль> или спавн-меню.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Шкаф снаряжения"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPIcon = "box"
ENT.DefaultRole = ""
ENT.Model = "models/props_c17/lockers001a.mdl"
ENT.Cooldown = 600

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Role")
end

function ENT:GetInteractText()
	local R = NYRP.Roles.List[self:GetRole()]
	return "Снаряжение: " .. (R and R.Name or "служба")
end

if SERVER then
	function ENT:Initialize()
		if self:GetRole() == "" then self:SetRole(self.DefaultRole) end
		self:SetModel(self.Model)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		local ph = self:GetPhysicsObject()
		if IsValid(ph) then ph:EnableMotion(false) end
	end

	function ENT:SpawnFunction(ply, tr)
		if not tr.Hit then return end
		local e = NYRP.Factions.Spawn("nyrp_armory", self.DefaultRole, tr.HitPos, Angle(0, ply:EyeAngles().y + 180, 0))
		if IsValid(e) then e:SetPos(tr.HitPos - Vector(0, 0, e:OBBMins().z)) end
		timer.Simple(0, NYRP.Factions.Save)
		return e
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or (ply.nyrpArmUse or 0) > CurTime() then return end
		ply.nyrpArmUse = CurTime() + 1
		local R = NYRP.Roles.List[self:GetRole()]
		if not R or ply:GetNW2String("nyrp.role", "") ~= self:GetRole() then
			NYRP.Notify(ply, "Шкаф заперт: только " .. (R and R.Name or self:GetRole()), "warning", 3)
			self:EmitSound("doors/default_locked.wav", 55)
			return
		end
		local left = (ply.nyrpArmoryAt or 0) - CurTime()
		if left > 0 then
			NYRP.Notify(ply, "Снаряжение уже выдано. Снова — через " .. math.ceil(left / 60) .. " мин", "info", 3)
			return
		end
		NYRP.Action(ply, "Беру снаряжение...", 3, function()
			if not IsValid(self) or self:GetPos():Distance(ply:GetPos()) > 150 then return end
			ply.nyrpArmoryAt = CurTime() + self.Cooldown
			local n = 0
			for _, id in ipairs(R.ArmoryItems or R.Items or {}) do
				if NYRP.Items.Get(id) then
					if NYRP.Inv.Add(ply, id, 1) <= 0 then NYRP.Inv.DropNew(ply, id, 1) end
					n = n + 1
				end
			end
			self:EmitSound("doors/door_metal_thin_open1.wav", 60)
			NYRP.Notify(ply, "Получено снаряжение: " .. n .. " шт.", "success")
		end, "box")
	end

	function ENT:OnRemove()
		if not NYRP.Factions.Loading then timer.Simple(0, function() NYRP.Factions.Save() end) end
	end
end
