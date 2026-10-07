--[[
	Базовая конфигурация фреймворка.
]]

NYRP.Config = NYRP.Config or {}

-- Цвета бренда (используются будущим HUD / меню).
NYRP.Config.Colors = {
	Navy = Color(10, 14, 28),
	Taxi = Color(247, 198, 0),
	White = Color(245, 246, 250),
}

-- Стандартные элементы HUD, которые скрываются.
-- CHudGMod (нужен для HUDPaint) и CHudChat не трогаем.
NYRP.Config.HiddenHUD = {
	CHudHealth = true,
	CHudBattery = true,
	CHudAmmo = true,
	CHudSecondaryAmmo = true,
	CHudCrosshair = true,
	CHudDamageIndicator = true,
	CHudPoisonDamageIndicator = true,
	CHudSuitPower = true,
	CHudSquadStatus = true,
	CHudZoom = true,
	CHudGeiger = true,
	CHudTrain = true,
	CHudQuickInfo = true,
	CHudHistoryResource = true,
	CHudDeathNotice = true,
	CHudHintDisplay = true,
	-- Выбор оружия колесом мыши. Если скрыть — переключение оружия
	-- тоже перестанет работать, пока не будет своего селектора.
	CHudWeaponSelection = false,
}

-- Показывать ник игрока при наведении (стандартный TargetID).
NYRP.Config.DrawTargetID = false
