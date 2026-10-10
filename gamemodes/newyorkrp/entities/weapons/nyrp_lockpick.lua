--[[
	Отмычки в руке (предмет «Отмычки», слот «В руке»). ЛКМ по запертой двери — мини-игра взлома
	(modules/crime/sv_lockpick.lua и cl_lockpick.lua). Своей вьюмодели нет: в руке от третьего лица — рычажок из HL2.
]]

AddCSLuaFile()

SWEP.Base = "nyrp_handheld"
SWEP.PrintName = "Отмычки"
SWEP.Category = "New-York Roleplay"
SWEP.Instructions = "ЛКМ по запертой двери — взломать"
SWEP.Slot = 4
SWEP.SlotPos = 6
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = "models/props_c17/TrapPropeller_Lever.mdl"
SWEP.HoldType = "slam"
SWEP.NYRPHandheld = false          -- рисовать вьюмодель не нужно (её нет)
SWEP.WMOffset = { pos = Vector(1, 0, -0.5), ang = Angle(0, 0, 90) }

function SWEP:ShouldDrawViewModel() return false end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 1)
	if CLIENT then return end
	local ply = self:GetOwner()
	if not IsValid(ply) or not NYRP.Crime or not NYRP.Crime.StartLockpick then return end
	local tr = ply:GetEyeTrace()
	NYRP.Crime.StartLockpick(ply, tr.Entity)
end

function SWEP:SecondaryAttack() end

if CLIENT then
	function SWEP:DrawHUD()
		local UI = NYRP.UI
		if not UI or (NYRP.HUDHidden and NYRP.HUDHidden()) then return end
		local tr = LocalPlayer():GetEyeTrace()
		local e = tr.Entity
		if IsValid(e) and string.find(e:GetClass(), "door", 1, true) and tr.HitPos:Distance(LocalPlayer():EyePos()) < 100 then
			local service = e:GetNW2String("nyrp.doorRole", "") ~= ""
			local txt = service and "Электронный замок — не взломать" or "ЛКМ — вскрыть замок"
			draw.SimpleText(txt, NYRP.Font("semibold", 16), ScrW() / 2 + 1, ScrH() / 2 + UI.S(42) + 1, Color(0, 0, 0, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(txt, NYRP.Font("semibold", 16), ScrW() / 2, ScrH() / 2 + UI.S(42), service and UI.Col.red or UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end
