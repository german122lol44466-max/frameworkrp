--[[
	Отключение стандартного HUD Garry's Mod / Half-Life 2.
	Свой HUD будет рисоваться в отдельном модуле через HUDPaint.
]]

function GM:HUDShouldDraw(name)
	if NYRP.Config.HiddenHUD[name] then
		return false
	end

	return self.BaseClass.HUDShouldDraw(self, name)
end

-- Ник/здоровье игрока при наведении прицела.
function GM:HUDDrawTargetID()
	if NYRP.Config.DrawTargetID then
		return self.BaseClass.HUDDrawTargetID(self)
	end
end

-- Список подобранных предметов/патронов справа.
function GM:HUDDrawPickupHistory() end
function GM:HUDItemPickedUp() end
function GM:HUDAmmoPickedUp() end
function GM:HUDWeaponPickedUp() end

-- Килфид в правом верхнем углу.
function GM:DrawDeathNotice() end
function GM:AddDeathNotice() end
