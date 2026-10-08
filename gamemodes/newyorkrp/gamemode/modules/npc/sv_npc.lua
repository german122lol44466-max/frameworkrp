--[[
	NPC на сервере: появление и сохранение, диалог, торговля, задания, редактор для админов.
]]

local N = NYRP.NPC
local Items = NYRP.Items
local DIR = "nyrp/npcs"

local function valid(ent) return IsValid(ent) and ent:GetClass() == "nyrp_npc" and ent.NPCData end
local function near(ply, ent) return valid(ent) and ply:Alive() and ent:GetPos():Distance(ply:GetPos()) <= 160 end

-- ------------------------------------------------------------- данные --
local function applyData(ent, d)
	ent.NPCData = d
	ent:SetModel(d.model)
	ent:SetNW2String("nyrp.npcName", d.name)
	ent:SetNW2String("nyrp.npcDesc", d.desc)
	ent:SetNW2String("nyrp.npcKind", d.kind)
	ent:SetNW2String("nyrp.npcSeq", d.seq)
	ent:SetNW2String("nyrp.npcId", d.id)
	ent:ApplySequence()
end

local function savePath() return DIR .. "/" .. game.GetMap() .. ".json" end

function N.SaveAll()
	local list = {}
	for _, ent in ipairs(ents.FindByClass("nyrp_npc")) do
		if ent.NPCData then
			local d = table.Copy(ent.NPCData)
			d.pos, d.ang = ent:GetPos(), ent:GetAngles()
			list[#list + 1] = d
		end
	end
	file.CreateDir(DIR)
	file.Write(savePath(), util.TableToJSON(list, true))
end

local function newId()
	local used = {}
	for _, e in ipairs(ents.FindByClass("nyrp_npc")) do if e.NPCData then used[e.NPCData.id] = true end end
	local i = 1
	while used["npc" .. i] do i = i + 1 end
	return "npc" .. i
end

function N.Spawn(data, pos, ang)
	local d = N.Sanitize(data) or N.Default("talk")
	d.id = data.id or newId()
	local ent = ents.Create("nyrp_npc")
	ent.NPCData = d
	ent:SetPos(pos)
	ent:SetAngles(Angle(0, ang.y, 0))
	ent:Spawn()
	applyData(ent, d)
	timer.Simple(0, N.SaveAll)
	return ent
end

local function loadAll()
	local list = util.JSONToTable(file.Read(savePath(), "DATA") or "") or {}
	for _, d in ipairs(list) do
		if d.pos and d.ang then
			local ent = ents.Create("nyrp_npc")
			local clean = N.Sanitize(d) or N.Default("talk")
			clean.id = d.id or newId()
			ent.NPCData = clean
			ent:SetPos(d.pos)
			ent:SetAngles(d.ang)
			ent:Spawn()
			applyData(ent, clean)
		end
	end
end
local cleaning = false
hook.Add("InitPostEntity", "nyrp.npc", function() timer.Simple(1, loadAll) end)
hook.Add("PreCleanupMap", "nyrp.npc", function() cleaning = true end)
hook.Add("PostCleanupMap", "nyrp.npc", function()
	timer.Simple(0, function() loadAll() cleaning = false end)
end)

-- -------------------------------------------------------------- задания --
local function quests(ply)
	local c = ply.nyrpChar
	if not c then return {} end
	c.flags = c.flags or {}
	c.flags.quests = c.flags.quests or {}
	return c.flags.quests
end

local function questDef(key)
	local npcId, qid = string.match(key, "^(.-)/(.+)$")
	for _, e in ipairs(ents.FindByClass("nyrp_npc")) do
		if e.NPCData and e.NPCData.id == npcId then return e.NPCData.quests[qid], e end
	end
end

local function countItem(ply, item)
	local n = 0
	for _, it in pairs(NYRP.Inv.Get(ply).slots) do if it.id == item then n = n + it.n end end
	return n
end

local function takeItems(ply, item, n)
	local inv = NYRP.Inv.Get(ply)
	for slot, it in pairs(inv.slots) do
		if n <= 0 then break end
		if it.id == item then
			local t = math.min(it.n, n)
			it.n = it.n - t
			n = n - t
			if it.n <= 0 then inv.slots[slot] = nil end
		end
	end
	NYRP.Inv.Sync(ply)
end

local function questReady(ply, q, st)
	if q.type == "bring" then return countItem(ply, q.item) >= q.n end
	return st.ready == true
end

function N.SyncQuests(ply)
	local out = {}
	for key, st in pairs(quests(ply)) do
		if st.state == "active" then
			local q, ent = questDef(key)
			if q then
				local goal
				if q.type == "bring" then
					local def = Items.Get(q.item)
					goal = string.format("Принести: %s ×%d (есть %d)", def and def.name or q.item, q.n, math.min(countItem(ply, q.item), q.n))
				else
					goal = st.ready and "Цель достигнута — вернитесь" or "Дойти до отмеченного места"
				end
				out[#out + 1] = { key = key, name = q.name, desc = q.desc, goal = goal, ready = questReady(ply, q, st),
					npc = ent:GetNW2String("nyrp.npcName"), point = q.type == "reach" and not st.ready and q.point or nil }
			end
		end
	end
	net.Start("nyrp.quest.sync")
	net.WriteTable(out)
	net.Send(ply)
end

-- Для меню памяти: выполненные задания (название, описание, кто дал)
function N.DoneQuests(ply)
	local out = {}
	for key, st in pairs(quests(ply)) do
		if st.state == "done" then
			local q, ent = questDef(key)
			if q then out[#out + 1] = { name = q.name, desc = q.desc, npc = IsValid(ent) and ent:GetNW2String("nyrp.npcName") or "", t = st.t or 0 } end
		end
	end
	table.sort(out, function(a, b) return a.t > b.t end)
	return out
end

-- дошёл до точки
timer.Create("nyrp.npc.quests", 1, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if NYRP.HasCharacter(ply) and ply:Alive() then
			local changed = false
			for key, st in pairs(quests(ply)) do
				if st.state == "active" and not st.ready then
					local q = questDef(key)
					if q and q.type == "reach" and ply:GetPos():Distance(Vector(q.point.x, q.point.y, q.point.z)) <= q.radius then
						st.ready = true
						changed = true
						NYRP.Notify(ply, "Цель задания «" .. q.name .. "» достигнута — возвращайтесь", "success", 6)
					end
				end
			end
			if changed then N.SyncQuests(ply) NYRP.Chars.Save(ply) end
		end
	end
end)
hook.Add("NYRP.CharacterLoaded", "nyrp.npc.quests", function(ply) timer.Simple(1, function() if IsValid(ply) then N.SyncQuests(ply) end end) end)
-- предметы в сумке меняются — обновляем счётчик «принести»
hook.Add("NYRP.InvChanged", "nyrp.npc.quests", function(ply) N.SyncQuests(ply) end)

-- --------------------------------------------------------------- диалог --
local function visibleOptions(ply, ent, node)
	local d = ent.NPCData
	local out = {}
	for i, o in ipairs(node.options or {}) do
		local show = true
		if o.act == "quest" then
			local q = d.quests[o.arg or ""]
			local st = quests(ply)[N.QuestKey(d.id, o.arg or "")]
			show = q ~= nil and (not st or (st.state == "done" and q.repeatable))
		elseif o.act == "turnin" then
			local st = quests(ply)[N.QuestKey(d.id, o.arg or "")]
			show = st ~= nil and st.state == "active"
		elseif o.act == "trade" then
			show = #d.trade > 0
		end
		if show then out[#out + 1] = { i = i, text = o.text, act = o.act } end
	end
	-- активные задания этого NPC всегда можно сдать, даже если в диалоге нет ответа «сдать»
	ply.nyrpTalkExtra = {}
	local has = {}
	for _, o in ipairs(node.options or {}) do if o.act == "turnin" then has[o.arg or ""] = true end end
	local slot = 15
	for qid, q in pairs(d.quests or {}) do
		local st = quests(ply)[N.QuestKey(d.id, qid)]
		if st and st.state == "active" and not has[qid] and slot > 11 then
			ply.nyrpTalkExtra[slot] = qid
			out[#out + 1] = { i = slot, text = "Насчёт задания «" .. q.name .. "»" .. (questReady(ply, q, st) and " — готово." or "…"), act = "turnin" }
			slot = slot - 1
		end
	end
	return out
end

-- Отправить реплику. nodeId = nil — закрыть. custom = { text, options } — служебная реплика.
local function sendNode(ply, ent, nodeId, custom)
	net.Start("nyrp.npc.node")
	net.WriteEntity(ent)
	net.WriteString(nodeId or "")
	if nodeId then
		local node = custom or ent.NPCData.dialog.nodes[nodeId]
		net.WriteString(node and node.text or "...")
		local opts = custom and custom.options or (node and visibleOptions(ply, ent, node) or {})
		if #opts == 0 then opts = { { i = 0, text = "Уйти", act = "close" } } end
		net.WriteUInt(#opts, 4)
		for _, o in ipairs(opts) do
			net.WriteUInt(o.i, 4)
			net.WriteString(o.text)
			net.WriteString(o.act)
		end
	end
	net.Send(ply)
	ply.nyrpTalk = nodeId and { ent = ent, node = nodeId } or nil
end

function N.Talk(ply, ent)
	if not NYRP.HasCharacter(ply) or not near(ply, ent) then return end
	if (ply.nyrpTalkNext or 0) > CurTime() then return end
	ply.nyrpTalkNext = CurTime() + 0.5
	if ply.nyrpTalk and ply.nyrpTalk.ent == ent then return end -- уже разговариваем
	sendNode(ply, ent, ent.NPCData.dialog.start)
end

net.Receive("nyrp.npc.choose", function(_, ply)
	local ent, idx = net.ReadEntity(), net.ReadUInt(4)
	local talk = ply.nyrpTalk
	if not talk or talk.ent ~= ent or not near(ply, ent) then sendNode(ply, ent, nil) return end
	local d = ent.NPCData
	if idx == 0 then sendNode(ply, ent, nil) return end
	-- служебные реплики (после задания) — любой ответ возвращает в начало
	if talk.node == "#back" then sendNode(ply, ent, d.dialog.start) return end
	local node = d.dialog.nodes[talk.node]
	local o = node and node.options[idx]
	-- автоматический ответ «сдать задание»
	if not o and ply.nyrpTalkExtra and ply.nyrpTalkExtra[idx] then
		o = { act = "turnin", arg = ply.nyrpTalkExtra[idx] }
	end
	if idx == 0 or not o then sendNode(ply, ent, nil) return end
	if o.act == "goto" then
		sendNode(ply, ent, d.dialog.nodes[o.arg or ""] and o.arg or nil)
	elseif o.act == "close" then
		sendNode(ply, ent, nil)
	elseif o.act == "trade" then
		sendNode(ply, ent, nil)
		net.Start("nyrp.npc.trade")
		net.WriteEntity(ent)
		net.WriteTable(d.trade)
		net.Send(ply)
	elseif o.act == "quest" then
		local q = d.quests[o.arg or ""]
		if not q then sendNode(ply, ent, nil) return end
		quests(ply)[N.QuestKey(d.id, o.arg)] = { state = "active", t = os.time() }
		NYRP.Chars.Save(ply)
		N.SyncQuests(ply)
		NYRP.Notify(ply, "Новое задание: " .. q.name, "info", 6)
		sendNode(ply, ent, "#back", { text = q.accept ~= "" and q.accept or "Договорились.", options = { { i = 1, text = "Хорошо.", act = "goto" } } })
	elseif o.act == "turnin" then
		local key = N.QuestKey(d.id, o.arg or "")
		local q, st = d.quests[o.arg or ""], quests(ply)[key]
		if not q or not st or st.state ~= "active" then sendNode(ply, ent, nil) return end
		if not questReady(ply, q, st) then
			local need = q.type == "bring" and ("Мне нужно: " .. ((Items.Get(q.item) or {}).name or q.item) .. " ×" .. q.n .. ".")
				or "Ты ещё не был там, куда я просил."
			sendNode(ply, ent, "#back", { text = "Рано пришёл. " .. need, options = { { i = 1, text = "Понял.", act = "goto" } } })
			return
		end
		if q.type == "bring" then takeItems(ply, q.item, q.n) end
		st.state = "done"
		st.ready = nil
		local got = {}
		if q.reward.money and q.reward.money > 0 then NYRP.Money.Add(ply, q.reward.money) got[#got + 1] = NYRP.Money.Format(q.reward.money) end
		if q.reward.item then
			local n = NYRP.Inv.Add(ply, q.reward.item, q.reward.n or 1)
			if n > 0 then got[#got + 1] = Items.Get(q.reward.item).name .. " ×" .. n end
		end
		NYRP.Chars.Save(ply)
		N.SyncQuests(ply)
		NYRP.Notify(ply, "Задание выполнено: " .. q.name .. (#got > 0 and (" · награда: " .. table.concat(got, ", ")) or ""), "success", 7)
		sendNode(ply, ent, "#back", { text = q.done ~= "" and q.done or "Спасибо, выручил.", options = { { i = 1, text = "Обращайся.", act = "goto" } } })
	end
end)

-- ------------------------------------------------------------ торговля --
net.Receive("nyrp.npc.buy", function(_, ply)
	if (ply.nyrpBuyNext or 0) > CurTime() then return end
	ply.nyrpBuyNext = CurTime() + 0.3
	local ent, idx = net.ReadEntity(), net.ReadUInt(8)
	if not near(ply, ent) then return end
	local o = ent.NPCData.trade[idx]
	if not o then return end
	if NYRP.Money.Get(ply) < (o.money or 0) then NYRP.Notify(ply, "Не хватает денег", "error") return end
	if o.costItem and countItem(ply, o.costItem) < o.costN then
		NYRP.Notify(ply, "Нужно: " .. Items.Get(o.costItem).name .. " ×" .. o.costN, "error")
		return
	end
	-- сначала проверим место
	local added = NYRP.Inv.Add(ply, o.item, o.n)
	if added <= 0 then NYRP.Notify(ply, "В сумке нет места", "error") return end
	if o.money and o.money > 0 then NYRP.Money.Set(ply, NYRP.Money.Get(ply) - o.money) end
	if o.costItem then takeItems(ply, o.costItem, o.costN) end
	ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 55)
	NYRP.Notify(ply, "Куплено: " .. Items.Get(o.item).name .. " ×" .. added, "item", 3)
	N.SyncQuests(ply)
end)

-- --------------------------------------------------------------- редактор --
local function isEditor(ply) return IsValid(ply) and ply:IsAdmin() end

net.Receive("nyrp.npc.edit", function(_, ply)
	local ent = net.ReadEntity()
	if not isEditor(ply) or not valid(ent) then return end
	net.Start("nyrp.npc.edit")
	net.WriteEntity(ent)
	net.WriteTable(ent.NPCData)
	net.Send(ply)
end)

net.Receive("nyrp.npc.save", function(len, ply)
	local ent = net.ReadEntity()
	local data = net.ReadTable()
	if not isEditor(ply) or not valid(ent) then return end
	local d = N.Sanitize(data)
	if not d then return end
	d.id = ent.NPCData.id
	applyData(ent, d)
	if data.moveHere then
		ent:SetPos(ply:GetPos())
		ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
		NYRP.SnapToFloor(ent)
	end
	N.SaveAll()
	NYRP.Notify(ply, "NPC «" .. d.name .. "» сохранён", "success")
end)

net.Receive("nyrp.npc.remove", function(_, ply)
	local ent = net.ReadEntity()
	if not isEditor(ply) or not valid(ent) then return end
	ent:Remove()
	timer.Simple(0, N.SaveAll)
	NYRP.Notify(ply, "NPC удалён", "success")
end)

-- nyrp_npc_create [trader|talk] — поставить NPC туда, куда смотрите
concommand.Add("nyrp_npc_create", function(ply, _, args)
	if not isEditor(ply) then return end
	local tr = ply:GetEyeTrace()
	local ent = N.Spawn(N.Default(args[1] == "trader" and "trader" or "talk"), tr.HitPos, Angle(0, ply:EyeAngles().y + 180, 0))
	undo.Create("NPC")
	undo.AddEntity(ent)
	undo.SetPlayer(ply)
	undo.Finish()
	NYRP.Notify(ply, "NPC поставлен. ПКМ по нему с зажатой C — «Настроить NPC»", "success", 6)
end)

-- после перемещения физганом/удаления — сохранить
hook.Add("PhysgunDrop", "nyrp.npc", function(ply, ent) if valid(ent) then timer.Simple(0, N.SaveAll) end end)
hook.Add("EntityRemoved", "nyrp.npc", function(ent)
	if ent:GetClass() == "nyrp_npc" and not ent.nyrpShutdown and not cleaning then
		timer.Simple(0, function() if not cleaning then N.SaveAll() end end)
	end
end)
hook.Add("ShutDown", "nyrp.npc", function()
	for _, e in ipairs(ents.FindByClass("nyrp_npc")) do e.nyrpShutdown = true end
	N.SaveAll()
end)
hook.Add("PhysgunPickup", "nyrp.npc", function(ply, ent) if valid(ent) then return ply:IsAdmin() end end)
