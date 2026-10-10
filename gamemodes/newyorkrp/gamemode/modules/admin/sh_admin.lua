--[[
	Администрирование: общая часть (сервер и клиент).
	- сетевые сообщения модуля;
	- поиск игрока по имени персонажа / нику / SteamID;
	- список настроек сервера, которые можно менять в игре (вкладка «Настройки»);
	- режим наблюдателя: блокировка обычного noclip (V у админа включает наблюдателя), тихие шаги.

	Меню: /admin, консоль nyrp_admin, F4 (только админам).
	Команды: /goto /bring /return /freeze /unfreeze /slay /hp /addmoney /kick /ban /unban /warn /warns
	         /observer /spectate /charkill — подробности в sv_admin.lua.
]]

NYRP.Admin = NYRP.Admin or {}
local A = NYRP.Admin

if SERVER then
	util.AddNetworkString("nyrp.admin.open")    -- сервер → клиент: открыть меню / окно подтверждения
	util.AddNetworkString("nyrp.admin.act")     -- клиент → сервер: действие над игроком
	util.AddNetworkString("nyrp.admin.req")     -- клиент → сервер: запрос данных (баны, логи, предупреждения, настройки)
	util.AddNetworkString("nyrp.admin.data")    -- сервер → клиент: данные (сжатый JSON)
	util.AddNetworkString("nyrp.admin.cfgset")  -- клиент → сервер: изменить настройки
	util.AddNetworkString("nyrp.admin.cfg")     -- сервер → клиенты: текущие значения настроек
end

-- Категории логов: id → { название, цвет }
A.LogCats = {
	{ id = "chat", name = "Чат", col = Color(150, 190, 255) },
	{ id = "command", name = "Команды", col = Color(190, 160, 255) },
	{ id = "death", name = "Смерти", col = Color(214, 70, 64) },
	{ id = "damage", name = "Урон", col = Color(255, 138, 36) },
	{ id = "connect", name = "Входы", col = Color(104, 200, 120) },
	{ id = "character", name = "Персонажи", col = Color(120, 214, 200) },
	{ id = "spawn", name = "Спавн", col = Color(200, 200, 120) },
	{ id = "money", name = "Деньги", col = Color(247, 198, 0) },
	{ id = "admin", name = "Админ", col = Color(255, 90, 140) },
	{ id = "other", name = "Прочее", col = Color(150, 155, 170) },
}
A.LogCatById = {}
for _, c in ipairs(A.LogCats) do A.LogCatById[c.id] = c end

-- Предупреждения: столько активных за WarnDays дней → бан на WarnBanMinutes.
A.WarnLimit = 3
A.WarnDays = 7
A.WarnBanMinutes = 1440

-- ------------------------------------------------------------ настройки --
-- path — путь в NYRP.Config; таблицы (Ranges, Needs, Movement) меняются на месте,
-- потому что модули держат на них локальные ссылки.
A.Settings = {
	{ key = "RespawnTime", path = { "RespawnTime" }, name = "Время возрождения", desc = "Секунд после смерти до автоматического возрождения", type = "number", min = 5, max = 600, def = 30, suffix = " с" },
	{ key = "MaxCharacters", path = { "MaxCharacters" }, name = "Персонажей на игрока", desc = "Лимит, если на карте не расставлены точки персонажей", type = "number", min = 1, max = 10, def = 3 },
	{ key = "StartMoney", path = { "StartMoney" }, name = "Стартовые деньги", desc = "Наличные у нового персонажа", type = "number", min = 0, max = 100000, def = 250, suffix = " $" },
	{ key = "ChatLimit", path = { "ChatLimit" }, name = "Длина сообщения", desc = "Максимум символов в одном сообщении чата", type = "number", min = 50, max = 1000, def = 300 },
	{ key = "ChatUseRecognition", path = { "ChatUseRecognition" }, name = "Незнакомцы в IC-чате", desc = "Подписывать незнакомых «Неизвестный»", type = "bool", def = false },
	{ key = "RangeSay", path = { "Ranges", "Say" }, name = "Дальность речи", desc = "Обычный IC-чат (52 ед. ≈ 1 м)", type = "number", min = 100, max = 1500, def = 320, suffix = " ед." },
	{ key = "RangeWhisper", path = { "Ranges", "Whisper" }, name = "Дальность шёпота", desc = "/w", type = "number", min = 30, max = 400, def = 90, suffix = " ед." },
	{ key = "RangeYell", path = { "Ranges", "Yell" }, name = "Дальность крика", desc = "/y", type = "number", min = 300, max = 3000, def = 750, suffix = " ед." },
	{ key = "RangeLOOC", path = { "Ranges", "LOOC" }, name = "Дальность LOOC", desc = ".// и /looc", type = "number", min = 100, max = 1500, def = 320, suffix = " ед." },
	{ key = "HungerMinutes", path = { "Needs", "HungerMinutes" }, name = "Голод: минут до нуля", desc = "За сколько минут сытость падает со 100 до 0", type = "number", min = 10, max = 600, def = 70, suffix = " мин" },
	{ key = "ThirstMinutes", path = { "Needs", "ThirstMinutes" }, name = "Жажда: минут до нуля", desc = "За сколько минут вода падает со 100 до 0", type = "number", min = 10, max = 600, def = 45, suffix = " мин" },
	{ key = "StarveDamage", path = { "Needs", "StarveDamage" }, name = "Урон от голода", desc = "Сколько здоровья отнимает голод за тик", type = "number", min = 0, max = 20, def = 2 },
	{ key = "MoveWalk", path = { "Movement", "Walk" }, name = "Скорость шага", desc = "Единиц в секунду", type = "number", min = 50, max = 200, def = 92 },
	{ key = "MoveRun", path = { "Movement", "Run" }, name = "Скорость бега", desc = "Единиц в секунду (Shift)", type = "number", min = 120, max = 400, def = 225 },
	{ key = "MoveJump", path = { "Movement", "Jump" }, name = "Сила прыжка", desc = "Без учёта навыка «Ловкость»", type = "number", min = 100, max = 400, def = 195 },
	{ key = "ObserverReturn", path = { "Admin", "ObserverReturn" }, name = "Наблюдатель: возврат", desc = "После выхода из наблюдателя вернуть админа на место входа", type = "bool", def = true },
	{ key = "ESPDistance", path = { "Admin", "ESPDistance" }, name = "Наблюдатель: дальность ESP", desc = "На каком расстоянии видно игроков сквозь стены", type = "number", min = 500, max = 30000, def = 8000, suffix = " ед." },
}
A.SettingByKey = {}
for _, s in ipairs(A.Settings) do A.SettingByKey[s.key] = s end

NYRP.Config.Admin = NYRP.Config.Admin or { ObserverReturn = true, ESPDistance = 8000 }

function A.GetSetting(s)
	local t = NYRP.Config
	for i = 1, #s.path - 1 do
		t = t[s.path[i]]
		if type(t) ~= "table" then return s.def end
	end
	local v = t[s.path[#s.path]]
	if v == nil then return s.def end
	return v
end

-- Проверка значения: возвращает нормализованное значение или nil.
function A.ValidateSetting(s, v)
	if s.type == "bool" then
		if type(v) == "boolean" then return v end
		if v == 1 or v == "1" or v == "true" then return true end
		if v == 0 or v == "0" or v == "false" then return false end
		return nil
	end
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
	v = math.floor(v + 0.5)
	if v < s.min or v > s.max then return nil end
	return v
end

function A.ApplySetting(s, v)
	local t = NYRP.Config
	for i = 1, #s.path - 1 do
		local k = s.path[i]
		if type(t[k]) ~= "table" then t[k] = {} end
		t = t[k]
	end
	t[s.path[#s.path]] = v
end

-- ------------------------------------------------------------ утилиты --
-- Нижний регистр с кириллицей (string.lower понимает только латиницу).
function A.Lower(s)
	s = string.lower(tostring(s or ""))
	local ok, out = pcall(function()
		local buf = {}
		for _, cp in utf8.codes(s) do
			if cp >= 0x410 and cp <= 0x42F then cp = cp + 0x20
			elseif cp == 0x401 then cp = 0x451 end
			buf[#buf + 1] = utf8.char(cp)
		end
		return table.concat(buf)
	end)
	return ok and out or s
end

-- «2 д 3 ч», «15 мин», «навсегда»
function A.FormatDuration(sec)
	if not sec or sec <= 0 then return "навсегда" end
	sec = math.floor(sec)
	local d = math.floor(sec / 86400)
	local h = math.floor((sec % 86400) / 3600)
	local m = math.floor((sec % 3600) / 60)
	local parts = {}
	if d > 0 then parts[#parts + 1] = d .. " д" end
	if h > 0 then parts[#parts + 1] = h .. " ч" end
	if m > 0 and d == 0 then parts[#parts + 1] = m .. " мин" end
	if #parts == 0 then return math.max(sec, 1) .. " с" end
	return table.concat(parts, " ")
end

-- SteamID в формате STEAM_0:X:Y из любого (STEAM_ или SteamID64). nil — не SteamID.
function A.NormalizeSteamID(s)
	s = string.Trim(tostring(s or ""))
	if string.match(s, "^STEAM_%d:%d:%d+$") then return "STEAM_0" .. string.sub(s, 8) end
	if string.match(s, "^7656%d+$") and #s >= 16 then
		local id = util.SteamIDFrom64(s)
		if id and id ~= "STEAM_0:0:0" then return id end
	end
end

-- Поиск онлайн-игрока: SteamID / SteamID64 / «^» (сам) / часть имени персонажа или ника.
-- Возвращает игрока или nil и текст ошибки.
function A.Find(query, self)
	query = string.Trim(tostring(query or ""))
	if query == "" then return nil, "Не указан игрок" end
	if query == "^" and IsValid(self) then return self end
	local sid = A.NormalizeSteamID(query)
	if sid then
		for _, p in ipairs(player.GetAll()) do
			if p:SteamID() == sid then return p end
		end
		return nil, "Игрок " .. sid .. " не на сервере"
	end
	local q = A.Lower(query)
	local exact, found = nil, {}
	for _, p in ipairs(player.GetAll()) do
		local cn, nn = A.Lower(NYRP.CharName(p)), A.Lower(p:Nick())
		if cn == q or nn == q then exact = p end
		if string.find(cn, q, 1, true) or string.find(nn, q, 1, true) then found[#found + 1] = p end
	end
	if exact then return exact end
	if #found == 1 then return found[1] end
	if #found > 1 then
		local names = {}
		for i = 1, math.min(#found, 4) do names[#names + 1] = NYRP.CharName(found[i]) end
		return nil, "Найдено несколько: " .. table.concat(names, ", ") .. (#found > 4 and "…" or "") .. " — уточните"
	end
	return nil, "Игрок «" .. query .. "» не найден"
end

-- Разбор «<цель> <остальное>»: цель может быть в кавычках или из нескольких слов
-- (берётся самая длинная однозначная цепочка слов). Возвращает игрока, остаток строки, ошибку.
function A.SplitTarget(args, self)
	args = string.Trim(args or "")
	if args == "" then return nil, "", "Не указан игрок" end
	local quoted, rest = string.match(args, '^"([^"]+)"%s*(.*)$')
	if quoted then
		local p, err = A.Find(quoted, self)
		return p, rest, err
	end
	local words = {}
	for w in string.gmatch(args, "%S+") do words[#words + 1] = w end
	local firstErr
	for i = #words, 1, -1 do
		local p, err = A.Find(table.concat(words, " ", 1, i), self)
		if p then return p, table.concat(words, " ", i + 1), nil end
		if i == 1 then firstErr = err end
	end
	return nil, "", firstErr
end

function A.IsObserver(ply) return IsValid(ply) and ply:GetNW2Bool("nyrp.observer", false) end
function A.Spectating(ply)
	local t = IsValid(ply) and ply:GetNW2Entity("nyrp.spectate") or nil
	if IsValid(t) then return t end
end

-- ----------------------------------------------- наблюдатель: общие хуки --
-- V (noclip) у администратора включает/выключает режим наблюдателя вместо обычного noclip.
hook.Add("PlayerNoClip", "nyrp.admin.observer", function(ply, desired)
	if not ply:IsAdmin() then return end
	if SERVER and A.ToggleObserver and (ply.nyrpObsNext or 0) < CurTime() then
		ply.nyrpObsNext = CurTime() + 0.4
		A.ToggleObserver(ply)
	end
	return false
end)

-- Шаги наблюдателя не слышны.
hook.Add("PlayerFootstep", "nyrp.admin.observer", function(ply)
	if A.IsObserver(ply) then return true end
end)

-- Во время слежки за игроком собственное движение отключено.
hook.Add("StartCommand", "nyrp.admin.spectate", function(ply, cmd)
	if A.Spectating(ply) then
		cmd:ClearMovement()
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
		cmd:RemoveKey(IN_USE)
	end
end)
