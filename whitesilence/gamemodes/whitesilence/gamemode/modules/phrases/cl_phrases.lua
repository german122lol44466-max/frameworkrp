--[[
	Радиальное меню фраз: держите G, ведите мышью к нужной фразе, отпустите — боец скажет её вслух
	(слышат рядом), покажет жест, фраза появится в чате рядом. Отпустить в центре — отмена.
]]

local UI = WS.UI
local E = WS.Ease
local open, openT, sel = false, 0, nil
local gDown = false

local function canUse()
	local ply = LocalPlayer()
	return IsValid(ply) and ply:Alive() and WS.Lobby.InGame(ply) and not vgui.GetKeyboardFocus() and not gui.IsGameUIVisible()
		and not (WS.Chat and WS.Chat.IsOpen and WS.Chat.IsOpen())
end

hook.Add("Think", "ws.phrases", function()
	local down = input.IsKeyDown(KEY_G)
	if down and not gDown and canUse() then
		open, openT, sel = true, RealTime(), nil
		gui.EnableScreenClicker(true)
		input.SetCursorPos(ScrW() / 2, ScrH() / 2)
	elseif not down and gDown and open then
		open = false
		gui.EnableScreenClicker(false)
		if sel then
			net.Start("ws.phrase")
			net.WriteUInt(sel, 4)
			net.SendToServer()
		end
	end
	gDown = down
end)

hook.Add("HUDPaint", "ws.phrases", function()
	if not open then return end
	local w, h = ScrW(), ScrH()
	local s = h / 1080
	local cx, cy = w / 2, h / 2
	local mx, my = input.GetCursorPos()
	local dx, dy = mx - cx, my - cy
	local n = #WS.Phrases
	local a = E.OutCubic((RealTime() - openT) / 0.15)
	local R = 230 * s * Lerp(a, 0.85, 1)
	sel = nil
	if dx * dx + dy * dy > (50 * s) ^ 2 then
		local ang = (math.deg(math.atan2(dy, dx)) + 90 + 360 / n / 2) % 360
		sel = math.floor(ang / (360 / n)) + 1
	end
	-- затемнение и кольцо
	surface.SetMaterial(UI.Mat(WS.Intro.Path .. "flake.png", "smooth"))
	surface.SetDrawColor(0, 0, 0, 200 * a)
	surface.DrawTexturedRect(cx - R * 1.6, cy - R * 1.6, R * 3.2, R * 3.2)
	for i, ph in ipairs(WS.Phrases) do
		local ang = math.rad((i - 1) * 360 / n - 90)
		local px, py = cx + math.cos(ang) * R, cy + math.sin(ang) * R
		local on = i == sel
		local font = WS.Font(on and "menusemi" or "menu", on and 22 or 19)
		surface.SetFont(font)
		local tw, th = surface.GetTextSize(ph.text)
		draw.RoundedBox(4, px - tw / 2 - 14 * s, py - th / 2 - 8 * s, tw + 28 * s, th + 16 * s,
			on and Color(196, 38, 38, 210 * a) or Color(10, 12, 16, 200 * a))
		draw.SimpleText(ph.text, font, px, py, Color(240, 242, 246, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	-- центр: что выбрано
	draw.SimpleText(sel and "Отпустите G" or "Голосовые фразы", WS.Font("menulight", 18), cx, cy, Color(200, 206, 216, 220 * a),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if sel then
		surface.SetDrawColor(196, 38, 38, 200 * a)
		local ang = math.rad((sel - 1) * 360 / n - 90)
		local r0 = 60 * s
		for k = 0, 10 do
			local t = k / 10
			surface.DrawRect(cx + math.cos(ang) * (r0 + t * (R - r0 - 40 * s)) - 1, cy + math.sin(ang) * (r0 + t * (R - r0 - 40 * s)) - 1, 3 * s, 3 * s)
		end
	end
end)

-- жест говорящего
net.Receive("ws.phrase.anim", function()
	local ply = net.ReadEntity()
	local ph = WS.Phrases[net.ReadUInt(4)]
	if IsValid(ply) and ph and ph.act then ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ph.act, true) end
end)
