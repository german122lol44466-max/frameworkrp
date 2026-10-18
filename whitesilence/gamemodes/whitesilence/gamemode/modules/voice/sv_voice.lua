--[[
	Голос: в игре — по близости и объёмно (тише с расстоянием, слышно, откуда); в меню — общий канал отряда.
	Мёртвые живых не слышат и не говорят им.
]]

local L = WS.Lobby

hook.Add("PlayerCanHearPlayersVoice", "ws.voice", function(listener, talker)
	local li, ti = L.InGame(listener), L.InGame(talker)
	if li and ti then
		if not talker:Alive() or not listener:Alive() then return false end
		return listener:GetPos():DistToSqr(talker:GetPos()) < WS.Config.VoiceRange ^ 2, true
	end
	if not li and not ti then
		local id = L.Id(talker)
		return id ~= 0 and id == L.Id(listener), false
	end
	return false
end)
