--[[
	Отряды (лобби) на сервере.

	Пока игрок в меню (не в игре): заморожен, невидим, неуязвим, без оружия.
	Каждый, кто нажал «Играть», получает свой отряд и становится его командиром.
	Приглашение: участник отряда выбирает игрока из тех, кто в меню → тому приходит запрос на InviteTime секунд →
	при согласии он переходит в отряд пригласившего. Командир нажимает «Выдвигаться» — весь отряд появляется в игре
	с моделью и оружием из конфига.
]]

local L = WS.Lobby
local C = WS.Config

for _, n in ipairs({ "ws.lobby.open", "ws.lobby.invite", "ws.lobby.invited", "ws.lobby.answer", "ws.lobby.leave",
	"ws.lobby.kick", "ws.lobby.callsign", "ws.lobby.start", "ws.lobby.started", "ws.lobby.notify" }) do
	util.AddNetworkString(n)
end

local nextId = 0
local pending = {}   -- [target] = { lobby, from, expires }

local function notify(ply, text, snd)
	net.Start("ws.lobby.notify")
	net.WriteString(text)
	net.WriteString(snd or "")
	net.Send(ply)
end

-- Не чаще, чем раз в delay секунд на действие
local function throttle(ply, key, delay)
	ply.wsThrottle = ply.wsThrottle or {}
	local now = CurTime()
	if (ply.wsThrottle[key] or 0) > now then return true end
	ply.wsThrottle[key] = now + delay
	return false
end

local function setLobby(ply, id, lead)
	ply:SetNW2Int("ws_lobby", id)
	ply:SetNW2Float("ws_lobby_t", CurTime())
	ply:SetNW2Bool("ws_lead", lead and true or false)
end

-- Если у отряда не осталось командира — им становится тот, кто пришёл раньше всех
local function ensureLeader(id)
	if id == 0 then return end
	local m = L.Members(id)
	if #m == 0 then return end
	for _, p in ipairs(m) do
		if L.IsLeader(p) then return end
	end
	table.sort(m, function(a, b) return a:GetNW2Float("ws_lobby_t", 0) < b:GetNW2Float("ws_lobby_t", 0) end)
	m[1]:SetNW2Bool("ws_lead", true)
	notify(m[1], "Вы теперь командир отряда.", "join")
end

local function newSolo(ply)
	local old = L.Id(ply)
	nextId = nextId + 1
	setLobby(ply, nextId, true)
	ensureLeader(old)
end

local function join(ply, id)
	local old = L.Id(ply)
	setLobby(ply, id, false)
	ensureLeader(old)
	for _, p in ipairs(L.Members(id)) do
		if p ~= ply then notify(p, L.Name(ply) .. " вступил в отряд.", "join") end
	end
end

-- ---------------------------------------------------------------- состояние «в меню»

function L.ApplyMenuState(ply)
	if L.InGame(ply) then return end
	ply:StripWeapons()
	ply:Freeze(true)
	ply:GodEnable()
	ply:SetNoDraw(true)
	ply:SetNotSolid(true)
	ply:DrawShadow(false)
end

local function leaveMenuState(ply)
	ply:Freeze(false)
	ply:GodDisable()
	ply:SetNoDraw(false)
	ply:SetNotSolid(false)
	ply:DrawShadow(true)
end

hook.Add("PlayerInitialSpawn", "ws.lobby", function(ply)
	ply:SetNW2Bool("ws_ingame", false)
	local cs = L.CleanCallsign(ply:GetPData("ws_callsign", ""))
	if cs then ply:SetNW2String("ws_callsign", cs) end
end)

hook.Add("PlayerSpawn", "ws.lobby", function(ply)
	if not L.InGame(ply) then
		timer.Simple(0, function() if IsValid(ply) then L.ApplyMenuState(ply) end end)
	end
end)

-- В меню — без стандартного набора оружия; в игре — набор отряда
hook.Add("PlayerLoadout", "ws.lobby", function(ply)
	if not L.InGame(ply) then return true end
	for _, cls in ipairs(C.SquadWeapons) do
		if weapons.GetStored(cls) then ply:Give(cls) end
	end
	if weapons.GetStored(C.SquadWeapons[1]) then ply:SelectWeapon(C.SquadWeapons[1]) end
	return true
end)

hook.Add("PlayerSetModel", "ws.lobby", function(ply)
	if not L.InGame(ply) then return end
	ply:SetModel(util.IsValidModel(C.SquadModel) and C.SquadModel or C.SquadModelFallback)
	ply:SetupHands()
	return true
end)

hook.Add("PlayerDisconnected", "ws.lobby", function(ply)
	local id = L.Id(ply)
	pending[ply] = nil
	ply:SetNW2Int("ws_lobby", 0)
	ply:SetNW2Bool("ws_lead", false)
	timer.Simple(0, function() ensureLeader(id) end)
end)

-- ---------------------------------------------------------------- сообщения от клиентов

-- Игрок открыл лобби: если отряда нет — создаём ему свой
net.Receive("ws.lobby.open", function(_, ply)
	if throttle(ply, "open", 0.5) or L.InGame(ply) then return end
	if L.Id(ply) == 0 then newSolo(ply) end
end)

net.Receive("ws.lobby.invite", function(_, ply)
	local target = net.ReadEntity()
	if throttle(ply, "invite", 1) or L.InGame(ply) then return end
	local id = L.Id(ply)
	if id == 0 or not IsValid(target) or not target:IsPlayer() or target == ply then return end
	if L.InGame(target) or L.Id(target) == id then return end
	if #L.Members(id) >= C.SquadSize then notify(ply, "В отряде нет мест.", "error") return end
	local p = pending[target]
	if p and p.expires > CurTime() and p.from == ply then notify(ply, "Приглашение уже отправлено.", "error") return end
	pending[target] = { lobby = id, from = ply, expires = CurTime() + C.InviteTime }
	net.Start("ws.lobby.invited")
	net.WriteEntity(ply)
	net.WriteFloat(C.InviteTime)
	net.Send(target)
	notify(ply, "Приглашение отправлено: " .. L.Name(target) .. ".", "click")
end)

net.Receive("ws.lobby.answer", function(_, ply)
	local accept = net.ReadBool()
	local p = pending[ply]
	pending[ply] = nil
	if not p or p.expires < CurTime() or L.InGame(ply) then return end
	if not accept then
		if IsValid(p.from) then notify(p.from, L.Name(ply) .. " отклонил приглашение.", "error") end
		return
	end
	-- отряд мог измениться, пока игрок думал
	local members = L.Members(p.lobby)
	if #members == 0 or L.InGame(members[1]) then notify(ply, "Отряд уже недоступен.", "error") return end
	if #members >= C.SquadSize then notify(ply, "В отряде уже нет мест.", "error") return end
	join(ply, p.lobby)
end)

net.Receive("ws.lobby.leave", function(_, ply)
	if throttle(ply, "leave", 1) or L.InGame(ply) then return end
	if #L.Members(L.Id(ply)) <= 1 then return end
	newSolo(ply)
	notify(ply, "Вы покинули отряд.", "click")
end)

net.Receive("ws.lobby.kick", function(_, ply)
	local target = net.ReadEntity()
	if throttle(ply, "kick", 0.5) or not L.IsLeader(ply) or L.InGame(ply) then return end
	if not IsValid(target) or target == ply or L.Id(target) ~= L.Id(ply) or L.InGame(target) then return end
	newSolo(target)
	notify(target, "Командир исключил вас из отряда.", "error")
end)

net.Receive("ws.lobby.callsign", function(_, ply)
	local raw = net.ReadString()
	if throttle(ply, "callsign", 1) then return end
	if raw == "" then
		ply:SetNW2String("ws_callsign", "")
		ply:RemovePData("ws_callsign")
		return
	end
	local cs = L.CleanCallsign(raw)
	if not cs then
		notify(ply, string.format("Позывной: %d–%d символов, буквы, цифры, пробел, - _ .", C.CallsignMin, C.CallsignMax), "error")
		return
	end
	ply:SetNW2String("ws_callsign", cs)
	ply:SetPData("ws_callsign", cs)
end)

-- Командир выводит отряд в игру
net.Receive("ws.lobby.start", function(_, ply)
	if throttle(ply, "start", 2) or L.InGame(ply) then return end
	local all = L.Members(L.Id(ply))
	-- если часть отряда уже в бою — любой боец может вернуться к ним сам; иначе выводит командир весь отряд
	local fighting = false
	for _, p in ipairs(all) do if L.InGame(p) then fighting = true end end
	if not fighting and not L.IsLeader(ply) then return end
	local members = {}
	for _, p in ipairs(fighting and { ply } or all) do
		if not L.InGame(p) then members[#members + 1] = p end
	end
	for _, p in ipairs(members) do
		p:SetNW2Bool("ws_ingame", true)
		pending[p] = nil
		leaveMenuState(p)
		p:Spawn()
	end
	net.Start("ws.lobby.started")
	net.Send(members)
	hook.Run("WSSquadDeployed", members)
end)

concommand.Add("ws_lobby_reset", function(ply)
	-- вернуть себя (или всех, с консоли сервера) в меню
	local list = IsValid(ply) and { ply } or player.GetAll()
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	for _, p in ipairs(list) do
		p:SetNW2Bool("ws_ingame", false)
		p:Spawn()
	end
end)
