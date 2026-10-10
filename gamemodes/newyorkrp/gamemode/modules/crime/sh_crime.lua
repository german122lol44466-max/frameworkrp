--[[
	Криминал: карманные кражи и взлом замков.
	  Карманная кража — E по человеку СО СПИНЫ → «Обчистить карманы» (круговое меню). 4 секунды
	    нужно оставаться незамеченным: жертва обернулась или отошла — провал. Шанс — от «Ловкости».
	  Взлом — предмет «Отмычки» (слот «В руке»), ЛКМ по запертой двери → мини-игра (cl_lockpick.lua).
	Общие настройки и проверки, которые нужны и серверу, и клиенту.
]]

NYRP.Crime = NYRP.Crime or {}
local C = NYRP.Crime

if SERVER then
	util.AddNetworkString("nyrp.crime.pick")        -- клиент -> сервер: начать кражу (цель)
	util.AddNetworkString("nyrp.crime.pickState")   -- сервер -> вор: кража началась / закончилась
	util.AddNetworkString("nyrp.crime.lock")        -- сервер -> клиент: открыть / закрыть мини-игру взлома
	util.AddNetworkString("nyrp.crime.lockTry")     -- клиент -> сервер: попытка провернуть (угол) / выход
	util.AddNetworkString("nyrp.crime.lockRes")     -- сервер -> клиент: результат попытки
end

C.Pick = {
	Time = 4,               -- сколько секунд шарить по карманам
	Range = 75,             -- насколько близко подойти
	BreakRange = 105,       -- отошли дальше — провал
	BehindAngle = 120,      -- угол между взглядом жертвы и направлением на вора (больше — вы за спиной)
	NoticeAngle = 100,      -- во время кражи: жертва повернулась сильнее — заметила
	Cooldown = 90,          -- пауза вора между попытками (с)
	VictimCooldown = 600,   -- одного и того же человека — не чаще (с)
	MinPct = 0.10, MaxPct = 0.30, MaxCash = 300,
	PoliceChance = 0.35,    -- шанс вызова полиции при провале
}

C.Lock = {
	Range = 90,
	MaxAngle = 90,          -- отмычка вращается от -90° до +90°
	ZoneBase = 4,           -- полуширина «сладкого места» при ловкости 0 (градусы)
	ZonePerLevel = 0.9,     -- + за уровень ловкости
	HintWidth = 22,         -- зона «вибрации» (подсказка), внутри неё точно есть сладкое место
	TryDelay = 0.7,         -- не чаще одной попытки за столько секунд
	Timeout = 90,           -- мини-игра закрывается сама
	AlarmChance = 0.4,      -- шанс сигнализации при успехе (минус 2% за уровень ловкости)
	Cooldown = 4,
}

-- Угол (0..180) между взглядом victim и направлением от victim на thief.
-- 0 — смотрит прямо на вора, 180 — вор ровно за спиной.
function C.ViewAngle(victim, thief)
	local fwd = victim:EyeAngles():Forward()
	fwd.z = 0
	fwd:Normalize()
	local dir = thief:GetPos() - victim:GetPos()
	dir.z = 0
	dir:Normalize()
	local dot = math.Clamp(fwd:Dot(dir), -1, 1)
	return math.deg(math.acos(dot))
end

function C.IsBehind(victim, thief)
	return C.ViewAngle(victim, thief) > C.Pick.BehindAngle
end

-- Можно ли вообще трогать этого человека (без учёта угла)
function C.CanPickTarget(thief, victim)
	if not IsValid(victim) or not victim:IsPlayer() or victim == thief or not victim:Alive() then return false, "Нет цели" end
	if NYRP.HasCharacter and not NYRP.HasCharacter(victim) then return false, "Нет цели" end
	if NYRP.Cond and NYRP.Cond.KO and NYRP.Cond.KO(victim) then return false, "Человек без сознания — обыщите тело" end
	if thief:GetPos():Distance(victim:GetPos()) > C.Pick.Range then return false, "Подойдите вплотную" end
	if thief:InVehicle() or victim:InVehicle() then return false, "Не получится" end
	return true
end
