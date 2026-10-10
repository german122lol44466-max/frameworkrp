--[[
	Записки и письма на сервере: написать записку из блокнота, передать записку человеку,
	отправить письмо (очередь писем по квартирам), выдача писем у почтовых ящиков, уведомления.
]]

local W = NYRP.Writing

local function Inv() return NYRP.Inv end

local function limited(ply, key, cd)
	local k = "nyrpWr" .. key
	if (ply[k] or 0) > CurTime() then return true end
	ply[k] = CurTime() + (cd or 1)
	return not NYRP.HasCharacter(ply) or not ply:Alive()
end

local function paperSound(ply)
	ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 45, math.random(120, 135), 0.5)
end

local function signOf(ply, mode, custom)
	if mode == 1 then return NYRP.CharName(ply) end
	if mode == 2 then return W.Clean(custom, W.MaxSign) end
	return ""
end

-- ============================================================ записка ==
net.Receive("nyrp.writing.write", function(_, ply)
	if limited(ply, "Write", 1.5) then return end
	local slot = net.ReadUInt(8)
	local title = W.Clean(net.ReadString(), W.MaxTitle)
	local text = W.Clean(net.ReadString(), W.MaxText, true)
	local signMode = net.ReadUInt(2)
	local custom = net.ReadString()
	local inv = Inv().Get(ply)
	local it = inv.slots[slot]
	if not it or it.id ~= "notebook" then return end
	if text == "" then NYRP.Notify(ply, "Записка пустая", "warning") return end
	it.data = it.data or {}
	local pages = tonumber(it.data.pages) or W.Pages
	if pages <= 0 then NYRP.Notify(ply, "В блокноте кончились листы", "warning") return end
	local data = {
		title = title, text = text, author = signOf(ply, signMode, custom),
		date = os.date("%d.%m.%Y %H:%M"), time = os.time(),
	}
	pages = pages - 1
	if pages <= 0 then
		Inv().Take(ply, slot, 1)
		NYRP.Notify(ply, "Это был последний лист блокнота", "info", 4)
	else
		it.data.pages = pages
	end
	if Inv().Add(ply, "note", 1, data) <= 0 then
		Inv().DropNew(ply, "note", 1, data)
		NYRP.Notify(ply, "В сумке нет места — записка у ваших ног", "warning")
	else
		NYRP.Notify(ply, "Записка готова (листов осталось: " .. math.max(pages, 0) .. ")", "success", 3)
	end
	Inv().Sync(ply)
	paperSound(ply)
	ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_PLACE, true)
	hook.Run("NYRP.NoteWritten", ply, data)
end)

-- ========================================================= передать ==
local GIVEABLE = { note = true, letter = true, notebook = true, envelope = true }

net.Receive("nyrp.writing.give", function(_, ply)
	if limited(ply, "Give", 1) then return end
	local slot = net.ReadUInt(8)
	local inv = Inv().Get(ply)
	local it = inv.slots[slot]
	if not it or not GIVEABLE[it.id] then return end
	local target = ply:GetEyeTrace().Entity
	if not IsValid(target) or not target:IsPlayer() or not target:Alive() or not NYRP.HasCharacter(target)
		or target:GetPos():DistToSqr(ply:GetPos()) > 120 * 120 then
		NYRP.Notify(ply, "Посмотрите на человека рядом", "warning")
		return
	end
	local data = table.Copy(it.data or {})
	data.nyrpFrom = nil
	if Inv().Add(target, it.id, 1, data) <= 0 then
		NYRP.Notify(ply, "Ему некуда положить", "warning")
		return
	end
	Inv().Take(ply, slot, 1)
	local name = NYRP.Items.Get(it.id).name
	NYRP.Notify(ply, "Вы передали: " .. name, "success", 3)
	NYRP.Notify(target, "Вам передали: " .. name .. " (инвентарь → ПКМ)", "item", 4)
	ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_GIVE, true)
	paperSound(ply)
end)

-- ============================================================= письма ==
local letters = { next = 1, list = {} }
local function path() return "nyrp/letters_" .. game.GetMap() .. ".json" end

local function save()
	file.CreateDir("nyrp")
	file.Write(path(), util.TableToJSON(letters))
end

local function load()
	local t = util.JSONToTable(file.Read(path(), "DATA") or "") or {}
	letters = { next = tonumber(t.next) or 1, list = type(t.list) == "table" and t.list or {} }
	local now, changed = os.time(), false
	for i = #letters.list, 1, -1 do
		if now - (tonumber(letters.list[i].at) or 0) > W.LetterLife then table.remove(letters.list, i) changed = true end
	end
	if changed then save() end
end
hook.Add("Initialize", "nyrp.writing", function(...) load(...) end)
load()

local function homeName(id)
	local d = NYRP.Doors and NYRP.Doors.Data[id]
	if not d then return "Помещение №" .. id end
	return d.business and (d.bizName or d.name or ("Помещение №" .. id)) or (d.name or ("Квартира №" .. id))
end

local function delivered(l) return os.time() >= (tonumber(l.ready) or 0) end

-- письма, доступные игроку (его квартиры), уже доставленные
local function lettersFor(ply)
	local out = {}
	local D = NYRP.Doors
	if not D then return out end
	for _, l in ipairs(letters.list) do
		if delivered(l) and D.Data[l.door] and D.HasAccess(ply, l.door) then out[#out + 1] = l end
	end
	return out
end

-- список адресов: все снятые квартиры и бизнесы
net.Receive("nyrp.writing.addr", function(_, ply)
	if limited(ply, "Addr", 0.8) then return end
	local out = {}
	local D = NYRP.Doors
	if D then
		local seen = {}
		for id, d in pairs(D.Data) do
			if d.owner then
				local name = homeName(id)
				-- у квартиры может быть несколько дверей с одним названием — показываем один адрес
				local key = name .. "|" .. tostring(d.owner)
				if not seen[key] then
					seen[key] = true
					out[#out + 1] = { id = id, name = name, biz = d.business and true or false }
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	net.Start("nyrp.writing.addr")
	net.WriteTable(out)
	net.WriteBool(W.NearPost(ply) ~= nil)
	net.Send(ply)
end)

net.Receive("nyrp.writing.send", function(_, ply)
	if limited(ply, "Send", 2) then return end
	local slot = net.ReadUInt(8)
	local door = net.ReadString()
	local text = W.Clean(net.ReadString(), W.MaxText, true)
	local signMode = net.ReadUInt(2)
	local custom = net.ReadString()
	local inv = Inv().Get(ply)
	local it = inv.slots[slot]
	if not it or it.id ~= "envelope" then return end
	if not W.NearPost(ply) then NYRP.Notify(ply, "Отправить письмо можно у почтовых ящиков или синего ящика USPS", "warning", 5) return end
	local D = NYRP.Doors
	local d = D and D.Data[door]
	if not d or not d.owner then NYRP.Notify(ply, "Такого адреса нет (квартира не сдана)", "error") return end
	if text == "" then NYRP.Notify(ply, "Письмо пустое", "warning") return end
	local n = 0
	for _, l in ipairs(letters.list) do if l.door == door then n = n + 1 end end
	if n >= W.MaxPerHome then NYRP.Notify(ply, "Почтовый ящик адресата переполнен", "error") return end
	Inv().Take(ply, slot, 1)
	local id = letters.next
	letters.next = id + 1
	letters.list[#letters.list + 1] = {
		id = id, door = door, to = homeName(door), from = signOf(ply, signMode, custom), text = text,
		date = os.date("%d.%m.%Y %H:%M"), at = os.time(), ready = os.time() + W.DeliveryDelay,
	}
	save()
	paperSound(ply)
	ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_PLACE, true)
	NYRP.Notify(ply, "Письмо отправлено: " .. homeName(door) .. ". Доставят примерно через минуту.", "success", 5)
	hook.Run("NYRP.LetterSent", ply, door)
end)

-- доставка: уведомить жильцов, когда письмо оказалось в ящике
timer.Create("nyrp.writing.deliver", 5, 0, function()
	local D = NYRP.Doors
	if not D then return end
	local changed = false
	for _, l in ipairs(letters.list) do
		if not l.notified and delivered(l) then
			l.notified = true
			changed = true
			for _, p in pairs(player.GetAll()) do
				if NYRP.HasCharacter(p) and D.HasAccess(p, l.door) then
					NYRP.Notify(p, "В почтовый ящик пришло письмо (" .. l.to .. "). Заберите его у почтовых ящиков.", "info", 8)
					p:EmitSound("nyrp/fx/zone_bell.wav", 40, 120, 0.4)
				end
			end
		end
	end
	if changed then save() end
end)

-- зашли персонажем — напомнить о письмах
hook.Add("NYRP.CharacterLoaded", "nyrp.writing", function(ply)
	timer.Simple(8, function()
		if not IsValid(ply) or not NYRP.HasCharacter(ply) then return end
		local n = #lettersFor(ply)
		if n > 0 then NYRP.Notify(ply, "В вашем почтовом ящике писем: " .. n, "info", 8) end
	end)
end)

-- окно почтового ящика спрашивает письма (cl_writing добавляет кнопку в окно modules/doors)
local function sendBox(ply)
	local out = {}
	for _, l in ipairs(lettersFor(ply)) do
		out[#out + 1] = { id = l.id, to = l.to, from = l.from ~= "" and l.from or "без подписи", date = l.date }
	end
	net.Start("nyrp.writing.box")
	net.WriteTable(out)
	net.Send(ply)
end

net.Receive("nyrp.writing.box", function(_, ply)
	if limited(ply, "Box", 0.5) then return end
	if not W.NearPost(ply) then return end
	sendBox(ply)
end)

net.Receive("nyrp.writing.take", function(_, ply)
	if limited(ply, "Take", 0.4) then return end
	local id = net.ReadUInt(32)
	local near = W.NearPost(ply)
	if not near or near:GetClass() ~= "nyrp_mailbox" then NYRP.Notify(ply, "Подойдите к почтовым ящикам", "warning") return end
	for i, l in ipairs(letters.list) do
		if l.id == id then
			if not delivered(l) or not NYRP.Doors.HasAccess(ply, l.door) then return end
			local data = { text = l.text, author = l.from, to = l.to, date = l.date, time = l.at }
			if Inv().Add(ply, "letter", 1, data) <= 0 then NYRP.Notify(ply, "В сумке нет места", "error") return end
			table.remove(letters.list, i)
			save()
			paperSound(ply)
			NYRP.Notify(ply, "Письмо у вас: инвентарь → ПКМ → «Прочитать»", "success", 4)
			sendBox(ply)
			return
		end
	end
end)
