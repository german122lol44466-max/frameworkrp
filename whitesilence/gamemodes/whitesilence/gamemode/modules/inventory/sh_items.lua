--[[
	Инвентарь — общая часть: предметы, сетка рюкзака, вес.

	Рюкзак — сетка GridW × GridH, предмет занимает w × h клеток (можно повернуть). У стопок — count,
	у аптечки — charges (применений), у коробок патронов — count патронов.
	Патроны в коробках и есть запас оружия: перезарядка списывает их из коробок (sv_inventory.lua).
	Вес замедляет: больше CarryLight — медленнее, больше CarryMax — нельзя подобрать.
]]

local I = WS.Inv or {}
WS.Inv = I

I.GridW, I.GridH = 6, 4
I.CarryLight, I.CarryMax = 18, 32           -- кг

I.Items = {
	bandage = {
		name = "Бинт", desc = "Останавливает кровотечение, немного восстанавливает здоровье.",
		mesh = "bandage", w = 1, h = 1, weight = 0.1, stack = 5, use = 3.0, heal = 8, stopBleed = true, quick = 4,
	},
	medkit = {
		name = "Аптечка АИ-4", desc = "Останавливает кровотечение и восстанавливает 35 здоровья. Можно применить на товарище.",
		mesh = "medkit", w = 2, h = 1, weight = 1.1, stack = 1, charges = 3, use = 5.0, heal = 35, stopBleed = true, quick = 5,
		other = true,
	},
	painkillers = {
		name = "Промедол", desc = "Снимает боль: меньше трясёт от ранений, быстрее восстанавливается выносливость (90 с).",
		mesh = "painkillers", w = 1, h = 1, weight = 0.1, stack = 4, use = 2.0, heal = 5, pain = 90, quick = 6,
	},
	battery = {
		name = "Батарея ПНВ", desc = "Полностью заряжает прибор ночного видения и тепловизор.",
		mesh = "battery", w = 1, h = 1, weight = 0.25, stack = 3, use = 2.5, battery = true, quick = 7,
	},
	ammo_rifle = {
		name = "Патроны 5.45×39", desc = "Цинк патронов к автомату. Перезарядка берёт патроны отсюда.",
		mesh = "ammo_rifle", w = 2, h = 1, weight = 0.011, ammo = 1, max = 120,
	},
	ammo_pistol = {
		name = "Пистолетные патроны", desc = "Коробка патронов к пистолету.",
		mesh = "ammo_pistol", w = 1, h = 1, weight = 0.015, ammo = 2, max = 50,
	},
}

-- набор на выход (награды за достижения добавляют к нему)
I.StartKit = {
	{ "bandage", 3 }, { "medkit", 1 }, { "painkillers", 2 }, { "battery", 1 },
	{ "ammo_rifle", 120 }, { "ammo_rifle", 90 }, { "ammo_pistol", 50 },
}

-- что падает с врагов: шанс, предмет, количество
I.Loot = {
	{ 0.45, "ammo_rifle", 20, 60 },
	{ 0.22, "bandage", 1, 2 },
	{ 0.07, "medkit", 1, 1 },
	{ 0.06, "painkillers", 1, 1 },
	{ 0.04, "battery", 1, 1 },
}

function I.Def(id) return I.Items[id] end

function I.Size(it)
	local d = I.Items[it.id]
	if it.rot then return d.h, d.w end
	return d.w, d.h
end

-- вес предмета: у патронов — за патрон
function I.Weight(it)
	local d = I.Items[it.id]
	if d.ammo then return d.weight * (it.count or 0) + 0.3 end
	return d.weight * (it.count or 1)
end

function I.TotalWeight(list)
	local w = 0
	for _, it in ipairs(list) do w = w + I.Weight(it) end
	return w
end

-- свободно ли место (x,y — левый верхний угол, с 1), кроме предмета skip
function I.Fits(list, x, y, w, h, skip)
	if x < 1 or y < 1 or x + w - 1 > I.GridW or y + h - 1 > I.GridH then return false end
	for _, it in ipairs(list) do
		if it ~= skip then
			local iw, ih = I.Size(it)
			if x < it.x + iw and x + w > it.x and y < it.y + ih and y + h > it.y then return false end
		end
	end
	return true
end

-- первое свободное место (с поворотом, если не влезает)
function I.FindSpot(list, id)
	local d = I.Items[id]
	for _, rot in ipairs({ false, true }) do
		local w, h = d.w, d.h
		if rot then w, h = h, w end
		if not rot or w ~= h then
			for y = 1, I.GridH do
				for x = 1, I.GridW do
					if I.Fits(list, x, y, w, h) then return x, y, rot end
				end
			end
		end
	end
end

-- сколько всего (патронов / штук) предметов вида
function I.Count(list, id)
	local n = 0
	for _, it in ipairs(list) do if it.id == id then n = n + (it.count or 1) end end
	return n
end

function I.CountAmmo(list, kind)
	local n = 0
	for _, it in ipairs(list) do
		local d = I.Items[it.id]
		if d.ammo == kind then n = n + (it.count or 0) end
	end
	return n
end

-- первый предмет с быстрым слотом key (4..7)
function I.ByQuick(list, key)
	for _, it in ipairs(list) do
		local d = I.Items[it.id]
		if d.quick == key then return it end
	end
end
