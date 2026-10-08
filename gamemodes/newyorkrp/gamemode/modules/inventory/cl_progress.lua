--[[
	Прогресс-бар действий: «Одеваю...», «Орудую...». Сервер присылает текст и длительность.
]]

local UI = NYRP.UI
local act

net.Receive("nyrp.action", function()
	local text, dur, icon = net.ReadString(), net.ReadFloat(), net.ReadString()
	if text == "" then
		if act then act.cancel = RealTime() end
		return
	end
	act = { text = text, dur = dur, icon = icon ~= "" and icon or "hourglass", start = RealTime() }
	UI.Sound("progress")
end)

hook.Add("DrawOverlay", "nyrp.progress", function()
	if not act then return end
	local now = RealTime()
	local el = now - act.start
	local frac = math.Clamp(el / act.dur, 0, 1)
	local done = el > act.dur
	local out = act.cancel and (now - act.cancel) or (done and (el - act.dur) or 0)
	if out > 0.35 then
		if done and not act.cancel then UI.Sound("complete") end
		act = nil
		return
	end
	local a = UI.Ease(el / 0.25) * (1 - out / 0.35)
	local w, h = UI.S(380), UI.S(70)
	local x, y = ScrW() / 2 - w / 2, ScrH() * 0.74 + (1 - a) * UI.S(20)
	surface.SetAlphaMultiplier(a)
	UI.BlurRect(x, y, w, h, 4)
	UI.RoundedRect(UI.S(14), x, y, w, h, Color(10, 12, 20, 230))
	UI.Outline(UI.S(14), x, y, w, h, Color(255, 255, 255, 16), 1)
	UI.Circle(x + UI.S(36), y + h / 2, UI.S(20), UI.Alpha(UI.Col.accent, 34))
	UI.DrawIcon(act.icon, x + UI.S(36), y + h / 2, UI.S(20), UI.Col.accent)
	draw.SimpleText(act.cancel and "Отменено" or act.text, NYRP.Font("semibold", 18), x + UI.S(68), y + UI.S(22), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(math.floor(frac * 100) .. "%", NYRP.Font("bold", 15), x + w - UI.S(20), y + UI.S(22), UI.Col.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	local bx, by, bw, bh = x + UI.S(68), y + UI.S(42), w - UI.S(88), UI.S(8)
	UI.RoundedRect(bh / 2, bx, by, bw, bh, Color(255, 255, 255, 16))
	UI.RoundedRect(bh / 2, bx, by, math.max(bw * frac, bh), bh, act.cancel and UI.Col.red or UI.Col.accent)
	surface.SetAlphaMultiplier(1)
end)
