--[[
	Сервер: проигрывание жеста у всех рядом (через nyrp.inv.anim — тот же канал, что у сумки).
]]

local G = NYRP.Gestures

function G.Play(ply, act)
	if not IsValid(ply) or (act ~= 0 and (not ply:Alive() or (NYRP.Cond and NYRP.Cond.KO(ply)))) then return end
	net.Start("nyrp.inv.anim")
	net.WriteEntity(ply)
	net.WriteUInt(act, 16)
	net.SendPVS(ply:GetPos())
end

net.Receive("nyrp.gesture.play", function(_, ply)
	local g = G.List[net.ReadUInt(8)]
	if not g or (ply.nyrpGestureNext or 0) > CurTime() then return end
	ply.nyrpGestureNext = CurTime() + 1.2
	if g.id == "dance" then
		-- танцевать можно только стоя на месте; пошёл — танец обрывается
		if ply:GetVelocity():Length2D() > 15 or not ply:OnGround() then
			NYRP.Notify(ply, "Чтобы танцевать, остановитесь", "warning", 2)
			return
		end
		ply.nyrpDancing = CurTime()
	end
	G.Play(ply, g.act)
end)

hook.Add("SetupMove", "nyrp.gestures.dance", function(ply, mv)
	if not ply.nyrpDancing then return end
	if CurTime() - ply.nyrpDancing > 12 then ply.nyrpDancing = nil return end
	local moving = mv:GetForwardSpeed() ~= 0 or mv:GetSideSpeed() ~= 0 or mv:KeyDown(IN_JUMP) or mv:KeyDown(IN_DUCK)
	if moving and CurTime() - ply.nyrpDancing > 0.2 then
		ply.nyrpDancing = nil
		G.Play(ply, 0)
	end
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
