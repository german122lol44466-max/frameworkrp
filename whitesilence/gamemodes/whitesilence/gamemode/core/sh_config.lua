--[[
	Общие настройки режима. Меняйте здесь, а не в коде модулей.
]]

local C = WS.Config

C.Color = {
	text = Color(232, 236, 242),
	dim = Color(150, 160, 172),
	accent = Color(196, 38, 38),     -- красный Фонда
	frost = Color(170, 205, 235),
}

-- Интро
C.IntroMaxTime = 90          -- сервер размораживает игрока, если клиент так и не сообщил о конце интро

-- Отряд (лобби) и выход в игру
C.SquadSize = 5                                                -- мест в отряде
C.SquadModel = "models/kuma96/winterizedarmor/winterizedarmor_pm.mdl"
C.SquadModelFallback = "models/player/combine_super_soldier.mdl"   -- если аддон с моделью не установлен
C.SquadWeapons = { "tfa_ins2_ak12", "tfa_ins2_usp_match" }       -- TFA INS2 (Workshop); чего нет — не выдаётся
C.MenuWeapon = "tfa_ins2_ak12"                                 -- что держат бойцы в главном меню
C.MenuWeaponFallback = "models/weapons/w_rif_ak47.mdl"
C.InviteTime = 30                                              -- секунд на ответ на приглашение
C.CallsignMin, C.CallsignMax = 2, 20                           -- длина позывного
