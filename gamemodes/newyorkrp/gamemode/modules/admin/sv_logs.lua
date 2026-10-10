--[[
	Логи сервера.
	NYRP.Log.Add(category, text, ply) — запись: в памяти последние 2000 строк + файл data/nyrp/logs/<ГГГГ-ММ-ДД>.txt.
	Категории: chat, command, death, damage, connect, character, spawn, money, admin, other (см. sh_admin.lua).
	Автоматически пишутся: чат, команды, смерти (кто убил), урон игроку от игрока, вход/выход,
	загрузка персонажа, спавн пропов/энтити/NPC/машин/оружия, изменения наличных (обёртка NYRP.Money.Set).
	Вкладка «Логи» в админ-меню запрашивает строки с фильтром (net nyrp.admin.req "logs", только админам).
]]

NYRP.Log = NYRP.Log or {}
NYRP.Admin = NYRP.Admin or {}
local L = NYRP.Log
local A = NYRP.Admin

local MAX = 2000
L.Entries = L.Entries or {}

-- «Имя персонажа (ник, SteamID)»
function L.Who(ply)
	if not IsValid(ply) then return "консоль" end
	if not ply:IsPlayer() then return ply:GetClass() end
	local cn = NYRP.CharName(ply)
	if cn ~= ply:Nick() then
		return string.format("%s (%s, %s)", cn, ply:Nick(), ply:SteamID())
	end
	return string.format("%s (%s)", ply:Nick(), ply:SteamID())
end

function L.Add(cat, text, ply)
	cat = A.LogCatById and A.LogCatById[cat] and cat or "other"
	text = tostring(text or "")
	if IsValid(ply) and ply:IsPlayer() then text = L.Who(ply) .. ": " .. text end
	local e = { t = os.time(), c = cat, x = text, s = IsValid(ply) and ply:IsPlayer() and ply:SteamID() or nil }
	local list = L.Entries
	list[#list + 1] = e
	if #list > MAX then table.remove(list, 1) end
	-- файл за день
	file.CreateDir("nyrp/logs")
	file.Append("nyrp/logs/" .. os.date("%Y-%m-%d", e.t) .. ".txt",
		os.date("[%H:%M:%S]", e.t) .. " [" .. cat .. "] " .. text .. "\n")
	return e
end

-- Выборка для меню: новые сверху, не больше limit строк.
function L.Query(cat, search, limit)
	local out = {}
	local q = search and search ~= "" and A.Lower(search) or nil
	for i = #L.Entries, 1, -1 do
		local e = L.Entries[i]
		if (cat == "" or cat == "all" or e.c == cat) and (not q or string.find(A.Lower(e.x), q, 1, true) or (e.s and string.find(A.Lower(e.s), q, 1, true))) then
			out[#out + 1] = e
			if #out >= limit then break end
		end
	end
	return out
end

-- -------------------------------------------------------------- автолог --
-- Чат: hook.Run("PlayerSay") вызывается нашим чатом для каждого обычного сообщения (флаг nyrpInternalSay).
hook.Add("PlayerSay", "nyrp.log.chat", function(ply, text)
	if not ply.nyrpInternalSay then return end
	L.Add("chat", text, ply)
end)

-- Чат-команды: обёртка NYRP.Chat.AddCommand (команды, зарегистрированные после модуля admin).
do
	local Chat = NYRP.Chat
	if Chat and Chat.AddCommand and not Chat.nyrpLogWrapped then
		Chat.nyrpLogWrapped = true
		local orig = Chat.AddCommand
		Chat.AddCommand = function(name, fn)
			return orig(name, function(ply, raw, ...)
				if IsValid(ply) then L.Add("command", raw, ply) end
				return fn(ply, raw, ...)
			end)
		end
	end
end

hook.Add("PlayerDeath", "nyrp.log.death", function(victim, inflictor, attacker)
	local how = ""
	if IsValid(inflictor) and inflictor ~= attacker then how = " [" .. inflictor:GetClass() .. "]" end
	if IsValid(attacker) and attacker:IsPlayer() then
		local wep = attacker:GetActiveWeapon()
		if how == "" and IsValid(wep) then how = " [" .. wep:GetClass() .. "]" end
		if attacker == victim then
			L.Add("death", "покончил с собой" .. how, victim)
		else
			L.Add("death", L.Who(attacker) .. " убил " .. L.Who(victim) .. how)
		end
	else
		local cause = victim.nyrpLastDmg and victim.nyrpLastDmg.type and ("тип урона " .. victim.nyrpLastDmg.type) or "причина неизвестна"
		L.Add("death", "погиб (" .. (IsValid(attacker) and attacker:GetClass() or "мир") .. how .. ", " .. cause .. ")", victim)
	end
end)

hook.Add("PostEntityTakeDamage", "nyrp.log.damage", function(ent, dmg, took)
	if not took or not IsValid(ent) or not ent:IsPlayer() then return end
	local att = dmg:GetAttacker()
	if not IsValid(att) or not att:IsPlayer() or att == ent then return end
	local wep = att:GetActiveWeapon()
	L.Add("damage", string.format("%s нанёс %d урона %s (осталось %d HP)%s", L.Who(att), math.Round(dmg:GetDamage()), L.Who(ent),
		math.max(ent:Health(), 0), IsValid(wep) and (" [" .. wep:GetClass() .. "]") or ""))
end)

gameevent.Listen("player_connect")
hook.Add("player_connect", "nyrp.log.connect", function(data)
	if data.bot == 1 then return end
	L.Add("connect", string.format("%s (%s) подключается", data.name or "?", data.networkid or "?"))
end)

hook.Add("PlayerInitialSpawn", "nyrp.log.connect", function(ply)
	L.Add("connect", "зашёл на сервер", ply)
end)

hook.Add("PlayerDisconnected", "nyrp.log.connect", function(ply)
	L.Add("connect", "вышел с сервера", ply)
end)

hook.Add("NYRP.CharacterLoaded", "nyrp.log.char", function(ply, c)
	L.Add("character", "загрузил персонажа «" .. tostring(c and c.name) .. "» (#" .. tostring(c and c.id) .. ")", ply)
end)

hook.Add("NYRP.RoleChanged", "nyrp.log.role", function(ply, id)
	local r = NYRP.Roles and NYRP.Roles.List and NYRP.Roles.List[id]
	L.Add("character", "роль: " .. (r and r.Name or tostring(id)), ply)
end)

hook.Add("PlayerSpawnedProp", "nyrp.log.spawn", function(ply, model)
	L.Add("spawn", "заспавнил проп " .. tostring(model), ply)
end)
hook.Add("PlayerSpawnedSENT", "nyrp.log.spawn", function(ply, ent)
	L.Add("spawn", "заспавнил энтити " .. (IsValid(ent) and ent:GetClass() or "?"), ply)
end)
hook.Add("PlayerSpawnedNPC", "nyrp.log.spawn", function(ply, ent)
	L.Add("spawn", "заспавнил NPC " .. (IsValid(ent) and ent:GetClass() or "?"), ply)
end)
hook.Add("PlayerSpawnedVehicle", "nyrp.log.spawn", function(ply, ent)
	L.Add("spawn", "заспавнил транспорт " .. (IsValid(ent) and ent:GetClass() or "?"), ply)
end)
hook.Add("PlayerSpawnedSWEP", "nyrp.log.spawn", function(ply, ent)
	L.Add("spawn", "заспавнил оружие " .. (IsValid(ent) and ent:GetClass() or "?"), ply)
end)
hook.Add("PlayerGiveSWEP", "nyrp.log.spawn", function(ply, class)
	L.Add("spawn", "взял оружие из меню: " .. tostring(class), ply)
end)
hook.Add("PlayerSpawnedRagdoll", "nyrp.log.spawn", function(ply, model)
	L.Add("spawn", "заспавнил рэгдолл " .. tostring(model), ply)
end)

-- Деньги: отдельного хука нет — оборачиваем NYRP.Money.Set (через него идут и Add, и все списания).
-- Модуль money грузится после admin, поэтому обёртка ставится, когда режим загружен.
local function callerSource()
	for lvl = 3, 7 do
		local info = debug.getinfo(lvl, "Sl")
		if not info then return "?" end
		local src = info.short_src or "?"
		if not string.find(src, "money/sv_money", 1, true) and not string.find(src, "admin/sv_logs", 1, true) then
			return (string.match(src, "modules/(.+)$") or string.match(src, "([^/]+/[^/]+)$") or src) .. ":" .. tostring(info.currentline)
		end
	end
	return "?"
end

function L.WrapMoney()
	local M = NYRP.Money
	if not M or not M.Set or M.nyrpLogWrapped then return end
	M.nyrpLogWrapped = true
	local orig = M.Set
	M.Set = function(ply, n, ...)
		local before = IsValid(ply) and M.Get and M.Get(ply) or 0
		local r = orig(ply, n, ...)
		if IsValid(ply) and M.Get then
			local after = M.Get(ply)
			if after ~= before then
				local ok, src = pcall(callerSource)
				L.Add("money", string.format("наличные %s → %s (%s%s) · %s", M.Format(before), M.Format(after),
					after > before and "+" or "−", M.Format(math.abs(after - before)), ok and src or "?"), ply)
			end
		end
		return r
	end
end
hook.Add("Initialize", "nyrp.log.money", L.WrapMoney)
hook.Add("InitPostEntity", "nyrp.log.money", L.WrapMoney)
timer.Simple(0, L.WrapMoney)

-- ------------------------------------------------------------- запрос --
-- req "logs": категория, поиск → до 400 строк
function A.SendLogs(ply, cat, search)
	cat = string.sub(cat or "", 1, 24)
	search = string.sub(search or "", 1, 64)
	local rows = L.Query(cat, search, 400)
	A.SendData(ply, "logs", { rows = rows, total = #L.Entries })
end
