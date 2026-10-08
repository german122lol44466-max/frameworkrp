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

function C.TypeOf(ent)
	return C.Types[ent:GetNW2String("nyrp.ctype", "crate")] or C.Types.crate
end
