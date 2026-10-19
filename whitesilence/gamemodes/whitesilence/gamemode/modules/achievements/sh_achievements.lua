--[[
	Достижения: за что выдаются и что дают.
	Награды двух видов:
	  title — звание (выбирается в меню «Достижения», видно в отряде, списке игроков и снаряжении);
	  kit   — постоянная прибавка к набору на выход (предметы инвентаря).
	Прогресс хранится на сервере (PData), счётчики — goal.
]]

local A = WS.Ach or {}
WS.Ach = A

A.List = {
	{ id = "first_blood", name = "Первый контакт", desc = "Уничтожить первого «бойца Дельты».", icon = "skull", reward = { title = "Боец «Бурана»" } },
	{ id = "hunter", name = "Охотник", desc = "Уничтожить 50 противников.", icon = "alert", goal = 50, stat = "kills",
		reward = { kit = { { "ammo_rifle", 60 } } } },
	{ id = "marksman", name = "Меткий", desc = "25 попаданий в голову, ставших смертельными.", icon = "eye", goal = 25, stat = "headshots",
		reward = { title = "Снайпер" } },
	{ id = "medic", name = "Санитар", desc = "Вылечить товарищей аптечкой на 150 здоровья.", icon = "health", goal = 150, stat = "healed",
		reward = { kit = { { "medkit", 1 } }, title = "Санитар" } },
	{ id = "bandager", name = "Перевязка", desc = "Остановить своё кровотечение 10 раз.", icon = "heart", goal = 10, stat = "bleedstops",
		reward = { kit = { { "bandage", 2 } } } },
	{ id = "untouched", name = "Ни царапины", desc = "Пройти главу, не получив урона.", icon = "armor", reward = { title = "Неуязвимый" } },
	{ id = "signal", name = "Связист", desc = "Запустить ретранслятор.", icon = "radio", reward = { kit = { { "battery", 1 } } } },
	{ id = "looter", name = "Хозяйственный", desc = "Подобрать 40 предметов.", icon = "users", goal = 40, stat = "picked",
		reward = { kit = { { "painkillers", 1 } } } },
	{ id = "supply", name = "Снабженец", desc = "Открыть 8 ящиков снабжения.", icon = "squad", goal = 8, stat = "crates",
		reward = { kit = { { "ammo_pistol", 50 } } } },
	{ id = "halfway", name = "Полпути", desc = "Дойти до главы «Источник».", icon = "steps", reward = { title = "Ветеран Арктики" } },
	{ id = "last_one", name = "Последний", desc = "Дойти до чекпоинта, когда весь отряд пал.", icon = "user", reward = { title = "Последний из «Бурана»" } },
	{ id = "complete", name = "Белая тишина", desc = "Завершить операцию.", icon = "nvg", reward = { title = "Белая тишина", kit = { { "medkit", 1 } } } },
	{ id = "no_losses", name = "Потерь нет", desc = "Завершить операцию без единой гибели в отряде.", icon = "thermal",
		reward = { title = "Призрак Арктики" } },
}
A.ById = {}
for i, a in ipairs(A.List) do a.index = i A.ById[a.id] = a end

function A.TitleOf(ply)
	local t = IsValid(ply) and ply:GetNW2String("ws_title", "") or ""
	return t ~= "" and t or nil
end

function A.RewardText(a)
	local parts = {}
	local r = a.reward or {}
	if r.title then parts[#parts + 1] = "звание «" .. r.title .. "»" end
	for _, k in ipairs(r.kit or {}) do
		local d = WS.Inv and WS.Inv.Items[k[1]]
		if d then parts[#parts + 1] = "+" .. (d.ammo and (k[2] .. " патр. ") or (k[2] .. " × ")) .. d.name .. " в наборе" end
	end
	return table.concat(parts, ", ")
end
