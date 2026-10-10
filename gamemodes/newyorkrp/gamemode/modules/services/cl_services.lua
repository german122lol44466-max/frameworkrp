local E = NYRP.E911
local UI = NYRP.UI
local P = NYRP.Phone
local RED = Color(230, 70, 60)

-- ------------------------------------------------------------ входящие вызовы --
E.Incoming = E.Incoming or {}
net.Receive("nyrp.e911.call", function()
	local c = { id = net.ReadUInt(16), service = net.ReadString(), reason = net.ReadString(), comment = net.ReadString(),
		from = net.ReadString(), pos = net.ReadVector(), born = RealTime() }
	table.insert(E.Incoming, 1, c)
	while #E.Incoming > 3 do table.remove(E.Incoming) end
	surface.PlaySound("nyrp/fx/dispatch.wav")
end)

local acceptKey = CreateClientConVar("nyrp_bind_911", tostring(KEY_F6), true, false, "Клавиша: принять вызов 911")
local wasDown = false
hook.Add("Think", "nyrp.e911", function()
	local down = input.IsKeyDown(acceptKey:GetInt())
	if down and not wasDown and #E.Incoming > 0 and not vgui.GetKeyboardFocus() then
		local c = table.remove(E.Incoming, 1)
		net.Start("nyrp.e911.accept") net.WriteUInt(c.id, 16) net.SendToServer()
	end
	wasDown = down
	for i = #E.Incoming, 1, -1 do if RealTime() - E.Incoming[i].born > 45 then table.remove(E.Incoming, i) end end
end)

hook.Add("HUDPaint", "nyrp.e911", function()
	if #E.Incoming == 0 or (NYRP.HUDHidden and NYRP.HUDHidden()) then return end
	local w = UI.S(360)
	local x, y = ScrW() - w - UI.S(24), ScrH() * 0.3
	for i, c in ipairs(E.Incoming) do
		local a = math.min(1, (RealTime() - c.born) / 0.3)
		local h = UI.S(c.comment ~= "" and 112 or 92)
		surface.SetAlphaMultiplier(a * (i == 1 and 1 or 0.6))
		UI.RoundedRect(UI.S(12), x, y, w, h, Color(24, 10, 12, 230))
		local pulse = 0.5 + 0.5 * math.abs(math.sin(RealTime() * 5))
		UI.RoundedRect(UI.S(3), x, y + UI.S(12), UI.S(4), h - UI.S(24), Color(RED.r, RED.g, RED.b, 150 + 105 * pulse))
		UI.DrawIcon("urgent", x + UI.S(30), y + UI.S(28), UI.S(24), RED)
		draw.SimpleText("911 · " .. c.service, NYRP.Font("bold", 13), x + UI.S(54), y + UI.S(12), RED)
		draw.SimpleText(c.reason, NYRP.Font("bold", 18), x + UI.S(54), y + UI.S(30), color_white)
		draw.SimpleText(c.from .. " · " .. math.floor(EyePos():Distance(c.pos) * 0.019) .. " м", NYRP.Font("medium", 12), x + UI.S(54), y + UI.S(56), UI.Col.dim)
		if c.comment ~= "" then draw.SimpleText("«" .. c.comment .. "»", NYRP.Font("regular", 12), x + UI.S(54), y + UI.S(74), Color(220, 220, 228)) end
		if i == 1 then
			draw.SimpleText("[" .. (input.GetKeyName(acceptKey:GetInt()) or "F6"):upper() .. "] принять", NYRP.Font("bold", 13), x + w - UI.S(14), y + h - UI.S(16), Color(247, 198, 0), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		surface.SetAlphaMultiplier(1)
		y = y + h + UI.S(8)
	end
end)

-- ------------------------------------------------------------ приложение 911 --
if not P or not P.Register then return end
local function S(x) return UI.S(x) end
local C = P.Col

table.insert(P.BaseApps, 2, { id = "e911", name = "911", icon = "urgent", color = Color(220, 50, 50) })

net.Receive("nyrp.e911", function() E.ServiceList = net.ReadTable() end)

P.Register("e911", {
	enter = function(st) E.ServiceList = nil net.Start("nyrp.e911") net.SendToServer() end,
	draw = function(st, x, y, w, h)
		local cy = P.Header("Экстренный вызов", x, y, w, RED)
		UI.RoundedRect(S(14), x + S(14), cy, w - S(28), S(60), Color(220, 50, 50, 40))
		P.Text("911", "title", 30, x + S(30), cy + S(30), RED, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		P.Text("Кого вызвать?", "semibold", 14, x + S(96), cy + S(30), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		cy = cy + S(72)
		local list = E.ServiceList
		if not list then P.Text("Соединение с диспетчером…", "medium", 13, x + w / 2, cy + S(40), C.dim, TEXT_ALIGN_CENTER) return end
		P.List(st, "row.911.", #list, x + S(12), cy, w - S(18), y + h - cy - S(16), S(64), function(i, rx, ry, rw, rh, f)
			local s = list[i]
			P.Row(rx, ry, rw, rh, f, s.job and s.icon or "urgent", s.name, s.online > 0 and (s.online .. " на линии") or "нет свободных", nil, s.color)
		end, function(i) P.Push("e911reason", { s = list[i], from = "row.911." .. i }) end)
	end,
})

P.Register("e911reason", {
	draw = function(st, x, y, w, h)
		local s = st.s
		local cy = P.Header(s.name, x, y, w, s.color)
		P.Text("Что случилось?", "semibold", 13, x + S(20), cy, C.dim)
		cy = cy + S(24)
		P.List(st, "row.911r.", #s.calls, x + S(12), cy, w - S(18), y + h - cy - S(16), S(52), function(i, rx, ry, rw, rh, f)
			P.Row(rx, ry, rw, rh, f, nil, s.calls[i], nil, nil)
		end, function(i)
			local reason = s.calls[i]
			P.Ask("Комментарий (необязательно)", "", { hint = "например: «двое в масках, синяя куртка»" }, function(comment)
				net.Start("nyrp.e911.call")
				net.WriteString(s.key)
				net.WriteString(reason)
				net.WriteString(comment or "")
				net.SendToServer()
				P.Toast("Вызов отправлен: " .. s.name)
				P.Back() P.Back()
			end)
		end)
	end,
})

-- 911 окном (таксофон): службы → причина → комментарий
function E.OpenWindow(title)
	net.Start("nyrp.e911") net.SendToServer()
	local win, body = UI.Window(title or "911", "urgent", 520, 520, { keyboard = true })
	E.Win = win
	local function show(list)
		body:Clear()
		for _, s in ipairs(list) do
			UI.AddButton(body, s.name .. "  ·  " .. (s.online > 0 and (s.online .. " на линии") or "нет свободных"), s.job and s.icon or "urgent", function()
				body:Clear()
				for _, reason in ipairs(s.calls) do
					UI.AddButton(body, reason, "chevron_right", function()
						net.Start("nyrp.e911.call") net.WriteString(s.key) net.WriteString(reason) net.WriteString("Звонок с таксофона") net.SendToServer()
						win:Close()
					end, { h = 42 })
				end
			end, { h = 48, accent = s.color })
		end
	end
	win.Think = function(s)
		if gui.IsGameUIVisible() and not s.Closing then gui.HideGameUI() s:Close() end
		if not s.Shown and E.ServiceList then s.Shown = true show(E.ServiceList) end
	end
	E.ServiceList = nil
end
