--[[
	Инвентарь на сервере. Сервер — единственный источник правды; клиент только просит.
	Данные: ply.nyrpInv = { slots = { [i] = {id, n, data} }, equip = { [slot] = {id, n, data} } }
]]

local Items = NYRP.Items
NYRP.Inv = NYRP.Inv or {}
local Inv = NYRP.Inv

-- Метка «чей предмет»: вещи, выброшенные/положенные в контейнер одним персонажем,
-- нельзя забрать другим персонажем того же игрока (защита от перекидывания лута между своими).
function Inv.Tag(ply, it)
	if not it or not ply.nyrpChar then return end
	it.data = it.data or {}
	it.data.nyrpFrom = NYRP.Chars.Key(ply) .. "|" .. ply.nyrpChar.id
end

function Inv.CanTake(ply, data)
	local from = data and data.nyrpFrom
	if not from or not ply.nyrpChar then return true end
	local key, char = string.match(from, "^(.*)|(%d+)$")
	if key == NYRP.Chars.Key(ply) and tonumber(char) ~= ply.nyrpChar.id then
		NYRP.Notify(ply, "Это вещь вашего другого персонажа — её нельзя забрать", "error")
		return false
	end
	return true
end

function Inv.Untag(it)
	if it and it.data then it.data.nyrpFrom = nil end
end

function Inv.Size(ply)
	local cfg = NYRP.Config.Bags[ply:GetNW2String("nyrp.bag", "waistbag")] or NYRP.Config.Bags.waistbag
	return cfg.cols * cfg.rows
end

function Inv.Get(ply)
	ply.nyrpInv = ply.nyrpInv or { slots = {}, equip = {} }
	return ply.nyrpInv
end

function Inv.Sync(ply)
	local inv = Inv.Get(ply)
	net.Start("nyrp.inv.sync")
	net.WriteUInt(Inv.Size(ply), 8)
	net.WriteTable(inv.slots)
	net.WriteTable(inv.equip)
	net.Send(ply)
	hook.Run("NYRP.InvChanged", ply)
end

function Inv.Clear(ply)
	ply.nyrpInv = { slots = {}, equip = {} }
	Inv.Sync(ply)
end

local function cleanItem(it)
	if type(it) ~= "table" or not Items.Get(it.id) then return end
	return { id = it.id, n = math.max(1, math.floor(tonumber(it.n) or 1)), data = type(it.data) == "table" and it.data or {} }
end

function Inv.Import(ply, slots, equip)
	local inv = { slots = {}, equip = {} }
	for k, it in pairs(slots or {}) do
		local i = tonumber(k)
		local c = cleanItem(it)
		if i and c then inv.slots[i] = c end
	end
	for k, it in pairs(equip or {}) do
		local c = cleanItem(it)
		if c and Items.EquipSlot[k] and Items.EquipTarget(Items.Get(c.id)) == k then inv.equip[k] = c end
	end
	ply.nyrpInv = inv
	Inv.Sync(ply)
end

function Inv.Export(ply)
	local inv = Inv.Get(ply)
	local slots = {}
	for i, it in pairs(inv.slots) do slots[tostring(i)] = it end
	return slots, inv.equip
end

function Inv.FreeSlot(ply)
	local inv = Inv.Get(ply)
	for i = 1, Inv.Size(ply) do
		if not inv.slots[i] then return i end
	end
end

-- Добавляет предметы, возвращает сколько поместилось.
function Inv.Add(ply, id, n, data)
	local def = Items.Get(id)
	if not def then return 0 end
	local inv = Inv.Get(ply)
	n = n or 1
	local added = 0
	if def.stack > 1 and not data then
		for i = 1, Inv.Size(ply) do
			local it = inv.slots[i]
			if it and it.id == id and it.n < def.stack then
				local put = math.min(def.stack - it.n, n - added)
				it.n = it.n + put
				added = added + put
				if added >= n then break end
			end
		end
	end
	while added < n do
		local free = Inv.FreeSlot(ply)
		if not free then break end
		local put = math.min(def.stack, n - added)
		inv.slots[free] = { id = id, n = put, data = data and table.Copy(data) or {} }
		added = added + put
	end
	if added > 0 then Inv.Sync(ply) end
	return added
end

function Inv.Take(ply, slot, n)
	local inv = Inv.Get(ply)
	local it = inv.slots[slot]
	if not it then return end
	n = math.min(n or 1, it.n)
	it.n = it.n - n
	if it.n <= 0 then inv.slots[slot] = nil end
	Inv.Sync(ply)
	return n
end

-- ------------------------------------------------------ эффекты снаряжения --
function Inv.ApplyEquipment(ply)
	local inv = Inv.Get(ply)
	local armor, speed, masked = 0, 0, false
	for slot, it in pairs(inv.equip) do
		local def = Items.Get(it.id)
		if def then
			armor = armor + (def.armor or 0)
			speed = speed + (def.speed or 0)
			if def.masks then masked = true end
		end
	end
	ply.nyrpSpeedBonus = speed
	ply.nyrpArmorMax = armor
	ply:SetArmor(math.min(ply:Armor(), armor))
	ply:SetNW2Bool("nyrp.masked", masked)
	NYRP.ApplyMovement(ply)
	hook.Run("NYRP.EquipmentApplied", ply, inv)
end

local function giveWeapon(ply, it)
	local def = Items.Get(it.id)
	if not def or not def.class then return end
	ply:Give(def.class, true)
	if def.ammo and not it.data.ammoGiven then
		ply:GiveAmmo(def.ammo[2], def.ammo[1], true)
		it.data.ammoGiven = true
	end
end

local function takeWeapon(ply, it)
	local def = Items.Get(it.id)
	if def and def.class and ply:HasWeapon(def.class) then ply:StripWeapon(def.class) end
end

hook.Add("NYRP.Loadout", "nyrp.inv", function(ply)
	local inv = Inv.Get(ply)
	for _, s in ipairs(Items.WeaponSlots) do
		if inv.equip[s.id] then giveWeapon(ply, inv.equip[s.id]) end
	end
end)

hook.Add("NYRP.PlayerSpawned", "nyrp.inv", function(ply)
	Inv.ApplyEquipment(ply)
	ply:SetArmor(ply.nyrpArmorMax or 0)
end)

-- --------------------------------------------------------------- действия --
-- Действие с прогресс-баром: NYRP.Action(ply, "Одеваю...", 2, fn, icon)
function NYRP.Action(ply, text, dur, fn, icon)
	if ply.nyrpAction then return false end
	ply.nyrpAction = { fin = CurTime() + dur }
	net.Start("nyrp.action")
	net.WriteString(text)
	net.WriteFloat(dur)
	net.WriteString(icon or "")
	net.Send(ply)
	timer.Create("nyrp.action." .. ply:EntIndex(), dur, 1, function()
		if not IsValid(ply) or not ply.nyrpAction then return end
		ply.nyrpAction = nil
		if ply:Alive() then fn() end
	end)
	return true
end

function NYRP.CancelAction(ply)
	if not ply.nyrpAction then return end
	ply.nyrpAction = nil
	timer.Remove("nyrp.action." .. ply:EntIndex())
	net.Start("nyrp.action")
	net.WriteString("")
	net.WriteFloat(0)
	net.WriteString("")
	net.Send(ply)
end
hook.Add("PlayerDeath", "nyrp.action", NYRP.CancelAction)

-- ----------------------------------------------------- экипировка/снятие --
function Inv.Equip(ply, slot, target)
	local inv = Inv.Get(ply)
	local it = inv.slots[slot]
	if not it then return end
	local def = Items.Get(it.id)
	target = target or Items.EquipTarget(def)
	if not target or Items.EquipTarget(def) ~= target then
		NYRP.Notify(ply, "Этот предмет сюда не подходит", "error")
		return
	end
	local isWeapon = def.category == "weapon"
	local text = def.weaponSlot == "phone" and "Беру телефон..." or (isWeapon and "Достаю оружие..." or "Одеваю...")
	NYRP.Action(ply, text, isWeapon and 0.9 or 1.2, function()
		if inv.slots[slot] ~= it then return end -- предмет успели переложить
		local prev = inv.equip[target]
		if prev then takeWeapon(ply, prev) end
		inv.equip[target] = it
		inv.slots[slot] = prev
		if def.weaponSlot == "phone" then
			-- телефон: сначала закрывается инвентарь (с анимацией сумки), потом телефон в руке
			giveWeapon(ply, it)
			net.Start("nyrp.phone.ui")
			net.Send(ply)
			timer.Simple(0.9, function()
				if IsValid(ply) and ply:Alive() and ply:HasWeapon(def.class) and Inv.Get(ply).equip[target] == it then ply:SelectWeapon(def.class) end
			end)
		elseif isWeapon then
			giveWeapon(ply, it)
			ply:SelectWeapon(def.class)
			ply:EmitSound("nyrp/fx/weapon_draw.wav", 62, math.random(96, 104))
		else
			ply:EmitSound("nyrp/fx/cloth_on.wav", 60, math.random(95, 105))
		end
		Inv.ApplyEquipment(ply)
		Inv.Sync(ply)
	end, isWeapon and "crosshair" or "hanger")
end

function Inv.Unequip(ply, target, toSlot)
	local inv = Inv.Get(ply)
	local it = inv.equip[target]
	if not it then return end
	local size = Inv.Size(ply)
	if toSlot and (toSlot < 1 or toSlot > size) then toSlot = nil end
	local dest = toSlot
	if dest and inv.slots[dest] then
		-- бросили на совместимую вещь — надеваем её (снятая встанет на её место)
		if Items.EquipTarget(Items.Get(inv.slots[dest].id)) == target then
			Inv.Equip(ply, dest, target)
			return
		end
		dest = nil
	end
	dest = dest or Inv.FreeSlot(ply)
	if not dest then NYRP.Notify(ply, "В сумке нет места", "error") return end
	local isWeapon = Items.Get(it.id).category == "weapon"
	-- снятие — тоже с коротким прогресс-баром
	NYRP.Action(ply, isWeapon and "Убираю оружие..." or "Снимаю...", isWeapon and 0.6 or 0.8, function()
		if inv.equip[target] ~= it then return end
		if inv.slots[dest] then dest = Inv.FreeSlot(ply) end
		if not dest then NYRP.Notify(ply, "В сумке нет места", "error") return end
		inv.equip[target] = nil
		inv.slots[dest] = it
		takeWeapon(ply, it)
		ply:EmitSound(isWeapon and "nyrp/fx/weapon_holster.wav" or "nyrp/fx/cloth_off.wav", 58, math.random(95, 105))
		Inv.ApplyEquipment(ply)
		Inv.Sync(ply)
	end, isWeapon and "arrow_left" or "hanger")
end

-- --------------------------------------------------------------- сеть --
local function limited(ply)
	if (ply.nyrpInvNext or 0) > CurTime() then return true end
	ply.nyrpInvNext = CurTime() + 0.12
	return not NYRP.HasCharacter(ply) or not ply:Alive()
end

net.Receive("nyrp.inv.move", function(_, ply)
	if limited(ply) then return end
	local fk, fkey, tk, tkey = net.ReadString(), net.ReadString(), net.ReadString(), net.ReadString()
	if hook.Run("NYRP.InvMove", ply, fk, fkey, tk, tkey) then return end -- особые случаи (SIM-карта на телефон)
	if (fk == "cont" or tk == "cont") and NYRP.Containers and NYRP.Containers.Move then
		NYRP.Containers.Move(ply, fk, fkey, tk, tkey)
		return
	end
	local inv = Inv.Get(ply)
	local size = Inv.Size(ply)
	if fk == "inv" and tk == "inv" then
		local a, b = tonumber(fkey), tonumber(tkey)
		if not a or not b or a == b or a < 1 or b < 1 or a > size or b > size or not inv.slots[a] then return end
		local A, B = inv.slots[a], inv.slots[b]
		local def = Items.Get(A.id)
		if B and B.id == A.id and def.stack > 1 and B.n < def.stack then
			local put = math.min(def.stack - B.n, A.n)
			B.n = B.n + put
			A.n = A.n - put
			if A.n <= 0 then inv.slots[a] = nil end
		else
			inv.slots[a], inv.slots[b] = B, A
		end
		Inv.Sync(ply)
	elseif fk == "inv" and tk == "eq" then
		local a = tonumber(fkey)
		if a and inv.slots[a] and Items.EquipSlot[tkey] then Inv.Equip(ply, a, tkey) end
	elseif fk == "eq" and tk == "inv" then
		if Items.EquipSlot[fkey] then Inv.Unequip(ply, fkey, tonumber(tkey)) end
	end
end)

net.Receive("nyrp.inv.equip", function(_, ply)
	if limited(ply) then return end
	Inv.Equip(ply, net.ReadUInt(8))
end)

net.Receive("nyrp.inv.unequip", function(_, ply)
	if limited(ply) then return end
	Inv.Unequip(ply, net.ReadString())
end)

net.Receive("nyrp.inv.use", function(_, ply)
	if limited(ply) then return end
	local slot = net.ReadUInt(8)
	local inv = Inv.Get(ply)
	local it = inv.slots[slot]
	if not it then return end
	local def = Items.Get(it.id)
	if not def.use then return end
	if def.use(ply, it) then Inv.Take(ply, slot, 1) end
end)

function Inv.Drop(ply, kind, key, all)
	local inv = Inv.Get(ply)
	local it = kind == "eq" and inv.equip[key] or inv.slots[tonumber(key) or -1]
	if not it then return end
	local def = Items.Get(it.id)
	if def.noDrop then NYRP.Notify(ply, "Этот предмет нельзя выбросить", "warning") return end
	local n = all and it.n or 1
	if kind == "eq" then
		inv.equip[key] = nil
		takeWeapon(ply, it)
		Inv.ApplyEquipment(ply)
		n = it.n
	else
		it.n = it.n - n
		if it.n <= 0 then inv.slots[tonumber(key)] = nil end
	end
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 60, filter = ply })
	local ent = ents.Create("nyrp_item")
	ent:SetPos(tr.HitPos + tr.HitNormal * 8)
	ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	local data = table.Copy(it.data or {})
	data.nyrpFrom = ply.nyrpChar and (NYRP.Chars.Key(ply) .. "|" .. ply.nyrpChar.id) or nil
	ent:SetItem(it.id, n, data)
	ent:Spawn()
	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:SetVelocity(ply:GetAimVector() * 80) end
	ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 5) .. ".wav", 55)
	ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_DROP, true)
	Inv.Sync(ply)
end

net.Receive("nyrp.inv.drop", function(_, ply)
	if limited(ply) then return end
	Inv.Drop(ply, net.ReadString(), net.ReadString(), net.ReadBool())
end)

-- Открытие/закрытие сумки: анимация у всех, звук молнии.
local function bagAnim(ply, open)
	ply:SetNW2Bool("nyrp.bagOpen", open)
	ply:SetNW2Float("nyrp.bagTime", CurTime())
	ply:EmitSound("nyrp/fx/zipper.wav", 58, open and 100 or 92, 0.8)
	net.Start("nyrp.inv.anim")
	net.WriteEntity(ply)
	net.WriteUInt(open and ACT_GMOD_GESTURE_ITEM_PLACE or ACT_GMOD_GESTURE_ITEM_GIVE, 16)
	net.SendPVS(ply:GetPos())
end

net.Receive("nyrp.inv.open", function(_, ply)
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return end
	if (ply.nyrpBagNext or 0) > CurTime() then return end
	ply.nyrpBagNext = CurTime() + 0.5
	bagAnim(ply, true)
end)
net.Receive("nyrp.inv.close", function(_, ply)
	if ply:GetNW2Bool("nyrp.bagOpen") then bagAnim(ply, false) end
end)
hook.Add("PlayerDeath", "nyrp.inv.bag", function(ply) ply:SetNW2Bool("nyrp.bagOpen", false) end)

-- Показать удостоверение игроку перед собой (он узнаёт ваше имя).
net.Receive("nyrp.inv.view", function(_, ply)
	if limited(ply) then return end
	local slot = net.ReadUInt(8)
	local it = Inv.Get(ply).slots[slot]
	if not it or it.id ~= "idcard" then return end
	local tr = ply:GetEyeTrace()
	local target = tr.Entity
	if not IsValid(target) or not target:IsPlayer() or target:GetPos():Distance(ply:GetPos()) > 140 then
		NYRP.Notify(ply, "Посмотрите на человека рядом, чтобы показать удостоверение", "warning")
		return
	end
	NYRP.OfferID(ply, target, it)
end)

-- ----------------------------------------------------------- админ-команды --
concommand.Add("nyrp_giveitem", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local target = IsValid(ply) and ply or nil
	if not target or not Items.Get(args[1] or "") then
		print("nyrp_giveitem <id> [кол-во]. Предметы: " .. table.concat(table.GetKeys(Items.List), ", "))
		return
	end
	local n = Inv.Add(target, args[1], tonumber(args[2]) or 1)
	NYRP.Notify(target, "Выдано: " .. Items.Get(args[1]).name .. " ×" .. n, "item")
end)

concommand.Add("nyrp_spawnitem", function(ply, _, args)
	if not IsValid(ply) or not ply:IsSuperAdmin() or not Items.Get(args[1] or "") then return end
	local tr = ply:GetEyeTrace()
	local ent = ents.Create("nyrp_item")
	ent:SetPos(tr.HitPos + tr.HitNormal * 10)
	ent:SetItem(args[1], tonumber(args[2]) or 1)
	ent:Spawn()
	undo.Create("Предмет")
	undo.AddEntity(ent)
	undo.SetPlayer(ply)
	undo.Finish()
end)

-- Тестовый набор для проверки инвентаря.
concommand.Add("nyrp_testkit", function(ply)
	if not IsValid(ply) or not ply:IsSuperAdmin() then return end
	for _, id in ipairs({ "water", "soda", "takeout", "medkit", "cap", "sunglasses", "mask", "tshirt", "jacket", "gloves", "jeans", "sneakers", "pistol", "smg", "crowbar" }) do
		Inv.Add(ply, id, 1)
	end
	NYRP.Notify(ply, "Тестовый набор выдан", "item")
end)
