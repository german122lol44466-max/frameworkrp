--[[
	Алкоголь и опьянение (общая часть).
	Предметы: пиво, вино, виски, водка (framework/items/drinks/*). Уровень опьянения — NW2Float "nyrp.drunk" (0..100):
	  15+  лёгкое — покачивание взгляда;
	  35+  среднее — походка заплетается, картинка плывёт и двоится;
	  55+  сильное — речь в IC-чате искажается («ик»);
	  80+  тяжёлое — можно рухнуть на ходу.
	Трезвеет со временем; вода, кофе, газировка и молоко ускоряют. Иконка состояния — в списке статусов (справа сверху).
	Уровень сохраняется в c.flags.drunk. Админ: /sober [часть имени] — протрезвить.
]]

NYRP.Alcohol = NYRP.Alcohol or {}
local A = NYRP.Alcohol

A.Max = 100
A.SoberRate = 0.09   -- единиц в секунду (100 → 0 примерно за 18 минут)
A.Absorb = 2         -- сколько выпитого всасывается в секунду
A.Levels = {
	{ at = 80, name = "Тяжёлое опьянение" },
	{ at = 55, name = "Сильное опьянение" },
	{ at = 35, name = "Опьянение" },
	{ at = 15, name = "Лёгкое опьянение" },
}

function A.Level(ply) return ply:GetNW2Float("nyrp.drunk", 0) end

function A.Name(lvl)
	for _, l in ipairs(A.Levels) do if lvl >= l.at then return l.name end end
	return "Трезв"
end

-- 0..1 — сила «заплетающихся ног»
function A.Stagger(ply)
	return math.Clamp((A.Level(ply) - 30) / 60, 0, 1)
end

-- ----------------------------------------------------------- статус в HUD --
local function addStatus()
	local Cond = NYRP.Cond
	if not Cond or not Cond.Statuses then return false end
	for _, s in ipairs(Cond.Statuses) do if s.id == "drunk" then return true end end
	table.insert(Cond.Statuses, {
		id = "drunk", name = "Опьянение", icon = "concussion", level = "warn",
		desc = "Алкоголь ударил в голову: взгляд плывёт, ноги заплетаются, а язык не слушается. Пройдёт со временем — вода и кофе помогут быстрее.",
		check = function(ply) return A.Level(ply) >= 15 end,
		danger = function(ply) return A.Level(ply) >= 80 end,
		value = function(ply) return A.Name(A.Level(ply)) .. " · " .. math.floor(A.Level(ply)) .. "%" end,
	})
	return true
end
-- модуль состояний грузится позже (по алфавиту) — добавляем, когда он готов
if not addStatus() then
	timer.Simple(0, addStatus)
	hook.Add("InitPostEntity", "nyrp.alcohol.status", addStatus)
end

-- ---------------------------------------------------------- походка --
-- Детерминированное (от CurTime) отклонение: одинаково на клиенте и сервере, без рассинхрона предсказания.
hook.Add("SetupMove", "nyrp.alcohol", function(ply, mv)
	local k = A.Stagger(ply)
	if k <= 0 then return end
	local fwd, side = mv:GetForwardSpeed(), mv:GetSideSpeed()
	if fwd == 0 and side == 0 then return end
	local t, ph = CurTime(), ply:EntIndex() * 1.37
	local wob = math.sin(t * 1.6 + ph) * 0.65 + math.sin(t * 0.55 + ph * 2) * 0.35
	local speed = math.max(math.abs(fwd), math.abs(side))
	mv:SetSideSpeed(side + speed * wob * 0.75 * k)
	mv:SetForwardSpeed(fwd * (1 - 0.25 * k * math.abs(math.sin(t * 0.9 + ph))))
	mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * (1 - 0.2 * k))
end)
