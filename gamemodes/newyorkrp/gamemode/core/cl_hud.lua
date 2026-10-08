--[[
	HUD: отключение стандартного HUD, виньетка, водяной знак «Работа в процессе».
	NYRP.HUDHidden() — true в меню/интро: тогда скрыто всё, кроме CHudGMod.
]]

local UI = NYRP.UI

function NYRP.HUDHidden()
	return NYRP.State ~= "playing"
end

function GM:HUDShouldDraw(name)
	if name ~= "CHudGMod" and NYRP.HUDHidden() then return false end
	if NYRP.Config.HiddenHUD[name] then return false end
	return self.BaseClass.HUDShouldDraw(self, name)
end

function GM:HUDDrawTargetID()
	if NYRP.Config.DrawTargetID then
		return self.BaseClass.HUDDrawTargetID(self)
	end
end

function GM:HUDDrawPickupHistory() end
function GM:HUDItemPickedUp() end
function GM:HUDAmmoPickedUp() end
function GM:HUDWeaponPickedUp() end
function GM:DrawDeathNotice() end
function GM:AddDeathNotice() end

-- Виньетка поверх мира (до остального HUD). Не отключается.
hook.Add("HUDPaintBackground", "nyrp.vignette", function()
	UI.Vignette(-UI.S(20), -UI.S(20), ScrW() + UI.S(40), ScrH() + UI.S(40), 225)
end)

-- Водяной знак в правом нижнем углу.
hook.Add("HUDPaint", "nyrp.watermark", function()
	if NYRP.HUDHidden() then return end -- водяной знак не отключается
	local w = UI.S(300)
	local h = w * 120 / 600
	surface.SetMaterial(UI.Mat("nyrp/watermark.png"))
	surface.SetDrawColor(255, 255, 255, 170)
	surface.DrawTexturedRect(ScrW() - w - UI.S(14), ScrH() - h - UI.S(14), w, h)
end)
