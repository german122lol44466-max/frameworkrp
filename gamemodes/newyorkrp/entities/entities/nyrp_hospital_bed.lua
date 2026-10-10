--[[
	Больничная койка: E — лечь (тело ложится на матрас), здоровье восстанавливается,
	рядом с медиком (EMS) — вдвое быстрее и останавливается кровотечение. Встать — Пробел.
	Ставит админ: /bed или спавн-меню.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Больничная койка"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.NYRPInteract = true
ENT.NYRPIcon = "bed"
ENT.Model = "models/nyrp/city/hospital_bed.mdl"

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Role")       -- не используется, для общего сохранения
	self:NetworkVar("Entity", 0, "Patient")
end

function ENT:GetInteractText()
	return IsValid(self:GetPatient()) and "Койка занята" or "Лечь на койку"
end

if SERVER then
	function ENT:Initialize()
		self:SetModel(util.IsValidModel(self.Model) and self.Model or "models/props_c17/furniturebed001a.mdl")
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
		local e = NYRP.Factions.Spawn("nyrp_hospital_bed", "", tr.HitPos, Angle(0, ply:EyeAngles().y + 90, 0))
		timer.Simple(0, NYRP.Factions.Save)
		return e
	end

	-- уложить тело: стоячая поза поворачивается на спину, голова — к подушке (-x модели)
	local function layDown(bed, ply, rag)
		local stand = Angle(0, ply:GetAngles().y, 0)
		local lie = bed:GetAngles()
		lie:RotateAroundAxis(lie:Right(), 90)
		local feet = bed:LocalToWorld(Vector(34, 0, 27))
		for i = 0, rag:GetPhysicsObjectCount() - 1 do
			local ph = rag:GetPhysicsObjectNum(i)
			if IsValid(ph) then
				local lp, la = WorldToLocal(ph:GetPos(), ph:GetAngles(), ply:GetPos(), stand)
				local wp, wa = LocalToWorld(lp, la, feet, lie)
				ph:SetPos(wp)
				ph:SetAngles(wa)
				ph:SetVelocity(vector_origin)
				ph:EnableMotion(false)
			end
		end
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or (ply.nyrpBedUse or 0) > CurTime() then return end
		ply.nyrpBedUse = CurTime() + 1
		local Cond = NYRP.Cond
		if IsValid(self:GetPatient()) then NYRP.Notify(ply, "Койка занята", "info") return end
		if Cond.KO(ply) then return end
		Cond.Fall(ply, true, 3600)
		local rag = ply.nyrpKO and ply.nyrpKO.rag
		if not IsValid(rag) then return end
		layDown(self, ply, rag)
		self:SetPatient(ply)
		ply.nyrpBed = self
		NYRP.Notify(ply, "Вы легли. Здоровье восстанавливается, рядом с медиком — быстрее. Встать — Пробел.", "info", 6)
	end

	function ENT:Think()
		local p = self:GetPatient()
		if IsValid(p) then
			if not p:Alive() or not NYRP.Cond.KO(p) or p.nyrpBed ~= self then
				if IsValid(p) and p.nyrpBed == self then p.nyrpBed = nil end
				self:SetPatient(NULL)
			else
				local medic = false
				for _, o in ipairs(ents.FindInSphere(self:GetPos(), 160)) do
					if o:IsPlayer() and o ~= p and o:Alive() and o:GetNW2String("nyrp.role", "") == "medic" then medic = true end
				end
				p:SetHealth(math.min(p:GetMaxHealth(), p:Health() + (medic and 2 or 1)))
				if medic and p:GetNW2Bool("nyrp.bleeding") then p:SetNW2Bool("nyrp.bleeding", false) end
			end
		end
		self:NextThink(CurTime() + 2)
		return true
	end

	function ENT:OnRemove()
		local p = self:GetPatient()
		if IsValid(p) and p.nyrpBed == self then
			p.nyrpBed = nil
			NYRP.Cond.WakeUp(p)
		end
		if not NYRP.Factions.Loading then timer.Simple(0, function() NYRP.Factions.Save() end) end
	end
end
