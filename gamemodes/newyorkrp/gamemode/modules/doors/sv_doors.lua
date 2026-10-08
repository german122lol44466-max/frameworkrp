--[[
	Аренда дверей (квартиры, офисы, гаражи).
	Админ: смотрите на дверь и пишите в чат
	  /doorownable <цена в день> [название]   — сдать дверь в аренду (повторно — изменить);
	  /doorownable off                         — снять с аренды.
	Игрок арендует через телефон (приложение «NY Homes»): первая оплата сразу, дальше — каждую игровую
	полночь со счёта банка его карты. Не хватило денег — аренда прекращается.
	Владелец: /lock, /unlock (смотря на дверь) или кнопки в приложении.
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
	d.owner, d.ownerName, d.ownerKey, d.bank, d.paidUntil, d.locked = nil, nil, nil, nil, nil, false
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

local function setLock(ply, id, lock)
	local d = D.Data[id]
	if not d or d.owner ~= (ply.nyrpChar and ply.nyrpChar.id) then NYRP.Notify(ply, "Это не ваше помещение", "error") return end
	d.locked = lock
	D.Save()
	apply(id)
	local e = doorById(id)
	if IsValid(e) then e:EmitSound(lock and "doors/door_latch1.wav" or "doors/door_latch3.wav", 60) end
	NYRP.Notify(ply, lock and "Дверь заперта" or "Дверь открыта", "success", 3)
end

NYRP.Chat.AddCommand("/lock", function(ply) local _, id = lookDoor(ply) if id then setLock(ply, id, true) end end)
NYRP.Chat.AddCommand("/unlock", function(ply) local _, id = lookDoor(ply) if id then setLock(ply, id, false) end end)

-- ----------------------------------------------------------- телефон: NY Homes --
local function sendList(ply)
	local me = ply.nyrpChar and ply.nyrpChar.id
	local list = {}
	for id, d in pairs(D.Data) do
		local e = doorById(id)
		list[#list + 1] = { id = id, name = d.name, price = d.price, rented = d.owner ~= nil, mine = d.owner == me and me ~= nil,
			locked = d.locked and true or false, bank = d.bank, dist = IsValid(e) and math.floor(e:GetPos():Distance(ply:GetPos()) / 52) or nil }
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
	sendList(ply)
end)

net.Receive("nyrp.door.act", function(_, ply)
	if (ply.nyrpDoorNext or 0) > CurTime() then return end
	ply.nyrpDoorNext = CurTime() + 0.3
	local id, act = net.ReadString(), net.ReadString()
	local d = D.Data[id]
	if not d or d.owner ~= (ply.nyrpChar and ply.nyrpChar.id) then return end
	if act == "lock" or act == "unlock" then
		setLock(ply, id, act == "lock")
	elseif act == "end" then
		evict(id, "вы отказались от аренды")
	end
	sendList(ply)
end)
