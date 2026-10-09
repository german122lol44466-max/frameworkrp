--[[
	Точка задания профессии (мусор, щиток, течь, пассажир, касса). Видна и доступна только своему работнику:
	у него подсвечена сквозь стены. E — действие (логика — modules/jobs/sv_jobs.lua, ENT.OnUsed).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Задание"
ENT.Spawnable = false
ENT.NYRPInteract = true
ENT.NYRPIcon = "hand"
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Kind")
	self:NetworkVar("String", 1, "Effect")
	self:NetworkVar("Entity", 0, "OwnerPly")
end

local TEXT = { collect = "Собрать", repair = "Починить", passenger = "Посадить пассажира", register = "Вскрыть кассу" }
function ENT:GetInteractText() return TEXT[self:GetKind()] or "Взаимодействовать" end

-- взаимодействие только у своего работника
function ENT:NYRPCanInteract(ply) return self:GetOwnerPly() == ply end

if SERVER then
	function ENT:Initialize()
		self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs())
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_BBOX)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		self:SetUseType(SIMPLE_USE)
		-- поставить на пол
		local tr = util.TraceLine({ start = self:GetPos() + Vector(0, 0, 20), endpos = self:GetPos() - Vector(0, 0, 80), filter = self })
		if tr.Hit then self:SetPos(tr.HitPos - Vector(0, 0, self:OBBMins().z)) end
		if self:GetKind() == "passenger" then
			local seq = self:LookupSequence("idle_subtle")
			if seq < 0 then seq = self:LookupSequence("Idle01") end
			if seq >= 0 then self:ResetSequence(seq) end
		end
		timer.Simple(1800, function() if IsValid(self) then self:Remove() end end)
	end

	function ENT:Use(ply)
		if not IsValid(ply) or ply ~= self:GetOwnerPly() then return end
		if self.OnUsed then self:OnUsed(ply) end
	end

	function ENT:Think()
		if not IsValid(self:GetOwnerPly()) then self:Remove() return end
		self:NextThink(CurTime() + 1)
		return true
	end
else
	function ENT:Draw()
		-- чужим работникам точки не видны (мусор/пассажир — только для себя)
		if self:GetOwnerPly() ~= LocalPlayer() and self:GetKind() ~= "register" then return end
		if self:GetKind() == "passenger" then self:FrameAdvance() end
		self:DrawModel()
	end

	function ENT:Think()
		local fx = self:GetEffect()
		if fx == "" or (self.NextFx or 0) > CurTime() or self:GetOwnerPly() ~= LocalPlayer() then return end
		self.NextFx = CurTime() + (fx == "sparks" and math.Rand(0.4, 1.4) or 0.15)
		local ed = EffectData()
		ed:SetOrigin(self:WorldSpaceCenter() + VectorRand() * 4)
		ed:SetNormal(Vector(0, 0, 1))
		if fx == "sparks" then
			ed:SetMagnitude(2) ed:SetScale(1) ed:SetRadius(3)
			util.Effect("ElectricSpark", ed)
			if math.random() < 0.3 then self:EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav", 55) end
		else
			util.Effect("watersplash", ed)
		end
	end

	hook.Add("PreDrawHalos", "nyrp.jobspot", function()
		local mine = {}
		for _, e in ipairs(ents.FindByClass("nyrp_jobspot")) do
			if e:GetOwnerPly() == LocalPlayer() then mine[#mine + 1] = e end
		end
		if #mine > 0 then halo.Add(mine, Color(247, 198, 0), 2, 2, 1, true, true) end
	end)
end
