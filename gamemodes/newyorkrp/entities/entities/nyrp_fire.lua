--[[
	Очаг пожара (FDNY). Сила 0–100: растёт со временем, при большой силе огонь перекидывается рядом,
	обжигает всех вокруг. Тушится огнетушителем (NYRP.Factions.Douse); погас — премия пожарному.
	Начать: /fire (админ), случайные пожары при пожарных на смене, спавн-меню.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Пожар"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

local MAX_FIRES = 10

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "Power")
end

function ENT:Radius() return 40 + self:GetPower() * 1.1 end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
		self:SetNoDraw(false)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_NONE)
		self:DrawShadow(false)
		if self:GetPower() <= 0 then self:SetPower(50) end
		self.Sound = CreateSound(self, "ambient/fire/fire_med_loop1.wav")
		self.Sound:PlayEx(0.8, 100)
		self.nextSpread = CurTime() + 25
	end

	function ENT:SpawnFunction(ply, tr)
		if not tr.Hit then return end
		return NYRP.Factions.StartFire(tr.HitPos + tr.HitNormal * 2, 60)
	end

	function ENT:Think()
		local pw = self:GetPower()
		self:SetPower(math.min(100, pw + 0.6))
		local r = self:Radius()
		for _, e in ipairs(ents.FindInSphere(self:GetPos(), r)) do
			if (e:IsPlayer() and e:Alive()) or e:IsNPC() then
				local d = DamageInfo()
				d:SetDamage(math.max(1, pw / 25))
				d:SetDamageType(DMG_BURN)
				d:SetAttacker(self)
				d:SetInflictor(self)
				e:TakeDamageInfo(d)
			end
		end
		-- перекидывается рядом
		if pw >= 85 and CurTime() > self.nextSpread then
			self.nextSpread = CurTime() + math.random(25, 45)
			if #ents.FindByClass("nyrp_fire") < MAX_FIRES then
				local dir = VectorRand()
				dir.z = 0
				local tr = util.TraceLine({ start = self:GetPos() + Vector(0, 0, 20), endpos = self:GetPos() + Vector(0, 0, 20) + dir:GetNormalized() * math.random(90, 160), mask = MASK_SOLID_BRUSHONLY })
				local down = util.TraceLine({ start = tr.HitPos - dir:GetNormalized() * 10, endpos = tr.HitPos - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
				if down.Hit then NYRP.Factions.StartFire(down.HitPos + Vector(0, 0, 2), 30, true) end
			end
		end
		if self.Sound then self.Sound:ChangeVolume(0.4 + pw / 170, 0.5) end
		self:NextThink(CurTime() + 1)
		return true
	end

	function ENT:OnRemove()
		if self.Sound then self.Sound:Stop() end
	end
else
	local flames = { "particles/flamelet1", "particles/flamelet2", "particles/flamelet3", "particles/flamelet4", "particles/flamelet5" }

	function ENT:Initialize()
		self.Emitter = ParticleEmitter(self:GetPos())
		self.nextPart = 0
	end

	function ENT:Draw() end
	function ENT:DrawTranslucent() end

	-- частицы — из Think (иначе огонь «замирает», когда очаг вне поля зрения)
	function ENT:Emit()
		local pw = self:GetPower()
		if pw <= 0 or not self.Emitter then return end
		if CurTime() < self.nextPart then return end
		self.nextPart = CurTime() + 0.05
		local pos, r = self:GetPos(), self:Radius() * 0.6
		for i = 1, math.ceil(pw / 30) do
			local off = VectorRand() * r
			off.z = 0
			local p = self.Emitter:Add(flames[math.random(#flames)], pos + off)
			if p then
				p:SetVelocity(Vector(math.Rand(-8, 8), math.Rand(-8, 8), math.Rand(40, 90) * (0.5 + pw / 100)))
				p:SetDieTime(math.Rand(0.5, 1.1))
				p:SetStartAlpha(230)
				p:SetEndAlpha(0)
				p:SetStartSize(math.Rand(14, 24) * (0.4 + pw / 90))
				p:SetEndSize(4)
				p:SetRoll(math.Rand(0, 360))
				p:SetRollDelta(math.Rand(-2, 2))
			end
		end
		if math.random() < 0.4 then
			local s = self.Emitter:Add("particle/particle_smokegrenade", pos + Vector(0, 0, 40 + pw * 0.4))
			if s then
				s:SetVelocity(Vector(math.Rand(-15, 15), math.Rand(-15, 15), math.Rand(40, 70)))
				s:SetDieTime(math.Rand(3, 5))
				s:SetStartAlpha(110)
				s:SetEndAlpha(0)
				s:SetStartSize(30)
				s:SetEndSize(120 + pw)
				s:SetColor(40, 40, 40)
				s:SetRoll(math.Rand(0, 360))
			end
		end
	end

	function ENT:Think()
		local pw = self:GetPower()
		local dl = DynamicLight(self:EntIndex())
		if dl and pw > 0 then
			dl.pos = self:GetPos() + Vector(0, 0, 30)
			dl.r, dl.g, dl.b = 255, 120, 30
			dl.brightness = 2 + pw / 50
			dl.decay = 1000
			dl.size = 200 + pw * 3
			dl.dietime = CurTime() + 0.2
		end
		if self.Emitter then
			self.Emitter:SetPos(self:GetPos())
			self:Emit()
		end
	end

	function ENT:OnRemove()
		if self.Emitter then self.Emitter:Finish() self.Emitter = nil end
	end
end
