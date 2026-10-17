--[[
	Аркадный автомат: E — окно с мини-играми «Змейка» и «Реакция» ($1 за игру, только рекорды).
	Над автоматом — светящийся экран с лучшими результатами обеих игр.
	Ставит админ: /arcade или спавн-меню (сохраняется для карты). Логика — modules/leisure/sv_arcade.lua.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Аркадный автомат"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.NYRPInteract = true
ENT.NYRPIcon = "p_game"

function ENT:GetInteractText()
	return "Аркада: сыграть за $1"
end

if SERVER then
	function ENT:SpawnFunction(ply, tr, class)
		if not tr.Hit then return end
		local ent = ents.Create(class)
		ent:SetPos(tr.HitPos + tr.HitNormal * 2)
		ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
		ent:Spawn()
		ent:SetPos(tr.HitPos - Vector(0, 0, ent:OBBMins().z))
		timer.Simple(0, function() if NYRP.Leisure and NYRP.Leisure.SavePlaced then NYRP.Leisure.SavePlaced() end end)
		return ent
	end

	function ENT:Initialize()
		self:SetModel("models/props_interiors/vendingmachinesoda01a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self:SetColor(Color(150, 120, 255))
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		timer.Simple(0.5, function()
			if not IsValid(self) then return end
			local AR = NYRP.Leisure and NYRP.Leisure.Arcade
			if AR and AR.UpdateScreens then AR.UpdateScreens() end
		end)
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or not NYRP.HasCharacter(ply) or not ply:Alive() then return end
		local AR = NYRP.Leisure and NYRP.Leisure.Arcade
		if AR and AR.Use then AR.Use(self, ply) end
	end
else
	local PURPLE = Color(170, 120, 255)
	local CYAN = Color(80, 230, 255)

	function ENT:Draw()
		self:DrawModel()
		local ply = LocalPlayer()
		if not IsValid(ply) or ply:GetPos():DistToSqr(self:GetPos()) > 900 * 900 then return end
		local top = self:LocalToWorld(Vector(0, 0, self:OBBMaxs().z + 16))
		local yaw = (ply:GetPos() - top):Angle().y
		cam.Start3D2D(top, Angle(0, yaw + 90, 90), 0.1)
			local t = RealTime()
			local pulse = (math.sin(t * 3) + 1) / 2
			draw.RoundedBox(16, -190, -80, 380, 170, Color(10, 6, 24, 240))
			-- «сканлайны» экрана
			surface.SetDrawColor(255, 255, 255, 6)
			for y = -76, 86, 6 do surface.DrawRect(-186, y, 372, 2) end
			surface.SetDrawColor(PURPLE.r, PURPLE.g, PURPLE.b, 120 + pulse * 120)
			surface.DrawOutlinedRect(-190, -80, 380, 170, 3)
			draw.SimpleText("АРКАДА", NYRP.FontRaw("title", 44), 0, -50, PURPLE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			local s = self:GetNW2String("nyrp.arc.snake", "")
			local r = self:GetNW2String("nyrp.arc.reaction", "")
			draw.SimpleText("ЗМЕЙКА", NYRP.FontRaw("bold", 20), -170, -6, CYAN, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(s ~= "" and s or "рекорда нет — будьте первым!", NYRP.FontRaw("semibold", 20), -170, 18, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText("РЕАКЦИЯ", NYRP.FontRaw("bold", 20), -170, 46, CYAN, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(r ~= "" and r or "рекорда нет — будьте первым!", NYRP.FontRaw("semibold", 20), -170, 70, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		cam.End3D2D()
	end
end
