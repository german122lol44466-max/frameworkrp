util.AddNetworkString("ws.phrase")
util.AddNetworkString("ws.phrase.anim")

net.Receive("ws.phrase", function(_, ply)
	local i = net.ReadUInt(4)
	local ph = WS.Phrases[i]
	if not ph or not ply:Alive() or not WS.Lobby.InGame(ply) then return end
	if (ply.wsNextPhrase or 0) > CurTime() then return end
	ply.wsNextPhrase = CurTime() + WS.Config.PhraseCooldown
	ply:EmitSound("whitesilence/game/vo_" .. WS.PhraseVoice(ply) .. "_" .. ph.id .. ".mp3", 80, math.random(97, 103), 1, CHAN_VOICE)
	net.Start("ws.phrase.anim")
	net.WriteEntity(ply)
	net.WriteUInt(i, 4)
	net.SendPVS(ply:GetPos())
	if WS.Chat and WS.Chat.Broadcast then WS.Chat.Broadcast(ply, "phrase", ph.text) end
end)
