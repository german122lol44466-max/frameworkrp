local E = NYRP.E911
NYRP.Waypoint = NYRP.Waypoint or {}
local W = NYRP.Waypoint   -- модуль меток грузится позже (по алфавиту) — берём общую таблицу заранее
E.Calls = E.Calls or {}
local lastId = 0

-- службы: роли с ROLE.Service и работы с JOB.Service
local function services()
	local out = {}
	for _, id in ipairs(NYRP.Roles.Order) do
		local r = NYRP.Roles.List[id]
		if r.Service then out[#out + 1] = { key = "role:" .. id, name = r.Service, icon = r.Icon, color = r.Color, calls = r.Calls or { "Другое" } } end
	end
	for _, id in ipairs(NYRP.Jobs and NYRP.Jobs.Order or {}) do
		local j = NYRP.Jobs.List[id]
		if j.Service then out[#out + 1] = { key = "job:" .. id, name = j.Service, icon = j.Icon, color = j.Color, calls = j.Calls or { "Вызов" }, job = true } end
	end
	return out
end
E.Services = services

local function responders(key)
	local kind, id = string.match(key, "^(%a+):(.+)$")
	local out = {}
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and NYRP.HasCharacter(p) then
			if kind == "role" and p:GetNW2String("nyrp.role") == id then out[#out + 1] = p end
			if kind == "job" and p:GetNW2String("nyrp.job") == id and p:GetNW2Bool("nyrp.onShift") then out[#out + 1] = p end
		end
	end
	return out
end

net.Receive("nyrp.e911", function(_, ply)
	if (ply.nyrp911Next or 0) > CurTime() then return end
	ply.nyrp911Next = CurTime() + 0.5
	local list = services()
	for _, s in ipairs(list) do s.online = #responders(s.key) end
	net.Start("nyrp.e911")
	net.WriteTable(list)
	net.Send(ply)
end)

local function dispatch(call)
	local recips = responders(call.key)
	for _, p in ipairs(recips) do
		if p ~= call.caller then
			net.Start("nyrp.e911.call")
			net.WriteUInt(call.id, 16)
			net.WriteString(call.service)
			net.WriteString(call.reason)
			net.WriteString(call.comment or "")
			net.WriteString(call.from or "")
			net.WriteVector(call.pos)
			net.Send(p)
			W.Set(p, "911_" .. call.id, call.pos, "911: " .. call.reason, "urgent", Color(230, 70, 60), {})
		end
	end
	return #recips
end

-- автоматический вызов (сигнализация и т.п.): roleId — id роли
function E.Auto(roleId, pos, reason)
	lastId = lastId + 1
	local r = NYRP.Roles.List[roleId]
	local call = { id = lastId, key = "role:" .. roleId, service = r and r.Service or roleId, reason = reason, comment = "Автоматический вызов",
		from = "Система охраны", pos = pos, time = CurTime() }
	E.Calls[call.id] = call
	dispatch(call)
end

net.Receive("nyrp.e911.call", function(_, ply)
	if (ply.nyrp911Call or 0) > CurTime() or not NYRP.HasCharacter(ply) then return end
	local key, reason, comment = net.ReadString(), net.ReadString(), string.sub(net.ReadString(), 1, 140)
	local svc
	for _, s in ipairs(services()) do if s.key == key then svc = s end end
	if not svc then return end
	ply.nyrp911Call = CurTime() + 20
	lastId = lastId + 1
	local z = NYRP.Zones and NYRP.Zones.At and NYRP.Zones.At(ply:GetPos())
	local call = { id = lastId, key = key, service = svc.name, reason = reason, comment = comment, caller = ply,
		from = NYRP.CharName(ply) .. (z and (" · " .. z.name) or ""), pos = ply:GetPos(), time = CurTime() }
	E.Calls[call.id] = call
	local n = dispatch(call)
	if n == 0 then
		NYRP.Notify(ply, "Диспетчер: свободных экипажей «" .. svc.name .. "» сейчас нет. Вызов записан.", "warning", 7)
	else
		NYRP.Notify(ply, "Диспетчер: вызов принят, «" .. svc.name .. "» уведомлены (" .. n .. ")", "success", 6)
	end
	ply:EmitSound("nyrp/fx/dispatch.wav", 50)
end)

local function accept(ply, id)
	local call = E.Calls[id]
	if not call then NYRP.Notify(ply, "Вызов уже неактуален", "warning") return end
	if call.taken then NYRP.Notify(ply, "Вызов уже принял другой экипаж", "warning") return end
	local ok = false
	for _, p in ipairs(responders(call.key)) do if p == ply then ok = true end end
	if not ok then return end
	call.taken = ply
	for _, p in ipairs(player.GetAll()) do if p ~= ply then W.Clear(p, "911_" .. id) end end
	W.Set(ply, "911_" .. id, call.pos, "911: " .. call.reason, "urgent", Color(230, 70, 60), { radius = 150, onReach = function()
		NYRP.Notify(ply, "Вы на месте вызова", "info", 4)
	end })
	NYRP.Notify(ply, "Вызов принят: " .. call.reason, "success")
	if IsValid(call.caller) then
		NYRP.Notify(call.caller, "Диспетчер: «" .. call.service .. "» едут к вам — " .. NYRP.CharName(ply), "success", 8)
		call.caller:EmitSound("nyrp/fx/dispatch.wav", 45)
	end
	-- такси: вызов игрока — пассажир не нужен, просто доехать
	if string.StartWith(call.key, "job:") and ply.nyrpShift then
		NYRP.Jobs.Task(ply, "Вызов такси: " .. call.from .. " — доберитесь до метки", "j_taxi")
	end
end

net.Receive("nyrp.e911.accept", function(_, ply) accept(ply, net.ReadUInt(16)) end)
NYRP.Chat.AddCommand("/911accept", function(ply)
	local best
	for id, c in pairs(E.Calls) do if not c.taken and (not best or id > best) then best = id end end
	if best then accept(ply, best) else NYRP.Notify(ply, "Нет новых вызовов", "info") end
end)

-- старые вызовы забываем через 10 минут
timer.Create("nyrp.e911.gc", 30, 0, function()
	for id, c in pairs(E.Calls) do
		if CurTime() - c.time > 600 then
			E.Calls[id] = nil
			for _, p in ipairs(player.GetAll()) do W.Clear(p, "911_" .. id) end
		end
	end
end)
