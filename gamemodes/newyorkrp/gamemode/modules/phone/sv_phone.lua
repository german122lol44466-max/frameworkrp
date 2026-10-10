--[[
	Телефон на сервере: выдача, SIM-карта, данные приложений, звонки (голос между собеседниками на любом
	расстоянии), будильники, банки, игровая дата.
]]

local P = NYRP.Phone
local Items = NYRP.Items
local Inv = NYRP.Inv

local AREAS = { "212", "347", "646", "718", "917" }

local function newNumber()
	return AREAS[math.random(#AREAS)] .. "555" .. string.format("%04d", math.random(0, 9999))
end

local function newSerial()
	return string.format("%08x", math.random(0, 0x7fffffff))
end

local function phoneData()
	return { serial = newSerial(), contacts = {}, notes = {}, alarms = {}, events = {}, apps = {}, recents = {},
		settings = { wall = 1, ring = 1, alarm = 1 } }
end

-- Номер → игрок (только у кого телефон в слоте и вставлена SIM)
local function findByNumber(number)
	number = P.Digits(number)
	if number == "" then return end
	for _, p in ipairs(player.GetAll()) do
		if NYRP.HasCharacter(p) and P.Digits(P.Number(p)) == number then return p end
	end
end

-- ---------------------------------------------------------------- выдача --
hook.Add("NYRP.CharInventoryReady", "nyrp.phone", function(ply, c)
	c.flags = c.flags or {}
	if c.flags.phoneIssued then return end
	c.flags.phoneIssued = true
	Inv.Add(ply, "phone", 1, phoneData())
	Inv.Add(ply, "simcard", 1, { number = newNumber() })
	NYRP.Notify(ply, "Вам выданы смартфон и SIM-карта. Перетащите SIM-карту на телефон, затем возьмите его в руки.", "item", 9)
end)

-- Предмет телефона без данных (выдан админом) — достраиваем
local function ensure(it)
	it.data = it.data or {}
	if not it.data.serial then table.Merge(it.data, phoneData()) end
	it.data.settings = it.data.settings or { wall = 1, ring = 1, alarm = 1 }
	return it.data
end

-- -------------------------------------------------------------- SIM-карта --
local function insertSim(ply, simRef, phoneIt)
	local inv = Inv.Get(ply)
	local sim = inv.slots[simRef]
	local d = ensure(phoneIt)
	if d.sim then NYRP.Notify(ply, "В телефоне уже есть SIM-карта — сначала извлеките её", "warning") return end
	NYRP.Action(ply, "Вставляю SIM-карту...", 1.4, function()
		if inv.slots[simRef] ~= sim or d.sim then return end
		inv.slots[simRef] = nil
		d.sim = { number = (sim.data and sim.data.number) or newNumber() }
		ply:EmitSound("nyrp/phone/unlock.wav", 55)
		NYRP.Notify(ply, "SIM-карта вставлена. Ваш номер: " .. P.FormatNumber(d.sim.number), "item", 6)
		Inv.Sync(ply)
	end, "p_sim")
end

hook.Add("NYRP.InvMove", "nyrp.phone", function(ply, fk, fkey, tk, tkey)
	if fk ~= "inv" then return end
	local inv = Inv.Get(ply)
	local a = tonumber(fkey)
	local sim = a and inv.slots[a]
	if not sim or sim.id ~= "simcard" then return end
	local target
	if tk == "inv" then
		local b = tonumber(tkey)
		target = b and inv.slots[b]
	elseif tk == "eq" and tkey == "phone" then
		target = inv.equip.phone
	end
	if not target or target.id ~= "phone" then return end
	insertSim(ply, a, target)
	return true
end)

local hangup

net.Receive("nyrp.phone.eject", function(_, ply)
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return end
	local kind, key = net.ReadString(), net.ReadString()
	local inv = Inv.Get(ply)
	local it = kind == "eq" and inv.equip[key] or inv.slots[tonumber(key) or -1]
	if not it or it.id ~= "phone" or not it.data or not it.data.sim then return end
	if not Inv.FreeSlot(ply) then NYRP.Notify(ply, "В сумке нет места для SIM-карты", "error") return end
	NYRP.Action(ply, "Извлекаю SIM-карту...", 1.2, function()
		if not it.data.sim then return end
		local free = Inv.FreeSlot(ply)
		if not free then NYRP.Notify(ply, "В сумке нет места для SIM-карты", "error") return end
		if inv.equip.phone == it and ply.nyrpCall then hangup(ply) end
		inv.slots[free] = { id = "simcard", n = 1, data = { number = it.data.sim.number } }
		it.data.sim = nil
		ply:EmitSound("nyrp/phone/lock.wav", 55)
		Inv.Sync(ply)
	end, "p_sim")
end)

-- ------------------------------------------------------ данные приложений --
local LIMITS = { contacts = 60, notes = 40, alarms = 12, events = 60, recents = 30 }

local function cleanStr(s, n) return string.sub(tostring(s or ""), 1, n) end

local CLEAN = {
	contacts = function(v)
		local out = {}
		for i, c in ipairs(v) do
			if i > LIMITS.contacts then break end
			if type(c) == "table" then out[#out + 1] = { name = cleanStr(c.name, 40), number = P.Digits(c.number):sub(1, 12) } end
		end
		return out
	end,
	notes = function(v)
		local out = {}
		for i, n in ipairs(v) do
			if i > LIMITS.notes then break end
			if type(n) == "table" then out[#out + 1] = { title = cleanStr(n.title, 60), text = cleanStr(n.text, 2000), t = tonumber(n.t) or 0 } end
		end
		return out
	end,
	alarms = function(v)
		local out = {}
		for i, a in ipairs(v) do
			if i > LIMITS.alarms then break end
			if type(a) == "table" then
				out[#out + 1] = { h = math.Clamp(math.floor(tonumber(a.h) or 7), 0, 23), m = math.Clamp(math.floor(tonumber(a.m) or 0), 0, 59),
					on = a.on and true or false, label = cleanStr(a.label, 30) }
			end
		end
		return out
	end,
	events = function(v)
		local out = {}
		for i, e in ipairs(v) do
			if i > LIMITS.events then break end
			if type(e) == "table" then out[#out + 1] = { day = math.floor(tonumber(e.day) or 0), text = cleanStr(e.text, 120) } end
		end
		return out
	end,
	apps = function(v)
		local out = {}
		for id in pairs(v) do if P.StoreByID[id] then out[id] = true end end
		return out
	end,
	settings = function(v, old)
		local s = table.Copy(old or {})
		s.wall = math.Clamp(math.floor(tonumber(v.wall) or s.wall or 1), 1, #P.Walls)
		s.ring = math.Clamp(math.floor(tonumber(v.ring) or s.ring or 1), 1, #P.Rings)
		s.alarm = math.Clamp(math.floor(tonumber(v.alarm) or s.alarm or 1), 1, #P.Alarms)
		s.pin = v.pin and P.Digits(v.pin):sub(1, 6) or nil
		if s.pin == "" then s.pin = nil end
		s.face = tonumber(v.face) or nil
		s.games = {}
		for k, n in pairs(type(v.games) == "table" and v.games or {}) do
			if P.StoreByID[k] then s.games[k] = math.max(0, math.floor(tonumber(n) or 0)) end
		end
		return s
	end,
}

net.Receive("nyrp.phone.set", function(_, ply)
	if (ply.nyrpPhoneSet or 0) > CurTime() then return end
	ply.nyrpPhoneSet = CurTime() + 0.15
	local key, val = net.ReadString(), net.ReadTable()
	local it = P.Equipped(ply)
	if not it or not CLEAN[key] then return end
	local d = ensure(it)
	if key == "settings" and val.face and tonumber(val.face) ~= (ply.nyrpChar and ply.nyrpChar.id) then val.face = d.settings.face end
	d[key] = CLEAN[key](val, d[key])
	Inv.Sync(ply)
end)

local function addRecent(ply, number, dir, ok)
	local it = P.Equipped(ply)
	if not it then return end
	local d = ensure(it)
	table.insert(d.recents, 1, { number = number, dir = dir, ok = ok, t = P.DayIndex() * 1440 + math.floor(NYRP.Time.Hour() * 60) })
	while #d.recents > LIMITS.recents do table.remove(d.recents) end
	Inv.Sync(ply)
end

-- ------------------------------------------------------------------ звонки --
-- ply.nyrpCall = { peer, state = "dialing" | "ringing" | "active", out = исходящий?, start }
local function sendState(ply, state, number, start)
	net.Start("nyrp.phone.state")
	net.WriteString(state)
	net.WriteString(number or "")
	net.WriteFloat(start or 0)
	net.Send(ply)
end

local function stopRing(ply)
	if ply.nyrpRing then ply.nyrpRing:Stop() ply.nyrpRing = nil end
end

function hangup(ply, reason)
	local c = ply.nyrpCall
	if not c then return end
	local peer = c.peer
	ply.nyrpCall = nil
	stopRing(ply)
	timer.Remove("nyrp.phone.timeout." .. ply:EntIndex())
	local myNum, peerNum = P.Number(ply) or "", IsValid(peer) and P.Number(peer) or c.peerNumber or ""
	addRecent(ply, peerNum, c.out and "out" or "in", c.state == "active")
	sendState(ply, reason or "ended", peerNum)
	if IsValid(peer) and peer.nyrpCall and peer.nyrpCall.peer == ply then
		local pc = peer.nyrpCall
		peer.nyrpCall = nil
		stopRing(peer)
		timer.Remove("nyrp.phone.timeout." .. peer:EntIndex())
		addRecent(peer, myNum, pc.out and "out" or "in", pc.state == "active")
		sendState(peer, pc.state == "ringing" and "missed" or "ended", myNum)
		if pc.state == "active" or pc.out then peer:EmitSound("nyrp/phone/hangup.wav", 50) end
	end
end
P.Hangup = hangup

local function canUse(ply)
	return NYRP.HasCharacter(ply) and ply:Alive() and not (NYRP.Cond and NYRP.Cond.KO and NYRP.Cond.KO(ply))
end

net.Receive("nyrp.phone.call", function(_, ply)
	if (ply.nyrpCallNext or 0) > CurTime() then return end
	ply.nyrpCallNext = CurTime() + 1
	local number = P.Digits(net.ReadString()):sub(1, 12)
	if not canUse(ply) or ply.nyrpCall then return end
	local me = P.Number(ply)
	if not me then return end
	local target = findByNumber(number)
	if not target or target == ply then
		sendState(ply, "nonumber", number)
		addRecent(ply, number, "out", false)
		return
	end
	if target.nyrpCall or not canUse(target) then
		sendState(ply, "busy", number)
		addRecent(ply, number, "out", false)
		return
	end
	ply.nyrpCall = { peer = target, state = "dialing", out = true, peerNumber = number }
	target.nyrpCall = { peer = ply, state = "ringing", out = false, peerNumber = me }
	sendState(ply, "dialing", number)
	sendState(target, "ringing", me)
	-- мелодия звонит у телефона вызываемого — слышно рядом
	local it = P.Equipped(target)
	local ring = P.Rings[it and it.data.settings and it.data.settings.ring or 1] or P.Rings[1]
	target.nyrpRing = CreateSound(target, "nyrp/phone/" .. ring[1] .. ".wav")
	target.nyrpRing:SetSoundLevel(72)
	target.nyrpRing:Play()
	timer.Create("nyrp.phone.timeout." .. ply:EntIndex(), 30, 1, function()
		if IsValid(ply) and ply.nyrpCall and ply.nyrpCall.state == "dialing" then hangup(ply, "noanswer") end
	end)
end)

net.Receive("nyrp.phone.answer", function(_, ply)
	local c = ply.nyrpCall
	if not c or c.state ~= "ringing" or not IsValid(c.peer) or not canUse(ply) then return end
	local peer = c.peer
	stopRing(ply)
	timer.Remove("nyrp.phone.timeout." .. peer:EntIndex())
	local now = CurTime()
	c.state, c.start = "active", now
	if peer.nyrpCall then peer.nyrpCall.state, peer.nyrpCall.start = "active", now end
	sendState(ply, "active", P.Number(peer), now)
	sendState(peer, "active", P.Number(ply), now)
end)

net.Receive("nyrp.phone.hangup", function(_, ply) hangup(ply) end)

hook.Add("PlayerDisconnected", "nyrp.phone", function(ply) hangup(ply) end)
hook.Add("PlayerDeath", "nyrp.phone", function(ply) hangup(ply) end)
-- телефон убрали из слота / вынули SIM — связь рвётся
hook.Add("NYRP.InvChanged", "nyrp.phone", function(ply)
	if ply.nyrpCall and not P.Number(ply) then hangup(ply) end
end)

-- Голос: собеседники слышат друг друга на любом расстоянии (не 3D — «в трубке»).
hook.Add("PlayerCanHearPlayersVoice", "nyrp.phone", function(listener, talker)
	local c = talker.nyrpCall
	if c and c.state == "active" and c.peer == listener and talker:Alive() then return true, false end
end)

-- ---------------------------------------------------------------- дата --
local lastHour
hook.Add("Think", "nyrp.phone.day", function()
	local h = NYRP.Time.Hour()
	if lastHour and h < lastHour - 12 then
		SetGlobal2Int("nyrp.day", P.DayIndex() + 1)
		file.CreateDir("nyrp")
		file.Write("nyrp/day.txt", tostring(P.DayIndex()))
		hook.Run("NYRP.NewDay", P.DayIndex()) -- полночь: аренда и т.п.
	end
	lastHour = h
end)
hook.Add("Initialize", "nyrp.phone.day", function()
	SetGlobal2Int("nyrp.day", tonumber(file.Read("nyrp/day.txt", "DATA") or "") or 0)
end)

-- ------------------------------------------------------------- будильник --
local function gameMinute() return P.DayIndex() * 1440 + math.floor(NYRP.Time.Hour() * 60) end

local function stopAlarm(ply)
	if ply.nyrpAlarmSnd then ply.nyrpAlarmSnd:Stop() ply.nyrpAlarmSnd = nil end
	timer.Remove("nyrp.phone.alarm." .. ply:EntIndex())
	ply.nyrpAlarmOn = nil
end

local function fireAlarm(ply, label)
	if not ply:Alive() or ply.nyrpAlarmOn then return end
	local it = P.Equipped(ply)
	if not it then return end
	ply.nyrpAlarmOn = true
	-- телефон сам оказывается в руке
	if not ply:HasWeapon("nyrp_phone") then ply:Give("nyrp_phone") end
	ply:SelectWeapon("nyrp_phone")
	local snd = P.Alarms[it.data.settings and it.data.settings.alarm or 1] or P.Alarms[1]
	ply.nyrpAlarmSnd = CreateSound(ply, "nyrp/phone/" .. snd[1] .. ".wav")
	ply.nyrpAlarmSnd:SetSoundLevel(75)
	ply.nyrpAlarmSnd:Play()
	net.Start("nyrp.phone.alarm")
	net.WriteString(label or "")
	net.Send(ply)
	timer.Create("nyrp.phone.alarm." .. ply:EntIndex(), 60, 1, function() if IsValid(ply) then stopAlarm(ply) end end)
end

net.Receive("nyrp.phone.alarmact", function(_, ply)
	local snooze = net.ReadBool()
	if not ply.nyrpAlarmOn then return end
	stopAlarm(ply)
	if snooze then ply.nyrpSnooze = gameMinute() + 10 end
end)

timer.Create("nyrp.phone.alarms", 1, 0, function()
	local now = gameMinute()
	for _, ply in ipairs(player.GetAll()) do
		local it = NYRP.HasCharacter(ply) and P.Equipped(ply)
		local last = ply.nyrpAlarmLast or now
		ply.nyrpAlarmLast = now
		if it and it.data and it.data.sim and now > last then
			for m = last + 1, now do
				if ply.nyrpSnooze and m >= ply.nyrpSnooze then
					ply.nyrpSnooze = nil
					fireAlarm(ply, "Повтор")
				end
				local hm = m % 1440
				for _, a in ipairs(it.data.alarms or {}) do
					if a.on and a.h * 60 + a.m == hm then fireAlarm(ply, a.label ~= "" and a.label or "Будильник") end
				end
			end
		end
	end
end)
hook.Add("PlayerDeath", "nyrp.phone.alarm", function(...) stopAlarm(...) end)
hook.Add("PlayerDisconnected", "nyrp.phone.alarm", function(...) stopAlarm(...) end)

-- ------------------------------------------------------------------ банки --
local function bankState(ply)
	local c = ply.nyrpChar
	if not c then return end
	c.flags = c.flags or {}
	c.flags.bank = c.flags.bank or {}
	c.flags.bankLog = c.flags.bankLog or {}
	return c.flags
end

local function logOp(f, bank, text, amount)
	f.bankLog[bank] = f.bankLog[bank] or {}
	table.insert(f.bankLog[bank], 1, { text = text, amount = amount, day = P.DayIndex(), time = NYRP.Time.Format() })
	while #f.bankLog[bank] > 15 do table.remove(f.bankLog[bank]) end
end

local function sendBank(ply, bank, msg)
	local f = bankState(ply)
	if not f then return end
	net.Start("nyrp.phone.bankinfo")
	net.WriteString(bank)
	net.WriteDouble(f.bank[bank] or 0)
	net.WriteTable(f.bankLog[bank] or {})
	net.WriteString(msg or "")
	net.Send(ply)
end

net.Receive("nyrp.phone.bank", function(_, ply)
	if (ply.nyrpBankNext or 0) > CurTime() then return end
	ply.nyrpBankNext = CurTime() + 0.3
	local op, bank = net.ReadString(), net.ReadString()
	local amount = math.floor(math.max(0, net.ReadDouble()))
	local number = P.Digits(net.ReadString())
	local it = P.Equipped(ply)
	if not P.Banks[bank] or not it or not it.data.sim or not (it.data.apps or {})[bank] or not canUse(ply) then return end
	local f = bankState(ply)
	if not f then return end
	local name = P.StoreByID[bank].name
	local bal = f.bank[bank] or 0
	if op == "deposit" then
		if amount <= 0 or NYRP.Money.Get(ply) < amount then sendBank(ply, bank, "Недостаточно наличных") return end
		NYRP.Money.Add(ply, -amount)
		f.bank[bank] = bal + amount
		logOp(f, bank, "Пополнение наличными", amount)
		sendBank(ply, bank, "Счёт пополнен")
	elseif op == "withdraw" then
		if amount <= 0 or bal < amount then sendBank(ply, bank, "Недостаточно средств") return end
		f.bank[bank] = bal - amount
		NYRP.Money.Add(ply, amount)
		logOp(f, bank, "Снятие наличных", -amount)
		sendBank(ply, bank, "Наличные получены")
	elseif op == "transfer" then
		if amount <= 0 or bal < amount then sendBank(ply, bank, "Недостаточно средств") return end
		local target = findByNumber(number)
		if not target or target == ply then sendBank(ply, bank, "Получатель с таким номером недоступен") return end
		local tf = bankState(target)
		if not tf then sendBank(ply, bank, "Получатель недоступен") return end
		f.bank[bank] = bal - amount
		tf.bank[bank] = (tf.bank[bank] or 0) + amount
		logOp(f, bank, "Перевод на " .. P.FormatNumber(number), -amount)
		logOp(tf, bank, "Перевод от " .. P.FormatNumber(P.Number(ply)), amount)
		NYRP.Notify(target, name .. ": поступил перевод " .. NYRP.Money.Format(amount) .. " от " .. P.FormatNumber(P.Number(ply)), "item", 7)
		target:EmitSound("nyrp/phone/notify.wav", 55)
		sendBank(ply, bank, "Перевод отправлен")
	else
		sendBank(ply, bank)
	end
end)

-- админ: nyrp_phone_number — узнать свой номер / выдать комплект
concommand.Add("nyrp_givephone", function(ply)
	if not IsValid(ply) or not ply:IsSuperAdmin() then return end
	Inv.Add(ply, "phone", 1, phoneData())
	Inv.Add(ply, "simcard", 1, { number = newNumber() })
end)
