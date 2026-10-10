local J = NYRP.Jobs
NYRP.Waypoint = NYRP.Waypoint or {}
local W = NYRP.Waypoint   -- модуль меток грузится позже (по алфавиту) — берём общую таблицу заранее

-- ------------------------------------------------------------------ точки --
-- У дверей карты (подъезды, магазины) — точки на тротуаре; плюс свои точки админа на профессию.
J.Doors = J.Doors or {}
local POINTS_FILE = function() return "nyrp/jobpoints_" .. game.GetMap() .. ".json" end
J.Custom = J.Custom or {}

local function floorAt(pos)
	local tr = util.TraceHull({ start = pos + Vector(0, 0, 40), endpos = pos - Vector(0, 0, 120),
		mins = Vector(-14, -14, 0), maxs = Vector(14, 14, 60), mask = MASK_PLAYERSOLID })
	if tr.Hit and not tr.StartSolid and tr.HitNormal.z > 0.7 then return tr.HitPos end
end

local function scanDoors()
	J.Doors = {}
	for _, cls in ipairs({ "prop_door_rotating", "func_door_rotating", "func_door" }) do
		for _, d in ipairs(ents.FindByClass(cls)) do
			local c = d:WorldSpaceCenter()
			for _, s in ipairs({ 1, -1 }) do
				local p = floorAt(c + d:GetRight() * 46 * s)
				if p then J.Doors[#J.Doors + 1] = p break end
			end
		end
	end
	local t = util.JSONToTable(file.Read(POINTS_FILE(), "DATA") or "") or {}
	J.Custom = {}
	for id, list in pairs(t) do
		J.Custom[id] = {}
		for _, v in ipairs(list) do J.Custom[id][#J.Custom[id] + 1] = Vector(v[1], v[2], v[3]) end
	end
	NYRP.Print("Профессии: точек у дверей — " .. #J.Doors)
end
hook.Add("InitPostEntity", "nyrp.jobs", function() timer.Simple(2, scanDoors) end)
hook.Add("PostCleanupMap", "nyrp.jobs", function() timer.Simple(1, scanDoors) end)

local function saveCustom()
	local out = {}
	for id, list in pairs(J.Custom) do
		out[id] = {}
		for _, v in ipairs(list) do out[id][#out[id] + 1] = { math.floor(v.x), math.floor(v.y), math.floor(v.z) } end
	end
	file.CreateDir("nyrp")
	file.Write(POINTS_FILE(), util.TableToJSON(out, true))
end

-- случайная точка на расстоянии [minD, maxD] от from (свои точки профессии важнее)
function J.Spot(jobId, from, minD, maxD, avoid)
	local pool = (J.Custom[jobId] and #J.Custom[jobId] > 0) and J.Custom[jobId] or J.Doors
	local good = {}
	for _, p in ipairs(pool) do
		local d = p:Distance(from)
		if d >= minD and d <= maxD and not (avoid and avoid[p]) then good[#good + 1] = p end
	end
	if #good == 0 then
		for _, p in ipairs(pool) do if p:Distance(from) >= 100 and not (avoid and avoid[p]) then good[#good + 1] = p end end
	end
	if #good == 0 then
		-- карта без дверей: просто точка неподалёку
		local p = floorAt(from + Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0):GetNormalized() * math.Rand(minD, maxD))
		return p or (from + Vector(200, 0, 0))
	end
	return good[math.random(#good)]
end

NYRP.Chat.AddCommand("/jobpoint", function(ply, raw)
	if not ply:IsAdmin() then return end
	local id = string.match(raw, "^%S+%s+(%S+)")
	if not J.List[id or ""] then NYRP.Notify(ply, "/jobpoint <профессия>: " .. table.concat(J.Order, ", "), "info", 8) return end
	local p = floorAt(ply:GetEyeTrace().HitPos) or ply:GetPos()
	J.Custom[id] = J.Custom[id] or {}
	table.insert(J.Custom[id], p)
	saveCustom()
	NYRP.Notify(ply, "Точка для «" .. J.List[id].Name .. "» добавлена (" .. #J.Custom[id] .. ")", "success")
end)
NYRP.Chat.AddCommand("/jobpointdel", function(ply)
	if not ply:IsAdmin() then return end
	local best, bi, bid
	for id, list in pairs(J.Custom) do
		for i, p in ipairs(list) do
			local d = p:Distance(ply:GetPos())
			if not best or d < best then best, bi, bid = d, i, id end
		end
	end
	if bid and best < 300 then table.remove(J.Custom[bid], bi) saveCustom() NYRP.Notify(ply, "Точка удалена", "success")
	else NYRP.Notify(ply, "Рядом нет своих точек", "warning") end
end)

-- -------------------------------------------------------------- задания --
local function clearSpots(ply)
	for _, e in ipairs(ply.nyrpJobSpots or {}) do if IsValid(e) then e:Remove() end end
	ply.nyrpJobSpots = {}
end

local function spawnSpot(ply, kind, pos, model, job, scale)
	local e = ents.Create("nyrp_jobspot")
	if not IsValid(e) then return end
	if istable(model) then model = model[math.random(#model)] end
	local m = model or "models/props_junk/cardboard_box004a.mdl"
	if not util.IsValidModel(m) then m = job and job.SpotFallback or "models/props_junk/cardboard_box004a.mdl" end
	e:SetModel(m)
	e:SetPos(pos + Vector(0, 0, 2))
	e:SetAngles(Angle(0, math.random(0, 359), 0))
	e:SetKind(kind)
	e:SetOwnerPly(ply)
	e:SetEffect(job and job.Effect or "")
	e:Spawn()
	if scale and scale ~= 1 then e:SetModelScale(scale, 0) end
	ply.nyrpJobSpots = ply.nyrpJobSpots or {}
	table.insert(ply.nyrpJobSpots, e)
	return e
end

local function task(ply, text, icon)
	net.Start("nyrp.jobs.task")
	net.WriteString(text or "")
	net.WriteString(icon or "")
	net.WriteUInt(math.floor(ply.nyrpShiftEarned or 0), 32)
	net.Send(ply)
end
J.Task = task

local function pay(ply, job, amount, why)
	amount = math.max(0, math.floor(amount))
	if amount <= 0 then return end
	NYRP.Money.Add(ply, amount)
	ply.nyrpShiftEarned = (ply.nyrpShiftEarned or 0) + amount
	ply:EmitSound("nyrp/fx/cash.wav", 55)
	NYRP.Notify(ply, "+" .. NYRP.Money.Format(amount) .. (why and ("  ·  " .. why) or ""), "success", 4)
	if job.Skill and NYRP.Skills then NYRP.Skills.AddXP(ply, job.Skill, job.SkillXP or 8) end
	local c = ply.nyrpChar
	if c then
		c.flags.jobEarned = (c.flags.jobEarned or 0) + amount
		c.flags.jobTasks = (c.flags.jobTasks or 0) + 1
	end
end
J.Pay = pay

local nextTask -- ниже

local function meters(a, b) return a:Distance(b) * 0.019 end

local Types = {}

-- доставка: (забрать) → адрес(а)
Types.deliver = function(ply, job)
	local st = J.NearestStation(job.id, ply:GetPos())
	local depot = IsValid(st) and st:GetPos() or ply.nyrpJobDepot or ply:GetPos()
	local function goDeliver(left)
		local from = ply:GetPos()
		local dest = J.Spot(job.id, from, 600, 3500)
		local dist = meters(from, dest)
		local started = CurTime()
		local limit = job.TimeLimit and (dist / 2.6 + 30) or nil
		ply.nyrpJobLimit = limit and (CurTime() + limit) or nil
		task(ply, "Отнесите заказ по адресу и передайте (E)" .. (left and left > 1 and (" (ещё " .. left .. ")") or "") .. (limit and (" · успеть за " .. math.floor(limit) .. " с") or ""), job.Icon)
		local target = spawnSpot(ply, job.TargetModel and (string.find(tostring(istable(job.TargetModel) and job.TargetModel[1] or job.TargetModel), "Humans") and "customer" or "drop") or "customer",
			dest, job.TargetModel or { "models/Humans/Group01/Male_02.mdl", "models/Humans/Group01/Female_01.mdl" }, job, job.TargetScale)
		W.Set(ply, "job", dest, "Адрес доставки", job.Icon, job.Color, {})
		local function handOver()
			NYRP.Action(ply, "Передаю заказ...", 2.5, function()
				if IsValid(target) then target:Remove() end
				W.Clear(ply, "job")
				local money = (job.Pay or 0) + dist * (job.PayPerMeter or 0)
				local why = "доставка " .. math.floor(dist) .. " м"
				if limit then
					if CurTime() - started <= limit then money = money + (job.Tip or 0) why = why .. ", успели — чаевые"
					else money = money * 0.5 why = why .. ", опоздали" end
				end
				pay(ply, job, money, why)
				ply.nyrpJobLimit = nil
				if left and left > 1 then goDeliver(left - 1) else nextTask(ply) end
			end, job.Icon)
		end
		if IsValid(target) then
			target.OnUsed = function(_, user) if user == ply and not target.Busy then target.Busy = true handOver() timer.Simple(3, function() if IsValid(target) then target.Busy = false end end) end end
		else
			W.Set(ply, "job", dest, "Адрес доставки", job.Icon, job.Color, { radius = 90, onReach = handOver })
		end
	end
	if job.Pickup then
		task(ply, "Заберите заказ у работодателя", job.Icon)
		W.Set(ply, "job", depot, "Забрать заказ", "package", job.Color, { radius = 140, onReach = function()
			ply:EmitSound("physics/cardboard/cardboard_box_impact_soft2.wav", 55)
			goDeliver(job.Chain)
		end })
	else
		goDeliver(job.Chain)
	end
end

-- такси: пассажир у подъезда → адрес
Types.taxi = function(ply, job, fare)
	local start = fare and fare.pos or J.Spot(job.id, ply:GetPos(), 400, 2500)
	clearSpots(ply)
	local pax = spawnSpot(ply, "passenger", start, table.Random({ "models/Humans/Group01/Female_01.mdl", "models/Humans/Group01/Male_04.mdl",
		"models/Humans/Group02/Male_02.mdl", "models/Humans/Group01/Female_04.mdl" }), job)
	task(ply, fare and ("Вызов: " .. fare.name .. " ждёт такси") or "Подберите пассажира (E)", job.Icon)
	W.Set(ply, "job", start, "Пассажир", "user", job.Color, {})
	if IsValid(pax) then
		pax.OnUsed = function(_, user)
			if user ~= ply then return end
			pax:Remove()
			ply:EmitSound("doors/door_metal_thin_close2.wav", 55)
			local dest = J.Spot(job.id, start, 1000, 5000)
			local dist = meters(start, dest)
			task(ply, "Отвезите пассажира по адресу (" .. math.floor(dist) .. " м)", job.Icon)
			W.Set(ply, "job", dest, "Высадить пассажира", "map_pin", job.Color, { radius = 160, onReach = function()
				local money = (job.Pay or 0) + dist * (job.PayPerMeter or 0)
				local car = ply:InVehicle()
				if car then money = money * (job.VehicleBonus or 1) end
				pay(ply, job, money, "поездка " .. math.floor(dist) .. " м" .. (car and ", на машине" or ""))
				nextTask(ply)
			end })
		end
	end
end

-- собрать N предметов по району (если есть JOB.DropModel — собранное отнести к контейнеру, оплата там)
Types.collect = function(ply, job)
	clearSpots(ply)
	local avoid = {}
	local total = job.Count or 5
	local left = total
	local function toDrop()
		local st = J.NearestStation(job.id, ply:GetPos())
		local base = IsValid(st) and st:GetPos() or ply:GetPos()
		local p = J.Spot(job.id, base, 100, 600)
		local bin = spawnSpot(ply, "drop", p, job.DropModel, job)
		task(ply, (job.DropText or "Отнесите собранное") .. " (E)", job.Icon)
		W.Set(ply, "job", p, job.DropText or "Сдать", "trash", job.Color, {})
		if IsValid(bin) then
			bin.OnUsed = function(_, user)
				if user ~= ply or bin.Busy then return end
				bin.Busy = true
				NYRP.Action(ply, "Сдаю...", 2, function()
					if IsValid(bin) then bin:Remove() end
					W.Clear(ply, "job")
					pay(ply, job, (job.Pay or 10) * total, "сдано " .. total .. " шт.")
					nextTask(ply)
				end, "trash")
			end
		end
	end
	for i = 1, left do
		local p = J.Spot(job.id, ply:GetPos(), 300, 2200, avoid)
		avoid[p] = true
		local e = spawnSpot(ply, "collect", p + Vector(math.Rand(-30, 30), math.Rand(-30, 30), 0), job.SpotModel, job)
		if IsValid(e) then
			e.OnUsed = function(_, user)
				if user ~= ply or e.Busy then return end
				e.Busy = true
				NYRP.Action(ply, job.UseText or "Собираю...", job.UseTime or 3, function()
					if not IsValid(e) then return end
					e:Remove()
					left = left - 1
					if not job.DropModel then pay(ply, job, job.Pay, nil) end
					if left <= 0 then
						if job.DropModel then toDrop() else nextTask(ply) end
					else task(ply, "Осталось собрать: " .. left, job.Icon) end
				end, job.Icon)
				timer.Simple((job.UseTime or 3) + 0.2, function() if IsValid(e) then e.Busy = false end end)
			end
		end
	end
	W.Clear(ply, "job")
	task(ply, "Соберите по району: " .. left .. " (видны сквозь стены)", job.Icon)
end

-- починить точку
Types.repair = function(ply, job)
	clearSpots(ply)
	local p = J.Spot(job.id, ply:GetPos(), 500, 3000)
	local e = spawnSpot(ply, "repair", p, job.SpotModel, job)
	task(ply, "Вызов: " .. (job.UseText or "ремонт"):gsub("%.%.%.", "") .. " — найдите метку", job.Icon)
	W.Set(ply, "job", p, "Ремонт", "tools", job.Color, {})
	if IsValid(e) then
		e.OnUsed = function(_, user)
			if user ~= ply or e.Busy then return end
			e.Busy = true
			local skill = job.Skill and NYRP.Skills and NYRP.Skills.Level(ply, job.Skill) or 0
			local t = (job.UseTime or 6) * (1 - math.min(skill, 10) * 0.05)
			NYRP.Action(ply, job.UseText or "Чиню...", t, function()
				if not IsValid(e) then return end
				if job.FailDamage and math.random() > 0.75 + skill * 0.03 then
					local d = DamageInfo() d:SetDamage(job.FailDamage) d:SetDamageType(DMG_SHOCK) d:SetAttacker(e) d:SetInflictor(e)
					ply:TakeDamageInfo(d)
					ply:EmitSound("ambient/energy/zap" .. math.random(1, 3) .. ".wav", 70)
					NYRP.Notify(ply, "Ударило током! Попробуйте ещё раз.", "error", 4)
					e.Busy = false
					return
				end
				e:Remove()
				W.Clear(ply, "job")
				pay(ply, job, job.Pay, "ремонт выполнен")
				nextTask(ply)
			end, "tools")
			timer.Simple(t + 0.3, function() if IsValid(e) then e.Busy = false end end)
		end
	end
end

-- перенести ящики к фургону
Types.carry = function(ply, job)
	clearSpots(ply)
	local base = ply:GetPos()
	local target = J.Spot(job.id, base, 250, 900)
	local left = job.Count or 4
	for i = 1, left do
		local p = floorAt(base + Vector(math.Rand(-80, 80), math.Rand(-80, 80), 0)) or base
		local e = ents.Create("prop_physics")
		e:SetModel(util.IsValidModel(job.SpotModel or "") and job.SpotModel or "models/props_junk/cardboard_box001a.mdl")
		e:SetPos(p + Vector(0, 0, 20 + i * 4))
		e:Spawn()
		e.nyrpJobBox = { ply = ply, target = target }
		table.insert(ply.nyrpJobSpots, e)
	end
	if job.TargetModel then
		local van = spawnSpot(ply, "van", target, job.TargetModel, job, job.TargetScale)
		if IsValid(van) then
			van:SetSolid(SOLID_VPHYSICS)
			van:PhysicsInit(SOLID_VPHYSICS)
			local ph = van:GetPhysicsObject()
			if IsValid(ph) then ph:EnableMotion(false) end
			target = van:GetPos()
		end
	end
	ply.nyrpJobCarry = { target = target, left = left, job = job }
	task(ply, "Перенесите ящики к фургону: " .. left .. " (ПКМ — взять руками)", job.Icon)
	W.Set(ply, "job", target, "Фургон", "j_loader", job.Color, {})
end

-- репортаж: приехать и постоять
Types.report = function(ply, job)
	local from = ply:GetPos()
	local p = J.Spot(job.id, from, 800, 4000)
	local dist = meters(from, p)
	task(ply, "Редакция: событие по адресу — снимите репортаж", job.Icon)
	if job.TargetModel then spawnSpot(ply, "scene", p + Vector(0, 140, 0), job.TargetModel, job, job.TargetScale) end
	W.Set(ply, "job", p, "Событие", "camera", job.Color, { radius = 140, onReach = function()
		NYRP.Action(ply, job.UseText or "Снимаю...", job.UseTime or 10, function()
			clearSpots(ply)
			pay(ply, job, (job.Pay or 0) + dist * (job.PayPerMeter or 0), "репортаж в редакции")
			nextTask(ply)
		end, "camera")
	end })
end

-- ограбление кассы
Types.rob = function(ply, job)
	local c = ply.nyrpChar
	local cd = (c.flags.robNext or 0) - os.time()
	if cd > 0 then
		task(ply, "Залягте на дно: следующее дело через " .. math.ceil(cd / 60) .. " мин", job.Icon)
		timer.Create("nyrp.jobs.rob." .. ply:EntIndex(), math.min(cd, 60), 1, function() if IsValid(ply) and ply.nyrpShift then nextTask(ply) end end)
		return
	end
	clearSpots(ply)
	local p
	if NYRP.Business and NYRP.Business.RandomShopSpot then p = NYRP.Business.RandomShopSpot(ply:GetPos()) end
	p = p or J.Spot(job.id, ply:GetPos(), 500, 3000)
	local e = spawnSpot(ply, "register", p, job.SpotModel, job)
	task(ply, "Наводка: касса без охраны. Вскройте её (E) и уходите", job.Icon)
	W.Set(ply, "job", p, "Касса", "j_robber", job.Color, {})
	if IsValid(e) then
		e.OnUsed = function(_, user)
			if user ~= ply or e.Busy then return end
			e.Busy = true
			e:EmitSound("nyrp/fx/alarm.wav", 80)
			timer.Create("nyrp.alarm." .. e:EntIndex(), 1.2, 10, function() if IsValid(e) then e:EmitSound("nyrp/fx/alarm.wav", 85) end end)
			if NYRP.E911 and NYRP.E911.Auto then NYRP.E911.Auto("police", e:GetPos(), "Сработала сигнализация: ограбление кассы") end
			NYRP.Action(ply, job.UseText or "Вскрываю...", job.UseTime or 20, function()
				if not IsValid(e) then return end
				e:Remove()
				W.Clear(ply, "job")
				local r = job.Reward or { 150, 300 }
				pay(ply, job, math.random(r[1], r[2]), "добыча")
				c.flags.robNext = os.time() + (job.Cooldown or 600)
				ply:SetNW2Float("nyrp.wantedUntil", CurTime() + (job.WantedTime or 300))
				NYRP.Notify(ply, "Вы в розыске! Полиция видит метку, где вас видели.", "warning", 8)
				if NYRP.Street.AddNews then NYRP.Street.AddNews("Ограбление кассы: неизвестный скрылся с выручкой, NYPD ведёт поиск") end
				nextTask(ply)
			end, "j_robber")
			timer.Simple((job.UseTime or 20) + 0.5, function() if IsValid(e) then e.Busy = false end end)
		end
	end
end

nextTask = function(ply, fare)
	if not IsValid(ply) or not ply.nyrpShift then return end
	local job = J.Of(ply)
	if not job then return end
	timer.Simple(fare and 0 or 2.5, function()
		if not IsValid(ply) or not ply.nyrpShift or not ply:Alive() then return end
		local fn = Types[job.Type]
		if fn then fn(ply, job, fare) end
	end)
end
J.NextTask = nextTask

-- ящики грузчика доехали до фургона
timer.Create("nyrp.jobs.carry", 0.5, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local cr = ply.nyrpJobCarry
		if cr then
			for _, e in ipairs(ply.nyrpJobSpots or {}) do
				if IsValid(e) and e.nyrpJobBox and e:GetPos():Distance(cr.target) < 150 then
					e:Remove()
					cr.left = cr.left - 1
					pay(ply, cr.job, cr.job.Pay, "ящик погружен")
					if cr.left <= 0 then ply.nyrpJobCarry = nil W.Clear(ply, "job") nextTask(ply)
					else task(ply, "Перенесите ящики к фургону: " .. cr.left, cr.job.Icon) end
				end
			end
		end
	end
end)

-- ------------------------------------------------------------ точки начала смены --
local ST_FILE = function() return "nyrp/jobstations_" .. game.GetMap() .. ".json" end

function J.SaveStations()
	if J.StLoading then return end
	local out = {}
	for _, e in ipairs(ents.FindByClass("nyrp_jobstation")) do
		local p, a = e:GetPos(), e:GetAngles()
		out[#out + 1] = { job = e:GetJobId(), pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r } }
	end
	file.CreateDir("nyrp")
	file.Write(ST_FILE(), util.TableToJSON(out, true))
end

function J.SpawnStation(job, pos, ang)
	local e = ents.Create("nyrp_jobstation")
	e:SetJobId(job)
	e:SetPos(pos)
	e:SetAngles(ang)
	e:Spawn()
	return e
end

local function loadStations()
	J.StLoading = true
	for _, e in ipairs(ents.FindByClass("nyrp_jobstation")) do e:Remove() end
	for _, t in ipairs(util.JSONToTable(file.Read(ST_FILE(), "DATA") or "") or {}) do
		if J.List[t.job] then J.SpawnStation(t.job, Vector(t.pos[1], t.pos[2], t.pos[3]), Angle(t.ang[1], t.ang[2], t.ang[3])) end
	end
	J.StLoading = false
end
hook.Add("InitPostEntity", "nyrp.jobs.st", function() timer.Simple(1.5, loadStations) end)
hook.Add("PostCleanupMap", "nyrp.jobs.st", function() timer.Simple(0.5, loadStations) end)

function J.NearestStation(job, pos)
	local best, bd
	for _, e in ipairs(ents.FindByClass("nyrp_jobstation")) do
		if e:GetJobId() == job then
			local d = e:GetPos():Distance(pos)
			if not bd or d < bd then best, bd = e, d end
		end
	end
	return best, bd
end

NYRP.Chat.AddCommand("/jobstation", function(ply, raw)
	if not ply:IsAdmin() then return end
	local id = string.match(raw, "^%S+%s+(%S+)")
	if not J.List[id or ""] then NYRP.Notify(ply, "/jobstation <профессия>: " .. table.concat(J.Order, ", "), "info", 10) return end
	local tr = ply:GetEyeTrace()
	local e = J.SpawnStation(id, tr.HitPos, Angle(0, ply:EyeAngles().y + 180, 0))
	undo.Create("Точка работы") undo.AddEntity(e) undo.SetPlayer(ply) undo.Finish()
	J.SaveStations()
	NYRP.Notify(ply, "Точка начала смены «" .. J.List[id].Name .. "» поставлена", "success")
end)

local function markStation(ply, job)
	local st = J.NearestStation(job.id, ply:GetPos())
	if IsValid(st) then
		W.Set(ply, "jobstation", st:GetPos(), "Начать смену: " .. job.Name, job.Icon, job.Color, { radius = 110, onReach = function()
			NYRP.Notify(ply, "Вы на месте. E по точке — начать смену.", "info", 5)
		end })
	end
end
J.MarkStation = markStation

-- ------------------------------------------------------------ смена и найм --
local function stopShift(ply, quiet)
	if not ply.nyrpShift then return end
	ply.nyrpShift = nil
	ply.nyrpJobCarry = nil
	ply:SetNW2Bool("nyrp.onShift", false)
	clearSpots(ply)
	W.Clear(ply, "job")
	timer.Remove("nyrp.jobs.rob." .. ply:EntIndex())
	task(ply, "", "")
	if not quiet then NYRP.Notify(ply, "Смена окончена. Заработано: " .. NYRP.Money.Format(ply.nyrpShiftEarned or 0), "info", 6) end
end
J.StopShift = stopShift

function J.Check(ply, id)
	local j = J.List[id]
	local c = ply.nyrpChar
	local out = {}
	if not j or not c then return { "Нет такой работы" } end
	local role = NYRP.Roles and NYRP.Roles.Of(ply)
	if role and role.Jobs == false and not role.Default then out[#out + 1] = "Только для гражданских (вы на службе)" end
	local hours = (c.flags and c.flags.played or 0) / 3600
	if (j.MinHours or 0) > 0 and hours < j.MinHours then out[#out + 1] = string.format("Отыграть %d ч", j.MinHours) end
	for sk, lv in pairs(j.MinSkills or {}) do
		if (c.skills and c.skills[sk] or 0) < lv then out[#out + 1] = "Навык " .. sk .. " " .. lv end
	end
	return out
end

local function sendMenu(ply, ent)
	if IsValid(ent) then ply.nyrpJobDepot = ent:GetPos() end
	local list = {}
	ent = IsValid(ent) and ent or ply.nyrpJobNPC
	ply.nyrpJobNPC = ent
	local only = IsValid(ent) and ent.NPCData and ent.NPCData.jobs
	if not (only and next(only)) then only = nil end
	for _, id in ipairs(J.Order) do
		if not only or only[id] then
			local n = 0
			for _, p in ipairs(player.GetAll()) do if p:GetNW2String("nyrp.job") == id then n = n + 1 end end
			list[#list + 1] = { id = id, workers = n, problems = J.Check(ply, id) }
		end
	end
	local c = ply.nyrpChar
	net.Start("nyrp.jobs")
	net.WriteTable(list)
	net.WriteUInt(math.floor(c and c.flags.jobEarned or 0), 32)
	net.WriteUInt(c and c.flags.jobTasks or 0, 16)
	net.Send(ply)
end

hook.Add("NYRP.NPCMenu", "nyrp.jobs", function(ply, ent, act) if act == "jobs" then sendMenu(ply, ent) end end)

net.Receive("nyrp.jobs.act", function(_, ply)
	if (ply.nyrpJobNext or 0) > CurTime() or not NYRP.HasCharacter(ply) then return end
	ply.nyrpJobNext = CurTime() + 0.8
	local act, id = net.ReadString(), net.ReadString()
	local c = ply.nyrpChar
	if act == "hire" then
		local j = J.List[id]
		if not j then return end
		local problems = J.Check(ply, id)
		if #problems > 0 then NYRP.Notify(ply, "Нельзя: " .. problems[1], "error") return end
		stopShift(ply, true)
		c.flags.job = id
		ply:SetNW2String("nyrp.job", id)
		ply:EmitSound("nyrp/fx/stamp.wav", 55)
		NYRP.Notify(ply, "Вы устроились: " .. j.Name .. ". Идите к точке работы (метка) и начните смену.", "success", 7)
		markStation(ply, j)
		sendMenu(ply)
	elseif act == "quit" then
		stopShift(ply, true)
		c.flags.job = nil
		ply:SetNW2String("nyrp.job", "")
		NYRP.Notify(ply, "Вы уволились", "info")
		sendMenu(ply)
	elseif act == "shift" then
		J.ToggleShift(ply)
	end
end)

function J.ToggleShift(ply, fromStation)
	local job = J.Of(ply)
	if not job then NYRP.Notify(ply, "Сначала устройтесь на работу в центре занятости", "warning") return end
	if ply.nyrpShift then stopShift(ply) return end
	-- если у профессии есть точки — смена начинается у точки
	local st, d = J.NearestStation(job.id, ply:GetPos())
	if IsValid(st) and d > 200 and not fromStation then
		NYRP.Notify(ply, "Смену начинают у точки работы — метка поставлена", "warning", 5)
		markStation(ply, job)
		return
	end
	W.Clear(ply, "jobstation")
	ply.nyrpShift = true
	ply.nyrpShiftEarned = 0
	ply.nyrpJobSpots = {}
	ply:SetNW2Bool("nyrp.onShift", true)
	ply:EmitSound("nyrp/fx/job_start.wav", 55)
	NYRP.Notify(ply, "Смена началась: " .. job.Name .. ". Закончить — /shift", "success", 6)
	nextTask(ply)
end
NYRP.Chat.AddCommand("/shift", function(ply) J.ToggleShift(ply) end)
NYRP.Chat.AddCommand("/смена", function(ply) J.ToggleShift(ply) end)

hook.Add("NYRP.CharacterLoaded", "nyrp.jobs", function(ply, c)
	stopShift(ply, true)
	ply:SetNW2String("nyrp.job", J.List[c.flags and c.flags.job or ""] and c.flags.job or "")
end)
hook.Add("PlayerDeath", "nyrp.jobs", function(ply) if ply.nyrpShift then stopShift(ply) end end)
hook.Add("PlayerDisconnected", "nyrp.jobs", function(ply) clearSpots(ply) end)
hook.Add("NYRP.RoleChanged", "nyrp.jobs", function(ply, id)
	local r = NYRP.Roles.List[id]
	if r and not r.Default and r.Jobs == false and ply.nyrpChar then
		stopShift(ply, true)
		ply.nyrpChar.flags.job = nil
		ply:SetNW2String("nyrp.job", "")
	end
end)

-- розыск: метка у полиции, пока грабитель в розыске
timer.Create("nyrp.jobs.wanted", 5, 0, function()
	for _, crim in ipairs(player.GetAll()) do
		if J.Wanted(crim) and crim:Alive() then
			for _, cop in ipairs(player.GetAll()) do
				if cop:GetNW2String("nyrp.role") == "police" then
					W.Set(cop, "wanted" .. crim:EntIndex(), crim:GetPos(), "Подозреваемый (последнее место)", "lock", Color(230, 70, 60), {})
				end
			end
		elseif crim.nyrpWasWanted then
			for _, cop in ipairs(player.GetAll()) do W.Clear(cop, "wanted" .. crim:EntIndex()) end
		end
		crim.nyrpWasWanted = J.Wanted(crim)
	end
end)
