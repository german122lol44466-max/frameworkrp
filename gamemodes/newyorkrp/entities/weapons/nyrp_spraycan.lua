--[[
	Баллончик с краской в руке (предметы «Баллончик с краской», 6 цветов, слот «В руке»).
	ЛКМ по стене — нанести выбранный рисунок (3 с), R — выбрать рисунок (12 вариантов).
	Логика — modules/street_fun (sv_graffiti.lua / cl_graffiti.lua). Краски хватает на 8 рисунков.
]]

AddCSLuaFile()

SWEP.Base = "nyrp_handheld"
SWEP.PrintName = "Баллончик с краской"
SWEP.Category = "New-York Roleplay"
SWEP.Instructions = "ЛКМ по стене — нарисовать, R — выбрать рисунок"
SWEP.Slot = 4
SWEP.SlotPos = 7
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = "models/props_junk/garbage_metalcan002a.mdl"
SWEP.HoldType = "pistol"
SWEP.NYRPHandheld = false
SWEP.WMOffset = { pos = Vector(1, 0, 1), ang = Angle(0, 0, 0) }
SWEP.FPModel = "models/props_junk/garbage_metalcan002a.mdl"

function SWEP:ShouldDrawViewModel() return false end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 1)
	if SERVER or not IsFirstTimePredicted() then return end
	local SF = NYRP.StreetFun
	if not SF or not SF.SelTag then return end
	net.Start("nyrp.graf.spray")
	net.WriteUInt(SF.SelTag, 8)
	net.SendToServer()
end

function SWEP:SecondaryAttack() end

function SWEP:Reload()
	if SERVER or (self.nyrpMenuNext or 0) > RealTime() then return end
	self.nyrpMenuNext = RealTime() + 0.6
	if NYRP.StreetFun and NYRP.StreetFun.OpenTagMenu then NYRP.StreetFun.OpenTagMenu() end
end

if CLIENT then
	-- баллончик в правой руке от первого лица (вьюмодели нет — рисуем модель сами)
	local fp
	function SWEP:DrawFP()
		if NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson() then return end
		if not IsValid(fp) then
			fp = ClientsideModel(self.FPModel, RENDERGROUP_OPAQUE)
			if not IsValid(fp) then return end
			fp:SetNoDraw(true)
		end
		local eye, ang = EyePos(), EyeAngles()
		local owner = self:GetOwner()
		local spraying = IsValid(owner) and owner:GetNW2Float("nyrp.sprayUntil", 0) > CurTime()
		local bob = math.sin(RealTime() * 2) * 0.15 + (spraying and math.sin(RealTime() * 40) * 0.08 or 0)
		local pos = eye + ang:Forward() * (spraying and 15 or 13) + ang:Right() * 6 - ang:Up() * (6 + bob)
		local a = Angle(ang.p, ang.y, ang.r)
		a:RotateAroundAxis(a:Right(), -8)
		fp:SetPos(pos)
		fp:SetAngles(a)
		fp:SetModelScale(0.75)
		cam.Start3D(eye, ang, 62, nil, nil, nil, nil, 1, 300)
		render.ClearDepth()
		fp:DrawModel()
		cam.End3D()
	end
	hook.Add("HUDPaintBackground", "nyrp.spraycan.fp", function()
		local w = LocalPlayer():GetActiveWeapon()
		if IsValid(w) and w:GetClass() == "nyrp_spraycan" and LocalPlayer():Alive() then w:DrawFP() end
	end)

	function SWEP:DrawHUD()
		local UI = NYRP.UI
		local SF = NYRP.StreetFun
		if not UI or not SF or (NYRP.HUDHidden and NYRP.HUDHidden()) then return end
		local inv = NYRP.Inventory and NYRP.Inventory.Data
		local it = inv and inv.equip and inv.equip.tool
		local def = it and NYRP.Items.Get(it.id)
		local uses = it and ((it.data and it.data.uses) or (def and def.uses)) or 0
		local tag = SF.Tags[SF.SelTag]
		local x, y = ScrW() - UI.S(40), ScrH() - UI.S(150)
		draw.SimpleText("Рисунок: «" .. (tag and tag.text or "?") .. "»  ·  краски на " .. uses, NYRP.Font("semibold", 15), x, y, UI.Col.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		draw.SimpleText("ЛКМ — нарисовать на стене · R — выбрать рисунок", NYRP.Font("regular", 13), x, y + UI.S(20), UI.Col.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end
