--[[
	Лотерейный автомат: E — меню (скретч-карта $5, билет NY Lotto $10, текущий джекпот).
	Сверху — светящаяся вывеска «NY LOTTO» с джекпотом. Ставит админ: /lotterymachine или спавн-меню.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Лотерейный автомат"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.NYRPInteract = true
ENT.NYRPIcon = "coins"

function ENT:GetInteractText()
	return "Лотерея: билеты и скретч-карты"
end

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Jackpot")
end

if SERVER then
	function ENT:SpawnFunction(ply, tr, class)
		if not tr.Hit then return end
		local ent = ents.Create(class)
		ent:SetPos(tr.HitPos + tr.HitNormal * 2)
		ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
		ent:Spawn()
		timer.Simple(0, function() if NYRP.Lottery and NYRP.Lottery.SaveMachines then NYRP.Lottery.SaveMachines() end end)
		return ent
	end

	function ENT:Initialize()
		self:SetModel("models/props_interiors/vendingmachinesoda01a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self:SetColor(Color(255, 225, 150))
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		self:Think()
	end

	function ENT:Think()
		local L = NYRP.Lottery
		if L and L.Data then self:SetJackpot(L.Data.jackpot) end
		self:NextThink(CurTime() + 5)
		return true
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or not NYRP.HasCharacter(ply) then return end
		if (ply.nyrpLotteryUse or 0) > CurTime() then return end
		ply.nyrpLotteryUse = CurTime() + 1
		self:EmitSound("buttons/button14.wav", 55)
		if NYRP.Lottery and NYRP.Lottery.SendMenu then NYRP.Lottery.SendMenu(ply, self) end
	end
else
	local GOLD = Color(247, 198, 0)
	function ENT:Draw()
		self:DrawModel()
		local ply = LocalPlayer()
		if not IsValid(ply) or ply:GetPos():DistToSqr(self:GetPos()) > 900 * 900 then return end
		-- вывеска над автоматом, повёрнута к игроку
		local top = self:LocalToWorld(Vector(0, 0, self:OBBMaxs().z + 14))
		local yaw = (ply:GetPos() - top):Angle().y
		local ang = Angle(0, yaw + 90, 90)
		cam.Start3D2D(top, ang, 0.1)
			local pulse = (math.sin(RealTime() * 3) + 1) / 2
			draw.RoundedBox(16, -170, -60, 340, 120, Color(14, 12, 26, 235))
			surface.SetDrawColor(GOLD.r, GOLD.g, GOLD.b, 120 + pulse * 120)
			surface.DrawOutlinedRect(-170, -60, 340, 120, 3)
			draw.SimpleText("NY LOTTO", NYRP.Font("title", 46), 0, -28, GOLD, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText("ДЖЕКПОТ " .. NYRP.Money.Format(self:GetJackpot()), NYRP.Font("bold", 30), 0, 22, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		cam.End3D2D()
	end
end
