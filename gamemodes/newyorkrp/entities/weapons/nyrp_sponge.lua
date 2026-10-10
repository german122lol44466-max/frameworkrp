--[[
	Губка с растворителем в руке (предмет «Губка», слот «В руке»).
	ЛКМ по граффити — оттереть (5 с). Уборщикам улиц город платит $10 за каждый рисунок.
	Без губки граффити можно оттереть руками: E по рисунку (10 с).
]]

AddCSLuaFile()

SWEP.Base = "nyrp_handheld"
SWEP.PrintName = "Губка"
SWEP.Category = "New-York Roleplay"
SWEP.Instructions = "ЛКМ по граффити — оттереть"
SWEP.Slot = 4
SWEP.SlotPos = 8
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = "models/props_junk/garbage_milkcarton002a.mdl"
SWEP.HoldType = "slam"
SWEP.NYRPHandheld = false
SWEP.WMOffset = { pos = Vector(1, 0, 0), ang = Angle(0, 0, 0) }

function SWEP:ShouldDrawViewModel() return false end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 1)
	if CLIENT then return end
	local SF = NYRP.StreetFun
	if SF and SF.TryErase then SF.TryErase(self:GetOwner(), true) end
end

function SWEP:SecondaryAttack() end

if CLIENT then
	function SWEP:DrawHUD()
		local UI = NYRP.UI
		if not UI or (NYRP.HUDHidden and NYRP.HUDHidden()) then return end
		draw.SimpleText("ЛКМ по граффити — оттереть", NYRP.Font("semibold", 15), ScrW() - UI.S(40), ScrH() - UI.S(150), UI.Col.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end
