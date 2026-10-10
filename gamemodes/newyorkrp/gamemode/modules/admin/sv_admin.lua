--[[
	Администрирование (сервер): действия над игроками, чат-команды, сеть меню, пермакилл.
	Всё — только для ply:IsAdmin(), проверка в каждой команде и каждом net.Receive.

	Чат-команды (<имя> — часть имени персонажа/ника, SteamID или "имя в кавычках"; ^ — вы сами):
	  /admin                                — админ-меню (также F7 и консоль nyrp_admin)
	  /goto <имя>   /bring <имя>   /return [имя]
	  /freeze <имя> (повторно — разморозить)   /unfreeze <имя>
	  /slay <имя>   /hp <имя> [здоровье]   /addmoney <имя> <сумма>
	  /kick <имя> [причина]
	  /ban <имя|SteamID> <минуты|0=навсегда> [причина]   /unban <SteamID>
	  /warn <имя> <причина>   /warns [имя]
	  /observer   /spectate [имя]   /charkill <имя> (подтверждение в окне)
]]

NYRP.Admin = NYRP.Admin or {}
local A = NYRP.Admin

local function log(text, ply)
	if NYRP.Log and NYRP.Log.Add then NYRP.Log.Add("admin", text, ply) end
end
local function who(p) return NYRP.Log and NYRP.Log.Who and NYRP.Log.Who(p) or (IsValid(p) and p:Nick() or "?") end

-- Сжатый JSON клиенту: kind + данные
function A.SendData(ply, kind, data)
	local ok, json = pcall(util.TableToJSON, data or {})
	if not ok or not json then return end
	local comp = util.Compress(json) or ""
	if #comp > 60000 then return end
	net.Start("nyrp.admin.data")
	net.WriteString(kind)
	net.WriteUInt(#comp, 32)
	net.WriteData(comp, #comp)
	net.Send(ply)
end

-- Свободное место рядом с игроком (для goto/bring).
local function freeSpot(target, ent)
	local base = target:GetPos()
	local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
	local yaw = target:EyeAngles().y
	for _, off in ipairs({ 180, 135, 225, 90, 270, 45, 315, 0 }) do
		local dir = Angle(0, yaw + off, 0):Forward()
		local pos = base + dir * 52 + Vector(0, 0, 4)
		local tr = util.TraceHull({ start = base + Vector(0, 0, 4), endpos = pos, mins = mins, maxs = maxs, filter = { target, ent }, mask = MASK_PLAYERSOLID })
		if not tr.Hit and not tr.StartSolid then return pos end
	end
	return base + Vector(0, 0, 80)
end

local function moveTo(ply, pos, faceTo)
	if ply:InVehicle() then ply:ExitVehicle() end
	if NYRP.Cond and NYRP.Cond.KO and NYRP.Cond.KO(ply) and NYRP.Cond.WakeUp then NYRP.Cond.WakeUp(ply) end
	ply.nyrpReturnPos = ply:GetPos()
	ply:SetPos(pos)
	ply:SetLocalVelocity(vector_origin)
	if faceTo then ply:SetEyeAngles((faceTo - ply:EyePos()):Angle()) end
end

-- Полное лечение: здоровье, ранения, кровотечение, нокаут, голод/жажда, выносливость.
local function heal(target, hp)
	if not target:Alive() then
		local pos = target:GetPos()
		target:Spawn()
		target:SetPos(pos)
	end
	if NYRP.Cond and NYRP.Cond.KO and NYRP.Cond.KO(target) and NYRP.Cond.WakeUp then NYRP.Cond.WakeUp(target) end
	target:SetHealth(hp or target:GetMaxHealth())
	target:SetNW2Bool("nyrp.bleeding", false)
	for _, k in ipairs({ "wound_head", "wound_body", "wound_arm", "wound_leg", "concussion", "bruise" }) do
		target:SetNW2Float("nyrp." .. k .. "Until", 0)
	end
	if not hp then
		target:SetNW2Float("nyrp.hunger", 100)
		target:SetNW2Float("nyrp.thirst", 100)
		target:SetNW2Float("nyrp.stamina", 100)
		target:Extinguish()
	end
end

-- Пермакилл: персонаж удаляется из базы навсегда, игрок уходит в меню персонажей.
function A.CharKill(admin, target)
	local c = target.nyrpChar
	if not c or not c.id then return false, "У игрока нет персонажа" end
	local id, name = c.id, c.name
	if NYRP.Inv and NYRP.Inv.Clear then pcall(NYRP.Inv.Clear, target) end
	target.nyrpChar = nil
	target.nyrpInvChar = nil
	target.nyrpLastChar = 0
	NYRP.DB.Query("DELETE FROM nyrp_characters WHERE id = " .. tonumber(id))
	file.Delete("nyrp/chars/" .. id .. ".json")
	if target:Alive() then target:KillSilent() end
	local Chars = NYRP.Chars
	if Chars.ToMenu then Chars.ToMenu(target) end
	if NYRP.Points and NYRP.Points.Configured and not NYRP.Points.Configured() and Chars.AutoLoad then
		timer.Simple(0.5, function() if IsValid(target) then Chars.AutoLoad(target) end end)
	end
	NYRP.Notify(target, "Ваш персонаж «" .. name .. "» погиб окончательно (решение администрации)", "error", 15)
	return true, name, id
end

-- ------------------------------------------------------------ действия --
-- A.Actions[id] = { target = нужна ли цель, fn = function(admin, target, a1, a2) -> текст для лога | nil, ошибка }
A.Actions = {
	["goto"] = { target = true, fn = function(admin, t)
		if A.IsObserver(admin) then admin.nyrpReturnPos = admin:GetPos() admin:SetPos(t:GetPos() + Vector(0, 0, 16))
		else moveTo(admin, freeSpot(t, admin), t:EyePos()) end
		return "телепортировался к " .. who(t)
	end },
	bring = { target = true, fn = function(admin, t)
		if t == admin then return nil, "Нельзя привести себя" end
		if not t:Alive() then return nil, "Игрок мёртв" end
		local ent = admin
		local pos = A.IsObserver(admin) and (admin:GetPos() + admin:GetAimVector() * 60) or freeSpot(admin, t)
		moveTo(t, pos, ent:EyePos())
		NYRP.Notify(t, "Администратор переместил вас", "info", 4)
		return "привёл " .. who(t)
	end },
	["return"] = { target = true, fn = function(admin, t)
		if not t.nyrpReturnPos then return nil, "Некуда возвращать: " .. NYRP.CharName(t) .. " не перемещали" end
		local pos = t.nyrpReturnPos
		if t:InVehicle() then t:ExitVehicle() end
		t:SetPos(pos)
		t:SetLocalVelocity(vector_origin)
		t.nyrpReturnPos = nil
		return "вернул на место " .. who(t)
	end },
	freeze = { target = true, fn = function(admin, t, a1)
		local on
		if a1 == "1" then on = true elseif a1 == "0" then on = false else on = not t:GetNW2Bool("nyrp.frozen", false) end
		t:Freeze(on)
		t:SetNW2Bool("nyrp.frozen", on)
		NYRP.Notify(t, on and "Вас заморозил администратор" or "Вы разморожены", on and "warning" or "info", 4)
		return (on and "заморозил " or "разморозил ") .. who(t)
	end },
	slay = { target = true, fn = function(admin, t)
		if not t:Alive() then return nil, "Игрок уже мёртв" end
		t.nyrpDeathCause = "Решение администрации"
		t:Kill()
		return "убил (slay) " .. who(t)
	end },
	heal = { target = true, fn = function(admin, t, a1)
		local hp = tonumber(a1)
		if hp then hp = math.Clamp(math.floor(hp), 1, 1000) end
		heal(t, hp)
		NYRP.Notify(t, "Администратор вылечил вас", "success", 4)
		return hp and ("установил " .. hp .. " HP " .. who(t)) or ("вылечил " .. who(t))
	end },
	money = { target = true, fn = function(admin, t, a1)
		local n = math.floor(tonumber(a1) or 0)
		if n == 0 or math.abs(n) > 10000000 then return nil, "Неверная сумма" end
		if not NYRP.HasCharacter(t) then return nil, "У игрока нет персонажа" end
		NYRP.Money.Add(t, n)
		NYRP.Notify(t, (n > 0 and "Администратор выдал вам " or "Администратор забрал ") .. NYRP.Money.Format(math.abs(n)), "info", 5)
		return (n > 0 and "выдал " or "забрал ") .. NYRP.Money.Format(math.abs(n)) .. " — " .. who(t)
	end },
	role = { target = true, fn = function(admin, t, a1)
		local R = NYRP.Roles
		if not R or not R.List or not R.List[a1 or ""] then return nil, "Нет такой роли" end
		if not NYRP.HasCharacter(t) then return nil, "У игрока нет персонажа" end
		if not R.Set(t, a1) then return nil, "Не удалось сменить роль" end
		return "сменил роль " .. who(t) .. " → " .. R.List[a1].Name
	end },
	kick = { target = true, fn = function(admin, t, a1)
		if t ~= admin and t:IsSuperAdmin() and not admin:IsSuperAdmin() then return nil, "Нельзя кикнуть суперадмина" end
		local reason = NYRP.CleanText(a1 ~= "" and a1 or "Не указана", 200)
		local text = who(t)
		t:Kick("Вас выгнали с сервера.\nПричина: " .. reason .. "\nАдминистратор: " .. admin:Nick())
		return "кикнул " .. text .. " (" .. reason .. ")"
	end },
	ban = { target = true, fn = function(admin, t, a1, a2)
		if t == admin then return nil, "Нельзя забанить себя" end
		if t ~= admin and t:IsSuperAdmin() and not admin:IsSuperAdmin() then return nil, "Нельзя забанить суперадмина" end
		local minutes = tonumber(a1)
		if not minutes or minutes < 0 then return nil, "Неверный срок" end
		local text = who(t)
		local ok, b = A.Ban(t:SteamID(), t:Nick(), minutes, a2 or "", admin)
		if not ok then return nil, b end
		return "забанил " .. text .. " на " .. A.FormatDuration(minutes * 60) .. " (" .. b.reason .. ")"
	end },
	warn = { target = true, fn = function(admin, t, a1)
		local reason = NYRP.CleanText(a1 or "", 200)
		if reason == "" then return nil, "Укажите причину предупреждения" end
		local n = A.Warn(t, reason, admin)
		return "выдал предупреждение " .. who(t) .. " (" .. reason .. "), активных: " .. n
	end },
	spectate = { target = true, fn = function(admin, t)
		if t == admin then return nil, "Нельзя наблюдать за собой" end
		A.Spectate(admin, t)
		return nil
	end },
	charkill = { target = true, fn = function(admin, t)
		local ok, name, id = A.CharKill(admin, t)
		if not ok then return nil, name end
		return "ПЕРМАКИЛЛ: удалил персонажа «" .. name .. "» (#" .. id .. ") игрока " .. t:Nick() .. " (" .. t:SteamID() .. ")"
	end },
	-- без цели
	observer = { fn = function(admin) A.ToggleObserver(admin) return nil end },
	banid = { fn = function(admin, _, a1, a2, a3)
		local sid = A.NormalizeSteamID(a1)
		if not sid then return nil, "Неверный SteamID" end
		local minutes = tonumber(a2)
		if not minutes or minutes < 0 then return nil, "Неверный срок" end
		local ok, b = A.Ban(sid, nil, minutes, a3 or "", admin)
		if not ok then return nil, b end
		return "забанил " .. sid .. " на " .. A.FormatDuration(minutes * 60) .. " (" .. b.reason .. ")"
	end },
	unban = { fn = function(admin, _, a1)
		local sid = A.NormalizeSteamID(a1)
		local b = sid and A.Bans[sid]
		if not b or not A.Unban(sid) then return nil, "Бан не найден" end
		return "разбанил " .. (b.name or sid) .. " (" .. sid .. ")"
	end },
	unwarn = { fn = function(admin, _, a1, a2)
		local sid = A.NormalizeSteamID(a1)
		local ok, w = A.Unwarn(sid or "", tonumber(a2) or -1)
		if not ok then return nil, "Предупреждение не найдено" end
		return "снял предупреждение с " .. (w.name or sid) .. " (" .. tostring(w.reason) .. ")"
	end },
}

local SUCCESS = {
	["goto"] = "Вы на месте", bring = "Игрок перемещён", ["return"] = "Игрок возвращён", slay = "Готово", heal = "Игрок вылечен",
	money = "Готово", role = "Роль изменена", kick = "Игрок выгнан", ban = "Игрок забанен", warn = "Предупреждение выдано",
	charkill = "Персонаж удалён навсегда", banid = "SteamID забанен", unban = "Бан снят", unwarn = "Предупреждение снято",
}

-- Выполнить действие (общая точка для меню и чат-команд).
function A.Do(admin, act, target, a1, a2, a3)
	if not IsValid(admin) or not admin:IsAdmin() then return false end
	local def = A.Actions[act]
	if not def then return false end
	if def.target and (not IsValid(target) or not target:IsPlayer()) then
		NYRP.Notify(admin, "Игрок не найден", "error")
		return false
	end
	local ok, res, err = pcall(def.fn, admin, target, a1 or "", a2 or "", a3 or "")
	if not ok then
		NYRP.Print("Админ-действие " .. act .. ": ошибка " .. tostring(res))
		NYRP.Notify(admin, "Ошибка выполнения (подробности в консоли сервера)", "error")
		return false
	end
	if err then NYRP.Notify(admin, err, "error", 6) return false end
	if res then
		log(res, admin)
		if SUCCESS[act] then NYRP.Notify(admin, SUCCESS[act], "success", 3) end
		-- остальных админов держим в курсе серьёзных действий
		if act == "kick" or act == "ban" or act == "banid" or act == "charkill" or act == "warn" then
			for _, p in ipairs(player.GetAll()) do
				if p ~= admin and p:IsAdmin() then NYRP.Notify(p, admin:Nick() .. " " .. res, "info", 6) end
			end
		end
	end
	return true
end

-- -------------------------------------------------------------------- сеть --
net.Receive("nyrp.admin.act", function(_, ply)
	if not IsValid(ply) or not ply:IsAdmin() then return end
	if (ply.nyrpAdmNext or 0) > CurTime() then return end
	ply.nyrpAdmNext = CurTime() + 0.3
	local act = net.ReadString()
	local target = net.ReadEntity()
	local a1, a2, a3 = net.ReadString(), net.ReadString(), net.ReadString()
	A.Do(ply, string.sub(act, 1, 24), target, string.sub(a1, 1, 220), string.sub(a2, 1, 220), string.sub(a3, 1, 220))
end)

net.Receive("nyrp.admin.req", function(_, ply)
	if not IsValid(ply) then return end
	local kind = net.ReadString()
	-- настройки нужны всем клиентам (дистанции чата и т.п.)
	if kind == "cfg" then
		if (ply.nyrpCfgReq or 0) > CurTime() then return end
		ply.nyrpCfgReq = CurTime() + 5
		A.SendConfig(ply)
		return
	end
	if not ply:IsAdmin() then return end
	if (ply.nyrpAdmReq or 0) > CurTime() then NYRP.Notify(ply, "Не так быстро", "warning", 2) return end
	ply.nyrpAdmReq = CurTime() + 1
	local p1, p2 = net.ReadString(), net.ReadString()
	if kind == "logs" then A.SendLogs(ply, p1, p2)
	elseif kind == "bans" then A.SendBans(ply)
	elseif kind == "warns" then A.SendWarns(ply)
	elseif kind == "cfgreset" then A.ResetSetting(ply, p1)
	end
end)

local function openMenu(ply, mode, ent)
	net.Start("nyrp.admin.open")
	net.WriteString(mode or "menu")
	net.WriteEntity(ent or NULL)
	net.Send(ply)
end
A.OpenMenu = openMenu

-- ----------------------------------------------------------- чат-команды --
local function cmd(names, fn)
	for _, n in ipairs(names) do
		NYRP.Chat.AddCommand(n, function(ply, raw)
			if not ply:IsAdmin() then NYRP.Notify(ply, "Только для администрации", "error") return end
			if NYRP.Log and NYRP.Log.Add then NYRP.Log.Add("command", raw, ply) end
			fn(ply, string.Trim(string.match(raw, "^%S+%s*(.*)$") or ""))
		end)
	end
end

-- команда «/x <цель> [аргументы]»
local function targetCmd(names, act, usage, parse)
	cmd(names, function(ply, args)
		if args == "" then NYRP.Notify(ply, "Использование: " .. usage, "info", 6) return end
		local t, rest, err = A.SplitTarget(args, ply)
		if not t then NYRP.Notify(ply, err or "Игрок не найден", "error", 6) return end
		if parse then
			local a1, a2, perr = parse(rest, t)
			if perr then NYRP.Notify(ply, perr .. ". " .. usage, "error", 6) return end
			A.Do(ply, act, t, a1, a2)
		else
			A.Do(ply, act, t, rest)
		end
	end)
end

cmd({ "/admin", "/админ" }, function(ply) openMenu(ply, "menu") end)
targetCmd({ "/goto", "/тп" }, "goto", "/goto <имя>")
targetCmd({ "/bring" }, "bring", "/bring <имя>")
cmd({ "/return" }, function(ply, args)
	local t = ply
	if args ~= "" then
		local err
		t, err = A.Find(args, ply)
		if not t then NYRP.Notify(ply, err, "error") return end
	end
	A.Do(ply, "return", t)
end)
targetCmd({ "/freeze" }, "freeze", "/freeze <имя>", function() return "" end)
targetCmd({ "/unfreeze" }, "freeze", "/unfreeze <имя>", function() return "0" end)
targetCmd({ "/slay" }, "slay", "/slay <имя>")
targetCmd({ "/hp", "/heal" }, "heal", "/hp <имя> [здоровье]", function(rest)
	if rest == "" then return "" end
	local n = tonumber(rest)
	if not n or n < 1 then return nil, nil, "Неверное значение здоровья" end
	return tostring(math.floor(n))
end)
targetCmd({ "/addmoney" }, "money", "/addmoney <имя> <сумма> (минус — забрать)", function(rest)
	local n = tonumber(string.match(rest, "^(%-?%d+)"))
	if not n or n == 0 then return nil, nil, "Укажите сумму" end
	return tostring(n)
end)
targetCmd({ "/kick" }, "kick", "/kick <имя> [причина]")
targetCmd({ "/warn" }, "warn", "/warn <имя> <причина>", function(rest)
	if rest == "" then return nil, nil, "Укажите причину" end
	return rest
end)

-- /ban <имя|SteamID> <минуты> [причина] — SteamID можно и офлайн
cmd({ "/ban" }, function(ply, args)
	local usage = "/ban <имя|SteamID> <минуты|0=навсегда> [причина]"
	local first, mins, reason = string.match(args, "^(%S+)%s+(%d+)%s*(.*)$")
	local sid = first and A.NormalizeSteamID(first)
	if sid then
		local online
		for _, p in ipairs(player.GetAll()) do if p:SteamID() == sid then online = p end end
		if online then A.Do(ply, "ban", online, mins, reason) else A.Do(ply, "banid", nil, sid, mins, reason) end
		return
	end
	local t, rest, err = A.SplitTarget(args, ply)
	if not t then NYRP.Notify(ply, (err or "Игрок не найден") .. ". " .. usage, "error", 8) return end
	local m, r = string.match(rest, "^(%d+)%s*(.*)$")
	if not m then NYRP.Notify(ply, "Укажите срок в минутах. " .. usage, "error", 8) return end
	A.Do(ply, "ban", t, m, r)
end)

cmd({ "/unban" }, function(ply, args)
	if args == "" then NYRP.Notify(ply, "Использование: /unban <SteamID>", "info", 6) return end
	A.Do(ply, "unban", nil, args)
end)

cmd({ "/warns" }, function(ply, args)
	if args == "" then openMenu(ply, "warns") return end
	local t, err = A.Find(args, ply)
	if not t then NYRP.Notify(ply, err, "error") return end
	local list = A.Warns[t:SteamID()] or {}
	local lines = {}
	for i = #list, math.max(1, #list - 4), -1 do
		local w = list[i]
		lines[#lines + 1] = os.date("%d.%m", w.time) .. " — " .. w.reason .. (w.removed and " (снято)" or "")
	end
	NYRP.Notify(ply, NYRP.CharName(t) .. ": активных " .. A.ActiveWarns(t:SteamID()) .. "/" .. A.WarnLimit
		.. (#lines > 0 and ("\n" .. table.concat(lines, "\n")) or ""), "info", 12)
end)

cmd({ "/observer", "/obs", "/наблюдатель" }, function(ply) A.ToggleObserver(ply) end)

-- /spectate без аргументов — выйти из слежки
cmd({ "/spectate", "/spec" }, function(ply, args)
	if args == "" then
		if A.Spectating(ply) then A.StopSpectate(ply) else NYRP.Notify(ply, "Использование: /spectate <имя>", "info") end
		return
	end
	local t, err = A.Find(args, ply)
	if not t then NYRP.Notify(ply, err, "error") return end
	A.Do(ply, "spectate", t)
end)

-- /charkill <имя> — подтверждение в окне у администратора
cmd({ "/charkill", "/pk" }, function(ply, args)
	if args == "" then NYRP.Notify(ply, "Использование: /charkill <имя>", "info") return end
	local t, err = A.Find(args, ply)
	if not t then NYRP.Notify(ply, err, "error") return end
	if not NYRP.HasCharacter(t) then NYRP.Notify(ply, "У игрока нет персонажа", "error") return end
	openMenu(ply, "charkill", t)
end)

-- F7 и консоль nyrp_admin открывают меню на клиенте (cl_admin.lua) — сервер лишь проверяет права в каждом действии.
