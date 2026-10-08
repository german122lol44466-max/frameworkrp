--[[
	Смартфон в руке. Вьюмодель v_phone (руки c_arms по бонмерджу): draw → idle,
	ЛКМ — поднести к лицу и открыть интерфейс (open → idle_open), ПКМ — закрыть (close → idle),
	при смене оружия — holster (телефон опускается и уходит из кадра), только потом переключение.
	Интерфейс — modules/phone/cl_phone*.lua.
]]

AddCSLuaFile()

SWEP.PrintName = "Телефон"
SWEP.Author = "NYRP"
SWEP.Instructions = "ЛКМ — открыть, ПКМ — закрыть"
SWEP.Slot = 4
SWEP.SlotPos = 1
SWEP.Spawnable = false
SWEP.ViewModel = "models/nyrp/phone/v_phone.mdl"
SWEP.WorldModel = "models/nyrp/phone/w_phone.mdl"
SWEP.ViewModelFOV = 62
SWEP.UseHands = true
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.HoldType = "slam"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local HOLSTER_TIME = 0.5

function SWEP:SetupDataTables()
	self:NetworkVar("Bool", 0, "Raised")
end

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:PlaySeq(name, rate)
	local owner = self:GetOwner()
	if not IsValid(owner) then return end
	local vm = owner:GetViewModel()
	if not IsValid(vm) then return end
	local seq = vm:LookupSequence(name)
	if seq < 0 then return end
	vm:SendViewModelMatchingSequence(seq)
	vm:SetPlaybackRate(rate or 1)
	self.SeqName = name
	self.SeqEnd = CurTime() + vm:SequenceDuration(seq) / (rate or 1)
end

function SWEP:Deploy()
	self.HolsterAt, self.HolsterTo, self.HolsterDone = nil, nil, nil
	self:SetRaised(false)
	self:PlaySeq("draw")
	self:SetNextPrimaryFire(CurTime() + 0.4)
	if SERVER then self:GetOwner():EmitSound("nyrp/fx/cloth_off.wav", 45, 130, 0.5) end
	return true
end

function SWEP:Raise(up)
	if self:GetRaised() == up then return end
	self:SetRaised(up)
	self:PlaySeq(up and "open" or "close")
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 0.3)
	if self.HolsterAt then return end
	-- без SIM-карты телефон не активирован — экран не открывается
	if SERVER and not (NYRP.Phone and NYRP.Phone.Number(self:GetOwner())) then return end
	if CLIENT and IsFirstTimePredicted() and NYRP.Phone and NYRP.Phone.OpenUI then
		if not NYRP.Phone.OpenUI() then return end
	end
	self:Raise(true)
end

function SWEP:SecondaryAttack()
	self:SetNextSecondaryFire(CurTime() + 0.3)
	if CLIENT and IsFirstTimePredicted() and NYRP.Phone and NYRP.Phone.CloseUI then NYRP.Phone.CloseUI(true) end
	self:Raise(false)
end

function SWEP:Reload() end

function SWEP:Think()
	-- переходы в зацикленные позы
	if self.SeqEnd and CurTime() >= self.SeqEnd then
		self.SeqEnd = nil
		if self.SeqName == "draw" or self.SeqName == "close" then self:PlaySeq("idle")
		elseif self.SeqName == "open" then self:PlaySeq("idle_open") end
	end
	if self.HolsterAt and CurTime() >= self.HolsterAt then
		local to = self.HolsterTo
		self.HolsterAt, self.HolsterTo = nil, nil
		self.HolsterDone = true
		if IsValid(to) then
			if SERVER then self:GetOwner():SelectWeapon(to:GetClass()) else input.SelectWeapon(to) end
		end
	end
end

function SWEP:Holster(wep)
	if self.HolsterDone or not IsValid(wep) or wep == self then
		self.HolsterDone = nil
		if CLIENT and NYRP.Phone and NYRP.Phone.CloseUI then NYRP.Phone.CloseUI(true) end
		return true
	end
	if not self.HolsterAt then
		self.HolsterTo = wep
		self.HolsterAt = CurTime() + HOLSTER_TIME
		self:SetRaised(false)
		self:PlaySeq("holster")
		if CLIENT and NYRP.Phone and NYRP.Phone.CloseUI then NYRP.Phone.CloseUI(true) end
	else
		self.HolsterTo = wep
	end
	return false
end

function SWEP:OnRemove()
	if CLIENT and NYRP.Phone and NYRP.Phone.CloseUI and IsValid(self:GetOwner()) and self:GetOwner() == LocalPlayer() then
		NYRP.Phone.CloseUI(true)
	end
end

if SERVER then
	concommand.Add("nyrp_phone_raise", function(ply, _, args)
		local w = IsValid(ply) and ply:GetActiveWeapon()
		if IsValid(w) and w:GetClass() == "nyrp_phone" and not w.HolsterAt then w:Raise(args[1] == "1") end
	end)
end

if CLIENT then
	-- от третьего лица телефон лежит в правой ладони
	function SWEP:DrawWorldModel()
		local owner = self:GetOwner()
		if not IsValid(owner) then self:DrawModel() return end
		local bone = owner:LookupBone("ValveBiped.Bip01_R_Hand")
		if not bone then return end
		local m = owner:GetBoneMatrix(bone)
		if not m then return end
		local pos, ang = m:GetTranslation(), m:GetAngles()
		pos = pos + ang:Forward() * 3.4 + ang:Right() * 1.6 + ang:Up() * -0.6
		ang:RotateAroundAxis(ang:Forward(), 90)
		ang:RotateAroundAxis(ang:Up(), 180)
		self:SetRenderOrigin(pos)
		self:SetRenderAngles(ang)
		self:DrawModel()
		self:SetRenderOrigin()
		self:SetRenderAngles()
	end

	function SWEP:DrawHUD() end
end
