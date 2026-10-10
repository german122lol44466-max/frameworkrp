--[[
	Огнетушитель (FDNY). Держать ЛКМ — струя: гасит очаги пожара (nyrp_fire) и горящие предметы.
	Заряд расходуется; заправка — E у пожарного гидранта с огнетушителем в руках.
]]

AddCSLuaFile()

SWEP.Base = "nyrp_handheld"
SWEP.PrintName = "Огнетушитель"
SWEP.Instructions = "Держать ЛКМ — тушить. Заправка — у гидранта (E)"
SWEP.Slot = 0
SWEP.SlotPos = 8
SWEP.ViewModel = "models/nyrp/city/v_extinguisher.mdl"
SWEP.WorldModel = "models/nyrp/city/extinguisher.mdl"
SWEP.HoldType = "slam"
SWEP.WMOffset = { pos = Vector(0, 0, -18.6), ang = Angle(0, 90, 0) }
SWEP.Primary.Automatic = true

local RANGE = 260

function SWEP:SetupDataTables()
	self:NetworkVar("Float", 0, "Charge")
	self:NetworkVar("Bool", 0, "Spraying")
	if SERVER then self:SetCharge(100) end
end

function SWEP:PrimaryAttack() end

function SWEP:OnThink()
	local ply = self:GetOwner()
	if not IsValid(ply) then return end
	if SERVER then
		local want = ply:KeyDown(IN_ATTACK) and not self.HolsterAt and self:GetCharge() > 0
		if want ~= self:GetSpraying() then
			self:SetSpraying(want)
			if want then
				self:PlaySeq("use")
				self.Snd = self.Snd or CreateSound(ply, "ambient/gas/steam_loop1.wav")
				self.Snd:PlayEx(0.7, 120)
			elseif self.Snd then
				self.Snd:Stop()
				if self:GetCharge() <= 0 then NYRP.Notify(ply, "Огнетушитель пуст — заправьте у гидранта", "warning") end
			end
		end
		if want and (self.nextTick or 0) < CurTime() then
			self.nextTick = CurTime() + 0.1
			self:SetCharge(math.max(0, self:GetCharge() - 0.7))
			NYRP.Factions.Douse(ply, ply:EyePos(), ply:GetAimVector(), RANGE, 2.5)
		end
	end
end

function SWEP:OnHolster()
	if SERVER then
		self:SetSpraying(false)
		if self.Snd then self.Snd:Stop() end
	end
end

function SWEP:OnRemove()
	if self.Snd then self.Snd:Stop() end
end

if CLIENT then
	-- струя: белое облако из сопла по направлению взгляда (видно всем)
	hook.Add("Think", "nyrp.extinguisher", function()
		for _, w in ipairs(ents.FindByClass("nyrp_extinguisher")) do
			local o = w:GetOwner()
			if IsValid(o) and w:GetSpraying() and o:GetActiveWeapon() == w then
				w.Emitter = w.Emitter or ParticleEmitter(o:EyePos())
				if (w.nextPart or 0) < CurTime() then
					w.nextPart = CurTime() + 0.03
					local dir = o:GetAimVector()
					local from = o:EyePos() + dir * 20 + o:GetRight() * 6 - Vector(0, 0, 10)
					local p = w.Emitter:Add("particle/particle_smokegrenade", from)
					if p then
						p:SetVelocity(dir * math.Rand(500, 650) + VectorRand() * 30)
						p:SetAirResistance(120)
						p:SetDieTime(math.Rand(0.8, 1.3))
						p:SetStartAlpha(160)
						p:SetEndAlpha(0)
						p:SetStartSize(4)
						p:SetEndSize(math.Rand(40, 60))
						p:SetColor(235, 238, 245)
						p:SetRoll(math.Rand(0, 360))
					end
				end
			elseif w.Emitter then
				w.Emitter:Finish()
				w.Emitter = nil
			end
		end
	end)

	function SWEP:DrawHUD()
		local c = self:GetCharge()
		local w, h = ScrW(), ScrH()
		local bw = NYRP.UI.S(220)
		local x, y = w / 2 - bw / 2, h - NYRP.UI.S(110)
		NYRP.UI.RoundedRect(NYRP.UI.S(6), x, y, bw, NYRP.UI.S(10), Color(10, 12, 20, 200))
		NYRP.UI.RoundedRect(NYRP.UI.S(6), x, y, bw * c / 100, NYRP.UI.S(10), c > 20 and Color(230, 235, 245) or Color(230, 70, 60))
		draw.SimpleText("Огнетушитель: " .. math.floor(c) .. "%", NYRP.Font("medium", 13), w / 2, y - NYRP.UI.S(6), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	end
end
