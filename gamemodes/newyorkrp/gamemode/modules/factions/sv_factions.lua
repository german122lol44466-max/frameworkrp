local F = NYRP.Factions
local W = NYRP.Waypoint
local Roles = NYRP.Roles

local function role(ply) return ply:GetNW2String("nyrp.role", "") end

-- ----------------------------------------------------------- сохранение объектов --
local CLASSES = { nyrp_terminal = true, nyrp_armory = true, nyrp_hospital_bed = true }
local FILE = function() return "nyrp/faction_props_" .. game.GetMap() .. ".json" end
function F.Save()
	if F.Loading then return end
	local out = {}
	for cls in pairs(CLASSES) do
		for _, e in ipairs(ents.FindByClass(cls)) do
			local p, a = e:GetPos(), e:GetAngles()
			out[#out + 1] = { cls = cls, role = e.GetRole and e:GetRole() or "", pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r } }
		end
	end
	file.CreateDir("nyrp")
	file.Write(FILE(), util.TableToJSON(out, true))
end
function F.Spawn(cls, roleId, pos, ang)
	local e = ents.Create(cls)
	if not IsValid(e) then return end
	if e.SetRole then e:SetRole(roleId or "") end
	e:SetPos(pos)
	e:SetAngles(ang)
	e:Spawn()
	return e
end
local function load()
	F.Loading = true
	for cls in pairs(CLASSES) do for _, e in ipairs(ents.FindByClass(cls)) do e:Remove() end end
	for _, t in ipairs(util.JSONToTable(file.Read(FILE(), "DATA") or "") or {}) do
		if CLASSES[t.cls] then F.Spawn(t.cls, t.role, Vector(t.pos[1], t.pos[2], t.pos[3]), Angle(t.ang[1], t.ang[2], t.ang[3])) end
	end
	F.Loading = false
end
hook.Add("InitPostEntity", "nyrp.factions", function() timer.Simple(1, load) end)
hook.Add("PostCleanupMap", "nyrp.factions", function() timer.Simple(0, load) end)
hook.Add("PhysgunDrop", "nyrp.factions", function(_, e) if CLASSES[e:GetClass()] then timer.Simple(0, F.Save) end end)

local function place(cls, needRole)
	return function(ply, raw)
		if not ply:IsAdmin() then return end
		local r = string.match(raw, "^%S+%s+(%S+)")
		if needRole and not Roles.List[r or ""] then NYRP.Notify(ply, "Укажите роль: police, medic, fire", "info") return end
		local tr = ply:GetEyeTrace()
		local e = F.Spawn(cls, r, tr.HitPos, Angle(0, ply:EyeAngles().y + 180, 0))
		if not IsValid(e) then return end
		if cls ~= "nyrp_terminal" then e:SetPos(tr.HitPos - Vector(0, 0, e:OBBMins().z)) end
		undo.Create("Объект службы") undo.AddEntity(e) undo.SetPlayer(ply) undo.Finish()
		F.Save()
		NYRP.Notify(ply, "Поставлено и сохранено", "success")
	end
end
NYRP.Chat.AddCommand("/terminal", place("nyrp_terminal", true))
NYRP.Chat.AddCommand("/armory", place("nyrp_armory", true))
NYRP.Chat.AddCommand("/bed", place("nyrp_hospital_bed", false))

-- ------------------------------------------------------------------- устав --
local charterCache = {}
local function charter(r)
	if charterCache[r] then return charterCache[r] end
	local txt = file.Read(NYRP.Root .. "framework/charters/" .. r .. ".txt", "LUA") or ("Устав для «" .. r .. "» ещё не написан.\nСоздайте файл framework/charters/" .. r .. ".txt")
	charterCache[r] = txt
	return txt
end

-- ------------------------------------------------------------------ терминал --
local function sendTerminal(ply, ent)
	local r = ent:GetRole()
	local data = { role = r, charter = charter(r), calls = {}, staff = {}, extra = {} }
	local svc = Roles.List[r] and Roles.List[r].Service
	for id, c in pairs(NYRP.E911.Calls or {}) do
		if c.key == "role:" .. r then
			data.calls[#data.calls + 1] = { id = id, reason = c.reason, from = c.from or "", comment = c.comment or "",
				taken = IsValid(c.taken) and NYRP.CharName(c.taken) or nil, ago = math.floor(CurTime() - c.time) }
		end
	end
	table.sort(data.calls, function(a, b) return a.id > b.id end)
	for _, p in ipairs(player.GetAll()) do
		if role(p) == r then data.staff[#data.staff + 1] = { name = NYRP.CharName(p), alive = p:Alive() } end
	end
	if r == "police" then
		for _, p in ipairs(player.GetAll()) do
			if NYRP.Jobs.Wanted(p) then data.extra[#data.extra + 1] = { id = p:EntIndex(), text = "Подозреваемый (приметы: " .. string.sub(p:GetNW2String("nyrp.desc", "?"), 1, 60) .. ")",
				left = math.floor(p:GetNW2Float("nyrp.wantedUntil") - CurTime()) } end
		end
		data.people = {}
		for _, p in ipairs(player.GetAll()) do if NYRP.HasCharacter(p) and p ~= ply then data.people[#data.people + 1] = NYRP.CharName(p) end end
	elseif r == "medic" then
		for _, p in ipairs(player.GetAll()) do
			if p:Alive() and NYRP.HasCharacter(p) then
				local st = {}
				if NYRP.Cond.KO(p) then st[#st + 1] = p:GetNW2Bool("nyrp.koCritical") and "КРИТИЧЕСКОЕ, без сознания" or "без сознания" end
				if p:GetNW2Bool("nyrp.bleeding") then st[#st + 1] = "кровотечение" end
				if p:Health() < 40 then st[#st + 1] = "здоровье " .. p:Health() .. "%" end
				if #st > 0 then data.extra[#data.extra + 1] = { id = p:EntIndex(), text = NYRP.CharName(p) .. ": " .. table.concat(st, ", ") } end
			end
		end
	elseif r == "fire" then
		for _, e in ipairs(ents.FindByClass("nyrp_fire")) do
			data.extra[#data.extra + 1] = { id = e:EntIndex(), text = "Очаг: сила " .. math.floor(e:GetPower()) .. "%" }
		end
	end
	net.Start("nyrp.terminal")
	net.WriteEntity(ent)
	net.WriteTable(data)
	net.Send(ply)
end
F.SendTerminal = sendTerminal

net.Receive("nyrp.terminal.act", function(_, ply)
	if (ply.nyrpTermNext or 0) > CurTime() then return end
	ply.nyrpTermNext = CurTime() + 0.5
	local ent, act, a, b, c = net.ReadEntity(), net.ReadString(), net.ReadString(), net.ReadString(), net.ReadString()
	if not IsValid(ent) or ent:GetClass() ~= "nyrp_terminal" or ent:GetPos():Distance(ply:GetPos()) > 200 or role(ply) ~= ent:GetRole() then return end
	if act == "accept" then
		ply:ConCommand("say /911accept")   -- верхний непринятый вызов
	elseif act == "mark" then
		local e = Entity(tonumber(a) or -1)
		if IsValid(e) then W.Set(ply, "term" .. e:EntIndex(), e:GetPos(), b ~= "" and b or "Метка из терминала", "map_pin", Color(230, 70, 60), { radius = 150 }) end
	elseif act == "fine" and ent:GetRole() == "police" then
		local amount = math.Clamp(math.floor(tonumber(b) or 0), 1, 10000)
		for _, p in ipairs(player.GetAll()) do
			if NYRP.CharName(p) == a then
				NYRP.Bank.AddFine(p, amount, c ~= "" and c or "Штраф NYPD")
				NYRP.Notify(ply, "Штраф выписан: " .. a .. ", " .. NYRP.Money.Format(amount), "success")
				ply:EmitSound("nyrp/fx/stamp.wav", 55)
				return
			end
		end
		NYRP.Notify(ply, "Человек не найден", "error")
	elseif act == "duty" then
		ply.nyrpOnDuty = not ply.nyrpOnDuty
		ply:SetNW2Bool("nyrp.onDuty", ply.nyrpOnDuty)
		NYRP.Notify(ply, ply.nyrpOnDuty and "Вы заступили на смену" or "Смена окончена", "info")
	end
	timer.Simple(0.2, function() if IsValid(ply) and IsValid(ent) then sendTerminal(ply, ent) end end)
end)

-- ----------------------------------------------------------- служебные двери --
-- /doorfaction <роль|off>: дверь открывают только сотрудники (остальным — заперто)
NYRP.Chat.AddCommand("/doorfaction", function(ply, raw)
	if not ply:IsAdmin() then return end
	local r = string.match(raw, "^%S+%s+(%S+)")
	local e = ply:GetEyeTrace().Entity
	if not IsValid(e) or not string.find(e:GetClass(), "door") then NYRP.Notify(ply, "Посмотрите на дверь", "warning") return end
	if not e:CreatedByMap() then return end
	local t = util.JSONToTable(file.Read("nyrp/faction_doors_" .. game.GetMap() .. ".json", "DATA") or "") or {}
	local id = tostring(e:MapCreationID())
	if r == "off" or not Roles.List[r or ""] then
		t[id] = nil
		e:SetNW2String("nyrp.doorRole", "")
		NYRP.Notify(ply, r == "off" and "Дверь снова общая" or "/doorfaction <police|medic|fire|off>", "info")
	else
		t[id] = r
		e:SetNW2String("nyrp.doorRole", r)
		NYRP.Notify(ply, "Служебная дверь: " .. Roles.List[r].Name, "success")
	end
	file.CreateDir("nyrp")
	file.Write("nyrp/faction_doors_" .. game.GetMap() .. ".json", util.TableToJSON(t, true))
end)
hook.Add("InitPostEntity", "nyrp.factions.doors", function()
	timer.Simple(2, function()
		for id, r in pairs(util.JSONToTable(file.Read("nyrp/faction_doors_" .. game.GetMap() .. ".json", "DATA") or "") or {}) do
			local e = ents.GetMapCreatedEntity(tonumber(id))
			if IsValid(e) then e:SetNW2String("nyrp.doorRole", r) end
		end
	end)
end)
hook.Add("PlayerUse", "nyrp.factions.doors", function(ply, e)
	local r = IsValid(e) and e:GetNW2String("nyrp.doorRole", "") or ""
	if r ~= "" and role(ply) ~= r then
		if (ply.nyrpDoorMsg or 0) < CurTime() then
			ply.nyrpDoorMsg = CurTime() + 2
			NYRP.Notify(ply, "Служебное помещение: только " .. (Roles.List[r] and Roles.List[r].Name or r), "warning", 3)
			e:EmitSound("doors/default_locked.wav", 55)
		end
		return false
	end
end)

-- ------------------------------------------------------------------ наручники --
function F.Cuff(ply, target, on)
	target:SetNW2Bool("nyrp.cuffed", on)
	target:SetNW2Entity("nyrp.cuffedBy", on and ply or NULL)
	target.nyrpDraggedBy = nil
	if on then
		target:SelectWeapon("nyrp_hands")
		target:EmitSound("nyrp/fx/lock_turn.wav", 60, 140)
		NYRP.Notify(target, "На вас надели наручники", "warning")
	else
		target:EmitSound("nyrp/fx/lock_turn.wav", 60, 120)
		NYRP.Notify(target, "С вас сняли наручники", "info")
	end
end
hook.Add("PlayerSwitchWeapon", "nyrp.cuffs", function(ply, old, new) if F.Cuffed(ply) and IsValid(new) and new:GetClass() ~= "nyrp_hands" then return true end end)
hook.Add("PlayerDeath", "nyrp.cuffs", function(ply) if F.Cuffed(ply) then F.Cuff(ply, ply, false) end end)
hook.Add("CanPlayerEnterVehicle", "nyrp.cuffs", function(ply) if F.Cuffed(ply) and not ply.nyrpDraggedBy then return false end end)
-- ведут: задержанный идёт за полицейским
hook.Add("Think", "nyrp.cuffs.drag", function()
	for _, p in ipairs(player.GetAll()) do
		local cop = p.nyrpDraggedBy
		if cop then
			if not IsValid(cop) or not cop:Alive() or not p:Alive() or not F.Cuffed(p) then p.nyrpDraggedBy = nil
			else
				local want = cop:GetPos() - cop:GetForward() * 40
				local d = want - p:GetPos()
				d.z = 0
				if d:Length() > 20 then p:SetVelocity(d:GetNormalized() * math.min(d:Length() * 4, 220) - p:GetVelocity() * 0.5) end
				if d:Length() > 300 then p:SetPos(want) end
			end
		end
	end
end)

-- ------------------------------------------------------- EMS: автовызов скорой --
hook.Add("Think", "nyrp.ems.auto", function()
	if (F.nextEMS or 0) > CurTime() then return end
	F.nextEMS = CurTime() + 5
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and NYRP.Cond.KO(p) and p:GetNW2Bool("nyrp.koCritical") and (p.nyrpEMSCalled or 0) < CurTime() then
			p.nyrpEMSCalled = CurTime() + 120
			NYRP.E911.Auto("medic", p:GetPos(), "Человек без сознания, критическое состояние")
		end
	end
end)

-- реанимация дефибриллятором
function F.Revive(medic, rag)
	local owner = rag:GetNW2Entity("nyrp.corpseOwner")
	if not IsValid(owner) or owner:Alive() then return false end
	if CurTime() - rag:GetNW2Float("nyrp.corpseTime", 0) > 30 then return false end
	local pos = rag:WorldSpaceCenter()
	owner.nyrpSpawnHealth = 25
	owner:Spawn()
	owner:SetPos(pos + Vector(0, 0, 4))
	owner:SetHealth(25)
	rag:Remove()
	NYRP.Notify(owner, "Вас вернули с того света: " .. NYRP.CharName(medic), "success", 8)
	return true
end

-- ------------------------------------------------------------- FDNY: пожары --
function F.StartFire(pos, power, quiet)
	local e = ents.Create("nyrp_fire")
	if not IsValid(e) then return end
	e:SetPos(pos)
	e:Spawn()
	e:SetPower(power or 60)
	if not quiet then
		NYRP.E911.Auto("fire", pos, "Пожар!")
		if NYRP.Street.AddNews then NYRP.Street.AddNews("Пожар в городе: на место выехали расчёты FDNY") end
	end
	return e
end
NYRP.Chat.AddCommand("/fire", function(ply)
	if not ply:IsAdmin() then return end
	F.StartFire(ply:GetEyeTrace().HitPos + Vector(0, 0, 2), 70)
	NYRP.Notify(ply, "Пожар начался", "warning")
end)
NYRP.Chat.AddCommand("/fireclear", function(ply)
	if not ply:IsAdmin() then return end
	for _, e in ipairs(ents.FindByClass("nyrp_fire")) do e:Remove() end
end)
-- случайные пожары раз в 25–45 минут, если на смене есть пожарные
timer.Create("nyrp.fire.random", 60, 0, function()
	F.fireAt = F.fireAt or (CurTime() + math.random(1500, 2700))
	if CurTime() < F.fireAt then return end
	F.fireAt = CurTime() + math.random(1500, 2700)
	local n = 0
	for _, p in ipairs(player.GetAll()) do if role(p) == "fire" then n = n + 1 end end
	if n == 0 or #ents.FindByClass("nyrp_fire") > 0 then return end
	local doors = NYRP.Jobs.Doors or {}
	if #doors == 0 then return end
	F.StartFire(doors[math.random(#doors)], 60)
end)
-- потушил — премия
function F.Extinguished(ply, fire)
	if not IsValid(ply) then return end
	if role(ply) == "fire" then
		NYRP.Money.Add(ply, 40)
		ply:EmitSound("nyrp/fx/cash.wav", 50)
		NYRP.Notify(ply, "Очаг потушен: премия +$40", "success")
		NYRP.Skills.AddXP(ply, "strength", 10)
	else
		NYRP.Notify(ply, "Очаг потушен", "success")
	end
end

-- огнетушитель: конус струи гасит пламя (вызывается из SWEP nyrp_extinguisher)
function F.Douse(ply, origin, dir, range, amount)
	for _, e in ipairs(ents.FindInSphere(origin, range)) do
		if e:GetClass() == "nyrp_fire" then
			local to = e:GetPos() + Vector(0, 0, 20) - origin
			if to:GetNormalized():Dot(dir) > 0.8 then
				local left = e:GetPower() - amount
				if left <= 0 then
					e:Remove()
					F.Extinguished(ply, e)
				else
					e:SetPower(left)
				end
			end
		elseif e.IsOnFire and e:IsOnFire() and (e:GetPos() - origin):GetNormalized():Dot(dir) > 0.8 then
			e:Extinguish()
		end
	end
end
