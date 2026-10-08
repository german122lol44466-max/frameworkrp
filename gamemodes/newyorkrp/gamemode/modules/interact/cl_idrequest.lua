--[[
	Запрос «показать удостоверение»: внизу экрана карточка «Человек протягивает вам удостоверение»,
	Y — посмотреть, N — отказаться (15 секунд на ответ).
]]

local UI = NYRP.UI
local queue = {}
local TIME = 15

net.Receive("nyrp.id.request", function()
	local from = net.ReadEntity()
	if not IsValid(from) then return end
	for i = #queue, 1, -1 do if queue[i].from == from then table.remove(queue, i) end end
	queue[#queue + 1] = { from = from, born = RealTime() }
	UI.Sound("notify")
end)

local function answer(req, yes)
	net.Start("nyrp.id.answer")
	net.WriteEntity(req.from)
	net.WriteBool(yes)
	net.SendToServer()
	req.done = RealTime()
	req.yes = yes
	UI.Sound(yes and "success" or "close")
end

local down = {}
hook.Add("Think", "nyrp.idrequest", function()
	local req = queue[1]
	if not req then return end
	if req.done then
		if RealTime() - req.done > 0.35 then table.remove(queue, 1) end
		return
	end
	if RealTime() - req.born > TIME or not IsValid(req.from) then answer(req, false) return end
	if vgui.GetKeyboardFocus() or gui.IsGameUIVisible() then return end
	for _, k in ipairs({ KEY_Y, KEY_N }) do
		local d = input.IsKeyDown(k)
		if d and not down[k] then answer(req, k == KEY_Y) end
		down[k] = d
	end
end)

local function key(x, y, letter, label, col, a)
	local kw = UI.S(26)
	UI.RoundedRect(UI.S(6), x, y - kw / 2, kw, kw, Color(255, 255, 255, 235 * a))
	draw.SimpleText(letter, NYRP.Font("bold", 15), x + kw / 2, y, Color(10, 12, 18, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(label, NYRP.Font("semibold", 15), x + kw + UI.S(8), y, UI.Alpha(col, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	return kw + UI.S(8) + UI.TextSize(label, NYRP.Font("semibold", 15))
end

hook.Add("HUDPaint", "nyrp.idrequest", function()
	local req = queue[1]
	if not req or NYRP.HUDHidden() then return end
	local el = RealTime() - req.born
	local a = UI.Ease(el / 0.3)
	if req.done then a = a * (1 - (RealTime() - req.done) / 0.35) end
	if a <= 0 then return end
	local who = IsValid(req.from) and ((NYRP.Recog and NYRP.Recog.Knows(req.from)) and NYRP.CharName(req.from) or "Незнакомец") or "Человек"
	local w, h = UI.S(460), UI.S(92)
	local x, y = ScrW() / 2 - w / 2, ScrH() - UI.S(260) + (1 - a) * UI.S(16)
	surface.SetAlphaMultiplier(a)
	UI.BlurRect(x, y, w, h, 4)
	UI.RoundedRect(UI.S(14), x, y, w, h, Color(10, 11, 16, 232))
	UI.Outline(UI.S(14), x, y, w, h, UI.Alpha(UI.Col.accent, 70), 1)
	UI.Circle(x + UI.S(38), y + UI.S(34), UI.S(20), UI.Alpha(UI.Col.accent, 36))
	UI.DrawIcon("id", x + UI.S(38), y + UI.S(34), UI.S(22), UI.Col.accent)
	draw.SimpleText(who .. " протягивает вам удостоверение", NYRP.Font("semibold", 17), x + UI.S(70), y + UI.S(24), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local kx = x + UI.S(70)
	kx = kx + key(kx, y + UI.S(56), "Y", "Посмотреть", UI.Col.green, 1) + UI.S(22)
	key(kx, y + UI.S(56), "N", "Отказаться", UI.Col.red, 1)
	local frac = req.done and 0 or 1 - math.Clamp(el / TIME, 0, 1)
	UI.RoundedRect(1, x + UI.S(14), y + h - UI.S(5), (w - UI.S(28)) * frac, UI.S(2), UI.Alpha(UI.Col.accent, 170))
	surface.SetAlphaMultiplier(1)
end)
