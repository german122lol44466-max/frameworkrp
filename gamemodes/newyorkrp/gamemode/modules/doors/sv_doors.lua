--[[
	Аренда дверей (квартиры, офисы, гаражи).
	Админ: смотрите на дверь и пишите в чат
	  /doorownable <цена в день> [название]   — сдать дверь в аренду (повторно — изменить);
	  /doorownable off                         — снять с аренды.
	Игрок арендует через телефон (приложение «NY Homes»): первая оплата сразу, дальше — каждую игровую
	полночь со счёта банка его карты. Не хватило денег — аренда прекращается.
	Ключи забирают из почтового ящика (nyrp_mailbox); ЛКМ ключами по двери — запереть/отпереть.
	F1, глядя на свою дверь, — меню квартиры: жильцы (у них тоже работают ключи), добавить/выселить.
	Данные: data/nyrp/doors_<карта>.json (по MapCreationID двери).
]]

NYRP.Doors = NYRP.Doors or {}
local D = NYRP.Doors
local B = NYRP.Bank

local DOOR_CLASSES = { prop_door_rotating = true, func_door = true, func_door_rotating = true }
D.Data = D.Data or {}

local function path() return "nyrp/doors_" .. game.GetMap() .. ".json" end
local function today() return NYRP.Phone and NYRP.Phone.DayIndex() or 0 end

function D.Save()
	file.CreateDir("nyrp")
	file.Write(path(), util.TableToJSON(D.Data, true))
end

local function doorById(id)
	local e = ents.GetMapCreatedEntity(tonumber(id) or -1)
	return IsValid(e) and e or nil
end

local function idOf(ent)
	if not IsValid(ent) or not DOOR_CLASSES[ent:GetClass()] then return end
	local id = ent:CreatedByMap() and ent:MapCreationID() or -1
	if id < 0 then return end
	return tostring(id)
end
D.IdOf = function(ent) local id = idOf(ent) return id and D.Data[id] and id or nil end

local function charId(ply) return ply.nyrpChar and ply.nyrpChar.id end

-- арендатор или жилец
function D.HasAccess(ply, id)
	local d = D.Data[id]
	local me = charId(ply)
	if not d or not me or not d.owner then return false end
	return d.owner == me or (d.residents and d.residents[tostring(me)] ~= nil) or false
end

function D.IsLocked(id) return D.Data[id] and D.Data[id].locked or false end

-- двери, к которым у персонажа есть доступ
function D.AccessList(ply)
	local out = {}
	for id in pairs(D.Data) do
		if D.HasAccess(ply, id) then out[#out + 1] = id end
	end
	return out
end

-- состояние двери -> NW2 (видно игрокам рядом) и замок
local function apply(id)
	local e = doorById(id)
	local d = D.Data[id]
	if not e then return end
	if not d then
		e:SetNW2Int("nyrp.rent", 0)
		e:SetNW2String("nyrp.rentName", "")
		e:SetNW2Int("nyrp.rentOwner", 0)
		e:SetNW2String("nyrp.rentOwnerName", "")
		return
	end
	e:SetNW2Int("nyrp.rent", d.price)
	e:SetNW2String("nyrp.rentName", d.name or "")
	e:SetNW2Int("nyrp.rentOwner", d.owner or 0)
	e:SetNW2String("nyrp.rentOwnerName", d.ownerName or "")
	e:SetNW2Bool("nyrp.locked", d.locked and true or false)
	e:SetNW2Bool("nyrp.business", d.business and true or false)
	e:SetNW2Bool("nyrp.bizOpen", d.bizOpen and true or false)
	e:SetNW2String("nyrp.bizType", d.bizType or "")
	local res = {}
	for cid in pairs(d.residents or {}) do res[#res + 1] = cid end
	e:SetNW2String("nyrp.residents", table.concat(res, ","))
	e:Fire(d.locked and "Lock" or "Unlock")
end

local function load()
	D.Data = util.JSONToTable(file.Read(path(), "DATA") or "") or {}
	for id in pairs(D.Data) do apply(id) end
end
hook.Add("InitPostEntity", "nyrp.doors", load)
hook.Add("PostCleanupMap", "nyrp.doors", load)

local function charOnline(charId)
	for _, p in ipairs(player.GetAll()) do
		if p.nyrpChar and p.nyrpChar.id == charId then return p end
	end
end

local function evict(id, why)
	local d = D.Data[id]
	if not d then return end
	local owner = d.owner and charOnline(d.owner)
	d.owner, d.ownerName, d.ownerKey, d.bank, d.paidUntil, d.locked, d.residents = nil, nil, nil, nil, nil, false, nil
	d.bizOpen, d.bizName, d.bizType = nil, nil, nil
	D.Save()
	apply(id)
	if IsValid(owner) then NYRP.Notify(owner, "Аренда «" .. (d.name or "помещение") .. "» прекращена: " .. why, "warning", 8) end
end

-- списать аренду за дни до сегодняшнего (включительно)
local function settle(id, ply)
	local d = D.Data[id]
	if not d or not d.owner then return end
	local days = today() - (d.paidUntil or today())
	if days <= 0 then return end
	local total = days * d.price
	if not B.Add(ply, d.bank, -total, "Аренда «" .. (d.name or "помещение") .. "»" .. (days > 1 and (" ×" .. days) or "")) then
		evict(id, "на счёте " .. (B.Banks[d.bank] and B.Banks[d.bank].name or "") .. " не хватило " .. NYRP.Money.Format(total))
		return
	end
	d.paidUntil = today()
	D.Save()
	NYRP.Notify(ply, "Списана аренда «" .. (d.name or "помещение") .. "»: " .. NYRP.Money.Format(total), "item", 5)
end

hook.Add("NYRP.NewDay", "nyrp.doors", function()
	for id, d in pairs(D.Data) do
		local p = d.owner and charOnline(d.owner)
		if p then settle(id, p) end
	end
end)

-- персонаж вошёл — рассчитываемся за пропущенные дни
hook.Add("NYRP.CharInventoryReady", "nyrp.doors", function(ply, c)
	for id, d in pairs(D.Data) do
		if d.owner == c.id then settle(id, ply) end
	end
end)

-- -------------------------------------------------------------- команды --
local function lookDoor(ply)
	local e = ply:GetEyeTrace().Entity
	if IsValid(e) and e:GetPos():Distance(ply:GetPos()) < 200 then return e, idOf(e) end
end

NYRP.Chat.AddCommand("/doorownable", function(ply, raw)
	if not ply:IsAdmin() then NYRP.Notify(ply, "Только для администрации", "error") return end
	local e, id = lookDoor(ply)
	if not id then NYRP.Notify(ply, "Посмотрите на дверь карты (вблизи)", "warning") return end
	local arg, rest = string.match(raw, "^%S+%s*(%S*)%s*(.*)$")
	if arg == "off" then
		D.Data[id] = nil
		D.Save()
		apply(id)
		NYRP.Notify(ply, "Дверь больше не сдаётся", "success")
		return
	end
	local price = math.floor(tonumber(arg) or 50)
	local d = D.Data[id] or {}
	d.price = math.Clamp(price, 1, 100000)
	d.name = rest ~= "" and string.sub(rest, 1, 40) or d.name or ("Помещение №" .. id)
	local p = e:GetPos()
	d.pos = { math.floor(p.x), math.floor(p.y), math.floor(p.z) }
	D.Data[id] = d
	D.Save()
	apply(id)
	NYRP.Notify(ply, "«" .. d.name .. "» сдаётся за " .. NYRP.Money.Format(d.price) .. " в день. Снять можно через телефон: NY Homes.", "success", 7)
end)

function D.SetLocked(ply, id, lock)
	local d = D.Data[id]
	if not d or not D.HasAccess(ply, id) then NYRP.Notify(ply, "Это не ваше помещение", "error") return end
	d.locked = lock
	D.Save()
	apply(id)
	local e = doorById(id)
	if IsValid(e) then
		e:EmitSound("nyrp/fx/lock_turn.wav", 60, math.random(96, 104))
		e:EmitSound(lock and "doors/door_latch1.wav" or "doors/door_latch3.wav", 55)
	end
	NYRP.Notify(ply, lock and "Дверь заперта" or "Дверь отперта", "success", 3)
end
local setLock = D.SetLocked

-- -------------------------------------------------------- F1: жильцы квартиры --
local function residentsOf(id)
	local d = D.Data[id]
	local list = {}
	for cid, name in pairs(d and d.residents or {}) do list[#list + 1] = { id = cid, name = name } end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

local function sendHome(ply, id)
	local d = D.Data[id]
	local near = {}
	for _, p in ipairs(player.GetAll()) do
		if p ~= ply and NYRP.HasCharacter(p) and p:GetPos():Distance(ply:GetPos()) < 300 then
			local cid = tostring(charId(p))
			if not (d.residents and d.residents[cid]) then near[#near + 1] = p end
		end
	end
	net.Start("nyrp.door.home")
	net.WriteString(id)
	net.WriteString(d.name or "")
	net.WriteBool(d.locked and true or false)
	net.WriteTable(residentsOf(id))
	net.WriteUInt(#near, 8)
	for _, p in ipairs(near) do net.WriteEntity(p) end
	net.WriteBool(d.business and true or false)
	net.WriteBool(d.bizOpen and true or false)
	net.Send(ply)
end
D.SendHome = sendHome
D.Apply = function(id) apply(id) end
D.DoorById = doorById

hook.Add("ShowHelp", "nyrp.doors", function(ply)
	local e, id = lookDoor(ply)
	if not id or not D.Data[id] then return end
	local d = D.Data[id]
	if d.owner ~= charId(ply) then
		if D.HasAccess(ply, id) then NYRP.Notify(ply, "Вы живёте здесь. Управляет квартирой арендатор: " .. (d.ownerName or "?"), "info", 4) end
		return
	end
	sendHome(ply, id)
	return true
end)

net.Receive("nyrp.door.resident", function(_, ply)
	if (ply.nyrpDoorNext or 0) > CurTime() then return end
	ply.nyrpDoorNext = CurTime() + 0.3
	local id, add, target, cid = net.ReadString(), net.ReadBool(), net.ReadEntity(), net.ReadString()
	local d = D.Data[id]
	if not d or d.owner ~= charId(ply) then return end
	d.residents = d.residents or {}
	if add then
		if not IsValid(target) or not target:IsPlayer() or not NYRP.HasCharacter(target) or target:GetPos():Distance(ply:GetPos()) > 300 then return end
		local tid = tostring(charId(target))
		if table.Count(d.residents) >= 6 then NYRP.Notify(ply, "Не больше 6 жильцов", "warning") return end
		d.residents[tid] = target.nyrpChar.name
		NYRP.Notify(ply, "Жилец добавлен: " .. target.nyrpChar.name, "success")
		NYRP.Notify(target, "Вас поселили в «" .. (d.name or "квартиру") .. "». Ключи — в почтовом ящике дома.", "success", 8)
	else
		local name = d.residents[cid]
		d.residents[cid] = nil
		if name then NYRP.Notify(ply, "Жилец выселен: " .. name, "success") end
	end
	D.Save()
	apply(id)
	sendHome(ply, id)
end)

-- ----------------------------------------------------------- телефон: NY Homes --
local function sendList(ply)
	local me = ply.nyrpChar and ply.nyrpChar.id
	local list = {}
	for id, d in pairs(D.Data) do
		local e = doorById(id)
		local mine = me ~= nil and (d.owner == me or (d.residents and d.residents[tostring(me)] ~= nil)) or false
		if not d.business or mine then
			list[#list + 1] = { id = id, name = d.business and (d.bizName or d.name) or d.name, price = d.price, rented = d.owner ~= nil, mine = mine,
				locked = d.locked and true or false, bank = d.bank, dist = IsValid(e) and math.floor(e:GetPos():Distance(ply:GetPos()) / 52) or nil }
		end
	end
	table.sort(list, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
	net.Start("nyrp.door.list")
	net.WriteTable(list)
	net.Send(ply)
end

net.Receive("nyrp.door.list", function(_, ply)
	if (ply.nyrpDoorNext or 0) > CurTime() then return end
	ply.nyrpDoorNext = CurTime() + 0.5
	sendList(ply)
end)

net.Receive("nyrp.door.rent", function(_, ply)
	if (ply.nyrpDoorNext or 0) > CurTime() then return end
	ply.nyrpDoorNext = CurTime() + 0.5
	local id = net.ReadString()
	local d = D.Data[id]
	if not d or not NYRP.HasCharacter(ply) then return end
	if d.owner then NYRP.Notify(ply, "Это помещение уже арендовано", "warning") sendList(ply) return end
	if d.business then NYRP.Notify(ply, "Это коммерческое помещение: оформляется в ратуше по лицензии", "warning", 6) return end
	local card = B.FindCard(ply)
	if not card then NYRP.Notify(ply, "Для оплаты аренды нужна банковская карта", "error") return end
	local bank = card.data.bank
	if not B.Add(ply, bank, -d.price, "Аренда «" .. d.name .. "» (первый день)") then
		NYRP.Notify(ply, "Недостаточно средств на карте " .. B.Banks[bank].name, "error")
		return
	end
	d.owner = ply.nyrpChar.id
	d.ownerName = ply.nyrpChar.name
	d.ownerKey = NYRP.Chars.Key(ply)
	d.bank = bank
	d.paidUntil = today()
	d.locked = false
	D.Save()
	apply(id)
	NYRP.Notify(ply, "Вы арендовали «" .. d.name .. "». Каждый день в полночь спишется " .. NYRP.Money.Format(d.price) .. " с карты " .. B.Banks[bank].name .. ".", "success", 8)
	NYRP.Notify(ply, "Ключи ждут вас в почтовом ящике дома (E по ящику).", "info", 10)
	D.Mark(ply, id)
	sendList(ply)
end)

net.Receive("nyrp.door.act", function(_, ply)
	if (ply.nyrpDoorNext or 0) > CurTime() then return end
	ply.nyrpDoorNext = CurTime() + 0.3
	local id, act = net.ReadString(), net.ReadString()
	local d = D.Data[id]
	if not d or not D.HasAccess(ply, id) then return end
	if act == "lock" or act == "unlock" then
		setLock(ply, id, act == "lock")
	elseif act == "mark" then
		D.Mark(ply, id)
	elseif act == "end" and d.owner == charId(ply) then
		evict(id, "вы отказались от аренды")
	end
	sendList(ply)
end)

-- метка на карте до помещения
function D.Mark(ply, id)
	local d = D.Data[id]
	local e = doorById(id)
	local pos = IsValid(e) and e:WorldSpaceCenter() or (d and d.pos and Vector(d.pos[1], d.pos[2], d.pos[3]))
	if not pos or not NYRP.Waypoint then return end
	NYRP.Waypoint.Set(ply, "home_" .. id, pos, d.business and (d.bizName or d.name or "Ваш бизнес") or (d.name or "Ваша квартира"),
		d.business and "store" or "home", d.business and Color(240, 160, 60) or Color(90, 200, 140), { radius = 110 })
end

-- коммерческие помещения: /doorbusiness <цена в день> [название] — сдаётся только по лицензии ратуши
NYRP.Chat.AddCommand("/doorbusiness", function(ply, raw)
	if not ply:IsAdmin() then NYRP.Notify(ply, "Только для администрации", "error") return end
	local e, id = lookDoor(ply)
	if not id then NYRP.Notify(ply, "Посмотрите на дверь карты (вблизи)", "warning") return end
	local arg, rest = string.match(raw, "^%S+%s*(%S*)%s*(.*)$")
	if arg == "off" then
		D.Data[id] = nil D.Save() apply(id)
		NYRP.Notify(ply, "Помещение больше не коммерческое", "success")
		return
	end
	local d = D.Data[id] or {}
	d.price = math.Clamp(math.floor(tonumber(arg) or 120), 1, 100000)
	d.name = rest ~= "" and string.sub(rest, 1, 40) or d.name or ("Помещение №" .. id)
	d.business = true
	local p = e:GetPos()
	d.pos = { math.floor(p.x), math.floor(p.y), math.floor(p.z) }
	D.Data[id] = d
	D.Save()
	apply(id)
	NYRP.Notify(ply, "Коммерческое помещение «" .. d.name .. "»: " .. NYRP.Money.Format(d.price) .. " в день, оформляется в ратуше", "success", 7)
end)
