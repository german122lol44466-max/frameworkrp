--[[
	Смартфон: предмет «Телефон» (оружие в отдельном слоте), «SIM-карта», общие данные приложений.
	Данные телефона живут в data предмета (сохраняются вместе с инвентарём персонажа):
	  serial, sim = {number}, contacts = {{name, number}}, notes = {{title, text, t}},
	  alarms = {{h, m, on, label}}, events = {{day, text}}, apps = {id=true}, recents = {{number, dir, t, ok}},
	  settings = {wall, ring, alarm, pin, face, games = {snake=рекорд, ...}}
]]

NYRP.Phone = NYRP.Phone or {}
local P = NYRP.Phone
local Items = NYRP.Items

-- слот телефона рядом с оружием
local has = false
for _, s in ipairs(Items.WeaponSlots) do if s.id == "phone" then has = true end end
if not has then
	Items.WeaponSlots[#Items.WeaponSlots + 1] = { id = "phone", name = "Телефон", icon = "p_mobile" }
	Items.EquipSlot.phone = Items.WeaponSlots[#Items.WeaponSlots]
end

Items.Register("phone", {
	name = "Смартфон NY One", desc = "Тонкий смартфон в графитовом корпусе с матовой тёмно-синей спинкой. Без SIM-карты — просто красивые часы.",
	model = "models/nyrp/phone/w_phone.mdl", category = "weapon", weaponSlot = "phone", class = "nyrp_phone",
	buffs = { { "Звонки, заметки, будильник", true }, { "Нужна SIM-карта", false } },
	icon = { ang = Angle(0, 180, 0), zoom = 0.8 },
})

Items.Register("simcard", {
	name = "SIM-карта", desc = "SIM-карта оператора NY Mobile. Перетащите на телефон, чтобы вставить.",
	model = "models/nyrp/phone/w_simcard.mdl", category = "misc", stack = 1,
	buffs = { { "Номер телефона", true } },
	icon = { ang = Angle(90, 180, 0), zoom = 0.6 },
})

P.Walls = { "wall1", "wall2", "wall3", "wall4", "wall5" }
P.Rings = { { "ring1", "Манхэттен" }, { "ring2", "Бродвей" }, { "ring3", "Метро" } }
P.Alarms = { { "alarm1", "Рассвет" }, { "alarm2", "Сирена" } }

-- Приложения магазина NY Store
P.Store = {
	{ id = "liberty", name = "Liberty Bank", icon = "p_bank", color = Color(32, 92, 200), kind = "bank", desc = "Банк статуи Свободы. Счёт, переводы по номеру телефона." },
	{ id = "hudson", name = "Hudson Trust", icon = "p_bank", color = Color(18, 140, 110), kind = "bank", desc = "Надёжный банк с берегов Гудзона." },
	{ id = "empire", name = "Empire Pay", icon = "p_card", color = Color(150, 60, 200), kind = "bank", desc = "Быстрые платежи от Эмпайр-стейт." },
	{ id = "snake", name = "Subway Snake", icon = "p_game", color = Color(60, 170, 70), kind = "game", desc = "Змейка в тоннелях метро." },
	{ id = "g2048", name = "2048 Blocks", icon = "p_game", color = Color(230, 150, 40), kind = "game", desc = "Складывайте кварталы до 2048." },
	{ id = "taxi", name = "Yellow Rush", icon = "p_game", color = Color(247, 198, 0), kind = "game", desc = "Такси уворачивается от машин на авеню." },
}
P.StoreByID = {}
for _, a in ipairs(P.Store) do P.StoreByID[a.id] = a end
P.Banks = { liberty = true, hudson = true, empire = true }

-- Игровая дата: сутки по NYRP.Time, отсчёт от 1 сентября.
local MONTHS = { "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря" }
P.MonthNames = { "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь" }
P.MonthGen = MONTHS
local MDAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
P.MonthDays = MDAYS

-- Номер игрового дня (0 = 1 сентября). Сервер хранит его в Global2Int и прибавляет в полночь.
function P.DayIndex() return GetGlobal2Int("nyrp.day", 0) end

-- день → {d, m, wd} (wd: 1 = понедельник)
function P.Date(idx)
	idx = idx or P.DayIndex()
	local m, d = 9, 1 + idx
	while d > MDAYS[m] do d = d - MDAYS[m] m = m % 12 + 1 end
	return d, m, (idx + 0) % 7 + 1 -- 1 сентября — понедельник
end

function P.DateText(idx)
	local d, m = P.Date(idx)
	return d .. " " .. MONTHS[m]
end

P.WeekDays = { "Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс" }

-- Номер в виде «(212) 555-0142» → только цифры
function P.Digits(s) return (string.gsub(s or "", "%D", "")) end
function P.FormatNumber(digits)
	digits = P.Digits(digits)
	if #digits == 10 then return string.format("(%s) %s-%s", digits:sub(1, 3), digits:sub(4, 6), digits:sub(7)) end
	return digits
end

-- Телефон, который у игрока в слоте (и вставлена ли SIM)
function P.Equipped(ply)
	local inv
	if SERVER then inv = NYRP.Inv and NYRP.Inv.Get(ply) else inv = NYRP.Inventory and NYRP.Inventory.Data end
	local it = inv and inv.equip and inv.equip.phone
	if it and it.id == "phone" then return it end
end

function P.Number(ply)
	local it = P.Equipped(ply)
	return it and it.data and it.data.sim and it.data.sim.number
end
