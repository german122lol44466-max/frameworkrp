--[[
	Бумбокс (ставится предметом «Бумбокс», ПКМ «Поставить»). Играет интернет-радио объёмным звуком:
	каждый клиент рядом сам проигрывает поток (modules/leisure/cl_boombox.lua). E владельца — меню
	(станция, громкость, выключить, забрать), E остальных — что играет и личные настройки звука.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Бумбокс"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPIcon = "music"

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "BoxStation")
	self:NetworkVar("Int", 1, "BoxVolume")
	self:NetworkVar("Entity", 0, "BoxOwner")
end

function ENT:GetInteractText()
	if self:GetBoxOwner() == LocalPlayer() then return "Бумбокс: станция, громкость, забрать" end
	return "Бумбокс: что играет"
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/props_lab/citizenradio.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:SetMass(15) phys:Wake() end
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or not NYRP.HasCharacter(ply) or not ply:Alive() then return end
		local BB = NYRP.Leisure and NYRP.Leisure.Boombox
		if BB and BB.Use then BB.Use(self, ply) end
	end
else
	function ENT:Draw()
		self:DrawModel()
		local st = self:GetBoxStation()
		if st <= 0 then return end
		local ply = LocalPlayer()
		if not IsValid(ply) or ply:GetPos():DistToSqr(self:GetPos()) > 350 * 350 then return end
		local BB = NYRP.Leisure and NYRP.Leisure.Boombox
		local s = BB and BB.Stations and BB.Stations[st]
		if not s then return end
		local UI = NYRP.UI
		local pos = self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 10 + math.sin(RealTime() * 2) * 1.5)
		cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.06)
			UI.RoundedRect(16, -150, -34, 300, 68, Color(10, 12, 18, 200))
			UI.DrawIcon("music", -116, 0, 36, s.color)
			draw.SimpleText(s.name, NYRP.FontRaw("title", 28), -88, -10, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(s.genre, NYRP.FontRaw("semibold", 20), -88, 16, Color(200, 200, 215), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		cam.End3D2D()
	end

	function ENT:OnRemove()
		local BB = NYRP.Leisure and NYRP.Leisure.Boombox
		if BB and BB.StopEnt then BB.StopEnt(self) end
	end
end
