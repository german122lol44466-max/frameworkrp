--[[
	Рация в руке (слот «Рация»). ЛКМ — настроить частоту (100.0–300.0) и включить/выключить,
	держать ПКМ — поднести ко рту и говорить голосом в эфир. Чат: /r текст.
]]

AddCSLuaFile()

SWEP.Base = "nyrp_handheld"
SWEP.PrintName = "Рация"
SWEP.Instructions = "ЛКМ — частота, держать ПКМ — говорить в эфир, /r — написать"
SWEP.Slot = 4
SWEP.SlotPos = 2
SWEP.ViewModel = "models/nyrp/props/v_radio.mdl"
SWEP.WorldModel = "models/nyrp/props/w_radio.mdl"
SWEP.HoldType = "slam"
SWEP.WMOffset = { pos = Vector(0.6, 0, -2.7), ang = Angle(-8, 0, 0) }    -- низ рации у мизинца
SWEP.NextSeq = { draw = "idle", use = "idle_use", unuse = "idle" }

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 0.4)
	if CLIENT and IsFirstTimePredicted() and NYRP.Radio and NYRP.Radio.OpenUI then NYRP.Radio.OpenUI() end
end

function SWEP:SecondaryAttack() end

function SWEP:OnThink()
	if CLIENT then return end
	local ply = self:GetOwner()
	if not IsValid(ply) then return end
	local want = ply:KeyDown(IN_ATTACK2) and not self.HolsterAt and NYRP.Radio.Freq(ply) > 0
	if want ~= (self.Tx or false) then
		self.Tx = want
		NYRP.Radio.SetTx(ply, want)
		self:PlaySeq(want and "use" or "unuse")
		ply:EmitSound(want and "nyrp/fx/radio_on.wav" or "nyrp/fx/radio_off.wav", 45)
		if want then ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_IN_CHAT, true) end
	end
	if want and not ply:KeyDown(IN_ATTACK2) then self.Tx = false end
end

function SWEP:OnHolster()
	if SERVER and self.Tx then
		self.Tx = false
		local ply = self:GetOwner()
		if IsValid(ply) then NYRP.Radio.SetTx(ply, false) end
	end
end

function SWEP:OnRemove()
	if SERVER and self.Tx and IsValid(self:GetOwner()) then NYRP.Radio.SetTx(self:GetOwner(), false) end
end
