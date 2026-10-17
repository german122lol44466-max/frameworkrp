--[[
	Занятия для служб на дежурстве — серверная часть.
	Задание игрока: ply.nyrpDuty = { kind = "patrol"|"hydrants"|"patient", title, text, idx, total, points, ent }.
	Метка задания одна — id "duty_task": снимается при выполнении, отмене, конце дежурства, смене роли, смерти, выходе.
	Точки патруля: data/nyrp/patrol_<карта>.json.
]]
NYRP.DutyTasks = NYRP.DutyTasks or {}
local D = NYRP.DutyTasks
NYRP.Waypoint = NYRP.Waypoint or {}
local W = NYRP.Waypoint   -- модуль меток грузится позже (по алфавиту) — берём общую таблицу заранее

local BLUE = Color(80, 140, 230)
local RED = Color(230, 70, 60)
local ROLE_OF = { patrol = "police", hydrants = "fire", patient = "medic" }
local MAX_DIST = 150

local function role(ply) return ply:GetNW2String("nyrp.role", "") end
local function onDuty(ply, r)
	return IsValid(ply) and ply:Alive() and NYRP.HasCharacter(ply) and ply:GetNW2Bool("nyrp.onDuty") and role(ply) == r
end
D.OnDuty = onDuty

-- ------------------------------------------------------------ точки патруля --
D.Points = D.Points or {}
local function pointsFile() return "nyrp/patrol_" .. game.GetMap() .. ".json" end

local function loadPoints()
	D.Points = {}
	local t = util.JSONToTable(file.Read(pointsFile(), "DATA") or "") or {}
	for _, v in ipairs(t) do
		if istable(v) and tonumber(v[1]) and tonumber(v[2]) and tonumber(v[3]) then
			D.Points[#D.Points + 1] = Vector(tonumber(v[1]), tonumber(v[2]), tonumber(v[3]))
		end
	end
end

local function savePoints()
	local out = {}
	for _, p in ipairs(D.Points) do out[#out + 1] = { math.floor(p.x), math.floor(p.y), math.floor(p.z) } end
	file.CreateDir("nyrp")
	file.Write(pointsFile(), util.TableToJSON(out, true))
end

loadPoints()
hook.Add("InitPostEntity", "nyrp.dutytasks", function() loadPoints() end)

NYRP.Chat.AddCommand("/patrolpoint", function(ply)
	if not ply:IsAdmin() then return end
	D.Points[#D.Points + 1] = ply:GetPos()
	savePoints()
	NYRP.Notify(ply, "Точка патруля #" .. #D.Points .. " сохранена", "success")
end)

NYRP.Chat.AddCommand("/patrolpointdel", function(ply)
	if not ply:IsAdmin() then return end
	local best, bestD = nil, 250
	for i, p in ipairs(D.Points) do
		local d = p:Distance(ply:GetPos())
		if d < bestD then best, bestD = i, d end
	end
	if not best then NYRP.Notify(ply, "Рядом (до 250 юнитов) нет точек патруля", "warning") return end
	table.remove(D.Points, best)
	savePoints()
	NYRP.Notify(ply, "Точка патруля удалена. Осталось: " .. #D.Points, "info")
end)

-- показать точки админу метками на 60 секунд (дошёл до точки — её метка исчезает)
NYRP.Chat.AddCommand("/patrols", function(ply)
	if not ply:IsAdmin() then return end
	for i = 1, (ply.nyrpPatrolShown or 0) do W.Clear(ply, "patrolpt" .. i) end
	local n = math.min(#D.Points, 64)
	ply.nyrpPatrolShown = n
	if n == 0 then NYRP.Notify(ply, "Точек патруля нет. Поставить: /patrolpoint", "info") return end
	for i = 1, n do
		W.Set(ply, "patrolpt" .. i, D.Points[i], "Точка патруля #" .. i, "map_pin", BLUE, { radius = 80, onReach = function() end })
	end
	NYRP.Notify(ply, "Точек патруля: " .. #D.Points .. ". Метки исчезнут через минуту.", "info", 5)
	timer.Create("nyrp.duty.patrols." .. ply:EntIndex(), 60, 1, function()
		if not IsValid(ply) then return end
		for i = 1, (ply.nyrpPatrolShown or 0) do W.Clear(ply, "patrolpt" .. i) end
		ply.nyrpPatrolShown = 0
	end)
end)

-- --------------------------------------------------------------- помощники --
local function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- порядок обхода: каждый раз к ближайшей из оставшихся (items: { pos = Vector, ... })
local function routeOrder(from, items)
	local left, out = {}, {}
	for i, it in ipairs(items) do left[i] = it end
	local cur = from
	while #left > 0 do
		local bi, bd = 1, math.huge
		for i, it in ipairs(left) do
			local d = it.pos:DistToSqr(cur)
			if d < bd then bi, bd = i, d end
		end
		local it = table.remove(left, bi)
		out[#out + 1] = it
		cur = it.pos
	end
	return out
end

local function sync(ply)
	local t = ply.nyrpDuty
	net.Start("nyrp.duty.task")
	net.WriteString(t and t.kind or "")
	net.WriteString(t and t.title or "")
	net.WriteString(t and t.text or "")
	net.WriteUInt(math.Clamp(t and t.idx or 0, 0, 255), 8)
	net.WriteUInt(math.Clamp(t and t.total or 0, 0, 255), 8)
	net.Send(ply)
end
D.Sync = sync

-- закончить задание (msg — уведомление, quiet — без сети: игрок выходит)
function D.Stop(ply, msg, quiet)
	if not IsValid(ply) then return end
	local t = ply.nyrpDuty
	if not t then return end
	ply.nyrpDuty = nil
	if t.kind == "patient" and IsValid(t.ent) and t.ent.nyrpClaimedBy == ply then t.ent.nyrpClaimedBy = nil end
	if quiet then return end
	W.Clear(ply, "duty_task")
	sync(ply)
	if msg then NYRP.Notify(ply, msg, "info") end
end

local function canTake(ply, r, what)
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return false end
	if role(ply) ~= r then
		local R = NYRP.Roles.List[r]
		NYRP.Notify(ply, what .. " — только для службы «" .. (R and R.Name or r) .. "»", "warning")
		return false
	end
	if not ply:GetNW2Bool("nyrp.onDuty") then
		NYRP.Notify(ply, "Сначала заступите на дежурство (служебный компьютер)", "warning")
		return false
	end
	if ply.nyrpDuty then
		NYRP.Notify(ply, "У вас уже есть задание. Отменить — /dutycancel", "warning")
		return false
	end
	local left = math.ceil((ply.nyrpDutyNext or 0) - CurTime())
	if left > 0 then
		NYRP.Notify(ply, "Следующее задание — через " .. left .. " с", "info")
		return false
	end
	return true
end

local function payout(ply, money, skill, xp, why, text)
	NYRP.Money.Add(ply, money)
	if NYRP.Skills and NYRP.Skills.AddXP then NYRP.Skills.AddXP(ply, skill, xp, why) end
	ply:EmitSound("nyrp/fx/cash.wav", 50)
	NYRP.Notify(ply, text .. ": +" .. NYRP.Money.Format(money), "success", 6)
end

-- ------------------------------------------------------------ NYPD: патруль --
local function markPatrol(ply)
	local t = ply.nyrpDuty
	if not t or t.kind ~= "patrol" then return end
	local p = t.points[t.idx]
	t.text = "Дойдите до точки патруля — отметка засчитается на месте (" .. t.idx .. " из " .. t.total .. ")"
	W.Set(ply, "duty_task", p.pos, "Патруль: точка " .. t.idx .. "/" .. t.total, "shield", BLUE, {
		radius = 150,
		onReach = function(pl)
			-- следующую метку ставим в следующем кадре (сейчас идёт обход списка меток)
			timer.Simple(0, function() if IsValid(pl) then D.PatrolReach(pl, t) end end)
		end,
	})
	sync(ply)
end

function D.PatrolReach(ply, t)
	if ply.nyrpDuty ~= t or not onDuty(ply, "police") then return end
	ply:EmitSound("buttons/button14.wav", 50)
	if t.idx >= t.total then
		D.Stop(ply)
		ply.nyrpDutyNext = CurTime() + 30
		payout(ply, 60, "stamina", 20, "патрулирование", "Маршрут патруля пройден")
		return
	end
	NYRP.Notify(ply, "Отметка: точка " .. t.idx .. " из " .. t.total, "info", 3)
	t.idx = t.idx + 1
	markPatrol(ply)
end

function D.StartPatrol(ply)
	if not canTake(ply, "police", "Патрулирование") then return end
	local pool = {}
	for _, p in ipairs(D.Points) do
		if p:Distance(ply:GetPos()) > 200 then pool[#pool + 1] = p end
	end
	-- мало своих точек — добавляем подъезды карты
	if #pool < 4 then
		local doors = {}
		for _, p in ipairs(NYRP.Jobs and NYRP.Jobs.Doors or {}) do doors[#doors + 1] = p end
		for _, p in ipairs(shuffle(doors)) do
			if #pool >= 12 then break end
			if p:Distance(ply:GetPos()) > 300 then pool[#pool + 1] = p end
		end
	end
	if #pool < 2 then
		NYRP.Notify(ply, "Точки патруля не настроены — сообщите администрации (/patrolpoint)", "warning", 6)
		return
	end
	shuffle(pool)
	local n = math.min(#pool, math.random(4, 6))
	local items = {}
	for i = 1, n do items[i] = { pos = pool[i] } end
	ply.nyrpDuty = { kind = "patrol", title = "NYPD · Патрулирование", text = "", idx = 1, total = n, points = routeOrder(ply:GetPos(), items) }
	NYRP.Notify(ply, "Маршрут патруля: " .. n .. " точек. Отменить — /dutycancel", "success", 5)
	markPatrol(ply)
end

-- ------------------------------------------------------- FDNY: гидранты --
local function markHydrant(ply)
	local t = ply.nyrpDuty
	if not t or t.kind ~= "hydrants" then return end
	-- снесённые гидранты пропускаем
	while t.idx <= t.total and not IsValid(t.points[t.idx].ent) do t.idx = t.idx + 1 end
	if t.idx > t.total then
		D.Stop(ply, "Обход прерван: гидрантов на маршруте не осталось")
		return
	end
	local e = t.points[t.idx].ent
	t.text = "Подойдите к гидранту и проверьте его — E, 3 секунды (" .. t.idx .. " из " .. t.total .. ")"
	W.Set(ply, "duty_task", e:GetPos(), "Гидрант " .. t.idx .. "/" .. t.total, "droplet", RED, {})
	sync(ply)
end

function D.StartHydrants(ply)
	if not canTake(ply, "fire", "Обход гидрантов") then return end
	local list = {}
	for _, e in ipairs(ents.FindByClass("nyrp_street_hydrant")) do
		if IsValid(e) then list[#list + 1] = { pos = e:GetPos(), ent = e, d = e:GetPos():DistToSqr(ply:GetPos()) } end
	end
	if #list == 0 then
		NYRP.Notify(ply, "На карте нет пожарных гидрантов — обход невозможен", "warning", 5)
		return
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	local n = math.min(#list, math.random(3, 5))
	local items = {}
	for i = 1, n do items[i] = list[i] end
	ply.nyrpDuty = { kind = "hydrants", title = "FDNY · Обход гидрантов", text = "", idx = 1, total = n, points = routeOrder(ply:GetPos(), items) }
	NYRP.Notify(ply, "Обход гидрантов: " .. n .. " шт. Отменить — /dutycancel", "success", 5)
	markHydrant(ply)
end

-- E по гидранту: true — нажатие обработано заданием
function D.HydrantUse(ply, e)
	local t = ply.nyrpDuty
	if not t or t.kind ~= "hydrants" or not IsValid(e) then return false end
	local cur = t.points[t.idx]
	if not cur or cur.ent ~= e then return false end
	local w = ply:GetActiveWeapon()
	if IsValid(w) and w:GetClass() == "nyrp_extinguisher" then return false end   -- с огнетушителем — заправка
	NYRP.Action(ply, "Проверяю гидрант...", 3, function()
		if ply.nyrpDuty ~= t or not onDuty(ply, "fire") or not IsValid(e) then return end
		if ply:GetPos():Distance(e:GetPos()) > MAX_DIST then NYRP.Notify(ply, "Вы отошли от гидранта", "warning") return end
		e:EmitSound("ambient/water/water_spray1.wav", 55)
		if t.idx >= t.total then
			D.Stop(ply)
			ply.nyrpDutyNext = CurTime() + 30
			payout(ply, 50, "strength", 15, "обход гидрантов", "Обход гидрантов завершён")
			return
		end
		NYRP.Notify(ply, "Гидрант исправен (" .. t.idx .. " из " .. t.total .. ")", "info", 3)
		t.idx = t.idx + 1
		markHydrant(ply)
	end, "droplet")
	return true
end

-- E по гидранту обрабатывает modules/street — встаём перед его обработчиком
local function wrapHydrant()
	local S = NYRP.Street
	if not S or not istable(S.Use) or not isfunction(S.Use.hydrant) then return end
	if S.Use.hydrant == D.HydrantWrapped then return end
	local orig = S.Use.hydrant
	D.HydrantWrapped = function(ply, e)
		if D.HydrantUse(ply, e) then return end
		return orig(ply, e)
	end
	S.Use.hydrant = D.HydrantWrapped
end
hook.Add("InitPostEntity", "nyrp.dutytasks.hydrant", function() wrapHydrant() end)

-- ------------------------------------------------ происшествия (NYPD / EMS) --
local function anyOnDuty(r)
	for _, p in ipairs(player.GetAll()) do
		if onDuty(p, r) then return true end
	end
	return false
end

local function randomSpot()
	local pool = {}
	for _, p in ipairs(D.Points) do pool[#pool + 1] = p end
	for _, p in ipairs(NYRP.Jobs and NYRP.Jobs.Doors or {}) do pool[#pool + 1] = p end
	if #pool == 0 then return nil end
	-- подальше от людей, чтобы не появлялось на глазах
	for _ = 1, 12 do
		local p = pool[math.random(#pool)]
		local near = false
		for _, pl in ipairs(player.GetAll()) do
			if pl:GetPos():DistToSqr(p) < 400 * 400 then near = true break end
		end
		if not near then return p end
	end
	return pool[math.random(#pool)]
end

local function lastCallId()
	local best = 0
	for id in pairs(NYRP.E911 and NYRP.E911.Calls or {}) do
		if isnumber(id) and id > best then best = id end
	end
	return best
end

function D.SpawnIncident(r)
	local cls = r == "police" and "nyrp_evidence" or "nyrp_patient"
	local pos = randomSpot()
	if not pos then return nil end
	local e = ents.Create(cls)
	if not IsValid(e) then return nil end
	e:SetPos(pos + Vector(0, 0, 4))
	e:SetAngles(Angle(0, math.random(0, 359), 0))
	e:Spawn()
	e.nyrpDieAt = CurTime() + 600
	local E = NYRP.E911
	if E and E.Auto then
		E.Auto(r, pos, r == "police" and "Подозрительная активность" or "Человеку плохо")
		e.nyrpCallId = lastCallId()
	end
	return e
end

-- происшествие закончилось (осмотрено, вылечено или истекло): снять вызов и метки у всех
function D.IncidentGone(e)
	if D.ShuttingDown then return end
	local id = e.nyrpCallId
	e.nyrpCallId = nil
	if id then
		local E = NYRP.E911
		if E and E.Calls then E.Calls[id] = nil end
		for _, p in ipairs(player.GetAll()) do W.Clear(p, "911_" .. id) end
	end
	for _, p in ipairs(player.GetAll()) do
		if p.nyrpDuty and p.nyrpDuty.ent == e then D.Stop(p, e.nyrpDone and nil or "Вызов снят: пострадавшего забрали") end
	end
end
hook.Add("ShutDown", "nyrp.dutytasks", function() D.ShuttingDown = true end)

timer.Create("nyrp.duty.incidents", 15, 0, function()
	local now = CurTime()
	-- истекли — убираем
	for _, cls in ipairs({ "nyrp_evidence", "nyrp_patient" }) do
		for _, e in ipairs(ents.FindByClass(cls)) do
			if e.nyrpDieAt and now > e.nyrpDieAt then e:Remove() end
		end
	end
	D.nextPolice = D.nextPolice or (now + math.random(360, 600))
	D.nextMedic = D.nextMedic or (now + math.random(360, 600))
	if now >= D.nextPolice then
		D.nextPolice = now + math.random(360, 600)
		if anyOnDuty("police") and #ents.FindByClass("nyrp_evidence") == 0 then D.SpawnIncident("police") end
	end
	if now >= D.nextMedic then
		D.nextMedic = now + math.random(360, 600)
		if anyOnDuty("medic") and #ents.FindByClass("nyrp_patient") == 0 then D.SpawnIncident("medic") end
	end
end)

NYRP.Chat.AddCommand("/dutyincident", function(ply, raw)
	if not ply:IsAdmin() then return end
	local r = string.match(raw or "", "^%S+%s+(%S+)")
	if r ~= "police" and r ~= "medic" then NYRP.Notify(ply, "/dutyincident <police|medic>", "info") return end
	local e = D.SpawnIncident(r)
	if IsValid(e) then
		NYRP.Notify(ply, "Происшествие создано", "success")
	else
		NYRP.Notify(ply, "Нет точек: поставьте /patrolpoint", "warning")
	end
end)

-- улика (NYPD): осмотр 4 с
local REPORTS = {
	"брошенная сумка, владелец не найден — изъята в участок",
	"следы взлома, хозяин помещения уведомлён",
	"вещи бездомного, угрозы нет",
	"потерянные документы — переданы в бюро находок",
	"следы драки, свидетели разошлись — составлен протокол",
}

function D.EvidenceUse(ply, e)
	if not onDuty(ply, "police") then
		if role(ply) == "police" then
			NYRP.Notify(ply, "Сначала заступите на дежурство", "warning")
		else
			NYRP.Notify(ply, "Похоже, здесь что-то случилось. Лучше сообщить в полицию (911).", "info", 4)
		end
		return
	end
	if (e.nyrpBusy or 0) > CurTime() then NYRP.Notify(ply, "Место уже осматривают", "info") return end
	local ok = NYRP.Action(ply, "Осматриваю место происшествия...", 4, function()
		if not IsValid(e) or not onDuty(ply, "police") then return end
		if ply:GetPos():Distance(e:GetPos()) > MAX_DIST then NYRP.Notify(ply, "Вы отошли слишком далеко", "warning") return end
		e.nyrpDone = true
		e:Remove()
		ply:EmitSound("nyrp/fx/stamp.wav", 55)
		NYRP.Notify(ply, "Отчёт: " .. REPORTS[math.random(#REPORTS)], "info", 8)
		payout(ply, 40, "intellect", 15, "осмотр места", "Отчёт о происшествии сдан")
	end, "eye")
	if ok then e.nyrpBusy = CurTime() + 4.5 end
end

-- пострадавший (EMS)
local function bandageSlot(ply)
	local Inv = NYRP.Inv
	local inv = Inv.Get(ply)
	for slot = 1, Inv.Size(ply) do
		local it = inv.slots[slot]
		if it and it.id == "bandage" and (it.n or 0) > 0 then return slot end
	end
	return nil
end

local function hasDefib(ply)
	local w = ply:GetActiveWeapon()
	return IsValid(w) and w:GetClass() == "nyrp_defib"
end

local DIAG = {
	bandage = { "Глубокий порез, сильное кровотечение", "Нужна перевязка (бинт)" },
	defib = { "Остановка сердца", "Нужен дефибриллятор (в руках)" },
}

function D.PatientUse(ply, e)
	if not onDuty(ply, "medic") then
		if role(ply) == "medic" then
			NYRP.Notify(ply, "Сначала заступите на дежурство", "warning")
		else
			NYRP.Notify(ply, "Человеку плохо. Вызовите скорую (911).", "info", 4)
		end
		return
	end
	local by = e.nyrpClaimedBy
	if IsValid(by) and by ~= ply and onDuty(by, "medic") then
		NYRP.Notify(ply, "Пострадавшим уже занимается " .. NYRP.CharName(by), "info")
		return
	end
	net.Start("nyrp.duty.patient")
	net.WriteEntity(e)
	net.WriteString(e:GetDiagnosis())
	net.WriteBool(bandageSlot(ply) ~= nil)
	net.WriteBool(hasDefib(ply))
	net.Send(ply)
end

local function claimPatient(ply, e)
	e.nyrpClaimedBy = ply
	if ply.nyrpDuty and ply.nyrpDuty.ent == e then return end
	if ply.nyrpDuty then return end   -- уже занят другим заданием — без панели
	local need = DIAG[e.nyrpNeed] or DIAG.bandage
	ply.nyrpDuty = { kind = "patient", title = "EMS · Вызов к пострадавшему", text = need[1] .. ". " .. need[2] .. ".", idx = 0, total = 0, ent = e }
	sync(ply)
end

net.Receive("nyrp.duty.patient.act", function(_, ply)
	if (ply.nyrpDutyNet or 0) > CurTime() then return end
	ply.nyrpDutyNet = CurTime() + 0.5
	local e, act = net.ReadEntity(), net.ReadString()
	if not IsValid(e) or e:GetClass() ~= "nyrp_patient" or not onDuty(ply, "medic") then return end
	if ply:GetPos():Distance(e:GetPos()) > MAX_DIST then return end
	local by = e.nyrpClaimedBy
	if IsValid(by) and by ~= ply and onDuty(by, "medic") then
		NYRP.Notify(ply, "Пострадавшим уже занимается " .. NYRP.CharName(by), "info")
		return
	end
	local function still()
		return IsValid(e) and onDuty(ply, "medic") and ply:GetPos():Distance(e:GetPos()) <= MAX_DIST
	end
	if act == "examine" then
		NYRP.Action(ply, "Осматриваю пострадавшего...", 3, function()
			if not still() then return end
			local need = DIAG[e.nyrpNeed] or DIAG.bandage
			e:SetDiagnosis(need[1])
			claimPatient(ply, e)
			NYRP.Notify(ply, "Диагноз: " .. need[1] .. ". " .. need[2] .. ".", "info", 7)
		end, "eye")
		return
	end
	if act ~= "bandage" and act ~= "defib" then return end
	if e:GetDiagnosis() == "" then NYRP.Notify(ply, "Сначала осмотрите пострадавшего", "warning") return end
	if act == "bandage" and not bandageSlot(ply) then NYRP.Notify(ply, "Нет бинта", "error") return end
	if act == "defib" and not hasDefib(ply) then NYRP.Notify(ply, "Возьмите дефибриллятор в руки", "error") return end
	if act ~= e.nyrpNeed then
		NYRP.Notify(ply, "Это не поможет. " .. (DIAG[e.nyrpNeed] or DIAG.bandage)[2] .. ".", "warning", 5)
		return
	end
	claimPatient(ply, e)
	NYRP.Action(ply, act == "bandage" and "Перевязываю рану..." or "Разряд дефибриллятора...", 5, function()
		if not still() then return end
		if act == "bandage" then
			local slot = bandageSlot(ply)
			if not slot then NYRP.Notify(ply, "Нет бинта", "error") return end
			NYRP.Inv.Take(ply, slot, 1)
			e:EmitSound("nyrp/fx/cloth.wav", 55)
		else
			if not hasDefib(ply) then NYRP.Notify(ply, "Возьмите дефибриллятор в руки", "error") return end
			e:EmitSound("ambient/energy/zap" .. math.random(1, 3) .. ".wav", 70)
		end
		e.nyrpDone = true
		D.Stop(ply)
		e:Remove()
		payout(ply, 70, "medicine", 30, "вызов к пострадавшему", "Пострадавший спасён, его забрала бригада")
	end, act == "bandage" and "bandage" or "heart")
end)

-- ----------------------------------------------- взять / отменить задание --
function D.Cancel(ply)
	if not ply.nyrpDuty then NYRP.Notify(ply, "У вас нет задания", "info") return end
	D.Stop(ply, "Задание отменено")
end

NYRP.Chat.AddCommand("/patrol", function(ply) D.StartPatrol(ply) end)
NYRP.Chat.AddCommand("/hydrants", function(ply) D.StartHydrants(ply) end)
NYRP.Chat.AddCommand("/dutycancel", function(ply) D.Cancel(ply) end)

net.Receive("nyrp.duty.act", function(_, ply)
	if (ply.nyrpDutyAct or 0) > CurTime() then return end
	ply.nyrpDutyAct = CurTime() + 1
	local act = net.ReadString()
	if act == "patrol" then
		D.StartPatrol(ply)
	elseif act == "hydrants" then
		D.StartHydrants(ply)
	elseif act == "cancel" then
		D.Cancel(ply)
	end
end)

-- ----------------------------------------------------------------- сброс --
hook.Add("PlayerDeath", "nyrp.dutytasks", function(ply) D.Stop(ply, "Задание отменено") end)
hook.Add("PlayerDisconnected", "nyrp.dutytasks", function(ply) D.Stop(ply, nil, true) end)
hook.Add("NYRP.RoleChanged", "nyrp.dutytasks", function(ply) D.Stop(ply, "Задание отменено: смена службы") end)
hook.Add("NYRP.CharacterLoaded", "nyrp.dutytasks", function(ply)
	D.Stop(ply)
	sync(ply)
end)

-- конец дежурства и прочие условия — проверка раз в секунду
timer.Create("nyrp.duty.check", 1, 0, function()
	wrapHydrant()
	for _, ply in ipairs(player.GetAll()) do
		local t = ply.nyrpDuty
		if t and ply:Alive() then
			if not onDuty(ply, ROLE_OF[t.kind] or "") then
				D.Stop(ply, "Задание отменено: дежурство окончено")
			elseif t.kind == "hydrants" and t.points[t.idx] and not IsValid(t.points[t.idx].ent) then
				markHydrant(ply)
			elseif t.kind == "patient" and not IsValid(t.ent) then
				D.Stop(ply)
			end
		end
	end
end)
