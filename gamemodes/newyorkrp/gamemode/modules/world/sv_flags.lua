--[[
	Флаги персонажа (как в Helix). Хранятся в c.flags.cflags — строка букв (см. W.Flags в sh_world.lua).
	  p — physgun, t — toolgun (выдаются при спавне персонажа), e — пропы, n — энтити, v — транспорт.
	Админам всё доступно и без флагов.

	Команды (админ):
	  /flaggive <имя> <буквы>  — выдать флаги персонажу (имя персонажа или ник Steam, можно часть)
	  /flagtake <имя> <буквы>  — забрать флаги
	  /flags [имя]             — показать флаги (без имени — свои)
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

-- Нижний регистр с кириллицей (string.lower её не трогает).
function W.Lower(s)
	s = string.lower(tostring(s or ""))
	return (string.gsub(s, utf8.charpattern, function(ch)
		local cp = utf8.codepoint(ch)
		if cp >= 0x410 and cp <= 0x42F then return utf8.char(cp + 0x20) end
		if cp == 0x401 then return utf8.char(0x451) end
	end))
end

-- Поиск игрока по имени персонажа / нику Steam / SteamID (точное совпадение важнее частичного).
function W.FindPlayer(query)
	query = string.Trim(tostring(query or ""))
	if query == "" then return nil, "Укажите имя" end
	local q = W.Lower(query)
	for _, p in ipairs(player.GetAll()) do
		if p:SteamID() == query or p:SteamID64() == query then return p end
	end
	local exact, partial = {}, {}
	for _, p in ipairs(player.GetAll()) do
		local names = { NYRP.CharName(p), p:Nick() }
		for _, n in ipairs(names) do
			local ln = W.Lower(n)
			if ln == q then exact[p] = true
			elseif string.find(ln, q, 1, true) then partial[p] = true end
		end
	end
	local function only(set)
		local found, cnt = nil, 0
		for p in pairs(set) do found, cnt = p, cnt + 1 end
		return found, cnt
	end
	local p, n = only(exact)
	if n == 1 then return p end
	if n > 1 then return nil, "Под «" .. query .. "» подходит несколько игроков — уточните" end
	p, n = only(partial)
	if n == 1 then return p end
	if n > 1 then return nil, "Под «" .. query .. "» подходит несколько игроков — уточните" end
	return nil, "Игрок «" .. query .. "» не найден"
end

-- Оставить только известные буквы без повторов.
local function cleanLetters(s)
	local out, seen = {}, {}
	for ch in string.gmatch(string.lower(tostring(s or "")), "%a") do
		if W.Flags[ch] and not seen[ch] then seen[ch] = true out[#out + 1] = ch end
	end
	return table.concat(out)
end

local function describe(letters)
	if letters == "" then return "нет" end
	local parts = {}
	for ch in string.gmatch(letters, ".") do
		local f = W.Flags[ch]
		parts[#parts + 1] = ch .. " (" .. (f and f.desc or "?") .. ")"
	end
	return table.concat(parts, ", ")
end

-- Оружие строителя по флагам: выдать / забрать.
function W.ApplyTools(ply)
	if not IsValid(ply) or not ply:Alive() or not NYRP.HasCharacter(ply) then return end
	local tools = { p = "weapon_physgun", t = "gmod_tool" }
	for f, class in pairs(tools) do
		local has = W.HasFlag(ply, f)
		if has and not ply:HasWeapon(class) then ply:Give(class)
		elseif not has and ply:HasWeapon(class) then ply:StripWeapon(class) end
	end
end

local function sync(ply)
	ply:SetNW2String("nyrp.cflags", W.GetFlags(ply))
end

function W.SetFlags(ply, letters)
	local c = ply.nyrpChar
	if not c then return false end
	c.flags = c.flags or {}
	letters = cleanLetters(letters)
	c.flags.cflags = letters ~= "" and letters or nil
	sync(ply)
	W.ApplyTools(ply)
	if NYRP.Chars and NYRP.Chars.Save then NYRP.Chars.Save(ply) end
	return true
end

function W.GiveFlags(ply, letters)
	return W.SetFlags(ply, W.GetFlags(ply) .. cleanLetters(letters))
end

function W.TakeFlags(ply, letters)
	local take = cleanLetters(letters)
	local rest = W.GetFlags(ply)
	if take ~= "" then rest = string.gsub(rest, "[" .. take .. "]", "") end
	return W.SetFlags(ply, rest)
end

-- Выдача при спавне: PlayerLoadout вызывает NYRP.Loadout (здесь персонаж уже загружен).
hook.Add("NYRP.Loadout", "nyrp.flags", function(ply)
	sync(ply)
	if ply:IsAdmin() then return end
	if W.HasFlag(ply, "p") then ply:Give("weapon_physgun") end
	if W.HasFlag(ply, "t") then ply:Give("gmod_tool") end
end)
hook.Add("NYRP.CharacterLoaded", "nyrp.flags", function(ply) sync(ply) end)

-- ------------------------------------------------------------- команды --
local function parse(raw)
	local rest = string.match(raw, "^%S+%s+(.+)$") or ""
	local name, letters = string.match(rest, "^(.-)%s+(%S+)$")
	return string.Trim(name or ""), letters or ""
end

local function flagCommand(give)
	return function(ply, raw)
		if not ply:IsAdmin() then NYRP.Notify(ply, "Команда только для администрации", "error") return end
		local name, letters = parse(raw)
		local clean = cleanLetters(letters)
		if name == "" or clean == "" then
			NYRP.Notify(ply, (give and "/flaggive" or "/flagtake") .. " <имя> <буквы>. Флаги: p — физган, t — тулган, e — пропы, n — энтити, v — транспорт", "warning", 8)
			return
		end
		local target, err = W.FindPlayer(name)
		if not target then NYRP.Notify(ply, err, "error") return end
		if not NYRP.HasCharacter(target) then NYRP.Notify(ply, "У игрока не выбран персонаж", "error") return end
		if give then W.GiveFlags(target, clean) else W.TakeFlags(target, clean) end
		local now = W.GetFlags(target)
		NYRP.Notify(ply, NYRP.CharName(target) .. ": флаги " .. (give and "выданы" or "забраны") .. " (" .. clean .. "). Сейчас: " .. (now ~= "" and now or "нет"), "success", 6)
		if target ~= ply then
			NYRP.Notify(target, (give and "Вам выданы права: " or "У вас забраны права: ") .. describe(clean), give and "success" or "warning", 8)
		end
		NYRP.Print(string.format("[флаги] %s %s %s (%s): %s", ply:Nick(), give and "выдал" or "забрал", NYRP.CharName(target), target:Nick(), clean))
	end
end

local function register()
	if not (NYRP.Chat and NYRP.Chat.AddCommand) then return false end
	NYRP.Chat.AddCommand("/flaggive", flagCommand(true))
	NYRP.Chat.AddCommand("/flagtake", flagCommand(false))
	NYRP.Chat.AddCommand("/flags", function(ply, raw)
		local name = string.Trim(string.match(raw, "^%S+%s+(.+)$") or "")
		local target = ply
		if name ~= "" then
			if not ply:IsAdmin() then NYRP.Notify(ply, "Чужие флаги смотрит только администрация", "error") return end
			local err
			target, err = W.FindPlayer(name)
			if not target then NYRP.Notify(ply, err, "error") return end
		end
		local letters = W.GetFlags(target)
		local text = NYRP.CharName(target) .. " — флаги: " .. describe(letters)
		if target:IsAdmin() then text = text .. " (администратор: доступно всё)" end
		NYRP.Chat.System(ply, text)
	end)
	return true
end
if not register() then hook.Add("Initialize", "nyrp.flags.cmd", function(...) register(...) end) end
