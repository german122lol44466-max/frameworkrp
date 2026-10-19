--[[
	Голос: в игре — по близости и объёмно (тише с расстоянием, слышно, откуда); в меню — общий канал отряда.
	Павших живые не слышат; павшие (наблюдатели) слышат всех и друг друга.
]]

local L = WS.Lobby

hook.Add("PlayerCanHearPlayersVoice", "ws.voice", function(listener, talker)
	local li, ti = L.InGame(listener), L.InGame(talker)
	if li and ti then
		local ta, la = talker:Alive(), listener:Alive()
		if not ta then return not la, false end          -- павших слышат только павшие
		if not la then return true, false end            -- наблюдатель слышит живых
		return listener:GetPos():DistToSqr(talker:GetPos()) < WS.Config.VoiceRange ^ 2, true
	end
	if not li and not ti then
		local id = L.Id(talker)
		return id ~= 0 and id == L.Id(listener), false
	end
	return false
end)
