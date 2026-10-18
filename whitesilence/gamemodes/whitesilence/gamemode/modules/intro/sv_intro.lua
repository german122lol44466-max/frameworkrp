--[[
	Интро на сервере: пока клиент смотрит интро, игрок заморожен и неуязвим.
	Если клиент так и не сообщил о конце (вылет, ошибка) — размораживаем по таймеру.
]]

util.AddNetworkString("ws.intro")

CreateConVar("ws_intro_force", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
	"1 — интро показывается каждому игроку при каждом входе", 0, 1)

local function release(ply)
	if not IsValid(ply) or not ply.wsInIntro then return end
	ply.wsInIntro = nil
	ply:Freeze(false)
	ply:GodDisable()
	timer.Remove("ws.intro." .. ply:EntIndex())
end

net.Receive("ws.intro", function(_, ply)
	local on = net.ReadBool()
	-- не чаще раза в секунду
	if (ply.wsIntroNext or 0) > CurTime() then return end
	ply.wsIntroNext = CurTime() + 1

	if on then
		ply.wsInIntro = true
		ply:Freeze(true)
		ply:GodEnable()
		timer.Create("ws.intro." .. ply:EntIndex(), WS.Config.IntroMaxTime, 1, function() release(ply) end)
	else
		release(ply)
	end
end)

hook.Add("PlayerSpawn", "ws.intro", function(ply)
	-- респавн во время интро: оставляем замороженным
	if ply.wsInIntro then
		timer.Simple(0, function()
			if IsValid(ply) and ply.wsInIntro then ply:Freeze(true) ply:GodEnable() end
		end)
	end
end)

hook.Add("PlayerDisconnected", "ws.intro", function(ply)
	timer.Remove("ws.intro." .. ply:EntIndex())
end)
