--[[
	Рация: свой слот рядом с телефоном. Частота 100.0–300.0 (шаг 0.1) хранится в предмете.
	В руке: ЛКМ — настроить частоту, держать ПКМ — говорить голосом в эфир.
	Чат: /r текст — зелёным всем на той же частоте: [РАЦИЯ: 150.0] Имя говорит по рации: 'текст'.
	Слышат все, у кого рация надета в слот и включена на той же частоте.
]]

NYRP.Radio = NYRP.Radio or {}
local R = NYRP.Radio
local Items = NYRP.Items

R.Min, R.Max = 100.0, 300.0

local has = false
for _, s in ipairs(Items.WeaponSlots) do if s.id == "radio" then has = true end end
if not has then
	Items.WeaponSlots[#Items.WeaponSlots + 1] = { id = "radio", name = "Рация", icon = "radio" }
	Items.EquipSlot.radio = Items.WeaponSlots[#Items.WeaponSlots]
end

function R.Clamp(f)
	f = tonumber(f) or R.Min
	return math.Clamp(math.floor(f * 10 + 0.5) / 10, R.Min, R.Max)
end

function R.Format(f) return string.format("%.1f", f or 0) end

-- частота включённой рации игрока (0 — нет рации или выключена)
function R.Freq(ply) return ply:GetNW2Float("nyrp.radioFreq", 0) end
function R.Transmitting(ply) return ply:GetNW2Bool("nyrp.radioTx") end
