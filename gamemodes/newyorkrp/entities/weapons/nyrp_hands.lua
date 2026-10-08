--[[
	Пустые руки — оружие по умолчанию. Ничего не делает, вьюмодель не рисуется (руки видно у тела).
]]

AddCSLuaFile()

SWEP.PrintName = "Руки"
SWEP.Author = "NYRP"
SWEP.Slot = 0
SWEP.SlotPos = 1
SWEP.Spawnable = false
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = true
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.HoldType = "normal"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end
function SWEP:DrawWorldModel() end
function SWEP:ShouldDrawViewModel() return false end
