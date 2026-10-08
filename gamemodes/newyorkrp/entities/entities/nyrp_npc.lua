--[[
	NPC (торговец / собеседник). Данные и логика — gamemode/modules/npc.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "NPC"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.AutomaticFrameAdvance = true
ENT.NYRPInteract = true
ENT.NYRPIcon = "message"

function ENT:GetInteractText()
	return "Поговорить: " .. self:GetNW2String("nyrp.npcName", "NPC")
end

function ENT:ApplySequence()
	local seq = self:LookupSequence(self:GetNW2String("nyrp.npcSeq", "idle_all_01"))
	if seq < 0 then seq = self:LookupSequence("idle_all_01") end
	if seq < 0 then seq = 0 end
	if self:GetSequence() ~= seq then self:ResetSequence(seq) end
	self:SetPlaybackRate(1)
end

function ENT:Think()
	self:ApplySequence()
	self:NextThink(CurTime())
	return true
end

if SERVER then
	function ENT:SpawnFunction(ply, tr)
		if not tr.Hit then return end
		return NYRP.NPC.Spawn(NYRP.NPC.Default("talk"), tr.HitPos, Angle(0, ply:EyeAngles().y + 180, 0))
	end

	function ENT:Initialize()
		self:SetModel(self.NPCData and self.NPCData.model or "models/player/group01/male_07.mdl")
		self:SetSolid(SOLID_BBOX)
		self:SetCollisionBounds(Vector(-14, -14, 0), Vector(14, 14, 72))
		self:SetMoveType(MOVETYPE_NONE)
		self:SetUseType(SIMPLE_USE)
		self:ApplySequence()
	end

	function ENT:Use(ply)
		if IsValid(ply) and ply:IsPlayer() then NYRP.NPC.Talk(ply, self) end
	end
else
	function ENT:Draw()
		self:DrawModel()
	end
end
