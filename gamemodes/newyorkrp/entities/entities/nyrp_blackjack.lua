--[[
	Стол для блэкджека: E — сесть за стол (до 4 игроков, у каждого своя игра против дилера).
	На столешнице — зелёное сукно, над столом — вывеска со ставками и занятыми местами.
	Ставит админ: /blackjack или спавн-меню (сохраняется для карты). Логика — modules/leisure/sv_blackjack.lua.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Стол для блэкджека"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.NYRPInteract = true
ENT.NYRPIcon = "coins"

function ENT:GetInteractText()
	return "Блэкджек: сесть за стол"
end

if SERVER then
	function ENT:SpawnFunction(ply, tr, class)
		if not tr.Hit then return end
		local ent = ents.Create(class)
		ent:SetPos(tr.HitPos + tr.HitNormal * 2)
		ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
		ent:Spawn()
		ent:SetPos(tr.HitPos - Vector(0, 0, ent:OBBMins().z))   -- ножками на пол
		timer.Simple(0, function() if NYRP.Leisure and NYRP.Leisure.SavePlaced then NYRP.Leisure.SavePlaced() end end)
		return ent
	end

	function ENT:Initialize()
		self:SetModel("models/props_c17/FurnitureTable001a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or not NYRP.HasCharacter(ply) or not ply:Alive() then return end
		local BJ = NYRP.Leisure and NYRP.Leisure.BJ
		if BJ and BJ.Use then BJ.Use(self, ply) end
	end
else
	local GOLD = Color(247, 198, 0)
	local FELT = Color(18, 92, 52, 245)

	function ENT:Draw()
		self:DrawModel()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local dist = ply:GetPos():DistToSqr(self:GetPos())
		if dist > 800 * 800 then return end
		local mins, maxs = self:OBBMins(), self:OBBMaxs()
		local sc = 0.1
		-- сукно на столешнице
		local top = self:LocalToWorld(Vector((mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2, maxs.z + 0.3))
		local ang = self:GetAngles()
		local w = (maxs.x - mins.x - 4) / sc
		local h = (maxs.y - mins.y - 4) / sc
		cam.Start3D2D(top, ang, sc)
			draw.RoundedBox(24, -w / 2, -h / 2, w, h, FELT)
			surface.SetDrawColor(GOLD.r, GOLD.g, GOLD.b, 160)
			surface.DrawOutlinedRect(-w / 2 + 14, -h / 2 + 14, w - 28, h - 28, 3)
			draw.SimpleText("BLACKJACK PAYS 3 TO 2", NYRP.FontRaw("title", 34), 0, -14, Color(GOLD.r, GOLD.g, GOLD.b, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText("Дилер добирает до 17", NYRP.FontRaw("semibold", 22), 0, 22, Color(255, 255, 255, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		cam.End3D2D()
		-- вывеска над столом, повёрнута к игроку
		if dist > 600 * 600 then return end
		local sign = self:LocalToWorld(Vector(0, 0, maxs.z + 34))
		local yaw = (ply:GetPos() - sign):Angle().y
		local BJ = NYRP.Leisure and NYRP.Leisure.BJ
		local seats = BJ and BJ.Seats or 4
		cam.Start3D2D(sign, Angle(0, yaw + 90, 90), 0.08)
			local bh = 104 + seats * 30
			draw.RoundedBox(16, -170, -60, 340, bh, Color(12, 14, 22, 230))
			surface.SetDrawColor(GOLD.r, GOLD.g, GOLD.b, 200)
			surface.DrawRect(-170, -60, 340, 4)
			draw.SimpleText("БЛЭКДЖЕК", NYRP.FontRaw("title", 40), 0, -30, GOLD, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			local minB = BJ and BJ.MinBet or 5
			local maxB = BJ and BJ.MaxBet or 500
			draw.SimpleText("Ставки " .. NYRP.Money.Format(minB) .. " – " .. NYRP.Money.Format(maxB), NYRP.FontRaw("semibold", 22), 0, 6, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			for i = 1, seats do
				local st = self:GetNW2String("nyrp.bj.s" .. i, "")
				local y = 22 + i * 30
				draw.SimpleText("Место " .. i, NYRP.FontRaw("medium", 20), -150, y, Color(160, 165, 180), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText(st ~= "" and st or "свободно", NYRP.FontRaw("semibold", 20), 150, y, st ~= "" and GOLD or Color(110, 200, 130), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
		cam.End3D2D()
	end
end
