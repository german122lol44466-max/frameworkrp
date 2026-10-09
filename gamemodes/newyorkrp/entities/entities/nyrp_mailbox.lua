--[[
	Стена почтовых ящиков. E — открыть свой ящик: там ключи от арендованной квартиры (или квартиры,
	где вы жилец). Ставит админ: спавн-меню (New-York Roleplay) или /mailbox, глядя на стену; удалить — /mailboxremove.
	Логика — modules/doors/sv_mailbox.lua.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Почтовые ящики"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.NYRPInteract = true
ENT.NYRPIcon = "mailbox"

function ENT:GetInteractText() return "Открыть почтовый ящик" end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/nyrp/props/mailbox.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		if not IsValid(self:GetPhysicsObject()) then
			local mn, mx = self:GetModelBounds()
			self:PhysicsInitBox(mn, mx)
		end
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
	end

	function ENT:SpawnFunction(ply, tr)
		if not tr.Hit then return end
		local e = NYRP.Doors.SpawnMailbox(tr.HitPos + tr.HitNormal * 1, Angle(0, ply:EyeAngles().y + 180, 0))
		timer.Simple(0, function() NYRP.Doors.SaveMailboxes() end)
		return e
	end

	function ENT:Use(ply)
		if IsValid(ply) and ply:IsPlayer() then NYRP.Doors.OpenMailbox(ply, self) end
	end

	function ENT:OnRemove()
		if not NYRP.Doors.MailLoading then timer.Simple(0, function() NYRP.Doors.SaveMailboxes() end) end
	end
end
