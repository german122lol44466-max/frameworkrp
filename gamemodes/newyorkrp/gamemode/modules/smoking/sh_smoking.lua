--[[
	Курение. Пачка «Liberty Lights» (ПКМ в инвентаре → «Взять сигарету в рот»): сигарета появляется во рту
	(видно и от первого лица). Зажигалка в руке (слот «В руке») — ЛКМ с анимацией подкуривает.
	Горит 90 секунд: затяжки с дымом; бафф — спокойствие и быстрее восстанавливается выносливость.
	Дебафф после: −5 к жажде, −2 к здоровью, иногда кашель. При смерти сигарета пропадает.
	Состояние: NW2Int nyrp.cig (0 — нет, 1 — не горит, 2 — горит), NW2Float nyrp.cigEnd — когда догорит.
]]

NYRP.Smoking = NYRP.Smoking or {}
local S = NYRP.Smoking
S.BurnTime = 90

function S.State(ply) return ply:GetNW2Int("nyrp.cig", 0) end
function S.Lit(ply) return S.State(ply) == 2 end

local Cond = NYRP.Cond
if Cond and Cond.Statuses then
	table.insert(Cond.Statuses, 1, { id = "smoking", name = "Курит", icon = "smoking", level = "info",
		desc = "Сигарета успокаивает: выносливость восстанавливается быстрее. Потом захочется пить, а здоровью — минус.",
		check = function(ply) return S.Lit(ply) end,
		value = function(ply) return "Догорит через " .. math.max(0, math.ceil(ply:GetNW2Float("nyrp.cigEnd", 0) - CurTime())) .. " с" end })
end
