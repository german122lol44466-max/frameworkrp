--[[
	Состояние персонажа: выносливость, статусы (голод, жажда, промок, ранен, ушиб, перелом,
	сотрясение...), потеря сознания. Всё хранится в NW2-переменных игрока:
	  nyrp.stamina (0..100), nyrp.exhausted — выдохся (бег недоступен, пока не отдышится)
	  nyrp.wetUntil, nyrp.bruiseUntil, nyrp.fractureUntil, nyrp.concussionUntil — до какого времени
	  nyrp.ko, nyrp.koCritical, nyrp.koStart, nyrp.koUntil, nyrp.koRag — без сознания
]]

NYRP.Cond = NYRP.Cond or {}
local Cond = NYRP.Cond

NYRP.Config.Stamina = {
	Seconds = 10,        -- сколько секунд можно бежать с полной выносливостью (без навыка)
	PerSkill = 0.15,     -- +15% ко времени бега за очко навыка «Выносливость»
	RegenStand = 9,      -- восстановление в секунду, когда стоишь
	RegenWalk = 1.5,     -- ...когда идёшь шагом (отдышаться на ходу почти нельзя)
	Recover = 35,        -- с какого значения снова можно бежать после «выдохся»
	Jump = 6,            -- цена прыжка
	InjuredDrain = 1.35, -- раненый (меньше 50 HP) выдыхается быстрее
}

NYRP.Config.Fall = {
	Safe = 500,          -- скорость приземления без урона (≈ 4 м при sv_gravity 600)
	Fatal = 1050,        -- скорость, при которой урон = 100 (≈ 17 м)
	Curve = 1.35,        -- форма кривой урона
	Fracture = 22,       -- урон, начиная с которого — перелом
	KnockOut = 720,      -- с такой скорости персонаж теряет сознание (≈ 8 м)
	CriticalHP = 25,     -- если после падения HP не больше — критическое состояние
}

NYRP.Config.Unconscious = {
	WakeTime = 5,        -- в стабильном состоянии приходит в себя сам через N секунд
	CriticalTime = 180,  -- в критическом — сколько ждать помощи, потом смерть
	HelpTime = 5,        -- сколько удерживать E, чтобы помочь
	HelpHP = 30,         -- здоровье после помощи
}

function Cond.Stamina(ply) return ply:GetNW2Float("nyrp.stamina", 100) end
function Cond.Exhausted(ply) return ply:GetNW2Bool("nyrp.exhausted", false) end
function Cond.Until(ply, key) return math.max(0, ply:GetNW2Float("nyrp." .. key .. "Until", 0) - CurTime()) end
function Cond.KO(ply) return ply:GetNW2Bool("nyrp.ko", false) end

function Cond.CanSprint(ply)
	return not Cond.Exhausted(ply) and Cond.Until(ply, "fracture") <= 0
end

-- Множитель скорости от травм.
function Cond.SpeedFactor(ply)
	local f = 1
	if Cond.Until(ply, "fracture") > 0 then f = f * 0.62
	elseif Cond.Until(ply, "bruise") > 0 then f = f * 0.85 end
	if ply:Health() < 25 then f = f * 0.85 end
	return f
end

-- Статусы для HUD. level: "info" | "warn" | "danger". value(ply) -> текст справа в подсказке.
local function secs(t)
	t = math.ceil(t)
	return t >= 60 and string.format("%d:%02d", math.floor(t / 60), t % 60) or (t .. " с")
end

Cond.Statuses = {
	{ id = "tired", name = "Нужно передохнуть", icon = "tired", level = "warn",
		desc = "Вы выдохлись: бегать не получится, пока не отдышитесь. Постойте на месте — так восстанавливаетесь быстрее всего.",
		check = function(ply) return Cond.Exhausted(ply) or Cond.Stamina(ply) < 20 end,
		value = function(ply) return "Выносливость " .. math.floor(Cond.Stamina(ply)) .. "%" end },
	{ id = "hunger", name = "Голод", icon = "hunger", level = "warn",
		desc = "Персонаж давно не ел. Когда сытость упадёт до нуля, начнёт терять здоровье.",
		check = function(ply) return ply:GetNW2Float("nyrp.hunger", 100) < 25 end,
		danger = function(ply) return ply:GetNW2Float("nyrp.hunger", 100) <= 0 end,
		value = function(ply) return "Сытость " .. math.floor(ply:GetNW2Float("nyrp.hunger", 100)) .. "%" end },
	{ id = "thirst", name = "Жажда", icon = "thirst", level = "warn",
		desc = "Хочется пить. Вы быстрее выдыхаетесь и медленнее отдыхаете, а без воды выносливость не поднимется выше 40%.",
		check = function(ply) return ply:GetNW2Float("nyrp.thirst", 100) < 25 end,
		danger = function(ply) return ply:GetNW2Float("nyrp.thirst", 100) <= 0 end,
		value = function(ply) return "Вода " .. math.floor(ply:GetNW2Float("nyrp.thirst", 100)) .. "%" end },
	{ id = "wet", name = "Промок", icon = "wet", level = "info",
		desc = "Одежда мокрая насквозь. Высохнет сама со временем.",
		check = function(ply) return Cond.Until(ply, "wet") > 0 end,
		value = function(ply) return "Высохнет через " .. secs(Cond.Until(ply, "wet")) end },
	{ id = "bruise", name = "Ушиб", icon = "fall", level = "warn",
		desc = "Неудачное приземление: ноги болят, вы двигаетесь медленнее.",
		check = function(ply) return Cond.Until(ply, "bruise") > 0 and Cond.Until(ply, "fracture") <= 0 end,
		value = function(ply) return "Пройдёт через " .. secs(Cond.Until(ply, "bruise")) end },
	{ id = "fracture", name = "Перелом ноги", icon = "bruise", level = "danger",
		desc = "Вы сильно разбились при падении. Бег недоступен, скорость сильно снижена. Аптечка поможет зафиксировать ногу.",
		check = function(ply) return Cond.Until(ply, "fracture") > 0 end,
		value = function(ply) return "Заживёт через " .. secs(Cond.Until(ply, "fracture")) end },
	{ id = "concussion", name = "Сотрясение", icon = "concussion", level = "warn",
		desc = "После потери сознания кружится голова и плывёт картинка.",
		check = function(ply) return Cond.Until(ply, "concussion") > 0 end,
		value = function(ply) return "Пройдёт через " .. secs(Cond.Until(ply, "concussion")) end },
	{ id = "injured", name = "Ранен", icon = "injured", level = "warn",
		desc = "Здоровье ниже половины: кружится голова, стучит сердце, бег утомляет быстрее. Используйте аптечку.",
		check = function(ply) local hp = ply:Health() return hp < 50 and hp >= 20 end,
		value = function(ply) return "Здоровье " .. ply:Health() .. "%" end },
	{ id = "critical", name = "Критическое состояние", icon = "critical", level = "danger",
		desc = "Вы можете умереть от любого удара. Срочно нужна медицинская помощь.",
		check = function(ply) return ply:Health() < 20 end,
		value = function(ply) return "Здоровье " .. ply:Health() .. "%" end },
}

-- Урон от падения по скорости приземления (реалистичная кривая вместо фиксированных 10).
function Cond.FallDamage(speed)
	local F = NYRP.Config.Fall
	if speed <= F.Safe then return 0 end
	local k = math.Clamp((speed - F.Safe) / (F.Fatal - F.Safe), 0, 2)
	return math.Round(100 * k ^ F.Curve)
end
