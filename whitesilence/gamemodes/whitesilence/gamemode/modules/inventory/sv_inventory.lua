--[[
	Инвентарь на сервере: рюкзак игрока, применение предметов, патроны из коробок, кровотечение, лут.

	• Перезарядка оружия списывает патроны из коробок (сверка раз в 0.2 с: сколько у оружия в запасе
	  против того, сколько в коробках); пустые коробки исчезают.
	• Применение занимает время (use), в это время боец идёт медленно и опускает оружие; урон не прерывает.
	• Пули и осколки вызывают кровотечение (до 3 степеней): −1 HP каждые 4/степень секунды, бинт и аптечка
	  останавливают. Промедол снимает «боль» (меньше трясёт, быстрее выносливость).
	• Погибший роняет патроны и аптечки рядом с телом; вернувшийся на чекпоинте получает новый набор.
]]

local I = WS.Inv
local L = WS.Lobby
local C = WS.Config

for _, n in ipairs({ "ws.inv", "ws.inv.use", "ws.inv.quick", "ws.inv.move", "ws.inv.drop", "ws.inv.notify", "ws.hand", "ws.inv.battery" }) do
	util.AddNetworkString(n)
end

local function list(ply)
	ply.wsInv = ply.wsInv or {}
	return ply.wsInv
end
I.List = list

local function nextUid(ply)
	ply.wsInvUid = (ply.wsInvUid or 0) + 1
	return ply.wsInvUid
end

function I.Sync(ply)
	local l = list(ply)
	net.Start("ws.inv")
	net.WriteUInt(#l, 6)
	for _, it in ipairs(l) do
		net.WriteUInt(it.uid, 16)
		net.WriteString(it.id)
		net.WriteUInt(it.x, 4)
		net.WriteUInt(it.y, 4)
		net.WriteBool(it.rot or false)
		net.WriteUInt(it.count or 1, 10)
		net.WriteUInt(it.charges or 0, 4)
	end
	net.Send(ply)
	ply:SetNW2Float("ws_weight", I.TotalWeight(l))
end

local function notify(ply, text)
	net.Start("ws.inv.notify")
	net.WriteString(text)
	net.Send(ply)
end
I.Notify = notify

-- Положить в рюкзак: сначала докладывает в неполные стопки/коробки. Возвращает, сколько не влезло.
function I.Add(ply, id, count, charges, silent)
	local d = I.Def(id)
	if not d then return count end
	local l = list(ply)
	count = count or 1
	local cap = d.ammo and d.max or (d.stack or 1)
	-- вес: сколько ещё можно взять
	local free = I.CarryMax - I.TotalWeight(l)
	local per = d.ammo and d.weight or d.weight
	local canW = math.floor(free / math.max(per, 0.001))
	if canW <= 0 then if not silent then notify(ply, "Слишком тяжело") end return count end
	local left = math.min(count, canW)
	local overflow = count - left
	for _, it in ipairs(l) do
		if left <= 0 then break end
		if it.id == id and not d.charges and (it.count or 1) < cap then
			local add = math.min(cap - it.count, left)
			it.count = it.count + add
			left = left - add
		end
	end
	while left > 0 do
		local x, y, rot = I.FindSpot(l, id)
		if not x then break end
		local n = math.min(cap, left)
		l[#l + 1] = { uid = nextUid(ply), id = id, x = x, y = y, rot = rot, count = n, charges = charges or d.charges }
		left = left - n
	end
	if left > 0 and not silent then notify(ply, "Нет места в рюкзаке") end
	I.SyncAmmo(ply, true)
	I.Sync(ply)
	return left + overflow
end

function I.Remove(ply, it, n)
	local l = list(ply)
	n = n or 1
	it.count = (it.count or 1) - n
	if it.count <= 0 then
		for i, x in ipairs(l) do if x == it then table.remove(l, i) break end end
	end
end

function I.Find(ply, uid)
	for _, it in ipairs(list(ply)) do if it.uid == uid then return it end end
end

function I.Clear(ply)
	ply.wsInv = {}
	ply.wsAmmoLast = {}
	I.Sync(ply)
end

function I.GiveKit(ply)
	ply.wsInv = {}
	for _, k in ipairs(I.StartKit) do I.Add(ply, k[1], k[2], nil, true) end
	for _, k in ipairs(hook.Run("WSExtraKit", ply) or {}) do I.Add(ply, k[1], k[2], nil, true) end
	I.SyncAmmo(ply, true)
	I.Sync(ply)
end

-- ---------------------------------------------------------------- патроны: коробки ↔ запас оружия

local function ammoTypeOf(kind)
	local cls = C.SquadWeapons[kind]
	local st = cls and weapons.GetStored(cls)
	local name = st and st.Primary and st.Primary.Ammo
	if not name or name == "" or name == "none" then name = kind == 1 and "ar2" or "pistol" end
	return game.GetAmmoID(name), name
end

-- force — выставить запас по коробкам (после изменения инвентаря); иначе — списать израсходованное
function I.SyncAmmo(ply, force)
	ply.wsAmmoLast = ply.wsAmmoLast or {}
	local l = list(ply)
	local changed = false
	for kind = 1, 2 do
		local tid = ammoTypeOf(kind)
		if tid and tid >= 0 then
			local have = ply:GetAmmoCount(tid)
			local last = ply.wsAmmoLast[kind]
			if not force and last and have < last then
				-- израсходовано (перезарядка): списать из самых пустых коробок
				local spend = last - have
				local boxes = {}
				for _, it in ipairs(l) do if I.Def(it.id).ammo == kind then boxes[#boxes + 1] = it end end
				table.sort(boxes, function(a, b) return a.count < b.count end)
				for _, it in ipairs(boxes) do
					if spend <= 0 then break end
					local take = math.min(it.count, spend)
					spend = spend - take
					I.Remove(ply, it, take)
				end
				changed = true
			end
			local total = I.CountAmmo(l, kind)
			if have ~= total then ply:SetAmmo(total, tid) end
			ply.wsAmmoLast[kind] = total
		end
	end
	if changed then I.Sync(ply) end
end

-- ---------------------------------------------------------------- применение

local function stopBleed(p) p:SetNW2Int("ws_bleed", 0) end

local function apply(ply, it, target)
	local d = I.Def(it.id)
	local who = IsValid(target) and target or ply
	local wasBleeding = who:GetNW2Int("ws_bleed", 0) > 0
	if d.heal then who:SetHealth(math.min(who:GetMaxHealth(), who:Health() + d.heal)) end
	if d.stopBleed then stopBleed(who) end
	if d.pain then who:SetNW2Float("ws_pain_until", CurTime() + d.pain) end
	if d.battery then net.Start("ws.inv.battery") net.Send(ply) end
	if d.charges then
		it.charges = (it.charges or d.charges) - 1
		if it.charges <= 0 then I.Remove(ply, it, it.count or 1) end
	else
		I.Remove(ply, it, 1)
	end
	hook.Run("WSItemUsed", ply, it.id, who, wasBleeding and d.stopBleed)
	ply:EmitSound(d.battery and "items/battery_pickup.wav" or "items/medshot4.wav", 60, 100)
	I.Sync(ply)
end

local function startUse(ply, it, target)
	if not ply:Alive() or not L.InGame(ply) then return end
	if ply.wsUsing then return end
	local d = I.Def(it.id)
	if not d.use then return end
	-- на ком применять: аптечку — на товарища, на которого смотришь вплотную
	if d.other and not IsValid(target) then
		local tr = ply:GetEyeTrace()
		if IsValid(tr.Entity) and tr.Entity:IsPlayer() and tr.Entity:Alive() and tr.HitPos:Distance(ply:EyePos()) < 90 then target = tr.Entity end
	end
	if d.heal and not d.stopBleed and not d.pain and (IsValid(target) and target or ply):Health() >= ply:GetMaxHealth() then return end
	local dur = d.use
	ply.wsUsing = { uid = it.uid, t1 = CurTime() + dur, target = target }
	ply:SetNW2Float("ws_using_until", CurTime() + dur)
	ply:SetNW2Float("ws_using_dur", dur)
	ply:SetNW2String("ws_using_item", it.id)
	net.Start("ws.hand")
	net.WriteString("use")
	net.WriteVector(Vector())
	net.WriteFloat(dur)
	net.Send(ply)
end

net.Receive("ws.inv.use", function(_, ply)
	local it = I.Find(ply, net.ReadUInt(16))
	if it then startUse(ply, it) end
end)

net.Receive("ws.inv.quick", function(_, ply)
	local key = net.ReadUInt(4)
	local it = I.ByQuick(list(ply), key)
	if it then startUse(ply, it) else notify(ply, "Нет предмета") end
end)

net.Receive("ws.inv.move", function(_, ply)
	local it = I.Find(ply, net.ReadUInt(16))
	local x, y, rot = net.ReadUInt(4), net.ReadUInt(4), net.ReadBool()
	if not it or ply.wsUsing then return end
	local old = it.rot
	it.rot = rot
	local w, h = I.Size(it)
	if I.Fits(list(ply), x, y, w, h, it) then
		it.x, it.y = x, y
	else
		it.rot = old
	end
	I.Sync(ply)
end)

function I.DropItem(ply, it, pos)
	local e = ents.Create("ws_item")
	if not IsValid(e) then return end
	e:SetItemId(it.id)
	e:SetCount(it.count or 1)
	e:SetCharges(it.charges or 0)
	e:SetPos(pos)
	e:SetAngles(Angle(0, math.random(0, 359), 0))
	e:Spawn()
	return e
end

net.Receive("ws.inv.drop", function(_, ply)
	local it = I.Find(ply, net.ReadUInt(16))
	if not it or ply.wsUsing or not ply:Alive() then return end
	local pos = ply:EyePos() + ply:GetAimVector() * 30
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = pos, filter = ply })
	I.DropItem(ply, it, tr.HitPos - ply:GetAimVector() * 6)
	I.Remove(ply, it, it.count or 1)
	I.SyncAmmo(ply, true)
	I.Sync(ply)
end)

-- Подобрать предмет с земли (ws_item:Use)
function I.Pickup(ply, ent)
	if not ply:Alive() or not L.InGame(ply) or ply.wsUsing then return end
	local id, n = ent:GetItemId(), ent:GetCount()
	local d = I.Def(id)
	if not d then return end
	local left = I.Add(ply, id, n, ent:GetCharges() > 0 and ent:GetCharges() or nil)
	if left >= n then return end
	ply:EmitSound("items/ammo_pickup.wav", 55, math.random(95, 105))
	net.Start("ws.hand")
	net.WriteString("pickup")
	net.WriteVector(ent:WorldSpaceCenter())
	net.WriteFloat(0.9)
	net.Send(ply)
	hook.Run("WSItemPicked", ply, id, n - left)
	if left > 0 then ent:SetCount(left) else ent:Remove() end
end

-- ---------------------------------------------------------------- ход времени

local nextTick = 0
hook.Add("Think", "ws.inv", function()
	local now = CurTime()
	if now < nextTick then return end
	nextTick = now + 0.2
	for _, ply in ipairs(player.GetAll()) do
		if L.InGame(ply) and ply:Alive() then
			I.SyncAmmo(ply)
			-- применение предмета
			local u = ply.wsUsing
			if u and now >= u.t1 then
				ply.wsUsing = nil
				ply:SetNW2Float("ws_using_until", 0)
				local it = I.Find(ply, u.uid)
				if it and (not IsValid(u.target) or (u.target:Alive() and u.target:GetPos():Distance(ply:GetPos()) < 130)) then
					apply(ply, it, u.target)
				end
			end
			-- кровотечение
			local b = ply:GetNW2Int("ws_bleed", 0)
			if b > 0 and now >= (ply.wsNextBleed or 0) then
				ply.wsNextBleed = now + 4 / b
				if ply:Health() <= 1 then
					ply.wsBleedDeath = true
					ply:Kill()
				else
					ply:SetHealth(ply:Health() - 1)
				end
			end
		elseif ply.wsUsing then
			ply.wsUsing = nil
			ply:SetNW2Float("ws_using_until", 0)
		end
	end
end)

hook.Add("EntityTakeDamage", "ws.inv.bleed", function(ent, dmg)
	if not ent:IsPlayer() or not L.InGame(ent) then return end
	if bit.band(dmg:GetDamageType(), bit.bor(DMG_BULLET, DMG_BLAST, DMG_SLASH, DMG_BUCKSHOT)) == 0 then return end
	if dmg:GetDamage() < 7 then return end
	local pain = ent:GetNW2Float("ws_pain_until", 0) > CurTime()
	if math.random() < (pain and 0.3 or 0.45) then
		ent:SetNW2Int("ws_bleed", math.min(3, ent:GetNW2Int("ws_bleed", 0) + 1))
		ent.wsNextBleed = CurTime() + 2
	end
end)

-- выход в игру — набор; возвращение на чекпоинте — новый набор; гибель — патроны и аптечки рядом с телом
hook.Add("WSSquadDeployed", "ws.inv", function(members)
	for _, p in ipairs(members) do if IsValid(p) then I.GiveKit(p) end end
end)
hook.Add("WSRevived", "ws.inv", function(ply) I.GiveKit(ply) end)

hook.Add("PlayerDeath", "ws.inv", function(ply)
	ply:SetNW2Int("ws_bleed", 0)
	ply:SetNW2Float("ws_pain_until", 0)
	ply.wsUsing = nil
	ply:SetNW2Float("ws_using_until", 0)
	if not L.InGame(ply) then return end
	local drops = 0
	for _, it in ipairs(table.Copy(list(ply))) do
		local d = I.Def(it.id)
		if drops < 4 and (d.ammo or d.heal) then
			drops = drops + 1
			I.DropItem(ply, it, ply:GetPos() + Vector(math.Rand(-30, 30), math.Rand(-30, 30), 20))
		end
	end
	I.Clear(ply)
end)

hook.Add("PlayerSpawn", "ws.inv", function(ply)
	if not L.InGame(ply) then ply.wsInv = {} end
	ply:SetNW2Int("ws_bleed", 0)
end)

-- лут с врагов
hook.Add("WSEnemyKilled", "ws.inv", function(enemy)
	local pos = enemy:GetPos() + Vector(0, 0, 24)
	for _, l in ipairs(I.Loot) do
		if math.random() < l[1] then
			local e = ents.Create("ws_item")
			if IsValid(e) then
				e:SetItemId(l[2])
				e:SetCount(math.random(l[3], l[4]))
				e:SetPos(pos + Vector(math.Rand(-16, 16), math.Rand(-16, 16), 0))
				e:Spawn()
				SafeRemoveEntityDelayed(e, 300)
			end
		end
	end
end)

concommand.Add("ws_give", function(ply, _, args)
	if not IsValid(ply) or not ply:IsSuperAdmin() then return end
	I.Add(ply, args[1] or "bandage", tonumber(args[2] or "1") or 1)
end)
