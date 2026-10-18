--[[
	Смерть на клиенте: камера из глаз падающего тела, мир теряет цвет и темнеет, глухой удар и затихающее
	сердцебиение; затем экран смерти — «ВЫ ПОГИБЛИ», причина, время в бою; через 5 с — [ПРОБЕЛ] в меню.
]]

local E = WS.Ease
local D = {}
WS.Death = D

local deathT, causeText, deployT = nil, "", nil
local wasAlive = true
local beats = 0

hook.Add("WSDeployed", "ws.death", function() deployT = CurTime() + 1.5 end)

net.Receive("ws.death", function()
	causeText = net.ReadString()
end)

local function onDeath()
	deathT = RealTime()
	D.deathCur = CurTime()
	beats = 0
	if WS.Vision and WS.Vision.Mode then WS.Vision.Set(nil) end
	WS.Audio.Play("whitesilence/game/death.ogg", { volume = 0.7 })
	WS.Audio.Play("whitesilence/game/bodyfall.ogg", { volume = 0.6 })
	-- сердце бьётся всё реже и тише
	local delay = 0.25
	for i = 1, 7 do
		delay = delay + 0.55 + i * 0.22
		timer.Simple(delay, function()
			if deathT then WS.Audio.Play("whitesilence/game/heartbeat.ogg", { volume = 0.8 * (1 - i / 8) }) end
		end)
	end
end

hook.Add("Think", "ws.death", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local alive = ply:Alive()
	if wasAlive and not alive and WS.Lobby.InGame(ply) then onDeath() end
	if alive and deathT then deathT = nil end
	wasAlive = alive
	if deathT and RealTime() - deathT > 5 and input.IsKeyDown(KEY_SPACE) and not vgui.GetKeyboardFocus() and not D.sent then
		D.sent = true
		net.Start("ws.death.return")
		net.SendToServer()
		timer.Simple(1, function() D.sent = nil end)
	end
end)

-- взгляд из глаз тела
hook.Add("CalcView", "ws.death", function(ply, origin, angles, fov)
	if not deathT then return end
	local rag = ply:GetRagdollEntity()
	if not IsValid(rag) then return end
	local att = rag:LookupAttachment("eyes")
	if not att or att <= 0 then return end
	local a = rag:GetAttachment(att)
	if not a then return end
	local k = E.Smooth((RealTime() - deathT) / 3)
	return { origin = a.Pos, angles = a.Ang, fov = Lerp(k, fov, fov * 0.8), drawviewer = false, znear = 1 }
end)

local cm = {
	["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 1,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
}

hook.Add("RenderScreenspaceEffects", "ws.death", function()
	if not deathT then return end
	local k = E.Smooth((RealTime() - deathT) / 2.5)
	cm["$pp_colour_colour"] = Lerp(k, 1, 0.05)
	cm["$pp_colour_brightness"] = Lerp(k, 0, -0.12)
	cm["$pp_colour_addr"] = Lerp(k, 0.08, 0.02)
	cm["$pp_colour_contrast"] = Lerp(k, 1.1, 0.85)
	DrawColorModify(cm)
	DrawMotionBlur(0.15, 0.85 * k, 0.02)
end)

hook.Add("HUDPaint", "ws.death", function()
	if not deathT then return end
	local w, h = ScrW(), ScrH()
	local s = h / 1080
	local t = RealTime() - deathT
	local FX = WS.Intro.FX
	FX.Ensure()
	-- красная вспышка в момент смерти
	local flash = 1 - E.Smooth(t / 0.8)
	if flash > 0 then
		surface.SetDrawColor(150, 0, 0, 160 * flash)
		surface.DrawRect(0, 0, w, h)
	end
	FX.Vignette(math.min(1, 0.6 + t * 0.2))
	-- затемнение и экран смерти
	local dark = E.Smooth((t - 2.2) / 1.6)
	if dark <= 0 then return end
	surface.SetDrawColor(4, 5, 7, 225 * dark)
	surface.DrawRect(0, 0, w, h)
	FX.Grain(dark)
	local a = E.Smooth((t - 2.8) / 1.2)
	local cy = h * 0.42
	draw.SimpleText("ВЫ ПОГИБЛИ", WS.Font("menubold", 74, 12), w / 2, cy, Color(160, 20, 20, 140 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText("ВЫ ПОГИБЛИ", WS.Font("menubold", 74), w / 2, cy, Color(236, 238, 242, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local lw = 260 * s * E.OutCubic((t - 3.0) / 1.0)
	surface.SetDrawColor(196, 38, 38, 220 * a)
	surface.DrawRect(w / 2 - lw / 2, cy + 50 * s, lw, 2 * s)
	draw.SimpleText(causeText ~= "" and causeText or "Неизвестно", WS.Font("menu", 24), w / 2, cy + 88 * s,
		Color(206, 212, 222, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if deployT then
		local sec = math.max(0, math.floor((D.deathCur or CurTime()) - deployT))
		draw.SimpleText(string.format("Время в бою: %d:%02d", sec / 60, sec % 60), WS.Font("menulight", 19), w / 2, cy + 124 * s,
			Color(160, 168, 180, 230 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	if t > 5 then
		local p = 0.6 + 0.4 * math.sin(RealTime() * 3)
		draw.SimpleText("[ПРОБЕЛ] — вернуться в меню", WS.Font("menu", 22), w / 2, h * 0.78,
			Color(226, 190, 120, 255 * p * E.Smooth((t - 5) / 0.6)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end)

function D.Active()
	return deathT ~= nil
end
