--[[
	Точка начала смены профессии (модель — JOB.StationModel, иначе табличка «РАБОТА»).
	E: своя профессия — начать/закончить смену; чужая — подсказка. Ставит админ: /jobstation <профессия>.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Точка работы"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPIcon = "briefcase"

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "JobId")
end

function ENT:GetInteractText()
	local j = NYRP.Jobs.List[self:GetJobId()]
	if not j then return "Точка работы" end
	local ply = LocalPlayer and LocalPlayer()
	if IsValid(ply) and ply:GetNW2String("nyrp.job") == j.id then
		return ply:GetNW2Bool("nyrp.onShift") and ("Закончить смену: " .. j.Name) or ("Начать смену: " .. j.Name)
	end
	return j.Name .. " — устроиться в центре занятости"
end

if SERVER then
	function ENT:Initialize()
		local j = NYRP.Jobs.List[self:GetJobId()]
		local m = j and j.StationModel
		if not m or not util.IsValidModel(m) then m = "models/nyrp/city/job_sign.mdl" end
		self:SetModel(m)
		self:PhysicsInit(SOLID_VPHYSICS)
		if not IsValid(self:GetPhysicsObject()) then self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs()) end
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		local ph = self:GetPhysicsObject()
		if IsValid(ph) then ph:EnableMotion(false) end
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or (ply.nyrpStationUse or 0) > CurTime() then return end
		ply.nyrpStationUse = CurTime() + 1
		local j = NYRP.Jobs.List[self:GetJobId()]
		if not j then return end
		if ply:GetNW2String("nyrp.job") ~= j.id then
			NYRP.Notify(ply, "Это точка профессии «" .. j.Name .. "». Устроиться можно в центре занятости.", "info", 5)
			return
		end
		NYRP.Jobs.ToggleShift(ply, true)
	end

	function ENT:OnRemove()
		if not NYRP.Jobs.StLoading then timer.Simple(0, function() NYRP.Jobs.SaveStations() end) end
	end
else
	-- над точкой — значок и название профессии
	function ENT:Draw()
		self:DrawModel()
		local j = NYRP.Jobs.List[self:GetJobId()]
		if not j or EyePos():DistToSqr(self:GetPos()) > 700 * 700 then return end
		local pos = self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 18 + math.sin(CurTime() * 2) * 2)
		local ang = EyeAngles()
		ang:RotateAroundAxis(ang:Up(), -90)
		ang:RotateAroundAxis(ang:Forward(), 90)
		cam.Start3D2D(pos, ang, 0.08)
		local UI = NYRP.UI
		draw.RoundedBox(24, -170, -50, 340, 100, Color(10, 12, 20, 220))
		UI.DrawIcon(j.Icon, -120, 0, 64, j.Color)
		draw.SimpleText(j.Name, NYRP.Font("bold", 30), -70, -16, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("точка работы", NYRP.Font("medium", 20), -70, 20, j.Color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		cam.End3D2D()
	end
end
