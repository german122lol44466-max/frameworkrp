--[[
	Чат на сервере: приём сообщений, команды, рассылка по дистанции.
	Совместим с хуком PlayerSay: другие аддоны могут изменить или отменить сообщение.
]]

local Chat = NYRP.Chat
local T = Chat.Types

local commands = {
	["/introduce"] = function(ply) NYRP.Recog.Introduce(ply) end,
	["/познакомиться"] = function(ply) NYRP.Recog.Introduce(ply) end,
	["/представиться"] = function(ply) NYRP.Recog.Introduce(ply) end,
}

function Chat.Send(recipients, kind, speaker, text)
	net.Start("nyrp.chat.msg")
	net.WriteUInt(kind, 4)
	net.WriteEntity(speaker or game.GetWorld())
	net.WriteString(text)
	net.Send(recipients)
end

function Chat.System(ply, text)
	Chat.Send(ply or player.GetAll(), T.SYSTEM, nil, text)
end

local function handle(ply, raw)
	raw = NYRP.CleanText(raw, NYRP.Config.ChatLimit)
	if raw == "" then return end

	local cmd = string.lower(string.match(raw, "^(%S+)") or "")
	if commands[cmd] then commands[cmd](ply, raw) return end

	-- совместимость с аддонами (ULX и т.п.)
	ply.nyrpInternalSay = true
	local res = hook.Run("PlayerSay", ply, raw, false)
	ply.nyrpInternalSay = nil
	if res ~= nil then
		if res == "" then return end
		raw = res
	end

	local kind, text = Chat.Parse(raw)
	if text == "" then return end
	if kind ~= T.OOC and kind ~= T.LOOC and (not NYRP.HasCharacter(ply) or not ply:Alive()) then
		Chat.System(ply, "Вы не можете говорить сейчас. Используйте // для OOC.")
		return
	end

	local recipients
	if kind == T.OOC then
		recipients = player.GetAll()
	else
		recipients = {}
		local range = Chat.Range(kind)
		local pos = ply:GetPos()
		for _, p in ipairs(player.GetAll()) do
			if p:GetPos():DistToSqr(pos) <= range * range then recipients[#recipients + 1] = p end
		end
	end
	Chat.Send(recipients, kind, ply, text)
	NYRP.Print(string.format("[чат:%d] %s (%s): %s", kind, ply:Nick(), NYRP.CharName(ply), text))
end

net.Receive("nyrp.chat.say", function(_, ply)
	if (ply.nyrpChatNext or 0) > CurTime() then return end
	ply.nyrpChatNext = CurTime() + 0.6
	handle(ply, net.ReadString())
	ply:SetNW2Int("nyrp.typing", 0)
end)

-- «Говорит/Кричит/Шепчет...» над головой.
net.Receive("nyrp.chat.typing", function(_, ply)
	local st = net.ReadUInt(4)
	if (ply.nyrpTypingNext or 0) > CurTime() and st ~= 0 then return end
	ply.nyrpTypingNext = CurTime() + 0.1
	ply:SetNW2Int("nyrp.typing", math.Clamp(st, 0, 7))
end)

-- «say» из консоли движка тоже идёт через наш чат.
function GM:PlayerSay(ply, text, team)
	if ply.nyrpInternalSay then return text end
	timer.Simple(0, function() if IsValid(ply) then handle(ply, text) end end)
	return ""
end
