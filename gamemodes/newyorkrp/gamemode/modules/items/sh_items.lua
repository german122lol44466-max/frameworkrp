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
Items.Needs = needs

-- ------------------------------------------------- предметы из папки items/ --
--[[
	Каждый файл gamemode/items/<папка>/<id>.lua описывает один предмет через таблицу ITEM
	(программировать не нужно — см. gamemode/items/README.md). Папка — это тип по умолчанию:
	food, drinks, medical, clothing, armor, weapons, tools, documents, misc.
]]
local FOLDER_TYPE = {
	food = "food", drinks = "drink", medical = "medical", clothing = "clothing", armor = "armor",
	weapons = "weapon", tools = "tool", documents = "document", misc = "misc",
}
local TYPE_CATEGORY = {
	food = "food", drink = "food", medical = "medical", clothing = "clothing", armor = "clothing",
	weapon = "weapon", tool = "weapon", document = "document", misc = "misc",
}

local function sign(n) return (n > 0 and "+" or "") .. n end

-- ITEM (как в файле) -> описание предмета для Items.Register
function Items.FromTable(id, I, folder)
	local typ = string.lower(I.Type or FOLDER_TYPE[folder] or "misc")
	local def = {
		name = I.Name or id, desc = I.Description or I.Desc or "", model = I.Model or "models/props_junk/cardboard_box004a.mdl",
		category = TYPE_CATEGORY[typ] or "misc", type = typ, stack = I.Stack or 1, skin = I.Skin,
		icon = I.Icon and { ang = I.Icon.Angle or I.Icon.ang or Angle(28, 220, 0), zoom = I.Icon.Zoom or I.Icon.zoom or 1 } or nil,
		useText = I.UseText, leaves = I.Leaves, buffs = I.Buffs,
		-- одежда и броня
		slot = I.Slot, bodygroups = I.Bodygroups, armor = I.Armor, speed = I.Speed, masks = I.HidesFace,
		protect = I.Protect, heavy = I.Heavy, wear = I.Wear,
		-- оружие и инструменты
		weaponSlot = (typ == "weapon" or typ == "tool") and (I.Slot or "melee") or nil, class = I.Weapon, ammo = I.Ammo,
		-- расходники
		uses = I.Uses, hunger = I.Hunger, thirst = I.Thirst, heal = I.Health, stamina = I.Stamina, sound = I.UseSound,
		effects = I.Effects, onUse = I.OnUse, onEquip = I.OnEquip, onUnequip = I.OnUnequip,
		data = I.Data, price = I.Price,
	}
	if def.category == "clothing" then def.slot = def.slot or (typ == "armor" and "vest" or "shirt") end
	if def.weaponSlot then def.slot = nil end
	-- плюсы/минусы в описании, если автор их не написал
	if not def.buffs then
		local b = {}
		if I.Hunger and I.Hunger ~= 0 then b[#b + 1] = { sign(I.Hunger) .. " к сытости", I.Hunger > 0 } end
		if I.Thirst and I.Thirst ~= 0 then b[#b + 1] = { sign(I.Thirst) .. " к жажде", I.Thirst > 0 } end
		if I.Health and I.Health ~= 0 then b[#b + 1] = { sign(I.Health) .. " к здоровью", I.Health > 0 } end
		if I.Stamina and I.Stamina ~= 0 then b[#b + 1] = { sign(I.Stamina) .. " к выносливости", I.Stamina > 0 } end
		if I.Armor and I.Armor ~= 0 then b[#b + 1] = { sign(I.Armor) .. " к броне", true } end
		if I.Protect then b[#b + 1] = { "Защита от ранений: " .. math.floor(I.Protect * 100) .. "%", true } end
		if I.Speed and I.Speed ~= 0 then b[#b + 1] = { sign(math.floor(I.Speed * 100)) .. "% к скорости", I.Speed > 0 } end
		if I.HidesFace then b[#b + 1] = { "Скрывает лицо: вас не узнают", true } end
		if I.Uses and I.Uses > 1 then b[#b + 1] = { "Использований: " .. I.Uses, true } end
		def.buffs = b
	end
	-- расходник без своего кода: сытость/жажда/здоровье/выносливость + звук
	local consumable = typ == "food" or typ == "drink" or typ == "medical" or I.Hunger or I.Thirst or I.Health
	if I.OnUse or consumable then
		def.useText = def.useText or (typ == "drink" and "Выпить" or typ == "food" and "Съесть" or "Использовать")
		def.use = function(ply, it)
			if I.OnUse then
				local r = I.OnUse(ply, it)
				if r ~= nil then return r end
			end
			if I.Health and I.Health > 0 and ply:Health() >= ply:GetMaxHealth() and not I.Hunger and not I.Thirst then
				NYRP.Notify(ply, "Вы и так здоровы", "warning")
				return false
			end
			needs(ply, I.Hunger, I.Thirst)
			if I.Health then ply:SetHealth(math.Clamp(ply:Health() + I.Health, 1, ply:GetMaxHealth())) end
			if I.Stamina then ply:SetNW2Float("nyrp.stamina", math.Clamp(ply:GetNW2Float("nyrp.stamina", 100) + I.Stamina, 0, 100)) end
			local snd = I.UseSound or (typ == "drink" and ("nyrp/fx/drink" .. math.random(1, 3) .. ".wav")) or (typ == "food" and "nyrp/fx/eat.wav") or nil
			if snd then ply:EmitSound(snd, 60, math.random(96, 104)) end
			hook.Run("NYRP.ItemUsed", ply, id)
			return true
		end
	end
	return def
end

function Items.LoadFolder()
	local root = NYRP.Root .. "items/"
	local _, dirs = file.Find(root .. "*", "LUA")
	local n = 0
	for di = 1, #dirs do
		local folder = dirs[di]
		local files = file.Find(root .. folder .. "/*.lua", "LUA")
		for fi = 1, #files do
			local f = files[fi]
			local id = string.StripExtension and string.StripExtension(f) or string.gsub(f, "%.lua$", "")
			ITEM = {}
			if SERVER then AddCSLuaFile(root .. folder .. "/" .. f) end
			include(root .. folder .. "/" .. f)
			local I = ITEM
			ITEM = nil
			if I and (I.Name or I.Model) and not I.Disabled then
				id = I.ID or id
				Items.Register(id, Items.FromTable(id, I, folder))
				n = n + 1
			end
		end
	end
	return n
end

-- слоты, которые появились вместе с новыми предметами
Items.ClothingSlots[#Items.ClothingSlots + 1] = { id = "vest", name = "Бронежилет", icon = "shield" }
Items.EquipSlot.vest = Items.ClothingSlots[#Items.ClothingSlots]
Items.WeaponSlots[#Items.WeaponSlots + 1] = { id = "tool", name = "В руке", icon = "hand" }
Items.EquipSlot.tool = Items.WeaponSlots[#Items.WeaponSlots]

Items.LoadFolder()
