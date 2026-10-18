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
C.InviteTime = 30                                              -- секунд на ответ на приглашение
C.CallsignMin, C.CallsignMax = 2, 20                           -- длина позывного

-- Движение (юниты/с) и стамина
C.WalkSpeed = 115
C.RunSpeed = 220
C.SlowWalkSpeed = 70           -- Alt
C.CrouchFactor = 0.4           -- доля скорости в приседе
C.JumpPower = 175
C.StaminaMax = 100
C.StaminaSprint = 13           -- расход в секунду при беге (≈7.5 с бега с полной)
C.StaminaJump = 14             -- расход на прыжок
C.StaminaRegen = 11            -- восстановление в секунду
C.StaminaRegenDelay = 1.4      -- пауза перед восстановлением
C.StaminaRecover = 30          -- после полного истощения бег снова доступен с этого значения

-- Зрение
C.NVGBattery = 240             -- секунд работы ПНВ / тепловизора от полного заряда
C.NVGRecharge = 0.5            -- заряд восстанавливается в 2 раза медленнее, когда прибор выключен

-- Голос
C.VoiceRange = 900             -- слышимость голоса в игре
C.ChatRange = 700              -- дальность обычного чата («рядом»)
C.PhraseCooldown = 2.5
