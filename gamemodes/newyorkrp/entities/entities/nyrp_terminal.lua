--[[
	Служебный компьютер (NYPD / EMS / FDNY): устав, вызовы 911, кто на смене, розыск/пострадавшие/пожары.
	Открывают только сотрудники своей службы. Ставит админ: /terminal <роль> или спавн-меню.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Служебный компьютер"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPIcon = "keyboard"
ENT.DefaultRole = ""
ENT.Model = "models/nyrp/city/terminal.mdl"

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Role")
end

function ENT:GetInteractText()
	local R = NYRP.Roles.List[self:GetRole()]
	return "Компьютер " .. (R and R.Name or "службы")
end

if SERVER then
	function ENT:Initialize()
		if self:GetRole() == "" then self:SetRole(self.DefaultRole) end
		self:SetModel(util.IsValidModel(self.Model) and self.Model or "models/props_lab/monitor01a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		if not IsValid(self:GetPhysicsObject()) then self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs()) end
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		local ph = self:GetPhysicsObject()
		if IsValid(ph) then ph:EnableMotion(false) end
	end

	function ENT:SpawnFunction(ply, tr)
		if not tr.Hit then return end
		local e = NYRP.Factions.Spawn("nyrp_terminal", self.DefaultRole, tr.HitPos, Angle(0, ply:EyeAngles().y + 180, 0))
		timer.Simple(0, NYRP.Factions.Save)
		return e
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or (ply.nyrpTermUse or 0) > CurTime() then return end
		ply.nyrpTermUse = CurTime() + 1
		if ply:GetNW2String("nyrp.role", "") ~= self:GetRole() then
			local R = NYRP.Roles.List[self:GetRole()]
			NYRP.Notify(ply, "Доступ только для сотрудников: " .. (R and R.Name or self:GetRole()), "warning", 3)
			self:EmitSound("buttons/button10.wav", 50)
			return
		end
		self:EmitSound("nyrp/fx/type.wav", 50)
		NYRP.Factions.SendTerminal(ply, self)
	end

	function ENT:OnRemove()
		if not NYRP.Factions.Loading then timer.Simple(0, function() NYRP.Factions.Save() end) end
	end
else
	-- на экране — эмблема службы
	function ENT:Draw()
		self:DrawModel()
		if EyePos():DistToSqr(self:GetPos()) > 500 * 500 then return end
		local R = NYRP.Roles.List[self:GetRole()]
		local pos = self:LocalToWorld(Vector(-3.2, 0, 40.5))
		local ang = self:LocalToWorldAngles(Angle(0, 90, 90))
		cam.Start3D2D(pos, ang, 0.05)
		local col = R and R.Color or Color(247, 198, 0)
		surface.SetDrawColor(8, 12, 22, 255)
		surface.DrawRect(-190, -120, 380, 240)
		if R and R.Icon then
			surface.SetMaterial(NYRP.UI.Mat("nyrp/status/" .. R.Icon .. ".png"))
			surface.SetDrawColor(col)
			surface.DrawTexturedRect(-50, -95, 100, 100)
		end
		draw.SimpleText(R and R.Name or "—", NYRP.Font("bold", 30), 0, 40, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText("нажмите E", NYRP.Font("medium", 20), 0, 80, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		cam.End3D2D()
	end
end
