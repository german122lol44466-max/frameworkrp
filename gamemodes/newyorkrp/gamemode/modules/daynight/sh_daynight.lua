--[[
	Общее время на сервере и смена дня и ночи.
	Игровые сутки длятся Config.DayMinutes реальных минут. Время одно для всех и сохраняется
	между перезапусками (data/nyrp/time.txt). Админ: nyrp_settime <час> (например 21.5).
]]

NYRP.Time = NYRP.Time or {}
local T = NYRP.Time

NYRP.Config.DayMinutes = NYRP.Config.DayMinutes or 60   -- реальных минут на игровые сутки
NYRP.Config.StartHour = NYRP.Config.StartHour or 9

-- Текущий час (0..24, дробный).
function T.Hour()
	local base = GetGlobal2Float("nyrp.timeBase", 0)      -- CurTime(), когда было baseHour
	local baseHour = GetGlobal2Float("nyrp.timeHour", NYRP.Config.StartHour)
	return (baseHour + (CurTime() - base) / (NYRP.Config.DayMinutes * 60) * 24) % 24
end

function T.Format(h)
	h = h or T.Hour()
	return string.format("%02d:%02d", math.floor(h), math.floor((h % 1) * 60))
end

-- Освещённость 0 (ночь) .. 1 (день): рассвет 5–8, закат 18–21.
function T.Daylight(h)
	h = h or T.Hour()
	if h >= 8 and h < 18 then return 1 end
	if h >= 21 or h < 5 then return 0 end
	if h < 8 then return math.Clamp((h - 5) / 3, 0, 1) end
	return math.Clamp(1 - (h - 18) / 3, 0, 1)
end

function T.Phase(h)
	h = h or T.Hour()
	if h >= 5 and h < 8 then return "sunrise", "Рассвет" end
	if h >= 8 and h < 18 then return "sun", "День" end
	if h >= 18 and h < 21 then return "sunset", "Закат" end
	return "moon", "Ночь"
end
