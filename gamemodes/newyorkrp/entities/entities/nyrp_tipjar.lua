--[[
	Шляпа для чаевых уличного музыканта (ставится предметом «Шляпа для чаевых», ПКМ «Поставить»).
	E прохожего — окно «Дать чаевые»; E владельца — забрать шляпу вместе с деньгами.
	Над шляпой — надпись с собранной суммой. Логика — modules/street_fun/sv_tipjar.lua.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Шляпа для чаевых"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPIcon = "music"

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Amount")
	self:NetworkVar("Entity", 0, "JarOwner")
end

function ENT:GetInteractText()
	if self:GetJarOwner() == LocalPlayer() then return "Забрать шляпу (" .. NYRP.Money.Format(self:GetAmount()) .. ")" end
	return "Дать чаевые"
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/props_junk/garbage_metalcan001a.mdl")
		self:SetModelScale(1.6, 0)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:SetMass(5) phys:Wake() end
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or not NYRP.HasCharacter(ply) or not ply:Alive() then return end
		local SF = NYRP.StreetFun
		if SF and SF.TipJarUse then SF.TipJarUse(self, ply) end
	end
else
	function ENT:Draw()
		self:DrawModel()
	end

	hook.Add("PostDrawTranslucentRenderables", "nyrp.tipjar", function(depth, sky)
		if depth or sky then return end
		local eye = EyePos()
		for _, e in ipairs(ents.FindByClass("nyrp_tipjar")) do
			local pos = e:GetPos() + Vector(0, 0, 22)
			if pos:DistToSqr(eye) < 500 * 500 then
				cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.06)
				local UI = NYRP.UI
				local amt = NYRP.Money.Format(e:GetAmount())
				UI.RoundedRect(16, -150, -46, 300, 92, Color(10, 12, 18, 200))
				UI.DrawIcon("music", -110, -14, 40, UI.Col.accent)
				draw.SimpleText("НА МУЗЫКУ", NYRP.FontRaw("title", 30), -80, -14, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText("Собрано: " .. amt, NYRP.FontRaw("semibold", 24), 0, 24, UI.Col.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				cam.End3D2D()
			end
		end
	end)
end
