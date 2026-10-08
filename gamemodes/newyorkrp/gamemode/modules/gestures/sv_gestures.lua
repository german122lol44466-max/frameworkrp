--[[
	Сервер: проигрывание жеста у всех рядом (через nyrp.inv.anim — тот же канал, что у сумки).
]]

local G = NYRP.Gestures

function G.Play(ply, act)
	if not IsValid(ply) or not ply:Alive() or (NYRP.Cond and NYRP.Cond.KO(ply)) then return end
	net.Start("nyrp.inv.anim")
	net.WriteEntity(ply)
	net.WriteUInt(act, 16)
	net.SendPVS(ply:GetPos())
end

net.Receive("nyrp.gesture.play", function(_, ply)
	local g = G.List[net.ReadUInt(8)]
	if not g or (ply.nyrpGestureNext or 0) > CurTime() then return end
	ply.nyrpGestureNext = CurTime() + 1.2
	G.Play(ply, g.act)
end)

-- Микро-жест, когда персонаж говорит (IC, шёпот, крик).
hook.Add("NYRP.ChatMessage", "nyrp.gestures", function(ply, kind, text)
	local T = NYRP.Chat.Types
	if kind ~= T.IC and kind ~= T.YELL and kind ~= T.WHISPER then return end
	if (ply.nyrpGestureNext or 0) > CurTime() then return end
	local act, matched = G.ForText(text)
	if not matched and math.random() > G.ChatChance then return end
	ply.nyrpGestureNext = CurTime() + 2
	G.Play(ply, act)
end)
