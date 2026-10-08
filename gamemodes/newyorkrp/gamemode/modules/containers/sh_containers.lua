--[[
	Контейнеры (ящики, шкафчики, мусорные баки...): E — «Открываю...» 3 с, затем окно:
	слева ваша сумка, справа содержимое контейнера; предметы перетаскиваются туда и обратно.
	Админ: nyrp_container <тип> — поставить там, куда смотрите; nyrp_container_remove — убрать.
	Контейнеры и их содержимое сохраняются (data/nyrp/containers/<карта>.json).
]]

NYRP.Containers = NYRP.Containers or {}
local C = NYRP.Containers

C.OpenTime = 3

C.Types = {
	crate = { name = "Деревянный ящик", model = "models/props_junk/wood_crate001a.mdl", cols = 4, rows = 3 },
	locker = { name = "Шкафчик", model = "models/props_c17/Lockers001a.mdl", cols = 4, rows = 5 },
	dumpster = { name = "Мусорный бак", model = "models/props_junk/TrashDumpster01a.mdl", cols = 6, rows = 4 },
	fridge = { name = "Холодильник", model = "models/props_c17/FurnitureFridge001a.mdl", cols = 4, rows = 4 },
	cabinet = { name = "Картотека", model = "models/props_wasteland/controlroom_filecabinet002a.mdl", cols = 4, rows = 3 },
	ammo = { name = "Армейский ящик", model = "models/items/ammocrate_smg1.mdl", cols = 5, rows = 3 },
}

-- Лут: раз в Interval секунд в каждом контейнере (если в нём меньше Max вещей) с шансом Chance
-- появляется 1–2 предмета из его таблицы. Таблица: { id, вес, [мин], [макс] }.
C.Loot = {
	Interval = 300, Chance = 0.6,
	crate = { Max = 4, { "water", 5 }, { "soda", 4 }, { "takeout", 3 }, { "crowbar", 1 }, { "gloves", 2 }, { "painkillers", 2 } },
	locker = { Max = 6, { "tshirt", 4 }, { "jacket", 2 }, { "jeans", 3 }, { "sneakers", 3 }, { "cap", 3 }, { "gloves", 3 },
		{ "sunglasses", 2 }, { "mask", 1 }, { "baton", 1 } },
	dumpster = { Max = 5, { "takeout", 5 }, { "soda", 4 }, { "milk", 2 }, { "tshirt", 2 }, { "sneakers", 1 }, { "crowbar", 1 } },
	fridge = { Max = 6, { "water", 6, 1, 2 }, { "soda", 5, 1, 2 }, { "milk", 4 }, { "takeout", 4 }, { "coffee", 3 } },
	cabinet = { Max = 3, { "painkillers", 4 }, { "medkit", 2 }, { "coffee", 3 }, { "sunglasses", 1 } },
	ammo = { Max = 3, { "pistol", 3 }, { "revolver", 2 }, { "smg", 1 }, { "shotgun", 1 }, { "baton", 3 }, { "medkit", 3 } },
}

function C.TypeOf(ent)
	return C.Types[ent:GetNW2String("nyrp.ctype", "crate")] or C.Types.crate
end
