--[[
	Чат на сервере: проверка, команды, совместимость с PlayerSay (админ-моды), рассылка по режимам.
]]

local CH = WS.Chat
local L = WS.Lobby

util.AddNetworkString("ws.chat.say")
util.AddNetworkString("ws.chat.msg")

local function receivers(ply, mode)
	local out = {}
	if mode == "ooc" then return player.GetAll() end
	local id = L.Id(ply)
	if mode == "squad" or not L.InGame(ply) then
		-- рация отряда; в меню «рядом» — тоже свой отряд
		for _, p in ipairs(player.GetAll()) do
			if p == ply or (id ~= 0 and L.Id(p) == id) then out[#out + 1] = p end
		end
		return out
	end
	local r2 = WS.Config.ChatRange ^ 2
	local pos = ply:GetPos()
	for _, p in ipairs(player.GetAll()) do
		if p == ply or (L.InGame(p) and p:GetPos():DistToSqr(pos) < r2) then out[#out + 1] = p end
	end
	return out
end

function CH.Broadcast(ply, mode, text)
	local to = receivers(ply, mode)
	if #to == 0 then return end
	net.Start("ws.chat.msg")
	net.WriteEntity(ply)
	net.WriteUInt(CH.ModeId[mode] or 1, 3)
	net.WriteString(text)
	net.Send(to)
	MsgN(string.format("[%s] %s: %s", mode, ply:Nick(), text))
end

net.Receive("ws.chat.say", function(_, ply)
	local mode = CH.ModeName[net.ReadUInt(3)] or "local"
	local raw = net.ReadString()
	if (ply.wsNextChat or 0) > CurTime() then return end
	ply.wsNextChat = CurTime() + 0.6
	if mode ~= "local" and mode ~= "squad" and mode ~= "ooc" then mode = "local" end
	local text = CH.Clean(raw)
	if text == "" then return end
	mode, text = CH.Parse(mode, text)
	text = CH.Clean(text)
	if text == "" then return end
	-- админ-моды и другие аддоны получают сообщение как обычно; пустая строка — подавить
	local res = hook.Run("PlayerSay", ply, text, mode == "squad")
	if res == "" then return end
	if isstring(res) then text = CH.Clean(res) end
	if text == "" then return end
	CH.Broadcast(ply, mode, text)
end)
