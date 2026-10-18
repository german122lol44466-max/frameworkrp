--[[
	Отряды (лобби) — общая часть.

	Состояние лежит в сетевых переменных игроков (NW2), его видят все клиенты:
	  ws_lobby   — номер отряда (0 — нет)
	  ws_lobby_t — когда вошёл (порядок в списке)
	  ws_lead    — командир отряда
	  ws_ingame  — уже в игре (не в меню)
	  ws_callsign — позывной, указанный игроком
	Действия игрок отправляет сообщениями ws.lobby.*, сервер проверяет и меняет переменные.
]]

local L = WS.Lobby

function L.Id(ply)
	return IsValid(ply) and ply:GetNW2Int("ws_lobby", 0) or 0
end

function L.InGame(ply)
	return IsValid(ply) and ply:GetNW2Bool("ws_ingame", false)
end

function L.IsLeader(ply)
	return IsValid(ply) and ply:GetNW2Bool("ws_lead", false)
end

-- Позывной, если указан, иначе ник Steam
function L.Name(ply)
	if not IsValid(ply) then return "?" end
	local cs = ply:GetNW2String("ws_callsign", "")
	return cs ~= "" and cs or ply:Nick()
end

-- Состав отряда по порядку входа (командир первым)
function L.Members(id)
	local out = {}
	if not id or id == 0 then return out end
	for _, p in ipairs(player.GetAll()) do
		if L.Id(p) == id then out[#out + 1] = p end
	end
	table.sort(out, function(a, b)
		local la, lb = L.IsLeader(a), L.IsLeader(b)
		if la ~= lb then return la end
		return a:GetNW2Float("ws_lobby_t", 0) < b:GetNW2Float("ws_lobby_t", 0)
	end)
	return out
end

-- Кого можно пригласить: на сервере, в меню (не в игре) и не в этом отряде
function L.Invitable(id)
	local out = {}
	for _, p in ipairs(player.GetAll()) do
		if not L.InGame(p) and L.Id(p) ~= id and not p:IsBot() then out[#out + 1] = p end
	end
	return out
end

-- Проверка позывного: 2–20 символов, буквы (любого алфавита), цифры, пробел, - _ .
function L.CleanCallsign(s)
	if not isstring(s) then return nil end
	s = string.Trim(s)
	local n = utf8.len(s)
	if not n or n < WS.Config.CallsignMin or n > WS.Config.CallsignMax then return nil end
	for _, code in utf8.codes(s) do
		local ok = code >= 0x80                                    -- не-ASCII буквы (кириллица и т.п.)
			or (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
			or code == 32 or code == 45 or code == 95 or code == 46
		if not ok then return nil end
		if code < 32 or (code >= 0x7F and code < 0xA0) or code == 0x200B or code == 0xFEFF then return nil end
	end
	return s
end
