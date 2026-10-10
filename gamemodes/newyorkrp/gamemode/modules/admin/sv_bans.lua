--[[
	Баны и предупреждения.
	Баны: data/nyrp/bans.json — { [SteamID] = { steamid, name, reason, by, bySteam, time, expires (0 — навсегда) } }.
	  Проверка при подключении (CheckPassword): отказ с причиной и оставшимся временем; истёкшие снимаются сами.
	Предупреждения: data/nyrp/warns.json — { [SteamID] = { { id, reason, by, time, name }, ... } }.
	  3 активных (за 7 дней) → автоматический бан на сутки.
]]

NYRP.Admin = NYRP.Admin or {}
local A = NYRP.Admin

local BANS = "nyrp/bans.json"
local WARNS = "nyrp/warns.json"

local function readJSON(path)
	local s = file.Read(path, "DATA")
	if not s or s == "" then return {} end
	local ok, t = pcall(util.JSONToTable, s)
	return (ok and type(t) == "table") and t or {}
end

local function writeJSON(path, t)
	file.CreateDir("nyrp")
	local ok, s = pcall(util.TableToJSON, t, true)
	if ok and s then file.Write(path, s) end
end

A.Bans = A.Bans or readJSON(BANS)
A.Warns = A.Warns or readJSON(WARNS)

function A.SaveBans() writeJSON(BANS, A.Bans) end
function A.SaveWarns() writeJSON(WARNS, A.Warns) end

-- ------------------------------------------------------------------ баны --
-- Снять истёкшие; true — что-то снято.
function A.PruneBans()
	local now, changed = os.time(), false
	for sid, b in pairs(A.Bans) do
		if (tonumber(b.expires) or 0) > 0 and b.expires <= now then
			A.Bans[sid] = nil
			changed = true
			if NYRP.Log and NYRP.Log.Add then NYRP.Log.Add("admin", "бан истёк: " .. (b.name or "?") .. " (" .. sid .. ")") end
		end
	end
	if changed then A.SaveBans() end
	return changed
end

function A.GetBan(sid)
	A.PruneBans()
	return A.Bans[sid]
end

function A.BanMessage(b)
	local left = (tonumber(b.expires) or 0) > 0 and A.FormatDuration(b.expires - os.time()) or "навсегда"
	return "Вы заблокированы на сервере New-York Roleplay\n\nПричина: " .. (b.reason or "не указана")
		.. "\nОсталось: " .. left
		.. "\nАдминистратор: " .. (b.by or "?")
		.. "\nДата: " .. os.date("%d.%m.%Y %H:%M", b.time or os.time())
end

-- Забанить SteamID (игрок может быть офлайн). minutes = 0 — навсегда.
function A.Ban(sid, name, minutes, reason, admin)
	sid = A.NormalizeSteamID(sid)
	if not sid then return false, "Неверный SteamID" end
	minutes = math.max(0, math.floor(tonumber(minutes) or 0))
	reason = NYRP.CleanText(reason ~= "" and reason or "Не указана", 200)
	local b = {
		steamid = sid, name = name or sid, reason = reason,
		by = IsValid(admin) and NYRP.CharName(admin) .. " (" .. admin:Nick() .. ")" or "Консоль",
		bySteam = IsValid(admin) and admin:SteamID() or "",
		time = os.time(), expires = minutes > 0 and os.time() + minutes * 60 or 0,
	}
	A.Bans[sid] = b
	A.SaveBans()
	for _, p in ipairs(player.GetAll()) do
		if p:SteamID() == sid then
			b.name = p:Nick()
			A.SaveBans()
			p:Kick(A.BanMessage(b))
		end
	end
	return true, b
end

function A.Unban(sid)
	sid = A.NormalizeSteamID(sid)
	if not sid or not A.Bans[sid] then return false end
	A.Bans[sid] = nil
	A.SaveBans()
	return true
end

hook.Add("CheckPassword", "nyrp.admin.bans", function(sid64, ip, svPass, clPass, name)
	local sid = util.SteamIDFrom64(sid64)
	local b = sid and A.GetBan(sid)
	if b then
		if NYRP.Log and NYRP.Log.Add then NYRP.Log.Add("connect", string.format("%s (%s) — вход отклонён: бан (%s)", name or "?", sid, b.reason or "")) end
		return false, A.BanMessage(b)
	end
end)

timer.Create("nyrp.admin.bans.prune", 60, 0, A.PruneBans)

-- ------------------------------------------------------- предупреждения --
local function activeWarns(sid)
	local list = A.Warns[sid] or {}
	local since, n = os.time() - A.WarnDays * 86400, 0
	for _, w in ipairs(list) do
		if (w.time or 0) >= since and not w.removed then n = n + 1 end
	end
	return n
end
A.ActiveWarns = activeWarns

-- Выдать предупреждение онлайн-игроку. Возвращает число активных.
function A.Warn(target, reason, admin)
	local sid = target:SteamID()
	A.Warns[sid] = A.Warns[sid] or {}
	local list = A.Warns[sid]
	local id = 1
	for _, w in ipairs(list) do id = math.max(id, (w.id or 0) + 1) end
	list[#list + 1] = {
		id = id, reason = NYRP.CleanText(reason ~= "" and reason or "Не указана", 200), time = os.time(),
		by = IsValid(admin) and NYRP.CharName(admin) .. " (" .. admin:Nick() .. ")" or "Консоль",
		name = target:Nick(), char = NYRP.CharName(target),
	}
	-- храним не больше 50 записей на игрока
	while #list > 50 do table.remove(list, 1) end
	A.SaveWarns()
	local n = activeWarns(sid)
	NYRP.Notify(target, "Вам выдано предупреждение (" .. n .. "/" .. A.WarnLimit .. "): " .. list[#list].reason, "error", 12)
	if NYRP.Chat and NYRP.Chat.System then
		NYRP.Chat.System(target, "Предупреждение от администрации: " .. list[#list].reason .. ". Активных: " .. n .. " из " .. A.WarnLimit .. ".")
	end
	if n >= A.WarnLimit then
		local name = target:Nick()
		timer.Simple(1, function()
			A.Ban(sid, name, A.WarnBanMinutes, "Автобан: " .. A.WarnLimit .. " предупреждения за " .. A.WarnDays .. " дней", nil)
		end)
		if NYRP.Log and NYRP.Log.Add then NYRP.Log.Add("admin", "автобан на " .. A.FormatDuration(A.WarnBanMinutes * 60) .. " за " .. n .. " предупреждения", target) end
		for _, p in ipairs(player.GetAll()) do
			if p:IsAdmin() then NYRP.Notify(p, name .. " автоматически забанен на сутки (" .. n .. " предупреждения)", "warning", 8) end
		end
	end
	return n
end

-- Снять предупреждение (помечается снятым, остаётся в истории).
function A.Unwarn(sid, id)
	local list = A.Warns[sid]
	if not list then return false end
	for _, w in ipairs(list) do
		if w.id == id and not w.removed then
			w.removed = true
			A.SaveWarns()
			return true, w
		end
	end
	return false
end

-- Данные для вкладок
function A.SendBans(ply)
	A.PruneBans()
	local rows = {}
	for sid, b in pairs(A.Bans) do
		rows[#rows + 1] = { steamid = sid, name = b.name, reason = b.reason, by = b.by, time = b.time, expires = b.expires or 0 }
	end
	table.sort(rows, function(a, b) return (a.time or 0) > (b.time or 0) end)
	A.SendData(ply, "bans", { rows = rows, now = os.time() })
end

function A.SendWarns(ply)
	local rows = {}
	local since = os.time() - A.WarnDays * 86400
	for sid, list in pairs(A.Warns) do
		for _, w in ipairs(list) do
			rows[#rows + 1] = { steamid = sid, id = w.id, name = w.name, char = w.char, reason = w.reason, by = w.by, time = w.time,
				active = (w.time or 0) >= since and not w.removed, removed = w.removed or false, count = activeWarns(sid) }
		end
	end
	table.sort(rows, function(a, b) return (a.time or 0) > (b.time or 0) end)
	while #rows > 300 do table.remove(rows) end
	A.SendData(ply, "warns", { rows = rows, now = os.time(), limit = A.WarnLimit, days = A.WarnDays })
end

-- Консоль сервера (RCON): nyrp_unban <SteamID>, nyrp_banid <SteamID> <минуты> <причина>
concommand.Add("nyrp_unban", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local ok = A.Unban(args[1])
	print(ok and ("[NYRP] Разбанен " .. tostring(args[1])) or "[NYRP] Бан не найден")
	if ok and NYRP.Log then NYRP.Log.Add("admin", "консоль разбанила " .. tostring(args[1])) end
end)

concommand.Add("nyrp_banid", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local reason = table.concat(args, " ", 3)
	local ok, b = A.Ban(args[1], nil, tonumber(args[2]) or 0, reason, IsValid(ply) and ply or nil)
	print(ok and ("[NYRP] Забанен " .. tostring(args[1])) or ("[NYRP] " .. tostring(b)))
	if ok and NYRP.Log then NYRP.Log.Add("admin", "бан " .. tostring(args[1]) .. " (" .. reason .. ")", IsValid(ply) and ply or nil) end
end)
