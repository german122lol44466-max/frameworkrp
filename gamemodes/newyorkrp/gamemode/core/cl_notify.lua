--[[
	Уведомления справа сверху: карточка со значком, текстом и полоской времени.
	NYRP.Notify(text, kind, duration)  kind: info | success | error | warning
]]

local UI = NYRP.UI
local list = {}

local styles = {
	info = { icon = "info", col = Color(96, 164, 232), sound = "notify" },
	success = { icon = "check", col = Color(104, 200, 120), sound = "success" },
	error = { icon = "warning", col = Color(214, 70, 64), sound = "error" },
	warning = { icon = "bell", col = Color(247, 198, 0), sound = "warning" },
	item = { icon = "item", col = Color(247, 198, 0), sound = "notify" },
}

function NYRP.Notify(text, kind, duration)
	kind = styles[kind] and kind or "info"
	table.insert(list, 1, { text = tostring(text), kind = kind, born = RealTime(), dur = duration or 5, y = nil, x = 1 })
	while #list > 6 do table.remove(list) end
	UI.Sound(styles[kind].sound)
end

net.Receive("nyrp.notify", function()
	NYRP.Notify(net.ReadString(), net.ReadString(), net.ReadFloat())
end)

-- Стандартные уведомления песочницы тоже в нашем стиле.
local legacy = { [NOTIFY_GENERIC or 0] = "info", [NOTIFY_ERROR or 1] = "error", [NOTIFY_UNDO or 2] = "info", [NOTIFY_HINT or 3] = "info", [NOTIFY_CLEANUP or 4] = "success" }
function notification.AddLegacy(text, kind, length)
	NYRP.Notify(text, legacy[kind] or "info", length)
end
function notification.AddProgress(_, text)
	NYRP.Notify(text, "info", 3)
end
function notification.Kill() end

hook.Add("DrawOverlay", "nyrp.notify", function()
	if #list == 0 then return end
	local now = RealTime()
	local w = UI.S(340)
	local x0 = ScrW() - UI.S(24)
	-- ниже полоски выносливости и иконок состояний (modules/condition)
	local y = UI.S(24) + (NYRP.Cond and NYRP.Cond.HUDHeight or 0)
	local font = NYRP.Font("medium", 16)
	for i = #list, 1, -1 do
		local n = list[i]
		if now - n.born > n.dur + 0.4 then table.remove(list, i) end
	end
	for _, n in ipairs(list) do
		local age = now - n.born
		local appear = UI.Ease(age / 0.35)
		local leave = age > n.dur and UI.Ease((age - n.dur) / 0.35) or 0
		local st = styles[n.kind]
		local lines = UI.Wrap(n.text, font, w - UI.S(78))
		local h = UI.S(28) + #lines * UI.S(20)
		h = math.max(h, UI.S(58))
		n.y = n.y and UI.Approach(n.y, y, 12) or y
		local x = x0 - w + (1 - appear + leave) * (w + UI.S(40))
		local a = (1 - leave) * appear

		surface.SetAlphaMultiplier(a)
		UI.BlurRect(x, n.y, w, h, 4)
		UI.RoundedRect(UI.S(10), x, n.y, w, h, Color(12, 14, 22, 225))
		UI.Outline(UI.S(10), x, n.y, w, h, Color(255, 255, 255, 14), 1)
		UI.Circle(x + UI.S(30), n.y + h / 2, UI.S(16), UI.Alpha(st.col, 40))
		UI.DrawIcon(st.icon, x + UI.S(30), n.y + h / 2, UI.S(18), st.col)
		local ty = n.y + h / 2 - #lines * UI.S(20) / 2
		for li, l in ipairs(lines) do
			draw.SimpleText(l, font, x + UI.S(58), ty + (li - 1) * UI.S(20), UI.Col.text)
		end
		local prog = 1 - math.Clamp(age / n.dur, 0, 1)
		UI.RoundedRect(1, x + UI.S(12), n.y + h - UI.S(4), (w - UI.S(24)) * prog, UI.S(2), UI.Alpha(st.col, 160))
		surface.SetAlphaMultiplier(1)
		y = y + (h + UI.S(10)) * (1 - leave)
	end
end)
