--[[
	Конфигурация фреймворка New-York Roleplay.
	Всё, что можно безопасно крутить без правки кода, — здесь.
]]

NYRP.Config = NYRP.Config or {}
local C = NYRP.Config

-- Цвета бренда.
C.Colors = {
	Navy = Color(10, 14, 28),
	Taxi = Color(247, 198, 0),
	Orange = Color(255, 138, 36),
	White = Color(245, 246, 250),
}

-- Стандартные элементы HUD, которые скрываются. CHudGMod (нужен для HUDPaint) не трогаем.
C.HiddenHUD = {
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
	CHudChat = true,              -- свой чат (modules/chat)
	CHudVoiceStatus = true,       -- свои иконки войса (modules/voice)
	CHudVoiceSelfStatus = true,
	-- Выбор оружия колесом мыши. Если скрыть — переключение оружия перестанет работать.
	CHudWeaponSelection = false,
}

-- Движение (единицы Source в секунду).
C.Movement = {
	Walk = 92,           -- обычный шаг
	Run = 225,           -- бег (Shift)
	SlowWalk = 58,       -- медленный шаг (Alt)
	CrouchFactor = 0.45, -- множитель скорости в приседе
	Jump = 195,          -- сила прыжка
	JumpCooldown = 0.5,  -- пауза между прыжками (против распрыжки)
	LandSlowdown = 0.55, -- скорость сразу после приземления (доля), восстанавливается за 0.4 с
	BackwardFactor = 0.7, -- спиной/боком бег медленнее
}

-- Дистанции (единицы Source; 1 метр ≈ 52 единицы).
C.Ranges = {
	Say = 320,
	Whisper = 90,
	Yell = 750,
	LOOC = 320,
	Voice = 650,
	Interact = 95,     -- взаимодействие (E)
	Hint = 260,        -- на каком расстоянии появляются иконки-подсказки
	NameTag = 260,     -- ник над игроком при наведении
}

C.RespawnTime = 30            -- через сколько секунд после смерти персонаж возрождается сам
C.MaxCharacters = 3           -- если на карте не поставлены точки для персонажей
C.CommunityURL = "https://discord.com"
C.ChatLimit = 300             -- максимум символов в сообщении
C.ChatUseRecognition = false  -- true: в IC-чате незнакомцы подписаны «Неизвестный»

-- Голод/жажда: за сколько минут падают со 100 до 0.
C.Needs = { HungerMinutes = 70, ThirstMinutes = 45, StarveDamage = 2 }

-- Размеры сумок (слотов).
C.Bags = {
	waistbag = { name = "Поясная сумка", cols = 4, rows = 3, icon = "briefcase" },
	backpack = { name = "Рюкзак", cols = 5, rows = 4, icon = "backpack" },
}

-- Модели персонажей при создании.
C.Models = {
	male = {
		"models/player/group01/male_01.mdl", "models/player/group01/male_02.mdl", "models/player/group01/male_03.mdl",
		"models/player/group01/male_04.mdl", "models/player/group01/male_05.mdl", "models/player/group01/male_06.mdl",
		"models/player/group01/male_07.mdl", "models/player/group01/male_08.mdl", "models/player/group01/male_09.mdl",
	},
	female = {
		"models/player/group01/female_01.mdl", "models/player/group01/female_02.mdl", "models/player/group01/female_03.mdl",
		"models/player/group01/female_04.mdl", "models/player/group01/female_05.mdl", "models/player/group01/female_06.mdl",
	},
}

-- Навыки при создании персонажа.
C.Skills = {
	{ id = "strength", name = "Сила", icon = "bolt", desc = "Урон в ближнем бою" },
	{ id = "stamina", name = "Выносливость", icon = "run", desc = "+2% к скорости бега за очко" },
	{ id = "agility", name = "Ловкость", icon = "walk", desc = "+3% к силе прыжка за очко" },
	{ id = "intellect", name = "Интеллект", icon = "info", desc = "Дольше помните имена знакомых" },
	{ id = "medicine", name = "Медицина", icon = "medkit", desc = "Точнее пульс, быстрее первая помощь" },
	{ id = "combat", name = "Стрельба", icon = "crosshair", desc = "Меньше отдача и разброс, твёрже рука" },
}
C.SkillPoints = 10
C.SkillMax = 5

C.HeightMin, C.HeightMax = 160, 200   -- рост, см

-- Показывать ник при наведении стандартным TargetID (у нас свой — modules/nametags).
C.DrawTargetID = false

-- Клиентские настройки (сохраняются у игрока).
if CLIENT then
	CreateClientConVar("nyrp_music_volume", "0.25", true, false, "Громкость фоновой музыки", 0, 1)
	CreateClientConVar("nyrp_ui_sounds", "1", true, false, "Звуки интерфейса")
	CreateClientConVar("nyrp_inv_combined", "0", true, false, "Инвентарь на одной странице")
	CreateClientConVar("nyrp_drag_hint", "1", true, false, "Панель-подсказка при перетаскивании предметов и тел")
	CreateClientConVar("nyrp_thirdperson", "0", true, false, "Третье лицо")
	CreateClientConVar("nyrp_tp_dist", "75", true, false, "Третье лицо: дистанция", 30, 160)
	CreateClientConVar("nyrp_tp_right", "18", true, false, "Третье лицо: смещение вправо", -40, 40)
	CreateClientConVar("nyrp_tp_up", "4", true, false, "Третье лицо: высота", -20, 30)
	CreateClientConVar("nyrp_tp_smooth", "10", true, false, "Третье лицо: плавность", 2, 30)
	CreateClientConVar("nyrp_chat_x", "0.0125", true, false, "Чат: X (доля экрана)", 0, 1)
	CreateClientConVar("nyrp_chat_y", "0.58", true, false, "Чат: Y (доля экрана)", 0, 1)
	CreateClientConVar("nyrp_chat_w", "0.32", true, false, "Чат: ширина (доля экрана)", 0.15, 1)
	CreateClientConVar("nyrp_chat_h", "0.36", true, false, "Чат: высота (доля экрана)", 0.15, 1)
	CreateClientConVar("nyrp_bind_inventory", tostring(KEY_O), true, false, "Клавиша: инвентарь")
	CreateClientConVar("nyrp_bind_gestures", tostring(KEY_G), true, false, "Клавиша: меню жестов")
	CreateClientConVar("nyrp_bind_thirdperson", tostring(KEY_F3), true, false, "Клавиша: третье лицо")
	CreateClientConVar("nyrp_bind_tpmenu", tostring(KEY_F4), true, false, "Клавиша: меню третьего лица")
end
