--[[
	Реестр предметов и тестовые предметы.
	NYRP.Items.Register(id, def) — def:
	  name, desc, model, category (food | medical | clothing | weapon | document | misc), stack,
	  slot (для одежды), weaponSlot + class + ammo (для оружия), buffs = { {text, good}, ... },
	  use = function(ply, item) -> true, если предмет тратится; useText — подпись кнопки.
	  icon = { ang = Angle, zoom = 1 } — ракурс иконки.
]]

NYRP.Items = NYRP.Items or {}
local Items = NYRP.Items
Items.List = Items.List or {}

Items.Categories = {
	food = "Еда и напитки", medical = "Медицина", clothing = "Одежда", weapon = "Оружие", document = "Документы", misc = "Разное",
}

Items.ClothingSlots = {
	{ id = "head", name = "Головной убор", icon = "helmet" },
	{ id = "glasses", name = "Очки", icon = "glasses" },
	{ id = "mask", name = "Маска", icon = "mask" },
	{ id = "jacket", name = "Куртка", icon = "jacket" },
	{ id = "shirt", name = "Футболка", icon = "shirt" },
	{ id = "gloves", name = "Перчатки", icon = "gloves" },
	{ id = "pants", name = "Штаны", icon = "pants" },
	{ id = "shoes", name = "Обувь", icon = "shoe" },
}
Items.WeaponSlots = {
	{ id = "primary", name = "Основное", icon = "crosshair" },
	{ id = "secondary", name = "Вторичное", icon = "target" },
	{ id = "melee", name = "Холодное", icon = "sword" },
}
Items.EquipSlot = {}
for _, s in ipairs(Items.ClothingSlots) do Items.EquipSlot[s.id] = s end
for _, s in ipairs(Items.WeaponSlots) do Items.EquipSlot[s.id] = s end

function Items.Register(id, def)
	def.id = id
	def.stack = def.stack or 1
	def.buffs = def.buffs or {}
	def.category = def.category or "misc"
	Items.List[id] = def
end

function Items.Get(id) return Items.List[id] end

-- В какой слот снаряжения встаёт предмет.
function Items.EquipTarget(def)
	if not def then return end
	if def.category == "clothing" then return def.slot end
	if def.category == "weapon" then return def.weaponSlot end
end

local function needs(ply, hunger, thirst)
	if hunger then ply:SetNW2Float("nyrp.hunger", math.Clamp(ply:GetNW2Float("nyrp.hunger", 100) + hunger, 0, 100)) end
	if thirst then ply:SetNW2Float("nyrp.thirst", math.Clamp(ply:GetNW2Float("nyrp.thirst", 100) + thirst, 0, 100)) end
end
local function heal(ply, n)
	ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + n))
end

-- ------------------------------------------------------------ еда/питьё --
Items.Register("water", {
	name = "Бутылка воды", desc = "Обычная вода из магазина на углу. Холодная.",
	model = "models/props_junk/garbage_plasticbottle003a.mdl", category = "food", stack = 5,
	buffs = { { "+35 к жажде", true } }, useText = "Выпить",
	use = function(ply) needs(ply, nil, 35) ply:EmitSound("npc/barnacle/barnacle_gulp1.wav", 60) return true end,
})
Items.Register("soda", {
	name = "Liberty Cola", desc = "Сладкая газировка в жестяной банке. Бодрит, но ненадолго.",
	model = "models/props_junk/PopCan01a.mdl", category = "food", stack = 6,
	buffs = { { "+20 к жажде", true }, { "+5 к сытости", true } }, useText = "Выпить",
	use = function(ply) needs(ply, 5, 20) ply:EmitSound("npc/barnacle/barnacle_gulp2.wav", 60) return true end,
})
Items.Register("coffee", {
	name = "Кофе навынос", desc = "Крепкий чёрный кофе из закусочной. Пахнет утренним Бруклином.",
	model = "models/props_junk/garbage_coffeemug001a.mdl", category = "food", stack = 3,
	buffs = { { "+15 к жажде", true }, { "+5 к здоровью", true } }, useText = "Выпить",
	use = function(ply) needs(ply, nil, 15) heal(ply, 5) ply:EmitSound("npc/barnacle/barnacle_gulp1.wav", 60) return true end,
})
Items.Register("takeout", {
	name = "Лапша в коробке", desc = "Китайская лапша из Чайна-тауна. Ещё тёплая.",
	model = "models/props_junk/garbage_takeoutcarton001a.mdl", category = "food", stack = 3,
	buffs = { { "+40 к сытости", true }, { "-5 к жажде", false } }, useText = "Съесть",
	use = function(ply) needs(ply, 40, -5) ply:EmitSound("npc/barnacle/barnacle_crunch2.wav", 60) return true end,
})
Items.Register("milk", {
	name = "Пакет молока", desc = "Литр молока. Срок годности лучше не проверять.",
	model = "models/props_junk/garbage_milkcarton002a.mdl", category = "food", stack = 3,
	buffs = { { "+20 к жажде", true }, { "+10 к сытости", true } }, useText = "Выпить",
	use = function(ply) needs(ply, 10, 20) ply:EmitSound("npc/barnacle/barnacle_gulp2.wav", 60) return true end,
})

-- --------------------------------------------------------------- медицина --
Items.Register("medkit", {
	name = "Аптечка", desc = "Бинты, антисептик и обезболивающее. Поможет продержаться до больницы.",
	model = "models/items/healthkit.mdl", category = "medical", stack = 2,
	buffs = { { "+40 к здоровью", true } }, useText = "Использовать",
	use = function(ply)
		if ply:Health() >= ply:GetMaxHealth() then NYRP.Notify(ply, "Вы и так здоровы", "warning") return false end
		heal(ply, 40) ply:EmitSound("items/medshot4.wav", 60) return true
	end,
})
Items.Register("painkillers", {
	name = "Обезболивающее", desc = "Шприц-тюбик. Снимает боль, но не лечит причину.",
	model = "models/healthvial.mdl", category = "medical", stack = 4,
	buffs = { { "+15 к здоровью", true }, { "-5 к жажде", false } }, useText = "Уколоть",
	use = function(ply) heal(ply, 15) needs(ply, nil, -5) ply:EmitSound("items/smallmedkit1.wav", 60) return true end,
})

-- ------------------------------------------------------------------ одежда --
local function cloth(id, slot, name, desc, buffs, extra)
	local def = { name = name, desc = desc, model = "models/nyrp/clothes/" .. id .. ".mdl", category = "clothing", slot = slot, buffs = buffs,
		icon = { ang = Angle(50, 210, 0) } }
	if extra then table.Merge(def, extra) end
	Items.Register(id, def)
end
cloth("cap", "head", "Бейсболка «NY»", "Тёмно-синяя кепка с жёлтой нашивкой. Классика нью-йоркских улиц.", { { "Скрывает причёску", true } })
cloth("sunglasses", "glasses", "Солнцезащитные очки", "Круглые очки с тёмными стёклами.", { { "Глаза не видно", true } })
cloth("mask", "mask", "Медицинская маска", "Одноразовая маска. Закрывает половину лица.", { { "Скрывает лицо: вас не узнают", true } }, { masks = true })
cloth("tshirt", "shirt", "Белая футболка", "Хлопковая футболка с жёлтым принтом.", {})
cloth("jacket", "jacket", "Кожаная куртка", "Плотная коричневая кожа. Защищает от ветра с Гудзона и не только.",
	{ { "+15 к броне", true }, { "Тёплая", true } }, { armor = 15 })
cloth("gloves", "gloves", "Кожаные перчатки", "Чёрные перчатки. Не оставляют отпечатков.", { { "Без отпечатков пальцев", true } })
cloth("jeans", "pants", "Джинсы", "Синие джинсы прямого кроя.", {})
cloth("sneakers", "shoes", "Красные кроссовки", "Лёгкие беговые кроссовки.", { { "+5% к скорости бега", true } }, { speed = 0.05 })

-- ------------------------------------------------------------------ оружие --
local function weapon(id, slot, class, name, desc, model, ammo, buffs)
	Items.Register(id, { name = name, desc = desc, model = model, category = "weapon", weaponSlot = slot, class = class,
		ammo = ammo, buffs = buffs or {}, icon = { ang = Angle(10, 90, 0), zoom = 1.1 } })
end
weapon("pistol", "secondary", "weapon_pistol", "Пистолет 9 мм", "Компактный полуавтоматический пистолет.",
	"models/weapons/w_pistol.mdl", { "Pistol", 36 }, { { "Урон: средний", true }, { "Шумный", false } })
weapon("revolver", "secondary", "weapon_357", "Револьвер .357", "Тяжёлый револьвер. Шесть патронов — шесть аргументов.",
	"models/weapons/w_357.mdl", { "357", 12 }, { { "Урон: высокий", true }, { "Медленная перезарядка", false } })
weapon("smg", "primary", "weapon_smg1", "Пистолет-пулемёт", "Скорострельный ПП. Трудно контролировать отдачу.",
	"models/weapons/w_smg1.mdl", { "SMG1", 90 }, { { "Высокая скорострельность", true }, { "Сильная отдача", false } })
weapon("shotgun", "primary", "weapon_shotgun", "Дробовик", "Помповый дробовик. Аргумент ближнего боя.",
	"models/weapons/w_shotgun.mdl", { "Buckshot", 12 }, { { "Огромный урон вблизи", true }, { "Бесполезен вдали", false } })
weapon("crowbar", "melee", "weapon_crowbar", "Монтировка", "Стальная монтировка. Открывает и двери, и разговоры.",
	"models/weapons/w_crowbar.mdl", nil, { { "Не нужны патроны", true } })
weapon("baton", "melee", "weapon_stunstick", "Дубинка", "Полицейская дубинка с электрошоком.",
	"models/weapons/w_stunbaton.mdl", nil, { { "Оглушает", true } })

-- --------------------------------------------------------------- документы --
Items.Register("idcard", {
	name = "Удостоверение личности", desc = "Пластиковая карточка штата Нью-Йорк с фотографией и данными владельца.",
	model = "models/nyrp/clothes/idcard.mdl", category = "document", stack = 1, noDrop = true,
	buffs = { { "Подтверждает личность", true } }, useText = "Посмотреть",
	icon = { ang = Angle(70, 180, 0), zoom = 0.9 },
})
